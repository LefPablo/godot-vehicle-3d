class_name VehicleAIDriver
extends Node
## Drives a [ShapeCastVehicle] along roads: a [VehicleRoad] network with
## [VehicleRoadJunction]s, or a plain Path3D.
##
## Route: the driver starts on the nearest lane that points roughly the way
## the vehicle faces. Whenever its lane runs into a junction it picks one of
## the other roads (left / straight / right, weighted at random, no U-turns)
## and follows a smooth turn curve into that road's lane. Loop roads are
## driven round and round; at a dead end it stops.
## Steering: pure pursuit, aiming at a point on the route a little ahead
## (further ahead at speed).
## Speed: it looks along the route, works out how fast each upcoming curve and
## turn can be taken ([member max_lateral_accel]) and brakes in time
## ([member max_braking]).
## Recovery: backs up when stuck; puts the vehicle back on its wheels when it
## lies on its side.
##
## Add it as a child of the vehicle (or set [member vehicle]), set [member path]
## to any road of the network (or a Path3D) and call [method start].
## While driving it takes over the vehicle (use_player_input is forced off).

signal started
signal stopped
## A dead end (or the end of an open Path3D) was reached.
signal finished
## The driver had to recover: "stuck" (backed up) or "flipped" (vehicle reset).
signal recovered(reason: String)
## The vehicle enters a junction: [param kind] is "left", "straight" or "right".
signal turning(kind: String, junction: Node, to_road: Node)

## Vehicle to drive. Empty = the parent node.
@export var vehicle: ShapeCastVehicle
## A [VehicleRoad] (the driver uses the whole network it belongs to) or any Path3D.
@export var path: Path3D
## Driving. Can be toggled in the inspector, also while the game runs.
@export var enabled: bool = false:
	set(value):
		enabled = value
		if is_inside_tree():
			if enabled:
				_begin()
			else:
				_end()

@export_group("Lane")
## Lane to drive in on roads (0 = next to the centre line).
@export_range(0, 3) var lane: int = 0
## Sideways offset from a plain Path3D (positive = right).
@export_range(-20.0, 20.0, 0.05, "suffix:m") var lane_offset: float = 0.0

@export_group("Junctions")
## How often each direction is chosen at junctions (relative weights; 0 = never,
## unless it is the only way).
@export_range(0.0, 10.0, 0.1) var straight_weight: float = 1.0
@export_range(0.0, 10.0, 0.1) var left_weight: float = 1.0
@export_range(0.0, 10.0, 0.1) var right_weight: float = 1.0
## Seed for the choices (0 = different every time).
@export var random_seed: int = 0

@export_group("Speed")
@export_range(5.0, 300.0, 1.0, "suffix:km/h") var max_speed_kmh: float = 60.0
## Sideways acceleration allowed in curves: lower = slower, safer cornering.
@export_range(1.0, 15.0, 0.1, "suffix:m/s²") var max_lateral_accel: float = 4.5
## Deceleration planned when slowing down for a curve, a turn or a dead end.
@export_range(1.0, 15.0, 0.1, "suffix:m/s²") var max_braking: float = 5.0
## Throttle per m/s below the target speed.
@export_range(0.05, 5.0, 0.05) var throttle_gain: float = 0.6
## Brake per m/s above the target speed.
@export_range(0.05, 5.0, 0.05) var brake_gain: float = 0.4

@export_group("Steering")
## Shortest look-ahead distance.
@export_range(1.0, 30.0, 0.1, "suffix:m") var lookahead_min: float = 5.0
## Look-ahead grows with speed: speed * this time.
@export_range(0.1, 3.0, 0.05, "suffix:s") var lookahead_time: float = 0.7

@export_group("Recovery")
## Back up when not moving for this long while trying to drive.
@export_range(0.5, 10.0, 0.1, "suffix:s") var stuck_time: float = 2.5
@export_range(0.2, 5.0, 0.1, "suffix:s") var reverse_time: float = 1.5
## Reset the vehicle onto its wheels after lying on its side this long.
@export_range(0.5, 10.0, 0.1, "suffix:s") var flip_reset_time: float = 2.0

