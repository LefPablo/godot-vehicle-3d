@tool
class_name VehicleCargoConfig
extends Resource
## Loose physics boxes in a cargo bed (see scripts/vehicle/cargo_load.gd).
## The property names match cargo_load.gd, so they are copied over one to one.

@export var enabled: bool = true
## Centre of the bed floor in vehicle space.
@export var position: Vector3 = Vector3.ZERO
@export_range(1, 10) var columns: int = 3
@export_range(1, 20) var rows: int = 5
@export_range(1, 5) var layers: int = 1
@export_range(0, 50) var extra_top_boxes: int = 5
@export var box_size: Vector3 = Vector3(0.52, 0.5, 0.6)
@export_range(0.0, 0.5, 0.005, "suffix:m") var spacing: float = 0.06
@export_range(0.0, 0.5, 0.01) var size_variation: float = 0.15
@export_range(10.0, 2000.0, 1.0, "suffix:kg/m3") var density: float = 150.0
@export_range(0.0, 2.0, 0.01) var friction: float = 0.8
@export_flags_3d_physics var box_collision_layer: int = 4
@export_flags_3d_physics var box_collision_mask: int = 7
## Half size of the bed interior, used to count boxes still in the bed.
@export var bed_half_extents: Vector3 = Vector3(0.95, 1.2, 1.8)
@export var random_seed: int = 7

## Properties copied onto the cargo node.
const CARGO_PROPERTIES: PackedStringArray = [
	"columns", "rows", "layers", "extra_top_boxes", "box_size", "spacing",
	"size_variation", "density", "friction", "box_collision_layer",
	"box_collision_mask", "bed_half_extents", "random_seed",
]
