extends Control
const TUNING: StackTuning = preload("res://game/prototype.tres")
const STATISTICS_VIEW = preload("res://game/statistics_view.gd")
const EQUIPMENT_VIEW = preload("res://game/equipment_view.gd")
const CRUSH_ANIMATION_TIME := 0.42
var model: StackSimulation
var demo: StackDemo
var profile: StackProfile
var sound: StackSound
var world: StackWorldView
var ui: Control
var screen := "menu"
var buttons := {}
var sliders := {}
var panel: PanelContainer
var score_label: Label
var boots_count: Label
var helmet_count: Label
var gloves_count: Label
var pointers := {}
var jump_pointers := {}
var pull_pointers := {}
var jump_pending := false
var pull_key_held := false
var session := 0
var result_saved := false
var crush_elapsed := -1.0
var first_match := 0
var expanded_match := -1
var qa_enabled := false
var qa_timer := 0.0
var qa_hero_pose := false
var qa_android_settings := false
var qa_freeze_demo := false
var qa_result_demo := false
var qa_statistics_preview: StackProfile
var qa_crane_preview := false
var qa_crane_releases: Array[Dictionary] = []
var qa_helmet_hits: Array[Dictionary] = []
var qa_gloves_pulls: Array[Dictionary] = []
var qa_animation_held := false
const CREAM := Color("f4e3ba")
const MINT := Color("8dc6ac")
const GOLD := Color("d7a45a")


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if OS.has_feature("web") and OS.is_debug_build():
		qa_enabled = bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('qa') === '1'"))
	var profile_path := StackProfile.SAVE_PATH + ".qa" if qa_enabled else StackProfile.SAVE_PATH
	profile = StackProfile.new(profile_path)
	model = StackSimulation.new(TUNING, 1)
	demo = StackDemo.new(TUNING)
	sound = StackSound.new()
	add_child(sound)
	sound.setup(profile)
	if OS.has_feature("android"):
		sound.unlock()
	theme = _make_theme()
	world = StackWorldView.new()
	world.model = demo.model
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(world)
	ui = Control.new()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(ui)
	resized.connect(_resize)
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
	result.default_font = preload("res://art/workshop_font.fnt")
	result.default_font_size = 17
	result.set_color("font_color", "Label", CREAM)
	result.set_color("font_color", "Button", CREAM)
	result.set_color("font_hover_color", "Button", Color.WHITE)
	result.set_color("font_pressed_color", "Button", GOLD)
	result.set_color("font_hover_pressed_color", "Button", GOLD)
	for kind in ["Label", "Button"]:
		result.set_color("font_outline_color", kind, Color("10202b"))
		result.set_constant("outline_size", kind, 3)
	var panel_style := _make_style(Color.TRANSPARENT, Color.TRANSPARENT, 12 if _compact_panel() else 18)
	panel_style.set_border_width_all(0)
	result.set_stylebox("panel", "PanelContainer", panel_style)
	result.set_constant("separation", "VBoxContainer", 4 if _compact_panel() else 10)
	result.set_constant("separation", "HBoxContainer", 16)
	result.set_font_size("font_size", "Button", 18)
	# Every action inherits the same game-over styling, including the Android toggle.
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var focused: bool = state == "focus"
		var fill := Color(0.055, 0.13, 0.16, 0.86 if state in ["normal", "disabled"] else 0.90)
		var border := Color(0.55, 0.65, 0.63, 0.45)
		if state in ["pressed", "hover_pressed", "focus"]:
			border = GOLD
		elif state == "hover":
			border = MINT
		var style := _make_style(Color.TRANSPARENT if focused else fill, border, 8 if _compact_panel() else 12)
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		style.shadow_color = Color(0.02, 0.06, 0.08, 0.35)
		style.shadow_size = 0 if focused else 2
		style.shadow_offset = Vector2(0, 2)
		result.set_stylebox(state, "Button", style)
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
	boots_count = null
	helmet_count = null
	gloves_count = null


