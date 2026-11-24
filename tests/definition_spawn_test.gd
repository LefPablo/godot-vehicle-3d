extends Node
## Data-driven vehicle test: exports a definition to JSON under user://, finds it
## in the catalog, spawns it at runtime, checks it rests on its suspension, then
## tunes it live, changes its structure, checks Ackermann steering and spawns a
## trailer. Run this scene directly (F6) and close it after "done" is printed.

const DEMO := preload("res://scenes/demo/demo.tscn")
const PACK_DIR := "user://vehicles/test_pickup"
const JSON_PATH := PACK_DIR + "/pickup.json"

var demo: Node
var spawner: Node
var switcher: Node
var tow: Node


func _ready() -> void:
	demo = DEMO.instantiate()
	add_child(demo)
	spawner = demo.get_node("VehicleSpawner")
	switcher = demo.get_node("VehicleSwitcher")
	tow = demo.get_node("TowManager")
	print("=== Definition / spawn test ===")
	_run()


func _run() -> void:
	# 1. Export a variant of the truck as an external JSON "mod".
	var truck_definition := load("res://vehicles/truck/truck.tres") as VehicleDefinition
	var pickup := truck_definition.duplicate(true) as VehicleDefinition
	pickup.id = "pickup"
	pickup.display_name = "Pickup"
	pickup.mass = 1800.0
	pickup.cargo_spaces.clear()
	DirAccess.make_dir_recursive_absolute(PACK_DIR)
	var error := VehicleSerializer.save_json(pickup, JSON_PATH)
	_check("export JSON to user://", error == OK, JSON_PATH)

	# 2. Catalog.
	spawner.refresh_catalog()
	var names := PackedStringArray()
	for path in spawner.catalog:
		names.append(path.get_file())
	_check("catalog finds project + user vehicles", JSON_PATH in spawner.catalog
			and "res://vehicles/car/car.tres" in spawner.catalog, ", ".join(names))

	# 3. Spawn from JSON and let it settle.
	var vehicle: ShapeCastVehicle = spawner.spawn_definition(
			VehicleLoader.load_definition(JSON_PATH), Vector3(20.0, 0.0, 20.0), 0.0)
	await _wait(3.0)
	var total := 0.0
	for wheel in vehicle.wheels:
		total += wheel.suspension_force
	var weight := vehicle.mass * 9.81
	var wheel_count := pickup.expanded_wheels().size()
	_check("spawned JSON vehicle rests on its wheels", vehicle.wheels.size() == wheel_count
			and absf(total - weight) / weight < 0.1,
			"%s: wheels %d, forces %.0f N vs weight %.0f N" % [vehicle.name, vehicle.wheels.size(), total, weight])
	var estimate := vehicle.definition.estimate_ride_height()
	_check("ride height estimate", absf(vehicle.global_position.y - estimate) < 0.08,
			"actual %.3f m, estimated %.3f m" % [vehicle.global_position.y, estimate])
	_check("registered with the switcher", vehicle in switcher.vehicles, "")

	# 4. Live tuning (no rebuild): stiffer front springs.
	var front := vehicle.get_node("WheelFL") as ShapeCastWheel
	var old_height := vehicle.global_position.y
	vehicle.definition.wheels[0].suspension.spring_stiffness *= 2.0
	await _wait(2.0)
	var same_node := is_instance_valid(front) and vehicle.get_node("WheelFL") == front
	_check("live tuning applied without rebuild", same_node and front.spring_stiffness == 90000.0,
			"WheelFL k = %.0f, same node %s, height %.3f -> %.3f m" % [
				front.spring_stiffness if is_instance_valid(front) else 0.0, same_node,
				old_height, vehicle.global_position.y])

	# 5. Structural change (rebuild): add a cargo bed.
	vehicle.definition.cargo_spaces.append(truck_definition.cargo_spaces[0].duplicate(true))
	await _wait(1.0)
	var cargo := vehicle.get_node_or_null("Cargo")
	_check("structural change rebuilds", cargo != null and cargo.boxes.size() > 0
			and vehicle.wheels.size() == wheel_count, "cargo boxes %d, wheels %d" % [
				cargo.boxes.size() if cargo else 0, vehicle.wheels.size()])

	# 5b. Cargo capacity checks.
	var bed: VehicleCargoSpace = truck_definition.cargo_spaces[0]
	var fits_pallet := bed.can_fit(Vector3(1.2, 1.0, 0.8))          # turned 90 deg: 0.8 x 1.2
	var too_long := not bed.can_fit(Vector3(1.0, 0.5, 4.0))         # longer than the bed
	var tall_ok := bed.can_fit(Vector3(1.0, 2.2, 1.0))              # open top: 0.6 + 1.8 m
	var too_heavy := not bed.can_carry(Vector3(1, 1, 1), 1600.0)    # max 1500 kg
	var tipping := VehicleCargoSpace.new()
	tipping.size = Vector3(2.0, 0.5, 3.0)
	var lay_down := not tipping.can_fit(Vector3(0.4, 1.8, 0.4)) and tipping.can_fit(Vector3(0.4, 1.8, 0.4), true)
	tipping.accepted_tags = PackedStringArray(["pallet"])
	var tags_ok := tipping.accepts("pallet") and not tipping.accepts("liquid")
	var found := truck_definition.find_cargo_space(Vector3(1, 1, 1), 500.0) == bed
	_check("cargo capacity: size, height, mass, tags",
			fits_pallet and too_long and tall_ok and too_heavy and lay_down and tags_ok and found,
			"pallet %s, too long %s, tall %s, too heavy %s, tipping %s, tags %s, find %s" % [
				fits_pallet, too_long, tall_ok, too_heavy, lay_down, tags_ok, found])
	var load_mass: float = cargo.get_load_mass() if cargo else 0.0
	_check("cargo bay reports its load", load_mass > 0.0 and cargo.can_carry(Vector3(1, 1, 1), 100.0)
			and not cargo.can_carry(Vector3(1, 1, 1), 1500.0),
			"%.0f kg loaded of %.0f kg" % [load_mass, bed.max_mass])

	# 6. Ackermann: the inner wheel steers more.
	var car_definition := (load("res://vehicles/car/car.tres") as VehicleDefinition).duplicate(true) as VehicleDefinition
	car_definition.steering.ackermann = 1.0
	var car: ShapeCastVehicle = spawner.spawn_definition(car_definition, Vector3(-20.0, 0.0, 20.0), 0.0)
	await _wait(1.0)
	car.set_controls(0.0, 1.0, false) # full left
	await _wait(1.0)
	var left_angle := rad_to_deg((car.get_node("WheelFL") as Node3D).rotation.y)
	var right_angle := rad_to_deg((car.get_node("WheelFR") as Node3D).rotation.y)
	_check("Ackermann: inner (left) wheel steers more", left_angle > right_angle + 1.0,
			"left %.1f deg, right %.1f deg, nominal %.1f deg" % [
				left_angle, right_angle, rad_to_deg(car.steer_angle)])

	# 7. Trailer from a definition file.
	var trailer: ShapeCastVehicle = spawner.spawn_path("res://vehicles/trailer/trailer.tres")
	await _wait(0.5)
	_check("spawned trailer is registered for hitching", trailer in tow.trailers
			and trailer.get_node_or_null("Coupler") != null, String(trailer.name))

	# 8. A brand-new car: a .glb model whose wheels are separate nodes, plus a
	#    minimal hand-written JSON, both loaded at runtime from user://.
	var new_dir := "user://vehicles/test_new_car"
	DirAccess.make_dir_recursive_absolute(new_dir)
	error = _write_test_model(new_dir.path_join("new_car.glb"))
	_check("test model exported as .glb", error == OK, error_string(error))
	var json_text := """{
	"format": "shapecast_vehicle", "version": 1,
	"id": "new_car", "display_name": "New Car", "mass": 1300,
	"center_of_mass": [0, -0.1, 0],
	"model": "new_car.glb", "auto_collision": "model_bounding_box",
	"wheels": [
		{"name": "WheelFL", "position": [-0.9, 0.1, -1.3], "mirror": true, "steering": true,
		 "radius": 0.35, "width": 0.25, "model_node": "Wheels/FL", "mirror_model_node": "Wheels/FR"},
		{"name": "WheelRL", "position": [-0.9, 0.1, 1.3], "mirror": true, "drive": true, "handbrake": true,
		 "radius": 0.35, "width": 0.25, "model_node": "Wheels/RL", "mirror_model_node": "Wheels/RR"}
	],
	"mount_points": [
		{"kind": "tow_hook_front", "position": [0, 0.1, -2.05]},
		{"kind": "driver_exit", "position": [-1.5, 0, 0]}
	]
}"""
	var json_file := FileAccess.open(new_dir.path_join("new_car.json"), FileAccess.WRITE)
	json_file.store_string(json_text)
	json_file.close()
	var load_warnings: Array[String] = []
	var new_definition := VehicleLoader.load_definition(new_dir.path_join("new_car.json"), load_warnings)
	_check("hand-written JSON loads cleanly", new_definition != null and load_warnings.is_empty()
			and new_definition.model != null, str(load_warnings))
	var new_car: ShapeCastVehicle = spawner.spawn_definition(new_definition, Vector3(-30.0, 0.0, 25.0), 0.0)
	await _wait(3.0)
	var body := new_car.get_node_or_null("Body")
	var front_left := new_car.get_node("WheelFL") as ShapeCastWheel
	var wheels_taken := body != null and body.get_node_or_null("Wheels/FL") == null \
			and is_instance_valid(front_left._custom_visual)
	_check("model wheel nodes drive the wheels", wheels_taken,
			"body %s, WheelFL visual %s" % [body != null, front_left._custom_visual])
	var collision := new_car.get_node_or_null("ModelCollision") as CollisionShape3D
	var box_size := (collision.shape as BoxShape3D).size if collision else Vector3.ZERO
	_check("auto collision box excludes the wheels", box_size.is_equal_approx(Vector3(1.8, 0.6, 4.0)),
			str(box_size))
	total = 0.0
	for wheel in new_car.wheels:
		total += wheel.suspension_force
	weight = new_car.mass * 9.81
	_check("new car rests on its suspension", absf(total - weight) / weight < 0.1,
			"forces %.0f N vs weight %.0f N, height %.3f (estimated %.3f)" % [
				total, weight, new_car.global_position.y, new_definition.estimate_ride_height()])

	# 9. Package export of a project vehicle (JSON + .glb) and loading it back.
	var pack_dir := "user://vehicles/test_truck_pack"
	var pack_warnings: Array[String] = []
	error = VehicleSerializer.export_package(truck_definition, pack_dir.path_join("truck.json"), true, pack_warnings)
	var packed_definition := VehicleLoader.load_definition(pack_dir.path_join("truck.json"), pack_warnings)
	var model_source := VehicleSerializer.resource_source_path(packed_definition.model) if packed_definition else ""
	_check("package export -> runtime load", error == OK and packed_definition != null
			and model_source.ends_with("truck.glb") and pack_warnings.is_empty(),
			"model %s %s" % [model_source, pack_warnings])

	# 10. Collision scene (shapes edited in the editor), in model space.
	var pickup_definition := load("res://vehicles/pickup/pickup.tres") as VehicleDefinition
	var real_pickup: ShapeCastVehicle = spawner.spawn_definition(pickup_definition, Vector3(-40.0, 0.0, 30.0), 0.0)
	await _wait(3.0)
	var cab := real_pickup.get_node_or_null("CabCollision") as CollisionShape3D
	var expected_cab := Vector3(-0.0237, 1.4670 - 0.575, -0.5180) # scene position + model offset
	var nested_bodies := real_pickup.find_children("*", "PhysicsBody3D", true, false).size()
	# Every shape of the collision scene and every numeric collider must be on the vehicle.
	var scene_shapes := VehicleBuilder.collision_scene_shapes(pickup_definition)
	var missing := PackedStringArray()
	for entry in scene_shapes:
		if not real_pickup.has_node(NodePath(entry.name)):
			missing.append(entry.name)
	for config in pickup_definition.colliders:
		if not real_pickup.has_node(NodePath(config.name)):
			missing.append(config.name)
	_check("collision scene shapes in model space", cab != null and scene_shapes.size() > 0
			and cab.position.distance_to(expected_cab) < 0.001 and missing.is_empty() and nested_bodies == 0,
			"%d scene shapes, CabCollision at %s (expected %s), missing %s, bodies inside the vehicle: %d" % [
				scene_shapes.size(), cab.position if cab else Vector3.INF, expected_cab, missing, nested_bodies])
	total = 0.0
	for wheel in real_pickup.wheels:
		total += wheel.suspension_force
	var pickup_bay := real_pickup.get_node_or_null("Cargo") as VehicleCargoBay
	var pickup_load := pickup_bay.get_load_mass() if pickup_bay else 0.0
	weight = (real_pickup.mass + pickup_load) * 9.81
	_check("your pickup rests on its suspension", absf(total - weight) / weight < 0.1
			and real_pickup.global_basis.y.y > 0.99,
			"forces %.0f N vs weight %.0f N (body + %.0f kg cargo), height %.3f m" % [
				total, weight, pickup_load, real_pickup.global_position.y])
	var flat_warnings: Array[String] = []
	var flat_dir := "user://vehicles/test_pickup_pack"
	VehicleSerializer.export_package(pickup_definition, flat_dir.path_join("pickup.json"), false, flat_warnings)
	var flat := VehicleSerializer.read_json_file(flat_dir.path_join("pickup.json"))
	var flat_colliders: Array = flat.get("colliders", [])
	var expected_flat := scene_shapes.size() + pickup_definition.colliders.size()
	_check("JSON export flattens the collision scene", flat.get("collision_scene") == null
			and flat_colliders.size() == expected_flat and flat_warnings.is_empty(),
			"%d of %d colliders %s" % [flat_colliders.size(), expected_flat, flat_warnings])
	var issues := VehicleValidator.validate(pickup_definition)
	var problems := PackedStringArray()
	for issue in issues:
		if issue.level != VehicleValidator.Level.INFO:
			problems.append(issue.text)
	print("  pickup validation: %s" % ("no warnings" if problems.is_empty() else " | ".join(problems)))
	var uid_text := ResourceUID.id_to_text(ResourceLoader.get_resource_uid("res://vehicles/pickup/pickup.tres"))
	var uid_warnings: Array[String] = []
	var by_uid := VehicleLoader.load_definition(uid_text, uid_warnings)
	_check("definitions load from uid:// paths", by_uid == pickup_definition and uid_warnings.is_empty(),
			"%s -> %s %s" % [uid_text, VehicleLoader.resolve_uid(uid_text), uid_warnings])
	_remove_dir(flat_dir)

	# Clean up the test files.
	for dir in [PACK_DIR, new_dir, pack_dir]:
		_remove_dir(dir)
	print("=== done ===")


