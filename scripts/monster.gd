extends CharacterBody2D
## Monstro PVE: patrulha a Área de Caça, persegue o player e recompensa quem derrotar.

const PATROL_SPEED := 58.0
const CHASE_SPEED := 96.0
const RETURN_SPEED := 110.0
const ATTACK_RANGE := 28.0
const ATTACK_COOLDOWN := 1.15
const PATROL_RADIUS := 90.0
const AGGRO_RANGE := 200.0
const LEASH_RANGE := 340.0
const RESPAWN_SEC := 8.0
const HUNT_BOUNDS := Rect2(1376, 96, 1728, 848)

@export var display_name: String = "Monstro":
	set(value):
		display_name = value
		_refresh_label()

@export var max_hp: int = 50:
	set(value):
		max_hp = maxi(value, 1)
		hp = mini(hp, max_hp)
		_refresh_health()

@export var hp: int = 50:
	set(value):
		hp = clampi(value, 0, maxi(max_hp, 1))
		_refresh_health()

@export var contact_damage: int = 6
@export var exp_reward: int = 18
@export var gold_reward: int = 5
@export var is_alive: bool = true:
	set(value):
		is_alive = value
		_apply_alive_state()

@onready var body_rect: ColorRect = %Body
@onready var name_label: Label = %NameLabel
@onready var health_bar: Node2D = %HealthBar
@onready var collision_shape: CollisionShape2D = %CollisionShape2D

var _home := Vector2.ZERO
var _patrol_target := Vector2.ZERO
var _attack_cd := 0.0
var _respawn_left := 0.0
var _hurt_flash := 0.0


func _ready() -> void:
	add_to_group("monster")
	motion_mode = MOTION_MODE_FLOATING
	_home = global_position
	_patrol_target = _home
	hp = max_hp
	_refresh_label()
	_refresh_health()
	_apply_alive_state()
	if health_bar.has_method("set_health"):
		health_bar.fill_color = Color(0.86, 0.38, 0.28, 1)


func _physics_process(delta: float) -> void:
	_hurt_flash = maxf(_hurt_flash - delta, 0.0)
	if body_rect:
		body_rect.modulate = Color(1.4, 1.4, 1.4) if _hurt_flash > 0.0 else Color.WHITE

	if not _is_ai_authority():
		velocity = Vector2.ZERO
		return

	if not is_alive:
		velocity = Vector2.ZERO
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			_respawn()
		move_and_slide()
		return

	_attack_cd = maxf(_attack_cd - delta, 0.0)
	var prey := _find_prey()
	var to_home := global_position.distance_to(_home)

	if to_home > LEASH_RANGE:
		_move_toward(_home, RETURN_SPEED)
	elif prey:
		var to_prey: float = global_position.distance_to(prey.global_position)
		if to_prey <= ATTACK_RANGE:
			velocity = Vector2.ZERO
			if _attack_cd <= 0.0:
				_strike_player(prey)
		else:
			_move_toward(prey.global_position, CHASE_SPEED)
	else:
		if global_position.distance_to(_patrol_target) < 12.0:
			_pick_patrol_point()
		_move_toward(_patrol_target, PATROL_SPEED)

	global_position.x = clampf(global_position.x, HUNT_BOUNDS.position.x + 16.0, HUNT_BOUNDS.end.x - 16.0)
	global_position.y = clampf(global_position.y, HUNT_BOUNDS.position.y + 16.0, HUNT_BOUNDS.end.y - 16.0)
	move_and_slide()


func request_player_hit(amount: int, attacker_peer: int) -> void:
	if not is_alive:
		return
	if multiplayer.is_server():
		_apply_player_hit(amount, attacker_peer)
		return
	rpc_id(1, "rpc_player_hit", amount, attacker_peer)


@rpc("any_peer", "reliable")
func rpc_player_hit(amount: int, attacker_peer: int) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != attacker_peer:
		return
	_apply_player_hit(amount, attacker_peer)


func _apply_player_hit(amount: int, attacker_peer: int) -> void:
	if not is_alive:
		return
	var dealt := clampi(amount, 1, 80)
	hp -= dealt
	_hurt_flash = 0.12
	if hp > 0:
		return
	_die(attacker_peer)


func _die(killer_peer: int) -> void:
	is_alive = false
	hp = 0
	_respawn_left = RESPAWN_SEC
	var killer := NetworkManager.get_player_node(killer_peer)
	if killer == null or not killer.has_method("rpc_receive_rewards"):
		return
	if killer_peer == multiplayer.get_unique_id():
		killer.rpc_receive_rewards(exp_reward, gold_reward)
	else:
		killer.rpc_id(killer_peer, "rpc_receive_rewards", exp_reward, gold_reward)


func _respawn() -> void:
	global_position = _home
	hp = max_hp
	is_alive = true
	_patrol_target = _home
	_attack_cd = 0.6


func _strike_player(player: Node) -> void:
	_attack_cd = ATTACK_COOLDOWN
	if not player.has_method("rpc_receive_monster_hit"):
		return
	var peer_id := int(str(player.name))
	if peer_id == multiplayer.get_unique_id():
		player.rpc_receive_monster_hit(contact_damage)
	else:
		player.rpc_id(peer_id, "rpc_receive_monster_hit", contact_damage)


func _find_prey() -> Node2D:
	var best: Node2D = null
	var best_dist := AGGRO_RANGE
	for node in get_tree().get_nodes_in_group("player"):
		if not (node is Node2D):
			continue
		if node.has_method("is_combat_alive") and not node.is_combat_alive():
			continue
		var dist: float = global_position.distance_to(node.global_position)
		if dist < best_dist:
			best = node
			best_dist = dist
	return best


func _move_toward(target: Vector2, speed: float) -> void:
	var offset := target - global_position
	if offset.length_squared() < 1.0:
		velocity = Vector2.ZERO
		return
	velocity = offset.normalized() * speed


func _pick_patrol_point() -> void:
	var angle := randf() * TAU
	var radius := randf() * PATROL_RADIUS
	var point := _home + Vector2.from_angle(angle) * radius
	point.x = clampf(point.x, HUNT_BOUNDS.position.x + 24.0, HUNT_BOUNDS.end.x - 24.0)
	point.y = clampf(point.y, HUNT_BOUNDS.position.y + 24.0, HUNT_BOUNDS.end.y - 24.0)
	_patrol_target = point


func _is_ai_authority() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	return multiplayer.is_server()


func _apply_alive_state() -> void:
	visible = is_alive
	collision_shape.set_deferred("disabled", not is_alive)
	set_collision_layer_value(3, is_alive)


func _refresh_label() -> void:
	if name_label:
		name_label.text = display_name


func _refresh_health() -> void:
	if health_bar and health_bar.has_method("set_health"):
		health_bar.set_health(hp, max_hp)
