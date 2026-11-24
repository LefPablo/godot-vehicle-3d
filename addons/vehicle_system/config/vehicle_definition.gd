@tool
class_name VehicleDefinition
extends Resource
## Complete description of a vehicle: model, body physics, collision, engine,
## brakes, steering, wheels & suspension, mount points (tow hooks, trailer
## coupler, driver door...) and optional cargo bed.
##
## Saved as .tres inside the project, or as .json for external / modded
## vehicles (see [VehicleSerializer]). Assign it to a [ShapeCastVehicle]
## (the "definition" property) or spawn it with [VehicleLoader].
##
## Vehicle space: +X right, +Y up, -Z forward; the origin is the body origin.

const FORMAT_NAME := "shapecast_vehicle"
const FORMAT_VERSION := 1

enum AutoCollision {
	## Only the colliders listed in [member colliders].
	NONE,
	## Add one convex hull around the model (wheel nodes excluded).
	MODEL_CONVEX_HULL,
	## Add one box around the model (wheel nodes excluded).
	MODEL_BOUNDING_BOX,
}

@export_group("Identity")
## Unique id, used for file names and lookups (e.g. "pickup_truck").
@export var id: String = "vehicle"
@export var display_name: String = "Vehicle"
## Free-form category ("car", "truck", "trailer", "bus"...), for menus and filters.
@export var category: String = "car"
@export_multiline var description: String = ""
@export var author: String = ""
## False for trailers and props: they are not offered to the player to drive.
@export var player_controllable: bool = true

@export_group("Model")
## Visual model (a .glb/.gltf/.blend import or a .tscn).
@export var model: PackedScene
@export var model_offset: Vector3 = Vector3.ZERO
## Imported models often face +Z; use (0, 180, 0) to turn them to -Z (forward).
@export var model_rotation_degrees: Vector3 = Vector3.ZERO
@export var model_scale: Vector3 = Vector3.ONE

@export_group("Body")
@export_range(1.0, 200000.0, 1.0, "suffix:kg") var mass: float = 1200.0
## Centre of mass in vehicle space. Lower = more stable.
@export var center_of_mass: Vector3 = Vector3(0.0, -0.15, 0.0)
@export_range(0.0, 2.0, 0.01) var body_friction: float = 0.4
@export_flags_3d_physics var collision_layer: int = 2
@export_flags_3d_physics var collision_mask: int = 7
## Collision shapes edited in the editor: a scene with CollisionShape3D nodes
## (Vehicles dock > Edit collision creates and opens one), or a separate
## collision model (.glb...) whose meshes each become a convex hull.
@export var collision_scene: PackedScene
## The collision scene was made for the model (e.g. exported with it): apply the
## model offset / rotation / scale to it. Off = it is already in vehicle space.
@export var collision_scene_in_model_space: bool = false
## Simple shapes defined by numbers (also what JSON packages use).
@export var colliders: Array[VehicleColliderConfig] = []
@export var auto_collision: AutoCollision = AutoCollision.NONE

@export_group("Stability")
## Anti-roll bar: resists left/right compression difference on each axle.
@export_range(0.0, 500000.0, 100.0, "suffix:N/m") var anti_roll_stiffness: float = 9000.0
## Aerodynamic drag (force = drag * speed^2).
@export_range(0.0, 10.0, 0.01) var air_drag: float = 0.4

@export_group("Drivetrain")
@export var engine: VehicleEngineConfig = VehicleEngineConfig.new()
@export var brakes: VehicleBrakeConfig = VehicleBrakeConfig.new()
@export var steering: VehicleSteeringConfig = VehicleSteeringConfig.new()

@export_group("Wheels")
@export var wheels: Array[VehicleWheelConfig] = []

@export_group("Mount Points")
@export var mount_points: Array[VehicleMountPoint] = []

@export_group("Cargo")
## Spaces that can carry cargo (bed, deck, trunk...): size, payload, accepted kinds.
@export var cargo_spaces: Array[VehicleCargoSpace] = []

@export_group("Camera")
@export_range(1.0, 60.0, 0.1, "suffix:m") var camera_distance: float = 7.5
@export_range(-2.0, 10.0, 0.05, "suffix:m") var camera_look_height: float = 0.6


func get_model_transform() -> Transform3D:
	var basis := Basis.from_euler(model_rotation_degrees * (PI / 180.0)).scaled(model_scale)
	return Transform3D(basis, model_offset)


## Every concrete wheel, mirrors included, in build order:
## [{"name", "position", "model_node", "mirrored", "config"}].
func expanded_wheels() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for config in wheels:
		if config == null:
			continue
		for entry in config.expand():
			entry["config"] = config
			result.append(entry)
	return result


