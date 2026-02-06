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
	carried_block = null

	# Put it back in the level
	block.reparent(get_parent(), true)

	# Drop in front of player (use facing_dir even if no input)
	block.global_position = global_position + Vector2(16 * facing_dir, 0)

	block.set_carried(false)


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
