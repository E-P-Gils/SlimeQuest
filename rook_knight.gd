extends CharacterBody2D

enum States { IDLE, WALK, ATTACK }
enum Phase { WINDUP, CHARGE, RECOVER }

const GRAVITY := 200.0

# Speeds are the pawn's divided by 1.5, so the pawn is 50% faster.
@export var patrol_speed := 27.0
@export var chase_speed := 47.0
@export var patrol_radius := 80.0
@export var idle_time_min := 1.2
@export var idle_time_max := 2.6
@export var sight_range := 140.0
@export var sight_lost_time := 1.6
@export var attack_cooldown := 1.5
@export var attack_knockback := Vector2(160.0, -80.0)
@export var charge_trigger_range := 120.0   # starts the attack from this far away
@export var windup_time := 0.5              # pause in idle stance before sliding
@export var charge_speed := 260.0
@export var recover_time := 0.9
@export var slide_hold_frame := 4           # attack frame to freeze on while sliding
@export var look_ahead := 10.0
@export var level_tolerance := 4.0
@export var chase_drop_limit := 48.0
@export var max_step_up := 1.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var attack_hitbox: Area2D = $Area2D

var state: States = States.IDLE
var phase: Phase = Phase.WINDUP
var phase_timer := 0.0
var facing_dir: int = -1
var patrol_target_x: float
var idle_timer := 0.0
var sight_memory := 0.0
var attack_ready_in := 0.0
var chase_target: Node2D
var did_hit_this_attack := false
var blocked_dir := 0


func _ready() -> void:
	patrol_target_x = global_position.x
	add_to_group("enemies")

	var frames := animated_sprite.sprite_frames
	if frames:
		for anim in ["attack_left", "attack_right"]:
			if frames.has_animation(anim):
				frames.set_animation_loop(anim, false)

	attack_hitbox.monitoring = false
	attack_hitbox.body_entered.connect(_on_attack_hitbox_body_entered)

	floor_snap_length = chase_drop_limit
	floor_max_angle = deg_to_rad(40.0)
	_enter_idle()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	attack_ready_in = maxf(0.0, attack_ready_in - delta)
	_update_sight(delta)

	# Keep the hitbox on the side the knight faces (place the Area2D at a POSITIVE x offset)
	attack_hitbox.position.x = absf(attack_hitbox.position.x) * facing_dir

	match state:
		States.IDLE:
			_idle_state(delta)
		States.WALK:
			_walk_state()
		States.ATTACK:
			_attack_state(delta)

	attack_hitbox.set_deferred("monitoring", state == States.ATTACK and phase == Phase.CHARGE)
	move_and_slide()
	_play_state_animation()


# ---------- states ----------

func _idle_state(delta: float) -> void:
	velocity.x = 0.0
	if _can_attack_player():
		_enter_attack()
		return
	if chase_target:
		state = States.WALK
		return
	idle_timer -= delta
	if idle_timer <= 0.0:
		_pick_new_patrol_point()
		state = States.WALK


func _walk_state() -> void:
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

	if absf(to_dest) > 2.0:
		facing_dir = 1 if to_dest > 0.0 else -1

	if _blocked_ahead():
		velocity.x = 0.0
		if chase_target == null:
			blocked_dir = facing_dir
			_enter_idle()
		return

	velocity.x = facing_dir * speed


func _enter_idle() -> void:
	state = States.IDLE
	velocity.x = 0.0
	idle_timer = randf_range(idle_time_min, idle_time_max)


# ---------- rook attack: pause, then slide to the end of the ledge ----------

func _enter_attack() -> void:
	state = States.ATTACK
	velocity.x = 0.0
	did_hit_this_attack = false
	_face_target()
	phase = Phase.WINDUP
	phase_timer = windup_time


func _attack_state(delta: float) -> void:
	match phase:
		Phase.WINDUP:
			velocity.x = 0.0
			phase_timer -= delta
			if phase_timer <= 0.0:
				_face_target()
				did_hit_this_attack = false
				phase = Phase.CHARGE
		Phase.CHARGE:
			# strict: stop at the end of THIS ledge level, even while chasing
			if _blocked_ahead(true) or is_on_wall():
				velocity.x = 0.0
				phase = Phase.RECOVER
				phase_timer = recover_time
			else:
				velocity.x = facing_dir * charge_speed
				_hold_slide_pose()
		Phase.RECOVER:
			velocity.x = 0.0
			phase_timer -= delta
			if phase_timer <= 0.0:
				attack_ready_in = attack_cooldown
				if chase_target:
					state = States.WALK
				else:
					_enter_idle()


func _hold_slide_pose() -> void:
	if animated_sprite.animation == _anim("attack") \
			and animated_sprite.is_playing() \
			and animated_sprite.frame >= slide_hold_frame:
		animated_sprite.pause()


func _on_attack_hitbox_body_entered(body: Node) -> void:
	if state != States.ATTACK or phase != Phase.CHARGE or did_hit_this_attack:
		return
	if not body.is_in_group("player"):
		return
	did_hit_this_attack = true

	var knock_dir := signf(body.global_position.x - global_position.x)
	if knock_dir == 0.0:
		knock_dir = float(facing_dir)

	if body.has_method("take_hit"):
		body.take_hit(knock_dir, attack_knockback)   # slime plays its Hurt anim in here
	elif body is CharacterBody2D:
		body.velocity = Vector2(knock_dir * attack_knockback.x, attack_knockback.y)


# ---------- sight ----------

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
	if signf(to_player.x) != 0.0 and int(signf(to_player.x)) != facing_dir:
		return false

	var query := PhysicsRayQueryParameters2D.create(global_position, player.global_position)
	query.exclude = [get_rid()]
	query.collision_mask = collision_mask
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit.collider == player or hit.collider.get_parent() == player


func _can_attack_player() -> bool:
	if attack_ready_in > 0.0 or chase_target == null:
		return false
	var to_player := chase_target.global_position - global_position
	return absf(to_player.x) <= charge_trigger_range and absf(to_player.y) <= 24.0


func _face_target() -> void:
	if chase_target:
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


# ---------- ledges / stairs ----------

# strict = true ignores chasing and always stays on the current level
func _blocked_ahead(strict := false) -> bool:
	if not is_on_floor():
		return false
	if _is_step_up_ahead():
		return true

	var ahead := _ground_ahead()
	if ahead.is_empty():
		return true

	var drop: float = ahead.position.y - _feet_y()
	if chase_target != null and not strict:
		return drop < -max_step_up or drop > chase_drop_limit
	return absf(drop) > level_tolerance


func _is_step_up_ahead() -> bool:
	var from := Vector2(global_position.x, _feet_y() - max_step_up - 2.0)
	var to := from + Vector2(facing_dir * look_ahead, 0.0)
	return not _intersect_ground(from, to).is_empty()


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


# ---------- animation ----------

func _play_state_animation() -> void:
	var kind := "idle"
	if state == States.ATTACK:
		if phase == Phase.CHARGE:
			kind = "attack"
	elif state == States.WALK and absf(velocity.x) > 1.0:
		kind = "walk"

	var anim := _anim(kind)
	if animated_sprite.animation != anim:
		animated_sprite.play(anim)


func _anim(kind: String) -> StringName:
	return StringName(kind + ("_right" if facing_dir >= 0 else "_left"))
