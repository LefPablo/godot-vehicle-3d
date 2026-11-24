extends Node
## Spawns vehicles from definition files while the game runs.
##
## Press "spawn_vehicle" (V, added automatically if missing) to drop the next
## vehicle of the catalog in front of the player. The catalog is every
## definition (.tres / vehicle .json) under [member search_dirs], so a new car
## is just a folder with its model and a definition: res://vehicles/<id>/ in
## the project, or user://vehicles/<id>/ for downloaded / modded vehicles.
##
## Spawned vehicles are registered with the [member switcher] (enter them with E)
## and the [member tow_manager] (tow ropes; trailers can be hitched).

const ACTION_SPAWN := &"spawn_vehicle"

signal vehicle_spawned(vehicle: ShapeCastVehicle)

@export var switcher: Node
@export var tow_manager: Node
## Folders scanned for definitions (subfolders included).
@export var search_dirs: PackedStringArray = ["res://vehicles", "user://vehicles"]
## How far in front of the player vehicles appear.
@export_range(2.0, 50.0, 0.5, "suffix:m") var spawn_distance: float = 9.0
## Physics layers treated as ground when placing a vehicle.
@export_flags_3d_physics var ground_mask: int = 1

## Definition paths found by [method refresh_catalog].
var catalog: PackedStringArray = []
var _next_index: int = 0


func _ready() -> void:
	if not InputMap.has_action(ACTION_SPAWN):
		InputMap.add_action(ACTION_SPAWN)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_V
		InputMap.action_add_event(ACTION_SPAWN, key)
	refresh_catalog()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_SPAWN):
		spawn_next()
		get_viewport().set_input_as_handled()


func refresh_catalog() -> void:
	catalog = VehicleLoader.find_definitions(search_dirs)


## Spawns the next catalog entry in front of the player.
func spawn_next() -> ShapeCastVehicle:
	if catalog.is_empty():
		_message("No vehicle definitions in %s" % ", ".join(search_dirs))
		return null
	var path := catalog[_next_index % catalog.size()]
	_next_index += 1
	return spawn_path(path)


## Loads [param path] and spawns it in front of the player.
func spawn_path(path: String) -> ShapeCastVehicle:
	var warnings: Array[String] = []
	var definition := VehicleLoader.load_definition(path, warnings)
	for warning in warnings:
		push_warning("%s: %s" % [path.get_file(), warning])
	if definition == null:
		_message("Can't load %s" % path.get_file())
		return null
	var spot := _spot_in_front()
	return spawn_definition(definition, spot.position, spot.yaw)


## Spawns [param definition] resting on the ground at [param ground_position].
func spawn_definition(definition: VehicleDefinition, ground_position: Vector3,
		yaw: float = 0.0) -> ShapeCastVehicle:
	var parent := get_parent()
	var vehicle := VehicleLoader.spawn(definition, parent, ground_position, yaw)
	if vehicle == null:
		return null
	register(vehicle)
	_message("Spawned %s" % vehicle.name)
	vehicle_spawned.emit(vehicle)
	return vehicle


## Makes an existing vehicle drivable / towable.
func register(vehicle: ShapeCastVehicle) -> void:
	var definition := vehicle.definition
	var is_trailer := vehicle.get_node_or_null(^"Coupler") != null
	var drivable := definition == null or definition.player_controllable
	if switcher and drivable and switcher.has_method(&"register_vehicle"):
		switcher.register_vehicle(vehicle)
	if tow_manager:
		if is_trailer and tow_manager.has_method(&"register_trailer"):
			tow_manager.register_trailer(vehicle)
		elif tow_manager.has_method(&"register_vehicle"):
			tow_manager.register_vehicle(vehicle)


## Ground point spawn_distance ahead of the player (or the camera) and its heading.
func _spot_in_front() -> Dictionary:
	var reference: Node3D = null
	if switcher:
		reference = switcher.get(&"active_vehicle")
		if reference == null:
			reference = switcher.get(&"character")
	if reference == null:
		reference = get_viewport().get_camera_3d()
	if reference == null:
		return {"position": Vector3.ZERO, "yaw": 0.0}
	var forward := -reference.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD
	var point := reference.global_position + forward * spawn_distance
	var space := reference.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 20.0,
			point + Vector3.DOWN * 50.0, ground_mask)
	var hit := space.intersect_ray(query)
	if hit:
		point = hit.position
	return {"position": point, "yaw": atan2(-forward.x, -forward.z)}


func _message(text: String) -> void:
	if switcher and switcher.has_method(&"_show_message"):
		switcher._show_message(text)
	print(text)
