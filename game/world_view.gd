class_name StackWorldView
extends Control
## Workshop presentation driven by the cell simulation.
var model: StackSimulation
var active := false
var clock := 0.0
var axis := 0.0
var field := Rect2()
var crane_rail := Rect2()
var cell := 24.0
var controls := {}
var pressed_actions: Array[String] = []
var line_caption := ""
var caption_life := 0.0
var hud_right := SCORE_PANEL_RIGHT
var crush_progress := -1.0
var boots_exhaust_life := 0.0
var helmet_impacts: Array[Dictionary] = []
var gloves_break_life := 0.0
var gloves_break_origin := Vector2.ZERO
var gloves_break_facing := 1
var _mallet_windup_age := -1.0
var _mallet_follow_age := -1.0
var _mallet_facing := 1
var _mallet_broke := false
var _mallet_impacts: Array[Dictionary] = []
var _layout_model_id := 0
var _reserve_grab_space := false
const FONT: Font = preload("res://art/workshop_font.fnt")
const HERO_SIZE := Vector2(16, 24)
const HERO_OFFSET := Vector2(-1, -2)
const HERO_FRAME_PIXELS := Vector2(32, 48)
const HERO_FRAME_COLUMNS := {"idle": 0, "walk": 1, "jump": 2, "push": 3, "grab": 4}
const HERO_BOOTS_ATLAS: Texture2D = preload("res://art/hero_rocket_boots.png")
const HERO_HELMET_ATLAS: Texture2D = preload("res://art/hero_helmet.png")
const HERO_GLOVES_ATLAS: Texture2D = preload("res://art/hero_work_gloves.png")
const HERO_MALLET_ATLAS: Texture2D = preload("res://art/hero_mallet.png")
const MALLET_TEXTURE: Texture2D = preload("res://art/wooden_mallet.png")
const MALLET_FRAGMENTS: Texture2D = preload("res://art/mallet_fragments.png")
const HERO_TEXTURES := {
	"idle": preload("res://art/hero_idle.png"), "walk": preload("res://art/hero_walk.png"),
	"jump": preload("res://art/hero_jump.png"), "push": preload("res://art/hero_push.png")}
const CRATE_TEXTURE: Texture2D = preload("res://art/crate_wood_variants.png")
const CRATE_TILE_SIZE := 48.0
const PIXELS_PER_CELL := 24.0
const CRANE_TRACK_Y := [-46.0, -34.0]
const CRANE_BODY := [Color("659a9a"), Color("da944f")]
const CRANE_LIGHT := [Color("a7c7bc"), Color("f6d18e")]
const CRANE_METAL := [Color("355762"), Color("785132")]
const CRANE_TOP := -52.0
const SCORE_PANEL_RIGHT := 138.0
const HUD_CLEARANCE_Y := 60.0
const LANDSCAPE_FRAME_CLEARANCE := 18.0
const WAREHOUSE_FRAME := 13.0
const GRAB_BUTTON_HEIGHT := 48.0
const GRAB_BUTTON_GAP := 8.0
const GRAB_ICONS: Texture2D = preload("res://art/glove_controls.png")
const GRAB_ICON_SIZE := Vector2(32, 32)
const INK := Color("102733")
const CREAM := Color("f4e3ba")
const GOLD := Color("d7a45a")
const CLEAR_GLOW_FRACTION := 0.30
const CLEAR_LIP_TIME := 0.08
const EFFECT_AMBER := Color("ffc276")
const EFFECT_DUST := Color("e9c598")
const BOOTS_EXHAUST_TIME := 0.20
const EXHAUST_FLAME := Color("ff803f")
const EXHAUST_CORE := Color("ffe6a0")
# The nozzle centers at the bottom of the jumping sprite in atlas pixels.
const JUMP_NOZZLES := [Vector2(7.5, 46), Vector2(21.5, 46)]
const HELMET_FLASH_TIME := 0.11
const HELMET_WOOD_TIME := 0.48
const HELMET_SHELL_TIME := 0.58
const HELMET_FRAGMENTS: Texture2D = preload("res://art/helmet_fragments.png")
const FRAGMENT_TILE := Vector2(20, 16)
const GLOVES_BREAK_TIME := 0.64
const GLOVE_FRAGMENTS: Texture2D = preload("res://art/glove_fragments.png")
const GLOVE_FRAGMENT_SIZE := Vector2(12, 8)
const MALLET_CONTACT_TIME := 0.055
const MALLET_RECOVERY_TIME := 0.19
const MALLET_DEBRIS_TIME := 0.54
const MALLET_GRIP := Vector2(16, 23)
# Horizontal flight, initial lift, and width in board pixels.
const WOOD_FLIGHT := [Vector3(-29, -21, 15), Vector3(30, -16, 14),
	Vector3(-42, -6, 6), Vector3(38, -2, 5), Vector3(14, -32, 6), Vector3(-11, -34, 4)]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	if model == null: return
	var model_id := model.get_instance_id()
	if _layout_model_id != model_id:
		_layout_model_id = model_id
		_reserve_grab_space = false
	var landscape := size.x > size.y
	var button_size := Vector2(66, 64)
	var jump_button: Rect2
	var left_limit := 0.0
	var right_limit := size.x
	var free_width := size.x - 36.0
	if landscape:
		var right_button := Rect2(Vector2(84, size.y - 90), button_size)
		jump_button = Rect2(Vector2(size.x - 82, size.y - 90), Vector2(70, 64))
		controls = {"left": Rect2(Vector2(12, size.y - 90), button_size),
			"right": right_button, "jump": jump_button}
		left_limit = right_button.end.x + LANDSCAPE_FRAME_CLEARANCE
		right_limit = jump_button.position.x - LANDSCAPE_FRAME_CLEARANCE
		free_width = right_limit - left_limit
	else:
		jump_button = Rect2(Vector2(size.x - 88, size.y - 92), Vector2(70, 64))
		controls = {"left": Rect2(Vector2(18, size.y - 92), button_size),
			"right": Rect2(Vector2(90, size.y - 92), button_size),
			"jump": jump_button}
	var grab_y := jump_button.position.y - GRAB_BUTTON_GAP - GRAB_BUTTON_HEIGHT
	var grab_button := Rect2(jump_button.position.x, grab_y, jump_button.size.x, GRAB_BUTTON_HEIGHT)
	if model.gloves_charges > 0:
		controls["grab"] = grab_button
		_reserve_grab_space = true
	elif model.mallet_charges > 0:
		controls["mallet"] = grab_button
		_reserve_grab_space = true
	var free_height := size.y - (84.0 if landscape else 204.0)
	cell = maxf(8.0, floorf(minf(free_width / model.tuning.columns, free_height / (model.tuning.rows + 2))))
	var field_bottom := INF
	var frame_clearance := WAREHOUSE_FRAME + 3.0
	var centered_right := floorf((size.x + model.tuning.columns * cell) * 0.5)
	if not landscape and _reserve_grab_space and centered_right + frame_clearance > grab_button.position.x:
		# Keep space for the hand action through the current game, even when the item breaks.
		field_bottom = grab_button.position.y - frame_clearance
		var rows_with_crane := model.tuning.rows - CRANE_TOP / PIXELS_PER_CELL
		cell = maxf(8.0, minf(cell, floorf((field_bottom - HUD_CLEARANCE_Y) / rows_with_crane)))
	var world_size := Vector2(model.tuning.columns * cell, model.tuning.rows * cell)
	var top := 60.0 + cell * 1.1
	if not landscape: top += maxf(0.0, (free_height - (model.tuning.rows + 2) * cell) * 0.4)
	top = minf(top, field_bottom - world_size.y)
	var left := floorf((size.x - world_size.x) * 0.5)
	if landscape:
		left = clampf(left, left_limit, maxf(left_limit, right_limit - world_size.x))
	var scale_to_view := cell / PIXELS_PER_CELL
	var rail_margin := clampf(10.0 * scale_to_view, 0.0, maxf(0.0, left - 3.0))
	# Keep the crane rail clear of the HUD on the narrower layouts.
	if left - rail_margin < hud_right:
		top = maxf(top, HUD_CLEARANCE_Y - CRANE_TOP * scale_to_view)
	field = Rect2(Vector2(left, top), world_size)
	crane_rail = Rect2(Vector2(left - rail_margin, top + CRANE_TOP * scale_to_view),
		Vector2(world_size.x + rail_margin * 2.0, (CRANE_TRACK_Y[1] + 6.0 - CRANE_TOP) * scale_to_view))
	queue_redraw()

