extends CharacterBody2D

const SPEED = 100.0
const JUMP_VELOCITY = -50.0
const GRAVITY = 200  # Gravity value for your game

enum STATES {WALK, WALL}  # Enum should use consistent case
var state = STATES.WALK

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D  # Adjust the node path if needed

func _physics_process(delta: float) -> void:
	if state == STATES.WALK:
		walk_state(delta)
	else:
		wall_state(delta)
	
	move_and_slide()

func walk_state(delta):
	# Only allow transition to wall state when near a wall and pressing "ui_up"
	if is_on_wall() and Input.is_action_just_pressed("ui_up"):
		state = STATES.WALL
		wall_state(delta)
		return

	if not is_on_floor():
		velocity.y += GRAVITY * delta  # Apply gravity when in the air

	# Jump if the "ui_up" action is pressed and character is on the floor
	if Input.is_action_just_pressed("ui_up") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		animated_sprite.play("WallClimb")  # Play wallclimb animation when jumping

	# Handle horizontal movement based on left/right inputs
	var direction := Input.get_axis("ui_left", "ui_right")
	if direction != 0:
		velocity.x = direction * SPEED
	else:
		# Slow down and stop if no horizontal input
		velocity.x = move_toward(velocity.x, 0, SPEED)

	# Return to normal state when on the floor (Idle or walking)
	if is_on_floor():
		animated_sprite.play("Idle")  # Play idle animation when on the floor

func wall_state(delta):
	# Transition back to walk state if not on a wall
	if not is_on_wall():
		state = STATES.WALK
		animated_sprite.play("Idle")  # Set to idle animation when off the wall
		return

	velocity = Vector2.ZERO  # Stop all movement on the wall

	# Handle jump when pressing "ui_up"
	if Input.is_action_just_pressed("ui_up"):
		velocity.y = JUMP_VELOCITY
		state = STATES.WALK  # Return to walk state after jump
		animated_sprite.play("WallClimb")  # Play wallclimb animation when jumping off the wall
		return

	# Handle left/right boost jumps from wall
	if Input.is_action_just_pressed("ui_left"):
		velocity.x = -SPEED * 1.5  # Launch left with a boost
		velocity.y = JUMP_VELOCITY
		state = STATES.WALK
		animated_sprite.play("WallClimb")  # Play wallclimb animation when jumping off the wall
		return
	if Input.is_action_just_pressed("ui_right"):
		velocity.x = SPEED * 1.5  # Launch right with a boost
		velocity.y = JUMP_VELOCITY
		state = STATES.WALK
		animated_sprite.play("WallClimb")  # Play wallclimb animation when jumping off the wall
		return
