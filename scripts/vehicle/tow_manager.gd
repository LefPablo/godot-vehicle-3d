extends Node
## Couples vehicles together with the "tow" action (T):
##  - a tow ROPE between two vehicles (your rear hitch to the other's front hook,
##    or theirs to yours), within [member attach_range];
##  - a rigid TRAILER hitch: reverse until your rear hitch is within
##    [member hitch_range] of a trailer's "Coupler" marker.
##
## Vehicles need a "TowHookFront" and/or "TowHitchRear" Node3D marker; trailers a
## "Coupler" marker. Pressing T removes the most recent coupling the active
## vehicle is part of; if it has none, it makes the best one in range (a trailer
## in hitch range wins over a rope). Couplings can be combined, e.g. the truck
## pulls the trailer and tows the car on a rope at the same time.
## While coupled, a vehicle or trailer that nobody drives rolls freely.

const ACTION_TOW := &"tow"
const FRONT_HOOK := ^"TowHookFront"
const REAR_HITCH := ^"TowHitchRear"
const COUPLER := ^"Coupler"
const TowRopeScript := preload("res://scripts/vehicle/tow_rope.gd")

signal tow_changed(towing: bool)

## Provides the drivable vehicles and the active one.
@export var switcher: Node
## Trailers that can be hitched (ShapeCastVehicle bodies with a "Coupler" marker).
@export var trailers: Array[ShapeCastVehicle] = []

@export_group("Rope")
## Max distance between a hitch and a hook to tie a rope.
@export_range(0.5, 20.0, 0.1, "suffix:m") var attach_range: float = 6.0
## The rope length is the distance at the moment of hooking, within these limits.
@export_range(0.5, 20.0, 0.1, "suffix:m") var min_rope_length: float = 2.5
@export_range(0.5, 20.0, 0.1, "suffix:m") var max_rope_length: float = 5.0
@export_range(1000.0, 500000.0, 100.0, "suffix:N/m") var rope_stiffness: float = 60000.0
@export_range(0.0, 100000.0, 100.0, "suffix:Ns/m") var rope_damping: float = 8000.0
## 0 = the rope never snaps.
@export_range(0.0, 500000.0, 100.0, "suffix:N") var rope_break_force: float = 0.0

@export_group("Trailer Hitch")
## Max distance between your rear hitch and a trailer coupler to hitch it.
@export_range(0.1, 5.0, 0.05, "suffix:m") var hitch_range: float = 1.2
## The HUD guides you to trailers closer than this.
@export_range(0.0, 50.0, 0.5, "suffix:m") var trailer_hint_range: float = 10.0
## Hitch angle limits (left/right, up/down, roll).
@export_range(0.0, 90.0, 0.1, "radians_as_degrees") var max_hitch_yaw: float = 1.309
@export_range(0.0, 90.0, 0.1, "radians_as_degrees") var max_hitch_pitch: float = 0.5236
@export_range(0.0, 90.0, 0.1, "radians_as_degrees") var max_hitch_roll: float = 0.349

## Active couplings: {kind: "rope"/"trailer", tower, towed, node (TowRope/Joint)}.
var connections: Array[Dictionary] = []

## Compatibility helpers: the first rope coupling.
var rope: TowRopeScript:
	get:
		var c := _first(&"rope")
		return c.node if not c.is_empty() else null
var tower: ShapeCastVehicle:
	get:
		var c := _first(&"")
		return c.tower if not c.is_empty() else null
var towed: ShapeCastVehicle:
	get:
		var c := _first(&"")
		return c.towed if not c.is_empty() else null


func _ready() -> void:
	var seen: Array[ShapeCastVehicle] = []
	for vehicle in _vehicles() + trailers:
		# A trailer may also be in the switcher's vehicle list; connect it once.
		if vehicle == null or vehicle in seen:
			continue
		seen.append(vehicle)
		vehicle.vehicle_reset.connect(_on_vehicle_reset.bind(vehicle))
	for trailer in trailers:
		trailer.use_player_input = false
		trailer.set_controls(0.0, 0.0, true) # parked on its jack


