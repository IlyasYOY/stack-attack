extends RefCounted

const CREAM := Color("f4e3ba")
const MINT := Color("8dc6ac")
const GOLD := Color("d7a45a")
const ROW_HEIGHT := 57
const EXPANDED_HEIGHT := 84
const ACTION_HEIGHT := 48
const ROW_GAP := 5
const CRUSHED := "Придавило ящиком"
const OVERFLOW := "Склад переполнен"


static func loss_description(reason: String) -> String:
	match reason:
		"crushed":
			return CRUSHED
		"overflow":
			return OVERFLOW
		"metal_crushed":
			return "Придавило железом"
		"trap":
			return "Попался в капкан"
		"mechanic":
			return "Сбит падением мастера"
	return ""


static func build(content: VBoxContainer, available: Vector2, stats: Dictionary, matches: Array,
		legacy: Array, first_match: int, expanded_match: int, button: Callable, text: Callable,
		change: Callable, back: Callable) -> void:
	var compact := available.y < 430
	var gap := 5 if compact else 10
	content.add_theme_constant_override("separation", gap)
	var title := _label(text, content, "Статистика", "statistics_heading", 23 if compact else 28, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var summary_height := _summary(content, available.x, compact, stats, text)

	var heading := HBoxContainer.new()
	content.add_child(heading)
	var history_title := _label(text, heading, "История матчей", "history_heading", 15, GOLD)
	history_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var history_range := _label(text, heading, "", "history_range", 12, MINT)
	history_range.hide()
	var total := matches.size() + legacy.size()
	if total == 0:
		var empty := _label(text, content, "Партий пока нет", "empty_history", 14, MINT)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.call(content, "Назад", "back", back)
		return

	var expanded := expanded_match >= 0 and expanded_match < total
	# Reserve the expanded row on every page so toggling details leaves page boundaries in place.
	var room := available.y - _line_height(title) - summary_height - _line_height(history_title) - 4 * gap - ACTION_HEIGHT
	room -= EXPANDED_HEIGHT - ROW_HEIGHT
	var page_size := clampi(floori((room + ROW_GAP) / (ROW_HEIGHT + ROW_GAP)), 1, 5)
	var start := clampi(first_match, 0, total - 1)
	if expanded:
		start = clampi(start, maxi(0, expanded_match - page_size + 1), expanded_match)
	var end := mini(total, start + page_size)
	if end - start < total:
		var shown := str(end) if end - start == 1 else "%d-%d" % [start + 1, end]
		history_range.text = "%s / %d" % [shown, total]
		history_range.show()
	var old_records := legacy.duplicate()
	old_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _legacy_date_key(str(a.date)) > _legacy_date_key(str(b.date)))
	var history := VBoxContainer.new()
	history.add_theme_constant_override("separation", ROW_GAP)
	content.add_child(history)
	for index in range(start, end):
		var old := index >= matches.size()
		var match_entry: Dictionary = old_records[index - matches.size()] if old else matches[index]
		var is_open := index == expanded_match
		var toggle := change.bind(start, -1 if is_open else index)
		_history_row(history, available.x, match_entry, index, old, is_open, button, text, toggle)
	_navigation(content, start, end, total, page_size, button, change, back)


