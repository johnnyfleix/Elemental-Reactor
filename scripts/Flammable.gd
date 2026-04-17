# Reacts to heat from HeatSource nodes that overlap its Area2D.
# This script LISTENS — it never polls. It reacts to signals only.
class_name Flammable
extends RigidBody2D

const BURNING_MODULATE: Color = Color(1.0, 0.45, 0.1, 1.0)
const NORMAL_MODULATE: Color = Color.WHITE

var _is_burning: bool = false

@onready var _sprite: ColorRect = $ColorRect
@onready var _burn_timer: Timer = $BurnTimer


func _ready() -> void:
	_burn_timer.timeout.connect(_on_burn_complete)


## Called by HeatSource (via signal) or Conductor when heat is applied.
## Idempotent — safe to call multiple times (won't restart the timer).
func ignite() -> void:
	if _is_burning:
		return
	_is_burning = true
	_sprite.color = BURNING_MODULATE
	_burn_timer.start()


func _on_burn_complete() -> void:
	queue_free()
