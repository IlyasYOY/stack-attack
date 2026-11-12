extends Control
const TUNING: StackTuning = preload("res://game/prototype.tres")
var model: StackSimulation
var profile: StackProfile
var sound: StackSound
var world: StackWorldView
var ui: Control
var screen := "menu"
var buttons := {}
var sliders := {}
var panel: PanelContainer
var score_label: Label
var pointers := {}
var jump_pending := false
var session := 0
var result_saved := false
var qa_enabled := false
var qa_timer := 0.0
const CREAM := Color("f4e3ba")
const MINT := Color("8dc6ac")
const GOLD := Color("d7a45a")


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	profile = StackProfile.new()
	model = StackSimulation.new(TUNING, 1)
	sound = StackSound.new()
	add_child(sound)
	sound.setup(profile)
	theme = _make_theme()
	world = StackWorldView.new()
	world.model = model
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(world)
	ui = Control.new()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(ui)
	resized.connect(_resize)
	if OS.has_feature("web") and OS.is_debug_build():
		qa_enabled = bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('qa') === '1'"))
	_show_screen("menu")
	_resize()
	print("STACK_ATTACK_READY")


func _make_style(color: Color, border: Color, margin: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(2)
	style.set_content_margin_all(margin)
	return style


func _make_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 17
	result.set_color("font_color", "Label", CREAM)
	result.set_color("font_color", "Button", CREAM)
	result.set_color("font_hover_color", "Button", Color.WHITE)
	var padding := 8 if size.y < 440 else 12
	result.set_stylebox("normal", "Button", _make_style(Color("28414c"), Color("7e8170"), padding))
	result.set_stylebox("hover", "Button", _make_style(Color("35565a"), MINT, padding))
	result.set_stylebox("pressed", "Button", _make_style(Color("456963"), GOLD, padding))
	result.set_stylebox("focus", "Button", _make_style(Color(0, 0, 0, 0), GOLD, 2))
	result.set_stylebox("panel", "PanelContainer", _make_style(Color(0.055, 0.12, 0.17, 0.97), Color("a88660"), 12 if _compact_panel() else 18))
	result.set_constant("separation", "VBoxContainer", 4 if _compact_panel() else 10)
	result.set_constant("separation", "HBoxContainer", 16)
	result.set_font_size("font_size", "Button", 18)
	var rail := _make_style(Color("243d4a"), Color("617b7b"), 3)
	result.set_stylebox("slider", "HSlider", rail)
	result.set_stylebox("grabber_area", "HSlider", _make_style(Color("a38459"), GOLD, 3))
	result.set_stylebox("grabber_area_highlight", "HSlider", _make_style(MINT, GOLD, 3))
	result.set_icon("grabber", "HSlider", preload("res://art/slider_knob.png"))
	result.set_icon("grabber_highlight", "HSlider", preload("res://art/slider_knob.png"))
	return result


func _compact_panel() -> bool:
	return size.y < 620


func _wide_panel() -> bool:
	return size.x > size.y * 1.25


func _column(parent: Control) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	return column


func _clear_ui() -> void:
	for child in ui.get_children():
		child.hide()
		child.process_mode = Node.PROCESS_MODE_DISABLED
		child.queue_free()
	buttons.clear()
	sliders.clear()
	panel = null
	score_label = null


func _show_screen(value: String) -> void:
	var previous_focus := get_viewport().gui_get_focus_owner()
	var focus_name := str(previous_focus.name) if previous_focus != null else ""
	screen = value
	theme = _make_theme()
	_release_controls()
	_clear_ui()
	world.active = screen in ["playing", "paused"]
	sound.music_player.volume_db = -5.0 if screen == "paused" else 0.0
	if screen in ["playing", "paused"]:
		_build_hud()
	if screen == "playing":
		return
	var content := _make_panel()
	match screen:
		"menu":
			var intro := content
			var actions := content
			if _wide_panel():
				var row := HBoxContainer.new()
				content.add_child(row)
				intro = _column(row)
				actions = _column(row)
			_heading(intro, "STACK ATTACK", "НОЧНАЯ СМЕНА", 32)
			_text(intro, "Сдвигай ящики. Собирай нижний ряд.\nБереги голову.", 14 if _compact_panel() else 16)
			_button(actions, "Играть", "play", _start_game)
			_button(actions, "Рекорды", "records", func(): _show_screen("records"))
			_button(actions, "Настройки", "settings", func(): _show_screen("settings"))
			_text(intro, "Стрелки: движение · Пробел: прыжок\nНа телефоне: экранные кнопки", 12, Color("9eafa5"))
		"paused":
			_heading(content, "Пауза", "ВЫДОХНИ. СКЛАД ПОДОЖДЁТ.")
			_button(content, "Продолжить", "resume", func(): _show_screen("playing"))
			_button(content, "Начать заново", "restart", _start_game)
			_button(content, "Главное меню", "home", func(): _show_screen("menu"))
		"over":
			_heading(content, "Смена окончена", "СКЛАД ЗАПОЛНЕН" if model.loss_reason == "overflow" else "ОСТОРОЖНО, ЯЩИКИ!")
			_text(content, str(model.score), 32 if _compact_panel() else 44, GOLD)
			_text(content, "Очищено рядов: %d" % model.lines, 16)
			var actions: Control = content
			if _compact_panel():
				actions = HBoxContainer.new()
				content.add_child(actions)
			_button(actions, "Играть снова", "again", _start_game)
			_button(actions, "Главное меню", "home", func(): _show_screen("menu"))
			if not profile.last_error.is_empty():
				_text(content, profile.last_error, 12)
		"records":
			_heading(content, "Рекорды", "ЛУЧШАЯ ДЕСЯТКА · НА ЭТОМ УСТРОЙСТВЕ")
			if profile.records.is_empty():
				_text(content, "Пока пусто. Первый ряд уже ждёт.", 16)
			var entries: Control = content
			if _compact_panel() and not profile.records.is_empty():
				var grid := GridContainer.new()
				grid.columns = 2
				grid.add_theme_constant_override("h_separation", 16)
				grid.add_theme_constant_override("v_separation", 6)
				content.add_child(grid)
				entries = grid
			for index in range(profile.records.size()):
				var entry: Dictionary = profile.records[index]
				if _compact_panel():
					var item := _column(entries)
					item.add_theme_constant_override("separation", 0)
					_text(item, "%02d   %d" % [index + 1, entry.score], 14, GOLD if index == 0 else CREAM)
					_text(item, str(entry.date), 10, MINT)
				else:
					_text(entries, "%02d   %s   ·   %d" % [index + 1, entry.date, entry.score], 16,
						GOLD if index == 0 else CREAM)
			_button(content, "Назад", "back", func(): _show_screen("menu"))
		"settings":
			_heading(content, "Настройки", "ЗВУК НОЧНОГО СКЛАДА")
			if _compact_panel():
				var row := HBoxContainer.new()
				content.add_child(row)
				_slider(_column(row), "Музыка", "music", profile.music)
				_slider(_column(row), "Звуки", "effects", profile.effects)
			else:
				_slider(content, "Музыка", "music", profile.music)
				_slider(content, "Звуки", "effects", profile.effects)
			if OS.has_feature("android"):
				_vibration_option(content)
			var actions: Control = content
			if _compact_panel():
				actions = HBoxContainer.new()
				content.add_child(actions)
			_button(actions, "Проверить звук", "sound_test", func(): sound.effect("line"))
			_button(actions, "Назад", "back", func(): _show_screen("menu"))
	_position_panel()
	_focus_panel.call_deferred(panel, focus_name)


func _make_panel() -> VBoxContainer:
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.06, 0.09, 0.43)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(shade)
	panel = PanelContainer.new()
	ui.add_child(panel)
	panel.resized.connect(_center_panel)
	panel.minimum_size_changed.connect(_position_panel)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(content)
	return content


