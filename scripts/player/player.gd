extends CharacterBody2D

const SPEED := 60.0

var direction := "down"
var is_moving := false
var can_move := true

@onready var sprite_layers: Array[AnimatedSprite2D] = [
	$Body,
	$Clothes,
	$Eyes,
	$Hair,
]


func _ready() -> void:
	add_to_group("player")


func _physics_process(_delta: float) -> void:
	if not can_move:
		velocity = Vector2.ZERO
		is_moving = false
		var anim := "idle_" + direction
		for sprite in sprite_layers:
			if sprite and sprite.animation != anim:
				sprite.play(anim)
		return

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
