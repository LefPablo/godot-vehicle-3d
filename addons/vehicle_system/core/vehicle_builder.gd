@tool
class_name VehicleBuilder
extends RefCounted
## Turns a [VehicleDefinition] into the parts of a [ShapeCastVehicle]:
## model, collision shapes, wheels, mount-point markers and cargo bays.
##
## Generated nodes have no owner (they are never saved with a scene) and are
## tagged with [constant GENERATED_META], so a rebuild can replace them.
## [ShapeCastVehicle] calls this itself when it has a definition; use
## [method create] / [method spawn] to make vehicles from code.

const GENERATED_META := &"vehicle_generated"

const PREVIEW_COLLIDER_COLOR := Color(0.2, 0.85, 1.0)
const PREVIEW_MOUNT_COLOR := Color(1.0, 0.75, 0.2)
const PREVIEW_WHEEL_COLOR := Color(0.4, 1.0, 0.4)
const PREVIEW_COM_COLOR := Color(1.0, 0.3, 0.3)
const PREVIEW_CARGO_COLOR := Color(0.9, 0.6, 1.0)

## Auto-collision shapes are expensive to compute; reuse them per model.
static var _auto_shape_cache := {}


## New vehicle node for [param definition] (built when it enters the tree).
static func create(definition: VehicleDefinition, node_name: String = "") -> ShapeCastVehicle:
	var vehicle := ShapeCastVehicle.new()
	vehicle.name = node_name if node_name != "" else node_name_for(definition)
	vehicle.definition = definition
	return vehicle


## Creates the vehicle, adds it to [param parent] and places it at [param xform]
## (global). Spawned vehicles start parked (no player input, handbrake on).
static func spawn(definition: VehicleDefinition, parent: Node, xform: Transform3D,
		node_name: String = "") -> ShapeCastVehicle:
	var vehicle := create(definition, node_name)
	vehicle.use_player_input = false
	parent.add_child(vehicle, true)
	vehicle.global_transform = xform
	vehicle.reset_physics_interpolation()
	vehicle.set_controls(0.0, 0.0, true)
	return vehicle


static func node_name_for(definition: VehicleDefinition) -> String:
	var base := definition.display_name if definition.display_name != "" else definition.id
	var node_name := base.to_pascal_case().validate_node_name()
	return node_name if node_name != "" else "Vehicle"


# --- Build --------------------------------------------------------------------

## Removes everything a previous build generated.
static func clear(vehicle: ShapeCastVehicle) -> void:
	for child in vehicle.get_children(true):
		if not child.has_meta(GENERATED_META):
			continue
		if child is ShapeCastWheel:
			child.free_collider()
		if child is VehicleCargoBay:
			child.free_boxes()
		vehicle.remove_child(child)
		child.queue_free()


