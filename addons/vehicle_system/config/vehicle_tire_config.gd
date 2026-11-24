@tool
class_name VehicleTireConfig
extends Resource
## Tyre grip settings of a wheel (or of every wheel that shares this resource).

## Friction coefficient: maximum tyre force = friction * wheel load.
@export_range(0.0, 3.0, 0.01) var friction: float = 1.2
## Fraction of sideways sliding velocity cancelled per physics tick.
@export_range(0.0, 1.0, 0.01) var lateral_grip: float = 0.6
## Sideways grip while the handbrake locks the wheel (lower = easier drifts).
@export_range(0.0, 1.0, 0.01) var handbrake_lateral_grip: float = 0.2
## Rolling resistance, proportional to rolling speed.
@export_range(0.0, 500.0, 1.0, "suffix:Ns/m") var rolling_resistance: float = 25.0
