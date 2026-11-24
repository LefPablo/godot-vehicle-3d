extends Node
## Solid wheel test: the wheel colliders must not touch the road, must block the
## character, and must make vehicles collide wheel-to-wheel.
## Run this scene directly (F6) and close it after "done" is printed.

const DEMO := preload("res://scenes/demo/demo.tscn")

var car: ShapeCastVehicle
var truck: ShapeCastVehicle
var character: CharacterBody3D
var camera: Camera3D

var step := 0
var step_frame := 0
var stats := {}


func _ready() -> void:
	process_physics_priority = 100
	var demo := DEMO.instantiate()
	add_child(demo)
	car = demo.get_node("Car")
	truck = demo.get_node("Truck")
	character = demo.get_node("Character")
	camera = demo.get_node("ChaseCamera")
	print("=== Solid wheel test ===")


func _physics_process(_delta: float) -> void:
	step_frame += 1
	match step:
		0:
			if step_frame == 360:
				_check_colliders_exist()
				_check_rest(car)
				_check_rest(truck)
				_start_character_walk()
				_next()
		1: # character walks sideways (+X) into the car's front-left wheel for 2.5 s
			if step_frame == 300:
				Input.action_release(&"steer_right")
				var local := car.to_local(character.global_position)
				# Wheel outer face at x = -1.11, character radius 0.3: blocked around -1.41.
				# Without wheel collision the chassis (x = -0.85) would stop it at -1.15.
				_check("character blocked by the wheel", local.x < -1.3,
						"character stopped at car-local x %.2f (wheel face -1.11, chassis -0.85)" % local.x)
				character.place_at(Vector3(20, 0.1, 30), 0.0) # out of the way
				_start_truck_pass()
				_next()
		2: # truck drives past the parked car with only the wheels overlapping
			truck.set_controls(clampf((2.5 - truck.forward_speed) * 0.8, -1.0, 1.0), 0.0, false)
			var truck_front_right: Node3D = _front_right_wheel(truck)
			var car_rear_left: Node3D = car.get_node("WheelRL")
			stats.min_wheel_gap = minf(stats.get("min_wheel_gap", INF),
					_flat(truck_front_right.global_position - car_rear_left.global_position))
			if step_frame == 120 * 6:
				var car_moved := _flat(car.global_position - stats.car_start)
				var truck_passed: bool = truck.global_position.z < car.global_position.z - 4.0
				_check("truck's wheels hit the car's wheels", not truck_passed and car_moved > 0.05,
						"truck passed the car=%s, car shoved %.2f m, closest wheel-centre gap %.2f m" % [
							truck_passed, car_moved, stats.min_wheel_gap])
				print("=== done ===")
				_next()


func _check_colliders_exist() -> void:
	var names := PackedStringArray()
	for child in car.get_children():
		if child is CollisionShape3D and String(child.name).ends_with("Collider"):
			names.append(child.name)
	_check("wheel colliders added to the car", names.size() == 4, ", ".join(names))


func _check_rest(vehicle: ShapeCastVehicle) -> void:
	# If a wheel collider touched the ground it would carry part of the weight.
	var total := 0.0
	for wheel in vehicle.wheels:
		total += wheel.suspension_force
	var cargo := vehicle.get_node_or_null("Cargo")
	var cargo_mass := 0.0
	if cargo:
		for box: RigidBody3D in cargo.boxes:
			if cargo.is_in_bed(box):
				cargo_mass += box.mass
	var weight := (vehicle.mass + cargo_mass) * 9.81
	_check("%s rests on its suspension only" % vehicle.name, absf(total - weight) / weight < 0.1,
			"wheel forces %.0f N vs weight %.0f N, speed %.2f m/s" % [
				total, weight, vehicle.linear_velocity.length()])


func _start_character_walk() -> void:
	# Stand 2.2 m left of the car's front-left wheel and walk right (+X) into it.
	var wheel: Node3D = car.get_node("WheelFL")
	var spot := car.to_global(Vector3(-2.2, 0.0, wheel.position.z))
	character.place_at(Vector3(spot.x, 0.1, spot.z), -PI * 0.5)
	camera._orbit_yaw = car.global_rotation.y # camera looks along the car, so D = +X of the car
	Input.action_press(&"steer_right")


func _start_truck_pass() -> void:
	# Truck parallel to the car, 2.2 m to its left and 8 m behind: its cab, bed
	# and tyres clear the car's body, but its right-hand tyres overlap the
	# car's left-hand tyres by ~0.23 m (truck tyre x -1.20..-0.88, car tyre
	# -1.11..-0.85, car body starts at -0.85).
	var start := car.to_global(Vector3(-2.2, 0.0, 8.0))
	truck.global_transform = Transform3D(car.global_basis.orthonormalized(),
			Vector3(start.x, car.global_position.y + 0.25, start.z))
	truck.linear_velocity = Vector3.ZERO
	truck.angular_velocity = Vector3.ZERO
	truck.reset_physics_interpolation()
	truck.get_node("Cargo").restack()
	truck.use_player_input = false
	stats = {"car_start": car.global_position}


func _next() -> void:
	step += 1
	step_frame = 0


## Front-most wheel on the right (+X) side, whatever the wheel layout.
func _front_right_wheel(vehicle: ShapeCastVehicle) -> ShapeCastWheel:
	var best: ShapeCastWheel = null
	for wheel in vehicle.wheels:
		if wheel.position.x > 0.0 and (best == null or wheel.position.z < best.position.z):
			best = wheel
	return best if best else vehicle.wheels[0]


func _check(label: String, ok: bool, details: String) -> void:
	print("%-40s %s  %s" % [label, "OK" if ok else "FAIL", details])


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()
