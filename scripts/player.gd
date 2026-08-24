extends CharacterBody2D

const SPEED := 180.0
const DIR_NAMES: PackedStringArray = PlayerSpriteFrames.DIR_NAMES
const DIR_VECTORS: Array[Vector2] = PlayerSpriteFrames.DIR_VECTORS
const MOVE_DEADZONE := 0.01
const ATTACK_OVERLAP_DIST := 18.0
const RESPAWN_SEC := 4.0

static var _frames_cache: Dictionary = {}

@export var display_name: String = "":
	set(value):
		display_name = value
		_refresh_name_label()

@export var customization: Dictionary = {}:
	set(value):
		customization = value
		_apply_customization()

@export var equipped_weapon: String = ""
@export var equipped_armor: Dictionary = {}

@export var facing_index: int = 2:
	set(value):
		facing_index = clampi(value, 0, DIR_NAMES.size() - 1)
		_refresh_animation()

@export var anim_state: String = "idle":
	set(value):
		anim_state = value
		_refresh_animation()

@export var can_pvp: bool = false:
	set(value):
		if can_pvp == value:
			return
		can_pvp = value
		_refresh_name_label()
		_refresh_zone_hud()

@onready var sprite: AnimatedSprite2D = %Sprite
@onready var name_label: Label = %NameLabel
@onready var camera: Camera2D = %Camera2D
@onready var data: PlayerData = %PlayerData
@onready var health_bar: Node2D = %HealthBar

var current_zone: String = ""
var _zone_titles: Dictionary = {}
var _zone_stack: Array[String] = []
const ATTACK_ANIM_TIME := 0.30

var _attack_cd := 0.0
var _attack_anim_left := 0.0
var _hurt_anim_left := 0.0
var _respawn_left := 0.0
var _hurt_flash := 0.0
var _attack_flash := 0.0


func _enter_tree() -> void:
	# A autoridade configurada no servidor não é replicada automaticamente.
	# O MultiplayerSpawner preserva o nome (peer_id), então cada peer consegue
	# atribuir a mesma autoridade antes de _ready() ativar câmera e controles.
	var peer_id := str(name).to_int()
	if peer_id > 0:
		set_multiplayer_authority(peer_id)


func _ready() -> void:
	add_to_group("player")
	_apply_saved_account()
	sprite.centered = true
	_apply_customization()

	var is_local := is_multiplayer_authority()
	camera.enabled = is_local
	if is_local:
		display_name = NetworkManager.local_player_name
		camera.make_current()
		_apply_camera_limits()
		sprite.modulate = Color.WHITE
		call_deferred("_bind_local_hud")
	else:
		sprite.modulate = Color(1.0, 0.88, 0.78)

	if not data.stats_changed.is_connected(_on_stats_changed):
		data.stats_changed.connect(_on_stats_changed)
	if is_multiplayer_authority() and not data.equipment_changed.is_connected(_on_equipment_changed):
		data.equipment_changed.connect(_on_equipment_changed)
	_on_stats_changed()
	_on_equipment_changed()
	_refresh_name_label()
	_refresh_animation()
	_refresh_zone_hud()


func _bind_local_hud() -> void:
	var hud := get_tree().get_first_node_in_group("player_hud")
	if hud and hud.has_method("bind_player_data"):
		hud.bind_player_data(data)
	# Conta: liga o autosave (o snapshot já foi consumido em _apply_saved_account).
	NetworkManager.bind_local_player_data(data)


## Restaura o progresso da conta (stats, itens e posição do último logout).
## Apenas o boneco LOCAL consome — réplicas dos outros não podem roubar o snapshot.
func _apply_saved_account() -> void:
	if not is_multiplayer_authority():
		return
	var account := NetworkManager.consume_local_account()
	if account.is_empty():
		return
	if account.has("level"):
		data.apply_snapshot(account)
	var pos := Vector2(float(account.get("pos_x", 0.0)), float(account.get("pos_y", 0.0)))
	if pos != Vector2.ZERO:
		global_position = pos


