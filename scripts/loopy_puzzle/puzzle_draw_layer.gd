extends Node2D
## Draws puzzle content (edges, dots, clues, black hole, progress, transition)
## above the CRT overlay so it is not affected by barrel warp distortion.

func _draw() -> void:
	var parent = get_parent()
	if parent == null:
		return
	parent._draw_puzzle_layer(self)