func animate(delta: float) -> void:
	clock += delta
	caption_life = maxf(0.0, caption_life - delta)
	boots_exhaust_life = maxf(0.0, boots_exhaust_life - delta)
	gloves_break_life = maxf(0.0, gloves_break_life - delta)
	if _mallet_windup_age >= 0.0:
		_mallet_windup_age += delta
		if _mallet_windup_age > StackSimulation.MALLET_WINDUP_TIME + MALLET_RECOVERY_TIME:
			cancel_mallet_swing()
	if _mallet_follow_age >= 0.0:
		_mallet_follow_age += delta
		if _mallet_follow_age >= MALLET_RECOVERY_TIME:
			_mallet_follow_age = -1.0
	for index in range(_mallet_impacts.size() - 1, -1, -1):
		_mallet_impacts[index].age += delta
		if _mallet_impacts[index].age >= MALLET_DEBRIS_TIME:
			_mallet_impacts.remove_at(index)
	for index in range(helmet_impacts.size() - 1, -1, -1):
		var impact := helmet_impacts[index]
		impact.age += delta
		if impact.age >= (HELMET_SHELL_TIME if impact.broke else HELMET_WOOD_TIME):
			helmet_impacts.remove_at(index)
	queue_redraw()

func boots_jump_effect() -> void:
	boots_exhaust_life = BOOTS_EXHAUST_TIME

func gloves_break(event: Dictionary) -> void:
	gloves_break_life = GLOVES_BREAK_TIME
	gloves_break_facing = int(event.facing)
	gloves_break_origin = _crate_origin(float(event.player_x) + model.tuning.player_width * 0.5,
		float(event.player_y) + model.tuning.player_height)

func mallet_swing(event: Dictionary) -> void:
	_mallet_windup_age = 0.0
	_mallet_follow_age = -1.0
	_mallet_facing = int(event.facing)
	_mallet_broke = false

func mallet_miss() -> void:
	_mallet_windup_age = -1.0
	_mallet_follow_age = 0.0

func mallet_hit(event: Dictionary) -> void:
	mallet_miss()
	_mallet_broke = bool(event.mallet_broke)
	var crate := _crate_origin(float(event.x), float(event.y))
	var center := crate + Vector2(12, 12)
	var player := _crate_origin(float(event.player_x), float(event.player_y))
	var contact := crate + Vector2(1.0 if _mallet_facing > 0 else PIXELS_PER_CELL - 1.0,
		clampf(player.y + 14.0 - crate.y, 3.0, PIXELS_PER_CELL - 3.0))
	_mallet_impacts.append({"age": 0.0, "crate": center, "contact": contact,
		"facing": _mallet_facing, "broke": _mallet_broke})

func cancel_mallet_swing() -> void:
	_mallet_windup_age = -1.0

func reset_mallet_effects() -> void:
	cancel_mallet_swing()
	_mallet_follow_age = -1.0
	_mallet_broke = false
	_mallet_impacts.clear()

func mallet_animation_phase() -> String:
	if _mallet_windup_age >= 0.0:
		return "windup"
	if _mallet_follow_age >= 0.0:
		return "strike" if _mallet_follow_age < MALLET_CONTACT_TIME else "recovery"
	return "none"

func helmet_hit(event: Dictionary) -> void:
	var crate := _crate_origin(float(event.x), float(event.y))
	var player := _crate_origin(float(event.player_x), float(event.player_y))
	var head := player + HERO_OFFSET + Vector2(HERO_SIZE.x * 0.5, 1.0)
	var contact := Vector2(clampf(head.x, crate.x + 1.0, crate.x + PIXELS_PER_CELL - 1.0), head.y)
	helmet_impacts.append({"age": 0.0, "crate": crate + Vector2(12, 13),
		"head": head, "contact": contact,
		"jump": event.direction == "jump", "broke": bool(event.helmet_broke),
		"facing_left": model.facing < 0})

func line_effect(chain: int) -> void:
	caption_life = 1.4
	line_caption = "+%d" % model.tuning.points_per_line if chain == 1 else "ЦЕПОЧКА · %d РЯДА" % chain

func clear_animation_phase() -> String:
	if model == null or model.state != "clearing":
		return "none"
	if model.clear_elapsed >= model.tuning.clear_flash_time:
		return "collapse"
	if model.clear_elapsed < model.tuning.clear_flash_time * CLEAR_GLOW_FRACTION:
		return "glow"
	return "retreat"

