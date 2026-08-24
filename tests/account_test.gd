extends Node

var failures := 0


func _ready() -> void:
	_run()


func _check(cond: bool, message: String) -> void:
	if not cond:
		failures += 1
		print("FALHOU: %s" % message)


func _run() -> void:
	# --- Hash de senha ---
	var salt_a := DatabaseManager.random_salt()
	var salt_b := DatabaseManager.random_salt()
	_check(salt_a != salt_b, "salts devem ser diferentes")
	var h1 := DatabaseManager.hash_password("abc123", salt_a)
	var h2 := DatabaseManager.hash_password("abc123", salt_a)
	var h3 := DatabaseManager.hash_password("abc123", salt_b)
	var h4 := DatabaseManager.hash_password("senha_errada", salt_a)
	_check(h1 == h2, "mesma senha+salt gera mesmo hash")
	_check(h1 != h3, "salt diferente gera hash diferente")
	_check(h1 != h4, "senha diferente gera hash diferente")
	_check(h1.length() == 64, "hash sha256 tem 64 hex")

	# --- Modo offline do banco (sem env vars no teste) ---
	if not DatabaseManager.enabled:
		var result := [false, ""]
		DatabaseManager.authenticate_or_register("register", "Zara", "segredo",
				func(ok: bool, message: String, _account: Dictionary) -> void:
					result[0] = ok
					result[1] = message)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(result[0], "registro offline permite jogar")
	else:
		print("AVISO: Supabase configurado; pulando teste de modo offline")

	# --- Snapshot do PlayerData (persistência) ---
	var data: PlayerData = load("res://scripts/player_data.gd").new()
	add_child(data)
	await get_tree().process_frame # starter kit nasce primeiro
	data.add_gold(700)
	data.add_experience(250) # sobe de nível
	data.add_item("wizard_staff", 1)
	var staff_slot := -1
	for i in PlayerData.SLOT_COUNT:
		if str(data.get_slot(i).get("item_id", "")) == "wizard_staff":
			staff_slot = i
			break
	data.toggle_equip(staff_slot)

	var snap := data.to_snapshot()
	_check(int(snap["level"]) == 2, "experiência subiu de nível")
	_check(str(snap["equipped_weapon_id"]) == "wizard_staff", "cajado equipado no snapshot")

	# Conta nova aplicando o mesmo snapshot
	var restored: PlayerData = load("res://scripts/player_data.gd").new()
	add_child(restored)
	await get_tree().process_frame # deixa o starter kit nascer antes de sobrescrever
	restored.apply_snapshot(snap)
	_check(restored.to_snapshot().hash() == snap.hash(), "snapshot restaurado é idêntico")
	_check(restored.level == data.level, "nível restaurado")
	_check(restored.max_hp == data.max_hp, "max_hp restaurado")
	_check(restored.equipped_weapon_id == "wizard_staff", "equipamento restaurado")
	_check(restored.hp == restored.max_hp, "vida cheia ao logar")

	# --- Wrapper do jsonb inventory (posição + aparência + flag, sem colunas extras) ---
	var packed: Variant = DatabaseManager.pack_inventory({
		"inventory": [{"item_id": "rusty_sword", "quantity": 1}],
		"pos_x": 1234.5,
		"pos_y": 678.9,
		"appearance": {"hair_style": 2, "shirt": "ff0000"},
		"character_created": true,
	})
	_check(packed is Dictionary and int(packed["v"]) == DatabaseManager.INVENTORY_VERSION,
			"pack cria wrapper v2")
	var expanded := DatabaseManager.expand_account({
		"name": "Zara", "level": 4, "gold": 250,
		"equipped_weapon_id": "rusty_sword",
		"inventory": packed,
	})
	_check(bool(expanded["character_created"]), "flag character_created lida")
	_check(expanded["appearance"] is Dictionary
			and int(expanded["appearance"]["hair_style"]) == 2,
			"aparência lida do banco")
	_check(absf(float(expanded["pos_x"]) - 1234.5) < 0.01, "posição X lida")
	_check(expanded["inventory"] is Array and not (expanded["inventory"] as Array).is_empty(),
			"slots restaurados do wrapper")
	var normalized: Dictionary = PlayerSpriteFrames.normalize(expanded["appearance"])
	_check(int(normalized["hair_style"]) == 2 \
			and (normalized["shirt"] as Color).is_equal_approx(Color("ff0000")),
			"aparência normaliza corretamente")

	# Array antigo = conta legado com personagem já criado
	var legacy := DatabaseManager.expand_account({"name": "Velho", "inventory": []})
	_check(bool(legacy["character_created"]), "legado conta como criado")

	# --- Pipeline do host desktop: linha CRUA do PostgREST → snapshot ---
	# Regressão: o caminho do host precisa expandir antes de decidir criador/posição.
	var host_path := NetworkManager._snapshot_from_account(DatabaseManager.expand_account({
		"name": "HostPath",
		"level": 5,
		"gold": 900,
		"equipped_weapon_id": "",
		"inventory": {
			"v": 2, "slots": [{"item_id": "bread", "quantity": 2}],
			"pos_x": 900.0, "pos_y": 480.0,
			"appearance": {"hair_style": 1},
			"character_created": true,
		},
	}))
	_check(bool(host_path.get("character_created", false)), "host: flag criado visível")
	_check(absf(float(host_path.get("pos_x", 0.0)) - 900.0) < 0.01, "host: posição visível")
	_check((host_path.get("inventory") as Array).size() == 1, "host: slots desempacotados")
	var fresh_host := NetworkManager._snapshot_from_account(DatabaseManager.expand_account({
		"name": "Fresh",
		"inventory": {"v": 2, "slots": [], "pos_x": 0.0, "pos_y": 0.0,
			"appearance": {}, "character_created": false},
	}))
	_check(not bool(fresh_host.get("character_created", true)),
			"host: conta nova NÃO marca personagem como criado")

	if failures == 0:
		print("TESTES DE CONTA OK")
	else:
		print("FALHAS: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
