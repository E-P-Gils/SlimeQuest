extends CharacterBody2D

const Mood := preload("res://scripts/combat_mood.gd")

enum States { IDLE, WALK, PRAY, SENT, WATCH, REPOSITION }

const GRAVITY := 200.0
const FIREBALL_SCENE := preload("res://fireball.tscn")

@export var patrol_speed := 28.0
@export var patrol_radius := 70.0
@export var idle_time_min := 1.4
@export var idle_time_max := 2.8
@export var sight_range := 180.0
@export var sight_lost_time := 1.6
@export var pray_time := 1.6
@export var sent_time := 0.45
@export var attack_cooldown := 2.3
@export var look_ahead := 10.0
@export var level_tolerance := 4.0
@export var chase_drop_limit := 48.0
@export var max_step_up := 1.0
@export var fireball_offset := Vector2(12.0, -8.0)

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var attack_hitbox: Area2D = $Area2D

var state: States = States.IDLE
var facing_dir: int = -1
var patrol_target_x: float
var idle_timer := 0.0
var sight_memory := 0.0
var attack_ready_in := 0.0
var phase_timer := 0.0
var chase_target: Node2D
var blocked_dir := 0
var hesitate := 0.0
var watch_timer := 0.0
var think_in := 0.0
var had_target := false
var last_cast_hit := false
var _fireball: Node


func _ready() -> void:
	patrol_target_x = global_position.x
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 1
	add_child(preload("res://scripts/enemy_blast.gd").new(1))
	add_child(preload("res://scripts/enemy_status.gd").new())
	var frames := animated_sprite.sprite_frames
	if frames:
		for anim in ["sent_left", "sent_right"]:
			if frames.has_animation(anim):
				frames.set_animation_loop(anim, false)
	attack_hitbox.monitoring = false
	floor_snap_length = chase_drop_limit
	floor_max_angle = deg_to_rad(40.0)
	_enter_idle()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	attack_ready_in = maxf(0.0, attack_ready_in - delta)
	hesitate = maxf(0.0, hesitate - delta)
	think_in = maxf(0.0, think_in - delta)
	_update_sight(delta)

	match state:
		States.IDLE:
			_idle_state(delta)
		States.WALK:
			_walk_state()
		States.PRAY:
			_pray_state(delta)
		States.SENT:
			_sent_state(delta)
		States.WATCH:
			_watch_state(delta)
		States.REPOSITION:
			_reposition_state()

	move_and_slide()
	_play_state_animation()


func _idle_state(delta: float) -> void:
	velocity.x = 0.0
	if chase_target:
		_face_target()
		if hesitate > 0.0:
			return
		if think_in <= 0.0:
			think_in = randf_range(0.4, 0.85)
			if _can_cast() and randf() < 0.7:
				_enter_pray()
				return
			_enter_reposition(Mood.flank_x(chase_target.global_position.x, global_position.x))
			return
	idle_timer -= delta
	if idle_timer <= 0.0:
		_pick_new_patrol_point()
		state = States.WALK


func _walk_state() -> void:
	if hesitate > 0.0:
		velocity.x = 0.0
		_face_target()
		return
	if think_in <= 0.0 and _can_cast() and randf() < 0.6:
		think_in = randf_range(0.4, 0.85)
		_enter_pray()
		return

	var to_dest := patrol_target_x - global_position.x
	if absf(to_dest) <= 4.0:
		_enter_idle()
		return
	if absf(to_dest) > 2.0:
		facing_dir = 1 if to_dest > 0.0 else -1
	if _blocked_ahead():
		velocity.x = 0.0
		blocked_dir = facing_dir
		_enter_idle()
		return
	velocity.x = facing_dir * patrol_speed


func _enter_idle() -> void:
	state = States.IDLE
	velocity.x = 0.0
	idle_timer = randf_range(idle_time_min, idle_time_max)


func _enter_pray() -> void:
	state = States.PRAY
	velocity.x = 0.0
	phase_timer = pray_time
	_face_target()
	_spawn_prepare_fireball()


func _pray_state(delta: float) -> void:
	velocity.x = 0.0
	_face_target()
	phase_timer -= delta
	if phase_timer <= 0.0:
		_enter_sent()


func _enter_sent() -> void:
	state = States.SENT
	velocity.x = 0.0
	phase_timer = sent_time
	attack_ready_in = attack_cooldown
	_face_target()
	_launch_fireball()


func _sent_state(delta: float) -> void:
	velocity.x = 0.0
	phase_timer -= delta
	if phase_timer <= 0.0:
		_enter_watch()


func _enter_watch() -> void:
	state = States.WATCH
	velocity.x = 0.0
	watch_timer = Mood.watch_time(last_cast_hit)


func _watch_state(delta: float) -> void:
	velocity.x = 0.0
	_face_target()
	watch_timer -= delta
	if watch_timer > 0.0:
		return
	_follow_intent(Mood.after_attack(last_cast_hit))


func _follow_intent(intent: int) -> void:
	match intent:
		Mood.Intent.PRESS:
			if _can_cast():
				_enter_pray()
			else:
				_enter_idle()
		Mood.Intent.WATCH:
			_enter_idle()
			idle_timer = Mood.watch_time(false)
		Mood.Intent.RETREAT:
			_enter_reposition(Mood.retreat_x(global_position.x, -facing_dir))
		Mood.Intent.FLANK:
			var px := global_position.x
			if chase_target:
				px = chase_target.global_position.x
			_enter_reposition(Mood.flank_x(px, global_position.x))


