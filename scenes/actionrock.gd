extends Area2D

@onready var solid_shape: CollisionShape2D = $Solid/CollisionShape2D

var carried: bool = false

func set_carried(value: bool) -> void:
	carried = value
	# Turn off solid collision while carried so it doesn't push/jitter the player
	solid_shape.disabled = value

	# Optional: stop the pickup area from detecting while carried
	monitoring = not value