@export_group("Debug")
## Draw the route ahead and the point the driver is aiming at.
@export var debug_draw: bool = true

## Speed the driver is aiming for right now, m/s.
var target_speed: float = 0.0
## Distance driven along the route since [method start], metres.
var distance_on_route: float = 0.0
## Sideways distance from the lane / turn being followed, metres.
var lane_error: float = 0.0
## Turns taken since [method start]: {"left", "straight", "right"}.
var turns: Dictionary = {"left": 0, "straight": 0, "right": 0}
## Total recoveries (stuck or flipped) since the start.
var recoveries: int = 0

## Route ahead: [{"curve": Curve3D (world space), "length", "kind": "lane" or a
## turn kind, "road", "forward", "junction", "to_road"}]. The first entry is
## the one being driven.
var _route: Array[Dictionary] = []
var _route_closed: bool = false # can't be extended (dead end)
var _offset: float = 0.0
var _plain_loop: bool = false
var _rng := RandomNumberGenerator.new()
var _running: bool = false
var _finished: bool = false
var _wheelbase: float = 2.5
var _last_steer: float = 0.0
var _stuck_timer: float = 0.0
var _reverse_timer: float = 0.0
var _flip_timer: float = 0.0
var _target: Vector3 = Vector3.ZERO
var _debug: MeshInstance3D


func _ready() -> void:
	set_physics_process(false)
	if vehicle == null:
		vehicle = get_parent() as ShapeCastVehicle
	if enabled:
		_begin.call_deferred()


func start() -> void:
	enabled = true


func stop() -> void:
	enabled = false


func is_driving() -> bool:
	return _running


## Kind of the junction turn being driven or coming next ("" if none).
func get_next_turn() -> String:
	for segment in _route:
		if segment.kind != "lane":
			return segment.kind
	return ""


func _begin() -> void:
	if _running:
		return
	if vehicle == null or path == null or path.curve == null or path.curve.point_count < 2:
		push_warning("VehicleAIDriver: needs a vehicle and a road / path with at least 2 points.")
		enabled = false
		return
	if random_seed != 0:
		_rng.seed = random_seed
	else:
		_rng.randomize()
	_route.clear()
	_route_closed = false
	_start_route()
	_offset = (_route[0].curve as Curve3D).get_closest_offset(vehicle.global_position)
	_running = true
	_finished = false
	distance_on_route = 0.0
	turns = {"left": 0, "straight": 0, "right": 0}
	_stuck_timer = 0.0
	_reverse_timer = 0.0
	_flip_timer = 0.0
	_wheelbase = _measure_wheelbase()
	vehicle.use_player_input = false
	set_physics_process(true)
	started.emit()


