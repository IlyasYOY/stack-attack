extends SceneTree
var failures: Array[String] = []
var assertions := 0
const Config = preload("res://game/tuning.gd")
const Simulation = preload("res://game/simulation.gd")
const Profile = preload("res://game/profile.gd")

class HapticProbe extends StackSound:
	var pulses: Array[int] = []
	func _play_effect(_name: String) -> void:
		pass
	func _supports_haptics() -> bool:
		return true
	func _vibrate(duration: int) -> void:
		pulses.append(duration)


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func empty(columns: int = 10, rows: int = 11) -> StackSimulation:
	var config := Config.new()
	config.columns = columns
	config.rows = rows
	var game := Simulation.new(config, 7481)
	game.crates.clear()
	game.player = Vector2(2, rows - config.player_height)
	game.drop_timer = 9999.0
	return game


func advance(game: StackSimulation, duration: float, axis: float = 0.0) -> void:
	for index in range(roundi(duration * 120)):
		game.advance(1.0 / 120.0, axis)


func run() -> void:
	movement_and_jump()
	pushing_and_danger()
	diagonal_crate_collisions()
	clearing()
	loss_and_drops()
	storage()
	random_sessions()
	demo_games()
	await app_flow()
	await vibration_toggle()
	if not failures.is_empty():
		for failure in failures:
			printerr("GAME_TEST_FAILED: " + failure)
		quit(1)
		return
	print("GAME_TEST_PASS: %d assertions; physics, clears, loss, tempo, storage and screens" % assertions)
	quit(0)


func movement_and_jump() -> void:
	var first := empty()
	var second := empty()
	for index in range(30):
		first.advance(1.0 / 30.0, 1.0)
	for index in range(144):
		second.advance(1.0 / 144.0, 1.0)
	var slow := empty()
	slow.advance(1.0, 1.0)
	check(slow.player.distance_to(first.player) < .0001, "A long render frame must retain every simulation tick")
	check(first.ticks == 120 and second.ticks == 120, "Simulation must use equal fixed ticks across frame rates")
	check(first.player.distance_to(second.player) < 0.0001, "Movement must not depend on render rate")
	check(absf(first.player.x - 5.6) < 0.001, "Configured walking speed must be respected")
	var late := empty()
	late.elapsed = 500
	advance(late, 1, 1)
	check(absf(late.player.x - first.player.x) < 0.001, "Difficulty must not accelerate the player")
	check(late.interval() == late.tuning.minimum_interval, "Drop interval must have a lower bound")
	var jumping := empty()
	var floor_y := jumping.player.y
	jumping.advance(1.0 / 120.0, 0, true)
	var highest := jumping.player.y
	for index in range(150):
		jumping.advance(1.0 / 120.0, 0)
		highest = minf(highest, jumping.player.y)
	check(highest < floor_y - 1.0, "Jump must clear a one-cell crate")
	check(absf(jumping.player.y - floor_y) < 0.001 and jumping.grounded, "Jump must land on the floor")
	check(jumping.score == 0, "Survival and jumping must not award points")


func pushing_and_danger() -> void:
	var pushing := empty()
	var crate := pushing.add_crate(4, 10)
	pushing.player.x = 4 - pushing.tuning.player_width
	advance(pushing, .4, 1)
	advance(pushing, .4)
	check(float(crate.x) >= 4.99, "Walking into a crate must push it smoothly")
	check(absf(float(crate.x) - roundf(float(crate.x))) < .001, "A completed push must align to columns")
	check(pushing.player.x + pushing.tuning.player_width <= float(crate.x) + .01, "Pushing must not penetrate the crate")
	var falling := empty()
	var airborne := falling.add_crate(4, 9.8, .2)
	falling.player.x = 4 - falling.tuning.player_width
	advance(falling, .04, 1)
	check(float(airborne.x) > 4.01 and float(airborne.y) > 9.8 and float(airborne.y) < 10,
		"The character must be able to push a crate while it is falling")
	var stack := empty()
	stack.player.x = 4 - stack.tuning.player_width
	stack.add_crate(4, 10)
	var upper := stack.add_crate(4, 9)
	advance(stack, .9, 1)
	check(float(upper.y) > 9.03, "Removing support must make the upper crate fall")
	check(stack.state == "over" and stack.loss_reason == "crushed", "An unsupported upper crate can kill the character")
	var blocked := empty()
	blocked.player.x = 4 - blocked.tuning.player_width
	var lower := blocked.add_crate(4, 10)
	blocked.add_crate(5, 10)
	advance(blocked, .4, 1)
	check(absf(float(lower.x) - 4) < .001, "One push must not move an entire horizontal chain")


