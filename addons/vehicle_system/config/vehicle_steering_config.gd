@tool
class_name VehicleSteeringConfig
extends Resource
## Steering settings. Which wheels steer is set per wheel
## ([member VehicleWheelConfig.steering] and [member VehicleWheelConfig.steer_ratio]).

## Steering lock at low speed.
@export_range(0.0, 80.0, 0.1, "radians_as_degrees") var max_steer_angle: float = 0.5585
## Steering lock at [member high_speed_kmh] and above.
@export_range(0.0, 80.0, 0.1, "radians_as_degrees") var high_speed_steer_angle: float = 0.157
@export_range(1.0, 400.0, 1.0, "suffix:km/h") var high_speed_kmh: float = 100.0
## How fast the wheels turn towards the input.
@export_range(0.1, 20.0, 0.1, "suffix:rad/s") var steer_speed: float = 2.5
## How fast the wheels return to straight when the input is released.
@export_range(0.1, 20.0, 0.1, "suffix:rad/s") var steer_return_speed: float = 4.0
## Ackermann geometry: 0 = all steered wheels turn by the same angle,
## 1 = every steered wheel points at the common turning centre (inner wheel
## turns more). The turning centre lies on the line of the non-steered axles.
@export_range(0.0, 1.0, 0.01) var ackermann: float = 0.0
