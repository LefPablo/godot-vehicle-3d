class_name TowRope
extends MeshInstance3D
## A tow rope between two rigid bodies.
##
## A rope can only pull: while the distance between its ends is shorter than
## [member length] it is slack and does nothing. Once stretched it acts like a
## stiff, damped spring on both bodies (applied at the attachment points, so it
## also turns the towed vehicle to follow). The rope is drawn as a tube that sags
## when slack and pulls straight when tight.

## Emitted when the tension exceeds [member break_force]. The rope removes itself.
signal snapped(force: float)

## Rope length. Shorter distances = slack rope.
@export_range(0.5, 20.0, 0.1, "suffix:m") var length: float = 4.0
## Spring rate of the rope when stretched.
@export_range(1000.0, 500000.0, 100.0, "suffix:N/m") var stiffness: float = 60000.0
## Damping of the stretch speed; stops the towed car from bouncing on the rope.
@export_range(0.0, 100000.0, 100.0, "suffix:Ns/m") var damping: float = 8000.0
## Upper limit of the rope force, keeps extreme yanks stable.
@export_range(1000.0, 500000.0, 100.0, "suffix:N") var max_force: float = 60000.0
## The rope snaps above this force. 0 = unbreakable.
@export_range(0.0, 500000.0, 100.0, "suffix:N") var break_force: float = 0.0

@export_group("Look")
@export_range(0.005, 0.2, 0.005, "suffix:m") var radius: float = 0.03
@export_range(2, 64) var segments: int = 20
@export_range(3, 16) var sides: int = 6
@export var color: Color = Color(0.95, 0.62, 0.1)

var body_a: RigidBody3D
var body_b: RigidBody3D
## Attachment points in each body's local space.
var local_a: Vector3
var local_b: Vector3
## Current rope force in N (0 when slack). Read by the HUD.
var tension: float = 0.0
## Current distance between the two attachment points.
var current_distance: float = 0.0

var _immediate := ImmediateMesh.new()
var _material := StandardMaterial3D.new()


## Connects [param a] (point [param point_a], local) to [param b] (point [param point_b]).
func setup(a: RigidBody3D, point_a: Vector3, b: RigidBody3D, point_b: Vector3, rope_length: float) -> void:
	body_a = a
	body_b = b
	local_a = point_a
	local_b = point_b
	length = rope_length


func _ready() -> void:
	# The mesh is built in world space every frame.
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	global_transform = Transform3D.IDENTITY
	mesh = _immediate
	_material.albedo_color = color
	_material.roughness = 0.85
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _physics_process(_delta: float) -> void:
	tension = 0.0
	if not _bodies_valid():
		queue_free()
		return
	var point_a := body_a.global_transform * local_a
	var point_b := body_b.global_transform * local_b
	var offset := point_b - point_a
	current_distance = offset.length()
	if current_distance <= length or current_distance < 0.001:
		return # slack

	var direction := offset / current_distance
	var stretch_speed := (_point_velocity(body_b, point_b) - _point_velocity(body_a, point_a)).dot(direction)
	var force := stiffness * (current_distance - length) + damping * stretch_speed
	if force <= 0.0:
		return # a rope can't push
	force = minf(force, max_force)
	tension = force
	if break_force > 0.0 and force >= break_force:
		snapped.emit(force)
		queue_free()
		return
	body_a.apply_force(direction * force, point_a - body_a.global_position)
	body_b.apply_force(-direction * force, point_b - body_b.global_position)


func _process(_delta: float) -> void:
	if not _bodies_valid():
		return
	# Draw from the interpolated transforms, so the rope matches the drawn cars.
	var point_a := body_a.get_global_transform_interpolated() * local_a
	var point_b := body_b.get_global_transform_interpolated() * local_b
	var distance := point_a.distance_to(point_b)
	# Parabola sag that makes the curve roughly as long as the rope.
	var sag := 0.5 * sqrt(maxf(length * length - distance * distance, 0.0)) + 0.01

	var points := PackedVector3Array()
	for i in segments + 1:
		var t := float(i) / segments
		points.append(point_a.lerp(point_b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t))

	_immediate.clear_surfaces()
	_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	for i in segments:
		_add_tube_segment(points[i], points[i + 1])
	_immediate.surface_end()


func _add_tube_segment(from: Vector3, to: Vector3) -> void:
	var axis := to - from
	if axis.length_squared() < 1e-8:
		return
	axis = axis.normalized()
	var side := axis.cross(Vector3.UP)
	if side.length_squared() < 1e-4:
		side = axis.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(axis)
	for s in sides:
		var angle_0 := TAU * s / sides
		var angle_1 := TAU * (s + 1) / sides
		var n0 := side * cos(angle_0) + up * sin(angle_0)
		var n1 := side * cos(angle_1) + up * sin(angle_1)
		_vertex(from, n0)
		_vertex(to, n0)
		_vertex(to, n1)
		_vertex(from, n0)
		_vertex(to, n1)
		_vertex(from, n1)


func _vertex(center: Vector3, normal: Vector3) -> void:
	_immediate.surface_set_normal(normal)
	_immediate.surface_add_vertex(center + normal * radius)


func _point_velocity(body: RigidBody3D, point: Vector3) -> Vector3:
	var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	return state.get_velocity_at_local_position(point - body.global_position)


func _bodies_valid() -> bool:
	return is_instance_valid(body_a) and is_instance_valid(body_b) \
			and body_a.is_inside_tree() and body_b.is_inside_tree()
