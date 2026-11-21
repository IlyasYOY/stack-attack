extends RefCounted

const ICONS := {
	"boots": preload("res://art/rocket_boots.png"),
	"speed_boots": preload("res://art/speed_boots.png"),
	"spring_boots": preload("res://art/spring_boots.png"),
	"helmet": preload("res://art/helmet.png"),
	"lamp_helmet": preload("res://art/lamp_helmet.png"),
	"gloves": preload("res://art/work_gloves.png"),
	"mallet": preload("res://art/wooden_mallet.png"),
	"strong_arms": preload("res://art/strong_arms.png"),
	"watch_cap": preload("res://art/watch_cap.png"),
	"hunting_boots": preload("res://art/hunting_boots.png"),
	"engineer_goggles": preload("res://art/engineer_goggles.png"),
	"slingshot": preload("res://art/slingshot.png"),
}
const SLOTS := StackSimulation.SLOTS
const NAMES := {"boots": "Rocket boots", "helmet": "Hard hat", "gloves": "Work gloves",
	"mallet": "Mallet", "strong_arms": "Strong arms", "speed_boots": "Speed boots",
	"lamp_helmet": "Headlamp", "spring_boots": "Spring boots",
	"watch_cap": "Watchmaker's cap", "hunting_boots": "Hunting boots",
	"engineer_goggles": "Engineer's goggles", "slingshot": "Slingshot"}
const ACTION_KEYS := {
	"lamp_helmet": "F", "engineer_goggles": "F", "watch_cap": "F",
	"gloves": "G", "mallet": "G", "slingshot": "G",
	"speed_boots": "Shift", "boots": "Space", "spring_boots": "Space",
}
const KEY_FONT_SIZE := 10
const CAPACITIES := StackSimulation.CAPACITIES
const CREAM := Color("f4e3ba")
const GOLD := Color("e7b46b")
const MINT := Color("8dc6ac")
const DARK := Color("102c35")
const EDGE := Color("567679")
const SPRING_COLORS := [Color("8bdb64"), Color("f2d858"), Color("f1a047"), Color("e66252")]
static func _loadout_charges(model: StackSimulation) -> Dictionary:
	var charges := {}
	for item: String in CAPACITIES:
		charges[item] = model.equipped_charges(item)
	return charges


static func _equipped_item(slot: String, charges: Dictionary) -> String:
	for item: String in SLOTS[slot]:
		if charges[item] >= 0:
			return item
	return SLOTS[slot][0]


static func build_pause(panel: PanelContainer, content: VBoxContainer, compact: bool,
		model: StackSimulation, text: Callable) -> void:
	_frame(panel, GOLD, 10 if compact else 16)
	var loadout: BoxContainer = HBoxContainer.new() if compact else VBoxContainer.new()
	loadout.alignment = BoxContainer.ALIGNMENT_CENTER
	loadout.add_theme_constant_override("separation", 12 if compact else 8)
	content.add_child(loadout)

	var charges := _loadout_charges(model)
	var portrait := PanelContainer.new()
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.add_theme_stylebox_override("panel", _style(DARK.darkened(0.10), EDGE, 4))
	loadout.add_child(portrait)
	_picture(portrait, StackWorldView.pause_portrait(model.boots_equipped, model.helmet_charges > 0,
		model.gloves_charges > 0, {"strong_arms": model.strong_arms_charges > 0,
			"speed_boots": model.speed_boots_charges > 0, "spring_boots": model.spring_boots_charges > 0,
			"lamp_helmet": model.lamp_helmet_equipped, "watch_cap": charges.watch_cap >= 0,
			"engineer_goggles": charges.engineer_goggles >= 0, "hunting_boots": charges.hunting_boots >= 0,
			"slingshot": charges.slingshot >= 0}),
		Vector2(48, 66) if compact else Vector2(64, 84))

	var center := CenterContainer.new()
	loadout.add_child(center)
	var slots := GridContainer.new()
	slots.columns = 2
	slots.add_theme_constant_override("h_separation", 12)
	slots.add_theme_constant_override("v_separation", 2)
	center.add_child(slots)
	var head := _equipped_item("head", charges)
	var hands := _equipped_item("hands", charges)
	var feet := _equipped_item("feet", charges)
	_equipment_slot(text, slots, TranslationServer.translate("Head"), "slot_head", head, charges[head], model.watch_cap_time)
	_equipment_slot(text, slots, TranslationServer.translate("Hands"), "slot_hands", hands, charges[hands])
	_equipment_slot(text, slots, TranslationServer.translate("Feet"), "slot_feet", feet, charges[feet])