func _draw() -> void:
	_draw_scenery()
	if model == null: return
	_draw_warehouse()
	if active: _draw_controls()
	if caption_life > 0.0 and active and model.state != "over" and not model.equipment_pending:
		var width := FONT.get_string_size(line_caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		var at := Vector2(size.x * 0.5 - width * 0.5, field.position.y + field.size.y * 0.3)
		draw_string_outline(FONT, at, line_caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 3, INK)
		draw_string(FONT, at, line_caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, CREAM)

func _draw_scenery() -> void:
	for band in range(24):
		draw_rect(Rect2(0, size.y * band / 24, size.x, size.y / 24 + 1), Color("233747").lerp(Color("102b38"), float(band) / 24))
	# Distant factory bays, amber windows and diagonal steel trusses replace the forest.
	for layer in range(2):
		for index in range(int(size.x / 74) + 2):
			var x := index * 74.0 - 18 + layer * 31
			var y := size.y * (0.18 + layer * 0.24) + fmod(index * 43.0, 83.0)
			var steel := Color("203240") if layer == 0 else Color("172e3a")
			draw_rect(Rect2(x, y, 58, size.y), steel)
			draw_rect(Rect2(x - 5, y + 17, 67, 6), Color("142b37"))
			draw_line(Vector2(x, y + 20), Vector2(x + 56, y + 67), Color("1b303d"), 6)
			for window in range(3):
				draw_rect(Rect2(x + 10 + window * 10, y + 9, 6, 12), Color(0.72, 0.40, 0.18, 0.22 if index % 3 == 0 else 0.05))
	for side in [-1, 1]:
		var gx := size.x * (0.12 if side == -1 else 0.88)
		var gy := size.y * 0.32
		for tooth in range(12):
			var angle := tooth * TAU / 12
			draw_line(Vector2(gx, gy) + Vector2.from_angle(angle) * 24, Vector2(gx, gy) + Vector2.from_angle(angle) * 33, Color("294450"), 7)
		draw_circle(Vector2(gx, gy), 25, Color("294450"))
		draw_circle(Vector2(gx, gy), 15, Color("1b3441"))
		draw_circle(Vector2(gx, gy), 4, Color("294450"))
	var lx := size.x * 0.5
	var ly := minf(57, crane_rail.position.y - 24)
	var beam := PackedVector2Array([Vector2(lx-17,ly+13),Vector2(lx+17,ly+13),Vector2(lx+61,ly+104),Vector2(lx-61,ly+104)])
	draw_colored_polygon(beam, Color(0.96,0.69,0.31,0.11))
	for glow in [28,20,13]: draw_circle(Vector2(lx,ly+13),glow,Color(1.0,0.69,0.29,0.045))
	draw_line(Vector2(lx,0),Vector2(lx,ly-13),Color("0b202b"),3)
	draw_rect(Rect2(lx-6,ly-14,12,10),Color("10232c"))
	draw_colored_polygon(PackedVector2Array([Vector2(lx-8,ly-7),Vector2(lx+8,ly-7),Vector2(lx+21,ly+11),Vector2(lx-21,ly+11)]),Color("0b1f29"))
	draw_line(Vector2(lx-20,ly+11),Vector2(lx+20,ly+11),GOLD,2)
	draw_circle(Vector2(lx,ly+12),6,Color("f9c56f"))
	draw_circle(Vector2(lx,ly+12),4,Color("fff0be"))
	for index in range(5):
		var wx := 22.0 + index * maxf(70, size.x / 5)
		var wy := size.y * 0.74 + fmod(index * 21.0, 38)
		draw_rect(Rect2(wx-3,wy-3,31,22),Color("142a35"))
		for pane in range(3): draw_rect(Rect2(wx+pane*9,wy,5,13),Color(0.80,0.46,0.20,0.17))
	for index in range(9):
		var point := Vector2(lx + sin(index*7.3+clock*0.18)*48, ly + 35 + fmod(index*13.0 + clock*5, 65))
		draw_rect(Rect2(point,Vector2.ONE),Color(0.97,0.74,0.4,0.17))
	# A restrained workbench stays scenery, with no new UI or interaction.
	var bench := size.y - 15
	draw_rect(Rect2(0,bench,size.x,15),Color("49362c"))
	draw_rect(Rect2(0,bench,size.x,3),Color("ae7442"))
	draw_line(Vector2(0,bench+6),Vector2(size.x,bench+6),Color("70482e"),2)
	var blueprint := Vector2(size.x*0.56-46,bench-24)
	draw_rect(Rect2(blueprint,Vector2(92,27)),Color("213f53"))
	draw_rect(Rect2(blueprint+Vector2(2,2),Vector2(88,23)),Color("6f94a0"),false,1)
	draw_circle(blueprint+Vector2(37,13),7,Color("afbea7"),false,1)
	draw_line(blueprint+Vector2(12,20),blueprint+Vector2(75,20),Color("a6b79f"),1)
	draw_line(blueprint+Vector2(37,4),blueprint+Vector2(37,22),Color("a6b79f"),1)
	draw_rect(Rect2(15,bench-16,13,16),Color("715347"))
	draw_rect(Rect2(17,bench-14,7,12),Color("a28266"))
	draw_rect(Rect2(28,bench-12,5,8),Color("715347"),false,2)
	var key_at := Vector2(size.x*0.72,bench-4)
	draw_line(key_at,key_at+Vector2(20,-9),Color("172e39"),7)
	draw_line(key_at,key_at+Vector2(20,-9),Color("8c9b95"),4)
	draw_line(key_at+Vector2(18,-10),key_at+Vector2(23,-16),Color("b6c2ae"),3)
	draw_line(key_at+Vector2(20,-8),key_at+Vector2(27,-10),Color("b6c2ae"),3)

func hero_frame() -> String:
	if model.grabbed_crate_id >= 0 or model.is_pulling(): return "grab"
	if not model.grounded: return "jump"
	if absf(axis) > 0.1:
		for crate in model.crates:
			var gap := float(crate.x) - model.player.x - model.tuning.player_width if axis > 0 else model.player.x - float(crate.x) - 1
			if absf(gap) < 0.09 and model.player.y + model.tuning.player_height > float(crate.y) + 0.15 and model.player.y < float(crate.y) + 0.85:
				return "push"
		if int(clock * 9) % 2 == 0: return "walk"
	return "idle"

func _bolt(at: Vector2) -> void:
	draw_rect(Rect2(at-Vector2(2,2),Vector2(5,5)),Color("253b43"))
	draw_rect(Rect2(at-Vector2.ONE,Vector2(3,3)),Color("c9c5ad"))
	draw_rect(Rect2(at,Vector2.ONE),Color("697b7d"))

func _bracket(at: Vector2, flip: Vector2) -> void:
	draw_set_transform(at,0,flip)
	draw_colored_polygon(PackedVector2Array([Vector2(0,19),Vector2(0,0),Vector2(19,0),Vector2(19,6),Vector2(6,6),Vector2(6,19)]),Color("172d36"))
	draw_colored_polygon(PackedVector2Array([Vector2(1,18),Vector2(1,1),Vector2(18,1),Vector2(18,5),Vector2(5,5),Vector2(5,18)]),Color("7f8c8b"))
	draw_line(Vector2(2,17),Vector2(2,2),Color("b7bfad"),1)
	draw_line(Vector2(2,2),Vector2(17,2),Color("d4c9ad"),1)
	_bolt(Vector2(4,4));_bolt(Vector2(14,3));_bolt(Vector2(3,14))
	draw_set_transform(Vector2.ZERO)

func _crate_origin(column: float, row: float) -> Vector2:
	return (Vector2(column, row) * PIXELS_PER_CELL).round()

func _crane_cargo_origin(crane: Dictionary) -> Vector2:
	return _crate_origin(float(crane.x) - 0.5, StackSimulation.CRATE_RELEASE_Y)

func crane_cargo_rect(index: int) -> Rect2:
	var origin := _crane_cargo_origin(model.cranes[index])
	return Rect2(field.position + origin * cell / PIXELS_PER_CELL, Vector2.ONE * cell)

func _crane_center(cargo: Vector2, index: int) -> Vector2:
	return Vector2(cargo.x + PIXELS_PER_CELL * 0.5, CRANE_TRACK_Y[index])

func crane_trolley_center(index: int) -> Vector2:
	return field.position + _crane_center(_crane_cargo_origin(model.cranes[index]), index) * cell / PIXELS_PER_CELL

func _draw_cranes() -> void:
	var span := Rect2((crane_rail.position - field.position) * PIXELS_PER_CELL / cell,
		Vector2(crane_rail.size.x * PIXELS_PER_CELL / cell, 2.0 - CRANE_TOP))
	for index in range(CRANE_TRACK_Y.size()):
		_draw_crane_track(span, index)
		var crane := model.cranes[index]
		if not bool(crane.waiting):
			_draw_crane(span, crane, index)
	_draw_crane_end_stops(span)

func _draw_crane_track(span: Rect2, index: int) -> void:
	var y: float = CRANE_TRACK_Y[index]
	var body: Color = CRANE_BODY[index]
	draw_rect(Rect2(span.position.x, y - 4.0, span.size.x, 9.0), INK)
	draw_rect(Rect2(span.position.x, y - 3.0, span.size.x, 6.0), CRANE_METAL[index])
	draw_rect(Rect2(span.position.x, y - 3.0, span.size.x, 1.0), body.darkened(0.25))
	for x in range(5, int(model.tuning.columns * PIXELS_PER_CELL), 36):
		draw_rect(Rect2(x - 1, y - 1.0, 3.0, 3.0), INK)
		draw_rect(Rect2(x, y - 1.0, 1.0, 1.0), CRANE_LIGHT[index])

func _draw_crane_end_stops(span: Rect2) -> void:
	var width := minf(7.0, -span.position.x)
	if width < 2.0:
		return
	for x in [span.position.x, span.end.x - width]:
		draw_rect(Rect2(x, span.position.y, width, span.size.y), INK)
		draw_rect(Rect2(x + 1.0, span.position.y + 1.0, width - 2.0, span.size.y - 3.0), Color("304d57"))
		draw_rect(Rect2(x + 1.0, span.position.y + 1.0, 1.0, span.size.y - 3.0), Color("637d7d"))
		for y in CRANE_TRACK_Y:
			draw_rect(Rect2(x + 1.0, y - 2.0, width - 1.0, 4.0), Color("52696a"))
			draw_rect(Rect2(x + 2.0, y - 1.0, 1.0, 2.0), Color("aaa78c"))

func _draw_crane_rect(bounds: Rect2, span: Rect2, color: Color) -> void:
	var visible := bounds.intersection(span)
	if visible.has_area():
		draw_rect(visible, color)

func _crate_source(variant: int) -> Rect2:
	return Rect2(variant * CRATE_TILE_SIZE, 0, CRATE_TILE_SIZE, CRATE_TILE_SIZE)

func _draw_crate(bounds: Rect2, variant: int, tint: Color = Color.WHITE) -> void:
	draw_texture_rect_region(CRATE_TEXTURE, bounds, _crate_source(variant), tint)

func _draw_crane_crate(position: Vector2, span: Rect2, variant: int) -> void:
	var bounds := Rect2(position, Vector2.ONE * PIXELS_PER_CELL)
	var visible := bounds.intersection(span)
	if visible == bounds:
		_draw_crate(bounds, variant)
	elif visible.has_area():
		var texture_scale := CRATE_TILE_SIZE / PIXELS_PER_CELL
		var source := _crate_source(variant)
		source.position += (visible.position - bounds.position) * texture_scale
		source.size = visible.size * texture_scale
		draw_texture_rect_region(CRATE_TEXTURE, visible, source)

func _draw_crane(span: Rect2, crane: Dictionary, index: int) -> void:
	var cargo := _crane_cargo_origin(crane)
	var center := _crane_center(cargo, index)
	var jaw_y := cargo.y - 2.0
	var body: Color = CRANE_BODY[index]
	var light: Color = CRANE_LIGHT[index]
	var metal: Color = CRANE_METAL[index]
	# The rear hoist reaches down behind the lower rail. Both jaws grip at the release height.
	_draw_crane_rect(Rect2(center.x - 3.0, center.y + 2.0, 6.0, jaw_y - center.y), span, INK)
	_draw_crane_rect(Rect2(center.x - 2.0, center.y + 3.0, 4.0, jaw_y - center.y - 2.0), span, metal)
	_draw_crane_rect(Rect2(center.x - 1.0, center.y + 3.0, 1.0, jaw_y - center.y - 2.0), span, light)
	_draw_crane_rect(Rect2(center.x - 10.0, center.y - 5.0, 20.0, 11.0), span, INK)
	_draw_crane_rect(Rect2(center.x - 9.0, center.y - 4.0, 18.0, 9.0), span, metal)
	_draw_crane_rect(Rect2(center.x - 8.0, center.y - 4.0, 16.0, 7.0), span, body)
	_draw_crane_rect(Rect2(center.x - 7.0, center.y - 4.0, 14.0, 1.0), span, light)
	for side in [-7.0, 5.0]:
		_draw_crane_rect(Rect2(center.x + side, center.y - 1.0, 2.0, 2.0), span, metal)

	if bool(crane.loaded):
		_draw_crane_crate(cargo, span, int(crane.variant))
	var cue := float(crane.open_time)
	var spread := 0.0
	if cue > 0.0:
		var duration := model.tuning.crane_open_time
		var opening := 0.55 + (duration - cue) / (duration * 0.25)
		var closing := cue / (duration * 0.35)
		spread = roundf(7.0 * clampf(minf(opening, closing), 0.0, 1.0))
	_draw_crane_rect(Rect2(center.x - 6.0, jaw_y - 2.0, 12.0, 5.0), span, INK)
	_draw_crane_rect(Rect2(center.x - 5.0, jaw_y - 2.0, 10.0, 3.0), span, body)
	_draw_crane_rect(Rect2(center.x - 2.0, jaw_y - 2.0, 4.0, 1.0), span, light)
	for side: float in [-1.0, 1.0]:
		_draw_crane_jaw(span, Vector2(center.x, jaw_y), side, spread, body, light)

func _draw_crane_jaw(span: Rect2, joint: Vector2, side: float, spread: float, body: Color, light: Color) -> void:
	var shoulder := joint.x + 5.0 * side
	var wrist := joint.x + (9.0 + roundf(spread * 0.6)) * side
	var hinge := joint.x + (12.0 + spread) * side
	var rise := roundf(spread * 0.33)
	var palm := Rect2(minf(shoulder, wrist) - 1.0, joint.y, absf(wrist - shoulder) + 3.0, 4.0)
	var arm := Rect2(minf(wrist, hinge) - 1.0, joint.y + 2.0, absf(hinge - wrist) + 3.0, 5.0)
	var finger := Rect2(hinge - 2.0, joint.y + 4.0, 5.0, 7.0 - rise)
	var toe := Rect2(hinge - (4.0 if side > 0.0 else 1.0), joint.y + 8.0 - rise, 5.0, 3.0)
	for part: Rect2 in [palm, arm, finger, toe]:
		_draw_crane_rect(part, span, INK)
	for part: Rect2 in [palm, arm, finger, toe]:
		_draw_crane_rect(part.grow(-1.0), span, body)
	_draw_crane_rect(Rect2(wrist, joint.y + 3.0, 1.0, 1.0), span, light)

func _draw_clearing_row(width: float, floor_y: float, phase: String) -> void:
	var row := Rect2(0.0, floor_y - PIXELS_PER_CELL, width, PIXELS_PER_CELL)
	var progress := model.clear_elapsed / model.tuning.clear_flash_time
	var retreat := inverse_lerp(CLEAR_GLOW_FRACTION, 1.0, progress) if phase == "retreat" else 0.0
	var depth: float = smoothstep(0.0, 1.0, retreat)
	var openness: float = smoothstep(0.0, 0.30, retreat)
	var glow: float = smoothstep(-0.04, 0.13, progress) * (1.0 - smoothstep(0.0, 0.24, retreat))
	var shadow: float = smoothstep(0.0, 0.82, retreat)
	var tint := Color(1.0 + 0.25 * glow, 1.0 + 0.12 * glow, 1.0 - 0.10 * glow)
	tint = tint.lerp(Color("62574b"), shadow)
	tint.a = 1.0 - smoothstep(0.62, 1.0, retreat)
	_draw_receiving_slot(row, openness)
	var width_scale := lerpf(1.0, 0.84, depth)
	var height := roundf(lerpf(PIXELS_PER_CELL, 12.0, depth))
	for crate in model.crates:
		if not model.is_clearing_crate(int(crate.id)):
			continue
		var x := _crate_origin(float(crate.x), float(crate.y)).x
		var left := roundf(lerpf(width * 0.5, x, width_scale))
		var right := roundf(lerpf(width * 0.5, x + PIXELS_PER_CELL, width_scale))
		_draw_crate(Rect2(left, floor_y - height, right - left, height), int(crate.variant), tint)
	_draw_receiving_lip(row, openness)
	if glow > 0.0:
		draw_rect(row.grow(1.0), Color(EFFECT_AMBER, glow * 0.28), false, 3.0)
		draw_rect(row.grow(-0.5), Color(EFFECT_AMBER, glow), false, 1.0)

func _draw_receiving_slot(row: Rect2, openness: float) -> void:
	if openness <= 0.0:
		return
	draw_rect(row, Color(Color("253b43"), openness))
	var inner := row.grow(-2.0)
	draw_rect(inner, Color(Color("0b202b"), openness))
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, 1.0)), Color(Color("536b6d"), openness))
	for side: float in [-1.0, 1.0]:
		var rim_x := inner.get_center().x + inner.size.x * 0.5 * side
		var back_x := rim_x - 9.0 * side
		var points := PackedVector2Array([Vector2(rim_x, inner.position.y + 1.0),
			Vector2(back_x, inner.position.y + 6.0), Vector2(back_x, inner.end.y),
			Vector2(rim_x, inner.end.y)])
		draw_colored_polygon(points, Color(Color("192f39"), openness))

