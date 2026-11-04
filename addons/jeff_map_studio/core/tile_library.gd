@tool
class_name TileLibrary
extends Resource
## Null tile_set uses the built-in procedural atlas. Imported art remains explicit.
@export var display_name: String = "Jeff · 内置地形"
@export var tile_set: TileSet
@export var rules: Array[MapTileRule] = []
@export var recipes: Array[TextureRecipe] = []
@export var layout_grid: int = 0
@export var layout_projection: int = 1
@export var layout_orientation: int = 0
@export var attribution: String = "Original procedural assets by Jeff Map Studio."
var _rule_index: Dictionary = {}
var _selection_cache: Dictionary = {}
var _compiled_count: int = -1

func compile_rules() -> void:
	_rule_index.clear()
	_selection_cache.clear()
	_compiled_count = rules.size()
	for rule in rules:
		if rule == null:
			continue
		var decoration := rule.decoration_id if rule.role == MapTileRule.Role.DECORATION else -1
		var key := Vector4i(rule.terrain, rule.role * 8 + decoration + 1, rule.neighbor_mask, rule.corner_mask)
		if not _rule_index.has(key):
			_rule_index[key] = []
		_rule_index[key].append(rule)

func validate_for(data: MapData) -> String:
	for recipe in recipes:
		if recipe != null and not recipe.validate().is_empty():
			return recipe.validate()
	if tile_set == null:
		return ""
	var p := data.profile
	if layout_grid != p.grid or layout_projection != p.projection or (p.grid == MapProfile.Grid.HEX and layout_orientation != p.hex_orientation):
		return "素材库的网格／投影与地图不一致，请切换对应素材库或重新导入图集。"
	if tile_set.tile_size != MapGrid.tile_dimensions(p):
		return "TileSet 格子尺寸为 %s，当前地图需要 %s。请调整地图地块尺寸。" % [tile_set.tile_size, MapGrid.tile_dimensions(p)]
	if rules.is_empty():
		return "素材库尚未绑定规则。请在纹理与地块页绑定地形顶面。"
	var mapped: Dictionary = {}
	for rule in rules:
		if rule == null or not tile_set.has_source(rule.source_id):
			return "素材规则引用了不存在的图集来源。"
		var source := tile_set.get_source(rule.source_id) as TileSetAtlasSource
		if source == null or not source.has_tile(rule.atlas_coords) or not source.has_alternative_tile(rule.atlas_coords, rule.alternative_id):
			return "无效瓦片：来源 %d，坐标 %s，替代编号 %d。" % [rule.source_id, rule.atlas_coords, rule.alternative_id]
		if not is_finite(rule.weight) or rule.weight <= 0.0:
			return "瓦片权重必须大于 0。"
		if rule.terrain < 0 or rule.terrain > 7 or rule.role < 0 or rule.role > 2:
			return "瓦片规则含未知地形或用途。"
		if rule.neighbor_mask < -1 or rule.neighbor_mask >= (1 << MapGrid.directions(p.grid).size()) or rule.corner_mask < -1 or rule.corner_mask > 15:
			return "瓦片邻接掩码超出当前网格范围。"
		if p.grid == MapProfile.Grid.HEX and rule.corner_mask != -1:
			return "六角规则只使用边掩码，角掩码请设置为 -1。"
		if rule.role == MapTileRule.Role.TOP:
			mapped[rule.terrain] = true
	for i in data.terrain.size():
		if data.terrain[i] >= 0 and not mapped.has(data.terrain[i]):
			return "缺少 %s 顶面绑定，首个位置：%s。" % [MapData.TERRAIN_NAMES[data.terrain[i]], data.cell_at(i)]
	return ""

