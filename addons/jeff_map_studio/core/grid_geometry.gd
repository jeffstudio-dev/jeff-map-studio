@tool
class_name MapGrid
extends RefCounted
## Axial hex storage is independent of display orientation and Godot's offset layout.

const SQUARE_DIRS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
const HEX_DIRS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)]

static func directions(grid: int) -> Array:
	return HEX_DIRS if grid == MapProfile.Grid.HEX else SQUARE_DIRS

static func tile_dimensions(p: MapProfile) -> Vector2i:
	var size := p.tile_size
	if p.grid == MapProfile.Grid.SQUARE:
		return Vector2i(size, size / 2 if p.projection == MapProfile.ProjectionMode.ISOMETRIC else size)
	var short_size := int(round(size * sqrt(3.0) / 2.0 / 2.0)) * 2
	var result := Vector2i(short_size, size) if p.hex_orientation == MapProfile.HexOrientation.POINTY else Vector2i(size, short_size)
	if p.projection == MapProfile.ProjectionMode.ISOMETRIC:
		result.y = maxi(2, result.y / 2)
	return result

static func to_offset(cell: Vector2i, p: MapProfile) -> Vector2i:
	if p.grid == MapProfile.Grid.SQUARE:
		return cell
	if p.hex_orientation == MapProfile.HexOrientation.POINTY:
		return Vector2i(cell.x + floori(cell.y / 2.0), cell.y)
	return Vector2i(cell.x, cell.y + floori(cell.x / 2.0))

static func from_offset(cell: Vector2i, p: MapProfile) -> Vector2i:
	if p.grid == MapProfile.Grid.SQUARE:
		return cell
	if p.hex_orientation == MapProfile.HexOrientation.POINTY:
		return Vector2i(cell.x - floori(cell.y / 2.0), cell.y)
	return Vector2i(cell.x, cell.y - floori(cell.x / 2.0))

static func cell_to_local(cell: Vector2i, p: MapProfile, height: int = 0) -> Vector2:
	var size := Vector2(tile_dimensions(p))
	var point: Vector2
	if p.grid == MapProfile.Grid.SQUARE:
		if p.projection == MapProfile.ProjectionMode.ISOMETRIC:
			point = Vector2((cell.x - cell.y) * size.x * 0.5, (cell.x + cell.y) * size.y * 0.5)
		else:
			point = Vector2(cell) * size
	elif p.hex_orientation == MapProfile.HexOrientation.POINTY:
		point = Vector2(size.x * (cell.x + cell.y * 0.5), size.y * 0.75 * cell.y)
	else:
		point = Vector2(size.x * 0.75 * cell.x, size.y * (cell.y + cell.x * 0.5))
	if p.projection == MapProfile.ProjectionMode.ISOMETRIC:
		point.y -= height * p.height_step
	return point

static func local_to_cell(point: Vector2, p: MapProfile) -> Vector2i:
	var size := Vector2(tile_dimensions(p))
	if p.grid == MapProfile.Grid.SQUARE:
		if p.projection == MapProfile.ProjectionMode.ISOMETRIC:
			return Vector2i(roundi(point.x / size.x + point.y / size.y), roundi(point.y / size.y - point.x / size.x))
		return Vector2i(roundi(point.x / size.x), roundi(point.y / size.y))
	var q: float
	var r: float
	if p.hex_orientation == MapProfile.HexOrientation.POINTY:
		r = point.y / (size.y * 0.75)
		q = point.x / size.x - r * 0.5
	else:
		q = point.x / (size.x * 0.75)
		r = point.y / size.y - q * 0.5
	var x := roundi(q)
	var z := roundi(r)
	var y := roundi(-q - r)
	var dx := absf(x - q)
	var dy := absf(y + q + r)
	var dz := absf(z - r)
	if dx > dy and dx > dz:
		x = -y - z
	elif dz > dy:
		z = -x - y
	return Vector2i(x, z)

