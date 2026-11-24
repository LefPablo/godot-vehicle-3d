@tool
extends VBoxContainer
## "Vehicles" dock: create, check, import / export and test drive vehicle definitions.
##
## Selecting a VehicleDefinition (or a vehicle node that uses one) in the
## editor makes it the dock's current vehicle.

const TEST_DRIVE_SCENE := "res://addons/vehicle_system/test_drive/test_drive.tscn"
const TEST_DRIVE_CONFIG := "user://vehicle_test_drive.cfg"
const VEHICLES_DIR := "res://vehicles"
const IMPORT_TIMEOUT_MS := 30000

var plugin: EditorPlugin

var _picker: EditorResourcePicker
var _export_model: CheckBox
var _report: RichTextLabel
var _file_dialog: EditorFileDialog
var _dialog_action: Callable


func _ready() -> void:
	custom_minimum_size = Vector2(240, 300)
	var title := Label.new()
	title.text = "Vehicle definition"
	add_child(title)

	_picker = EditorResourcePicker.new()
	_picker.base_type = "VehicleDefinition"
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.resource_changed.connect(func(_resource: Resource) -> void: _validate())
	add_child(_picker)

	var buttons := HFlowContainer.new()
	add_child(buttons)
	_add_button(buttons, "New…", "Create a new vehicle definition from a template.", _new_vehicle)
	_add_button(buttons, "Validate", "Check the definition and show suspension numbers.", _validate)
	_add_button(buttons, "Test drive", "Save the definition and drive it on the vehicle test track.", _test_drive)
	_add_button(buttons, "Add to scene", "Add a vehicle with this definition to the edited scene.", _add_to_scene)
	_add_button(buttons, "Edit collision",
			"Open the vehicle's collision scene (created from its current colliders) to edit the shapes with gizmos.",
			_edit_collision)
	_add_button(buttons, "Create scene", "Save a vehicle scene (.tscn) that uses this definition.", _create_scene)
	_add_button(buttons, "Extract from selected",
			"Make a definition from the selected hand-built ShapeCastVehicle.", _extract_selected)
	_add_button(buttons, "Import JSON…", "Import a vehicle .json (and its model) into res://vehicles.", _import_json)
	_add_button(buttons, "Export JSON…", "Write the definition as .json (optionally with a .glb model).", _export_json)
	_add_button(buttons, "Rebuild previews", "Rebuild all definition-driven vehicles in the edited scene.", _rebuild_previews)

	_export_model = CheckBox.new()
	_export_model.text = "Export model as .glb with JSON"
	_export_model.button_pressed = true
	add_child(_export_model)

	_report = RichTextLabel.new()
	_report.bbcode_enabled = true
	_report.selection_enabled = true
	_report.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_report.custom_minimum_size = Vector2(0, 200)
	add_child(_report)
	_report.text = "Select a VehicleDefinition (.tres) or a vehicle node, or create a new one."

	_file_dialog = EditorFileDialog.new()
	_file_dialog.file_selected.connect(func(path: String) -> void: _dialog_action.call(path))
	add_child(_file_dialog)

	EditorInterface.get_inspector().edited_object_changed.connect(_on_inspector_object_changed)


func _exit_tree() -> void:
	var inspector := EditorInterface.get_inspector()
	if inspector and inspector.edited_object_changed.is_connected(_on_inspector_object_changed):
		inspector.edited_object_changed.disconnect(_on_inspector_object_changed)


# --- Current definition -------------------------------------------------------

func _current() -> VehicleDefinition:
	return _picker.edited_resource as VehicleDefinition


func _set_current(definition: VehicleDefinition) -> void:
	if definition != _current():
		_picker.edited_resource = definition
		_validate()


func _on_inspector_object_changed() -> void:
	var object := EditorInterface.get_inspector().get_edited_object()
	if object is VehicleDefinition:
		_set_current(object)
	elif object is ShapeCastVehicle and object.definition:
		_set_current(object.definition)


func _saved_path(definition: VehicleDefinition) -> String:
	var path := definition.resource_path
	return path if path != "" and not path.contains("::") else ""


# --- Actions ------------------------------------------------------------------

func _validate() -> void:
	var definition := _current()
	if definition == null:
		_report.text = "No definition selected."
		return
	_report.text = VehicleValidator.report_bbcode(definition)


