extends SceneTree
## Spec-driven terrain art: TerrainArtSpec + Aseprite concept data → pixel grass.

var checks := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func run() -> void:
	var spec := MapPixelArt.GRASS_SPEC
	check(spec != null and spec.validate().is_empty(), "Pixel grass spec validates: " + (spec.validate() if spec != null else "missing"))
	check(spec.concept != null and spec.concept.ramps.has("top") and spec.concept.source_hash.length() == 64, "Concept data imported from Aseprite")
	for layer in spec.motif_layers:
		check(spec.concept.motifs.has(layer.group) and not spec.concept.motifs[layer.group].is_empty(), "Concept has motif group " + layer.group)
		check(spec.concept.motif_ramps.get(layer.group, "") == "top", "Motifs map back to the top ramp: " + layer.group)
	check(TerrainArtSpec.new().validate().is_empty(), "Built-in default spec validates")
	var changed := spec.duplicate() as TerrainArtSpec
	changed.light_above += 0.01
	check(changed.fingerprint() != spec.fingerprint(), "Spec edits change the atlas fingerprint")
	var broken := spec.duplicate() as TerrainArtSpec
	broken.variant_order = PackedInt32Array([0, 0, 1, 2])
	check(not broken.validate().is_empty(), "Invalid variant order is rejected")
	var recipe := TextureRecipe.block_preset(0, MapProfile.Style.PIXEL)
	# Quantise through an Image, exactly as the renderer stores colours.
	var allowed := {}
	var probe := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	for color in Array(MapPixelArt.ramp(recipe.base_color, recipe.detail_color)) + spec.concept.accents.values():
		probe.set_pixel(0, 0, color)
		allowed[probe.get_pixel(0, 0).to_html()] = true
	for shape in 3:
		var p := MapProfile.new()
		p.grid = MapProfile.Grid.SQUARE if shape == 0 else MapProfile.Grid.HEX
		p.hex_orientation = MapProfile.HexOrientation.POINTY if shape == 1 else MapProfile.HexOrientation.FLAT
		recipe.resolution = p.tile_size
		var bases: Array[Image] = []
		var foreign := 0
		for variant in MapPixelArt.MOODS * 4:
			var layers := MapPixelArt.top_layers(p, recipe, variant)
			var base: Image = layers.base
			bases.append(base)
			for y in base.get_height():
				for x in base.get_width():
					var c := base.get_pixel(x, y)
					if c.a > 0.0 and not allowed.has(c.to_html()):
						foreign += 1
		check(foreign == 0, "Grass colours come only from the ramp and concept accents (shape %d)" % shape)
		check(bases[5].get_data() == MapPixelArt.top_layers(p, recipe, 5).base.get_data(), "Grass variant drawing is deterministic (shape %d)" % shape)
		check(bases[0].get_data() != bases[1].get_data() and bases[1].get_data() != bases[5].get_data(), "Moods and interior sub-variants differ (shape %d)" % shape)
		var mismatched := 0
		var compared := 0
		for direction: Vector2i in MapGrid.directions(p.grid):
			var offset := Vector2i((MapGrid.cell_to_local(direction, p) - MapGrid.cell_to_local(Vector2i.ZERO, p)).round())
			for pair: Vector2i in [Vector2i(0, 0), Vector2i(0, 7), Vector2i(3, 9), Vector2i(14, 2), Vector2i(6, 11)]:
				var a := bases[pair.x]
				var b := bases[pair.y]
				for y in a.get_height():
					for x in a.get_width():
						var other := Vector2i(x, y) - offset
						if other.x < 0 or other.y < 0 or other.x >= b.get_width() or other.y >= b.get_height():
							continue
						if a.get_pixel(x, y).a == 0.0 or b.get_pixelv(other).a == 0.0:
							continue
						compared += 1
						if a.get_pixel(x, y) != b.get_pixelv(other):
							mismatched += 1
		check(compared > 0 and mismatched == 0, "Any two grass variants meet without a seam (shape %d: %d of %d overlap pixels differ)" % [shape, mismatched, compared])
	# Region selection groups moods; without regions it falls back to per-cell picks.
	var same := 0
	var total := 0
	var seen := {}
	for y in 40:
		for x in 40:
			var mood := MapRenderer.pick_variant(spec, Vector2i(x, y), 77, MapPixelArt.MOODS)
			seen[mood] = true
			if x > 0:
				total += 1
				same += int(mood == MapRenderer.pick_variant(spec, Vector2i(x - 1, y), 77, MapPixelArt.MOODS))
	check(seen.size() == MapPixelArt.MOODS, "Every mood appears on a 40×40 map")
	check(float(same) / total > 0.4, "Neighbouring cells usually share a mood (%.2f)" % (float(same) / total))
	check(MapRenderer.pick_variant(spec, Vector2i(9, 4), 77, 4) == MapRenderer.pick_variant(spec, Vector2i(9, 4), 77, 4), "Mood choice is deterministic")
	check(MapRenderer.pick_variant(null, Vector2i(9, 4), 77, 2) == mini(1, int(MapGenerator.random_at(77, Vector2i(9, 4), 71) * 2)), "Specless terrains keep per-cell variants")
	# Atlas layout: interior sub-variants exist and only fully surrounded cells use them.
	var p := MapProfile.new()
	p.width = 10
	p.height = 10
	var data := MapData.new()
	data.initialize(p)
	for i in data.terrain.size():
		data.terrain[i] = MapData.Terrain.GRASS
	data.terrain[data.index_of(Vector2i(5, 5))] = MapData.Terrain.SAND
	var images := MapAtlasBuilder.prepare_images(p, null, MapGenerationJob.new())
	check(images.variants == MapPixelArt.MOODS and images.interior_variants == 4, "Pixel atlas has four moods with four interior sub-variants")
	var atlas := images.duplicate()
	atlas["tileset"] = MapAtlasBuilder.create_tileset(images, p)
	var renderer := MapRenderer.new()
	root.add_child(renderer)
	renderer.setup(data, atlas, null)
	for i in data.terrain.size():
		renderer.update_cell(data.cell_at(i))
	check(renderer.error.is_empty(), "Grass map renders with the spec")
	var source := renderer.tile_set.get_source(0) as TileSetAtlasSource
	var interior_used := false
	var misplaced := false
	for coords in renderer.layers.top_0.get_used_cells():
		var atlas_coords: Vector2i = renderer.layers.top_0.get_cell_atlas_coords(coords)
		check(source.has_tile(atlas_coords), "Top tile exists in the atlas")
		if atlas_coords.y >= images.masks:
			interior_used = true
			var cell := MapGrid.from_offset(coords, p)
			misplaced = misplaced or renderer.neighbor_mask(cell) != images.masks - 1
	check(interior_used and not misplaced, "Interior sub-variants appear only on fully surrounded cells")
	renderer.free()
	print("ART SPEC TESTS: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