func pick(terrain_id: int, role: int, mask: int, corners: int, seed_value: int, cell: Vector2i, decoration_id: int = -1) -> MapTileRule:
	if _compiled_count != rules.size():
		compile_rules()
	var cache_key := Vector4i(terrain_id, role * 8 + decoration_id + 1, mask, corners)
	if not _selection_cache.has(cache_key):
		var candidates: Array[MapTileRule] = []
		var best := -1
		var edge_options := [mask, -1] if mask != -1 else [-1]
		var corner_options := [corners, -1] if corners != -1 else [-1]
		var decoration_options := [decoration_id, -1] if role == MapTileRule.Role.DECORATION and decoration_id != -1 else [-1]
		for edge: int in edge_options:
			for corner: int in corner_options:
				for decoration: int in decoration_options:
					var key := Vector4i(terrain_id, role * 8 + decoration + 1, edge, corner)
					if not _rule_index.has(key):
						continue
					var specificity := int(edge != -1) + int(corner != -1) + int(decoration != -1)
					if specificity > best:
						candidates.clear()
						best = specificity
					if specificity == best:
						candidates.append_array(_rule_index[key])
		candidates.sort_custom(func(a: MapTileRule, b: MapTileRule) -> bool: return a.sort_key() < b.sort_key())
		var total := 0.0
		for rule in candidates:
			total += rule.weight
		_selection_cache[cache_key] = {"candidates": candidates, "weight": total}
	var selection: Dictionary = _selection_cache[cache_key]
	if selection.candidates.is_empty():
		return null
	var value := MapGenerator.random_at(seed_value, cell, 71 + role) * float(selection.weight)
	for rule: MapTileRule in selection.candidates:
		value -= rule.weight
		if value < 0.0:
			return rule
	return selection.candidates[-1]

static func import_atlas(texture: Texture2D, region: Vector2i, margin: Vector2i, separation: Vector2i, p: MapProfile) -> TileLibrary:
	if texture == null or region.x <= 0 or region.y <= 0:
		return null
	var library := TileLibrary.new()
	library.display_name = texture.resource_path.get_file()
	library.layout_grid = p.grid
	library.layout_projection = p.projection
	library.layout_orientation = p.hex_orientation
	library.tile_set = TileSet.new()
	MapAtlasBuilder.configure_tileset(library.tile_set, p)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = region
	source.margins = margin
	source.separation = separation
	var dimensions := source.get_atlas_grid_size()
	for y in dimensions.y:
		for x in dimensions.x:
			source.create_tile(Vector2i(x, y))
	library.tile_set.add_source(source, 0)
	return library

func read_native_terrains(p: MapProfile) -> int:
	if tile_set == null:
		return 0
	var bits: Array
	var corner_bits: Array = []
	if p.grid == MapProfile.Grid.SQUARE:
		if p.projection == MapProfile.ProjectionMode.TOP_DOWN:
			bits = [TileSet.CELL_NEIGHBOR_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_SIDE]
			corner_bits = [TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER]
		else:
			bits = [TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE]
			corner_bits = [TileSet.CELL_NEIGHBOR_BOTTOM_CORNER, TileSet.CELL_NEIGHBOR_LEFT_CORNER, TileSet.CELL_NEIGHBOR_TOP_CORNER, TileSet.CELL_NEIGHBOR_RIGHT_CORNER]
	elif p.hex_orientation == MapProfile.HexOrientation.POINTY:
		bits = [TileSet.CELL_NEIGHBOR_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE, TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE]
	else:
		bits = [TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE]
	var added := 0
	for s in tile_set.get_source_count():
		var source_id := tile_set.get_source_id(s)
		var source := tile_set.get_source(source_id) as TileSetAtlasSource
		if source == null:
			continue
		for t in source.get_tiles_count():
			var coords := source.get_tile_id(t)
			for a in source.get_alternative_tiles_count(coords):
				var alternative := source.get_alternative_tile_id(coords, a)
				var tile := source.get_tile_data(coords, alternative)
				if tile.terrain < 0 or tile.terrain > 7:
					continue
				var rule := MapTileRule.new()
				rule.terrain = tile.terrain
				rule.source_id = source_id
				rule.atlas_coords = coords
				rule.alternative_id = alternative
				rule.weight = maxf(0.01, tile.probability)
				var mask := 0
				var has_sides := false
				for i in bits.size():
					if tile.is_valid_terrain_peering_bit(bits[i]):
						has_sides = true
						if tile.get_terrain_peering_bit(bits[i]) == tile.terrain:
							mask |= 1 << i
				rule.neighbor_mask = mask if has_sides else -1
				var corners := 0
				var has_corners := false
				for i in corner_bits.size():
					if tile.is_valid_terrain_peering_bit(corner_bits[i]):
						has_corners = true
						if tile.get_terrain_peering_bit(corner_bits[i]) == tile.terrain:
							corners |= 1 << i
				rule.corner_mask = corners if has_corners else -1
				rules.append(rule)
				added += 1
	return added
