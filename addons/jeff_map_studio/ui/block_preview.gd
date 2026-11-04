@tool
class_name MapBlockPreview
extends Control

var textures: Array[Texture2D] = []
var selected: int = 0:
	set(value):
		selected = value
		queue_redraw()

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("111d27"))
	if textures.size() != 3:
		return
	var font := get_theme_default_font()
	draw_string(font, Vector2(24, 30), "独立地块 · 顶面 + 侧面 + 标志物", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("c5d8cf"))
	draw_string(font, Vector2(24, 54), "与地图共用材质 · 导出图片为透明背景", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("8ba7a5"))
	var main_area := Rect2(24, 80, size.x - 48, maxf(80, size.y - 270))
	_draw_centered(textures[selected], main_area, 0.85)
	var captions := ["等角方形", "尖顶六角柱", "平顶六角柱"]
	var column := (size.x - 48) / 3.0
	for i in 3:
		var rect := Rect2(24 + column * i, size.y - 170, column - 8, 130)
		draw_rect(rect, Color("24433f") if i == selected else Color("1b2b34"))
		_draw_centered(textures[i], rect.grow(-14), 0.85)
		draw_string(font, Vector2(rect.position.x, size.y - 20), captions[i], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 12, Color("9db9b2"))

func _draw_centered(texture: Texture2D, area: Rect2, factor: float) -> void:
	var zoom := minf(area.size.x / texture.get_width(), area.size.y / texture.get_height()) * factor
	var dimensions := texture.get_size() * zoom
	draw_texture_rect(texture, Rect2(area.get_center() - dimensions * 0.5, dimensions), false)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.position.y > size.y - 180:
		selected = clampi(int((event.position.x - 24) / ((size.x - 48) / 3.0)), 0, 2)
		accept_event()