func _position_panel() -> void:
	if panel != null:
		panel.size = Vector2(minf(720 if _wide_panel() else 440, size.x - 32), panel.get_combined_minimum_size().y)
		_center_panel()


func _center_panel() -> void:
	if panel != null:
		panel.position = ((size - panel.size) * 0.5).floor()


func _focus_panel(expected_panel: PanelContainer, preferred: String) -> void:
	if panel != expected_panel or not is_instance_valid(expected_panel):
		return
	var controls: Array[Control] = []
	for control in panel.find_children("*", "Control", true, false):
		if control.focus_mode == Control.FOCUS_ALL:
			controls.append(control)
	for index in range(controls.size()):
		var control := controls[index]
		control.focus_next = control.get_path_to(controls[(index + 1) % controls.size()])
		control.focus_previous = control.get_path_to(controls[(index - 1 + controls.size()) % controls.size()])
	if not controls.is_empty():
		var target := controls[0]
		for control in controls:
			if str(control.name) == preferred:
				target = control
		target.grab_focus()


func _heading(parent: Control, title: String, subtitle: String, text_size: int = 28) -> void:
	_text(parent, subtitle, 11, MINT)
	_text(parent, title, mini(22, text_size) if _compact_panel() else text_size, GOLD)
	var separator := HSeparator.new()
	separator.modulate = Color("9a7d5e")
	parent.add_child(separator)


