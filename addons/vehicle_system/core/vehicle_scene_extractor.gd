@tool
class_name VehicleSceneExtractor
extends RefCounted
## Creates a [VehicleDefinition] from a hand-built [ShapeCastVehicle] node
## (ShapeCastWheel / CollisionShape3D / marker children, like the original
## vehicle scenes). Useful to convert old scenes, or to place wheels and hooks
## visually with gizmos and then turn the result into a definition.
##
## Children are sorted into:
##   ShapeCastWheel                  -> wheels (left/right twins become one mirrored entry)
##   CollisionShape3D                -> colliders
##   TowHookFront / TowHitchRear /
##   Coupler / DriverExit / Marker3D -> mount points
##   VehicleCargoBay                 -> cargo spaces
##   anything else ("Body", meshes)  -> the model, saved as its own scene


## [param model_path]: where to save the model scene (e.g.
## "res://vehicles/car/car_body.tscn"); "" = no model.
static func extract(vehicle: ShapeCastVehicle, model_path: String = "",
		warnings: Array[String] = []) -> VehicleDefinition:
	var definition := VehicleDefinition.new()
	var node_name := String(vehicle.name)
	definition.id = node_name.to_snake_case()
	definition.display_name = node_name.capitalize()

	# Body physics & tuning.
	definition.mass = vehicle.mass
	if vehicle.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM:
		definition.center_of_mass = vehicle.center_of_mass
	else:
		definition.center_of_mass = Vector3.ZERO
		warnings.append("Centre of mass was automatic; set it in the definition.")
	if vehicle.physics_material_override:
		definition.body_friction = vehicle.physics_material_override.friction
	definition.collision_layer = vehicle.collision_layer
	definition.collision_mask = vehicle.collision_mask
	definition.anti_roll_stiffness = vehicle.anti_roll_stiffness
	definition.air_drag = vehicle.air_drag
	definition.camera_distance = vehicle.camera_distance
	definition.camera_look_height = vehicle.camera_look_height

	definition.engine.engine_force = vehicle.engine_force
	definition.engine.max_speed_kmh = vehicle.max_speed_kmh
	definition.engine.max_reverse_speed_kmh = vehicle.max_reverse_speed_kmh
	definition.engine.power_curve = vehicle.power_curve
	definition.engine.reverse_force_ratio = vehicle.reverse_force_ratio
	definition.brakes.brake_force = vehicle.brake_force
	definition.brakes.handbrake_force = vehicle.handbrake_force
	definition.steering.max_steer_angle = vehicle.max_steer_angle
	definition.steering.high_speed_steer_angle = vehicle.high_speed_steer_angle
	definition.steering.high_speed_kmh = vehicle.high_speed_kmh
	definition.steering.steer_speed = vehicle.steer_speed
	definition.steering.steer_return_speed = vehicle.steer_return_speed
	definition.steering.ackermann = vehicle.ackermann

	var wheels: Array[ShapeCastWheel] = []
	var model_parts: Array[Node3D] = []
	for child in vehicle.get_children():
		if child.has_meta(VehicleBuilder.GENERATED_META):
			continue
		if child is ShapeCastWheel:
			wheels.append(child)
		elif child is CollisionShape3D:
			if String(child.name).ends_with("Collider"):
				continue # runtime collider of a solid wheel
			var collider := VehicleColliderConfig.new()
			collider.name = child.name
			if child.shape and collider.set_from_shape(child.shape, child.transform):
				definition.colliders.append(collider)
			else:
				warnings.append("Collider '%s' has an unsupported shape (skipped)." % child.name)
		elif child is VehicleCargoBay:
			if child.space:
				var space := child.space.duplicate(true) as VehicleCargoSpace
				space.name = child.name
				space.position = child.position
				space.rotation_degrees = child.rotation_degrees
				definition.cargo_spaces.append(space)
		elif child is Marker3D or VehicleMountPoint.kind_for_node_name(child.name) != VehicleMountPoint.Kind.CUSTOM:
			definition.mount_points.append(_mount_point(child))
		elif child is Node3D:
			model_parts.append(child)

	definition.wheels = _wheel_configs(wheels)
	definition.category = "trailer" if definition.get_mount_point(
			VehicleMountPoint.Kind.TRAILER_COUPLER) else "car"
	definition.player_controllable = definition.category != "trailer"

	if model_path != "" and not model_parts.is_empty():
		var scene := _save_model(model_parts, model_path, definition, warnings)
		if scene:
			definition.model = scene
	return definition


# --- Wheels -------------------------------------------------------------------

static func _wheel_configs(wheels: Array[ShapeCastWheel]) -> Array[VehicleWheelConfig]:
	var configs: Array[VehicleWheelConfig] = []
	var suspensions: Array[VehicleSuspensionConfig] = []
	var tires: Array[VehicleTireConfig] = []
	var used: Array[ShapeCastWheel] = []
	for wheel in wheels:
		if wheel in used:
			continue
		used.append(wheel)
		var config := _wheel_config(wheel)
		for other in wheels:
			if other in used or not _is_mirror_twin(wheel, other):
				continue
			used.append(other)
			config.mirror = true
			if config.get_mirror_name() != String(other.name):
				config.mirror_name = other.name
			break
		# Share identical suspension / tyre settings, so they can be tuned together.
		config.suspension = _shared(config.suspension, suspensions)
		config.tire = _shared(config.tire, tires)
		configs.append(config)
	return configs


