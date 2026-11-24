extends Camera3D
## Chase camera with mouse orbit and zoom, for driving, walking and for
## inspecting the suspension up close.
##
## Controls (Project Settings > Input Map):
##   camera_orbit (hold Right Mouse Button) + move mouse - orbit around the target
##   camera_zoom_in / camera_zoom_out (Mouse Wheel)       - zoom
##   camera_toggle_mode (C)                                - switch mode
##
## Modes:
##   CHASE - the camera stays behind the vehicle. You can orbit while holding the
##           right mouse button; after you let go it swings back behind it.
##   ORBIT - the camera keeps the world-space angle you chose and just follows
##           the target's position, so you can look at one wheel from the side
##           while the car drives over bumps.
## Targets followed with chase_heading = false (the walking character) always
## behave like ORBIT: the view only turns when you orbit it.

enum Mode { CHASE, ORBIT }

const ACTION_ORBIT := &"camera_orbit"
const ACTION_TOGGLE := &"camera_toggle_mode"
const ACTION_ZOOM_IN := &"camera_zoom_in"
const ACTION_ZOOM_OUT := &"camera_zoom_out"

@export var target: Node3D
@export var mode: Mode = Mode.CHASE
## Turn with the target's heading in CHASE mode (off for the walking character).
@export var chase_heading: bool = true

@export_group("Framing")
@export_range(1.0, 40.0, 0.1, "suffix:m") var distance: float = 7.5
@export_range(0.5, 40.0, 0.1, "suffix:m") var min_distance: float = 2.0
@export_range(1.0, 80.0, 0.1, "suffix:m") var max_distance: float = 25.0
## Pitch in CHASE mode when you are not orbiting.
@export_range(-10.0, 85.0, 0.1, "radians_as_degrees") var default_pitch: float = 0.33
## Negative pitch lets you look from below the car's centre (near the ground).
@export_range(-45.0, 0.0, 0.1, "radians_as_degrees") var min_pitch: float = -0.17
@export_range(0.0, 89.0, 0.1, "radians_as_degrees") var max_pitch: float = 1.4
## Point on the target the camera looks at, above its origin.
@export_range(-2.0, 5.0, 0.05, "suffix:m") var look_height: float = 0.6

@export_group("Smoothing")
## How tightly the camera follows the target's position (higher = less lag).
@export_range(0.1, 50.0, 0.1) var follow_smoothing: float = 12.0
## How quickly CHASE mode turns with the vehicle.
@export_range(0.1, 30.0, 0.1) var heading_smoothing: float = 3.0
## CHASE mode waits this long after you release the mouse, then swings back.
@export_range(0.0, 10.0, 0.1, "suffix:s") var return_delay: float = 1.5
@export_range(0.1, 20.0, 0.1) var return_speed: float = 2.0

@export_group("Mouse")
@export_range(0.0005, 0.02, 0.0005) var mouse_sensitivity: float = 0.004
@export var invert_y: bool = false
## Zoom factor per mouse wheel step.
@export_range(1.01, 2.0, 0.01) var zoom_step: float = 1.12

@export_group("Collision")
## Pull the camera in when the ground or an obstacle is between it and the target.
@export var avoid_obstacles: bool = true
@export_flags_3d_physics var collision_mask: int = 1
@export_range(0.0, 1.0, 0.01, "suffix:m") var collision_margin: float = 0.25

var _heading_yaw := 0.0 # smoothed yaw of the target
var _yaw_offset := 0.0 # CHASE: orbit angle relative to the target heading
var _orbit_yaw := 0.0 # ORBIT / no heading: absolute world yaw
var _pitch := 0.0
var _zoom_distance := 0.0
var _look_point := Vector3.ZERO
var _idle_time := 0.0
var _dragging := false


func _ready() -> void:
	# Moved in _process from the interpolated target transform,
	# so the camera itself must not be physics-interpolated.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	top_level = true
	_pitch = default_pitch
	_zoom_distance = distance
	if target:
		var xform := target.global_transform
		_heading_yaw = _yaw_of(xform, 0.0)
		_orbit_yaw = _heading_yaw
		_look_point = xform.origin + Vector3.UP * look_height
		_place_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _dragging:
			_orbit(event.relative)
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(ACTION_ORBIT):
		_set_dragging(true)
	elif event.is_action_released(ACTION_ORBIT):
		_set_dragging(false)
	elif event.is_action_pressed(ACTION_ZOOM_IN):
		_zoom_distance = clampf(_zoom_distance / zoom_step, min_distance, max_distance)
	elif event.is_action_pressed(ACTION_ZOOM_OUT):
		_zoom_distance = clampf(_zoom_distance * zoom_step, min_distance, max_distance)
	elif event.is_action_pressed(ACTION_TOGGLE):
		toggle_mode()
	else:
		return
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# Don't leave the mouse captured if the window loses focus mid-drag.
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and _dragging:
		_set_dragging(false)


