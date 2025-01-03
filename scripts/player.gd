extends CharacterBody2D

const SPEED = 100.0
const WALL_SLIDE_ACCEL = -10
const CLIMB_SPEED = 100
const JUMP_VELOCITY = -50.0
const GRAVITY = 200  # Gravity value for your game

enum STATES {WALK, WALL}  # Enum should use consistent case
var state = STATES.WALK

func _physics_process(delta: float) -> void:
	if state == STATES.WALK:
		walk_state(delta)
	else:
		wall_state(delta)
	
	move_and_slide()

func walk_state(delta):
	if is_on_wall_only():
		state = STATES.WALL

	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var direction := Input.get_axis("ui_left", "ui_right")
	if direction != 0:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

func wall_state(delta):
	if not is_on_wall():
		state = STATES.WALK
		return

	velocity = Vector2.ZERO  # Stop all motion on the wall

	if Input.is_action_just_pressed("ui_accept"):
		velocity.y = JUMP_VELOCITY
		state = STATES.WALK
		return

	var direction = Input.get_axis("ui_up", "ui_down")
	if direction != 0:
		velocity.y = direction * CLIMB_SPEED
