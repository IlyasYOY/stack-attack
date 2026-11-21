extends Control
const TUNING: StackTuning = preload("res://game/prototype.tres")
const STATISTICS_VIEW = preload("res://game/statistics_view.gd")
const EQUIPMENT_VIEW = preload("res://game/equipment_view.gd")
const CRUSH_ANIMATION_TIME := 0.42
const SPRING_METER_FLASH_TIME := 0.18
const MENU_IDLE_MS := 30_000
const MENU_FADE_MS := 500
var model: StackSimulation
var demo: StackDemo
var profile: StackProfile
var sound: StackSound
var world: StackWorldView
var ui: Control
var screen := ""
var menu_last_input_ms := 0
var menu_opacity := 1.0
var wake_key := KEY_NONE
var wake_mouse_button := MOUSE_BUTTON_NONE
var wake_touch := -1
var wake_emulated_mouse := false
var buttons := {}
var sliders := {}
var panel: PanelContainer
var score_label: Label
var keyboard_input := false
var pickup_button: Button
var found_label: Label
var gear_counts := {}
var pointers := {}
var jump_keys := {}
var jump_pointers := {}
var pull_pointers := {}
var mallet_pointers := {}
var head_pointers := {}
var shot_pointers := {}
var shot_pending := false
var head_action_pending := false
var frame_time_usec := 0
var qa_release_events: Array[Dictionary] = []
var speed_pointers := {}
var speed_keys := {}
var jump_pending := false
var mallet_pending := false
var lamp_pending := false
var head_key_held := false
var spring_meter_peak := 0
var spring_meter_limit := 0
var spring_meter_flash := 0.0
var pull_key_held := false
var slide_active := false
var slide_focused := true
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
var qa_mallet_events: Array[Dictionary] = []
var qa_bonus_events: Array[Dictionary] = []
var qa_animation_held := false
const CREAM := Color("f4e3ba")
const MINT := Color("8dc6ac")
const GOLD := Color("d7a45a")


func _ready() -> void:
	keyboard_input = not DisplayServer.is_touchscreen_available()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if OS.has_feature("web") and OS.is_debug_build():
		qa_enabled = bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('qa') === '1'"))
	var profile_path := StackProfile.SAVE_PATH + ".qa" if qa_enabled else StackProfile.SAVE_PATH
	profile = StackProfile.new(profile_path)
	_apply_language()
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
	gear_counts.clear()


func _show_screen(value: String, focus_name := "") -> void:
	if value != "over":
		qa_result_demo = false
	if value != "statistics":
		qa_statistics_preview = null
	var previous_focus := get_viewport().gui_get_focus_owner()
	if focus_name.is_empty() and previous_focus != null:
		focus_name = str(previous_focus.name)
	if value != screen:
		menu_last_input_ms = Time.get_ticks_msec()
		menu_opacity = 1.0
		_clear_wake_input()
	screen = value
	theme = _make_theme()
	_release_controls()
	_clear_ui()
	world.keyboard_hints = keyboard_input and screen == "playing"
	world.active = screen in ["playing", "paused"]
	world.model = demo.model if _background_demo() else model
	world._layout()
	sound.music_player.volume_db = -5.0 if screen == "paused" else 0.0
	for item in EQUIPMENT_VIEW.ICONS:
		gear_counts[item] = EQUIPMENT_VIEW.build_hud(ui, item)
	EQUIPMENT_VIEW.update_hud(gear_counts, world)
	if world.active:
		_build_hud()
	if screen == "playing":
		return
	var content := _make_panel()
	match screen:
		"menu":
			_heading(content, "Stack Attack", 32)
			_button(content, tr("Play"), "play", _start_game)
			_button(content, tr("Statistics"), "statistics", _open_statistics)
			_button(content, tr("Settings"), "settings", func(): _show_screen("settings"))
			_apply_menu_opacity()
		"paused":
			_heading(content, tr("Pause"))
			EQUIPMENT_VIEW.build_pause(panel, content, _compact_panel(), model, _text)
			_button(content, tr("Resume"), "resume", func(): _show_screen("playing"))
			_button(content, tr("Restart"), "restart", _start_game)
			_button(content, tr("Main menu"), "home", func(): _show_screen("menu"))
		"over":
			_heading(content, tr("Shift over"))
			_result_score(content)
			if model.loss_reason in ["metal_crushed", "trap", "mechanic"]:
				_text(content, STATISTICS_VIEW.loss_description(model.loss_reason), 14, MINT)
			_button(content, tr("Play again"), "again", _start_game)
			_button(content, tr("Main menu"), "home", func(): _show_screen("menu"))
			if not profile.last_error.is_empty():
				_text(content, tr(profile.last_error), 12)
		"statistics":
			var display_profile := qa_statistics_preview if qa_statistics_preview != null else profile
			var margins := panel.get_theme_stylebox("panel").get_minimum_size()
			var available := Vector2(_panel_width(), size.y - 12) - margins
			STATISTICS_VIEW.build(content, available, display_profile.statistics(), display_profile.matches,
				display_profile.records, first_match, expanded_match, _button, _text, _change_statistics,
				func(): _show_screen("menu"))
		"settings":
			_heading(content, tr("Settings"))
			if _compact_panel():
				var row := HBoxContainer.new()
				content.add_child(row)
				_slider(_column(row), tr("Music"), "music", profile.music)
				_slider(_column(row), tr("Sound"), "effects", profile.effects)
			else:
				_slider(content, tr("Music"), "music", profile.music)
				_slider(content, tr("Sound"), "effects", profile.effects)
			_language_option(content)
			if OS.has_feature("android") or (qa_enabled and qa_android_settings):
				_vibration_option(content)
			_button(content, tr("Back"), "back", func(): _show_screen("menu"))
		"language":
			_heading(content, tr("Language"))
			for code: String in StackProfile.LANGUAGES:
				var option := _button(content, _language_name(code), code, _select_language.bind(code))
				option.toggle_mode = true
				option.set_pressed_no_signal(code == profile.language)
			_button(content, tr("Back"), "back", func(): _show_screen("settings", "language"))
	_position_panel()
	_focus_panel.call_deferred(panel, focus_name)


func _apply_language() -> void:
	var locale := OS.get_locale()
	if OS.has_feature("web"):
		locale = str(JavaScriptBridge.get_interface("navigator").language)
	TranslationServer.set_locale(StackProfile.resolve_locale(profile.language, locale))
	if OS.has_feature("web"):
		var document := JavaScriptBridge.get_interface("document")
		document.documentElement.lang = TranslationServer.get_locale()
		document.title = "Stack Attack"


