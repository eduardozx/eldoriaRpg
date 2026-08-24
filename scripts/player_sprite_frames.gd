class_name PlayerSpriteFrames
extends RefCounted
## SpriteFrames proceduais do herói: 8 direções × Idle/Walk/Attack,
## com aparência customizável e visuais de equipamentos (arma na mão,
## elmo e peitoral alteram o desenho).

const SIZE := 32
const HAIR_STYLE_COUNT := 4
const DEFAULT_APPEARANCE := {
	"skin": Color(0.96, 0.84, 0.70),
	"hair": Color(0.28, 0.20, 0.14),
	"hair_style": 1,
	"shirt": Color(0.32, 0.62, 0.88),
	"pants": Color(0.20, 0.26, 0.42),
}
const COLOR_KEYS: PackedStringArray = ["skin", "hair", "shirt", "pants"]
const DIR_NAMES: PackedStringArray = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
const DIR_VECTORS: Array[Vector2] = [
	Vector2(1, 0),
	Vector2(1, 1),
	Vector2(0, 1),
	Vector2(-1, 1),
	Vector2(-1, 0),
	Vector2(-1, -1),
	Vector2(0, -1),
	Vector2(1, -1),
]

## Visuais dos equipamentos por id (espalhados com o ItemCatalog).
const EQUIPMENT_VISUALS := {
	"rusty_sword": {
		"kind": "sword",
		"blade": Color(0.74, 0.64, 0.50),
		"edge": Color(0.88, 0.82, 0.68),
		"hilt": Color(0.38, 0.26, 0.15),
	},
	"wizard_staff": {
		"kind": "staff",
		"wood": Color(0.46, 0.32, 0.19),
		"orb": Color(0.40, 0.82, 1.00),
	},
	"iron_helm": {
		"kind": "helm",
		"tint": Color(0.67, 0.70, 0.80),
		"dark": Color(0.44, 0.47, 0.58),
	},
	"iron_chest": {
		"kind": "chest",
		"tint": Color(0.63, 0.66, 0.77),
		"dark": Color(0.41, 0.44, 0.56),
	},
}


static func build(appearance: Dictionary = {}, equipment: Dictionary = {}) -> SpriteFrames:
	var look := normalize(appearance)
	var gear := normalize_equipment(equipment)
	var frames := SpriteFrames.new()
	for i in DIR_NAMES.size():
		var dir_name := DIR_NAMES[i]
		var facing := DIR_VECTORS[i]
		_add_clip(frames, "idle_%s" % dir_name, facing, false, 2, 2.0, look, gear, -1)
		_add_clip(frames, "walk_%s" % dir_name, facing, true, 4, 8.0, look, gear, -1)
		_add_clip(frames, "attack_%s" % dir_name, facing, false, 3, 10.0, look, gear, i)
	return frames


static func normalize(raw: Variant) -> Dictionary:
	var look: Dictionary = DEFAULT_APPEARANCE.duplicate(true)
	if raw is Dictionary:
		for key in COLOR_KEYS:
			var value: Variant = raw.get(key)
			if value is Color:
				look[key] = value
			elif value is String and not value.is_empty():
				var html: String = value if value.begins_with("#") else "#" + value
				if html.is_valid_html_color():
					look[key] = Color(html)
				elif value.contains("("):
					# Aceita também o formato interno "R, G, B, A" do Godot.
					look[key] = Color.from_string(value, look[key])
		var style := int(raw.get("hair_style", -1))
		if style >= 0 and style < HAIR_STYLE_COUNT:
			look["hair_style"] = style
	return look


## Normaliza {hand, helmet, chest} para ids válidos + visuais resolvidos.
static func normalize_equipment(equipment: Variant) -> Dictionary:
	var out := {"hand": "", "helmet": "", "chest": ""}
	if equipment is Dictionary:
		for key in ["hand", "helmet", "chest"]:
			var item_id := str(equipment.get(key, ""))
			out[key] = item_id if EQUIPMENT_VISUALS.has(item_id) else ""
	return out


static func _add_clip(
		frames: SpriteFrames,
		anim_name: String,
		facing: Vector2,
		walking: bool,
		frame_count: int,
		fps: float,
		look: Dictionary,
		gear: Dictionary,
		attack_dir_index: int
) -> void:
	if frames.has_animation(anim_name):
		frames.remove_animation(anim_name)
	frames.add_animation(anim_name)
	frames.set_animation_speed(anim_name, fps)
	frames.set_animation_loop(anim_name, true)
	for frame_i in frame_count:
		var image := _draw_frame(facing, walking, frame_i, look, gear, attack_dir_index)
		frames.add_frame(anim_name, ImageTexture.create_from_image(image))


