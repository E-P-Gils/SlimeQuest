extends CharacterBody2D

const SPEED = 100.0
const JUMP_VELOCITY = -50.0
const GRAVITY = 200
const MAX_HEALTH := 3
const HURT_LOCK := 0.35
const INVINCIBLE_TIME := 1.0
const CONTACT_KNOCKBACK := Vector2(120.0, -60.0)

signal health_changed(current: int, maximum: int)

enum STATES { WALK, WALL }
var state = STATES.WALK
var health := MAX_HEALTH
var hurt_lock := 0.0
var invincible := 0.0
var dying := false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var pickup_detector: Area2D = $PickupDetector
@onready var hurt_detector: Area2D = $HurtDetector
@onready var hold_point: Marker2D = $HoldPoint

var carried_block: Node2D = null
var facing_dir: int = 1
const DROP_FORWARD_OFFSET := 16.0
const DROP_MAX_GROUND_SNAP_DISTANCE := 6.0
const DROP_GROUND_SEARCH_DISTANCE := 160.0
const BLOCK_HALF_EXTENTS := Vector2(7.0, 5.5)


func _ready() -> void:
	health_changed.emit(health, MAX_HEALTH)


func take_hit(knock_dir: float, knockback: Vector2, damage: int = 1) -> void:
	if dying:
		return
	if damage <= 1 and invincible > 0.0:
		return

	health = maxi(0, health - damage)
	health_changed.emit(health, MAX_HEALTH)
	invincible = INVINCIBLE_TIME
	hurt_lock = HURT_LOCK
	state = STATES.WALK
	velocity = Vector2(knock_dir * knockback.x, knockback.y)
	animated_sprite.play("hurt")
	animated_sprite.modulate = Color(1.0, 0.55, 0.55)

	if health <= 0:
		dying = true
		get_tree().create_timer(0.85).timeout.connect(_restart_scene)


func _restart_scene() -> void:
	get_tree().reload_current_scene()


func _check_enemy_contact() -> void:
	if invincible > 0.0 or dying:
		return
	for body in hurt_detector.get_overlapping_bodies():
		if body == self:
			continue
		if body is Node and (body as Node).is_in_group("enemies"):
			var knock_dir := signf(global_position.x - body.global_position.x)
			if knock_dir == 0.0:
				knock_dir = float(-facing_dir)
			take_hit(knock_dir, CONTACT_KNOCKBACK)
			return


func _physics_process(delta: float) -> void:
	hurt_lock = maxf(0.0, hurt_lock - delta)
	invincible = maxf(0.0, invincible - delta)
	if invincible <= 0.0:
		animated_sprite.modulate = Color.WHITE
	elif int(invincible * 12.0) % 2 == 0:
		animated_sprite.modulate = Color(1.0, 0.55, 0.55)
	else:
		animated_sprite.modulate = Color(1.0, 1.0, 1.0, 0.55)

	# Interact (pick up / drop)
	if not dying and Input.is_action_just_pressed("interact"):
		if carried_block:
			drop_block()
		else:
			try_pickup_block()

	# Movement/state
	if dying:
		if not is_on_floor():
			velocity.y += GRAVITY * delta
		velocity.x = move_toward(velocity.x, 0, SPEED * 0.5)
	elif hurt_lock > 0.0:
		if not is_on_floor():
			velocity.y += GRAVITY * delta
	elif state == STATES.WALK:
		walk_state(delta)
	else:
		wall_state(delta)

	move_and_slide()
	_keep_carried_block()
	_check_enemy_contact()

	# Animation selection (single source of truth)
	update_animation()


func update_animation() -> void:
	if hurt_lock > 0.0 or dying:
		if animated_sprite.animation != "hurt":
			animated_sprite.play("hurt")
		return

	# Wall state always uses WallClimb
	if state == STATES.WALL:
		if animated_sprite.animation != "WallClimb":
			animated_sprite.play("WallClimb")
		return

	# WALK state:
	# If carrying and on floor, use WallClimb as "carrying" anim
	if carried_block and is_on_floor():
		if animated_sprite.animation != "WallClimb":
			animated_sprite.play("WallClimb")
		return

	# If jumping / falling you can keep WallClimb or add a dedicated air anim later
	if not is_on_floor():
		if animated_sprite.animation != "WallClimb":
			animated_sprite.play("WallClimb")
		return

	# Default idle
	if animated_sprite.animation != "Idle":
		animated_sprite.play("Idle")


