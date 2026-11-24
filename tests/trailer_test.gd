extends Node
## Trailer test: parked trailer on its jack, reversing up to it, hitching (T),
## towing straight / turn / reverse, unhitching, and hitching to the higher truck hitch.
## Run this scene directly (F6) and close it after "done" is printed.

const DEMO := preload("res://scenes/demo/demo.tscn")

var car: ShapeCastVehicle
var truck: ShapeCastVehicle
var trailer: ShapeCastVehicle
var switcher: Node
var tow: Node
var cargo: Node

var phase := "settle"
var phase_frame := 0
var lane_x := 8.0
var stats := {}


func _ready() -> void:
	process_physics_priority = 100
	var demo := DEMO.instantiate()
	add_child(demo)
	car = demo.get_node("Car")
	truck = demo.get_node("Truck")
	trailer = demo.get_node("Trailer")
	switcher = demo.get_node("VehicleSwitcher")
	tow = demo.get_node("TowManager")
	cargo = trailer.get_node("Cargo")
	print("=== Trailer test ===")


func _physics_process(_delta: float) -> void:
	phase_frame += 1
	match phase:
		"settle":
			if phase_frame == 360:
				_report_trailer("Parked trailer (on its jack)")
				_place_car_in_front_of_trailer()
				_next("reverse_to_trailer")
		"reverse_to_trailer":
			_reverse_to_trailer()
		"hitched":
			if phase_frame == 10:
				var c: Dictionary = tow.connections[0] if tow.is_towing() else {}
				var ok: bool = not c.is_empty() and c.kind == &"trailer" and c.tower == car \
						and c.towed == trailer and trailer.is_towed
				print("after T: kind=%s tower=%s trailer.is_towed=%s coupler gap %.3f m, cargo %d/%d  %s" % [
					c.get("kind", "none"), _name(c.get("tower")), trailer.is_towed, _hitch_gap(car),
					cargo.count_in_bed(), cargo.boxes.size(), "OK" if ok else "FAIL"])
				lane_x = car.global_position.x
				_next("straight")
		"straight":
			_drive(car, 8.0, _keep_x(car))
			_measure(car)
			if phase_frame >= 120 * 10:
				_report("Car pulling the trailer straight, ~29 km/h, 10 s")
				_next("turn")
		"turn":
			_drive(car, 5.0, 0.7)
			_measure(car)
			if phase_frame >= 120 * 7:
				_report("Left turn, ~18 km/h, 7 s")
				_next("stop")
		"stop":
			car.set_controls(-1.0 if car.forward_speed > 0.3 else 0.0, 0.0, car.forward_speed <= 0.3)
			if phase_frame >= 240:
				_next("reverse")
		"reverse":
			car.set_controls(-0.4, 0.0, false)
			_measure(car)
			if phase_frame >= 120 * 4:
				_report("Reversing with the trailer, wheels straight, 4 s")
				_next("unhitch")
		"unhitch":
			car.set_controls(0.0, 0.0, true)
			if phase_frame == 120:
				_press_key(KEY_T)
			if phase_frame == 130:
				var ok: bool = not tow.is_towing() and not trailer.is_towed and trailer._handbrake
				print("after second T: coupled=%s trailer.is_towed=%s trailer brake=%s  %s" % [
					tow.is_towing(), trailer.is_towed, trailer._handbrake, "OK" if ok else "FAIL"])
			if phase_frame == 480:
				_report_trailer("Unhitched trailer after 3 s")
				_place_truck_in_front_of_trailer()
				_next("truck_settle")
		"truck_settle":
			if phase_frame == 240:
				print("truck parked, hitch %.2f m from coupler; HUD: \"%s\"" % [
					_hitch_gap(truck), tow.get_status_text()])
				_press_key(KEY_T)
			if phase_frame == 250:
				var c: Dictionary = tow.connections[0] if tow.is_towing() else {}
				print("truck hitch: kind=%s tower=%s gap %.3f m, trailer pitch %.1f deg  %s" % [
					c.get("kind", "none"), _name(c.get("tower")), _hitch_gap(truck),
					rad_to_deg(trailer.global_rotation.x),
					"OK" if not c.is_empty() and c.tower == truck else "FAIL"])
				lane_x = truck.global_position.x
				_next("truck_drive")
		"truck_drive":
			_drive(truck, 7.0, _keep_x(truck))
			_measure(truck)
			if phase_frame >= 120 * 8:
				_report("Truck pulling the trailer straight, ~25 km/h, 8 s")
				print("=== done ===")
				_next("done")


func _place_car_in_front_of_trailer() -> void:
	# Car stops 3 m in front of the coupler, facing away from it, then reverses.
	var coupler: Node3D = trailer.get_node("Coupler")
	car.global_transform = Transform3D(Basis.IDENTITY,
			Vector3(coupler.global_position.x, 0.9, coupler.global_position.z - 2.07 - 3.0))
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.reset_physics_interpolation()
	switcher.activate(0)
	car.use_player_input = false
	car.set_controls(0.0, 0.0, true)


