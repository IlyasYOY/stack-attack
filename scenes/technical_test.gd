extends Control
## A launch, layout and input diagnostic; not a gameplay prototype.

var input_count: int = 0
var layout_name: String = ""

@onready var content: VBoxContainer = $Margin/Scroll/Content
@onready var input_button: Button = $Margin/Scroll/Content/InputButton


func _ready() -> void:
	content.get_node("Platform").text = "%s · Godot %s" % [
		OS.get_name(), Engine.get_version_info()["string"]
	]
	input_button.pressed.connect(_on_input_pressed)
	input_button.item_rect_changed.connect(_publish_browser_status)
	get_viewport().size_changed.connect(_update_layout)
	_update_layout()
	print("STACK_ATTACK_TECH_READY")


func _update_layout() -> void:
	var viewport_size := get_viewport_rect().size
	layout_name = "landscape" if viewport_size.x > viewport_size.y else "portrait"
	var description := "Альбомный режим" if layout_name == "landscape" else "Портретный режим"
	content.get_node("Layout").text = description
	_publish_browser_status()


func _on_input_pressed() -> void:
	input_count += 1
	content.get_node("Status").text = "Нажатий: %d" % input_count
	_publish_browser_status()


func _publish_browser_status() -> void:
	if not OS.has_feature("web"):
		return
	# Only the technical Web test reads this diagnostic object.
	var button_rect := input_button.get_global_rect()
	var viewport_size := get_viewport_rect().size
	var status := {
		"ready": true,
		"layout": layout_name,
		"clicks": input_count,
		"viewport": [viewport_size.x, viewport_size.y],
		"button": [button_rect.position.x, button_rect.position.y,
			button_rect.size.x, button_rect.size.y],
	}
	JavaScriptBridge.eval("window.stackAttackTech = " + JSON.stringify(status))
