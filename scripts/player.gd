extends CharacterBody2D

const SPEED = 100.0
const WALL_SLIDE_ACCEL = -10
const CLIMB_SPEED = 100
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
	# Transition to wall state if the character is only touching a wall
	if is_on_wall_only():
		state = STATES.WALL
		wall_state(delta)
		return

	if not is_on_floor():
		velocity.y += GRAVITY * delta  # Apply gravity when in the air

	# Jump if the "ui_up" action is pressed and character is on the floor
	if Input.is_action_just_pressed("ui_up") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Handle horizontal movement based on left/right inputs
	var direction := Input.get_axis("ui_left", "ui_right")
	if direction != 0:
		velocity.x = direction * SPEED
	else:
		# Slow down and stop if no horizontal input
		velocity.x = move_toward(velocity.x, 0, SPEED)

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
		animated_sprite.play("Idle")  # Set to idle animation when jumping off the wall
		return

	# Handle climbing when moving up/down (use 'ui_down' to control climbing)
	var direction = Input.get_axis("ui_down", "")
	if direction != 0:
		velocity.y = direction * CLIMB_SPEED
		animated_sprite.play("WallClimb")  # Play wall climbing animation
	else:
		velocity.y = move_toward(velocity.y, 0, SPEED)
		animated_sprite.play("Idle")  # Return to idle animation when climbing stops

	
