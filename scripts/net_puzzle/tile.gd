extends Node2D
## Visual representation of a single grid tile.
## Draws connection arms via _draw() and handles click input via Area2D.
## Supports three draw modes: ROTATION, TRACE, and CALIBRATION.

const NC := preload("res://scripts/net_puzzle/net_consts.gd")

signal tile_clicked(grid_x: int, grid_y: int)

const CELL_SIZE := 120.0
const ARM_WIDTH := 8.0
const CENTER := Vector2(CELL_SIZE / 2.0, CELL_SIZE / 2.0)

const BG_COLOR := Color(0.15, 0.15, 0.2)
const ACTIVE_COLOR := Color(1.0, 0.85, 0.0)   # warm yellow when powered
const INACTIVE_COLOR := Color(0.4, 0.4, 0.45)  # gray when unpowered
const SOURCE_COLOR := Color(1.0, 1.0, 1.0)     # white source indicator
const SOLDER_COLOR := Color(0.8, 0.8, 0.8)     # bright silver for soldered traces
const UNSOLDER_COLOR := Color(0.25, 0.25, 0.3) # dim for unsoldered traces

## Draw mode enum matching net_puzzle.gd Stage enum values.
enum DrawMode { ROTATION, TRACE, CALIBRATION }
var draw_mode: int = DrawMode.ROTATION

## Color override used by calibration stage to tint all arms.
var calibration_color: Color = SOLDER_COLOR

var grid_x: int = 0
var grid_y: int = 0
var tile_data = null


func setup(x: int, y: int) -> void:
	grid_x = x
	grid_y = y


func refresh(data) -> void:
	tile_data = data
	queue_redraw()


func _draw() -> void:
	# Background
	draw_rect(Rect2(2, 2, CELL_SIZE - 4, CELL_SIZE - 4), BG_COLOR)

	if tile_data == null:
		return

	if draw_mode == DrawMode.ROTATION:
		_draw_rotation()
	elif draw_mode == DrawMode.TRACE:
		_draw_trace()
	elif draw_mode == DrawMode.CALIBRATION:
		_draw_calibration()


func _draw_rotation() -> void:
	var color: Color = ACTIVE_COLOR if tile_data.is_active else INACTIVE_COLOR
	_draw_arms(color)
	draw_circle(CENTER, ARM_WIDTH * 0.75, color)
	if tile_data.is_source:
		draw_circle(CENTER, 12.0, SOURCE_COLOR)


func _draw_trace() -> void:
	var color: Color = SOLDER_COLOR if tile_data.is_soldered else UNSOLDER_COLOR
	_draw_arms(color)
	draw_circle(CENTER, ARM_WIDTH * 0.75, color)
	if tile_data.is_source:
		draw_circle(CENTER, 12.0, SOURCE_COLOR)


func _draw_calibration() -> void:
	_draw_arms(calibration_color)
	draw_circle(CENTER, ARM_WIDTH * 0.75, calibration_color)
	if tile_data.is_source:
		draw_circle(CENTER, 12.0, SOURCE_COLOR)

	# Draw potentiometer knob if this tile has one
	if tile_data.has_pot:
		_draw_pot_knob()


func _draw_pot_knob() -> void:
	var knob_radius := 28.0
	var knob_bg := Color(0.3, 0.3, 0.35)
	var knob_ring := Color(0.6, 0.6, 0.65)

	# Knob background circle
	draw_circle(CENTER, knob_radius, knob_bg)
	# Outer ring
	draw_arc(CENTER, knob_radius, 0, TAU, 32, knob_ring, 2.0)

	# Indicator line: pot_value 0-100 maps to angle range (roughly 225 deg sweep)
	# 0 = 7 o'clock (225 deg), 100 = 5 o'clock (-45 deg / 315 deg)
	var min_angle := deg_to_rad(225.0)  # 0 position
	var max_angle := deg_to_rad(-45.0)  # 100 position (same as 315 but going CW)
	var t: float = float(tile_data.pot_value) / 100.0
	var angle := min_angle + t * (max_angle - min_angle)
	var indicator_end := CENTER + Vector2(cos(angle), -sin(angle)) * (knob_radius - 4.0)
	draw_line(CENTER, indicator_end, Color.WHITE, 3.0, true)

	# Dial label (V / R / F) above the knob
	var font := ThemeDB.fallback_font
	if tile_data.pot_label != "":
		var label_size := 16
		var label_w := font.get_string_size(tile_data.pot_label, HORIZONTAL_ALIGNMENT_CENTER, -1, label_size)
		draw_string(font, CENTER + Vector2(-label_w.x / 2.0, -knob_radius - 6.0),
			tile_data.pot_label, HORIZONTAL_ALIGNMENT_CENTER, -1, label_size, Color.WHITE)

	# Value label below the knob
	var val_str := str(tile_data.pot_value)
	var font_size := 14
	var text_size := font.get_string_size(val_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(font, CENTER + Vector2(-text_size.x / 2.0, knob_radius + 16.0), val_str, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)


func _draw_arms(color: Color) -> void:
	for dir in NC.DIRECTIONS:
		if tile_data.has_connection(dir):
			var end_offset := Vector2(NC.DIR_OFFSET[dir]) * (CELL_SIZE / 2.0)
			draw_line(CENTER, CENTER + end_offset, color, ARM_WIDTH, true)


func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tile_clicked.emit(grid_x, grid_y)
