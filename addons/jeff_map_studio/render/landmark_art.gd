@tool
class_name MapLandmarkArt
extends RefCounted

const PAINTED = preload("res://addons/jeff_map_studio/assets/landmarks/painted.res")
const HEIGHTS := [0.88, 0.35, 0.34, 0.36, 0.84, 0.88]

static func sprite(style: int, id: int, tile_width: int, maximum_height: int = 0, maximum_width: int = 0) -> Image:
	if id < 1 or id > HEIGHTS.size():
		return null
	if style == MapProfile.Style.PIXEL:
		return _pixel_sprite(id, tile_width, maximum_height, maximum_width)
	var image: Image = PAINTED.sprites[id - 1].duplicate()
	var height: float = tile_width * HEIGHTS[id - 1]
	if maximum_height > 0:
		height = minf(height, maximum_height)
	var scale := minf(tile_width * 0.78 / image.get_width(), height / image.get_height())
	image.resize(maxi(2, roundi(image.get_width() * scale)), maxi(2, roundi(image.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	return image

## Whole-number enlargement keeps object pixels the same size as terrain pixels.
static func _pixel_sprite(id: int, tile_width: int, maximum_height: int, maximum_width: int) -> Image:
	var image := MapPixelArt.landmark(id)
	var scale := MapPixelArt.landmark_scale(tile_width)
	while scale > 1 and ((maximum_height > 0 and image.get_height() * scale > maximum_height) or (maximum_width > 0 and image.get_width() * scale > maximum_width)):
		scale -= 1
	var size := image.get_size() * scale
	var fit := 1.0
	if maximum_height > 0 and size.y > maximum_height:
		fit = float(maximum_height) / size.y
	if maximum_width > 0 and size.x > maximum_width:
		fit = minf(fit, float(maximum_width) / size.x)
	if fit < 1.0:
		# Very small tiles cannot hold the authored sprite; shrink as a last resort.
		size = Vector2i(maxi(2, floori(size.x * fit)), maxi(2, floori(size.y * fit)))
	image.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
	return image

## Horizontal placement snapped to the object's pixel size, matching the terrain grid.
static func centered_x(style: int, width: int, item_width: int, tile_width: int) -> int:
	var x := (width - item_width) / 2
	if style == MapProfile.Style.PIXEL:
		var scale := MapPixelArt.landmark_scale(tile_width)
		x = floori(float(x) / scale) * scale
	return x

static func atlas(width: int, height: int, style: int, tile_size: int = 0) -> Image:
	# Pixel objects scale with the tile size, like terrain pixels; painted art keeps
	# fitting the atlas cell width as before.
	var tile_width := tile_size if tile_size > 0 and style == MapProfile.Style.PIXEL else width
	var result := Image.create(width * HEIGHTS.size(), height, false, Image.FORMAT_RGBA8)
	var anchor := roundi(height * 0.72)
	for id in range(1, HEIGHTS.size() + 1):
		var item := sprite(style, id, tile_width, anchor - 2, width)
		var position := Vector2i((id - 1) * width + centered_x(style, width, item.get_width(), tile_width), anchor - item.get_height())
		result.blend_rect(item, Rect2i(Vector2i.ZERO, item.get_size()), position)
	result.fix_alpha_edges()
	return result
