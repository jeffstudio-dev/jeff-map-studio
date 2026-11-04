@tool
class_name MapAtlasBuilder
extends RefCounted

const SIDE_PHASES := 5
const PALETTE := [Color("42b9b3"), Color("f1ce94"), Color("88ac6a"), Color("a58a68"), Color("7f8d92"), Color("d4e0de"), Color("606f79"), Color("929786")]

static func configure_tileset(tile_set: TileSet, p: MapProfile) -> void:
	tile_set.tile_size = MapGrid.tile_dimensions(p)
	if p.grid == MapProfile.Grid.HEX:
		tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
		tile_set.tile_layout = TileSet.TILE_LAYOUT_STACKED
		tile_set.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_HORIZONTAL if p.hex_orientation == MapProfile.HexOrientation.POINTY else TileSet.TILE_OFFSET_AXIS_VERTICAL
	elif p.projection == MapProfile.ProjectionMode.ISOMETRIC:
		tile_set.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
		tile_set.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	else:
		tile_set.tile_shape = TileSet.TILE_SHAPE_SQUARE

static func cache_key(p: MapProfile, library: TileLibrary) -> String:
	var key := "coastal4:%d:%d:%d:%d:%d:%d:%d" % [p.grid, p.projection, p.hex_orientation, p.style, p.tile_size, p.height_step, p.base_thickness]
	if p.style == MapProfile.Style.PIXEL:
		key += ":grass_spec=" + MapPixelArt.GRASS_SPEC.fingerprint()
	if library != null:
		for recipe in library.recipes:
			if recipe == null:
				key += ":none"
			else:
				key += ":%d,%d,%s,%s,%s,%s,%d" % [recipe.material, recipe.seed_value, recipe.base_color, recipe.detail_color, recipe.grain, recipe.scale, recipe.pixel_size]
				key += ":%d,%s,%s,%s" % [recipe.side_pattern, recipe.side_color, recipe.side_detail_color, recipe.side_grain]
				key += ":art=%s" % recipe.illustrated
	return key

## Top atlas layout: column = variant × 8 + terrain, row = neighbour mask. Variants are
## pixel "moods"; fully surrounded cells (the vast majority) also get extra interior
## sub-variants in the rows after the masks, so a meadow never repeats one tile.
static func top_coords(terrain_id: int, variant: int, sub: int, mask: int, masks: int) -> Vector2i:
	return Vector2i(variant * 8 + terrain_id, mask if sub == 0 else masks + sub - 1)

