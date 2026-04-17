# Destroys any HeatSource node whose Area2D enters the WaterArea.
class_name Extinguisher
extends RigidBody2D

@onready var _water_area: Area2D = $WaterArea


func _ready() -> void:
	# area_entered — we detect Fire's HeatArea (Layer 3), not a body.
	_water_area.area_entered.connect(_on_water_area_area_entered)


func _on_water_area_area_entered(area: Area2D) -> void:
	var fire_body: Node = area.get_parent()
	if fire_body is HeatSource:
		fire_body.queue_free()
		# Water evaporates on contact — remove this line to let water persist.
		queue_free()