func _new_vehicle() -> void:
	_ask_file(EditorFileDialog.FILE_MODE_SAVE_FILE, EditorFileDialog.ACCESS_RESOURCES,
			["*.tres ; Vehicle definition"], VEHICLES_DIR.path_join("new_vehicle/new_vehicle.tres"),
			_create_new_vehicle)


func _create_new_vehicle(path: String) -> void:
	var definition := _template(path.get_file().get_basename())
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := ResourceSaver.save(definition, path)
	if error != OK:
		_fail("Can't save %s: %s" % [path, error_string(error)])
		return
	EditorInterface.get_resource_filesystem().update_file(path)
	var saved := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as VehicleDefinition
	_set_current(saved)
	EditorInterface.edit_resource(saved)
	_report.text = ("[b]Created %s[/b]\nSet its model, move the wheels and mount points, " % path) \
			+ "then use Add to scene to preview it.\n\n" + VehicleValidator.report_bbcode(saved)


func _test_drive() -> void:
	var definition := _require_saved()
	if definition == null:
		return
	# Save pending inspector edits: the game loads the file from disk.
	var error := ResourceSaver.save(definition)
	if error != OK:
		_fail("Can't save %s: %s" % [definition.resource_path, error_string(error)])
		return
	var config := ConfigFile.new()
	config.set_value("test_drive", "definition", definition.resource_path)
	config.save(TEST_DRIVE_CONFIG)
	EditorInterface.play_custom_scene(TEST_DRIVE_SCENE)


func _add_to_scene() -> void:
	var definition := _current()
	var root := EditorInterface.get_edited_scene_root()
	if definition == null or root == null:
		_fail("Select a definition and open a 3D scene first.")
		return
	if not root is Node3D:
		_fail("The edited scene's root must be a Node3D.")
		return
	var vehicle := VehicleBuilder.create(definition)
	vehicle.position = Vector3.UP * definition.estimate_ride_height()
	var undo_redo := plugin.get_undo_redo()
	undo_redo.create_action("Add vehicle %s" % vehicle.name)
	undo_redo.add_do_method(root, "add_child", vehicle, true)
	undo_redo.add_do_method(vehicle, "set_owner", root)
	undo_redo.add_do_reference(vehicle)
	undo_redo.add_undo_method(root, "remove_child", vehicle)
	undo_redo.commit_action()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(vehicle)
	_report.text = "Added [b]%s[/b]. Edit the definition in the inspector: the preview updates live.\n\n" \
			% vehicle.name + VehicleValidator.report_bbcode(definition)


## Opens the collision scene of the definition. The first time it is created
## from the definition's numeric / auto colliders, which it then replaces.
func _edit_collision() -> void:
	var definition := _require_saved()
	if definition == null:
		return
	var existing := VehicleSerializer.resource_source_path(definition.collision_scene)
	if existing != "" and existing.begins_with("res://") and existing.get_extension() in ["tscn", "scn"]:
		EditorInterface.open_scene_from_path(existing)
		_report.text = _collision_help(existing)
		return
	if existing != "":
		_fail("The collision scene is %s (a model file). Edit it in your 3D tool, or clear " % existing
				+ "collision_scene and press Edit collision again to create an editable scene.")
		return

	var path := definition.resource_path.get_base_dir().path_join(definition.id + "_collision.tscn")
	var root := VehicleCollisionShapes.new()
	root.name = (definition.id + "_collision").to_pascal_case()
	root.reference_definition = definition.resource_path
	for config in definition.colliders:
		if config:
			_add_shape(root, config.name, config.create_shape(), config.get_transform())
	var auto_shape: Variant = VehicleBuilder.compute_auto_collision(definition)
	if auto_shape:
		_add_shape(root, "ModelCollision", auto_shape.shape, auto_shape.transform)
	if root.get_child_count() == 0:
		# Nothing yet: a box around the body to start from.
		var box := BoxShape3D.new()
		box.size = Vector3(1.8, 0.8, 4.2)
		_add_shape(root, "BodyCollision", box, Transform3D(Basis.IDENTITY, Vector3.UP * 0.3))
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	var error := ResourceSaver.save(scene, path)
	if error != OK:
		_fail("Can't save %s: %s" % [path, error_string(error)])
		return
	EditorInterface.get_resource_filesystem().update_file(path)

	# The scene now holds the shapes: point the definition at it.
	definition.collision_scene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE)
	definition.collision_scene_in_model_space = false
	definition.colliders.clear()
	definition.auto_collision = VehicleDefinition.AutoCollision.NONE
	error = ResourceSaver.save(definition)
	if error != OK:
		_fail("Can't save %s: %s" % [definition.resource_path, error_string(error)])
		return
	definition.emit_changed()
	EditorInterface.open_scene_from_path(path)
	_report.text = "[b]Created %s[/b] from the definition's colliders.\n" % path + _collision_help(path)