func _enter_reposition(dest_x: float) -> void:
	state = States.REPOSITION
	patrol_target_x = dest_x
	attack_ready_in = maxf(attack_ready_in, 0.8)


func _reposition_state() -> void:
	var to_dest := patrol_target_x - global_position.x
	if absf(to_dest) <= 5.0:
		_enter_idle()
		return
	facing_dir = 1 if to_dest > 0.0 else -1
	if _blocked_ahead():
		blocked_dir = facing_dir
		_enter_idle()
		return
	velocity.x = facing_dir * patrol_speed


func _can_cast() -> bool:
	return attack_ready_in <= 0.0 and hesitate <= 0.0 and chase_target != null


func _spawn_prepare_fireball() -> void:
	_clear_fireball()
	var fb := FIREBALL_SCENE.instantiate()
	get_parent().add_child(fb)
	_fireball = fb
	if fb.has_method("prepare_at"):
		fb.prepare_at(self, facing_dir, fireball_offset)


func _launch_fireball() -> void:
	if is_instance_valid(_fireball) and _fireball.has_method("launch"):
		_fireball.launch(_aim_dir())
	_fireball = null


func _clear_fireball() -> void:
	if is_instance_valid(_fireball):
		_fireball.queue_free()
	_fireball = null


func _aim_dir() -> Vector2:
	var dx := 1.0 if facing_dir >= 0 else -1.0
	var options: Array[Vector2] = [
		Vector2(dx, 0.0),
		Vector2(dx, -1.0).normalized(),
		Vector2(dx, 1.0).normalized(),
	]
	if chase_target == null:
		return options[0]
	var aim := (chase_target.global_position - global_position).normalized()
	var best := options[0]
	var best_dot := -2.0
	for option in options:
		var d := option.dot(aim)
		if d > best_dot:
			best_dot = d
			best = option
	return best


func _update_sight(delta: float) -> void:
	var player := _find_player()
	if player and _can_see_player(player):
		if not had_target:
			hesitate = Mood.hesitate_time()
		chase_target = player
		had_target = true
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
	var query := PhysicsRayQueryParameters2D.create(global_position, player.global_position)
	query.exclude = [get_rid()]
	query.collision_mask = collision_mask
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit.collider == player or hit.collider.get_parent() == player


func _face_target() -> void:
	if chase_target == null:
		return
	var dx := chase_target.global_position.x - global_position.x
	if absf(dx) > 1.0:
		facing_dir = 1 if dx > 0.0 else -1


func _pick_new_patrol_point() -> void:
	var offset := randf_range(-patrol_radius, patrol_radius)
	if absf(offset) < 16.0:
		offset = 16.0 if offset >= 0.0 else -16.0
	if blocked_dir != 0:
		offset = -absf(offset) * blocked_dir
		blocked_dir = 0
	patrol_target_x = global_position.x + offset


func _blocked_ahead() -> bool:
	if not is_on_floor():
		return false
	if _is_step_up_ahead():
		return true
	var ahead := _ground_ahead()
	if ahead.is_empty():
		return true
	var drop: float = ahead.position.y - _feet_y()
	return absf(drop) > level_tolerance


func _is_step_up_ahead() -> bool:
	var from := Vector2(global_position.x, _feet_y() - max_step_up - 2.0)
	var to := from + Vector2(facing_dir * look_ahead, 0.0)
	var hit := _intersect_ground(from, to)
	if hit.is_empty():
		return false
	return not (hit.collider is CharacterBody2D)


func _ground_ahead() -> Dictionary:
	var from := Vector2(global_position.x + facing_dir * look_ahead, _feet_y() - 2.0)
	var to := from + Vector2(0.0, chase_drop_limit + 8.0)
	return _intersect_ground(from, to)


func _feet_y() -> float:
	var half := 14.0
	var shape := body_shape.shape
	if shape is RectangleShape2D:
		half = (shape as RectangleShape2D).size.y * 0.5
	elif shape is CapsuleShape2D:
		half = (shape as CapsuleShape2D).height * 0.5
	elif shape is CircleShape2D:
		half = (shape as CircleShape2D).radius
	return body_shape.global_position.y + half


func _intersect_ground(from: Vector2, to: Vector2) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.exclude = [get_rid(), attack_hitbox.get_rid()]
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return hit
	if hit.collider is Node and (hit.collider as Node).is_in_group("player"):
		return {}
	return hit


func _play_state_animation() -> void:
	var kind := "idle"
	match state:
		States.PRAY:
			kind = "pray"
		States.SENT:
			kind = "sent"
		States.WALK, States.REPOSITION:
			if absf(velocity.x) > 1.0:
				kind = "walk"
	var anim := _anim(kind)
	if animated_sprite.animation != anim:
		animated_sprite.play(anim)


func _anim(kind: String) -> StringName:
	return StringName(kind + ("_right" if facing_dir >= 0 else "_left"))


func _exit_tree() -> void:
	_clear_fireball()
