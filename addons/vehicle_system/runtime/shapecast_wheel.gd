@tool
class_name ShapeCastWheel
extends ShapeCast3D
## Physics wheel that finds the ground with a swept, wheel-shaped ShapeCast3D
## instead of a single ray.
##
## The node itself is the suspension mount: the wheel centre sits here when the
## suspension is fully compressed. The sweep does NOT start at the mount but
## [member cast_headroom] above it (the hull points are offset upwards), and runs
## down to full extension. Starting above the wheel matters because Jolt ignores a
## body completely when the cast shape starts inside it; starting high means steps
## and curbs are always met from above, so the wheel climbs them instead of
## sinking into them.
##
## Because the whole round tyre profile is tested (not one point under the axle):
## - the wheel starts climbing a bump or curb as soon as its front edge touches it,
## - it rolls smoothly over sharp edges instead of snapping up when the axle passes,
## - it bridges pits narrower than the tyre and only dips as deep as a real
##   round wheel would.
##
## If an obstacle is higher than the suspension can absorb, the fully compressed
## wheel acts like a rigid part of the car ("hard contact"): it lifts the car onto
## a step, or stops it against a wall, instead of passing through.
##
## The owning [ShapeCastVehicle] calls [method update_wheel] every physics tick.

@export_group("Wheel")
## Tyre radius. The cast shape and the visual mesh are generated from it.
@export_range(0.1, 1.5, 0.01, "suffix:m") var wheel_radius: float = 0.36:
	set(value):
		wheel_radius = value
		_queue_rebuild()
## Tyre width (along the axle, local X axis).
@export_range(0.05, 1.0, 0.01, "suffix:m") var wheel_width: float = 0.26:
	set(value):
		wheel_width = value
		_queue_rebuild()
## Number of sides of the convex wheel hull used for the sweep.
@export_range(8, 48, 1) var shape_segments: int = 24:
	set(value):
		shape_segments = value
		_queue_rebuild()
## This wheel turns with the steering input.
@export var is_steering: bool = false
## Multiplier of the vehicle's steering angle (negative = counter-steer).
@export_range(-2.0, 2.0, 0.01) var steer_ratio: float = 1.0
## This wheel receives engine force.
@export var is_drive: bool = false
## This wheel is locked by the handbrake.
@export var has_handbrake: bool = false

@export_group("Suspension")
## How far the wheel centre can travel below the mount point (node origin).
@export_range(0.05, 1.5, 0.01, "suffix:m") var suspension_travel: float = 0.35:
	set(value):
		suspension_travel = value
		_queue_rebuild()
## The sweep starts this far above the mount. Anything lower than
## (mount + headroom - radius) is found from above and climbed. Taller things are
## handled as walls. Too large a value makes low ceilings count as obstacles.
@export_range(0.0, 1.5, 0.01, "suffix:m") var cast_headroom: float = 0.4:
	set(value):
		cast_headroom = value
		_queue_rebuild()
## Spring rate. Static sag = (car weight / wheel count) / stiffness.
@export_range(0.0, 200000.0, 100.0, "suffix:N/m") var spring_stiffness: float = 22000.0
## Damping while the suspension is being compressed (bump).
@export_range(0.0, 20000.0, 10.0, "suffix:Ns/m") var damping_compression: float = 1800.0
## Damping while the suspension is extending (rebound).
@export_range(0.0, 20000.0, 10.0, "suffix:Ns/m") var damping_rebound: float = 2600.0
## Length of the stiff bump stop at the end of the travel.
@export_range(0.0, 0.3, 0.005, "suffix:m") var bump_stop_length: float = 0.05
## Stiffness of the bump stop (added on top of the spring).
@export_range(0.0, 1000000.0, 1000.0, "suffix:N/m") var bump_stop_stiffness: float = 150000.0
## Clamp for the damper input velocity. When the swept wheel meets a sharp edge
## the compression can jump several centimetres in one tick; this keeps the damper
## from producing an unrealistic force spike.
@export_range(0.5, 20.0, 0.1, "suffix:m/s") var max_damper_speed: float = 4.0
## Direction of the suspension force: 0 = along the strut (car up), 1 = along the
## contact normal reported by the shape cast. With a round wheel, hitting the edge
## of a step gives a slanted normal, so part of the force pushes the car back and up
## like a real curb impact.
@export_range(0.0, 1.0, 0.01) var contact_normal_influence: float = 0.5