func _add_shape(root: Node3D, shape_name: String, shape: Shape3D, xform: Transform3D) -> void:
	var node := CollisionShape3D.new()
	node.name = shape_name if shape_name != "" else "BodyCollision"
	node.shape = shape.duplicate()
	node.transform = xform
	root.add_child(node, true)
	node.owner = root


func _collision_help(path: String) -> String:
	return ("Editing [b]%s[/b]\n" % path) \
			+ "Select a shape and drag its handles; add CollisionShape3D nodes (Box, Sphere, Capsule, " \
			+ "Cylinder, ConvexPolygon) for more parts. The vehicle is shown for reference. " \
			+ "Save (Ctrl+S): vehicle previews update automatically. Name shapes freely, " \
			+ "except with the ending 'Collider' (reserved for wheels)."


func _create_scene() -> void:
	var definition := _require_saved()
	if definition == null:
		return
	var path := definition.resource_path.get_base_dir().path_join(definition.id + ".tscn")
	if not FileAccess.file_exists(path):
		var vehicle := VehicleBuilder.create(definition)
		var scene := PackedScene.new()
		scene.pack(vehicle)
		vehicle.free()
		var error := ResourceSaver.save(scene, path)
		if error != OK:
			_fail("Can't save %s: %s" % [path, error_string(error)])
			return
		EditorInterface.get_resource_filesystem().update_file(path)
	EditorInterface.open_scene_from_path(path)
	_report.text = "Opened [b]%s[/b]. Instance it in your levels like any scene." % path


func _extract_selected() -> void:
	var vehicle: ShapeCastVehicle = null
	for node in EditorInterface.get_selection().get_selected_nodes():
		if node is ShapeCastVehicle:
			vehicle = node
			break
	if vehicle == null:
		_fail("Select a hand-built ShapeCastVehicle node in the scene tree.")
		return
	if vehicle.definition:
		_set_current(vehicle.definition)
		_fail("%s already uses a definition (%s)." % [vehicle.name, vehicle.definition.resource_path])
		return
	var id := String(vehicle.name).to_snake_case()
	var dir := _unique_dir(VEHICLES_DIR.path_join(id))
	DirAccess.make_dir_recursive_absolute(dir)
	var warnings: Array[String] = []
	var definition := VehicleSceneExtractor.extract(vehicle, dir.path_join(id + "_body.tscn"), warnings)
	definition.id = id
	var path := dir.path_join(id + ".tres")
	var error := ResourceSaver.save(definition, path)
	if error != OK:
		_fail("Can't save %s: %s" % [path, error_string(error)])
		return
	EditorInterface.get_resource_filesystem().scan()
	_set_current(ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as VehicleDefinition)
	_report.text = "[b]Extracted %s -> %s[/b]\n%s\n\n%s" % [
			vehicle.name, path, _warnings_bbcode(warnings), VehicleValidator.report_bbcode(_current())]


func _import_json() -> void:
	_ask_file(EditorFileDialog.FILE_MODE_OPEN_FILE, EditorFileDialog.ACCESS_FILESYSTEM,
			["*.json ; Vehicle JSON"], "", _import_json_file)