static func _equipment_slot(text: Callable, slots: GridContainer, title: String, id: String,
		item: String, charges: int, watch_time: float = 0.0) -> void:
	if charges < 0:
		_slot_label(text, slots, title, id)
		return
	_slot_title(text, slots, title, id + "_title")
	var details := HBoxContainer.new()
	details.add_theme_constant_override("separation", 5)
	slots.add_child(details)
	_picture(details, ICONS[item], Vector2.ONE * 24)
	var remaining := _watch_time_text(watch_time) if item == "watch_cap" else str(charges)
	var label := _label(text, details, "%s / %d" % [remaining, CAPACITIES[item]], id, 15, GOLD)
	label.accessibility_name = "%s · %s" % [TranslationServer.translate(NAMES[item]), label.text]


# Draw outside the badge's content box so the counter, meter and timer keep their space.
static func _attach_keycap(control: Control, pickup := false) -> void:
	var face := _style(Color("29444a"), GOLD, 0)
	face.set_corner_radius_all(2)
	face.border_width_bottom = 2
	control.draw.connect(func():
		var key: String = control.get_meta("action_key", "")
		if key.is_empty():
			return
		var rect := keycap_rect(control, key, pickup)
		control.draw_style_box(face, rect)
		control.draw_string(StackWorldView.FONT, rect.position + Vector2(0, 10), key,
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, KEY_FONT_SIZE, CREAM))


static func keycap_rect(control: Control, key: String, pickup: bool) -> Rect2:
	var width := StackWorldView.FONT.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_FONT_SIZE).x + 6
	var corner := control.size.round()
	if pickup:
		corner.y -= StackWorldView.KEYCAP_HEIGHT
	return Rect2(corner - Vector2(width, 0), Vector2(width, StackWorldView.KEYCAP_HEIGHT))


static func set_action_key(control: Control, key: String) -> void:
	if control.get_meta("action_key", "") != key:
		control.set_meta("action_key", key)
		control.queue_redraw()


static func build_hud(parent: Control, item: String) -> Label:
	var plate := PanelContainer.new()
	plate.name = item + "_hud"
	plate.size = Vector2(StackWorldView.BADGE_WIDTH, StackWorldView.BADGE_HEIGHT)
	plate.add_theme_stylebox_override("panel", _style(Color(0.055, 0.13, 0.16, 0.9), EDGE, 2))
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(plate)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 1 if item in ["watch_cap", "spring_boots"] else 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(row)
	_picture(row, ICONS[item], Vector2.ONE * (15 if item in ["spring_boots", "watch_cap"] else 20))
	if item == "watch_cap":
		plate.draw.connect(_draw_watch_reserve.bind(plate))
	if item == "spring_boots":
		var meter := Control.new()
		meter.name = "spring_charge_meter"
		meter.custom_minimum_size = Vector2(5, 20)
		meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		meter.draw.connect(_draw_spring_charge.bind(meter))
		row.add_child(meter)
	var count := Label.new()
	count.name = item + "_charges"
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override("font_size", 13 if item == "watch_cap" else 16)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(count)
	if ACTION_KEYS.has(item):
		_attach_keycap(plate)
	plate.hide()
	return count


static func update_hud(badges: Dictionary, world: StackWorldView, spring_peak: int = 0,
		spring_peak_limit: int = 0) -> void:
	var model := world.model
	var charges := _loadout_charges(model)
	if spring_peak > 0:
		charges.spring_boots = model.spring_boots_charges
	for item: String in badges:
		var count: Label = badges[item]
		var plate := count.get_parent().get_parent() as PanelContainer
		var charge_count: int = charges[item]
		plate.visible = charge_count >= 0
		if plate.visible:
			plate.position = world.badge_position(item, plate.size)
			var key: String = ACTION_KEYS.get(item, "") if world.keyboard_hints and charge_count > 0 else ""
			set_action_key(plate, TranslationServer.translate(key) if not key.is_empty() else "")
			var remaining := str(charge_count)
			if item == "watch_cap":
				remaining = _watch_time_text(model.watch_cap_time)
				var fraction := model.watch_cap_time / float(CAPACITIES.watch_cap)
				if plate.get_meta("fraction", -1.0) != fraction:
					plate.set_meta("fraction", fraction)
					plate.queue_redraw()
			if count.text != remaining:
				count.text = remaining
				count.accessibility_name = "%s · %s" % [TranslationServer.translate(NAMES[item]), remaining]
	var spring: Label = badges.spring_boots
	var meter := spring.get_parent().get_node("spring_charge_meter") as Control
	var stages := maxi(model.spring_charge_stages, spring_peak)
	var limit := spring_peak_limit if spring_peak > 0 else model.spring_charge_limit()
	if meter.get_meta("limit", 0) != limit or meter.get_meta("stages", 0) != stages:
		meter.set_meta("limit", limit)
		meter.set_meta("stages", stages)
		meter.queue_redraw()


static func build_swap(parent: Control, action: Callable) -> Button:
	var button := Button.new()
	button.name = "pickup"
	button.focus_mode = Control.FOCUS_NONE
	button.flat = true
	button.custom_minimum_size = Vector2.ONE * StackWorldView.SWAP_SIZE
	parent.add_child(button)
	button.pressed.connect(action)
	button.draw.connect(_draw_swap.bind(button))
	_attach_keycap(button, true)
	return button


