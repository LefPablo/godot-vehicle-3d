extends Control
## Debug HUD: controls, prompts (get in / towing), speed and live suspension
## telemetry for the vehicle being driven.

## Vehicle being driven (null while walking).
@export var vehicle: ShapeCastVehicle
## Optional: the follow camera, to show its current mode.
@export var camera: Node
## Optional: the tow manager, to show the towing status.
@export var tow_manager: Node
## Optional: the vehicle switcher, for the "get in / get out" prompt.
@export var switcher: Node

const BAR_SIZE := Vector2(22.0, 80.0)
const CELL_WIDTH := 150.0
const ROW_HEIGHT := 104.0
const PANEL_COLOR := Color(0.0, 0.0, 0.0, 0.45)
const PROMPT_COLOR := Color(1.0, 0.8, 0.35)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	_draw_help(font)
	_draw_prompts(font)
	if vehicle:
		_draw_vehicle_panel(font)
	else:
		_draw_on_foot_panel(font)


func _draw_help(font: Font) -> void:
	var help: PackedStringArray = []
	if vehicle:
		help.append_array([
			"W / S   throttle / brake + reverse",
			"A / D   steer",
			"Space   handbrake",
			"R       reset vehicle (restacks cargo)",
			"T       tow rope / hitch trailer (reverse to it)",
		])
		if _has_character():
			help.append("E       get out")
		else:
			help.append("X       switch vehicle")
	else:
		help.append_array([
			"W A S D walk",
			"Shift   run",
			"Space   jump",
			"E       get into a vehicle",
		])
	help.append_array([
		"V       spawn next vehicle from res://vehicles",
		"H       AI drives the Car on the road / take over",
		"RMB     hold + move mouse: orbit camera",
		"Wheel   zoom camera",
		"C       camera mode: chase / orbit",
	])
	if camera and camera.has_method(&"get_mode_name"):
		help.append("Camera: %s" % camera.get_mode_name())
	draw_rect(Rect2(Vector2(12, 12), Vector2(380, 22.0 * help.size() + 12.0)), PANEL_COLOR)
	for i in help.size():
		draw_string(font, Vector2(22, 36 + 22 * i), help[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 16)


## Prompts at the top centre: get in / get out, towing status.
func _draw_prompts(font: Font) -> void:
	var lines: PackedStringArray = []
	if switcher and switcher.has_method(&"get_status_text"):
		var text: String = switcher.get_status_text()
		if text != "":
			lines.append(text)
	if tow_manager and tow_manager.has_method(&"get_status_text"):
		var text: String = tow_manager.get_status_text()
		if text != "":
			lines.append(text)
	var y := 12.0
	for line in lines:
		var width := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 24.0
		var box := Rect2(Vector2((size.x - width) * 0.5, y), Vector2(width, 34.0))
		draw_rect(box, PANEL_COLOR)
		draw_string(font, box.position + Vector2(12, 23), line,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, PROMPT_COLOR)
		y += 40.0


func _draw_on_foot_panel(font: Font) -> void:
	var panel := Rect2(Vector2(12.0, size.y - 56.0), Vector2(220.0, 44.0))
	draw_rect(panel, PANEL_COLOR)
	draw_string(font, panel.position + Vector2(12, 30), "On foot",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22)


## Suspension panel (bottom-left): one row per axle, front at the top, left and
## right wheels side by side, like the vehicle seen from above.
func _draw_vehicle_panel(font: Font) -> void:
	var axles := _axle_positions(vehicle)
	var panel_size := Vector2(CELL_WIDTH * 2.0 + 20.0, ROW_HEIGHT * axles.size() + 64.0)
	var panel_pos := Vector2(12.0, size.y - panel_size.y - 12.0)
	draw_rect(Rect2(panel_pos, panel_size), PANEL_COLOR)
	draw_string(font, panel_pos + Vector2(12, 28),
			"%s  %3d km/h" % [vehicle.name, roundi(vehicle.get_speed_kmh())],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	draw_string(font, panel_pos + Vector2(190, 28), "suspension",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.7))
	var cargo := vehicle.get_node_or_null(^"Cargo")
	if cargo and cargo.has_method(&"count_in_bed"):
		draw_string(font, panel_pos + Vector2(12, panel_size.y - 8),
				"cargo in bed: %d / %d" % [cargo.count_in_bed(), cargo.boxes.size()],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8))

	for wheel in vehicle.wheels:
		var column := 0 if wheel.position.x < 0.0 else 1
		var row := _axle_index(axles, wheel.position.z)
		var origin := panel_pos + Vector2(14.0 + column * CELL_WIDTH, 44.0 + row * ROW_HEIGHT)
		_draw_wheel(font, origin, wheel)


func _draw_wheel(font: Font, origin: Vector2, wheel: ShapeCastWheel) -> void:
	draw_rect(Rect2(origin, BAR_SIZE), Color(1, 1, 1, 0.15))
	var fill := BAR_SIZE.y * clampf(wheel.compression_ratio, 0.0, 1.0)
	var color := Color(0.3, 0.85, 0.4)
	if not wheel.is_grounded:
		color = Color(0.5, 0.5, 0.5)
	elif wheel.compression_ratio > 0.85:
		color = Color(0.95, 0.3, 0.25)
	elif wheel.compression_ratio > 0.6:
		color = Color(0.95, 0.75, 0.2)
	draw_rect(Rect2(origin + Vector2(0.0, BAR_SIZE.y - fill), Vector2(BAR_SIZE.x, fill)), color)

	var text_x := BAR_SIZE.x + 10.0
	var label := String(wheel.name).trim_prefix("Wheel")
	draw_string(font, origin + Vector2(text_x, 14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	draw_string(font, origin + Vector2(text_x, 32),
			"%3d %%" % roundi(wheel.compression_ratio * 100.0),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	draw_string(font, origin + Vector2(text_x, 50),
			"%5.0f N" % wheel.suspension_force, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	var status := ""
	if wheel.is_blocked:
		status = "WALL"
	elif not wheel.is_grounded:
		status = "AIR"
	elif wheel.impact_force > 0.0:
		status = "HIT"
	elif wheel.is_slipping:
		status = "SLIP"
	if status != "":
		draw_string(font, origin + Vector2(text_x, 68), status,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.6, 0.3))


## Distinct axle positions (local Z of the wheels), front (-Z) first.
func _axle_positions(v: ShapeCastVehicle) -> Array[float]:
	var axles: Array[float] = []
	for wheel in v.wheels:
		if _axle_index(axles, wheel.position.z) < 0:
			axles.append(wheel.position.z)
	axles.sort()
	return axles


func _axle_index(axles: Array[float], z: float) -> int:
	for i in axles.size():
		if absf(axles[i] - z) < 0.2:
			return i
	return -1


func _has_character() -> bool:
	return switcher != null and switcher.get(&"character") != null
