extends "res://scripts/pickup_block.gd"

const PLAYER_JUMP := -220.0
const ENEMY_JUMP := -200.0
const COOLDOWN := 0.45


var bounce_cd := 0.0


func _ready() -> void:
	super._ready()
	add_to_group("jumpblocks")
	pickup_area.collision_mask = 9
	pickup_area.monitoring = true
	var shape_node := pickup_area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node and shape_node.shape is RectangleShape2D:
		var rect := (shape_node.shape as RectangleShape2D).duplicate() as RectangleShape2D
		rect.size = Vector2(maxf(rect.size.x, 16.0), maxf(rect.size.y, 22.0))
		shape_node.shape = rect
		shape_node.position.y = -5.0


func _physics_process(delta: float) -> void:
	bounce_cd = maxf(0.0, bounce_cd - delta)
	if carried or bounce_cd > 0.0:
		return
	for body in pickup_area.get_overlapping_bodies():
		if not _standing_on_top(body):
			continue
		_launch(body)
		bounce_cd = COOLDOWN
		return


func _standing_on_top(body: Node) -> bool:
	if body == null or body is not Node2D:
		return false
	var n2d := body as Node2D
	if absf(n2d.global_position.x - global_position.x) > 10.0:
		return false
	var top_y := global_position.y - HALF_EXTENTS.y
	# Must be above the block, not beside or below it (Y grows downward).
	if n2d.global_position.y > top_y + 1.0:
		return false
	if body is CharacterBody2D:
		var cb := body as CharacterBody2D
		if cb.velocity.y < -20.0:
			return false
		return true
	return false


func _launch(body: Node) -> void:
	var enemy := enemy_from_body(body)
	if enemy:
		var status := enemy_status(enemy)
		if status and status.has_method("bounce"):
			status.bounce(ENEMY_JUMP)
		elif enemy is CharacterBody2D:
			(enemy as CharacterBody2D).velocity.y = ENEMY_JUMP
		return
	if body is Node and (body as Node).is_in_group("player") and body is CharacterBody2D:
		(body as CharacterBody2D).velocity.y = PLAYER_JUMP
