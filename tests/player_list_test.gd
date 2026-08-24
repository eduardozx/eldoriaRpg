extends Node

var failures := 0


func _ready() -> void:
	_run()


func _check(cond: bool, message: String) -> void:
	if not cond:
		failures += 1
		print("FALHOU: %s" % message)


func _run() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	NetworkManager.local_player_name = "Aurora";
	var hud: CanvasLayer = (load("res://ui/player_hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	await get_tree().process_frame

	var panel: PanelContainer = hud.get_node("%PlayerListPanel")
	_check(not panel.visible, "lista começa oculta")

	var a: CharacterBody2D = (load("res://scenes/player.tscn") as PackedScene).instantiate()
	a.display_name = "Aurora"
	a.position = Vector2(100, 100)
	add_child(a)
	var b: CharacterBody2D = (load("res://scenes/player.tscn") as PackedScene).instantiate()
	b.display_name = "Boreas"
	b.set_multiplayer_authority(2) # simula outro jogador
	b.position = Vector2(140, 100)
	add_child(b)
	await get_tree().process_frame

	hud._refresh_player_list()
	var rows: VBoxContainer = hud.get_node("%ListRows")
	var texts: Array[String] = []
	for row in rows.get_children():
		texts.append((row as Label).text)
	_check(texts.size() == 2, "duas linhas na lista (%d)" % texts.size())
	_check(str(hud.get_node("%ListTitle").text).contains("online: 2"), "contador mostra 2")
	var joined := "; ".join(texts)
	_check(joined.contains("Aurora") and joined.contains("Boreas"), "nomes presentes")
	_check(joined.contains("você") and joined.count("você") == 1, "marca apenas o jogador local")
	_check(joined.contains("Nv 1"), "nível exibido")

	if failures == 0:
		print("TESTES DE LISTA OK")
	else:
		print("FALHAS: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)
