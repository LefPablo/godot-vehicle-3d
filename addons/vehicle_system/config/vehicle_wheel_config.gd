@tool
class_name VehicleWheelConfig
extends Resource
## One wheel of a vehicle, or a left/right pair when [member mirror] is on.
##
## [member position] is the suspension mount in vehicle space (+X right, +Y up,
## -Z forward): the wheel centre sits there when the suspension is fully
## compressed and [member VehicleSuspensionConfig.travel] below it when fully
## extended.

## Node name of the wheel. With [member mirror] this is the wheel at
## [member position]; the mirrored one gets [member mirror_name].
@export var name: String = "Wheel"
## Suspension mount point in vehicle space.
@export var position: Vector3 = Vector3.ZERO
## Also create an identical wheel at (-x, y, z).
@export var mirror: bool = false
## Name of the mirrored wheel. Empty = swap the last upper-case L/R in [member name]
## ("WheelFL" -> "WheelFR"), or append "R".
@export var mirror_name: String = ""

@export_group("Size")
@export_range(0.05, 2.0, 0.01, "suffix:m") var radius: float = 0.36
@export_range(0.05, 1.5, 0.01, "suffix:m") var width: float = 0.26
## Sides of the convex hull used for the ground sweep.
@export_range(8, 48, 1) var shape_segments: int = 24

@export_group("Function")
## Turns with the steering input.
@export var steering: bool = false
## Multiplier of the steering angle. 1 = normal, negative = counter-steering
## (rear-wheel steering), 0.5 = second steered axle of a truck, ...
@export_range(-2.0, 2.0, 0.01) var steer_ratio: float = 1.0
## Receives engine force.
@export var drive: bool = false
## Locked by the handbrake.
@export var handbrake: bool = false

@export_group("Suspension & Tyre")
## Share one resource between several wheels to tune them together.
@export var suspension: VehicleSuspensionConfig = VehicleSuspensionConfig.new()
@export var tire: VehicleTireConfig = VehicleTireConfig.new()
## What the tyre drives on (the sweep's collision mask).
@export_flags_3d_physics var collision_mask: int = 5

@export_group("Solid Wheel")
## Adds a wheel-shaped collider to the body so other objects can't pass through the tyre.
@export var solid: bool = true
@export_range(0.5, 1.0, 0.01) var collider_radius_scale: float = 0.9
@export_range(0.0, 0.3, 0.005, "suffix:m") var collider_ground_clearance: float = 0.08

@export_group("Visual")
## Wheel model to use instead of the generated tyre. Model it centred on the
## axle, with the axle along X and its outer face towards +X.
@export var visual_scene: PackedScene
## Instead of [member visual_scene]: path of a node inside the vehicle model
## (e.g. "Wheels/FrontLeft") that is the wheel. It is taken out of the body and
## spun/steered/moved by the suspension. Its origin must be the wheel centre
## (use [member visual_offset] otherwise).
@export var model_node: NodePath
## Model node for the mirrored wheel (only with [member mirror]).
@export var mirror_model_node: NodePath
## Offset of the visual from the wheel centre (wheel space).
@export var visual_offset: Vector3 = Vector3.ZERO
@export var visual_rotation_degrees: Vector3 = Vector3.ZERO
## Centre the visual on the wheel using the bounds of its meshes (handles
## models whose wheel pivot isn't at the hub).
@export var auto_center_visual: bool = true
## Rotate [member visual_scene] 180 deg on the left side (x < 0) so the outer face points out.
@export var flip_visual_on_left: bool = true
## Place the visual every rendered frame from the interpolated body transform.
@export var sync_visual_every_frame: bool = true
## How far the visual may rise above the fully compressed position.
@export_range(0.0, 0.5, 0.005, "suffix:m") var max_visual_overlift: float = 0.1


## The concrete wheels this entry produces:
## [{"name", "position", "model_node", "mirrored"}].
func expand() -> Array[Dictionary]:
	var result: Array[Dictionary] = [{
		"name": name, "position": position, "model_node": model_node, "mirrored": false,
	}]
	if mirror:
		result.append({
			"name": get_mirror_name(),
			"position": Vector3(-position.x, position.y, position.z),
			"model_node": mirror_model_node,
			"mirrored": true,
		})
	return result


func get_mirror_name() -> String:
	if mirror_name != "":
		return mirror_name
	for i in range(name.length() - 1, -1, -1):
		var c := name[i]
		if c == "L":
			return name.substr(0, i) + "R" + name.substr(i + 1)
		if c == "R":
			return name.substr(0, i) + "L" + name.substr(i + 1)
	return name + "R"