func _language_option(content: Control) -> void:
	var language := _button(content, tr("Language · %s") % _language_name(profile.language),
		"language", func(): _show_screen("language", profile.language))
	var room := _panel_width() - panel.get_theme_stylebox("panel").get_minimum_size().x
	room -= language.get_theme_stylebox("normal").get_minimum_size().x
	var font_size := language.get_theme_font_size("font_size")
	while font_size > 12 and theme.default_font.get_string_size(language.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > room:
		font_size -= 1
	language.add_theme_font_size_override("font_size", font_size)


func _language_name(code: String) -> String:
	match code:
		"en": return "English"
		"ru": return "Русский"
		"es": return "Español"
	return tr("System default")


func _select_language(code: String) -> void:
	profile.language = code
	if profile.save_profile() and OS.has_feature("web"):
		JavaScriptBridge.force_fs_sync()
	_apply_language()
	_show_screen("settings", "language")


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
	if _short_strip_panel():
		var frame := _make_style(Color.TRANSPARENT, Color.TRANSPARENT, 2)
		frame.set_border_width_all(0)
		panel.add_theme_stylebox_override("panel", frame)
		content.add_theme_constant_override("separation", 2)
	return content


func _short_strip_panel() -> bool:
	return screen in ["menu", "over"] and world.equipment_strip.has_area() and world.equipment_strip.position.y < 248


func _position_panel() -> void:
	if panel != null:
		panel.size = Vector2(_panel_width(), panel.get_combined_minimum_size().y)
		_center_panel()


func _panel_area() -> Rect2:
	if screen in ["menu", "over"]:
		var minimum_width := 300 if _short_strip_panel() else 230
		var width := minf(size.x - 12, maxf(minimum_width, world.field.size.x * 0.90))
		var center := world.field.get_center()
		return Rect2(center - Vector2(width * 0.5, world.field.size.y * 0.5), Vector2(width, world.field.size.y))
	return Rect2(Vector2.ZERO, size)


func _panel_width() -> float:
	if screen == "paused":
		return minf(360, size.x - 32)
	var margin := 16 if screen in ["menu", "over"] else 32
	var max_width := 720 if _wide_panel() and screen != "menu" else 440
	return minf(max_width, _panel_area().size.x - margin)


func _result_score(parent: Control) -> void:
	var label := _text(parent, tr("Score: %d") % model.score, 32 if _compact_panel() else 44, GOLD)
	label.name = "result_score"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	var available := _panel_width() - panel.get_theme_stylebox("panel").get_minimum_size().x - 8
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	while font_size > 12 and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > available:
		font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)