func _text(parent: Control, value: String, text_size: int = 17, color: Color = CREAM) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", text_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _button(parent: Control, title: String, id: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = id
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.text = title
	button.custom_minimum_size.y = 48
	button.pressed.connect(func():
		sound.unlock()
		sound.effect("click")
		action.call_deferred())
	parent.add_child(button)
	buttons[id] = button
	return button


func _slider(parent: Control, title: String, id: String, value: float) -> void:
	var label := _text(parent, "%s · %d%%" % [title, roundi(value * 100)], 16)
	var slider := HSlider.new()
	slider.name = id
	slider.min_value = 0
	slider.max_value = 1
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(0, 28 if size.y < 440 else 38)
	slider.value_changed.connect(func(volume: float):
		if id == "music":
			profile.music = volume
		else:
			profile.effects = volume
		label.text = "%s · %d%%" % [title, roundi(volume * 100)]
		sound.apply_volumes()
		profile.save_profile())
	parent.add_child(slider)
	sliders[id] = slider


func _vibration_option(parent: Control) -> void:
	var vibration := CheckButton.new()
	vibration.name = "vibration"
	vibration.text = "Виброотклик"
	vibration.button_pressed = profile.vibration
	vibration.toggled.connect(func(enabled: bool):
		profile.vibration = enabled
		profile.save_profile())
	parent.add_child(vibration)


func _build_hud() -> void:
	score_label = Label.new()
	score_label.position = Vector2(18, 12)
	score_label.add_theme_font_size_override("font_size", 25)
	score_label.text = "%06d" % model.score
	ui.add_child(score_label)
	var pause := _button(ui, "II", "pause", _pause)
	pause.focus_mode = Control.FOCUS_NONE
	pause.size = Vector2(48, 48)
	pause.custom_minimum_size.y = 48
	pause.position = Vector2(size.x - 66, 10)


func _start_game() -> void:
	session += 1
	model = StackSimulation.new(TUNING, Time.get_ticks_usec())
	world.model = model
	world.particles.clear()
	world.caption_life = 0.0
	world._layout()
	result_saved = false
	_show_screen("playing")


func _pause() -> void:
	if screen == "playing":
		_show_screen("paused")


func _end_game() -> void:
	if not result_saved:
		result_saved = true
		profile.add_result(model.score)
	_show_screen("over")


