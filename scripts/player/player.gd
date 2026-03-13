extends CharacterBody2D

const SPEED := 60.0

var direction := "down"
var is_moving := false

@onready var sprite_layers: Array[AnimatedSprite2D] = [
	$Body,
	$Clothes,
	$Eyes,
	$Hair,
]


func _physics_process(_delta: float) -> void:
	var input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	if input != Vector2.ZERO:
		velocity = input.normalized() * SPEED
		is_moving = true
		if abs(input.x) > abs(input.y):
			direction = "right" if input.x > 0 else "left"
		else:
			direction = "down" if input.y > 0 else "up"
	else:
		velocity = Vector2.ZERO
		is_moving = false

	move_and_slide()

	var anim := ("walk_" if is_moving else "idle_") + direction
	for sprite in sprite_layers:
		if sprite and sprite.animation != anim:
			sprite.play(anim)