## (Re)generates all parts of [param vehicle] from [param definition].
static func build(vehicle: ShapeCastVehicle, definition: VehicleDefinition) -> void:
	clear(vehicle)
	var entries := definition.expanded_wheels()

	# 1. Model. Wheel nodes named in the wheel configs are taken out of it.
	var model := _instantiate_model(definition)
	var wheel_visuals := _take_wheel_visuals(model, entries)
	if model:
		_add_generated(vehicle, model)

	# 2. Collision shapes: numeric colliders, the collision scene, auto collision.
	for config in definition.colliders:
		if config == null:
			continue
		var shape_node := CollisionShape3D.new()
		shape_node.name = config.name if config.name != "" else "BodyCollision"
		shape_node.shape = config.create_shape()
		shape_node.transform = config.get_transform()
		_add_generated(vehicle, shape_node)
	for entry in collision_scene_shapes(definition):
		var scene_shape := CollisionShape3D.new()
		scene_shape.name = entry.name
		scene_shape.shape = entry.shape
		scene_shape.transform = entry.transform
		if entry.has("preview_mesh"):
			scene_shape.set_meta(&"preview_mesh", entry.preview_mesh)
		_add_generated(vehicle, scene_shape)
	var auto_shape: Variant = _auto_collision_shape(definition, model)
	if auto_shape:
		var auto_node := CollisionShape3D.new()
		auto_node.name = "ModelCollision"
		auto_node.shape = auto_shape.shape
		auto_node.transform = auto_shape.transform
		_add_generated(vehicle, auto_node)

	# 3. Mount points (TowHookFront, TowHitchRear, Coupler, DriverExit, custom).
	for point in definition.mount_points:
		if point == null:
			continue
		var marker := Marker3D.new()
		marker.name = point.get_node_name()
		marker.transform = point.get_transform()
		if point.marker_size != Vector3.ZERO:
			var mesh := BoxMesh.new()
			mesh.size = point.marker_size
			mesh.material = _metal_material(point.marker_color)
			var mesh_instance := MeshInstance3D.new()
			mesh_instance.name = "Mesh"
			mesh_instance.mesh = mesh
			marker.add_child(mesh_instance)
		_add_generated(vehicle, marker)

	# 4. Cargo bays.
	for space in definition.cargo_spaces:
		if space == null:
			continue
		var bay := VehicleCargoBay.new()
		bay.name = space.name if space.name != "" else "Cargo"
		bay.transform = space.get_transform()
		bay.space = space
		_add_generated(vehicle, bay)

	# 5. Wheels.
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var wheel := ShapeCastWheel.new()
		wheel.name = entry.name
		wheel.position = entry.position
		_apply_wheel(wheel, entry.config)
		var visual: Dictionary = wheel_visuals.get(i, {})
		if visual.is_empty() and entry.config.visual_scene:
			var instance := entry.config.visual_scene.instantiate() as Node3D
			if instance:
				visual = {"node": instance, "basis": Basis.IDENTITY, "flip": true}
		if not visual.is_empty():
			wheel.set_custom_visual(visual.node, _visual_transform(visual, entry))
		_add_generated(vehicle, wheel)

	apply_tuning(vehicle, definition, true)
	vehicle.built_structure_fingerprint = structure_fingerprint(definition)

	if Engine.is_editor_hint():
		_pose_wheels_at_rest(vehicle, definition)
		if vehicle.show_preview_helpers:
			_add_generated(vehicle, _build_preview(vehicle, definition))


## Copies all tuning values (body, engine, brakes, steering, wheels) onto an
## already built vehicle. Returns false if a rebuild is needed instead (the
## wheel layout, model, colliders, mount points or cargo changed).
static func apply_tuning(vehicle: ShapeCastVehicle, definition: VehicleDefinition,
		skip_structure_check: bool = false) -> bool:
	if not skip_structure_check \
			and vehicle.built_structure_fingerprint != structure_fingerprint(definition):
		return false
	var entries := definition.expanded_wheels()
	var wheels: Array[ShapeCastWheel] = []
	for child in vehicle.get_children():
		if child is ShapeCastWheel and child.has_meta(GENERATED_META) \
				and not child.is_queued_for_deletion():
			wheels.append(child)
	if wheels.size() != entries.size():
		return false

	# Body.
	vehicle.mass = definition.mass
	vehicle.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	vehicle.center_of_mass = definition.center_of_mass
	var material := vehicle.physics_material_override
	if material == null or not is_equal_approx(material.friction, definition.body_friction):
		material = PhysicsMaterial.new()
		material.friction = definition.body_friction
		vehicle.physics_material_override = material
	vehicle.collision_layer = definition.collision_layer
	vehicle.collision_mask = definition.collision_mask
	vehicle.anti_roll_stiffness = definition.anti_roll_stiffness
	vehicle.air_drag = definition.air_drag
	vehicle.camera_distance = definition.camera_distance
	vehicle.camera_look_height = definition.camera_look_height

	var engine := definition.engine if definition.engine else VehicleEngineConfig.new()
	vehicle.engine_force = engine.engine_force
	vehicle.max_speed_kmh = engine.max_speed_kmh
	vehicle.max_reverse_speed_kmh = engine.max_reverse_speed_kmh
	vehicle.power_curve = engine.power_curve
	vehicle.reverse_force_ratio = engine.reverse_force_ratio

	var brakes := definition.brakes if definition.brakes else VehicleBrakeConfig.new()
	vehicle.brake_force = brakes.brake_force
	vehicle.handbrake_force = brakes.handbrake_force

	var steering := definition.steering if definition.steering else VehicleSteeringConfig.new()
	vehicle.max_steer_angle = steering.max_steer_angle
	vehicle.high_speed_steer_angle = steering.high_speed_steer_angle
	vehicle.high_speed_kmh = steering.high_speed_kmh
	vehicle.steer_speed = steering.steer_speed
	vehicle.steer_return_speed = steering.steer_return_speed
	vehicle.ackermann = steering.ackermann

	# Wheels.
	for i in entries.size():
		var wheel := wheels[i]
		if wheel.position != entries[i].position:
			wheel.position = entries[i].position
		_apply_wheel(wheel, entries[i].config)
	return true


