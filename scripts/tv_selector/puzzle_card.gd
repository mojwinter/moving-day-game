extends Control
## A single puzzle splash card for the TV selector carousel.

@export var puzzle_name: String = "PUZZLE"
@export var puzzle_scene_path: String = ""
@export var preview_color: Color = Color(0.15, 0.2, 0.3)
@export var preview_texture: Texture2D = null
@export var title_texture: Texture2D = null


func _ready() -> void:
	var color_rect := get_node_or_null("CardBG/PreviewColor") as ColorRect
	var tex_rect := get_node_or_null("CardBG/PreviewImage") as TextureRect
	var title_img := get_node_or_null("CardBG/TitleImage") as TextureRect
	if color_rect:
		color_rect.color = preview_color
	if tex_rect and preview_texture:
		tex_rect.texture = preview_texture
	elif tex_rect:
		tex_rect.visible = false
	if title_img and title_texture:
		title_img.texture = title_texture
		# Center at native size within the title area
		var tex_size := title_texture.get_size()
		title_img.size = tex_size
		title_img.position = Vector2(
			(240.0 - tex_size.x) / 2.0,
			85.0 + (25.0 - tex_size.y) / 2.0 + 1.0
		)
	elif title_img:
		title_img.visible = false