func _apply_customization() -> void:
	if sprite == null:
		return
	var look := PlayerSpriteFrames.normalize(customization)
	var gear := PlayerSpriteFrames.normalize_equipment({
		"hand": effective_weapon_id(),
		"helmet": str(equipped_armor.get("helmet", "")),
		"chest": str(equipped_armor.get("chest", "")),
	})
	var cache_key := str([look, gear].hash())
	if not _frames_cache.has(cache_key):
		_frames_cache[cache_key] = PlayerSpriteFrames.build(look, gear)
	sprite.sprite_frames = _frames_cache[cache_key]
	if PlayerSpriteFrames.uses_sheet():
		var sc := 0.31
		sprite.scale = Vector2(sc, sc)
		# Pés da folha (~y124 de 128) alinhados com a sombra/base antiga (+14).
		sprite.position = Vector2(0, 14.0 - 64.0 * sc)
	else:
		sprite.scale = Vector2.ONE
		sprite.position = Vector2.ZERO


func enter_zone(zone_id: String, zone_title: String) -> void:
	_zone_titles[zone_id] = zone_title
	if not _zone_stack.has(zone_id):
		_zone_stack.append(zone_id)
	current_zone = zone_id
	_refresh_zone_hud()


func exit_zone(zone_id: String) -> void:
	var idx := _zone_stack.find(zone_id)
	if idx >= 0:
		_zone_stack.remove_at(idx)
	_zone_titles.erase(zone_id)
	current_zone = _zone_stack[_zone_stack.size() - 1] if not _zone_stack.is_empty() else ""
	_refresh_zone_hud()


func is_combat_alive() -> bool:
	return data != null and data.hp > 0


func _physics_process(delta: float) -> void:
	_hurt_flash = maxf(_hurt_flash - delta, 0.0)
	_attack_flash = maxf(_attack_flash - delta, 0.0)
	_update_flash_modulate()

	if not is_multiplayer_authority():
		return

	_attack_cd = maxf(_attack_cd - delta, 0.0)

	if not is_combat_alive():
		velocity = Vector2.ZERO
		anim_state = "death"
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			_respawn_at_spawn()
		move_and_slide()
		return

	if NetworkManager.is_chat_blocking_movement():
		velocity = Vector2.ZERO
		anim_state = "idle"
		move_and_slide()
		return

	if _attack_anim_left > 0.0:
		# Golpe em andamento: trava movimento e toca a animação de ataque.
		_attack_anim_left -= delta
		velocity = Vector2.ZERO
		anim_state = "attack"
		move_and_slide()
		return

	if _hurt_anim_left > 0.0:
		_hurt_anim_left -= delta
		anim_state = "hurt"
		move_and_slide()
		return

	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_dir.length_squared() > MOVE_DEADZONE:
		input_dir = input_dir.normalized()
		velocity = input_dir * SPEED
		facing_index = _vector_to_facing(input_dir)
		anim_state = "walk"
	else:
		velocity = Vector2.ZERO
		anim_state = "idle"

	if Input.is_action_just_pressed("attack") and not NetworkManager.is_chat_blocking_movement():
		_try_attack()

	move_and_slide()


func _try_attack() -> void:
	if _attack_cd > 0.0 or not is_combat_alive():
		return
	var weapon := effective_weapon_id()
	_attack_cd = ItemCatalog.weapon_cooldown(weapon)
	_attack_flash = 0.12
	var damage := data.attack_damage(weapon)
	var attack_range := ItemCatalog.weapon_range(weapon)
	var arc_dot := ItemCatalog.weapon_arc_dot(weapon)
	var attack_type := ItemCatalog.weapon_attack(weapon)
	var facing: Vector2 = DIR_VECTORS[facing_index].normalized()
	_attack_anim_left = ATTACK_ANIM_TIME
	_broadcast_attack_effect(attack_type, facing_index)

	for node in get_tree().get_nodes_in_group("monster"):
		if not _is_in_attack_arc(node, facing, attack_range, arc_dot):
			continue
		if node.has_method("request_player_hit"):
			node.request_player_hit(damage, multiplayer.get_unique_id())

	for node in get_tree().get_nodes_in_group("player"):
		if node == self:
			continue
		if not _is_in_attack_arc(node, facing, attack_range, arc_dot):
			continue
		_request_pvp_hit(node, damage, attack_range)


