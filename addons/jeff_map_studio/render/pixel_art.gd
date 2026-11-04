@tool
class_name MapPixelArt
extends RefCounted
## Pixel style renderer. Tops, cliffs and objects share one screen-aligned logical
## grid and short hue-shifted ramps, so isometric projection never shears pixels.
## Patterns are periodic on the tile lattice and continue across neighbours.

## Pixel size is authored against a 64 px tile: pixel_size 2 gives a 32 px logical tile.
const REFERENCE_TILE := 64.0
const GRASS := TextureRecipe.MaterialKind.GRASS
const SAND := TextureRecipe.MaterialKind.SAND
const ROCK := TextureRecipe.MaterialKind.ROCK
const WATER := TextureRecipe.MaterialKind.WATER
const BRICK := TextureRecipe.MaterialKind.BRICK
const ACCENTS := {"a": Color("fff4d6"), "b": Color("f6d65a"), "d": Color("c8b6f0"), "l": Color("f7d9cf")}
## Ramp indices drawn on exposed front / rear top edges, per material.
const RIM_FRONT := [4, 5, 4, 5, 4]
const RIM_REAR := [2, 2, 2, 4, 1]

## Art authored in Aseprite (assets/pixel/*.aseprite), imported by tools/export_pixel_art.py.
## Cluster digits are ramp indices recoloured per material; letters are fixed accents.
const CLUSTERS = preload("res://addons/jeff_map_studio/assets/pixel/clusters.res")
## Objects at the 32 px logical tile; the bottom row is a translucent contact shadow.
const OBJECTS = preload("res://addons/jeff_map_studio/assets/pixel/landmarks.res")
## Terrains drawn from a TerrainArtSpec + Aseprite concept (art/specs, art/concepts).
## Other materials use built-in rules; a default TerrainArtSpec carries their values.
const GRASS_SPEC = preload("res://addons/jeff_map_studio/art/specs/pixel/grass.tres")

## Top variants per terrain ("moods"); larger variant ids are interior sub-variants
## of mood id % MOODS.
const MOODS := 4

static func spec_for(material: int) -> TerrainArtSpec:
	return GRASS_SPEC if material == GRASS else TerrainArtSpec.new()

static func step(recipe: TextureRecipe, tile_size: int) -> int:
	return maxi(1, roundi(recipe.pixel_size * tile_size / REFERENCE_TILE))

## Six-step ramp: 0 deep shadow … 3 base … 5 highlight. Shadows cool, lights warm.
static func ramp(base: Color, light: Color) -> PackedColorArray:
	var mid := Color.from_hsv(base.h, minf(1.0, base.s * 1.12 + 0.03), base.v)
	return PackedColorArray([_shade(mid, -0.74), _shade(mid, -0.5), _shade(mid, -0.25), mid, _shade(mid.lerp(light, 0.7), 0.16), _shade(light, 0.5)])

static func _shade(color: Color, amount: float) -> Color:
	var target := 0.69 if amount < 0.0 else 0.13
	var hue := color.h
	var saturation := color.s
	var value := color.v
	if saturation < 0.08:
		hue = target
	else:
		hue = fposmod(hue + wrapf(target - hue, -0.5, 0.5) * absf(amount) * 0.32, 1.0)
	if amount < 0.0:
		saturation = minf(1.0, saturation + 0.26 * -amount)
		value *= 1.0 + amount * 0.6
	else:
		saturation *= 1.0 - amount * 0.5
		value += (1.0 - value) * amount * 0.8
	return Color.from_hsv(hue, clampf(saturation, 0.0, 1.0), clampf(value, 0.0, 1.0))

## Lattice basis of the top surface in tile-local pixels; neighbours sit at integer offsets.
static func lattice(p: MapProfile) -> Array[Vector2]:
	var size := Vector2(MapGrid.tile_dimensions(p))
	if p.grid == MapProfile.Grid.SQUARE:
		if p.projection == MapProfile.ProjectionMode.ISOMETRIC:
			return [Vector2(size.x, size.y) * 0.5, Vector2(-size.x, size.y) * 0.5]
		return [Vector2(size.x, 0), Vector2(0, size.y)]
	if p.hex_orientation == MapProfile.HexOrientation.POINTY:
		return [Vector2(size.x, 0), Vector2(size.x * 0.5, size.y * 0.75)]
	return [Vector2(size.x * 0.75, size.y * 0.5), Vector2(0, size.y)]

