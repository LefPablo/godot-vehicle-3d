@tool
class_name VehicleMountPoint
extends Resource
## A named point on the vehicle that other systems look up by node name
## (a Marker3D child is created for it).
##
## TOW_HOOK_FRONT  -> "TowHookFront"  rope attaches here when this vehicle is towed
## TOW_HITCH_REAR  -> "TowHitchRear"  rope / trailer hitch of a towing vehicle
## TRAILER_COUPLER -> "Coupler"       where a trailer attaches to a hitch
## DRIVER_EXIT     -> "DriverExit"    where the driver gets in / out
## CUSTOM          -> [member name]   anything else (lights, seats, exhausts...)

enum Kind { TOW_HOOK_FRONT, TOW_HITCH_REAR, TRAILER_COUPLER, DRIVER_EXIT, CUSTOM }

const NODE_NAMES := {
	Kind.TOW_HOOK_FRONT: "TowHookFront",
	Kind.TOW_HITCH_REAR: "TowHitchRear",
	Kind.TRAILER_COUPLER: "Coupler",
	Kind.DRIVER_EXIT: "DriverExit",
}

@export var kind: Kind = Kind.CUSTOM
## Node name for CUSTOM points (ignored for the other kinds).
@export var name: String = ""
@export var position: Vector3 = Vector3.ZERO
@export var rotation_degrees: Vector3 = Vector3.ZERO
## Size of a small box drawn at the point (e.g. a tow hook). Zero = invisible.
@export var marker_size: Vector3 = Vector3.ZERO
@export var marker_color: Color = Color(0.15, 0.15, 0.16)


func get_node_name() -> String:
	if kind == Kind.CUSTOM:
		return name if name != "" else "Mount"
	return NODE_NAMES[kind]


func get_transform() -> Transform3D:
	return Transform3D(Basis.from_euler(rotation_degrees * (PI / 180.0)), position)


## Kind for a node name, or CUSTOM.
static func kind_for_node_name(node_name: String) -> Kind:
	for k in NODE_NAMES:
		if NODE_NAMES[k] == node_name:
			return k
	return Kind.CUSTOM
