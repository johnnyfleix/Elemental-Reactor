# Does not burn. When touching a HeatSource, relays heat to nearby Flammables.
class_name Conductor
extends RigidBody2D

const HEAT_SOAK_TIME: float = 1.5

var _is_heated: bool = false
var _heat_soak_timer: float = 0.0

@onready var _conductor_area: Area2D = $ConductorArea
@onready var _sprite: ColorRect = $ColorRect


func start_conducting() -> void:
	_is_heated = true
	_heat_soak_timer = 0.0
	# Tint metal red-hot to give visual feedback.
	var tween := create_tween()
	tween.tween_property(_sprite, "color", Color(0.9, 0.2, 0.1), HEAT_SOAK_TIME)


func stop_conducting() -> void:
	_is_heated = false
	_heat_soak_timer = 0.0
	var tween := create_tween()
	tween.tween_property(_sprite, "color", Color(0.55, 0.55, 0.6), 1.0)


func _physics_process(delta: float) -> void:
	if not _is_heated:
		return

	_heat_soak_timer += delta
	if _heat_soak_timer < HEAT_SOAK_TIME:
		return

	for body: Node2D in _conductor_area.get_overlapping_bodies():
		if body is Flammable:
			body.ignite()