func crates_separate(game: StackSimulation) -> bool:
	for a in game.crates:
		for b in game.crates:
			if int(a.id) >= int(b.id):
				continue
			var width := minf(float(a.x) + 1, float(b.x) + 1) - maxf(float(a.x), float(b.x))
			var height := minf(float(a.y) + 1, float(b.y) + 1) - maxf(float(a.y), float(b.y))
			if width > 0.000001 and height > 0.000001:
				return false
	return true


func diagonal_crate_collisions() -> void:
	for direction in [1, -1]:
		# The review's end-to-end repro, plus a small initial vertical gap.
		for start_y in [8.0, 7.97]:
			var game := empty()
			var ax := 4.0 if direction == 1 else 5.0
			var bx := 5.0 if direction == 1 else 4.0
			var support_x := 3.0 if direction == 1 else 6.0
			var moving := game.add_crate(ax, start_y, 6)
			game.add_crate(bx, 9)
			game.add_crate(bx, 10)
			game.add_crate(support_x, 9)
			game.add_crate(support_x, 10)
			game.player = Vector2(ax - game.tuning.player_width if direction == 1 else ax + 1,
				9 - game.tuning.player_height)
			check(crates_separate(game), "Diagonal fixture must start without penetration")
			for tick in range(120):
				game.advance(StackSimulation.STEP, direction)
				var separate := crates_separate(game)
				check(separate, "Diagonal push dir=%d y=%.2f penetrated at tick %d" % [direction, start_y, tick + 1])
				if not separate:
					break
				if tick == 0:
					check(absf(float(moving.y) - 8) < .000001 and absf(float(moving.x) - ax) > .01,
						"A falling push must land on the neighbour's top instead of entering its corner")
		# A command is already active, but gravity has moved its body below the
		# neighbour's top. Vertical support alone cannot resolve this contact.
		for speed in [3.1, 240.0]:
			var side := empty()
			side.tuning.push_speed = speed
			var ax := 4.0 if direction == 1 else 5.0
			var bx := 5.0 if direction == 1 else 4.0
			var moving := side.add_crate(ax, 8.15, 6)
			moving.target_x = ax + direction
			side.add_crate(bx, 9)
			side.add_crate(bx, 10)
			check(crates_separate(side), "Side-contact fixture must start without penetration")
			for tick in range(120):
				side.advance(StackSimulation.STEP, 0)
				var separate := crates_separate(side)
				check(separate, "Active push dir=%d speed=%.1f penetrated at tick %d" % [direction, speed, tick + 1])
				if not separate:
					break
			check(absf(float(moving.x) - ax) < .000001 and absf(float(moving.target_x) - ax) < .000001,
				"A blocked push must stop at the side, including a large horizontal step")
			check(absf(float(moving.y) - 10) < .000001,
				"Side contact must preserve ordinary falling alongside the obstacle")


func clearing() -> void:
	var game := empty(4, 6)
	game.player = Vector2(2, 5 - game.tuning.player_height)
	for column in range(4):
		game.add_crate(column, 5)
	var survivor := game.add_crate(0, 4)
	var player_y := game.player.y
	game.advance(1.0 / 120, 0)
	check(game.state == "clearing", "Only a complete settled bottom row starts clearing")
	check(game.score == 100, "A line awards exactly the configured points")
	advance(game, .55)
	check(game.crates.size() == 1 and absf(float(survivor.y) - 5) < .001, "All crates above a cleared row descend one cell")
	check(absf(game.player.y - player_y - 1) < .001, "The character descends together with the warehouse contents")
	check(game.state == "playing", "Joint descent must not cause a false crush")
	var chain_game := empty(4, 6)
	chain_game.player = Vector2(2, 4 - chain_game.tuning.player_height)
	for row in [4, 5]:
		for column in range(4):
			chain_game.add_crate(column, row)
	advance(chain_game, 1.2)
	check(chain_game.lines == 2 and chain_game.score == 200, "Successive full bottom rows clear without score multipliers")
	check(chain_game.crates.is_empty() and chain_game.state == "playing", "A chain must finish with safe descent")
	var upper_only := empty(4, 6)
	upper_only.player.x = 2
	for column in range(4):
		upper_only.add_crate(column, 3)
	upper_only.advance(1.0 / 120, 0)
	check(upper_only.lines == 0, "A full upper row must not clear independently")


