extends SceneTree
## Headless review of actual TileMapLayer selections, using CPU image compositing.
## This is not a GPU screenshot or a replacement for test_seams.gd.

const OUTPUT := "res://test_output/assembled_maps"
const BACKGROUND := Color("16232b")
var checks: int = 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: ", message)

func sample_data(shape: int) -> MapData:
	var p := MapProfile.new()
	p.width = 9 if shape > 0 else 8
	p.height = p.width
	p.tile_size = 128
	p.height_step = 20
	p.base_thickness = 28
	p.max_height = 4
	p.grid = MapProfile.Grid.SQUARE if shape == 0 else MapProfile.Grid.HEX
	p.hex_orientation = MapProfile.HexOrientation.POINTY if shape == 1 else MapProfile.HexOrientation.FLAT
	p.seed_value = 20261017
	var library := TileLibrary.new()
	library.display_name = "地块拼接观察 · 草地 / 沙地 / 水域"
	library.recipes.resize(8)
	library.recipes[MapData.Terrain.GRASS] = TextureRecipe.block_preset(0)
	library.recipes[MapData.Terrain.SAND] = TextureRecipe.block_preset(3)
	library.recipes[MapData.Terrain.WATER] = TextureRecipe.block_preset(2)
	var data := MapData.new()
	data.initialize(p)
	data.tile_library = library
	for i in data.terrain.size():
		var cell := data.cell_at(i)
		var position: Vector2
		if shape == 0:
			# Back-left plateau, beach and a low foreground lagoon.
			position = Vector2(cell.x - 3.0, cell.y - 3.0)
		else:
			var axial := cell - Vector2i(4, 4)
			if MapGrid.distance(axial, Vector2i.ZERO, p.grid) > 4:
				continue
			position = Vector2(axial.x + axial.y * 0.5, axial.y * 0.866)
		var distance := Vector2(position.x + 0.7, (position.y + 0.7) * 1.08).length()
		var land_limit := 2.9 + sin(position.y * 1.7) * 0.22
		if distance < 1.45:
			data.terrain[i] = MapData.Terrain.GRASS
			data.elevation[i] = 4 if position.y < 0.4 and position.x < 0.7 else 3
		elif distance < 2.15:
			data.terrain[i] = MapData.Terrain.GRASS
			data.elevation[i] = 2
		elif distance < land_limit:
			data.terrain[i] = MapData.Terrain.SAND
			data.elevation[i] = 1
		else:
			data.terrain[i] = MapData.Terrain.WATER
		data.manual[i] = 1
	data.metadata["purpose"] = "草地、沙岸、水域及 0–4 层落差的拼接观察"
	return data

