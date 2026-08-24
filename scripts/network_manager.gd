extends Node
## Autoload de rede para HTML5 e WebSocket.

signal connection_failed(reason: String)
signal auth_failed(reason: String)
signal register_result(ok: bool, message: String)
signal needs_character_creation
signal chat_message_received(player_name: String, message: String)

const PORT := 9080
const BIND_ADDRESS := "*"
const SERVER_ADDRESS := "127.0.0.1"
const WORLD_SCENE := "res://scenes/world.tscn"
const PLAYER_SCENE_PATH := "res://scenes/player.tscn"
const CONNECT_TIMEOUT_SEC := 6.0
const AUTH_RESPONSE_TIMEOUT := 10.0
const MAX_CHAT_LENGTH := 200
const MIN_PASSWORD_LENGTH := 3
const SAVE_INTERVAL_SEC := 20.0

const DEFAULT_WEB_SERVER_URL := "wss://eldoriarpg.onrender.com"

var local_player_name: String = ""
var local_player_appearance: Dictionary = {}
var is_host: bool = false
var chat_input_active: bool = false
var current_port: int = PORT

var _account_password: String = ""
var _auth_in_progress: bool = false
var _register_only: bool = false
var _local_pending_account: Dictionary = {}
var _peer_accounts: Dictionary = {} # peer_id -> {"name": String, "snapshot": Dictionary}
var _save_timer: Timer
var _tracked_data: PlayerData = null
var _auth_timer: Timer

var _player_scene: PackedScene
var _players_root: Node2D
var _pending_spawn_data: Array[Dictionary] = []
var _player_names: Dictionary = {} # Guarda os nomes informados via RPC
var _connect_timer: Timer
var _spawn_position := Vector2(380, 420)


func _ready() -> void:
	var env_port := OS.get_environment("PORT")
	if not env_port.is_empty() and env_port.is_valid_int():
		current_port = env_port.to_int()
		print("Usando porta configurada via variável de ambiente: %d" % current_port)
	else:
		current_port = PORT

	_player_scene = load(PLAYER_SCENE_PATH) as PackedScene
	_connect_timer = Timer.new()
	_connect_timer.one_shot = true
	_connect_timer.wait_time = CONNECT_TIMEOUT_SEC
	_connect_timer.timeout.connect(_on_connect_timeout)
	add_child(_connect_timer)

	_save_timer = Timer.new()
	_save_timer.wait_time = SAVE_INTERVAL_SEC
	_save_timer.timeout.connect(_on_save_timer)
	add_child(_save_timer)
	_save_timer.start()

	_auth_timer = Timer.new()
	_auth_timer.one_shot = true
	_auth_timer.wait_time = AUTH_RESPONSE_TIMEOUT
	_auth_timer.timeout.connect(_on_auth_response_timeout)
	add_child(_auth_timer)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func join_or_host(player_name: String, password: String = "") -> void:
	local_player_name = player_name.strip_edges()
	_account_password = password
	is_host = false
	_auth_in_progress = not password.is_empty()
	_register_only = false

	if OS.has_feature("web"):
		_start_client()
		return

	if _start_host():
		if _auth_in_progress:
			_host_auth_then_enter()
			return
		_enter_world()
		return
	_start_client()


## Registro independente: conecta, cria a conta no banco e volta ao login.
func start_register(player_name: String, password: String) -> void:
	local_player_name = player_name.strip_edges()
	_account_password = password
	is_host = false
	_auth_in_progress = true
	_register_only = true

	if OS.has_feature("web"):
		_start_client()
		return

	if _start_host():
		DatabaseManager.authenticate_or_register("register", local_player_name, _account_password,
				func(ok: bool, message: String, _account: Dictionary) -> void:
					_finish_register(ok, message))
		return
	_start_client()


func _finish_register(ok: bool, message: String) -> void:
	var was_register := _register_only
	_reset_peer()
	if was_register:
		register_result.emit(ok, "Conta criada! Faça login." if ok else message)


## Pós-criação de personagem: guarda aparência e entra no mundo.
func complete_character_creation(appearance: Dictionary) -> void:
	local_player_appearance = appearance
	_enter_world()