func loss_and_drops() -> void:
	var crushed := empty(4, 6)
	crushed.player.x = 1.2
	crushed.add_crate(1, 3, 1)
	advance(crushed, 1)
	check(crushed.state == "over" and crushed.loss_reason == "crushed", "A crate falling on the head must end the party")
	var final_ticks := crushed.ticks
	advance(crushed, .5)
	check(crushed.ticks == final_ticks and crushed.events.is_empty(), "Game over must be emitted only once and freeze the model")
	var full := empty(4, 6)
	for row in range(6):
		full.add_crate(0, row)
	full.advance(1.0 / 120, 0)
	check(full.state == "over" and full.loss_reason == "overflow", "A settled tower at full field height blocks the cranes")
	var waves := empty()
	waves.tuning.double_drop_chance = 1
	for index in range(25):
		waves.crates.clear()
		waves._pick_next_columns()
		waves._drop()
		check(waves.crates.size() == 2, "A double drop must release exactly two crates")
		check(float(waves.crates[0].x) != float(waves.crates[1].x), "A double drop must use different columns")
	waves.tuning.double_drop_chance = 0
	waves.crates.clear()
	waves._pick_next_columns()
	waves._drop()
	check(waves.crates.size() == 1, "A single drop must release one crate")


func storage() -> void:
	var path := "user://test-profile-%d.json" % Time.get_ticks_usec()
	var original := Profile.new(path)
	original.music = .2
	original.effects = 0
	original.vibration = false
	original.add_result(300)
	original.add_result(100)
	var loaded := Profile.new(path)
	check(is_equal_approx(loaded.music, .2) and loaded.effects == 0 and not loaded.vibration,
		"Sound and vibration settings must survive a new profile instance")
	check(loaded.records.size() == 2 and int(loaded.records[0].score) == 300,
		"Local scores must survive reload and be sorted")
	for index in range(15):
		loaded.add_result(index * 100)
	check(loaded.records.size() == 10 and int(loaded.records[0].score) == 1400, "Only the ten best local scores are retained")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("broken-json")
	file.close()
	var recovered := Profile.new(path)
	check(recovered.records.is_empty() and not recovered.last_error.is_empty(), "Corrupt storage must fall back safely")
	DirAccess.remove_absolute(path)


func demo_games() -> void:
	var personal := Simulation.new(Config.new(), 74)
	var rng_state: int = personal._rng.state
	var demo := StackDemo.new(Config.new(), 7481)
	for tick in range(120 * 120):
		demo.advance(1.0 / 120.0)
	check(demo.model != personal, "Demo and personal game must be different simulations")
	check(personal.ticks == 0 and personal.score == 0 and personal._rng.state == rng_state, "AI demo must not consume personal time, score or randomness")
	check(demo.jumps > 0 and demo.drops > 0, "Demo must jump and receive real crane drops")
	check(demo.lines > 0, "Reactive AI must be able to clear a real bottom line")
	check(demo.losses > 0 and demo.rounds > 1, "Demo must restart real lost games without inventing victory rules")
	print("DEMO_PASS: %d jumps, %d drops, %d lines, %d losses, %d rounds" % [demo.jumps, demo.drops, demo.lines, demo.losses, demo.rounds])