static func _wheel_config(wheel: ShapeCastWheel) -> VehicleWheelConfig:
	var config := VehicleWheelConfig.new()
	config.name = wheel.name
	config.position = wheel.position
	config.radius = wheel.wheel_radius
	config.width = wheel.wheel_width
	config.shape_segments = wheel.shape_segments
	config.steering = wheel.is_steering
	config.steer_ratio = wheel.steer_ratio
	config.drive = wheel.is_drive
	config.handbrake = wheel.has_handbrake
	config.collision_mask = wheel.collision_mask
	config.solid = wheel.solid
	config.collider_radius_scale = wheel.collider_radius_scale
	config.collider_ground_clearance = wheel.collider_ground_clearance
	config.sync_visual_every_frame = wheel.sync_visual_every_frame
	config.max_visual_overlift = wheel.max_visual_overlift
	config.visual_scene = wheel.visual_scene

	var suspension := VehicleSuspensionConfig.new()
	suspension.travel = wheel.suspension_travel
	suspension.cast_headroom = wheel.cast_headroom
	suspension.spring_stiffness = wheel.spring_stiffness
	suspension.damping_compression = wheel.damping_compression
	suspension.damping_rebound = wheel.damping_rebound
	suspension.bump_stop_length = wheel.bump_stop_length
	suspension.bump_stop_stiffness = wheel.bump_stop_stiffness
	suspension.max_damper_speed = wheel.max_damper_speed
	suspension.contact_normal_influence = wheel.contact_normal_influence
	suspension.hard_contact_strength = wheel.hard_contact_strength
	suspension.hard_contact_correction = wheel.hard_contact_correction
	suspension.max_correction_speed = wheel.max_correction_speed
	suspension.blocked_push_depth = wheel.blocked_push_depth
	config.suspension = suspension

	var tire := VehicleTireConfig.new()
	tire.friction = wheel.tire_friction
	tire.lateral_grip = wheel.lateral_grip
	tire.handbrake_lateral_grip = wheel.handbrake_lateral_grip
	tire.rolling_resistance = wheel.rolling_resistance
	config.tire = tire
	return config


## Same settings, mirrored position (x -> -x).
static func _is_mirror_twin(a: ShapeCastWheel, b: ShapeCastWheel) -> bool:
	var mirrored := Vector3(-a.position.x, a.position.y, a.position.z)
	if absf(a.position.x) < 0.01 or not mirrored.is_equal_approx(b.position):
		return false
	return _settings(_wheel_config(a)) == _settings(_wheel_config(b))


static func _settings(config: VehicleWheelConfig) -> Dictionary:
	var data := VehicleSerializer._object_to_dict(config, "")
	for key in ["name", "position", "mirror", "mirror_name"]:
		data.erase(key)
	return data


static func _shared(resource: Resource, pool: Array) -> Resource:
	var data := VehicleSerializer._object_to_dict(resource, "")
	for existing in pool:
		if VehicleSerializer._object_to_dict(existing, "") == data:
			return existing
	pool.append(resource)
	return resource


# --- Mount points & model -----------------------------------------------------

static func _mount_point(node: Node3D) -> VehicleMountPoint:
	var point := VehicleMountPoint.new()
	point.kind = VehicleMountPoint.kind_for_node_name(node.name)
	if point.kind == VehicleMountPoint.Kind.CUSTOM:
		point.name = node.name
	point.position = node.position
	point.rotation_degrees = node.rotation_degrees
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh:
			point.marker_size = child.mesh.size
			var material := child.mesh.material as StandardMaterial3D
			if material:
				point.marker_color = material.albedo_color
			break
	return point


static func _save_model(parts: Array[Node3D], path: String, definition: VehicleDefinition,
		warnings: Array[String]) -> PackedScene:
	var root: Node3D
	if parts.size() == 1:
		root = parts[0].duplicate() as Node3D
		definition.model_offset = root.position
		definition.model_rotation_degrees = root.rotation_degrees
		definition.model_scale = root.scale
		root.transform = Transform3D.IDENTITY
	else:
		root = Node3D.new()
		root.name = "Body"
		for part in parts:
			root.add_child(part.duplicate())
	own_recursive(root, root)
	var scene := PackedScene.new()
	var error := scene.pack(root)
	root.free()
	if error == OK:
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		error = ResourceSaver.save(scene, path)
	if error != OK:
		warnings.append("Can't save the model to '%s': %s" % [path, error_string(error)])
		return null
	# Reference the saved file (not the in-memory copy), so definitions point to it.
	return ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene


## Makes [param scene_root] the owner of every node below it, except the
## insides of instanced sub-scenes (they stay instances).
static func own_recursive(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		if child.scene_file_path == "":
			own_recursive(child, scene_root)