func _center_panel() -> void:
	if panel != null:
		var centered := (_panel_area().get_center() - panel.size * 0.5).floor()
		if screen in ["menu", "over"]:
			var bottom := world.field.end.y - world.cell
			if world.equipment_strip.has_area():
				bottom = minf(bottom, world.equipment_strip.position.y - 4)
			centered.y = minf(centered.y, bottom - panel.size.y)
		centered.y = maxf(centered.y, 0.0)
		var below_hud := StackWorldView.HUD_CLEARANCE_Y
		if screen == "paused" and size.y - panel.size.y >= below_hud + 6.0:
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
	slider.accessibility_name = title
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
	vibration.text = tr("Vibration: On") if profile.vibration else tr("Vibration: Off")
	vibration.toggled.connect(func(enabled: bool):
		profile.vibration = enabled
		vibration.text = tr("Vibration: On") if enabled else tr("Vibration: Off")
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
	if screen == "playing":
		pickup_button = EQUIPMENT_VIEW.build_swap(ui, func():
			sound.unlock()
			sound.effect("click")
			_pick_up())
		buttons.pickup = pickup_button
		found_label = _text(ui, "", 14, CREAM)
		found_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		found_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_update_pickup()
	var pause := _button(ui, "II", "pause", _pause)
	pause.text = ""
	pause.accessibility_name = tr("Pause")
	pause.icon = preload("res://art/pause_icon.png")
	pause.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause.expand_icon = true
	pause.focus_mode = Control.FOCUS_NONE
	pause.size = Vector2(48, 48)
	pause.custom_minimum_size.y = 48
	pause.position = Vector2(size.x - 66, 10)


func _pick_up() -> void:
	if screen == "playing" and crush_elapsed < 0.0:
		if model.pick_up_nearest() in StackSimulation.SLOTS.feet:
			_release_speed_input()
		EQUIPMENT_VIEW.update_hud(gear_counts, world)
		_update_pickup()
		world._layout()


func _update_pickup() -> void:
	var item := model.nearest_item()
	pickup_button.visible = not item.is_empty()
	found_label.visible = pickup_button.visible
	if item.is_empty():
		return
	var kind := str(item.kind)
	var show_key := world.keyboard_hints and model.can_pick_up_item(item)
	EQUIPMENT_VIEW.set_action_key(pickup_button, "E" if show_key else "")
	var body := world.equipment_body
	if world.equipment_strip.has_area():
		var slot := world.strip_slot(kind)
		pickup_button.position = Vector2(slot.end.x - StackWorldView.SWAP_SIZE, slot.position.y).round()
		found_label.position = world.equipment_strip.position + Vector2(4, StackWorldView.SWAP_SIZE + 3)
		found_label.size = Vector2(body.position.x - found_label.position.x - 5, 0)
	else:
		pickup_button.position = Vector2(body.end.x + 3, world.slot_height(kind) - StackWorldView.SWAP_SIZE * 0.5).round()
		var name_x := body.position.x - StackWorldView.BADGE_WIDTH
		var label_width := body.end.x + 3 + StackWorldView.SWAP_SIZE - name_x
		found_label.position = Vector2(name_x, maxf(world.equipment_bottom() + 6, pickup_button.position.y + StackWorldView.SWAP_SIZE + 4))
		found_label.size = Vector2(label_width, 0)
	if pickup_button.get_meta("kind", "") != kind or pickup_button.get_meta("charges", -1) != item.charges:
		pickup_button.set_meta("kind", kind)
		pickup_button.set_meta("charges", item.charges)
		pickup_button.queue_redraw()
		found_label.text = tr(EQUIPMENT_VIEW.NAMES[kind])
	var equipped := model.equipped_in_slot(kind)
	var action := tr("Swap") if not equipped.is_empty() else tr("Pick up")
	pickup_button.tooltip_text = "%s%s · %s · %d" % [action, " (E)" if show_key else "", found_label.text, item.charges]
	pickup_button.accessibility_name = pickup_button.tooltip_text


func _update_hud_score() -> void:
	var value := "%06d" % model.score
	if score_label.text == value:
		return
	score_label.text = value
	score_label.accessibility_name = tr("Score: %d") % model.score
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
	qa_mallet_events.clear()
	qa_bonus_events.clear()
	qa_release_events.clear()
	qa_animation_held = false
	crush_elapsed = -1.0
	session += 1
	model = StackSimulation.new(TUNING, Time.get_ticks_usec())
	world.model = model
	world.caption_life = 0.0
	world.boots_exhaust_life = 0.0
	world.helmet_impacts.clear()
	world.gloves_break_life = 0.0
	world.reset_mallet_effects()
	world.reset_bonus_effects()
	world._layout()
	result_saved = false
	_show_screen("playing")


func _pause() -> void:
	if screen == "playing":
		_show_screen("paused")


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
	if screen == "playing" and not gear_counts.is_empty():
		EQUIPMENT_VIEW.update_hud(gear_counts, world)
		_update_pickup()
	if buttons.has("pause"):
		buttons.pause.position = Vector2(size.x - 66, 10)


func _release_controls() -> void:
	pointers.clear()
	jump_keys.clear()
	jump_pointers.clear()
	pull_pointers.clear()
	mallet_pointers.clear()
	head_pointers.clear()
	shot_pointers.clear()
	shot_pending = false
	head_action_pending = false
	_release_speed_input()
	jump_pending = false
	mallet_pending = false
	lamp_pending = false
	head_key_held = false
	spring_meter_peak = 0
	spring_meter_flash = 0.0
	pull_key_held = false
	_stop_crate_slide()
	if model != null:
		model.release_pull_input()
		model.cancel_mallet_swing()
		model.cancel_bonus_input()
	if world != null:
		world.pressed_actions.clear()
		world.axis = 0.0
		world.cancel_mallet_swing()


func _release_speed_input() -> void:
	speed_keys.clear()
	speed_pointers.clear()


func _stop_crate_slide() -> void:
	slide_active = false
	if sound != null:
		sound.stop_slide()


func _pull_held() -> bool:
	return model != null and model.gloves_charges > 0 and (pull_key_held or pull_pointers.values().has(true))


func _jump_held() -> bool:
	return not jump_keys.is_empty() or not jump_pointers.is_empty()


func _apply_menu_opacity() -> void:
	for button in buttons.values():
		button.modulate.a = menu_opacity


func _update_menu_idle() -> void:
	var elapsed := Time.get_ticks_msec() - menu_last_input_ms
	var opacity := clampf(1.0 - float(elapsed - MENU_IDLE_MS) / MENU_FADE_MS, 0.0, 1.0)
	if opacity != menu_opacity:
		menu_opacity = opacity
		_apply_menu_opacity()


func _clear_wake_input() -> void:
	wake_key = KEY_NONE
	wake_mouse_button = MOUSE_BUTTON_NONE
	wake_touch = -1
	wake_emulated_mouse = false


func _menu_input(event: InputEvent) -> bool:
	if not (event is InputEventKey or event is InputEventMouse or
			event is InputEventScreenTouch or event is InputEventScreenDrag):
		return false
	var waking := menu_opacity < 1.0
	menu_last_input_ms = Time.get_ticks_msec()
	if waking:
		menu_opacity = 1.0
		_apply_menu_opacity()

	if event is InputEventKey:
		if waking and event.pressed:
			wake_key = event.physical_keycode
		if wake_key != KEY_NONE and wake_key == event.physical_keycode:
			if not event.pressed:
				wake_key = KEY_NONE
			return true
	elif event is InputEventScreenTouch:
		# On Web the emulated left button can arrive before its source touch.
		if event.pressed and (waking or wake_emulated_mouse) and wake_touch < 0:
			wake_touch = event.index
		if event.index == wake_touch:
			if not event.pressed or event.canceled:
				wake_touch = -1
			return true
	elif event is InputEventScreenDrag:
		return waking or event.index == wake_touch
	elif event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION:
		var consume := waking or wake_emulated_mouse or wake_touch >= 0
		wake_emulated_mouse = consume and event.pressed and not event.canceled
		return consume
	elif event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
				MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			return waking
		if waking and event.pressed:
			wake_mouse_button = event.button_index
		if wake_mouse_button == event.button_index:
			if not event.pressed or event.canceled:
				wake_mouse_button = MOUSE_BUTTON_NONE
			return true
	return waking


func _track_hint_input(event: InputEvent) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	var keyboard := keyboard_input
	if event is InputEventKey and event.pressed:
		keyboard = true
	elif event is InputEventScreenTouch and event.pressed:
		keyboard = false
	if keyboard == keyboard_input:
		return
	keyboard_input = keyboard
	if screen == "playing":
		world.keyboard_hints = keyboard
		world.queue_redraw()
		EQUIPMENT_VIEW.update_hud(gear_counts, world, spring_meter_peak if spring_meter_flash > 0.0 else 0, spring_meter_limit)
		_update_pickup()


func _input(event: InputEvent) -> void:
	_track_hint_input(event)
	if sound != null and ((event is InputEventMouseButton and event.pressed) or
		(event is InputEventScreenTouch and event.pressed) or (event is InputEventKey and event.pressed)):
		sound.unlock()
	if screen == "menu" and _menu_input(event):
		get_viewport().set_input_as_handled()
		return
	if screen == "paused" and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		_show_screen("playing")
		get_viewport().set_input_as_handled()
		return
	if screen != "playing":
		return
	if event is InputEventKey and event.physical_keycode == KEY_E:
		if event.pressed and not event.echo:
			_pick_up()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.physical_keycode == KEY_G and crush_elapsed < 0.0:
		if not event.echo:
			pull_key_held = event.pressed and model.gloves_charges > 0
			if event.pressed and model.mallet_charges > 0:
				mallet_pending = true
			if event.pressed and model.slingshot_charges > 0:
				shot_pending = true
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.physical_keycode == KEY_SHIFT and crush_elapsed < 0.0:
		if not event.echo:
			if event.pressed and model.speed_boots_charges > 0:
				speed_keys[event.location] = true
			else:
				speed_keys.erase(event.location)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.physical_keycode == KEY_F and crush_elapsed < 0.0:
		if not event.echo:
			if event.pressed and not head_key_held:
				lamp_pending = model.lamp_helmet_charges > 0
				head_action_pending = model.engineer_goggles_charges > 0
			head_key_held = event.pressed
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.physical_keycode in [KEY_SPACE, KEY_UP] and crush_elapsed < 0.0:
		if not event.echo:
			if event.pressed:
				if not jump_keys.has(event.physical_keycode):
					jump_pending = true
				jump_keys[event.physical_keycode] = true
			else:
				jump_keys.erase(event.physical_keycode)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			_pause()
			get_viewport().set_input_as_handled()
	elif crush_elapsed >= 0.0:
		return
	elif event is InputEventScreenTouch:
		if event.canceled and jump_pointers.has(event.index) and jump_pointers.size() == 1 and jump_keys.is_empty():
			jump_pending = false
			model.cancel_jump_input()
		var down: bool = event.pressed and not event.canceled
		_pointer(event.index, event.position, down, down)
	elif event is InputEventScreenDrag and (pointers.has(event.index) or pull_pointers.has(event.index)
			or mallet_pointers.has(event.index) or head_pointers.has(event.index)
			or shot_pointers.has(event.index) or speed_pointers.has(event.index)):
		_pointer(event.index, event.position, true)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var real_press: bool = event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION
		_pointer(-1, event.position, event.pressed, real_press)
	elif event is InputEventMouseMotion and (pointers.has(-1) or pull_pointers.has(-1)
			or mallet_pointers.has(-1) or head_pointers.has(-1)
			or shot_pointers.has(-1) or speed_pointers.has(-1)):
		_pointer(-1, event.position, true)


func _pointer(id: int, position: Vector2, down: bool, just_pressed: bool = false) -> void:
	if not down:
		jump_pointers.erase(id)
		var was_pulling := pull_pointers.erase(id)
		var was_hitting := mallet_pointers.erase(id)
		var was_on_head := head_pointers.erase(id)
		var was_shooting := shot_pointers.erase(id)
		var was_running := speed_pointers.erase(id)
		if pointers.erase(id) or was_pulling or was_hitting or was_on_head or was_shooting or was_running:
			get_viewport().set_input_as_handled()
		return
	var speed_control: Rect2 = world.controls.get("speed", Rect2())
	if just_pressed and speed_control.has_point(position):
		speed_pointers[id] = true
	if speed_pointers.has(id):
		if not speed_control.has_point(position):
			speed_pointers.erase(id)
		get_viewport().set_input_as_handled()
		return
	var head_control: Rect2 = world.controls.get("watch_cap",
		world.controls.get("engineer_goggles", world.controls.get("lamp", Rect2())))
	var on_head := head_control.has_point(position)
	if just_pressed and on_head:
		head_pointers[id] = true
		lamp_pending = model.lamp_helmet_charges > 0
		head_action_pending = model.engineer_goggles_charges > 0
	if head_pointers.has(id):
		head_pointers[id] = on_head
		get_viewport().set_input_as_handled()
		return
	var shot_control: Rect2 = world.controls.get("slingshot", Rect2())
	var on_shot := shot_control.has_point(position)
	if just_pressed and on_shot:
		shot_pointers[id] = true
		shot_pending = true
	if shot_pointers.has(id):
		shot_pointers[id] = on_shot
		get_viewport().set_input_as_handled()
		return
	var mallet_control: Rect2 = world.controls.get("mallet", Rect2())
	var on_mallet := mallet_control.has_point(position)
	if just_pressed and on_mallet and model.mallet_charges > 0:
		mallet_pointers[id] = true
		mallet_pending = true
	if mallet_pointers.has(id):
		mallet_pointers[id] = on_mallet
		get_viewport().set_input_as_handled()
		return
	var pull_control: Rect2 = world.controls.get("grab", Rect2())
	var on_pull := pull_control.has_point(position)
	if just_pressed and on_pull:
		pull_pointers[id] = true
		pointers.erase(id)
	if pull_pointers.has(id):
		pull_pointers[id] = on_pull
		get_viewport().set_input_as_handled()
		return
	var action := ""
	for candidate in world.controls:
		if candidate in ["left", "right", "jump"] and world.controls[candidate].has_point(position):
			action = candidate
			break
	if not action.is_empty():
		pointers[id] = action
		if action == "jump" and not jump_pointers.has(id):
			jump_pointers[id] = true
			jump_pending = true
		get_viewport().set_input_as_handled()
	elif pointers.has(id):
		pointers.erase(id)


func _advance_game(delta: float, realtime: float = -1.0) -> bool:
	if model == null or screen != "playing":
		return false
	if crush_elapsed >= 0.0:
		crush_elapsed = minf(crush_elapsed + delta, CRUSH_ANIMATION_TIME)
		if crush_elapsed >= CRUSH_ANIMATION_TIME:
			_end_game()
		return false
	spring_meter_flash = maxf(0.0, spring_meter_flash - delta)
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
	if model.mallet_charges > 0 and (mallet_pointers.values().has(true) or Input.is_physical_key_pressed(KEY_G)):
		actions.append("mallet")
	var head_held := head_key_held or head_pointers.values().has(true)
	if head_held:
		for action in ["lamp", "engineer_goggles", "watch_cap"]:
			if world.controls.has(action):
				actions.append(action)
	if model.slingshot_charges > 0 and (shot_pointers.values().has(true) or shot_pending):
		actions.append("slingshot")
	var speed_held := not speed_keys.is_empty() or not speed_pointers.is_empty()
	if speed_held:
		actions.append("speed")
	world.pressed_actions = actions
	world.axis = 0.0 if pulling else axis
	model.advance(delta, axis, jump_pending, pull_held, mallet_pending,
		{"jump_held": _jump_held(), "lamp_pressed": lamp_pending, "speed_held": speed_held,
			"goggles_pressed": head_action_pending, "watch_held": head_held,
			"slingshot_pressed": shot_pending, "real_delta": delta if realtime < 0.0 else realtime})
	jump_pending = false
	mallet_pending = false
	lamp_pending = false
	head_action_pending = false
	shot_pending = false
	for event in model.events:
		_workshop_event(event)
		match event.type:
			"jump": sound.effect("jump")
			"air_jump":
				sound.effect("jump")
				world.boots_jump_effect()
				_record_bonus_event(event)
			"spring_jump":
				sound.effect("spring_jump_auto" if event.automatic else "spring_jump")
				world.spring_jump_effect(event)
				spring_meter_peak = int(event.stages)
				spring_meter_limit = int(event.limit)
				spring_meter_flash = SPRING_METER_FLASH_TIME
				_record_bonus_event(event)
			"lamp_reveal":
				sound.effect("lamp_reveal")
				if model.lamp_helmet_charges == 0:
					world._layout()
				_record_bonus_event(event)
			"lamp_break":
				sound.effect("lamp_break")
				world.lamp_break_effect(event)
				world._layout()
				_record_bonus_event(event)
			"speed_step":
				if model.speed_boots_charges == 0:
					_release_speed_input()
					world._layout()
				_record_bonus_event(event)
			"strong_push":
				_record_bonus_event(event)
			"ground_impact":
				sound.effect("helmet_hit")
				world.helmet_impacts.append({"age": 0.0, "crate": Vector2(event.x + 0.5, event.y + 0.5) * StackWorldView.PIXELS_PER_CELL,
					"jump": false, "broke": false, "contact": Vector2(event.x + 0.5, event.y + 1.0) * StackWorldView.PIXELS_PER_CELL})
			"helmet_hit":
				sound.effect("helmet_break" if event.helmet_broke else "helmet_hit")
				world.helmet_hit(event)
				if qa_enabled:
					qa_helmet_hits.append(event)
					if qa_helmet_hits.size() > 24:
						qa_helmet_hits.pop_front()
			"gloves_pull":
				if event.gloves_broke:
					sound.effect("gloves_tear")
					world.gloves_break(event)
					world._layout()
				if qa_enabled:
					qa_gloves_pulls.append(event)
					if qa_gloves_pulls.size() > 24:
						qa_gloves_pulls.pop_front()
			"mallet_swing", "mallet_hit", "mallet_miss":
				_mallet_effect(event)
			"land": sound.effect("land")
			"drop":
				if qa_enabled:
					qa_crane_releases.append({"crane": event.crane, "column": event.column,
						"crate_id": event.crate_id, "variant": event.variant, "tick": event.tick, "material": event.material})
					if qa_crane_releases.size() > 24:
						qa_crane_releases.pop_front()
			"line":
				sound.effect("line")
				world.cancel_mallet_swing()
				world.line_effect(int(event.chain))
			"over":
				sound.loss(event.reason)
				if event.reason in ["crushed", "metal_crushed"]:
					_record_result()
					_release_controls()
					crush_elapsed = 0.0
				else:
					_end_game()
	if score_label != null:
		_update_hud_score()
		EQUIPMENT_VIEW.update_hud(gear_counts, world,
			spring_meter_peak if spring_meter_flash > 0.0 else 0, spring_meter_limit)
	if screen == "playing":
		_update_pickup()
	return screen == "playing" and crush_elapsed < 0.0 and model.is_crate_sliding(axis, pull_held)


func _workshop_event(event: Dictionary, haptics: bool = true) -> void:
	var kind: String = event.type
	match kind:
		"watch_start", "watch_end", "watch_break", "trap_warning", "trap_open", "trap_crushed", \
		"trap_caught", "trap_escape", "trap_disarmed", "mallet_ring", "metal_land", "metal_impact", \
		"slingshot_fire", "crane_break", "mechanic_repair", "crane_fixed", "mechanic_hit", "mechanic_land":
			sound.effect(kind, haptics)
			world.workshop_effect(event)
			if kind == "mallet_ring":
				world.mallet_miss()
			if qa_enabled and haptics:
				qa_release_events.append(event)
				if qa_release_events.size() > 32:
					qa_release_events.pop_front()
			if haptics and kind in ["watch_break", "trap_disarmed", "slingshot_fire"]:
				world._layout()
		"mechanic_guard":
			var cue := "lamp_break" if event.lamp else ("helmet_break" if event.helmet_broke else "helmet_hit")
			sound.effect(cue, haptics)
			world._layout()


func _record_bonus_event(event: Dictionary) -> void:
	if qa_enabled:
		qa_bonus_events.append(event)
		if qa_bonus_events.size() > 48:
			qa_bonus_events.pop_front()


func _mallet_effect(event: Dictionary) -> void:
	match event.type:
		"mallet_swing":
			world.mallet_swing(event)
			sound.effect("mallet_swing")
		"mallet_hit":
			world.mallet_hit(event)
			sound.effect("mallet_hit")
			if event.mallet_broke:
				sound.effect("mallet_break")
				world._layout()
		"mallet_miss":
			world.mallet_miss()
	if qa_enabled:
		qa_mallet_events.append(event)
		if qa_mallet_events.size() > 24:
			qa_mallet_events.pop_front()


func _background_demo() -> bool:
	return screen in ["menu", "settings", "language", "statistics"] or (qa_enabled and qa_result_demo and screen == "over")


func _advance_demo(delta: float) -> bool:
	if not _background_demo() or qa_freeze_demo:
		return false
	demo.advance(delta)
	world.model = demo.model
	world.axis = demo.axis
	EQUIPMENT_VIEW.update_hud(gear_counts, world)
	for event in demo.events:
		_workshop_event(event, false)
		match event.type:
			"jump", "land": sound.effect(str(event.type), false)
			"over": sound.loss(event.reason, false)
			"line":
				sound.effect("line", false)
				world.line_effect(int(event.chain))
	return demo.model.is_crate_sliding(demo.axis, false)


func _update_crush_view() -> void:
	var elapsed := crush_elapsed
	if _background_demo():
		elapsed = demo.over_elapsed if demo.model.state == "over" and demo.model.loss_reason in ["crushed", "metal_crushed"] else -1.0
	world.crush_progress = minf(elapsed / CRUSH_ANIMATION_TIME, 1.0) if elapsed >= 0.0 else -1.0


func _process(delta: float) -> void:
	if world == null:
		return
	var now := Time.get_ticks_usec()
	var real_delta := delta if frame_time_usec == 0 else (now - frame_time_usec) / 1000000.0
	frame_time_usec = now
	if screen == "menu":
		_update_menu_idle()
	var world_delta := delta
	var slide_moving := _advance_demo(delta)
	if screen == "playing" and not (qa_enabled and (qa_hero_pose or qa_animation_held)):
		var animating_loss := crush_elapsed >= 0.0
		slide_moving = _advance_game(delta, real_delta)
		if not animating_loss:
			world_delta = model.frame_world_delta
	elif _background_demo() and demo.model.watch_cap_active:
		world_delta *= 0.5
	slide_active = slide_focused and slide_moving
	sound.set_slide_active(slide_active, delta)
	_update_crush_view()
	var frozen := screen == "paused" or (qa_enabled and (qa_hero_pose or qa_freeze_demo or qa_animation_held))
	world.animate(0.0 if frozen else world_delta)
	if qa_enabled:
		qa_timer += delta
		if qa_timer >= 0.08:
			qa_timer = 0.0
			_qa_command()
			_publish_qa()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN]:
		slide_focused = true
	elif what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT] and is_inside_tree():
		slide_focused = false
		_clear_wake_input()
		if screen == "playing":
			_pause()
		else:
			_stop_crate_slide()


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
		if is_instance_valid(buttons[id]) and buttons[id].visible:
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
		visible_crates.append({"id": crate.id, "x": crate.x, "y": crate.y, "color": crate.color,
			"variant": crate.variant, "material": crate.material})
		if world.model.is_clearing_crate(int(crate.id)):
			retiring_ids.append(crate.id)
	var cranes := []
	var trolleys := []
	var cargo_rects := []
	for index in range(world.model.cranes.size()):
		var crane: Dictionary = world.model.cranes[index]
		var cargo := world.crane_cargo_rect(index)
		cranes.append({"x": crane.x, "direction": crane.direction, "loaded": crane.loaded,
			"waiting": crane.waiting, "wait_remaining": crane.wait_remaining,
			"release_column": crane.release_column, "open_time": crane.open_time, "variant": crane.variant,
			"material": crane.material, "repair_phase": world.model.repair.workers[index].phase,
			"broken": world.model.repair.workers[index].broken})
		cargo_rects.append([cargo.position.x, cargo.position.y, cargo.size.x, cargo.size.y])
		var trolley := world.crane_trolley_center(index)
		trolleys.append([trolley.x, trolley.y])
	var hints := {}
	for item in gear_counts:
		var plate: Control = gear_counts[item].get_parent().get_parent()
		_qa_keycap(hints, item, plate)
	if screen == "playing":
		_qa_keycap(hints, "pickup", pickup_button)
	var rail := world.crane_rail
	var body := world.equipment_body
	var status := {"ready": true, "screen": screen, "score": model.score,
		"lines": model.lines, "cleared_crates": model.cleared_crates, "broken_crates": model.broken_crates,
		"loss_reason": model.loss_reason,
		"release": {"watch_cap_time": model.watch_cap_time, "watch_cap_active": model.watch_cap_active,
			"hunting_boots_charges": model.hunting_boots_charges, "engineer_goggles_charges": model.engineer_goggles_charges,
			"slingshot_charges": model.slingshot_charges, "trap_hold_time": model.trap_hold_time,
			"traps": model.traps, "shots": model.repair.shots.size(), "fallen": model.repair.fallen.size(),
			"events": qa_release_events},
		"session": session, "ticks": model.ticks, "state": model.state,
		"animation_held": qa_animation_held,
		"jump_pending": jump_pending, "jump_held": _jump_held(),
		"pull_held": _pull_held(), "pull_in_progress": model.is_pulling(),
		"ground_items": model.ground_items, "nearest_item": model.nearest_item(),
		"boots_equipped": model.boots_equipped, "boots_charges": model.boots_charges,
		"boots_hud": _gear_hud_snapshot(gear_counts.get("boots")),
		"helmet_charges": model.helmet_charges, "helmet_hud": _gear_hud_snapshot(gear_counts.get("helmet")),
		"helmet_hits": qa_helmet_hits,
		"gloves_charges": model.gloves_charges, "gloves_hud": _gear_hud_snapshot(gear_counts.get("gloves")),
		"mallet_charges": model.mallet_charges, "mallet_hud": _gear_hud_snapshot(gear_counts.get("mallet")),
		"strong_arms_charges": model.strong_arms_charges,
		"strong_arms_hud": _gear_hud_snapshot(gear_counts.get("strong_arms")),
		"speed_boots_charges": model.speed_boots_charges, "speed_boots_progress": model.speed_boots_progress,
		"speed_boost_active": model.speed_boost_active,
		"speed_boots_hud": _gear_hud_snapshot(gear_counts.get("speed_boots")),
		"lamp_helmet_charges": model.lamp_helmet_charges, "lamp_helmet_equipped": model.lamp_helmet_equipped,
		"lamp_helmet_hud": _gear_hud_snapshot(gear_counts.get("lamp_helmet")),
		"lamp_columns": model.lamp_columns(), "lamp_active_time": model.lamp_active_time,
		"spring_boots_charges": model.spring_boots_charges, "spring_charge_stages": model.spring_charge_stages,
		"spring_charge_limit": model.spring_charge_limit(),
		"spring_boots_hud": _gear_hud_snapshot(gear_counts.get("spring_boots")),
		"bonus_events": qa_bonus_events,
		"mallet_animation": world.mallet_animation_phase(),
		"mallet_swings": qa_mallet_events.filter(func(event): return event.type == "mallet_swing"),
		"mallet_hits": qa_mallet_events.filter(func(event): return event.type == "mallet_hit"),
		"mallet_misses": qa_mallet_events.filter(func(event): return event.type == "mallet_miss"),
		"grabbed_crate_id": model.grabbed_crate_id, "gloves_pulls": qa_gloves_pulls,
		"crate_slide": {"active": slide_active, "playing": sound.slide_player.playing,
			"position": sound.slide_player.get_playback_position(), "volume_db": sound.slide_player.volume_db,
			"loop_seconds": sound.slide_player.stream.get_length()},
		"clear_animation": {"phase": world.clear_animation_phase(), "elapsed": world.model.clear_elapsed, "ids": retiring_ids},
		"crush_animation": {"active": screen in ["playing", "paused"] and crush_elapsed >= 0.0,
			"progress": world.crush_progress, "impact_crate": world.model.impact_crate_id},
		"active_duration_ms": roundi(model.ticks * StackSimulation.STEP * 1000.0),
		"player": [model.player.x, model.player.y], "grounded": model.grounded,
		"player_velocity": [model.player_velocity.x, model.player_velocity.y],
		"player_size": [TUNING.player_width, TUNING.player_height],
		"facing": model.facing, "hero_pose": qa_hero_pose, "hero_frame": world.hero_frame(),
		"equipment_body": [body.position.x, body.position.y, body.size.x, body.size.y],
		"columns": model.tuning.columns, "rows": model.tuning.rows, "crates": model.crates.size(), "first_crate_x": model.crates[0].x if not model.crates.is_empty() else -1,
		"layout": "landscape" if size.x > size.y else "portrait", "viewport": [size.x, size.y],
		"field": [world.field.position.x, world.field.position.y, world.field.size.x, world.field.size.y], "visible_crates": visible_crates,
		"overload_phase": StackCraneOverload.Phase.keys()[model.overload.phase],
		"cranes": cranes, "crane_releases": qa_crane_releases, "crane_preview": qa_crane_preview,
		"crane_rail": [rail.position.x, rail.position.y, rail.size.x, rail.size.y], "crane_trolleys": trolleys,
		"crane_cargo_rects": cargo_rects,
		"crane_settings": {"speed": TUNING.crane_speed, "wait_min": TUNING.crane_wait_min,
			"wait_max": TUNING.crane_wait_max, "margin": StackSimulation.CRANE_EDGE_MARGIN},
		"key_hints": hints, "buttons": rects, "sliders": slider_rects, "controls": input_rects,
		"missing_menu_glyphs": _missing_menu_glyphs(),
		"panel": _panel_snapshot(),
		"button_modes": button_modes,
		"vibration_styles": vibration_styles,
		"demo": {"active": _background_demo(), "rounds": demo.rounds, "ticks": demo.total_ticks,
			"jumps": demo.jumps, "drops": demo.drops, "lines": demo.lines, "losses": demo.losses,
			"player": [demo.model.player.x, demo.model.player.y], "facing": demo.model.facing,
			"state": demo.model.state, "helmet": demo.model.helmet_charges,
			"separate_model": demo.model != model},
		"profile": {"language": profile.language, "locale": TranslationServer.get_locale(), "music": profile.music, "effects": profile.effects,
			"matches": profile.matches, "statistics": profile.statistics(), "records": profile.records,
			"vibration": profile.vibration, "vibration_visible": buttons.has("vibration")},
		"statistics_view": {"first_match": first_match, "expanded_match": expanded_match,
			"preview": qa_statistics_preview != null},
		"audio": {"music_playing": sound.music_player.playing, "music_position": sound.music_player.get_playback_position(), "stream_format": sound.music_player.stream.format, "loop_end": sound.music_player.stream.loop_end, "unlocked": sound.unlocked,
			"music_muted": AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")),
			"effects_muted": AudioServer.is_bus_mute(AudioServer.get_bus_index("Effects"))}}
	JavaScriptBridge.eval("window.stackAttackState = " + JSON.stringify(status))


