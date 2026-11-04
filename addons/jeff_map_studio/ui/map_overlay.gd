@tool
extends Node2D

var map: JeffMap2D
var hover := Vector2i(-1, -1)
var show_locks: bool = true
var locked_cells: Array[Vector2i] = []

func refresh_locks() -> void:
	locked_cells.clear()
	if map != null and map.map_data != null:
		for i in map.map_data.locked.size():
			if map.map_data.locked[i]:
				locked_cells.append(map.map_data.cell_at(i))
	queue_redraw()

func _draw() -> void:
	if map == null or map.map_data == null:
		return
	var data := map.map_data
	var polygon := MapGrid.polygon(data.profile)
	if show_locks and map.scale.x > 0.12:
		var drawn := 0
		for cell in locked_cells:
			var center := map.cell_to_local(cell)
			var screen := map.position + center * map.scale
			if not Rect2(Vector2.ZERO, get_parent().size).grow(100).has_point(screen):
				continue
			var points := PackedVector2Array()
			for point in polygon:
				points.append(map.position + (center + point * 0.8) * map.scale)
			draw_colored_polygon(points, Color(0.93, 0.72, 0.36, 0.18))
			draw_circle(screen, maxf(1.5, 3 * map.scale.x), Color("edbf76"))
			drawn += 1
			if drawn > 6000:
				break
	if data.contains(hover):
		var points := PackedVector2Array()
		var center := map.cell_to_local(hover)
		for point in polygon:
			points.append(map.position + (point + center) * map.scale)
		points.append(points[0])
		draw_polyline(points, Color("d4f3b8"), 2.0, true)
