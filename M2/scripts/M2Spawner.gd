# M2Spawner.gd
# Extends the M1 Spawner concept for the CA layer.
# Left-click: paint CA cells at cursor (fast, fluid-like)
# Right-click: instance a full M1 RigidBody2D (for cross-system testing)
#
# This dual approach lets you demonstrate the M1↔M2 bridge in action:
# a M1 Fire RigidBody2D paints fire cells into the CA grid which then
# propagates independently of the physics simulation.
extends Node2D

# ── Element map: key → CA cell type ──────────────────────────────────────────
const ELEMENT_CA_TYPE : Dictionary = {
	"Wood":  CellState.Type.WOOD,
	"Fire":  CellState.Type.FIRE,
	"Water": CellState.Type.WATER,
	"Metal": CellState.Type.METAL,
}

# ── M1 scene preloads (for right-click RigidBody2D instancing) ────────────────
const WOOD_SCENE  : PackedScene = preload("res://scenes/elements/Wood.tscn")
const FIRE_SCENE  : PackedScene = preload("res://scenes/elements/Fire.tscn")
const WATER_SCENE : PackedScene = preload("res://scenes/elements/Water.tscn")
const METAL_SCENE : PackedScene = preload("res://scenes/elements/Metal.tscn")

const M1_SCENES : Dictionary = {
	"Wood": WOOD_SCENE, "Fire": FIRE_SCENE,
	"Water": WATER_SCENE, "Metal": METAL_SCENE,
}

# ── State ─────────────────────────────────────────────────────────────────────
var _selected_element : String = "Fire"
var _brush_radius     : int    = 2   # CA cell radius for painting
var _spawn_cooldown   : float  = 0.0

const COOLDOWN_TIME   : float  = 0.08

@onready var _grid      : CAGrid  = get_parent().get_node("CAGrid")
@onready var _container : Node2D  = get_parent().get_node("ElementContainer")


func _ready() -> void:
	# Wire up UI buttons (same pattern as M1 Spawner).
	var panel := get_node("UI/SelectionPanel")
	for button : Button in panel.get_children():
		var name_key : String = button.name.replace("Button", "")
		button.pressed.connect(func(): _select(name_key))
	_highlight("Fire")

	# Wire radius slider.
	var slider : HSlider = get_node("UI/BrushSlider")
	slider.value_changed.connect(func(v): _brush_radius = int(v))


func _process(delta: float) -> void:
	_spawn_cooldown -= delta

	# Left-click: paint CA cells.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and _spawn_cooldown <= 0.0:
		if not _is_mouse_over_ui():
			var ca_type : int = ELEMENT_CA_TYPE.get(_selected_element, CellState.Type.FIRE)
			_grid.paint_circle(get_global_mouse_position(), ca_type, _brush_radius)
			_spawn_cooldown = COOLDOWN_TIME

	# Right-click: instance M1 RigidBody2D and register with grid.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and _spawn_cooldown <= 0.0:
		if not _is_mouse_over_ui():
			_spawn_m1_body()
			_spawn_cooldown = COOLDOWN_TIME

	# E key: erase (paint EMPTY).
	if Input.is_key_pressed(KEY_E) and _spawn_cooldown <= 0.0:
		if not _is_mouse_over_ui():
			_grid.paint_circle(get_global_mouse_position(), CellState.Type.EMPTY, _brush_radius)
			_spawn_cooldown = COOLDOWN_TIME


func _select(element_name: String) -> void:
	if element_name in ELEMENT_CA_TYPE:
		_selected_element = element_name
		_highlight(element_name)


func _spawn_m1_body() -> void:
	if not _selected_element in M1_SCENES:
		return
	var body : RigidBody2D = M1_SCENES[_selected_element].instantiate()
	_container.add_child(body)
	body.global_position = get_global_mouse_position()
	# Register with the CA grid so it stamps its position each tick.
	_grid.register_body(body)
	# Auto-unregister when the body is freed.
	body.tree_exited.connect(func(): _grid.unregister_body(body))


func _highlight(selected: String) -> void:
	var panel := get_node("UI/SelectionPanel")
	for button : Button in panel.get_children():
		var k : String = button.name.replace("Button", "")
		button.modulate = Color(1.3, 1.3, 0.5) if k == selected else Color.WHITE


func _is_mouse_over_ui() -> bool:
	var panel := get_node("UI/SelectionPanel")
	return panel.get_global_rect().has_point(get_viewport().get_mouse_position())
