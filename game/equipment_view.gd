extends RefCounted

const ICONS := {
	"boots": preload("res://art/rocket_boots.png"),
	"helmet": preload("res://art/helmet.png"),
}
const NAMES := {"boots": "Ботинки-ракеты", "helmet": "Каска"}
const EFFECTS := {"boots": "Двойной прыжок", "helmet": "Разбивает ящики"}
const CREAM := Color("f4e3ba")
const GOLD := Color("e7b46b")
const MINT := Color("8dc6ac")
const DARK := Color("102c35")
const EDGE := Color("567679")
const HUD_START := 148.0
const HUD_SINGLE_WIDTH := 76.0
const HUD_PAIR_WIDTH := 64.0
const HUD_GAP := 8.0
const HUD_RIGHT := HUD_START + HUD_PAIR_WIDTH * 2.0 + HUD_GAP


static func build_offer(panel: PanelContainer, content: VBoxContainer, compact: bool,
		model: StackSimulation, button: Callable, text: Callable, resolve: Callable) -> void:
	var options := model.equipment_options()
	var tight := compact or (options.size() > 1 and panel.get_viewport_rect().size.x < 420.0)
	_frame(panel, GOLD, 10 if tight else 16)
	content.add_theme_constant_override("separation", 5 if tight else 9)
	if options.size() == 1:
		_offer_item(content, model, options[0], compact, false, button, text, resolve)
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		content.add_child(row)
		for item in options:
			var backing := PanelContainer.new()
			backing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			backing.add_theme_stylebox_override("panel", _style(DARK.darkened(.12), EDGE, 5))
			row.add_child(backing)
			var card := VBoxContainer.new()
			card.add_theme_constant_override("separation", 4)
			backing.add_child(card)
			_offer_item(card, model, item, compact, true, button, text, resolve)
	button.call(content, "Пропустить", "skip", resolve.bind(""))


static func _offer_item(parent: VBoxContainer, model: StackSimulation, item: String,
		compact: bool, paired: bool, button: Callable, text: Callable, resolve: Callable) -> void:
	var boots := item == "boots"
	var equipped := model.boots_equipped if boots else model.helmet_charges > 0
	var charges := model.boots_charges if boots else model.helmet_charges
	var capacity := StackSimulation.BOOTS_MAX_CHARGES if boots else StackSimulation.HELMET_MAX_CHARGES
	var prefix := "equipment" if boots else "helmet"
	var narrow_pair := paired and parent.get_viewport_rect().size.x < 420.0
	var title_size := 23 if compact else 26
	var effect_size := 17
	if paired:
		title_size = 15 if narrow_pair else 18
		effect_size = 12 if narrow_pair else 13
	_label(text, parent, NAMES[item], prefix + "_title", title_size, GOLD)

	var details := HBoxContainer.new()
	details.alignment = BoxContainer.ALIGNMENT_CENTER
	details.add_theme_constant_override("separation", 5 if paired else 16)
	parent.add_child(details)
	var badge := PanelContainer.new()
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_theme_stylebox_override("panel", _style(DARK.darkened(0.10), EDGE, 3))
	details.add_child(badge)
	var icon_size := 34 if paired else (54 if compact else 64)
	_picture(badge, ICONS[item], Vector2.ONE * icon_size)
	if equipped:
		_charge_change(details, charges, capacity, prefix, paired, text)

	_label(text, parent, EFFECTS[item], prefix + "_effect", effect_size, CREAM)
	var capacity_label := "%d удара" % capacity
	if boots:
		capacity_label = "%d прыжков" % capacity if paired else "%d прыжков в воздухе" % capacity
	_label(text, parent, capacity_label, prefix + "_capacity", 13 if paired else 14, MINT)
	var action: Button = button.call(parent, "Заменить" if equipped else "Надеть",
		"equip" if boots else "equip_helmet", resolve.bind(item))
	if paired:
		action.add_theme_font_size_override("font_size", 16)


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
	_picture(portrait, StackWorldView.pause_portrait(model.boots_equipped, model.helmet_charges > 0),
		Vector2(48, 66) if compact else Vector2(64, 84))

	var center := CenterContainer.new()
	loadout.add_child(center)
	var slots := GridContainer.new()
	slots.columns = 2
	slots.add_theme_constant_override("h_separation", 12)
	slots.add_theme_constant_override("v_separation", 2)
	center.add_child(slots)
	_equipment_slot(text, slots, "Голова", "slot_head", "helmet",
		model.helmet_charges if model.helmet_charges > 0 else -1, StackSimulation.HELMET_MAX_CHARGES)
	_slot_label(text, slots, "Руки", "slot_hands")
	_equipment_slot(text, slots, "Ноги", "slot_feet", "boots",
		model.boots_charges if model.boots_equipped else -1, StackSimulation.BOOTS_MAX_CHARGES)


