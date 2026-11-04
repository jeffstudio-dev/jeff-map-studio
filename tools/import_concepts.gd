extends SceneTree
## Turns Aseprite concept exports (art/concepts/<style>/export/) into MapArtConcept
## resources next to each sheet. Run through tools/export_concepts.py.
const ROOT := "res://addons/jeff_map_studio/art/concepts/"
const Concept = preload("res://addons/jeff_map_studio/core/art_concept.gd")

func _init() -> void:
	var ok := true
	for style in DirAccess.get_directories_at(ROOT):
		var export := ROOT + style + "/export/"
		for file in DirAccess.get_files_at(export):
			if file.get_extension() == "json":
				ok = _import(export, file.get_basename(), ROOT + style + "/" + file.get_basename() + ".res") and ok
	quit(0 if ok else 1)

func _import(folder: String, name: String, target: String) -> bool:
	var text := FileAccess.get_file_as_string(folder + name + ".json")
	var data: Variant = JSON.parse_string(text)
	var palette := Image.load_from_file(ProjectSettings.globalize_path(folder + name + "_palette.png"))
	var motifs := Image.load_from_file(ProjectSettings.globalize_path(folder + name + "_motifs.png"))
	if not data is Dictionary or palette == null or motifs == null:
		push_error("Concept %s is missing its palette or motif export" % name)
		return false
	palette.convert(Image.FORMAT_RGBA8)
	motifs.convert(Image.FORMAT_RGBA8)
	var concept = Concept.new()
	concept.source = folder.get_base_dir().get_base_dir() + "/" + name + ".aseprite"
	var slices := {}
	for item: Dictionary in data.meta.slices:
		var b: Dictionary = item["keys"][0]["bounds"]
		slices[String(item["name"])] = Rect2i(int(b.x), int(b.y), int(b.w), int(b.h))
	var names: Array = slices.keys()
	names.sort()
	var keys := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	for slice: String in names:
		var rect: Rect2i = slices[slice]
		if slice.begins_with("ramp/"):
			var colors := PackedColorArray()
			for i in rect.size.x / rect.size.y:
				colors.append(palette.get_pixel(rect.position.x + i * rect.size.y + rect.size.y / 2, rect.position.y + rect.size.y / 2))
			concept.ramps[slice.trim_prefix("ramp/")] = colors
		elif slice.begins_with("accent/"):
			var key := keys[concept.accents.size()]
			concept.accents[key] = palette.get_pixelv(rect.get_center())
			concept.accent_names[key] = slice.trim_prefix("accent/")
	for slice: String in names:
		if not slice.begins_with("motif/"):
			continue
		var group := slice.get_slice("/", 1)
		var rect: Rect2i = slices[slice]
		var rows := PackedStringArray()
		for y in range(rect.position.y, rect.end.y):
			var row := ""
			for x in range(rect.position.x, rect.end.x):
				var key := _key(concept, group, motifs.get_pixel(x, y))
				if key.is_empty():
					push_error("%s: %s uses colour #%s outside the palette slices" % [name, slice, motifs.get_pixel(x, y).to_html(false)])
					return false
				row += key
			rows.append(row)
		if not concept.motifs.has(group):
			concept.motifs[group] = []
		concept.motifs[group].append(rows)
	concept.source_hash = (text + palette.get_data().hex_encode() + motifs.get_data().hex_encode()).sha256_text()
	var result := ResourceSaver.save(concept, target, ResourceSaver.FLAG_COMPRESS)
	print("Imported concept ", target, ": ramps ", concept.ramps.keys(), ", motif groups ", concept.motifs.keys())
	return result == OK

## Accent letter, or the ramp step of the group's ramp (the first ramp that matches).
func _key(concept, group: String, color: Color) -> String:
	if color.a < 0.5:
		return "."
	for key: String in concept.accents:
		if concept.accents[key].is_equal_approx(color):
			return key
	var ramps: Array = [concept.motif_ramps[group]] if concept.motif_ramps.has(group) else concept.ramps.keys()
	for ramp: String in ramps:
		var colors: PackedColorArray = concept.ramps[ramp]
		for i in colors.size():
			if colors[i].is_equal_approx(color):
				concept.motif_ramps[group] = ramp
				return str(i)
	return ""
