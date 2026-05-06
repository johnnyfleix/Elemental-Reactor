# M2Main.gd
# Root script for the M2 scene.
# Responsibilities:
#   1. Build procedural walls
#   2. Wire CARenderer and CABenchmark to CAGrid via signals
#   3. Move ElementContainer above CARenderer in draw order so M1 sprites
#      render ON TOP of the CA texture (fixes the "diamond" visibility issue)
#   4. Tab key → switch back to M1
extends Node2D


func _ready() -> void:
	_build_walls()
	_wire_nodes()
	_fix_draw_order()

	print("[M2] Ready. Grid: %dx%d  Cell: %.1f×%.1fpx" % [
		CAGrid.COLS, CAGrid.ROWS,
		$CAGrid.cell_w, $CAGrid.cell_h
	])


func _wire_nodes() -> void:
	var grid     : CAGrid       = $CAGrid
	var renderer : CARenderer   = $CARenderer
	var bench    : CABenchmark  = $BenchmarkUI/BenchmarkLabel

	# Assign grid reference then connect — order matters here.
	renderer._grid = grid
	grid.grid_updated.connect(renderer._on_grid_updated)

	bench._grid = grid
	grid.grid_updated.connect(bench._on_grid_updated)


func _fix_draw_order() -> void:
	# In Godot 2D, children draw in scene-tree order (top = drawn first = behind).
	# The scene tree order is:  Background → CARenderer → ElementContainer
	# That means the CA texture draws OVER the M1 sprites — wrong.
	# We move ElementContainer to be the LAST child so it draws on top.
	var container := $ElementContainer
	move_child(container, get_child_count() - 1)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _build_walls() -> void:
	var W : float = get_viewport_rect().size.x
	var H : float = get_viewport_rect().size.y
	const T : float = 40.0

	var wall_data : Array = [
		[Vector2(W / 2.0, H + T / 2.0), Vector2(W, T)],
		[Vector2(W / 2.0, -T / 2.0),    Vector2(W, T)],
		[Vector2(-T / 2.0, H / 2.0),    Vector2(T, H)],
		[Vector2(W + T / 2.0, H / 2.0), Vector2(T, H)],
	]
	

	for data in wall_data:
		var body  := StaticBody2D.new()
		var shape := CollisionShape2D.new()
		var rect  := RectangleShape2D.new()
		rect.size            = data[1]
		shape.shape          = rect
		body.position        = data[0]
		body.collision_layer = 1
		body.collision_mask  = 0
		body.add_child(shape)
		$Walls.add_child(body)
