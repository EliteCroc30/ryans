extends CharacterBody2D


const SPEED = 300.0
const JUMP_VELOCITY = -400.0

@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var sprite: Sprite2D = $Sprite2D
@onready var camera: Camera2D = $Camera2D
@onready var hitbox: CollisionShape2D = $CollisionShape2D

var bounds := Rect2()

func _physics_process(delta: float) -> void:
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = direction * SPEED
	move_and_slide()
	_clamp_to_camera_limits()

	if direction:
		anim.play("new_animation23")
		if direction.x != 0:
			sprite.flip_h = direction.x > 0
	else:
		anim.play("RESET")


# Keeps the player's hitbox inside `bounds` (the world script sets it to cover the hallway and
# all rooms). If nothing sets it, the Camera2D limits are used.
func _clamp_to_camera_limits() -> void:
	var area := bounds
	if not area.has_area():
		area = Rect2(camera.limit_left, camera.limit_top,
			camera.limit_right - camera.limit_left, camera.limit_bottom - camera.limit_top)
	var half := Vector2.ZERO
	var offset := Vector2.ZERO
	if hitbox and hitbox.shape is RectangleShape2D:
		half = (hitbox.shape as RectangleShape2D).size * 0.5 * global_scale.abs()
		offset = hitbox.position * global_scale
	var min_pos := area.position + half - offset
	var max_pos := area.end - half - offset
	global_position = global_position.clamp(min_pos, max_pos)
