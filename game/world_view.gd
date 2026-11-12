class_name StackWorldView
extends Control
## Original pixel scenery and sprites; the model stays in cell coordinates.
var model: StackSimulation
var active := false
var clock := 0.0
var axis := 0.0
var field := Rect2()
var cell := 24.0
var controls := {}
var pressed_actions: Array[String] = []
var particles: Array[Dictionary] = []
var line_caption := ""
var caption_life := 0.0
var hero_idle: Texture2D = preload("res://art/hero_idle.png")
var hero_walk: Texture2D = preload("res://art/hero_walk.png")
var crate_textures: Array[Texture2D] = [preload("res://art/crate_copper.png"),
	preload("res://art/crate_teal.png"), preload("res://art/crate_violet.png")]
const INK := Color("172333")
const CREAM := Color("f4e3ba")
const GOLD := Color("d7a45a")
const MINT := Color("8dc6ac")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	if model == null:
		return
	var landscape := size.x > size.y
	var free_width := size.x - (202.0 if landscape else 36.0)
	var free_height := size.y - (84.0 if landscape else 204.0)
	cell = maxf(8.0, floorf(minf(free_width / model.tuning.columns,
		free_height / (model.tuning.rows + 2))))
	var world_size := Vector2(model.tuning.columns * cell, model.tuning.rows * cell)
	var top := 60.0 + cell * 1.1
	if not landscape:
		top += maxf(0.0, (free_height - (model.tuning.rows + 2) * cell) * 0.4)
	field = Rect2(Vector2(floorf((size.x - world_size.x) * 0.5), top), world_size)
	var button_size := Vector2(66, 64)
	if landscape:
		controls = {"left": Rect2(Vector2(12, size.y - 90), button_size),
			"right": Rect2(Vector2(84, size.y - 90), button_size),
			"jump": Rect2(Vector2(size.x - 82, size.y - 90), Vector2(70, 64))}
	else:
		controls = {"left": Rect2(Vector2(18, size.y - 92), button_size),
			"right": Rect2(Vector2(90, size.y - 92), button_size),
			"jump": Rect2(Vector2(size.x - 88, size.y - 92), Vector2(70, 64))}
	queue_redraw()


func animate(delta: float) -> void:
	clock += delta
	caption_life = maxf(0.0, caption_life - delta)
	for particle in particles:
		particle.life = float(particle.life) - delta
		particle.position += particle.velocity * delta
		particle.velocity.y += 7.0 * delta
	particles = particles.filter(func(p: Dictionary) -> bool: return float(p.life) > 0.0)
	queue_redraw()


func line_effect(chain: int) -> void:
	caption_life = 1.4
	line_caption = "+%d" % model.tuning.points_per_line if chain == 1 else "ЦЕПОЧКА · %d РЯДА" % chain
	for index in range(40):
		particles.append({"position": Vector2(float(index) / 40 * model.tuning.columns,
			model.tuning.rows - 0.5), "velocity": Vector2(sin(index * 7.1) * 2.5,
			-1.0 - fmod(index * 0.7, 3.0)), "life": 0.5 + fmod(index * 0.13, 0.5)})


