extends CharacterBody2D

const Mood := preload("res://scripts/combat_mood.gd")

enum States { IDLE, CHASE, ATTACK, MAGIC, FIREBALL, WATCH, LEAVE }
enum MagicPhase { CAST, FINISH }

const GRAVITY := 200.0
const FIREBALL_SCENE := preload("res://fireball.tscn")

@export_group("Movement")
@export var walk_speed := 55.0
@export var fly_speed := 70.0
@export var wander_speed := 55.0
@export var ground_align := 18.0

@export_group("Sight")
@export var sight_range := 220.0
@export var sight_lost_time := 1.4

@export_group("Boredom")
@export var chase_time_min := 4.5
@export var chase_time_max := 7.0
@export var notice_cooldown := 1.8
@export var leave_distance_min := 140.0
@export var leave_distance_max := 240.0

@export_group("Combat")
@export var attack_range := 32.0
@export var magic_min_range := 40.0
@export var magic_max_range := 140.0
@export var attack_cooldown := 1.35
@export var magic_cooldown := 2.2
@export var magic_cast_time := 0.7
@export var magic_finish_time := 0.5
@export var ultima_interval := 5.0
@export var fireball_prepare_time := 1.6
@export var fireball_offset := Vector2(16.0, -10.0)
@export var attack_knockback := Vector2(150.0, -70.0)
@export var hit_frame_start := 1
@export var hit_frame_end := 2

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var attack_hitbox: Area2D = $Area2D

var state: States = States.IDLE
var magic_phase: MagicPhase = MagicPhase.CAST
var facing_dir: int = -1
var chase_target: Node2D
var sight_memory := 0.0
var chase_left := 0.0
var notice_ready_in := 0.0
var leave_point := Vector2.ZERO
var attack_ready_in := 0.0
var magic_ready_in := 0.8
var ultima_ready_in := 2.0
var phase_timer := 0.0
var did_hit_this_attack := false
var hesitate := 0.0
var watch_timer := 0.0
var think_in := 0.0
var had_target := false
var flying := true
var _walk_mask: int = 1
var _fireball: Node


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 1
	add_child(preload("res://scripts/enemy_blast.gd").new(2))
	add_child(preload("res://scripts/enemy_status.gd").new())
	_walk_mask = collision_mask
	var frames := animated_sprite.sprite_frames
	if frames:
		for anim in ["attack_left", "attack_right", "ultima_magic", "magicfly_left", "magicfly_right"]:
			if frames.has_animation(anim):
				frames.set_animation_loop(anim, false)

	animated_sprite.animation_finished.connect(_on_animation_finished)
	attack_hitbox.monitoring = false
	attack_hitbox.body_entered.connect(_on_attack_hitbox_body_entered)
	_set_flying(true)
	_enter_idle()


func _physics_process(delta: float) -> void:
	if not flying and not is_on_floor():
		velocity.y += GRAVITY * delta

	attack_ready_in = maxf(0.0, attack_ready_in - delta)
	magic_ready_in = maxf(0.0, magic_ready_in - delta)
	ultima_ready_in = maxf(0.0, ultima_ready_in - delta)
	notice_ready_in = maxf(0.0, notice_ready_in - delta)
	hesitate = maxf(0.0, hesitate - delta)
	think_in = maxf(0.0, think_in - delta)
	_update_sight(delta)

	attack_hitbox.position.x = absf(attack_hitbox.position.x) * facing_dir

	match state:
		States.IDLE:
			_idle_state(delta)
		States.CHASE:
			_chase_state(delta)
		States.ATTACK:
			_attack_state(delta)
		States.MAGIC:
			_magic_state(delta)
		States.FIREBALL:
			_fireball_state(delta)
		States.WATCH:
			_watch_state(delta)
		States.LEAVE:
			_leave_state(delta)

	attack_hitbox.set_deferred("monitoring", _hitbox_active())
	move_and_slide()
	_play_state_animation()


func _enter_idle() -> void:
	state = States.IDLE
	chase_target = null
	velocity = Vector2.ZERO


func _idle_state(delta: float) -> void:
	_hover_or_stand(delta)
	if chase_target:
		if hesitate > 0.0:
			return
		if _can_ultima():
			_enter_fireball()
			return
		_enter_chase()


func _enter_chase() -> void:
	state = States.CHASE
	chase_left = randf_range(chase_time_min, chase_time_max)
	think_in = randf_range(0.25, 0.55)


