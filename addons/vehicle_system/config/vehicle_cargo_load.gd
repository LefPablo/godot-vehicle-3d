@tool
class_name VehicleCargoLoad
extends Resource
## Loose physics boxes spawned into a [VehicleCargoSpace] when the vehicle is
## created (and stacked back when it is reset). Boxes are laid out in a grid
## of [member columns] x [member rows] x [member layers], plus some loose ones on top.

## Boxes across the space (X).
@export_range(1, 10) var columns: int = 3
## Boxes along the space (Z).
@export_range(1, 20) var rows: int = 5
## Full layers of boxes.
@export_range(1, 5) var layers: int = 1
## Extra loose boxes placed on top of the full layers.
@export_range(0, 50) var extra_top_boxes: int = 5
## Largest box size; every box is up to [member size_variation] smaller.
@export var box_size: Vector3 = Vector3(0.52, 0.5, 0.6)
## Gap between neighbouring boxes.
@export_range(0.0, 0.5, 0.005, "suffix:m") var spacing: float = 0.06
@export_range(0.0, 0.5, 0.01) var size_variation: float = 0.15
## Box mass = volume * density.
@export_range(10.0, 2000.0, 1.0, "suffix:kg/m3") var density: float = 150.0
@export_range(0.0, 2.0, 0.01) var friction: float = 0.8
## Keep the boxes out of the camera's collision mask but inside the wheels' mask.
@export_flags_3d_physics var box_collision_layer: int = 4
@export_flags_3d_physics var box_collision_mask: int = 7
@export var random_seed: int = 7
