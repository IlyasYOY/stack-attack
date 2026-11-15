class_name StackProfile
extends RefCounted
const SAVE_PATH := "user://stack-attack-profile-v1.json"
const SAVE_VERSION := 2
const MATCH_METRICS := ["duration_ms", "score", "lines", "crates", "best_combo"]
const MAX_EXACT_JSON_INTEGER := 9007199254740991
const DAYS_IN_MONTH := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
static var _timestamp_pattern := RegEx.create_from_string(
	r"\A([0-9]{4})-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]\z")
var music := 0.45
var effects := 0.75
var vibration := true
var records: Array[Dictionary] = []
var matches: Array[Dictionary] = []
var last_error := ""
var path: String


func _init(save_path: String = SAVE_PATH) -> void:
	path = save_path
	load_profile()


func _volume(value: Variant, fallback: float) -> float:
	if (value is float or value is int) and is_finite(float(value)):
		return clampf(float(value), 0.0, 1.0)
	return fallback


func _valid_timestamp(value: Variant) -> bool:
	if not value is String:
		return false
	var parts := _timestamp_pattern.search(value)
	if parts == null:
		return false
	var year := int(parts.get_string(1))
	var month := int(parts.get_string(2))
	var is_leap_year := year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)
	var max_day: int = DAYS_IN_MONTH[month - 1] + int(month == 2 and is_leap_year)
	return int(parts.get_string(3)) <= max_day


func _validated_match(entry: Variant) -> Dictionary:
	if not entry is Dictionary:
		return {}
	var ended_at: Variant = entry.get("ended_at")
	var reason: Variant = entry.get("reason")
	if not _valid_timestamp(ended_at) or reason not in ["crushed", "overflow"]:
		return {}
	var result := {"ended_at": ended_at, "reason": reason}
	for key in MATCH_METRICS:
		var value: Variant = entry.get(key)
		if not (value is int or value is float):
			return {}
		if not is_finite(value) or value < 0 or value > MAX_EXACT_JSON_INTEGER or value != floorf(value):
			return {}
		result[key] = int(value)
	return result


func load_profile() -> void:
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "Не удалось прочитать сохранение"
		return
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		last_error = "Сохранение повреждено. Использованы начальные настройки."
		return
	var data: Dictionary = parser.data
	music = _volume(data.get("music"), music)
	effects = _volume(data.get("effects"), effects)
	if data.get("vibration") is bool:
		vibration = data.vibration
	records.clear()
	var saved: Variant = data.get("records", [])
	if saved is Array:
		for entry in saved:
			if entry is Dictionary and (entry.get("score") is float or entry.get("score") is int):
				if not is_finite(float(entry.score)):
					continue
				var value := int(entry.score)
				if value >= 0 and value <= 100000000:
					records.append({"score": value, "date": str(entry.get("date", "")).left(32)})
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.score) > int(b.score))
	if records.size() > 10:
		records.resize(10)
	matches.clear()
	var saved_matches: Variant = data.get("matches", [])
	if saved_matches is Array:
		for entry in saved_matches:
			var result := _validated_match(entry)
			if not result.is_empty():
				matches.append(result)


func save_profile() -> bool:
	last_error = ""
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "Не удалось сохранить данные"
		return false
	var contents := JSON.stringify({"version": SAVE_VERSION, "music": music,
		"effects": effects, "vibration": vibration, "records": records, "matches": matches}, "", true, true).to_utf8_buffer()
	var stored := file.store_buffer(contents)
	file.flush()
	file.close()
	# Godot's flush does not report errors. Check the complete temporary file before replacing the save.
	if not stored or FileAccess.get_file_as_bytes(temporary) != contents or DirAccess.rename_absolute(temporary, path) != OK:
		DirAccess.remove_absolute(temporary)
		last_error = "Не удалось сохранить данные"
		return false
	return true


func add_match(result: Dictionary) -> void:
	var entry := _validated_match(result)
	if entry.is_empty():
		return
	matches.push_front(entry)
	save_profile()


func statistics() -> Dictionary:
	var result := {"played": matches.size(), "best_score": 0,
		"total_lines": 0, "total_crates": 0, "max_lines": 0, "best_combo": 0,
		"crushed": 0, "overflow": 0, "average_duration_ms": 0, "max_duration_ms": 0}
	var total_duration_ms := 0.0
	for record in records:
		result.best_score = maxi(result.best_score, record.score)
	for entry in matches:
		result.best_score = maxi(result.best_score, entry.score)
		result.total_lines += entry.lines
		result.total_crates += entry.crates
		result.max_lines = maxi(result.max_lines, entry.lines)
		result.best_combo = maxi(result.best_combo, entry.best_combo)
		result[entry.reason] += 1
		result.max_duration_ms = maxi(result.max_duration_ms, entry.duration_ms)
		total_duration_ms += entry.duration_ms
	if not matches.is_empty():
		result.average_duration_ms = roundi(total_duration_ms / matches.size())
	return result