func _show_screen(value: String) -> void:
	if value != "over":
		qa_result_demo = false
	if value != "statistics":
		qa_statistics_preview = null
	var previous_focus := get_viewport().gui_get_focus_owner()
	var focus_name := str(previous_focus.name) if previous_focus != null else ""
	screen = value
	theme = _make_theme()
	_release_controls()
	_clear_ui()
	world.active = screen in ["playing", "paused", "equipment"]
	world.hud_right = EQUIPMENT_VIEW.HUD_RIGHT if world.active else StackWorldView.SCORE_PANEL_RIGHT
	world.model = demo.model if _background_demo() else model
	world._layout()
	sound.music_player.volume_db = -5.0 if screen in ["paused", "equipment"] else 0.0
	if world.active:
		_build_hud()
	if screen == "playing":
		return
	var content := _make_panel()
	match screen:
		"menu":
			_heading(content, "Stack Attack", 32)
			_button(content, "Играть", "play", _start_game)
			_button(content, "Статистика", "statistics", _open_statistics)
			_button(content, "Настройки", "settings", func(): _show_screen("settings"))
		"paused":
			_heading(content, "Пауза")
			EQUIPMENT_VIEW.build_pause(panel, content, _compact_panel(), model, _text)
			_button(content, "Продолжить", "resume", func(): _show_screen("playing"))
			_button(content, "Начать заново", "restart", _start_game)
			_button(content, "Главное меню", "home", func(): _show_screen("menu"))
		"equipment":
			var offer := panel
			var resolve := func(item: String): _resolve_equipment(item, offer)
			EQUIPMENT_VIEW.build_offer(panel, content, _compact_panel(), model, _button, _text, resolve)
		"over":
			_heading(content, "Смена окончена")
			_result_score(content)
			var actions: Control = content
			if _compact_panel() and _wide_panel():
				actions = HBoxContainer.new()
				content.add_child(actions)
			_button(actions, "Играть снова", "again", _start_game)
			_button(actions, "Главное меню", "home", func(): _show_screen("menu"))
			if not profile.last_error.is_empty():
				_text(content, profile.last_error, 12)
		"statistics":
			var display_profile := qa_statistics_preview if qa_statistics_preview != null else profile
			var margins := panel.get_theme_stylebox("panel").get_minimum_size()
			var available := Vector2(_panel_width(), size.y - 12) - margins
			STATISTICS_VIEW.build(content, available, display_profile.statistics(), display_profile.matches,
				display_profile.records, first_match, expanded_match, _button, _text, _change_statistics,
				func(): _show_screen("menu"))
		"settings":
			_heading(content, "Настройки")
			if _compact_panel():
				var row := HBoxContainer.new()
				content.add_child(row)
				_slider(_column(row), "Музыка", "music", profile.music)
				_slider(_column(row), "Звуки", "effects", profile.effects)
			else:
				_slider(content, "Музыка", "music", profile.music)
				_slider(content, "Звуки", "effects", profile.effects)
			if OS.has_feature("android") or (qa_enabled and qa_android_settings):
				_vibration_option(content)
			_button(content, "Назад", "back", func(): _show_screen("menu"))
	_position_panel()
	_focus_panel.call_deferred(panel, focus_name)


func _open_statistics() -> void:
	_change_statistics(0, -1)


func _change_statistics(offset: int, expanded: int) -> void:
	first_match = offset
	expanded_match = expanded
	_show_screen("statistics")


func _make_panel() -> VBoxContainer:
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.06, 0.09, 0.38)
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
		panel.size = Vector2(_panel_width(), panel.get_combined_minimum_size().y)
		_center_panel()


func _panel_width() -> float:
	if screen == "equipment":
		return minf(440 if model.equipment_options().size() > 1 else 330, size.x - 32)
	if screen == "paused":
		return minf(360, size.x - 32)
	return minf(720 if _wide_panel() and screen != "menu" else 440, size.x - 32)


func _result_score(parent: Control) -> void:
	var label := _text(parent, "Счёт: %d" % model.score, 32 if _compact_panel() else 44, GOLD)
	label.name = "result_score"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	var available := _panel_width() - panel.get_theme_stylebox("panel").get_minimum_size().x - 8
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	while font_size > 20 and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > available:
		font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)


func _center_panel() -> void:
	if panel != null:
		var centered := ((size - panel.size) * 0.5).floor()
		var below_hud := StackWorldView.HUD_CLEARANCE_Y
		if screen in ["paused", "equipment"] and size.y - panel.size.y >= below_hud + 6.0:
			centered.y = maxf(centered.y, below_hud)
		panel.position = centered


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


func _heading(parent: Control, title: String, text_size: int = 28) -> void:
	var label := _text(parent, title, mini(26, text_size) if _compact_panel() else text_size, GOLD)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

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
	button.draw.connect(_workshop_trim.bind(button))
	buttons[id] = button
	return button


