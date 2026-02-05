extends Node2D

@onready var solid_shape: CollisionShape2D = $Solid/CollisionShape2D
@onready var pickup_area: Area2D = $PickupArea

var carried: bool = false

func set_carried(value: bool) -> void:
	carried = value

	# Disable solid collision while carried
	solid_shape.disabled = value

	# Disable pickup detection while carried
	pickup_area.monitoring = not value
