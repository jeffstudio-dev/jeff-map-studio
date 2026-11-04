extends SceneTree

var failures: Array[String] = []
var checks: int = 0

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: ", message)

func run() -> void:
	var p := MapProfile.new()
	p.width = 8
	p.height = 8
	p.projection = MapProfile.ProjectionMode.TOP_DOWN
	var image := Image.create(130, 130, false, Image.FORMAT_RGBA8)
	image.fill(Color("93bb8f"))
	var library := TileLibrary.import_atlas(ImageTexture.create_from_image(image), Vector2i(64, 64), Vector2i.ZERO, Vector2i.ONE * 2, p)
	check(library != null and library.tile_set.get_source(0).get_tiles_count() == 4, "PNG atlas region/separation")
	var data := MapData.new()
	data.initialize(p, MapData.Terrain.GRASS)
	check(not library.validate_for(data).is_empty(), "Unbound atlas has actionable validation")
	var fallback := MapTileRule.new()
	fallback.terrain = MapData.Terrain.GRASS
	library.rules.append(fallback)
	check(library.validate_for(data).is_empty(), "Mapped atlas validates")
	var exact := fallback.duplicate(true) as MapTileRule
	exact.neighbor_mask = 15
	exact.atlas_coords = Vector2i(1, 0)
	library.rules.append(exact)
	check(library.pick(2, 0, 15, 0, 2, Vector2i(1, 1)) == exact, "Specific mask wins")
	check(library.pick(2, 0, 3, 0, 2, Vector2i(1, 1)) == fallback, "Wildcard fallback")
	var variant := exact.duplicate(true) as MapTileRule
	variant.atlas_coords = Vector2i(0, 1)
	variant.weight = 3
	library.rules.append(variant)
	var selection: Array[String] = []
	for i in 100:
		selection.append(library.pick(2, 0, 15, 0, 3, Vector2i(i, 1)).sort_key())
	library.rules.reverse()
	for i in 100:
		check(library.pick(2, 0, 15, 0, 3, Vector2i(i, 1)).sort_key() == selection[i], "Rule order does not change seeded variants")
	# Read native terrain peering bits and probabilities, including alternatives.
	var tiles := library.tile_set
	tiles.add_terrain_set()
	tiles.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_SIDES)
	for _i in 3:
		tiles.add_terrain(0)
	var source := tiles.get_source(0) as TileSetAtlasSource
	var native := source.get_tile_data(Vector2i.ZERO, 0)
	native.terrain_set = 0
	native.terrain = 2
	native.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_RIGHT_SIDE, 2)
	native.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, 2)
	native.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_LEFT_SIDE, 2)
	native.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_TOP_SIDE, 2)
	var native_library := TileLibrary.new()
	native_library.tile_set = tiles
	check(native_library.read_native_terrains(p) == 1, "Native terrain import")
	check(native_library.rules[0].neighbor_mask == 15, "Native neighbor bits mapped")
	# Exercise imported rendering and missing-pattern failure transactionally.
	var map := JeffMap2D.new()
	root.add_child(map)
	map.tile_library = library
	var failed_messages: Array[String] = []
	map.generation_failed.connect(func(message: String) -> void: failed_messages.append(message))
	map.apply_data(data)
	while map.busy:
		await process_frame
	check(map.map_data != null, "Imported atlas renders")
	check(map.renderer.tile_set.get_terrain_sets_count() == 1, "External TileSet retains native terrain definitions")
	var hash_before := map.map_data.content_hash()
	var incomplete := library.duplicate(true) as TileLibrary
	incomplete.rules = [exact]
	var next := data.copy()
	next.tile_library = incomplete
	map.apply_data(next)
	while map.busy:
		await process_frame
	check(not failed_messages.is_empty() and failed_messages[-1].contains("掩码"), "Missing pattern identifies cell and masks")
	check(map.map_data.content_hash() == hash_before, "Failed atlas application preserves map")
	check(map.tile_library == map.map_data.tile_library, "Failed application restores committed material library")
	map.apply_data(null)
	check(not map.busy and map.map_data.content_hash() == hash_before, "Null data reports failure without replacing the map")
	# Material recipe survives map persistence.
	data.tile_library = library
	check(ResourceSaver.save(data, "user://asset_map_test.tres") == OK, "Map and library save")
	var loaded := ResourceLoader.load("user://asset_map_test.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as MapData
	check(loaded != null and loaded.tile_library.rules.size() == 3, "Map restores library bindings")
	for name in ["square_iso_pixel", "square_top_soft", "hex_pointy_iso_soft", "hex_flat_top_pixel"]:
		var example_profile := load("res://addons/jeff_map_studio/examples/profiles/" + name + ".tres") as MapProfile
		example_profile = example_profile.copy()
		example_profile.width = 20
		example_profile.height = 20
		var example_data := MapGenerator.generate(example_profile)
		example_data.tile_library = load("res://addons/jeff_map_studio/examples/libraries/" + name + ".res") as TileLibrary
		map.apply_data(example_data)
		while map.busy:
			await process_frame
		check(map.map_data.content_hash() == example_data.content_hash(), "Prebound example library renders: " + name)
		check(map.renderer.error.is_empty(), "Prebound masks complete: " + name)
	print("ASSET TESTS: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
