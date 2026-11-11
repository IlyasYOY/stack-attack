extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var scene = load("res://scenes/technical_test.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	_check(scene.input_count == 0, "Input counter must start at zero")
	_check(scene.content.get_node("Notice").text.contains("ТЕХНИЧЕСКИЙ ТЕСТ"),
		"The scene must identify itself as a technical test")
	# Activate the connected button signal, rather than calling its handler.
	scene.input_button.pressed.emit()
	scene.input_button.pressed.emit()
	_check(scene.input_count == 2, "Each button activation must count exactly once")
	_check(scene.content.get_node("Status").text == "Нажатий: 2", "Counter must be visible")
	for dimensions in [Vector2i(360, 780), Vector2i(780, 360)]:
		root.size = dimensions
		await process_frame
		await process_frame
		var expected := "landscape" if dimensions.x > dimensions.y else "portrait"
		_check(scene.layout_name == expected, "Orientation must follow the viewport")
		_check(scene.input_count == 2, "Resizing must preserve the input counter")
		_check(scene.input_button.size.y >= 52, "Button must retain its minimum height")
	scene.queue_free()
	await process_frame
	if not failures.is_empty():
		for failure in failures:
			printerr("TECH_TEST_FAILED: " + failure)
		quit(1)
		return
	print("TECH_TEST_PASS: scene, button signal, counter and both orientations")
	quit(0)
