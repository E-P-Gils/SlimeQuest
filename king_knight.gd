extends CharacterBody2D

enum States { IDLE, TELEPORTING, ATTACK }

const GRAVITY := 200.0

@export_group("Sight")
@export var sight_range := 180.0
@export var sight_height := 60.0        # max vertical distance it can notice the slime from
@export var sight_lost_time := 2.0

@export_group("Teleport attack")
@export var decision_interval := 0.6    # how often it "rolls the dice" while it sees the slime
@export var teleport_attack_chance := 0.65
@export var attack_cooldown := 1.8
@export var behind_distance := 30.0     # how far behind the slime it appears
@export var vanish_time := 0.18
@export var appear_time := 0.18
@export var appear_pause := 0.12        # short beat after appearing, before swinging

@export_group("Attack")
@export var attack_range := 22.0        # if the slime is this close it just attacks in place
@export var attack_knockback := Vector2(140.0, -70.0)
@export var hit_frame_start := 1        # attack frames where the hitbox is live
@export var hit_frame_end := 2

@export_group("Roaming")
@export var roam_interval_min := 50.0   # seconds between random teleports
@export var roam_interval_max := 70.0
@export var roam_radius := 300.0        # random teleports stay within this distance of its start
@export var roam_height_up := 150.0     # how far above its start to look for ground
@export var roam_height_down := 300.0   # how far below its start to look for ground
@export var min_roam_distance := 80.0

@export_group("Landing search")
@export var ground_search_up := 24.0    # looking for ground near the slime: start this far above it
@export var ground_search_down := 60.0  # ...and search this far below that

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var attack_hitbox: Area2D = $Area2D

var state: States = States.IDLE
var facing_dir: int = -1
var home_pos: Vector2
var chase_target: Node2D
var sight_memory := 0.0
var decision_timer := 0.0
var attack_ready_in := 0.0
var roam_timer := 0.0
var attack_fallback := -1.0
var did_hit_this_attack := false


func _ready() -> void:
	home_pos = global_position
	add_to_group("enemies")
	roam_timer = randf_range(roam_interval_min, roam_interval_max)

	var frames := animated_sprite.sprite_frames
	if frames:
		for anim in ["attack_left", "attack_right"]:
			if frames.has_animation(anim):
				frames.set_animation_loop(anim, false)

	animated_sprite.animation_finished.connect(_on_animation_finished)
	attack_hitbox.monitoring = false
	attack_hitbox.body_entered.connect(_on_attack_hitbox_body_entered)
	_enter_idle()


func _physics_process(delta: float) -> void:
	if state == States.TELEPORTING:
		return

	if not is_on_floor():
		velocity.y += GRAVITY * delta
	velocity.x = 0.0

	attack_ready_in = maxf(0.0, attack_ready_in - delta)
	_update_sight(delta)

	# Keep the hitbox on the side the king faces (place the Area2D at a POSITIVE x offset)
	attack_hitbox.position.x = absf(attack_hitbox.position.x) * facing_dir

	match state:
		States.IDLE:
			_idle_state(delta)
		States.ATTACK:
			_attack_state(delta)

	attack_hitbox.set_deferred("monitoring", _hitbox_active())
	move_and_slide()
	_play_state_animation()


# ---------- states ----------

func _enter_idle() -> void:
	state = States.IDLE
	decision_timer = 0.3


func _idle_state(delta: float) -> void:
	if chase_target:
		_face_target()
		decision_timer -= delta
		if decision_timer <= 0.0 and attack_ready_in <= 0.0:
			decision_timer = decision_interval
			if _in_melee_range():
				_enter_attack()
			elif randf() < teleport_attack_chance:
				var dest := _find_behind_player()
				if dest != Vector2.INF:
					_teleport_to(dest, true)
		return

	# Only roams while it hasn't noticed the slime
	roam_timer -= delta
	if roam_timer <= 0.0:
		_roam()


func _enter_attack() -> void:
	state = States.ATTACK
	velocity.x = 0.0
	did_hit_this_attack = false
	attack_ready_in = attack_cooldown
	_face_target()

	var anim := _anim("attack")
	var frames := animated_sprite.sprite_frames
	if frames and frames.has_animation(anim):
		attack_fallback = -1.0
		animated_sprite.play(anim)
	else:
		attack_fallback = 0.5   # no attack animation yet; just wait a moment


func _attack_state(delta: float) -> void:
	velocity.x = 0.0
	if attack_fallback >= 0.0:
		attack_fallback -= delta
		if attack_fallback < 0.0:
			_enter_idle()


func _on_animation_finished() -> void:
	if state == States.ATTACK:
		_enter_idle()


func _hitbox_active() -> bool:
	if state != States.ATTACK:
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
		body.take_hit(knock_dir, attack_knockback)   # slime plays its Hurt anim in here
	elif body is CharacterBody2D:
		body.velocity = Vector2(knock_dir * attack_knockback.x, attack_knockback.y)


# ---------- teleporting ----------

func _teleport_to(dest: Vector2, then_attack: bool) -> void:
	state = States.TELEPORTING
	velocity = Vector2.ZERO
	attack_hitbox.set_deferred("monitoring", false)

	var out := create_tween()
	out.tween_property(animated_sprite, "modulate:a", 0.0, vanish_time)
	await out.finished

	body_shape.set_deferred("disabled", true)
	global_position = dest
	velocity = Vector2.ZERO
	_face_target()
	body_shape.set_deferred("disabled", false)

	var back := create_tween()
	back.tween_property(animated_sprite, "modulate:a", 1.0, appear_time)
	await back.finished

	if then_attack and is_instance_valid(chase_target):
		await get_tree().create_timer(appear_pause).timeout
		_enter_attack()
	else:
		_enter_idle()