func _end() -> void:
	if not _running:
		return
	_running = false
	set_physics_process(false)
	if is_instance_valid(vehicle):
		vehicle.set_controls(0.0, 0.0, true)
	if is_instance_valid(_debug):
		_debug.visible = false
	stopped.emit()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(vehicle) or not is_instance_valid(path):
		stop()
		return
	vehicle.use_player_input = false
	var position := vehicle.global_position
	var speed := vehicle.forward_speed
	_advance(position)
	_extend_to(_horizon(speed))
	var current: Curve3D = _route[0].curve
	lane_error = _flat_distance(position, current.sample_baked(_offset, true))

	# On its side or roof: put it back on its wheels.
	if vehicle.global_basis.y.y < 0.3:
		_flip_timer += delta
		vehicle.set_controls(0.0, 0.0, false)
		if _flip_timer > flip_reset_time:
			_flip_timer = 0.0
			recoveries += 1
			vehicle.reset_vehicle()
			recovered.emit("flipped")
		return
	_flip_timer = 0.0

	# Backing up after getting stuck.
	if _reverse_timer > 0.0:
		_reverse_timer -= delta
		vehicle.set_controls(-0.8, -_last_steer, false)
		return

	# Steering: pure pursuit towards a point on the route ahead.
	var lookahead := maxf(lookahead_min, absf(speed) * lookahead_time)
	_target = _route_point(lookahead)
	var local_target := vehicle.global_transform.affine_inverse() * _target
	local_target.y = 0.0
	var distance := maxf(local_target.length(), 0.1)
	var alpha := atan2(-local_target.x, -local_target.z) # > 0: target on the left
	var wanted_angle := atan(2.0 * _wheelbase * sin(alpha) / distance)
	var speed_factor := clampf(absf(speed) / (vehicle.high_speed_kmh / 3.6), 0.0, 1.0)
	var steer_limit := lerpf(vehicle.max_steer_angle, vehicle.high_speed_steer_angle, speed_factor)
	var steer := clampf(wanted_angle / maxf(steer_limit, 0.01), -1.0, 1.0)

	# Speed: fastest speed that still makes every upcoming curve / the end.
	target_speed = _plan_speed(speed)
	if absf(alpha) > deg_to_rad(70.0):
		target_speed = minf(target_speed, 4.0) # still turning towards the route
	var throttle := 0.0
	var error := target_speed - speed
	if error > 0.0:
		throttle = clampf(error * throttle_gain, 0.0, 1.0)
	elif error < -0.3 and speed > 1.5:
		throttle = clampf(error * brake_gain, -1.0, 0.0) # brakes while rolling forward
	var handbrake := target_speed < 0.3 and absf(speed) < 0.5

	# Not moving although it should: back up for a moment.
	if throttle > 0.3 and absf(speed) < 0.4:
		_stuck_timer += delta
		if _stuck_timer > stuck_time:
			_stuck_timer = 0.0
			_reverse_timer = reverse_time
			recoveries += 1
			recovered.emit("stuck")
	else:
		_stuck_timer = 0.0

	_last_steer = steer
	vehicle.set_controls(throttle, steer, handbrake)

	if _route_closed and not _finished and _remaining() < 2.0 and absf(speed) < 0.3:
		_finished = true
		finished.emit()
	if debug_draw:
		_draw_debug()


# --- Route --------------------------------------------------------------------

## True when [member path] is a road: drive the whole road network.
func _is_network() -> bool:
	return path is VehicleRoad


func _start_route() -> void:
	if not _is_network():
		_route.append(_segment(_plain_lane_curve(), "lane", path, true))
		return
	var position := vehicle.global_position
	var facing := -vehicle.global_basis.z
	facing.y = 0.0
	facing = facing.normalized()
	var best: Dictionary = {}
	var best_score := INF
	for node in get_tree().get_nodes_in_group(VehicleRoad.GROUP):
		var road := node as VehicleRoad
		if road == null:
			continue
		for forward: bool in ([true, false] if road.two_way else [true]):
			var lane_curve := road.get_lane_curve(forward, lane)
			if lane_curve.point_count < 2:
				continue
			var offset := lane_curve.get_closest_offset(position)
			var point := lane_curve.sample_baked(offset, true)
			var direction := _curve_direction(lane_curve, offset)
			# Near, and pointing the way the vehicle faces.
			var score := _flat_distance(position, point) + (1.0 - direction.dot(facing)) * 6.0
			if score < best_score:
				best_score = score
				best = _segment(lane_curve, "lane", road, forward)
	if best.is_empty():
		best = _segment(_plain_lane_curve(), "lane", path, true)
	_route.append(best)


func _segment(curve: Curve3D, kind: String, road: Node, forward: bool) -> Dictionary:
	return {"curve": curve, "length": curve.get_baked_length(), "kind": kind,
			"road": road, "forward": forward}


