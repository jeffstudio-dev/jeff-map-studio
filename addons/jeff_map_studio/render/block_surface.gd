@tool
class_name MapBlockSurface
extends RefCounted
## Shared rasterization for live atlases and inspectable/exportable single blocks.

static func side_pattern(recipe: TextureRecipe) -> int:
	if recipe.side_pattern != TextureRecipe.SidePattern.AUTO:
		return recipe.side_pattern
	return [TextureRecipe.SidePattern.MOSS, TextureRecipe.SidePattern.SOIL, TextureRecipe.SidePattern.ROCK, TextureRecipe.SidePattern.WATER, TextureRecipe.SidePattern.BRICK][recipe.material]

static func paint_face(image: Image, a: Vector2, b: Vector2, depth: int, offset: Vector2, recipe: TextureRecipe, tile_size: int, cap: bool = false, art_offset: float = -1.0, grid_origin: Vector2 = Vector2.INF) -> void:
	if depth <= 0 or is_zero_approx(a.x - b.x):
		return
	if recipe.style == MapProfile.Style.PIXEL:
		MapPixelArt.paint_face(image, a, b, depth, offset, recipe, tile_size, cap, maxf(art_offset, 0.0), offset if grid_origin == Vector2.INF else grid_origin)
		return
	var points := PackedVector2Array([a, b, b + Vector2(0, depth), a + Vector2(0, depth)])
	var coverage: PackedVector2Array = Geometry2D.offset_polygon(points, 0.55, Geometry2D.JOIN_MITER)[0]
	var bounds := Rect2(a, Vector2.ZERO).expand(b).expand(a + Vector2(0, depth)).expand(b + Vector2(0, depth))
	bounds.position += offset
	var noise := FastNoiseLite.new()
	noise.seed = recipe.seed_value + 3701
	noise.frequency = recipe.scale / maxf(tile_size, 1)
	noise.fractal_octaves = 3
	var pattern := side_pattern(recipe)
	var step := recipe.pixel_size if recipe.style == MapProfile.Style.PIXEL else 1
	var shade := 0.24 if (a.x + b.x) > 0 else 0.055
	var unit := maxf(0.5, tile_size / 128.0)
	# Older recipes have no explicit side palette. Derive it from their top color.
	var side_base := recipe.side_color if recipe.side_color.a > 0.0 else recipe.base_color.darkened(0.18)
	var side_detail := recipe.side_detail_color if recipe.side_detail_color.a > 0.0 else recipe.detail_color.darkened(0.2)
	var art := MapSurfaceArt.side(recipe, tile_size, cap, art_offset >= 0)
	var foliage := _moss_foliage(recipe, tile_size, depth) if art == null and pattern == TextureRecipe.SidePattern.MOSS else null
	for y in range(floori(bounds.position.y), ceili(bounds.end.y)):
		for x in range(floori(bounds.position.x), ceili(bounds.end.x)):
			var point := Vector2(x + 0.5, y + 0.5) - offset
			if not Geometry2D.is_point_in_polygon(point, coverage):
				continue
			var u := clampf((point.x - a.x) / (b.x - a.x), 0.0, 1.0)
			var v := clampf(point.y - lerpf(a.y, b.y, u), 0.0, depth)
			var sx := floorf(u * tile_size / step) * step
			var sy := floorf(v / step) * step
			var n := clampf(noise.get_noise_2d(sx, sy) * 1.4 + 0.5, 0.0, 1.0)
			var grain := recipe.side_grain
			var fleck := MapTextureFactory._hash(floori(sx / unit), floori(sy / unit), recipe.seed_value + 73)
			var c := side_base.lerp(side_detail, (0.18 + n * 0.45) * grain)
			if art != null:
				var texture_y := clampi(floori(v / depth * art.get_height()), 0, art.get_height() - 1)
				if art_offset >= 0:
					texture_y = posmod(floori((art_offset + v) / (tile_size * 0.75) * art.get_height()), art.get_height())
				c = art.get_pixel(clampi(floori(u * art.get_width()), 0, art.get_width() - 1), texture_y)
				c = MapSurfaceArt.tint(c, side_base, MapSurfaceArt.SIDES[recipe.material])
				c += (side_detail - MapSurfaceArt.SIDE_DETAILS[recipe.material]) * c.get_luminance() * 0.55
				c = side_base.lerp(c, minf(1.0, grain * 1.6)).darkened(shade * 0.65)
				var pixel := Vector2i(x, y)
				if Rect2i(Vector2i.ZERO, image.get_size()).has_point(pixel):
					image.set_pixelv(pixel, c)
				continue
			c = c.darkened(maxf(0, 0.5 - fleck) * 0.10 * grain)
			match pattern:
				TextureRecipe.SidePattern.SOIL:
					var bend := noise.get_noise_2d(sx * 0.7, 17.0) * depth * 0.055
					var t := (v + bend) / depth
					if t < 0.18:
						c = recipe.base_color.lerp(recipe.detail_color, 0.2 + n * 0.2) if cap else c.lightened(0.12)
					elif t < 0.24:
						c = side_detail.lerp(recipe.base_color, 0.5)
					elif t < 0.52:
						c = c.lerp(side_detail, 0.3)
					elif t < 0.58:
						c = c.darkened(0.20)
					elif t < 0.84:
						c = c.darkened(0.08)
					else:
						c = c.darkened(0.27)
					if fleck > 0.96 and t > 0.26:
						c = c.lerp(side_detail, 0.65 * grain)
				TextureRecipe.SidePattern.MOSS:
					var hanging := clampf(noise.get_noise_2d(sx * 1.5, 0) * 2.0 + 0.5, 0.0, 1.0)
					var fringe := depth * (0.27 + hanging * 0.54)
					if (cap and v < fringe) or n > 0.66:
						c = recipe.base_color.darkened(0.24).lerp(side_detail, n * 0.30)
						var leaf := foliage.get_pixel(clampi(floori(sx), 0, tile_size - 1), clampi(floori(sy), 0, depth - 1))
						c = c.lerp(Color(leaf, 1.0), leaf.a)
					else:
						c = side_base.lerp(Color("56452d"), 0.45).lerp(side_detail, n * 0.15)
						var root := fposmod(sx + sin(sy / (6 * unit) + n) * 1.8 * unit, 13 * unit)
						if root < unit and n > 0.4:
							c = c.lerp(side_detail, 0.50)
						if fleck > 0.96:
							c = c.lightened(0.10)
				TextureRecipe.SidePattern.ROCK:
					var band := fposmod(sy + floorf(n * 5.0 * unit), maxf(4, depth / 2.0))
					if band < unit:
						c = c.darkened(0.38)
					elif band < 2 * unit:
						c = c.lightened(0.14)
					if fposmod(sx + sy * 0.3 + n * 4 * unit, 19 * unit) < unit:
						c = c.darkened(0.20)
				TextureRecipe.SidePattern.BRICK:
					var brick_h := maxf(3, depth / (3.0 if cap else 2.0))
					var brick_w := maxf(8, tile_size / 4.0)
					var row := floori(sy / brick_h)
					var bx := sx + (brick_w * 0.5 if row % 2 else 0.0)
					var variation := MapTextureFactory._hash(floori(bx / brick_w), row, recipe.seed_value + 3)
					var ux := fposmod(bx, brick_w)
					var vy := fposmod(sy, brick_h)
					c = side_base.lerp(side_detail, (variation * 0.30 + 0.16 + n * 0.12) * grain)
					if vy < unit or ux < unit:
						c = side_base.darkened(0.32)
					elif vy < 2 * unit or ux < 2 * unit:
						c = c.lerp(side_detail.lightened(0.14), 0.60)
					elif brick_h - vy < unit or brick_w - ux < unit:
						c = c.darkened(0.18)
					elif variation > 0.75 and absf(ux - brick_w * 0.73 + floorf(vy / (3 * unit)) * unit) < unit and vy > brick_h * 0.55:
						c = c.darkened(0.20)
				TextureRecipe.SidePattern.WATER:
					var t := v / depth
					var bend := sin(sx / tile_size * TAU * 2.0) * 0.018
					c = side_base.lerp(side_detail, 0.6 - t * 0.35 + n * 0.05)
					if t + bend > 0.78:
						c = side_base.darkened(0.20)
					elif t + bend > 0.58:
						c = side_base.darkened(0.02)
					if v < 1.5 * unit and cap:
						c = recipe.detail_color.lerp(recipe.base_color, 0.4)
					elif v < depth * 0.45 and fleck > 0.98:
						c = c.lerp(side_detail, 0.3)
			if recipe.style == MapProfile.Style.SOFT:
				c = _painted_side(pattern, recipe, side_base, side_detail, n, v / depth, cap, sx / tile_size)
			c = c.darkened(shade)
			if v > depth - unit:
				c = c.darkened(0.18)
			if u < 0.008 or u > 0.992:
				c = c.darkened(0.10)
			var pixel := Vector2i(x, y)
			if pixel.x >= 0 and pixel.y >= 0 and pixel.x < image.get_width() and pixel.y < image.get_height():
				image.set_pixelv(pixel, c)