## Lets a vehicle created at runtime take part in towing (rope couplings are
## made between the switcher's vehicles, so register it there too).
func register_vehicle(vehicle: ShapeCastVehicle) -> void:
	if vehicle == null:
		return
	var on_reset := _on_vehicle_reset.bind(vehicle)
	if not vehicle.vehicle_reset.is_connected(on_reset):
		vehicle.vehicle_reset.connect(on_reset)
		vehicle.tree_exiting.connect(_on_vehicle_removed.bind(vehicle), CONNECT_ONE_SHOT)


## Adds a trailer created at runtime (needs a "Coupler" marker). It starts parked.
func register_trailer(trailer: ShapeCastVehicle) -> void:
	if trailer == null or trailer in trailers:
		return
	trailers.append(trailer)
	trailer.use_player_input = false
	trailer.set_controls(0.0, 0.0, true)
	register_vehicle(trailer)


func _on_vehicle_removed(vehicle: ShapeCastVehicle) -> void:
	for c in connections_of(vehicle):
		disconnect_coupling(c)
	trailers.erase(vehicle)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION_TOW):
		toggle()
		get_viewport().set_input_as_handled()


## Unhooks the active vehicle's latest coupling, or makes the best new one.
func toggle() -> void:
	var active := _active_vehicle()
	if active == null:
		return
	var own := connections_of(active)
	if not own.is_empty():
		disconnect_coupling(own[-1])
		return
	var candidate := find_candidate()
	if not candidate.is_empty():
		connect_candidate(candidate)


func is_towing() -> bool:
	return not connections.is_empty()


func connections_of(vehicle: ShapeCastVehicle) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for c in connections:
		if c.tower == vehicle or c.towed == vehicle:
			result.append(c)
	return result


## Kept for compatibility: attach the best candidate.
func attach_nearest() -> bool:
	var candidate := find_candidate()
	if candidate.is_empty():
		return false
	connect_candidate(candidate)
	return true


## Removes every coupling.
func detach() -> void:
	for c in connections.duplicate():
		disconnect_coupling(c)


## Best new coupling for the active vehicle, or {}.
func find_candidate() -> Dictionary:
	var active := _active_vehicle()
	if active == null:
		return {}
	var best := {}

	# 1. Trailer: our rear hitch right at a free coupler.
	var hitch := active.get_node_or_null(REAR_HITCH) as Node3D
	if hitch and not _hitch_in_use(active):
		for trailer in trailers:
			var coupler := trailer.get_node_or_null(COUPLER) as Node3D
			if coupler == null or _is_pulled(trailer):
				continue
			var distance := hitch.global_position.distance_to(coupler.global_position)
			if distance <= hitch_range and (best.is_empty() or distance < best.distance):
				best = {"kind": &"trailer", "tower": active, "hitch": hitch, "towed": trailer,
						"hook": coupler, "distance": distance}
	if not best.is_empty():
		return best

	# 2. Rope: rear hitch <-> front hook between the active vehicle and another one.
	for other in _vehicles():
		if other == active:
			continue
		for pair in [[active, other], [other, active]]:
			var pulling: ShapeCastVehicle = pair[0]
			var pulled: ShapeCastVehicle = pair[1]
			if _hitch_in_use(pulling) or _is_pulled(pulled):
				continue
			var rear := pulling.get_node_or_null(REAR_HITCH) as Node3D
			var hook := pulled.get_node_or_null(FRONT_HOOK) as Node3D
			if rear == null or hook == null:
				continue
			var distance := rear.global_position.distance_to(hook.global_position)
			if distance <= attach_range and (best.is_empty() or distance < best.distance):
				best = {"kind": &"rope", "tower": pulling, "hitch": rear, "towed": pulled,
						"hook": hook, "distance": distance}
	return best


