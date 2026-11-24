extends Node
## AI driver on the demo road network: press the toggle (H), let the AI drive
## the Car through the crossroads, check lane keeping and turn choices, then
## toggle back. Run directly (F6).

const DEMO := preload("res://scenes/demo/demo.tscn")
const DRIVE_TIME := 150.0

var demo: Node
var car: ShapeCastVehicle
var driver: VehicleAIDriver
var toggle: Node
var switcher: Node


func _ready() -> void:
	demo = DEMO.instantiate()
	driver = demo.get_node("Car/AIDriver")
	driver.random_seed = 7 # repeatable choices
	add_child(demo)
	car = demo.get_node("Car")
	toggle = demo.get_node("AIDriverToggle")
	switcher = demo.get_node("VehicleSwitcher")
	print("=== AI driver test ===")
	_run()


func _run() -> void:
	await _wait(1.0)
	var roads := get_tree().get_nodes_in_group(VehicleRoad.GROUP).size()
	var junctions := get_tree().get_nodes_in_group(VehicleRoadJunction.GROUP)
	var legs := PackedStringArray()
	for junction: VehicleRoadJunction in junctions:
		legs.append("%s: %d roads" % [junction.name, junction.get_legs().size()])
	_check("road network", roads == 4 and junctions.size() == 2, "%d roads, %s" % [roads, ", ".join(legs)])

	driver.turning.connect(func(kind: String, junction: Node, to_road: Node) -> void:
		print("  turn: %-8s at %s onto %s (%.0f km/h)" % [kind, junction.name, to_road.name,
				car.forward_speed * 3.6]))
	toggle.toggle()
	_check("H gives the Car to the AI", driver.is_driving() and not car.use_player_input
			and switcher.active_vehicle == car, "player in %s" % switcher.active_vehicle.name)

	var time := 0.0
	var joined_at := -1.0
	var max_error := 0.0
	var error_sum := 0.0
	var samples := 0
	var max_speed := 0.0
	var speed_sum := 0.0
	var max_roll := 0.0
	while time < DRIVE_TIME:
		await _wait(0.25)
		time += 0.25
		var error := driver.lane_error
		if joined_at < 0.0 and error < 1.0:
			joined_at = time
		if joined_at >= 0.0:
			max_error = maxf(max_error, error)
			error_sum += error
			samples += 1
			max_speed = maxf(max_speed, car.forward_speed * 3.6)
			speed_sum += car.forward_speed * 3.6
		max_roll = maxf(max_roll, rad_to_deg(acos(clampf(car.global_basis.y.y, -1.0, 1.0))))

	var mean_error := error_sum / maxi(samples, 1)
	var mean_speed := speed_sum / maxi(samples, 1)
	var turn_kinds := 0
	var turn_total := 0
	for kind: String in driver.turns:
		turn_total += driver.turns[kind]
		if driver.turns[kind] > 0:
			turn_kinds += 1
	_check("reaches the road", joined_at >= 0.0 and joined_at < 20.0, "on its lane after %.1f s" % joined_at)
	_check("keeps its lane (also in turns)", max_error < 2.0 and mean_error < 0.5,
			"mean error %.2f m, max %.2f m" % [mean_error, max_error])
	_check("drives at a sensible speed", mean_speed > 20.0 and max_speed <= driver.max_speed_kmh + 5.0,
			"mean %.0f km/h, max %.0f km/h (limit %.0f)" % [mean_speed, max_speed, driver.max_speed_kmh])
	_check("turns at the crossroads", turn_total >= 3 and turn_kinds >= 2,
			"%s, %.0f m driven" % [driver.turns, driver.distance_on_route])
	_check("no recoveries, stays upright", driver.recoveries == 0 and max_roll < 15.0,
			"recoveries %d, max roll %.1f deg" % [driver.recoveries, max_roll])

	toggle.toggle()
	await _wait(0.5)
	_check("H again gives the Car back", not driver.is_driving() and car.use_player_input, "")
	print("=== done ===")


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout


func _check(label: String, ok: bool, details: String) -> void:
	print("%-32s %s  %s" % [label, "OK" if ok else "FAIL", details])