func _roam() -> void:
	roam_timer = randf_range(roam_interval_min, roam_interval_max)
	var dest := _pick_roam_point()
	if dest == Vector2.INF:
		roam_timer = 5.0   # nothing valid right now, try again soon
		return
	_teleport_to(dest, false)


func _pick_roam_point() -> Vector2:
	# If you place Marker2D nodes in the group "king_teleport_points", it only uses those.
	var points := get_tree().get_nodes_in_group("king_teleport_points")
	if not points.is_empty():
		points.shuffle()
		for p in points:
			if p is Node2D and p.global_position.distance_to(global_position) >= min_roam_distance:
				var d := _find_landing(p.global_position.x, p.global_position.y - 40.0, 120.0)
				if d != Vector2.INF:
					return d
		return Vector2.INF

	# Otherwise it picks random spots near where it started.
	for i in 20:
		var x := home_pos.x + randf_range(-roam_radius, roam_radius)
		var d := _find_landing(x, home_pos.y - roam_height_up, roam_height_up + roam_height_down)
		if d != Vector2.INF and d.distance_to(global_position) >= min_roam_distance:
			return d
	return Vector2.INF


func _find_behind_player() -> Vector2:
	var p := chase_target
	if p == null:
		return Vector2.INF
	var behind: int = -_player_facing(p)
	var sides: Array[int] = [behind, -behind]
	var mults: Array[float] = [1.0, 1.5, 2.0]
	# Try behind the slime first, then (as a fallback) in front of it
	for side: int in sides:
		for mult: float in mults:
			var x: float = p.global_position.x + side * behind_distance * mult
			var d: Vector2 = _find_landing(x, p.global_position.y - ground_search_up,
					ground_search_up + ground_search_down)
			if d != Vector2.INF:
				return d
	return Vector2.INF


# Which way is the slime facing? Uses a `facing_dir` variable on the slime if it has one,
# otherwise its movement direction, otherwise assumes it faces toward the king.
func _player_facing(p: Node2D) -> int:
	var f: Variant = p.get("facing_dir")
	if f is int or f is float:
		return 1 if f > 0 else -1
	var v: Variant = p.get("velocity")
	if v is Vector2 and absf(v.x) > 5.0:
		return 1 if v.x > 0.0 else -1
	return 1 if global_position.x > p.global_position.x else -1


# Finds a valid standing spot below (x, from_y). Returns Vector2.INF if there isn't one.
func _find_landing(x: float, from_y: float, depth: float) -> Vector2:
	var query := PhysicsRayQueryParameters2D.create(Vector2(x, from_y), Vector2(x, from_y + depth))
	query.exclude = _exclude_rids()
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector2.INF
	if hit.normal.y > -0.5:
		return Vector2.INF   # not a floor surface

	var dest := Vector2(x, hit.position.y - _feet_offset() - 1.0)
	if not _space_is_free(dest):
		return Vector2.INF
	return dest


func _space_is_free(pos: Vector2) -> bool:
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = body_shape.shape
	params.transform = Transform2D(0.0, pos + body_shape.position)
	params.collision_mask = collision_mask
	params.exclude = _exclude_rids()
	params.collide_with_areas = false
	for result in get_world_2d().direct_space_state.intersect_shape(params, 8):
		var c: Object = result.collider
		if c is Node and (c as Node).is_in_group("player"):
			continue
		return false
	return true


func _exclude_rids() -> Array[RID]:
	var rids: Array[RID] = [get_rid()]
	for p in get_tree().get_nodes_in_group("player"):
		if p is CollisionObject2D:
			rids.append(p.get_rid())
	return rids


func _feet_offset() -> float:
	var half := 14.0
	var shape := body_shape.shape
	if shape is RectangleShape2D:
		half = (shape as RectangleShape2D).size.y * 0.5
	elif shape is CapsuleShape2D:
		half = (shape as CapsuleShape2D).height * 0.5
	elif shape is CircleShape2D:
		half = (shape as CircleShape2D).radius
	return body_shape.position.y + half


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


func _find_player() -> Node2D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0] as Node2D


func _can_see_player(player: Node2D) -> bool:
	var to_player := player.global_position - global_position
	if to_player.length() > sight_range:
		return false
	if absf(to_player.y) > sight_height:
		return false

	var query := PhysicsRayQueryParameters2D.create(global_position, player.global_position)
	query.exclude = [get_rid()]
	query.collision_mask = collision_mask
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit.collider == player or hit.collider.get_parent() == player


func _in_melee_range() -> bool:
	if chase_target == null:
		return false
	var to_player := chase_target.global_position - global_position
	return absf(to_player.x) <= attack_range and absf(to_player.y) <= 24.0


func _face_target() -> void:
	if chase_target:
		var dx := chase_target.global_position.x - global_position.x
		if absf(dx) > 1.0:
			facing_dir = 1 if dx > 0.0 else -1


# ---------- animation ----------

func _play_state_animation() -> void:
	var kind := "idle"
	if state == States.ATTACK:
		kind = "attack"
	var anim := _anim(kind)
	var frames := animated_sprite.sprite_frames
	if frames == null or not frames.has_animation(anim):
		return
	if animated_sprite.animation != anim:
		animated_sprite.play(anim)


func _anim(kind: String) -> StringName:
	return StringName(kind + ("_right" if facing_dir >= 0 else "_left"))
