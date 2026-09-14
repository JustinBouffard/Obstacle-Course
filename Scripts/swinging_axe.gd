extends AnimatableBody3D

@export var swing_angle: float = 60.0
@export var period: float = 2.0
@export var rotation_axis: Vector3 = Vector3(0, 0, 1)

@onready var pivot: Node3D = $Pivot

var start_rotation: Quaternion
var time := 0.0


func _ready():
	start_rotation = pivot.quaternion


func _physics_process(delta):
	time += delta
	var angle := swing_angle * sin(time * TAU / period)

	pivot.quaternion = start_rotation * Quaternion(
		rotation_axis.normalized(),
		deg_to_rad(angle)
	)