func effective_weapon_id() -> String:
	if equipped_weapon.is_empty() or not ItemCatalog.is_equipment(equipped_weapon):
		return ""
	return equipped_weapon


func _is_in_attack_arc(target: Node, facing: Vector2, max_range: float, arc_dot: float) -> bool:
	if not (target is Node2D):
		return false
	if target.has_method("is_combat_alive") and not target.is_combat_alive():
		return false
	if "is_alive" in target and not bool(target.is_alive):
		return false
	var offset: Vector2 = (target as Node2D).global_position - global_position
	var dist := offset.length()
	if dist > max_range or dist < 0.01:
		return dist <= ATTACK_OVERLAP_DIST and dist > 0.01
	return facing.dot(offset.normalized()) >= arc_dot


func _request_pvp_hit(target: Node, damage: int, attack_range: float) -> void:
	if not can_pvp:
		return
	if not ("can_pvp" in target) or not bool(target.can_pvp):
		return
	var target_peer := int(str(target.name))
	if multiplayer.is_server():
		_server_resolve_pvp(multiplayer.get_unique_id(), target_peer, damage, attack_range)
	else:
		rpc_id(1, "rpc_request_pvp_hit", target_peer, damage, attack_range)


@rpc("any_peer", "reliable")
func rpc_request_pvp_hit(target_peer: int, damage: int, attack_range: float) -> void:
	if not multiplayer.is_server():
		return
	var attacker := multiplayer.get_remote_sender_id()
	_server_resolve_pvp(attacker, target_peer, damage, attack_range)


func _server_resolve_pvp(attacker_peer: int, target_peer: int, damage: int, attack_range: float) -> void:
	var attacker := NetworkManager.get_player_node(attacker_peer)
	var target := NetworkManager.get_player_node(target_peer)
	if attacker == null or target == null:
		return
	if not bool(attacker.can_pvp) or not bool(target.can_pvp):
		return
	if not attacker.is_combat_alive() or not target.is_combat_alive():
		return
	var dist: float = attacker.global_position.distance_to(target.global_position)
	if dist > attack_range + 12.0:
		return
	var dealt := clampi(damage, 1, 80)
	if target_peer == multiplayer.get_unique_id():
		target.rpc_receive_pvp_hit(dealt, attacker_peer)
	else:
		target.rpc_id(target_peer, "rpc_receive_pvp_hit", dealt, attacker_peer)