func get_mount_point(kind: VehicleMountPoint.Kind, custom_name: String = "") -> VehicleMountPoint:
	for point in mount_points:
		if point and point.kind == kind and (kind != VehicleMountPoint.Kind.CUSTOM or point.name == custom_name):
			return point
	return null


func get_cargo_space(space_name: String = "Cargo") -> VehicleCargoSpace:
	for space in cargo_spaces:
		if space and space.name == space_name:
			return space
	return null


## First cargo space that takes an item of this size, mass and kind (or null).
func find_cargo_space(item_size: Vector3, item_mass: float = 0.0, tag: String = "",
		allow_tipping: bool = false) -> VehicleCargoSpace:
	for space in cargo_spaces:
		if space and space.can_carry(item_size, item_mass, tag, 0.0, allow_tipping):
			return space
	return null


## Sum of the cargo spaces' max_mass (0 if any space is unlimited or there are none).
func get_payload_capacity() -> float:
	var total := 0.0
	for space in cargo_spaces:
		if space == null:
			continue
		if space.max_mass <= 0.0:
			return 0.0
		total += space.max_mass
	return total


## Weighted centre of the cargo spaces' max payload (where a full load sits).
func get_payload_center() -> Vector3:
	var total := 0.0
	var moment := Vector3.ZERO
	for space in cargo_spaces:
		if space and space.max_mass > 0.0:
			total += space.max_mass
			moment += (space.position + space.get_transform().basis.y * space.size.y * 0.5) * space.max_mass
	return moment / total if total > 0.0 else center_of_mass


## Estimated static suspension compression of every expanded wheel (metres,
## clamped to the travel), from a rigid-body-on-springs equilibrium.
## [param payload_mass] at [param payload_position] adds a load (e.g. full cargo).
func estimate_static_sag(payload_mass: float = 0.0,
		payload_position: Vector3 = Vector3.ZERO) -> PackedFloat32Array:
	var entries := expanded_wheels()
	var sag := PackedFloat32Array()
	sag.resize(entries.size())
	if entries.is_empty():
		return sag
	# Unknowns: heave h, pitch p, roll r. Compression d_i = h + p*z_i + r*x_i
	# (coordinates relative to the centre of mass). Equilibrium:
	# sum k d = W, sum k d z = 0, sum k d x = 0.
	var total_mass := mass + maxf(payload_mass, 0.0)
	var weight := total_mass * 9.81
	var com := (center_of_mass * mass + payload_position * maxf(payload_mass, 0.0)) / total_mass
	var s := 0.0; var sz := 0.0; var sx := 0.0
	var szz := 0.0; var sxx := 0.0; var sxz := 0.0
	for e in entries:
		var k: float = e.config.suspension.spring_stiffness if e.config.suspension else 0.0
		var p: Vector3 = e.position - com
		s += k; sz += k * p.z; sx += k * p.x
		szz += k * p.z * p.z; sxx += k * p.x * p.x; sxz += k * p.x * p.z
	var h := 0.0; var pitch := 0.0; var roll := 0.0
	var m := Basis(Vector3(s, sz, sx), Vector3(sz, szz, sxz), Vector3(sx, sxz, sxx))
	if absf(m.determinant()) > 1e-6 * maxf(s * szz * sxx, 1e-9):
		var solution := m.inverse() * Vector3(weight, 0.0, 0.0)
		h = solution.x; pitch = solution.y; roll = solution.z
	elif s * sxx - sx * sx > 1e-9:
		# All wheels on one axle (e.g. a trailer): heave + roll only.
		var det := s * sxx - sx * sx
		h = weight * sxx / det
		roll = -weight * sx / det
	elif s > 0.0:
		h = weight / s
	for i in entries.size():
		var e: Dictionary = entries[i]
		var p: Vector3 = e.position - com
		var travel: float = e.config.suspension.travel if e.config.suspension else 0.0
		sag[i] = clampf(h + pitch * p.z + roll * p.x, 0.0, travel)
	return sag


## Height of the body origin above flat ground when the vehicle rests on it.
func estimate_ride_height() -> float:
	var entries := expanded_wheels()
	if entries.is_empty():
		return 0.5
	var sag := estimate_static_sag()
	var total := 0.0
	for i in entries.size():
		var e: Dictionary = entries[i]
		var travel: float = e.config.suspension.travel if e.config.suspension else 0.0
		total += e.config.radius + (travel - sag[i]) - e.position.y
	return total / entries.size()
