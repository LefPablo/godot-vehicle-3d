@tool
class_name VehicleRoadJunction
extends Node3D
## A crossroads (or T-junction, or any number of roads) for [VehicleRoad]s.
##
## Place it where roads meet and end each road [member radius] metres from the
## junction's centre: every road end within [member radius] +
## [member connect_distance] is connected. The junction draws the asphalt
## between the road ends.
##
## [VehicleAIDriver]s arriving here pick one of the other roads (left,
## straight or right, no U-turns) and follow a smooth turn curve from their
## lane into the new lane.

const GROUP := &"vehicle_road_junctions"

## Distance from the centre to where the roads end. Bigger = wider turns.
@export_range(2.0, 40.0, 0.1, "suffix:m") var radius: float = 8.0:
	set(value):
		radius = value
		_queue_build()
## Extra distance at which road ends still count as connected.
@export_range(0.1, 10.0, 0.1, "suffix:m") var connect_distance: float = 1.5
## Width of the roads (sizes the asphalt patch).
@export_range(2.0, 40.0, 0.1, "suffix:m") var road_width: float = 8.0:
	set(value):
		road_width = value
		_queue_build()
## Slightly below the roads' surface, so the road ends draw on top.
@export_range(0.0, 0.5, 0.001, "suffix:m") var surface_height: float = 0.017:
	set(value):
		surface_height = value
		_queue_build()
@export var asphalt_color: Color = Color(0.17, 0.17, 0.18):
	set(value):
		asphalt_color = value
		_queue_build()
@export var generate_collision: bool = true:
	set(value):
		generate_collision = value
		_queue_build()
@export_flags_3d_physics var collision_layer: int = 1:
	set(value):
		collision_layer = value
		_queue_build()

var _generated: Array[Node] = []
var _build_queued: bool = false
var _legs: Array[Dictionary] = []
var _legs_ready: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	_build()


## Road ends connected here: [{"road", "at_start", "position", "heading_out"}].
## heading_out points from the junction into the road.
func get_legs() -> Array[Dictionary]:
	if _legs_ready and not Engine.is_editor_hint():
		return _legs
	_legs.clear()
	var center := global_position
	for node in get_tree().get_nodes_in_group(VehicleRoad.GROUP):
		var road := node as VehicleRoad
		if road == null or road.curve == null or road.curve.point_count < 2 or road.is_loop():
			continue
		for at_start: bool in [true, false]:
			var end := road.get_end(at_start)
			var position_on_ground: Vector3 = end.position
			var flat := Vector2(position_on_ground.x - center.x, position_on_ground.z - center.z)
			if flat.length() <= radius + connect_distance:
				end["road"] = road
				end["at_start"] = at_start
				_legs.append(end)
	_legs_ready = true
	return _legs


func has_leg(road: Node, at_start: bool) -> bool:
	for leg in get_legs():
		if leg.road == road and leg.at_start == at_start:
			return true
	return false


## Where a vehicle can go after arriving along [param road] at its start
## ([param arrived_at_start]) or end: [{"road", "forward", "kind", "angle"}].
## kind is "left", "straight" or "right"; U-turns are not offered.
func get_exits(road: Node, arrived_at_start: bool) -> Array[Dictionary]:
	var exits: Array[Dictionary] = []
	var heading_in := Vector3.ZERO
	for leg in get_legs():
		if leg.road == road and leg.at_start == arrived_at_start:
			var arriving_out: Vector3 = leg.heading_out
			heading_in = -arriving_out
	if heading_in == Vector3.ZERO:
		return exits
	for leg in get_legs():
		if leg.road == road and leg.at_start == arrived_at_start:
			continue
		# Leaving along the road from its start = driving forward along it.
		var forward: bool = leg.at_start
		var leg_road: VehicleRoad = leg.road
		if not forward and not leg_road.two_way:
			continue
		var heading_out: Vector3 = leg.heading_out
		var angle := atan2(heading_in.cross(heading_out).y, heading_in.dot(heading_out))
		var kind := "straight"
		if absf(angle) > deg_to_rad(35.0):
			kind = "left" if angle > 0.0 else "right"
		exits.append({"road": leg_road, "forward": forward, "kind": kind, "angle": angle})
	return exits


## Smooth path through the junction from one lane end to another lane start.
func make_turn_curve(from_point: Vector3, from_heading: Vector3, to_point: Vector3,
		to_heading: Vector3) -> Curve3D:
	var turn := Curve3D.new()
	turn.bake_interval = 0.25
	var handle := from_point.distance_to(to_point) * 0.45
	turn.add_point(from_point, Vector3.ZERO, from_heading.normalized() * handle)
	turn.add_point(to_point, -to_heading.normalized() * handle, Vector3.ZERO)
	return turn


func _queue_build() -> void:
	if _build_queued or not is_inside_tree():
		return
	_build_queued = true
	_build.call_deferred()


## Round asphalt patch reaching the corners of the road ends.
func _build() -> void:
	_build_queued = false
	for node in _generated:
		if is_instance_valid(node):
			node.queue_free()
	_generated.clear()
	var patch_radius := sqrt(radius * radius + road_width * road_width * 0.25)
	var segments := 48
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3.UP * surface_height
	for i in segments:
		var a := TAU * i / segments
		var b := TAU * (i + 1) / segments
		for vertex: Vector3 in [center, center + Vector3(cos(a), 0.0, sin(a)) * patch_radius,
				center + Vector3(cos(b), 0.0, sin(b)) * patch_radius]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(vertex)
	var mesh := surface.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = asphalt_color
	material.roughness = 0.92
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var view := MeshInstance3D.new()
	view.name = "Asphalt"
	view.mesh = mesh
	view.material_override = material
	_add(view)
	if generate_collision:
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(mesh.get_faces())
		var body := StaticBody3D.new()
		body.name = "JunctionCollision"
		body.collision_layer = collision_layer
		body.collision_mask = 0
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		_add(body)


func _add(node: Node) -> void:
	add_child(node, false, Node.INTERNAL_MODE_BACK)
	_generated.append(node)