## Cancela a sessão (ex.: jogador desiste da criação de personagem).
func abort_session() -> void:
	_reset_peer()


func bind_world(
	players_root: Node2D,
	spawn_position: Vector2 = Vector2.ZERO
) -> void:
	_players_root = players_root
	if spawn_position != Vector2.ZERO:
		_spawn_position = spawn_position

	var pending := _pending_spawn_data.duplicate(true)
	_pending_spawn_data.clear()
	for data in pending:
		_spawn_player_local(
			int(data.get("peer_id", 1)),
			str(data.get("player_name", "")),
			data.get("position", _spawn_position),
			data.get("appearance", {})
		)

	if multiplayer.is_server():
		var host_id := multiplayer.get_unique_id()
		_player_names[host_id] = local_player_name
		_spawn_player_local(host_id, local_player_name, _spawn_position_for(host_id), local_player_appearance)
		_mark_character_created(host_id, local_player_appearance)
	else:
		_request_spawn_after_world_ready()


func _request_spawn_after_world_ready() -> void:
	# A mudança de cena e o registro dos nós de rede terminam no próximo frame.
	# Esperar dois frames evita perder o spawn em navegadores muito rápidos.
	await get_tree().process_frame
	await get_tree().process_frame
	if _players_root != null and multiplayer.has_multiplayer_peer():
		rpc_id(1, "_rpc_request_spawn", local_player_name, local_player_appearance)


## Autenticação do host (desktop) direto no banco, sem RPC.
func _host_auth_then_enter() -> void:
	var mode := "register" if _register_only else "login"
	DatabaseManager.authenticate_or_register(mode, local_player_name, _account_password,
			func(ok: bool, message: String, raw_account: Dictionary) -> void:
				if not ok:
					_fail_auth(message)
					return
				if _register_only:
					_finish_register(true, "")
					return
				if raw_account.is_empty():
					# Modo offline: entra direto.
					local_player_appearance = {}
					_finish_auth()
					return
				# A linha crua precisa ser expandida (desempacota o jsonb inventory).
				var account := DatabaseManager.expand_account(raw_account)
				# Registra a conta do próprio host para flips/merges de save funcionarem.
				_peer_accounts[multiplayer.get_unique_id()] = {
					"name": local_player_name,
					"snapshot": _snapshot_from_account(account),
				}
				if bool(account.get("character_created", false)):
					_local_pending_account = _snapshot_from_account(account)
					var appearance: Variant = _local_pending_account.get("appearance")
					if appearance is Dictionary and not appearance.is_empty():
						local_player_appearance = PlayerSpriteFrames.normalize(appearance)
					_finish_auth()
				else:
					# Conta sem personagem: abre a tela de criação antes de entrar no mundo.
					_account_password = ""
					_local_pending_account = {}
					needs_character_creation.emit())


