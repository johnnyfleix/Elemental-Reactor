extends Node2D

const WOOD_SCENE  : PackedScene = preload("res://scenes/elements/Wood.tscn")
const FIRE_SCENE  : PackedScene = preload("res://scenes/elements/Fire.tscn")
const WATER_SCENE : PackedScene = preload("res://scenes/elements/Water.tscn")
const METAL_SCENE : PackedScene = preload("res://scenes/elements/Metal.tscn")

var _element_map : Dictionary = {
	"Wood":  WOOD_SCENE,
	"Fire":  FIRE_SCENE,
	"Water": WATER_SCENE,
	"Metal": METAL_SCENE,
}

var _selected_element : String = "Wood"

const SPAWN_COOLDOWN : float = 0.12
var   _spawn_timer   : float = 0.0

@onready var _container : Node2D = get_parent().get_node("ElementContainer")


func _ready() -> void:
	var panel : Control = get_node("UI/SelectionPanel")
	for button : Button in panel.get_children():
		var element_name : String = button.name.replace("Button", "")
		button.pressed.connect(func(): _select_element(element_name))
	# Highlight the default button.
	_highlight_button("Wood")


func _process(delta: float) -> void:
	if _spawn_timer > 0.0:
		_spawn_timer -= delta

	if Input.is_action_pressed("click") and _spawn_timer <= 0.0:
		# Don't spawn if the mouse is over the UI panel.
		if not _is_mouse_over_ui():
			_spawn_at_cursor()
			_spawn_timer = SPAWN_COOLDOWN


func _select_element(element_name: String) -> void:
	if element_name in _element_map:
		_selected_element = element_name
		_highlight_button(element_name)


func _spawn_at_cursor() -> void:
	if not _selected_element in _element_map:
		return
	var instance : RigidBody2D = _element_map[_selected_element].instantiate()
	_container.add_child(instance)
	instance.global_position = get_global_mouse_position()


func _highlight_button(selected: String) -> void:
	var panel : Control = get_node("UI/SelectionPanel")
	for button : Button in panel.get_children():
		var element_name : String = button.name.replace("Button", "")
		button.modulate = Color.WHITE if element_name != selected else Color(1.3, 1.3, 0.5)


func _is_mouse_over_ui() -> bool:
	# Prevent spawning through the button panel.
	var panel : Control = get_node("UI/SelectionPanel")
	var mouse := get_viewport().get_mouse_position()
	var rect  := panel.get_global_rect()
	return rect.has_point(mouse)
