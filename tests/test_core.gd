extends SceneTree

var failures: Array[String] = []
var checks: int = 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func run() -> void:
	for grid in 2:
		for orientation in 2:
			for projection in 2:
				var p := MapProfile.new()
				p.grid = grid
				p.hex_orientation = orientation
				p.projection = projection
				var tiles := TileSet.new()
				MapAtlasBuilder.configure_tileset(tiles, p)
				var layer := TileMapLayer.new()
				layer.tile_set = tiles
				for cell in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(5, 7), Vector2i(-3, -5)]:
					var point := MapGrid.cell_to_local(cell, p)
					check(MapGrid.local_to_cell(point, p) == cell, "Grid roundtrip %s %s" % [p.grid, cell])
					check(MapGrid.from_offset(MapGrid.to_offset(cell, p), p) == cell, "Offset roundtrip")
					var native := layer.map_to_local(MapGrid.to_offset(cell, p)) - layer.map_to_local(Vector2i.ZERO)
					check(native.distance_to(point) < 0.01, "Native layout grid=%d orientation=%d projection=%d cell=%s native=%s expected=%s" % [grid, orientation, projection, cell, native, point])
				layer.free()
	for grid in 2:
		for generator in 3:
			for seed_value in range(12):
				var p := MapProfile.new()
				p.grid = grid
				p.generator = generator
				p.seed_value = seed_value
				p.width = 48
				p.height = 40
				p.room_count = 6
				p.room_min_size = 3
				p.room_max_size = 6
				var job := MapGenerationJob.new()
				var a := MapGenerator.generate(p, null, job)
				check(a != null, "Generation grid=%d kind=%d seed=%d %s" % [grid, generator, seed_value, job.error])
				if a == null:
					continue
				check(a.validate().is_empty(), "Generated data valid")
				var b := MapGenerator.generate(p)
				check(a.content_hash() == b.content_hash(), "Determinism")
				if generator != MapProfile.Generator.NATURE:
					check(MapGenerator.floor_regions(a).size() == 1, "Dungeon/cave connected")
				p.decoration_density = 0.7
				var decorated := MapGenerator.generate(p)
				check(a.terrain == decorated.terrain and a.elevation == decorated.elevation, "Decoration stream independent")
	var p := MapProfile.new()
	p.width = 32
	p.height = 32
	var a := MapGenerator.generate(p)
	var edited := Vector2i(4, 4)
	MapEdits.brush(a, edited, MapEdits.Tool.TERRAIN, MapData.Terrain.SNOW, 0, 0)
	MapEdits.brush(a, edited, MapEdits.Tool.LOCK, 0, 0, 0)
	a.elevation[a.index_of(edited)] = 12
	p.seed_value += 1
	var b := MapGenerator.generate(p, a)
	check(b.get_cell(edited) == a.get_cell(edited), "Locked edits preserved")
	var saved := "user://test_map.tres"
	check(ResourceSaver.save(b, saved) == OK, "Resource save")
	var loaded := ResourceLoader.load(saved, "", ResourceLoader.CACHE_MODE_IGNORE) as MapData
	check(loaded != null and loaded.content_hash() == b.content_hash(), "Resource reload")
	var invalid := p.copy()
	invalid.generator = MapProfile.Generator.DUNGEON
	invalid.width = 8
	invalid.height = 8
	invalid.room_count = 80
	var failed := MapGenerationJob.new()
	check(MapGenerator.generate(invalid, null, failed) == null and not failed.error.is_empty(), "Impossible configuration fails")
	var cancelled := MapGenerationJob.new()
	cancelled.cancel()
	check(MapGenerator.generate(p, null, cancelled) == null, "Cancellation")
	for style in 2:
		for material in 5:
			var recipe := TextureRecipe.preset(material, style)
			var image := MapTextureFactory.create(recipe)
			var image_again := MapTextureFactory.create(recipe)
			check(image.get_data() == image_again.get_data(), "Texture deterministic")
			var seamless := true
			for i in image.get_width():
				seamless = seamless and image.get_pixel(0, i) == image.get_pixel(image.get_width() - 1, i) and image.get_pixel(i, 0) == image.get_pixel(i, image.get_height() - 1)
			check(seamless, "Texture periodic border")
	print("CORE TESTS: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
