class_name HeatSource
extends RigidBody2D

@onready var _heat_area: Area2D = $HeatArea
@onready var _sprite: ColorRect = $ColorRect


func _ready() -> void:
	_heat_area.body_entered.connect(_on_heat_area_body_entered)
	_heat_area.body_exited.connect(_on_heat_area_body_exited)
	# Flicker effect using a Tween
	_start_flicker()


func _on_heat_area_body_entered(body: Node2D) -> void:
	if body is Flammable:
		body.ignite()
	elif body is Conductor:
		body.start_conducting()


func _on_heat_area_body_exited(body: Node2D) -> void:
	if body is Conductor:
		body.stop_conducting()


func _start_flicker() -> void:
	# Simple colour flicker between orange and yellow using a looping Tween.
	var tween := create_tween().set_loops()
	tween.tween_property(_sprite, "color", Color(1.0, 0.85, 0.1), 0.15)
	tween.tween_property(_sprite, "color", Color(1.0, 0.4, 0.05), 0.15)
