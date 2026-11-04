@tool
class_name MapTextureWorkbench
extends HBoxContainer

signal library_applied(library: TileLibrary)
signal status_message(message: String)
signal base_thickness_changed(value: int)

var profile: MapProfile = MapProfile.new():
	set(value):
		profile = value
		_dirty = true
		if _depth_field != null:
			_depth_field.set_value_no_signal(profile.base_thickness)
var library: TileLibrary = TileLibrary.new()
var recipe: TextureRecipe = TextureRecipe.preset(0)
var _preview: Control
var _block_preview: MapBlockPreview
var _preview_tabs: TabContainer
var _depth_field: SpinBox
var preview_decoration: int = MapData.Decoration.MUSHROOMS
var _decoration_field: OptionButton
var _atlas_preview: Control
var _fields: Dictionary = {}
var _rules: ItemList
var _binding_terrain: int = 2
var _recipe_terrain: int = 2
var _binding_role: int = 0
var _binding_decoration: int = -1
var _texture_origin := Vector2i.ZERO
var _sort_origin: int = 0
var _binding_source: int = 0
var _binding_coords := Vector2i.ZERO
var _binding_alternative: int = 0
var _binding_mask: int = -1
var _binding_corner: int = -1
var _binding_weight: float = 1.0
var _region := Vector2i(64, 64)
var _margin := Vector2i.ZERO
var _separation := Vector2i.ZERO
var _image: Image
var _thread: Thread
var _dirty: bool = true
var _syncing: bool = false

func use_library(value: TileLibrary) -> void:
	library = value
	if is_node_ready():
		_binding_source = library.tile_set.get_source_id(0) if library.tile_set != null and library.tile_set.get_source_count() > 0 else 0
		_refresh_atlas()
		_refresh_rules()

