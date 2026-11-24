extends Node
## Decides what the player controls: the on-foot character or one of the vehicles.
##
## With a [member character] assigned:
##   - On foot, press "interact" (E) near a vehicle's driver door to get in.
##   - Driving, press E to get out: the character appears next to the driver's
##     door (or the other side / behind, if that is blocked). Not above
##     [member max_exit_speed_kmh].
##   Every vehicle stays where you leave it, parked with its handbrake on.
## Without a character, "switch_vehicle" (X) cycles through the vehicles instead.
##
## Vehicles may have a "DriverExit" Marker3D next to the driver's door.

const ACTION_SWITCH := &"switch_vehicle"
const ACTION_INTERACT := &"interact"
const DRIVER_EXIT := ^"DriverExit"

signal active_vehicle_changed(vehicle: ShapeCastVehicle)

## Vehicles in switching order.
@export var vehicles: Array[ShapeCastVehicle] = []
## Follow camera to retarget (needs a follow(target, distance, look_height, chase) method).
@export var camera: Camera3D
## HUD to retarget (needs a "vehicle" property).
@export var hud: Control
## Vehicle driven when the scene starts (only used without a character, or
## when [member start_on_foot] is off).
@export var active_index: int = 0

@export_group("Character")
## The on-foot player. Leave empty to switch vehicles with X instead.
@export var character: CharacterBody3D
@export var start_on_foot: bool = true
## How close the character must be to a driver door (or the vehicle centre) to get in.
@export_range(0.5, 10.0, 0.1, "suffix:m") var enter_range: float = 3.0
## Getting out is refused above this speed.
@export_range(0.0, 100.0, 0.5, "suffix:km/h") var max_exit_speed_kmh: float = 8.0
@export_range(1.0, 20.0, 0.1, "suffix:m") var on_foot_camera_distance: float = 4.5
@export_range(0.0, 5.0, 0.05, "suffix:m") var on_foot_look_height: float = 1.4
## What counts as an obstacle when looking for a free spot to get out.
@export_flags_3d_physics var exit_blocking_mask: int = 7

## The vehicle being driven, or null while on foot.
var active_vehicle: ShapeCastVehicle
## Short message for the HUD (e.g. "Slow down to get out").
var message: String = ""
var _message_time: float = 0.0


func _ready() -> void:
	for i in range(vehicles.size() - 1, -1, -1):
		if vehicles[i] == null:
			vehicles.remove_at(i)
	for vehicle in vehicles:
		_park(vehicle)
	if character and start_on_foot:
		_go_on_foot()
	elif not vehicles.is_empty():
		activate(clampi(active_index, 0, vehicles.size() - 1))


func _process(delta: float) -> void:
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			message = ""


func _unhandled_input(event: InputEvent) -> void:
	if character:
		if event.is_action_pressed(ACTION_INTERACT):
			if active_vehicle:
				exit_vehicle()
			else:
				var vehicle := find_enterable_vehicle()
				if vehicle:
					enter_vehicle(vehicle)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(ACTION_SWITCH) and vehicles.size() > 1:
		activate((active_index + 1) % vehicles.size())
		get_viewport().set_input_as_handled()


## Drives vehicles[index] (with a character: puts the character in it).
func activate(index: int) -> void:
	if index < 0 or index >= vehicles.size():
		return
	enter_vehicle(vehicles[index])


## Adds a vehicle created at runtime (e.g. spawned from a definition). It starts parked.
func register_vehicle(vehicle: ShapeCastVehicle) -> void:
	if vehicle == null or vehicle in vehicles:
		return
	vehicles.append(vehicle)
	if vehicle != active_vehicle:
		_park(vehicle)
	vehicle.tree_exiting.connect(unregister_vehicle.bind(vehicle), CONNECT_ONE_SHOT)


## Removes a vehicle (called automatically when a registered vehicle is freed).
func unregister_vehicle(vehicle: ShapeCastVehicle) -> void:
	vehicles.erase(vehicle)
	if vehicle == active_vehicle and character:
		_go_on_foot()


func is_on_foot() -> bool:
	return active_vehicle == null


func enter_vehicle(vehicle: ShapeCastVehicle) -> void:
	if active_vehicle and active_vehicle != vehicle:
		_park(active_vehicle)
	active_index = vehicles.find(vehicle)
	active_vehicle = vehicle
	for other in vehicles:
		if other != vehicle:
			_park(other)
	vehicle.use_player_input = true
	if character:
		character.set_active(false)
	if camera and camera.has_method(&"follow"):
		camera.follow(vehicle, vehicle.camera_distance, vehicle.camera_look_height, true)
	if hud:
		hud.set(&"vehicle", vehicle)
	active_vehicle_changed.emit(vehicle)