func _workshop_trim(control: Control) -> void:
	for at in [Vector2(6, 6), Vector2(control.size.x - 7, 6), Vector2(6, control.size.y - 7), control.size - Vector2(7, 7)]:
		control.draw_rect(Rect2(at, Vector2(3, 3)), Color("132f3b"))
		control.draw_rect(Rect2(at, Vector2(2, 2)), Color("aa9875"))
		control.draw_rect(Rect2(at, Vector2.ONE), Color("e2d4af"))


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
	var vibration := Button.new()
	vibration.name = "vibration"
	vibration.toggle_mode = true
	vibration.custom_minimum_size.y = 48
	vibration.set_pressed_no_signal(profile.vibration)
	vibration.text = "Виброотклик: Вкл" if profile.vibration else "Виброотклик: Выкл"
	vibration.toggled.connect(func(enabled: bool):
		profile.vibration = enabled
		vibration.text = "Виброотклик: Вкл" if enabled else "Виброотклик: Выкл"
		profile.save_profile()
		if enabled:
			sound.preview_vibration())
	parent.add_child(vibration)
	vibration.draw.connect(_workshop_trim.bind(vibration))
	buttons["vibration"] = vibration

func _build_hud() -> void:
	var plate := Panel.new()
	plate.position = Vector2(14, 10)
	plate.size = Vector2(124, 46)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", theme.get_stylebox("normal", "Button"))
	ui.add_child(plate)
	plate.draw.connect(_workshop_trim.bind(plate))
	score_label = Label.new()
	score_label.position = Vector2(24, 14)
	score_label.size = Vector2(104, 36)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_update_hud_score()
	ui.add_child(score_label)
	boots_count = EQUIPMENT_VIEW.build_hud(ui, "boots")
	helmet_count = EQUIPMENT_VIEW.build_hud(ui, "helmet")
	gloves_count = EQUIPMENT_VIEW.build_hud(ui, "gloves")
	EQUIPMENT_VIEW.update_hud(boots_count, helmet_count, gloves_count, model)
	if screen == "equipment":
		return
	var pause := _button(ui, "II", "pause", _pause)
	pause.text = ""
	pause.icon = preload("res://art/pause_icon.png")
	pause.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause.expand_icon = true
	pause.focus_mode = Control.FOCUS_NONE
	pause.size = Vector2(48, 48)
	pause.custom_minimum_size.y = 48
	pause.position = Vector2(size.x - 66, 10)


