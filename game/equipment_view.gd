extends RefCounted

const BOOTS_ICON: Texture2D = preload("res://art/spring_boots.png")
const BOOTS_NAME := "Пружинные ботинки"
const BOOTS_EFFECT := "Двойной прыжок"
const CREAM := Color("f4e3ba")
const GOLD := Color("e7b46b")
const MINT := Color("8dc6ac")
const DARK := Color("102c35")
const EDGE := Color("567679")
const HUD_RIGHT := 224.0


static func build_offer(panel: PanelContainer, content: VBoxContainer, compact: bool,
		previous_charges: int, max_charges: int, button: Callable, text: Callable,
		accept: Callable, skip: Callable) -> void:
	_frame(panel, GOLD, 10 if compact else 16)
	content.add_theme_constant_override("separation", 5 if compact else 9)
	_label(text, content, BOOTS_NAME, "equipment_title", 23 if compact else 26, GOLD)
	var replacement := previous_charges >= 0
	var item := HBoxContainer.new()
	item.alignment = BoxContainer.ALIGNMENT_CENTER
	item.add_theme_constant_override("separation", 16)
	content.add_child(item)
	var badge := PanelContainer.new()
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_theme_stylebox_override("panel", _style(DARK.darkened(0.10), EDGE, 3))
	item.add_child(badge)
	_picture(badge, BOOTS_ICON, Vector2.ONE * (54 if compact else 64))
	if replacement:
		_charge_change(item, previous_charges, max_charges, text)
	_label(text, content, BOOTS_EFFECT, "equipment_effect", 17, CREAM)
	_label(text, content, "%d прыжков в воздухе" % max_charges, "equipment_capacity", 14, MINT)
	var actions: Control = content
	if replacement:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		content.add_child(row)
		actions = row
	var equip: Button = button.call(actions, "Заменить" if replacement else "Надеть", "equip", accept)
	var pass_offer: Button = button.call(actions, "Пропустить", "skip", skip)
	if replacement:
		equip.add_theme_font_size_override("font_size", 16)
		pass_offer.add_theme_font_size_override("font_size", 16)


static func build_pause(panel: PanelContainer, content: VBoxContainer, compact: bool,
		boots_equipped: bool, charges: int, max_charges: int, text: Callable) -> void:
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
	_picture(portrait, StackWorldView.pause_portrait(boots_equipped),
		Vector2(48, 66) if compact else Vector2(64, 84))

	var center := CenterContainer.new()
	loadout.add_child(center)
	var slots := GridContainer.new()
	slots.columns = 2
	slots.add_theme_constant_override("h_separation", 12)
	slots.add_theme_constant_override("v_separation", 2)
	center.add_child(slots)
	_slot_label(text, slots, "Голова", "slot_head")
	_slot_label(text, slots, "Руки", "slot_hands")
	var feet_title := _slot_title(text, slots, "Ноги", "slot_feet_title")
	feet_title.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	if boots_equipped:
		var feet := VBoxContainer.new()
		feet.add_theme_constant_override("separation", 1)
		slots.add_child(feet)
		var details := HBoxContainer.new()
		details.add_theme_constant_override("separation", 5)
		feet.add_child(details)
		_picture(details, BOOTS_ICON, Vector2.ONE * 24)
		_label(text, details, "%d / %d" % [charges, max_charges], "slot_feet", 15, GOLD)
		_label(text, feet, BOOTS_EFFECT, "slot_feet_effect", 12, MINT)
	else:
		var empty := _label(text, slots, "—", "slot_feet", 15, MINT)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


static func build_hud(parent: Control) -> Label:
	var plate := PanelContainer.new()
	plate.name = "boots_hud"
	plate.position = Vector2(148, 10)
	plate.size = Vector2(76, 46)
	plate.add_theme_stylebox_override("panel", _style(Color(0.055, 0.13, 0.16, 0.9), EDGE, 4))
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(plate)
	plate.draw.connect(_draw_rivets.bind(plate))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(row)
	_picture(row, BOOTS_ICON, Vector2.ONE * 32)
	var count := Label.new()
	count.name = "boots_charges"
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override("font_size", 23)
	count.custom_minimum_size.x = 27
	row.add_child(count)
	plate.hide()
	return count


static func update_hud(count: Label, equipped: bool, charges: int) -> void:
	var plate := count.get_parent().get_parent() as PanelContainer
	if plate.visible != equipped:
		plate.visible = equipped
	var value := str(charges)
	if count.text != value:
		count.text = value
		count.accessibility_name = "%s · %s" % [BOOTS_NAME, value]


static func _charge_change(parent: Control, before: int, after: int, text: Callable) -> void:
	var comparison := VBoxContainer.new()
	comparison.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	comparison.add_theme_constant_override("separation", 1)
	parent.add_child(comparison)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	comparison.add_child(row)
	_label(text, row, str(before), "equipment_old_charges", 27, CREAM)
	var arrow := Control.new()
	arrow.custom_minimum_size = Vector2(20, 14)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(arrow)
	arrow.draw.connect(_draw_arrow.bind(arrow))
	_label(text, row, str(after), "equipment_new_charges", 27, GOLD)
	_label(text, comparison, "заряды", "equipment_charge_label", 13, MINT)


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
