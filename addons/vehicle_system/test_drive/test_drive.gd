extends Node3D
## Vehicle test track: drive any vehicle definition on a built-in course.
##
## Started by the Vehicles dock (Test drive), which stores the definition path
## in [constant CONFIG_PATH]. Run it directly (F6) to drive [member definition_path],
## or the dock's last choice, or the first vehicle found in res://vehicles.
##
## The course (everything starts at the spawn point, driving towards -Z):
##   x =   0  speed bumps, then a cone slalom
##   x =  12  big bumps
##   x =  24  alternating left/right bumps (roll)
##   x =  36  curb steps 5 - 25 cm
##   x = -14  jump ramp
##   x = -32  20 % hill with a plateau
## The track only uses physics layer 1 (ground) and layer 3 (cones, crates),
## like the vehicles' default masks.

const CONFIG_PATH := "user://vehicle_test_drive.cfg"
const CameraScript := preload("res://addons/vehicle_system/test_drive/test_drive_camera.gd")
const HudScript := preload("res://addons/vehicle_system/test_drive/test_drive_hud.gd")

## Default controls, added when the project doesn't define these actions.
const INPUT_ACTIONS := {
	&"move_forward": [KEY_W, KEY_UP],
	&"move_backward": [KEY_S, KEY_DOWN],
	&"steer_left": [KEY_A, KEY_LEFT],
	&"steer_right": [KEY_D, KEY_RIGHT],
	&"handbrake": [KEY_SPACE],
	&"reset_vehicle": [KEY_R],
}

## Vehicle to drive when this scene is run on its own ("" = the dock's choice).
@export_file("*.tres", "*.res", "*.json") var definition_path: String = ""
@export var spawn_position: Vector3 = Vector3(0.0, 0.0, 12.0)
@export var spawn_yaw_degrees: float = 0.0

var vehicle: ShapeCastVehicle
var definition: VehicleDefinition

var _path: String = ""
var _camera: CameraScript
var _hud: HudScript
var _props: Array[Dictionary] = [] # {"body": RigidBody3D, "transform": Transform3D}
var _ground_material: StandardMaterial3D
var _feature_material: StandardMaterial3D
var _bump_material: StandardMaterial3D


func _ready() -> void:
	_ensure_input_actions()
	_build_environment()
	_build_track()

	_camera = CameraScript.new()
	_camera.name = "TestDriveCamera"
	add_child(_camera)
	_camera.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = HudScript.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)

	_path = _choose_definition()
	spawn_vehicle(false)


func _process(_delta: float) -> void:
	if _hud and _camera:
		_hud.camera_mode = _camera.get_mode_name()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_F5:
			spawn_vehicle(true)
		KEY_C:
			_camera.next_mode()
		KEY_H, KEY_F1:
			_hud.show_help = not _hud.show_help
		KEY_P:
			reset_props()
		KEY_ESCAPE:
			get_tree().quit()
		_:
			return
	get_viewport().set_input_as_handled()


## (Re)spawns the vehicle. [param reload] re-reads the definition from disk and
## keeps the vehicle where it is.
func spawn_vehicle(reload: bool) -> void:
	var warnings: Array[String] = []
	var loaded: VehicleDefinition = null
	if _path != "":
		loaded = VehicleLoader.load_definition(_path, warnings, reload)
	if loaded == null:
		_hud.load_warnings = warnings
		_hud.show_message("Can't load a vehicle (%s)" % (_path if _path != "" else "no definition found"), 8.0)
		return

	var ground := spawn_position
	var yaw := deg_to_rad(spawn_yaw_degrees)
	if is_instance_valid(vehicle):
		if reload:
			ground = _ground_below(vehicle.global_position)
			var forward := -vehicle.global_basis.z
			yaw = atan2(-forward.x, -forward.z)
		VehicleBuilder.clear(vehicle)
		remove_child(vehicle)
		vehicle.queue_free()

	definition = loaded
	vehicle = VehicleLoader.spawn(definition, self, ground, yaw)
	vehicle.use_player_input = definition.player_controllable
	vehicle.set_controls(0.0, 0.0, not definition.player_controllable)

	_camera.target = vehicle
	_camera.reset_view()
	_hud.vehicle = vehicle
	_hud.definition = definition
	_hud.source_path = _path
	_hud.issues = VehicleValidator.validate(definition)
	_hud.load_warnings = warnings
	_hud.show_message(("Reloaded %s" if reload else "Driving %s") % definition.display_name)
	print("Test drive: %s (%s)" % [definition.display_name, _path])