static func polygon(p: MapProfile) -> PackedVector2Array:
	var s := Vector2(tile_dimensions(p)) * 0.5
	if p.grid == MapProfile.Grid.SQUARE:
		if p.projection == MapProfile.ProjectionMode.ISOMETRIC:
			return PackedVector2Array([Vector2(0, -s.y), Vector2(s.x, 0), Vector2(0, s.y), Vector2(-s.x, 0)])
		return PackedVector2Array([Vector2(-s.x, -s.y), Vector2(s.x, -s.y), Vector2(s.x, s.y), Vector2(-s.x, s.y)])
	if p.hex_orientation == MapProfile.HexOrientation.POINTY:
		return PackedVector2Array([Vector2(0, -s.y), Vector2(s.x, -s.y * 0.5), Vector2(s.x, s.y * 0.5), Vector2(0, s.y), Vector2(-s.x, s.y * 0.5), Vector2(-s.x, -s.y * 0.5)])
	return PackedVector2Array([Vector2(s.x, 0), Vector2(s.x * 0.5, s.y), Vector2(-s.x * 0.5, s.y), Vector2(-s.x, 0), Vector2(-s.x * 0.5, -s.y), Vector2(s.x * 0.5, -s.y)])

static func edge_directions(p: MapProfile) -> PackedInt32Array:
	var poly := polygon(p)
	var dirs := directions(p.grid)
	var result := PackedInt32Array()
	for i in poly.size():
		var middle := (poly[i] + poly[(i + 1) % poly.size()]) * 0.5
		var best := 0
		var best_distance := INF
		for d in dirs.size():
			var distance := middle.distance_squared_to(cell_to_local(dirs[d], p) * 0.5)
			if distance < best_distance:
				best_distance = distance
				best = d
		result.append(best)
	return result

static func sample_position(cell: Vector2i, p: MapProfile) -> Vector2:
	if p.grid == MapProfile.Grid.HEX:
		return Vector2(cell.x + cell.y * 0.5, cell.y * sqrt(3.0) * 0.5)
	return Vector2(cell)

static func distance(a: Vector2i, b: Vector2i, grid: int) -> int:
	var d := a - b
	if grid == MapProfile.Grid.HEX:
		return maxi(absi(d.x), maxi(absi(d.y), absi(d.x + d.y)))
	return absi(d.x) + absi(d.y)

static func pick_cell(point: Vector2, data: MapData) -> Vector2i:
	var p := data.profile
	var candidates: Dictionary = {}
	var limit := 16 if p.projection == MapProfile.ProjectionMode.ISOMETRIC else 0
	# Sample the projected vertical ray at grid-sized intervals. Sampling only
	# integer height planes skips narrow blocks when the layer height is large.
	var below := p.base_thickness if limit > 0 else 0
	var spacing := maxi(1, tile_dimensions(p).y / 2)
	var neighbors := [Vector2i.ZERO]
	if limit > 0:
		neighbors.append_array(directions(p.grid))
	var end := limit * p.height_step + spacing if limit > 0 else 0
	for offset in range(-below, end + 1, spacing):
		var cell := local_to_cell(point + Vector2(0, offset), p)
		for direction: Vector2i in neighbors:
			var candidate := cell + direction
			if data.contains(candidate):
				candidates[candidate] = true
	var ordered: Array = candidates.keys()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var pa := cell_to_local(a, p)
		var pb := cell_to_local(b, p)
		return pa.y > pb.y if not is_equal_approx(pa.y, pb.y) else pa.x > pb.x)
	var poly := polygon(p)
	for cell: Vector2i in ordered:
		var i := data.index_of(cell)
		if data.terrain[i] < 0:
			continue
		var top := cell_to_local(cell, p, data.elevation[i])
		if Geometry2D.is_point_in_polygon(point - top, poly):
			return cell
		if limit > 0:
			for edge in poly.size():
				var a := poly[edge]
				var b := poly[(edge + 1) % poly.size()]
				if b.x < a.x:
					var down := Vector2(0, data.elevation[i] * p.height_step + p.base_thickness)
					if Geometry2D.is_point_in_polygon(point - top, PackedVector2Array([a, b, b + down, a + down])):
						return cell
	# Empty cells remain paintable.
	var empty := local_to_cell(point, p)
	return empty if data.contains(empty) and data.terrain[data.index_of(empty)] < 0 else Vector2i(-1, -1)
