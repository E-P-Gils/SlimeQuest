extends CharacterBody2D

enum States { IDLE, WALK, ATTACK }

const GRAVITY := 200.0

@export var patrol_speed := 40.0
@export var chase_speed := 70.0
@export var patrol_radius := 80.0
@export var idle_time_min := 1.2
@export var idle_time_max := 2.6
@export var sight_range := 140.0
@export var sight_lost_time := 1.6
@export var attack_range := 18.0
@export var attack_cooldown := 0.7
@export var attack_knockback := Vector2(120.0, -60.0)
@export var look_ahead := 10.0
@export var max_step_down := 20.0
@export var max_step_up := 1.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var floor_ray: RayCast2D = $RayCast2D
@onready var attack_hitbox: Area2D = $Area2D

var state: States = States.IDLE
var facing_dir: int = -1
var home_x: float
var patrol_target_x: float
var idle_timer := 0.0
var sight_memory := 0.0
var attack_ready_in := 0.0
var chase_target: Node2D
var did_hit_this_attack := false

func _ready() -> void:
	home_x = global_position.x
	patrol_target_x = home_x
	add_to_group("enemies")

	if animated_sprite.sprite_frames:
		animated_sprite.sprite_frames.set_animation_loop("attack_left", false)
		animated_sprite.sprite_frames.set_animation_loop("attack_right", false)

	if not animated_sprite.animation_finished.is_connected(_on_animation_finished):
		animated_sprite.animation_finished.connect(_on_animation_finished)

	attack_hitbox.monitoring = false
	if not attack_hitbox.body_entered.is_connected(_on_attack_hitbox_body_entered):
		attack_hitbox.body_entered.connect(_on_attack_hitbox_body_entered)

	floor_snap_length = max_step_down
	floor_max_angle = deg_to_rad(40.0)
	_enter_idle()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	attack_ready_in = maxf(0.0, attack_ready_in - delta)
	_update_sight(delta)
	_update_floor_ray()

	match state:
		States.IDLE:
			_idle_state(delta)
		States.WALK:
			_walk_state(delta)
		States.ATTACK:
			_attack_state()

	move_and_slide()
	_play_state_animation()


func _idle_state(delta: float) -> void:
	velocity.x = 0.0

	if _can_attack_player():
		_enter_attack()
		return

	if chase_target:
		_enter_walk()
		return

	idle_timer -= delta
	if idle_timer <= 0.0:
		_pick_new_patrol_point()
		_enter_walk()


func _walk_state(delta: float) -> void:
	if _can_attack_player():
		_enter_attack()
		return

	var destination_x := patrol_target_x
	var speed := patrol_speed
	if chase_target:
		destination_x = chase_target.global_position.x
		speed = chase_speed

	var to_dest := destination_x - global_position.x
	if absf(to_dest) <= 4.0 and chase_target == null:
		_enter_idle()
		return

	facing_dir = 1 if to_dest > 0.0 else -1
	if _blocked_ahead():
		if chase_target:
			velocity.x = 0.0
		else:
			_enter_idle()
		return

	velocity.x = facing_dir * speed


func _attack_state() -> void:
	velocity.x = 0.0
	if chase_target:
		var to_player := chase_target.global_position.x - global_position.x
		if absf(to_player) > 1.0:
			facing_dir = 1 if to_player > 0.0 else -1


func _enter_idle() -> void:
	state = States.IDLE
	velocity.x = 0.0
	attack_hitbox.monitoring = false
	idle_timer = randf_range(idle_time_min, idle_time_max)


func _enter_walk() -> void:
	state = States.WALK
	attack_hitbox.monitoring = false


func _enter_attack() -> void:
	state = States.ATTACK
	velocity.x = 0.0
	did_hit_this_attack = false
	attack_ready_in = attack_cooldown
	attack_hitbox.monitoring = true
	_play_state_animation()
	animated_sprite.play(_anim("attack"))


