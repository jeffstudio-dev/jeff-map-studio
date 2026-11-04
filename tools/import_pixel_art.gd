extends SceneTree
## Converts the Aseprite exports in assets/pixel/ into CPU resources that worker
## threads can read. Run tools/export_pixel_art.py, which exports and then calls this.
const BASE := "res://addons/jeff_map_studio/assets/pixel/"
## Must match CLUSTER_COLORS in tools/aseprite/author_pixel_art.lua.
const CLUSTER_KEYS := {"1c1f26": "0", "3d434f": "1", "666e7d": "2", "959daa": "3", "c4cad3": "4", "f2f4f7": "5", "fff4d6": "a", "f6d65a": "b", "c8b6f0": "d", "f7d9cf": "l"}
const OBJECTS := ["tree", "rock", "chest", "mushrooms", "palm", "lighthouse"]

func _init() -> void:
	var ok := _import_landmarks() and _import_clusters()
	quit(0 if ok else 1)

func _sheet(name: String) -> Array:
	var image := Image.load_from_file(BASE + name + ".png")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASE + name + ".json"))
	if image == null or not data is Dictionary:
		push_error("Missing Aseprite export for " + name)
		return []
	image.convert(Image.FORMAT_RGBA8)
	var tags := {}
	for tag: Dictionary in data.meta.frameTags:
		tags[tag.name] = [int(tag.from), int(tag.to)]
	var frames: Array[Rect2i] = []
	for frame: Dictionary in data.frames:
		frames.append(Rect2i(int(frame.frame.x), int(frame.frame.y), int(frame.frame.w), int(frame.frame.h)))
	return [image, tags, frames]

func _import_landmarks() -> bool:
	var sheet := _sheet("landmarks")
	if sheet.is_empty():
		return false
	var pack = preload("res://addons/jeff_map_studio/render/landmark_source.gd").new()
	for name: String in OBJECTS:
		if not sheet[1].has(name):
			push_error("landmarks.aseprite has no tag " + name)
			return false
		var cell: Image = sheet[0].get_region(sheet[2][sheet[1][name][0]])
		var used := cell.get_used_rect()
		# Trim, keep the bottom (contact shadow) row, add a transparent top/side gutter.
		var sprite := Image.create(used.size.x + 2, used.size.y + 1, false, Image.FORMAT_RGBA8)
		sprite.blit_rect(cell, used, Vector2i(1, 1))
		pack.sprites.append(sprite)
	var result := ResourceSaver.save(pack, BASE + "landmarks.res", ResourceSaver.FLAG_COMPRESS)
	print("Imported ", pack.sprites.size(), " pixel objects")
	return result == OK

func _import_clusters() -> bool:
	var sheet := _sheet("clusters")
	if sheet.is_empty():
		return false
	var clusters = preload("res://addons/jeff_map_studio/render/pixel_clusters.gd").new()
	for name: String in sheet[1]:
		var stamps: Array = []
		for index in range(sheet[1][name][0], sheet[1][name][1] + 1):
			var cell: Image = sheet[0].get_region(sheet[2][index])
			var used := cell.get_used_rect()
			var rows := PackedStringArray()
			for y in range(used.position.y, used.end.y):
				var row := ""
				for x in range(used.position.x, used.end.x):
					var color := cell.get_pixel(x, y)
					if color.a < 0.5:
						row += "."
						continue
					var key: String = CLUSTER_KEYS.get(color.to_html(false), "")
					if key.is_empty():
						push_error("clusters.aseprite frame %d uses colour #%s outside the cluster palette" % [index + 1, color.to_html(false)])
						return false
					row += key
				rows.append(row)
			stamps.append(rows)
		clusters.groups[name] = stamps
	var result := ResourceSaver.save(clusters, BASE + "clusters.res", ResourceSaver.FLAG_COMPRESS)
	print("Imported cluster groups: ", clusters.groups.keys())
	return result == OK