static func _moss_foliage(recipe: TextureRecipe, width: int, depth: int) -> Image:
	var image := Image.create(width, depth, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = recipe.seed_value + 3049
	var unit := width / 128.0
	var count := roundi(width * depth / maxf(1.0, unit * unit) * 0.036 * recipe.side_grain)
	for i in count:
		var origin := Vector2(rng.randf() * width, rng.randf() * depth)
		var green := recipe.base_color.lerp(recipe.detail_color, rng.randf_range(0.15, 0.65))
		for leaf in rng.randi_range(2, 4):
			var a := origin + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2)) * unit
			var b := a + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(0.5, 2)) * unit
			MapTextureFactory._stroke(image, a + Vector2(0, unit), b + Vector2(0, unit), recipe.base_color.darkened(0.35), unit)
			MapTextureFactory._stroke(image, a, b, green, unit)
	return image

static func _painted_side(pattern: int, recipe: TextureRecipe, base: Color, detail: Color, noise_value: float, depth: float, cap: bool, u: float) -> Color:
	var t := depth + (noise_value - 0.5) * 0.07
	var color := base.lerp(detail, 0.18 + noise_value * recipe.side_grain * 0.6)
	match pattern:
		TextureRecipe.SidePattern.MOSS:
			var foliage := recipe.base_color.lerp(recipe.detail_color, noise_value * 0.45)
			var earth := base.lerp(Color("80633e"), 0.35)
			var fringe := 0.48 + sin(u * TAU * 3.0) * 0.16 + noise_value * 0.18
			color = foliage.lerp(earth, smoothstep(fringe - 0.06, fringe + 0.07, t)) if cap else color
		TextureRecipe.SidePattern.SOIL:
			var sand := recipe.base_color.lerp(recipe.detail_color, 0.28)
			color = sand.lerp(detail, smoothstep(0.16, 0.23, t)) if cap else color
			color = color.lerp(base, smoothstep(0.46, 0.53, t))
			color = color.lerp(base.darkened(0.20), smoothstep(0.78, 0.84, t))
		TextureRecipe.SidePattern.WATER:
			color = detail.lerp(base, smoothstep(0.05, 0.90, t))
			color = color.lerp(base.darkened(0.16), smoothstep(0.70, 0.96, t))
		TextureRecipe.SidePattern.BRICK:
			var row := floori(depth * 3.0)
			var mortar := minf(fposmod(depth * 3.0, 1.0), fposmod(u * 4.0 + (0.5 if row % 2 else 0.0), 1.0))
			color = base.darkened(0.20).lerp(color, smoothstep(0.015, 0.08, mortar))
		TextureRecipe.SidePattern.ROCK:
			color = color.darkened(smoothstep(0.65, 1.0, t) * 0.15)
	return color

