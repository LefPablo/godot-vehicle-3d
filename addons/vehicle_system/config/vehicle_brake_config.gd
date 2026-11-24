@tool
class_name VehicleBrakeConfig
extends Resource
## Brake settings.

## Brake force per wheel.
@export_range(0.0, 100000.0, 100.0, "suffix:N") var brake_force: float = 3500.0
## Extra brake force on wheels with [member VehicleWheelConfig.handbrake].
@export_range(0.0, 100000.0, 100.0, "suffix:N") var handbrake_force: float = 6000.0