func _resize() -> void:
	_release_controls()
	if world != null:
		world._layout()
	if panel != null:
		_show_screen(screen)
	else:
		_position_panel()
	if buttons.has("pause"):
		buttons.pause.position = Vector2(size.x - 66, 10)


func _release_controls() -> void:
	pointers.clear()
	jump_pending = false
	if world != null:
		world.pressed_actions.clear()
		world.axis = 0.0


func _input(event: InputEvent) -> void:
	if sound != null and ((event is InputEventMouseButton and event.pressed) or
		(event is InputEventScreenTouch and event.pressed) or (event is InputEventKey and event.pressed)):
		sound.unlock()
	if screen == "paused" and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		_show_screen("playing")
		get_viewport().set_input_as_handled()
		return
	if screen != "playing":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			_pause()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_SPACE:
			jump_pending = true
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		_pointer(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag and pointers.has(event.index):
		_pointer(event.index, event.position, true)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_pointer(-1, event.position, event.pressed)
	elif event is InputEventMouseMotion and pointers.has(-1):
		_pointer(-1, event.position, true)


func _pointer(id: int, position: Vector2, down: bool) -> void:
	var previous: String = pointers.get(id, "")
	if not down:
		if pointers.has(id):
			pointers.erase(id)
			get_viewport().set_input_as_handled()
		return
	var action := ""
	for candidate in world.controls:
		if world.controls[candidate].has_point(position):
			action = candidate
			break
	if not action.is_empty():
		pointers[id] = action
		if action == "jump" and previous != "jump":
			jump_pending = true
		get_viewport().set_input_as_handled()
	elif pointers.has(id):
		pointers.erase(id)


func _advance_game(delta: float) -> void:
	if model == null or screen != "playing":
		return
	var actions: Array[String] = []
	for action in pointers.values():
		if not actions.has(action):
			actions.append(action)
	world.pressed_actions = actions
	var axis := float(Input.is_physical_key_pressed(KEY_RIGHT) or actions.has("right")) - float(
		Input.is_physical_key_pressed(KEY_LEFT) or actions.has("left"))
	world.axis = axis
	model.advance(delta, axis, jump_pending)
	jump_pending = false
	for event in model.events:
		match event.type:
			"jump": sound.effect("jump")
			"land": sound.effect("land")
			"line":
				sound.effect("line")
				world.line_effect(int(event.chain))
			"over":
				sound.effect("over")
				_end_game()
	if score_label != null:
		score_label.text = "%06d" % model.score


func _process(delta: float) -> void:
	if world == null:
		return
	_advance_game(delta)
	world.animate(delta if screen != "paused" else 0.0)
	if qa_enabled:
		qa_timer += delta
		if qa_timer >= 0.08:
			qa_timer = 0.0
			_qa_command()
			_publish_qa()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT] and is_inside_tree() and screen == "playing":
		_pause()


func _publish_qa() -> void:
	var rects := {}
	for id in buttons:
		if is_instance_valid(buttons[id]):
			var rect: Rect2 = buttons[id].get_global_rect()
			rects[id] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	var slider_rects := {}
	for id in sliders:
		var rect: Rect2 = sliders[id].get_global_rect()
		slider_rects[id] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	var input_rects := {}
	for id in world.controls:
		var rect: Rect2 = world.controls[id]
		input_rects[id] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	var status := {"ready": true, "screen": screen, "score": model.score,
		"session": session, "ticks": model.ticks, "state": model.state,
		"player": [model.player.x, model.player.y], "grounded": model.grounded,
		"columns": model.tuning.columns, "rows": model.tuning.rows, "crates": model.crates.size(), "first_crate_x": model.crates[0].x if not model.crates.is_empty() else -1,
		"layout": "landscape" if size.x > size.y else "portrait", "viewport": [size.x, size.y],
		"field": [world.field.position.x, world.field.position.y, world.field.size.x, world.field.size.y],
		"buttons": rects, "sliders": slider_rects, "controls": input_rects,
		"missing_menu_glyphs": _missing_menu_glyphs(),
		"panel": _panel_snapshot(),
		"profile": {"music": profile.music, "effects": profile.effects,
			"records": profile.records, "vibration_visible": OS.has_feature("android")},
		"audio": {"music_playing": sound.music_player.playing, "music_position": sound.music_player.get_playback_position(), "stream_format": sound.music_player.stream.format, "loop_end": sound.music_player.stream.loop_end, "unlocked": sound.unlocked,
			"music_muted": AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")),
			"effects_muted": AudioServer.is_bus_mute(AudioServer.get_bus_index("Effects"))}}
	JavaScriptBridge.eval("window.stackAttackState = " + JSON.stringify(status))