## Adds the next piece of route. False at a dead end.
func _extend_route() -> bool:
	if _route_closed:
		return false
	var last: Dictionary = _route.back()
	var road: Node = last.road
	var loops := _plain_loop if not _is_network() else (road as VehicleRoad).is_loop()
	if loops:
		_route.append(last.duplicate())
		return true
	if not _is_network():
		_route_closed = true
		return false
	# The lane ends at the road's end (forward) or start (backward).
	var arrive_at_start: bool = not last.forward
	var junction := _junction_for(road, arrive_at_start)
	var exits: Array[Dictionary] = []
	if junction:
		exits = junction.get_exits(road, arrive_at_start)
	if exits.is_empty():
		_route_closed = true
		return false
	var exit := _choose(exits)
	var exit_road: VehicleRoad = exit.road
	var next := _segment(exit_road.get_lane_curve(exit.forward, lane), "lane", exit_road, exit.forward)
	var from_curve: Curve3D = last.curve
	var from_length: float = last.length
	var to_curve: Curve3D = next.curve
	var turn: Curve3D = junction.make_turn_curve(
			from_curve.sample_baked(from_length, true), _curve_direction(from_curve, from_length),
			to_curve.sample_baked(0.0, true), _curve_direction(to_curve, 0.0))
	var turn_segment := _segment(turn, exit.kind, null, true)
	turn_segment["junction"] = junction
	turn_segment["to_road"] = exit_road
	_route.append(turn_segment)
	_route.append(next)
	return true


func _junction_for(road: Node, at_start: bool) -> VehicleRoadJunction:
	for node in get_tree().get_nodes_in_group(VehicleRoadJunction.GROUP):
		var junction := node as VehicleRoadJunction
		if junction and junction.has_leg(road, at_start):
			return junction
	return null


## Weighted random choice between left / straight / right.
func _choose(exits: Array[Dictionary]) -> Dictionary:
	var weights := {"left": left_weight, "straight": straight_weight, "right": right_weight}
	var total := 0.0
	for exit in exits:
		total += weights[exit.kind]
	if total <= 0.0:
		return exits[_rng.randi_range(0, exits.size() - 1)]
	var pick := _rng.randf() * total
	for exit in exits:
		pick -= weights[exit.kind]
		if pick <= 0.0:
			return exit
	return exits.back()


## Moves on to the next route piece once the vehicle has passed the current one.
func _advance(position: Vector3) -> void:
	for attempt in 4:
		var current: Dictionary = _route[0]
		var current_curve: Curve3D = current.curve
		var offset := current_curve.get_closest_offset(position)
		var current_length: float = current.length
		if _offset < 1.0 and offset > current_length - 1.0 and current_length > 5.0:
			offset = 0.0 # loop: start and end are the same point, we are at the start
		if offset > _offset and offset - _offset < 20.0:
			distance_on_route += offset - _offset
		_offset = offset
		if _route.size() < 2:
			_extend_route()
			if _route.size() < 2:
				return
		var length: float = current.length
		var next_curve: Curve3D = _route[1].curve
		var next_length: float = _route[1].length
		var next_offset := next_curve.get_closest_offset(position)
		var closer_to_next := _flat_distance(position, next_curve.sample_baked(next_offset, true)) + 0.05 \
				< _flat_distance(position, current_curve.sample_baked(offset, true))
		if offset >= length - 0.75 or (closer_to_next and next_offset > 0.2
				and next_offset < next_length - 0.5):
			distance_on_route += maxf(length - _offset, 0.0)
			_route.pop_front()
			_offset = 0.0
			_on_enter(_route[0])
			continue
		return


func _on_enter(segment: Dictionary) -> void:
	var kind: String = segment.kind
	if turns.has(kind):
		turns[kind] += 1
		turning.emit(kind, segment.junction, segment.to_road)


## Makes the route reach at least [param distance] ahead.
func _extend_to(distance: float) -> void:
	while _remaining() < distance:
		if not _extend_route():
			return


func _remaining() -> float:
	var first_length: float = _route[0].length
	var total := first_length - _offset
	for i in range(1, _route.size()):
		var length: float = _route[i].length
		total += length
	return total


func _horizon(speed: float) -> float:
	return clampf(speed * speed / (2.0 * max_braking) + lookahead_min + 25.0, 40.0, 200.0)


## Point [param ahead] metres further along the route.
func _route_point(ahead: float) -> Vector3:
	var along := _offset + ahead
	for segment in _route:
		var length: float = segment.length
		if along <= length:
			return (segment.curve as Curve3D).sample_baked(maxf(along, 0.0), true)
		along -= length
	var last: Dictionary = _route.back()
	return (last.curve as Curve3D).sample_baked(last.length, true)


