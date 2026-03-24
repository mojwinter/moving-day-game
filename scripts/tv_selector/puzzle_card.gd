extends Control
## A single puzzle splash card for the TV selector carousel.

@export var puzzle_name: String = "PUZZLE"
@export var puzzle_scene_path: String = ""
@export var preview_color: Color = Color(0.15, 0.2, 0.3)
@export var preview_texture: Texture2D = null


func _ready() -> void:
	var color_rect := get_node_or_null("CardBG/PreviewColor") as ColorRect
	var tex_rect := get_node_or_null("CardBG/PreviewImage") as TextureRect
	var title := get_node_or_null("CardBG/TitleLabel") as Label
	if color_rect:
		color_rect.color = preview_color
	if tex_rect and preview_texture:
		tex_rect.texture = preview_texture
	elif tex_rect:
		tex_rect.visible = false
	if title:
		title.text = puzzle_name