func _missing_menu_glyphs() -> String:
	var missing := ""
	if screen == "menu":
		for label in ui.find_children("*", "Label", true, false):
			var font: Font = label.get_theme_font("font")
			for character in label.text:
				if character.unicode_at(0) > 32 and not font.has_char(character.unicode_at(0)) and not missing.contains(character):
					missing += character
	return missing


func _panel_snapshot() -> Dictionary:
	if panel == null:
		return {}
	var rect := panel.get_global_rect()
	var items := []
	for control in panel.find_children("*", "Control", true, false):
		if control is Label or control.focus_mode == Control.FOCUS_ALL:
			var bounds: Rect2 = control.get_global_rect()
			items.append({"name": str(control.name), "kind": control.get_class(), "rect": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
				"focusable": control.focus_mode == Control.FOCUS_ALL})
	var focused := get_viewport().gui_get_focus_owner()
	return {"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "items": items,
		"scroll_containers": panel.find_children("*", "ScrollContainer", true, false).size(),
		"focus": str(focused.name) if focused != null else ""}


func _qa_command() -> void:
	# Deliberate opt-in on debug Web exports only. No gameplay UI exposes fixtures.
	var raw: Variant = JavaScriptBridge.eval("JSON.stringify(window.stackAttackQARequest || null)")
	if raw == null or str(raw) == "null":
		return
	JavaScriptBridge.eval("window.stackAttackQARequest = null")
	var request: Variant = JSON.parse_string(str(raw))
	if not request is Dictionary:
		return
	if str(request.get("scenario", "")) == "records_menu" and screen in ["menu", "records"]:
		profile.records.clear()
		for index in range(10):
			profile.records.append({"score": 1000000 - index * 100, "date": "12.11.2026"})
		_show_screen("records")
		return
	if screen != "playing":
		return
	if str(request.get("scenario", "")) not in ["line", "chain", "crush", "overflow", "push", "showcase"]:
		return
	model.crates.clear()
	model.drop_timer = 999.0
	model.player_velocity = Vector2.ZERO
	model.player = Vector2(4.3, TUNING.rows - TUNING.player_height)
	model.state = "playing"
	model.chain = 0
	match str(request.get("scenario", "")):
		"line", "chain":
			var count := 2 if request.scenario == "chain" else 1
			for row in range(count):
				for column in range(TUNING.columns):
					model.add_crate(float(column), float(TUNING.rows - 1 - row))
			model.player.y -= count
		"crush":
			model.add_crate(4.0, float(TUNING.rows - 3), 1.0)
		"overflow":
			for row in range(TUNING.rows):
				model.add_crate(0.0, float(row))
		"push":
			model.player.x = 5.0 - TUNING.player_width
			model.add_crate(5.0, float(TUNING.rows - 1))

		"showcase":
			for column in [0, 1, 2, 6, 7, 8, 9]:
				model.add_crate(float(column), float(TUNING.rows - 1))
			for column in [0, 1, 8, 9]:
				model.add_crate(float(column), float(TUNING.rows - 2))
			for column in [0, 9]:
				model.add_crate(float(column), float(TUNING.rows - 3))
			model.add_crate(5, 2, .5)
			model.next_columns.assign([3, 6])