@export_group("Hard Contact")
## Share of the impulse needed to stop the wheel moving into an obstacle that is
## applied per tick. Below 1 because both wheels of an axle usually hit together.
@export_range(0.0, 1.0, 0.01) var hard_contact_strength: float = 0.5
## How fast penetration is pushed out (per second, as a fraction of the depth).
@export_range(0.0, 60.0, 0.1, "suffix:1/s") var hard_contact_correction: float = 20.0
## Upper limit for the push-out speed.
@export_range(0.0, 10.0, 0.1, "suffix:m/s") var max_correction_speed: float = 3.0
## Assumed depth when the tyre is inside something even at the top of its travel.
@export_range(0.0, 0.5, 0.005, "suffix:m") var blocked_push_depth: float = 0.05

@export_group("Tyre")
## Friction coefficient: maximum tyre force = friction * wheel load.
@export_range(0.0, 3.0, 0.01) var tire_friction: float = 1.2
## Fraction of sideways sliding velocity cancelled per physics tick.
@export_range(0.0, 1.0, 0.01) var lateral_grip: float = 0.6
## Sideways grip while the handbrake locks this wheel (lower = easier drifts).
@export_range(0.0, 1.0, 0.01) var handbrake_lateral_grip: float = 0.2
## Rolling resistance, proportional to rolling speed.
@export_range(0.0, 500.0, 1.0, "suffix:Ns/m") var rolling_resistance: float = 25.0

@export_group("Visual")
## Places the wheel mesh with its own cast every rendered frame, using the same
## (interpolated) car position that is drawn. Without it the mesh lags one physics
## tick behind the body and can clip into steps at speed.
@export var sync_visual_every_frame: bool = true
## How far the mesh may rise above the fully compressed position while an
## obstacle is being pushed out (looks like the tyre going into the wheel arch).
@export_range(0.0, 0.5, 0.005, "suffix:m") var max_visual_overlift: float = 0.1
## Wheel model used instead of the generated tyre (centred on the axle, axle
## along X). Set before the wheel enters the tree, or call [method set_custom_visual].
@export var visual_scene: PackedScene:
	set(value):
		visual_scene = value
		_queue_rebuild()
## Transform of the custom visual relative to the wheel centre.
@export var visual_transform: Transform3D = Transform3D.IDENTITY:
	set(value):
		visual_transform = value
		if is_instance_valid(_custom_visual):
			_custom_visual.transform = value

@export_group("Solid Wheel")
## Adds a wheel-shaped collision shape to the vehicle body that follows the
## suspension, so characters, other vehicles (and their wheels) and loose boxes
## can't pass through the tyre. The road itself is still handled by the sweep.
@export var solid: bool = true
## Collider radius as a fraction of the tyre radius.
@export_range(0.5, 1.0, 0.01) var collider_radius_scale: float = 0.9
## Gap kept between the collider and the ground under the tyre, so the collider
## never fights the suspension on the road.
@export_range(0.0, 0.3, 0.005, "suffix:m") var collider_ground_clearance: float = 0.08

# --- Runtime state (read by the vehicle and the HUD) -------------------------
## True when the swept wheel touches the ground.
var is_grounded: bool = false
## True when the tyre is inside an obstacle even at the top of its travel (a wall).
var is_blocked: bool = false
## Distance from the mount point to the wheel centre.
var suspension_length: float = 0.0
## How much the suspension is compressed (0 = fully extended).
var compression: float = 0.0
## Compression normalised to 0..1.
var compression_ratio: float = 0.0
## How far above the fully compressed position the obstacle wants the wheel.
var overcompression: float = 0.0
## Current suspension force (also the tyre load).
var suspension_force: float = 0.0
## Force of the hard contact this tick (0 when the suspension coped).
var impact_force: float = 0.0
## World-space contact point and normal of the tyre.
var contact_point: Vector3 = Vector3.ZERO
var contact_normal: Vector3 = Vector3.UP
## Loose physics body under the tyre (e.g. a fallen box), or null for static ground.
## It receives the opposite of every force the tyre gets, so boxes get squashed,
## kicked and pushed instead of acting like rocks.
var contact_body: RigidBody3D = null
## True when the tyre force hit the friction limit.
var is_slipping: bool = false
## Wheel angular speed in rad/s (for visuals).
var spin_speed: float = 0.0