func _update_hud_score() -> void:
	var value := "%06d" % model.score
	if score_label.text == value:
		return
	score_label.text = value
	var font_size := 25
	while font_size > 12 and theme.default_font.get_string_size(score_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > 100:
		font_size -= 1
	score_label.add_theme_font_size_override("font_size", font_size)


func _start_game() -> void:
	qa_hero_pose = false
	qa_crane_preview = false
	qa_crane_releases.clear()
	qa_helmet_hits.clear()
	qa_gloves_pulls.clear()
	qa_animation_held = false
	crush_elapsed = -1.0
	session += 1
	model = StackSimulation.new(TUNING, Time.get_ticks_usec())
	model.equipment_enabled = true
	world.model = model
	world.caption_life = 0.0
	world.boots_exhaust_life = 0.0
	world.helmet_impacts.clear()
	world.gloves_break_life = 0.0
	world._layout()
	result_saved = false
	_show_screen("playing")


func _pause() -> void:
	if screen == "playing":
		_show_screen("paused")


func _resolve_equipment(item: String, offer: PanelContainer) -> void:
	if screen != "equipment" or panel != offer:
		return
	model.resolve_equipment(item)
	_show_screen("equipment" if model.equipment_pending else "playing")


func _record_result() -> void:
	if not result_saved:
		result_saved = true
		profile.add_match(model.match_result(Time.get_datetime_string_from_system()))


func _end_game() -> void:
	_record_result()
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
	jump_pointers.clear()
	pull_pointers.clear()
	jump_pending = false
	pull_key_held = false
	if model != null:
		model.release_pull_input()
	if world != null:
		world.pressed_actions.clear()
		world.axis = 0.0


func _pull_held() -> bool:
	return model != null and model.gloves_charges > 0 and (pull_key_held or pull_pointers.values().has(true))


func _input(event: InputEvent) -> void:
	if sound != null and ((event is InputEventMouseButton and event.pressed) or
		(event is InputEventScreenTouch and event.pressed) or (event is InputEventKey and event.pressed)):
		sound.unlock()
	if screen == "paused" and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		_show_screen("playing")
		get_viewport().set_input_as_handled()
		return
	if screen == "equipment" and event is InputEventKey and event.echo:
		get_viewport().set_input_as_handled()
		return
	if screen != "playing":
		return
	if event is InputEventKey and event.physical_keycode == KEY_G and crush_elapsed < 0.0:
		if not event.echo:
			pull_key_held = event.pressed and model.gloves_charges > 0
			if pull_key_held:
				jump_pending = false
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			_pause()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode in [KEY_SPACE, KEY_UP] and crush_elapsed < 0.0:
			jump_pending = not _pull_held() and not model.is_pulling()
			get_viewport().set_input_as_handled()
	elif crush_elapsed >= 0.0:
		return
	elif event is InputEventScreenTouch:
		_pointer(event.index, event.position, event.pressed, event.pressed)
	elif event is InputEventScreenDrag and (pointers.has(event.index) or pull_pointers.has(event.index)):
		_pointer(event.index, event.position, true)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var real_press: bool = event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION
		_pointer(-1, event.position, event.pressed, real_press)
	elif event is InputEventMouseMotion and (pointers.has(-1) or pull_pointers.has(-1)):
		_pointer(-1, event.position, true)


func _pointer(id: int, position: Vector2, down: bool, just_pressed: bool = false) -> void:
	if not down:
		jump_pointers.erase(id)
		var was_pulling := pull_pointers.erase(id)
		if pointers.erase(id) or was_pulling:
			get_viewport().set_input_as_handled()
		return
	var pull_control: Rect2 = world.controls.get("grab", Rect2())
	var on_pull := pull_control.has_point(position)
	if just_pressed and on_pull:
		pull_pointers[id] = true
		pointers.erase(id)
		jump_pending = false
	if pull_pointers.has(id):
		pull_pointers[id] = on_pull
		get_viewport().set_input_as_handled()
		return
	var action := ""
	for candidate in world.controls:
		if candidate != "grab" and world.controls[candidate].has_point(position):
			action = candidate
			break
	if not action.is_empty():
		pointers[id] = action
		if action == "jump" and not jump_pointers.has(id):
			jump_pointers[id] = true
			if not _pull_held() and not model.is_pulling():
				jump_pending = true
		get_viewport().set_input_as_handled()
	elif pointers.has(id):
		pointers.erase(id)


func _advance_game(delta: float) -> void:
	if model == null or screen != "playing":
		return
	if crush_elapsed >= 0.0:
		crush_elapsed = minf(crush_elapsed + delta, CRUSH_ANIMATION_TIME)
		if crush_elapsed >= CRUSH_ANIMATION_TIME:
			_end_game()
		return
	var actions: Array[String] = []
	for action in pointers.values():
		if not actions.has(action):
			actions.append(action)
	var axis := float(Input.is_physical_key_pressed(KEY_RIGHT) or actions.has("right")) - float(
		Input.is_physical_key_pressed(KEY_LEFT) or actions.has("left"))
	var pull_held := _pull_held()
	var pulling := pull_held or model.is_pulling()
	if pulling:
		actions.clear()
	if pull_held:
		actions.append("grab")
	world.pressed_actions = actions
	world.axis = 0.0 if pulling else axis
	model.advance(delta, axis, jump_pending, pull_held)
	jump_pending = false
	for event in model.events:
		match event.type:
			"jump": sound.effect("jump")
			"air_jump":
				sound.effect("jump")
				world.boots_jump_effect()
			"helmet_hit":
				sound.effect("helmet_break" if event.helmet_broke else "helmet_hit")
				world.helmet_hit(event)
				if qa_enabled:
					qa_helmet_hits.append(event)
					if qa_helmet_hits.size() > 24:
						qa_helmet_hits.pop_front()
			"gloves_pull":
				sound.effect("gloves_tear" if event.gloves_broke else "gloves_pull")
				if event.gloves_broke:
					world.gloves_break(event)
					world._layout()
				if qa_enabled:
					qa_gloves_pulls.append(event)
					if qa_gloves_pulls.size() > 24:
						qa_gloves_pulls.pop_front()
			"land": sound.effect("land")
			"drop":
				if qa_enabled:
					qa_crane_releases.append({"crane": event.crane, "column": event.column,
						"crate_id": event.crate_id, "tick": event.tick})
					if qa_crane_releases.size() > 24:
						qa_crane_releases.pop_front()
			"line":
				sound.effect("line")
				world.line_effect(int(event.chain))
			"over":
				sound.effect("over")
				if event.reason == "crushed":
					_record_result()
					_release_controls()
					crush_elapsed = 0.0
				else:
					_end_game()
	if screen == "playing" and model.equipment_pending:
		_show_screen("equipment")
		return
	if score_label != null:
		_update_hud_score()
		EQUIPMENT_VIEW.update_hud(boots_count, helmet_count, gloves_count, model)


func _background_demo() -> bool:
	return screen in ["menu", "settings", "statistics"] or (qa_enabled and qa_result_demo and screen == "over")


func _advance_demo(delta: float) -> void:
	if not _background_demo() or qa_freeze_demo:
		return
	demo.advance(delta)
	world.model = demo.model
	world.axis = demo.axis
	for event in demo.events:
		match event.type:
			"jump", "land", "over": sound.effect(str(event.type), false)
			"line":
				sound.effect("line", false)
				world.line_effect(int(event.chain))


func _update_crush_view() -> void:
	var elapsed := crush_elapsed
	if _background_demo():
		elapsed = demo.over_elapsed if demo.model.state == "over" and demo.model.loss_reason == "crushed" else -1.0
	world.crush_progress = minf(elapsed / CRUSH_ANIMATION_TIME, 1.0) if elapsed >= 0.0 else -1.0


func _process(delta: float) -> void:
	if world == null:
		return
	_advance_demo(delta)
	if not (qa_enabled and (qa_hero_pose or qa_animation_held)):
		_advance_game(delta)
	_update_crush_view()
	var frozen := screen in ["paused", "equipment"] or (qa_enabled and (qa_hero_pose or qa_freeze_demo or qa_animation_held))
	world.animate(0.0 if frozen else delta)
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
	var button_modes := {}
	for id in buttons:
		button_modes[id] = buttons[id].get_draw_mode()
	var vibration_styles := {}
	if buttons.has("vibration"):
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			vibration_styles[state] = buttons.vibration.get_theme_stylebox(state).bg_color.a
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
	var visible_crates := []
	var retiring_ids := []
	for crate in world.model.crates:
		visible_crates.append({"id": crate.id, "x": crate.x, "y": crate.y, "color": crate.color})
		if world.model.is_clearing_crate(int(crate.id)):
			retiring_ids.append(crate.id)
	var cranes := []
	var trolleys := []
	for index in range(world.model.cranes.size()):
		var crane: Dictionary = world.model.cranes[index]
		cranes.append({"x": crane.x, "direction": crane.direction, "loaded": crane.loaded,
			"waiting": crane.waiting, "wait_remaining": crane.wait_remaining,
			"release_column": crane.release_column, "open_time": crane.open_time})
		var trolley := world.crane_trolley_center(index)
		trolleys.append([trolley.x, trolley.y])
	var rail := world.crane_rail
	var status := {"ready": true, "screen": screen, "score": model.score,
		"lines": model.lines, "cleared_crates": model.cleared_crates, "loss_reason": model.loss_reason,
		"session": session, "ticks": model.ticks, "state": model.state,
		"animation_held": qa_animation_held,
		"jump_pending": jump_pending, "pull_held": _pull_held(), "pull_in_progress": model.is_pulling(),
		"equipment_rows": model.equipment_rows, "equipment_pending": model.equipment_pending,
		"equipment_options": model.equipment_options() if model.equipment_pending else [],
		"boots_equipped": model.boots_equipped, "boots_charges": model.boots_charges,
		"boots_hud": _gear_hud_snapshot(boots_count),
		"helmet_charges": model.helmet_charges, "helmet_hud": _gear_hud_snapshot(helmet_count),
		"helmet_hits": qa_helmet_hits,
		"gloves_charges": model.gloves_charges, "gloves_hud": _gear_hud_snapshot(gloves_count),
		"grabbed_crate_id": model.grabbed_crate_id, "gloves_pulls": qa_gloves_pulls,
		"clear_animation": {"phase": world.clear_animation_phase(), "elapsed": world.model.clear_elapsed, "ids": retiring_ids},
		"crush_animation": {"active": screen in ["playing", "paused"] and crush_elapsed >= 0.0,
			"progress": world.crush_progress, "impact_crate": world.model.impact_crate_id},
		"active_duration_ms": roundi(model.ticks * StackSimulation.STEP * 1000.0),
		"player": [model.player.x, model.player.y], "grounded": model.grounded,
		"player_velocity": [model.player_velocity.x, model.player_velocity.y],
		"player_size": [TUNING.player_width, TUNING.player_height],
		"facing": model.facing, "hero_pose": qa_hero_pose, "hero_frame": world.hero_frame(),
		"columns": model.tuning.columns, "rows": model.tuning.rows, "crates": model.crates.size(), "first_crate_x": model.crates[0].x if not model.crates.is_empty() else -1,
		"layout": "landscape" if size.x > size.y else "portrait", "viewport": [size.x, size.y],
		"field": [world.field.position.x, world.field.position.y, world.field.size.x, world.field.size.y], "visible_crates": visible_crates,
		"cranes": cranes, "crane_releases": qa_crane_releases, "crane_preview": qa_crane_preview,
		"crane_rail": [rail.position.x, rail.position.y, rail.size.x, rail.size.y], "crane_trolleys": trolleys,
		"crane_settings": {"speed": TUNING.crane_speed, "wait_min": TUNING.crane_wait_min,
			"wait_max": TUNING.crane_wait_max, "margin": StackSimulation.CRANE_EDGE_MARGIN},
		"buttons": rects, "sliders": slider_rects, "controls": input_rects,
		"missing_menu_glyphs": _missing_menu_glyphs(),
		"panel": _panel_snapshot(),
		"button_modes": button_modes,
		"vibration_styles": vibration_styles,
		"demo": {"active": _background_demo(), "rounds": demo.rounds, "ticks": demo.total_ticks,
			"jumps": demo.jumps, "drops": demo.drops, "lines": demo.lines, "losses": demo.losses,
			"player": [demo.model.player.x, demo.model.player.y], "facing": demo.model.facing,
			"state": demo.model.state,
			"separate_model": demo.model != model},
		"profile": {"music": profile.music, "effects": profile.effects,
			"matches": profile.matches, "statistics": profile.statistics(), "records": profile.records,
			"vibration": profile.vibration, "vibration_visible": buttons.has("vibration")},
		"statistics_view": {"first_match": first_match, "expanded_match": expanded_match,
			"preview": qa_statistics_preview != null},
		"audio": {"music_playing": sound.music_player.playing, "music_position": sound.music_player.get_playback_position(), "stream_format": sound.music_player.stream.format, "loop_end": sound.music_player.stream.loop_end, "unlocked": sound.unlocked,
			"music_muted": AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")),
			"effects_muted": AudioServer.is_bus_mute(AudioServer.get_bus_index("Effects"))}}
	JavaScriptBridge.eval("window.stackAttackState = " + JSON.stringify(status))


func _gear_hud_snapshot(count: Label) -> Dictionary:
	if count == null or not count.is_visible_in_tree():
		return {}
	var plate := count.get_parent().get_parent() as Control
	var bounds := plate.get_global_rect()
	return {"text": count.text, "rect": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]}


