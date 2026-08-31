extends CanvasLayer
class_name PlayerJoystickUI

const MAX_TILT = 0.7

@export var translation_speed: float = 5.0
@export var rotation_speed: float = 2.0
@export var mouse_sensitivity: float = 0.3

@onready var joystick_slide = get_node("%JoystickSlide")
@onready var joystick_look = get_node("%JoystickLook")
@onready var joysticks = get_node("%Joysticks")

var current_auto_aim_mode: AutoAim.Mode = AutoAim.Mode.MANUAL
var auto_aim_button: Button


func _ready() -> void:
	_setup_auto_aim_button()


func _setup_auto_aim_button() -> void:
	auto_aim_button = Button.new()
	auto_aim_button.name = "AutoAimButton"
	auto_aim_button.text = "Manual"
	auto_aim_button.custom_minimum_size = Vector2(80, 40)

	# Position the button near the center of the screen or between joysticks
	auto_aim_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	auto_aim_button.offset_bottom = -40
	auto_aim_button.offset_left = -40
	auto_aim_button.offset_right = 40
	auto_aim_button.offset_top = -80

	auto_aim_button.pressed.connect(_on_auto_aim_pressed)
	add_child(auto_aim_button)


func _on_auto_aim_pressed() -> void:
	match current_auto_aim_mode:
		AutoAim.Mode.MANUAL:
			current_auto_aim_mode = AutoAim.Mode.WIDE
			auto_aim_button.text = "Aim:Auto Wide"
		AutoAim.Mode.WIDE:
			current_auto_aim_mode = AutoAim.Mode.LONG
			auto_aim_button.text = "Aim: Auto Long"
		AutoAim.Mode.LONG:
			current_auto_aim_mode = AutoAim.Mode.MANUAL
			auto_aim_button.text = "Aim:Manual"


#func _process(delta):
#var player_list = get_tree().get_nodes_in_group("player")
#for player in player_list:
## --- Gather Touch Inputs ---
#var slide_input = joystick_slide.output
#var look_input = Vector2(joystick_look.output.x, 0)
#
## W/S for Forward/Backward
#slide_input.y += Input.get_axis("move_backward", "move_forward")
#
## A/D for Strafe Left/Right
#slide_input.x += Input.get_axis("move_left", "move_right")
#
## Q/E for Looking Left/Right
#look_input.x += Input.get_axis("look_left", "look_right")
#
## Clamp values to prevent double-speed when combining keyboard + touch
#slide_input = slide_input.limit_length(1.0)
#look_input = look_input.limit_length(1.0)
#
## 1. Apply manual rotations
#player.rotate_object_local(Vector3.RIGHT, -look_input.y * rotation_speed * delta)
#player.rotate_object_local(Vector3.UP, -look_input.x * rotation_speed * delta)
#
## 2. AUTOMATIC STRAIGHTENING LOGIC
#var current_basis: Basis = player.global_transform.basis
#if abs(current_basis.z.y) < MAX_TILT:
#var upright_speed: float = 2.0
#var target_basis: Basis = Basis.looking_at(-current_basis.z, Vector3.UP)
#player.global_transform.basis = (
#current_basis.slerp(target_basis, upright_speed * delta).orthonormalized()
#)
#
## 3. Handle translation/movement
#var cam_basis = player.global_transform.basis
#var direction = Vector3.ZERO
#direction += cam_basis.x * slide_input.x
#direction -= cam_basis.y * slide_input.y
#
#player.global_position += direction * translation_speed * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var player_list = get_tree().get_nodes_in_group("player")

		for player in player_list:
			player.rotate_object_local(
				Vector3.UP, -deg_to_rad(event.relative.x * mouse_sensitivity)
			)
			player.rotate_object_local(
				Vector3.RIGHT, -deg_to_rad(event.relative.y * mouse_sensitivity)
			)
			return

		var camera = get_viewport().get_camera_3d()
		if camera:
			camera.rotate_object_local(
				Vector3.UP, -deg_to_rad(event.relative.x * mouse_sensitivity)
			)
			camera.rotate_object_local(
				Vector3.RIGHT, -deg_to_rad(event.relative.y * mouse_sensitivity)
			)