func _draw_receiving_lip(row: Rect2, openness: float) -> void:
	if openness <= 0.0:
		return
	var lip_y := row.end.y - 4.0
	draw_rect(Rect2(0.0, lip_y, row.size.x, 4.0), Color(Color("192f39"), openness))
	draw_rect(Rect2(1.0, lip_y + 1.0, row.size.x - 2.0, 1.0), Color(Color("627874"), openness))

func _draw_clear_dust(width: float, floor_y: float, elapsed: float) -> void:
	var collapse_time := model.tuning.collapse_time
	var progress := clampf(elapsed / collapse_time, 0.0, 1.0)
	var opacity: float = smoothstep(0.35, 0.54, progress) * (1.0 - smoothstep(0.75, 1.0, progress))
	if opacity <= 0.0:
		return
	for fraction: float in [0.12, 0.28]:
		var x := roundf(width * fraction)
		var rise := roundf(progress * 6.0)
		draw_rect(Rect2(x, floor_y - 2.0 - rise, 2.0, 2.0), Color(EFFECT_DUST, opacity * 0.90))
		draw_rect(Rect2(x + 4.0, floor_y - rise, 1.0, 1.0), Color(EFFECT_DUST, opacity * 0.69))

func _hero_bounds() -> Rect2:
	var at := Vector2(roundf(model.player.x * PIXELS_PER_CELL), roundf(model.player.y * PIXELS_PER_CELL))
	return Rect2(at + HERO_OFFSET, HERO_SIZE)

