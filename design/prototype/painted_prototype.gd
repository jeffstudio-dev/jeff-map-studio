extends SceneTree
## Design prototype (headless): paints the hand-painted grass terrain entirely in code
## from design/specs/painted_grass.json and the exported Aseprite concept sheet.
## Not part of the addon; it shows that spec + concept + seed are enough to draw.
const DESIGN := "res://design"
const OUT := "res://design/examples/painted"
const W := 128
const H := 64
const SEEDS := [42, 7, 2026]
## name, grain, stroke scale, base colour override ("" keeps the concept palette), detail override
const PARAMS := [["默认", 0.6, 1.0, "", ""], ["浓密·细笔触", 0.95, 0.75, "", ""], ["秋草配色", 0.6, 1.0, "b3a85a", "e8d48c"]]

var spec: Dictionary
var ramps: Dictionary = {}
var accents: Array[Color] = []
var brushes: Dictionary = {}
var polygon := PackedVector2Array([Vector2(0, -H / 2), Vector2(W / 2, 0), Vector2(0, H / 2), Vector2(-W / 2, 0)])
var basis_a := Vector2(W, H) * 0.5
var basis_b := Vector2(-W, H) * 0.5

func _init() -> void:
	spec = JSON.parse_string(FileAccess.get_file_as_string(DESIGN + "/specs/painted_grass.json"))
	load_concept()
	var timings: Array = []
	for seed_value: int in SEEDS:
		for index in PARAMS.size():
			var started := Time.get_ticks_msec()
			var params := make_params(seed_value, PARAMS[index])
			patch(params).save_png(OUT.path_join("seed%d_param%d.png" % [seed_value, index]))
			timings.append(Time.get_ticks_msec() - started)
	var block := block_image(make_params(42, PARAMS[0]))
	block.save_png(OUT.path_join("block_default.png"))
	print("PAINTED PROTOTYPE DONE; ms per 5x5 patch (2 variants + faces): ", timings)
	quit()

# Concept sheet --------------------------------------------------------------

func load_concept() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DESIGN + "/concepts/export/painted_grass.json"))
	var palette := Image.load_from_file(ProjectSettings.globalize_path(DESIGN + "/concepts/export/painted_grass_palette.png"))
	var strokes := Image.load_from_file(ProjectSettings.globalize_path(DESIGN + "/concepts/export/painted_grass_brushes.png"))
	palette.convert(Image.FORMAT_RGBA8)
	strokes.convert(Image.FORMAT_RGBA8)
	for item: Dictionary in data.meta.slices:
		var b: Dictionary = item["keys"][0]["bounds"]
		var rect := Rect2i(int(b.x), int(b.y), int(b.w), int(b.h))
		var name: String = item["name"]
		if name.begins_with("ramp/"):
			var colors := PackedColorArray()
			for i in rect.size.x / rect.size.y:
				colors.append(palette.get_pixel(rect.position.x + i * rect.size.y + rect.size.y / 2, rect.position.y + rect.size.y / 2))
			ramps[name.trim_prefix("ramp/")] = colors
		elif name.begins_with("accent/"):
			accents.append(palette.get_pixelv(rect.get_center()))
		elif name.begins_with("brush/"):
			brushes[name] = strokes.get_region(rect)

func make_params(seed_value: int, preset: Array) -> Dictionary:
	var top: PackedColorArray = ramps.top
	if not String(preset[3]).is_empty():
		top = recolor(top, Color(preset[3]), Color(preset[4]))
	return {"seed": seed_value, "grain": preset[1], "stroke_scale": preset[2], "top": top, "soil": ramps.soil, "stone": ramps.stone}

## Moves a concept ramp so its anchor steps land on the user's colours, keeping the
## artist's hue shifts between steps.
func recolor(ramp: PackedColorArray, base: Color, light: Color) -> PackedColorArray:
	var anchors: Array = spec.palette.top.anchor_steps
	var a: Color = ramp[int(anchors[0])]
	var b: Color = ramp[int(anchors[1])]
	var result := PackedColorArray()
	for i in ramp.size():
		var weight := clampf((i - float(anchors[0])) / (float(anchors[1]) - float(anchors[0])), 0.0, 1.0)
		var source := a.lerp(b, weight)
		var target := base.lerp(light, weight)
		var c := ramp[i]
		result.append(Color.from_hsv(fposmod(c.h + target.h - source.h, 1.0), clampf(c.s * target.s / maxf(source.s, 0.01), 0, 1), clampf(c.v * target.v / maxf(source.v, 0.01), 0, 1)))
	return result

