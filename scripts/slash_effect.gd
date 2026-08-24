class_name SlashEffect
extends Node2D
## Efeito de corte em arco da espada. Rotacione o nó para a direção do golpe.

const LIFETIME := 0.18
const RADIUS := 26.0

var color := Color(1.0, 1.0, 1.0, 0.9)

var _time := 0.0


func _ready() -> void:
	z_index = 20


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()
	if _time >= LIFETIME:
		queue_free()


func _draw() -> void:
	var progress := clampf(_time / LIFETIME, 0.0, 1.0)
	var alpha := 1.0 - progress
	var half_span := lerpf(0.5, 1.35, minf(progress * 2.2, 1.0))
	var radius := RADIUS * (0.7 + 0.3 * progress)
	var arc_color := Color(color.r, color.g, color.b, color.a * alpha)
	draw_arc(Vector2.ZERO, radius, -half_span, half_span, 12, arc_color, 3.0, true)
	draw_arc(Vector2.ZERO, radius - 4.0, -half_span, half_span, 10, Color(arc_color.r, arc_color.g, arc_color.b, arc_color.a * 0.55), 1.5, true)