func _draw_hero(bounds: Rect2, frame: String) -> void:
	if model.facing < 0:
		bounds.size.x = -bounds.size.x
	var boots := model.boots_equipped
	var helmet := model.helmet_charges > 0
	var gloves := model.gloves_charges > 0
	var atlas := _hero_atlas(boots, helmet, gloves)
	if atlas != null:
		draw_texture_rect_region(atlas, bounds, _hero_region(frame, boots, helmet, gloves))
	else:
		draw_texture_rect(HERO_TEXTURES[frame], bounds, false)

func _draw_mallet_hero(bounds: Rect2, frame: String) -> void:
	var phase := mallet_animation_phase()
	var carrying := model.mallet_charges > 0
	if phase == "none" and not carrying:
		_draw_hero(bounds, frame)
		return
	var facing := model.facing if phase == "none" else _mallet_facing
	var hand := Vector2(24.5, 36.5)
	if frame == "push":
		hand = Vector2(27.5, 35.5)
	var angle := 0.34
	var column := -1
	if phase == "windup":
		var progress := _mallet_windup_age / StackSimulation.MALLET_WINDUP_TIME
		column = 0
		hand = Vector2(28, 19)
		angle = lerpf(-0.82, 0.72, smoothstep(0.50, 1.0, progress))
	elif phase == "strike" or phase == "recovery":
		column = 1
		hand = Vector2(29, 33.5)
		angle = lerpf(1.44, 0.34, smoothstep(MALLET_CONTACT_TIME, MALLET_RECOVERY_TIME, _mallet_follow_age))
	if carrying or (phase == "strike" and _mallet_broke):
		if facing < 0:
			hand.x = HERO_FRAME_PIXELS.x - hand.x
		var grip := (bounds.position + hand / HERO_FRAME_PIXELS * bounds.size).round()
		var board := Transform2D(0.0, Vector2.ONE * cell / PIXELS_PER_CELL, 0.0, field.position)
		var motion := Transform2D(angle * facing, Vector2(0.66 * facing, 0.66), 0.0, grip)
		draw_set_transform_matrix(board * motion)
		draw_texture(MALLET_TEXTURE, -MALLET_GRIP)
		draw_set_transform_matrix(board)
	if column < 0:
		_draw_hero(bounds, frame)
	else:
		var row := int(model.boots_equipped) + 2 * int(model.helmet_charges > 0)
		bounds.size.x *= facing
		var source := Rect2(Vector2(column, row) * HERO_FRAME_PIXELS, HERO_FRAME_PIXELS)
		draw_texture_rect_region(HERO_MALLET_ATLAS, bounds, source)

static func pause_portrait(boots_equipped: bool, helmet_equipped: bool = false,
		gloves_equipped: bool = false) -> Texture2D:
	var atlas := _hero_atlas(boots_equipped, helmet_equipped, gloves_equipped)
	if atlas == null:
		return HERO_TEXTURES.idle
	var portrait := AtlasTexture.new()
	portrait.atlas = atlas
	portrait.region = _hero_region("idle", boots_equipped, helmet_equipped, gloves_equipped)
	portrait.filter_clip = true
	return portrait

static func _hero_atlas(boots_equipped: bool, helmet_equipped: bool, gloves_equipped: bool) -> Texture2D:
	if gloves_equipped:
		return HERO_GLOVES_ATLAS
	if helmet_equipped:
		return HERO_HELMET_ATLAS
	return HERO_BOOTS_ATLAS if boots_equipped else null

static func _hero_region(frame: String, boots_equipped: bool, helmet_equipped: bool,
		gloves_equipped: bool) -> Rect2:
	var column: int = HERO_FRAME_COLUMNS[frame]
	var row := 1 if boots_equipped and helmet_equipped else 0
	if gloves_equipped:
		row = int(boots_equipped) + 2 * int(helmet_equipped)
	return Rect2(Vector2(column, row) * HERO_FRAME_PIXELS, HERO_FRAME_PIXELS)