@rpc("any_peer", "reliable")
func rpc_receive_pvp_hit(amount: int, _attacker_peer: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	if not is_multiplayer_authority():
		return
	if not can_pvp:
		return
	_apply_damage(amount)


@rpc("any_peer", "reliable")
func rpc_receive_monster_hit(amount: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	if not is_multiplayer_authority():
		return
	_apply_damage(amount)


@rpc("any_peer", "reliable")
func rpc_receive_rewards(exp_amount: int, gold_amount: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	if not is_multiplayer_authority():
		return
	data.add_experience(exp_amount)
	data.add_gold(gold_amount)
	QuestManager.report_monster_kill()


func _apply_damage(amount: int) -> void:
	if amount <= 0 or not is_combat_alive():
		return
	data.take_damage(amount)
	_hurt_flash = 0.14
	_hurt_anim_left = 0.25
	if data.hp <= 0:
		_respawn_left = RESPAWN_SEC
		velocity = Vector2.ZERO
		anim_state = "idle"


func _respawn_at_spawn() -> void:
	var map := get_tree().get_first_node_in_group("world_map")
	if map and map.has_method("get_spawn_position"):
		global_position = map.get_spawn_position()
	data.set_hp(data.max_hp)
	can_pvp = false
	_respawn_left = 0.0


func _vector_to_facing(direction: Vector2) -> int:
	var index := int(round(direction.angle() / (PI * 0.25)))
	return posmod(index, DIR_NAMES.size())


func _apply_camera_limits() -> void:
	var map := get_tree().get_first_node_in_group("world_map")
	if map == null or not map.has_method("get_map_size"):
		return
	var size: Vector2 = map.get_map_size()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(size.x)
	camera.limit_bottom = int(size.y)


func _on_stats_changed() -> void:
	if health_bar and health_bar.has_method("set_health"):
		health_bar.set_health(data.hp, data.max_hp)


func _on_equipment_changed() -> void:
	if is_multiplayer_authority():
		equipped_weapon = data.equipped_weapon_id
		equipped_armor = data.equipped_armor.duplicate(true)
		_apply_customization()
		if health_bar and health_bar.has_method("set_health"):
			health_bar.set_health(data.hp, data.max_hp)


func _broadcast_attack_effect(attack_type: String, dir_index: int) -> void:
	if attack_type.is_empty():
		return
	if multiplayer.is_server():
		rpc("rpc_play_attack_effect", attack_type, dir_index)
	else:
		rpc_id(1, "rpc_relay_attack_effect", attack_type, dir_index)


@rpc("any_peer", "call_local", "reliable")
func rpc_relay_attack_effect(attack_type: String, dir_index: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and NetworkManager.get_player_node(sender) != self:
		return
	rpc("rpc_play_attack_effect", attack_type, dir_index)


@rpc("any_peer", "call_local", "reliable")
func rpc_play_attack_effect(attack_type: String, dir_index: int) -> void:
	_spawn_attack_effect(attack_type, dir_index)


func _spawn_attack_effect(attack_type: String, dir_index: int) -> void:
	var parent := get_parent()
	if parent == null or attack_type.is_empty():
		return
	var index := clampi(dir_index, 0, DIR_VECTORS.size() - 1)
	var direction: Vector2 = DIR_VECTORS[index].normalized()
	var origin := global_position + direction * 14.0

	match attack_type:
		ItemCatalog.ATTACK_SLASH:
			var slash := SlashEffect.new()
			slash.position = origin
			slash.rotation = direction.angle()
			parent.add_child(slash)
		ItemCatalog.ATTACK_BOLT:
			var bolt := BoltEffect.new()
			bolt.direction = direction
			bolt.max_dist = ItemCatalog.weapon_range(effective_weapon_id())
			bolt.position = origin
			parent.add_child(bolt)


func _update_flash_modulate() -> void:
	if sprite == null:
		return
	var base := Color.WHITE if is_multiplayer_authority() else Color(1.0, 0.88, 0.78)
	if not is_combat_alive():
		sprite.modulate = base.darkened(0.45)
	elif _hurt_flash > 0.0:
		sprite.modulate = Color(1.45, 0.55, 0.55)
	elif _attack_flash > 0.0:
		sprite.modulate = Color(1.25, 1.2, 0.75)
	else:
		sprite.modulate = base


func _refresh_animation() -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	var clip := "%s_%s" % [anim_state, DIR_NAMES[facing_index]]
	if not sprite.sprite_frames.has_animation(clip):
		return
	if sprite.animation != clip or not sprite.is_playing():
		sprite.play(clip)


func _refresh_name_label() -> void:
	if name_label == null:
		return
	name_label.text = display_name
	var color := Color(1.0, 0.35, 0.32) if can_pvp else Color(0.95, 0.96, 0.98)
	name_label.add_theme_color_override("font_color", color)


func _refresh_zone_hud() -> void:
	if not is_inside_tree() or not is_multiplayer_authority():
		return
	var label := get_tree().get_first_node_in_group("zone_hud")
	if label == null:
		return
	var title := str(_zone_titles.get(current_zone, "Campo"))
	if current_zone.is_empty():
		title = "Campo"
	if can_pvp:
		label.text = "Zona: %s  ·  PVP ligado" % title
	else:
		label.text = "Zona: %s  ·  PVP desligado" % title
