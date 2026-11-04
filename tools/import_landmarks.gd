extends SceneTree
## Import generated sprite sheets into engine-native, exportable CPU resources.
const BASE := "res://addons/jeff_map_studio/assets/landmarks/"

func _init() -> void:
	for style in ["pixel", "painted"]:
		var sheet := Image.load_from_file(BASE + style + "_source.png")
		var pack = preload("res://addons/jeff_map_studio/render/landmark_source.gd").new()
		for i in 6:
			var cell := sheet.get_region(Rect2i((i % 3) * 512, (i / 3) * 512, 512, 512))
			var bounds := Rect2i(512, 512, 0, 0)
			var found := false
			for y in 512:
				for x in 512:
					if cell.get_pixel(x, y).a > 0.12:
						var pixel := Rect2i(x, y, 1, 1)
						bounds = bounds.merge(pixel) if found else pixel
						found = true
			assert(found and bounds.position.x > 2 and bounds.position.y > 2 and bounds.end.x < 510 and bounds.end.y < 510)
			var sprite := cell.get_region(bounds.grow(3).intersection(Rect2i(0, 0, 512, 512)))
			sprite.fix_alpha_edges()
			pack.sprites.append(sprite)
		assert(ResourceSaver.save(pack, BASE + style + ".res", ResourceSaver.FLAG_COMPRESS) == OK)
		print("Imported ", style, ": ", pack.sprites.size(), " transparent sprites")
	quit()
