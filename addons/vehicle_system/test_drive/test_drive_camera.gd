extends Camera3D
## Test-drive camera: chase, orbit, side, wheel close-up and top view.
## RMB drag orbits, the mouse wheel zooms, [method next_mode] cycles the views.

enum Mode { CHASE, ORBIT, SIDE, WHEELS, TOP }
const MODE_NAMES: PackedStringArray = ["chase", "orbit", "side", "wheels", "top"]

var target: ShapeCastVehicle
var mode: Mode = Mode.CHASE
var distance: float = 7.5
var look_height: float = 0.6
var yaw: float = 0.0
var pitch: float = -0.28

var _dragging: bool = false
var _snap: bool = true


func _ready() -> void:
	fov = 70.0
	far = 1000.0


## Takes distance and look height from the vehicle and jumps behind it.
func reset_view() -> void:
	if target == null:
		return
	distance = target.camera_distance
	look_height = target.camera_look_height
	pitch = -0.28
	_snap = true


func next_mode() -> void:
	mode = ((mode + 1) % MODE_NAMES.size()) as Mode
	_snap = true


func get_mode_name() -> String:
	return MODE_NAMES[mode]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_dragging = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					distance = clampf(distance * 0.9, 2.0, 60.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					distance = clampf(distance * 1.1, 2.0, 60.0)
	elif event is InputEventMouseMotion and _dragging:
		yaw -= event.relative.x * 0.005
		pitch = clampf(pitch - event.relative.y * 0.005, -1.4, 0.35)
		if mode == Mode.CHASE:
			mode = Mode.ORBIT


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var xform := target.get_global_transform_interpolated()
	var focus := xform.origin + Vector3.UP * look_height
	match mode:
		Mode.CHASE:
			var forward := -xform.basis.z
			forward.y = 0.0
			if forward.length_squared() > 0.01:
				var behind := atan2(-forward.x, -forward.z)
				yaw = behind if _snap else lerp_angle(yaw, behind, 1.0 - exp(-3.0 * delta))
			_orbit(focus)
		Mode.ORBIT:
			_orbit(focus)
		Mode.SIDE:
			_look(focus + xform.basis.x * distance * 0.8 + Vector3.UP * 0.3, focus)
		Mode.WHEELS:
			# Low on the left side: watch the suspension work.
			var center := xform.origin + Vector3.UP * 0.1
			_look(xform * Vector3(-maxf(distance * 0.45, 2.5), 0.15, 0.0), center)
		Mode.TOP:
			var up := -xform.basis.z
			up.y = 0.0
			_look(focus + Vector3.UP * distance * 2.2, focus, up if up.length_squared() > 0.01 else Vector3.FORWARD)
	_snap = false


func _orbit(focus: Vector3) -> void:
	var offset := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3(0.0, 0.0, distance)
	_look(focus + offset, focus)


func _look(from: Vector3, at: Vector3, up: Vector3 = Vector3.UP) -> void:
	global_position = from
	if from.distance_squared_to(at) > 0.0001:
		look_at(at, up.normalized())
