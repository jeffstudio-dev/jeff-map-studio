extends SceneTree

func _init() -> void:
	for style in ["pixel", "painted"]:
		var sheet := Image.load_from_file("res://addons/jeff_map_studio/assets/surfaces/%s_source.png" % style)
		var pack = preload("res://addons/jeff_map_studio/render/landmark_source.gd").new()
		for i in 6:
			var cell := sheet.get_region(Rect2i((i % 3) * 512, (i / 3) * 512, 512, 512))
			# Blend only the outer band so the authored pattern repeats continuously.
			for y in 512:
				for x in 32:
					var a := cell.get_pixel(x, y)
					var b := cell.get_pixel(511 - x, y)
					var weight := 0.5 * (1.0 - float(x) / 32.0)
					cell.set_pixel(x, y, a.lerp(b, weight))
					cell.set_pixel(511 - x, y, b.lerp(a, weight))
			if i < 3:
				for x in 512:
					for y in 32:
						var a := cell.get_pixel(x, y)
						var b := cell.get_pixel(x, 511 - y)
						var weight := 0.5 * (1.0 - float(y) / 32.0)
						cell.set_pixel(x, y, a.lerp(b, weight))
						cell.set_pixel(x, 511 - y, b.lerp(a, weight))
			pack.sprites.append(cell)
		assert(ResourceSaver.save(pack, "res://addons/jeff_map_studio/assets/surfaces/%s.res" % style, ResourceSaver.FLAG_COMPRESS) == OK)
		print("Imported surface textures: ", style)
	quit()
