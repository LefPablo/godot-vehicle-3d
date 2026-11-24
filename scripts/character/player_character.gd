extends CharacterBody3D
## Third-person character that walks around and gets into vehicles.
##
## Movement is relative to the camera: W walks away from the camera, A/D walk
## left/right. Shift runs, Space jumps. The body does not rotate; only the
## "Model" child turns to face the walking direction.
## Getting into and out of vehicles is handled by the VehicleSwitcher, which calls
## [method set_active] and [method place_at].

const ACTION_FORWARD := &"move_forward"
const ACTION_BACKWARD := &"move_backward"
const ACTION_LEFT := &"steer_left"
const ACTION_RIGHT := &"steer_right"
const ACTION_SPRINT := &"sprint"
const ACTION_JUMP := &"jump"

@export_range(0.5, 20.0, 0.1, "suffix:m/s") var walk_speed: float = 4.0
@export_range(0.5, 30.0, 0.1, "suffix:m/s") var sprint_speed: float = 7.5
## How quickly the character reaches the target speed on the ground.
@export_range(1.0, 200.0, 0.5, "suffix:m/s²") var acceleration: float = 30.0
## Fraction of [member acceleration] available in the air.
@export_range(0.0, 1.0, 0.01) var air_control: float = 0.3
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var jump_velocity: float = 4.8
@export_range(0.1, 50.0, 0.1) var turn_speed: float = 12.0
## Force used to shove rigid bodies the character walks into (boxes move, cars barely).
@export_range(0.0, 5000.0, 10.0, "suffix:N") var push_force: float = 450.0

## False while sitting in a vehicle.
var is_active: bool = true

@onready var _model: Node3D = $Model
@onready var _collision: CollisionShape3D = $CollisionShape3D


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	var input := Input.get_vector(ACTION_LEFT, ACTION_RIGHT, ACTION_FORWARD, ACTION_BACKWARD)
	var direction := _camera_yaw_basis() * Vector3(input.x, 0.0, input.y)
	var speed := sprint_speed if Input.is_action_pressed(ACTION_SPRINT) else walk_speed
	var target := direction * speed
	var accel := acceleration * (1.0 if is_on_floor() else air_control)
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)

	if Input.is_action_just_pressed(ACTION_JUMP) and is_on_floor():
		velocity.y = jump_velocity

	if direction.length_squared() > 0.01:
		var yaw := atan2(-direction.x, -direction.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, yaw, 1.0 - exp(-turn_speed * delta))

	move_and_slide()
	_push_rigid_bodies(delta)


## Shows / hides the character and turns its collision and controls on or off.
func set_active(active: bool) -> void:
	is_active = active
	visible = active
	velocity = Vector3.ZERO
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	_collision.set_deferred(&"disabled", not active)


## Teleports the feet to [param feet_position] facing [param yaw] (radians).
func place_at(feet_position: Vector3, yaw: float) -> void:
	global_position = feet_position
	velocity = Vector3.ZERO
	_model.rotation.y = yaw
	reset_physics_interpolation()


## Radius / height of the collision capsule (used to check free exit spots).
func get_capsule() -> CapsuleShape3D:
	return _collision.shape as CapsuleShape3D


func get_capsule_offset() -> Vector3:
	return _collision.position


func _camera_yaw_basis() -> Basis:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Basis.IDENTITY
	return Basis(Vector3.UP, camera.global_rotation.y)


func _push_rigid_bodies(delta: float) -> void:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var body := collision.get_collider() as RigidBody3D
		if body == null:
			continue
		var push := -collision.get_normal()
		push.y = 0.0
		if push.length_squared() < 1e-4:
			continue
		body.apply_impulse(push.normalized() * push_force * delta,
				collision.get_position() - body.global_position)