## Hash of everything that needs a full rebuild when it changes.
static func structure_fingerprint(definition: VehicleDefinition) -> int:
	var data := VehicleSerializer.to_dict(definition)
	var wheel_keys := ["name", "mirror", "mirror_name", "visual_scene", "model_node",
			"mirror_model_node", "visual_offset", "visual_rotation_degrees",
			"auto_center_visual", "flip_visual_on_left"]
	var wheels := []
	for wheel: Dictionary in data.get("wheels", []):
		var reduced := {}
		for key in wheel_keys:
			reduced[key] = wheel.get(key)
		wheels.append(reduced)
	return [data.get("model"), data.get("model_offset"), data.get("model_rotation_degrees"),
			data.get("model_scale"), data.get("colliders"), data.get("auto_collision"),
			data.get("collision_scene"), data.get("collision_scene_in_model_space"),
			data.get("mount_points"), data.get("cargo_spaces"), wheels].hash()


# --- Wheels -------------------------------------------------------------------

static func _apply_wheel(wheel: ShapeCastWheel, config: VehicleWheelConfig) -> void:
	var suspension := config.suspension if config.suspension else VehicleSuspensionConfig.new()
	var tire := config.tire if config.tire else VehicleTireConfig.new()
	var values := {
		"wheel_radius": config.radius,
		"wheel_width": config.width,
		"shape_segments": config.shape_segments,
		"is_steering": config.steering,
		"steer_ratio": config.steer_ratio,
		"is_drive": config.drive,
		"has_handbrake": config.handbrake,
		"collision_mask": config.collision_mask,
		"solid": config.solid,
		"collider_radius_scale": config.collider_radius_scale,
		"collider_ground_clearance": config.collider_ground_clearance,
		"sync_visual_every_frame": config.sync_visual_every_frame,
		"max_visual_overlift": config.max_visual_overlift,
		"suspension_travel": suspension.travel,
		"cast_headroom": suspension.cast_headroom,
		"spring_stiffness": suspension.spring_stiffness,
		"damping_compression": suspension.damping_compression,
		"damping_rebound": suspension.damping_rebound,
		"bump_stop_length": suspension.bump_stop_length,
		"bump_stop_stiffness": suspension.bump_stop_stiffness,
		"max_damper_speed": suspension.max_damper_speed,
		"contact_normal_influence": suspension.contact_normal_influence,
		"hard_contact_strength": suspension.hard_contact_strength,
		"hard_contact_correction": suspension.hard_contact_correction,
		"max_correction_speed": suspension.max_correction_speed,
		"blocked_push_depth": suspension.blocked_push_depth,
		"tire_friction": tire.friction,
		"lateral_grip": tire.lateral_grip,
		"handbrake_lateral_grip": tire.handbrake_lateral_grip,
		"rolling_resistance": tire.rolling_resistance,
	}
	for property: String in values:
		# Only touch changed values: some setters rebuild the sweep shape.
		if wheel.get(property) != values[property]:
			wheel.set(property, values[property])


## Takes the wheel nodes named in the configs out of the model.
## Returns {wheel index: {"node", "basis" (orientation in vehicle space)}}.
static func _take_wheel_visuals(model: Node3D, entries: Array[Dictionary]) -> Dictionary:
	var result := {}
	if model == null:
		return result
	for i in entries.size():
		var path: NodePath = entries[i].model_node
		if path.is_empty():
			continue
		var node := model.get_node_or_null(path) as Node3D
		if node == null:
			push_warning("Vehicle model has no wheel node '%s' (wheel %s)." % [path, entries[i].name])
			continue
		var vehicle_space := model.transform * _transform_in(node, model)
		node.get_parent().remove_child(node)
		node.owner = null
		node.transform = Transform3D.IDENTITY
		result[i] = {"node": node, "basis": vehicle_space.basis, "flip": false}
	return result


## Places a wheel visual relative to the wheel centre.
static func _visual_transform(visual: Dictionary, entry: Dictionary) -> Transform3D:
	var config: VehicleWheelConfig = entry.config
	var basis: Basis = Basis.from_euler(config.visual_rotation_degrees * (PI / 180.0)) * visual.basis
	if visual.flip and config.flip_visual_on_left and entry.position.x < 0.0:
		basis = Basis(Vector3.UP, PI) * basis
	var origin := config.visual_offset
	if config.auto_center_visual:
		var bounds := _mesh_bounds(visual.node, visual.node)
		if bounds.size != Vector3.ZERO:
			origin -= basis * bounds.get_center()
	return Transform3D(basis, origin)


