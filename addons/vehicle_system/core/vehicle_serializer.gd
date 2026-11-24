@tool
class_name VehicleSerializer
extends RefCounted
## Converts [VehicleDefinition]s to and from JSON-friendly dictionaries.
##
## The conversion is driven by the exported properties of the config classes,
## so new fields are picked up automatically. JSON files:
##  - may leave out any key (the default value is used),
##  - store vectors as [x, y, z], colours as [r, g, b, a], enums by name
##    ("shape_type": "box"), angles in degrees where the property says so,
##  - reference models / wheel scenes by path: res://, user://, absolute, or
##    relative to the JSON file ("model": "pickup.glb").

const FORMAT_KEY := "format"
const VERSION_KEY := "version"

## Config classes that are written as nested objects.
static var CLASSES := {
	&"VehicleDefinition": VehicleDefinition,
	&"VehicleWheelConfig": VehicleWheelConfig,
	&"VehicleSuspensionConfig": VehicleSuspensionConfig,
	&"VehicleTireConfig": VehicleTireConfig,
	&"VehicleEngineConfig": VehicleEngineConfig,
	&"VehicleBrakeConfig": VehicleBrakeConfig,
	&"VehicleSteeringConfig": VehicleSteeringConfig,
	&"VehicleColliderConfig": VehicleColliderConfig,
	&"VehicleMountPoint": VehicleMountPoint,
	&"VehicleCargoSpace": VehicleCargoSpace,
	&"VehicleCargoLoad": VehicleCargoLoad,
}

## Metadata key holding the file a runtime-loaded model came from.
const SOURCE_PATH_META := &"vehicle_source_path"


# --- Public API ---------------------------------------------------------------

## Dictionary for [param definition]. Paths inside [param base_dir] are written
## relative to it.
static func to_dict(definition: VehicleDefinition, base_dir: String = "") -> Dictionary:
	var data := {
		FORMAT_KEY: VehicleDefinition.FORMAT_NAME,
		VERSION_KEY: VehicleDefinition.FORMAT_VERSION,
	}
	data.merge(_object_to_dict(definition, base_dir))
	return data


## New definition from [param data]. Problems (unknown keys, missing files...)
## are appended to [param warnings]. Relative paths are resolved against [param base_dir].
static func from_dict(data: Dictionary, base_dir: String = "",
		warnings: Array[String] = []) -> VehicleDefinition:
	if data.get(FORMAT_KEY, VehicleDefinition.FORMAT_NAME) != VehicleDefinition.FORMAT_NAME:
		warnings.append("Unexpected format '%s'." % data.get(FORMAT_KEY))
	var version := int(data.get(VERSION_KEY, VehicleDefinition.FORMAT_VERSION))
	if version > VehicleDefinition.FORMAT_VERSION:
		warnings.append("File version %d is newer than supported (%d)." % [
				version, VehicleDefinition.FORMAT_VERSION])
	var definition := VehicleDefinition.new()
	var fields := data.duplicate()
	fields.erase(FORMAT_KEY)
	fields.erase(VERSION_KEY)
	_fill_object(definition, fields, base_dir, warnings, "")
	return definition


static func to_json(definition: VehicleDefinition, base_dir: String = "") -> String:
	return JSON.stringify(to_dict(definition, base_dir), "\t", false)