static func _draw_swap(button: Button) -> void:
	var kind: String = button.get_meta("kind", "")
	if kind.is_empty():
		return
	var center := button.size * 0.5
	var fill := Color("37575c") if button.is_hovered() else DARK
	button.draw_circle(center, 23, fill, true, -1, true)
	button.draw_circle(center, 23, GOLD, false, 1, true)
	# Two opposed arrowheads leave the centre open for the found item's silhouette.
	for start: float in [-PI / 2, PI / 2]:
		var end := start + PI * 0.73
		button.draw_arc(center, 18, start, end, 14, MINT, 2, true)
		var tip := center + Vector2.from_angle(end) * 18
		var tangent := Vector2.from_angle(end + PI / 2)
		button.draw_colored_polygon(PackedVector2Array([tip + tangent * 3.5,
			tip - tangent * 3 - tangent.orthogonal() * 4, tip - tangent * 3 + tangent.orthogonal() * 4]), MINT)
	if StackWorldView.WORKSHOP_ICONS.has(kind):
		button.draw_texture_rect(ICONS[kind], Rect2(center - Vector2(12, 17), Vector2(24, 24)), false)
	else:
		button.draw_texture_rect_region(StackWorldView.GROUND_ATLAS, Rect2(center - Vector2(15, 17), Vector2(30, 24)),
			StackWorldView.ground_icon_region(kind))
	var counter := str(button.get_meta("charges", 0))
	var baseline := center + Vector2(-12, 16)
	button.draw_string_outline(StackWorldView.FONT, baseline, counter, HORIZONTAL_ALIGNMENT_CENTER, 24, 15, 3, DARK)
	button.draw_string(StackWorldView.FONT, baseline, counter, HORIZONTAL_ALIGNMENT_CENTER, 24, 15, CREAM)


static func _watch_time_text(time: float) -> String:
	return TextServerManager.get_primary_interface().format_number("%.1f" % (ceilf(time * 10.0) / 10.0), TranslationServer.get_locale())


static func _draw_watch_reserve(plate: PanelContainer) -> void:
	var bar := Rect2(4.0, plate.size.y - 4.0, plate.size.x - 8.0, 2.0)
	var fraction := clampf(float(plate.get_meta("fraction", 0.0)), 0.0, 1.0)
	plate.draw_rect(bar, EDGE.darkened(0.35))
	bar.size.x *= fraction
	plate.draw_rect(bar, StackWorldView.WATCH_LIGHT)


static func _draw_spring_charge(meter: Control) -> void:
	var stages := int(meter.get_meta("stages", 0))
	meter.draw_rect(Rect2(Vector2.ZERO, meter.size), EDGE)
	meter.draw_rect(Rect2(1, 1, meter.size.x - 2, meter.size.y - 2), Color("172a33"))
	var limit := int(meter.get_meta("limit", 0))
	for index in range(limit):
		var height := (meter.size.y - 2.0) / limit
		var y := meter.size.y - 1.0 - height * (index + 1)
		var tint := Color("31454c")
		if index < stages:
			var fraction := float(index) / (limit - 1) if limit > 1 else 1.0
			var stop := fraction * (SPRING_COLORS.size() - 1)
			var low := floori(stop)
			tint = SPRING_COLORS[low].lerp(SPRING_COLORS[mini(low + 1, SPRING_COLORS.size() - 1)], stop - low)
		meter.draw_rect(Rect2(1.0, y, meter.size.x - 2.0, height - (1.0 if height >= 2.0 else 0.0)), tint)


static func _slot_label(text: Callable, slots: GridContainer, title: String, id: String) -> void:
	_slot_title(text, slots, title, id + "_title")
	var empty := _label(text, slots, "—", id, 15, MINT)
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


static func _slot_title(text: Callable, slots: GridContainer, value: String, id: String) -> Label:
	var label := _label(text, slots, value, id, 15, CREAM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return label


static func _label(text: Callable, parent: Control, value: String, id: String,
		font_size: int, tint: Color) -> Label:
	var label: Label = text.call(parent, value, font_size, tint)
	label.name = id
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func _picture(parent: Control, texture: Texture2D, minimum: Vector2) -> void:
	var picture := TextureRect.new()
	picture.texture = texture
	picture.custom_minimum_size = minimum
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(picture)


static func _style(fill: Color, edge: Color, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(margin)
	return style


static func _frame(panel: PanelContainer, edge: Color, margin: int) -> void:
	var style := _style(DARK, edge, margin)
	style.shadow_color = Color(0.01, 0.05, 0.07, 0.55)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 3)
	panel.add_theme_stylebox_override("panel", style)
	panel.draw.connect(_draw_rivets.bind(panel))


static func _draw_rivets(panel: Control) -> void:
	for x in [5.0, panel.size.x - 7.0]:
		for y in [5.0, panel.size.y - 7.0]:
			panel.draw_rect(Rect2(x, y, 2, 2), CREAM)