func _keep_carried_block() -> void:
	if carried_block == null or not is_instance_valid(carried_block):
		return
	carried_block.position = Vector2.ZERO
	carried_block.rotation = 0.0
	if carried_block is RigidBody2D:
		var body := carried_block as RigidBody2D
		body.freeze = true
		body.linear_velocity = Vector2.ZERO
		body.angular_velocity = 0.0
		body.sleeping = true


func try_pickup_block() -> void:
	pickup_detector.monitoring = true
	for area in pickup_detector.get_overlapping_areas():
		var n: Node = area
		while n and not n.has_method("set_carried"):
			n = n.get_parent()

		if n and n.get("carried") == false:
			pick_up(n as Node2D)
			return


func pick_up(block: Node2D) -> void:
	carried_block = block
	carried_block.set_carried(true)

	# Parent it to HoldPoint so it follows walk, jump, and wall climb.
	carried_block.reparent(hold_point, true)
	carried_block.position = Vector2.ZERO
	carried_block.rotation = 0.0
	_keep_carried_block()


func drop_block() -> void:
	var block := carried_block
	var drop_origin := global_position + Vector2(DROP_FORWARD_OFFSET * facing_dir, 0)
	if _is_wall_adjacent_drop(drop_origin):
		return

	carried_block = null

	# Put it back in the level
	block.reparent(get_parent(), true)
	block.global_position = drop_origin
	block.set_carried(false)

	var ground_hit := _find_ground_below(drop_origin)
	if not ground_hit.is_empty():
		var hit_position: Vector2 = ground_hit["position"]
		var support_distance := hit_position.y - (drop_origin.y + BLOCK_HALF_EXTENTS.y)
		if support_distance <= DROP_MAX_GROUND_SNAP_DISTANCE:
			block.global_position.y = hit_position.y - BLOCK_HALF_EXTENTS.y


func _is_wall_adjacent_drop(drop_origin: Vector2) -> bool:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.new()
	query.exclude = [self]

	var mid_y := drop_origin.y - 1.0
	var side_distance := BLOCK_HALF_EXTENTS.x + 2.0

	query.from = Vector2(drop_origin.x, mid_y)
	query.to = Vector2(drop_origin.x - side_distance, mid_y)
	if not space_state.intersect_ray(query).is_empty():
		return true

	query.from = Vector2(drop_origin.x, mid_y)
	query.to = Vector2(drop_origin.x + side_distance, mid_y)
	if not space_state.intersect_ray(query).is_empty():
		return true

	return false


func _find_ground_below(drop_origin: Vector2) -> Dictionary:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.new()
	query.exclude = [self]
	query.from = Vector2(drop_origin.x, drop_origin.y + BLOCK_HALF_EXTENTS.y)
	query.to = query.from + Vector2(0, DROP_GROUND_SEARCH_DISTANCE)
	return space_state.intersect_ray(query)


func walk_state(delta: float) -> void:
	# Transition to wall state
	if is_on_wall() and Input.is_action_just_pressed("ui_up") and not _wall_is_enemy():
		state = STATES.WALL
		return

	if not is_on_floor():
		velocity.y += GRAVITY * delta

	# Jump
	if Input.is_action_just_pressed("ui_up") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Horizontal movement
	var direction := Input.get_axis("ui_left", "ui_right")
	if direction != 0:
		facing_dir = sign(direction)
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)


func _wall_is_enemy() -> bool:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if absf(col.get_normal().x) < 0.6:
			continue
		var collider := col.get_collider()
		if collider is Node and (collider as Node).is_in_group("enemies"):
			return true
	return false


func wall_state(delta: float) -> void:
	# Transition back to walk state
	if not is_on_wall() or _wall_is_enemy():
		state = STATES.WALK
		return

	velocity = Vector2.ZERO

	# Jump off wall
	if Input.is_action_just_pressed("ui_up"):
		velocity.y = JUMP_VELOCITY
		state = STATES.WALK
		return

	# Boost left/right off wall
	if Input.is_action_just_pressed("ui_left"):
		facing_dir = -1
		velocity.x = -SPEED * 1.5
		velocity.y = JUMP_VELOCITY
		state = STATES.WALK
		return

	if Input.is_action_just_pressed("ui_right"):
		facing_dir = 1
		velocity.x = SPEED * 1.5
		velocity.y = JUMP_VELOCITY
		state = STATES.WALK
		return
		return