static func _pose_wheels_at_rest(vehicle: ShapeCastVehicle, definition: VehicleDefinition) -> void:
	var sag := definition.estimate_static_sag()
	var i := 0
	for child in vehicle.get_children():
		if child is ShapeCastWheel and child.has_meta(GENERATED_META) and i < sag.size():
			child.set_preview_suspension_length(child.suspension_travel - sag[i])
			i += 1


# --- Model & collision --------------------------------------------------------

## In the editor, scenes are reloaded by path so a model or collision scene that
## was edited and saved shows up without restarting.
static func _latest(scene: PackedScene) -> PackedScene:
	if scene == null or not Engine.is_editor_hint():
		return scene
	var path := scene.resource_path
	if path == "" or path.contains("::") or not ResourceLoader.exists(path):
		return scene
	var latest := ResourceLoader.load(path) as PackedScene
	return latest if latest else scene


static func _instantiate_model(definition: VehicleDefinition) -> Node3D:
	if definition.model == null:
		return null
	var instance := _latest(definition.model).instantiate()
	var model := instance as Node3D
	if model == null:
		model = Node3D.new()
		model.add_child(instance)
	model.name = "Body"
	model.transform = definition.get_model_transform()
	return model


## Shapes of the definition's collision scene, in vehicle space:
## [{"name", "shape", "transform"}]. CollisionShape3D nodes are used as they
## are; MeshInstance3D nodes become convex hulls (for collision models).
static func collision_scene_shapes(definition: VehicleDefinition) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var scene := _latest(definition.collision_scene)
	if scene == null:
		return result
	var root := scene.instantiate()
	var base := definition.get_model_transform() if definition.collision_scene_in_model_space \
			else Transform3D.IDENTITY
	_collect_collision(root, root, base, result)
	root.free()
	return result


static func _collect_collision(node: Node, root: Node, base: Transform3D,
		result: Array[Dictionary]) -> void:
	for child in node.get_children():
		if child is CollisionShape3D:
			if child.shape and not child.disabled:
				result.append({"name": String(child.name), "shape": child.shape,
						"transform": base * _transform_in(child, root)})
		elif child is MeshInstance3D and child.mesh:
			var hull := child.mesh.create_convex_shape(true, true) as ConvexPolygonShape3D
			if hull:
				result.append({"name": String(child.name) + "Hull", "shape": hull,
						"transform": base * _transform_in(child, root), "preview_mesh": child.mesh})
		_collect_collision(child, root, base, result)


## Auto collision shape of the definition, computed from its model (wheel
## nodes excluded): {"shape", "transform"} or null.
static func compute_auto_collision(definition: VehicleDefinition) -> Variant:
	var model := _instantiate_model(definition)
	if model == null:
		return null
	var wheel_visuals := _take_wheel_visuals(model, definition.expanded_wheels())
	var result: Variant = _auto_collision_shape(definition, model)
	for visual: Dictionary in wheel_visuals.values():
		visual.node.free()
	model.free()
	return result


## {"shape", "transform"} for the definition's auto collision, or null.
static func _auto_collision_shape(definition: VehicleDefinition, model: Node3D) -> Variant:
	if definition.auto_collision == VehicleDefinition.AutoCollision.NONE or model == null:
		return null
	var key := [definition.model.get_instance_id(), definition.auto_collision,
			definition.get_model_transform(), model.get_child_count()].hash()
	if _auto_shape_cache.has(key):
		return _auto_shape_cache[key]
	var result: Variant = null
	if definition.auto_collision == VehicleDefinition.AutoCollision.MODEL_BOUNDING_BOX:
		var bounds := _mesh_bounds(model, model)
		if bounds.size != Vector3.ZERO:
			bounds = model.transform * bounds
			var box := BoxShape3D.new()
			box.size = bounds.size
			result = {"shape": box, "transform": Transform3D(Basis.IDENTITY, bounds.get_center())}
	else:
		var points := PackedVector3Array()
		for mesh_instance in _mesh_instances(model):
			var hull := mesh_instance.mesh.create_convex_shape(true, true) as ConvexPolygonShape3D
			if hull == null:
				continue
			var xform := model.transform * _transform_in(mesh_instance, model)
			for point in hull.points:
				points.append(xform * point)
		if points.size() >= 4:
			var shape := ConvexPolygonShape3D.new()
			shape.points = points
			result = {"shape": shape, "transform": Transform3D.IDENTITY}
	_auto_shape_cache[key] = result
	return result


