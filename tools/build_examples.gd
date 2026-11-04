extends SceneTree

const BASE := "res://addons/jeff_map_studio/examples"

func _init() -> void:
	call_deferred("run")

func run() -> void:
	for folder in ["profiles", "libraries", "textures", "atlases", "blocks"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASE.path_join(folder)))
	if "--blocks-only" in OS.get_cmdline_user_args():
		build_blocks()
		print("Block sample PNGs rendered in the background.")
		quit()
		return
	for kind in 3:
		for style in 2:
			var p := MapProfile.new()
			p.base_thickness = 16
			p.generator = kind
			p.style = style
			if kind != 0:
				p.max_height = 2
				p.decoration_density = 0.02
				p.projection = MapProfile.ProjectionMode.TOP_DOWN
			ResourceSaver.save(p, BASE.path_join("profiles/%s_%s.tres" % [["nature", "dungeon", "cave"][kind], ["pixel", "soft"][style]]))
	for kind in 2:
		for style in 2:
			var library := TileLibrary.new()
			library.display_name = ("自然地形" if kind == 0 else "石砖地牢") + (" · 像素" if style == 0 else " · 手绘")
			for terrain_id in 8:
				var material: int = [3, 1, 0, 1, 2, 2, 4, 4][terrain_id]
				var recipe := TextureRecipe.preset(material, style)
				recipe.base_color = MapAtlasBuilder.PALETTE[terrain_id]
				recipe.detail_color = recipe.base_color.lightened(0.3)
				if kind == 1 and terrain_id == MapData.Terrain.FLOOR:
					recipe.base_color = Color("8b806f")
					recipe.detail_color = Color("c3b694")
				library.recipes.append(recipe)
			ResourceSaver.save(library, BASE.path_join("libraries/%s_%s.tres" % [["nature", "dungeon"][kind], ["pixel", "soft"][style]]))
	for style in 2:
		for material in 5:
			var recipe := TextureRecipe.preset(material, style)
			var name := "%s_%s" % [["grass", "sand", "rock", "water", "brick"][material], ["pixel", "soft"][style]]
			MapTextureFactory.create(recipe).save_png(BASE.path_join("textures/" + name + ".png"))
			ResourceSaver.save(recipe, BASE.path_join("textures/" + name + ".tres"))
	var layouts := [["square_iso_pixel", 0, 1, 0, 0], ["square_top_soft", 0, 0, 0, 1], ["hex_pointy_iso_soft", 1, 1, 0, 1], ["hex_flat_top_pixel", 1, 0, 1, 0]]
	for layout in layouts:
		var p := MapProfile.new()
		p.base_thickness = 16
		p.grid = layout[1]
		p.projection = layout[2]
		p.hex_orientation = layout[3]
		p.style = layout[4]
		ResourceSaver.save(p, BASE.path_join("profiles/" + layout[0] + ".tres"))
		var images := MapAtlasBuilder.prepare_images(p, null, MapGenerationJob.new())
		var library := TileLibrary.new()
		library.display_name = layout[0]
		library.layout_grid = p.grid
		library.layout_projection = p.projection
		library.layout_orientation = p.hex_orientation
		library.tile_set = MapAtlasBuilder.create_tileset(images, p)
		for terrain_id in 8:
			for variant in images.variants:
				for mask in images.masks:
					var rule := MapTileRule.new()
					rule.terrain = terrain_id
					rule.neighbor_mask = mask
					rule.atlas_coords = MapAtlasBuilder.top_coords(terrain_id, variant, 0, mask, images.masks)
					library.rules.append(rule)
			for mask: int in images.side_rows:
				if mask == 0:
					continue
				var rule := MapTileRule.new()
				rule.terrain = terrain_id
				rule.role = MapTileRule.Role.SIDE
				rule.source_id = 1
				rule.neighbor_mask = mask
				rule.atlas_coords = Vector2i(terrain_id, images.side_rows[mask])
				library.rules.append(rule)
			for decoration_id in range(1, 7):
				var rule := MapTileRule.new()
				rule.terrain = terrain_id
				rule.role = MapTileRule.Role.DECORATION
				rule.source_id = 2
				rule.decoration_id = decoration_id
				rule.atlas_coords = Vector2i(decoration_id - 1, 0)
				library.rules.append(rule)
		ResourceSaver.save(library, BASE.path_join("libraries/" + layout[0] + ".res"), ResourceSaver.FLAG_COMPRESS)
		images.top.save_png(BASE.path_join("atlases/" + layout[0] + "_top.png"))
		images.side.save_png(BASE.path_join("atlases/" + layout[0] + "_side.png"))
		images.base.save_png(BASE.path_join("atlases/" + layout[0] + "_base.png"))
		images.decoration.save_png(BASE.path_join("atlases/" + layout[0] + "_decoration.png"))
	build_blocks()
	print("Example profiles, libraries, textures and atlases generated.")
	quit()

func build_blocks() -> void:
	for material in 4:
		var recipe := TextureRecipe.block_preset(material)
		var name: String = ["moss", "jade_brick", "lagoon", "sandstone"][material]
		ResourceSaver.save(recipe, BASE.path_join("blocks/" + name + ".tres"))
		for shape in 3:
			MapBlockSurface.thumbnail(recipe, shape, 72, 256).save_png(BASE.path_join("blocks/%s_%s.png" % [name, ["square", "hex_pointy", "hex_flat"][shape]]))
