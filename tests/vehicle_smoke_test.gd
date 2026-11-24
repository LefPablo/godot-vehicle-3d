extends Node
## Automated smoke test: loads the demo, checks track geometry with raycasts,
## then auto-drives the car through every lane and prints suspension telemetry.
## Run this scene directly (F6) and close it after "finished" is printed.

const DEMO := preload("res://scenes/demo/demo.tscn")
const TARGET_SPEED := 12.0 # m/s (~43 km/h)
const LANES := [
	{"name": "Small bumps", "x": 0.0, "end_z": -108.0},
	{"name": "Big bumps", "x": -16.0, "end_z": -88.0},
	{"name": "Pits", "x": 16.0, "end_z": -108.0},
	{"name": "Roll test", "x": 32.0, "end_z": -108.0},
	{"name": "Jumps", "x": -32.0, "end_z": -112.0},
]
# [position, expected surface height]
const PROBES := [
	[Vector3(0, 5, 15), 0.0],
	[Vector3(0, 5, -36), 0.16],
	[Vector3(0, 5, -100), 0.15],
	[Vector3(-16, 5, -30), 0.7],
	[Vector3(-16, 5, -48), 0.3],
	[Vector3(16, 5, -27), -0.25],
	[Vector3(16, 5, -102), -0.5],
	[Vector3(31, 5, -10), 0.2],
	[Vector3(-32, 5, -20), 1.2],
	[Vector3(-32, 5, -44), 0.333],
	[Vector3(-32, 5, -53), 0.6],
	[Vector3(-32, 5, -95), 2.5],
	[Vector3(0, 5, -160), 3.0],
]

var vehicle: ShapeCastVehicle
var frame := 0
var phase := "settle"
var phase_frame := 0
var lane_index := -1
var stats := {}


func _ready() -> void:
	var demo := DEMO.instantiate()
	add_child(demo)
	vehicle = demo.get_node("Car")
	vehicle.use_player_input = false
	print("=== ShapeCast vehicle smoke test ===")


func _physics_process(delta: float) -> void:
	frame += 1
	phase_frame += 1
	match phase:
		"settle":
			vehicle.set_controls(0.0, 0.0, false)
			if phase_frame == 10:
				_probe_track()
			if phase_frame == 240:
				_print_rest_state()
				_next_lane()
		"lane_settle":
			vehicle.set_controls(0.0, 0.0, true)
			if phase_frame == 90:
				phase = "lane_drive"
				phase_frame = 0
		"lane_drive":
			_drive_lane(delta)


func _probe_track() -> void:
	var space := vehicle.get_world_3d().direct_space_state
	var ok := true
	for probe in PROBES:
		var from: Vector3 = probe[0]
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 20.0, 1)
		var hit := space.intersect_ray(query)
		var height: float = hit.position.y if hit else NAN
		var good := absf(height - probe[1]) < 0.05
		ok = ok and good
		print("probe %s -> %.3f (expected %.3f) %s" % [from, height, probe[1], "OK" if good else "MISMATCH"])
	print("Track geometry: ", "OK" if ok else "CHECK MISMATCHES")


func _print_rest_state() -> void:
	print("--- At rest after 2 s ---")
	print("body height: %.3f  speed: %.3f m/s" % [vehicle.global_position.y, vehicle.linear_velocity.length()])
	for w in vehicle.wheels:
		print("  %s grounded=%s compression=%.3f m (%.0f%%) force=%.0f N" % [
			w.name, w.is_grounded, w.compression, w.compression_ratio * 100.0, w.suspension_force])


func _next_lane() -> void:
	lane_index += 1
	if lane_index >= LANES.size():
		print("=== Smoke test finished ===")
		set_physics_process(false)
		return
	var lane: Dictionary = LANES[lane_index]
	vehicle.global_transform = Transform3D(Basis.IDENTITY, Vector3(lane.x, 1.0, 5.0))
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	vehicle.reset_physics_interpolation()
	stats = {"max_comp": 0.0, "bottomed": 0, "air_frames": 0, "max_roll": 0.0,
			"max_pitch": 0.0, "flipped": false, "max_speed": 0.0, "slip_frames": 0}
	phase = "lane_settle"
	phase_frame = 0


func _drive_lane(_delta: float) -> void:
	var lane: Dictionary = LANES[lane_index]
	var speed := vehicle.forward_speed
	var throttle := clampf((TARGET_SPEED - speed) * 0.5, -1.0, 1.0)
	# Keep the car in its lane.
	var lateral_error: float = vehicle.global_position.x - lane.x
	var heading := -vehicle.global_basis.z
	var steer := clampf(lateral_error * 0.3 + heading.x * 2.0, -1.0, 1.0)
	vehicle.set_controls(throttle, steer, false)

	var airborne := 0
	for w in vehicle.wheels:
		stats.max_comp = maxf(stats.max_comp, w.compression_ratio)
		if w.compression_ratio > 0.97:
			stats.bottomed += 1
		if not w.is_grounded:
			airborne += 1
		if w.is_slipping:
			stats.slip_frames += 1
	if airborne == vehicle.wheels.size():
		stats.air_frames += 1
	var up := vehicle.global_basis.y
	stats.max_roll = maxf(stats.max_roll, rad_to_deg(absf(vehicle.global_rotation.z)))
	stats.max_pitch = maxf(stats.max_pitch, rad_to_deg(absf(vehicle.global_rotation.x)))
	stats.max_speed = maxf(stats.max_speed, speed)
	if up.y < 0.3:
		stats.flipped = true

	var done: bool = vehicle.global_position.z < lane.end_z or phase_frame > 120 * 25 or stats.flipped
	if done:
		print("--- Lane: %s ---" % lane.name)
		print("  reached z=%.1f in %.1f s, x drift=%.2f" % [
			vehicle.global_position.z, phase_frame / 120.0, vehicle.global_position.x - lane.x])
		print("  max speed %.1f km/h, max compression %.0f%%, bottom-out wheel-frames %d" % [
			stats.max_speed * 3.6, stats.max_comp * 100.0, stats.bottomed])
		print("  max roll %.1f deg, max pitch %.1f deg, all-wheels-airborne frames %d, slip wheel-frames %d" % [
			stats.max_roll, stats.max_pitch, stats.air_frames, stats.slip_frames])
		print("  flipped: %s" % stats.flipped)
		_next_lane()
