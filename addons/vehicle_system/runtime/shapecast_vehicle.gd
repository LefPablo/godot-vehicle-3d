@tool
class_name ShapeCastVehicle
extends RigidBody3D
## Physics car driven by [ShapeCastWheel] children.
##
## The body is a regular RigidBody3D. Each wheel sweeps its own tyre shape
## down its suspension axis and pushes the body with suspension and tyre
## forces. This script only reads input, turns the steering wheels and
## distributes engine / brake force.
##
## Two ways to set a vehicle up:
##  - Data driven: assign a [VehicleDefinition] to [member definition]. The
##    model, colliders, wheels, mount points and cargo are generated from it
##    (also in the editor, as a live preview) and all tuning comes from it.
##  - Hand built: leave [member definition] empty and add ShapeCastWheel,
##    CollisionShape3D and marker children yourself (the original workflow).
##
## Controls (Project Settings > Input Map):
##   move_forward (W), move_backward (S), steer_left (A), steer_right (D),
##   handbrake (Space), reset_vehicle (R)

const ACTION_FORWARD := &"move_forward"
const ACTION_BACKWARD := &"move_backward"
const ACTION_LEFT := &"steer_left"
const ACTION_RIGHT := &"steer_right"
const ACTION_HANDBRAKE := &"handbrake"
const ACTION_RESET := &"reset_vehicle"

## Properties that come from the definition when one is assigned. They are
## then read-only in the inspector and not saved with the scene.
const DEFINITION_PROPERTIES: PackedStringArray = [
	"camera_distance", "camera_look_height", "engine_force", "max_speed_kmh",
	"max_reverse_speed_kmh", "power_curve", "reverse_force_ratio", "brake_force",
	"handbrake_force", "max_steer_angle", "high_speed_steer_angle", "high_speed_kmh",
	"steer_speed", "steer_return_speed", "ackermann", "anti_roll_stiffness", "air_drag",
	"mass", "center_of_mass_mode", "center_of_mass", "physics_material_override",
	"collision_layer", "collision_mask",
]

## Emitted after [method reset_vehicle] put the vehicle back on its wheels.
signal vehicle_reset
## Emitted after the vehicle was (re)built from its [member definition].
signal rebuilt

## Data-driven setup. When set, the vehicle's parts and tuning are generated
## from this resource (see [VehicleBuilder]).
@export var definition: VehicleDefinition:
	set(value):
		if definition == value:
			return
		if definition and definition.changed.is_connected(_on_definition_changed):
			definition.changed.disconnect(_on_definition_changed)
		definition = value
		if definition:
			definition.changed.connect(_on_definition_changed)
		_definition_fingerprint = 0
		notify_property_list_changed()
		if is_inside_tree():
			_queue_rebuild()

## Disable to drive the car from code (see [method set_controls]).
@export var use_player_input: bool = true

@export_group("Definition Preview")
## Editor: draw colliders, mount points, suspension travel and the cargo bed.
@export var show_preview_helpers: bool = true:
	set(value):
		show_preview_helpers = value
		if is_inside_tree() and Engine.is_editor_hint():
			_queue_rebuild()
## Editor: opacity of the filled collision and cargo volumes (0 = outlines only).
@export_range(0.0, 1.0, 0.05) var preview_opacity: float = 0.5:
	set(value):
		preview_opacity = value
		if is_inside_tree() and Engine.is_editor_hint():
			_queue_rebuild()
## Debug builds: pick up changes made to the definition while the game runs
## (e.g. from the Remote scene tree inspector) and apply them live.
@export var live_update: bool = true

@export_group("Camera")
## Chase camera distance used when this vehicle becomes the active one.
@export_range(1.0, 40.0, 0.1, "suffix:m") var camera_distance: float = 7.5
## Height above the vehicle origin the chase camera looks at.
@export_range(-2.0, 5.0, 0.05, "suffix:m") var camera_look_height: float = 0.6

@export_group("Engine")
## Total engine force, split between the drive wheels.
@export_range(0.0, 50000.0, 100.0, "suffix:N") var engine_force: float = 6500.0
@export_range(1.0, 400.0, 1.0, "suffix:km/h") var max_speed_kmh: float = 130.0
@export_range(1.0, 100.0, 1.0, "suffix:km/h") var max_reverse_speed_kmh: float = 30.0
## Optional: X = speed / top speed, Y = force multiplier. Empty = full force up
## to 70% of the top speed, then a smooth fade.
@export var power_curve: Curve
@export_range(0.0, 2.0, 0.01) var reverse_force_ratio: float = 1.0

