extends Control
## Test-drive telemetry: speed, inputs, per-wheel suspension, cargo,
## validation warnings and the key help.

const PANEL_COLOR := Color(0.0, 0.0, 0.0, 0.55)
const TEXT_COLOR := Color(0.92, 0.94, 0.96)
const DIM_COLOR := Color(0.62, 0.66, 0.72)
const WARN_COLOR := Color(1.0, 0.76, 0.3)
const ERROR_COLOR := Color(1.0, 0.42, 0.42)
const GOOD_COLOR := Color(0.48, 0.85, 0.56)
const FONT_SIZE := 15
const HELP: PackedStringArray = [
	"W/S, Up/Down   throttle, brake, reverse",
	"A/D, Left/Right  steer",
	"Space          handbrake",
	"R              reset the vehicle",
	"F5             reload the definition from disk",
	"C              camera: chase / orbit / side / wheels / top",
	"RMB drag       orbit     wheel  zoom",
	"P              put cones and crates back",
	"H              hide this help",
	"Esc            quit",
]

var vehicle: ShapeCastVehicle
var definition: VehicleDefinition
var source_path: String = ""
var issues: Array[Dictionary] = []
var load_warnings: Array[String] = []
var camera_mode: String = ""
var show_help: bool = true

var _font: Font
var _message: String = ""
var _message_time: float = 0.0


func _ready() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "DejaVu Sans Mono", "Menlo", "Monospace"])
	_font = font


func show_message(text: String, seconds: float = 4.0) -> void:
	_message = text
	_message_time = seconds


func _process(delta: float) -> void:
	_message_time -= delta
	queue_redraw()


func _draw() -> void:
	var lines: Array[Array] = [] # [text, colour]
	if is_instance_valid(vehicle) and definition:
		_vehicle_lines(lines)
	else:
		lines.append(["No vehicle loaded", ERROR_COLOR])
	_panel(Vector2(12, 12), lines)

	if show_help:
		var help: Array[Array] = []
		for line in HELP:
			help.append([line, DIM_COLOR])
		var height := help.size() * _line_height() + 16.0
		_panel(Vector2(12, size.y - height - 12.0), help)

	if _message_time > 0.0 and _message != "":
		var width := _font.get_string_size(_message, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE + 3).x
		var at := Vector2((size.x - width) * 0.5, size.y - 48.0)
		draw_rect(Rect2(at - Vector2(10, 22), Vector2(width + 20, 32)), PANEL_COLOR)
		draw_string(_font, at, _message, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE + 3, TEXT_COLOR)


func _vehicle_lines(lines: Array[Array]) -> void:
	lines.append(["%s  (%s)  %s" % [definition.display_name, definition.category, source_path.get_file()], TEXT_COLOR])
	var throttle: float = vehicle.get(&"_throttle")
	var handbrake: bool = vehicle.get(&"_handbrake")
	lines.append(["%6.1f km/h   throttle %+.2f   steer %+5.1f deg   %s" % [
			vehicle.forward_speed * 3.6, throttle, rad_to_deg(vehicle.steer_angle),
			"HANDBRAKE" if handbrake else ""], TEXT_COLOR])
	lines.append(["mass %.0f kg   camera %s   %s" % [vehicle.mass, camera_mode,
			"" if definition.player_controllable else "(not drivable: preview only)"], DIM_COLOR])
	lines.append(["", TEXT_COLOR])
	for wheel in vehicle.wheels:
		var ratio := clampf(wheel.compression_ratio, 0.0, 1.0)
		var filled := roundi(ratio * 12.0)
		var bar := "#".repeat(filled) + "-".repeat(12 - filled)
		var state := "air" if not wheel.is_grounded else ("BLOCKED" if wheel.is_blocked else "")
		var color := WARN_COLOR if ratio > 0.9 or wheel.is_blocked else TEXT_COLOR
		lines.append(["%-9s [%s] %3d%%  %6.0f N  %s" % [wheel.name, bar, roundi(ratio * 100.0),
				wheel.suspension_force, state], color])
	for child in vehicle.get_children():
		if child is VehicleCargoBay and child.space:
			var space: VehicleCargoSpace = child.space
			var limit := "%.0f kg" % space.max_mass if space.max_mass > 0.0 else "no limit"
			var text := "%s: %.2f x %.2f x %.2f m, load %.0f kg (%s)" % [child.name, space.size.x,
					space.size.y, space.size.z, child.get_load_mass(), limit]
			if not child.boxes.is_empty():
				text += ", boxes %d/%d" % [child.count_in_bed(), child.boxes.size()]
			lines.append([text, TEXT_COLOR])
	var shown := 0
	for issue in issues:
		if issue.level == VehicleValidator.Level.INFO or shown >= 6:
			continue
		shown += 1
		var is_error: bool = issue.level == VehicleValidator.Level.ERROR
		lines.append([("ERROR " if is_error else "WARN  ") + issue.text, ERROR_COLOR if is_error else WARN_COLOR])
	for warning in load_warnings:
		lines.append(["LOAD  " + warning, WARN_COLOR])
	if shown == 0 and load_warnings.is_empty():
		lines.append(["definition OK", GOOD_COLOR])


func _panel(at: Vector2, lines: Array[Array]) -> void:
	var width := 0.0
	for line in lines:
		width = maxf(width, _font.get_string_size(line[0], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x)
	var height := lines.size() * _line_height()
	draw_rect(Rect2(at, Vector2(width + 24.0, height + 16.0)), PANEL_COLOR)
	var y := at.y + 8.0 + _font.get_ascent(FONT_SIZE)
	for line in lines:
		draw_string(_font, Vector2(at.x + 12.0, y), line[0], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, line[1])
		y += _line_height()


func _line_height() -> float:
	return _font.get_height(FONT_SIZE) + 2.0
