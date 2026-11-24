# Vehicle System (Godot 4)

Data-driven, ShapeCast-based vehicles. A vehicle is a **definition** (a resource
or a JSON file) plus a **model**; the addon builds the physics body, wheels,
suspension, collision, tow points and cargo spaces from it, in the editor (live
preview) and at runtime (spawn from a file, even from `user://` mod folders).

```
addons/vehicle_system/
  plugin.cfg, plugin.gd      editor plugin (Vehicles dock)
  runtime/                   ShapeCastVehicle, ShapeCastWheel, VehicleCargoBay, VehicleCollisionShapes
  config/                    VehicleDefinition and its parts (wheels, suspension, tyres, engine,
							 brakes, steering, colliders, mount points, cargo spaces, cargo load)
  core/                      VehicleBuilder, VehicleLoader, VehicleSerializer,
							 VehicleSceneExtractor, VehicleValidator
  editor/                    the Vehicles dock
  test_drive/                standalone test track (Test drive button)
```

Install: copy `addons/vehicle_system` into your project, then enable
**Project > Project Settings > Plugins > Vehicle System**. The **Vehicles** dock
appears next to the Inspector.

License: MIT (see `LICENSE`). Free to use in any project, commercial included.

## Vehicle space

+X right, +Y up, **-Z forward**; the origin is the body origin. Imported models
often face +Z: set the definition's *Model Rotation Degrees* to `(0, 180, 0)`.

## Creating a vehicle

1. Import the model (`.glb`, `.gltf`, `.blend`, `.fbx`...) or wrap it in a `.tscn`.
2. Dock > **New…** creates a definition from a 4-wheel template. Set **Model**.
3. **Add to scene** shows it in the edited scene. The preview draws colliders
   (cyan), suspension travel (green: mount = fully compressed, down to fully
   extended), mount points (orange), centre of mass (red) and cargo spaces
   (purple, with their size and payload). Wheels are drawn at their estimated rest
   height. Every change in the inspector updates the preview.
4. **Wheels**: `position` is the suspension mount. `mirror` adds the right-hand
   twin. To use the model's own wheel meshes set `model_node` (e.g. `Wheels/FL`)
   and `mirror_model_node`; they are taken out of the body and spun, steered and
   moved by the suspension. Or give `visual_scene` a separate wheel model.
   Several wheels can share one suspension / tyre resource to tune them together.
5. **Collision**: see below.
6. **Validate** checks the setup and lists, per wheel, the static load, sag (aim for
   25-45 % of the travel), natural frequency and damping ratio (0.3-0.6), plus the
   suspension at full payload.
7. **Test drive** saves the definition and drives it on the test track.
8. **Create scene** saves a `.tscn` to place in your levels.

Hand-built vehicles (ShapeCastWheel / CollisionShape3D / Marker3D children) still
work without a definition. **Extract from selected** converts one into a
definition plus a model scene.

## Collision

Three sources, all combined:

- **Collision scene** (`collision_scene`): edit shapes in the editor. Dock >
  **Edit collision** creates `<id>_collision.tscn` from the current colliders,
  links it to the definition and opens it. Move and resize the CollisionShape3D
  nodes with the usual gizmos, add more (box, sphere, capsule, cylinder, convex
  polygon). The vehicle is shown for reference (not saved). Save, and every
  vehicle preview updates.
  You can also point `collision_scene` at a **collision model** made in your 3D
  tool: every mesh in it becomes a convex hull, and Godot's `-colonly` /
  `-convcolonly` import shapes are used as they are. If that model shares the
  visual model's coordinates, enable `collision_scene_in_model_space` so the
  model offset / rotation / scale is applied to it.
- **colliders**: simple shapes defined by numbers (this is also what JSON uses).
- **auto_collision**: a box or convex hull around the model (wheels excluded).

Don't put physics bodies (RigidBody3D, StaticBody3D) inside the vehicle model:
they become separate bodies. Shape node names ending in `Collider` are reserved
for the wheels.

## Cargo spaces

`cargo_spaces` lists everything that can carry cargo: a pickup bed, a trailer
deck, a car trunk... Each `VehicleCargoSpace` has:

| Property | Meaning |
| --- | --- |
| `name` | node name of the runtime `VehicleCargoBay` (default `Cargo`) |
| `position`, `rotation_degrees` | centre of the floor, vehicle space |
| `size` | inner width (X), height (Y), length (Z) |
| `max_mass` | payload limit in kg (0 = none) |
| `accepted_tags` | kinds of cargo allowed, e.g. `boxes`, `pallet`, `liquid` (empty = anything) |
| `open_top`, `max_overhang_height` | open beds: how far a load may stick out above the walls |
| `initial_load` | optional loose boxes spawned into the space |

