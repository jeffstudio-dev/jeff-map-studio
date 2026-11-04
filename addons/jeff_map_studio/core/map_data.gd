@tool
class_name MapData
extends Resource

enum Terrain { WATER, SAND, GRASS, DIRT, ROCK, SNOW, WALL, FLOOR }
const TERRAIN_NAMES := ["水域", "沙地", "草地", "泥地", "岩石", "雪地", "墙体", "地板"]
enum Decoration { NONE, TREE, ROCK, CRATE, MUSHROOMS, PALM, LIGHTHOUSE }
const DECORATION_NAMES := ["移除装饰", "树木", "石头", "木箱", "蘑菇群", "棕榈树", "灯塔"]
const GENERATOR_VERSION := "1.1.0"

@export var generator_version: String = GENERATOR_VERSION
@export var profile: MapProfile
@export var tile_library: TileLibrary
@export var terrain: PackedInt32Array
@export var elevation: PackedByteArray
@export var decoration: PackedByteArray
@export var locked: PackedByteArray
@export var manual: PackedByteArray
@export var metadata: Dictionary = {}

func initialize(settings: MapProfile, fill: int = -1) -> void:
	profile = settings.copy()
	var count := profile.width * profile.height
	terrain.resize(count)
	terrain.fill(fill)
	elevation.resize(count)
	elevation.fill(0)
	decoration.resize(count)
	decoration.fill(0)
	locked.resize(count)
	locked.fill(0)
	manual.resize(count)
	manual.fill(0)

func contains(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < profile.width and cell.y < profile.height

func index_of(cell: Vector2i) -> int:
	return cell.y * profile.width + cell.x

func cell_at(index: int) -> Vector2i:
	return Vector2i(index % profile.width, index / profile.width)

func get_cell(cell: Vector2i) -> Dictionary:
	if not contains(cell):
		return {}
	var i := index_of(cell)
	return {"terrain": terrain[i], "height": elevation[i], "decoration": decoration[i], "locked": locked[i] != 0, "manual": manual[i] != 0}

func copy() -> MapData:
	var result := MapData.new()
	result.profile = profile.copy()
	result.tile_library = tile_library.duplicate(true) as TileLibrary if tile_library != null else null
	result.generator_version = generator_version
	result.terrain = terrain.duplicate()
	result.elevation = elevation.duplicate()
	result.decoration = decoration.duplicate()
	result.locked = locked.duplicate()
	result.manual = manual.duplicate()
	result.metadata = metadata.duplicate(true)
	return result

func validate() -> String:
	if profile == null:
		return "地图缺少配置。"
	var error := profile.validate()
	if not error.is_empty():
		return error
	var n := profile.width * profile.height
	if terrain.size() != n or elevation.size() != n or decoration.size() != n or locked.size() != n or manual.size() != n:
		return "地图数组尺寸与配置不一致。"
	for i in n:
		if terrain[i] < -1 or terrain[i] > Terrain.FLOOR or elevation[i] > 16 or decoration[i] > Decoration.LIGHTHOUSE:
			return "地图含无效地形、高度或装饰，位置：%s" % cell_at(i)
	return ""

func content_hash() -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(terrain.to_byte_array())
	context.update(elevation)
	context.update(decoration)
	context.update(locked)
	context.update(manual)
	return context.finish().hex_encode()