static func thumbnail(recipe: TextureRecipe, shape: int, depth: int = 24, tile_width: int = 128, decoration_id: int = 0) -> Image:
	var p := MapProfile.new()
	p.tile_size = tile_width
	p.grid = MapProfile.Grid.SQUARE if shape == 0 else MapProfile.Grid.HEX
	p.hex_orientation = MapProfile.HexOrientation.POINTY if shape == 1 else MapProfile.HexOrientation.FLAT
	p.style = recipe.style
	var dimensions := MapGrid.tile_dimensions(p)
	var margin := 4
	var landmark := MapLandmarkArt.sprite(recipe.style, decoration_id, tile_width)
	var above := maxi(0, landmark.get_height() - dimensions.y / 2) if landmark != null else 0
	var image := Image.create(dimensions.x + margin * 2, dimensions.y + depth + margin * 2 + above, false, Image.FORMAT_RGBA8)
	var offset := Vector2(dimensions) * 0.5 + Vector2.ONE * margin + Vector2(0, above)
	var poly := MapGrid.polygon(p)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if b.x < a.x:
			paint_face(image, a, b, depth, offset, recipe, tile_width, true, -1.0, Vector2(margin, margin + above))
	var top := top_image(p, recipe, true)
	image.blend_rect(top, Rect2i(Vector2i.ZERO, top.get_size()), Vector2i(margin, margin + above))
	if landmark != null:
		var position := Vector2i(offset) - Vector2i(landmark.get_width() / 2, landmark.get_height())
		if recipe.style == MapProfile.Style.PIXEL:
			position.x = margin + MapLandmarkArt.centered_x(recipe.style, dimensions.x, landmark.get_width(), tile_width)
		image.blend_rect(landmark, Rect2i(Vector2i.ZERO, landmark.get_size()), position)
	image.fix_alpha_edges()
	return image