# Drawing primitives -----------------------------------------------------------

func tone(ramp: PackedColorArray, value: float) -> Color:
	var t := clampf(value, 0.0, ramp.size() - 1.0)
	var i := mini(floori(t), ramp.size() - 2)
	return ramp[i].lerp(ramp[i + 1], t - i)

func jitter(color: Color, rng: RandomNumberGenerator) -> Color:
	var j: Dictionary = spec.palette.jitter
	return Color.from_hsv(fposmod(color.h + rng.randf_range(-1, 1) * float(j.hue), 1.0), color.s, clampf(color.v * (1.0 + rng.randf_range(-1, 1) * float(j.value)), 0, 1))

func stream(seed_value: int, name: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 92821 + int(spec.random.streams[name])
	return rng

func lattice(point: Vector2) -> Vector2:
	var det := basis_a.cross(basis_b)
	return Vector2(point.cross(basis_b) / det, basis_a.cross(point) / det)

## Rotated, scaled brush alpha blended over pixels that are already covered.
func stamp(image: Image, brush: Image, center: Vector2, size: float, degrees: float, color: Color, opacity: float) -> void:
	var bw := brush.get_width()
	var bh := brush.get_height()
	var scale := size / maxf(bw, bh)
	var reach := Vector2(bw, bh).length() * 0.5 * scale + 1.0
	var c := cos(deg_to_rad(-degrees))
	var s := sin(deg_to_rad(-degrees))
	for y in range(maxi(0, floori(center.y - reach)), mini(image.get_height(), ceili(center.y + reach))):
		for x in range(maxi(0, floori(center.x - reach)), mini(image.get_width(), ceili(center.x + reach))):
			var d := Vector2(x + 0.5, y + 0.5) - center
			var local := Vector2(d.x * c - d.y * s, d.x * s + d.y * c) / scale + Vector2(bw, bh) * 0.5
			if local.x < 0 or local.y < 0 or local.x >= bw - 1 or local.y >= bh - 1:
				continue
			var fx := local.x - floorf(local.x)
			var fy := local.y - floorf(local.y)
			var ix := floori(local.x)
			var iy := floori(local.y)
			var alpha := lerpf(lerpf(brush.get_pixel(ix, iy).a, brush.get_pixel(ix + 1, iy).a, fx), lerpf(brush.get_pixel(ix, iy + 1).a, brush.get_pixel(ix + 1, iy + 1).a, fx), fy)
			if alpha < 0.01:
				continue
			var dst := image.get_pixel(x, y)
			if dst.a == 0.0:
				continue
			var mixed := dst.lerp(color, alpha * opacity)
			mixed.a = dst.a
			image.set_pixel(x, y, mixed)

# Top surface ------------------------------------------------------------------

func wash_value(st: Vector2, seed_value: int) -> float:
	var w: Dictionary = spec.top.wash
	return MapPixelArt._noise(st, int(w.octaves[0]), seed_value) * float(w.weights[0]) + MapPixelArt._noise(st, int(w.octaves[1]), seed_value + 31) * float(w.weights[1])

func top_image(params: Dictionary, variant: int) -> Image:
	var image := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var cover: PackedVector2Array = Geometry2D.offset_polygon(polygon, 1.0, Geometry2D.JOIN_MITER)[0]
	var wash: Dictionary = spec.top.wash
	var low := float(wash.tone_range[0])
	var high := float(wash.tone_range[1])
	var levels := float(wash.posterize)
	for y in H:
		for x in W:
			var point := Vector2(x + 0.5, y + 0.5) - Vector2(W, H) * 0.5
			if not Geometry2D.is_point_in_polygon(point, cover):
				continue
			var n: float = wash_value(lattice(point), params.seed)
			# Gouache wash: flat value steps with softened borders, plus faint paper grain.
			var stepped := floorf(n * levels) / (levels - 1.0)
			var t := lerpf(stepped, n, float(wash.soften))
			var color := tone(params.top, lerpf(low, high, t))
			color = color.lightened((MapTextureFactory._hash(x, y, params.seed) - 0.5) * 0.03)
			image.set_pixel(x, y, color)
	var density: float = params.grain / 0.6
	for layer: Dictionary in spec.top.strokes:
		var shared: bool = layer.placement == "shared"
		var rng := stream(params.seed + (0 if shared else 7919 * (variant + 1)), "strokes_shared" if shared else "strokes_variant")
		rng.seed += hash(layer.name)
		var count: int = roundi(rng.randi_range(int(layer.per_tile[0]), int(layer.per_tile[1])) * density)
		for i in count:
			var st := Vector2(rng.randf(), rng.randf())
			if layer.get("prefer", "") == "wash_low" and wash_value(st, params.seed) > 0.5:
				st = Vector2(rng.randf(), rng.randf())
			var size: float = rng.randf_range(float(layer.size[0]), float(layer.size[1])) * params.stroke_scale
			var degrees: float = rng.randf_range(float(layer.angle[0]), float(layer.angle[1])) if layer.has("angle") else 0.0
			var opacity := rng.randf_range(float(layer.opacity[0]), float(layer.opacity[1]))
			var color: Color
			if layer.has("accent"):
				color = accents[rng.randi() % accents.size()]
			else:
				color = jitter(tone(params.top, rng.randf_range(float(layer.tone[0]), float(layer.tone[1]))), rng)
			var offset: Vector2 = Vector2(layer.light_offset[0], layer.light_offset[1]) if layer.has("light_offset") else Vector2.ZERO
			var brush: Image = brushes[layer.brush]
			# A cluster fans several blades from one root, like a hand-painted tuft.
			var blades: int = rng.randi_range(int(layer.cluster[0]), int(layer.cluster[1])) if layer.has("cluster") else 1
			var fan: float = float(layer.get("fan", 0.0))
			for blade in blades:
				var spread := (blade - (blades - 1) * 0.5) / maxf(1.0, blades - 1.0)
				var blade_offset := offset + Vector2(spread * size * 0.45, absf(spread) * size * 0.12)
				var blade_color := color if blade == 0 else jitter(color, rng)
				_place(image, brush, st, shared, blade_offset, size * (1.0 - absf(spread) * 0.25), degrees + spread * fan, blade_color, opacity)
	return image

func _place(image: Image, brush: Image, st: Vector2, shared: bool, offset: Vector2, size: float, degrees: float, color: Color, opacity: float) -> void:
	if shared:
		# Periodic on the tile lattice: every translate that touches the tile.
		for j in range(-1, 2):
			for k in range(-1, 2):
				var center := basis_a * (st.x + j) + basis_b * (st.y + k) + Vector2(W, H) * 0.5 + offset
				if Rect2(Vector2.ZERO, Vector2(W, H)).grow(size).has_point(center):
					stamp(image, brush, center, size, degrees, color, opacity)
		return
	var center := basis_a * st.x + basis_b * st.y + Vector2(W, H) * 0.5 + offset
	# Variant strokes stay clear of the outline so neighbours still match.
	var inset: Array = Geometry2D.offset_polygon(polygon, -size * 0.6, Geometry2D.JOIN_MITER)
	if not inset.is_empty() and Geometry2D.is_point_in_polygon(center - Vector2(W, H) * 0.5, inset[0]):
		stamp(image, brush, center, size, degrees, color, opacity)

## Exposed edges: light flicks catching the sun at the front, a soft shade at the back.
func add_rims(image: Image, params: Dictionary, exposed: Array) -> void:
	var rim: Dictionary = spec.edges.rim
	var rng := stream(params.seed, "rim")
	for edge in 4:
		if not exposed[edge]:
			continue
		var a := polygon[edge]
		var b := polygon[(edge + 1) % 4]
		var rear: bool = a.y + b.y < 0
		var inward := (Vector2.ZERO - (a + b) * 0.5).normalized()
		if rear:
			for y in H:
				for x in W:
					var point := Vector2(x + 0.5, y + 0.5) - Vector2(W, H) * 0.5
					var distance := Geometry2D.get_closest_point_to_segment(point, a, b).distance_to(point)
					var c := image.get_pixel(x, y)
					if c.a > 0 and distance < float(rim.rear.width_px):
						image.set_pixel(x, y, Color(c.lerp(params.top[0], float(rim.rear.opacity) * (1.0 - distance / float(rim.rear.width_px))), c.a))
			continue
		var length := a.distance_to(b)
		var spacing := float(rim.front.spacing_px)
		for i in int(length / spacing):
			var center := a.lerp(b, (i + rng.randf()) * spacing / length) + inward * 2.5 + Vector2(W, H) * 0.5
			stamp(image, brushes[rim.front.brush], center, rng.randf_range(6, 9) * params.stroke_scale, rng.randf_range(-15, 15), jitter(tone(params.top, float(rim.front.tone)), rng), float(rim.front.opacity))

# Cliff faces ------------------------------------------------------------------

## A face painted flat (width = half a tile, periodic in x), sheared onto the slope later.
func face_strip(params: Dictionary, depth: int) -> Image:
	var side: Dictionary = spec.side
	var width := W / 2
	var strip := Image.create(width, depth, false, Image.FORMAT_RGBA8)
	for y in depth:
		for x in width:
			var n: float = MapPixelArt._noise(Vector2(float(x) / width, y / 64.0), 3, params.seed + 3701)
			var t := lerpf(float(side.wash.tone_top), float(side.wash.tone_bottom), float(y) / depth) + (n - 0.5) * 1.4 * float(side.wash.banding) * 4.0
			strip.set_pixel(x, y, tone(params.soil, t))
	var rng := stream(params.seed, "side")
	var lip_depth: float = side.lip.depth_px[1]
	var strata: Dictionary = side.strata
	for i in rng.randi_range(int(strata.per_face[0]), int(strata.per_face[1])):
		var x := rng.randf() * width
		var y := rng.randf_range(lip_depth, depth)
		var size := rng.randf_range(float(strata.size[0]), float(strata.size[1]))
		var color := jitter(tone(params.soil, rng.randf_range(float(strata.tone[0]), float(strata.tone[1]))), rng)
		var opacity := rng.randf_range(float(strata.opacity[0]), float(strata.opacity[1]))
		for k in [-1, 0, 1]:
			stamp(strip, brushes[strata.brush], Vector2(x + k * width, y), size, rng.randf_range(-3, 3), color, opacity)
	var stones: Dictionary = side.stones
	for i in roundi(rng.randi_range(int(stones.per_face[0]), int(stones.per_face[1])) * params.grain / 0.6):
		var center := Vector2(rng.randf() * width, rng.randf_range(lip_depth + 4, depth - 4))
		var size := rng.randf_range(float(stones.size[0]), float(stones.size[1]))
		for k in [-1, 0, 1]:
			var at := center + Vector2(k * width, 0)
			stamp(strip, brushes[stones.brush], at + Vector2(1, 2), size * 1.08, 0, tone(params.soil, 0.2), 0.55)
			stamp(strip, brushes[stones.brush], at, size, rng.randf_range(-8, 8), tone(params.stone, 1.0), 1.0)
			stamp(strip, brushes[stones.brush], at + Vector2(-2, -2), size * 0.62, 0, tone(params.stone, 2.4), 0.8)
			stamp(strip, brushes["brush/flick"], at + Vector2(-size * 0.2, -size * 0.18), size * 0.35, 70, tone(params.stone, 3.0), 0.7)
	for i in rng.randi_range(int(side.roots.per_face[0]), int(side.roots.per_face[1])):
		var x := rng.randf() * width
		var phase := rng.randf() * TAU
		for y in range(int(lip_depth) - 2, int(lip_depth) + rng.randi_range(8, 16)):
			for k in [-1, 0, 1]:
				stamp(strip, brushes["brush/dot"], Vector2(x + sin(y * 0.35 + phase) * 1.6 + k * width, y), 2.2, 0, tone(params.soil, float(side.roots.tone)), 0.75)
	# Turf lip: soft shade under the overhang, then hanging blades over it.
	var lip: Dictionary = side.lip
	for y in int(lip_depth) + 4:
		for x in width:
			var c := strip.get_pixel(x, y)
			strip.set_pixel(x, y, c.lerp(tone(params.soil, 0.0), float(lip.shadow) * (1.0 - y / (lip_depth + 4.0))))
	for x in width:
		var band := float(lip.band_px) * (0.7 + 0.6 * MapPixelArt._noise(Vector2(float(x) / width, 0.0), 8, params.seed + 5))
		for y in ceili(band):
			strip.set_pixel(x, y, tone(params.top, 2.0 + MapPixelArt._noise(Vector2(float(x) / width, 0.0), 6, params.seed) * 0.9 - y * 0.12))
	var count := roundi(width * float(lip.per_px))
	for i in count:
		var x := (i + rng.randf()) * width / count
		var length := rng.randf_range(float(lip.depth_px[0]), float(lip.depth_px[1]))
		var color := jitter(tone(params.top, rng.randf_range(float(lip.tone[0]), float(lip.tone[1]))), rng)
		for k in [-1, 0, 1]:
			stamp(strip, brushes[lip.brush], Vector2(x + k * width, length * 0.45), length, 180 + rng.randf_range(-12, 12), color, 0.95)
	return strip

## Shear the flat strip onto a front edge from `a` to `b` (tile-local, b.x < a.x).
func draw_face(target: Image, strip: Image, origin: Vector2, a: Vector2, b: Vector2, darken: float) -> void:
	var left := minf(a.x, b.x)
	for column in strip.get_width():
		var x := left + column + 0.5
		var edge := lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
		for row in strip.get_height():
			var c := strip.get_pixel(column, row)
			if darken > 0.0:
				c = c.darkened(darken)
			var pixel := Vector2i(origin + Vector2(x, edge + row))
			if Rect2i(Vector2i.ZERO, target.get_size()).has_point(pixel):
				target.set_pixelv(pixel, c)

# Scenes -----------------------------------------------------------------------

func block_image(params: Dictionary) -> Image:
	var depth := 48
	var image := Image.create(W + 8, H + depth + 8, false, Image.FORMAT_RGBA8)
	var origin := Vector2(W, H) * 0.5 + Vector2(4, 4)
	var strip := face_strip(params, depth)
	draw_face(image, strip, origin, polygon[2], polygon[3], 0.0)
	draw_face(image, strip, origin, polygon[1], polygon[2], float(spec.side.shading.right_face_darken))
	var top := top_image(params, 0)
	add_rims(top, params, [true, true, true, true])
	image.blend_rect(top, Rect2i(Vector2i.ZERO, top.get_size()), Vector2i(4, 4))
	return image

## Same 5×5 layout as the pixel example: a raised 3×3 meadow on a one-level base.
func patch(params: Dictionary) -> Image:
	var size := 5
	var step := 20
	var base := 36
	var tops := [top_image(params, 0), top_image(params, 1)]
	var strips := {}
	var image := Image.create(size * W + 16, size * H + 2 * step + base + 24, false, Image.FORMAT_RGBA8)
	var origin := Vector2(image.get_width() * 0.5, H * 0.5 + 2 * step + 8)
	var cells: Array[Vector2i] = []
	for y in size:
		for x in size:
			cells.append(Vector2i(x, y))
	cells.sort_custom(func(p: Vector2i, q: Vector2i) -> bool: return p.x + p.y < q.x + q.y)
	var elevation := func(c: Vector2i) -> int:
		if c.x < 0 or c.y < 0 or c.x >= size or c.y >= size:
			return -1
		return 2 if c.x >= 1 and c.x <= 3 and c.y >= 1 and c.y <= 3 else 1
	# Edge order matches the polygon: rear-right (0,-1), front-right (1,0), front-left (0,1), rear-left (-1,0).
	var neighbours := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for cell in cells:
		var level: int = elevation.call(cell)
		var center := origin + Vector2((cell.x - cell.y) * W * 0.5, (cell.x + cell.y) * H * 0.5 - level * step)
		for edge in [1, 2]:
			var below: int = elevation.call(cell + neighbours[edge])
			var depth := (level - below) * step if below >= 0 else level * step + base
			if depth <= 0:
				continue
			if not strips.has(depth):
				strips[depth] = face_strip(params, depth)
			draw_face(image, strips[depth], center, polygon[edge], polygon[(edge + 1) % 4], float(spec.side.shading.right_face_darken) if edge == 1 else 0.0)
		var variant := int(MapTextureFactory._hash(cell.x, cell.y, params.seed) * 2.0)
		var top: Image = tops[variant].duplicate()
		var exposed := []
		for edge in 4:
			exposed.append(elevation.call(cell + neighbours[edge]) != level)
		add_rims(top, params, exposed)
		image.blend_rect(top, Rect2i(Vector2i.ZERO, top.get_size()), Vector2i(center - Vector2(W, H) * 0.5))
	return image