func _import_json_file(path: String) -> void:
	var warnings: Array[String] = []
	var data := VehicleSerializer.read_json_file(path, warnings)
	if data.is_empty():
		_fail(_warnings_bbcode(warnings))
		return
	var source_dir := path.get_base_dir()
	var id := str(data.get("id", path.get_file().get_basename())).validate_filename()
	var dir := VEHICLES_DIR.path_join(id)
	DirAccess.make_dir_recursive_absolute(dir)

	# Copy the model and wheel models into the project, next to the definition.
	var copied: Array[String] = []
	if data.get("model") is String:
		data["model"] = _import_asset(data["model"], source_dir, dir, copied, warnings)
	var wheels: Variant = data.get("wheels", [])
	if wheels is Array:
		for wheel: Variant in wheels:
			if wheel is Dictionary and wheel.get("visual_scene") is String:
				wheel["visual_scene"] = _import_asset(wheel["visual_scene"], source_dir, dir, copied, warnings)
	if not copied.is_empty():
		_report.text = "Importing %s…" % ", ".join(copied)
		if not await _wait_for_import(copied):
			warnings.append("The editor hasn't finished importing %s; run Import again if the model is missing." \
					% ", ".join(copied))

	var definition := VehicleSerializer.from_dict(data, dir, warnings)
	var target := dir.path_join(id + ".tres")
	if FileAccess.file_exists(target):
		target = dir.path_join(id + "_imported.tres")
		warnings.append("%s already existed; saved as %s." % [id + ".tres", target.get_file()])
	var error := ResourceSaver.save(definition, target)
	if error != OK:
		_fail("Can't save %s: %s" % [target, error_string(error)])
		return
	EditorInterface.get_resource_filesystem().update_file(target)
	var saved := ResourceLoader.load(target, "", ResourceLoader.CACHE_MODE_REPLACE) as VehicleDefinition
	_set_current(saved)
	EditorInterface.edit_resource(saved)
	_report.text = "[b]Imported %s -> %s[/b]\n%s\n\n%s" % [
			path.get_file(), target, _warnings_bbcode(warnings), VehicleValidator.report_bbcode(saved)]


func _export_json() -> void:
	var definition := _current()
	if definition == null:
		_fail("Select a definition first.")
		return
	_ask_file(EditorFileDialog.FILE_MODE_SAVE_FILE, EditorFileDialog.ACCESS_FILESYSTEM,
			["*.json ; Vehicle JSON"], definition.id + ".json", _export_json_file)


func _export_json_file(path: String) -> void:
	var definition := _current()
	var warnings: Array[String] = []
	var error := VehicleSerializer.export_package(definition, path, _export_model.button_pressed, warnings)
	if error != OK:
		_fail("Can't write %s: %s" % [path, error_string(error)])
		return
	_report.text = "[b]Exported %s -> %s[/b]\n%s" % [definition.id, path, _warnings_bbcode(warnings)]


func _rebuild_previews() -> void:
	VehicleLoader.clear_model_cache()
	var root := EditorInterface.get_edited_scene_root()
	var count := 0
	if root:
		for node in root.find_children("*", "RigidBody3D", true, false) + [root]:
			if node is ShapeCastVehicle and node.definition:
				node.rebuild()
				count += 1
	_report.text = "Rebuilt %d vehicle preview(s)." % count


# --- Import / export helpers --------------------------------------------------

## Copies a model referenced by an imported JSON into [param dir]; returns its new path.
func _import_asset(value: String, source_dir: String, dir: String, copied: Array[String],
		warnings: Array[String]) -> String:
	if value == "":
		return value
	var source := VehicleSerializer.resolve_path(value, source_dir)
	if source.begins_with("res://"):
		return source
	var target := dir.path_join(source.get_file())
	var error := DirAccess.copy_absolute(source, ProjectSettings.globalize_path(target))
	if error != OK:
		warnings.append("Can't copy %s: %s" % [source, error_string(error)])
		return value
	copied.append(target)
	if source.get_extension().to_lower() == "gltf":
		# A .gltf keeps buffers and textures in separate files next to it.
		var gltf := VehicleSerializer.read_json_file(source, warnings)
		for key in ["buffers", "images"]:
			for item: Variant in gltf.get(key, []):
				var uri: String = item.get("uri", "") if item is Dictionary else ""
				if uri != "" and not uri.begins_with("data:"):
					var dependency := source.get_base_dir().path_join(uri.uri_decode())
					var dependency_target := dir.path_join(uri.uri_decode())
					DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dependency_target.get_base_dir()))
					DirAccess.copy_absolute(dependency, ProjectSettings.globalize_path(dependency_target))
	return target


