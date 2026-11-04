@tool
class_name MapRenderer
extends Node2D

var data: MapData
var library: TileLibrary
var tile_set: TileSet
var masks: int
var variants: int
var interior_variants: int = 1
## Per terrain id: TerrainArtSpec that chooses variants by region, or null.
var variant_specs: Array = []
var side_count: int
var side_rows: Dictionary
var front_dirs: Array
var layers: Dictionary = {}
var custom_sources: Dictionary = {}
var builtin_sources: Dictionary = {0: 0, 1: 1, 2: 2, 3: 3}
var error: String = ""

func setup(map_data: MapData, atlas: Dictionary, custom_library: TileLibrary) -> void:
	data = map_data
	library = custom_library
	if library != null:
		library.compile_rules()
	tile_set = atlas.tileset
	masks = atlas.masks
	variants = atlas.variants
	interior_variants = atlas.get("interior_variants", 1)
	variant_specs = atlas.get("variant_specs", [])
	side_rows = atlas.side_rows
	side_count = atlas.side_count
	front_dirs = atlas.front_dirs
	y_sort_enabled = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if data.profile.style == MapProfile.Style.PIXEL else CanvasItem.TEXTURE_FILTER_LINEAR
	if library != null and library.tile_set != null:
		var builtin := tile_set
		tile_set = library.tile_set.duplicate(true) as TileSet
		MapAtlasBuilder.configure_tileset(tile_set, data.profile)
		for i in library.tile_set.get_source_count():
			var id := library.tile_set.get_source_id(i)
			custom_sources[id] = id
		for id in 4:
			var new_id := tile_set.get_next_source_id()
			tile_set.add_source(builtin.get_source(id).duplicate(true), new_id)
			builtin_sources[id] = new_id
	var levels := 16 if data.profile.projection == MapProfile.ProjectionMode.ISOMETRIC else 0
	if data.profile.projection == MapProfile.ProjectionMode.ISOMETRIC and data.profile.base_thickness > 0:
		_make_layer("base_side", 0)
	for level in range(levels + 1):
		if level > 0:
			_make_layer("side_%d" % level, level)
		_make_layer("top_%d" % level, level)
		_make_layer("decoration_%d" % level, level)

func _make_layer(key: String, height: int) -> void:
	var layer := TileMapLayer.new()
	layer.name = key
	layer.tile_set = tile_set
	layer.y_sort_enabled = true
	layer.y_sort_origin = height * data.profile.height_step
	layer.position = -layer.map_to_local(Vector2i.ZERO) - Vector2(0, height * data.profile.height_step)
	layer.collision_enabled = false
	layer.navigation_enabled = false
	add_child(layer)
	layers[key] = layer

func update_cell(cell: Vector2i, clear_previous: bool = false) -> void:
	if not data.contains(cell):
		return
	var p := data.profile
	var coords := MapGrid.to_offset(cell, p)
	if clear_previous:
		for layer: TileMapLayer in layers.values():
			layer.erase_cell(coords)
	var index := data.index_of(cell)
	var terrain_id := data.terrain[index]
	if terrain_id < 0:
		return
	var level := int(data.elevation[index]) if p.projection == MapProfile.ProjectionMode.ISOMETRIC else 0
	if layers.has("base_side"):
		var exposed_base := 0
		for direction_index: int in front_dirs:
			var next: Vector2i = cell + MapGrid.directions(p.grid)[direction_index]
			if not data.contains(next) or data.terrain[data.index_of(next)] < 0:
				exposed_base |= 1 << direction_index
		if exposed_base != 0:
			layers.base_side.set_cell(coords, builtin_sources[3], Vector2i(terrain_id, side_rows[exposed_base] + (level % MapAtlasBuilder.SIDE_PHASES) * side_count))
	var mask := neighbor_mask(cell)
	var corners := corner_mask(cell)
	var top: TileMapLayer = layers["top_%d" % level]
	if library != null and library.tile_set != null:
		var rule := library.pick(terrain_id, MapTileRule.Role.TOP, mask, corners, p.seed_value, cell)
		if rule == null:
			error = "未匹配到 %s 顶面：格子 %s，边掩码 %d，角掩码 %d。请添加对应规则或通用规则（-1）。" % [MapData.TERRAIN_NAMES[terrain_id], cell, mask, corners]
			return
		top.set_cell(coords, custom_sources[rule.source_id], rule.atlas_coords, rule.alternative_id)
	else:
		var spec: TerrainArtSpec = variant_specs[terrain_id] if terrain_id < variant_specs.size() else null
		var variant := pick_variant(spec, cell, p.seed_value, variants)
		var sub := 0
		if mask == masks - 1 and interior_variants > 1:
			sub = mini(interior_variants - 1, int(MapGenerator.random_at(p.seed_value, cell, 73) * interior_variants))
		top.set_cell(coords, builtin_sources[0], MapAtlasBuilder.top_coords(terrain_id, variant, sub, mask, masks))
	for h in range(1, level + 1):
		var exposed := 0
		for direction_index: int in front_dirs:
			var next: Vector2i = cell + MapGrid.directions(p.grid)[direction_index]
			if not data.contains(next) or data.terrain[data.index_of(next)] < 0 or data.elevation[data.index_of(next)] < h:
				exposed |= 1 << direction_index
		if exposed == 0:
			continue
		var side: TileMapLayer = layers["side_%d" % h]
		var rule: MapTileRule = library.pick(terrain_id, MapTileRule.Role.SIDE, exposed, -1, p.seed_value, cell) if library != null and library.tile_set != null else null
		if rule != null:
			side.set_cell(coords, custom_sources[rule.source_id], rule.atlas_coords, rule.alternative_id)
		else:
			side.set_cell(coords, builtin_sources[1], Vector2i(terrain_id, side_rows[exposed] + ((level - h) % MapAtlasBuilder.SIDE_PHASES) * side_count))
	if data.decoration[index] > 0:
		var decoration_layer: TileMapLayer = layers["decoration_%d" % level]
		var rule: MapTileRule = library.pick(terrain_id, MapTileRule.Role.DECORATION, mask, corners, p.seed_value, cell, data.decoration[index]) if library != null and library.tile_set != null else null
		if rule != null:
			decoration_layer.set_cell(coords, custom_sources[rule.source_id], rule.atlas_coords, rule.alternative_id)
		else:
			decoration_layer.set_cell(coords, builtin_sources[2], Vector2i(data.decoration[index] - 1, 0))