func _chase_state(delta: float) -> void:
	if chase_target == null:
		_enter_leave()
		return

	chase_left -= delta
	if chase_left <= 0.0:
		_enter_leave()
		return

	if hesitate > 0.0:
		_face_target()
		velocity = Vector2.ZERO
		return
	if think_in <= 0.0:
		think_in = randf_range(0.35, 0.75)
		if _can_melee():
			_enter_attack()
			return
		if _can_ultima() and randf() < 0.55:
			_enter_fireball()
			return
		if _can_magic() and randf() < 0.4:
			_enter_magic()
			return

	_face_target()
	_move_toward(chase_target.global_position, fly_speed, walk_speed, delta)


func _enter_leave() -> void:
	_clear_fireball()
	state = States.LEAVE
	chase_target = null
	sight_memory = 0.0
	notice_ready_in = notice_cooldown
	leave_point = _pick_leave_point()
	var dx := leave_point.x - global_position.x
	if absf(dx) > 1.0:
		facing_dir = 1 if dx > 0.0 else -1


func _leave_state(delta: float) -> void:
	var to_point := leave_point - global_position
	if to_point.length() <= 12.0:
		_enter_idle()
		return
	if absf(to_point.x) > 1.0:
		facing_dir = 1 if to_point.x > 0.0 else -1
	_move_toward(leave_point, wander_speed, walk_speed, delta)


func _enter_attack() -> void:
	state = States.ATTACK
	velocity = Vector2.ZERO
	did_hit_this_attack = false
	attack_ready_in = attack_cooldown
	_face_target()
	_set_flying(false)
	animated_sprite.play(_anim("attack"))


func _attack_state(_delta: float) -> void:
	velocity = Vector2.ZERO


func _enter_magic() -> void:
	state = States.MAGIC
	velocity = Vector2.ZERO
	magic_ready_in = magic_cooldown
	magic_phase = MagicPhase.CAST
	phase_timer = magic_cast_time
	_face_target()
	animated_sprite.play(_anim("magicfly"))


func _magic_state(delta: float) -> void:
	velocity = Vector2.ZERO
	phase_timer -= delta
	if phase_timer <= 0.0:
		_resume_after_cast()


func _enter_fireball() -> void:
	state = States.FIREBALL
	velocity = Vector2.ZERO
	ultima_ready_in = ultima_interval
	phase_timer = fireball_prepare_time
	_set_flying(false)
	_face_target()
	if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(&"ultima_magic"):
		animated_sprite.play(&"ultima_magic")
	_spawn_prepare_fireball()


func _fireball_state(delta: float) -> void:
	velocity = Vector2.ZERO
	phase_timer -= delta
	if phase_timer <= 0.0:
		_launch_fireball()
		_resume_after_cast()


func _resume_after_cast() -> void:
	_enter_watch()


func _enter_watch() -> void:
	state = States.WATCH
	velocity = Vector2.ZERO
	watch_timer = Mood.watch_time(did_hit_this_attack)


func _watch_state(delta: float) -> void:
	velocity = Vector2.ZERO
	_face_target()
	watch_timer -= delta
	if watch_timer > 0.0:
		return
	var intent: int = Mood.after_attack(did_hit_this_attack)
	match intent:
		Mood.Intent.PRESS:
			if chase_target and chase_left > 0.0:
				state = States.CHASE
			else:
				_enter_leave()
		Mood.Intent.WATCH:
			if chase_target and chase_left > 0.0:
				state = States.CHASE
			else:
				_enter_idle()
		Mood.Intent.RETREAT:
			_enter_leave()
		Mood.Intent.FLANK:
			if chase_target:
				leave_point = Vector2(Mood.flank_x(chase_target.global_position.x, global_position.x), global_position.y + randf_range(-30.0, 20.0))
				state = States.LEAVE
				notice_ready_in = 1.2
			else:
				_enter_leave()


func _on_animation_finished() -> void:
	if state == States.ATTACK:
		_resume_after_cast()
	elif state == States.MAGIC:
		_resume_after_cast()


func _hover_or_stand(delta: float) -> void:
	if _ground_below() and absf(global_position.y - (_ground_y() - 1.0)) <= ground_align:
		_set_flying(false)
		if not is_on_floor():
			velocity.y += GRAVITY * delta
		velocity.x = 0.0
	else:
		_set_flying(true)
		velocity = Vector2(0.0, sin(Time.get_ticks_msec() * 0.004) * 8.0)


func _move_toward(dest: Vector2, air_speed: float, ground_speed: float, delta: float) -> void:
	var to_dest := dest - global_position
	var want_fly := absf(to_dest.y) > ground_align or not _ground_below()
	_set_flying(want_fly)
	if flying:
		if to_dest.length() > 4.0:
			velocity = to_dest.normalized() * air_speed
		else:
			velocity = Vector2.ZERO
	else:
		if not is_on_floor():
			velocity.y += GRAVITY * delta
		if absf(to_dest.x) > 4.0:
			velocity.x = facing_dir * ground_speed
		else:
			velocity.x = 0.0


