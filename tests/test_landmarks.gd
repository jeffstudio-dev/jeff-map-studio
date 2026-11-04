extends SceneTree

var checks := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func idle(map: JeffMap2D) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while map.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not map.busy, "Landmark rendering completes")

func run() -> void:
	for style in 2:
		var recipe := TextureRecipe.block_preset(0, style)
		var artwork := MapTextureFactory.create(recipe)
		recipe.detail_color = Color("88ccec")
		check(artwork.get_data() != MapTextureFactory.create(recipe).get_data(), "Illustrated material responds to detail color")
		recipe.illustrated = false
		check(artwork.get_data() != MapTextureFactory.create(recipe).get_data(), "Procedural texture option remains available")
	for id in range(1, 7):
		var pixel := MapLandmarkArt.sprite(0, id, 128)
		var painted := MapLandmarkArt.sprite(1, id, 128)
		check(pixel.get_data() != painted.get_data(), "Each object has distinct pixel and painted art")
		for item: Image in [pixel, painted]:
			check(item.get_used_rect().has_area() and item.get_pixel(0, 0).a == 0, "Object has content and transparent gutters")
	var map := JeffMap2D.new()
	root.add_child(map)
	for shape in 3:
		var p := MapProfile.new()
		p.width = 8
		p.height = 8
		p.grid = 0 if shape == 0 else 1
		p.hex_orientation = 1 if shape == 2 else 0
		var data := MapData.new()
		data.initialize(p, MapData.Terrain.GRASS)
		for id in range(1, 7):
			var cell := Vector2i(id, 3)
			MapEdits.brush(data, cell, MapEdits.Tool.DECORATION, 0, 0, id)
			MapEdits.brush(data, cell, MapEdits.Tool.LOCK, 0, 0, 0)
			data.elevation[data.index_of(cell)] = id % 3
		check(data.validate().is_empty(), "All six decoration IDs are valid")
		var original := data.content_hash()
		for style in 2:
			data.profile.style = style
			map.apply_data(data)
			await idle(map)
			check(map.map_data.content_hash() == original, "Changing style retains placed items and edits")
			for id in range(1, 7):
				var layer: TileMapLayer = map.renderer.layers["decoration_%d" % (id % 3)]
				var coords := MapGrid.to_offset(Vector2i(id, 3), p)
				check(layer.get_cell_atlas_coords(coords) == Vector2i(id - 1, 0), "Height layer displays the selected landmark")
			var cliff_coords := MapGrid.to_offset(Vector2i(2, 3), p)
			for height in [1, 2]:
				var cliff: TileMapLayer = map.renderer.layers["side_%d" % height]
				var phase := cliff.get_cell_atlas_coords(cliff_coords).y / map.renderer.side_count
				check(phase == 2 - height, "Cliff samples advance vertically below the surface")
			check(map.save_map("user://landmark_map.tres") == OK, "Save decorated map")
			var loaded := ResourceLoader.load("user://landmark_map.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as MapData
			check(loaded != null and loaded.content_hash() == original and loaded.profile.style == style, "Reload retains style and all decorations")
		var regenerated := MapGenerator.generate(p, data)
		for id in range(1, 7):
			check(regenerated.get_cell(Vector2i(id, 3)) == data.get_cell(Vector2i(id, 3)), "Regeneration preserves locked landmarks")
		data.decoration[0] = 7
		check(not data.validate().is_empty(), "Unknown decoration ID reports validation error")
	map.queue_free()
	for grid in 2:
		var p := MapProfile.new()
		p.width = 48
		p.height = 48
		p.grid = grid
		p.decoration_density = 0.8
		var a := MapGenerator.generate(p)
		p.style = 1
		var b := MapGenerator.generate(p)
		check(a.content_hash() == b.content_hash(), "Style never changes generated terrain or object placement")
		var valid := true
		var seen: Dictionary = {}
		for i in a.decoration.size():
			var id := a.decoration[i]
			seen[id] = true
			match id:
				MapData.Decoration.TREE, MapData.Decoration.MUSHROOMS:
					valid = valid and a.terrain[i] == MapData.Terrain.GRASS
				MapData.Decoration.PALM:
					valid = valid and a.terrain[i] == MapData.Terrain.SAND
				MapData.Decoration.LIGHTHOUSE:
					var coastal := false
					for direction: Vector2i in MapGrid.directions(grid):
						var next := a.cell_at(i) + direction
						if a.contains(next) and a.terrain[a.index_of(next)] in [MapData.Terrain.SAND, MapData.Terrain.GRASS]:
							coastal = true
					valid = valid and coastal and a.terrain[i] == MapData.Terrain.WATER
		check(valid, "Natural landmarks respect terrain and coast adjacency")
		check(seen.has(4) and seen.has(5) and seen.has(6), "Natural generation includes mushrooms, palms and coastal lighthouses")
		p.decoration_density = 0.0
		var empty := MapGenerator.generate(p)
		check(empty.decoration.count(0) == empty.decoration.size(), "Zero density removes generated objects")
		check(a.terrain == empty.terrain and a.elevation == empty.elevation, "Object density leaves land structure unchanged")
	print("LANDMARK TESTS: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