func _draw() -> void:
	_draw_scenery()
	if model == null:
		return
	_draw_warehouse()
	if active:
		_draw_controls()
	if caption_life > 0.0 and active:
		var font := ThemeDB.fallback_font
		var text_size := 22
		var width := font.get_string_size(line_caption, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
		var at := Vector2(size.x * 0.5 - width * 0.5, field.position.y + field.size.y * 0.3)
		draw_string_outline(font, at, line_caption, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, 5, INK)
		draw_string(font, at, line_caption, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, CREAM)


func _draw_scenery() -> void:
	for band in range(20):
		var shade := Color("383850").lerp(Color("172c3a"), float(band) / 20)
		draw_rect(Rect2(0, size.y * band / 20, size.x, size.y / 20 + 1), shade)
	var moon := Vector2(size.x * 0.79, size.y * 0.16)
	for radius in [42, 34, 25]:
		draw_rect(Rect2(moon - Vector2(radius, radius), Vector2.ONE * radius * 2),
			Color(0.75, 0.66, 0.53, 0.035))
	draw_rect(Rect2(moon - Vector2(14, 14), Vector2(28, 28)), Color("c9c4a1"))
	draw_rect(Rect2(moon - Vector2(19, 8), Vector2(7, 17)), Color("c9c4a1"))
	for index in range(35):
		var point := Vector2(fmod(index * 113.3, maxf(1.0, size.x)),
			fmod(index * 71.7, maxf(1.0, size.y * 0.5)))
		draw_rect(Rect2(point, Vector2(2, 2)), Color(0.9, 0.78, 0.54, 0.25 + sin(clock + index) * 0.15))
	for layer in range(3):
		for index in range(18):
			var x := index * 60.0 - 20.0 + layer * 15
			var baseline := size.y * (0.55 + layer * 0.13)
			var height := 80.0 + fmod(index * 41.0 + layer * 13.0, 95)
			var color := Color("253746").lerp(Color("142b32"), layer * 0.35)
			draw_rect(Rect2(x + 19, baseline - height, 8, height + size.y), color)
			for tier in range(4):
				var span := 16 + tier * 9
				draw_rect(Rect2(x + 23 - span, baseline - height + tier * 20, span * 2, 22), color)
	for index in range(14):
		var x := fmod(index * 77.0 + sin(clock * 0.2 + index) * 8, maxf(size.x, 1.0))
		var y := size.y * 0.7 + sin(index * 3.4 + clock * 0.4) * 60
		draw_rect(Rect2(x, y, 3, 3), Color(0.8, 0.87, 0.55, 0.18 + 0.1 * sin(clock * 2 + index)))


func hero_frame() -> String:
	return "walk" if absf(axis) > 0.1 and int(clock * 9) % 2 == 0 and model.grounded else "idle"


func _draw_warehouse() -> void:
	var outer := field.grow(8)
	draw_rect(outer.grow(4), Color("10232b"))
	draw_rect(outer, Color("79534d"))
	draw_rect(Rect2(outer.position, Vector2(outer.size.x, 3)), GOLD)
	draw_rect(field, Color("182d39"))
	for column in range(model.tuning.columns):
		var shade := Color("1d3340") if column % 2 == 0 else Color("203644")
		draw_rect(Rect2(field.position + Vector2(column * cell, 0), Vector2(cell - 1, field.size.y)), shade)
	for row in range(model.tuning.rows):
		draw_line(field.position + Vector2(0, row * cell), field.position + Vector2(field.size.x, row * cell),
			Color(0.52, 0.6, 0.59, 0.055))
	var rail_y := field.position.y - cell * 1.15
	draw_rect(Rect2(field.position.x - 13, rail_y, field.size.x + 26, 5), Color("a17b58"))
	draw_rect(Rect2(field.position.x - 13, rail_y + 5, field.size.x + 26, 4), Color("463947"))
	for column in model.next_columns:
		var x := field.position.x + (column + 0.5) * cell
		draw_rect(Rect2(x - 8, rail_y - 4, 16, 12), Color("c49c61"))
		draw_rect(Rect2(x - 4, rail_y + 8, 8, 6), Color("62464a"))
		draw_line(Vector2(x, rail_y + 14), Vector2(x, field.position.y - 4), Color("b1a378"), 2)
		draw_rect(Rect2(x - 4, field.position.y - 6, 9, 3), Color("e5c878"))
	for side in [-1, 1]:
		var x := field.position.x - 11 if side == -1 else field.end.x + 7
		draw_rect(Rect2(x - 2, field.position.y + 12, 4, 24), Color("b9ac77"))
		draw_rect(Rect2(x - 5, field.position.y + 25, 10, 12), Color("edbf70"))
		draw_rect(Rect2(x - 8, field.position.y + 28, 16, 6), Color(0.97, 0.71, 0.34, 0.12))
	draw_set_transform(field.position, 0.0, Vector2.ONE * cell / 24.0)
	for crate in model.crates:
		var position := Vector2(roundf(float(crate.x) * 24), roundf(float(crate.y) * 24))
		if float(crate.y) < -1.0:
			continue
		var tint := Color.WHITE
		if model.state == "clearing" and model.clear_elapsed < model.tuning.clear_flash_time:
			if float(crate.y) > model.tuning.rows - 1.01:
				tint = Color(1.8, 1.6, 1.1, 1.0)
		draw_texture(crate_textures[int(crate.color) % 3], position, tint)
	var hero_position := Vector2(roundf(model.player.x * 24), roundf(model.player.y * 24))
	var texture := hero_walk if hero_frame() == "walk" else hero_idle
	var hero_rect := Rect2(hero_position, Vector2(14, 22))
	if model.facing < 0:
		# Negative width mirrors UVs inside the same canvas; it does not move its origin.
		# Keep the full 14 px canvas: the torso axis is x=7 in both animation frames.
		hero_rect.size.x = -14
	draw_texture_rect(texture, hero_rect, false)
	for particle in particles:
		draw_rect(Rect2(particle.position * 24, Vector2(2, 2)), Color(0.95, 0.76, 0.4, clampf(float(particle.life) * 2, 0, 1)))
	draw_set_transform(Vector2.ZERO)
	var floor_y := field.end.y
	draw_rect(Rect2(field.position.x - 8, floor_y, field.size.x + 16, 8), Color("bb8c5f"))
	draw_rect(Rect2(field.position.x - 8, floor_y + 8, field.size.x + 16, 6), Color("5d4550"))
	for tile in range(model.tuning.columns * 2):
		draw_rect(Rect2(field.position.x + tile * cell * 0.5, floor_y + 1, cell * 0.5 - 2, 2), Color("ebbe7e"))


func _draw_controls() -> void:
	for action in controls:
		var rect: Rect2 = controls[action]
		var down := pressed_actions.has(action)
		draw_rect(rect.grow(2), Color("bb9362") if down else Color("6a6f69"))
		draw_rect(rect, Color("405d60") if down else Color("243d4a"))
		draw_line(rect.position + Vector2(4, 3), rect.position + Vector2(rect.size.x - 4, 3),
			MINT if down else Color("617b7b"), 2)
		var center := rect.get_center()
		if action == "jump":
			_draw_arrow(center + Vector2(0, -4), Vector2.UP)
			draw_string(ThemeDB.fallback_font, rect.position + Vector2(9, 54), "ПРЫЖОК", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, CREAM)
		else:
			_draw_arrow(center, Vector2.LEFT if action == "left" else Vector2.RIGHT)


func _draw_arrow(center: Vector2, direction: Vector2) -> void:
	var normal := Vector2(-direction.y, direction.x)
	var points := PackedVector2Array([center + direction * 12,
		center - direction * 2 + normal * 10, center - direction * 2 + normal * 4,
		center - direction * 12 + normal * 4, center - direction * 12 - normal * 4,
		center - direction * 2 - normal * 4, center - direction * 2 - normal * 10])
	draw_colored_polygon(points, CREAM)
