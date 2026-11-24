@tool
class_name VehicleCargoSpace
extends Resource
## A space that can carry cargo: a pickup bed, a trailer deck, a van's load
## area, a car trunk... A vehicle can have several.
##
## The space is a box: [member position] is the centre of its FLOOR (vehicle
## space), [member size] its inner dimensions (X = width, Y = usable height,
## Z = length). Use [method can_fit] / [method can_carry] to check whether an
## item fits; [member accepted_tags] limits which kinds of cargo are allowed.

## Node name of the generated [VehicleCargoBay] (other systems look it up by name).
@export var name: String = "Cargo"
## Centre of the floor of the space, in vehicle space.
@export var position: Vector3 = Vector3.ZERO
@export var rotation_degrees: Vector3 = Vector3.ZERO
## Inner size: width (X), usable height (Y), length (Z).
@export var size: Vector3 = Vector3(1.6, 1.0, 2.0)
## Maximum payload. 0 = no limit.
@export_range(0.0, 100000.0, 10.0, "or_greater", "suffix:kg") var max_mass: float = 0.0
## Kinds of cargo this space takes (e.g. "boxes", "pallet", "liquid", "livestock").
## Empty = anything.
@export var accepted_tags: PackedStringArray = PackedStringArray()
## Open top (pickup bed, flatbed): items may stick out above [member size].y,
## up to [member max_overhang_height].
@export var open_top: bool = false
@export_range(0.0, 5.0, 0.05, "suffix:m") var max_overhang_height: float = 0.0

@export_group("Initial Load")
## Loose boxes spawned into the space when the vehicle is created (optional).
@export var initial_load: VehicleCargoLoad


## Inner volume in cubic metres.
func get_volume() -> float:
	return size.x * size.y * size.z


func get_transform() -> Transform3D:
	return Transform3D(Basis.from_euler(rotation_degrees * (PI / 180.0)), position)


## Does an item of [param item_size] (width, height, length) fit? It may be
## turned around its vertical axis; with [param allow_tipping] it may also be
## laid on any side.
func can_fit(item_size: Vector3, allow_tipping: bool = false) -> bool:
	var limit := size
	if open_top:
		limit.y += max_overhang_height
	var orientations: Array[Vector3] = [item_size, Vector3(item_size.z, item_size.y, item_size.x)]
	if allow_tipping:
		orientations.append_array([
			Vector3(item_size.x, item_size.z, item_size.y), Vector3(item_size.y, item_size.x, item_size.z),
			Vector3(item_size.y, item_size.z, item_size.x), Vector3(item_size.z, item_size.x, item_size.y),
		])
	for o in orientations:
		if o.x <= limit.x and o.y <= limit.y and o.z <= limit.z:
			return true
	return false


## True if this space accepts the [param tag] ("" = untagged cargo).
func accepts(tag: String) -> bool:
	return accepted_tags.is_empty() or tag in accepted_tags


## Full check: kind, size and mass ([param current_mass] = what is already loaded).
func can_carry(item_size: Vector3, item_mass: float = 0.0, tag: String = "",
		current_mass: float = 0.0, allow_tipping: bool = false) -> bool:
	if not accepts(tag):
		return false
	if max_mass > 0.0 and current_mass + item_mass > max_mass:
		return false
	return can_fit(item_size, allow_tipping)