## Flat square swatch for previews and exported material PNGs.
static func texture(recipe: TextureRecipe) -> Image:
	var n := recipe.resolution
	var size := step(recipe, n)
	var canvas := _surface(recipe, Vector2i(n, n), size, [Vector2(n, 0), Vector2(0, n)], PackedVector2Array(), 0)
	var image := _enlarge(canvas, size, Vector2i(n, n))
	# Periodic border samples keep the seam check exact.
	for y in n:
		image.set_pixel(n - 1, y, image.get_pixel(0, y))
	for x in n:
		image.set_pixel(x, n - 1, image.get_pixel(x, 0))
	return image

## Tile top without rims plus one rim overlay per polygon edge.
static func top_layers(p: MapProfile, recipe: TextureRecipe, variant: int = 0) -> Dictionary:
	var dimensions := MapGrid.tile_dimensions(p)
	var size := step(recipe, p.tile_size)
	var polygon := MapGrid.polygon(p)
	var canvas := _surface(recipe, dimensions, size, lattice(p), polygon, variant)
	var rims: Array[Image] = []
	var colors := ramp(recipe.base_color, recipe.detail_color)
	var spec := spec_for(recipe.material)
	var front: int = spec.rim_front_tone if recipe.material == GRASS else RIM_FRONT[recipe.material]
	var back: int = spec.rim_rear_tone if recipe.material == GRASS else RIM_REAR[recipe.material]
	var logical := canvas.get_size()
	var half := Vector2(dimensions) * 0.5
	for edge in polygon.size():
		rims.append(Image.create(logical.x, logical.y, false, Image.FORMAT_RGBA8))
	if recipe.grain > 0.0:
		for y in logical.y:
			for x in logical.x:
				var point := Vector2((x + 0.5) * size, (y + 0.5) * size) - half
				if not Geometry2D.is_point_in_polygon(point, polygon):
					continue
				for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var outside := point + Vector2(offset) * size
					if Geometry2D.is_point_in_polygon(outside, polygon):
						continue
					var edge := _closest_edge(outside, polygon)
					var rear := polygon[edge].y + polygon[(edge + 1) % polygon.size()].y < 0
					var index := back if rear else front
					# Water foam breaks into dashes rather than drawing a ruled line.
					if recipe.material == WATER and MapTextureFactory._hash(x / 2, y, recipe.seed_value + edge) > 0.78:
						index = 4
					rims[edge].set_pixel(x, y, colors[index])
	var result: Array[Image] = []
	for rim in rims:
		result.append(_enlarge(rim, size, dimensions))
	return {"base": _enlarge(canvas, size, dimensions), "rims": result}

static func top_image(p: MapProfile, recipe: TextureRecipe, exposed: bool = false, variant: int = 0) -> Image:
	var layers := top_layers(p, recipe, variant)
	var image: Image = layers.base
	if exposed:
		for rim: Image in layers.rims:
			image.blend_rect(rim, Rect2i(Vector2i.ZERO, rim.get_size()), Vector2i.ZERO)
	return image

static func _closest_edge(point: Vector2, polygon: PackedVector2Array) -> int:
	var best := 0
	var best_distance := INF
	for edge in polygon.size():
		var distance := Geometry2D.get_closest_point_to_segment(point, polygon[edge], polygon[(edge + 1) % polygon.size()]).distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best = edge
	return best

static func _enlarge(canvas: Image, size: int, dimensions: Vector2i) -> Image:
	var image := canvas.duplicate() as Image
	if size > 1:
		image.resize(canvas.get_width() * size, canvas.get_height() * size, Image.INTERPOLATE_NEAREST)
	if image.get_size() != dimensions:
		image = image.get_region(Rect2i(Vector2i.ZERO, dimensions))
	return image

