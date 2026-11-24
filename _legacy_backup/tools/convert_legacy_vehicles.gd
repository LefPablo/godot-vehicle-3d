extends Node
## One-off tool: converts the hand-built vehicles of the demo into vehicle
## definitions (res://vehicles/<id>/<id>.tres + <id>_body.tscn) and checks that
## each definition survives a JSON round trip. Run this scene (F6), then close it.

const DEMO_PATH := "res://scenes/demo/demo.tscn"
## [node name in the demo, id, display name]
const VEHICLES := [
	["Car", "car", "Car"],
	["Truck", "truck", "Truck"],
	["Trailer", "trailer", "Trailer"],
]


func _ready() -> void:
	print("=== Converting legacy vehicles ===")
	var demo := (load(DEMO_PATH) as PackedScene).instantiate()
	var ok := true
	for spec in VEHICLES:
		var vehicle := demo.get_node(spec[0]) as ShapeCastVehicle
		if vehicle.definition:
			print("%s already uses a definition, skipped" % spec[0])
			continue
		var dir := "res://vehicles/%s" % spec[1]
		DirAccess.make_dir_recursive_absolute(dir)
		var warnings: Array[String] = []
		var definition := VehicleSceneExtractor.extract(vehicle,
				"%s/%s_body.tscn" % [dir, spec[1]], warnings)
		definition.id = spec[1]
		definition.display_name = spec[2]
		if spec[1] == "truck":
			definition.category = "truck"
		if spec[1] == "trailer":
			definition.description = "Engine force comes from the demo, where the trailer " \
					+ "could be driven around on its own for testing. Set it to 0 for a real trailer."
		var path := "%s/%s.tres" % [dir, spec[1]]
		var error := ResourceSaver.save(definition, path)
		print("%s -> %s  %s" % [spec[0], path, error_string(error)])
		for w in warnings:
			print("  warning: ", w)
		ok = ok and error == OK

		# JSON round trip must reproduce every value.
		var json_path := "user://convert_check_%s.json" % spec[1]
		VehicleSerializer.save_json(definition, json_path)
		var read_warnings: Array[String] = []
		var copy := VehicleSerializer.load_json(json_path, read_warnings)
		var same := copy != null and VehicleSerializer.to_dict(copy) == VehicleSerializer.to_dict(definition)
		print("  JSON round trip: %s %s" % ["OK" if same else "MISMATCH", read_warnings])
		ok = ok and same
		print("  wheels: %d entries -> %d wheels, colliders %d, mount points %d, cargo %s" % [
				definition.wheels.size(), definition.expanded_wheels().size(),
				definition.colliders.size(), definition.mount_points.size(), definition.cargo != null])
		print(VehicleValidator.report_bbcode(definition))
	demo.free()
	print("=== Conversion %s ===" % ("finished" if ok else "FAILED"))
