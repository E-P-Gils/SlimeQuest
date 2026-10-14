extends Node

const GRAVITY := 200.0
const STICK_TIME := 2.5
const INVERT_TIME := 30.0
const CEILING_SPEED := 28.0
const LIFT := -220.0
const WARP_COOLDOWN := 1.15

var host: CharacterBody2D
var sprite: AnimatedSprite2D
var freeze_left := 0.0
var invert_left := 0.0
var warp_cd := 0.0
var frozen_pos := Vector2.ZERO
var walk_dir := 1


func _ready() -> void:
	name = "EnemyStatus"
	host = get_parent() as CharacterBody2D
	if host:
		sprite = host.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	set_physics_process(false)


func _process(delta: float) -> void:
	warp_cd = maxf(0.0, warp_cd - delta)


func stick_freeze(duration: float = STICK_TIME) -> void:
	if host == null:
		return
	_clear_invert_visuals()
	invert_left = 0.0
	freeze_left = duration
	frozen_pos = host.global_position
	host.velocity = Vector2.ZERO
	_seize_control()
	if sprite:
		sprite.modulate = Color(0.65, 1.0, 0.7)


func invert_gravity(duration: float = INVERT_TIME) -> void:
	if host == null:
		return
	freeze_left = 0.0
	if sprite:
		sprite.modulate = Color.WHITE
		sprite.flip_v = true
		sprite.rotation = 0.0
	invert_left = duration
	host.up_direction = Vector2.DOWN
	host.floor_snap_length = 8.0
	host.set("flying", false)
	host.collision_mask = 1
	host.motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	var facing: Variant = host.get("facing_dir")
	walk_dir = 1 if (facing is int and facing >= 0) or (facing is float and facing >= 0.0) else -1
	host.velocity = Vector2(float(walk_dir) * CEILING_SPEED, LIFT)
	_seize_control()


func warp_to(pos: Vector2) -> bool:
	if host == null or warp_cd > 0.0:
		return false
	warp_cd = WARP_COOLDOWN
	host.global_position = pos
	host.velocity = Vector2.ZERO
	return true


func bounce(jump_velocity: float) -> void:
	if host == null or freeze_left > 0.0:
		return
	host.velocity.y = jump_velocity


func clear(restore_ai: bool = true) -> void:
	freeze_left = 0.0
	invert_left = 0.0
	_clear_invert_visuals()
	if sprite:
		sprite.modulate = Color.WHITE
	if restore_ai:
		_release_control()
	else:
		set_physics_process(false)


func _seize_control() -> void:
	_stop_attack()
	if host.has_method("_clear_fireball"):
		host.call("_clear_fireball")
	host.set_physics_process(false)
	set_physics_process(true)


func _release_control() -> void:
	set_physics_process(false)
	if host == null or not is_instance_valid(host):
		return
	host.set_physics_process(true)
	if host.has_method("_enter_idle"):
		host.call("_enter_idle")


func _clear_invert_visuals() -> void:
	if host:
		host.up_direction = Vector2.UP
	if sprite:
		sprite.flip_v = false


func _stop_attack() -> void:
	var hitbox: Variant = host.get("attack_hitbox")
	if hitbox is Area2D:
		(hitbox as Area2D).set_deferred("monitoring", false)


func _physics_process(delta: float) -> void:
	if host == null or not is_instance_valid(host):
		return
	if freeze_left > 0.0:
		freeze_left -= delta
		host.global_position = frozen_pos
		host.velocity = Vector2.ZERO
		if freeze_left <= 0.0:
			if sprite:
				sprite.modulate = Color.WHITE
			_release_control()
		return
	if invert_left > 0.0:
		invert_left -= delta
		if _snap_to_ceiling():
			if host.is_on_wall():
				walk_dir *= -1
				host.set("facing_dir", walk_dir)
			host.velocity.x = float(walk_dir) * CEILING_SPEED
			host.velocity.y = 0.0
		else:
			host.velocity.y -= GRAVITY * delta
		_play_walk()
		host.move_and_slide()
		if invert_left <= 0.0:
			_clear_invert_visuals()
			if sprite:
				sprite.modulate = Color.WHITE
			host.velocity.y = 40.0
			_release_control()


func _snap_to_ceiling() -> bool:
	var space := host.get_world_2d().direct_space_state
	var half := _body_half_height()
	var query := PhysicsRayQueryParameters2D.create(
		host.global_position,
		host.global_position + Vector2(0.0, -(half + 20.0))
	)
	query.exclude = [host.get_rid()]
	query.collision_mask = 1
	query.hit_from_inside = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return host.is_on_floor()
	host.global_position.y = hit.position.y + half
	return true


func _body_half_height() -> float:
	var shape_node := host.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or shape_node.shape == null:
		return 8.0
	var shape := shape_node.shape
	if shape is RectangleShape2D:
		return (shape as RectangleShape2D).size.y * 0.5
	if shape is CapsuleShape2D:
		return (shape as CapsuleShape2D).height * 0.5
	if shape is CircleShape2D:
		return (shape as CircleShape2D).radius
	return 8.0


func _play_walk() -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	var facing: Variant = host.get("facing_dir")
	var right := true
	if facing is int:
		right = facing >= 0
	elif facing is float:
		right = facing >= 0.0
	var anim := StringName("walk_right" if right else "walk_left")
	if sprite.sprite_frames.has_animation(anim):
		if sprite.animation != anim:
			sprite.play(anim)
	else:
		anim = StringName("idle_right" if right else "idle_left")
		if sprite.sprite_frames.has_animation(anim) and sprite.animation != anim:
			sprite.play(anim)