func vibration_toggle() -> void:
	var path := "user://test-vibration-profile.json"
	var app = load("res://game/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.profile = Profile.new(path)
	app.profile.vibration = false
	app.sound.queue_free()
	var probe := HapticProbe.new()
	app.add_child(probe)
	probe.setup(app.profile)
	app.sound = probe
	app._show_screen("settings")
	app._vibration_option(app.panel.get_child(0))
	await process_frame
	var toggle: Button = app.buttons.vibration
	toggle.grab_focus()
	toggle.button_pressed = true
	check(app.profile.vibration and toggle.text.ends_with("Вкл") and toggle.button_pressed, "Enabled vibration must immediately show a clear on state")
	check(probe.pulses == [60], "Enabling vibration must request one short preview pulse")
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var style: StyleBoxFlat = toggle.get_theme_stylebox(state)
		check(is_zero_approx(style.bg_color.a) if state == "focus" else style.bg_color.a >= 0.7 and style.bg_color.a <= 0.9, "Vibration must use the shared translucent action styles without a black fallback: " + state)
		check(style == app.theme.get_stylebox(state, "Button"), "Vibration must share every action state: " + state)
	toggle.button_pressed = false
	check(not app.profile.vibration and toggle.text.ends_with("Выкл") and probe.pulses == [60], "Disabling vibration must update the state without a pulse")
	app.profile.vibration = true
	probe.unlocked = true
	probe.effect("jump", false)
	check(probe.pulses == [60], "Background game effects must never vibrate the phone")
	probe.effect("jump")
	check(probe.pulses == [60, 12], "Personal game haptics must remain enabled by the saved setting")
	app.profile.vibration = false
	probe.preview_vibration()
	check(probe.pulses == [60, 12], "A disabled vibration setting must suppress preview requests")
	app.queue_free()
	await process_frame
	DirAccess.remove_absolute(path)


func app_flow() -> void:
	check(ProjectSettings.get_setting("application/config/name") == "Stack Attack · Ночная смена", "Visual changes must preserve the existing user data namespace")
	var app = load("res://game/main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	check(app.sound.music_player.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and app.sound.music_player.stream.loop_end > 300000, "Music must loop over decoded frames on every platform")
	check(app.screen == "menu" and app.buttons.has("play") and app.buttons.has("settings"), "Main menu must offer the agreed screens")
	var art_model = app.world.model
	var art_snapshot := [art_model.player, art_model.score, art_model.crates.duplicate(true), art_model._rng.state, art_model.ticks]
	for equipped in [false, true]:
		app.world.cosmetic_magnet = equipped
		app.world.hero_frame()
		check(art_snapshot == [art_model.player, art_model.score, art_model.crates, art_model._rng.state, art_model.ticks], "Cosmetic equipment and pose selection must never mutate gameplay")
	for pose in ["idle", "walk", "jump", "push", "idle_bare", "walk_bare", "jump_bare", "push_bare"]:
		check(app.world.HERO_TEXTURES[pose].get_size() == Vector2(32, 48), "All workshop poses must preserve the same full sprite canvas")
	check(app._missing_menu_glyphs().is_empty(), "The original workshop bitmap face must cover the visible menu text")
	var initial_records: Array = app.profile.records.duplicate(true)
	var personal = app.model
	var random_before: int = personal._rng.state
	var path_exists := FileAccess.file_exists(app.profile.path)
	var file_before := FileAccess.get_file_as_string(app.profile.path) if path_exists else ""
	app._advance_demo(5.0)
	check(app.model == personal and personal.ticks == 0 and personal._rng.state == random_before, "Menu demo must not advance or replace the personal game")
	check(app.session == 0 and app.profile.records == initial_records, "Demo cannot create personal sessions or records")
	check(FileAccess.file_exists(app.profile.path) == path_exists and (not path_exists or FileAccess.get_file_as_string(app.profile.path) == file_before), "Demo must not write the profile file")
	var saved_records: Array = app.profile.records.duplicate(true)
	app.profile.records.clear()
	for index in range(10):
		app.profile.records.append({"score": 1000000 - index * 100, "date": "12.11.2026"})
	for dimensions in [Vector2i(320, 568), Vector2i(568, 320), Vector2i(390, 844), Vector2i(844, 390),
			Vector2i(344, 882), Vector2i(882, 344), Vector2i(768, 1004), Vector2i(1004, 768), Vector2i(360, 360)]:
		root.size = dimensions
		for menu in ["menu", "settings", "records", "paused", "over"]:
			app._show_screen(menu)
			if menu == "settings" and not OS.has_feature("android"):
				# Include the real Android-only row when checking the smallest layouts.
				app._vibration_option(app.panel.get_child(0))
			for frame in range(4):
				await process_frame
			var viewport := Rect2(Vector2.ZERO, app.size)
			check(viewport.encloses(app.panel.get_global_rect()), "%s panel must fit %s without scrolling" % [menu, dimensions])
			check(app.panel.find_children("*", "ScrollContainer", true, false).is_empty(), "Menus must not contain a ScrollContainer")
			for control in app.panel.find_children("*", "Control", true, false):
				if control is Button:
					check(control.size.y >= 48, "Shared styling must preserve touch target height")
					for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
						var style: StyleBoxFlat = control.get_theme_stylebox(state)
						check(style == app.theme.get_stylebox(state, "Button"), "Every menu button must share the result action style: " + menu + "/" + str(control.name) + "/" + state)
						check(style.border_width_left == 1 and style.corner_radius_top_left == 4 and (is_zero_approx(style.bg_color.a) if state == "focus" else style.bg_color.a >= 0.7 and style.bg_color.a <= 0.9), "Shared actions must retain the thin border and translucent backing")
				if control is Label or control.focus_mode == Control.FOCUS_ALL:
					check(viewport.encloses(control.get_global_rect()), "%s content must remain visible at %s: %s" % [menu, dimensions, control.name])
			var focused := root.gui_get_focus_owner()
			check(focused != null and app.panel.is_ancestor_of(focused), "Focus must start inside each menu panel")
	app.profile.records = saved_records
	for reason in ["crushed", "overflow"]:
		app.model.loss_reason = reason
		app.model.score = 200
		app.model.lines = 2
		app._show_screen("over")
		var labels: Array[String] = []
		for label in app.panel.find_children("*", "Label", true, false):
			labels.append(label.text)
		check(labels == ["Смена окончена", "Счёт: 200"], "Game over must display only its unchanged title and final score for either loss")
		check(app.model.loss_reason == reason and app.model.lines == 2, "Hiding result details must preserve the model's reason and line count")
	for dimensions in [Vector2i(390, 844), Vector2i(844, 390), Vector2i(768, 1004)]:
		root.size = dimensions
		for score in [0, 200, 100000000]:
			app.model.score = score
			app._show_screen("over")
			for frame in range(4):
				await process_frame
			var label: Label = app.panel.find_child("result_score", true, false)
			check(label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "Result score must be horizontally centered")
			check(absf(label.get_global_rect().get_center().x - app.size.x * 0.5) <= 1, "Result score layout must share the viewport's center")
			var text_width := label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
			check(label.autowrap_mode == TextServer.AUTOWRAP_OFF and text_width <= label.size.x - 4, "Long result scores must fit on one centered line")
			for id in ["again", "home"]:
				for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
					var style: StyleBoxFlat = app.buttons[id].get_theme_stylebox(state)
					check(style.bg_color.a >= 0.7 and style.bg_color.a <= 0.9 and style.border_width_left == 1, "Result buttons need a subtle backing and thin border in every state")
	app._show_screen("menu")
	app._start_game()
	app._pause()
	var paused_ticks: int = app.model.ticks
	var paused_player: Vector2 = app.model.player
	app._show_screen("menu")
	app._advance_demo(5.0)
	check(app.model.ticks == paused_ticks and app.model.player == paused_player and app.session == 1, "Visiting a demo menu must preserve a paused personal game")
	app._show_screen("paused")
	for index in range(4):
		await process_frame
	check(app.model.ticks == paused_ticks, "Pause must freeze the entire simulation")
	app._show_screen("playing")
	for dimensions in [Vector2i(390, 844), Vector2i(844, 390), Vector2i(320, 568), Vector2i(568, 320)]:
		root.size = dimensions
		await process_frame
		await process_frame
		check(app.model.tuning.columns == 10 and app.model.tuning.rows == 11, "Orientation cannot change field dimensions")
		for rect in app.world.controls.values():
			check(Rect2(Vector2.ZERO, app.size).encloses(rect), "Every touch control must stay inside the viewport")
			check(not app.world.field.intersects(rect), "Touch controls must not cover the field")
	app._show_screen("settings")
	check(app.sliders.has("music") and app.sliders.has("effects"), "Music and effects need separate sliders")
	app._show_screen("records")
	check(app.buttons.has("back"), "Records must provide a return path")
	app._start_game()
	check(app.session == 2 and app.model.score == 0, "Restart must start a fresh party")
	app.queue_free()
	await process_frame


func random_sessions() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 48132
	var count := 0
	for trial in range(8):
		var game := Simulation.new(Config.new(), trial + 100)
		var axis := 0.0
		var valid := true
		for tick in range(6000):
			if tick % 36 == 0:
				axis = rng.randi_range(-1, 1)
			game.advance(1.0 / 120, axis, tick % 67 == 0)
			count += 1
			if tick % 20 == 0:
				for a in game.crates:
					valid = valid and float(a.x) >= -.001 and float(a.x) <= 9.001 and float(a.y) <= 10.001
					if game.state == "playing":
						var hero_rect := Rect2(game.player + Vector2(.04, .04), Vector2(game.tuning.player_width - .08, game.tuning.player_height - .08))
						valid = valid and not hero_rect.intersects(Rect2(a.x+.04,a.y+.04,.92,.92))
					for b in game.crates:
						if int(a.id) >= int(b.id):
							continue
						valid = valid and not Rect2(a.x+.01,a.y+.01,.98,.98).intersects(Rect2(b.x+.01,b.y+.01,.98,.98))
			if game.state == "over":
				break
		check(valid, "Seeded session %d must keep crates inside the field without interpenetration" % trial)
	print("STRESS_PASS: %d ticks across eight seeded sessions" % count)
