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
const SLOTS := {"feet": ["boots", "speed_boots", "spring_boots"],
	"head": ["helmet", "lamp_helmet"], "hands": ["gloves", "mallet", "strong_arms"]}
const NAMES := {"boots": "Ботинки-ракеты", "helmet": "Каска", "gloves": "Рабочие перчатки",
	"mallet": "Киянка", "strong_arms": "Накачанные руки", "speed_boots": "Сапоги-скороходы",
	"lamp_helmet": "Каска с фонарём", "spring_boots": "Пружинные ботинки"}
const EFFECTS := {"boots": "Рывки в воздухе", "helmet": "Разбивает ящики", "gloves": "Тянут ящики",
	"mallet": "Бьёт ящик спереди", "strong_arms": "Толкают 2 ящика", "speed_boots": "Ускоряют бег",
	"lamp_helmet": "Показывает сбросы", "spring_boots": "Прыжок с зарядкой"}
const CAPACITIES := {"boots": StackSimulation.BOOTS_MAX_CHARGES, "helmet": StackSimulation.HELMET_MAX_CHARGES,
	"gloves": StackSimulation.GLOVES_MAX_CHARGES, "mallet": StackSimulation.MALLET_MAX_CHARGES,
	"strong_arms": StackSimulation.STRONG_ARMS_MAX_CHARGES, "speed_boots": StackSimulation.SPEED_BOOTS_MAX_CHARGES,
	"lamp_helmet": StackSimulation.LAMP_HELMET_MAX_CHARGES, "spring_boots": StackSimulation.SPRING_BOOTS_MAX_CHARGES}
const CHARGE_UNITS := {"boots": "рывков", "helmet": "удара", "gloves": "подтягиваний", "mallet": "удара",
	"strong_arms": "клеток", "speed_boots": "клеток", "lamp_helmet": "включения", "spring_boots": "зарядов"}
const CREAM := Color("f4e3ba")
const GOLD := Color("e7b46b")
const MINT := Color("8dc6ac")
const DARK := Color("102c35")
const EDGE := Color("567679")
const HUD_START := 148.0
const HUD_SINGLE_WIDTH := 76.0
const HUD_PAIR_WIDTH := 64.0
const HUD_GAP := 8.0
const HUD_TRIPLE_WIDTH := 46.0
const HUD_TRIPLE_GAP := 3.0
const HUD_RIGHT := HUD_START + HUD_TRIPLE_WIDTH * 3.0 + HUD_TRIPLE_GAP * 2.0
const SPRING_COLORS := [Color("8bdb64"), Color("f2d858"), Color("f1a047"), Color("e66252")]
const OFFER_MAX_WIDTH := 520.0


static func build_offer(panel: PanelContainer, content: VBoxContainer, compact: bool,
		model: StackSimulation, button: Callable, text: Callable, resolve: Callable) -> void:
	var options := model.equipment_options()
	var width := minf(OFFER_MAX_WIDTH, panel.get_viewport_rect().size.x - 32.0)
	var narrow := width < 395.0
	var margin := 10 if compact or narrow else 14
	var gap := 5 if compact else 7
	var charges := _loadout_charges(model)
	_frame(panel, GOLD, margin)
	content.add_theme_constant_override("separation", gap)
	if not options.is_empty():
		var grid := GridContainer.new()
		grid.columns = 2 if options.size() > 1 else 1
		grid.add_theme_constant_override("h_separation", gap)
		grid.add_theme_constant_override("v_separation", gap)
		content.add_child(grid)
		var card_width := (width - margin * 2 - gap * (grid.columns - 1)) / grid.columns
		for item in options:
			_offer_card(grid, item, charges[item], _equipped_alternative(item, charges), card_width,
				compact, narrow, button, text, resolve)
	button.call(content, "Пропустить", "skip", resolve.bind(""))


static func _loadout_charges(model: StackSimulation) -> Dictionary:
	return {"boots": model.boots_charges if model.boots_equipped else -1,
		"speed_boots": model.speed_boots_charges if model.speed_boots_charges > 0 else -1,
		"spring_boots": model.spring_boots_charges if model.spring_boots_charges > 0 else -1,
		"helmet": model.helmet_charges if model.helmet_charges > 0 else -1,
		"lamp_helmet": model.lamp_helmet_charges if model.lamp_helmet_equipped else -1,
		"gloves": model.gloves_charges if model.gloves_charges > 0 else -1,
		"mallet": model.mallet_charges if model.mallet_charges > 0 else -1,
		"strong_arms": model.strong_arms_charges if model.strong_arms_charges > 0 else -1}


static func _equipped_item(slot: String, charges: Dictionary) -> String:
	for item: String in SLOTS[slot]:
		if charges[item] >= 0:
			return item
	return SLOTS[slot][0]


static func _equipped_alternative(item: String, charges: Dictionary) -> bool:
	for slot in SLOTS:
		if item in SLOTS[slot]:
			var equipped := _equipped_item(slot, charges)
			return item != equipped and charges[equipped] >= 0
	return false


