@tool
class_name VehicleRoad
extends Path3D
## A road along this node's curve: asphalt, lane markings and collision,
## regenerated whenever the curve changes (also while editing it in the editor).
##
## Edit the road like any Path3D: select it and use the curve tools in the 3D
## toolbar (add / move points, drag the handles). For a loop, enable the
## curve's "closed" option (if your Godot version has it) or put the last
## point on top of the first one.
##
## Roads form a network: end a road near a [VehicleRoadJunction] and the
## junction connects it to the other roads ending there. [VehicleAIDriver]
## drives the network: the right-hand lane in either direction (or only along
## the curve for one-way roads), choosing left / straight / right at junctions.
## The generated nodes are never saved with the scene.

const GROUP := &"vehicle_roads"

## Total width of the asphalt.
@export_range(2.0, 40.0, 0.1, "suffix:m") var width: float = 8.0:
	set(value):
		width = value
		_queue_build()
## Lanes per direction (one-way roads: lanes in total).
@export_range(1, 4) var lanes_per_direction: int = 1:
	set(value):
		lanes_per_direction = value
		_queue_build()
## Traffic in both directions. Off = only along the curve's direction.
@export var two_way: bool = true:
	set(value):
		two_way = value
		_queue_build()
## The surface is raised this much above the curve (avoids flickering with the ground).
@export_range(0.0, 0.5, 0.005, "suffix:m") var surface_height: float = 0.02:
	set(value):
		surface_height = value
		_queue_build()
## Length of one mesh segment. Smaller = smoother curves, more triangles.
@export_range(0.25, 10.0, 0.05, "suffix:m") var segment_length: float = 1.0:
	set(value):
		segment_length = value
		_queue_build()

@export_group("Look")
@export var asphalt_color: Color = Color(0.17, 0.17, 0.18):
	set(value):
		asphalt_color = value
		_queue_build()
@export var marking_color: Color = Color(0.92, 0.92, 0.88):
	set(value):
		marking_color = value
		_queue_build()
@export_range(0.05, 0.5, 0.01, "suffix:m") var marking_width: float = 0.15:
	set(value):
		marking_width = value
		_queue_build()
## Dash length (and gap) of the lane lines.
@export_range(0.5, 20.0, 0.1, "suffix:m") var dash_length: float = 3.0:
	set(value):
		dash_length = value
		_queue_build()

@export_group("Collision")
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
var _lane_cache: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP)
	curve_changed.connect(_queue_build)
	_build()


## Whether the curve forms a loop (closed, or last point on the first one).
func is_loop() -> bool:
	if curve == null or curve.point_count < 2:
		return false
	if curve.get(&"closed") == true:
		return true
	var first := curve.get_point_position(0)
	var last := curve.get_point_position(curve.point_count - 1)
	return first.distance_to(last) < 0.5


## Sideways offset of a lane's centre from the centre line, to the right of the
## driving direction. Lane 0 is the one next to the centre line.
func get_lane_offset(lane: int = 0) -> float:
	if not two_way:
		var one_way_lane := width / lanes_per_direction
		return -width * 0.5 + one_way_lane * (clampi(lane, 0, lanes_per_direction - 1) + 0.5)
	var lane_width := width * 0.5 / lanes_per_direction
	return lane_width * (clampi(lane, 0, lanes_per_direction - 1) + 0.5)


## Centre line of a lane in world space, in its driving direction:
## [param forward] = along the curve, otherwise against it (two-way roads).
func get_lane_curve(forward: bool = true, lane: int = 0) -> Curve3D:
	var key := "%s/%d" % [forward, lane]
	if _lane_cache.has(key):
		return _lane_cache[key]
	var lane_curve := Curve3D.new()
	lane_curve.bake_interval = 0.5
	if curve == null or curve.point_count < 2:
		return lane_curve
	var length := curve.get_baked_length()
	var steps := maxi(2, ceili(length))
	var side := get_lane_offset(lane)
	for i in steps + 1:
		var along := length * i / steps
		var offset := along if forward else length - along
		var direction := _tangent(offset, length) * (1.0 if forward else -1.0)
		var right := direction.cross(Vector3.UP).normalized()
		var point := curve.sample_baked(offset, true) + right * side + Vector3.UP * surface_height
		lane_curve.add_point(global_transform * point)
	_lane_cache[key] = lane_curve
	return lane_curve