## A car model: body box + four wheel cylinders under "Wheels", saved as .glb.
func _write_test_model(path: String) -> Error:
	var root := Node3D.new()
	root.name = "NewCarModel"
	var body := MeshInstance3D.new()
	body.name = "Body"
	var box := BoxMesh.new()
	box.size = Vector3(1.8, 0.6, 4.0)
	body.mesh = box
	body.position.y = 0.3
	root.add_child(body)
	var wheels := Node3D.new()
	wheels.name = "Wheels"
	root.add_child(wheels)
	for spec: Array in [["FL", Vector3(-0.9, -0.1, -1.3)], ["FR", Vector3(0.9, -0.1, -1.3)],
			["RL", Vector3(-0.9, -0.1, 1.3)], ["RR", Vector3(0.9, -0.1, 1.3)]]:
		var wheel := MeshInstance3D.new()
		wheel.name = spec[0]
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.35
		cylinder.bottom_radius = 0.35
		cylinder.height = 0.25
		wheel.mesh = cylinder
		wheel.rotation.z = PI * 0.5
		wheel.position = spec[1]
		wheels.add_child(wheel)
	VehicleSceneExtractor.own_recursive(root, root)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_scene(root, state)
	if error == OK:
		error = document.write_to_filesystem(state, path)
	root.free()
	return error


func _remove_dir(dir: String) -> void:
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout


func _check(label: String, ok: bool, details: String) -> void:
	print("%-44s %s  %s" % [label, "OK" if ok else "FAIL", details])
