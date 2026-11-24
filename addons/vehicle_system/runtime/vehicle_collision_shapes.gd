@tool
class_name VehicleCollisionShapes
extends Node3D
## Root of a vehicle collision scene (Vehicles dock > Edit collision).
##
## Add, move, rotate and resize CollisionShape3D children with the usual 3D
## gizmos (box, sphere, capsule, cylinder, convex polygon), then save the scene.
## MeshInstance3D children are allowed too: each becomes a convex hull.
## Coordinates are vehicle space (+X right, +Y up, -Z forward), unless the
## definition sets collision_scene_in_model_space.
##
## In the editor the vehicle of [member reference_definition] is shown for
## reference: model, wheels, suspension travel, mount points and cargo spaces.
## The reference is never saved and does not exist in the game.

## Vehicle definition to display while editing (.tres or .json).
@export_file("*.tres", "*.res", "*.json") var reference_definition: String = "":
	set(value):
		reference_definition = value
		_refresh_reference()
@export var show_reference: bool = true:
	set(value):
		show_reference = value
		_refresh_reference()

var _reference: Node3D


func _ready() -> void:
	_refresh_reference()


## Rebuilds the reference vehicle (e.g. after editing its definition).
func _refresh_reference() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if is_instance_valid(_reference):
		_reference.queue_free()
		_reference = null
	if not show_reference or reference_definition == "":
		return
	var source := VehicleLoader.load_definition(reference_definition)
	if source == null:
		return
	# Show everything except the vehicle's own collision (that is what is edited here).
	var definition := source.duplicate(true) as VehicleDefinition
	definition.collision_scene = null
	definition.colliders.clear()
	definition.auto_collision = VehicleDefinition.AutoCollision.NONE
	var vehicle := VehicleBuilder.create(definition, "Reference")
	_reference = vehicle
	add_child(vehicle, false, Node.INTERNAL_MODE_BACK)
	if definition.collision_scene_in_model_space:
		# The shapes are in model space: undo the model transform for the preview.
		vehicle.transform = definition.get_model_transform().affine_inverse()
