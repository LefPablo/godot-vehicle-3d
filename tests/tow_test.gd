extends Node
## Towing test: truck hooks the car (T), tows it straight over the small-bumps
## lane, brakes, tows it through a turn, then unhooks (T).
## Run this scene directly (F6) and close it after "done" is printed.

const DEMO := preload("res://scenes/demo/demo.tscn")

var car: ShapeCastVehicle
var truck: ShapeCastVehicle
var switcher: Node
var tow: Node
var cargo: Node

var frame := 0
var phase := "setup"
var phase_frame := 0
var stats := {}
var car_yaw_start := 0.0
var truck_yaw_start := 0.0


func _ready() -> void:
	process_physics_priority = 100
	var demo := DEMO.instantiate()
	add_child(demo)
	car = demo.get_node("Car")
	truck = demo.get_node("Truck")
	switcher = demo.get_node("VehicleSwitcher")
	tow = demo.get_node("TowManager")
	cargo = truck.get_node("Cargo")
	print("=== Tow test ===")


func _physics_process(_delta: float) -> void:
	frame += 1
	phase_frame += 1
	match phase:
		"setup":
			if frame == 240:
				_place_vehicles()
			if frame == 480:
				print("status before hooking: \"%s\"" % tow.get_status_text())
				_press_key(KEY_T)
			if frame == 490:
				var ok: bool = tow.is_towing() and tow.tower == truck and tow.towed == car and car.is_towed
				print("after T: towing=%s tower=%s towed=%s car.is_towed=%s rope length %.2f m  %s" % [
					tow.is_towing(), _name(tow.tower), _name(tow.towed), car.is_towed,
					tow.rope.length if tow.is_towing() else 0.0, "OK" if ok else "FAIL"])
				_start("straight")
		"straight":
			_drive(8.0, _lane_steer(0.0))
			_measure()
			if phase_frame >= 120 * 12:
				_report("Straight tow over small bumps (~29 km/h, 12 s)")
				_start("brake")
		"brake":
			truck.set_controls(-1.0 if truck.forward_speed > 0.5 else 0.0, 0.0, truck.forward_speed <= 0.5)
			_measure()
			if phase_frame >= 120 * 4:
				_report("Hard stop (car keeps rolling into the slack rope)")
				_start("turn")
				car_yaw_start = car.global_rotation.y
				truck_yaw_start = truck.global_rotation.y
		"turn":
			_drive(6.0, 0.6)
			_measure()
			if phase_frame >= 120 * 6:
				_report("Towing through a left turn (~22 km/h, 6 s)")
				print("  truck turned %.0f deg, car turned %.0f deg" % [
					rad_to_deg(wrapf(truck.global_rotation.y - truck_yaw_start, -PI, PI)),
					rad_to_deg(wrapf(car.global_rotation.y - car_yaw_start, -PI, PI))])
				truck.set_controls(-1.0, 0.0, true)
				_start("stop")
		"stop":
			truck.set_controls(-1.0 if truck.forward_speed > 0.5 else 0.0, 0.0, true)
			if phase_frame == 360:
				_press_key(KEY_T)
			if phase_frame == 370:
				var ok: bool = not tow.is_towing() and not car.is_towed and car._handbrake
				print("after second T: towing=%s car.is_towed=%s car handbrake=%s  %s" % [
					tow.is_towing(), car.is_towed, car._handbrake, "OK" if ok else "FAIL"])
				print("=== done ===")
				phase = "done"


func _place_vehicles() -> void:
	switcher.activate(1) # drive the truck
	truck.use_player_input = false
	# Car parked in the open area facing -Z, truck in front of it with ~4 m gap
	# between the truck's rear hitch and the car's front hook.
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.9, 30.0))
	truck.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 1.2, 30.0 - 2.07 - 4.0 - 3.0))
	for body: RigidBody3D in [car, truck]:
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.reset_physics_interpolation()
	cargo.restack()
	car.set_controls(0.0, 0.0, true)
	truck.set_controls(0.0, 0.0, true)


func _start(new_phase: String) -> void:
	phase = new_phase
	phase_frame = 0
	stats = {"max_tension": 0.0, "max_stretch": 0.0, "min_gap": INF, "car_speed": 0.0,
			"max_car_offset": 0.0, "truck_speed": 0.0}


func _drive(speed: float, steer: float) -> void:
	truck.set_controls(clampf((speed - truck.forward_speed) * 0.6, -1.0, 1.0), steer, false)


func _lane_steer(x: float) -> float:
	return clampf((truck.global_position.x - x) * 0.3 + (-truck.global_basis.z).x * 2.0, -1.0, 1.0)


func _measure() -> void:
	if tow.is_towing():
		stats.max_tension = maxf(stats.max_tension, tow.rope.tension)
		stats.max_stretch = maxf(stats.max_stretch, tow.rope.current_distance - tow.rope.length)
	var hitch: Node3D = truck.get_node("TowHitchRear")
	var hook: Node3D = car.get_node("TowHookFront")
	stats.min_gap = minf(stats.min_gap, hitch.global_position.distance_to(hook.global_position))
	stats.car_speed = car.forward_speed
	stats.truck_speed = truck.forward_speed
	# How far the car strays sideways from the truck's path.
	var local := truck.to_local(car.global_position)
	stats.max_car_offset = maxf(stats.max_car_offset, absf(local.x))


func _report(title: String) -> void:
	print("--- %s ---" % title)
	print("  still hooked: %s" % tow.is_towing())
	print("  max rope force %.1f kN, max stretch %.1f cm, closest hitch-hook gap %.2f m" % [
		stats.max_tension / 1000.0, stats.max_stretch * 100.0, stats.min_gap])
	print("  speeds at end: truck %.1f km/h, car %.1f km/h; max sideways offset of car %.2f m" % [
		stats.truck_speed * 3.6, stats.car_speed * 3.6, stats.max_car_offset])


func _press_key(keycode: Key) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = keycode
	key.pressed = true
	Input.parse_input_event(key)
	var release := key.duplicate()
	release.pressed = false
	Input.parse_input_event(release)


func _name(node: Node) -> String:
	return String(node.name) if node else "none"
