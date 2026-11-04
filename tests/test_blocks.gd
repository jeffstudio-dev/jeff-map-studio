extends SceneTree

var checks: int = 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: ", message)

func idle(map: JeffMap2D) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while map.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not map.busy, "Block rendering completes")

func run() -> void:
	var map := JeffMap2D.new()
	root.add_child(map)
	for shape in 3:
		var p := MapProfile.new()
		p.width = 8
		p.height = 8
		p.grid = 0 if shape == 0 else 1
		p.hex_orientation = 1 if shape == 2 else 0
		p.base_thickness = 24
		var data := MapData.new()
		data.initialize(p)
		var cell := Vector2i(3, 3)
		data.terrain[data.index_of(cell)] = MapData.Terrain.GRASS
		var hash_before := data.content_hash()
		map.apply_data(data)
		await idle(map)
		check(map.renderer.layers.base_side.get_used_cells().size() == 1, "Height-zero block has a base")
		var point := map.cell_to_local(cell) + Vector2(2, MapGrid.tile_dimensions(p).y * 0.5 + p.base_thickness * 0.5)
		check(map.local_to_cell(point) == cell, "Base side picking shape %d" % shape)
		var changed := data.copy()
		changed.profile.base_thickness = 48
		map.apply_data(changed)
		await idle(map)
		check(map.map_data.content_hash() == hash_before, "Changing base depth preserves structural data")
		var flat := changed.copy()
		flat.profile.projection = MapProfile.ProjectionMode.TOP_DOWN
		map.apply_data(flat)
		await idle(map)
		check(not map.renderer.layers.has("base_side"), "Top-down display hides the base")
		var filled := MapData.new()
		filled.initialize(p, MapData.Terrain.GRASS)
		map.apply_data(filled)
		await idle(map)
		check(map.renderer.layers.base_side.get_cell_source_id(MapGrid.to_offset(cell, p)) == -1, "Interior base faces are hidden")
		var front: Vector2i = MapGrid.directions(p.grid)[map.renderer.front_dirs[0]]
		filled.terrain[filled.index_of(cell + front)] = -1
		map.map_data.terrain[map.map_data.index_of(cell + front)] = -1
		map.refresh_cells([cell + front])
		check(map.renderer.layers.base_side.get_cell_source_id(MapGrid.to_offset(cell, p)) != -1, "Erasing a neighbor reveals the base")
		check(map.save_map("user://block_map.tres") == OK, "Save map with base")
		var restored := ResourceLoader.load("user://block_map.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as MapData
		check(restored.profile.base_thickness == 24, "Base depth survives persistence")
	map.queue_free()
	for shape in 3:
		for height in [0, 1, 16]:
			var narrow := MapProfile.new()
			narrow.width = 8
			narrow.height = 8
			narrow.tile_size = 16
			narrow.height_step = 32
			narrow.base_thickness = 2
			narrow.grid = 0 if shape == 0 else 1
			narrow.hex_orientation = 1 if shape == 2 else 0
			var single := MapData.new()
			single.initialize(narrow)
			var cell := Vector2i(3, 3)
			single.terrain[single.index_of(cell)] = MapData.Terrain.GRASS
			single.elevation[single.index_of(cell)] = height
			var top := MapGrid.cell_to_local(cell, narrow, height)
			var point := top + Vector2(0, MapGrid.tile_dimensions(narrow).y * 0.5 + (height * narrow.height_step + narrow.base_thickness) * 0.5)
			check(MapGrid.pick_cell(point, single) == cell, "Tall narrow block side pick: shape=%d height=%d" % [shape, height])
	for material in 4:
		var recipe := TextureRecipe.block_preset(material)
		for shape in 3:
			var image := MapBlockSurface.thumbnail(recipe, shape, 36)
			check(image.get_data() == MapBlockSurface.thumbnail(recipe, shape, 36).get_data(), "Single block output is deterministic")
			check(image.get_pixel(0, 0).a == 0.0, "Single block has a genuine transparent margin")
			var point := Vector2i(image.get_width() / 2 + 4, image.get_height() - 16)
			check(image.get_pixelv(point).a > 0.9, "Single block side has opaque coverage")
	var profile := MapProfile.new()
	var library := TileLibrary.new()
	library.recipes.append(TextureRecipe.block_preset(0))
	var first_key := MapAtlasBuilder.cache_key(profile, library)
	library.recipes[0].side_color = Color.RED
	check(first_key != MapAtlasBuilder.cache_key(profile, library), "Side colors invalidate atlas cache")
	var scene := load("res://demo/studio.tscn").instantiate() as Control
	root.add_child(scene)
	var panel := scene.get_node("Margin/Studio") as MapStudioPanel
	panel._tabs.current_tab = 1
	panel.texture_workbench.recipe = TextureRecipe.block_preset(1)
	panel.texture_workbench._sync_recipe()
	var deadline := Time.get_ticks_msec() + 30000
	while (panel.texture_workbench._dirty or panel.texture_workbench._thread != null) and Time.get_ticks_msec() < deadline:
		await process_frame
	check(panel.texture_workbench._block_preview.textures.size() == 3, "Workbench renders three block shapes")
	panel.texture_workbench._save_block("user://single_block_export.png")
	var exported := Image.load_from_file(ProjectSettings.globalize_path("user://single_block_export.png"))
	check(exported != null and exported.get_pixel(0, 0).a == 0, "Workbench exports current block with transparency")
	await idle(panel.canvas.map)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://test_output/block_workbench.png")
	var before_recipe := panel.texture_workbench.recipe
	var messages: Array[String] = []
	panel.texture_workbench.status_message.connect(func(message: String) -> void: messages.append(message))
	var invalid := TextureRecipe.new()
	invalid.resolution = 1
	ResourceSaver.save(invalid, "user://invalid_block_recipe.tres")
	panel.texture_workbench._load_recipe("user://invalid_block_recipe.tres")
	check(panel.texture_workbench.recipe == before_recipe, "Invalid imported recipe preserves current block")
	check(not messages.is_empty() and messages[-1].contains("尺寸"), "Invalid imported recipe provides a useful error")
	print("BLOCK TESTS: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
