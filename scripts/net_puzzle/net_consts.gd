extends RefCounted
## Shared direction constants for the Net puzzle.

const DIR_R := 1
const DIR_U := 2
const DIR_L := 4
const DIR_D := 8

const DIRECTIONS := [1, 2, 4, 8]  # R, U, L, D

# Literal int keys because Godot 4.x doesn't allow const-refs as dict keys.
const DIR_OFFSET := {
	1: Vector2i(1, 0),   # R
	2: Vector2i(0, -1),  # U
	4: Vector2i(-1, 0),  # L
	8: Vector2i(0, 1),   # D
}


## Returns the opposite direction. Port of net.c F(d) macro.
static func opposite(dir: int) -> int:
	return ((dir & 0x0C) >> 2) | ((dir & 0x03) << 2)
