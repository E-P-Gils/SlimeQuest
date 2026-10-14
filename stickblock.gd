extends "res://scripts/pickup_block.gd"


func _ready() -> void:
	super._ready()
	add_to_group("stickblocks")
	pickup_area.collision_mask = 8
	pickup_area.monitoring = true
	pickup_area.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	var enemy := enemy_from_body(body)
	if enemy == null:
		return
	var status := enemy_status(enemy)
	if status and status.has_method("stick_freeze"):
		status.stick_freeze()
