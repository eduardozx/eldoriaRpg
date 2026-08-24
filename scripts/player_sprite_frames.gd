class_name PlayerSpriteFrames
extends RefCounted
## SpriteFrames placeholder (8 direções × Idle/Walk) até entrar o spritesheet final.
## Aceita uma aparência customizável (pele, cabelo, túnica e calça).

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


static func build(appearance: Dictionary = {}) -> SpriteFrames:
	var look := normalize(appearance)
	var frames := SpriteFrames.new()
	for i in DIR_NAMES.size():
		var dir_name := DIR_NAMES[i]
		var facing := DIR_VECTORS[i]
		_add_clip(frames, "idle_%s" % dir_name, facing, false, 2, 2.0, look)
		_add_clip(frames, "walk_%s" % dir_name, facing, true, 4, 8.0, look)
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


static func _add_clip(
		frames: SpriteFrames,
		anim_name: String,
		facing: Vector2,
		walking: bool,
		frame_count: int,
		fps: float,
		look: Dictionary
) -> void:
	if frames.has_animation(anim_name):
		frames.remove_animation(anim_name)
	frames.add_animation(anim_name)
	frames.set_animation_speed(anim_name, fps)
	frames.set_animation_loop(anim_name, true)
	for frame_i in frame_count:
		var image := _draw_frame(facing, walking, frame_i, look)
		frames.add_frame(anim_name, ImageTexture.create_from_image(image))


static func _draw_frame(facing: Vector2, walking: bool, frame_i: int, look: Dictionary) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var f := facing.normalized()
	var walk_bob: Array[int] = [0, -2, 0, 2]
	var bob := 0
	if walking:
		bob = walk_bob[frame_i % 4]
	elif frame_i == 1:
		bob = -1

	_fill(image, Rect2i(10, 24, 12, 4), Color(0, 0, 0, 0.28))
	var leg: Color = look.pants
	if walking:
		var stride := 2 if frame_i < 2 else -2
		_fill(image, Rect2i(12 + int(round(f.x)) - stride, 20 + bob, 4, 6), leg)
		_fill(image, Rect2i(16 + int(round(f.x)) + stride, 20 + bob, 4, 6), leg)
	else:
		_fill(image, Rect2i(12, 21 + bob, 4, 5), leg)
		_fill(image, Rect2i(16, 21 + bob, 4, 5), leg)

	_fill(image, Rect2i(11, 12 + bob, 10, 10), look.shirt)
	var head := Vector2i(13 + int(round(f.x * 2.0)), 6 + bob + int(round(f.y * 2.0)))
	_fill(image, Rect2i(head.x, head.y, 6, 6), look.skin)
	_draw_hair(image, head, look)
	var eye := Color(0.12, 0.12, 0.16)
	_fill(image, Rect2i(head.x + 1 + int(f.x > 0.3), head.y + 2, 1, 1), eye)
	_fill(image, Rect2i(head.x + 3 + int(f.x > 0.3), head.y + 2, 1, 1), eye)
	return image


static func _draw_hair(image: Image, head: Vector2i, look: Dictionary) -> void:
	var hair: Color = look.hair
	match int(look.hair_style):
		0:
			pass
		1:
			_fill(image, Rect2i(head.x - 1, head.y - 1, 8, 3), hair)
		2:
			_fill(image, Rect2i(head.x - 1, head.y - 1, 8, 3), hair)
			_fill(image, Rect2i(head.x - 1, head.y + 2, 2, 5), hair)
			_fill(image, Rect2i(head.x + 5, head.y + 2, 2, 5), hair)
		3:
			_fill(image, Rect2i(head.x - 2, head.y - 1, 10, 3), hair)
			_fill(image, Rect2i(head.x - 2, head.y + 2, 2, 5), hair)
			_fill(image, Rect2i(head.x + 6, head.y + 2, 2, 5), hair)


static func _fill(image: Image, rect: Rect2i, color: Color) -> void:
	var clipped := rect.intersection(Rect2i(0, 0, SIZE, SIZE))
	if clipped.size.x > 0 and clipped.size.y > 0:
		image.fill_rect(clipped, color)