var _prev_compression: float = 0.0
var _spin_angle: float = 0.0
var _rebuild_queued: bool = false
var _visual_root: Node3D
var _visual_spin: Node3D
var _query := PhysicsShapeQueryParameters3D.new()
var _visual_query := PhysicsShapeQueryParameters3D.new()
var _query_body: RigidBody3D
var _collider: CollisionShape3D
var _collider_transform := Transform3D()
## Node used as the wheel visual (from [member visual_scene] or handed over by
## the vehicle builder, e.g. a wheel taken out of the car model).
var _custom_visual: Node3D
var _custom_visual_from_scene: bool = false


func _ready() -> void:
	max_results = 4
	_rebuild()
	suspension_length = suspension_travel
	if not Engine.is_editor_hint():
		# The vehicle forces the update itself, so results are always fresh
		# at the exact moment forces are computed.
		enabled = false
		if solid:
			# The parent body is still setting up its children during _ready.
			_create_collider.call_deferred()


## Runs the shape cast and applies suspension + tyre forces to [param body].
func update_wheel(
		delta: float,
		body: RigidBody3D,
		body_state: PhysicsDirectBodyState3D,
		drive_force: float,
		brake_force: float,
		handbrake_on: bool,
		mass_share: float) -> void:
	var up := global_basis.y.normalized()
	_prev_compression = compression
	impact_force = 0.0
	is_blocked = false
	contact_body = null

	# ---- 1. Find where the wheel rests ------------------------------------
	# raw_length < 0 means the obstacle wants the wheel above the mount.
	var raw_length := _find_ground(body, up)
	is_grounded = not is_nan(raw_length)
	if is_grounded:
		overcompression = maxf(-raw_length, 0.0)
		suspension_length = clampf(raw_length, 0.0, suspension_travel)
	else:
		overcompression = 0.0
		suspension_length = suspension_travel

	compression = suspension_travel - suspension_length
	compression_ratio = compression / suspension_travel
	var wheel_center := global_transform * Vector3(0.0, -suspension_length, 0.0)

	if not is_grounded:
		suspension_force = 0.0
		is_slipping = false
		_update_air_spin(delta, drive_force, handbrake_on)
		_update_visual()
		_update_collider()
		return

	var normal_up := contact_normal.dot(up)

	# ---- 2. Suspension: spring + damper + bump stop -------------------------
	# Compression speed comes from the swept result, so it includes the change
	# caused by the wheel profile rolling onto a bump, not only body motion.
	var compression_speed := clampf(
			(compression - _prev_compression) / delta, -max_damper_speed, max_damper_speed)
	var damping := damping_compression if compression_speed > 0.0 else damping_rebound
	var spring := compression * spring_stiffness
	var damper := compression_speed * damping
	var bump_stop := 0.0
	var bump_start := suspension_travel - bump_stop_length
	if compression > bump_start:
		bump_stop = (compression - bump_start) * bump_stop_stiffness
	# Only contacts that face upwards load the spring; a wall contact doesn't.
	var support := smoothstep(0.2, 0.5, normal_up)
	suspension_force = maxf(spring + damper + bump_stop, 0.0) * support

	if suspension_force > 0.0:
		var force_dir := up.lerp(contact_normal, contact_normal_influence).normalized()
		if force_dir.dot(up) < 0.1:
			force_dir = up
		# A normal force on a round wheel always points through the wheel centre,
		# so applying it at the centre gives the correct torque on the body.
		body.apply_force(force_dir * suspension_force, wheel_center - body.global_position)
		_push_contact_body(-force_dir * suspension_force)

	# ---- 3. Hard contact: obstacle is beyond what the suspension can absorb --
	if is_blocked:
		_apply_hard_contact(delta, body, body_state, wheel_center, contact_normal, blocked_push_depth)
	elif overcompression > 0.0:
		_apply_hard_contact(delta, body, body_state, wheel_center, contact_normal,
				overcompression * maxf(normal_up, 0.0))

	# ---- 4. Tyre forces in the contact plane -------------------------------
	# Near-vertical contacts (step faces, walls) are not a driving surface.
	is_slipping = false
	if normal_up > 0.4 and suspension_force > 0.0:
		_apply_tire_forces(delta, body, body_state, drive_force, brake_force, handbrake_on, mass_share)

	# ---- 5. Visuals ---------------------------------------------------------
	if handbrake_on:
		spin_speed = 0.0
	else:
		var rolling_velocity := body_state.get_velocity_at_local_position(
				contact_point - body.global_position)
		spin_speed = rolling_velocity.dot(-global_basis.z) / wheel_radius
	_spin_angle = wrapf(_spin_angle - spin_speed * delta, -PI, PI)
	_update_visual()
	_update_collider()


