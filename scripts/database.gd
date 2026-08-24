extends Node
## Cliente Supabase (PostgREST) para contas persistentes.
## Roda apenas no lado do servidor do jogo (a service key nunca vai ao cliente).
##
## Configuração por variáveis de ambiente:
##   SUPABASE_URL  → https://xxxx.supabase.co
##   SUPABASE_KEY  → service_role key (Dashboard → Settings → API)
## Sem as variáveis o modo offline fica ativo: dá pra jogar, sem persistência.

const ITERATIONS := 512
## Formato do jsonb `inventory`:
##   Array  → formato antigo: apenas os slots (conta com personagem criado)
##   Object → v2: { "v": 2, "slots": [...], "pos_x", "pos_y", "appearance",
##                  "character_created" }
const INVENTORY_VERSION := 2

var enabled: bool = false
var base_url: String = ""
var api_key: String = ""


func _ready() -> void:
	base_url = OS.get_environment("SUPABASE_URL").strip_edges().trim_suffix("/")
	# Aceita tanto a Project URL pura quanto a URL completa do REST.
	for suffix in ["/rest/v1/", "/rest/v1"]:
		if base_url.ends_with(suffix):
			base_url = base_url.trim_suffix(suffix)
	api_key = OS.get_environment("SUPABASE_KEY").strip_edges()
	enabled = not base_url.is_empty() and not api_key.is_empty()
	if enabled:
		print("DatabaseManager: Supabase ativo (%s)" % base_url)
	else:
		print("DatabaseManager: modo offline (SUPABASE_URL/SUPABASE_KEY ausentes). Sem persistência.")


static func hash_password(password: String, salt: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(salt.to_utf8_buffer())
	ctx.update(password.to_utf8_buffer())
	for i in ITERATIONS:
		var previous := ctx.finish()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(previous)
	return ctx.finish().hex_encode()


static func random_salt() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


## Empacota os dados estendidos (posição/aparência/flag) dentro do jsonb inventory,
## evitando colunas extras no banco.
static func pack_inventory(snapshot: Dictionary) -> Variant:
	var slots: Variant = snapshot.get("inventory", [])
	if not (snapshot.has("pos_x") or snapshot.has("pos_y")
			or snapshot.has("appearance") or snapshot.has("character_created")):
		return slots
	return {
		"v": INVENTORY_VERSION,
		"slots": slots,
		"pos_x": float(snapshot.get("pos_x", 0.0)),
		"pos_y": float(snapshot.get("pos_y", 0.0)),
		"appearance": snapshot.get("appearance", {}),
		"character_created": bool(snapshot.get("character_created", false)),
	}


## Desempacota a linha do banco para o formato plano usado pelo jogo.
static func expand_account(account: Dictionary) -> Dictionary:
	var out := account.duplicate(true)
	var inv: Variant = out.get("inventory")
	if inv is Dictionary:
		out["pos_x"] = float(inv.get("pos_x", 0.0))
		out["pos_y"] = float(inv.get("pos_y", 0.0))
		out["appearance"] = inv.get("appearance", {})
		out["character_created"] = bool(inv.get("character_created", false))
		out["inventory"] = inv.get("slots", [])
	else:
		# Formato antigo (array): personagem já existia.
		if not out.has("character_created"):
			out["character_created"] = true
		if not out.has("appearance"):
			out["appearance"] = {}
		if not out.has("pos_x"):
			out["pos_x"] = 0.0
		if not out.has("pos_y"):
			out["pos_y"] = 0.0
	return out


## mode: "login" ou "register".
## cb(ok: bool, message: String, account: Dictionary) — account contém os stats salvos.
func authenticate_or_register(mode: String, p_name: String, password: String, cb: Callable) -> void:
	if not enabled:
		cb.call(true, "", {})
		return
	if mode == "register":
		_register(p_name, password, cb)
	else:
		_authenticate(p_name, password, cb)


func save_account(p_name: String, snapshot: Dictionary, cb: Callable = Callable()) -> void:
	if not enabled:
		if cb.is_valid():
			cb.call(false, "modo offline", {})
		return
	var body := {
		"level": int(snapshot.get("level", 1)),
		"experience": int(snapshot.get("experience", 0)),
		"max_hp": int(snapshot.get("max_hp", 100)),
		"base_damage": int(snapshot.get("base_damage", 8)),
		"gold": int(snapshot.get("gold", 0)),
		"equipped_weapon_id": str(snapshot.get("equipped_weapon_id", "")),
		"inventory": pack_inventory(snapshot),
	}
	_request(HTTPClient.METHOD_PATCH,
			"/rest/v1/accounts?name=eq.%s" % p_name.uri_encode(), body,
			func(code: int, _data: Variant) -> void:
				if cb.is_valid():
					cb.call(code >= 200 and code < 300, "", {}))


func _register(p_name: String, password: String, cb: Callable) -> void:
	var salt := random_salt()
	var row := {
		"name": p_name,
		"salt": salt,
		"password_hash": hash_password(password, salt),
		"inventory": {
			"v": INVENTORY_VERSION,
			"slots": [],
			"pos_x": 0.0,
			"pos_y": 0.0,
			"appearance": {},
			"character_created": false,
		},
	}
	_request(HTTPClient.METHOD_POST, "/rest/v1/accounts", row,
			func(code: int, data: Variant) -> void:
				if code >= 200 and code < 300:
					cb.call(true, "", {})
				elif code == 409 or _error_has(data, "23505"):
					cb.call(false, "Este nome já está em uso.", {})
				elif code < 0:
					cb.call(false, "Banco de dados inacessível.", {})
				else:
					cb.call(false, "Falha ao criar conta (%d)." % code, {}))


func _authenticate(p_name: String, password: String, cb: Callable) -> void:
	_request(HTTPClient.METHOD_GET,
			"/rest/v1/accounts?select=*&name=eq.%s" % p_name.uri_encode(), null,
			func(code: int, data: Variant) -> void:
				if code < 0:
					cb.call(false, "Banco de dados inacessível.", {})
					return
				if code < 200 or code >= 300 or not (data is Array):
					cb.call(false, "Falha na consulta (%d)." % code, {})
					return
				var rows: Array = data
				if rows.is_empty():
					cb.call(false, "Conta não encontrada. Use a aba Registrar.", {})
					return
				var account: Dictionary = rows[0]
				var expected := str(account.get("password_hash", ""))
				var salt := str(account.get("salt", ""))
				if hash_password(password, salt) != expected:
					cb.call(false, "Senha incorreta.", {})
					return
				cb.call(true, "", expand_account(account)))


func _request(method: int, path: String, body: Variant, cb: Callable) -> void:
	var http := HTTPRequest.new()
	http.timeout = 8.0
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
		http.queue_free()
		var data: Variant = null
		var text := bytes.get_string_from_utf8()
		if not text.is_empty():
			data = JSON.parse_string(text)
		cb.call(code if result == HTTPRequest.RESULT_SUCCESS else -1, data)
	)
	var headers := PackedStringArray([
		"apikey: %s" % api_key,
		"Authorization: Bearer %s" % api_key,
		"Content-Type: application/json",
		"Prefer: return=minimal",
	])
	var payload := "" if body == null else JSON.stringify(body)
	var err := http.request(base_url + path, headers, method, payload)
	if err != OK:
		push_warning("HTTPRequest falhou ao iniciar (%s)." % error_string(err))
		http.queue_free()
		cb.call(-1, null)


func _error_has(data: Variant, needle: String) -> bool:
	return JSON.stringify(data).contains(needle)
