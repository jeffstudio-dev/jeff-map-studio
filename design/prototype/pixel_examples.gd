extends "res://tools/render_map_samples.gd"
## Design example (headless): the pixel style drawn by the plugin's own code, swept
## over art seeds and user parameters on one fixed map layout. Not part of the addon.
const OUT := "res://design/examples/pixel"
const SOURCE := "res://design/concepts/source"
const SEEDS := [42, 7, 2026]
## name, grain (detail density), scale (patch size), base colour, detail colour
const PARAMS := [["默认", 0.6, 4.0, "88ac6a", "c5d58c"], ["高密度·小色块", 0.95, 8.0, "88ac6a", "c5d58c"], ["秋草配色", 0.6, 4.0, "a3a35c", "e0c98a"]]

func run() -> void:
	for seed_value: int in SEEDS:
		for index in PARAMS.size():
			var recipe := grass_recipe(seed_value, PARAMS[index])
			var data := patch(recipe)
			var images := MapAtlasBuilder.prepare_images(data.profile, data.tile_library, MapGenerationJob.new())
			var atlas := images.duplicate()
			atlas["tileset"] = MapAtlasBuilder.create_tileset(images, data.profile)
			var renderer := MapRenderer.new()
			root.add_child(renderer)
			renderer.setup(data, atlas, data.tile_library)
			for i in data.terrain.size():
				renderer.update_cell(data.cell_at(i))
			var commands := draw_commands(renderer, images)
			var image := composite(commands, command_bounds(commands).grow(6))
			image.save_png(OUT.path_join("seed%d_param%d.png" % [seed_value, index]))
			renderer.free()
	# Concept reference layer: one block at the logical resolution (tile 64 / step 2).
	var reference := grass_recipe(42, PARAMS[0])
	var block := MapBlockSurface.thumbnail(reference, 0, 16, 64)
	block.resize(block.get_width() / 2, block.get_height() / 2, Image.INTERPOLATE_NEAREST)
	block.save_png(SOURCE.path_join("pixel_reference_block.png"))
	var ramps := {"top": hexes(MapPixelArt.ramp(reference.base_color, reference.detail_color)), "soil": hexes(MapPixelArt.ramp(reference.side_color, reference.side_detail_color)), "stone": hexes(MapPixelArt.ramp(Color("8a86a0").lerp(reference.side_color, 0.2), Color("cfc8d6")))}
	FileAccess.open(SOURCE.path_join("pixel_ramps.json"), FileAccess.WRITE).store_string(JSON.stringify(ramps, "\t"))
	print("PIXEL EXAMPLES DONE")
	quit()

func hexes(colors: PackedColorArray) -> Array:
	var result := []
	for color in colors:
		result.append(color.to_html(false))
	return result

func grass_recipe(seed_value: int, params: Array) -> TextureRecipe:
	var recipe := TextureRecipe.block_preset(0, MapProfile.Style.PIXEL)
	recipe.seed_value = seed_value
	recipe.grain = params[1]
	recipe.scale = params[2]
	recipe.base_color = Color(params[3])
	recipe.detail_color = Color(params[4])
	return recipe

## Fixed 5×5 layout: a raised 3×3 meadow on a one-level base, so only the art varies.
func patch(recipe: TextureRecipe) -> MapData:
	var p := MapProfile.new()
	p.width = 5
	p.height = 5
	p.tile_size = 64
	p.height_step = 8
	p.base_thickness = 16
	p.style = MapProfile.Style.PIXEL
	var library := TileLibrary.new()
	library.recipes.resize(8)
	library.recipes[MapData.Terrain.GRASS] = recipe
	var data := MapData.new()
	data.initialize(p)
	data.tile_library = library
	for i in data.terrain.size():
		var cell := data.cell_at(i)
		data.terrain[i] = MapData.Terrain.GRASS
		data.elevation[i] = 2 if cell.x >= 1 and cell.x <= 3 and cell.y >= 1 and cell.y <= 3 else 1
		data.manual[i] = 1
	return data