## Logical-resolution surface. Each block is sampled at its centre in tile-local
## pixels; blocks within half a block of the outline overlap the neighbour.
static func _surface(recipe: TextureRecipe, dimensions: Vector2i, size: int, basis: Array, polygon: PackedVector2Array, variant: int) -> Image:
	var logical := Vector2i(ceili(float(dimensions.x) / size), ceili(float(dimensions.y) / size))
	var canvas := Image.create(logical.x, logical.y, false, Image.FORMAT_RGBA8)
	var colors := ramp(recipe.base_color, recipe.detail_color)
	var half := Vector2(dimensions) * 0.5
	var a: Vector2 = basis[0]
	var b: Vector2 = basis[1]
	var det := a.cross(b)
	var grown := polygon if polygon.is_empty() else Geometry2D.offset_polygon(polygon, size * 0.5, Geometry2D.JOIN_MITER)[0]
	var spec := spec_for(recipe.material)
	var period := spec.period(recipe.scale)
	var grain := recipe.grain
	var material := recipe.material
	# Identifier grid with a one-block border: edges of slabs, facets and ripples
	# come from neighbouring blocks, which keeps every line one pixel wide.
	var ids := PackedInt32Array()
	ids.resize((logical.x + 2) * (logical.y + 2))
	for y in range(-1, logical.y + 1):
		for x in range(-1, logical.x + 1):
			var st := _lattice_point(Vector2((x + 0.5) * size, (y + 0.5) * size) - half, a, b, det)
			ids[(y + 1) * (logical.x + 2) + x + 1] = _cell_id(material, st, recipe.seed_value, period, a, b)
	var window := maxf(1.0, minf(dimensions.x, dimensions.y) * spec.variant_window)
	var margin := spec.variant_margin_steps * size
	var snowy := material == ROCK and recipe.base_color.get_luminance() > 0.72
	for y in logical.y:
		for x in logical.x:
			var point := Vector2((x + 0.5) * size, (y + 0.5) * size) - half
			if not grown.is_empty() and not Geometry2D.is_point_in_polygon(point, grown):
				continue
			var st := _lattice_point(point, a, b, det)
			var n := _noise(st, period, recipe.seed_value) * spec.coarse_weight + _noise(st, period * 2, recipe.seed_value + 31) * (1.0 - spec.coarse_weight)
			if not polygon.is_empty() and variant > 0:
				# Variants differ only away from the outline, so neighbours stay continuous.
				var inside := clampf((_edge_distance(point, polygon) - margin) / window, 0.0, 1.0)
				n += ((_noise(st, period + 1, recipe.seed_value + variant * 1013) - 0.5) * spec.variant_strength + spec.tone_bias(variant % MOODS)) * inside
			var id := ids[(y + 1) * (logical.x + 2) + x + 1]
			var right := ids[(y + 1) * (logical.x + 2) + x + 2]
			var down := ids[(y + 2) * (logical.x + 2) + x + 1]
			var left := ids[(y + 1) * (logical.x + 2) + x]
			var up := ids[y * (logical.x + 2) + x + 1]
			var index := 3
			match material:
				GRASS:
					index = _tone(n, grain, spec.dark_below, spec.light_above)
				SAND:
					index = 4 if n > 1.0 - grain * 0.55 else 3
					if grain > 0.0 and _noise(st, period + 2, recipe.seed_value + 7) > 0.5:
						if id != down:
							index = 2
						elif id != up:
							index = 4 if index == 3 else 5
				WATER:
					index = _tone(n, grain, 0.24, 0.84)
					# Sparse wave crests: a lit line over a one-pixel trough.
					if grain > 0.0 and recipe.illustrated and _noise(st, period + 1, recipe.seed_value + 13) > 0.66:
						if id != down:
							index = 4
						elif id != up:
							index = 2
				ROCK:
					var crack := _noise(st, period * 2, recipe.seed_value + 19) > 0.38
					if snowy:
						# Snow: soft drifts, with only a few buried stone edges showing.
						index = _tone(n, grain, 0.16, 0.74)
						if grain > 0.0 and crack and _noise(st, period, recipe.seed_value + 23) > 0.62 and (id != right or id != down):
							index = 2
					else:
						# Rock: broad facets with broken cracks, lit on their upper-left edges.
						index = 2 + int(MapTextureFactory._hash(id, 7, recipe.seed_value) > 0.4)
						if n > 0.72 and grain > 0.0:
							index = 4
						if grain > 0.0 and crack:
							if id != right or id != down:
								index = 1
							elif id != left or id != up:
								index = mini(index + 1, 4)
				BRICK:
					# Flagstones: per-slab tone, dark joints below/right, a lit upper edge and
					# fine chisel pits. Slabs inside the tile vary by variant.
					var inner := posmod(id / 4096, 2) == 0 or posmod(id, 2) == 1
					index = 3 - int(MapTextureFactory._hash(id, 11 + (variant if inner else 0) * 97, recipe.seed_value) > 0.68)
					if id != right or id != down:
						index = 1
					elif id != up:
						index = 4 if index == 3 else 3
					elif grain > 0.0:
						var pits := _noise(st, 18, recipe.seed_value + 29)
						if pits > 0.8:
							index -= 1
						elif pits < 0.12 * grain:
							index += 1
			canvas.set_pixel(x, y, colors[index])
	if grain > 0.0 and (recipe.illustrated or material in [ROCK, BRICK]):
		_stamp_all(canvas, recipe, spec, colors, dimensions, size, a, b, polygon, variant)
	return canvas

