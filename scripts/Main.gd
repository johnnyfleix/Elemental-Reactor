# Main.gd
# Root scene script. Builds viewport-fitting walls procedurally.
extends Node2D


func _ready() -> void:
	_build_walls()


func _build_walls() -> void:
	var W : float = get_viewport_rect().size.x
	var H : float = get_viewport_rect().size.y
	const T : float = 40.0  # wall thickness

	# [center_position, size]
	var wall_data : Array = [
		[Vector2(W / 2.0, H + T / 2.0), Vector2(W, T)],   # floor
		[Vector2(W / 2.0, -T / 2.0),    Vector2(W, T)],   # ceiling
		[Vector2(-T / 2.0, H / 2.0),    Vector2(T, H)],   # left
		[Vector2(W + T / 2.0, H / 2.0), Vector2(T, H)],   # right
	]

	for data in wall_data:
		var body  := StaticBody2D.new()
		var shape := CollisionShape2D.new()
		var rect  := RectangleShape2D.new()
		rect.size              = data[1]
		shape.shape            = rect
		body.position          = data[0]
		body.collision_layer   = 1   # "walls" layer
		body.collision_mask    = 0
		body.add_child(shape)
		$Walls.add_child(body)
