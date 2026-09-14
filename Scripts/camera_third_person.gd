extends Node3D

@export var mouse_sensitivity := 0.01
@export var parent_character: CharacterBody3D

var yaw := 0.0
var pitch := -20.0
var is_camera_captured := false


func _ready() -> void:
	yaw = rotation.y
	pitch = $SpringArm3D.rotation.x


func _unhandled_input(event):
	if event.is_action_pressed("left_click"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		is_camera_captured = true

	elif event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		is_camera_captured = false

	if event is InputEventMouseMotion and is_camera_captured:
		yaw -= event.relative.x * mouse_sensitivity

		pitch -= event.relative.y * mouse_sensitivity

		pitch = clamp(
			pitch,
			deg_to_rad(-80.0),
			deg_to_rad(60.0)
		)

		rotation.y = yaw
		$SpringArm3D.rotation.x = pitch