static func _offer_card(parent: GridContainer, item: String, charges: int, replaces: bool,
		width: float, compact: bool, narrow: bool, button: Callable, text: Callable, resolve: Callable) -> void:
	var action: Button = button.call(parent, "", "equip" if item == "boots" else "equip_" + item, resolve.bind(item))
	action.custom_minimum_size = Vector2(48, 51 if compact else 64)
	var verb := "Пополнить" if charges >= 0 else ("Заменить" if replaces else "Надеть")
	action.accessibility_name = "%s · %s" % [verb, NAMES[item]]
	action.tooltip_text = action.accessibility_name
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	action.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -8
	var icon_size := 24 if narrow else 32
	_picture(row, ICONS[item], Vector2.ONE * icon_size)

	var details := VBoxContainer.new()
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_theme_constant_override("separation", 0)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(details)
	var prefix := "equipment" if item == "boots" else item
	var available := width - icon_size - 22.0
	var title := "Перчатки" if item == "gloves" and narrow else str(NAMES[item])
	_offer_label(text, details, title, prefix + "_title", 14 if narrow else 16, available, GOLD)
	_offer_label(text, details, EFFECTS[item], prefix + "_effect", 11 if narrow else 13, available, CREAM)
	if charges >= 0:
		_charge_change(details, charges, CAPACITIES[item], prefix, text)
	else:
		var capacity := "%d %s" % [CAPACITIES[item], CHARGE_UNITS[item]]
		if replaces:
			capacity = "Замена · %d" % CAPACITIES[item] if narrow else "Замена · " + capacity
		_offer_label(text, details, capacity, prefix + "_capacity", 11 if narrow else 13, available, MINT)


static func _offer_label(text: Callable, parent: Control, value: String, id: String, font_size: int,
		width: float, color: Color) -> void:
	var label := _label(text, parent, value, id, font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.clip_text = true
	var font := label.get_theme_font("font")
	while font_size > 9 and font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)


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
	plate.position = Vector2(HUD_START, 10)
	plate.size = Vector2(HUD_SINGLE_WIDTH, 46)
	plate.add_theme_stylebox_override("panel", _style(Color(0.055, 0.13, 0.16, 0.9), EDGE, 2))
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(plate)
	plate.draw.connect(_draw_rivets.bind(plate))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(row)
	_picture(row, ICONS[item], Vector2.ONE * 27)
	if item == "spring_boots":
		row.add_theme_constant_override("separation", 1)
		var meter := Control.new()
		meter.name = "spring_charge_meter"
		meter.custom_minimum_size = Vector2(7, 27)
		meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		meter.draw.connect(_draw_spring_charge.bind(meter))
		row.add_child(meter)
	var count := Label.new()
	count.name = item + "_charges"
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.add_theme_font_size_override("font_size", 23)
	count.custom_minimum_size.x = 26
	row.add_child(count)
	plate.hide()
	return count


static func update_hud(badges: Dictionary, model: StackSimulation, spring_peak: int = 0,
		spring_peak_limit: int = 0) -> void:
	var charges := _loadout_charges(model)
	if spring_peak > 0:
		charges.spring_boots = model.spring_boots_charges
	var visible_count := charges.size() - charges.values().count(-1)
	var width := HUD_TRIPLE_WIDTH if visible_count == 3 else (HUD_PAIR_WIDTH if visible_count == 2 else HUD_SINGLE_WIDTH)
	var gap := HUD_TRIPLE_GAP if visible_count == 3 else HUD_GAP
	var x := HUD_START
	for item in badges:
		var charge_count: int = charges[item]
		_update_badge(badges[item], item, charge_count, x, width, visible_count)
		if charge_count >= 0:
			x += width + gap
	var spring: Label = badges.spring_boots
	var meter := spring.get_parent().get_node("spring_charge_meter") as Control
	var stages := maxi(model.spring_charge_stages, spring_peak)
	var limit := spring_peak_limit if spring_peak > 0 else model.spring_charge_limit()
	if meter.get_meta("limit", 0) != limit or meter.get_meta("stages", 0) != stages:
		meter.set_meta("limit", limit)
		meter.set_meta("stages", stages)
		meter.queue_redraw()


static func _update_badge(count: Label, item: String, charges: int, x: float, width: float,
		visible_count: int) -> void:
	var row := count.get_parent() as HBoxContainer
	var plate := row.get_parent() as PanelContainer
	plate.visible = charges >= 0
	if charges < 0:
		return
	var value := str(charges)
	if count.text != value:
		count.text = value
		count.accessibility_name = "%s · %s" % [NAMES[item], value]
	var tight := visible_count == 3
	var font_size := 16 if tight else (20 if visible_count == 2 else 23)
	if count.get_theme_font_size("font_size") != font_size:
		count.add_theme_font_size_override("font_size", font_size)
		count.custom_minimum_size.x = (15 if tight else 22) if item == "spring_boots" else (22 if tight else 26)
		var icon := row.get_child(0) as TextureRect
		icon.custom_minimum_size = Vector2.ONE * ((14 if item == "spring_boots" else 16) if tight else 27)
	elif item == "spring_boots" and not tight:
		count.custom_minimum_size.x = 22
	plate.position.x = x
	plate.size.x = width


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


static func _charge_change(parent: Control, before: int, after: int, prefix: String, text: Callable) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)
	_label(text, row, str(before), prefix + "_old_charges", 12, CREAM)
	var arrow := Control.new()
	arrow.custom_minimum_size = Vector2(20, 14)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(arrow)
	arrow.draw.connect(_draw_arrow.bind(arrow))
	_label(text, row, str(after), prefix + "_new_charges", 12, GOLD)


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


static func _draw_arrow(arrow: Control) -> void:
	var points := PackedVector2Array([Vector2(12, 2), Vector2(17, 7), Vector2(12, 12)])
	arrow.draw_polyline(points, CREAM, 2)
	arrow.draw_line(Vector2(2, 7), Vector2(17, 7), CREAM, 2)
