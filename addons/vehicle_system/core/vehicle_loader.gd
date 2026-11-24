@tool
class_name VehicleLoader
extends RefCounted
## Loads vehicle definitions and models from anywhere, at runtime or in the editor.
##
##   var vehicle := VehicleLoader.spawn("user://vehicles/pickup/pickup.json",
##           get_tree().current_scene, Vector3(0, 0, 10))
##
## Definitions: .tres / .res (project resources) or .json (external / mods).
## Models: anything ResourceLoader can load (imported .glb/.gltf/.blend/.fbx,
## .tscn/.scn), plus .glb/.gltf files that were never imported (user://, mod
## folders, absolute paths), which are loaded with GLTFDocument at runtime.

## Folders scanned by [method find_definitions] by default.
const DEFAULT_DIRS: PackedStringArray = ["res://vehicles", "user://vehicles"]

## Runtime-loaded glTF models by path (imported resources are cached by Godot).
static var _model_cache := {}


## Loads a definition from a .tres/.res or .json file. [param fresh] re-reads
## the file and its dependencies from disk instead of using the resource cache.
static func load_definition(path: String, warnings: Array[String] = [],
		fresh: bool = false) -> VehicleDefinition:
	path = resolve_uid(path)
	if path.get_extension().to_lower() == "json":
		if fresh:
			clear_model_cache()
		return VehicleSerializer.load_json(path, warnings)
	if not path.begins_with("res://"):
		warnings.append("'%s': resource files from outside the project can contain scripts; " % path
				+ "use JSON for downloadable / modded vehicles.")
	if not ResourceLoader.exists(path):
		warnings.append("'%s' does not exist." % path)
		return null
	var mode := ResourceLoader.CACHE_MODE_REPLACE_DEEP if fresh else ResourceLoader.CACHE_MODE_REUSE
	var definition := ResourceLoader.load(path, "", mode) as VehicleDefinition
	if definition == null:
		warnings.append("'%s' is not a VehicleDefinition." % path)
	return definition


## Loads a model scene from [param path] (see the class description).
static func load_model(path: String) -> PackedScene:
	path = resolve_uid(path)
	if path == "":
		return null
	var extension := path.get_extension().to_lower()
	if ResourceLoader.exists(path):
		var resource := ResourceLoader.load(path)
		if resource is PackedScene:
			return resource
	if extension in ["glb", "gltf"]:
		if _model_cache.has(path):
			return _model_cache[path]
		var scene := _load_gltf(path)
		if scene:
			scene.set_meta(VehicleSerializer.SOURCE_PATH_META, path)
			_model_cache[path] = scene
		return scene
	return null


static func clear_model_cache() -> void:
	_model_cache.clear()


## "uid://..." -> the file path it stands for (other paths are returned as they are).
## The editor stores file properties as uids since Godot 4.4.
static func resolve_uid(path: String) -> String:
	if not path.begins_with("uid://"):
		return path
	var id := ResourceUID.text_to_id(path)
	if id == ResourceUID.INVALID_ID or not ResourceUID.has_id(id):
		return path
	return ResourceUID.get_id_path(id)


## Loads (if needed) and spawns a vehicle resting on the ground at
## [param ground_position], facing [param yaw] (0 = -Z). [param source] is a
## [VehicleDefinition] or a path. Returns null on failure (see [param warnings]).
static func spawn(source: Variant, parent: Node, ground_position: Vector3, yaw: float = 0.0,
		warnings: Array[String] = []) -> ShapeCastVehicle:
	var definition := source as VehicleDefinition
	if definition == null and source is String:
		definition = load_definition(source, warnings)
	if definition == null:
		return null
	var origin := ground_position + Vector3.UP * (definition.estimate_ride_height() + 0.05)
	return VehicleBuilder.spawn(definition, parent, Transform3D(Basis(Vector3.UP, yaw), origin))


## Paths of every vehicle definition (.tres/.res with a VehicleDefinition, or
## vehicle .json) in [param dirs] and their subfolders.
static func find_definitions(dirs: PackedStringArray = DEFAULT_DIRS) -> PackedStringArray:
	var result := PackedStringArray()
	for dir in dirs:
		_scan(dir, result)
	return result


# --- Internals ----------------------------------------------------------------

static func _scan(dir_path: String, result: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		if not sub.begins_with("."):
			_scan(dir_path.path_join(sub), result)
	for file in dir.get_files():
		# Exported projects list converted resources as "name.tres.remap".
		var file_name := file.trim_suffix(".remap")
		var path := dir_path.path_join(file_name)
		if path in result:
			continue
		match file_name.get_extension().to_lower():
			"json":
				if _is_vehicle_json(path):
					result.append(path)
			"tres":
				if _tres_is_definition(path, file != file_name):
					result.append(path)
			"res":
				if ResourceLoader.load(path) is VehicleDefinition:
					result.append(path)


static func _is_vehicle_json(path: String) -> bool:
	var data := VehicleSerializer.read_json_file(path)
	return data.get(VehicleSerializer.FORMAT_KEY) == VehicleDefinition.FORMAT_NAME


## Reads only the header, so the model isn't loaded just to list the file.
static func _tres_is_definition(path: String, remapped: bool) -> bool:
	if remapped:
		return ResourceLoader.load(path) is VehicleDefinition
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	return file.get_line().contains("script_class=\"VehicleDefinition\"")


static func _load_gltf(path: String) -> PackedScene:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(path, state)
	if error != OK:
		push_error("Can't load model '%s': %s" % [path, error_string(error)])
		return null
	var root := document.generate_scene(state)
	if root == null:
		return null
	VehicleSceneExtractor.own_recursive(root, root)
	var scene := PackedScene.new()
	error = scene.pack(root)
	root.free()
	return scene if error == OK else null