## Sweeps the tyre down and returns the suspension length at which it touches
## (negative = above the mount), or NAN when nothing is below the wheel.
## Also sets contact_point / contact_normal / is_blocked.
func _find_ground(body: RigidBody3D, up: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	if _query_body != body:
		_query_body = body
		_query.exclude = [body.get_rid()]
	_query.collision_mask = collision_mask
	_query.motion = Vector3.ZERO

	# 1. Normal case: the top of the sweep is clear, use this ShapeCast3D.
	_query.transform = global_transform
	if space.intersect_shape(_query, 1).is_empty():
		force_shapecast_update()
		if not is_colliding():
			return NAN
		_pick_contact(up)
		var sweep_length := cast_headroom + suspension_travel
		return sweep_length * get_closest_collision_safe_fraction() - cast_headroom

	# 2. Something sits inside the headroom (very tall step, overhang):
	#    sweep again from lower starting points that are clear.
	for start_height: float in [cast_headroom * 0.5, 0.0]:
		_query.motion = Vector3.ZERO
		_query.transform = global_transform.translated(-up * (cast_headroom - start_height))
		if not space.intersect_shape(_query, 1).is_empty():
			continue
		var sweep_length := start_height + suspension_travel
		_query.motion = -up * sweep_length
		var fractions := space.cast_motion(_query)
		if fractions[1] >= 1.0:
			return NAN
		_query.transform = _query.transform.translated(_query.motion * fractions[1])
		_query.motion = Vector3.ZERO
		_set_contact_from_rest_info(space.get_rest_info(_query), up)
		return sweep_length * fractions[0] - start_height

	# 3. The tyre is inside an obstacle even at the top of its travel: a wall.
	_query.transform = global_transform.translated(-up * cast_headroom)
	var info := space.get_rest_info(_query)
	if info.is_empty():
		return NAN
	is_blocked = true
	contact_point = info.point
	contact_normal = (info.normal as Vector3).normalized()
	contact_body = _as_dynamic(instance_from_id(info.collider_id))
	return 0.0


## Picks the contact that stopped the sweep (the highest one along the strut).
func _pick_contact(up: Vector3) -> void:
	var count := get_collision_count()
	if count == 0:
		contact_point = global_transform * Vector3(0.0, -suspension_length - wheel_radius, 0.0)
		contact_normal = up
		return
	var best_height := -INF
	for i in count:
		var point := get_collision_point(i)
		var height := point.dot(up)
		if height > best_height:
			best_height = height
			contact_point = point
			contact_normal = get_collision_normal(i)
			contact_body = _as_dynamic(get_collider(i))
	if contact_normal.dot(up) < 0.0:
		contact_normal = -contact_normal
	contact_normal = contact_normal.normalized()


func _set_contact_from_rest_info(info: Dictionary, up: Vector3) -> void:
	if info.is_empty():
		contact_point = global_transform * Vector3(0.0, -wheel_radius, 0.0)
		contact_normal = up
		return
	contact_point = info.point
	contact_normal = (info.normal as Vector3).normalized()
	contact_body = _as_dynamic(instance_from_id(info.collider_id))
	if contact_normal.dot(up) < 0.0:
		contact_normal = -contact_normal


## Returns the object if it is a movable rigid body, otherwise null.
func _as_dynamic(object: Object) -> RigidBody3D:
	var rigid := object as RigidBody3D
	if rigid == null or rigid.freeze:
		return null
	return rigid


## Velocity of the surface under the tyre (zero for static ground).
func _contact_velocity(point: Vector3) -> Vector3:
	if contact_body == null or not is_instance_valid(contact_body):
		return Vector3.ZERO
	var state := PhysicsServer3D.body_get_direct_state(contact_body.get_rid())
	if state == null:
		return contact_body.linear_velocity
	return state.get_velocity_at_local_position(point - contact_body.global_position)


## Newton's third law for loose objects under the tyre.
func _push_contact_body(force: Vector3) -> void:
	if contact_body == null or not is_instance_valid(contact_body):
		return
	contact_body.sleeping = false
	contact_body.apply_force(force, contact_point - contact_body.global_position)


## Rigid contact along [param normal] at [param point], like a physics solver:
## removes the velocity that drives the wheel into the obstacle and pushes the
## penetration out. Lifts the car onto a step or stops it against a wall.
func _apply_hard_contact(
		delta: float,
		body: RigidBody3D,
		body_state: PhysicsDirectBodyState3D,
		point: Vector3,
		normal: Vector3,
		depth: float) -> void:
	var rel := point - body.global_position
	var normal_speed := (body_state.get_velocity_at_local_position(rel)
			- _contact_velocity(contact_point)).dot(normal)
	var target_speed := minf(depth * hard_contact_correction, max_correction_speed)
	var speed_change := target_speed - normal_speed
	if speed_change <= 0.0:
		return
	# Effective mass of the body at this point along the normal (includes rotation).
	var arm := rel - body_state.center_of_mass
	var arm_x_n := arm.cross(normal)
	var inv_mass := body_state.inverse_mass \
			+ (body_state.inverse_inertia_tensor * arm_x_n).cross(arm).dot(normal)
	# A loose object shares the impulse: a light box gets shoved instead of
	# launching the car over it.
	if contact_body:
		inv_mass += 1.0 / contact_body.mass
	if inv_mass <= 0.0:
		return
	impact_force = speed_change / inv_mass / delta * hard_contact_strength
	body.apply_force(normal * impact_force, rel)
	_push_contact_body(-normal * impact_force)


func _apply_tire_forces(
		delta: float,
		body: RigidBody3D,
		body_state: PhysicsDirectBodyState3D,
		drive_force: float,
		brake_force: float,
		handbrake_on: bool,
		mass_share: float) -> void:
	var forward := -global_basis.z
	forward = (forward - contact_normal * forward.dot(contact_normal)).normalized()
	var right := forward.cross(contact_normal).normalized()

	var rel_contact := contact_point - body.global_position
	# Slip is measured relative to the surface, which may be a moving box.
	var point_velocity := body_state.get_velocity_at_local_position(rel_contact) \
			- _contact_velocity(contact_point)
	var long_speed := point_velocity.dot(forward)
	var lat_speed := point_velocity.dot(right)

	# Mass that has to change speed: our share of the car, or (on a loose box)
	# the reduced mass of car share + box, so a light box doesn't get launched.
	var effective_mass := mass_share
	if contact_body:
		effective_mass = mass_share * contact_body.mass / (mass_share + contact_body.mass)

	# Lateral: cancel part of the sideways slide this tick.
	var grip := handbrake_lateral_grip if handbrake_on else lateral_grip
	var lat_force := -lat_speed * effective_mass * grip / delta

	# Longitudinal: engine, brakes (never strong enough to reverse), rolling drag.
	var long_force := drive_force - long_speed * rolling_resistance
	if brake_force > 0.0:
		var stop_force := absf(long_speed) * effective_mass / delta
		long_force -= signf(long_speed) * minf(brake_force, stop_force)

	# Friction circle: combined force limited by load * friction.
	var tire_force := Vector2(long_force, lat_force)
	var max_force := suspension_force * tire_friction
	is_slipping = tire_force.length() > max_force
	if is_slipping:
		tire_force = tire_force.limit_length(max_force)

	var tire_vector := forward * tire_force.x + right * tire_force.y
	body.apply_force(tire_vector, rel_contact)
	_push_contact_body(-tire_vector)


func _update_air_spin(delta: float, drive_force: float, handbrake_on: bool) -> void:
	if handbrake_on:
		spin_speed = 0.0
	elif is_drive and not is_zero_approx(drive_force):
		spin_speed = clampf(spin_speed + signf(drive_force) * 40.0 * delta, -120.0, 120.0)
	else:
		spin_speed = move_toward(spin_speed, 0.0, 3.0 * delta)
	_spin_angle = wrapf(_spin_angle - spin_speed * delta, -PI, PI)


func _update_visual() -> void:
	if _visual_root and not _syncs_visual():
		_visual_root.position = Vector3(0.0, -suspension_length, 0.0)
	if _visual_spin:
		_visual_spin.rotation.x = _spin_angle


# --- Per-frame visual placement ---------------------------------------------

func _process(_delta: float) -> void:
	if not _syncs_visual() or not _visual_root:
		return
	_visual_root.position = Vector3(0.0, -_visual_suspension_length(), 0.0)


func _syncs_visual() -> bool:
	return sync_visual_every_frame and _query_body != null and not Engine.is_editor_hint()


## Same sweep as the physics, but from the transform that is actually drawn
## this frame. Only moves the mesh; it never touches the physics state.
func _visual_suspension_length() -> float:
	var xform := get_global_transform_interpolated()
	var up := xform.basis.y.normalized()
	var space := get_world_3d().direct_space_state
	_visual_query.exclude = _query.exclude
	_visual_query.collision_mask = collision_mask
	_visual_query.transform = xform
	_visual_query.motion = Vector3.ZERO
	if not space.intersect_shape(_visual_query, 1).is_empty():
		# Start is blocked (rare): fall back to the physics result.
		return -overcompression if overcompression > 0.0 else suspension_length
	var sweep_length := cast_headroom + suspension_travel
	_visual_query.motion = -up * sweep_length
	var fractions := space.cast_motion(_visual_query)
	var length := sweep_length * fractions[0] - cast_headroom
	return clampf(length, -max_visual_overlift, suspension_travel)


# --- Shape / visual generation ----------------------------------------------

func _queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_queued = false
	target_position = Vector3(0.0, -(cast_headroom + suspension_travel), 0.0)
	shape = _make_wheel_shape()
	_query.shape = shape
	_query.margin = 0.0
	_visual_query.shape = shape
	_visual_query.margin = 0.0
	_build_visual()
	_update_visual()


## Builds a convex hull shaped like a tyre, with its axle along local X, centred
## [member cast_headroom] above the node origin (the start of the sweep).
## (A CylinderShape3D has its axis along Y, which would need the whole
## ShapeCast3D node rotated; a hull keeps the node aligned with the car.)
func _make_wheel_shape() -> ConvexPolygonShape3D:
	var points := PackedVector3Array()
	var half_width := wheel_width * 0.5
	# Push the polygon out slightly so its flats sit on the true radius on average.
	var radius := wheel_radius / cos(PI / float(shape_segments) * 0.5)
	for i in shape_segments:
		var angle := TAU * float(i) / float(shape_segments)
		var y := cast_headroom + cos(angle) * radius
		var z := sin(angle) * radius
		points.append(Vector3(-half_width, y, z))
		points.append(Vector3(half_width, y, z))
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	return hull


## Uses [param node] as the wheel visual (the wheel takes ownership of it).
## [param xform] places it relative to the wheel centre.
func set_custom_visual(node: Node3D, xform: Transform3D = Transform3D.IDENTITY) -> void:
	if is_instance_valid(_custom_visual) and _custom_visual != node:
		_custom_visual.queue_free()
	_custom_visual = node
	_custom_visual_from_scene = false
	visual_transform = xform
	_queue_rebuild()


## Shows the wheel at [param length] below the mount (editor preview / rest pose).
func set_preview_suspension_length(length: float) -> void:
	suspension_length = clampf(length, 0.0, suspension_travel)
	compression = suspension_travel - suspension_length
	_update_visual()


## Removes the collider this wheel added to the vehicle body.
func free_collider() -> void:
	if is_instance_valid(_collider):
		_collider.get_parent().remove_child(_collider)
		_collider.queue_free()
	_collider = null


func _build_visual() -> void:
	# Keep a custom visual alive while the old visual tree is freed.
	if is_instance_valid(_custom_visual) and _custom_visual.get_parent():
		_custom_visual.get_parent().remove_child(_custom_visual)
	if _visual_root:
		_visual_root.queue_free()
	# Internal children are not saved with the scene and don't show in the dock.
	_visual_root = Node3D.new()
	_visual_root.name = "WheelVisual"
	# Placed every rendered frame from the interpolated transform (see _process),
	# so it must not be interpolated a second time. The spin still is.
	_visual_root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_visual_root, false, Node.INTERNAL_MODE_BACK)

	_visual_spin = Node3D.new()
	_visual_spin.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	_visual_root.add_child(_visual_spin)

	# Custom wheel model: from visual_scene, or a node handed over by the builder.
	if visual_scene and (not is_instance_valid(_custom_visual) or _custom_visual_from_scene):
		if is_instance_valid(_custom_visual):
			_custom_visual.queue_free()
		_custom_visual = visual_scene.instantiate() as Node3D
		_custom_visual_from_scene = true
	if is_instance_valid(_custom_visual):
		_custom_visual.transform = visual_transform
		_visual_spin.add_child(_custom_visual)
		return

	var tyre_material := StandardMaterial3D.new()
	tyre_material.albedo_color = Color(0.08, 0.08, 0.09)
	tyre_material.roughness = 0.9

	var tyre_mesh := CylinderMesh.new()
	tyre_mesh.top_radius = wheel_radius
	tyre_mesh.bottom_radius = wheel_radius
	tyre_mesh.height = wheel_width
	tyre_mesh.radial_segments = 32
	tyre_mesh.material = tyre_material

	var tyre := MeshInstance3D.new()
	tyre.mesh = tyre_mesh
	tyre.rotation.z = PI * 0.5
	_visual_spin.add_child(tyre)

	# Two spokes poking out of the tyre sides so wheel rotation is visible.
	var rim_material := StandardMaterial3D.new()
	rim_material.albedo_color = Color(0.8, 0.8, 0.82)
	rim_material.metallic = 0.7
	rim_material.roughness = 0.3
	for i in 2:
		var spoke_mesh := BoxMesh.new()
		spoke_mesh.size = Vector3(wheel_width + 0.02, wheel_radius * 1.3, 0.07)
		spoke_mesh.material = rim_material
		var spoke := MeshInstance3D.new()
		spoke.mesh = spoke_mesh
		spoke.rotation.x = PI * 0.5 * i
		_visual_spin.add_child(spoke)


