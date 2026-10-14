extends RigidBody2D

const HALF_EXTENTS := Vector2(4.0, 4.0)
const WALL_PROBE := 8.0

@onready var solid_shape: CollisionShape2D = $CollisionShape2D
@onready var pickup_area: Area2D = $pickup
@onready var floor_ray: RayCast2D = $RayCast2D

var carried := false


func _ready() -> void:
	lock_rotation = true
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	collision_layer = 1
	collision_mask = 1
	pickup_area.collision_layer = 3
	pickup_area.monitorable = true
	pickup_area.monitoring = true
	_ensure_grab_size()
	_setup_floor_ray()
	var sprite := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(&"idle"):
		sprite.play(&"idle")


func _setup_floor_ray() -> void:
	floor_ray.enabled = true
	floor_ray.hit_from_inside = true
	floor_ray.collide_with_bodies = true
	floor_ray.collide_with_areas = false
	floor_ray.collision_mask = collision_mask
	if floor_ray.target_position.length() < 4.0:
		floor_ray.target_position = Vector2(0, 8)


func _ensure_grab_size() -> void:
	var shape_node := pickup_area.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or shape_node.shape is not RectangleShape2D:
		return
	var rect := (shape_node.shape as RectangleShape2D).duplicate() as RectangleShape2D
	rect.size = Vector2(maxf(rect.size.x, 24.0), maxf(rect.size.y, 16.0))
	shape_node.shape = rect


func set_carried(value: bool) -> void:
	carried = value
	solid_shape.set_deferred("disabled", value)
	freeze = value
	floor_ray.enabled = not value
	# Keep the pickup area live so the slime can grab it, and so held
	# blocks can still be struck / touched by enemies.
	if value:
		linear_velocity = Vector2.ZERO
		angular_velocity = 0.0
		sleeping = true
		position = Vector2.ZERO
		rotation = 0.0
	else:
		sleeping = false


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if carried:
		return
	_snap_to_floor(state)
	_block_side_walls(state)


func _snap_to_floor(state: PhysicsDirectBodyState2D) -> void:
	floor_ray.force_raycast_update()
	if not floor_ray.is_colliding():
		return
	var hit := floor_ray.get_collision_point()
	var normal := floor_ray.get_collision_normal()
	if normal.y > -0.35:
		return
	var xform := state.transform
	var rest_y := hit.y - HALF_EXTENTS.y
	if xform.origin.y >= rest_y - 1.5:
		xform.origin.y = rest_y
		state.transform = xform
		var velocity := state.linear_velocity
		if velocity.y > 0.0:
			velocity.y = 0.0
		state.linear_velocity = velocity


func _block_side_walls(state: PhysicsDirectBodyState2D) -> void:
	var space := state.get_space_state()
	var origin := state.transform.origin
	var feet_y := origin.y + HALF_EXTENTS.y
	for dir in [-1.0, 1.0]:
		for y_off in [-3.0, 0.0, 3.0]:
			var from := origin + Vector2(0.0, y_off)
			var query := PhysicsRayQueryParameters2D.create(
				from,
				from + Vector2(dir * WALL_PROBE, 0.0)
			)
			query.exclude = [get_rid()]
			query.collision_mask = collision_mask
			query.hit_from_inside = true
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				continue
			var normal: Vector2 = hit.normal
			var hit_pos: Vector2 = hit.position
			if normal.y < -0.5 and hit_pos.y >= feet_y - 2.0:
				continue
			var xform := state.transform
			xform.origin.x = hit_pos.x - dir * HALF_EXTENTS.x
			state.transform = xform
			var velocity := state.linear_velocity
			if signf(velocity.x) == dir:
				velocity.x = 0.0
			state.linear_velocity = velocity
			return


func enemy_from_area(area: Area2D) -> Node:
	if not is_instance_valid(area) or not area.monitoring:
		return null
	return _enemy_ancestor(area)


func enemy_from_body(body: Node) -> Node:
	return _enemy_ancestor(body)


func _enemy_ancestor(n: Node) -> Node:
	while n:
		if n.is_in_group("enemies"):
			return n
		n = n.get_parent()
	return null


func enemy_status(enemy: Node) -> Node:
	if enemy == null:
		return null
	return enemy.get_node_or_null("EnemyStatus")