static func save_json(definition: VehicleDefinition, path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(to_json(definition, path.get_base_dir()))
	file.close()
	return OK


## Writes a self-contained vehicle package: [param json_path] plus, with
## [param include_models], the body and wheel models next to it as .glb
## (copied if they are .glb already, converted with GLTFDocument otherwise).
## The folder can be shared and loaded at runtime with [VehicleLoader].
static func export_package(definition: VehicleDefinition, json_path: String,
		include_models: bool = true, warnings: Array[String] = []) -> Error:
	var dir := json_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var data := to_dict(definition, dir)
	# A project collision scene can't travel with the JSON: write its shapes as colliders.
	if definition.collision_scene:
		var colliders: Array = data.get("colliders", [])
		for entry in VehicleBuilder.collision_scene_shapes(definition):
			var config := VehicleColliderConfig.new()
			config.name = entry.name
			if config.set_from_shape(entry.shape, entry.transform):
				colliders.append(_object_to_dict(config, dir))
			else:
				warnings.append("Collision shape '%s' (%s) can't be stored in JSON; skipped." % [
						entry.name, entry.shape.get_class()])
		data["colliders"] = colliders
		data["collision_scene"] = null
		data["collision_scene_in_model_space"] = false
	if include_models:
		var exported := {}
		if definition.model:
			data["model"] = _export_model(definition.model, dir, definition.id, exported, warnings)
		var wheels: Array = data.get("wheels", [])
		for i in mini(wheels.size(), definition.wheels.size()):
			var scene := definition.wheels[i].visual_scene
			if scene:
				wheels[i]["visual_scene"] = _export_model(scene, dir,
						"%s_wheel_%d" % [definition.id, i], exported, warnings)
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t", false))
	file.close()
	return OK


## Writes [param scene] into [param dir] as .glb; returns the file name for the JSON.
static func _export_model(scene: PackedScene, dir: String, file_base: String,
		exported: Dictionary, warnings: Array[String]) -> String:
	if exported.has(scene):
		return exported[scene]
	var source := resource_source_path(scene)
	var file_name := file_base + ".glb"
	var error := OK
	if source.get_extension().to_lower() == "glb":
		file_name = source.get_file()
		error = DirAccess.copy_absolute(ProjectSettings.globalize_path(source),
				ProjectSettings.globalize_path(dir.path_join(file_name)))
	else:
		var instance := scene.instantiate()
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		error = document.append_from_scene(instance, state)
		if error == OK:
			error = document.write_to_filesystem(state, dir.path_join(file_name))
		instance.free()
	if error != OK:
		warnings.append("Can't export %s as glTF (%s); the JSON references it by path instead." % [
				source, error_string(error)])
		file_name = source
	exported[scene] = file_name
	return file_name


## Parses a JSON file into a dictionary ({} and a warning on failure).
static func read_json_file(path: String, warnings: Array[String] = []) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		warnings.append("Can't read '%s' (%s)." % [path, error_string(FileAccess.get_open_error())])
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		warnings.append("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if not json.data is Dictionary:
		warnings.append("'%s' does not contain a JSON object." % path)
		return {}
	return json.data


static func load_json(path: String, warnings: Array[String] = []) -> VehicleDefinition:
	var data := read_json_file(path, warnings)
	if data.is_empty():
		return null
	return from_dict(data, path.get_base_dir(), warnings)


## Hash of every value of the definition (changes when anything is edited).
static func fingerprint(definition: VehicleDefinition) -> int:
	return _object_to_dict(definition, "").hash()


## Path a resource was loaded from ("" for built-in resources).
static func resource_source_path(resource: Resource) -> String:
	if resource == null:
		return ""
	if resource.resource_path != "" and not resource.resource_path.contains("::"):
		return resource.resource_path
	return str(resource.get_meta(SOURCE_PATH_META, ""))


static func resolve_path(path: String, base_dir: String) -> String:
	if path == "" or path.is_absolute_path() or base_dir == "":
		return path
	return base_dir.path_join(path).simplify_path()


# --- Writing ------------------------------------------------------------------

static func _object_to_dict(object: Object, base_dir: String) -> Dictionary:
	var data := {}
	for property in object.get_property_list():
		if _is_config_property(property):
			data[property.name] = _to_json(object.get(property.name), property, base_dir)
	return data


static func _to_json(value: Variant, property: Dictionary, base_dir: String) -> Variant:
	match typeof(value):
		TYPE_NIL:
			return null
		TYPE_BOOL, TYPE_STRING:
			return value
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(value)
		TYPE_INT:
			if property.get("hint", 0) == PROPERTY_HINT_ENUM:
				return _enum_name(property.hint_string, value)
			return value
		TYPE_FLOAT:
			return _num(value)
		TYPE_VECTOR2:
			return [_num(value.x), _num(value.y)]
		TYPE_VECTOR3:
			return [_num(value.x), _num(value.y), _num(value.z)]
		TYPE_COLOR:
			return [_num(value.r), _num(value.g), _num(value.b), _num(value.a)]
		TYPE_PACKED_VECTOR3_ARRAY:
			var points := []
			for p: Vector3 in value:
				points.append([_num(p.x), _num(p.y), _num(p.z)])
			return points
		TYPE_PACKED_STRING_ARRAY:
			return Array(value)
		TYPE_ARRAY:
			var items := []
			for item in value:
				items.append(_to_json(item, {}, base_dir))
			return items
		TYPE_OBJECT:
			if value is Curve:
				return _curve_to_json(value)
			if _config_class_of(value) != &"":
				return _object_to_dict(value, base_dir)
			if value is Resource:
				var path := resource_source_path(value)
				if path == "":
					push_warning("Vehicle JSON: a built-in %s can't be referenced by path; save it to a file." % value.get_class())
					return null
				if base_dir != "" and path.begins_with(base_dir.trim_suffix("/") + "/"):
					return path.substr(base_dir.trim_suffix("/").length() + 1)
				return path
	return null


static func _num(value: float) -> float:
	return snappedf(value, 0.000001)


static func _curve_to_json(curve: Curve) -> Dictionary:
	var points := []
	for i in curve.point_count:
		var p := curve.get_point_position(i)
		points.append([_num(p.x), _num(p.y), _num(curve.get_point_left_tangent(i)),
				_num(curve.get_point_right_tangent(i))])
	return {"min_value": _num(curve.min_value), "max_value": _num(curve.max_value), "points": points}


static func _enum_name(hint_string: String, value: int) -> Variant:
	var entries := _enum_entries(hint_string)
	for label: String in entries:
		if entries[label] == value:
			return label
	return value


## {"snake_case_name": value} from an enum hint string ("Box:0,Convex Hull:4").
static func _enum_entries(hint_string: String) -> Dictionary:
	var entries := {}
	var index := 0
	for part in hint_string.split(","):
		var label := part
		var value := index
		if part.contains(":"):
			label = part.get_slice(":", 0)
			value = part.get_slice(":", 1).to_int()
		entries[_normalize_name(label)] = value
		index = value + 1
	return entries


static func _normalize_name(text: String) -> String:
	return text.strip_edges().to_lower().replace(" ", "_").replace("-", "_")


# --- Reading ------------------------------------------------------------------

static func _fill_object(object: Object, data: Dictionary, base_dir: String,
		warnings: Array[String], context: String) -> void:
	var properties := {}
	for property in object.get_property_list():
		if _is_config_property(property):
			properties[property.name] = property
	for key: String in data:
		if not properties.has(key):
			warnings.append("Unknown key '%s%s' (ignored)." % [context, key])
			continue
		var property: Dictionary = properties[key]
		var json_value: Variant = data[key]
		var where := context + key
		if property.type == TYPE_ARRAY:
			var target: Array = object.get(key)
			target.clear()
			if not json_value is Array:
				warnings.append("'%s' should be a list." % where)
				continue
			var element_class := _array_element_class(property)
			for i in json_value.size():
				var item: Variant = _object_from_json(json_value[i], element_class, null,
						base_dir, warnings, "%s[%d]." % [where, i])
				if item != null:
					target.append(item)
			continue
		var value: Variant = _from_json(json_value, property, object.get(key), base_dir, warnings, where)
		object.set(key, value)


static func _from_json(value: Variant, property: Dictionary, current: Variant,
		base_dir: String, warnings: Array[String], where: String) -> Variant:
	match property.type:
		TYPE_BOOL:
			return bool(value)
		TYPE_INT:
			if value is String and property.hint == PROPERTY_HINT_ENUM:
				var entries := _enum_entries(property.hint_string)
				var normalized := _normalize_name(value)
				if entries.has(normalized):
					return entries[normalized]
				warnings.append("'%s': unknown value '%s' (expected one of %s)." % [
						where, value, ", ".join(entries.keys())])
				return current
			return int(value)
		TYPE_FLOAT:
			return float(value)
		TYPE_STRING:
			return str(value)
		TYPE_STRING_NAME:
			return StringName(str(value))
		TYPE_NODE_PATH:
			return NodePath(str(value))
		TYPE_VECTOR2:
			var a := _numbers(value, 2, where, warnings)
			return Vector2(a[0], a[1]) if a.size() == 2 else current
		TYPE_VECTOR3:
			var a := _numbers(value, 3, where, warnings)
			return Vector3(a[0], a[1], a[2]) if a.size() == 3 else current
		TYPE_COLOR:
			if value is String:
				return Color.from_string(value, current)
			var a := _numbers(value, -1, where, warnings)
			if a.size() < 3:
				return current
			return Color(a[0], a[1], a[2], a[3] if a.size() > 3 else 1.0)
		TYPE_PACKED_VECTOR3_ARRAY:
			var points := PackedVector3Array()
			if value is Array:
				for p in value:
					var a := _numbers(p, 3, where, warnings)
					if a.size() == 3:
						points.append(Vector3(a[0], a[1], a[2]))
			return points
		TYPE_PACKED_STRING_ARRAY:
			var strings := PackedStringArray()
			if value is Array:
				for s in value:
					strings.append(str(s))
			elif value is String:
				strings.append(value)
			return strings
		TYPE_OBJECT:
			var object_class: StringName = property.get("class_name", &"")
			if object_class == &"":
				object_class = StringName(property.hint_string)
			return _object_from_json(value, object_class, current, base_dir, warnings, where + ".")
	warnings.append("'%s': unsupported property type." % where)
	return current


static func _object_from_json(value: Variant, object_class: StringName, current: Variant,
		base_dir: String, warnings: Array[String], where: String) -> Variant:
	if value == null:
		return null
	if CLASSES.has(object_class):
		if not value is Dictionary:
			warnings.append("'%s' should be an object." % where.trim_suffix("."))
			return current
		var target: Object = current if current != null and _config_class_of(current) == object_class \
				else CLASSES[object_class].new()
		_fill_object(target, value, base_dir, warnings, where)
		return target
	if object_class == &"Curve":
		return _curve_from_json(value)
	if value is String:
		var path := resolve_path(value, base_dir)
		if object_class == &"PackedScene":
			var scene := VehicleLoader.load_model(path)
			if scene == null:
				warnings.append("'%s': can't load '%s'." % [where.trim_suffix("."), path])
			return scene
		if ResourceLoader.exists(path):
			return load(path)
		warnings.append("'%s': can't load '%s'." % [where.trim_suffix("."), path])
		return null
	warnings.append("'%s': unexpected value." % where.trim_suffix("."))
	return current


static func _curve_from_json(value: Variant) -> Curve:
	if not value is Dictionary:
		return null
	var curve := Curve.new()
	curve.min_value = float(value.get("min_value", 0.0))
	curve.max_value = float(value.get("max_value", 1.0))
	for p in value.get("points", []):
		if p is Array and p.size() >= 2:
			curve.add_point(Vector2(p[0], p[1]),
					float(p[2]) if p.size() > 2 else 0.0,
					float(p[3]) if p.size() > 3 else 0.0)
	return curve


static func _numbers(value: Variant, count: int, where: String, warnings: Array[String]) -> Array[float]:
	var result: Array[float] = []
	if value is Array and (count < 0 or value.size() == count):
		for v in value:
			result.append(float(v))
		return result
	warnings.append("'%s' should be a list of %s numbers." % [where, str(count) if count > 0 else "3 or 4"])
	return result


# --- Helpers ------------------------------------------------------------------

static func _is_config_property(property: Dictionary) -> bool:
	var usage: int = property.usage
	return usage & PROPERTY_USAGE_SCRIPT_VARIABLE and usage & PROPERTY_USAGE_STORAGE


static func _config_class_of(object: Variant) -> StringName:
	if not object is Resource:
		return &""
	var script: Script = object.get_script()
	if script == null:
		return &""
	var global_name := script.get_global_name()
	return global_name if CLASSES.has(global_name) else &""


## Element class of a typed array property ("24/17:VehicleWheelConfig" -> VehicleWheelConfig).
static func _array_element_class(property: Dictionary) -> StringName:
	var hint: String = property.hint_string
	if hint.contains(":"):
		hint = hint.get_slice(":", hint.get_slice_count(":") - 1)
	return StringName(hint)