## Puts the cones and crates back.
func reset_props() -> void:
	for prop in _props:
		var body: RigidBody3D = prop.body
		body.global_transform = prop.transform
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.reset_physics_interpolation()


func _choose_definition() -> String:
	if definition_path != "":
		return definition_path
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		var path: String = config.get_value("test_drive", "definition", "")
		if path != "":
			return path
	var catalog := VehicleLoader.find_definitions()
	return catalog[0] if not catalog.is_empty() else ""


func _ensure_input_actions() -> void:
	for action: StringName in INPUT_ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: Key in INPUT_ACTIONS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)


func _ground_below(at: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 20.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position if hit else Vector3(at.x, 0.0, at.z)


# --- Environment & track ------------------------------------------------------

func _build_environment() -> void:
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	add_child(sun)

	_ground_material = _grid_material(Color(0.36, 0.38, 0.4), Color(0.48, 0.5, 0.53), 2.0)
	_feature_material = _grid_material(Color(0.55, 0.5, 0.42), Color(0.66, 0.6, 0.5), 1.0)
	_bump_material = StandardMaterial3D.new()
	_bump_material.albedo_color = Color(0.95, 0.78, 0.2)
	_bump_material.roughness = 0.7


func _build_track() -> void:
	# Ground: 400 x 400 m, top at y = 0.
	_box("Ground", Vector3(400.0, 1.0, 400.0), Transform3D(Basis.IDENTITY, Vector3(0.0, -0.5, -80.0)),
			_ground_material)
	_text("START", Vector3(0.0, 0.02, spawn_position.z - 4.0), 2.0, true)

	# Distance boards along the main lane.
	for i in 9:
		var z := spawn_position.z - 4.0 - i * 25.0
		_text("%d m" % (i * 25), Vector3(6.0, 1.2, z), 1.0)
		_box("Post%d" % i, Vector3(0.1, 1.0, 0.1), Transform3D(Basis.IDENTITY, Vector3(6.0, 0.5, z)),
				_bump_material, false)

	# x = 0: speed bumps (12 cm), then a slalom.
	_text("Speed bumps", Vector3(0.0, 1.6, -4.0), 1.2)
	for i in 8:
		_bump(Vector3(0.0, 0.0, -10.0 - i * 6.0), 0.12, 6.0)
	_text("Slalom", Vector3(0.0, 1.6, -64.0), 1.2)
	for i in 9:
		_cone(Vector3(0.0, 0.0, -72.0 - i * 10.0))

	# x = 12: big bumps (25 cm).
	_text("Big bumps", Vector3(12.0, 1.6, -4.0), 1.2)
	for i in 6:
		_bump(Vector3(12.0, -0.1, -12.0 - i * 9.0), 0.35, 6.0)

	# x = 24: alternating left/right bumps -> body roll.
	_text("Roll bumps", Vector3(24.0, 1.6, -4.0), 1.2)
	for i in 10:
		var side := -1.0 if i % 2 == 0 else 1.0
		_box("RollBump%d" % i, Vector3(2.6, 0.15, 1.2),
				Transform3D(Basis.IDENTITY, Vector3(24.0 + side * 1.4, 0.075, -10.0 - i * 5.0)), _bump_material)

	# x = 36: curb steps up and down.
	_text("Steps", Vector3(36.0, 1.6, -4.0), 1.2)
	var heights := [0.05, 0.1, 0.15, 0.2, 0.25]
	for i in heights.size():
		var h: float = heights[i]
		_box("Step%d" % i, Vector3(5.0, h, 3.0),
				Transform3D(Basis.IDENTITY, Vector3(36.0, h * 0.5, -12.0 - i * 10.0)), _feature_material)
		_text("%d cm" % roundi(h * 100.0), Vector3(39.0, 0.6, -12.0 - i * 10.0), 0.6)

	# x = -14: jump ramp (10 deg, 1.4 m high).
	_text("Ramp", Vector3(-14.0, 1.6, -4.0), 1.2)
	_slope("Ramp", -14.0, -14.0, 8.0, 10.0, 0.0, 4.5)

	# x = -32: 20 % hill (11.3 deg) with a plateau.
	_text("Hill 20 %", Vector3(-32.0, 1.6, -4.0), 1.2)
	var angle := rad_to_deg(atan(0.2))
	var climb := 12.0
	var top := climb * sin(deg_to_rad(angle))
	var hill_start := -10.0
	var plateau_start := hill_start - climb * cos(deg_to_rad(angle))
	_slope("HillUp", -32.0, hill_start, climb, angle, 0.0, 6.0)
	_box("HillTop", Vector3(6.0, top, 10.0),
			Transform3D(Basis.IDENTITY, Vector3(-32.0, top * 0.5, plateau_start - 5.0)), _feature_material)
	_slope("HillDown", -32.0, plateau_start - 10.0, climb, -angle, top, 6.0)

	# Crates to push around.
	for i in 6:
		var crate_position := Vector3(-10.0 + (i % 3) * 0.9, 0.4 + (i / 3) * 0.8, 20.0)
		_crate(crate_position)


## Box along -Z rising by [param angle_degrees] (negative = falling), whose top
## surface starts at height [param start_height] at z = [param start_z].
func _slope(node_name: String, x: float, start_z: float, length: float, angle_degrees: float,
		start_height: float, width: float) -> void:
	var a := deg_to_rad(angle_degrees)
	var thickness := 0.4
	var center := Vector3(x, start_height + length * 0.5 * sin(a) - thickness * 0.5 * cos(a),
			start_z - length * 0.5 * cos(a))
	_box(node_name, Vector3(width, thickness, length), Transform3D(Basis(Vector3.RIGHT, a), center),
			_feature_material)


func _bump(at: Vector3, radius: float, width: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Bump"
	body.collision_mask = 0
	body.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5), at)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = width
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = width
	mesh.material = _bump_material
	var view := MeshInstance3D.new()
	view.mesh = mesh
	body.add_child(view)
	add_child(body, true)