@rpc("any_peer", "reliable")
func _rpc_auth_request(mode: String, p_name: String, password: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	p_name = p_name.strip_edges()
	password = str(password)
	var offline := not DatabaseManager.enabled
	if p_name.is_empty() or password.length() < MIN_PASSWORD_LENGTH:
		rpc_id(sender, "_rpc_auth_response", false, "Nome ou senha inválidos.", {})
		return
	if offline:
		# Sem banco configurado: permite jogar sem persistência.
		if mode == "register":
			rpc_id(sender, "_rpc_auth_response", true, "", {"register_only": true})
			return
		_peer_accounts[sender] = {"name": p_name, "snapshot": {}}
		rpc_id(sender, "_rpc_auth_response", true, "", {"character_created": true})
		return
	DatabaseManager.authenticate_or_register(mode, p_name, password,
			func(ok: bool, message: String, account: Dictionary) -> void:
				if not multiplayer.get_peers().has(sender):
					return
				if ok and mode == "register":
					rpc_id(sender, "_rpc_auth_response", true, "", {"register_only": true})
				elif ok:
					_peer_accounts[sender] = {
						"name": p_name,
						"snapshot": _snapshot_from_account(account),
					}
					rpc_id(sender, "_rpc_auth_response", true, "",
							_peer_accounts[sender]["snapshot"])
				else:
					rpc_id(sender, "_rpc_auth_response", false, message, {}))


@rpc("authority", "call_remote", "reliable")
func _rpc_auth_response(ok: bool, message: String, snapshot: Dictionary) -> void:
	_auth_timer.stop()
	if not _auth_in_progress:
		return
	_auth_in_progress = false
	if bool(snapshot.get("register_only", false)) or _register_only:
		_finish_register(ok, "Conta criada! Faça login." if ok else message)
		return
	if not ok:
		_fail_auth(message)
		return
	if bool(snapshot.get("character_created", false)):
		_local_pending_account = snapshot
		var appearance: Variant = snapshot.get("appearance")
		if appearance is Dictionary and not appearance.is_empty():
			local_player_appearance = PlayerSpriteFrames.normalize(appearance)
		_finish_auth()
	else:
		# Conta sem personagem: abre a tela de criação antes de entrar no mundo.
		# Pending fica vazio para o jogador novo ganhar o kit inicial normal.
		_account_password = ""
		_local_pending_account = {}
		needs_character_creation.emit()


func _finish_auth() -> void:
	_auth_timer.stop()
	_account_password = ""
	_enter_world()


## Estouro de espera pela resposta de autenticação (servidor antigo/morto).
func _on_auth_response_timeout() -> void:
	if not _auth_in_progress:
		return
	var registering := _register_only
	_reset_peer()
	var reason := "O servidor demorou para responder. Pode estar fora do ar ou desatualizado."
	if registering:
		register_result.emit(false, reason)
	else:
		auth_failed.emit(reason)


func _fail_auth(reason: String) -> void:
	_auth_timer.stop()
	_account_password = ""
	_connect_timer.stop()
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_host = false
	_auth_in_progress = false
	auth_failed.emit(reason)


func _snapshot_from_account(account: Dictionary) -> Dictionary:
	if account.is_empty():
		return {}
	var appearance: Variant = account.get("appearance")
	return {
		"level": int(account.get("level", 1)),
		"experience": int(account.get("experience", 0)),
		"max_hp": int(account.get("max_hp", 100)),
		"base_damage": int(account.get("base_damage", 8)),
		"gold": int(account.get("gold", 0)),
		"equipped_weapon_id": str(account.get("equipped_weapon_id", "")),
		"inventory": account.get("inventory", []),
		"character_created": bool(account.get("character_created", false)),
		"appearance": appearance if appearance is Dictionary else {},
		"pos_x": float(account.get("pos_x", 0.0)),
		"pos_y": float(account.get("pos_y", 0.0)),
	}


func consume_local_account() -> Dictionary:
	var account := _local_pending_account
	_local_pending_account = {}
	return account


## Primeiro spawn de uma conta: grava flag + aparência no banco.
## Serve tanto para o host (bind_world) quanto para clientes (_rpc_request_spawn).
func _mark_character_created(peer_id: int, appearance: Dictionary) -> void:
	if not _peer_accounts.has(peer_id):
		return
	var entry: Dictionary = _peer_accounts[peer_id]
	var snap: Dictionary = entry.get("snapshot", {})
	if bool(snap.get("character_created", false)):
		return
	snap["character_created"] = true
	snap["appearance"] = _appearance_for_storage(appearance)
	entry["snapshot"] = snap
	DatabaseManager.save_account(str(entry.get("name", "")), snap)


## Aparência em formato serializável (hex), estável entre sessões.
func _appearance_for_storage(appearance: Dictionary) -> Dictionary:
	var look := PlayerSpriteFrames.normalize(appearance)
	return {
		"skin": (look["skin"] as Color).to_html(false),
		"hair": (look["hair"] as Color).to_html(false),
		"shirt": (look["shirt"] as Color).to_html(false),
		"pants": (look["pants"] as Color).to_html(false),
		"hair_style": int(look["hair_style"]),
	}


func bind_local_player_data(data: PlayerData) -> void:
	_tracked_data = data


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	if not _has_live_session():
		return
	# Fechar o jogo é o momento definitivo de logout: salva sempre.
	get_tree().auto_accept_quit = false
	_save_now()
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()


func _on_save_timer() -> void:
	if _tracked_data == null:
		return
	if not _has_live_session():
		return
	_save_now()


func _save_now() -> void:
	if _tracked_data == null or not _has_live_session():
		return
	var payload := _build_save_payload()
	if multiplayer.is_server():
		_store_snapshot_locally(multiplayer.get_unique_id(), payload)
		_push_account_to_db(local_player_name, payload)
	else:
		rpc_id(1, "_rpc_save_account", payload)


## Snapshot completo do dono da sessão: stats + posição atual.
func _build_save_payload() -> Dictionary:
	var payload := _tracked_data.to_snapshot()
	var me := get_player_node(multiplayer.get_unique_id())
	if me is Node2D:
		payload["pos_x"] = (me as Node2D).global_position.x
		payload["pos_y"] = (me as Node2D).global_position.y
	return payload


func _has_live_session() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return false
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return false
	return true


func _store_snapshot_locally(peer_id: int, payload: Dictionary) -> void:
	if not _peer_accounts.has(peer_id):
		return
	# Preserva dados da conta que o payload do cliente não carrega.
	var previous: Dictionary = _peer_accounts[peer_id].get("snapshot", {})
	for key in ["character_created", "appearance"]:
		if not payload.has(key) and previous.has(key):
			payload[key] = previous[key]
	_peer_accounts[peer_id]["snapshot"] = payload


func _push_account_to_db(p_name: String, snapshot: Dictionary) -> void:
	if not DatabaseManager.enabled or p_name.is_empty():
		return
	DatabaseManager.save_account(p_name, snapshot)


@rpc("any_peer", "reliable")
func _rpc_save_account(snapshot: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _peer_accounts.has(sender):
		return
	_store_snapshot_locally(sender, snapshot)
	var entry: Dictionary = _peer_accounts[sender]
	_push_account_to_db(str(entry.get("name", "")), snapshot)


@rpc("any_peer", "call_local", "reliable")
func _rpc_request_spawn(p_name: String, appearance: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	
	_player_names[sender_id] = p_name
	# Primeiro spawn de uma conta nova: marca o personagem como criado no banco.
	_mark_character_created(sender_id, appearance)
	var position := _spawn_position_for(sender_id)
	_spawn_player_local(sender_id, p_name, position, appearance)
	rpc("_rpc_spawn_player", sender_id, p_name, position, appearance)
	rpc_id(sender_id, "_rpc_sync_players", _current_player_roster())
	print("Roster enviado: peer=%d jogadores=%d" % [sender_id, _current_player_roster().size()])


@rpc("authority", "call_remote", "reliable")
func _rpc_spawn_player(peer_id: int, p_name: String, position: Vector2, appearance: Dictionary) -> void:
	_spawn_player_local(peer_id, p_name, position, appearance)


@rpc("authority", "call_remote", "reliable")
func _rpc_sync_players(roster: Array) -> void:
	for data in roster:
		if data is Dictionary:
			_spawn_player_local(
				int(data.get("peer_id", 1)),
				str(data.get("player_name", "")),
				data.get("position", _spawn_position),
				data.get("appearance", {})
			)


func _spawn_player_local(peer_id: int, p_name: String, position: Vector2, appearance: Dictionary = {}) -> void:
	if _players_root == null:
		_pending_spawn_data.append({
			"peer_id": peer_id,
			"player_name": p_name,
			"position": position,
			"appearance": appearance,
		})
		return

	if _players_root.has_node(str(peer_id)):
		return

	var player := _player_scene.instantiate() as Node2D
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	player.position = position
	if "display_name" in player:
		player.display_name = p_name if not p_name.is_empty() else "Jogador %d" % peer_id
	if "customization" in player:
		player.customization = PlayerSpriteFrames.normalize(appearance)
	_players_root.add_child(player)
	print("Jogador instanciado: peer=%d autoridade=%d nome=%s" % [
		peer_id,
		player.get_multiplayer_authority(),
		str(player.display_name),
	])


func _spawn_position_for(peer_id: int) -> Vector2:
	var slot := peer_id % 8
	return _spawn_position + Vector2(
		float(slot % 4) * 28.0 - 42.0,
		float(int(slot / 4)) * 28.0
	)


func _current_player_roster() -> Array[Dictionary]:
	var roster: Array[Dictionary] = []
	if _players_root == null:
		return roster
	for child in _players_root.get_children():
		var player := child as Node2D
		if player == null or not str(player.name).is_valid_int():
			continue
		var p_name := _player_names.get(str(player.name).to_int(), "") as String
		if "display_name" in player:
			p_name = str(player.display_name)
		var entry := {
			"peer_id": str(player.name).to_int(),
			"player_name": p_name,
			"position": player.position,
		}
		if "customization" in player:
			entry["appearance"] = player.customization
		roster.append(entry)
	return roster


func send_chat(message: String) -> bool:
	var cleaned := _sanitize_chat(message)
	if cleaned.is_empty():
		return false
	if multiplayer.is_server():
		_broadcast_chat(multiplayer.get_unique_id(), cleaned)
	else:
		rpc_id(1, "_rpc_submit_chat", cleaned)
	return true


func is_chat_blocking_movement() -> bool:
	if chat_input_active:
		return true
	if QuestManager.is_blocking_input():
		return true
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


func get_player_node(peer_id: int) -> Node:
	if _players_root == null:
		return null
	return _players_root.get_node_or_null(str(peer_id))


@rpc("any_peer", "reliable")
func _rpc_submit_chat(message: String) -> void:
	if not multiplayer.is_server():
		return
	var cleaned := _sanitize_chat(message)
	if cleaned.is_empty():
		return
	_broadcast_chat(multiplayer.get_remote_sender_id(), cleaned)


func _broadcast_chat(peer_id: int, message: String) -> void:
	rpc("_rpc_receive_chat", _name_for_peer(peer_id), message)


@rpc("authority", "call_local", "reliable")
func _rpc_receive_chat(player_name: String, message: String) -> void:
	chat_message_received.emit(player_name, message)


func _sanitize_chat(message: String) -> String:
	var cleaned := message.strip_edges().replace("\n", " ").replace("\r", "")
	if cleaned.length() > MAX_CHAT_LENGTH:
		cleaned = cleaned.substr(0, MAX_CHAT_LENGTH)
	return cleaned


func _name_for_peer(peer_id: int) -> String:
	if _players_root:
		var player := _players_root.get_node_or_null(str(peer_id))
		if player and "display_name" in player:
			var shown := str(player.display_name).strip_edges()
			if not shown.is_empty():
				return shown
	if peer_id == multiplayer.get_unique_id() and not local_player_name.is_empty():
		return local_player_name
	return _player_names.get(peer_id, "Jogador %d" % peer_id)


func _start_host() -> bool:
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(current_port, BIND_ADDRESS)
	if err != OK:
		push_warning("Host WebSocket indisponível na porta %d (%s)." % [current_port, error_string(err)])
		return false
	multiplayer.multiplayer_peer = peer
	is_host = true
	print("Eldoria host WebSocket em ws://0.0.0.0:%d" % current_port)
	return true


func _start_client() -> void:
	var peer := WebSocketMultiplayerPeer.new()
	var url := resolve_websocket_url()
	var err := peer.create_client(url)
	if err != OK:
		connection_failed.emit("Não foi possível iniciar o cliente (%s)." % error_string(err))
		_reset_peer()
		return
	multiplayer.multiplayer_peer = peer
	_connect_timer.start()
	print("Conectando a %s ..." % url)


func resolve_websocket_url() -> String:
	if OS.has_feature("web"):
		var from_query := _web_query_ws_url()
		if not from_query.is_empty():
			return from_query
		
		var configured_url := _configured_web_server_url()
		if not configured_url.is_empty():
			var host: Variant = JavaScriptBridge.eval("window.location.hostname", true)
			if host and str(host) != "localhost" and str(host) != "127.0.0.1" and str(host) != "":
				return configured_url
	return "ws://%s:%d" % [SERVER_ADDRESS, PORT]


func _configured_web_server_url() -> String:
	if not OS.has_feature("web"):
		return DEFAULT_WEB_SERVER_URL
	var configured: Variant = JavaScriptBridge.eval("window.ELDORIA_SERVER_URL || ''", true)
	if typeof(configured) != TYPE_STRING:
		return DEFAULT_WEB_SERVER_URL
	var url := str(configured).strip_edges().trim_suffix("/")
	return url if not url.is_empty() else DEFAULT_WEB_SERVER_URL


func _web_query_ws_url() -> String:
	if not OS.has_feature("web"):
		return ""
	var search: Variant = JavaScriptBridge.eval("window.location.search", true)
	if typeof(search) != TYPE_STRING:
		return ""
	var query := str(search)
	var ws := _query_param(query, "ws")
	if not ws.is_empty():
		return ws
	var server := _query_param(query, "server")
	if server.is_empty():
		return ""
	var port := _query_param(query, "port")
	if port.is_empty():
		port = str(PORT)
	var scheme := "wss" if _page_is_https() else "ws"
	return "%s://%s:%s" % [scheme, server, port]


func _page_is_https() -> bool:
	var protocol: Variant = JavaScriptBridge.eval("window.location.protocol", true)
	return str(protocol) == "https:"


func _query_param(query: String, key: String) -> String:
	var q := query
	if q.begins_with("?"):
		q = q.substr(1)
	for part in q.split("&"):
		if part.is_empty():
			continue
		var eq := part.find("=")
		if eq <= 0:
			continue
		if part.substr(0, eq) != key:
			continue
		return part.substr(eq + 1).uri_decode()
	return ""


func _enter_world() -> void:
	_connect_timer.stop()
	get_tree().change_scene_to_file(WORLD_SCENE)


func _despawn_player(peer_id: int) -> void:
	if _players_root == null:
		return
	var node := _players_root.get_node_or_null(str(peer_id))
	if node:
		node.queue_free()


@rpc("authority", "call_remote", "reliable")
func _rpc_despawn_player(peer_id: int) -> void:
	_despawn_player(peer_id)


func _on_peer_connected(peer_id: int) -> void:
	print("Peer conectado (aguardando carregamento do mapa): %d" % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer saiu: %d" % peer_id)
	if _peer_accounts.has(peer_id):
		var entry: Dictionary = _peer_accounts[peer_id]
		var snapshot: Dictionary = entry.get("snapshot", {})
		# Usa a posição ao vivo do nó (mais recente que o último autosave).
		var node := get_player_node(peer_id)
		if node is Node2D:
			snapshot["pos_x"] = (node as Node2D).global_position.x
			snapshot["pos_y"] = (node as Node2D).global_position.y
		entry["snapshot"] = snapshot
		_push_account_to_db(str(entry.get("name", "")), snapshot)
		_peer_accounts.erase(peer_id)
	_player_names.erase(peer_id)
	_despawn_player(peer_id)
	if multiplayer.is_server():
		rpc("_rpc_despawn_player", peer_id)


func _on_connected_to_server() -> void:
	if not _account_password.is_empty():
		# Autentica (ou registra) antes de qualquer coisa. Com teto de tempo:
		# servidores antigos sem suporte a login não respondem nunca.
		_auth_timer.start()
		rpc_id(1, "_rpc_auth_request", "register" if _register_only else "login",
				local_player_name, _account_password)
		return
	_enter_world()


func _on_connection_failed() -> void:
	_connect_timer.stop()
	_reset_peer()
	connection_failed.emit("Servidor não encontrado em %s." % resolve_websocket_url())


func _on_connect_timeout() -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_reset_peer()
	connection_failed.emit("Tempo esgotado. Abra o host no desktop e tente de novo.")


func _on_server_disconnected() -> void:
	var was_authenticating := _auth_in_progress
	_auth_in_progress = false
	_reset_peer()
	_players_root = null
	# Se a falha ocorreu no login (auth recusada), não recarrega a cena:
	# o motivo já foi exibido na tela.
	if was_authenticating or _is_on_login_scene():
		return
	get_tree().change_scene_to_file("res://ui/login.tscn")


func _is_on_login_scene() -> bool:
	var current := get_tree().current_scene
	return current != null and current.scene_file_path == "res://ui/login.tscn"


func _reset_peer() -> void:
	_connect_timer.stop()
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_host = false
	_auth_in_progress = false
	_register_only = false
	_account_password = ""
	chat_input_active = false
	_players_root = null
	_pending_spawn_data.clear()
	_player_names.clear()
	QuestManager.reset_all()
