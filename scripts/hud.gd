extends CanvasLayer

const HEART_SCALE := 4
const HEART_GAP := 6

var _filled: Texture2D
var _empty: Texture2D
var _icons: Array[TextureRect] = []


func _ready() -> void:
	layer = 20
	_filled = _make_heart(true)
	_empty = _make_heart(false)

	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 10)
	root.add_theme_constant_override("margin_top", 10)
	add_child(root)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", HEART_GAP)
	root.add_child(row)

	for i in 3:
		var icon := TextureRect.new()
		icon.texture = _filled
		icon.stretch_mode = TextureRect.STRETCH_KEEP
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		row.add_child(icon)
		_icons.append(icon)

	var player := get_tree().get_first_node_in_group("player")
	if player:
		if player.has_signal("health_changed"):
			player.health_changed.connect(_on_health_changed)
		var current: Variant = player.get("health")
		var maximum: Variant = player.get("MAX_HEALTH")
		if current is int and maximum is int:
			_on_health_changed(current, maximum)


func _on_health_changed(current: int, maximum: int) -> void:
	for i in _icons.size():
		if i < maximum:
			_icons[i].visible = true
			_icons[i].texture = _filled if i < current else _empty
		else:
			_icons[i].visible = false


func _make_heart(filled: bool) -> Texture2D:
	var pixels: Array[PackedInt32Array] = [
		PackedInt32Array([0, 1, 1, 0, 1, 1, 0]),
		PackedInt32Array([1, 1, 1, 1, 1, 1, 1]),
		PackedInt32Array([1, 1, 1, 1, 1, 1, 1]),
		PackedInt32Array([1, 1, 1, 1, 1, 1, 1]),
		PackedInt32Array([0, 1, 1, 1, 1, 1, 0]),
		PackedInt32Array([0, 0, 1, 1, 1, 0, 0]),
		PackedInt32Array([0, 0, 0, 1, 0, 0, 0]),
	]
	var h: int = pixels.size()
	var w: int = pixels[0].size()
	var img := Image.create(w * HEART_SCALE, h * HEART_SCALE, false, Image.FORMAT_RGBA8)
	var fill := Color(0.86, 0.18, 0.28) if filled else Color(0.22, 0.16, 0.18, 0.85)
	var outline := Color(0.12, 0.05, 0.08)
	for y in h:
		for x in w:
			var on: bool = pixels[y][x] == 1
			var color := Color(0, 0, 0, 0)
			if on:
				color = fill
			elif filled and _is_outline(pixels, x, y):
				color = outline
			for py in HEART_SCALE:
				for px in HEART_SCALE:
					img.set_pixel(x * HEART_SCALE + px, y * HEART_SCALE + py, color)
	return ImageTexture.create_from_image(img)


func _is_outline(pixels: Array[PackedInt32Array], x: int, y: int) -> bool:
	if pixels[y][x] == 1:
		return false
	var h: int = pixels.size()
	var w: int = pixels[0].size()
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var nx: int = x + ox
			var ny: int = y + oy
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			if pixels[ny][nx] == 1:
				return true
	return false