@export_group("Brakes")
## Brake force per wheel.
@export_range(0.0, 20000.0, 100.0, "suffix:N") var brake_force: float = 3500.0
## Extra brake force on wheels with [member ShapeCastWheel.has_handbrake].
@export_range(0.0, 20000.0, 100.0, "suffix:N") var handbrake_force: float = 6000.0

@export_group("Steering")
@export_range(0.0, 60.0, 0.1, "radians_as_degrees") var max_steer_angle: float = 0.5585
## Steering lock at [member high_speed_kmh] and above.
@export_range(0.0, 60.0, 0.1, "radians_as_degrees") var high_speed_steer_angle: float = 0.157
@export_range(1.0, 300.0, 1.0, "suffix:km/h") var high_speed_kmh: float = 100.0
@export_range(0.1, 20.0, 0.1, "suffix:rad/s") var steer_speed: float = 2.5
@export_range(0.1, 20.0, 0.1, "suffix:rad/s") var steer_return_speed: float = 4.0
## 0 = all steered wheels turn equally, 1 = full Ackermann geometry.
@export_range(0.0, 1.0, 0.01) var ackermann: float = 0.0

@export_group("Stability")
## Anti-roll bar: resists left/right compression difference on each axle.
@export_range(0.0, 100000.0, 100.0, "suffix:N/m") var anti_roll_stiffness: float = 9000.0
## Aerodynamic drag coefficient (force = drag * speed^2).
@export_range(0.0, 5.0, 0.01) var air_drag: float = 0.4

## All wheels of this car (direct ShapeCastWheel children).
var wheels: Array[ShapeCastWheel] = []
var steer_angle: float = 0.0
## Signed speed along the car's forward axis, m/s.
var forward_speed: float = 0.0
## Set by the tow manager while a rope pulls this vehicle. If nobody drives it,
## it then rolls freely instead of standing on its handbrake.
var is_towed: bool = false

var _throttle: float = 0.0
var _steer: float = 0.0
var _handbrake: bool = false
var _axle_pairs: Array[Array] = []
## Ackermann: Z of the axle line the turning centre lies on, and the distance
## from it to the front-most steered wheel.
var _steer_pivot_z: float = 0.0
var _steer_wheelbase: float = 0.0
var _rebuild_queued: bool = false
var _definition_fingerprint: int = 0
var _fingerprint_timer: float = 0.0
## Set by [VehicleBuilder]: tells whether a definition edit needs a full rebuild.
var built_structure_fingerprint: int = 0


func _ready() -> void:
	if definition:
		VehicleBuilder.build(self, definition)
		_definition_fingerprint = _current_fingerprint()
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	set_process(definition != null and live_update and OS.is_debug_build())
	can_sleep = false
	_collect_wheels()


func _collect_wheels() -> void:
	wheels.clear()
	for child in get_children():
		if child is ShapeCastWheel and not child.is_queued_for_deletion():
			wheels.append(child)
			child.add_exception(self)
	_build_axle_pairs()
	if wheels.is_empty():
		push_warning("%s has no ShapeCastWheel children." % name)


## Regenerates everything from [member definition] (keeps position and velocity).
func rebuild() -> void:
	_rebuild_queued = false
	if not is_inside_tree():
		return
	if definition == null:
		VehicleBuilder.clear(self)
		return
	VehicleBuilder.build(self, definition)
	_definition_fingerprint = _current_fingerprint()
	if not Engine.is_editor_hint():
		_collect_wheels()
		set_process(live_update and OS.is_debug_build())
	rebuilt.emit()


## Re-applies the tuning values of [member definition] without rebuilding
## (falls back to [method rebuild] if the wheel layout changed).
func apply_definition() -> void:
	if definition == null:
		return
	if not VehicleBuilder.apply_tuning(self, definition):
		rebuild()
		return
	_definition_fingerprint = _current_fingerprint()
	if not Engine.is_editor_hint():
		_build_axle_pairs()


func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func _on_definition_changed() -> void:
	if is_inside_tree():
		_queue_rebuild()


