@tool
class_name VehicleEngineConfig
extends Resource
## Engine / drivetrain settings. The force is split evenly between the drive wheels.

## Total engine force at full throttle.
@export_range(0.0, 200000.0, 100.0, "suffix:N") var engine_force: float = 6500.0
@export_range(1.0, 600.0, 1.0, "suffix:km/h") var max_speed_kmh: float = 130.0
@export_range(1.0, 200.0, 1.0, "suffix:km/h") var max_reverse_speed_kmh: float = 30.0
## Optional force curve: X = speed / max speed (0..1), Y = force multiplier (0..1).
## Empty = full force up to 70% of the top speed, then a smooth fade to zero.
@export var power_curve: Curve
## Force multiplier while reversing.
@export_range(0.0, 2.0, 0.01) var reverse_force_ratio: float = 1.0
