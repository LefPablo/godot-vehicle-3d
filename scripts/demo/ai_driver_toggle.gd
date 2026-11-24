extends Node
## Demo: "toggle_ai_driver" (H) lets the AI drive the Car on the road, and
## gives it back to the player.
##
## Turning the AI on puts the player in the Car (so the camera follows it),
## wherever they are. Turning it off leaves the player driving the Car.

const ACTION_TOGGLE := &"toggle_ai_driver"

@export var driver: VehicleAIDriver
@export var switcher: Node


func _ready() -> void:
	if not InputMap.has_action(ACTION_TOGGLE):
		InputMap.add_action(ACTION_TOGGLE)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_H
		InputMap.action_add_event(ACTION_TOGGLE, key)
	if driver:
		driver.turning.connect(_on_turning)


func _on_turning(kind: String, junction: Node, to_road: Node) -> void:
	_message("AI: %s at %s onto %s" % [kind, junction.name, to_road.name])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_TOGGLE):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if driver == null or driver.vehicle == null:
		return
	var car := driver.vehicle
	if driver.is_driving():
		driver.stop()
		if switcher and switcher.get(&"active_vehicle") == car:
			car.use_player_input = true
		_message("You drive the %s" % car.name)
	else:
		if switcher and switcher.get(&"active_vehicle") != car:
			switcher.enter_vehicle(car)
		driver.start()
		_message("AI drives the %s - press H to take over" % car.name)


func _message(text: String) -> void:
	if switcher and switcher.has_method(&"_show_message"):
		switcher.call(&"_show_message", text)
	print(text)
