@tool
class_name MapSurfaceArt
extends RefCounted

const PAINTED = preload("res://addons/jeff_map_studio/assets/surfaces/painted.res")
const BASES := [Color("88ac6a"), Color("f1ce94"), Color("77848b"), Color("42b9b3"), Color("666f79")]
const DETAILS := [Color("c5d58c"), Color("fff0c0"), Color("b0b7b1"), Color("a9e4ce"), Color("9ca49f")]
const SIDES := [Color("b38361"), Color("d7a571"), Color("56606b"), Color("258d9d"), Color("505d63")]
const SIDE_DETAILS := [Color("ccb48b"), Color("edcd9b"), Color("8e9794"), Color("62c1ba"), Color("829087")]

static func index(material: int) -> int:
	return {0: 0, 1: 1, 3: 2}.get(material, -1)

static func top(recipe: TextureRecipe) -> Image:
	# Pixel style is drawn by MapPixelArt; these sheets are the painted materials.
	var source: Image = PAINTED.sprites[index(recipe.material)].duplicate()
	# The artwork is a large material field. Sample a broad detail instead of
	# shrinking the whole sheet into every cell, which turns brushwork into noise.
	var crop := 160 if recipe.material == TextureRecipe.MaterialKind.WATER else 256
	source = source.get_region(Rect2i((512 - crop) / 2, (512 - crop) / 2, crop, crop))
	var step := recipe.pixel_size if recipe.style == MapProfile.Style.PIXEL else 1
	var size := maxi(8, recipe.resolution / step)
	source.resize(size, size, Image.INTERPOLATE_NEAREST if recipe.style == 0 else Image.INTERPOLATE_LANCZOS)
	var result := Image.create(recipe.resolution, recipe.resolution, false, Image.FORMAT_RGBA8)
	var repeats := maxi(1, roundi(recipe.scale / 4.0))
	var seed_tone := MapGenerator.random_at(recipe.seed_value, Vector2i.ZERO, 89) * 0.025
	for y in recipe.resolution:
		for x in recipe.resolution:
			var color := source.get_pixel(posmod((x / step) * repeats, size), posmod((y / step) * repeats, size))
			color = tint(color, recipe.base_color, BASES[recipe.material])
			color += (recipe.detail_color - DETAILS[recipe.material]) * color.get_luminance() * 0.65
			var strength := 0.6 if recipe.material == TextureRecipe.MaterialKind.WATER else 1.3
			color = recipe.base_color.lerp(color, minf(1.0, recipe.grain * strength)).lightened(seed_tone)
			result.set_pixel(x, y, color)
	var border := maxi(2, recipe.resolution / 12)
	for y in recipe.resolution:
		for x in border:
			var a := result.get_pixel(x, y)
			var b := result.get_pixel(recipe.resolution - 1 - x, y)
			var weight := 0.5 * (1.0 - float(x) / border)
			result.set_pixel(x, y, a.lerp(b, weight))
			result.set_pixel(recipe.resolution - 1 - x, y, b.lerp(a, weight))
	for x in recipe.resolution:
		for y in border:
			var a := result.get_pixel(x, y)
			var b := result.get_pixel(x, recipe.resolution - 1 - y)
			var weight := 0.5 * (1.0 - float(y) / border)
			result.set_pixel(x, y, a.lerp(b, weight))
			result.set_pixel(x, recipe.resolution - 1 - y, b.lerp(a, weight))
	for y in recipe.resolution:
		result.set_pixel(recipe.resolution - 1, y, result.get_pixel(0, y))
	for x in recipe.resolution:
		result.set_pixel(x, recipe.resolution - 1, result.get_pixel(x, 0))
	return result

static func side(recipe: TextureRecipe, tile_width: int, cap: bool, vertical_phase: bool = false) -> Image:
	if not recipe.illustrated or index(recipe.material) < 0 or recipe.side_pattern != TextureRecipe.SidePattern.AUTO:
		return null
	var source: Image = PAINTED.sprites[index(recipe.material) + 3].duplicate()
	if not cap and not vertical_phase:
		source = source.get_region(Rect2i(0, 112, 512, 368))
	var size := maxi(16, tile_width / (recipe.pixel_size if recipe.style == 0 else 1))
	source.resize(size, size, Image.INTERPOLATE_NEAREST if recipe.style == 0 else Image.INTERPOLATE_LANCZOS)
	return source

static func tint(color: Color, target: Color, reference: Color) -> Color:
	return Color(clampf(color.r * target.r / reference.r, 0, 1), clampf(color.g * target.g / reference.g, 0, 1), clampf(color.b * target.b / reference.b, 0, 1), 1)