func _reverse_to_trailer() -> void:
	var gap := _hitch_gap(car)
	if phase_frame == 120:
		print("HUD while reversing: \"%s\"" % tow.get_status_text())
	if phase_frame < 120:
		car.set_controls(0.0, 0.0, true) # settle first
		return
	var reverse_speed := -car.forward_speed
	var target_speed := clampf(gap - 0.3, 0.0, 1.5)
	if gap <= 0.5:
		car.set_controls(0.0, 0.0, true)
		if absf(car.forward_speed) < 0.05:
			print("stopped with hitch %.2f m from coupler; HUD: \"%s\"" % [gap, tow.get_status_text()])
			_press_key(KEY_T)
			_next("hitched")
	elif reverse_speed < target_speed:
		car.set_controls(-0.4, 0.0, false)
	else:
		car.set_controls(0.0, 0.0, true)
	if phase_frame > 120 * 15:
		print("FAIL: could not reverse to the trailer (gap %.2f m)" % gap)
		_next("done")


func _place_truck_in_front_of_trailer() -> void:
	# Truck hitch 0.6 m in front of the coupler, facing the way the trailer faces.
	var coupler: Node3D = trailer.get_node("Coupler")
	var yaw := trailer.global_rotation.y
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var hitch_target := coupler.global_position + forward * 0.6
	var basis := Basis(Vector3.UP, yaw)
	var hitch_offset: Vector3 = basis * (truck.get_node("TowHitchRear") as Node3D).position
	truck.global_transform = Transform3D(basis,
			Vector3(hitch_target.x - hitch_offset.x, 1.2, hitch_target.z - hitch_offset.z))
	truck.linear_velocity = Vector3.ZERO
	truck.angular_velocity = Vector3.ZERO
	truck.reset_physics_interpolation()
	truck.get_node("Cargo").restack()
	switcher.activate(1)
	truck.use_player_input = false
	truck.set_controls(0.0, 0.0, true)


func _next(new_phase: String) -> void:
	phase = new_phase
	phase_frame = 0
	stats = {"max_gap": 0.0, "max_angle": 0.0, "max_trailer_roll": 0.0, "max_trailer_pitch": 0.0,
			"trailer_flipped": false}


func _drive(vehicle: ShapeCastVehicle, speed: float, steer: float) -> void:
	vehicle.set_controls(clampf((speed - vehicle.forward_speed) * 0.6, -1.0, 1.0), steer, false)


func _keep_x(vehicle: ShapeCastVehicle) -> float:
	return clampf((vehicle.global_position.x - lane_x) * 0.3 + (-vehicle.global_basis.z).x * 2.0, -1.0, 1.0)


func _measure(vehicle: ShapeCastVehicle) -> void:
	stats.max_gap = maxf(stats.max_gap, _hitch_gap(vehicle))
	if tow.is_towing():
		stats.max_angle = maxf(stats.max_angle, absf(rad_to_deg(tow.hitch_angle(tow.connections[0]))))
	stats.max_trailer_roll = maxf(stats.max_trailer_roll, absf(rad_to_deg(trailer.global_rotation.z)))
	stats.max_trailer_pitch = maxf(stats.max_trailer_pitch, absf(rad_to_deg(trailer.global_rotation.x)))
	if trailer.global_basis.y.y < 0.3:
		stats.trailer_flipped = true


func _report(title: String) -> void:
	print("--- %s ---" % title)
	print("  still hitched: %s, max hitch-coupler separation %.1f cm, max hitch angle %.0f deg" % [
		tow.is_towing(), stats.max_gap * 100.0, stats.max_angle])
	print("  trailer: max roll %.1f deg, max pitch %.1f deg, flipped=%s, cargo %d/%d, speed %.1f km/h" % [
		stats.max_trailer_roll, stats.max_trailer_pitch, stats.trailer_flipped,
		cargo.count_in_bed(), cargo.boxes.size(), trailer.linear_velocity.length() * 3.6])
	var comps := PackedStringArray()
	for w in trailer.wheels:
		comps.append("%s %.0f%%" % [w.name, w.compression_ratio * 100.0])
	print("  trailer suspension now: %s" % ", ".join(comps))


func _report_trailer(title: String) -> void:
	var coupler: Node3D = trailer.get_node("Coupler")
	print("--- %s ---" % title)
	print("  pitch %.1f deg, coupler height %.2f m, speed %.2f m/s, cargo %d/%d" % [
		rad_to_deg(trailer.global_rotation.x), coupler.global_position.y,
		trailer.linear_velocity.length(), cargo.count_in_bed(), cargo.boxes.size()])
	for w in trailer.wheels:
		print("  %s compression %.3f m (%.0f%%) force %.0f N" % [
			w.name, w.compression, w.compression_ratio * 100.0, w.suspension_force])


func _hitch_gap(vehicle: ShapeCastVehicle) -> float:
	var hitch: Node3D = vehicle.get_node("TowHitchRear")
	var coupler: Node3D = trailer.get_node("Coupler")
	return hitch.global_position.distance_to(coupler.global_position)


func _press_key(keycode: Key) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = keycode
	key.pressed = true
	Input.parse_input_event(key)
	var release := key.duplicate()
	release.pressed = false
	Input.parse_input_event(release)


func _name(node: Variant) -> String:
	return String(node.name) if node is Node else "none"
