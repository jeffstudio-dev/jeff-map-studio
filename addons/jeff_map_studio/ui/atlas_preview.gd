@tool
extends Control

signal tile_selected(coords: Vector2i)
var source: TileSetAtlasSource
var selected := Vector2i.ZERO
var _rect := Rect2()

func _ready() -> void:
	custom_minimum_size.y = 180
	resized.connect(queue_redraw)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("101d26"))
	if source == null or source.texture == null:
		return
	var texture_size := Vector2(source.texture.get_size())
	var zoom := minf(size.x / texture_size.x, size.y / texture_size.y)
	_rect = Rect2((size - texture_size * zoom) / 2, texture_size * zoom)
	draw_texture_rect(source.texture, _rect, false)
	var region := Vector2(source.texture_region_size)
	var separation := Vector2(source.separation)
	var margin := Vector2(source.margins)
	if region.x * zoom > 5:
		var grid := source.get_atlas_grid_size()
		for y in grid.y:
			for x in grid.x:
				var rect := Rect2(_rect.position + (margin + Vector2(x, y) * (region + separation)) * zoom, region * zoom)
				draw_rect(rect, Color(0.7, 0.9, 0.8, 0.25), false)
	var selected_rect := Rect2(_rect.position + (margin + Vector2(selected) * (region + separation)) * zoom, region * zoom)
	draw_rect(selected_rect, Color("e6c47a"), false, 2.0)

func _gui_input(event: InputEvent) -> void:
	if source != null and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and _rect.has_point(event.position):
		var image_point: Vector2 = (event.position - _rect.position) / _rect.size * Vector2(source.texture.get_size())
		var coords := Vector2i((image_point - Vector2(source.margins)) / Vector2(source.texture_region_size + source.separation))
		if source.has_tile(coords):
			selected = coords
			tile_selected.emit(coords)
			queue_redraw()