func _box(node_name: String, size: Vector3, xform: Transform3D, material: Material,
		solid: bool = true) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_mask = 0
	body.transform = xform
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
	else:
		body.collision_layer = 0
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var view := MeshInstance3D.new()
	view.mesh = mesh
	body.add_child(view)
	add_child(body, true)


func _cone(at: Vector3) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.45, 0.1)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.04
	mesh.bottom_radius = 0.22
	mesh.height = 0.7
	mesh.material = material
	var shape := CylinderShape3D.new()
	shape.radius = 0.16
	shape.height = 0.7
	_prop("Cone", mesh, shape, 4.0, at + Vector3.UP * 0.35)


func _crate(at: Vector3) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.62, 0.45, 0.28)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.8, 0.8, 0.8)
	mesh.material = material
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	_prop("Crate", mesh, shape, 40.0, at)


func _prop(node_name: String, mesh: Mesh, shape: Shape3D, mass: float, at: Vector3) -> void:
	var body := RigidBody3D.new()
	body.name = node_name
	body.mass = mass
	body.collision_layer = 4
	body.collision_mask = 7
	body.position = at
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	var view := MeshInstance3D.new()
	view.mesh = mesh
	body.add_child(view)
	add_child(body, true)
	_props.append({"body": body, "transform": body.global_transform})


func _text(text: String, at: Vector3, size: float, flat: bool = false) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.pixel_size = 0.01 * size
	label.font_size = 64
	label.outline_size = 12
	label.modulate = Color(1.0, 1.0, 1.0, 0.9)
	if flat:
		label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	add_child(label)


func _grid_material(base: Color, line: Color, cell: float) -> StandardMaterial3D:
	var image := Image.create(64, 64, false, Image.FORMAT_RGB8)
	image.fill(base)
	for i in 64:
		for w in 2:
			image.set_pixel(i, w, line)
			image.set_pixel(w, i, line)
	image.generate_mipmaps()
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE / cell
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.roughness = 0.9
	return material
