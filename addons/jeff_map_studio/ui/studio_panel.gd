@tool
class_name MapStudioPanel
extends VBoxContainer

signal apply_requested(data: MapData, library: TileLibrary)
signal files_saved

const WEB_PROJECT_URL := "https://github.com/jeffstudio-dev/jeff-map-studio"
const WEB_MAP_SIZE := 64
var profile := MapProfile.new()
var library := TileLibrary.new()
var canvas: MapStudioCanvas
var texture_workbench: MapTextureWorkbench
var _fields: Dictionary = {}
var _status: Label
var _hover_status: Label
var _progress: ProgressBar
var _generate_button: Button
var _cancel_button: Button
var _undo_button: Button
var _redo_button: Button
var _tabs: TabContainer
var _history: Array[Dictionary] = []
var _history_index: int = -1
var _history_previous_index: int = -1
var _pending_kind: String = ""
var _pending_fit: bool = true
var _syncing: bool = false
var _auto_preview: bool = false
var _debounce: Timer
var _display_pending: bool = false

func _init() -> void:
	profile.base_thickness = 16

func _ready() -> void:
	theme = StudioUI.theme()
	add_theme_constant_override("separation", 12)
	_build_header()
	_build_toolbar()
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_tabs)
	_build_map_tab()
	texture_workbench = MapTextureWorkbench.new()
	texture_workbench.name = "纹理与地块"
	texture_workbench.profile = profile
	texture_workbench.library = library
	texture_workbench.library_applied.connect(_apply_library)
	texture_workbench.base_thickness_changed.connect(func(value: int) -> void: _parameter("base_thickness", value))
	texture_workbench.status_message.connect(_set_status)
	_tabs.add_child(texture_workbench)
	var footer := HBoxContainer.new()
	_status = StudioUI.label("准备就绪 · 选择预设，或调整参数后生成", 12, Color("9db7b4"))
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	footer.add_child(_status)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(160, 16)
	_progress.show_percentage = false
	footer.add_child(_progress)
	add_child(footer)
	_debounce = Timer.new()
	_debounce.wait_time = 0.3
	_debounce.one_shot = true
	_debounce.timeout.connect(func() -> void:
		if _display_pending:
			_display_pending = false
			_refresh_presentation()
		elif _auto_preview and profile.width <= 128 and profile.height <= 128:
			generate_map())
	add_child(_debounce)
	canvas.map.generation_completed.connect(_on_completed)
	canvas.map.generation_progress.connect(func(value: float, stage: String) -> void:
		_progress.value = value * 100
		_set_status(stage))
	canvas.map.generation_failed.connect(_on_failed)
	canvas.map.generation_cancelled.connect(_on_cancelled)
	canvas.edit_rejected.connect(_on_failed)
	canvas.stroke_committed.connect(func(_before: MapData, after: MapData) -> void:
		_push_history(after)
		_set_status("手绘修改已记录 · 锁定区域会在重新生成时保留"))
	canvas.edit_requested.connect(func(_before: MapData, after: MapData) -> void:
		_pending_kind = "edit"
		_pending_fit = false
		_set_busy(true)
		canvas.map.apply_data(after))
	canvas.cell_hovered.connect(func(cell: Vector2i, info: Dictionary) -> void:
		_hover_status.text = "滚轮缩放 · 右键 / 中键拖动画布" if info.is_empty() else "(%d, %d)  %s  高度 %d%s" % [cell.x, cell.y, MapData.TERRAIN_NAMES[info.terrain] if info.terrain >= 0 else "空", info.height, "  · 已锁定" if info.locked else ""])
	_update_history_buttons()
	if not Engine.is_editor_hint():
		call_deferred("ensure_initialized")

func _build_header() -> void:
	var header := HBoxContainer.new()
	var icon := TextureRect.new()
	icon.texture = StudioUI.logo()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(48, 48)
	header.add_child(icon)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(StudioUI.label("JEFF  /  MAP STUDIO", 24, Color("e5eedf")))
	titles.add_child(StudioUI.label("种子生成   /   手绘地形   /   程序纹理", 12, Color("8eaaa7")))
	header.add_child(titles)
	header.add_child(StudioUI.label("GODOT 4.7   ·   v1.1", 12, Color("85b59c")))
	add_child(header)

