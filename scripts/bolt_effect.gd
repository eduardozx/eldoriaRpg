class_name BoltEffect
extends Node2D
## Projétil mágico do cajado: viaja em linha reta e desaparece no alcance máximo.

const SPEED := 340.0
const TRAIL_COUNT := 4

var direction := Vector2.RIGHT
var max_dist := 175.0
var color := Color(0.55, 0.75, 1.0, 1.0)

var _traveled := 0.0
var _trail: Array[Vector2] = []


func _ready() -> void:
	z_index = 20


func _process(delta: float) -> void:
	var step := SPEED * delta
	position += direction * step
	_traveled += step
	_trail.push_front(position)
	while _trail.size() > TRAIL_COUNT:
		_trail.pop_back()
	queue_redraw()
	if _traveled >= max_dist:
		queue_free()


func _draw() -> void:
	for i in _trail.size():
		var trail_pos := to_local(_trail[i])
		var fade := (1.0 - float(i + 1) / float(TRAIL_COUNT + 1)) * 0.35
		draw_circle(trail_pos, 3.0, Color(color.r, color.g, color.b, fade))
	draw_circle(Vector2.ZERO, 6.5, Color(color.r, color.g, color.b, 0.30))
	draw_circle(Vector2.ZERO, 4.2, Color(color.r, color.g, color.b, 0.85))
	draw_circle(Vector2.ZERO, 1.8, Color(1, 1, 1, 0.95))