func _missing_menu_glyphs() -> String:
	var missing := ""
	if screen in ["menu", "statistics", "equipment", "paused"]:
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
				"text": str(control.text) if control is Label or control is Button else "",
				"alignment": control.horizontal_alignment if control is Label else -1,
				"font_size": control.get_theme_font_size("font_size") if control is Label else 0,
				"styles": _button_style_snapshot(control),
				"focusable": control.focus_mode == Control.FOCUS_ALL})
	var focused := get_viewport().gui_get_focus_owner()
	return {"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "items": items,
		"scroll_containers": panel.find_children("*", "ScrollContainer", true, false).size(),
		"focus": str(focused.name) if focused != null else ""}


func _button_style_snapshot(control: Control) -> Dictionary:
	var styles := {}
	if control is Button:
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			var style: StyleBoxFlat = control.get_theme_stylebox(state)
			styles[state] = {"alpha": style.bg_color.a, "border": style.border_width_left,
				"fill": style.bg_color.to_html(true), "edge": style.border_color.to_html(true),
				"radius": style.corner_radius_top_left, "margin": style.content_margin_left}
	return styles


func _qa_show_statistics() -> void:
	qa_statistics_preview = StackProfile.new(profile.path + ".qa-preview")
	qa_statistics_preview.matches.clear()
	qa_statistics_preview.records.assign([{"date": "12.11.2026", "score": 1600}])
	var results := [
		["2026-11-15T21:47:26", 142800, 14, 4, "overflow"],
		["2026-11-15T21:40:11", 93150, 9, 3, "crushed"],
		["2026-11-15T21:35:59", 69600, 5, 2, "crushed"],
		["2026-11-15T21:30:07", 55800, 6, 2, "overflow"],
		["2026-11-15T21:25:41", 46833, 2, 1, "crushed"],
		["2026-11-15T21:18:33", 76267, 8, 2, "overflow"],
		["2026-11-15T21:12:36", 20942, 0, 0, "crushed"],
	]
	for result in results:
		qa_statistics_preview.matches.append({"ended_at": result[0], "duration_ms": result[1],
			"score": result[2] * 100, "lines": result[2], "crates": result[2] * TUNING.columns,
			"best_combo": result[3], "reason": result[4]})
	_open_statistics()