## One end of the road, in world space: {"position", "heading_out"} where
## heading_out points from that end into the road.
func get_end(at_start: bool) -> Dictionary:
	var length := curve.get_baked_length() if curve else 0.0
	var offset := 0.0 if at_start else length
	var direction := _tangent(offset, length) * (1.0 if at_start else -1.0)
	return {
		"position": global_transform * curve.sample_baked(offset, true),
		"heading_out": (global_transform.basis * direction).normalized(),
	}


## Flat direction of the curve at [param offset].
func _tangent(offset: float, length: float) -> Vector3:
	var ahead := curve.sample_baked(minf(offset + 0.5, length), true)
	var behind := curve.sample_baked(maxf(offset - 0.5, 0.0), true)
	var tangent := ahead - behind
	tangent.y = 0.0
	return tangent.normalized() if tangent.length_squared() > 0.000001 else Vector3.FORWARD


func _queue_build() -> void:
	if _build_queued or not is_inside_tree():
		return
	_build_queued = true
	_build.call_deferred()


func _build() -> void:
	_build_queued = false
	_lane_cache.clear()
	for node in _generated:
		if is_instance_valid(node):
			node.queue_free()
	_generated.clear()
	if curve == null or curve.point_count < 2 or curve.get_baked_length() < 0.5:
		return

	# Sample the centre line and its sideways direction.
	var length := curve.get_baked_length()
	var steps := maxi(2, ceili(length / segment_length))
	var points: Array[Vector3] = []
	var rights: Array[Vector3] = []
	for i in steps + 1:
		var offset := length * i / steps
		points.append(curve.sample_baked(offset, true) + Vector3.UP * surface_height)
		rights.append(_tangent(offset, length).cross(Vector3.UP).normalized())
	if is_loop():
		# Seamless join: same point and direction at both ends.
		var joined := (rights[0] + rights[steps]).normalized()
		rights[0] = joined
		rights[steps] = joined
		points[steps] = points[0]

	var half := width * 0.5
	var asphalt := SurfaceTool.new()
	asphalt.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in steps:
		_quad(asphalt, points, rights, i, -half, half, 0.0)
	var asphalt_mesh := asphalt.commit()
	_mesh_instance("Asphalt", asphalt_mesh, asphalt_color)

	# Markings: solid edge lines, dashed lines between lanes and at the centre.
	var markings := SurfaceTool.new()
	markings.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inset := 0.3 + marking_width * 0.5
	_marking(markings, points, rights, -half + inset, false)
	_marking(markings, points, rights, half - inset, false)
	var lane_count := lanes_per_direction * (2 if two_way else 1)
	var lane_width := width / lane_count
	for i in range(1, lane_count):
		_marking(markings, points, rights, -half + i * lane_width, true)
	_mesh_instance("Markings", markings.commit(), marking_color)

	if generate_collision:
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(asphalt_mesh.get_faces())
		var body := StaticBody3D.new()
		body.name = "RoadCollision"
		body.collision_layer = collision_layer
		body.collision_mask = 0
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		_add(body)


## Quad between sample i and i + 1, from sideways offset [param from] to [param to].
func _quad(surface: SurfaceTool, points: Array[Vector3], rights: Array[Vector3], i: int,
		from: float, to: float, lift: float) -> void:
	var up := Vector3.UP * lift
	var a := points[i] + rights[i] * from + up
	var b := points[i] + rights[i] * to + up
	var c := points[i + 1] + rights[i + 1] * from + up
	var d := points[i + 1] + rights[i + 1] * to + up
	for vertex: Vector3 in [a, b, c, b, d, c]:
		surface.set_normal(Vector3.UP)
		surface.add_vertex(vertex)


func _marking(surface: SurfaceTool, points: Array[Vector3], rights: Array[Vector3],
		offset: float, dashed: bool) -> void:
	var distance := 0.0
	for i in points.size() - 1:
		if not dashed or fmod(distance, dash_length * 2.0) < dash_length:
			_quad(surface, points, rights, i, offset - marking_width * 0.5,
					offset + marking_width * 0.5, 0.005)
		distance += points[i].distance_to(points[i + 1])


func _mesh_instance(node_name: String, mesh: Mesh, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var view := MeshInstance3D.new()
	view.name = node_name
	view.mesh = mesh
	view.material_override = material
	_add(view)


## Generated nodes are internal and unowned: never saved with the scene.
func _add(node: Node) -> void:
	add_child(node, false, Node.INTERNAL_MODE_BACK)
	_generated.append(node)