func _process(delta: float) -> void:
	if not target:
		return
	var xform := target.get_global_transform_interpolated()
	_heading_yaw = lerp_angle(_heading_yaw, _yaw_of(xform, _heading_yaw),
			1.0 - exp(-heading_smoothing * delta))
	_look_point = _look_point.lerp(xform.origin + Vector3.UP * look_height,
			1.0 - exp(-follow_smoothing * delta))

	# CHASE mode: swing back behind the vehicle after a short pause.
	if _uses_heading() and not _dragging:
		_idle_time += delta
		if _idle_time > return_delay:
			var t := 1.0 - exp(-return_speed * delta)
			_yaw_offset = lerp_angle(_yaw_offset, 0.0, t)
			_pitch = lerpf(_pitch, default_pitch, t)

	_place_camera()


## Switches between CHASE and ORBIT without jumping the view.
func toggle_mode() -> void:
	var current_yaw := _current_yaw()
	if mode == Mode.CHASE:
		mode = Mode.ORBIT
	else:
		mode = Mode.CHASE
	_set_yaw(current_yaw)


func get_mode_name() -> String:
	if not chase_heading:
		return "FREE (on foot)"
	return "CHASE" if mode == Mode.CHASE else "ORBIT"


## Starts following another node. The camera glides over to it (position and
## heading are smoothed). Pass a distance / look height to reframe for its size;
## chase = false keeps the view direction instead of turning with the target.
func follow(new_target: Node3D, new_distance: float = -1.0, new_look_height: float = NAN,
		chase: bool = true) -> void:
	if new_target == null:
		return
	# Keep the current view direction so switching doesn't whip the camera around.
	var current_yaw := _current_yaw()
	target = new_target
	chase_heading = chase
	_heading_yaw = _yaw_of(new_target.global_transform, _heading_yaw)
	_set_yaw(current_yaw)
	if new_distance > 0.0:
		distance = new_distance
		_zoom_distance = clampf(new_distance, min_distance, max_distance)
	if not is_nan(new_look_height):
		look_height = new_look_height


func _uses_heading() -> bool:
	return mode == Mode.CHASE and chase_heading


## Points the view along [param yaw] in whatever mode is active.
func _set_yaw(yaw: float) -> void:
	_orbit_yaw = yaw
	_yaw_offset = wrapf(yaw - _heading_yaw, -PI, PI)
	_idle_time = 0.0


func _set_dragging(value: bool) -> void:
	_dragging = value
	_idle_time = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if value else Input.MOUSE_MODE_VISIBLE


func _orbit(relative: Vector2) -> void:
	# Mouse right turns the view right; mouse up looks up (camera goes lower).
	var yaw_delta := -relative.x * mouse_sensitivity
	var pitch_delta := relative.y * mouse_sensitivity * (-1.0 if invert_y else 1.0)
	if _uses_heading():
		_yaw_offset = wrapf(_yaw_offset + yaw_delta, -PI, PI)
	else:
		_orbit_yaw = wrapf(_orbit_yaw + yaw_delta, -PI, PI)
	_pitch = clampf(_pitch + pitch_delta, min_pitch, max_pitch)
	_idle_time = 0.0


func _current_yaw() -> float:
	return _heading_yaw + _yaw_offset if _uses_heading() else _orbit_yaw


func _place_camera() -> void:
	var yaw := _current_yaw()
	var view_forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var offset := (-view_forward * cos(_pitch) + Vector3.UP * sin(_pitch)) * _zoom_distance
	var desired := _look_point + offset
	if avoid_obstacles:
		desired = _resolve_collision(_look_point, desired)
	global_position = desired
	if desired.distance_squared_to(_look_point) > 0.0025:
		look_at(_look_point, Vector3.UP)


## Moves the camera in front of anything between it and the target.
func _resolve_collision(from: Vector3, to: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	if target is CollisionObject3D:
		query.exclude = [target.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return to
	var direction := (to - from).normalized()
	var safe_length := maxf(from.distance_to(hit.position) - collision_margin, 0.1)
	return from + direction * safe_length


## Yaw of the target's flattened forward axis (Godot forward is -Z).
func _yaw_of(xform: Transform3D, fallback: float) -> float:
	var forward := -xform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.05:
		return fallback
	return atan2(-forward.x, -forward.z)