func _qa_keycap(hints: Dictionary, id: String, control: Control) -> void:
	var key: String = control.get_meta("action_key", "")
	if key.is_empty() or not control.is_visible_in_tree():
		return
	var owner_rect := control.get_global_rect()
	var rect := EQUIPMENT_VIEW.keycap_rect(control, key, id == "pickup")
	rect.position += owner_rect.position
	hints[id] = {"key": key, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
		"owner": [owner_rect.position.x, owner_rect.position.y, owner_rect.size.x, owner_rect.size.y]}


func _gear_hud_snapshot(count: Label) -> Dictionary:
	if count == null or not count.is_visible_in_tree():
		return {}
	var plate := count.get_parent().get_parent() as Control
	var bounds := plate.get_global_rect()
	var result := {"text": count.text, "rect": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]}
	var meter := count.get_parent().get_node_or_null("spring_charge_meter") as Control
	if meter != null:
		var meter_rect := meter.get_global_rect()
		result.meter_rect = [meter_rect.position.x, meter_rect.position.y, meter_rect.size.x, meter_rect.size.y]
		result.meter_limit = meter.get_meta("limit", 0)
		result.meter_stages = meter.get_meta("stages", 0)
	return result


func _missing_menu_glyphs() -> String:
	var missing := ""
	if panel != null:
		for control in panel.find_children("*", "Control", true, false):
			if control is Label or control is Button:
				var font: Font = control.get_theme_font("font")
				for character in control.text:
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
				"opacity": control.modulate.a, "styles": _button_style_snapshot(control),
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
	if str(request.get("scenario", "")) == "release_board" and screen == "playing":
		var board := str(request.get("case", ""))
		if board in ["input", "cap", "boots", "goggles", "repair", "metal"]:
			_qa_prepare_equipment_board(bool(request.get("animation_hold", false)))
			preload("res://game/qa_demo_boards.gd").prepare_release(model, board)
			_show_screen("playing")
		return
	if str(request.get("scenario", "")) == "crate_appearance" and screen in ["menu", "playing"]:
		_qa_crate_appearance(request)
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
	if request.get("scenario") in ["demo_dodge", "demo_row", "demo_pickup"] and screen == "menu":
		demo = preload("res://game/qa_demo_boards.gd").prepare(str(request.scenario))
		world.model = demo.model
		qa_freeze_demo = false
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
	if request.get("scenario") == "ground_board":
		_qa_set_test_board(request)
		for entry in request.get("items", []):
			if entry is Array and entry.size() == 4 and entry[0] in StackSimulation.CAPACITIES:
				model.add_ground_item(entry[0], entry[1], entry[2], entry[3])
		if request.has("seed"):
			model._loot_rng.seed = int(request.seed)
		_show_screen("playing")
		return
	if str(request.get("scenario", "")) == "bonus_board":
		if crush_elapsed < 0.0:
			_qa_set_bonus_board(request)
		return
	if str(request.get("scenario", "")) in ["helmet_board", "gloves_board"]:
		if crush_elapsed < 0.0:
			_qa_set_test_board(request)
		return
	if str(request.get("scenario", "")) == "mallet_board":
		if crush_elapsed < 0.0:
			_qa_set_mallet_board(request)
		return
	if str(request.get("scenario", "")) == "boots_jump":
		_qa_set_jump_board(bool(request.get("animation_hold", false)))
		return
	if str(request.get("scenario", "")) == "cranes":
		# Reset a real simulation and start the first routes at known positions for capture.
		qa_hero_pose = false
		qa_crane_preview = true
		qa_animation_held = bool(request.get("animation_hold", false))
		qa_crane_releases.clear()
		_release_controls()
		world.reset_mallet_effects()
		model.reset(7481)
		model.player.x = 4.3
		model.cranes[0].x = -0.75
		model.cranes[1].x = TUNING.columns + 0.75
		model.cranes[0].release_column = 7
		model.cranes[1].release_column = 1
		if request.get("overload_preview", false):
			model.elapsed = model.overload.phase_end - 2.0
			model.player.x = 3.15
		world.caption_life = 0.0
		return
	if str(request.get("scenario", "")) == "hero_pose":
		var pose := str(request.get("pose", "idle"))
		if pose not in ["idle", "walk_stride", "walk_recover", "jump", "push"]:
			return
		_release_controls()
		world.reset_mallet_effects()
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
		EQUIPMENT_VIEW.update_hud(gear_counts, world)
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
	_release_controls()
	world.reset_mallet_effects()
	model.cancel_grab()
	model.crates.clear()
	model.ground_items.clear()
	model._loot_rng.seed = 14
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