func _ready() -> void:
	add_theme_constant_override("separation", 18)
	var left := StudioUI.scroll_column(self, 245)
	StudioUI.heading(left, "地块材质", "调整笔触、配色与纹理，检查平铺接缝。")
	StudioUI.choice(left, "地块配色预设", ["自定义配方", "苔藓草块", "青玉砖块", "浅海水柱", "分层沙土"], 0, func(value: int) -> void:
		if value == 0:
			return
		recipe = TextureRecipe.block_preset(value - 1, recipe.style)
		preview_decoration = [MapData.Decoration.MUSHROOMS, MapData.Decoration.CRATE, MapData.Decoration.LIGHTHOUSE, MapData.Decoration.PALM][value - 1]
		if _decoration_field != null:
			_decoration_field.select(preview_decoration)
		_sync_recipe())
	_fields.material = StudioUI.choice(left, "纹理模板", ["草地", "沙土", "岩石", "水面", "石砖"], recipe.material, _set_material)
	_fields.style = StudioUI.choice(left, "输出风格", ["像素风", "手绘风"], recipe.style, func(value: int) -> void: _change_recipe("style", value))
	var illustrated := CheckButton.new()
	illustrated.text = "使用绘制材质"
	illustrated.tooltip_text = "手绘风：草地、沙地、水域使用配套绘制纹理。像素风：叠加 Aseprite 制作的草簇、小花、卵石与波光。关闭后只保留程序色块。"
	illustrated.button_pressed = recipe.illustrated
	illustrated.toggled.connect(func(value: bool) -> void: _change_recipe("illustrated", value))
	left.add_child(illustrated)
	_fields.illustrated = illustrated
	_decoration_field = StudioUI.choice(left, "单块标志物", ["无标志物", "树木", "石头", "木箱", "蘑菇群", "棕榈树", "灯塔"], preview_decoration, func(value: int) -> void:
		preview_decoration = value
		_dirty = true)
	_fields.seed_value = StudioUI.number(left, "纹理种子", recipe.seed_value, 0, 2147483647, 1, func(value: float) -> void: _change_recipe("seed_value", int(value)))
	_fields.resolution = StudioUI.number(left, "分辨率", recipe.resolution, 16, 256, 16, func(value: float) -> void: _change_recipe("resolution", int(value)))
	_fields.grain = StudioUI.number(left, "纹理细节", recipe.grain, 0, 1, 0.05, func(value: float) -> void: _change_recipe("grain", value))
	_fields.scale = StudioUI.number(left, "纹理尺度", recipe.scale, 1, 16, 0.5, func(value: float) -> void: _change_recipe("scale", value))
	_fields.pixel_size = StudioUI.number(left, "像素步长", recipe.pixel_size, 1, 8, 1, func(value: float) -> void: _change_recipe("pixel_size", int(value)))
	for field in ["base_color", "detail_color"]:
		left.add_child(StudioUI.label("基础颜色" if field == "base_color" else "细节颜色", 12))
		var color := ColorPickerButton.new()
		color.color = recipe.get(field)
		color.custom_minimum_size.y = 32
		color.color_changed.connect(func(value: Color) -> void: _change_recipe(field, value))
		left.add_child(color)
		_fields[field] = color
	StudioUI.choice(left, "应用到地图地形", MapData.TERRAIN_NAMES, 2, func(value: int) -> void: _recipe_terrain = value)
	left.add_child(StudioUI.button("应用纹理到地图", _apply_recipe, true))
	StudioUI.heading(left, "地块侧面", "底座只改变外观，保留地图高度数据。")
	_depth_field = StudioUI.number(left, "底座厚度", profile.base_thickness, 0, 64, 2, func(value: float) -> void:
		profile.base_thickness = int(value)
		_dirty = true
		base_thickness_changed.emit(int(value)))
	_fields.side_pattern = StudioUI.choice(left, "侧面纹理", ["随材质", "土层", "苔藓", "岩层", "砖墙", "水层"], recipe.side_pattern, func(value: int) -> void: _change_recipe("side_pattern", value))
	_fields.side_grain = StudioUI.number(left, "侧面细节", recipe.side_grain, 0, 1, 0.05, func(value: float) -> void: _change_recipe("side_grain", value))
	for field in ["side_color", "side_detail_color"]:
		left.add_child(StudioUI.label("侧面底色" if field == "side_color" else "侧面细节色", 12))
		var color := ColorPickerButton.new()
		color.color = recipe.get(field)
		color.edit_alpha = false
		color.custom_minimum_size.y = 32
		color.color_changed.connect(func(value: Color) -> void: _change_recipe(field, value))
		left.add_child(color)
		_fields[field] = color
	left.add_child(StudioUI.button("导出当前地块 PNG", func() -> void: _choose(FileDialog.FILE_MODE_SAVE_FILE, ["*.png ; 透明地块图片"], "block.png", _save_block)))
	left.add_child(StudioUI.button("导出纹理 PNG", func() -> void: _choose(FileDialog.FILE_MODE_SAVE_FILE, ["*.png ; PNG 图片"], "texture.png", _save_png)))
	left.add_child(StudioUI.button("保存纹理配方", func() -> void: _choose(FileDialog.FILE_MODE_SAVE_FILE, ["*.tres ; 纹理配方"], "texture_recipe.tres", func(path: String) -> void: _report_save(ResourceSaver.save(recipe, path), path))))
	left.add_child(StudioUI.button("载入纹理配方", func() -> void: _choose(FileDialog.FILE_MODE_OPEN_FILE, ["*.tres ; 纹理配方"], "", _load_recipe)))
	_preview_tabs = TabContainer.new()
	_preview_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_tabs.custom_minimum_size.x = 320
	add_child(_preview_tabs)
	_block_preview = MapBlockPreview.new()
	_block_preview.name = "立体地块"
	_preview_tabs.add_child(_block_preview)
	_preview = Control.new()
	_preview.name = "3×3 平铺"
	_preview.set_script(preload("res://addons/jeff_map_studio/ui/texture_preview.gd"))
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size.x = 260
	_preview_tabs.add_child(_preview)
	var right := StudioUI.scroll_column(self, 300)
	StudioUI.heading(right, "地块集与图集", "导入后点击图集选格，绑定地形与邻接规则。")
	StudioUI.number(right, "图集格宽", _region.x, 8, 512, 1, func(v: float) -> void: _region.x = int(v))
	StudioUI.number(right, "图集格高", _region.y, 8, 512, 1, func(v: float) -> void: _region.y = int(v))
	StudioUI.number(right, "边距 X / Y", 0, 0, 128, 1, func(v: float) -> void: _margin = Vector2i.ONE * int(v))
	StudioUI.number(right, "间隔 X / Y", 0, 0, 128, 1, func(v: float) -> void: _separation = Vector2i.ONE * int(v))
	right.add_child(StudioUI.button("导入 PNG 图集", func() -> void: _choose(FileDialog.FILE_MODE_OPEN_FILE, ["*.png ; PNG 图集"], "", _import_png)))
	right.add_child(StudioUI.button("载入 TileSet / TileLibrary", func() -> void: _choose(FileDialog.FILE_MODE_OPEN_FILE, ["*.tres,*.res ; Godot 素材资源"], "", _import_resource)))
	_atlas_preview = Control.new()
	_atlas_preview.set_script(preload("res://addons/jeff_map_studio/ui/atlas_preview.gd"))
	_atlas_preview.tile_selected.connect(func(coords: Vector2i) -> void:
		_binding_coords = coords
		_fields.atlas_x.set_value_no_signal(coords.x)
		_fields.atlas_y.set_value_no_signal(coords.y))
	right.add_child(_atlas_preview)
	_fields.binding_terrain = StudioUI.choice(right, "规则地形", MapData.TERRAIN_NAMES, 2, func(v: int) -> void: _binding_terrain = v)
	StudioUI.choice(right, "地块用途", ["顶面", "侧面", "装饰"], 0, func(v: int) -> void: _binding_role = v)
	_fields.source_id = StudioUI.number(right, "来源 ID", 0, 0, 10000, 1, func(v: float) -> void:
		_binding_source = int(v)
		_refresh_atlas())
	_fields.atlas_x = StudioUI.number(right, "格子 X", 0, 0, 512, 1, func(v: float) -> void:
		_binding_coords.x = int(v)
		_atlas_preview.selected = _binding_coords
		_atlas_preview.queue_redraw())
	_fields.atlas_y = StudioUI.number(right, "格子 Y", 0, 0, 512, 1, func(v: float) -> void:
		_binding_coords.y = int(v)
		_atlas_preview.selected = _binding_coords
		_atlas_preview.queue_redraw())
	StudioUI.number(right, "替代瓦片 ID", 0, 0, 65535, 1, func(v: float) -> void: _binding_alternative = int(v))
	StudioUI.number(right, "边掩码（-1 通用）", -1, -1, 63, 1, func(v: float) -> void: _binding_mask = int(v))
	StudioUI.number(right, "角掩码（方形）", -1, -1, 15, 1, func(v: float) -> void: _binding_corner = int(v))
	StudioUI.number(right, "随机权重", 1, 0.01, 100, 0.1, func(v: float) -> void: _binding_weight = v)
	StudioUI.choice(right, "装饰规则类型", ["任意装饰", "树木", "石头", "木箱", "蘑菇群", "棕榈树", "灯塔"], 0, func(v: int) -> void: _binding_decoration = -1 if v == 0 else v)
	right.add_child(StudioUI.button("添加瓦片绑定", _add_rule))
	StudioUI.number(right, "绘制原点 X", 0, -512, 512, 1, func(v: float) -> void: _texture_origin.x = int(v))
	StudioUI.number(right, "绘制原点 Y", 0, -512, 512, 1, func(v: float) -> void: _texture_origin.y = int(v))
	StudioUI.number(right, "排序锚点 Y", 0, -512, 512, 1, func(v: float) -> void: _sort_origin = int(v))
	right.add_child(StudioUI.button("设置选中瓦片锚点", _set_tile_anchor))
	right.add_child(StudioUI.button("读取 TileSet Terrain 规则", _read_native))
	_rules = ItemList.new()
	_rules.custom_minimum_size.y = 120
	right.add_child(_rules)
	right.add_child(StudioUI.button("删除选中绑定", func() -> void:
		if not _rules.get_selected_items().is_empty():
			library.rules.remove_at(_rules.get_selected_items()[0])
			_refresh_rules()))
	right.add_child(StudioUI.button("应用素材库到地图", func() -> void: library_applied.emit(library.duplicate(true)), true))
	right.add_child(StudioUI.button("保存素材库", func() -> void: _choose(FileDialog.FILE_MODE_SAVE_FILE, ["*.tres ; 素材库"], "tile_library.tres", func(path: String) -> void: _report_save(ResourceSaver.save(library, path), path))))
	right.add_child(StudioUI.button("恢复内置素材库", func() -> void:
		library = TileLibrary.new()
		_refresh_atlas()
		_refresh_rules()
		library_applied.emit(library)))

