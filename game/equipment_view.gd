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
}
const SLOTS := StackSimulation.SLOTS
const NAMES := {"boots": "Ботинки-ракеты", "helmet": "Каска", "gloves": "Рабочие перчатки",
	"mallet": "Киянка", "strong_arms": "Накачанные руки", "speed_boots": "Сапоги-скороходы",
	"lamp_helmet": "Каска с фонарём", "spring_boots": "Пружинные ботинки"}
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

	var portrait := PanelContainer.new()
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.add_theme_stylebox_override("panel", _style(DARK.darkened(0.10), EDGE, 4))
	loadout.add_child(portrait)
	_picture(portrait, StackWorldView.pause_portrait(model.boots_equipped, model.helmet_charges > 0,
		model.gloves_charges > 0, {"strong_arms": model.strong_arms_charges > 0,
			"speed_boots": model.speed_boots_charges > 0, "spring_boots": model.spring_boots_charges > 0,
			"lamp_helmet": model.lamp_helmet_equipped}),
		Vector2(48, 66) if compact else Vector2(64, 84))

	var center := CenterContainer.new()
	loadout.add_child(center)
	var slots := GridContainer.new()
	slots.columns = 2
	slots.add_theme_constant_override("h_separation", 12)
	slots.add_theme_constant_override("v_separation", 2)
	center.add_child(slots)
	var charges := _loadout_charges(model)
	var head := _equipped_item("head", charges)
	var hands := _equipped_item("hands", charges)
	var feet := _equipped_item("feet", charges)
	_equipment_slot(text, slots, "Голова", "slot_head", head, charges[head])
	_equipment_slot(text, slots, "Руки", "slot_hands", hands, charges[hands])
	_equipment_slot(text, slots, "Ноги", "slot_feet", feet, charges[feet])


static func _equipment_slot(text: Callable, slots: GridContainer, title: String, id: String,
		item: String, charges: int) -> void:
	if charges < 0:
		_slot_label(text, slots, title, id)
		return
	_slot_title(text, slots, title, id + "_title")
	var details := HBoxContainer.new()
	details.add_theme_constant_override("separation", 5)
	slots.add_child(details)
	_picture(details, ICONS[item], Vector2.ONE * 24)
	var label := _label(text, details, "%d / %d" % [charges, CAPACITIES[item]], id, 15, GOLD)
	label.accessibility_name = "%s · %s" % [NAMES[item], label.text]


static func build_hud(parent: Control, item: String) -> Label:
	var plate := PanelContainer.new()
	plate.name = item + "_hud"
	plate.size = Vector2(StackWorldView.BADGE_WIDTH, 26)
	plate.add_theme_stylebox_override("panel", _style(Color(0.055, 0.13, 0.16, 0.9), EDGE, 2))
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(plate)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(row)
	_picture(row, ICONS[item], Vector2.ONE * (15 if item == "spring_boots" else 20))
	if item == "spring_boots":
		row.add_theme_constant_override("separation", 1)
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
	count.add_theme_font_size_override("font_size", 16)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(count)
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
			plate.position = Vector2(world.equipment_body.position.x - StackWorldView.BADGE_WIDTH - 4,
				world.slot_height(item) - plate.size.y * 0.5).round()
			if count.text != str(charge_count):
				count.text = str(charge_count)
				count.accessibility_name = "%s · %d" % [NAMES[item], charge_count]
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
	button.draw_texture_rect_region(StackWorldView.GROUND_ATLAS, Rect2(center - Vector2(15, 17), Vector2(30, 24)),
		StackWorldView.ground_icon_region(kind))
	var counter := str(button.get_meta("charges", 0))
	var baseline := center + Vector2(-12, 16)
	button.draw_string_outline(StackWorldView.FONT, baseline, counter, HORIZONTAL_ALIGNMENT_CENTER, 24, 15, 3, DARK)
	button.draw_string(StackWorldView.FONT, baseline, counter, HORIZONTAL_ALIGNMENT_CENTER, 24, 15, CREAM)


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