static func _draw_frame(
		facing: Vector2,
		walking: bool,
		frame_i: int,
		look: Dictionary,
		gear: Dictionary,
		attack_dir_index: int
) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var f := facing.normalized()
	var fx := int(round(f.x))
	var fy := int(round(f.y))

	var bob := 0
	var stride := 0
	if attack_dir_index >= 0:
		bob = [0, 1, 0][frame_i % 3]
	elif walking:
		var walk_bob: Array[int] = [0, -2, 0, 2]
		bob = walk_bob[frame_i % 4]
		stride = 2 if frame_i < 2 else -2
	elif frame_i == 1:
		bob = -1

	# Fase do golpe: 0=prepara, 1=golpeia, 2=recupera (-1 = sem ataque)
	var swing := -1.0
	if attack_dir_index >= 0:
		swing = [0.0, 1.0, 0.55][frame_i % 3]
	var lean := int(round(f.x * (swing * 1.4 - 0.4)))

	_fill(image, Rect2i(10, 25, 13, 3), Color(0, 0, 0, 0.30))

	var skin: Color = look.skin
	var skin_dark: Color = skin.darkened(0.25)
	var pants: Color = look.pants
	var boot: Color = pants.darkened(0.55)

	# Pernas + botas
	var leg_off := stride * (1 if absf(f.x) > 0.01 else 0)
	_fill(image, Rect2i(12 - leg_off, 20, 4, 5), pants)
	_fill(image, Rect2i(16 + leg_off, 20, 4, 5), pants)
	_fill(image, Rect2i(12 - leg_off, 24, 4, 2), boot)
	_fill(image, Rect2i(16 + leg_off, 24, 4, 2), boot)

	# Torso (túnica) com sombra lateral e cinto
	var torso := Rect2i(11 + lean, 11 + bob, 10, 10)
	_fill(image, Rect2i(torso), look.shirt)
	_fill(image, Rect2i(torso.position.x + 8, torso.position.y, 2, 10), look.shirt.darkened(0.22))
	_fill(image, Rect2i(torso.position.x, torso.position.y + 8, 10, 2), Color(0.23, 0.16, 0.10))
	_fill(image, Rect2i(torso.position.x + 4, torso.position.y + 8, 2, 2), Color(0.75, 0.65, 0.30))

	# Braços (mangas) + mãos
	var arm_color: Color = look.shirt.darkened(0.30)
	var back_arm := Rect2i(9 + lean, 12 + bob, 2, 6)
	var front_arm := Rect2i(21 + lean, 12 + bob, 2, 6)
	_fill(image, back_arm, arm_color)
	_fill(image, Rect2i(back_arm.position.x, back_arm.position.y + 6, 2, 2), skin_dark)
	if swing > 0.6:
		# Braço da frente estendido na direção do golpe
		var ext := Rect2i(21 + lean + fx * 3, 13 + bob + fy * 2, 2, 5)
		_fill(image, ext, arm_color)
		_fill(image, Rect2i(ext.position.x, ext.position.y + 5, 2, 2), skin)
	else:
		_fill(image, front_arm, arm_color)
		_fill(image, Rect2i(front_arm.position.x, front_arm.position.y + 6, 2, 2), skin)

	# Peitoral por cima da túnica
	var chest_id: String = gear.chest
	if chest_id != "":
		var chest: Dictionary = EQUIPMENT_VISUALS[chest_id]
		var tint: Color = chest.tint
		var dark: Color = chest.dark
		_fill(image, Rect2i(torso.position.x, torso.position.y + 1, 10, 7), tint)
		_fill(image, Rect2i(torso.position.x, torso.position.y + 1, 2, 7), tint.lightened(0.18))
		_fill(image, Rect2i(torso.position.x + 8, torso.position.y + 1, 2, 7), dark)
		_fill(image, Rect2i(torso.position.x + 4, torso.position.y + 2, 2, 5), dark)
		_fill(image, Rect2i(8 + lean, 11 + bob, 3, 3), tint)   # ombro esquerdo
		_fill(image, Rect2i(21 + lean, 11 + bob, 3, 3), tint) # ombro direito

	# Cabeça
	var head := Vector2i(12 + lean, 4 + bob + fy * 2)
	_fill(image, Rect2i(head.x, head.y, 8, 7), skin)
	_fill(image, Rect2i(head.x, head.y + 5, 8, 2), skin_dark)
	_fill(image, Rect2i(head.x, head.y, 1, 7), skin_dark)

	# Cabelo ou elmo
	var helm_id: String = gear.helmet
	if helm_id != "":
		var helm: Dictionary = EQUIPMENT_VISUALS[helm_id]
		_fill(image, Rect2i(head.x - 1, head.y - 1, 10, 4), helm.tint)
		_fill(image, Rect2i(head.x - 1, head.y - 1, 10, 1), helm.tint.lightened(0.2))
		_fill(image, Rect2i(head.x - 1, head.y + 2, 10, 1), helm.dark)
		if f.x > -0.99:
			_fill(image, Rect2i(head.x + 3, head.y + 1, 2, 3), helm.dark)
	elif int(look.hair_style) > 0:
		var hair: Color = look.hair
		match int(look.hair_style):
			1:
				_fill(image, Rect2i(head.x - 1, head.y - 1, 10, 3), hair)
				_fill(image, Rect2i(head.x - 1, head.y + 1, 2, 3), hair)
				_fill(image, Rect2i(head.x + 7, head.y + 1, 2, 3), hair)
			2:
				_fill(image, Rect2i(head.x - 1, head.y - 1, 10, 3), hair)
				_fill(image, Rect2i(head.x - 1, head.y + 1, 2, 8), hair)
				_fill(image, Rect2i(head.x + 7, head.y + 1, 2, 8), hair)
			3:
				_fill(image, Rect2i(head.x - 2, head.y - 1, 12, 4), hair)
				_fill(image, Rect2i(head.x - 2, head.y + 2, 3, 6), hair)
				_fill(image, Rect2i(head.x + 7, head.y + 2, 3, 6), hair)

	# Olhos (some quando olha pra trás / elmo fechado é fino o bastante pra manter)
	if fy > -0.99:
		var eye := Color(0.10, 0.10, 0.14)
		var eye_shift := 1 if f.x > 0.3 else (-1 if f.x < -0.3 else 0)
		_fill(image, Rect2i(head.x + 2 + eye_shift, head.y + 3, 1, 2), eye)
		_fill(image, Rect2i(head.x + 5 + eye_shift, head.y + 3, 1, 2), eye)

	# Arma na mão (com golpe animado)
	_draw_weapon(image, f, gear, swing, bob, lean)

	return image