static func _tone(n: float, grain: float, low: float, high: float) -> int:
	if grain <= 0.0:
		return 3
	# Low grain pushes thresholds outward: fewer, smaller patches with clean edges.
	var amount := minf(1.0, grain * 1.6)
	if n > high + (1.0 - high) * (1.0 - amount):
		return 4
	if n < low * amount:
		return 2
	return 3

static func _lattice_point(point: Vector2, a: Vector2, b: Vector2, det: float) -> Vector2:
	return Vector2(point.cross(b) / det, a.cross(point) / det)

static func _edge_distance(point: Vector2, polygon: PackedVector2Array) -> float:
	var best := INF
	for edge in polygon.size():
		best = minf(best, Geometry2D.get_closest_point_to_segment(point, polygon[edge], polygon[(edge + 1) % polygon.size()]).distance_to(point))
	return best

## Periodic value noise on the tile lattice.
static func _noise(st: Vector2, period: int, seed_value: int) -> float:
	var x := st.x * period
	var y := st.y * period
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := x - x0
	var fy := y - y0
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var c00 := MapTextureFactory._hash(posmod(x0, period), posmod(y0, period), seed_value)
	var c10 := MapTextureFactory._hash(posmod(x0 + 1, period), posmod(y0, period), seed_value)
	var c01 := MapTextureFactory._hash(posmod(x0, period), posmod(y0 + 1, period), seed_value)
	var c11 := MapTextureFactory._hash(posmod(x0 + 1, period), posmod(y0 + 1, period), seed_value)
	return lerpf(lerpf(c00, c10, fx), lerpf(c01, c11, fx), fy)

## Region identifiers whose borders become one-pixel lines.
static func _cell_id(material: int, st: Vector2, seed_value: int, period: int, a: Vector2, b: Vector2) -> int:
	match material:
		SAND:
			var bands := maxi(3, period + 1)
			return floori(st.y * bands + 0.28 * sin(TAU * (st.x * 2.0 + st.y)) + 0.12 * sin(TAU * st.x * 3.0))
		WATER:
			var waves := maxi(3, period + 2)
			return floori(st.y * waves + 0.35 * sin(TAU * (st.x * 3.0 + st.y * 2.0)))
		BRICK:
			var row := floori(st.y * 2.0)
			return row * 4096 + floori(st.x * 2.0 + (0.5 if posmod(row, 2) == 1 else 0.0))
		ROCK:
			var cells := maxi(2, period - 1)
			var origin := Vector2i(floori(st.x * cells), floori(st.y * cells))
			var best := 0
			var best_distance := INF
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var cell := origin + Vector2i(dx, dy)
					var wrapped := Vector2i(posmod(cell.x, cells), posmod(cell.y, cells))
					var jitter := Vector2(MapTextureFactory._hash(wrapped.x, wrapped.y, seed_value + 5), MapTextureFactory._hash(wrapped.x, wrapped.y, seed_value + 9))
					var delta := (Vector2(cell) + Vector2(0.15, 0.15) + jitter * 0.7) / cells - st
					var distance := (a * delta.x + b * delta.y).length_squared()
					if distance < best_distance:
						best_distance = distance
						best = wrapped.y * cells + wrapped.x
			return best
	return 0