static func _summary(parent: Control, width: float, compact: bool, stats: Dictionary, text: Callable) -> float:
	var plate := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.13, 0.16, 0.91)
	style.border_color = Color(0.55, 0.65, 0.63, 0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(5 if compact else 12)
	plate.add_theme_stylebox_override("panel", style)
	parent.add_child(plate)
	var column := VBoxContainer.new()
	var section_gap := 4 if compact else 8
	column.add_theme_constant_override("separation", section_gap)
	plate.add_child(column)
	var grid := GridContainer.new()
	grid.columns = 3 if width >= 525 else 2
	grid.add_theme_constant_override("h_separation", 12)
	var row_gap := 2 if compact else 8
	grid.add_theme_constant_override("v_separation", row_gap)
	column.add_child(grid)
	var cell_width := (width - style.get_minimum_size().x - 12 * (grid.columns - 1)) / grid.columns
	var played: int = stats.get("played", 0)
	var time := "%s / %s" % [_duration(stats.get("average_duration_ms", 0)), _duration(stats.get("max_duration_ms", 0))]
	var metrics := [
		["played", "Сыграно", str(played)],
		["best_score", "Лучший счёт", str(stats.get("best_score", 0))],
		["lines_crates", "Ряды / Ящики", "%s / %s" % [stats.get("total_lines", 0), stats.get("total_crates", 0)]],
		["max_lines", "Макс. рядов", str(stats.get("max_lines", 0))],
		["best_combo", "Лучшее комбо", "x%d" % stats.get("best_combo", 0)],
		["duration", "Время: ср. / макс.", time if played > 0 else "— / —"],
		["broken_crates", "Учтено сломанных", str(stats.get("total_broken_crates", "—"))],
	]
	var row_height := 0.0
	for metric in metrics:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
		var caption := _label(text, cell, metric[1], metric[0], 11 if compact else 12, MINT)
		_fit(caption, cell_width)
		var value := _label(text, cell, metric[2], metric[0] + "_value", 15 if compact else 18, GOLD)
		_fit(value, cell_width)
		row_height = maxf(row_height, _line_height(caption) + _line_height(value))

	var losses := HBoxContainer.new()
	losses.add_theme_constant_override("separation", 12)
	column.add_child(losses)
	var crushed := _label(text, losses, "%s %d" % [CRUSHED, stats.get("crushed", 0)], "crushed", 11 if compact else 12, CREAM)
	crushed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fit(crushed, (width - style.get_minimum_size().x) * 0.44)
	var overflow := _label(text, losses, "%s %d" % [OVERFLOW, stats.get("overflow", 0)], "overflow", 11 if compact else 12, CREAM)
	_fit(overflow, (width - style.get_minimum_size().x) * 0.50)
	var rows := ceili(float(metrics.size()) / grid.columns)
	return style.get_minimum_size().y + rows * row_height + (rows - 1) * row_gap + section_gap + maxf(_line_height(crushed), _line_height(overflow))


static func _history_row(parent: Control, width: float, entry: Dictionary, index: int, old: bool,
		is_open: bool, button: Callable, text: Callable, toggle: Callable) -> void:
	var id := "match_%d" % index
	var row: Button = button.call(parent, "", id, toggle)
	row.custom_minimum_size.y = EXPANDED_HEIGHT if is_open else ROW_HEIGHT
	var date := str(entry.date) if old else _local_date(str(entry.ended_at), is_open)
	if date.is_empty():
		date = "Дата не сохранена"
	var score := str(entry.score)
	var reason := loss_description(str(entry.get("reason", "")))
	var duration := _duration(entry.get("duration_ms", 0))
	row.accessibility_name = "%s, счёт %s, %s" % [date, score, "Старый рекорд" if old else reason]
	row.accessibility_description = "Свернуть" if is_open else "Показать подробности"

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	row.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var body := VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", 2)
	margin.add_child(body)
	var header := _line(body)
	var date_label := _label(text, header, date, id + "_date", 13, CREAM)
	date_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fit(date_label, (width - 66) * 0.62)
	var score_label := _label(text, header, score, id + "_score", 16, GOLD)
	_fit(score_label, (width - 66) * 0.38)
	_label(text, header, "-" if is_open else "+", id + "_toggle", 14, MINT)
	if old:
		_label(text, body, "Старый рекорд", id + "_legacy", 12, MINT)
		if is_open:
			_label(text, body, "Сохранены дата и счёт", id + "_legacy_details", 12, CREAM)
		return
	if not is_open:
		_pair(text, body, width, reason, id + "_status", duration, id + "_short_duration")
		var preview := "Ряды %s · Ящики %s · x%s" % [entry.lines, entry.crates, entry.best_combo]
		_fit(_label(text, body, preview, id + "_preview", 11, MINT), width - 32)
		return
	_pair(text, body, width, "Длительность " + duration, id + "_duration", reason, id + "_reason")
	_pair(text, body, width, "Ряды %s" % entry.lines, id + "_lines", "Ящики %s" % entry.crates, id + "_crates")
	_pair(text, body, width, "Лучшее комбо x%s" % entry.best_combo, id + "_combo",
		"Сломано %s" % entry.get("broken_crates", "—"), id + "_broken_crates")


static func _pair(text: Callable, parent: Control, width: float, left: String, left_id: String,
		right: String, right_id: String) -> void:
	var line := _line(parent)
	var left_label := _label(text, line, left, left_id, 12, MINT)
	left_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fit(left_label, (width - 42) * 0.58)
	_fit(_label(text, line, right, right_id, 12, MINT), (width - 42) * 0.42)


static func _navigation(parent: Control, start: int, end: int, total: int, page_size: int,
		button: Callable, change: Callable, back: Callable) -> void:
	if end - start == total:
		button.call(parent, "Назад", "back", back)
		return
	var line := _line(parent)
	var previous: Control
	if start > 0:
		previous = button.call(line, "«", "history_previous", change.bind(maxi(0, start - page_size), -1))
		previous.accessibility_name = "Предыдущая страница"
	else:
		previous = Control.new()
		line.add_child(previous)
	previous.size_flags_horizontal = Control.SIZE_FILL
	previous.custom_minimum_size.x = ACTION_HEIGHT
	button.call(line, "Назад", "back", back)
	var next: Control
	if end < total:
		next = button.call(line, "»", "history_next", change.bind(end, -1))
		next.accessibility_name = "Следующая страница"
	else:
		next = Control.new()
		line.add_child(next)
	next.size_flags_horizontal = Control.SIZE_FILL
	next.custom_minimum_size.x = ACTION_HEIGHT


static func _line(parent: Control) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 8)
	parent.add_child(line)
	return line


static func _label(text: Callable, parent: Control, value: String, id: String, font_size: int, color: Color) -> Label:
	var label: Label = text.call(parent, value, font_size, color)
	label.name = id
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	return label


static func _fit(label: Label, width: float) -> void:
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	while font_size > 6 and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)


static func _line_height(label: Label) -> float:
	return ceilf(label.get_theme_font("font").get_height(label.get_theme_font_size("font_size")))


static func _local_date(value: String, seconds: bool) -> String:
	return "%s.%s.%s %s" % [value.substr(8, 2), value.substr(5, 2), value.substr(0, 4), value.substr(11, 8 if seconds else 5)]


static func _legacy_date_key(date: String) -> String:
	var parts := date.split(".")
	if parts.size() == 3 and parts[0].length() == 2 and parts[1].length() == 2 and parts[2].length() == 4:
		return parts[2] + parts[1] + parts[0]
	return ""


@warning_ignore("integer_division")
static func _duration(milliseconds: int) -> String:
	var seconds := milliseconds / 1000
	var minutes := seconds / 60
	if minutes >= 60:
		return "%d:%02d:%02d" % [minutes / 60, minutes % 60, seconds % 60]
	return "%02d:%02d" % [minutes, seconds % 60]
