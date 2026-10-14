extends "res://scripts/pickup_block.gd"

const PROJECTILE_LAYER := 16


func _ready() -> void:
	super._ready()
	add_to_group("mirrorblocks")
	_setup_reflect_area()


func _setup_reflect_area() -> void:
	var reflect := Area2D.new()
	reflect.name = "ReflectArea"
	reflect.collision_layer = 0
	reflect.collision_mask = PROJECTILE_LAYER
	reflect.monitorable = false
	reflect.monitoring = true
	var cs := CollisionShape2D.new()
	if solid_shape.shape:
		cs.shape = solid_shape.shape
	cs.position = solid_shape.position
	reflect.add_child(cs)
	add_child(reflect)
	reflect.body_entered.connect(_on_reflect_body)


func _on_reflect_body(body: Node) -> void:
	if body != null and body.has_method("reflect_toward"):
		reflect_magic(body)


func reflect_magic(fireball: Node) -> void:
	if fireball == null or not fireball.has_method("reflect_toward"):
		return
	var toward := Vector2.LEFT
	var caster: Variant = fireball.get("caster")
	if caster is Node2D and is_instance_valid(caster):
		toward = (caster as Node2D).global_position - (fireball as Node2D).global_position
	else:
		var vel: Variant = fireball.get("velocity")
		if vel is Vector2:
			toward = -(vel as Vector2)
	if toward.length_squared() < 0.01 and fireball is Node2D:
		toward = global_position - (fireball as Node2D).global_position
	fireball.reflect_toward(toward)