## Gets out of the current vehicle. Returns false if that is not possible now.
func exit_vehicle() -> bool:
	if active_vehicle == null or character == null:
		return false
	if active_vehicle.get_speed_kmh() > max_exit_speed_kmh:
		_show_message("Slow down to get out")
		return false
	var spot: Variant = _find_exit_spot(active_vehicle)
	if spot == null:
		_show_message("No room to get out here")
		return false
	var vehicle := active_vehicle
	_park(vehicle)
	character.set_active(true)
	character.place_at(spot, vehicle.global_rotation.y)
	_go_on_foot()
	return true


## Nearest vehicle the character can get into, or null.
func find_enterable_vehicle() -> ShapeCastVehicle:
	if character == null or active_vehicle:
		return null
	var best: ShapeCastVehicle
	var best_distance := INF
	for vehicle in vehicles:
		var distance := _distance_to_door(vehicle)
		if distance <= enter_range and distance < best_distance:
			best = vehicle
			best_distance = distance
	return best


## Prompt for the HUD.
func get_status_text() -> String:
	if message != "":
		return message
	if character == null:
		return ""
	if active_vehicle:
		return ""
	var vehicle := find_enterable_vehicle()
	return "[E] get into the %s" % vehicle.name if vehicle else ""


func _go_on_foot() -> void:
	active_vehicle = null
	active_index = -1
	if camera and camera.has_method(&"follow"):
		camera.follow(character, on_foot_camera_distance, on_foot_look_height, false)
	if hud:
		hud.set(&"vehicle", null)
	active_vehicle_changed.emit(null)


func _park(vehicle: ShapeCastVehicle) -> void:
	vehicle.use_player_input = false
	vehicle.set_controls(0.0, 0.0, true)


## Distance from the character to the vehicle's driver door (or its centre).
func _distance_to_door(vehicle: ShapeCastVehicle) -> float:
	var feet := character.global_position
	var distance := _flat_distance(feet, vehicle.global_position) - 1.5
	var door := vehicle.get_node_or_null(DRIVER_EXIT) as Node3D
	if door:
		distance = minf(distance, _flat_distance(feet, door.global_position))
	return maxf(distance, 0.0)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## First free spot next to the vehicle where the character fits, or null.
func _find_exit_spot(vehicle: ShapeCastVehicle) -> Variant:
	var candidates: Array[Vector3] = []
	var door := vehicle.get_node_or_null(DRIVER_EXIT) as Node3D
	var door_local := vehicle.to_local(door.global_position) if door else Vector3(-1.6, 0.0, 0.0)
	candidates.append(vehicle.to_global(door_local))                                    # driver side
	candidates.append(vehicle.to_global(Vector3(-door_local.x, door_local.y, door_local.z)))  # other side
	candidates.append(vehicle.to_global(Vector3(0.0, door_local.y, _rear_offset(vehicle))))  # behind
	candidates.append(vehicle.to_global(Vector3(0.0, door_local.y, -_rear_offset(vehicle)))) # in front

	var space := character.get_world_3d().direct_space_state
	var capsule := PhysicsShapeQueryParameters3D.new()
	capsule.shape = character.get_capsule()
	capsule.collision_mask = exit_blocking_mask
	capsule.exclude = [character.get_rid()]
	for candidate in candidates:
		# Find the ground under the spot (ignore the vehicle itself).
		var ray := PhysicsRayQueryParameters3D.create(
				candidate + Vector3.UP * 1.0, candidate + Vector3.DOWN * 4.0, 1)
		var hit := space.intersect_ray(ray)
		var feet: Vector3 = hit.position if hit else candidate
		capsule.transform = Transform3D(Basis.IDENTITY,
				feet + character.get_capsule_offset() + Vector3.UP * 0.05)
		if space.intersect_shape(capsule, 1).is_empty():
			return feet
	return null


## Distance from the vehicle origin to just behind its rear (local +Z).
func _rear_offset(vehicle: ShapeCastVehicle) -> float:
	var hitch := vehicle.get_node_or_null(^"TowHitchRear") as Node3D
	return (hitch.position.z if hitch else 2.5) + 1.0


func _show_message(text: String) -> void:
	message = text
	_message_time = 2.0