## Watches the definition for edits (sub-resources don't emit "changed").
func _process(delta: float) -> void:
	if definition == null:
		return
	_fingerprint_timer -= delta
	if _fingerprint_timer > 0.0:
		return
	_fingerprint_timer = 0.25
	var fingerprint := _current_fingerprint()
	if fingerprint == _definition_fingerprint:
		return
	if Engine.is_editor_hint():
		_queue_rebuild()
	else:
		apply_definition()


## Definition values, plus (in the editor) the save times of the model and
## collision scene files, so re-saving them refreshes the preview.
func _current_fingerprint() -> int:
	var fingerprint := VehicleSerializer.fingerprint(definition)
	if not Engine.is_editor_hint():
		return fingerprint
	var stamps := [fingerprint]
	for scene: PackedScene in [definition.model, definition.collision_scene]:
		var path := VehicleSerializer.resource_source_path(scene)
		stamps.append(FileAccess.get_modified_time(path) if path != "" else 0)
	return stamps.hash()


func _validate_property(property: Dictionary) -> void:
	if definition != null and property.name in DEFINITION_PROPERTIES:
		property.usage = (property.usage & ~PROPERTY_USAGE_STORAGE) | PROPERTY_USAGE_READ_ONLY


## Sets the controls when [member use_player_input] is off.
## throttle: -1..1, steer: -1 (right)..1 (left).
func set_controls(throttle: float, steer: float, handbrake: bool) -> void:
	_throttle = clampf(throttle, -1.0, 1.0)
	_steer = clampf(steer, -1.0, 1.0)
	_handbrake = handbrake


func get_speed_kmh() -> float:
	return linear_velocity.length() * 3.6


## Puts the car back on its wheels, keeping its heading.
func reset_vehicle(lift: float = 1.5) -> void:
	var flat_forward := -global_basis.z
	flat_forward.y = 0.0
	if flat_forward.length_squared() < 0.01:
		flat_forward = Vector3.FORWARD
	var yaw := atan2(-flat_forward.x, -flat_forward.z)
	global_transform = Transform3D(Basis(Vector3.UP, yaw), global_position + Vector3.UP * lift)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	steer_angle = 0.0
	reset_physics_interpolation()
	vehicle_reset.emit()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if use_player_input:
		if Input.is_action_just_pressed(ACTION_RESET):
			reset_vehicle()
			return
		_throttle = Input.get_axis(ACTION_BACKWARD, ACTION_FORWARD)
		_steer = Input.get_axis(ACTION_RIGHT, ACTION_LEFT)
		_handbrake = Input.is_action_pressed(ACTION_HANDBRAKE)
	elif is_towed:
		# Towed with nobody at the wheel: roll freely, wheels straight.
		_throttle = 0.0
		_steer = 0.0
		_handbrake = false

	if wheels.is_empty():
		return

	forward_speed = linear_velocity.dot(-global_basis.z)

	# ---- Throttle / brake / reverse ---------------------------------------
	# W accelerates, or brakes while rolling backwards.
	# S brakes while rolling forwards, otherwise reverses.
	var drive := 0.0
	var brake := 0.0
	if _throttle > 0.0:
		if forward_speed < -1.0:
			brake = _throttle
		else:
			drive = _throttle
	elif _throttle < 0.0:
		if forward_speed > 1.0:
			brake = -_throttle
		else:
			drive = _throttle

	# Speed limiter / power curve (default: full power up to 70% of the limit,
	# then fade out).
	var max_forward := max_speed_kmh / 3.6
	var max_reverse := max_reverse_speed_kmh / 3.6
	if drive > 0.0:
		drive *= _force_factor(forward_speed / max_forward)
	elif drive < 0.0:
		drive *= _force_factor(-forward_speed / max_reverse) * reverse_force_ratio

	# ---- Steering: less lock at speed, smooth turning -------------------------
	var speed_factor := clampf(absf(forward_speed) / (high_speed_kmh / 3.6), 0.0, 1.0)
	var steer_limit := lerpf(max_steer_angle, high_speed_steer_angle, speed_factor)
	var rate := steer_return_speed if is_zero_approx(_steer) else steer_speed
	steer_angle = move_toward(steer_angle, _steer * steer_limit, rate * delta)

	# ---- Wheels ----------------------------------------------------------
	var drive_wheel_count := 0
	for wheel in wheels:
		if wheel.is_drive:
			drive_wheel_count += 1
	var drive_per_wheel := 0.0
	if drive_wheel_count > 0:
		drive_per_wheel = drive * engine_force / drive_wheel_count

	var body_state := PhysicsServer3D.body_get_direct_state(get_rid())
	var mass_share := mass / wheels.size()

	for wheel in wheels:
		if wheel.is_steering:
			wheel.rotation.y = _wheel_steer_angle(wheel)
		var locked := _handbrake and wheel.has_handbrake
		var wheel_drive := drive_per_wheel if wheel.is_drive and not locked else 0.0
		var wheel_brake := brake * brake_force + (handbrake_force if locked else 0.0)
		wheel.update_wheel(delta, self, body_state, wheel_drive, wheel_brake, locked, mass_share)

	_apply_anti_roll()

	# ---- Air drag --------------------------------------------------------
	apply_central_force(-linear_velocity * linear_velocity.length() * air_drag)


