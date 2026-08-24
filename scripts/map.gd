extends Node2D
## Mapa geral top-down: spawn, vila (safe), caça (PVE) e arena PVP.

const MAP_SIZE := Vector2(3200, 1920)

@onready var spawn_point: Marker2D = %SpawnPoint


func _ready() -> void:
	add_to_group("world_map")
	y_sort_enabled = true


func get_spawn_position() -> Vector2:
	return spawn_point.global_position


func get_map_size() -> Vector2:
	return MAP_SIZE
