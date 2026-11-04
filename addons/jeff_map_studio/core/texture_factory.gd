@tool
class_name MapTextureFactory
extends RefCounted

static func create(recipe: TextureRecipe) -> Image:
	if not recipe.validate().is_empty():
		return null
	if recipe.style == MapProfile.Style.PIXEL:
		return MapPixelArt.texture(recipe)
	if recipe.illustrated and MapSurfaceArt.index(recipe.material) >= 0 and recipe.grain > 0:
		return MapSurfaceArt.top(recipe)
	var n := recipe.resolution
	var image := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = recipe.seed_value
	noise.frequency = recipe.scale / n
	noise.fractal_octaves = 3
	var seamless := noise.get_seamless_image(n, n, false, false, 0.2)
	if recipe.style == MapProfile.Style.SOFT:
		return _hand_painted(recipe, seamless)
	var step := recipe.pixel_size if recipe.style == MapProfile.Style.PIXEL else 1
	for y in n:
		for x in n:
			var sx := (x / step) * step
			var sy := (y / step) * step
			var value := seamless.get_pixel(sx, sy).r
			var color := recipe.base_color.lerp(recipe.detail_color, clampf((value - 0.25) * 1.4, 0.0, 1.0) * recipe.grain * 0.6)
			var fleck := _hash(sx, sy, recipe.seed_value)
			color = color.lightened((fleck - 0.5) * 0.10 * recipe.grain) if fleck > 0.5 else color.darkened((0.5 - fleck) * 0.12 * recipe.grain)
			if recipe.material == TextureRecipe.MaterialKind.BRICK:
				color = _paving(Vector2(sx, sy), n, recipe, value)
			elif recipe.material == TextureRecipe.MaterialKind.WATER:
				var wave := sin(TAU * (float(sy) / n * 3.0 + sin(TAU * sx / n * 2.0) * 0.10))
				color = color.lerp(recipe.detail_color, maxf(0, wave) * 0.10 * recipe.grain)
			image.set_pixel(x, y, color)
	if recipe.grain > 0.0:
		_paint_details(image, recipe)
	if step > 1:
		for y in n:
			for x in n:
				image.set_pixel(x, y, image.get_pixel((x / step) * step, (y / step) * step))
	# Periodic border samples make seam QA exact, including the pixelated output.
	for y in n:
		image.set_pixel(n - 1, y, image.get_pixel(0, y))
	for x in n:
		image.set_pixel(x, n - 1, image.get_pixel(x, 0))
	return image

static func _hand_painted(recipe: TextureRecipe, wash: Image) -> Image:
	var n := recipe.resolution
	var image := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var grain := recipe.grain
	var base := recipe.base_color.lerp(recipe.detail_color, 0.18 * grain)
	for y in n:
		for x in n:
			var value := wash.get_pixel(x, y).r
			var color := base.lerp(recipe.detail_color, (0.12 + value * 0.60) * grain)
			if recipe.material == TextureRecipe.MaterialKind.BRICK:
				color = _paving(Vector2(x, y), n, recipe, value).lerp(color, 0.18)
			var paper := (_hash(x, y, recipe.seed_value) - 0.5) * 0.035 * grain
			color = color.lightened(paper) if paper > 0 else color.darkened(-paper)
			image.set_pixel(x, y, color)
	var rng := RandomNumberGenerator.new()
	rng.seed = recipe.seed_value + 65003
	var unit := n / 128.0
	if grain > 0:
		if recipe.material != TextureRecipe.MaterialKind.BRICK:
			for i in 42:
				var position := Vector2(rng.randf() * n, rng.randf() * n)
				var radius := Vector2(rng.randf_range(5, 18), rng.randf_range(2, 7)) * unit
				var pigment := recipe.detail_color if i % 3 else recipe.base_color.darkened(0.12)
				_dab(image, position, radius, rng.randf_range(-0.6, 0.6), pigment, grain * rng.randf_range(0.15, 0.5), recipe.seed_value + i)
		if recipe.material == TextureRecipe.MaterialKind.GRASS:
			for i in roundi(50 * grain):
				var center := Vector2(rng.randf() * n, rng.randf() * n)
				for blade in 3:
					_dab(image, center + Vector2(blade * 1.5, -blade) * unit, Vector2(0.9, 3.2) * unit, -0.5 + blade * 0.5, recipe.detail_color, 0.6, i)
		elif recipe.material == TextureRecipe.MaterialKind.WATER:
			for i in roundi(26 * grain):
				var center := Vector2(rng.randf() * n, rng.randf() * n)
				var radius := Vector2(rng.randf_range(5, 12), rng.randf_range(2, 4)) * unit
				for part in 12:
					var angle := 0.2 + part * 0.12
					var point := center + Vector2(cos(angle), sin(angle)) * radius
					_dab(image, point, Vector2(1.2, 0.7) * unit, 0.0, recipe.detail_color.lightened(0.1), 0.30, i)
		elif recipe.material == TextureRecipe.MaterialKind.SAND:
			for i in roundi(45 * grain):
				_dab(image, Vector2(rng.randf() * n, rng.randf() * n), Vector2(1.2, 0.6) * unit, 0.0, recipe.base_color.darkened(0.15), 0.35, i)
	for y in n:
		image.set_pixel(n - 1, y, image.get_pixel(0, y))
	for x in n:
		image.set_pixel(x, n - 1, image.get_pixel(x, 0))
	return image

