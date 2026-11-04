@tool
class_name MapGenerator
extends RefCounted
## Pure data generation. No SceneTree, editor APIs or global random state.

static func random_at(seed_value: int, cell: Vector2i, stream: int = 0) -> float:
	var value := (seed_value ^ (cell.x * 374761393) ^ (cell.y * 668265263) ^ (stream * 1442695041)) & 0x7fffffff
	value = ((value ^ (value >> 13)) * 1274126177) & 0x7fffffff
	value = (value ^ (value >> 16)) & 0x7fffffff
	return float(value) / 2147483648.0

static func generate(profile: MapProfile, previous: MapData = null, job: MapGenerationJob = null) -> MapData:
	if job == null:
		job = MapGenerationJob.new()
	job.error = profile.validate()
	if not job.error.is_empty():
		return null
	var started := Time.get_ticks_usec()
	var data := MapData.new()
	data.initialize(profile)
	var rng := RandomNumberGenerator.new()
	rng.seed = profile.seed_value
	match profile.generator:
		MapProfile.Generator.NATURE:
			_nature(data, job)
		MapProfile.Generator.DUNGEON:
			_dungeon(data, rng, job)
		MapProfile.Generator.CAVE:
			_cave(data, job)
	if job.is_cancelled() or not job.error.is_empty():
		return null
	job.report(0.9, "布置装饰与保留锁定区域")
	for i in data.terrain.size():
		if i % 2048 == 0 and job.is_cancelled():
			return null
		var cell := data.cell_at(i)
		if random_at(profile.seed_value, cell, 37) < profile.decoration_density:
			match data.terrain[i]:
				MapData.Terrain.GRASS:
					data.decoration[i] = MapData.Decoration.MUSHROOMS if random_at(profile.seed_value, cell, 41) < 0.4 else MapData.Decoration.TREE
				MapData.Terrain.SAND:
					data.decoration[i] = MapData.Decoration.PALM
				MapData.Terrain.WATER:
					# Rare coastal markers; never populate the open sea with towers.
					if random_at(profile.seed_value, cell, 43) < 0.08:
						for direction: Vector2i in MapGrid.directions(profile.grid):
							var next := cell + direction
							if data.contains(next) and data.terrain[data.index_of(next)] in [MapData.Terrain.SAND, MapData.Terrain.GRASS]:
								data.decoration[i] = MapData.Decoration.LIGHTHOUSE
								break
				MapData.Terrain.ROCK, MapData.Terrain.SNOW:
					data.decoration[i] = 2
				MapData.Terrain.FLOOR:
					data.decoration[i] = 3
	var preserved := 0
	if previous != null and previous.validate().is_empty() and previous.profile.width == profile.width and previous.profile.height == profile.height and previous.profile.grid == profile.grid:
		for i in data.terrain.size():
			if previous.locked[i] != 0:
				data.terrain[i] = previous.terrain[i]
				data.elevation[i] = previous.elevation[i]
				data.decoration[i] = previous.decoration[i]
				data.locked[i] = previous.locked[i]
				data.manual[i] = previous.manual[i]
				preserved += 1
	data.metadata["preserved_cells"] = preserved
	data.metadata["generation_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	data.metadata["data_bytes"] = data.terrain.size() * 8
	if preserved > 0 and profile.generator != MapProfile.Generator.NATURE:
		data.metadata["regions_after_locks"] = floor_regions(data, job).size()
	job.report(1.0, "地图数据完成")
	return null if job.is_cancelled() else data

static func _noise(seed_value: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value & 0x7fffffff
	noise.frequency = frequency
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	return noise

static func _nature(data: MapData, job: MapGenerationJob) -> void:
	var p := data.profile
	var height_noise := _noise(p.seed_value, p.noise_scale, p.octaves)
	var moisture := _noise(p.seed_value + 3817, p.noise_scale * 0.7, 3)
	var temperature := _noise(p.seed_value + 7589, p.noise_scale * 0.45, 2)
	for y in p.height:
		if job.is_cancelled():
			return
		job.report(0.65 * y / p.height, "生成自然地形")
		for x in p.width:
			var cell := Vector2i(x, y)
			var i := data.index_of(cell)
			var point := MapGrid.sample_position(cell, p)
			var h := height_noise.get_noise_2dv(point) * 0.65 + 0.55
			if p.island:
				var normalized := Vector2((x + 0.5) / p.width * 2.0 - 1.0, (y + 0.5) / p.height * 2.0 - 1.0)
				h -= pow(normalized.length() / 1.1, 3.0) * 0.65
			var wet := moisture.get_noise_2dv(point)
			var cold := temperature.get_noise_2dv(point)
			var terrain := MapData.Terrain.GRASS
			if h < p.sea_level:
				terrain = MapData.Terrain.WATER
			elif h < p.sea_level + p.beach_width:
				terrain = MapData.Terrain.SAND
			elif h > 0.77 or (h > 0.65 and cold < -0.25):
				terrain = MapData.Terrain.SNOW
			elif h > 0.65:
				terrain = MapData.Terrain.ROCK
			elif wet < -0.28:
				terrain = MapData.Terrain.DIRT
			data.terrain[i] = terrain
			data.elevation[i] = 0 if terrain == MapData.Terrain.WATER else clampi(roundi((h - p.sea_level) / (1.0 - p.sea_level) * p.max_height * p.mountain_strength), 0, p.max_height)
	for iteration in p.smoothing:
		var next := data.elevation.duplicate()
		for y in p.height:
			if job.is_cancelled():
				return
			for x in p.width:
				var cell := Vector2i(x, y)
				var i := data.index_of(cell)
				if data.terrain[i] == MapData.Terrain.WATER:
					continue
				var total := int(data.elevation[i]) * 2
				var count := 2
				for direction: Vector2i in MapGrid.directions(p.grid):
					var n := cell + direction
					if data.contains(n):
						total += data.elevation[data.index_of(n)]
						count += 1
				next[i] = roundi(float(total) / count)
		data.elevation = next
		job.report(0.65 + 0.2 * (iteration + 1) / maxi(p.smoothing, 1), "平滑地块高度")

static func _dungeon(data: MapData, rng: RandomNumberGenerator, job: MapGenerationJob) -> void:
	var p := data.profile
	data.terrain.fill(MapData.Terrain.WALL)
	data.elevation.fill(mini(p.max_height, 2))
	var reserved := PackedByteArray()
	reserved.resize(data.terrain.size())
	var centers: Array[Vector2i] = []
	for attempt in p.room_count * 100:
		if job.is_cancelled():
			return
		if centers.size() >= p.room_count:
			break
		var w := rng.randi_range(p.room_min_size, p.room_max_size)
		var h := rng.randi_range(p.room_min_size, p.room_max_size)
		var center := Vector2i(rng.randi_range(1, p.width - 2), rng.randi_range(1, p.height - 2))
		var cells: Array[Vector2i] = []
		var valid := true
		var radius := maxi(1, w / 2)
		var bounds := Vector2i(radius, radius) if p.grid == MapProfile.Grid.HEX else Vector2i(w / 2, h / 2)
		for dy in range(-bounds.y, bounds.y + 1):
			for dx in range(-bounds.x, bounds.x + 1):
				var cell := center + Vector2i(dx, dy)
				if p.grid == MapProfile.Grid.HEX and MapGrid.distance(cell, center, p.grid) > radius:
					continue
				if not _interior(cell, data) or reserved[data.index_of(cell)] != 0:
					valid = false
					break
				cells.append(cell)
			if not valid:
				break
		if not valid:
			continue
		centers.append(center)
		for cell in cells:
			_floor(data, cell)
			reserved[data.index_of(cell)] = 1
			for direction: Vector2i in MapGrid.directions(p.grid):
				var next := cell + direction
				if data.contains(next):
					reserved[data.index_of(next)] = 1
		job.report(0.35 * centers.size() / p.room_count, "放置地牢房间")
	if centers.size() < p.room_count:
		job.error = "只能放置 %d / %d 个房间。请增大地图、减少房间数量或缩小房间。" % [centers.size(), p.room_count]
		return
	var connected: Array[int] = [0]
	var remaining: Array[int] = []
	for i in range(1, centers.size()):
		remaining.append(i)
	var edges: Dictionary = {}
	while not remaining.is_empty():
		if job.is_cancelled():
			return
		var best_a := 0
		var best_b := remaining[0]
		var best_distance := 2147483647
		for a in connected:
			for b in remaining:
				var distance := MapGrid.distance(centers[a], centers[b], p.grid)
				if distance < best_distance:
					best_distance = distance
					best_a = a
					best_b = b
		_carve_path(data, centers[best_a], centers[best_b], p.corridor_width, job)
		edges[Vector2i(mini(best_a, best_b), maxi(best_a, best_b))] = true
		connected.append(best_b)
		remaining.erase(best_b)
		job.report(0.35 + 0.35 * connected.size() / centers.size(), "连接房间与走廊")
	for a in centers.size():
		var b := (a + 1) % centers.size()
		if not edges.has(Vector2i(mini(a, b), maxi(a, b))) and rng.randf() < p.extra_connection_chance:
			_carve_path(data, centers[a], centers[b], p.corridor_width, job)
	data.metadata["room_centers"] = centers
	data.metadata["room_count"] = centers.size()

static func _cave(data: MapData, job: MapGenerationJob) -> void:
	var p := data.profile
	for y in p.height:
		if job.is_cancelled():
			return
		for x in p.width:
			var cell := Vector2i(x, y)
			var wall := not _interior(cell, data) or random_at(p.seed_value, cell, 11) < p.cave_fill
			data.terrain[data.index_of(cell)] = MapData.Terrain.WALL if wall else MapData.Terrain.FLOOR
	var directions: Array = MapGrid.directions(p.grid).duplicate()
	if p.grid == MapProfile.Grid.SQUARE:
		directions.append_array([Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)])
	for iteration in p.cave_iterations:
		var next := data.terrain.duplicate()
		for y in p.height:
			if job.is_cancelled():
				return
			for x in p.width:
				var cell := Vector2i(x, y)
				var walls := 0
				for direction: Vector2i in directions:
					var neighbor := cell + direction
					if not data.contains(neighbor) or data.terrain[data.index_of(neighbor)] == MapData.Terrain.WALL:
						walls += 1
				var i := data.index_of(cell)
				if not _interior(cell, data) or walls > directions.size() / 2:
					next[i] = MapData.Terrain.WALL
				elif walls < directions.size() / 2:
					next[i] = MapData.Terrain.FLOOR
		data.terrain = next
		job.report(0.1 + 0.45 * (iteration + 1) / maxi(1, p.cave_iterations), "细胞自动机平滑洞穴")
	var regions := floor_regions(data, job)
	var representatives: Array[Vector2i] = []
	for region: PackedInt32Array in regions:
		if region.size() < p.min_region_area:
			for i in region:
				data.terrain[i] = MapData.Terrain.WALL
		else:
			representatives.append(data.cell_at(region[region.size() / 2]))
	if representatives.is_empty():
		job.error = "洞穴没有足够大的开放区域。请降低填充率或最小区域面积。"
		return
	# Scan-order connection avoids quadratic region comparisons on large noisy maps.
	for i in range(1, representatives.size()):
		if job.is_cancelled():
			return
		_carve_path(data, representatives[i - 1], representatives[i], p.corridor_width, job)
		job.report(0.55 + 0.3 * i / representatives.size(), "连接洞穴区域")
	for i in data.terrain.size():
		data.elevation[i] = mini(p.max_height, 2) if data.terrain[i] == MapData.Terrain.WALL else 0
	data.metadata["original_regions"] = representatives.size()

static func floor_regions(data: MapData, job: MapGenerationJob = null) -> Array:
	var visited := PackedByteArray()
	visited.resize(data.terrain.size())
	var regions: Array = []
	var dirs := MapGrid.directions(data.profile.grid)
	for start in data.terrain.size():
		if start % 2048 == 0 and job != null and job.is_cancelled():
			return []
		if visited[start] or data.terrain[start] != MapData.Terrain.FLOOR:
			continue
		var queue := PackedInt32Array([start])
		visited[start] = 1
		var cursor := 0
		while cursor < queue.size():
			if cursor % 2048 == 0 and job != null and job.is_cancelled():
				return []
			var cell := data.cell_at(queue[cursor])
			cursor += 1
			for direction: Vector2i in dirs:
				var next := cell + direction
				if not data.contains(next):
					continue
				var index := data.index_of(next)
				if visited[index] == 0 and data.terrain[index] == MapData.Terrain.FLOOR:
					visited[index] = 1
					queue.append(index)
		regions.append(queue)
	return regions

static func _interior(cell: Vector2i, data: MapData) -> bool:
	return cell.x > 0 and cell.y > 0 and cell.x < data.profile.width - 1 and cell.y < data.profile.height - 1

static func _floor(data: MapData, cell: Vector2i) -> void:
	if _interior(cell, data):
		var index := data.index_of(cell)
		data.terrain[index] = MapData.Terrain.FLOOR
		data.elevation[index] = 0

static func _carve_path(data: MapData, start: Vector2i, goal: Vector2i, width: int, job: MapGenerationJob) -> void:
	var path := _astar(data, start, goal, job)
	for cell: Vector2i in path:
		_floor(data, cell)
		if width > 1:
			var radius := width / 2
			for y in range(-radius, width - radius):
				for x in range(-radius, width - radius):
					if data.profile.grid != MapProfile.Grid.HEX or MapGrid.distance(Vector2i.ZERO, Vector2i(x, y), data.profile.grid) <= radius:
						_floor(data, cell + Vector2i(x, y))

static func _astar(data: MapData, start: Vector2i, goal: Vector2i, job: MapGenerationJob) -> Array[Vector2i]:
	var frontier: Array[Vector2i] = []
	var start_index := data.index_of(start)
	var goal_index := data.index_of(goal)
	_heap_push(frontier, Vector2i(0, start_index))
	var came_from: Dictionary = {start_index: -1}
	var cost: Dictionary = {start_index: 0}
	var closed: Dictionary = {}
	var steps := 0
	while not frontier.is_empty():
		if steps % 256 == 0 and job.is_cancelled():
			return []
		steps += 1
		var current := _heap_pop(frontier).y
		if closed.has(current):
			continue
		closed[current] = true
		if current == goal_index:
			var result: Array[Vector2i] = []
			while current != -1:
				result.append(data.cell_at(current))
				current = came_from[current]
			result.reverse()
			return result
		var cell := data.cell_at(current)
		for direction: Vector2i in MapGrid.directions(data.profile.grid):
			var next := cell + direction
			if not _interior(next, data):
				continue
			var index := data.index_of(next)
			var new_cost: int = cost[current] + (8 if data.terrain[index] == MapData.Terrain.FLOOR else 10)
			if not cost.has(index) or new_cost < cost[index]:
				cost[index] = new_cost
				came_from[index] = current
				_heap_push(frontier, Vector2i(new_cost + 8 * MapGrid.distance(next, goal, data.profile.grid), index))
	job.error = "无法在地图边界内连接区域。"
	return []

static func _heap_push(heap: Array[Vector2i], value: Vector2i) -> void:
	heap.append(value)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if heap[parent].x < value.x or (heap[parent].x == value.x and heap[parent].y <= value.y):
			break
		heap[i] = heap[parent]
		i = parent
	heap[i] = value

static func _heap_pop(heap: Array[Vector2i]) -> Vector2i:
	var result := heap[0]
	var last: Vector2i = heap.pop_back()
	if heap.is_empty():
		return result
	var i := 0
	while i * 2 + 1 < heap.size():
		var child := i * 2 + 1
		if child + 1 < heap.size() and (heap[child + 1].x < heap[child].x or (heap[child + 1].x == heap[child].x and heap[child + 1].y < heap[child].y)):
			child += 1
		if last.x < heap[child].x or (last.x == heap[child].x and last.y <= heap[child].y):
			break
		heap[i] = heap[child]
		i = child
	heap[i] = last
	return result
