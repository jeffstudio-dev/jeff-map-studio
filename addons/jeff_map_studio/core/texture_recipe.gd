@tool
class_name TextureRecipe
extends Resource

enum MaterialKind { GRASS, SAND, ROCK, WATER, BRICK }
enum SidePattern { AUTO, SOIL, MOSS, ROCK, BRICK, WATER }
@export_enum("草地", "沙土", "岩石", "水面", "石砖") var material: int = MaterialKind.GRASS
@export_enum("像素", "手绘") var style: int = MapProfile.Style.PIXEL
@export var seed_value: int = 42
@export_range(16, 256, 1) var resolution: int = 64
@export var base_color: Color = Color("82a56f")
@export var detail_color: Color = Color("b6c58b")
@export_range(0.0, 1.0, 0.01) var grain: float = 0.35
@export_range(1.0, 16.0, 0.5) var scale: float = 4.0
@export_range(1, 8, 1) var pixel_size: int = 2
@export var illustrated: bool = false
@export_group("Block sides")
@export_enum("随材质", "土层", "苔藓", "岩层", "砖墙", "水层") var side_pattern: int = SidePattern.AUTO
@export var side_color: Color = Color.TRANSPARENT
@export var side_detail_color: Color = Color.TRANSPARENT
@export_range(0.0, 1.0, 0.05) var side_grain: float = 0.65

static func preset(kind: int, visual_style: int = 0) -> TextureRecipe:
	var result := TextureRecipe.new()
	result.material = kind
	result.style = visual_style
	var colors := [["88ac6a", "c5d58c"], ["f1ce94", "fff0c0"], ["77848b", "b0b7b1"], ["42b9b3", "a9e4ce"], ["666f79", "9ca49f"]]
	result.base_color = Color(colors[kind][0])
	result.detail_color = Color(colors[kind][1])
	var sides := [["b38361", "ccb48b"], ["d7a571", "edcd9b"], ["56606b", "8e9794"], ["258d9d", "62c1ba"], ["505d63", "829087"]]
	result.side_color = Color(sides[kind][0])
	result.side_detail_color = Color(sides[kind][1])
	result.illustrated = kind in [MaterialKind.GRASS, MaterialKind.SAND, MaterialKind.WATER]
	result.grain = 0.6
	return result

static func block_preset(index: int, visual_style: int = MapProfile.Style.PIXEL) -> TextureRecipe:
	var kinds := [MaterialKind.GRASS, MaterialKind.BRICK, MaterialKind.WATER, MaterialKind.SAND]
	var result := preset(kinds[clampi(index, 0, 3)], visual_style)
	var colors := [["88ac6a", "c5d58c", "b38361", "ccb48b"], ["83bba2", "c2dec2", "56816f", "91b59b"], ["42b9b3", "a9e4ce", "258d9d", "62c1ba"], ["f1ce94", "fff0c0", "d7a571", "edcd9b"]]
	var palette: Array = colors[clampi(index, 0, 3)]
	result.base_color = Color(palette[0])
	result.detail_color = Color(palette[1])
	result.side_color = Color(palette[2])
	result.side_detail_color = Color(palette[3])
	result.grain = 0.6
	result.pixel_size = 2
	result.resolution = 128
	return result

func validate() -> String:
	if material < 0 or material > 4 or style < 0 or style > 1:
		return "未知的纹理模板或风格。"
	if resolution < 16 or resolution > 256 or pixel_size < 1 or pixel_size > 8 or not is_finite(scale) or scale <= 0.0 or scale > 16.0:
		return "纹理尺寸需为 16–256，像素步长和纹理尺度必须大于 0。"
	if not is_finite(grain) or grain < 0.0 or grain > 1.0:
		return "颗粒强度必须为 0–1。"
	if side_pattern < 0 or side_pattern > SidePattern.WATER or not is_finite(side_grain) or side_grain < 0.0 or side_grain > 1.0:
		return "侧面样式无效，侧面细节强度必须为 0–1。"
	return ""
