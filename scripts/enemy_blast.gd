extends Node

const FLY_SPEED := 250.0
const LIFT := -80.0
const GRAVITY := 200.0

var hits_to_kill := 1
var hp := 1
var blasting := false
var killing := false
var dir := 1
var air_t := 0.0
var blink_t := 0.0
var host: CharacterBody2D
var sprite: AnimatedSprite2D


func _init(p_hits: int = 1) -> void:
	hits_to_kill = p_hits
	hp = p_hits


func _ready() -> void:
	name = "EnemyBlast"
	host = get_parent() as CharacterBody2D
	sprite = host.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	set_physics_process(false)


func take_bomb_hit(from_pos: Vector2) -> void:
	if killing or host == null:
		return
	hp -= 1
	dir = 1 if host.global_position.x >= from_pos.x else -1
	if dir == 0:
		dir = 1
	blasting = true
	killing = hp <= 0
	air_t = 0.0
	blink_t = 0.0
	host.velocity = Vector2(float(dir) * FLY_SPEED, LIFT)
	host.set("facing_dir", dir)
	host.collision_mask = 1
	host.motion_mode = CharacterBody2D.MOTION_MODE_GROUNDED
	host.set("flying", false)
	if sprite:
		sprite.rotation = 0.0
		sprite.modulate = Color.WHITE
	var hitbox: Variant = host.get("attack_hitbox")
	if hitbox is Area2D:
		(hitbox as Area2D).set_deferred("monitoring", false)
	if host.has_method("_clear_fireball"):
		host.call("_clear_fireball")
	var status: Node = host.get_node_or_null("EnemyStatus")
	if status and status.has_method("clear"):
		status.clear(false)
	host.set_physics_process(false)
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if host == null or not is_instance_valid(host):
		return
	air_t += delta
	if not host.is_on_floor():
		host.velocity.y += GRAVITY * delta
	host.velocity.x = float(dir) * FLY_SPEED
	_play_sent()
	if killing:
		blink_t += delta
		if sprite:
			sprite.modulate.a = 1.0 if int(blink_t * 14.0) % 2 == 0 else 0.12
		host.move_and_slide()
		if blink_t > 1.2 or (air_t > 0.12 and (host.is_on_wall() or host.is_on_floor())):
			host.queue_free()
		return
	host.move_and_slide()
	if air_t > 0.12 and (host.is_on_wall() or host.is_on_floor()):
		host.velocity = Vector2.ZERO
		blasting = false
		if sprite:
			sprite.modulate = Color.WHITE
		set_physics_process(false)
		host.set_physics_process(true)
		if host.has_method("_enter_idle"):
			host.call("_enter_idle")


func _play_sent() -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	var anim := StringName("sent_right" if dir >= 0 else "sent_left")
	if sprite.sprite_frames.has_animation(anim) and sprite.animation != anim:
		sprite.play(anim)
