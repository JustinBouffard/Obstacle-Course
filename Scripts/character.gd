extends CharacterBody3D

@export var camera: Camera3D
@export var player_model: Node3D

@export var SPEED = 5.0
@export var RUN_SPEED = 15.0
@export var JUMP_VELOCITY = 4.5
@export var max_jumps := 2
@export var rotation_speed := 10.0
@export var spawn_point : Node3D

var jump_count = max_jumps
var current_speed = SPEED
var is_running: bool

var min_fov = 25
var max_fov = 150

var did_double_jump := false
var input_enabled := true
var triggered := false

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var animation_tree: AnimationTree = $AnimationTree

func _physics_process(delta: float) -> void:
	if input_enabled:
		# Remember whether we were on the floor before movement.
		var was_on_floor = is_on_floor()

		# Gravity
		if not is_on_floor():
			velocity += get_gravity() * delta
		else:
			jump_count = max_jumps

		# Jump
		if Input.is_action_just_pressed("ui_accept") and jump_count > 0:
			velocity.y = JUMP_VELOCITY

			# If one jump was remaining, this is the double jump.
			if jump_count == 1:
				did_double_jump = true
			else:
				did_double_jump = false

			jump_count -= 1

		# Running
		if Input.is_action_pressed("run"):
			current_speed = RUN_SPEED
			is_running = true
		else:
			current_speed = SPEED
			is_running = false

		# Get movement input
		var input_dir := Input.get_vector(
			"ui_left",
			"ui_right",
			"ui_up",
			"ui_down"
		)

		# Camera-relative movement
		var camera_forward := -camera.global_transform.basis.z
		var camera_right := camera.global_transform.basis.x

		# Ignore camera's vertical angle.
		camera_forward.y = 0
		camera_right.y = 0

		camera_forward = camera_forward.normalized()
		camera_right = camera_right.normalized()

		var direction := (
			camera_right * input_dir.x +
			camera_forward * -input_dir.y
		).normalized()

		# Movement + character rotation
		if direction:
			velocity.x = direction.x * current_speed
			velocity.z = direction.z * current_speed

			# Rotate the MODEL toward the movement direction.
			var target_rotation := atan2(
				direction.x,
				direction.z
			)

			player_model.rotation.y = lerp_angle(
				player_model.rotation.y,
				target_rotation,
				rotation_speed * delta
			)
		else:
			velocity.x = move_toward(
				velocity.x,
				0,
				current_speed
			)

			velocity.z = move_toward(
				velocity.z,
				0,
				current_speed
			)

		# Move first so is_on_floor() gets updated.
		move_and_slide()

		# Update animations after movement.
		animate(was_on_floor)

		if not triggered:
			for i in get_slide_collision_count():
				var collider = get_slide_collision(i).get_collider()
				if collider.is_in_group("end_zone"):
					_on_end_zone_touched(collider as EndZone)
					break


func _unhandled_input(event):
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				camera.fov = clamp(
					camera.fov + 1,
					min_fov,
					max_fov
				)

			MOUSE_BUTTON_WHEEL_DOWN:
				camera.fov = clamp(
					camera.fov - 1,
					min_fov,
					max_fov
				)

func respawn():
	global_position = spawn_point.global_position
	velocity = Vector3.ZERO

func animate(was_on_floor: bool):
	var horizontal_speed = Vector2(
		velocity.x,
		velocity.z
	).length()

	# Idle
	$AnimationTree["parameters/conditions/is_idle"] = (
		is_on_floor()
		and horizontal_speed < 0.05
	)

	# Walking
	$AnimationTree["parameters/conditions/is_walking"] = (
		is_on_floor()
		and horizontal_speed >= 0.05
		and not is_running
	)

	# Running
	$AnimationTree["parameters/conditions/is_running"] = (
		is_on_floor()
		and is_running
		and horizontal_speed > 0.05
	)

	# First jump
	$AnimationTree["parameters/conditions/is_jumping"] = (
		was_on_floor
		and not is_on_floor()
		and velocity.y > 0
	)

	# Double jump
	$AnimationTree["parameters/conditions/is_double_jumping"] = (
		did_double_jump
	)

	# Falling
	$AnimationTree["parameters/conditions/is_falling"] = (
		not is_on_floor()
		and velocity.y < 0
	)

	# Landing
	$AnimationTree["parameters/conditions/is_landing"] = (
		not was_on_floor
		and is_on_floor()
	)

	# Jump button
	$AnimationTree["parameters/conditions/jump_pressed"] = (
		Input.is_action_just_pressed("ui_accept")
	)

	did_double_jump = false

func play_salsa():
	animation_player.play("SalsaDancing")

func set_input_enabled(value: bool):
	input_enabled = value

func _on_end_zone_touched(end_zone: EndZone):
	triggered = true
	input_enabled = false
	velocity = Vector3.ZERO
	animation_tree.active = false

	end_zone.congrats_label.text = "Congradulations!"
	end_zone.congrats_label.show()
	play_salsa()