static func _draw_weapon(image: Image, f: Vector2, gear: Dictionary, swing: float, bob: int, lean: int) -> void:
	var hand_id: String = gear.hand
	if hand_id == "":
		return
	var visual: Dictionary = EQUIPMENT_VISUALS[hand_id]
	# Pivô = mão da frente; ângulo base aponta levemente pra baixo-frente.
	var pivot := Vector2(22 + lean + f.x * 2.0, 17 + bob + f.y * 2.0)
	var base_angle := f.angle() + deg_to_rad(38.0)
	var angle := base_angle
	var length := 11.0
	match visual.kind:
		"sword":
			match signf(swing):
				0.0:
					angle = base_angle - deg_to_rad(70.0)
					length = 9.0
				1.0:
					angle = base_angle + deg_to_rad(52.0)
					length = 14.0
				-1.0:
					pass
			if swing == 1.0:
				# Rastro do golpe
				_plot_line(image, pivot, angle - deg_to_rad(34.0), length + 2.0, Color(1, 1, 1, 0.35), 1.0)
			_plot_line(image, pivot, angle, length, visual.blade, 2.0)
			_plot_line(image, pivot, angle, length, visual.edge, 1.0)
			_plot_dot(image, pivot + Vector2.from_angle(angle) * (length + 1.0), visual.edge)
			_plot_line(image, pivot - Vector2.from_angle(angle) * 3.0, angle, 3.0, visual.hilt, 2.0)
		"staff":
			angle = base_angle - deg_to_rad(20.0)
			if swing == 0.0:
				angle -= deg_to_rad(30.0)
			elif swing == 1.0:
				angle += deg_to_rad(18.0)
			_plot_line(image, pivot, angle, 13.0, visual.wood, 2.0)
			var tip := pivot + Vector2.from_angle(angle) * 13.0
			var orb: Color = visual.orb
			if swing == 1.0:
				_plot_dot(image, tip + Vector2.ZERO, Color(orb.r, orb.g, orb.b, 0.35), 4)
			_plot_dot(image, tip, orb, 2)
			_plot_dot(image, tip, Color(1, 1, 1, 0.9), 1)


static func _plot_line(image: Image, from: Vector2, angle: float, length: float, color: Color, width: float) -> void:
	var step := Vector2.from_angle(angle)
	var steps := int(length * 2.0)
	for i in steps + 1:
		var pos := from + step * (float(i) / 2.0)
		var half := int(width / 2.0)
		for dx in range(-half, half + 1):
			for dy in range(-half, half + 1):
				_px(image, int(pos.x) + dx, int(pos.y) + dy, color)


static func _plot_dot(image: Image, pos: Vector2, color: Color, radius: int = 1) -> void:
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			_px(image, int(pos.x) + dx, int(pos.y) + dy, color)


static func _px(image: Image, x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
		return
	image.set_pixel(x, y, color)


static func _fill(image: Image, rect: Rect2i, color: Color) -> void:
	var clipped := rect.intersection(Rect2i(0, 0, SIZE, SIZE))
	if clipped.size.x > 0 and clipped.size.y > 0:
		image.fill_rect(clipped, color)
