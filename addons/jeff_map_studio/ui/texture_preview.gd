@tool
extends Control

var texture: Texture2D:
	set(value):
		texture = value
		queue_redraw()

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("111d27"))
	if texture == null:
		return
	var single := minf(size.x - 60, size.y * 0.32)
	var first := Rect2(Vector2((size.x - single) * 0.5, 34), Vector2.ONE * single)
	draw_texture_rect(texture, first, false)
	var cell_size := minf((size.x - 60) / 3, (size.y - single - 115) / 3)
	var origin := Vector2((size.x - cell_size * 3) * 0.5, single + 96)
	for y in 3:
		for x in 3:
			draw_texture_rect(texture, Rect2(origin + Vector2(x, y) * cell_size, Vector2.ONE * cell_size), false)
	draw_string(get_theme_default_font(), Vector2(20, 22), "单张纹理", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("a4bfba"))
	draw_string(get_theme_default_font(), Vector2(20, single + 82), "3 × 3 连续平铺", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("a4bfba"))
