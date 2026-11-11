class_name StackProfile
extends RefCounted
const SAVE_PATH := "user://stack-attack-profile-v1.json"
var music := 0.45
var effects := 0.75
var vibration := true
var records: Array[Dictionary] = []
var last_error := ""
var path: String


func _init(save_path: String = SAVE_PATH) -> void:
	path = save_path
	load_profile()


func _volume(value: Variant, fallback: float) -> float:
	if (value is float or value is int) and is_finite(float(value)):
		return clampf(float(value), 0.0, 1.0)
	return fallback


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


func save_profile() -> bool:
	last_error = ""
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "Не удалось сохранить данные"
		return false
	file.store_string(JSON.stringify({"version": 1, "music": music,
		"effects": effects, "vibration": vibration, "records": records}))
	file.flush()
	file.close()
	if DirAccess.rename_absolute(temporary, path) != OK:
		last_error = "Не удалось сохранить данные"
		return false
	return true


func add_result(value: int) -> void:
	var now := Time.get_datetime_dict_from_system()
	var date := "%02d.%02d.%04d" % [now.day, now.month, now.year]
	records.append({"score": maxi(0, value), "date": date})
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.score) > int(b.score))
	if records.size() > 10:
		records.resize(10)
	save_profile()
