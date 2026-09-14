extends AnimatableBody3D

@export var spawn_point : Node3D

@export var direction: Vector3 = Vector3.FORWARD
@export var distance: float = 5.0
@export var speed: float = 2.0

@export var start_at_start_position: bool = true
@export var loop: bool = true

var start_position: Vector3
var end_position: Vector3
var moving_to_end := true

func _ready():
	start_position = global_position
	end_position = start_position + direction.normalized() * distance

func _physics_process(delta):
	if moving_to_end:
		global_position = global_position.move_toward(
			end_position,
			speed * delta
		)

		if global_position.distance_to(end_position) < 0.01:
			global_position = end_position
			moving_to_end = false

	else:
		global_position = global_position.move_toward(
			start_position,
			speed * delta
		)

		if global_position.distance_to(start_position) < 0.01:
			global_position = start_position
			
			if loop:
				moving_to_end = true
		