func _qa_command() -> void:
	# Deliberate opt-in on debug Web exports only. No gameplay UI exposes fixtures.
	var raw: Variant = JavaScriptBridge.eval("JSON.stringify(window.stackAttackQARequest || null)")
	if raw == null or str(raw) == "null":
		return
	JavaScriptBridge.eval("window.stackAttackQARequest = null")
	var request: Variant = JSON.parse_string(str(raw))
	if not request is Dictionary:
		return
	if str(request.get("scenario", "")) == "animation_step":
		qa_animation_held = bool(request.get("animation_hold", qa_animation_held))
		if qa_animation_held:
			for frame in range(clampi(int(request.get("frames", 0)), 0, 180)):
				if screen != "playing":
					break
				_advance_game(StackSimulation.STEP)
				world.animate(StackSimulation.STEP)
		_update_crush_view()
		return
	if str(request.get("scenario", "")) == "crate_appearance" and screen in ["menu", "playing"]:
		var target := demo.model if screen == "menu" else model
		target.cancel_grab()
		target.crates.clear()
		target.state = "playing"
		var player_x := clampf(float(request.get("player_x", 8.4)), 0.0, TUNING.columns - TUNING.player_width)
		target.player = Vector2(player_x, TUNING.rows - TUNING.player_height)
		target.player_velocity = Vector2.ZERO
		target.grounded = true
		target.facing = -1 if int(request.get("facing", target.facing)) < 0 else 1
		for index in range(3):
			var crate := target.add_crate(float(1 + index * 3), 2.0)
			crate.color = index
		qa_freeze_demo = screen == "menu"
		qa_hero_pose = screen == "playing"
		world.axis = 0.0
		return
	if str(request.get("scenario", "")) == "result_preview" and screen in ["menu", "over"]:
		model.score = clampi(int(request.get("score", 0)), 0, 100000000)
		model.state = "over"
		qa_result_demo = true
		_show_screen("over")
		return
	if str(request.get("scenario", "")) == "android_settings" and _background_demo():
		qa_android_settings = true
		qa_freeze_demo = true
		_show_screen("settings")
		return
	if str(request.get("scenario", "")) == "demo_crush" and _background_demo():
		demo.model.state = "playing"
		demo.model.crates.clear()
		demo.model.add_crate(floorf(demo.model.player.x), demo.model.player.y - 1.01, 6.0)
		return
	if str(request.get("scenario", "")) == "statistics_menu" and screen in ["menu", "statistics"]:
		_qa_show_statistics()
		return
	if screen != "playing":
		return
	if str(request.get("scenario", "")) in ["helmet_board", "gloves_board"]:
		if crush_elapsed < 0.0:
			_qa_set_test_board(request)
		return
	if str(request.get("scenario", "")) in ["boots_rows", "boots_jump"]:
		var count := clampi(int(request.get("count", 1)), 1, 6) if request.scenario == "boots_rows" else 0
		_qa_set_equipment_board(count, bool(request.get("animation_hold", false)))
		return
	if str(request.get("scenario", "")) == "cranes":
		# Reset a real simulation and start the first routes at known positions for capture.
		qa_hero_pose = false
		qa_crane_preview = true
		qa_animation_held = false
		qa_crane_releases.clear()
		_release_controls()
		model.reset(7481)
		model.player.x = 4.3
		model.cranes[0].x = -0.75
		model.cranes[1].x = TUNING.columns + 0.75
		model.cranes[0].release_column = 7
		model.cranes[1].release_column = 1
		world.caption_life = 0.0
		return
	if str(request.get("scenario", "")) == "hero_pose":
		var pose := str(request.get("pose", "idle"))
		if pose not in ["idle", "walk_stride", "walk_recover", "jump", "push"]:
			return
		qa_hero_pose = true
		model.cancel_grab()
		model.crates.clear()
		model.player = Vector2(4.3, TUNING.rows - TUNING.player_height)
		model.player_velocity = Vector2.ZERO
		model.grounded = pose != "jump"
		model.facing = -1 if int(request.get("facing", 1)) < 0 else 1
		world.axis = 0.0 if pose in ["idle", "jump"] else float(model.facing)
		model.boots_equipped = bool(request.get("boots", false))
		model.boots_charges = StackSimulation.BOOTS_MAX_CHARGES if model.boots_equipped else 0
		world.boots_exhaust_life = 0.0
		EQUIPMENT_VIEW.update_hud(boots_count, helmet_count, gloves_count, model)
		if pose == "push":
			model.add_crate(model.player.x + TUNING.player_width if model.facing > 0 else model.player.x - 1, float(TUNING.rows - 1))
		world.clock = 0.15 if pose == "walk_recover" else 0.0
		world.caption_life = 0.0
		return
	if str(request.get("scenario", "")) not in ["line", "chain", "crush", "overflow", "push", "showcase"]:
		return
	qa_hero_pose = false
	qa_crane_preview = false
	qa_animation_held = bool(request.get("animation_hold", false))
	model.cancel_grab()
	model.crates.clear()
	model.cranes_enabled = false
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
			model.cranes[0].x = 3.5
			model.cranes[1].x = 6.5


