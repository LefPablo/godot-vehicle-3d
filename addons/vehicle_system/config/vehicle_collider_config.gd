@tool
class_name VehicleColliderConfig
extends Resource
## One collision shape of the vehicle body.

enum ShapeType { BOX, SPHERE, CAPSULE, CYLINDER, CONVEX_HULL }

## Node name of the generated CollisionShape3D.
@export var name: String = "BodyCollision"
@export var shape_type: ShapeType = ShapeType.BOX
@export var position: Vector3 = Vector3.ZERO
@export var rotation_degrees: Vector3 = Vector3.ZERO
## BOX: full size.
@export var size: Vector3 = Vector3(1.8, 0.6, 4.0)
## SPHERE / CAPSULE / CYLINDER.
@export_range(0.01, 10.0, 0.01, "suffix:m") var radius: float = 0.5
## CAPSULE / CYLINDER (along local Y).
@export_range(0.01, 20.0, 0.01, "suffix:m") var height: float = 1.0
## CONVEX_HULL: hull points (collider space).
@export var points: PackedVector3Array = PackedVector3Array()


func create_shape() -> Shape3D:
	match shape_type:
		ShapeType.SPHERE:
			var sphere := SphereShape3D.new()
			sphere.radius = radius
			return sphere
		ShapeType.CAPSULE:
			var capsule := CapsuleShape3D.new()
			capsule.radius = radius
			capsule.height = maxf(height, radius * 2.0)
			return capsule
		ShapeType.CYLINDER:
			var cylinder := CylinderShape3D.new()
			cylinder.radius = radius
			cylinder.height = height
			return cylinder
		ShapeType.CONVEX_HULL:
			var hull := ConvexPolygonShape3D.new()
			hull.points = points
			return hull
		_:
			var box := BoxShape3D.new()
			box.size = size
			return box


func get_transform() -> Transform3D:
	var rotation := Basis.from_euler(rotation_degrees * (PI / 180.0))
	return Transform3D(rotation, position)


## Fills this config from an existing shape. Returns false for unsupported shapes.
func set_from_shape(shape: Shape3D, xform: Transform3D) -> bool:
	position = xform.origin
	rotation_degrees = xform.basis.get_euler() * (180.0 / PI)
	if shape is BoxShape3D:
		shape_type = ShapeType.BOX
		size = shape.size
	elif shape is SphereShape3D:
		shape_type = ShapeType.SPHERE
		radius = shape.radius
	elif shape is CapsuleShape3D:
		shape_type = ShapeType.CAPSULE
		radius = shape.radius
		height = shape.height
	elif shape is CylinderShape3D:
		shape_type = ShapeType.CYLINDER
		radius = shape.radius
		height = shape.height
	elif shape is ConvexPolygonShape3D:
		shape_type = ShapeType.CONVEX_HULL
		points = shape.points
	else:
		return false
	return true