## Transform of [param node] relative to [param root] (root's own transform excluded).
static func _transform_in(node: Node, root: Node) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var current := node
	while current and current != root:
		if current is Node3D:
			xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform


static func _mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if root is MeshInstance3D and root.mesh:
		result.append(root)
	for child in root.get_children():
		result.append_array(_mesh_instances(child))
	return result


## Bounds of all meshes under [param node], in [param space_root] space.
static func _mesh_bounds(node: Node, space_root: Node) -> AABB:
	var bounds := AABB()
	var first := true
	for mesh_instance in _mesh_instances(node):
		var aabb := _transform_in(mesh_instance, space_root) * mesh_instance.mesh.get_aabb()
		if space_root == mesh_instance:
			aabb = mesh_instance.mesh.get_aabb()
		bounds = aabb if first else bounds.merge(aabb)
		first = false
	return bounds


static func _add_generated(vehicle: Node, node: Node) -> void:
	node.set_meta(GENERATED_META, true)
	vehicle.add_child(node, true)


static func _metal_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.8
	material.roughness = 0.4
	return material


# --- Editor preview -----------------------------------------------------------

## Lines and labels that show colliders, mount points, suspension travel,
## centre of mass and the cargo bed. Drawn on top of the model.
static func _build_preview(vehicle: ShapeCastVehicle, definition: VehicleDefinition) -> Node3D:
	var root := Node3D.new()
	root.name = "DefinitionPreview"
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)

	# Colliders (all generated collision shapes): filled volume + outline.
	var opacity := vehicle.preview_opacity
	for child in vehicle.get_children():
		if child is CollisionShape3D and child.has_meta(GENERATED_META) and child.shape:
			var meshes := _shape_meshes(child.shape)
			var fill: Mesh = meshes.faces
			if fill == null and child.has_meta(&"preview_mesh"):
				fill = child.get_meta(&"preview_mesh")
			if fill and opacity > 0.0:
				var fill_view := MeshInstance3D.new()
				fill_view.mesh = fill
				fill_view.transform = child.transform
				fill_view.material_override = _fill_material(PREVIEW_COLLIDER_COLOR, opacity)
				fill_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(fill_view)
			var shape_view := MeshInstance3D.new()
			shape_view.mesh = meshes.lines
			shape_view.transform = child.transform
			shape_view.material_override = _line_material(PREVIEW_COLLIDER_COLOR)
			root.add_child(shape_view)

	# Wheels: suspension travel from the mount (fully compressed) down.
	for entry in definition.expanded_wheels():
		var mount: Vector3 = entry.position
		var travel: float = entry.config.suspension.travel if entry.config.suspension else 0.0
		_line(lines, PREVIEW_WHEEL_COLOR, mount, mount + Vector3.DOWN * travel)
		_cross(lines, PREVIEW_WHEEL_COLOR, mount, 0.06)
		_cross(lines, PREVIEW_WHEEL_COLOR, mount + Vector3.DOWN * travel, 0.06)
		root.add_child(_label(entry.name, mount + Vector3.UP * 0.12, PREVIEW_WHEEL_COLOR))

	# Mount points with their axes.
	for point in definition.mount_points:
		if point == null:
			continue
		var xform := point.get_transform()
		_line(lines, PREVIEW_MOUNT_COLOR, xform.origin, xform.origin + xform.basis.x * 0.25)
		_line(lines, PREVIEW_MOUNT_COLOR, xform.origin, xform.origin + xform.basis.y * 0.25)
		_line(lines, PREVIEW_MOUNT_COLOR, xform.origin, xform.origin - xform.basis.z * 0.4)
		root.add_child(_label(point.get_node_name(), xform.origin + Vector3.UP * 0.3, PREVIEW_MOUNT_COLOR))

	# Centre of mass.
	_cross(lines, PREVIEW_COM_COLOR, definition.center_of_mass, 0.25)
	root.add_child(_label("COM", definition.center_of_mass + Vector3.UP * 0.2, PREVIEW_COM_COLOR))

	# Cargo spaces with their size and payload.
	for space in definition.cargo_spaces:
		if space == null:
			continue
		var box := BoxShape3D.new()
		box.size = space.size
		var space_xform := space.get_transform() * Transform3D(Basis.IDENTITY, Vector3.UP * space.size.y * 0.5)
		if opacity > 0.0:
			var volume := BoxMesh.new()
			volume.size = space.size
			var volume_view := MeshInstance3D.new()
			volume_view.mesh = volume
			volume_view.transform = space_xform
			volume_view.material_override = _fill_material(PREVIEW_CARGO_COLOR, opacity)
			volume_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(volume_view)
		var bed := MeshInstance3D.new()
		bed.mesh = _shape_meshes(box).lines
		bed.transform = space_xform
		bed.material_override = _line_material(PREVIEW_CARGO_COLOR)
		root.add_child(bed)
		var text := "%s  %.2f x %.2f x %.2f m" % [space.name, space.size.x, space.size.y, space.size.z]
		if space.max_mass > 0.0:
			text += "  max %.0f kg" % space.max_mass
		var top := space.get_transform() * (Vector3.UP * (space.size.y + 0.15))
		root.add_child(_label(text, top, PREVIEW_CARGO_COLOR))

	lines.surface_end()
	var lines_view := MeshInstance3D.new()
	lines_view.mesh = lines
	lines_view.material_override = _line_material(Color.WHITE, true)
	root.add_child(lines_view)
	return root