static func top_image(p: MapProfile, recipe: TextureRecipe, exposed: bool = false, variant: int = 0) -> Image:
	if recipe.style == MapProfile.Style.PIXEL:
		return MapPixelArt.top_image(p, recipe, exposed, variant)
	var dimensions := MapGrid.tile_dimensions(p)
	var outline := MapGrid.polygon(p)
	var poly: PackedVector2Array = Geometry2D.offset_polygon(outline, 1.0, Geometry2D.JOIN_MITER)[0]
	var texture := MapTextureFactory.create(recipe)
	var image := Image.create(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8)
	for y in dimensions.y:
		for x in dimensions.x:
			var point := Vector2(x + 0.5, y + 0.5) - Vector2(dimensions) * 0.5
			if not Geometry2D.is_point_in_polygon(point, poly):
				continue
			var uv := Vector2(point.x / dimensions.x, point.y / dimensions.y)
			if p.grid == MapProfile.Grid.SQUARE and p.projection == MapProfile.ProjectionMode.ISOMETRIC:
				uv = Vector2(uv.x + uv.y, uv.y - uv.x)
			uv += Vector2.ONE * 0.5
			var sample := Vector2i(posmod(floori(uv.x * texture.get_width()), texture.get_width()), posmod(floori(uv.y * texture.get_height()), texture.get_height()))
			var c := texture.get_pixelv(sample)
			if exposed:
				for edge in outline.size():
					var a := outline[edge]
					var b := outline[(edge + 1) % outline.size()]
					var distance := Geometry2D.get_closest_point_to_segment(point, a, b).distance_to(point)
					if distance < maxf(1.0, p.tile_size / 100.0):
						c = rim_color(c, recipe, point, a.y + b.y < 0)
						break
			image.set_pixel(x, y, c)
	return image

static func rim_color(color: Color, recipe: TextureRecipe, point: Vector2, rear: bool) -> Color:
	if recipe.grain <= 0.0:
		return color
	var variation := MapTextureFactory._hash(floori(point.x), floori(point.y), recipe.seed_value)
	var strength := 0.07 + variation * 0.10
	if recipe.material == TextureRecipe.MaterialKind.WATER:
		return color.lerp(recipe.detail_color, 0.25 + variation * 0.12)
	if recipe.material == TextureRecipe.MaterialKind.GRASS:
		strength *= 0.65
	return color.lerp(recipe.detail_color, strength + 0.10) if rear else color.darkened(strength)
