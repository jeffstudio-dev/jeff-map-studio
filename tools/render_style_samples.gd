extends "res://tools/render_map_samples.gd"

const STYLE_OUTPUT := "res://test_output/style_landmarks"
const EXAMPLES := "res://addons/jeff_map_studio/examples/styles"

func run() -> void:
	if DisplayServer.get_name() != "headless":
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STYLE_OUTPUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EXAMPLES))
	var hashes: Dictionary = {}
	var reports: Array = []
	for style in 2:
		var style_name := "pixel" if style == 0 else "painted"
		for shape in 3:
			var shape_name: String = ["square", "hex_pointy", "hex_flat"][shape]
			var name := style_name + "_" + shape_name
			var data := sample_data(shape)
			data.profile.style = style
			add_landmarks(data)
			if hashes.has(shape):
				check(data.content_hash() == hashes[shape], "Both styles retain the same terrain, heights and objects")
			else:
				hashes[shape] = data.content_hash()
			var images := MapAtlasBuilder.prepare_images(data.profile, data.tile_library, MapGenerationJob.new())
			var atlas := images.duplicate()
			atlas["tileset"] = MapAtlasBuilder.create_tileset(images, data.profile)
			var renderer := MapRenderer.new()
			root.add_child(renderer)
			renderer.setup(data, atlas, data.tile_library)
			for i in data.terrain.size():
				renderer.update_cell(data.cell_at(i))
			check(renderer.error.is_empty(), "Landmark layers render")
			var commands := draw_commands(renderer, images)
			var bounds := command_bounds(commands).grow(30)
			var render := composite(commands, bounds)
			with_background(render).save_png(STYLE_OUTPUT.path_join(name + ".png"))
			var sample_count := verify_shared_edges(data, render, bounds)
			check(ResourceSaver.save(data, EXAMPLES.path_join(name + ".tres")) == OK, "Style sample is editable")
			reports.append({"name": name, "hash": data.content_hash(), "edge_samples": sample_count, "decorations": count_objects(data)})
			renderer.free()
			print("EXPORTED: ", name)
		for material in 4:
			var recipe := TextureRecipe.block_preset(material, style)
			var prop: int = [MapData.Decoration.MUSHROOMS, MapData.Decoration.CRATE, MapData.Decoration.LIGHTHOUSE, MapData.Decoration.PALM][material]
			for shape in 3:
				var name := "%s_%s_%s_block" % [style_name, ["grass", "brick", "water", "sand"][material], ["square", "hex_pointy", "hex_flat"][shape]]
				var block := MapBlockSurface.thumbnail(recipe, shape, 64, 256, prop)
				block.save_png(STYLE_OUTPUT.path_join(name + ".png"))
				block.save_png(EXAMPLES.path_join(name + ".png"))
		var board := Image.create(960, 800, false, Image.FORMAT_RGBA8)
		board.fill(Color("e9eee5"))
		for row in 2:
			for column in 3:
				var material: int = [0, 3, 2][column]
				var prop: int = [MapData.Decoration.MUSHROOMS, MapData.Decoration.PALM, MapData.Decoration.LIGHTHOUSE][column]
				var block := MapBlockSurface.thumbnail(TextureRecipe.block_preset(material, style), row, 66, 256, prop)
				var position := Vector2i(column * 320 + (320 - block.get_width()) / 2, row * 400 + 365 - block.get_height())
				board.blend_rect(block, Rect2i(Vector2i.ZERO, block.get_size()), position)
		board.save_png(STYLE_OUTPUT.path_join(style_name + "_tile_board.png"))
	var report := {"checks": checks, "failures": failures, "mode": "headless_cpu_atlas_composite", "gpu_screenshot": false, "maps": reports}
	var file := FileAccess.open(STYLE_OUTPUT.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("STYLE PREVIEW TESTS: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func add_landmarks(data: MapData) -> void:
	var center := Vector2i(3, 3) if data.profile.grid == 0 else Vector2i(4, 4)
	place_nearest(data, MapData.Terrain.GRASS, MapData.Decoration.TREE, center + Vector2i(-1, -1))
	place_nearest(data, MapData.Terrain.GRASS, MapData.Decoration.MUSHROOMS, center + Vector2i(0, 1))
	place_nearest(data, MapData.Terrain.GRASS, MapData.Decoration.ROCK, center + Vector2i(1, -1))
	place_nearest(data, MapData.Terrain.GRASS, MapData.Decoration.CRATE, center + Vector2i(1, 0))
	place_nearest(data, MapData.Terrain.SAND, MapData.Decoration.PALM, center + Vector2i(1, 2))
	place_nearest(data, MapData.Terrain.SAND, MapData.Decoration.PALM, center + Vector2i(-2, 1))
	place_nearest(data, MapData.Terrain.WATER, MapData.Decoration.LIGHTHOUSE, center + Vector2i(3, 1))

func place_nearest(data: MapData, terrain: int, id: int, target: Vector2i) -> void:
	var best := -1
	var distance := INF
	for i in data.terrain.size():
		if data.terrain[i] != terrain or data.decoration[i] != 0:
			continue
		var next := Vector2(data.cell_at(i) - target).length_squared()
		if next < distance:
			distance = next
			best = i
	if best >= 0:
		data.decoration[best] = id

func count_objects(data: MapData) -> int:
	var count := 0
	for id in data.decoration:
		if id > 0:
			count += 1
	return count