static func _dab(image: Image, center: Vector2, radius: Vector2, angle: float, color: Color, opacity: float, seed_value: int) -> void:
	var bounds := ceili(maxf(radius.x, radius.y))
	var ca := cos(angle)
	var sa := sin(angle)
	for dy in range(-bounds, bounds + 1):
		for dx in range(-bounds, bounds + 1):
			var local := Vector2((dx * ca + dy * sa) / maxf(0.6, radius.x), (-dx * sa + dy * ca) / maxf(0.6, radius.y))
			var distance := local.length()
			if distance >= 1.0:
				continue
			var x := posmod(roundi(center.x) + dx, image.get_width())
			var y := posmod(roundi(center.y) + dy, image.get_height())
			var amount := (1.0 - smoothstep(0.30, 1.0, distance)) * opacity
			amount *= 0.82 + _hash(x, y, seed_value) * 0.18
			image.set_pixel(x, y, image.get_pixel(x, y).lerp(color, amount))

## Coordinate hashes and wrapped strokes keep detail deterministic and repeatable.
static func _hash(x: int, y: int, seed_value: int) -> float:
	var h := (x * 374761393 + y * 668265263 + seed_value * 144269) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h ^ (h >> 16)) / 2147483647.0

static func _paving(point: Vector2, n: int, recipe: TextureRecipe, noise_value: float) -> Color:
	var size := n / 4.0
	var cell := Vector2i(floori(point.x / size), floori(point.y / size))
	var uv := Vector2(fposmod(point.x, size), fposmod(point.y, size))
	var variation := _hash(cell.x, cell.y, recipe.seed_value)
	var c := recipe.base_color.lerp(recipe.detail_color, (0.08 + variation * 0.24 + noise_value * 0.13) * recipe.grain)
	var bevel := maxf(1.0, n / 100.0)
	var seam := maxf(0.7, n / 220.0)
	var left := minf(uv.x, uv.y)
	var right := minf(size - uv.x, size - uv.y)
	if left < seam:
		return recipe.base_color.darkened(0.30)
	if left < bevel + seam:
		return c.lerp(recipe.detail_color.lightened(0.1), 0.60)
	if right < bevel:
		return c.darkened(0.17)
	# Small worn corners, rather than a uniformly perfect grid.
	if variation > 0.58 and uv.x + uv.y > size * 1.92 - bevel:
		return c.darkened(0.22)
	return c

static func _dot(image: Image, point: Vector2, color: Color) -> void:
	image.set_pixel(posmod(roundi(point.x), image.get_width()), posmod(roundi(point.y), image.get_height()), color)

static func _stroke(image: Image, a: Vector2, b: Vector2, color: Color, width: float = 1.0) -> void:
	var length := maxi(1, ceili(a.distance_to(b) * 1.5))
	var radius := maxi(0, floori(width * 0.5))
	for i in length + 1:
		var point := a.lerp(b, float(i) / length)
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if dx * dx + dy * dy <= radius * radius:
					_dot(image, point + Vector2(dx, dy), color)

static func _oval(image: Image, center: Vector2, radius: Vector2, color: Color) -> void:
	var rx := maxf(0.7, radius.x)
	var ry := maxf(0.7, radius.y)
	for y in range(floori(center.y - ry), ceili(center.y + ry) + 1):
		for x in range(floori(center.x - rx), ceili(center.x + rx) + 1):
			if Vector2((x - center.x) / rx, (y - center.y) / ry).length_squared() <= 1.0:
				_dot(image, Vector2(x, y), color)

