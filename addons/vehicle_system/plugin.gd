@tool
extends EditorPlugin
## Adds the "Vehicles" dock (see vehicle_dock.gd).

const VehicleDock := preload("res://addons/vehicle_system/editor/vehicle_dock.gd")

var _dock: Control


func _enter_tree() -> void:
	_dock = VehicleDock.new()
	_dock.name = "Vehicles"
	_dock.plugin = self
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