## Lets the editor scan and import new files. True when all can be loaded.
func _wait_for_import(paths: Array[String]) -> bool:
	var file_system := EditorInterface.get_resource_filesystem()
	file_system.scan()
	var deadline := Time.get_ticks_msec() + IMPORT_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.25).timeout
		if file_system.is_scanning():
			continue
		var all_imported := true
		for path in paths:
			all_imported = all_imported and ResourceLoader.exists(path)
		if all_imported:
			return true
	return false


# --- Template -----------------------------------------------------------------

## A 4-wheel, rear-wheel-drive car to start from (no model yet).
static func _template(id: String) -> VehicleDefinition:
	var definition := VehicleDefinition.new()
	definition.id = id
	definition.display_name = id.capitalize()

	var chassis := VehicleColliderConfig.new()
	chassis.name = "ChassisCollision"
	chassis.position = Vector3(0.0, 0.15, 0.0)
	chassis.size = Vector3(1.7, 0.5, 4.0)
	definition.colliders.append(chassis)
	var cabin := VehicleColliderConfig.new()
	cabin.name = "CabinCollision"
	cabin.position = Vector3(0.0, 0.65, 0.2)
	cabin.size = Vector3(1.5, 0.5, 2.0)
	definition.colliders.append(cabin)

	var front := VehicleWheelConfig.new()
	front.name = "WheelFL"
	front.position = Vector3(-0.98, 0.0, -1.35)
	front.mirror = true
	front.steering = true
	definition.wheels.append(front)
	var rear := VehicleWheelConfig.new()
	rear.name = "WheelRL"
	rear.position = Vector3(-0.98, 0.0, 1.3)
	rear.mirror = true
	rear.drive = true
	rear.handbrake = true
	definition.wheels.append(rear)

	var points := [
		[VehicleMountPoint.Kind.TOW_HOOK_FRONT, Vector3(0.0, 0.02, -2.07)],
		[VehicleMountPoint.Kind.TOW_HITCH_REAR, Vector3(0.0, 0.02, 2.07)],
		[VehicleMountPoint.Kind.DRIVER_EXIT, Vector3(-1.5, 0.0, -0.2)],
	]
	for entry: Array in points:
		var point := VehicleMountPoint.new()
		point.kind = entry[0]
		point.position = entry[1]
		if point.kind != VehicleMountPoint.Kind.DRIVER_EXIT:
			point.marker_size = Vector3(0.12, 0.1, 0.14)
		definition.mount_points.append(point)

	var trunk := VehicleCargoSpace.new()
	trunk.name = "Trunk"
	trunk.position = Vector3(0.0, 0.3, 1.45)
	trunk.size = Vector3(1.2, 0.45, 0.8)
	trunk.max_mass = 250.0
	trunk.accepted_tags = PackedStringArray(["luggage", "boxes"])
	definition.cargo_spaces.append(trunk)
	return definition


# --- UI helpers ---------------------------------------------------------------

func _require_saved() -> VehicleDefinition:
	var definition := _current()
	if definition == null:
		_fail("Select a definition first.")
		return null
	if _saved_path(definition) == "":
		_fail("Save the definition to its own .tres file first (it is embedded in another resource).")
		return null
	return definition


func _unique_dir(dir: String) -> String:
	var candidate := dir
	var index := 2
	while DirAccess.dir_exists_absolute(candidate):
		candidate = "%s_%d" % [dir, index]
		index += 1
	return candidate


func _ask_file(mode: EditorFileDialog.FileMode, access: EditorFileDialog.Access,
		filters: PackedStringArray, current_path: String, action: Callable) -> void:
	_dialog_action = action
	_file_dialog.file_mode = mode
	_file_dialog.access = access
	_file_dialog.filters = filters
	if current_path.contains("/"):
		_file_dialog.current_path = current_path
	elif current_path != "":
		_file_dialog.current_file = current_path
	_file_dialog.popup_file_dialog()


func _add_button(parent: Control, text: String, tooltip: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(action)
	parent.add_child(button)


func _fail(text: String) -> void:
	_report.text = "[color=#ff6b6b]%s[/color]" % text


func _warnings_bbcode(warnings: Array[String]) -> String:
	if warnings.is_empty():
		return "[color=#7bd88f]No warnings.[/color]"
	var lines := PackedStringArray()
	for warning in warnings:
		lines.append("[color=#ffc14d]WARN[/color]  " + warning)
	return "\n".join(lines)