func _qa_crate_appearance(request: Dictionary) -> void:
	var target := demo.model if screen == "menu" else model
	_release_controls()
	world.reset_mallet_effects()
	target.cancel_grab()
	target.crates.clear()
	target.state = "playing"
	var stacks := bool(request.get("stacks", false))
	var default_x := (TUNING.columns - TUNING.player_width) * 0.5 if stacks else 8.4
	var player_x := clampf(float(request.get("player_x", default_x)), 0.0, TUNING.columns - TUNING.player_width)
	target.player = Vector2(player_x, TUNING.rows - TUNING.player_height)
	target.player_velocity = Vector2.ZERO
	target.grounded = true
	target.facing = -1 if int(request.get("facing", target.facing)) < 0 else 1
	var tag_offset := int(request.get("tag_offset", 0))
	if stacks:
		var heights := [2, 4, 3, 1, 0, 0, 1, 3, 4, 2]
		var variant := 0
		for column in range(heights.size()):
			for row in range(heights[column]):
				target.add_crate(float(column), float(TUNING.rows - 1 - row), 0.0, variant)
				variant = (variant + 1) % StackSimulation.CRATE_VARIANT_COUNT
	elif bool(request.get("gallery", false)):
		for index in range(StackSimulation.CRATE_VARIANT_COUNT):
			@warning_ignore("integer_division")
			var row := index / 5
			var crate := target.add_crate(float(1 + (index % 5) * 2), float(2 + row * 2), 0.0, index)
			crate.color = posmod(index + tag_offset, 3)
	else:
		for index in range(3):
			var crate := target.add_crate(float(1 + index * 3), 2.0, 0.0, 0)
			crate.color = posmod(index + tag_offset, 3)
	qa_freeze_demo = screen == "menu"
	qa_hero_pose = screen == "playing"
	world.axis = 0.0


