extends RigidBody2D

const BLAST_RADIUS := 42.0
const PLAYER_HURT_RANGE := 36.0
const ENEMY_KNOCK := Vector2(180.0, -90.0)
const HALF_EXTENTS := Vector2(5.0, 5.0)
const WALL_PROBE := 8.0

@onready var solid_shape: CollisionShape2D = $CollisionShape2D
@onready var pickup_area: Area2D = $pickup
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var floor_ray: RayCast2D = $RayCast2D

var carried := false
var exploding := false


func _ready() -> void:
	lock_rotation = true
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	collision_layer = 1
	collision_mask = 1
	add_to_group("bombblocks")
	pickup_area.area_entered.connect(_on_pickup_area_entered)
	_setup_floor_ray()
	var frames := sprite.sprite_frames
	if frames and frames.has_animation(&"explode"):
		frames.set_animation_loop(&"explode", false)
	sprite.animation_finished.connect(_on_sprite_finished)
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(&"idle"):
		sprite.play(&"idle")


func _setup_floor_ray() -> void:
	floor_ray.enabled = true
	floor_ray.hit_from_inside = true
	floor_ray.collide_with_bodies = true
	floor_ray.collide_with_areas = false
	floor_ray.collision_mask = collision_mask
	if floor_ray.target_position.length() < 4.0:
		floor_ray.target_position = Vector2(0, 8)


func set_carried(value: bool) -> void:
	carried = value
	solid_shape.disabled = value
	freeze = value
	floor_ray.enabled = not value
	if value:
		linear_velocity = Vector2.ZERO
		angular_velocity = 0.0
	# Keep pickup monitoring so enemy attacks can still strike a held bomb.


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if carried or exploding:
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
			# Skip the floor we're standing on (upward normal at our feet).
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


func explode() -> void:
	if exploding:
		return
	exploding = true
	floor_ray.enabled = false
	_release_from_carrier()
	freeze = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	solid_shape.set_deferred("disabled", true)
	pickup_area.set_deferred("monitoring", false)
	sprite.scale = Vector2(0.22, 0.22)
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(&"explode"):
		sprite.play(&"explode")
	else:
		_apply_blast()
		queue_free()
		return
	_apply_blast()


func _release_from_carrier() -> void:
	for p in get_tree().get_nodes_in_group("player"):
		if p.get("carried_block") == self:
			p.set("carried_block", null)
	var level := get_tree().current_scene
	if level and get_parent() != level:
		var pos := global_position
		reparent(level, true)
		global_position = pos


func _on_pickup_area_entered(area: Area2D) -> void:
	if exploding or not area.monitoring:
		return
	var n: Node = area
	while n:
		if n.is_in_group("enemies"):
			explode()
			return
		n = n.get_parent()


func _apply_blast() -> void:
	var origin := global_position
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy is Node2D and origin.distance_to((enemy as Node2D).global_position) <= BLAST_RADIUS:
			_hurt_enemy(enemy, origin)
	for player in get_tree().get_nodes_in_group("player"):
		if player is Node2D and origin.distance_to((player as Node2D).global_position) <= PLAYER_HURT_RANGE:
			_hurt_player(player, origin)


func _hurt_enemy(enemy: Node, origin: Vector2) -> void:
	var blast: Node = enemy.get_node_or_null("EnemyBlast")
	if blast and blast.has_method("take_bomb_hit"):
		blast.take_bomb_hit(origin)
	elif enemy.has_method("take_bomb_hit"):
		enemy.take_bomb_hit(origin)


func _hurt_player(player: Node, origin: Vector2) -> void:
	var knock_dir := signf(player.global_position.x - origin.x)
	if knock_dir == 0.0:
		knock_dir = 1.0
	if player.has_method("take_hit"):
		player.take_hit(knock_dir, ENEMY_KNOCK, 2)


func _on_sprite_finished() -> void:
	if exploding:
		queue_free()