static func _stamp_all(canvas: Image, recipe: TextureRecipe, spec: TerrainArtSpec, colors: PackedColorArray, dimensions: Vector2i, size: int, a: Vector2, b: Vector2, polygon: PackedVector2Array, variant: int) -> void:
	# Each entry: [motifs, count, shared]. Shared entries draw first, then interior
	# entries, each from its own random stream so variants never move shared motifs.
	var layers: Array = []
	var accents: Dictionary = ACCENTS
	var density := recipe.grain / 0.6
	match recipe.material:
		GRASS:
			if spec.concept != null:
				accents = spec.concept.accents
				for layer in spec.motif_layers:
					if layer.requires_illustrated and not recipe.illustrated:
						continue
					layers.append([spec.concept.motifs[layer.group], layer.count(density, variant % MOODS), layer.placement == ArtMotifLayer.Placement.SHARED])
			else:
				layers = [[CLUSTERS.groups.grass_tufts, roundi(9 * density), true], [CLUSTERS.groups.grass_tufts, roundi(3 * density), false], [CLUSTERS.groups.grass_flowers, roundi(1.4 * density), false]]
		SAND:
			layers = [[CLUSTERS.groups.sand_pebbles, roundi(2 * density), true], [CLUSTERS.groups.sand_pebbles, roundi(2 * density), false]]
		WATER:
			layers = [[CLUSTERS.groups.water_glints, roundi(2 * density), true], [CLUSTERS.groups.water_glints, roundi(2 * density), false]]
		ROCK:
			layers = [[CLUSTERS.groups.rock_chips, roundi(2 * density), true]]
		BRICK:
			return
	var half := Vector2(dimensions) * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = recipe.seed_value * 31 + recipe.material
	for layer: Array in layers:
		if not layer[2]:
			continue
		var motifs: Array = layer[0]
		for i in layer[1]:
			var sprite: PackedStringArray = motifs[rng.randi() % motifs.size()]
			var st := Vector2(rng.randf(), rng.randf())
			for j in range(-1, 2):
				for k in range(-1, 2):
					var point := a * (st.x + j) + b * (st.y + k) + half
					_stamp(canvas, sprite, Vector2i(floori(point.x / size), floori(point.y / size)), colors, accents)
	rng.seed = recipe.seed_value * 31 + recipe.material + 7919 * (variant + 1)
	for layer: Array in layers:
		if layer[2]:
			continue
		var motifs: Array = layer[0]
		var placed := 0
		var attempts := 0
		while placed < layer[1] and attempts < 40:
			attempts += 1
			var sprite: PackedStringArray = motifs[rng.randi() % motifs.size()]
			var st := Vector2(rng.randf(), rng.randf())
			var point := a * st.x + b * st.y + half
			var anchor := Vector2i(floori(point.x / size), floori(point.y / size))
			if not polygon.is_empty() and not _fits(sprite, anchor, size, half, polygon):
				continue
			_stamp(canvas, sprite, anchor, colors, accents)
			placed += 1

static func _fits(sprite: PackedStringArray, anchor: Vector2i, size: int, half: Vector2, polygon: PackedVector2Array) -> bool:
	var width: int = sprite[0].length()
	var origin := anchor - Vector2i(width / 2, sprite.size() - 1)
	for corner: Vector2i in [Vector2i(-1, -1), Vector2i(width, -1), Vector2i(-1, sprite.size()), Vector2i(width, sprite.size())]:
		var point := Vector2((origin.x + corner.x + 0.5) * size, (origin.y + corner.y + 0.5) * size) - half
		if not Geometry2D.is_point_in_polygon(point, polygon):
			return false
	return true

## Bottom-centre anchored; only paints blocks that already belong to the surface.
static func _stamp(canvas: Image, sprite: PackedStringArray, anchor: Vector2i, colors: PackedColorArray, accents: Dictionary = ACCENTS) -> void:
	var width: int = sprite[0].length()
	var origin := anchor - Vector2i(width / 2, sprite.size() - 1)
	for row in sprite.size():
		var line: String = sprite[row]
		for column in line.length():
			var key: String = line[column]
			if key == ".":
				continue
			var pixel := origin + Vector2i(column, row)
			if pixel.x < 0 or pixel.y < 0 or pixel.x >= canvas.get_width() or pixel.y >= canvas.get_height():
				continue
			if canvas.get_pixelv(pixel).a == 0.0:
				continue
			canvas.set_pixelv(pixel, accents[key] if accents.has(key) else colors[int(key)])