func _process(_delta: float) -> void:
	if _thread != null and not _thread.is_alive():
		var result: Dictionary = _thread.wait_to_finish()
		_image = result.texture
		_thread = null
		if _image != null:
			_preview.texture = ImageTexture.create_from_image(_image)
			_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if recipe.style == MapProfile.Style.PIXEL else CanvasItem.TEXTURE_FILTER_LINEAR
			_block_preview.textures.clear()
			for block: Image in result.blocks:
				_block_preview.textures.append(ImageTexture.create_from_image(block))
			_block_preview.texture_filter = _preview.texture_filter
			_block_preview.queue_redraw()
	if _dirty and _thread == null and is_visible_in_tree():
		_dirty = false
		var validation := recipe.validate() if profile.validate().is_empty() else profile.validate()
		if not validation.is_empty():
			status_message.emit(validation)
			return
		var snapshot := recipe.duplicate(true) as TextureRecipe
		var depth := profile.base_thickness * 128 / profile.tile_size
		var landmark := preview_decoration
		_thread = Thread.new()
		var result := _thread.start(func() -> Dictionary:
			var blocks: Array[Image] = []
			for shape in 3:
				blocks.append(MapBlockSurface.thumbnail(snapshot, shape, depth, 128, landmark))
			return {"texture": MapTextureFactory.create(snapshot), "blocks": blocks})
		if result != OK:
			_thread = null
			status_message.emit("无法启动纹理预览线程。")

