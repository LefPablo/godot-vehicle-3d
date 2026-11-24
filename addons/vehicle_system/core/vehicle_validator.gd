@tool
class_name VehicleValidator
extends RefCounted
## Checks a [VehicleDefinition] for mistakes and reports useful numbers
## (static wheel loads, suspension sag, damping ratios, ride height...).

enum Level { INFO, WARNING, ERROR }


## [{"level": Level, "text": String}]
static func validate(definition: VehicleDefinition) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	if definition == null:
		issues.append(_issue(Level.ERROR, "No definition."))
		return issues
	if definition.id.strip_edges() == "" or definition.id.validate_filename() != definition.id:
		issues.append(_issue(Level.ERROR, "id '%s' must be a non-empty, file-name-safe string." % definition.id))

	var entries := definition.expanded_wheels()
	if entries.is_empty():
		issues.append(_issue(Level.ERROR, "The vehicle has no wheels."))
		return issues

	# Names must be unique (other systems find nodes by name).
	var names := {}
	for entry in entries:
		if names.has(entry.name):
			issues.append(_issue(Level.ERROR, "Two wheels are called '%s'." % entry.name))
		names[entry.name] = true
		if entry.config.mirror and absf(entry.config.position.x) < 0.01:
			issues.append(_issue(Level.WARNING,
					"Wheel '%s' is mirrored but sits on the centre line (x = 0)." % entry.config.name))
		if entry.config.suspension == null or entry.config.tire == null:
			issues.append(_issue(Level.ERROR, "Wheel '%s' needs suspension and tire settings." % entry.name))
			return issues
	for point in definition.mount_points:
		if point == null:
			continue
		if names.has(point.get_node_name()):
			issues.append(_issue(Level.ERROR, "Node name '%s' is used twice." % point.get_node_name()))
		names[point.get_node_name()] = true

	# Function.
	var drive_count := 0
	var steer_count := 0
	for entry in entries:
		drive_count += int(entry.config.drive)
		steer_count += int(entry.config.steering)
	var engine := definition.engine
	if definition.player_controllable:
		if engine and engine.engine_force > 0.0 and drive_count == 0:
			issues.append(_issue(Level.WARNING, "Engine force is set but no wheel has 'drive'."))
		if steer_count == 0:
			issues.append(_issue(Level.WARNING, "No wheel has 'steering'."))
	if definition.colliders.is_empty() and definition.collision_scene == null \
			and definition.auto_collision == VehicleDefinition.AutoCollision.NONE:
		issues.append(_issue(Level.WARNING, "No body colliders: the body will pass through walls."))
	if definition.collision_scene and VehicleBuilder.collision_scene_shapes(definition).is_empty():
		issues.append(_issue(Level.WARNING, "The collision scene has no CollisionShape3D or mesh nodes."))
	if definition.category == "trailer" \
			and definition.get_mount_point(VehicleMountPoint.Kind.TRAILER_COUPLER) == null:
		issues.append(_issue(Level.WARNING, "Trailer without a TRAILER_COUPLER mount point can't be hitched."))

	# Centre of mass inside the wheel footprint?
	var min_corner := Vector2(INF, INF)
	var max_corner := Vector2(-INF, -INF)
	for entry in entries:
		var p: Vector3 = entry.position
		min_corner = min_corner.min(Vector2(p.x, p.z))
		max_corner = max_corner.max(Vector2(p.x, p.z))
	var com := definition.center_of_mass
	if com.x < min_corner.x or com.x > max_corner.x:
		issues.append(_issue(Level.WARNING, "Centre of mass is outside the track width."))
	# Springs centred under the mass? Otherwise the vehicle leans at rest
	# (e.g. a single wheel on one side of an axle: a mirror that was switched off).
	var stiffness_sum := 0.0
	var stiffness_x := 0.0
	for entry in entries:
		var k: float = entry.config.suspension.spring_stiffness
		var wheel_position: Vector3 = entry.position
		stiffness_sum += k
		stiffness_x += k * wheel_position.x
	var track_width := max_corner.x - min_corner.x
	if stiffness_sum > 0.0 and track_width > 0.01:
		var support_x := stiffness_x / stiffness_sum
		if absf(support_x - com.x) > track_width * 0.1:
			issues.append(_issue(Level.WARNING,
					"The springs are off-centre (support at x = %.2f, centre of mass at x = %.2f): " % [
					support_x, com.x] + "the vehicle leans to one side. Is a wheel missing its mirror?"))
	if (com.z < min_corner.y or com.z > max_corner.y) \
			and definition.get_mount_point(VehicleMountPoint.Kind.TRAILER_COUPLER) == null:
		issues.append(_issue(Level.WARNING, "Centre of mass is outside the wheelbase (the vehicle will tip)."))

	# Model wheel nodes.
	var needs_model := false
	for entry in entries:
		var model_path: NodePath = entry.model_node
		if not model_path.is_empty():
			needs_model = true
	if needs_model:
		if definition.model == null:
			issues.append(_issue(Level.ERROR, "Wheels use model nodes but there is no model."))
		else:
			var model := definition.model.instantiate()
			for entry in entries:
				var path: NodePath = entry.model_node
				if not path.is_empty() and model.get_node_or_null(path) == null:
					issues.append(_issue(Level.ERROR, "Model has no node '%s' (wheel %s)." % [path, entry.name]))
			model.free()

	# Suspension at rest.
	var sag := definition.estimate_static_sag()
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var suspension: VehicleSuspensionConfig = entry.config.suspension
		var load_n := sag[i] * suspension.spring_stiffness
		var ratio := sag[i] / suspension.travel if suspension.travel > 0.0 else 1.0
		var sprung_mass := load_n / 9.81
		var critical := 2.0 * sqrt(maxf(suspension.spring_stiffness * sprung_mass, 0.0))
		var damping := 0.5 * (suspension.damping_compression + suspension.damping_rebound)
		var damping_ratio := damping / critical if critical > 0.0 else 0.0
		var frequency := sqrt(suspension.spring_stiffness / sprung_mass) / TAU if sprung_mass > 0.0 else 0.0
		issues.append(_issue(Level.INFO,
				"%s: load %.0f N, sag %.3f m (%d%% of travel), %.2f Hz, damping ratio %.2f" % [
				entry.name, load_n, sag[i], roundi(ratio * 100.0), frequency, damping_ratio]))
		if ratio >= 0.95:
			issues.append(_issue(Level.WARNING,
					"%s bottoms out at rest: raise spring_stiffness or travel." % entry.name))
		elif ratio < 0.1 and load_n > 0.0:
			issues.append(_issue(Level.WARNING, "%s: very stiff spring (sag under 10%% of travel)." % entry.name))
		if damping_ratio > 0.0 and (damping_ratio < 0.1 or damping_ratio > 1.5):
			issues.append(_issue(Level.WARNING,
					"%s: damping ratio %.2f is unusual (0.2 - 0.8 is typical)." % [entry.name, damping_ratio]))

	# Cargo spaces and suspension at full payload.
	var cargo_names := {}
	for space in definition.cargo_spaces:
		if space == null:
			continue
		if cargo_names.has(space.name) or names.has(space.name):
			issues.append(_issue(Level.ERROR, "Node name '%s' is used twice." % space.name))
		cargo_names[space.name] = true
		if space.size.x <= 0.0 or space.size.y <= 0.0 or space.size.z <= 0.0:
			issues.append(_issue(Level.ERROR, "Cargo space '%s' has an empty size." % space.name))
		issues.append(_issue(Level.INFO, "Cargo '%s': %.2f x %.2f x %.2f m (%.2f m^3), max %s, takes %s" % [
				space.name, space.size.x, space.size.y, space.size.z, space.get_volume(),
				"%.0f kg" % space.max_mass if space.max_mass > 0.0 else "unlimited",
				", ".join(space.accepted_tags) if not space.accepted_tags.is_empty() else "anything"]))
	var payload := definition.get_payload_capacity()
	if payload > 0.0:
		var loaded_sag := definition.estimate_static_sag(payload, definition.get_payload_center())
		for i in entries.size():
			var travel: float = entries[i].config.suspension.travel
			var ratio := loaded_sag[i] / travel if travel > 0.0 else 1.0
			if ratio >= 0.95:
				issues.append(_issue(Level.WARNING,
						"%s bottoms out with the full payload (%.0f kg): stiffer springs or a lower max_mass." % [
						entries[i].name, payload]))
		issues.append(_issue(Level.INFO, "Full payload %.0f kg: sag %s" % [payload,
				_sag_list(entries, loaded_sag)]))

	# Summary.
	var wheelbase := max_corner.y - min_corner.y
	var track := max_corner.x - min_corner.x
	var accel := engine.engine_force / definition.mass if engine else 0.0
	issues.append(_issue(Level.INFO, "%d wheels (%d driven, %d steered), wheelbase %.2f m, track %.2f m" % [
			entries.size(), drive_count, steer_count, wheelbase, track]))
	issues.append(_issue(Level.INFO, "Ride height (origin above ground) ~%.2f m, max acceleration ~%.1f m/s^2" % [
			definition.estimate_ride_height(), accel]))
	return issues