func _qa_prepare_equipment_board(hold: bool) -> void:
	qa_hero_pose = false
	qa_crane_preview = false
	qa_animation_held = hold
	qa_helmet_hits.clear()
	qa_gloves_pulls.clear()
	world.caption_life = 0.0
	world.boots_exhaust_life = 0.0
	world.helmet_impacts.clear()
	world.gloves_break_life = 0.0
	_release_controls()
	model.cancel_grab()
	model.crates.clear()
	model.cranes_enabled = false
	model.cranes[0].x = 2.5
	model.cranes[1].x = 7.5
	model.player = Vector2(4.3, TUNING.rows - TUNING.player_height)
	model.player_velocity = Vector2.ZERO
	model.grounded = true
	model.state = "playing"
	model.chain = 0
	model.accumulator = 0.0


func _qa_set_equipment_board(row_count: int, hold: bool) -> void:
	_qa_prepare_equipment_board(hold)
	model.player.y -= row_count
	for row in range(row_count):
		for column in range(TUNING.columns):
			model.add_crate(float(column), float(TUNING.rows - 1 - row))
	var stacks := [[0, 1, 2, 7, 8, 9], [0, 1, 8, 9], [0, 9]]
	for row in range(stacks.size()):
		for column in stacks[row]:
			model.add_crate(float(column), float(TUNING.rows - 1 - row_count - row))