func run() -> void:
	if DisplayServer.get_name() != "headless":
		printerr("This export must run with --headless; no graphical window is needed.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var results: Array = []
	for shape in 3:
		var name: String = ["square", "hex_pointy", "hex_flat"][shape]
		var data := sample_data(shape)
		check(data.validate().is_empty(), name + ": valid map")
		var images := MapAtlasBuilder.prepare_images(data.profile, data.tile_library, MapGenerationJob.new())
		var atlas := images.duplicate()
		atlas["tileset"] = MapAtlasBuilder.create_tileset(images, data.profile)
		var renderer := MapRenderer.new()
		root.add_child(renderer)
		renderer.setup(data, atlas, data.tile_library)
		for i in data.terrain.size():
			renderer.update_cell(data.cell_at(i))
		check(renderer.error.is_empty(), name + ": atlas selections")
		var counts := verify_faces(renderer)
		var commands := draw_commands(renderer, images)
		var bounds := command_bounds(commands).grow(36)
		var image := composite(commands, bounds)
		var seam_samples := verify_shared_edges(data, image, bounds)
		check(image.save_png(OUTPUT.path_join(name + "_alpha.png")) == OK, name + ": transparent map export")
		var preview := with_background(image)
		check(preview.save_png(OUTPUT.path_join(name + ".png")) == OK, name + ": map preview")
		# Select a front-facing grass / beach / water border from actual map data.
		var focus := shoreline_focus(data)
		var detail_bounds := Rect2i(Vector2i(focus) - Vector2i(270, 180), Vector2i(540, 360))
		var detail := with_background(composite(commands, detail_bounds))
		check(detail.save_png(OUTPUT.path_join(name + "_detail.png")) == OK, name + ": shoreline closeup")
		check(ResourceSaver.save(data, OUTPUT.path_join(name + ".tres")) == OK, name + ": editable map saved")
		var restored := ResourceLoader.load(OUTPUT.path_join(name + ".tres"), "", ResourceLoader.CACHE_MODE_IGNORE) as MapData
		check(restored != null and restored.content_hash() == data.content_hash(), name + ": saved data matches")
		results.append({"name": name, "profile_size": [data.profile.width, data.profile.height], "cells": counts.cells, "top_tiles": counts.top, "visible_height_strips": counts.sides, "visible_base_tiles": counts.base, "hidden_base_cells": counts.hidden_base, "height_range": [0, 4], "same_level_edge_samples": seam_samples, "draw_commands": commands.size(), "image_size": [image.get_width(), image.get_height()], "data_hash": data.content_hash()})
		renderer.free()
		print("EXPORTED: ", name)
	var report := {"mode": "headless_cpu_atlas_composite", "gpu_screenshot": false, "native_gpu_seam_test": "skipped", "engine": Engine.get_version_info().string, "checks": checks, "failures": failures, "maps": results}
	var file := FileAccess.open(OUTPUT.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("MAP PREVIEW TESTS: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func verify_faces(renderer: MapRenderer) -> Dictionary:
	var data := renderer.data
	var result := {"cells": 0, "top": 0, "sides": 0, "base": 0, "hidden_base": 0}
	for terrain in data.terrain:
		if terrain >= 0:
			result.cells += 1
	for key: String in renderer.layers:
		var count: int = renderer.layers[key].get_used_cells().size()
		if key.begins_with("top_"):
			result.top += count
		elif key.begins_with("side_"):
			result.sides += count
		elif key == "base_side":
			result.base = count
	result.hidden_base = result.cells - result.base
	check(result.top == result.cells, "Every occupied cell has one top")
	check(result.sides > 0 and result.base > 0, "Preview contains cliffs and exposed map boundaries")
	# Both fixtures place this cell inside a solid raised plateau.
	var plateau := Vector2i(3, 3) if data.profile.grid == MapProfile.Grid.SQUARE else Vector2i(4, 4)
	var center := MapGrid.to_offset(plateau, data.profile)
	check(renderer.layers.base_side.get_cell_source_id(center) < 0, "Interior plateau has no base face")
	check(renderer.layers.side_1.get_cell_source_id(center) < 0, "Buried first height layer stays hidden")
	return result

func draw_commands(renderer: MapRenderer, images: Dictionary) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	var sources: Array[Image] = [images.top, images.side, images.decoration, images.base]
	for order in renderer.get_child_count():
		var layer := renderer.get_child(order) as TileMapLayer
		for coords in layer.get_used_cells():
			var source_id := layer.get_cell_source_id(coords)
			var source := renderer.tile_set.get_source(source_id) as TileSetAtlasSource
			var atlas_coords := layer.get_cell_atlas_coords(coords)
			var tile := source.get_tile_data(atlas_coords, layer.get_cell_alternative_tile(coords))
			var region := source.get_tile_texture_region(atlas_coords)
			var center := layer.position + layer.map_to_local(coords)
			var position := center - Vector2(region.size) * 0.5 - Vector2(tile.texture_origin)
			# Pixel-center nearest sampling; exact half-pixel ties take the lower pixel.
			var pixel_position := Vector2i(ceili(position.x - 0.5), ceili(position.y - 0.5))
			commands.append({"image": sources[source_id], "region": region, "position": pixel_position, "sort_y": center.y + layer.y_sort_origin + tile.y_sort_origin, "layer": order, "sort_x": center.x})
	commands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(a.sort_y, b.sort_y):
			return a.sort_y < b.sort_y
		if a.layer != b.layer:
			return a.layer < b.layer
		return a.sort_x < b.sort_x)
	return commands

func command_bounds(commands: Array[Dictionary]) -> Rect2i:
	var result := Rect2i(commands[0].position, commands[0].region.size)
	for item in commands:
		result = result.merge(Rect2i(item.position, item.region.size))
	return result

func composite(commands: Array[Dictionary], bounds: Rect2i) -> Image:
	var result := Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	for item in commands:
		result.blend_rect(item.image, item.region, item.position - bounds.position)
	return result

func with_background(image: Image) -> Image:
	var result := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	result.fill(BACKGROUND)
	result.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	return result

func verify_shared_edges(data: MapData, image: Image, bounds: Rect2i) -> int:
	var samples := 0
	for i in data.terrain.size():
		if data.terrain[i] < 0:
			continue
		var cell := data.cell_at(i)
		for direction: Vector2i in MapGrid.directions(data.profile.grid):
			var next := cell + direction
			if not data.contains(next):
				continue
			var other := data.index_of(next)
			if other <= i or data.terrain[other] < 0 or data.elevation[i] != data.elevation[other]:
				continue
			var a := MapGrid.cell_to_local(cell, data.profile, data.elevation[i])
			var b := MapGrid.cell_to_local(next, data.profile, data.elevation[other])
			var pixel := Vector2i(a.lerp(b, 0.5)) - bounds.position
			var covered := true
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					covered = covered and image.get_pixelv(pixel + Vector2i(dx, dy)).a > 0.99
			check(covered, "Same-height shared edge covered in CPU export")
			samples += 1
	return samples

func shoreline_focus(data: MapData) -> Vector2:
	var best_score := -INF
	var result := Vector2.ZERO
	for i in data.terrain.size():
		if data.terrain[i] != MapData.Terrain.SAND:
			continue
		var cell := data.cell_at(i)
		var types: Dictionary = {}
		for direction: Vector2i in MapGrid.directions(data.profile.grid):
			var next := cell + direction
			if data.contains(next):
				types[data.terrain[data.index_of(next)]] = true
		if not types.has(MapData.Terrain.GRASS) or not types.has(MapData.Terrain.WATER):
			continue
		var point := MapGrid.cell_to_local(cell, data.profile, data.elevation[i])
		if point.y > best_score:
			best_score = point.y
			result = point + Vector2(0, -30)
	return result
