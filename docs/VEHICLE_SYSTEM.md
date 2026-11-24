# Vehicle system

The vehicle system is the `addons/vehicle_system` addon.
Its documentation is in [addons/vehicle_system/README.md](../addons/vehicle_system/README.md).

Project-specific parts (not in the addon):

- `scripts/vehicle/vehicle_switcher.gd` - enter / leave vehicles, active vehicle.
- `scripts/vehicle/tow_manager.gd`, `tow_rope.gd` - tow ropes and trailer hitching
  (uses the `TowHookFront`, `TowHitchRear` and `Coupler` mount points, and the
  cargo bay's `carry()` when a trailer snaps onto a hitch).
- `scripts/vehicle/vehicle_spawner.gd` - V in the demo spawns the next vehicle
  from `res://vehicles` and `user://vehicles` and registers it with the two above.
- `vehicles/<id>/` - the project's vehicle definitions, models and collision scenes.
- `tests/` - `definition_spawn_test` covers the data-driven system; the other
  tests drive the demo vehicles.