func connect_candidate(candidate: Dictionary) -> void:
	if candidate.kind == &"trailer":
		_hitch_trailer(candidate.tower, candidate.hitch, candidate.towed, candidate.hook)
	else:
		_tie_rope(candidate.tower, candidate.hitch, candidate.towed, candidate.hook)


func disconnect_coupling(connection: Dictionary) -> void:
	if not connections.has(connection):
		return
	connections.erase(connection)
	if is_instance_valid(connection.node):
		connection.node.queue_free()
	var pulled: ShapeCastVehicle = connection.towed
	if is_instance_valid(pulled) and not _is_pulled(pulled):
		pulled.is_towed = false
		if not pulled.use_player_input:
			pulled.set_controls(0.0, 0.0, true) # parked again
	tow_changed.emit(is_towing())


## One-line status for the HUD.
func get_status_text() -> String:
	var active := _active_vehicle()
	if active == null:
		return ""
	var parts: PackedStringArray = []
	for c in connections_of(active):
		if c.kind == &"rope":
			var r: TowRopeScript = c.node
			parts.append("%s is towing %s   rope %.1f / %.1f m   %.1f kN" % [
				c.tower.name, c.towed.name, r.current_distance, r.length, r.tension / 1000.0])
		else:
			parts.append("%s is pulling the %s   hitch angle %d deg" % [
				c.tower.name, c.towed.name, roundi(rad_to_deg(hitch_angle(c)))])
	if not parts.is_empty():
		parts.append("[T] unhook")
		return "   ".join(parts)

	var candidate := find_candidate()
	if not candidate.is_empty():
		if candidate.kind == &"trailer":
			return "[T] hitch the %s to %s" % [candidate.towed.name, candidate.tower.name]
		return "[T] hook %s to tow %s (%.1f m)" % [candidate.tower.name, candidate.towed.name, candidate.distance]

	var hint := _nearest_free_trailer(active)
	if not hint.is_empty():
		return "Reverse to the %s: hitch is %.1f m from its coupler" % [hint.trailer.name, hint.distance]
	return ""


## Yaw angle between the tower and its trailer, radians.
func hitch_angle(connection: Dictionary) -> float:
	var a := -(connection.tower as Node3D).global_basis.z
	var b := -(connection.towed as Node3D).global_basis.z
	a.y = 0.0
	b.y = 0.0
	if a.length_squared() < 1e-4 or b.length_squared() < 1e-4:
		return 0.0
	return a.normalized().signed_angle_to(b.normalized(), Vector3.UP)


# --- Making couplings ------------------------------------------------------

func _tie_rope(pulling: ShapeCastVehicle, hitch: Node3D, pulled: ShapeCastVehicle, hook: Node3D) -> void:
	var distance := hitch.global_position.distance_to(hook.global_position)
	var new_rope: TowRopeScript = TowRopeScript.new()
	new_rope.name = "TowRope"
	new_rope.stiffness = rope_stiffness
	new_rope.damping = rope_damping
	new_rope.break_force = rope_break_force
	new_rope.setup(pulling, pulling.to_local(hitch.global_position),
			pulled, pulled.to_local(hook.global_position),
			clampf(distance, min_rope_length, max_rope_length))
	add_child(new_rope)
	var connection := {"kind": &"rope", "tower": pulling, "towed": pulled, "node": new_rope}
	new_rope.snapped.connect(func(_force: float) -> void: disconnect_coupling(connection))
	_add(connection)


