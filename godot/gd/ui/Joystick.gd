@tool
extends ColorRect
class_name Joystick

enum AxisMode { FREE, VERTICAL_ONLY, HORIZONTAL_ONLY }

@export var mode: AxisMode = AxisMode.FREE:
	set(value):
		mode = value
		_update_visuals()

@onready var stick = $Stick

var dragging = false
var max_distance = 128.0  # Half of 256
var output = Vector2.ZERO


func _ready():
	_update_visuals()


func _update_visuals():
	if not is_inside_tree() or not stick:
		return

	var base = self
	match mode:
		AxisMode.VERTICAL_ONLY:
			base.size = Vector2(64, 256)
			#base.position = Vector2((size.x / 2) - 64, (size.y / 2) - 64)
		AxisMode.HORIZONTAL_ONLY:
			base.size = Vector2(256, 64)
			#base.position = Vector2((size.x / 2) - 64, (size.y / 2) - 64)
		AxisMode.FREE:
			base.size = Vector2(256, 256)
			#base.position = Vector2((size.x / 2) - 128, (size.y / 2) - 128)

	if stick:
		stick.position = (base.size / 2) - (stick.size / 2)


func _gui_input(event):
	#if Engine.is_editor_hint():
	#return
	#if OS.has_feature("editor"):
	#return
	var base = self
	var center = base.size / 2
	var stick_center_offset = stick.size / 2

	if event is InputEventScreenTouch:
		accept_event()
		dragging = event.pressed
		if not dragging:
			stick.position = center - stick_center_offset
	#if event is InputEventMouseButton:
	#if event.button_index == MOUSE_BUTTON_LEFT:
	#dragging = event.pressed
	#if not dragging:
	#stick.position = center - stick_center_offset

	if event is InputEventScreenDrag:
		accept_event()
		if dragging:
			#if event is InputEventMouseMotion and dragging:
			var base_local_mouse = event.position  #- base.position
			var new_pos = base_local_mouse - center

			match mode:
				AxisMode.VERTICAL_ONLY:
					new_pos.x = 0
				AxisMode.HORIZONTAL_ONLY:
					new_pos.y = 0

			stick.position = new_pos.limit_length(max_distance) + (center - stick_center_offset)

	var pressed = "unknown"
	if event is InputEventMouseButton:
		pressed = str(event.pressed)
	#get_tree().get_first_node_in_group("note_label").text = (
	#"joystick " + name + " " + event.get_class() + " " + pressed + " " + str(event.position)
	#)


func _process(_delta):
	var base = self
	if dragging:
		var center = base.size / 2
		var stick_center = stick.position + (stick.size / 2)
		output = (stick_center - center) / max_distance
	else:
		output = Vector2.ZERO