func _pick_new_patrol_point() -> void:
	var offset := randf_range(-patrol_radius, patrol_radius)
	if absf(offset) < 16.0:
		offset = 16.0 * signf(offset if offset != 0.0 else float(facing_dir))
	patrol_target_x = global_position.x + offset


func _update_sight(delta: float) -> void:
	var player := _find_player()
	if player and _can_see_player(player):
		chase_target = player
		sight_memory = sight_lost_time
		return

	if sight_memory > 0.0:
		sight_memory -= delta
		if sight_memory <= 0.0:
			chase_target = null
			patrol_target_x = global_position.x


func _find_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node2D


func _can_see_player(player: Node2D) -> bool:
	var to_player := player.global_position - global_position
	if to_player.length() > sight_range:
		return false
	if absf(to_player.y) > 36.0:
		return false
	if signf(to_player.x) != 0.0 and signf(to_player.x) != facing_dir:
		return false

	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, player.global_position)
	query.exclude = [self]
	query.collision_mask = collision_mask
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit.collider == player or hit.collider.get_parent() == player


func _can_attack_player() -> bool:
	if attack_ready_in > 0.0 or chase_target == null:
		return false
	var to_player := chase_target.global_position - global_position
	return absf(to_player.x) <= attack_range and absf(to_player.y) <= 24.0


func _blocked_ahead() -> bool:
	if not is_on_floor():
		return false
	if _is_step_up_ahead():
		return true

	var ahead := _ground_ahead()
	if ahead.is_empty():
		return true

	var drop: float = ahead.position.y - _feet_y()
	if drop < -max_step_up:
		return true
	if drop > max_step_down:
		return true
	return false


func _is_step_up_ahead() -> bool:
	var from := Vector2(global_position.x, _feet_y() - max_step_up - 2.0)
	var to := from + Vector2(facing_dir * look_ahead, 0.0)
	var hit := _intersect_ground(from, to)
	if hit.is_empty():
		return false
	return true


func _ground_ahead() -> Dictionary:
	var from := Vector2(global_position.x + facing_dir * look_ahead, _feet_y() - 2.0)
	var to := from + Vector2(0.0, max_step_down + 8.0)
	return _intersect_ground(from, to)


func _feet_y() -> float:
	var rect := body_shape.shape as RectangleShape2D
	if rect == null:
		return global_position.y + 14.0
	return body_shape.global_position.y + rect.size.y * 0.5


func _intersect_ground(from: Vector2, to: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.exclude = [self, attack_hitbox]
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return hit
	if hit.collider is Node and (hit.collider as Node).is_in_group("player"):
		return {}
	return hit


func _update_floor_ray() -> void:
	floor_ray.target_position = Vector2(facing_dir * look_ahead, max_step_down + 4.0)
	floor_ray.force_raycast_update()


func _play_state_animation() -> void:
	var anim := _anim("idle")
	match state:
		States.WALK:
			anim = _anim("walk")
		States.ATTACK:
			anim = _anim("attack")
		_:
			anim = _anim("idle")

	if animated_sprite.animation != anim:
		animated_sprite.play(anim)


func _anim(kind: String) -> StringName:
	if facing_dir >= 0:
		return StringName(kind + "_right")
	return StringName(kind + "_left")


func _on_animation_finished() -> void:
	if state != States.ATTACK:
		return
	attack_hitbox.monitoring = false
	if _can_attack_player():
		_enter_attack()
	elif chase_target:
		_enter_walk()
	else:
		_enter_idle()


func _on_attack_hitbox_body_entered(body: Node) -> void:
	if state != States.ATTACK or did_hit_this_attack:
		return
	if not body.is_in_group("player"):
		return
	did_hit_this_attack = true
	if body is CharacterBody2D:
		var knock_dir := signf(body.global_position.x - global_position.x)
		if knock_dir == 0.0:
			knock_dir = float(facing_dir)
		body.velocity.x = knock_dir * attack_knockback.x
		body.velocity.y = attack_knockback.y