func _hitch_trailer(pulling: ShapeCastVehicle, hitch: Node3D, trailer: ShapeCastVehicle, coupler: Node3D) -> void:
	# 1. Swing the trailer about its axle so the coupler lands exactly on the
	#    hitch ball (and carry its load along).
	var old_xform := trailer.global_transform
	var coupler_local := old_xform.affine_inverse() * coupler.global_position
	var pivot := old_xform * _axle_point(trailer)
	var from := coupler.global_position - pivot
	var to := hitch.global_position - pivot
	var new_xform := old_xform
	if from.length() > 0.01 and to.length() > 0.01:
		var turn := Basis(Quaternion(from.normalized(), to.normalized()))
		new_xform = Transform3D(turn * old_xform.basis, pivot + turn * (old_xform.origin - pivot))
	new_xform.origin += hitch.global_position - new_xform * coupler_local
	var cargo := trailer.get_node_or_null(^"Cargo")
	if cargo and cargo.has_method(&"carry"):
		cargo.carry(new_xform * old_xform.affine_inverse())
	trailer.global_transform = new_xform
	trailer.linear_velocity = pulling.linear_velocity
	trailer.angular_velocity = pulling.angular_velocity
	trailer.reset_physics_interpolation()

	# 2. Ball joint at the hitch with angle limits. Joint axes follow the tower:
	#    X = pitch, Y = yaw, Z = roll. The linear axes stay locked (default).
	var joint := Generic6DOFJoint3D.new()
	joint.name = "TrailerHitch"
	add_child(joint)
	joint.global_transform = Transform3D(pulling.global_basis, hitch.global_position)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -max_hitch_pitch)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, max_hitch_pitch)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -max_hitch_yaw)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, max_hitch_yaw)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -max_hitch_roll)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, max_hitch_roll)
	joint.exclude_nodes_from_collision = true
	joint.node_a = joint.get_path_to(pulling)
	joint.node_b = joint.get_path_to(trailer)
	_add({"kind": &"trailer", "tower": pulling, "towed": trailer, "node": joint})


func _add(connection: Dictionary) -> void:
	connections.append(connection)
	connection.towed.is_towed = true
	tow_changed.emit(true)


# --- Helpers ---------------------------------------------------------------

## Middle of the trailer's axle (average of its wheel mounts), local space.
func _axle_point(vehicle: ShapeCastVehicle) -> Vector3:
	if vehicle.wheels.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for wheel in vehicle.wheels:
		sum += wheel.position
	return sum / vehicle.wheels.size()


func _nearest_free_trailer(active: ShapeCastVehicle) -> Dictionary:
	var hitch := active.get_node_or_null(REAR_HITCH) as Node3D
	if hitch == null or _hitch_in_use(active):
		return {}
	var best := {}
	for trailer in trailers:
		var coupler := trailer.get_node_or_null(COUPLER) as Node3D
		if coupler == null or _is_pulled(trailer):
			continue
		var distance := hitch.global_position.distance_to(coupler.global_position)
		if distance <= trailer_hint_range and (best.is_empty() or distance < best.distance):
			best = {"trailer": trailer, "distance": distance}
	return best


func _hitch_in_use(vehicle: ShapeCastVehicle) -> bool:
	for c in connections:
		if c.tower == vehicle:
			return true
	return false


func _is_pulled(vehicle: ShapeCastVehicle) -> bool:
	for c in connections:
		if c.towed == vehicle:
			return true
	return false


func _first(kind: StringName) -> Dictionary:
	for c in connections:
		if kind == &"" or c.kind == kind:
			return c
	return {}


func _on_vehicle_reset(vehicle: ShapeCastVehicle) -> void:
	# A reset teleports the vehicle; a coupling would yank the other one after it.
	for c in connections_of(vehicle):
		disconnect_coupling(c)


func _active_vehicle() -> ShapeCastVehicle:
	if switcher:
		return switcher.active_vehicle # null while on foot
	var list := _vehicles()
	return list[0] if not list.is_empty() else null


func _vehicles() -> Array[ShapeCastVehicle]:
	var list: Array[ShapeCastVehicle] = []
	if switcher:
		list.assign(switcher.vehicles)
	return list
