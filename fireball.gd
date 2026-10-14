extends CharacterBody2D

enum Phase { PREPARE, FLY, EXPLODE }

const PROJECTILE_LAYER := 16

@export var fly_speed := 150.0
@export var knockback := Vector2(140.0, -60.0)
@export var lifetime := 3.5

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D

var phase: Phase = Phase.PREPARE
var facing: int = 1
var caster: Node
var follow_caster := false
var did_hit := false
var reflected := false
var bounce_grace := 0.0
var life_left := 0.0
var spawn_offset := Vector2(14.0, -10.0)


func _ready() -> void:
	add_to_group("projectiles")
	motion_mode = MOTION_MODE_FLOATING
	collision_layer = 0
	collision_mask = 0
	body_shape.disabled = true
	var frames := sprite.sprite_frames
	if frames:
		for anim in ["explode_left", "explode_right"]:
			if frames.has_animation(anim):
				frames.set_animation_loop(anim, false)
	sprite.animation_finished.connect(_on_animation_finished)


func prepare_at(caster_node: Node2D, dir: int, offset: Vector2 = Vector2(14.0, -10.0)) -> void:
	caster = caster_node
	facing = 1 if dir >= 0 else -1
	spawn_offset = offset
	follow_caster = true
	phase = Phase.PREPARE
	did_hit = false
	reflected = false
	bounce_grace = 0.0
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	body_shape.disabled = true
	sprite.rotation = 0.0
	sprite.play(_anim("prepare"))
	_snap_to_caster()


func launch(dir: Vector2) -> void:
	follow_caster = false
	phase = Phase.FLY
	life_left = lifetime
	if absf(dir.x) > 0.01:
		facing = 1 if dir.x > 0.0 else -1
	var aim := dir.normalized()
	if aim == Vector2.ZERO:
		aim = Vector2(float(facing), 0.0)
	velocity = aim * fly_speed
	sprite.play(_anim("move"))
	sprite.rotation = aim.angle() if facing >= 0 else aim.angle() + PI
	collision_layer = PROJECTILE_LAYER
	collision_mask = 1
	body_shape.disabled = false


func _physics_process(delta: float) -> void:
	if phase == Phase.PREPARE:
		if follow_caster:
			_snap_to_caster()
		return

	if phase == Phase.EXPLODE:
		velocity = Vector2.ZERO
		return

	life_left -= delta
	bounce_grace = maxf(0.0, bounce_grace - delta)
	if life_left <= 0.0:
		_explode()
		return

	if bounce_grace <= 0.0 and _try_reflect_from_mirrors():
		return

	move_and_slide()
	for i in get_slide_collision_count():
		var col := get_slide_collision(i).get_collider()
		if col == caster and not reflected:
			continue
		if _is_mirror(col):
			if bounce_grace <= 0.0:
				_reflect_off(col)
			return
		if col is Node and (col as Node).is_in_group("player"):
			_hit_player(col)
		elif reflected and col is Node and (col as Node).is_in_group("enemies"):
			_hit_enemy(col)
		if col is Node and (col as Node).has_method("explode"):
			col.explode()
		_explode()
		return


func _snap_to_caster() -> void:
	if not is_instance_valid(caster) or caster is not Node2D:
		queue_free()
		return
	var c := caster as Node2D
	var dir: int = facing
	var f: Variant = c.get("facing_dir")
	if f is int or f is float:
		dir = 1 if f >= 0 else -1
		facing = dir
		if sprite.animation != _anim("prepare"):
			sprite.play(_anim("prepare"))
	global_position = c.global_position + Vector2(spawn_offset.x * dir, spawn_offset.y)


func reflect_toward(dir: Vector2) -> void:
	if phase != Phase.FLY:
		return
	reflected = true
	did_hit = false
	bounce_grace = 0.35
	life_left = lifetime
	var aim := dir.normalized()
	if aim == Vector2.ZERO:
		aim = -velocity.normalized()
	if aim == Vector2.ZERO:
		aim = Vector2(float(-facing), 0.0)
	if absf(aim.x) > 0.01:
		facing = 1 if aim.x > 0.0 else -1
	velocity = aim * fly_speed
	global_position += aim * 10.0
	sprite.play(_anim("move"))
	sprite.rotation = aim.angle() if facing >= 0 else aim.angle() + PI


func _try_reflect_from_mirrors() -> bool:
	for node in get_tree().get_nodes_in_group("mirrorblocks"):
		if _overlaps_mirror(node):
			_reflect_off(node)
			return true
	return false


func _overlaps_mirror(mirror: Node) -> bool:
	if mirror is not Node2D or not is_instance_valid(mirror):
		return false
	var solid := (mirror as Node).get_node_or_null("CollisionShape2D") as CollisionShape2D
	if solid == null or solid.shape is not RectangleShape2D:
		return global_position.distance_to((mirror as Node2D).global_position) < 12.0
	var size: Vector2 = (solid.shape as RectangleShape2D).size
	var center := solid.global_position
	var fb_half := Vector2(8.0, 7.0)
	if body_shape and body_shape.shape is RectangleShape2D:
		fb_half = (body_shape.shape as RectangleShape2D).size * 0.5
	var mirror_half := size * 0.5
	var delta := global_position - center
	return absf(delta.x) <= mirror_half.x + fb_half.x and absf(delta.y) <= mirror_half.y + fb_half.y


func _is_mirror(col: Object) -> bool:
	var n := col as Node
	while n:
		if n.is_in_group("mirrorblocks") or n.has_method("reflect_magic"):
			return true
		n = n.get_parent()
	return false


func _reflect_off(col: Object) -> void:
	var n := col as Node
	while n:
		if n.has_method("reflect_magic"):
			n.reflect_magic(self)
			return
		n = n.get_parent()
	var toward := -velocity
	var c: Variant = caster
	if c is Node2D and is_instance_valid(c):
		toward = (c as Node2D).global_position - global_position
	reflect_toward(toward)


func _hit_enemy(body: Node) -> void:
	if did_hit:
		return
	did_hit = true
	var blast: Node = body.get_node_or_null("EnemyBlast")
	if blast and blast.has_method("take_bomb_hit"):
		blast.take_bomb_hit(global_position)


func _hit_player(body: Node) -> void:
	if did_hit:
		return
	did_hit = true
	var knock_dir := signf(body.global_position.x - global_position.x)
	if knock_dir == 0.0:
		knock_dir = float(facing)
	if body.has_method("take_hit"):
		body.take_hit(knock_dir, knockback)
	elif body is CharacterBody2D:
		body.velocity = Vector2(knock_dir * knockback.x, knockback.y)


func _explode() -> void:
	if phase == Phase.EXPLODE:
		return
	phase = Phase.EXPLODE
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	body_shape.set_deferred("disabled", true)
	sprite.rotation = 0.0
	var anim := _anim("explode")
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)
	else:
		queue_free()


func _on_animation_finished() -> void:
	if phase == Phase.EXPLODE:
		queue_free()


func _anim(kind: String) -> StringName:
	return StringName(kind + ("_right" if facing >= 0 else "_left"))