## Cliff and base faces. The grid is anchored at the tile's top-left corner, the same
## origin as the top image; `phase` continues strata across stacked height layers.
static func paint_face(image: Image, a: Vector2, b: Vector2, depth: int, offset: Vector2, recipe: TextureRecipe, tile_size: int, cap: bool, phase: float, origin: Vector2) -> void:
	var size := step(recipe, tile_size)
	var pattern := MapBlockSurface.side_pattern(recipe)
	var side_base := recipe.side_color if recipe.side_color.a > 0.0 else recipe.base_color.darkened(0.18)
	var side_detail := recipe.side_detail_color if recipe.side_detail_color.a > 0.0 else recipe.detail_color.darkened(0.2)
	var earth := ramp(side_base, side_detail)
	var top := ramp(recipe.base_color, recipe.detail_color)
	var spec := spec_for(recipe.material)
	var stone := ramp(spec.stone_color.lerp(side_base, spec.stone_tint), spec.stone_light)
	var shadow := 1 if a.x + b.x > 0.5 else 0
	var left := minf(a.x, b.x)
	var right := maxf(a.x, b.x)
	var columns := maxi(1, roundi((right - left) / size))
	# Blocks belong to the face that contains their centre and are drawn whole, so a
	# block straddling the front vertex never leaves a gap. Clip to the tile cell only.
	var clip := Rect2i(Vector2i(roundi(origin.x), floori(offset.y + minf(a.y, b.y) - size)), Vector2i.ZERO)
	clip.end = Vector2i(roundi(2.0 * offset.x - origin.x), ceili(offset.y + maxf(a.y, b.y) + depth))
	clip = clip.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if not clip.has_area():
		return
	var first := Vector2i(floori((clip.position.x - origin.x) / size), floori((clip.position.y - origin.y) / size))
	var last := Vector2i(ceili((clip.end.x - origin.x) / size), ceili((clip.end.y - origin.y) / size))
	var grain := recipe.side_grain
	for by in range(first.y, last.y):
		for bx in range(first.x, last.x):
			var center := origin + Vector2((bx + 0.5) * size, (by + 0.5) * size) - offset
			if center.x < left or center.x > right:
				continue
			var u := (center.x - a.x) / (b.x - a.x)
			var v := center.y - lerpf(a.y, b.y, u)
			if v < -size * 0.5 or v > depth + size * 0.5:
				continue
			var column := posmod(floori((center.x - left) / size), columns)
			var row := floori((phase + maxf(v, 0.0)) / size)
			var color := _side_color(pattern, spec, column, row, columns, cap, grain, recipe.seed_value, earth, top, stone, shadow)
			var block := Rect2i(Vector2i(origin + Vector2(bx, by) * size), Vector2i(size, size)).intersection(clip)
			if block.has_area():
				image.fill_rect(block, color)

