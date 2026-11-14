class_name StackWorldView
extends Control
## Workshop presentation only: all gameplay remains in the unchanged cell simulation.
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
var cosmetic_magnet := true
const FONT: Font = preload("res://art/workshop_font.fnt")
const HERO_SIZE := Vector2(16, 24)
const HERO_OFFSET := Vector2(-1, -2)
const HERO_TEXTURES := {
	"idle": preload("res://art/hero_idle.png"), "walk": preload("res://art/hero_walk.png"),
	"jump": preload("res://art/hero_jump.png"), "push": preload("res://art/hero_push.png"),
	"idle_bare": preload("res://art/hero_idle_bare.png"), "walk_bare": preload("res://art/hero_walk_bare.png"),
	"jump_bare": preload("res://art/hero_jump_bare.png"), "push_bare": preload("res://art/hero_push_bare.png")}
var crate_textures: Array[Texture2D] = [preload("res://art/crate_copper.png"), preload("res://art/crate_teal.png"), preload("res://art/crate_violet.png")]
const INK := Color("102733")
const CREAM := Color("f4e3ba")
const GOLD := Color("d7a45a")
const MINT := Color("8dc6ac")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	if model == null: return
	var landscape := size.x > size.y
	var free_width := size.x - (202.0 if landscape else 36.0)
	var free_height := size.y - (84.0 if landscape else 204.0)
	cell = maxf(8.0, floorf(minf(free_width / model.tuning.columns, free_height / (model.tuning.rows + 2))))
	var world_size := Vector2(model.tuning.columns * cell, model.tuning.rows * cell)
	var top := 60.0 + cell * 1.1
	if not landscape: top += maxf(0.0, (free_height - (model.tuning.rows + 2) * cell) * 0.4)
	field = Rect2(Vector2(floorf((size.x - world_size.x) * 0.5), top), world_size)
	var button_size := Vector2(66, 64)
	if landscape:
		controls = {"left": Rect2(Vector2(12, size.y - 90), button_size), "right": Rect2(Vector2(84, size.y - 90), button_size), "jump": Rect2(Vector2(size.x - 82, size.y - 90), Vector2(70, 64))}
	else:
		controls = {"left": Rect2(Vector2(18, size.y - 92), button_size), "right": Rect2(Vector2(90, size.y - 92), button_size), "jump": Rect2(Vector2(size.x - 88, size.y - 92), Vector2(70, 64))}
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
		particles.append({"position": Vector2(float(index) / 40 * model.tuning.columns, model.tuning.rows - 0.5), "velocity": Vector2(sin(index * 7.1) * 2.5, -1.0 - fmod(index * 0.7, 3.0)), "life": 0.5 + fmod(index * 0.13, 0.5)})

func _draw() -> void:
	_draw_scenery()
	if model == null: return
	_draw_warehouse()
	if active: _draw_controls()
	if caption_life > 0.0 and active:
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
	var ly := minf(57, field.position.y - cell * 1.15 - 28)
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

func _draw_warehouse() -> void:
	var outer := field.grow(13)
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
	var rail_y := field.position.y-cell*1.15
	draw_rect(Rect2(field.position.x-15,rail_y,field.size.x+30,8),Color("624532"))
	draw_rect(Rect2(field.position.x-14,rail_y+1,field.size.x+28,4),Color("d39248"))
	draw_rect(Rect2(field.position.x-14,rail_y+1,field.size.x+28,1),Color("f6d18e"))
	for x in range(int(field.position.x),int(field.end.x),48): _bolt(Vector2(x,rail_y+4))
	for column in model.next_columns:
		var x := field.position.x+(column+0.5)*cell
		draw_rect(Rect2(x-9,rail_y-7,18,19),INK)
		draw_rect(Rect2(x-8,rail_y-6,16,17),Color("b47a3f"))
		draw_rect(Rect2(x-7,rail_y-5,14,2),Color("f3cb80"))
		_bolt(Vector2(x-5,rail_y-2));_bolt(Vector2(x+5,rail_y+7))
		draw_rect(Rect2(x-3,rail_y+12,6,5),Color("655443"))
		draw_line(Vector2(x,rail_y+17),Vector2(x,field.position.y-5),Color("b6afa0"),2)
		draw_line(Vector2(x,field.position.y-5),Vector2(x+4,field.position.y-2),GOLD,2)
	draw_set_transform(field.position,0.0,Vector2.ONE*cell/24.0)
	for crate in model.crates:
		var position := Vector2(roundf(float(crate.x)*24),roundf(float(crate.y)*24))
		if float(crate.y) < -1.0: continue
		var tint := Color.WHITE
		if model.state == "clearing" and model.clear_elapsed < model.tuning.clear_flash_time and float(crate.y) > model.tuning.rows-1.01: tint=Color(1.8,1.6,1.1,1.0)
		draw_texture_rect(crate_textures[int(crate.color)%3],Rect2(position,Vector2(24,24)),false,tint)
	var hero_position := Vector2(roundf(model.player.x*24),roundf(model.player.y*24))+HERO_OFFSET
	var texture: Texture2D = HERO_TEXTURES[hero_frame() + ("" if cosmetic_magnet else "_bare")]
	var hero_rect := Rect2(hero_position,HERO_SIZE)
	if model.facing < 0: hero_rect.size.x=-HERO_SIZE.x
	draw_texture_rect(texture,hero_rect,false)
	for particle in particles: draw_rect(Rect2(particle.position*24,Vector2(2,2)),Color(0.95,0.76,0.4,clampf(float(particle.life)*2,0,1)))
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
		var down := pressed_actions.has(action)
		var p := rect.position
		var s := rect.size
		var points := PackedVector2Array([p+Vector2(7,0),p+Vector2(s.x-7,0),p+Vector2(s.x,7),p+Vector2(s.x,s.y-7),p+Vector2(s.x-7,s.y),p+Vector2(7,s.y),p+Vector2(0,s.y-7),p+Vector2(0,7)])
		draw_colored_polygon(points,GOLD if down else Color("6d8385"))
		var inside := rect.grow(-2)
		var a := inside.position
		var b := inside.end
		draw_colored_polygon(PackedVector2Array([a+Vector2(5,0),Vector2(b.x-5,a.y),Vector2(b.x,a.y+5),b-Vector2(0,5),b-Vector2(5,0),Vector2(a.x+5,b.y),Vector2(a.x,b.y-5),a+Vector2(0,5)]),Color("34565d") if down else Color("193844"))
		draw_line(p+Vector2(7,3),p+Vector2(s.x-7,3),Color("b3c6b5"),1)
		for at in [p+Vector2(6,6),p+Vector2(s.x-7,6),p+Vector2(6,s.y-7),p+s-Vector2(7,7)]: _bolt(at)
		_draw_arrow(rect.get_center()+Vector2(1,2),Vector2.UP if action=="jump" else (Vector2.LEFT if action=="left" else Vector2.RIGHT),Color("0b2632"))
		_draw_arrow(rect.get_center(),Vector2.UP if action=="jump" else (Vector2.LEFT if action=="left" else Vector2.RIGHT),CREAM)

func _draw_arrow(center: Vector2,direction: Vector2,color: Color) -> void:
	var normal := Vector2(-direction.y,direction.x)
	draw_colored_polygon(PackedVector2Array([center+direction*12,center-direction*2+normal*10,center-direction*2+normal*4,center-direction*12+normal*4,center-direction*12-normal*4,center-direction*2-normal*4,center-direction*2-normal*10]),color)
