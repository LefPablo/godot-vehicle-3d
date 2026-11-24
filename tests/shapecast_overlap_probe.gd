extends Node
## Diagnostic: how does a ShapeCast3D behave when its shape starts inside geometry?

const DEMO := preload("res://scenes/demo/demo.tscn")
const WheelScript := preload("res://scripts/vehicle/shapecast_wheel.gd")

var frame := 0
var probe: ShapeCast3D


func _ready() -> void:
	add_child(DEMO.instantiate())
	# Same wheel hull as the car uses.
	var wheel := WheelScript.new()
	probe = ShapeCast3D.new()
	probe.shape = wheel._make_wheel_shape()
	probe.max_results = 4
	probe.enabled = false
	add_child(probe)
	wheel.free()


func _physics_process(_delta: float) -> void:
	frame += 1
	if frame == 1200:
		get_tree().quit()
	if frame != 5:
		return
	# The 25 cm step in the Big Bumps lane: front face at z=-76, top at y=0.25.
	_case("clear above step, sweep down", Vector3(-16, 1.2, -78), 1.2)
	_case("just past step face, bottom of wheel 3 cm below step top", Vector3(-16, 0.576, -76.1), 0.35)
	_case("before step face, wheel front overlaps face", Vector3(-16, 0.40, -75.8), 0.35)
	_case("flat ground, wheel starts 5 cm into ground", Vector3(0, 0.31, 20), 0.35)


func _case(label: String, pos: Vector3, length: float) -> void:
	probe.global_position = pos
	probe.target_position = Vector3(0, -length, 0)
	probe.force_shapecast_update()
	var text := "%s: colliding=%s safe=%.3f unsafe=%.3f count=%d" % [
		label, probe.is_colliding(), probe.get_closest_collision_safe_fraction(),
		probe.get_closest_collision_unsafe_fraction(), probe.get_collision_count()]
	for i in probe.get_collision_count():
		text += " | p=%s n=%s" % [probe.get_collision_point(i), probe.get_collision_normal(i)]
	print(text)