func _qa_prepare_equipment_board(hold: bool) -> void:
	qa_hero_pose = false
	qa_crane_preview = false
	qa_animation_held = hold
	qa_helmet_hits.clear()
	qa_gloves_pulls.clear()
	qa_mallet_events.clear()
	qa_bonus_events.clear()
	qa_release_events.clear()
	world.caption_life = 0.0
	world.boots_exhaust_life = 0.0
	world.helmet_impacts.clear()
	world.gloves_break_life = 0.0
	world.reset_mallet_effects()
	world.reset_bonus_effects()
	_release_controls()
	model.cancel_grab()
	model.crates.clear()
	model.ground_items.clear()
	model.traps.clear()
	model.repair.reset(14)
	model._loot_rng.seed = 14
	model.cranes_enabled = false
	model.cranes[0].x = 2.5
	model.cranes[1].x = 7.5
	model.player = Vector2(4.3, TUNING.rows - TUNING.player_height)
	model.player_velocity = Vector2.ZERO
	model.grounded = true
	model.state = "playing"
	model.chain = 0
	model.accumulator = 0.0


func _qa_set_jump_board(hold: bool) -> void:
	_qa_prepare_equipment_board(hold)
	var stacks := [[0, 1, 2, 7, 8, 9], [0, 1, 8, 9], [0, 9]]
	for row in range(stacks.size()):
		for column in stacks[row]:
			model.add_crate(float(column), float(TUNING.rows - 1 - row))


