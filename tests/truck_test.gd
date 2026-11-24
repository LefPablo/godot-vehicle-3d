extends Node
## Truck + cargo + vehicle switching test.
## Run this scene directly (F6) and close it after "done" is printed.

const DEMO := preload("res://scenes/demo/demo.tscn")
const LANES := [
	{"name": "Big bumps", "x": -16.0, "end_z": -88.0, "speed": 7.0},
	{"name": "Roll test", "x": 32.0, "end_z": -108.0, "speed": 9.0},
]

var car: ShapeCastVehicle
var truck: ShapeCastVehicle
var switcher: Node
var camera: Camera3D
var hud: Control
var cargo: Node

var step := "settle"
var frame := 0
var lane := -1
var stats := {}
var car_parked_at := Vector3.ZERO


func _ready() -> void:
	process_physics_priority = 100
	var demo := DEMO.instantiate()
	add_child(demo)
	car = demo.get_node("Car")
	truck = demo.get_node("Truck")
	switcher = demo.get_node("VehicleSwitcher")
	camera = demo.get_node("ChaseCamera")
	hud = demo.get_node("UI/HUD")
	cargo = truck.get_node("Cargo")
	print("=== Truck test ===")


func _physics_process(_delta: float) -> void:
	frame += 1
	match step:
		"settle":
			if frame == 360:
				_report_rest("Truck at rest with cargo")
				_check_start_and_press_x()
			if frame == 372:
				_check_after_x()
				_start_lane()
		"drive":
			_drive()


func _report_rest(title: String) -> void:
	print("--- %s ---" % title)
	print("  truck height %.3f, cargo in bed %d / %d, total cargo mass %.0f kg" % [
		truck.global_position.y, cargo.count_in_bed(), cargo.boxes.size(), _cargo_mass()])
	for w in truck.wheels:
		print("  %s compression %.3f m (%.0f%%) force %.0f N blocked=%s" % [
			w.name, w.compression, w.compression_ratio * 100.0, w.suspension_force, w.is_blocked])


func _check_start_and_press_x() -> void:
	print("--- Switching ---")
	var ok: bool = switcher.is_on_foot() and not car.use_player_input and not truck.use_player_input \
			and camera.target.name == "Character" and hud.vehicle == null
	print("  start (on foot): car active=%s truck active=%s camera->%s hud->%s  %s" % [
		car.use_player_input, truck.use_player_input, camera.target.name, hud.vehicle,
		"OK" if ok else "FAIL"])
	# Put the character into the truck (vehicles are entered with E on foot).
	switcher.activate(1)


func _check_after_x() -> void:
	var ok: bool = truck.use_player_input and not car.use_player_input and camera.target == truck \
			and hud.vehicle == truck
	print("  after entering the truck: car active=%s truck active=%s camera->%s hud->%s distance=%.1f  %s" % [
		car.use_player_input, truck.use_player_input, camera.target.name, hud.vehicle.name,
		camera.distance, "OK" if ok else "FAIL"])
	car_parked_at = car.global_position


func _start_lane() -> void:
	lane += 1
	if lane >= LANES.size():
		_finish()
		return
	var l: Dictionary = LANES[lane]
	truck.use_player_input = false
	truck.global_transform = Transform3D(Basis.IDENTITY, Vector3(l.x, 1.4, 5.0))
	truck.linear_velocity = Vector3.ZERO
	truck.angular_velocity = Vector3.ZERO
	truck.reset_physics_interpolation()
	cargo.restack()
	stats = {"frames": 0, "blocked": 0, "max_comp": 0.0, "max_roll": 0.0, "max_pitch": 0.0,
			"flipped": false, "hits": 0}
	step = "drive"


func _drive() -> void:
	var l: Dictionary = LANES[lane]
	stats.frames += 1
	if stats.frames < 120:
		truck.set_controls(0.0, 0.0, true) # let the load settle after restacking
		return
	var throttle := clampf((l.speed - truck.forward_speed) * 0.6, -1.0, 1.0)
	var steer := clampf((truck.global_position.x - l.x) * 0.3 + (-truck.global_basis.z).x * 2.0, -1.0, 1.0)
	truck.set_controls(throttle, steer, false)
	for w in truck.wheels:
		stats.max_comp = maxf(stats.max_comp, w.compression_ratio)
		if w.is_blocked:
			stats.blocked += 1
		if w.impact_force > 0.0:
			stats.hits += 1
	stats.max_roll = maxf(stats.max_roll, rad_to_deg(absf(truck.global_rotation.z)))
	stats.max_pitch = maxf(stats.max_pitch, rad_to_deg(absf(truck.global_rotation.x)))
	if truck.global_basis.y.y < 0.3:
		stats.flipped = true
	if truck.global_position.z < l.end_z or stats.frames > 120 * 30 or stats.flipped:
		print("--- Truck lane: %s at ~%d km/h ---" % [l.name, roundi(l.speed * 3.6)])
		print("  reached z=%.1f in %.1f s, flipped=%s" % [
			truck.global_position.z, stats.frames / 120.0, stats.flipped])
		print("  max compression %.0f%%, max roll %.1f deg, max pitch %.1f deg" % [
			stats.max_comp * 100.0, stats.max_roll, stats.max_pitch])
		print("  WALL (blocked) wheel-frames: %d, hard-contact wheel-frames: %d, cargo left in bed: %d / %d" % [
			stats.blocked, stats.hits, cargo.count_in_bed(), cargo.boxes.size()])
		_start_lane()


func _finish() -> void:
	step = "finishing"
	print("--- Parked car ---")
	var moved := car.global_position.distance_to(car_parked_at)
	print("  car moved %.3f m while parked  %s" % [moved, "OK" if moved < 0.05 else "FAIL"])
	# Reset restacks the cargo.
	truck.reset_vehicle()
	await get_tree().create_timer(3.0).timeout
	_report_rest("After R reset (restacked)")
	# Empty truck for comparison: move the boxes away.
	for box: RigidBody3D in cargo.boxes:
		box.global_position += Vector3(0, 0, 40)
	await get_tree().create_timer(3.0).timeout
	_report_rest("Empty truck")
	print("=== done ===")
	step = "done"


func _cargo_mass() -> float:
	var total := 0.0
	for box: RigidBody3D in cargo.boxes:
		total += box.mass
	return total