## How fast the vehicle may go now so it can still slow down for every curve
## and turn within its braking distance (and stop at a dead end).
func _plan_speed(speed: float) -> float:
	var limit := max_speed_kmh / 3.6
	var horizon := minf(_horizon(speed), _remaining())
	var ahead := 0.0
	while ahead <= horizon:
		var curvature := _curvature_at(ahead)
		if curvature > 0.0005:
			var corner_speed := sqrt(max_lateral_accel / curvature)
			var braking_room := maxf(ahead - 2.0, 0.0)
			limit = minf(limit, sqrt(corner_speed * corner_speed + 2.0 * max_braking * braking_room))
		ahead += 2.0
	if _route_closed:
		limit = minf(limit, sqrt(2.0 * max_braking * maxf(_remaining() - 1.0, 0.0)))
	return limit


## Route curvature (1 / radius) [param ahead] metres ahead.
func _curvature_at(ahead: float) -> float:
	var h := 2.0
	var a := _route_point(ahead - h)
	var b := _route_point(ahead)
	var c := _route_point(ahead + h)
	var first := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var second := Vector3(c.x - b.x, 0.0, c.z - b.z)
	if first.length_squared() < 0.0001 or second.length_squared() < 0.0001:
		return 0.0
	return first.angle_to(second) / h


## A plain Path3D as a world-space lane curve (with [member lane_offset]).
func _plain_lane_curve() -> Curve3D:
	var source := path.curve
	var length := source.get_baked_length()
	_plain_loop = source.get(&"closed") == true or \
			source.get_point_position(0).distance_to(source.get_point_position(source.point_count - 1)) < 0.5
	var lane_curve := Curve3D.new()
	lane_curve.bake_interval = 0.5
	var steps := maxi(2, ceili(length))
	for i in steps + 1:
		var offset := length * i / steps
		var ahead := source.sample_baked(minf(offset + 0.5, length), true)
		var behind := source.sample_baked(maxf(offset - 0.5, 0.0), true)
		var tangent := ahead - behind
		tangent.y = 0.0
		var right := tangent.normalized().cross(Vector3.UP) if tangent.length_squared() > 0.000001 else Vector3.ZERO
		lane_curve.add_point(path.global_transform * (source.sample_baked(offset, true) + right * lane_offset))
	return lane_curve


func _curve_direction(curve: Curve3D, offset: float) -> Vector3:
	var length := curve.get_baked_length()
	var ahead := curve.sample_baked(minf(offset + 0.5, length), true)
	var behind := curve.sample_baked(maxf(offset - 0.5, 0.0), true)
	var direction := ahead - behind
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 0.000001 else Vector3.FORWARD


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Distance between the front-most and rear-most wheels.
func _measure_wheelbase() -> float:
	if vehicle.wheels.is_empty():
		return 2.5
	var front := INF
	var rear := -INF
	for wheel in vehicle.wheels:
		front = minf(front, wheel.position.z)
		rear = maxf(rear, wheel.position.z)
	return maxf(rear - front, 1.0)


## Yellow: the route ahead. Cyan: the point the driver is aiming at.
func _draw_debug() -> void:
	if not is_instance_valid(_debug):
		_debug = MeshInstance3D.new()
		_debug.name = "AIDebug"
		_debug.mesh = ImmediateMesh.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		material.no_depth_test = true
		_debug.material_override = material
		_debug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_debug, false, Node.INTERNAL_MODE_BACK)
	_debug.visible = true
	var mesh := _debug.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var lift := Vector3.UP * 0.3
	var previous := _route_point(0.0) + lift
	var ahead := 2.0
	while ahead <= minf(45.0, _remaining()):
		var point := _route_point(ahead) + lift
		_debug_line(mesh, previous, point, Color(1.0, 0.85, 0.1))
		previous = point
		ahead += 2.0
	var target := _target + lift
	var aim := Color(0.2, 0.9, 1.0)
	_debug_line(mesh, vehicle.global_position + Vector3.UP * 0.8, target, aim)
	_debug_line(mesh, target, target + Vector3.UP * 0.8, aim)
	mesh.surface_end()


func _debug_line(mesh: ImmediateMesh, from: Vector3, to: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(from)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(to)