## Pairs left/right wheels that share an axle (same local Z).
func _build_axle_pairs() -> void:
	_build_steering_geometry()
	_axle_pairs.clear()
	var used: Array[ShapeCastWheel] = []
	for a in wheels:
		if a in used:
			continue
		for b in wheels:
			if b == a or b in used:
				continue
			var same_axle := absf(a.position.z - b.position.z) < 0.2
			var opposite_sides := signf(a.position.x) != signf(b.position.x)
			if same_axle and opposite_sides:
				var left := a if a.position.x < b.position.x else b
				var right := b if left == a else a
				_axle_pairs.append([left, right])
				used.append(a)
				used.append(b)
				break


## Anti-roll bar: pushes up the more compressed side and pulls down the other.
func _apply_anti_roll() -> void:
	if anti_roll_stiffness <= 0.0:
		return
	var up := global_basis.y
	for pair in _axle_pairs:
		var left: ShapeCastWheel = pair[0]
		var right: ShapeCastWheel = pair[1]
		if not (left.is_grounded and right.is_grounded):
			continue
		var force := (left.compression - right.compression) * anti_roll_stiffness
		apply_force(up * force, left.global_position - global_position)
		apply_force(-up * force, right.global_position - global_position)


## Engine force multiplier at [param speed_ratio] = speed / top speed.
func _force_factor(speed_ratio: float) -> float:
	if power_curve != null and power_curve.point_count > 0:
		if speed_ratio >= 1.0:
			return 0.0
		return clampf(power_curve.sample(clampf(speed_ratio, 0.0, 1.0)), 0.0, 1.0)
	return 1.0 - smoothstep(0.7, 1.0, speed_ratio)


## Steering angle of one wheel: steer_angle * steer_ratio, blended towards the
## Ackermann angle that points the wheel at the common turning centre.
func _wheel_steer_angle(wheel: ShapeCastWheel) -> float:
	var angle := steer_angle * wheel.steer_ratio
	if ackermann <= 0.0 or absf(steer_angle) < 1e-4 or _steer_wheelbase < 0.01:
		return angle
	# Turning centre at x = -radius (left turn = positive angle = centre on -X).
	var radius := _steer_wheelbase / tan(steer_angle)
	var arm := _steer_pivot_z - wheel.position.z
	var lateral := radius + wheel.position.x
	if absf(lateral) < 0.01:
		lateral = 0.01 * signf(radius)
	return lerpf(angle, atan(arm / lateral), ackermann)


## Ackermann reference: the turning centre lies on the line of the non-steered
## wheels (their mean Z); the wheelbase is measured to the front-most steered wheel.
func _build_steering_geometry() -> void:
	_steer_pivot_z = 0.0
	_steer_wheelbase = 0.0
	var fixed_sum := 0.0
	var fixed_count := 0
	var all_sum := 0.0
	for wheel in wheels:
		all_sum += wheel.position.z
		if not wheel.is_steering:
			fixed_sum += wheel.position.z
			fixed_count += 1
	if wheels.is_empty():
		return
	_steer_pivot_z = fixed_sum / fixed_count if fixed_count > 0 else all_sum / wheels.size()
	for wheel in wheels:
		if wheel.is_steering:
			_steer_wheelbase = maxf(_steer_wheelbase, _steer_pivot_z - wheel.position.z)