func _hitbox_active() -> bool:
	if state != States.ATTACK or _in_air():
		return false
	if animated_sprite.animation != _anim("attack"):
		return false
	var f := animated_sprite.frame
	return f >= hit_frame_start and f <= hit_frame_end


func _on_attack_hitbox_body_entered(body: Node) -> void:
	if state != States.ATTACK or did_hit_this_attack:
		return
	if not body.is_in_group("player"):
		return
	did_hit_this_attack = true

	var knock_dir := signf(body.global_position.x - global_position.x)
	if knock_dir == 0.0:
		knock_dir = float(facing_dir)

	if body.has_method("take_hit"):
		body.take_hit(knock_dir, attack_knockback)
	elif body is CharacterBody2D:
		body.velocity = Vector2(knock_dir * attack_knockback.x, attack_knockback.y)


func _update_sight(delta: float) -> void:
	if state == States.LEAVE:
		chase_target = null
		return

	var player := _find_player()
	if player and notice_ready_in <= 0.0 and _can_see_player(player):
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
	query.collision_mask = _walk_mask
	query.collide_with_areas = false
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit.collider == player or hit.collider.get_parent() == player


func _pick_leave_point() -> Vector2:
	var player := _find_player()
	var away := Vector2.LEFT if facing_dir >= 0 else Vector2.RIGHT
	if player:
		away = (global_position - player.global_position).normalized()
		if away == Vector2.ZERO:
			away = Vector2(float(-facing_dir), -0.4)
	away = away.rotated(randf_range(-0.8, 0.8)).normalized()
	var dist := randf_range(leave_distance_min, leave_distance_max)
	return global_position + away * dist + Vector2(0.0, randf_range(-60.0, -10.0))


func _in_air() -> bool:
	return flying or not is_on_floor()


func _ground_y() -> float:
	var from := Vector2(global_position.x, _feet_y() - 2.0)
	var to := from + Vector2(0.0, 48.0)
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.exclude = [get_rid()]
	query.collision_mask = _walk_mask
	query.collide_with_areas = false
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return global_position.y
	return hit.position.y


func _ground_below() -> bool:
	var from := Vector2(global_position.x, _feet_y() - 2.0)
	var to := from + Vector2(0.0, 24.0)
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.exclude = [get_rid()]
	query.collision_mask = _walk_mask
	query.collide_with_areas = false
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	if hit.collider is Node and (hit.collider as Node).is_in_group("player"):
		return false
	return hit.normal.y <= -0.5


func _set_flying(should_fly: bool) -> void:
	flying = should_fly
	if flying:
		collision_mask = 0
		motion_mode = MOTION_MODE_FLOATING
	else:
		collision_mask = _walk_mask
		motion_mode = MOTION_MODE_GROUNDED


func _can_melee() -> bool:
	if attack_ready_in > 0.0 or chase_target == null or _in_air():
		return false
	return global_position.distance_to(chase_target.global_position) <= attack_range


func _can_magic() -> bool:
	if magic_ready_in > 0.0 or chase_target == null or not _in_air():
		return false
	var dist := global_position.distance_to(chase_target.global_position)
	return dist >= magic_min_range and dist <= magic_max_range


func _can_ultima() -> bool:
	if ultima_ready_in > 0.0 or chase_target == null or _in_air():
		return false
	return true


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


func _face_target() -> void:
	if chase_target == null:
		return
	var dx := chase_target.global_position.x - global_position.x
	if absf(dx) > 1.0:
		facing_dir = 1 if dx > 0.0 else -1


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


func _play_state_animation() -> void:
	var kind := "idle"
	if _in_air():
		kind = "magicfly" if state == States.MAGIC else "fly"
	elif state == States.ATTACK:
		kind = "attack"
	elif state == States.FIREBALL:
		var ultima := &"ultima_magic"
		if animated_sprite.sprite_frames and animated_sprite.sprite_frames.has_animation(ultima):
			if animated_sprite.animation != ultima:
				animated_sprite.play(ultima)
			return
		kind = "idle"
	elif absf(velocity.x) > 8.0:
		kind = "walk"

	var anim := _anim(kind)
	var frames := animated_sprite.sprite_frames
	if frames == null or not frames.has_animation(anim):
		return
	if animated_sprite.animation != anim:
		animated_sprite.play(anim)


func _anim(kind: String) -> StringName:
	return StringName(kind + ("_right" if facing_dir >= 0 else "_left"))


func _exit_tree() -> void:
	_clear_fireball()
