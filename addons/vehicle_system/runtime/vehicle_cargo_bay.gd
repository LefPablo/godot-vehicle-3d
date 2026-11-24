@tool
class_name VehicleCargoBay
extends Node3D
## Runtime side of a [VehicleCargoSpace]: a node at the centre of the space's
## floor, child of the vehicle. Answers "what fits / how much is loaded" and,
## if the space has an [member VehicleCargoSpace.initial_load], fills it with
## loose physics boxes.
##
## The boxes are independent RigidBody3D nodes next to the vehicle (not inside
## it: a rigid body inside a moving rigid body jitters), so they slide, bounce
## and can fall out. When the vehicle is reset the boxes are stacked back.

@export var space: VehicleCargoSpace

## Boxes spawned from the initial load.
var boxes: Array[RigidBody3D] = []
var _slots: Array[Transform3D] = []


func _ready() -> void:
	if Engine.is_editor_hint() or space == null or space.initial_load == null:
		return
	_build_slots(space.initial_load)
	var vehicle := get_parent()
	if vehicle.has_signal(&"vehicle_reset"):
		vehicle.connect(&"vehicle_reset", restack)
	# The parent's parent is still being set up during _ready.
	_spawn_boxes.call_deferred()


# --- Capacity -----------------------------------------------------------------

## Half the inner size of the space.
func get_half_extents() -> Vector3:
	return space.size * 0.5 if space else Vector3.ZERO


## Usable height: the walls, plus the allowed overhang for open-top spaces.
func get_load_height() -> float:
	if space == null:
		return 0.0
	return space.size.y + (space.max_overhang_height if space.open_top else 0.0)


## Mass of the spawned boxes that are still inside the space.
func get_load_mass() -> float:
	var total := 0.0
	for box in boxes:
		if is_instance_valid(box) and is_in_bed(box):
			total += box.mass
	return total


## Can an item of this size / mass / kind be added, given what is loaded now?
func can_carry(item_size: Vector3, item_mass: float = 0.0, tag: String = "",
		allow_tipping: bool = false) -> bool:
	return space != null and space.can_carry(item_size, item_mass, tag, get_load_mass(), allow_tipping)


# --- Loose boxes --------------------------------------------------------------

## Puts every box back into its slot, at rest.
func restack() -> void:
	for i in boxes.size():
		var box := boxes[i]
		if not is_instance_valid(box):
			continue
		box.global_transform = global_transform * _slots[i]
		box.linear_velocity = get_parent().linear_velocity if get_parent() is RigidBody3D else Vector3.ZERO
		box.angular_velocity = Vector3.ZERO
		box.sleeping = false
		box.reset_physics_interpolation()


## Number of boxes that are still inside the space.
func count_in_bed() -> int:
	var count := 0
	for box in boxes:
		if is_instance_valid(box) and is_in_bed(box):
			count += 1
	return count


## True if [param node] is inside the space (above its floor, below the load height).
func is_in_bed(node: Node3D) -> bool:
	var half := get_half_extents()
	var local := to_local(node.global_position)
	return absf(local.x) < half.x and absf(local.z) < half.z \
			and local.y > -0.2 and local.y < get_load_height()


## Moves the boxes that are in the space rigidly by [param delta] (world space).
## Call it right before the vehicle itself is teleported by the same delta,
## e.g. when a trailer snaps onto a hitch.
func carry(delta: Transform3D) -> void:
	for box in boxes:
		if not is_instance_valid(box) or not is_in_bed(box):
			continue
		box.global_transform = delta * box.global_transform
		box.reset_physics_interpolation()


## Frees the spawned boxes (when the vehicle is rebuilt or removed).
func free_boxes() -> void:
	for box in boxes:
		if is_instance_valid(box):
			box.queue_free()
	boxes.clear()


func _build_slots(cargo_load: VehicleCargoLoad) -> void:
	_slots.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = cargo_load.random_seed
	var box_size := cargo_load.box_size
	var pitch := Vector3(box_size.x + cargo_load.spacing, box_size.y + 0.01, box_size.z + cargo_load.spacing)
	var origin := Vector3(-(cargo_load.columns - 1) * 0.5 * pitch.x, 0.0, -(cargo_load.rows - 1) * 0.5 * pitch.z)
	var cells: Array[Vector3] = []
	for layer in cargo_load.layers:
		for row in cargo_load.rows:
			for column in cargo_load.columns:
				cells.append(origin + Vector3(column * pitch.x, layer * pitch.y, row * pitch.z))
	# Loose boxes on top go into random cells of the next layer.
	var top_cells: Array[Vector3] = []
	for row in cargo_load.rows:
		for column in cargo_load.columns:
			top_cells.append(origin + Vector3(column * pitch.x, cargo_load.layers * pitch.y, row * pitch.z))
	for i in mini(cargo_load.extra_top_boxes, top_cells.size()):
		var pick := rng.randi_range(i, top_cells.size() - 1)
		var cell := top_cells[pick]
		top_cells[pick] = top_cells[i]
		top_cells[i] = cell
		cells.append(cell)
	for cell in cells:
		var yaw := rng.randf_range(-0.12, 0.12)
		# Slightly above the slot so boxes of different heights settle, not overlap.
		var position_in_slot := cell + Vector3(0.0, box_size.y * 0.5 + 0.02, 0.0)
		_slots.append(Transform3D(Basis(Vector3.UP, yaw), position_in_slot))


func _spawn_boxes() -> void:
	var cargo_load := space.initial_load
	var world := get_parent().get_parent()
	if world == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = cargo_load.random_seed + 1
	var physics_material := PhysicsMaterial.new()
	physics_material.friction = cargo_load.friction
	var colors := [Color(0.72, 0.55, 0.36), Color(0.64, 0.47, 0.3), Color(0.8, 0.64, 0.42),
			Color(0.58, 0.43, 0.29)]
	var owner_name := String(get_parent().name)
	for i in _slots.size():
		var size := cargo_load.box_size * Vector3(
				1.0 - rng.randf() * cargo_load.size_variation,
				1.0 - rng.randf() * cargo_load.size_variation,
				1.0 - rng.randf() * cargo_load.size_variation)
		var box := RigidBody3D.new()
		box.name = "%sCargo%02d" % [owner_name, i + 1]
		box.mass = maxf(size.x * size.y * size.z * cargo_load.density, 1.0)
		box.physics_material_override = physics_material
		box.collision_layer = cargo_load.box_collision_layer
		box.collision_mask = cargo_load.box_collision_mask
		# Stay awake: a box resting on a parked truck must react as soon as it moves.
		box.can_sleep = false

		var shape := BoxShape3D.new()
		shape.size = size
		var collision := CollisionShape3D.new()
		collision.shape = shape
		box.add_child(collision)

		var material := StandardMaterial3D.new()
		material.albedo_color = colors[i % colors.size()]
		material.roughness = 0.9
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = material
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = mesh
		box.add_child(mesh_instance)

		# Tape strip so the boxes read as cardboard boxes.
		var tape_material := StandardMaterial3D.new()
		tape_material.albedo_color = Color(0.85, 0.8, 0.65)
		var tape_mesh := BoxMesh.new()
		tape_mesh.size = Vector3(0.08, 0.004, size.z + 0.004)
		tape_mesh.material = tape_material
		var tape := MeshInstance3D.new()
		tape.mesh = tape_mesh
		tape.position.y = size.y * 0.5
		box.add_child(tape)

		world.add_child(box)
		boxes.append(box)
	restack()
