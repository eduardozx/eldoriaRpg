extends Node
## Lógica do teste end-to-end. Vive fora da cena para sobreviver ao mundo.

var mode := ""
var p_name := ""
var password := ""
var done := false


func _ready() -> void:
	mode = OS.get_environment("ELDORIA_TEST_MODE")
	p_name = OS.get_environment("ELDORIA_TEST_NAME")
	password = OS.get_environment("ELDORIA_TEST_PASS")
	print("TEST_MODE=", mode, " name=", p_name)
	if mode == "register":
		NetworkManager.register_result.connect(_on_register_result)
		await get_tree().process_frame
		NetworkManager.start_register(p_name, password)
	elif mode == "login_new":
		NetworkManager.needs_character_creation.connect(_on_needs_creation)
		NetworkManager.auth_failed.connect(func(reason: String) -> void:
			_finish("LOGIN_FAILED " + reason))
		await get_tree().process_frame
		NetworkManager.join_or_host(p_name, password)
	elif mode == "login_existing":
		NetworkManager.needs_character_creation.connect(func() -> void:
			_finish("FAIL_CREATOR_SHOULD_NOT_SHOW"))
		NetworkManager.join_or_host(p_name, password)
		var expected := OS.get_environment("ELDORIA_TEST_EXPECT")
		var parts := expected.split(",") if not expected.is_empty() else PackedStringArray(["1500", "300"])
		_await_world_then_check_position(float(parts[0]), float(parts[1]))
	else:
		_finish("UNKNOWN_MODE")
	_timeout_guard()


func _timeout_guard() -> void:
	await get_tree().create_timer(20.0).timeout
	if not done:
		print("RESULT=TIMEOUT")
		get_tree().quit(1)


func _finish(line: String, code := 0) -> void:
	if done:
		return
	done = true
	print("RESULT=" + line)
	get_tree().quit(code)


func _on_register_result(ok: bool, message: String) -> void:
	_finish(("REGISTER_OK" if ok else "REGISTER_FAIL " + message))


func _on_needs_creation() -> void:
	print("STEP=CREATOR_SHOWN")
	# Confirma a aparência e entra no mundo.
	NetworkManager.complete_character_creation({
		"hair_style": 3, "shirt": "ff0000", "skin": "eec39a",
	})
	_await_world_then_save()


func _await_world_then_save() -> void:
	var waited := 0.0
	while waited < 12.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
		var scene := get_tree().current_scene
		if scene != null and scene.scene_file_path == "res://scenes/world.tscn":
			break
	if waited >= 12.0:
		_finish("FAIL_WORLD_NEVER_LOADED", 1)
		return
	print("STEP=WORLD_LOADED")
	var player := await _find_local_player()
	if player == null:
		_finish("FAIL_NO_PLAYER", 1)
		return
	player.global_position = Vector2(1500, 300)
	NetworkManager._save_now()
	await get_tree().create_timer(1.5).timeout
	_finish("SAVED_WITH_POSITION")


func _find_local_player() -> Node2D:
	for attempt in 40:
		for node in get_tree().get_nodes_in_group("player"):
			if node is Node2D and str(node.display_name) == p_name:
				return node
		await get_tree().create_timer(0.25).timeout
	return null


func _await_world_then_check_position(expected_x: float, expected_y: float) -> void:
	var waited := 0.0
	while waited < 12.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
		var scene := get_tree().current_scene
		if scene != null and scene.scene_file_path == "res://scenes/world.tscn":
			break
	if waited >= 12.0:
		_finish("FAIL_WORLD_NEVER_LOADED", 1)
		return
	var player := await _find_local_player()
	if player == null:
		_finish("FAIL_NO_PLAYER", 1)
		return
	var pos := player.global_position
	if pos.distance_to(Vector2(expected_x, expected_y)) >= 60.0:
		_finish("FAIL_POSITION_MISMATCH %d,%d" % [int(pos.x), int(pos.y)], 1)
		return
	print("STEP=RESTORED %d,%d" % [int(pos.x), int(pos.y)])
	# Move para outro lugar e salva de novo: a posição NOVA deve vencer no banco.
	player.global_position = Vector2(expected_x + 100.0, expected_y + 50.0)
	NetworkManager._save_now()
	await get_tree().create_timer(1.5).timeout
	_finish("RESAVED %d,%d" % [int(player.global_position.x), int(player.global_position.y)])
