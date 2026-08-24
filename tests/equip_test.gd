extends Node

const SlashFx := preload("res://scripts/slash_effect.gd")
const BoltFx := preload("res://scripts/bolt_effect.gd")

var failures := 0


func _ready() -> void:
	_run()


func _check(cond: bool, message: String) -> void:
	if not cond:
		failures += 1
		print("FALHOU: %s" % message)


func _run() -> void:
	# --- ItemCatalog ---
	_check(ItemCatalog.weapon_attack("rusty_sword") == "slash", "espada deveria ser slash")
	_check(ItemCatalog.weapon_attack("wizard_staff") == "bolt", "cajado deveria ser bolt")
	_check(ItemCatalog.is_equipment("wizard_staff"), "cajado é equipamento")
	_check(not ItemCatalog.is_consumable("rusty_sword"), "espada não é consumível")
	_check(ItemCatalog.weapon_range("inexistente") == ItemCatalog.FIST_RANGE, "item inexistente usa alcance de punhos")

	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

	# --- PlayerData: equipar/desequipar ---
	var player: CharacterBody2D = (load("res://scenes/player.tscn") as PackedScene).instantiate()
	add_child(player)
	var data: PlayerData = player.get_node("%PlayerData")
	await get_tree().process_frame
	_check(data.count_item("wizard_staff") == 1, "kit inicial tem cajado")

	var staff_index := _find_slot(data, "wizard_staff")
	_check(staff_index >= 0, "cajado está no inventário")

	_check(data.toggle_equip(staff_index) and data.equipped_weapon_id == "wizard_staff", "equipou o cajado")
	_check(data.toggle_equip(staff_index) and data.equipped_weapon_id.is_empty(), "desequipou o cajado")
	_check(data.attack_damage("wizard_staff") == data.base_damage + 1, "bônus do cajado aplicado")
	_check(data.attack_damage("") == data.base_damage, "punhos sem bônus")

	data.toggle_equip(staff_index)
	_check(player.equipped_weapon == "wizard_staff", "player.equipped_weapon espelhou o equipamento")

	# --- Ataque com cajado: acerta monstro à distância e cria o projétil ---
	# Posições dentro de HUNT_BOUNDS (o monstro é preso a essa área pela física).
	player.global_position = Vector2(1600, 300)
	var monster: CharacterBody2D = (load("res://scenes/monster.tscn") as PackedScene).instantiate()
	monster.global_position = Vector2(1750, 300)
	add_child(monster)
	await get_tree().process_frame
	var hp_before: int = monster.hp
	player.facing_index = 0 # olhando para leste, na direção do monstro
	player._try_attack()
	await get_tree().process_frame
	_check(monster.hp == hp_before - clampi(data.attack_damage("wizard_staff"), 1, 80),
			"raio mágico causou dano (%d -> %d)" % [hp_before, monster.hp])
	_check(_has_fx(BoltFx), "BoltEffect criado")

	# --- Fora do alcance do cajado: sem dano ---
	monster.hp = monster.max_hp
	monster.global_position = Vector2(2150, 300)
	hp_before = monster.hp
	player._attack_cd = 0.0
	player.facing_index = 0
	player._try_attack()
	await get_tree().process_frame
	_check(monster.hp == hp_before, "monstro longe demais não tomou dano do cajado")

	# --- Espada: corte curto ---
	data.toggle_equip(staff_index)
	data.toggle_equip(_find_slot(data, "rusty_sword"))
	player._attack_cd = 0.0
	player.facing_index = 0
	player.global_position = Vector2(2500, 600)
	monster.global_position = Vector2(2535, 600)
	hp_before = monster.hp
	player._try_attack()
	await get_tree().process_frame
	_check(monster.hp == hp_before - clampi(data.attack_damage("rusty_sword"), 1, 80),
			"espada cortou (%d -> %d)" % [hp_before, monster.hp])
	_check(_has_fx(SlashFx), "SlashEffect criado")

	# --- Corte acompanha a direção do personagem (regressão rotação) ---
	player._attack_cd = 0.0
	player.facing_index = 4 # oeste
	player._try_attack()
	await get_tree().process_frame
	var west_slash: SlashFx = null
	for child in get_children():
		if is_instance_of(child, SlashFx) and child.rotation > 3.0:
			west_slash = child
	_check(west_slash != null, "corte para oeste fica rotacionado (~PI)")

	player._attack_cd = 0.0
	player.facing_index = 2 # sul
	player._try_attack()
	await get_tree().process_frame
	var south_slash: SlashFx = null
	for child in get_children():
		if is_instance_of(child, SlashFx) and absf(child.rotation - PI / 2.0) < 0.01:
			south_slash = child
	_check(south_slash != null, "corte para sul fica rotacionado (~PI/2)")

	# --- Alvo atrás do player: sem dano ---
	monster.hp = monster.max_hp
	monster.global_position = Vector2(2465, 600)
	hp_before = monster.hp
	player.facing_index = 0
	player._attack_cd = 0.0
	player._try_attack()
	await get_tree().process_frame
	_check(monster.hp == hp_before, "golpe nas costas não acerta")

	if failures == 0:
		print("TESTES DE EQUIPAMENTO OK")
	else:
		print("FALHAS: %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _find_slot(data: PlayerData, item_id: String) -> int:
	for i in PlayerData.SLOT_COUNT:
		if str(data.get_slot(i).get("item_id", "")) == item_id:
			return i
	return -1


func _has_fx(script_type: GDScript) -> bool:
	for child in get_children():
		if is_instance_of(child, script_type):
			return true
	return false