# --- Solid wheel ----------------------------------------------------------

## Adds the wheel's collision shape to the vehicle body (a shape of the body
## itself, so collisions push the whole vehicle correctly).
func _create_collider() -> void:
	var body := get_parent() as CollisionObject3D
	if body == null or is_instance_valid(_collider):
		return
	var cylinder := CylinderShape3D.new()
	cylinder.radius = wheel_radius * collider_radius_scale
	cylinder.height = wheel_width
	_collider = CollisionShape3D.new()
	_collider.name = "%sCollider" % name
	_collider.shape = cylinder
	body.add_child(_collider)
	_collider_transform = Transform3D()
	_update_collider()


## Moves the collider with the suspension and steering. The collider is a bit
## smaller than the tyre and lifted, so it keeps [member collider_ground_clearance]
## above the ground under the tyre.
func _update_collider() -> void:
	if not is_instance_valid(_collider):
		return
	var collider_radius := wheel_radius * collider_radius_scale
	var lift := collider_ground_clearance - (wheel_radius - collider_radius)
	# Cylinder axis (Y) turned onto the axle (X).
	var basis_in_body := transform.basis * Basis(Vector3.BACK, PI * 0.5)
	var origin_in_body := position + transform.basis * Vector3(0.0, -suspension_length + lift, 0.0)
	var new_transform := Transform3D(basis_in_body, origin_in_body)
	# Changing a body's shapes has a cost; skip sub-millimetre changes.
	if new_transform.origin.distance_squared_to(_collider_transform.origin) < 1e-6 \
			and new_transform.basis.is_equal_approx(_collider_transform.basis):
		return
	_collider_transform = new_transform
	_collider.transform = new_transform
