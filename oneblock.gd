extends "res://scripts/pickup_block.gd"


func _ready() -> void:
	super._ready()
	add_to_group("one_blocks")
	pickup_area.collision_mask = 1
	pickup_area.monitoring = true
	pickup_area.area_entered.connect(_on_area_entered)


func _on_area_entered(area: Area2D) -> void:
	var enemy := enemy_from_area(area)
	if enemy == null:
		return
	_warp_enemy(enemy, "two_blocks")


func _warp_enemy(enemy: Node, dest_group: String) -> void:
	var dests := get_tree().get_nodes_in_group(dest_group)
	var dest: Node2D = null
	var best := INF
	for n in dests:
		if n is Node2D and is_instance_valid(n):
			var d := global_position.distance_squared_to((n as Node2D).global_position)
			if d < best:
				best = d
				dest = n as Node2D
	if dest == null:
		return
	var status := enemy_status(enemy)
	var land := dest.global_position + Vector2(0.0, -18.0)
	if status and status.has_method("warp_to"):
		status.warp_to(land)
	elif enemy is Node2D:
		(enemy as Node2D).global_position = land