func _change_recipe(key: String, value: Variant) -> void:
	if _syncing:
		return
	recipe.set(key, value)
	_dirty = true

func _set_material(value: int) -> void:
	recipe = TextureRecipe.preset(value, recipe.style)
	_sync_recipe()

func _sync_recipe() -> void:
	_syncing = true
	for key: String in _fields:
		if key.begins_with("atlas_") or key in ["binding_terrain", "source_id"]:
			continue
		var control: Control = _fields[key]
		if control is OptionButton:
			control.select(recipe.get(key))
		elif control is SpinBox:
			control.set_value_no_signal(recipe.get(key))
		elif control is CheckButton:
			control.set_pressed_no_signal(recipe.get(key))
		elif control is ColorPickerButton:
			var value: Color = recipe.get(key)
			if key == "side_color" and value.a == 0.0:
				value = recipe.base_color.darkened(0.18)
			elif key == "side_detail_color" and value.a == 0.0:
				value = recipe.detail_color.darkened(0.2)
			control.color = value
	_syncing = false
	_dirty = true

func _apply_recipe() -> void:
	if library.tile_set != null:
		status_message.emit("程序纹理用于内置地块。请先恢复内置素材库，再应用配方；外部图集可另行保存。")
		return
	if library.recipes.size() < 8:
		library.recipes.resize(8)
	library.recipes[_recipe_terrain] = recipe.duplicate(true)
	library_applied.emit(library.duplicate(true))
	status_message.emit("已应用 %s 纹理。地图的像素／手绘风格设置保持不变；地图物品使用装饰画笔放置。" % MapData.TERRAIN_NAMES[_recipe_terrain])

func _import_png(path: String) -> void:
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		status_message.emit("无法读取 PNG：" + path)
		return
	var imported := TileLibrary.import_atlas(ImageTexture.create_from_image(image), _region, _margin, _separation, profile)
	if imported == null or imported.tile_set.get_source(0).get_tiles_count() == 0:
		status_message.emit("图集切分后没有格子，请检查格子尺寸、间隔和边距。")
		return
	library = imported
	library.display_name = path.get_file()
	library.attribution = "Imported by user: " + path.get_file()
	_binding_source = 0
	_refresh_atlas()
	_refresh_rules()
	status_message.emit("图集已导入。请选择瓦片并绑定地形，再应用素材库。")

func _import_resource(path: String) -> void:
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource is TileLibrary:
		library = resource.duplicate(true)
	elif resource is TileSet:
		library = TileLibrary.new()
		library.tile_set = resource.duplicate(true)
		library.display_name = path.get_file()
		library.layout_grid = profile.grid
		library.layout_projection = profile.projection
		library.layout_orientation = profile.hex_orientation
	else:
		status_message.emit("请选择 TileSet 或 TileLibrary 资源。")
		return
	_binding_source = library.tile_set.get_source_id(0) if library.tile_set != null and library.tile_set.get_source_count() > 0 else 0
	_refresh_atlas()
	_refresh_rules()
	status_message.emit("素材已载入，请核对形状、尺寸和绑定后应用。")