func _qa_set_mallet_board(request: Dictionary) -> void:
	var facing := -1 if int(request.get("facing", 1)) < 0 else 1
	var floor_y := float(TUNING.rows - 1)
	var crate_x := 5.0 if facing > 0 else 4.0
	var player_x := crate_x - TUNING.player_width if facing > 0 else crate_x + 1.0
	if bool(request.get("at_edge", false)):
		player_x = TUNING.columns - TUNING.player_width if facing > 0 else 0.0
	var placements := []
	if bool(request.get("target", true)):
		placements.append([crate_x, floor_y, 0.0])
		if bool(request.get("stack", false)):
			placements.append([crate_x, floor_y - 1.0, 0.0])
	var board := {"facing": facing, "player": [player_x, TUNING.rows - TUNING.player_height], "crates": placements}
	board.merge(request, true)
	_qa_set_test_board(board)
	model.helmet_charges = clampi(int(request.get("helmet", model.helmet_charges)), 0, StackSimulation.HELMET_MAX_CHARGES)
	if request.has("boots"):
		model.boots_charges = clampi(int(request.boots), 0, StackSimulation.BOOTS_MAX_CHARGES)
		model.boots_equipped = model.boots_charges > 0
	if bool(request.get("equip", false)):
		model.gloves_charges = 0
		model.mallet_charges = clampi(int(request.get("charges", StackSimulation.MALLET_MAX_CHARGES)),
			1, StackSimulation.MALLET_MAX_CHARGES)
		_show_screen("playing")