func _draw_glove_fragments(width: float, floor_y: float) -> void:
	if gloves_break_life <= 0.0:
		return
	var progress := 1.0 - gloves_break_life / GLOVES_BREAK_TIME
	var travel: float = smoothstep(0.0, 0.42, progress)
	var opacity: float = 1.0 - smoothstep(0.58, 1.0, progress)
	var floor_contact := minf(gloves_break_origin.y, floor_y)
	for index in range(3):
		var direction := float(index - 1) * gloves_break_facing
		var x := gloves_break_origin.x + direction * lerpf(4.0, 13.0, travel)
		var hop := roundf(sin(travel * PI) * (4.0 + index))
		var piece_size := Vector2(8, 5) if index < 2 else Vector2(6, 4)
		var at := Vector2(clampf(roundf(x - piece_size.x * 0.5), 0.0, width - piece_size.x),
			floor_contact - piece_size.y - hop)
		var source := Rect2(index * GLOVE_FRAGMENT_SIZE.x, 0, GLOVE_FRAGMENT_SIZE.x, GLOVE_FRAGMENT_SIZE.y)
		draw_texture_rect_region(GLOVE_FRAGMENTS, Rect2(at, piece_size), source, Color(Color.WHITE, opacity))

func _draw_helmet_impacts(width: float, floor_y: float) -> void:
	for impact in helmet_impacts:
		var age := float(impact.age)
		if age < HELMET_WOOD_TIME:
			_draw_wood_fragments(impact.crate, age, bool(impact.jump), width, floor_y)
		if bool(impact.broke):
			_draw_helmet_shell(impact.head, age, bool(impact.facing_left), width, floor_y)
		if age < HELMET_FLASH_TIME:
			_draw_helmet_flash(impact.contact, age, width)

func _draw_mallet_impacts(width: float, floor_y: float) -> void:
	for impact in _mallet_impacts:
		var age := float(impact.age)
		var facing := int(impact.facing)
		var contact: Vector2 = impact.contact
		if age < HELMET_WOOD_TIME:
			_draw_wood_fragments(impact.crate, age, false, width, floor_y)
		if age < MALLET_CONTACT_TIME * 1.7:
			var opacity: float = 1.0 - smoothstep(0.02, MALLET_CONTACT_TIME * 1.7, age)
			var flash := PackedVector2Array([Vector2(-4, 0), Vector2(2, -2), Vector2(5, -7),
				Vector2(6, -2), Vector2(11, -3), Vector2(7, 1), Vector2(9, 4),
				Vector2(4, 3), Vector2(5, 7), Vector2(1, 3)])
			for index in range(flash.size()):
				flash[index] = contact + Vector2(flash[index].x * facing, flash[index].y)
			draw_colored_polygon(flash, Color(EFFECT_AMBER, opacity))
			draw_rect(Rect2(contact - Vector2(1, 1), Vector2(3, 3)), Color(CREAM, opacity))
		if impact.broke and age >= MALLET_CONTACT_TIME:
			_draw_mallet_fragments(contact, facing, age - MALLET_CONTACT_TIME, width, floor_y)

func _draw_mallet_fragments(contact: Vector2, facing: int, age: float, width: float, floor_y: float) -> void:
	var progress := age / (MALLET_DEBRIS_TIME - MALLET_CONTACT_TIME)
	var opacity: float = 1.0 - smoothstep(0.64, 1.0, progress)
	for index in range(3):
		var drift := float([-11, 27, -23][index]) * facing
		var lift := float([16, 24, 10][index])
		var at := contact + Vector2(drift * progress, 64.0 * progress * progress - lift * progress)
		var piece := Vector2(13.0, 10.0) if index < 2 else Vector2(10.0, 8.0)
		var corner := (at - piece * 0.5).round().clamp(Vector2(0, -PIXELS_PER_CELL),
			Vector2(width, floor_y) - piece)
		var source := Rect2(index * 20.0, 0.0, 20.0, 16.0)
		piece.x *= facing
		draw_texture_rect_region(MALLET_FRAGMENTS, Rect2(corner, piece), source, Color(Color.WHITE, opacity))

func _draw_wood_fragments(origin: Vector2, age: float, jumped: bool, width: float, floor_y: float) -> void:
	var progress := age / HELMET_WOOD_TIME
	var travel := 1.0 - (1.0 - progress) * (1.0 - progress)
	var opacity: float = smoothstep(0.015, 0.045, age) * (1.0 - smoothstep(0.64, 1.0, progress))
	var lift := 5.0 if jumped else 0.0
	for index in range(WOOD_FLIGHT.size()):
		var flight: Vector3 = WOOD_FLIGHT[index]
		var offset := Vector2(flight.x * (0.12 + travel),
			(flight.y - lift) * travel + 43.0 * progress * progress)
		_draw_helmet_fragment(origin + offset, flight.z, index % 4, 0, opacity, false, width, floor_y)

func _draw_helmet_shell(head: Vector2, age: float, facing_left: bool, width: float, floor_y: float) -> void:
	var progress := age / HELMET_SHELL_TIME
	var opacity: float = smoothstep(0.025, 0.062, age) * (1.0 - smoothstep(0.69, 1.0, progress))
	for index in range(2):
		var side := -1.0 if index == 0 else 1.0
		var drift := 29.0 * progress - 11.0 * progress * progress
		var fall := 63.0 * progress * progress - 42.0 * progress
		var at := head + Vector2(side * (4.0 + drift), fall - 4.0 - index * 2.0)
		_draw_helmet_fragment(at, 12.0, 1 - index if facing_left else index, 1,
			opacity, facing_left, width, floor_y)

func _draw_helmet_fragment(at: Vector2, piece_width: float, column: int, row: int,
		opacity: float, flip: bool, width: float, floor_y: float) -> void:
	var piece_size := Vector2(piece_width, roundf(piece_width * FRAGMENT_TILE.y / FRAGMENT_TILE.x))
	var corner := (at - piece_size * 0.5).round().clamp(
		Vector2(0, -PIXELS_PER_CELL), Vector2(width, floor_y) - piece_size)
	var source := Rect2(Vector2(column, row) * FRAGMENT_TILE, FRAGMENT_TILE)
	if flip:
		piece_size.x = -piece_size.x
	draw_texture_rect_region(HELMET_FRAGMENTS, Rect2(corner, piece_size), source, Color(Color.WHITE, opacity))

func _draw_helmet_flash(contact: Vector2, age: float, width: float) -> void:
	var progress := age / HELMET_FLASH_TIME
	var alpha: float = 1.0 - smoothstep(0.40, 1.0, progress)
	var at := Vector2(clampf(contact.x, 16.0, width - 16.0), contact.y - 2.0)
	var rays := PackedVector2Array([Vector2(-16, -2), Vector2(-6, -4), Vector2(-10, -11),
		Vector2(-2, -6), Vector2(0, -14), Vector2(3, -6), Vector2(10, -11),
		Vector2(7, -4), Vector2(16, -2), Vector2(7, 0), Vector2(9, 3),
		Vector2(0, 1), Vector2(-9, 3), Vector2(-7, 0)])
	for index in range(rays.size()):
		rays[index] = at + (rays[index] * lerpf(0.88, 1.08, progress)).round()
	draw_colored_polygon(rays, Color(Color("e88a37"), alpha))
	draw_colored_polygon(PackedVector2Array([at + Vector2(-10, -2), at + Vector2(-2, -4),
		at + Vector2(0, -10), at + Vector2(2, -4), at + Vector2(10, -2),
		at + Vector2(0, 0)]), Color(Color("ffe7a1"), alpha))

