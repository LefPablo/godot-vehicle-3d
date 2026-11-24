extends Node
## Regression test for "wheel passes through a step".
## Drives into the 25 cm step and out of the 30 cm trench at different speeds and
## measures how deep each wheel's real tyre shape sinks into the track geometry.
## Run this scene directly (F6) and close it after "done" is printed.

const DEMO := preload("res://scenes/demo/demo.tscn")
const DEPTH_LEVELS := [0.02, 0.05, 0.10, 0.20]
const SCENARIOS := [
	{"name": "25 cm step, 3 m/s", "x": -16.0, "start_z": -67.0, "end_z": -86.0, "speed": 3.0},
	{"name": "25 cm step, 10 m/s", "x": -16.0, "start_z": -66.0, "end_z": -86.0, "speed": 10.0},
	{"name": "30 cm trench exit, 3 m/s", "x": 16.0, "start_z": -31.0, "end_z": -45.0, "speed": 3.0},
	{"name": "30 cm trench exit, 8 m/s", "x": 16.0, "start_z": -31.0, "end_z": -45.0, "speed": 8.0},
	{"name": "15 cm curb, 10 m/s", "x": 0.0, "start_z": -88.0, "end_z": -108.0, "speed": 10.0},
]

var vehicle: ShapeCastVehicle
var probe_shape: ConvexPolygonShape3D
var index := -1
var phase_frame := 0
var settling := true
var result := {}


func _ready() -> void:
	# Measure after the vehicle has updated its wheels in the same physics tick.
	process_physics_priority = 100
	process_priority = 100
	var demo := DEMO.instantiate()
	add_child(demo)
	vehicle = demo.get_node("Car")
	vehicle.use_player_input = false
	probe_shape = _make_probe_shape(0.36, 0.26, 24)
	print("=== Step penetration test ===")
	_next()


func _process(_delta: float) -> void:
	# What is actually drawn: wheel meshes placed from the interpolated transform.
	if settling or index >= SCENARIOS.size() or result.is_empty():
		return
	for wheel in vehicle.wheels:
		var visual: Node3D = wheel.get_child(0, true)
		var xform := wheel.get_global_transform_interpolated()
		var depth := _penetration_at(xform * visual.position, xform.basis)
		if depth > 0.0:
			result.visual_frames += 1
		result.visual_max = maxf(result.visual_max, depth)


func _physics_process(_delta: float) -> void:
	if index >= SCENARIOS.size():
		return
	phase_frame += 1
	var s: Dictionary = SCENARIOS[index]
	if settling:
		vehicle.set_controls(0.0, 0.0, true)
		if phase_frame > 90:
			settling = false
			phase_frame = 0
		return

	var throttle := clampf((s.speed - vehicle.forward_speed) * 0.8, -1.0, 1.0)
	var steer := clampf((vehicle.global_position.x - s.x) * 0.3 + (-vehicle.global_basis.z).x * 2.0, -1.0, 1.0)
	vehicle.set_controls(throttle, steer, false)

	for wheel in vehicle.wheels:
		var depth := _penetration(wheel)
		if depth > 0.0:
			result.frames_over_2cm += 1
			if result.logged < 12:
				result.logged += 1
				var c := wheel.global_transform * Vector3(0.0, -wheel.suspension_length, 0.0)
				print("    %s depth>=%.2f center=(%.2f, %.3f, %.2f) comp=%.2f over=%.3f blocked=%s n=%s impact=%.0f" % [
					wheel.name, depth, c.x, c.y, c.z, wheel.compression_ratio, wheel.overcompression,
					wheel.is_blocked, wheel.contact_normal.snappedf(0.01), wheel.impact_force])
		result.max_depth = maxf(result.max_depth, depth)
	result.max_pitch = maxf(result.max_pitch, rad_to_deg(absf(vehicle.global_rotation.x)))

	if vehicle.global_position.z < s.end_z or phase_frame > 120 * 20:
		var passed: bool = vehicle.global_position.z < s.end_z
		print("%-28s passed=%s  physics: deepest %s, wheel-frames >2cm %d | drawn: deepest %s, wheel-frames >2cm %d | max pitch %.1f deg" % [
			s.name, passed, _depth_text(result.max_depth), result.frames_over_2cm,
			_depth_text(result.visual_max), result.visual_frames, result.max_pitch])
		_next()


func _next() -> void:
	index += 1
	if index >= SCENARIOS.size():
		print("=== done ===")
		return
	var s: Dictionary = SCENARIOS[index]
	vehicle.global_transform = Transform3D(Basis.IDENTITY, Vector3(s.x, 1.0, s.start_z))
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	vehicle.reset_physics_interpolation()
	result = {"max_depth": 0.0, "frames_over_2cm": 0, "max_pitch": 0.0, "logged": 0,
			"visual_max": 0.0, "visual_frames": 0}
	settling = true
	phase_frame = 0


## How deep the tyre at its current (visual) position is inside the track:
## the tyre is lifted in steps until it no longer overlaps anything.
func _penetration(wheel: ShapeCastWheel) -> float:
	var center := wheel.global_transform * Vector3(0.0, -wheel.suspension_length, 0.0)
	return _penetration_at(center, wheel.global_basis)


func _penetration_at(center: Vector3, basis: Basis) -> float:
	var up := basis.y.normalized()
	var space := vehicle.get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = probe_shape
	params.collision_mask = 1
	params.exclude = [vehicle.get_rid()]
	var deepest := 0.0
	for level in DEPTH_LEVELS:
		params.transform = Transform3D(basis, center + up * level)
		if space.intersect_shape(params, 1).is_empty():
			break
		deepest = level
	return deepest


func _depth_text(depth: float) -> String:
	if depth <= 0.0:
		return "< 2 cm"
	if depth >= DEPTH_LEVELS[-1]:
		return ">= %d cm" % roundi(depth * 100.0)
	return "%d-%d cm" % [roundi(depth * 100.0), roundi(DEPTH_LEVELS[DEPTH_LEVELS.find(depth) + 1] * 100.0)]


## Tyre hull centred on its own origin (independent of the wheel script).
func _make_probe_shape(radius: float, width: float, segments: int) -> ConvexPolygonShape3D:
	var points := PackedVector3Array()
	for i in segments:
		var a := TAU * i / segments
		points.append(Vector3(-width * 0.5, cos(a) * radius, sin(a) * radius))
		points.append(Vector3(width * 0.5, cos(a) * radius, sin(a) * radius))
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	return hull