func _qa_set_bonus_board(request: Dictionary) -> void:
	model.reset(7481)
	_qa_set_test_board(request)
	qa_crane_releases.clear()
	if request.has("grounded"):
		model.grounded = bool(request.grounded)
	var loadout: Variant = request.get("loadout", {})
	var charges: Variant = request.get("charges", {})
	if loadout is Dictionary and charges is Dictionary:
		for slot in EQUIPMENT_VIEW.SLOTS:
			var item := str(loadout.get(slot, ""))
			if item not in EQUIPMENT_VIEW.SLOTS[slot]:
				continue
			var capacity: int = EQUIPMENT_VIEW.CAPACITIES[item]
			var count := clampi(int(charges.get(item, capacity)), 0, capacity)
			model.set(item + "_charges", count)
			if item in ["boots", "lamp_helmet"]:
				model.set(item + "_equipped", true)
	model.cranes_enabled = bool(request.get("cranes_enabled", false))
	var crane_states: Variant = request.get("cranes", [])
	if crane_states is Array:
		for index in range(mini(crane_states.size(), model.cranes.size())):
			var overrides: Variant = crane_states[index]
			if not overrides is Dictionary:
				continue
			var crane := model.cranes[index]
			crane.x = clampf(float(overrides.get("x", crane.x)), -StackSimulation.CRANE_EDGE_MARGIN,
				TUNING.columns + StackSimulation.CRANE_EDGE_MARGIN)
			crane.loaded = bool(overrides.get("loaded", crane.loaded))
			crane.waiting = bool(overrides.get("waiting", crane.waiting))
			crane.wait_remaining = maxf(0.0, float(overrides.get("wait_remaining", crane.wait_remaining)))
			crane.release_column = clampi(int(overrides.get("release_column", crane.release_column)), -1, TUNING.columns - 1)
	_show_screen("playing")


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