func _draw_boots_exhaust(bounds: Rect2, floor_y: float) -> void:
	if boots_exhaust_life <= 0.0 or model.grounded or not model.boots_equipped:
		return
	var progress := 1.0 - boots_exhaust_life / BOOTS_EXHAUST_TIME
	var opacity: float = 1.0 - smoothstep(0.35, 1.0, progress)
	for nozzle: Vector2 in JUMP_NOZZLES:
		if model.facing < 0:
			nozzle.x = HERO_FRAME_PIXELS.x - nozzle.x
		var at := (bounds.position + nozzle / HERO_FRAME_PIXELS * bounds.size).round()
		var length := minf(roundf(lerpf(8.0, 2.0, progress)), floor_y - at.y)
		if length < 2.0:
			continue
		var shoulder := length / 3.0
		var taper := length * 0.8
		var flame := PackedVector2Array([at + Vector2(-1, 0), at + Vector2(1, 0),
			at + Vector2(2, shoulder), at + Vector2(1, taper), at + Vector2(0, length),
			at + Vector2(-1, taper), at + Vector2(-2, shoulder)])
		draw_colored_polygon(flame, Color(EXHAUST_FLAME, opacity))
		draw_rect(Rect2(at + Vector2(-1, 0), Vector2(2, roundf(shoulder))), Color(EXHAUST_CORE, opacity))

func crush_geometry(impact: Dictionary) -> Dictionary[String, Rect2]:
	var strength: float = smoothstep(0.0, 0.39, crush_progress)
	var floor_y := model.tuning.rows * PIXELS_PER_CELL
	var hero := _hero_bounds()
	var player_feet := roundf((model.player.y + model.tuning.player_height) * PIXELS_PER_CELL)
	var feet := roundf(lerpf(hero.end.y, minf(player_feet, floor_y), strength))
	hero.size.y = roundf(lerpf(hero.size.y, 7.0, strength))
	hero.position.y = feet - hero.size.y
	var overlap := roundf(4.0 * strength)
	var crate := _impact_crate_bounds(impact, hero.position.y + overlap, floor_y)
	# A nearby stack can stop the crate before it reaches the usual pose.
	hero.position.y = minf(hero.position.y, crate.end.y - overlap)
	hero = _spread_squashed_hero(hero, strength)
	var geometry: Dictionary[String, Rect2] = {"hero": hero, "crate": crate}
	return geometry

func _spread_squashed_hero(bounds: Rect2, strength: float) -> Rect2:
	var left := 0.0
	var right := model.tuning.columns * PIXELS_PER_CELL
	var center_x := bounds.get_center().x
	# Preserve the base pose while keeping any extra spread out of adjacent crates.
	for crate in model.crates:
		var at := _crate_origin(float(crate.x), float(crate.y))
		if at.y >= bounds.end.y or at.y + PIXELS_PER_CELL <= bounds.position.y:
			continue
		if at.x + PIXELS_PER_CELL <= center_x:
			left = maxf(left, at.x + PIXELS_PER_CELL)
		elif at.x >= center_x:
			right = minf(right, at.x)
	var spread := roundf(10.0 * strength)
	var x := maxf(bounds.position.x - spread, minf(left, bounds.position.x))
	var end_x := minf(bounds.end.x + spread, maxf(right, bounds.end.x))
	return Rect2(x, bounds.position.y, end_x - x, bounds.size.y)

func _impact_crate_bounds(impact: Dictionary, target_bottom: float, floor_y: float) -> Rect2:
	var x := float(impact.x)
	var bottom := float(impact.y) + 1.0
	var at := _crate_origin(x, float(impact.y))
	# The cosmetic descent stops at the same solid surfaces as a falling crate.
	for crate in model.crates:
		if float(crate.y) + StackSimulation.EPS < bottom or crate.id == impact.id:
			continue
		var other_x := float(crate.x)
		if x < other_x + 1.0 and x + 1.0 > other_x:
			floor_y = minf(floor_y, roundf(float(crate.y) * PIXELS_PER_CELL))
	at.y = maxf(at.y, minf(floor_y, target_bottom) - PIXELS_PER_CELL)
	return Rect2(at, Vector2.ONE * PIXELS_PER_CELL)

func _draw_crush(impact: Dictionary, width: float) -> void:
	var geometry := crush_geometry(impact)
	var pose := geometry["hero"]
	var crate := geometry["crate"]
	var reach: float = smoothstep(0.13, 0.40, crush_progress)
	_draw_hero(pose, hero_frame() if crush_progress == 0.0 else "idle")
	if reach > 0.0:
		for x in [pose.position.x, pose.end.x - 4.0]:
			var glove := Vector2(x, pose.end.y - 4.0)
			draw_rect(Rect2(glove, Vector2(4, 3)), Color(INK, reach))
			draw_rect(Rect2(glove + Vector2(1, 0), Vector2(2, 2)), Color(Color("f1bb83"), reach))
	_draw_crate(crate, int(impact.variant))
	if reach > 0.0:
		var center := _hero_bounds().get_center().x
		for x in [center - 6.0, center + 2.0]:
			var boot := Vector2(x, pose.end.y - 5.0)
			draw_rect(Rect2(boot, Vector2(4, 5)), Color(INK, reach))
			draw_rect(Rect2(boot + Vector2(1, 1), Vector2(2, 3)), Color(Color("79583c"), reach))
	_draw_crush_marks(crate, pose.end.y, width)

func _draw_crush_marks(crate: Rect2, feet: float, width: float) -> void:
	var shock: float = smoothstep(-0.05, 0.10, crush_progress) * (1.0 - smoothstep(0.12, 0.36, crush_progress))
	var dust: float = 1.0 - smoothstep(0.13, 0.44, crush_progress)
	for side: float in [-1.0, 1.0]:
		var edge := crate.get_center().x + crate.size.x * side * 0.5
		if edge + side * 9.0 >= 0.0 and edge + side * 9.0 <= width:
			var contact := Vector2(edge, crate.end.y - 4.0)
			if shock > 0.0:
				draw_colored_polygon(PackedVector2Array([contact + Vector2(side, 2),
					contact + Vector2(side * 9, -7), contact + Vector2(side * 6, -1),
					contact + Vector2(side * 9, 0), contact + Vector2(side * 5, 2),
					contact + Vector2(side * 6, 4)]), Color(EFFECT_AMBER, shock))
			if dust > 0.0:
				draw_rect(Rect2(edge + side * 7.0 - 1.0, feet - 5.0, 3.0, 2.0), Color(EFFECT_DUST, dust * 0.78))
				draw_rect(Rect2(edge + side * 4.0 - 1.0, feet - 3.0, 2.0, 2.0), Color(EFFECT_DUST, dust * 0.62))
	var stars: float = smoothstep(0.53, 0.74, crush_progress)
	if stars > 0.0:
		for index in range(-1, 2):
			var lift := 3.0 * absf(float(index)) + roundf((1.0 - stars) * 3.0)
			var center := Vector2(clampf(crate.get_center().x + index * 9.0, 3.0, width - 3.0),
				crate.position.y - 9.0 + lift)
			_draw_crush_star(center, stars)

func _draw_crush_star(center: Vector2, opacity: float) -> void:
	var shape := PackedVector2Array([center + Vector2(0, -3), center + Vector2(1, -1),
		center + Vector2(3, -1), center + Vector2(2, 1), center + Vector2(2, 3), center + Vector2(0, 2),
		center + Vector2(-2, 3), center + Vector2(-2, 1), center + Vector2(-3, -1), center + Vector2(-1, -1)])
	draw_colored_polygon(shape, Color(EFFECT_AMBER, opacity))
	draw_rect(Rect2(center, Vector2.ONE), Color(Color("fff0be"), opacity))

