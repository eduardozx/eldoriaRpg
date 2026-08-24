extends Node2D

@onready var players: Node2D = %Players
@onready var map: Node2D = %Map
@onready var zone_label: Label = %ZoneLabel


func _ready() -> void:
	NetworkManager.bind_world(players, map.get_spawn_position())