func _qa_set_test_board(request: Dictionary) -> void:
	_qa_prepare_equipment_board(bool(request.get("animation_hold", false)))
	var floor_y := TUNING.rows - TUNING.player_height
	var spawn: Variant = request.get("player", [])
	if spawn is Array and spawn.size() == 2:
		model.player = Vector2(clampf(float(spawn[0]), 0.0, TUNING.columns - TUNING.player_width),
			clampf(float(spawn[1]), -1.0, floor_y))
	var velocity: Variant = request.get("velocity", [])
	if velocity is Array and velocity.size() == 2:
		model.player_velocity = Vector2(clampf(float(velocity[0]), -TUNING.player_speed, TUNING.player_speed),
			clampf(float(velocity[1]), -TUNING.jump_speed, 12.0))
	model.grounded = is_equal_approx(model.player.y, floor_y) and is_zero_approx(model.player_velocity.y)
	model.facing = -1 if int(request.get("facing", model.facing)) < 0 else 1
	var crates: Variant = request.get("crates", [])
	if crates is Array:
		for placement in crates.slice(0, 48):
			if placement is Array and placement.size() == 3:
				model.add_crate(clampf(float(placement[0]), 0.0, TUNING.columns - 1.0),
					clampf(float(placement[1]), -1.0, TUNING.rows - 1.0),
					clampf(float(placement[2]), -TUNING.crate_fall_speed, TUNING.crate_fall_speed))