func _add_rule() -> void:
	if library.tile_set == null or not library.tile_set.has_source(_binding_source):
		status_message.emit("请先导入图集，并选择有效来源 ID。")
		return
	var source := library.tile_set.get_source(_binding_source) as TileSetAtlasSource
	if source == null or not source.has_tile(_binding_coords) or not source.has_alternative_tile(_binding_coords, _binding_alternative):
		status_message.emit("该格子或替代瓦片不存在。")
		return
	var rule := MapTileRule.new()
	rule.terrain = _binding_terrain
	rule.role = _binding_role as MapTileRule.Role
	rule.source_id = _binding_source
	rule.atlas_coords = _binding_coords
	rule.alternative_id = _binding_alternative
	rule.decoration_id = _binding_decoration
	rule.neighbor_mask = _binding_mask
	rule.corner_mask = _binding_corner
	rule.weight = _binding_weight
	library.rules.append(rule)
	_refresh_rules()

func _read_native() -> void:
	var count := library.read_native_terrains(profile)
	_refresh_rules()
	status_message.emit("读取 %d 条规则。原生 Terrain 0–7 对应本工具的水域到地板，请核对语义。" % count)

func _refresh_atlas() -> void:
	_fields.source_id.set_value_no_signal(_binding_source)
	_atlas_preview.source = library.tile_set.get_source(_binding_source) as TileSetAtlasSource if library.tile_set != null and library.tile_set.has_source(_binding_source) else null
	_atlas_preview.queue_redraw()

func _set_tile_anchor() -> void:
	if library.tile_set == null or not library.tile_set.has_source(_binding_source):
		status_message.emit("请先导入图集。")
		return
	var source := library.tile_set.get_source(_binding_source) as TileSetAtlasSource
	if source == null or not source.has_tile(_binding_coords) or not source.has_alternative_tile(_binding_coords, _binding_alternative):
		status_message.emit("请先选择有效瓦片。")
		return
	var tile := source.get_tile_data(_binding_coords, _binding_alternative)
	tile.texture_origin = _texture_origin
	tile.y_sort_origin = _sort_origin
	status_message.emit("锚点已设置，应用素材库后查看。正绘制原点会使图片向左／向上偏移。")

func _refresh_rules() -> void:
	_rules.clear()
	for rule in library.rules:
		_rules.add_item("%s · %s · %s · mask %d · ×%s" % [MapData.TERRAIN_NAMES[clampi(rule.terrain, 0, 7)], ["顶面", "侧面", "装饰"][rule.role], rule.atlas_coords, rule.neighbor_mask, rule.weight])

func _load_recipe(path: String) -> void:
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as TextureRecipe
	if loaded == null:
		status_message.emit("该文件不是 TextureRecipe。")
		return
	if not loaded.validate().is_empty():
		status_message.emit(loaded.validate())
		return
	recipe = loaded
	_sync_recipe()

func _save_png(path: String) -> void:
	# Export the current recipe, even when an older preview is still visible.
	var image := MapTextureFactory.create(recipe)
	_report_save(image.save_png(path) if image != null else ERR_INVALID_DATA, path)

func _save_block(path: String) -> void:
	var validation := recipe.validate() if profile.validate().is_empty() else profile.validate()
	if not validation.is_empty():
		status_message.emit(validation)
		return
	var width := clampi(recipe.resolution, 16, 256)
	width += width % 2
	var depth := roundi(float(profile.base_thickness) * width / profile.tile_size)
	var image := MapBlockSurface.thumbnail(recipe, _block_preview.selected, depth, width, preview_decoration)
	_report_save(image.save_png(path), path)

func _report_save(result: Error, path: String) -> void:
	status_message.emit("已保存：" + path if result == OK else "保存失败：" + error_string(result))

func _choose(mode: int, filters: Array, filename: String, callback: Callable) -> void:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode as FileDialog.FileMode
	dialog.filters = PackedStringArray(filters)
	dialog.current_dir = ProjectSettings.globalize_path("res://")
	dialog.current_file = filename
	dialog.size = Vector2i(850, 600)
	add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		callback.call(ProjectSettings.localize_path(path))
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
