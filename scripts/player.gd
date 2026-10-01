extends CharacterBody2D

const SPEED = 100.0
const JUMP_VELOCITY = -50.0
const GRAVITY = 200

enum STATES { WALK, WALL }
var state = STATES.WALK

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var pickup_detector: Area2D = $PickupDetector
@onready var hold_point: Marker2D = $HoldPoint

var carried_block: Node2D = null
var facing_dir: int = 1
const DROP_FORWARD_OFFSET := 16.0
const DROP_MAX_GROUND_SNAP_DISTANCE := 6.0
const DROP_GROUND_SEARCH_DISTANCE := 160.0
const BLOCK_HALF_EXTENTS := Vector2(7.0, 5.5)


func _physics_process(delta: float) -> void:
	# Interact (pick up / drop)
	if Input.is_action_just_pressed("interact"):
		if carried_block:
			drop_block()
		else:
			try_pickup_block()

	# Movement/state
	if state == STATES.WALK:
		walk_state(delta)
	else:
		wall_state(delta)

	move_and_slide()

	# Animation selection (single source of truth)
	update_animation()


func update_animation() -> void:
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


func try_pickup_block() -> void:
	for area in pickup_detector.get_overlapping_areas():
		var n: Node = area
		while n and not n.has_method("set_carried"):
			n = n.get_parent()

		if n and not n.carried:
			pick_up(n as Node2D)
			return


func pick_up(block: Node2D) -> void:
	carried_block = block
	carried_block.set_carried(true)

	# Parent it to HoldPoint so it inherits the marker transform
	carried_block.reparent(hold_point, true)

	# Sit exactly on HoldPoint (local space)
	carried_block.position = Vector2.ZERO


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
	if is_on_wall() and Input.is_action_just_pressed("ui_up"):
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


func wall_state(delta: float) -> void:
	# Transition back to walk state
	if not is_on_wall():
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