static func _side_color(pattern: int, spec: TerrainArtSpec, column: int, row: int, columns: int, cap: bool, grain: float, seed_value: int, earth: PackedColorArray, top: PackedColorArray, stone: PackedColorArray, shadow: int) -> Color:
	var grit := MapTextureFactory._hash(column, row, seed_value + 211)
	var lip := 0
	if cap:
		# Clustered drip lengths: a slow wave plus occasional longer strands.
		var wave := _noise(Vector2(float(column) / columns, 0.0), maxi(2, columns / 3), seed_value + 41)
		lip = spec.lip_rows + int(wave > spec.lip_wave_above) + int(MapTextureFactory._hash(column, 0, seed_value + 43) > 1.0 - spec.lip_strand_chance)
	match pattern:
		TextureRecipe.SidePattern.MOSS:
			if row < lip:
				# The turf edge sits in shade under the lit top rim; strands end dark.
				var index := 3 if row == 0 else 2
				if row == lip - 1 and row > 1:
					index = 1
				return top[maxi(0, index - shadow)]
			if cap and row == lip:
				return earth[maxi(0, 1 - shadow)]
			var index := 3
			var band := posmod(row + int(MapTextureFactory._hash(column / 4, 1, seed_value) * 2.0), spec.band_period)
			if band == spec.band_period - 1:
				index = 2
			if grain > 0.0:
				var cell := Vector2i(floori(float(column) / spec.stone_cell.x), floori(float(row) / spec.stone_cell.y))
				var chance := MapTextureFactory._hash(cell.x, cell.y, seed_value + 59)
				if chance < spec.stone_chance * grain:
					var local := Vector2i(column - cell.x * spec.stone_cell.x, row - cell.y * spec.stone_cell.y)
					var start := int(MapTextureFactory._hash(cell.x, cell.y, seed_value + 61) * (spec.stone_cell.x - 3))
					if local.x >= start and local.x < start + 3 and local.y < 2:
						var tone := 4 if local.y == 0 else 2
						if local.x == start + 2 and local.y == 1:
							tone = 1
						return stone[maxi(0, tone - shadow)]
					if local.x >= start and local.x < start + 3 and local.y == 2:
						return earth[maxi(0, 1 - shadow)]
				if MapTextureFactory._hash(column, 3, seed_value + 67) > 1.0 - spec.root_chance * grain and row < spec.root_rows and row >= lip:
					index = 4
				elif grit > 1.0 - spec.speck_chance * grain:
					index = 5
			return earth[maxi(0, index - shadow)]
		TextureRecipe.SidePattern.SOIL:
			if row < lip - 1:
				return top[maxi(0, (4 if row == 0 else 3) - shadow)]
			if cap and row == lip - 1:
				return top[maxi(0, 2 - shadow)]
			var plate := int(MapTextureFactory._hash(column / 4, 2, seed_value) * 3.0)
			var band := posmod(row + plate, 4)
			var index := 3
			if band == 0:
				index = 4
			elif band == 3:
				index = 2
			if grain > 0.0:
				if posmod(column, 4) == 3 and MapTextureFactory._hash(column / 4, (row + plate) / 4, seed_value + 71) > 1.0 - 0.45 * grain:
					index = 1
				elif grit > 1.0 - 0.05 * grain:
					index = 5
			return earth[maxi(0, index - shadow)]
		TextureRecipe.SidePattern.WATER:
			if cap and row == 0:
				return top[maxi(0, 5 - shadow)]
			if cap and row == 1:
				return top[maxi(0, (5 if (column + int(grit * 2.0)) % 3 == 0 else 4) - shadow)]
			var index := 4
			var depth_band := row + int((column + row) % 2 == 0)
			if depth_band > 9:
				index = 1
			elif depth_band > 6:
				index = 2
			elif depth_band > 3:
				index = 3
			if grain > 0.0 and MapTextureFactory._hash(column, row / 3, seed_value + 73) > 1.0 - 0.1 * grain:
				index = mini(5, index + 1)
			return earth[maxi(0, index - shadow)]
		TextureRecipe.SidePattern.ROCK:
			if cap and row == 0:
				return top[maxi(0, 4 - shadow)]
			var course := floori(row / 3.0)
			var shifted := column + (2 if posmod(course, 2) == 1 else 0)
			var stone_id := floori(shifted / (4.0 + float(posmod(course, 3) == 0)))
			var index := 2 + int(MapTextureFactory._hash(stone_id, course, seed_value + 79) > 0.5)
			if posmod(row, 3) == 2 or posmod(shifted, 4 + int(posmod(course, 3) == 0)) == 0:
				index = 1
			elif posmod(row, 3) == 0:
				index = 4
			return earth[maxi(0, index - shadow)]
		TextureRecipe.SidePattern.BRICK:
			if cap and row == 0:
				return top[maxi(0, 4 - shadow)]
			var course := floori(row / 3.0)
			var shifted := column + (3 if posmod(course, 2) == 1 else 0)
			var index := 2 + int(MapTextureFactory._hash(floori(shifted / 6.0), course, seed_value + 83) > 0.45)
			if posmod(row, 3) == 2 or posmod(shifted, 6) == 5:
				index = 1
			elif posmod(row, 3) == 0:
				index = 4
			return earth[maxi(0, index - shadow)]
	return earth[3 - shadow]

static func landmark(id: int) -> Image:
	if id < 1 or id > OBJECTS.sprites.size():
		return null
	return OBJECTS.sprites[id - 1].duplicate()

## Objects follow the default terrain pixel size: one logical pixel per 32nd of the tile.
static func landmark_scale(tile_size: int) -> int:
	return maxi(1, roundi(tile_size / 32.0))
