extends CharacterBody2D

const SPEED = 100.0
const JUMP_VELOCITY = -50.0
const GRAVITY = 200

enum STATES { WALK, WALL }
var state = STATES.WALK

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var pickup_detector: Area2D = $PickupDetector
@onready var hold_point: Marker2D = $HoldPoint

# --- Carry variables ---
var carried_block: Area2D = null

func _physics_process(delta: float) -> void:
	# --- Interact key (pick up / drop) ---
	if Input.is_action_just_pressed("interact"):
		if carried_block:
			drop_block()
		else:
			try_pickup_block()

	# Keep carried block glued to HoldPoint (use global to avoid teleporting)
	if carried_block:
		carried_block.global_position = hold_point.global_position

	if state == STATES.WALK:
		walk_state(delta)
	else:
		wall_state(delta)

	move_and_slide()


func try_pickup_block() -> void:
	# Find any carriable block in range (robust: doesn't rely on node name)
	for area in pickup_detector.get_overlapping_areas():
		# Case 1: overlapping the block root Area2D
		if area.has_method("set_carried") and not area.carried:
			pick_up(area)
			return

		# Case 2: overlapping a child Area2D (common)
		var p := area.get_parent()
		if p and p.has_method("set_carried") and not p.carried:
			pick_up(p)
			return


func pick_up(block: Node2D) -> void:
	carried_block = block
	carried_block.set_carried(true)

	# Reparent while preserving world transform (prevents random jumps)
	var world_pos := carried_block.global_position
	carried_block.get_parent().remove_child(carried_block)
	add_child(carried_block)
	carried_block.global_position = world_pos

	# Snap to hold point
	carried_block.global_position = hold_point.global_position


func drop_block() -> void:
	var block := carried_block
	carried_block = null

	# Reparent back to the level (player's parent)
	remove_child(block)
	get_parent().add_child(block)

	# Drop in front of player based on input direction (fallback to +1)
	var dir := 1
	var axis := Input.get_axis("ui_left", "ui_right")
	if axis != 0:
		dir = sign(axis)

	block.global_position = global_position + Vector2(16 * dir, 0)
	block.set_carried(false)


func walk_state(delta: float) -> void:
	# Only allow transition to wall state when near a wall and pressing "ui_up"
	if is_on_wall() and Input.is_action_just_pressed("ui_up"):
		state = STATES.WALL
		wall_state(delta)
		return

	if not is_on_floor():
		velocity.y += GRAVITY * delta

	# Jump if the "ui_up" action is pressed and character is on the floor
	if Input.is_action_just_pressed("ui_up") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		animated_sprite.play("WallClimb")

	# Handle horizontal movement based on left/right inputs
	var direction := Input.get_axis("ui_left", "ui_right")
	if direction != 0:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	# Return to normal state when on the floor
	if is_on_floor():
		animated_sprite.play("Idle")


func wall_state(delta: float) -> void:
	# Transition back to walk state if not on a wall
	if not is_on_wall():
		state = STATES.WALK
		animated_sprite.play("Idle")
		return

	velocity = Vector2.ZERO

	# Handle jump when pressing "ui_up"
	if Input.is_action_just_pressed("ui_up"):
		velocity.y = JUMP_VELOCITY
		state = STATES.WALK
		animated_sprite.play("WallClimb")
		return

	# Handle left/right boost jumps from wall
	if Input.is_action_just_pressed("ui_left"):
		velocity.x = -SPEED * 1.5
		velocity.y = JUMP_VELOCITY
		state = STATES.WALK
		animated_sprite.play("WallClimb")
		return

	if Input.is_action_just_pressed("ui_right"):
		velocity.x = SPEED * 1.5
		velocity.y = JUMP_VELOCITY
		state = STATES.WALK
		animated_sprite.play("WallClimb")
		return
