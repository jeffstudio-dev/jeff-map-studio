@tool
class_name MapStudioCanvas
extends Control

signal stroke_committed(before: MapData, after: MapData)
signal edit_requested(before: MapData, after: MapData)
signal edit_rejected(message: String)
signal cell_hovered(cell: Vector2i, info: Dictionary)

var map: JeffMap2D
var overlay: Node2D
var tool: int = MapEdits.Tool.SELECT
var terrain_id: int = MapData.Terrain.GRASS
var radius: int = 0
var decoration_id: int = 1
var _panning: bool = false
var _painting: bool = false
var _before: MapData
var _touched: Dictionary = {}

func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	map = JeffMap2D.new()
	map.name = "PreviewMap"
	add_child(map)
	overlay = Node2D.new()
	overlay.set_script(preload("res://addons/jeff_map_studio/ui/map_overlay.gd"))
	overlay.map = map
	add_child(overlay)
	map.generation_completed.connect(func(_data: MapData) -> void:
		overlay.refresh_locks()
		queue_redraw())
	resized.connect(queue_redraw)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("111d27"))
	for x in range(24, int(size.x), 40):
		for y in range(24, int(size.y), 40):
			draw_circle(Vector2(x, y), 0.7, Color("263540"))
	if map == null or map.map_data == null:
		draw_string(ThemeDB.fallback_font, size * 0.5 + Vector2(-125, 0), "选择一个预设，开始生成地图", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("8caaa9"))

func fit_map() -> void:
	if map == null or map.map_data == null or size.x < 1:
		return
	var p := map.map_data.profile
	var points := [Vector2i.ZERO, Vector2i(p.width - 1, 0), Vector2i(0, p.height - 1), Vector2i(p.width - 1, p.height - 1)]
	var bounds := Rect2(map.cell_to_local(points[0], false), Vector2.ZERO)
	for cell: Vector2i in points:
		bounds = bounds.expand(map.cell_to_local(cell, false))
	bounds = bounds.grow(p.tile_size + 16 * p.height_step)
	var zoom := clampf(minf(size.x / bounds.size.x, size.y / bounds.size.y) * 0.9, 0.015, 3.0)
	map.scale = Vector2.ONE * zoom
	map.position = size * 0.5 - bounds.get_center() * zoom
	overlay.queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if map == null:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_WHEEL_UP or mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mouse.pressed:
				var old_zoom := map.scale.x
				var new_zoom := clampf(old_zoom * (1.15 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.015, 5.0)
				map.position = mouse.position - (mouse.position - map.position) * new_zoom / old_zoom
				map.scale = Vector2.ONE * new_zoom
				overlay.queue_redraw()
			accept_event()
		elif mouse.button_index == MOUSE_BUTTON_MIDDLE or mouse.button_index == MOUSE_BUTTON_RIGHT:
			_panning = mouse.pressed
			accept_event()
		elif mouse.button_index == MOUSE_BUTTON_LEFT:
			grab_focus()
			if mouse.pressed and not map.busy and map.map_data != null:
				var cell := map.local_to_cell((mouse.position - map.position) / map.scale)
				if not map.map_data.contains(cell) or tool == MapEdits.Tool.SELECT:
					return
				_before = map.map_data.copy()
				if tool == MapEdits.Tool.FILL:
					var after := _before.copy()
					MapEdits.flood_fill(after, cell, terrain_id)
					edit_requested.emit(_before, after)
					_before = null
				else:
					_painting = true
					_touched.clear()
					_paint(cell)
			elif not mouse.pressed:
				_finish_stroke()
			accept_event()
	elif event is InputEventMouseMotion:
		var mouse := event as InputEventMouseMotion
		if _panning:
			map.position += mouse.relative
		if map.map_data != null:
			var cell := map.local_to_cell((mouse.position - map.position) / map.scale)
			overlay.hover = cell
			cell_hovered.emit(cell, map.get_cell(cell))
			if _painting and not map.busy:
				_paint(cell)
		overlay.queue_redraw()

func _paint(cell: Vector2i) -> void:
	var changed := MapEdits.brush(map.map_data, cell, tool, terrain_id, radius, decoration_id, _touched)
	if not changed.is_empty():
		map.renderer.error = ""
		map.refresh_cells(changed)
		if not map.renderer.error.is_empty():
			var message := map.renderer.error
			map.map_data = _before.copy()
			map.renderer.data = map.map_data
			var affected: Array[Vector2i] = []
			affected.assign(_touched.keys())
			map.renderer.error = ""
			map.refresh_cells(affected)
			_painting = false
			_before = null
			_touched.clear()
			edit_rejected.emit(message)
		overlay.refresh_locks()

func _finish_stroke() -> void:
	if _painting and _before != null and not _touched.is_empty():
		stroke_committed.emit(_before, map.map_data.copy())
	_painting = false
	_before = null
	_touched.clear()

func _input(event: InputEvent) -> void:
	# Releasing outside the viewport must still close a brush transaction.
	if _painting and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_finish_stroke()
	if _panning and event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE) and not event.pressed:
		_panning = false