func _build_toolbar() -> void:
	var toolbar := HBoxContainer.new()
	_generate_button = StudioUI.button("生成地图", generate_map, true)
	toolbar.add_child(_generate_button)
	toolbar.add_child(StudioUI.button("随机种子", func() -> void:
		profile.seed_value = int(Time.get_ticks_usec()) & 0x7fffffff
		_sync_fields()
		generate_map()))
	_cancel_button = StudioUI.button("取消", func() -> void: canvas.map.cancel_generation())
	_cancel_button.disabled = true
	toolbar.add_child(_cancel_button)
	toolbar.add_child(VSeparator.new())
	_undo_button = StudioUI.button("撤销", undo)
	_redo_button = StudioUI.button("重做", redo)
	toolbar.add_child(_undo_button)
	toolbar.add_child(_redo_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	if OS.has_feature("web"):
		# The browser build cannot write project files; saving lives in the plugin itself.
		toolbar.add_child(StudioUI.button("下载插件以保存和导出", func() -> void: OS.shell_open(WEB_PROJECT_URL)))
	else:
		toolbar.add_child(StudioUI.button("打开", _open_dialog))
		toolbar.add_child(StudioUI.button("保存地图", func() -> void: _save_dialog("map")))
		toolbar.add_child(StudioUI.button("保存配置", func() -> void: _save_dialog("profile")))
		toolbar.add_child(StudioUI.button("导出场景", func() -> void: _save_dialog("scene")))
	if Engine.is_editor_hint():
		toolbar.add_child(StudioUI.button("应用到当前场景", func() -> void:
			if canvas.map.map_data != null and not canvas.map.busy:
				apply_requested.emit(canvas.map.map_data.copy(), library.duplicate(true)), true))
	add_child(toolbar)

func _build_map_tab() -> void:
	var body := HBoxContainer.new()
	body.name = "地图工作区"
	body.add_theme_constant_override("separation", 16)
	_tabs.add_child(body)
	var left := StudioUI.scroll_column(body, 170)
	StudioUI.heading(left, "开始一张地图", "预设会创建新地图配置。")
	var presets := [
		["海岸群岛", "沙滩 · 森林 · 浅海", 0, 0, 1, 0],
		["高原大陆", "岩层 · 高差 · 雪地", 0, 0, 1, 1],
		["石砖地牢", "房间 · 回路 · 走廊", 1, 0, 0, 0],
		["天然洞穴", "洞室 · 随机通道", 2, 0, 0, 0],
		["六角群岛", "六角柱 · 等角地块", 0, 1, 1, 1],
		["六角地牢", "六边形房间 · 走廊", 1, 1, 1, 0]]
	for item in presets:
		var button := StudioUI.button(item[0] + "\n" + item[1], func() -> void: _preset(item))
		button.custom_minimum_size.y = 58
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 13)
		left.add_child(button)
	StudioUI.heading(left, "地形画笔")
	for i in MapData.TERRAIN_NAMES.size():
		var button := StudioUI.button("●  " + MapData.TERRAIN_NAMES[i], func() -> void:
			canvas.terrain_id = i
			canvas.tool = MapEdits.Tool.TERRAIN
			_fields.tool.select(MapEdits.Tool.TERRAIN))
		button.add_theme_color_override("font_color", MapAtlasBuilder.PALETTE[i].lightened(0.15))
		left.add_child(button)
	var note := StudioUI.label("锁定仅保护重新生成。\n手绘仍可修改锁定格子。\n\n高度用于视觉表现，\n不会自动改变游戏通行。", 12, Color("8ba29e"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(note)
	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(middle)
	var brushbar := HBoxContainer.new()
	var tools := OptionButton.new()
	for title in ["选择", "地形画笔", "擦除", "区域填充", "升高", "降低", "装饰", "锁定", "解锁"]:
		tools.add_item(title)
	tools.item_selected.connect(func(v: int) -> void: canvas.tool = v)
	tools.custom_minimum_size.x = 120
	_fields.tool = tools
	brushbar.add_child(tools)
	brushbar.add_child(StudioUI.label("半径", 12))
	var radius := SpinBox.new()
	radius.max_value = 6
	radius.custom_minimum_size.x = 72
	radius.value_changed.connect(func(v: float) -> void: canvas.radius = int(v))
	brushbar.add_child(radius)
	var decorations := OptionButton.new()
	for title in MapData.DECORATION_NAMES:
		decorations.add_item(title)
	decorations.select(1)
	decorations.item_selected.connect(func(v: int) -> void: canvas.decoration_id = v)
	brushbar.add_child(decorations)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brushbar.add_child(spacer)
	brushbar.add_child(StudioUI.button("适应画布", func() -> void: canvas.fit_map()))
	middle.add_child(brushbar)
	canvas = MapStudioCanvas.new()
	canvas.custom_minimum_size = Vector2(380, 320)
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_child(canvas)
	_hover_status = StudioUI.label("滚轮缩放 · 右键 / 中键拖动画布", 12, Color("829b9f"))
	middle.add_child(_hover_status)
	var right := StudioUI.scroll_column(body, 256)
	StudioUI.heading(right, "生成参数")
	_choice(right, "生成器", "generator", ["自然地形", "房间地牢", "洞穴"])
	_number(right, "随机种子", "seed_value", 0, 2147483647, 1)
	_number(right, "宽度", "width", 8, 512, 1)
	_number(right, "高度", "height", 8, 512, 1)
	_choice(right, "网格", "grid", ["方形", "六角"])
	_choice(right, "显示", "projection", ["俯视", "等角"])
	_choice(right, "六角朝向", "hex_orientation", ["尖顶", "平顶"])
	_choice(right, "纹理风格", "style", ["像素风", "手绘风"])
	_number(right, "地块尺寸", "tile_size", 16, 128, 2)
	_number(right, "每层像素高度", "height_step", 2, 32, 2)
	_number(right, "底座厚度（像素）", "base_thickness", 0, 64, 2)
	_number(right, "生成最高层数", "max_height", 0, 16, 1)
	var auto := CheckButton.new()
	auto.text = "自动预览（≤128²）"
	auto.toggled.connect(func(value: bool) -> void: _auto_preview = value)
	right.add_child(auto)
	StudioUI.heading(right, "自然地形")
	var island := CheckButton.new()
	island.text = "海岛边缘衰减"
	island.button_pressed = profile.island
	island.toggled.connect(func(value: bool) -> void: _parameter("island", value))
	right.add_child(island)
	_fields.island = island
	_number(right, "噪声尺度", "noise_scale", 0.002, 0.15, 0.001)
	_number(right, "噪声层数", "octaves", 1, 6, 1)
	_number(right, "海平面", "sea_level", 0, 0.95, 0.01)
	_number(right, "沙滩宽度", "beach_width", 0.01, 0.2, 0.01)
	_number(right, "山地强度", "mountain_strength", 0, 2, 0.05)
	_number(right, "高度平滑", "smoothing", 0, 4, 1)
	_number(right, "装饰密度", "decoration_density", 0, 0.8, 0.01)
	StudioUI.heading(right, "房间地牢")
	_number(right, "房间数量", "room_count", 2, 80, 1)
	_number(right, "最小房间尺寸", "room_min_size", 2, 20, 1)
	_number(right, "最大房间尺寸", "room_max_size", 3, 30, 1)
	_number(right, "走廊宽度", "corridor_width", 1, 5, 1)
	_number(right, "额外连边概率", "extra_connection_chance", 0, 1, 0.05)
	StudioUI.heading(right, "洞穴")
	_number(right, "初始墙体比例", "cave_fill", 0.1, 0.85, 0.01)
	_number(right, "平滑迭代", "cave_iterations", 0, 10, 1)
	_number(right, "最小区域面积", "min_region_area", 1, 1000, 1)

func _choice(parent: Control, title: String, key: String, items: Array) -> void:
	_fields[key] = StudioUI.choice(parent, title, items, profile.get(key), func(value: int) -> void: _parameter(key, value))

func _number(parent: Control, title: String, key: String, minimum: float, maximum: float, step: float) -> void:
	_fields[key] = StudioUI.number(parent, title, profile.get(key), minimum, maximum, step, func(value: float) -> void: _parameter(key, int(value) if step >= 1 else value))

func _parameter(key: String, value: Variant) -> void:
	if _syncing:
		return
	profile.set(key, value)
	texture_workbench.profile = profile
	_set_status("配置已修改 · 点击生成以应用")
	if key in ["projection", "style", "hex_orientation", "tile_size", "height_step", "base_thickness"]:
		_display_pending = true
		_debounce.start()
	elif _auto_preview:
		_debounce.start()

func _sync_fields() -> void:
	_syncing = true
	for key: String in _fields:
		if key == "tool":
			continue
		var control: Control = _fields[key]
		if control is SpinBox:
			control.set_value_no_signal(profile.get(key))
		elif control is OptionButton:
			control.select(profile.get(key))
		elif control is CheckButton:
			control.set_pressed_no_signal(profile.get(key))
	_syncing = false
	texture_workbench.profile = profile

func ensure_initialized() -> void:
	if canvas.map.map_data == null and not canvas.map.busy:
		_fit_web(profile)
		_sync_fields()
		generate_map()

## Browser builds run generation on the main thread; start from smaller maps there.
func _fit_web(settings: MapProfile) -> void:
	if OS.has_feature("web"):
		settings.width = mini(settings.width, WEB_MAP_SIZE)
		settings.height = mini(settings.height, WEB_MAP_SIZE)

func generate_map() -> void:
	_debounce.stop()
	_display_pending = false
	_pending_kind = "generate"
	_pending_fit = canvas.map.map_data == null or canvas.map.map_data.profile.width != profile.width or canvas.map.map_data.profile.height != profile.height or canvas.map.map_data.profile.grid != profile.grid
	canvas.map.tile_library = library
	_set_busy(true)
	canvas.map.generate(profile)

func _preset(item: Array) -> void:
	profile = MapProfile.new()
	profile.generator = item[2]
	profile.grid = item[3]
	profile.projection = item[4]
	profile.style = item[5]
	profile.base_thickness = 16
	_fit_web(profile)
	profile.island = item[0] != "高原大陆"
	if profile.generator != MapProfile.Generator.NATURE:
		profile.decoration_density = 0.02
		profile.max_height = 2
	var library_path := "res://addons/jeff_map_studio/examples/libraries/%s_%s.tres" % ["nature" if profile.generator == 0 else "dungeon", "pixel" if profile.style == 0 else "soft"]
	library = (load(library_path) as TileLibrary).duplicate(true) if ResourceLoader.exists(library_path) else TileLibrary.new()
	texture_workbench.use_library(library)
	_sync_fields()
	_pending_fit = true
	generate_map()
	_pending_fit = true

func _refresh_presentation() -> void:
	if canvas.map.map_data == null or canvas.map.map_data.profile.grid != profile.grid:
		return
	var data := canvas.map.map_data.copy()
	for key in ["projection", "style", "hex_orientation", "tile_size", "height_step", "base_thickness"]:
		data.profile.set(key, profile.get(key))
	data.tile_library = library
	_pending_kind = "presentation"
	_pending_fit = data.profile.projection != canvas.map.map_data.profile.projection or data.profile.hex_orientation != canvas.map.map_data.profile.hex_orientation
	_set_busy(true)
	canvas.map.apply_data(data)

func _apply_library(value: TileLibrary) -> void:
	library = value
	canvas.map.tile_library = library
	if canvas.map.map_data != null:
		var data := canvas.map.map_data.copy()
		data.tile_library = library
		_pending_kind = "library"
		_pending_fit = false
		_set_busy(true)
		canvas.map.apply_data(data)

func _on_completed(data: MapData) -> void:
	if _pending_kind != "history":
		_push_history(data)
	if _pending_kind in ["generate", "history", "load"]:
		profile = data.profile.copy()
	_sync_fields()
	if _pending_fit:
		canvas.fit_map()
	_pending_kind = ""
	_history_previous_index = -1
	_set_busy(false)
	var extra := ""
	if data.metadata.get("regions_after_locks", 1) > 1:
		extra = " · 锁定修改使开放区域分离"
	_set_status("%d × %d · seed %d · %.2f 秒 · 保留 %d 个锁定格子%s" % [data.profile.width, data.profile.height, data.profile.seed_value, data.metadata.get("total_ms", 0.0) / 1000.0, data.metadata.get("preserved_cells", 0), extra])

func _on_failed(message: String) -> void:
	if _history_previous_index >= 0:
		_history_index = _history_previous_index
		_history_previous_index = -1
	_pending_kind = ""
	_restore_active_library()
	_set_busy(false)
	_set_status(message)
	var dialog := AcceptDialog.new()
	dialog.title = "地图未更新"
	dialog.dialog_text = message
	dialog.min_size = Vector2i(480, 150)
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _restore_active_library() -> void:
	if canvas.map.map_data != null:
		library = canvas.map.map_data.tile_library if canvas.map.map_data.tile_library != null else TileLibrary.new()
		canvas.map.tile_library = library

func _on_cancelled() -> void:
	if _history_previous_index >= 0:
		_history_index = _history_previous_index
		_history_previous_index = -1
	_pending_kind = ""
	_restore_active_library()
	_set_busy(false)
	_set_status("已取消，保留上一份完整地图。")

func _push_history(data: MapData) -> void:
	while _history.size() > _history_index + 1:
		_history.pop_back()
	_history.append({"data": data.copy(), "library": library.duplicate(true)})
	if _history.size() > 16:
		_history.pop_front()
	_history_index = _history.size() - 1
	_update_history_buttons()

func undo() -> void:
	if _history_index > 0 and not canvas.map.busy:
		_restore_history(_history_index - 1)

func redo() -> void:
	if _history_index + 1 < _history.size() and not canvas.map.busy:
		_restore_history(_history_index + 1)

func _restore_history(index: int) -> void:
	_history_previous_index = _history_index
	_history_index = index
	var item := _history[index]
	library = item.library.duplicate(true)
	texture_workbench.use_library(library)
	canvas.map.tile_library = library
	var data := item.data.copy() as MapData
	data.tile_library = library
	_pending_kind = "history"
	_pending_fit = false
	_set_busy(true)
	canvas.map.apply_data(data)

func _update_history_buttons() -> void:
	_undo_button.disabled = _history_index <= 0 or (canvas != null and canvas.map != null and canvas.map.busy)
	_redo_button.disabled = _history_index + 1 >= _history.size() or (canvas != null and canvas.map != null and canvas.map.busy)

func _set_busy(value: bool) -> void:
	_generate_button.disabled = value
	_cancel_button.disabled = not value
	for key: String in _fields:
		if key == "tool":
			continue
		var control: Control = _fields[key]
		if control is SpinBox:
			control.editable = not value
		elif control is BaseButton:
			control.disabled = value
	_update_history_buttons()

func _set_status(message: String) -> void:
	if _status != null:
		_status.text = message
		_status.tooltip_text = message

func _open_dialog() -> void:
	_file_dialog(FileDialog.FILE_MODE_OPEN_FILE, "*.tres,*.res ; 地图或配置", "", func(path: String) -> void:
		var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if loaded is MapProfile:
			profile = loaded.copy()
			_sync_fields()
			_set_status("配置已载入，点击生成。")
		elif loaded is MapData:
			_pending_kind = "load"
			_pending_fit = true
			library = loaded.tile_library if loaded.tile_library != null else TileLibrary.new()
			texture_workbench.use_library(library)
			canvas.map.tile_library = library
			_set_busy(true)
			canvas.map.apply_data(loaded)
		else:
			_set_status("请选择 MapData 或 MapProfile 资源。"))

func _save_dialog(kind: String) -> void:
	if kind != "profile" and canvas.map.map_data == null:
		_set_status("请先生成地图。")
		return
	if canvas.map.busy:
		_set_status("请等待生成完成或取消，再保存。")
		return
	var extension := "tscn" if kind == "scene" else "tres"
	_file_dialog(FileDialog.FILE_MODE_SAVE_FILE, "*.%s ; Godot 资源" % extension, "jeff_%s.%s" % [kind, extension], func(path: String) -> void:
		var result: Error
		match kind:
			"profile": result = ResourceSaver.save(profile, path)
			"scene": result = canvas.map.bake_scene(path)
			_: result = canvas.map.save_map(path)
		_set_status("已保存：" + path if result == OK else "保存失败：" + error_string(result))
		if result == OK:
			files_saved.emit())

func _file_dialog(mode: int, filter_text: String, filename: String, callback: Callable) -> void:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode as FileDialog.FileMode
	dialog.filters = PackedStringArray([filter_text])
	dialog.current_dir = ProjectSettings.globalize_path("res://")
	dialog.current_file = filename
	dialog.size = Vector2i(850, 600)
	add_child(dialog)
	dialog.file_selected.connect(func(path: String) -> void:
		callback.call(ProjectSettings.localize_path(path))
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed:
		return
	if event.is_command_or_control_pressed() and event.keycode == KEY_Z:
		if event.shift_pressed:
			redo()
		else:
			undo()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F and canvas.has_focus():
		canvas.fit_map()
