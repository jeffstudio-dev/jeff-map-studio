@tool
class_name MapEdits
extends RefCounted

enum Tool { SELECT, TERRAIN, ERASE, FILL, RAISE, LOWER, DECORATION, LOCK, UNLOCK }

static func brush(data: MapData, center: Vector2i, tool: int, terrain_id: int, radius: int, decoration_id: int, touched: Dictionary = {}) -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	if not data.contains(center) or tool == Tool.SELECT:
		return changed
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var cell := center + Vector2i(dx, dy)
			if not data.contains(cell) or touched.has(cell):
				continue
			if data.profile.grid == MapProfile.Grid.HEX and MapGrid.distance(cell, center, data.profile.grid) > radius:
				continue
			var i := data.index_of(cell)
			match tool:
				Tool.TERRAIN:
					data.terrain[i] = terrain_id
					if terrain_id == MapData.Terrain.WATER:
						data.elevation[i] = 0
						data.decoration[i] = 0
				Tool.ERASE:
					data.terrain[i] = -1
					data.elevation[i] = 0
					data.decoration[i] = 0
				Tool.RAISE:
					if data.terrain[i] >= 0:
						data.elevation[i] = mini(16, data.elevation[i] + 1)
				Tool.LOWER:
					data.elevation[i] = maxi(0, data.elevation[i] - 1)
				Tool.DECORATION:
					if data.terrain[i] >= 0:
						data.decoration[i] = decoration_id
				Tool.LOCK:
					data.locked[i] = 1
				Tool.UNLOCK:
					data.locked[i] = 0
			data.manual[i] = 1
			touched[cell] = true
			changed.append(cell)
	return changed

static func flood_fill(data: MapData, start: Vector2i, terrain_id: int) -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	if not data.contains(start):
		return changed
	var original := data.terrain[data.index_of(start)]
	if original == terrain_id:
		return changed
	var queue: Array[Vector2i] = [start]
	var visited: Dictionary = {start: true}
	var cursor := 0
	while cursor < queue.size():
		var cell := queue[cursor]
		cursor += 1
		var i := data.index_of(cell)
		data.terrain[i] = terrain_id
		data.manual[i] = 1
		if terrain_id == MapData.Terrain.WATER:
			data.elevation[i] = 0
			data.decoration[i] = 0
		changed.append(cell)
		for direction: Vector2i in MapGrid.directions(data.profile.grid):
			var next := cell + direction
			if data.contains(next) and not visited.has(next) and data.terrain[data.index_of(next)] == original:
				visited[next] = true
				queue.append(next)
	return changed
