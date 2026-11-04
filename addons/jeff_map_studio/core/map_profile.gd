@tool
class_name MapProfile
extends Resource
## Serializable generation and presentation settings. Heights are visual only.

enum Generator { NATURE, DUNGEON, CAVE }
enum Grid { SQUARE, HEX }
enum ProjectionMode { TOP_DOWN, ISOMETRIC }
enum HexOrientation { POINTY, FLAT }
# SOFT retains serialized value 1; its renderer now uses the hand-painted style.
enum Style { PIXEL, SOFT }

@export var seed_value: int = 20261017
@export_range(8, 512, 1) var width: int = 128
@export_range(8, 512, 1) var height: int = 128
@export_enum("自然地形", "房间地牢", "洞穴") var generator: int = Generator.NATURE
@export_enum("方形", "六角") var grid: int = Grid.SQUARE
@export_enum("俯视", "等角") var projection: int = ProjectionMode.ISOMETRIC
@export_enum("尖顶", "平顶") var hex_orientation: int = HexOrientation.POINTY
@export_enum("像素", "手绘") var style: int = Style.PIXEL
@export_range(16, 128, 2) var tile_size: int = 64
@export_range(2, 32, 2) var height_step: int = 8
@export_range(0, 64, 2) var base_thickness: int = 0
@export_range(0, 16, 1) var max_height: int = 8

@export_group("Nature")
@export_range(0.002, 0.15, 0.001) var noise_scale: float = 0.025
@export_range(1, 6, 1) var octaves: int = 4
@export var island: bool = true
@export_range(0.0, 1.0, 0.01) var sea_level: float = 0.4
@export_range(0.01, 0.2, 0.01) var beach_width: float = 0.08
@export_range(0.0, 2.0, 0.05) var mountain_strength: float = 1.1
@export_range(0, 4, 1) var smoothing: int = 1
@export_range(0.0, 0.8, 0.01) var decoration_density: float = 0.12

@export_group("Dungeon")
@export_range(2, 80, 1) var room_count: int = 16
@export_range(2, 20, 1) var room_min_size: int = 4
@export_range(3, 30, 1) var room_max_size: int = 10
@export_range(1, 5, 1) var corridor_width: int = 2
@export_range(0.0, 1.0, 0.05) var extra_connection_chance: float = 0.15

@export_group("Cave")
@export_range(0.1, 0.85, 0.01) var cave_fill: float = 0.46
@export_range(0, 10, 1) var cave_iterations: int = 4
@export_range(1, 1000, 1) var min_region_area: int = 20

func validate() -> String:
	if width < 8 or height < 8 or width > 512 or height > 512:
		return "地图宽高必须在 8–512 之间。"
	if grid < 0 or grid > 1 or generator < 0 or generator > 2:
		return "未知的网格或生成器类型。"
	if projection < 0 or projection > 1 or hex_orientation < 0 or hex_orientation > 1:
		return "未知的投影或六角朝向。"
	if style < 0 or style > 1:
		return "未知的纹理风格。"
	if max_height < 0 or max_height > 16 or height_step < 2 or height_step > 32:
		return "高度必须为 0–16 层，层高为 2–32 像素。"
	if base_thickness < 0 or base_thickness > 64 or base_thickness % 2 != 0:
		return "底座厚度必须为 0–64 的偶数像素。"
	if tile_size < 16 or tile_size > 128 or tile_size % 2 != 0:
		return "地块尺寸必须为 16–128 的偶数。"
	if room_min_size > room_max_size or room_min_size < 2 or room_max_size > 30 or room_max_size < 3:
		return "房间最小尺寸不能大于最大尺寸。"
	if room_count < 2 or room_count > 80 or corridor_width < 1 or corridor_width > 5:
		return "房间数应为 2–80，走廊宽度为 1–5。"
	if not is_finite(noise_scale) or not is_finite(sea_level) or noise_scale <= 0.0 or sea_level < 0.0 or sea_level >= 1.0:
		return "噪声尺度必须大于 0，海平面必须小于 1。"
	if octaves < 1 or octaves > 6 or smoothing < 0 or smoothing > 4:
		return "噪声层数为 1–6，平滑次数为 0–4。"
	if not is_finite(beach_width) or beach_width <= 0.0 or beach_width > 0.2 or not is_finite(mountain_strength) or mountain_strength < 0.0 or mountain_strength > 2.0:
		return "沙滩宽度需大于 0 且不超过 0.2，山地强度为 0–2。"
	if not is_finite(decoration_density) or decoration_density < 0.0 or decoration_density > 0.8 or not is_finite(extra_connection_chance) or extra_connection_chance < 0.0 or extra_connection_chance > 1.0:
		return "装饰密度为 0–0.8，额外连边概率为 0–1。"
	if not is_finite(cave_fill) or cave_fill < 0.1 or cave_fill > 0.85 or cave_iterations < 0 or cave_iterations > 10 or min_region_area < 1 or min_region_area > 1000:
		return "洞穴填充率为 0.1–0.85，迭代次数 0–10，最小区域面积 1–1000。"
	return ""

func copy() -> MapProfile:
	return duplicate(true) as MapProfile
