class_name FloatingHealthBar
extends Node2D
## Barra de HP no mundo (player e monstros).

@export var bar_size := Vector2(36, 5)
@export var fill_color := Color(0.32, 0.86, 0.42, 1)
@export var low_color := Color(0.92, 0.28, 0.24, 1)
@export var back_color := Color(0.08, 0.08, 0.1, 0.85)

var _ratio := 1.0


func set_health(current: int, maximum: int) -> void:
	if maximum <= 0:
		_ratio = 0.0
	else:
		_ratio = clampf(float(current) / float(maximum), 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var bg := Rect2(-bar_size.x * 0.5, 0.0, bar_size.x, bar_size.y)
	draw_rect(bg, back_color, true)
	var inner_w := (bar_size.x - 2.0) * _ratio
	if inner_w > 0.0:
		var fill := fill_color if _ratio > 0.35 else low_color
		draw_rect(Rect2(-bar_size.x * 0.5 + 1.0, 1.0, inner_w, bar_size.y - 2.0), fill, true)