## Variant for a map cell. Without regions every cell draws independently (the
## original behaviour); with regions, slow noise over the map groups similar moods.
static func pick_variant(spec: TerrainArtSpec, cell: Vector2i, seed_value: int, count: int) -> int:
	var jitter := MapGenerator.random_at(seed_value, cell, 71)
	if spec == null or spec.variant_region_cells <= 0.0:
		return mini(count - 1, int(jitter * count))
	var p := Vector2(cell) / spec.variant_region_cells
	var base := Vector2i(floori(p.x), floori(p.y))
	var f := p - Vector2(base)
	f = f * f * (Vector2(3, 3) - f * 2.0)
	var top := lerpf(MapGenerator.random_at(seed_value, base, 97), MapGenerator.random_at(seed_value, base + Vector2i(1, 0), 97), f.x)
	var bottom := lerpf(MapGenerator.random_at(seed_value, base + Vector2i(0, 1), 97), MapGenerator.random_at(seed_value, base + Vector2i(1, 1), 97), f.x)
	var region := clampf((lerpf(top, bottom, f.y) - 0.5) * spec.variant_region_contrast + 0.5, 0.0, 0.999)
	var slot := clampi(floori(region * count + (jitter - 0.5) * spec.variant_mix), 0, count - 1)
	return spec.variant_order[slot] if spec.variant_order.size() == count else slot

func neighbor_mask(cell: Vector2i) -> int:
	var i := data.index_of(cell)
	var result := 0
	var dirs := MapGrid.directions(data.profile.grid)
	for d in dirs.size():
		var next: Vector2i = cell + dirs[d]
		if data.contains(next):
			var n := data.index_of(next)
			if data.terrain[n] == data.terrain[i] and (data.profile.projection == MapProfile.ProjectionMode.TOP_DOWN or data.elevation[n] == data.elevation[i]):
				result |= 1 << d
	return result

func corner_mask(cell: Vector2i) -> int:
	if data.profile.grid == MapProfile.Grid.HEX:
		return -1
	var offsets := [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(1, -1)]
	var result := 0
	var i := data.index_of(cell)
	for d in 4:
		var next: Vector2i = cell + offsets[d]
		if data.contains(next):
			var n := data.index_of(next)
			if data.terrain[n] == data.terrain[i] and (data.profile.projection == MapProfile.ProjectionMode.TOP_DOWN or data.elevation[n] == data.elevation[i]):
				result |= 1 << d
	return result

func refresh_cells(cells: Array[Vector2i]) -> void:
	var affected: Dictionary = {}
	for cell in cells:
		affected[cell] = true
		for direction: Vector2i in MapGrid.directions(data.profile.grid):
			affected[cell + direction] = true
		if data.profile.grid == MapProfile.Grid.SQUARE:
			for offset: Vector2i in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(1, -1)]:
				affected[cell + offset] = true
	for cell: Vector2i in affected:
		update_cell(cell, true)

func native_copy() -> Node2D:
	var root := Node2D.new()
	root.name = "JeffMapBaked"
	root.y_sort_enabled = true
	root.texture_filter = texture_filter
	root.set_meta("seed", data.profile.seed_value)
	root.set_meta("generator_version", data.generator_version)
	root.set_meta("heights_are_visual", true)
	for layer: TileMapLayer in layers.values():
		if layer.get_used_cells().is_empty():
			continue
		var copy := layer.duplicate() as TileMapLayer
		root.add_child(copy)
		copy.owner = root
	return root