Checks you can build gameplay on:

```gdscript
space.can_fit(Vector3(1.2, 1.0, 0.8))               # fits? (may be turned around Y)
space.can_fit(size, true)                           # ...also laid on its side
space.can_carry(size, mass, "pallet", current_mass) # kind + size + payload
definition.find_cargo_space(size, mass, "boxes")    # first space that takes it
definition.get_payload_capacity()

var bay := vehicle.get_node("Cargo") as VehicleCargoBay   # at runtime
bay.can_carry(size, mass, tag)                      # minus what is loaded now
bay.get_load_mass()
```

## Test track

`test_drive/test_drive.tscn` is a standalone course: speed bumps, big bumps,
alternating roll bumps, curb steps (5-25 cm), a jump ramp, a 20 % hill, a cone
slalom, crates to push and distance boards. The HUD shows speed, inputs, every
wheel's compression and load, cargo and validation warnings.

Keys: WASD / arrows drive, Space handbrake, R reset, **F5 reload the definition
from disk** (edit in the editor, save, press F5), C camera (chase / orbit / side /
wheels / top), RMB drag orbit, wheel zoom, P reset cones and crates, H help, Esc quit.
Missing input actions are added automatically. Run the scene directly to drive
`definition_path`, or the vehicle last chosen in the dock.

## Tuning while the game runs

In debug builds a vehicle watches its definition: open the Remote scene tree,
select the vehicle, expand `definition` and edit. Springs, grip, engine, steering
and wheel positions apply immediately; model, collision, mount point or cargo
changes rebuild the vehicle in place. Copy good values back into the .tres.

## JSON

For vehicles from outside the project (downloads, mods). Any key may be left out.
Vectors are `[x, y, z]`, colours `[r, g, b, a]`, enums by name, steering angles in
radians, paths `res://`, `user://`, absolute or relative to the JSON file. Unknown
keys and bad values produce warnings.

```json
{
	"format": "shapecast_vehicle", "version": 1,
	"id": "new_car", "display_name": "New Car", "mass": 1300,
	"model": "new_car.glb", "model_rotation_degrees": [0, 180, 0],
	"auto_collision": "model_bounding_box",
	"engine": { "engine_force": 7000, "max_speed_kmh": 150 },
	"wheels": [
		{ "name": "WheelFL", "position": [-0.9, 0.1, -1.3], "mirror": true, "steering": true,
		  "radius": 0.35, "width": 0.25, "model_node": "Wheels/FL", "mirror_model_node": "Wheels/FR" },
		{ "name": "WheelRL", "position": [-0.9, 0.1, 1.3], "mirror": true, "drive": true, "handbrake": true,
		  "radius": 0.35, "width": 0.25, "model_node": "Wheels/RL", "mirror_model_node": "Wheels/RR" }
	],
	"mount_points": [ { "kind": "tow_hitch_rear", "position": [0, 0.1, 2.05] } ],
	"cargo_spaces": [ { "name": "Trunk", "position": [0, 0.3, 1.4], "size": [1.2, 0.45, 0.8],
						"max_mass": 250, "accepted_tags": ["luggage"] } ]
}
```

Dock **Export JSON…** writes a self-contained folder (JSON + models as .glb; the
collision scene is written as colliders). **Import JSON…** copies the models into
`res://vehicles/<id>/` and creates the .tres. Prefer JSON for outside content:
`.tres` files can contain scripts.

## Runtime API

```gdscript
var car := VehicleLoader.spawn("user://vehicles/new_car/new_car.json", level, Vector3(0, 0, 10))
for path in VehicleLoader.find_definitions():        # res://vehicles + user://vehicles
	print(path)
var definition := VehicleLoader.load_definition("res://vehicles/truck/truck.tres")
var truck := VehicleBuilder.spawn(definition, level, Transform3D(Basis(), Vector3(5, 1, 0)))
```

Mount points become Marker3D children found by name: `TowHookFront`,
`TowHitchRear`, `Coupler`, `DriverExit`, or custom names (lights, seats...).
Towing, vehicle switching and the player character are game code, not part of
the addon.

## Extending

Add an exported property to a config class: it is saved in .tres and written to
and read from JSON automatically. Use it in `VehicleBuilder.build()` (new nodes)
or `VehicleBuilder.apply_tuning()` (values that may change live).