static func has_errors(issues: Array[Dictionary]) -> bool:
	for issue in issues:
		if issue.level == Level.ERROR:
			return true
	return false


## BBCode report (errors first).
static func report_bbcode(definition: VehicleDefinition) -> String:
	var issues := validate(definition)
	issues.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.level > b.level)
	var lines := PackedStringArray()
	var title := definition.display_name if definition else "?"
	lines.append("[b]%s[/b]" % title)
	for issue in issues:
		match issue.level:
			Level.ERROR:
				lines.append("[color=#ff6b6b]ERROR[/color]  %s" % issue.text)
			Level.WARNING:
				lines.append("[color=#ffc14d]WARN[/color]   %s" % issue.text)
			_:
				lines.append("[color=#9aa4b2]%s[/color]" % issue.text)
	return "\n".join(lines)


static func _issue(level: Level, text: String) -> Dictionary:
	return {"level": level, "text": text}


static func _sag_list(entries: Array[Dictionary], sag: PackedFloat32Array) -> String:
	var parts := PackedStringArray()
	for i in entries.size():
		var travel: float = entries[i].config.suspension.travel
		parts.append("%s %d%%" % [entries[i].name, roundi(sag[i] / travel * 100.0) if travel > 0.0 else 100])
	return ", ".join(parts)
