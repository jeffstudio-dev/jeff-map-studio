extends SceneTree
## Render an opaque, uniform surface: any dark interior pixel is a coverage gap.

var failures: Array[String] = []
var checks: int = 0

func _init() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("SEAM TESTS: skipped (requires a graphics context)")
		quit(0)
		return
	var map := JeffMap2D.new()
	root.add_child(map)
	var camera := Camera2D.new()
	root.add_child(camera)
	var library := TileLibrary.new()
	library.recipes.resize(8)
	var recipe := TextureRecipe.new()
	recipe.base_color = Color.WHITE
	recipe.detail_color = Color.WHITE
	recipe.grain = 0.0
	library.recipes[MapData.Terrain.GRASS] = recipe
	for grid in 2:
		for orientation in (2 if grid == MapProfile.Grid.HEX else 1):
			for projection in 2:
				for style in 2:
					var profile := MapProfile.new()
					profile.width = 24
					profile.height = 24
					profile.grid = grid
					profile.hex_orientation = orientation
					profile.projection = projection
					profile.style = style
					var data := MapData.new()
					data.initialize(profile, MapData.Terrain.GRASS)
					data.tile_library = library
					map.apply_data(data)
					while map.busy:
						await process_frame
					camera.position = map.cell_to_local(Vector2i(12, 12))
					for zoom in [0.28, 0.65, 1.4]:
						camera.zoom = Vector2.ONE * zoom
						await process_frame
						await RenderingServer.frame_post_draw
						var image := root.get_texture().get_image()
						var center := image.get_size() / 2
						var minimum := 1.0
						for y in range(center.y - 32, center.y + 32):
							for x in range(center.x - 32, center.x + 32):
								minimum = minf(minimum, image.get_pixel(x, y).r)
						checks += 1
						if minimum < 0.9:
							var message := "grid=%d orientation=%d projection=%d style=%d zoom=%.2f min=%.3f" % [grid, orientation, projection, style, zoom, minimum]
							failures.append(message)
							printerr("FAIL: ", message)
	print("SEAM TESTS: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
