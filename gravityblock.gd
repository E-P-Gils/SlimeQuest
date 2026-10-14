extends "res://scripts/pickup_block.gd"


func _ready() -> void:
	super._ready()
	add_to_group("gravityblocks")
	pickup_area.collision_mask = 1
	pickup_area.monitoring = true
	pickup_area.area_entered.connect(_on_area_entered)


func _on_area_entered(area: Area2D) -> void:
	var enemy := enemy_from_area(area)
	if enemy == null:
		return
	var status := enemy_status(enemy)
	if status and status.has_method("invert_gravity"):
		status.invert_gravity()
