extends Node
## Character test: walking, running, jumping, getting into / out of the car and
## the truck with E, refusing to get out at speed, and getting out on the other
## side when the driver's side is blocked.
## Run this scene directly (F6) and close it after "done" is printed.

const DEMO := preload("res://scenes/demo/demo.tscn")

var car: ShapeCastVehicle
var truck: ShapeCastVehicle
var character: CharacterBody3D
var switcher: Node
var camera: Camera3D
var hud: Control

var step := 0
var step_frame := 0
var mark := Vector3.ZERO
var max_height := 0.0


func _ready() -> void:
	process_physics_priority = 100
	var demo := DEMO.instantiate()
	add_child(demo)
	car = demo.get_node("Car")
	truck = demo.get_node("Truck")
	character = demo.get_node("Character")
	switcher = demo.get_node("VehicleSwitcher")
	camera = demo.get_node("ChaseCamera")
	hud = demo.get_node("UI/HUD")
	print("=== Character test ===")


func _physics_process(_delta: float) -> void:
	step_frame += 1
	match step:
		0: # settle
			if step_frame == 240:
				_check("start on foot",
						switcher.is_on_foot() and character.visible and character.is_on_floor()
						and camera.target == character and hud.vehicle == null,
						"on floor=%s, feet y=%.2f, camera->%s, prompt \"%s\"" % [
							character.is_on_floor(), character.global_position.y,
							camera.target.name, switcher.get_status_text()])
				mark = character.global_position
				Input.action_press(&"move_forward")
				_next()
		1: # walk 2 s
			if step_frame == 240:
				var speed := Vector2(character.velocity.x, character.velocity.z).length()
				_check("walk", absf(speed - 4.0) < 0.2,
						"moved %.1f m in 2 s, speed %.1f m/s" % [
							_flat(character.global_position - mark), speed])
				Input.action_press(&"sprint")
				mark = character.global_position
				_next()
		2: # run 2 s
			if step_frame == 240:
				var speed := Vector2(character.velocity.x, character.velocity.z).length()
				_check("run", absf(speed - 7.5) < 0.3,
						"moved %.1f m in 2 s, speed %.1f m/s" % [
							_flat(character.global_position - mark), speed])
				Input.action_release(&"sprint")
				Input.action_release(&"move_forward")
				_next()
		3: # jump
			if step_frame == 60:
				mark = character.global_position
				max_height = 0.0
				Input.action_press(&"jump")
			if step_frame == 62:
				Input.action_release(&"jump")
			if step_frame > 60:
				max_height = maxf(max_height, character.global_position.y - mark.y)
			if step_frame == 240:
				_check("jump", max_height > 0.8 and character.is_on_floor(),
						"peak %.2f m, landed=%s" % [max_height, character.is_on_floor()])
				_walk_up_to(car)
				_next()
		4: # get into the car
			if step_frame == 30:
				print("  prompt next to the car: \"%s\"" % switcher.get_status_text())
				_press_key(KEY_E)
			if step_frame == 40:
				_check("E: into the car",
						switcher.active_vehicle == car and car.use_player_input
						and not character.visible and camera.target == car and hud.vehicle == car, "")
				Input.action_press(&"move_forward")
				_next()
		5: # drive 3 s with W, then try to get out at speed
			if step_frame == 360:
				var kmh := car.get_speed_kmh()
				Input.action_release(&"move_forward")
				_press_key(KEY_E)
				mark = Vector3(kmh, 0, 0)
			if step_frame == 370:
				_check("E at %.0f km/h is refused" % mark.x,
						switcher.active_vehicle == car and not character.visible,
						"message \"%s\"" % switcher.get_status_text())
				Input.action_press(&"handbrake") # stop
				_next()
		6: # stop, then get out
			if car.get_speed_kmh() < 1.0 and step_frame > 10 and step_frame < 1000:
				Input.action_release(&"handbrake")
				step_frame = 1000
			if step_frame == 1060:
				_press_key(KEY_E)
			if step_frame == 1070:
				var local := car.to_local(character.global_position)
				_check("E: out of the car (driver side)",
						switcher.is_on_foot() and character.visible and not car.use_player_input
						and car._handbrake and camera.target == character and local.x < -1.0,
						"character at car-local (%.2f, %.2f, %.2f)" % [local.x, local.y, local.z])
			if step_frame == 1180:
				_check("stands on the ground after getting out", character.is_on_floor(),
						"feet y %.2f" % character.global_position.y)
				_walk_up_to(truck)
				_next()
		7: # truck: in and out
			if step_frame == 30:
				_press_key(KEY_E)
			if step_frame == 40:
				_check("E: into the truck",
						switcher.active_vehicle == truck and truck.use_player_input
						and camera.target == truck, "camera distance %.1f" % camera.distance)
			if step_frame == 160:
				_press_key(KEY_E)
			if step_frame == 170:
				_check("E: out of the truck", switcher.is_on_foot() and character.visible, "")
				_walk_up_to(car)
				_next()
		8: # driver side blocked by the truck -> get out on the other side
			if step_frame == 30:
				_press_key(KEY_E)
			if step_frame == 40:
				_park_truck_against_driver_side()
			if step_frame == 280:
				_press_key(KEY_E)
			if step_frame == 290:
				var local := car.to_local(character.global_position)
				_check("driver side blocked: out on the passenger side",
						switcher.is_on_foot() and local.x > 1.0,
						"character at car-local x %.2f" % local.x)
				print("=== done ===")
				_next()


func _walk_up_to(vehicle: ShapeCastVehicle) -> void:
	# Stand 1 m outside the driver door.
	var door: Node3D = vehicle.get_node("DriverExit")
	var outward := (door.global_position - vehicle.global_position)
	outward.y = 0.0
	var spot := door.global_position + outward.normalized() * 1.0
	spot.y = 0.1
	character.place_at(spot, 0.0)


func _park_truck_against_driver_side() -> void:
	# Truck alongside the car's driver side with a 0.6 m gap: no room for the door.
	var position := car.to_global(Vector3(-2.3, 0.0, 0.0))
	truck.global_transform = Transform3D(car.global_basis.orthonormalized(),
			Vector3(position.x, car.global_position.y + 0.25, position.z))
	truck.linear_velocity = Vector3.ZERO
	truck.angular_velocity = Vector3.ZERO
	truck.reset_physics_interpolation()
	truck.get_node("Cargo").restack()


func _next() -> void:
	step += 1
	step_frame = 0


func _check(label: String, ok: bool, details: String) -> void:
	print("%-42s %s  %s" % [label, "OK" if ok else "FAIL", details])


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _press_key(keycode: Key) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = keycode
	key.pressed = true
	Input.parse_input_event(key)
	var release := key.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
