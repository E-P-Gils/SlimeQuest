extends RigidBody2D

@onready var solid_shape: CollisionShape2D = $CollisionShape2D
@onready var pickup_area: Area2D = $PickupArea

var carried: bool = false

func set_carried(value: bool) -> void:
	carried = value

	# Disable solid collision while carried
	solid_shape.disabled = value

	# Disable pickup detection while carried
	pickup_area.monitoring = not value

	# Carried blocks should not simulate physics.
	freeze = value
	if value:
		linear_velocity = Vector2.ZERO
		angular_velocity = 0.0