static func _equipment_slot(text: Callable, slots: GridContainer, title: String, id: String,
		item: String, charges: int, capacity: int) -> void:
	if charges < 0:
		_slot_label(text, slots, title, id)
		return
	_slot_title(text, slots, title, id + "_title")
	var details := HBoxContainer.new()
	details.add_theme_constant_override("separation", 5)
	slots.add_child(details)
	_picture(details, ICONS[item], Vector2.ONE * 24)
	_label(text, details, "%d / %d" % [charges, capacity], id, 15, GOLD)


static func build_hud(parent: Control, item: String) -> Label:
	var plate := PanelContainer.new()
	plate.name = item + "_hud"
	plate.position = Vector2(HUD_START, 10)
	plate.size = Vector2(HUD_SINGLE_WIDTH, 46)
	plate.add_theme_stylebox_override("panel", _style(Color(0.055, 0.13, 0.16, 0.9), EDGE, 4))
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(plate)
	plate.draw.connect(_draw_rivets.bind(plate))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(row)
	_picture(row, ICONS[item], Vector2.ONE * 27)
	var count := Label.new()
	count.name = item + "_charges"
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override("font_size", 23)
	count.custom_minimum_size.x = 26
	row.add_child(count)
	plate.hide()
	return count


static func update_hud(boots: Label, helmet: Label, model: StackSimulation) -> void:
	var helmet_equipped := model.helmet_charges > 0
	var paired := model.boots_equipped and helmet_equipped
	var width := HUD_PAIR_WIDTH if paired else HUD_SINGLE_WIDTH
	_update_badge(boots, "boots", model.boots_equipped, model.boots_charges, HUD_START, width)
	var helmet_x := HUD_START + (HUD_PAIR_WIDTH + HUD_GAP if paired else 0.0)
	_update_badge(helmet, "helmet", helmet_equipped, model.helmet_charges, helmet_x, width)


static func _update_badge(count: Label, item: String, equipped: bool, charges: int,
		x: float, width: float) -> void:
	var plate := count.get_parent().get_parent() as PanelContainer
	if plate.visible != equipped:
		plate.visible = equipped
	plate.position.x = x
	plate.size.x = width
	var value := str(charges)
	if count.text != value:
		count.text = value
		count.accessibility_name = "%s · %s" % [NAMES[item], value]


static func _charge_change(parent: Control, before: int, after: int, prefix: String,
		paired: bool, text: Callable) -> void:
	var comparison := VBoxContainer.new()
	comparison.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	comparison.add_theme_constant_override("separation", 1)
	parent.add_child(comparison)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 3 if paired else 6)
	comparison.add_child(row)
	var font_size := 19 if paired else 27
	_label(text, row, str(before), prefix + "_old_charges", font_size, CREAM)
	var arrow := Control.new()
	arrow.custom_minimum_size = Vector2(20, 14)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(arrow)
	arrow.draw.connect(_draw_arrow.bind(arrow))
	_label(text, row, str(after), prefix + "_new_charges", font_size, GOLD)
	_label(text, comparison, "заряды", prefix + "_charge_label", 12 if paired else 13, MINT)


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


static func _draw_arrow(arrow: Control) -> void:
	var points := PackedVector2Array([Vector2(12, 2), Vector2(17, 7), Vector2(12, 12)])
	arrow.draw_polyline(points, CREAM, 2)
	arrow.draw_line(Vector2(2, 7), Vector2(17, 7), CREAM, 2)
