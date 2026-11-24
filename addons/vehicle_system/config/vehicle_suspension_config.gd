@tool
class_name VehicleSuspensionConfig
extends Resource
## Suspension settings of a wheel (or of every wheel that shares this resource).
##
## Share one instance between the wheels of an axle (or several axles) to tune
## them together in the inspector. See [ShapeCastWheel] for what each value does.

## How far the wheel centre can travel below the mount point.
@export_range(0.05, 1.5, 0.01, "suffix:m") var travel: float = 0.35
## The sweep starts this far above the mount (lets the wheel climb steps).
@export_range(0.0, 1.5, 0.01, "suffix:m") var cast_headroom: float = 0.4
## Spring rate. Static sag = wheel load / stiffness.
@export_range(0.0, 500000.0, 100.0, "suffix:N/m") var spring_stiffness: float = 22000.0
## Damping while the suspension is being compressed (bump).
@export_range(0.0, 50000.0, 10.0, "suffix:Ns/m") var damping_compression: float = 1800.0
## Damping while the suspension is extending (rebound).
@export_range(0.0, 50000.0, 10.0, "suffix:Ns/m") var damping_rebound: float = 2600.0
## Length of the stiff bump stop at the end of the travel.
@export_range(0.0, 0.3, 0.005, "suffix:m") var bump_stop_length: float = 0.05
## Stiffness of the bump stop (added on top of the spring).
@export_range(0.0, 2000000.0, 1000.0, "suffix:N/m") var bump_stop_stiffness: float = 150000.0
## Clamp for the damper input velocity (avoids force spikes on sharp edges).
@export_range(0.5, 20.0, 0.1, "suffix:m/s") var max_damper_speed: float = 4.0
## 0 = force along the strut, 1 = along the contact normal.
@export_range(0.0, 1.0, 0.01) var contact_normal_influence: float = 0.5

@export_group("Hard Contact")
## Share of the stopping impulse applied per tick when the suspension bottoms out.
@export_range(0.0, 1.0, 0.01) var hard_contact_strength: float = 0.5
## How fast penetration is pushed out (per second, as a fraction of the depth).
@export_range(0.0, 60.0, 0.1, "suffix:1/s") var hard_contact_correction: float = 20.0
## Upper limit for the push-out speed.
@export_range(0.0, 10.0, 0.1, "suffix:m/s") var max_correction_speed: float = 3.0
## Assumed depth when the tyre is inside something even at the top of its travel.
@export_range(0.0, 0.5, 0.005, "suffix:m") var blocked_push_depth: float = 0.05


## Static compression under [param load_newtons], in metres.
func static_sag(load_newtons: float) -> float:
	if spring_stiffness <= 0.0:
		return travel
	return load_newtons / spring_stiffness