## Worker-safe image baking. Texture2D/TileSet resources are created later on main.
static func prepare_images(p: MapProfile, library: TileLibrary, job: MapGenerationJob) -> Dictionary:
	var dimensions := MapGrid.tile_dimensions(p)
	var w := dimensions.x
	var h := dimensions.y
	var masks := 1 << MapGrid.directions(p.grid).size()
	# Pixel tops get four moods, each with four interior sub-variants; painted keeps two.
	var variants := MapPixelArt.MOODS if p.style == MapProfile.Style.PIXEL else 2
	var interior_variants := 4 if p.style == MapProfile.Style.PIXEL else 1
	var variant_specs: Array = []
	var top_atlas := Image.create(w * 8 * variants, h * (masks + interior_variants - 1), false, Image.FORMAT_RGBA8)
	var polygon := MapGrid.polygon(p)
	# Adjacent translucent edges otherwise multiply alpha and reveal the backdrop
	# at fractional zoom. One texel of overlap also closes nearest-filter cracks.
	var coverage_polygon: PackedVector2Array = Geometry2D.offset_polygon(polygon, 1.0, Geometry2D.JOIN_MITER)[0]
	var edge_dirs := MapGrid.edge_directions(p)
	var edge_pixels: Array = []
	for _edge in polygon.size():
		edge_pixels.append([])
	for y in h:
		for x in w:
			var point := Vector2(x + 0.5 - w * 0.5, y + 0.5 - h * 0.5)
			if not Geometry2D.is_point_in_polygon(point, coverage_polygon):
				continue
			for edge in polygon.size():
				var closest := Geometry2D.get_closest_point_to_segment(point, polygon[edge], polygon[(edge + 1) % polygon.size()])
				if closest.distance_to(point) < maxf(1.0, p.tile_size / 100.0):
					edge_pixels[edge].append(Vector2i(x, y))
	for terrain_id in 8:
		if job.is_cancelled():
			return {}
		job.report(float(terrain_id) / 10.0, "烘焙地形纹理与过渡图集")
		variant_specs.append(MapPixelArt.spec_for(_terrain_recipe(terrain_id, p, library).material) if p.style == MapProfile.Style.PIXEL else null)
		for index in variants * interior_variants:
			var variant := index % variants
			var sub := index / variants
			var recipe := _terrain_recipe(terrain_id, p, library)
			var pixel_layers := {}
			var base: Image
			if p.style == MapProfile.Style.PIXEL:
				# Pixel variants keep one seed so their outlines match; only interiors vary.
				pixel_layers = MapPixelArt.top_layers(p, recipe, index)
				base = pixel_layers.base
			else:
				recipe.seed_value += variant * 1009
				base = MapBlockSurface.top_image(p, recipe)
			if sub > 0:
				# Interior sub-variants are only used where every neighbour matches: no rims.
				top_atlas.blit_rect(base, Rect2i(0, 0, w, h), Vector2i(top_coords(terrain_id, variant, sub, masks - 1, masks)) * Vector2i(w, h))
				continue
			for mask in masks:
				if mask % 8 == 0 and job.is_cancelled():
					return {}
				var origin := top_coords(terrain_id, variant, 0, mask, masks) * Vector2i(w, h)
				top_atlas.blit_rect(base, Rect2i(0, 0, w, h), origin)
				for edge in polygon.size():
					if mask & (1 << edge_dirs[edge]):
						continue
					if not pixel_layers.is_empty():
						var rim: Image = pixel_layers.rims[edge]
						top_atlas.blend_rect(rim, Rect2i(0, 0, w, h), origin)
						continue
					for pixel: Vector2i in edge_pixels[edge]:
						var c := base.get_pixelv(pixel)
						# A narrow material edge; no outline inside continuous terrain.
						c = MapBlockSurface.rim_color(c, recipe, Vector2(pixel) - Vector2(w, h) * 0.5, polygon[edge].y + polygon[(edge + 1) % polygon.size()].y < 0)
						top_atlas.set_pixelv(origin + pixel, c)
	var front_dirs: Array[int] = []
	var front_edges: Array[int] = []
	for edge in polygon.size():
		if polygon[(edge + 1) % polygon.size()].x < polygon[edge].x:
			front_dirs.append(edge_dirs[edge])
			front_edges.append(edge)
	var side_count := 1 << front_dirs.size()
	var side_rows: Dictionary = {}
	var side_atlas := Image.create(w * 8, (h + p.height_step) * side_count * SIDE_PHASES, false, Image.FORMAT_RGBA8)
	var base_atlas := Image.create(w * 8, (h + p.base_thickness) * side_count * SIDE_PHASES, false, Image.FORMAT_RGBA8)
	for m in side_count * SIDE_PHASES:
		var face_mask := m % side_count
		var logical_mask := 0
		for bit in front_dirs.size():
			if face_mask & (1 << bit):
				logical_mask |= 1 << front_dirs[bit]
		side_rows[logical_mask] = face_mask
		for terrain_id in 8:
			var recipe := _terrain_recipe(terrain_id, p, library)
			for bit in front_edges.size():
				if not (face_mask & (1 << bit)):
					continue
				var edge := front_edges[bit]
				var a := polygon[edge]
				var b := polygon[(edge + 1) % polygon.size()]
				var offset := Vector2(terrain_id * w + w * 0.5, m * (h + p.height_step) + h * 0.5)
				MapBlockSurface.paint_face(side_atlas, a, b, p.height_step, offset, recipe, p.tile_size, m < side_count, (m / side_count) * p.height_step, Vector2(terrain_id * w, m * (h + p.height_step)))
				var base_offset := Vector2(terrain_id * w + w * 0.5, m * (h + p.base_thickness) + h * 0.5)
				MapBlockSurface.paint_face(base_atlas, a, b, p.base_thickness, base_offset, recipe, p.tile_size, m < side_count, (m / side_count) * p.height_step, Vector2(terrain_id * w, m * (h + p.base_thickness)))
	var decoration_atlas := MapLandmarkArt.atlas(w, h + p.tile_size, p.style, p.tile_size)
	# Keep edge RGB in transparent pixels so linear filtering does not mix black
	# into a partially transparent border before alpha compositing.
	top_atlas.fix_alpha_edges()
	side_atlas.fix_alpha_edges()
	base_atlas.fix_alpha_edges()
	decoration_atlas.fix_alpha_edges()
	job.report(1.0, "纹理图集完成")
	return {"top": top_atlas, "side": side_atlas, "base": base_atlas, "decoration": decoration_atlas, "masks": masks, "variants": variants, "interior_variants": interior_variants, "variant_specs": variant_specs, "side_rows": side_rows, "front_dirs": front_dirs, "side_count": side_count}

static func _terrain_recipe(terrain_id: int, p: MapProfile, library: TileLibrary) -> TextureRecipe:
	var mapping := [3, 1, 0, 1, 2, 2, 4, 4]
	var recipe: TextureRecipe
	if library != null and library.recipes.size() > terrain_id and library.recipes[terrain_id] != null:
		recipe = library.recipes[terrain_id].duplicate(true) as TextureRecipe
	else:
		recipe = TextureRecipe.preset(mapping[terrain_id], p.style)
		recipe.base_color = PALETTE[terrain_id]
		recipe.detail_color = PALETTE[terrain_id].lightened(0.3)
		recipe.seed_value = 42 + terrain_id * 137
		recipe.grain = 0.5
	recipe.style = p.style
	recipe.resolution = p.tile_size
	return recipe

static func create_tileset(images: Dictionary, p: MapProfile) -> TileSet:
	var result := TileSet.new()
	configure_tileset(result, p)
	var dimensions := MapGrid.tile_dimensions(p)
	_add_source(result, images.top, dimensions, 8 * images.variants, images.masks + images.get("interior_variants", 1) - 1, 0, Vector2i.ZERO)
	_add_source(result, images.side, Vector2i(dimensions.x, dimensions.y + p.height_step), 8, images.side_count * SIDE_PHASES, 1, Vector2i(0, -p.height_step / 2))
	_add_source(result, images.decoration, Vector2i(dimensions.x, dimensions.y + p.tile_size), 6, 1, 2, Vector2i(0, roundi((dimensions.y + p.tile_size) * 0.72) - (dimensions.y + p.tile_size) / 2))
	_add_source(result, images.base, Vector2i(dimensions.x, dimensions.y + p.base_thickness), 8, images.side_count * SIDE_PHASES, 3, Vector2i(0, -p.base_thickness / 2))
	return result

static func _add_source(tile_set: TileSet, image: Image, size: Vector2i, columns: int, rows: int, id: int, origin: Vector2i) -> void:
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = size
	for y in rows:
		for x in columns:
			var coords := Vector2i(x, y)
			source.create_tile(coords)
			source.get_tile_data(coords, 0).texture_origin = origin
	tile_set.add_source(source, id)