func _draw_field_objects() -> void:
	var width := model.tuning.columns * PIXELS_PER_CELL
	var floor_y := model.tuning.rows * PIXELS_PER_CELL
	var phase := clear_animation_phase()
	var collapse_elapsed := model.clear_elapsed - model.tuning.clear_flash_time
	if phase == "glow" or phase == "retreat":
		_draw_clearing_row(width, floor_y, phase)
	elif phase == "collapse":
		var openness: float = 1.0 - smoothstep(0.0, CLEAR_LIP_TIME, collapse_elapsed)
		var row := Rect2(0.0, floor_y - PIXELS_PER_CELL, width, PIXELS_PER_CELL)
		_draw_receiving_slot(row, openness)
		_draw_receiving_lip(row, openness)
	var impact := {}
	for crate in model.crates:
		if float(crate.y) < -1.0 or model.is_clearing_crate(int(crate.id)):
			continue
		if crush_progress >= 0.0 and int(crate.id) == model.impact_crate_id:
			impact = crate
			continue
		var position := _crate_origin(float(crate.x), float(crate.y))
		_draw_crate(Rect2(position, Vector2.ONE * PIXELS_PER_CELL), int(crate.variant))
	if impact.is_empty():
		var bounds := _hero_bounds()
		_draw_boots_exhaust(bounds, floor_y)
		_draw_mallet_hero(bounds, hero_frame())
	else:
		_draw_crush(impact, width)
	if active:
		_draw_helmet_impacts(width, floor_y)
		_draw_glove_fragments(width, floor_y)
		_draw_mallet_impacts(width, floor_y)
	if phase == "collapse":
		_draw_clear_dust(width, floor_y, collapse_elapsed)

func _draw_warehouse() -> void:
	var outer := field.grow(WAREHOUSE_FRAME)
	draw_rect(outer.grow(3),Color("0a1e28"))
	draw_rect(outer,Color("74442f"))
	draw_rect(outer.grow(-2),Color("ae6b36"))
	for offset in [3,7,11]:
		draw_line(outer.position+Vector2(offset,2),Vector2(outer.position.x+offset,outer.end.y-2),Color("cc8643"),1)
		draw_line(Vector2(outer.end.x-offset,outer.position.y+2),outer.end-Vector2(offset,2),Color("8d512e"),1)
	draw_line(outer.position+Vector2(3,3),Vector2(outer.end.x-3,outer.position.y+3),Color("efba6d"),2)
	draw_rect(field.grow(2),Color("0f2936"))
	draw_rect(field,Color("193a47"))
	for row in range(model.tuning.rows):
		for column in range(model.tuning.columns):
			if (row+column)%2 == 0: draw_rect(Rect2(field.position+Vector2(column,row)*cell,Vector2.ONE*cell),Color(0.15,0.29,0.34,0.17))
	for column in range(model.tuning.columns+1):
		draw_line(field.position+Vector2(column*cell,0),Vector2(field.position.x+column*cell,field.end.y),Color(0.30,0.49,0.52,0.28),1)
	for row in range(model.tuning.rows+1):
		draw_line(field.position+Vector2(0,row*cell),Vector2(field.end.x,field.position.y+row*cell),Color(0.30,0.49,0.52,0.28),1)
	_bracket(outer.position,Vector2.ONE)
	_bracket(Vector2(outer.end.x,outer.position.y),Vector2(-1,1))
	_bracket(Vector2(outer.position.x,outer.end.y),Vector2(1,-1))
	_bracket(outer.end,Vector2(-1,-1))
	draw_set_transform(field.position, 0.0, Vector2.ONE * cell / PIXELS_PER_CELL)
	_draw_cranes()
	_draw_field_objects()
	draw_set_transform(Vector2.ZERO)
	var floor_y := field.end.y
	draw_rect(Rect2(field.position.x-8,floor_y,field.size.x+16,8),Color("bc8549"))
	draw_rect(Rect2(field.position.x-7,floor_y+1,field.size.x+14,2),Color("f4ce89"))
	for tile in range(model.tuning.columns*2):
		var x := field.position.x+tile*cell*0.5
		draw_line(Vector2(x,floor_y+1),Vector2(x-2,floor_y+7),Color("79502e"),1)
		draw_line(Vector2(x+3,floor_y+5),Vector2(x+cell*.5-3,floor_y+5),Color("dca65f"),1)

func _draw_controls() -> void:
	for action in controls:
		var rect: Rect2 = controls[action]
		var down: bool = pressed_actions.has(action) or (action == "mallet" and mallet_animation_phase() != "none")
		var grabbing: bool = action == "grab" and model.grabbed_crate_id >= 0
		var p := rect.position
		var s := rect.size
		var points := PackedVector2Array([p+Vector2(7,0),p+Vector2(s.x-7,0),p+Vector2(s.x,7),p+Vector2(s.x,s.y-7),p+Vector2(s.x-7,s.y),p+Vector2(7,s.y),p+Vector2(0,s.y-7),p+Vector2(0,7)])
		draw_colored_polygon(points, EFFECT_AMBER if grabbing else (GOLD if down else Color("6d8385")))
		var inside := rect.grow(-2)
		var a := inside.position
		var b := inside.end
		var fill := Color("443a30") if grabbing else (Color("34565d") if down else Color("193844"))
		draw_colored_polygon(PackedVector2Array([a+Vector2(5,0),Vector2(b.x-5,a.y),Vector2(b.x,a.y+5),b-Vector2(0,5),b-Vector2(5,0),Vector2(a.x+5,b.y),Vector2(a.x,b.y-5),a+Vector2(0,5)]), fill)
		draw_line(p+Vector2(7,3),p+Vector2(s.x-7,3), EFFECT_AMBER if grabbing else Color("b3c6b5"),1)
		for at in [p+Vector2(6,6),p+Vector2(s.x-7,6),p+Vector2(6,s.y-7),p+s-Vector2(7,7)]: _bolt(at)
		if action == "grab":
			var source := Rect2(Vector2(GRAB_ICON_SIZE.x if grabbing else 0.0, 0), GRAB_ICON_SIZE)
			var icon_at := rect.get_center() - GRAB_ICON_SIZE * 0.5
			if grabbing:
				icon_at.y -= 4.0
				var indicator := Vector2(rect.get_center().x, rect.end.y - 8.0)
				draw_circle(indicator, 5.0, Color(0.89, 0.51, 0.18, 0.22))
				draw_circle(indicator, 3.0, EFFECT_AMBER)
				draw_rect(Rect2(indicator - Vector2.ONE, Vector2(2, 2)), CREAM)
			draw_texture_rect_region(GRAB_ICONS, Rect2(icon_at, GRAB_ICON_SIZE), source)
		elif action == "mallet":
			var icon_size := Vector2(32, 32)
			draw_texture_rect(MALLET_TEXTURE, Rect2(rect.get_center() - icon_size * 0.5, icon_size), false)
		else:
			var direction := Vector2.UP if action == "jump" else (Vector2.LEFT if action == "left" else Vector2.RIGHT)
			_draw_arrow(rect.get_center() + Vector2(1, 2), direction, Color("0b2632"))
			_draw_arrow(rect.get_center(), direction, CREAM)

func _draw_arrow(center: Vector2,direction: Vector2,color: Color) -> void:
	var normal := Vector2(-direction.y,direction.x)
	draw_colored_polygon(PackedVector2Array([center+direction*12,center-direction*2+normal*10,center-direction*2+normal*4,center-direction*12+normal*4,center-direction*12-normal*4,center-direction*2-normal*4,center-direction*2-normal*10]),color)