static func _line(mesh: ImmediateMesh, color: Color, from: Vector3, to: Vector3) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(from)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(to)


static func _cross(mesh: ImmediateMesh, color: Color, at: Vector3, size: float) -> void:
	_line(mesh, color, at - Vector3.RIGHT * size, at + Vector3.RIGHT * size)
	_line(mesh, color, at - Vector3.UP * size, at + Vector3.UP * size)
	_line(mesh, color, at - Vector3.BACK * size, at + Vector3.BACK * size)


## A shape's debug mesh split into its outline (line surfaces) and its filled
## volume (triangle surfaces). Since Godot 4.4 debug meshes contain both; drawing
## the whole mesh with the opaque line material painted the volume solid.
## {"lines": ArrayMesh, "faces": Mesh or null}
static func _shape_meshes(shape: Shape3D) -> Dictionary:
	var lines := ArrayMesh.new()
	var faces := ArrayMesh.new()
	var debug := shape.get_debug_mesh()
	if debug:
		for i in debug.get_surface_count():
			var primitive := debug.surface_get_primitive_type(i)
			if primitive == Mesh.PRIMITIVE_LINES or primitive == Mesh.PRIMITIVE_LINE_STRIP:
				lines.add_surface_from_arrays(primitive, debug.surface_get_arrays(i))
			elif primitive == Mesh.PRIMITIVE_TRIANGLES or primitive == Mesh.PRIMITIVE_TRIANGLE_STRIP:
				faces.add_surface_from_arrays(primitive, debug.surface_get_arrays(i))
	# Older Godot versions only have the lines: build the volume from the shape.
	var fill: Mesh = faces if faces.get_surface_count() > 0 else _fill_mesh(shape)
	return {"lines": lines, "faces": fill}


## Solid mesh matching a collision shape (null for convex hulls).
static func _fill_mesh(shape: Shape3D) -> Mesh:
	if shape is BoxShape3D:
		var box := BoxMesh.new()
		box.size = shape.size
		return box
	if shape is SphereShape3D:
		var sphere := SphereMesh.new()
		sphere.radius = shape.radius
		sphere.height = shape.radius * 2.0
		return sphere
	if shape is CapsuleShape3D:
		var capsule := CapsuleMesh.new()
		capsule.radius = shape.radius
		capsule.height = shape.height
		return capsule
	if shape is CylinderShape3D:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = shape.radius
		cylinder.bottom_radius = shape.radius
		cylinder.height = shape.height
		return cylinder
	return null


## Translucent, unlit, drawn through the model like the outlines.
static func _fill_material(color: Color, opacity: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color, clampf(opacity, 0.0, 1.0))
	material.no_depth_test = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.render_priority = 9
	return material


static func _line_material(color: Color, use_vertex_color: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = color
	material.vertex_color_use_as_albedo = use_vertex_color
	material.render_priority = 10
	return material


static func _label(text: String, at: Vector3, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0008
	label.font_size = 28
	label.outline_size = 8
	label.modulate = color
	label.render_priority = 11
	label.outline_render_priority = 10
	return label