static func _paint_details(image: Image, recipe: TextureRecipe) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = recipe.seed_value + 8191
	var n := image.get_width()
	var unit := n / 128.0
	var dark := recipe.base_color.darkened(0.28)
	var light := recipe.detail_color
	match recipe.material:
		TextureRecipe.MaterialKind.GRASS:
			# Each tuft has a contact shadow, separate blades and a few lit tips.
			for i in roundi(270 * recipe.grain):
				var center := Vector2(rng.randf() * n, rng.randf() * n)
				var size := rng.randf_range(0.7, 1.4) * unit
				_oval(image, center + Vector2(0, size), Vector2(2.7, 1.2) * size, recipe.base_color.darkened(0.18))
				var green := recipe.base_color.lerp(light, rng.randf_range(0.16, 0.56))
				for blade in rng.randi_range(3, 5):
					var tip := center + Vector2(rng.randf_range(-3.4, 3.4), rng.randf_range(-4.0, -0.8)) * size
					_stroke(image, center + Vector2(size, size), tip + Vector2(size, 0), dark, unit)
					_stroke(image, center, tip, green, unit)
					if blade % 2 == 0:
						_dot(image, tip, green.lerp(light, 0.5))
			for i in roundi(5 * recipe.grain):
				var center := Vector2(rng.randf() * n, rng.randf() * n)
				_oval(image, center + Vector2(unit, unit), Vector2(3, 2) * unit, dark)
				_oval(image, center, Vector2(2.7, 1.7) * unit, recipe.base_color.lerp(Color("9d9e79"), 0.65))
				_stroke(image, center + Vector2(-unit, -unit), center + Vector2(unit, -unit), light, unit)
		TextureRecipe.MaterialKind.SAND:
			# Sparse grains and small wind-etched streaks leave broad quiet areas.
			for i in roundi(230 * recipe.grain):
				var center := Vector2(rng.randf() * n, rng.randf() * n)
				_dot(image, center, recipe.base_color.darkened(rng.randf_range(0.08, 0.22)))
				if i % 4 == 0:
					_dot(image, center + Vector2(-unit, -unit), light)
			for i in roundi(24 * recipe.grain):
				var a := Vector2(rng.randf() * n, rng.randf() * n)
				var b := a + Vector2(rng.randf_range(2, 6), -1) * unit
				_stroke(image, a, b, recipe.base_color.darkened(0.12), unit)
				_stroke(image, a + Vector2(0, -unit), b + Vector2(0, -unit), recipe.base_color.lerp(light, 0.75), unit)
		TextureRecipe.MaterialKind.WATER:
			for i in roundi(30 * recipe.grain):
				var center := Vector2(rng.randf() * n, rng.randf() * n)
				var radius := Vector2(rng.randf_range(4, 12), rng.randf_range(1.5, 4.0)) * unit
				var begin := rng.randf_range(0.1, 2.5)
				var sweep := rng.randf_range(0.9, 2.2)
				var previous := center + Vector2(cos(begin), sin(begin)) * radius
				for part in range(1, 14):
					var angle := begin + sweep * part / 13.0
					var point := center + Vector2(cos(angle), sin(angle)) * radius
					_stroke(image, previous + Vector2(0, unit), point + Vector2(0, unit), recipe.base_color.darkened(0.10), unit)
					_stroke(image, previous, point, light.lerp(Color.WHITE, 0.20 if i % 3 == 0 else 0.0), unit)
					previous = point
		TextureRecipe.MaterialKind.BRICK:
			var size := n / 4.0
			for row in 4:
				for col in 4:
					if rng.randf() > recipe.grain * 0.65:
						continue
					var a := Vector2(col * size + size * 0.75, row * size + size - 2 * unit)
					var b := a + Vector2(-2, -4) * unit
					var c := b + Vector2(1, -3) * unit
					_stroke(image, a, b, recipe.base_color.darkened(0.25), unit)
					_stroke(image, b, c, recipe.base_color.darkened(0.22), unit)
					_stroke(image, a + Vector2(unit, 0), b + Vector2(unit, 0), light, unit)
		TextureRecipe.MaterialKind.ROCK:
			for i in roundi(22 * recipe.grain):
				var a := Vector2(rng.randf() * n, rng.randf() * n)
				var b := a + Vector2(rng.randf_range(2, 8), rng.randf_range(-3, 3)) * unit
				_stroke(image, a, b, dark, unit)
				_stroke(image, a + Vector2(0, -unit), b + Vector2(0, -unit), light, unit)
