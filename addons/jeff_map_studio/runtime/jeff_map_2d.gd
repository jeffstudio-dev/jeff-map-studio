@tool
class_name JeffMap2D
extends Node2D
## Both the editor and exported games use this node. No editor-only dependencies.

signal generation_progress(value: float, stage: String)
signal generation_completed(data: MapData)
signal generation_failed(message: String)
signal generation_cancelled

@export var profile: MapProfile = MapProfile.new()
@export var tile_library: TileLibrary
@export var map_data: MapData
@export var generate_on_ready: bool = false

var renderer: MapRenderer
var busy: bool = false
var _serial: int = 0
var _tasks: Array[Dictionary] = []
var _atlas_cache: Dictionary = {}
var _active_job: MapGenerationJob
var _start_time: int = 0

func _ready() -> void:
	if map_data != null:
		apply_data(map_data)
	elif generate_on_ready and not Engine.is_editor_hint():
		generate(profile)

func generate(settings: MapProfile = null) -> void:
	if settings == null:
		settings = profile
	_begin()
	if settings == null:
		_fail("请提供有效的 MapProfile。", _serial)
		return
	var snapshot := settings.copy()
	var previous := map_data.copy() if map_data != null else null
	var job := MapGenerationJob.new()
	_active_job = job
	var thread := MapWork.new()
	var token := _serial
	var result := thread.start(func() -> MapData: return MapGenerator.generate(snapshot, previous, job))
	if result != OK:
		_fail("无法启动生成线程：%s" % error_string(result), token)
		return
	_tasks.append({"thread": thread, "job": job, "token": token, "kind": "map"})

func apply_data(data: MapData) -> void:
	_begin()
	if data == null:
		_fail("请提供有效的 MapData。", _serial)
		return
	if data.tile_library != null:
		tile_library = data.tile_library
	var message := data.validate()
	if not message.is_empty():
		_fail(message, _serial)
		return
	_prepare_render(data.copy(), _serial)

func _begin() -> void:
	_cancel_work()
	_serial += 1
	busy = true
	_start_time = Time.get_ticks_usec()
	generation_progress.emit(0.0, "准备生成")

func _cancel_work() -> void:
	for task in _tasks:
		task.job.cancel()
	if _active_job != null:
		_active_job.cancel()
	_active_job = null

func cancel_generation() -> void:
	var was_busy := busy
	_cancel_work()
	_serial += 1
	busy = false
	if map_data != null:
		tile_library = map_data.tile_library
	if was_busy:
		generation_cancelled.emit()

func _process(_delta: float) -> void:
	if _active_job != null and busy:
		var status := _active_job.status()
		generation_progress.emit(float(status[0]) * 0.5, status[1])
	for i in range(_tasks.size() - 1, -1, -1):
		var task := _tasks[i]
		var thread: MapWork = task.thread
		if thread.is_alive():
			continue
		var result: Variant = thread.wait_to_finish()
		_tasks.remove_at(i)
		if task.token != _serial or task.job.is_cancelled():
			continue
		_active_job = null
		if task.kind == "map":
			if result == null:
				_fail(task.job.error if not task.job.error.is_empty() else "地图生成未完成。", task.token)
			else:
				_prepare_render(result as MapData, task.token)
		else:
			if result.is_empty():
				_fail("图集生成未完成。", task.token)
			else:
				var atlas: Dictionary = result
				atlas["tileset"] = MapAtlasBuilder.create_tileset(atlas, task.data.profile)
				# Keep only two layouts: changing presets cannot accumulate GPU atlases.
				if _atlas_cache.size() >= 2:
					_atlas_cache.erase(_atlas_cache.keys()[0])
				_atlas_cache[task.key] = atlas
				_build(task.data, atlas, task.token)

func _prepare_render(data: MapData, token: int) -> void:
	if token != _serial:
		return
	var library := tile_library
	if library != null:
		var message := library.validate_for(data)
		if not message.is_empty():
			_fail(message, token)
			return
	var key := MapAtlasBuilder.cache_key(data.profile, library)
	if _atlas_cache.has(key):
		_build(data, _atlas_cache[key], token)
		return
	var job := MapGenerationJob.new()
	_active_job = job
	var thread := MapWork.new()
	var library_copy := library.duplicate(true) as TileLibrary if library != null else null
	var result := thread.start(func() -> Dictionary: return MapAtlasBuilder.prepare_images(data.profile, library_copy, job))
	if result != OK:
		_fail("无法启动图集生成线程。", token)
		return
	_tasks.append({"thread": thread, "job": job, "token": token, "kind": "atlas", "key": key, "data": data})

func _build(data: MapData, atlas: Dictionary, token: int) -> void:
	var stage := MapRenderer.new()
	stage.name = "GeneratedMap"
	stage.visible = false
	add_child(stage)
	stage.setup(data, atlas, tile_library)
	var batch_start := Time.get_ticks_usec()
	for i in data.terrain.size():
		if token != _serial or not is_inside_tree():
			stage.queue_free()
			return
		stage.update_cell(data.cell_at(i))
		if not stage.error.is_empty():
			stage.queue_free()
			_fail(stage.error, token)
			return
		if i % 64 == 0 and Time.get_ticks_usec() - batch_start > 6000:
			generation_progress.emit(0.5 + 0.48 * i / data.terrain.size(), "铺设地块 %d / %d" % [i, data.terrain.size()])
			await get_tree().process_frame
			batch_start = Time.get_ticks_usec()
	if token != _serial:
		stage.queue_free()
		return
	if renderer != null:
		remove_child(renderer)
		renderer.queue_free()
	renderer = stage
	renderer.visible = true
	map_data = data
	map_data.tile_library = tile_library
	profile = data.profile.copy()
	map_data.metadata["total_ms"] = (Time.get_ticks_usec() - _start_time) / 1000.0
	map_data.metadata["static_memory_bytes"] = OS.get_static_memory_usage()
	busy = false
	generation_progress.emit(1.0, "完成")
	generation_completed.emit(map_data)

func _fail(message: String, token: int) -> void:
	if token != _serial:
		return
	busy = false
	_active_job = null
	if map_data != null:
		tile_library = map_data.tile_library
	generation_failed.emit(message)

func refresh_cells(cells: Array[Vector2i]) -> void:
	if renderer != null:
		renderer.refresh_cells(cells)

func get_cell(cell: Vector2i) -> Dictionary:
	return map_data.get_cell(cell) if map_data != null else {}

func cell_to_local(cell: Vector2i, include_height: bool = true) -> Vector2:
	if map_data == null:
		return MapGrid.cell_to_local(cell, profile)
	var h := int(map_data.elevation[map_data.index_of(cell)]) if include_height and map_data.contains(cell) else 0
	return MapGrid.cell_to_local(cell, map_data.profile, h)

func local_to_cell(point: Vector2) -> Vector2i:
	return MapGrid.pick_cell(point, map_data) if map_data != null else MapGrid.local_to_cell(point, profile)

func save_map(path: String) -> Error:
	if map_data == null:
		return ERR_UNCONFIGURED
	return ResourceSaver.save(map_data, path)

func clear_map() -> void:
	cancel_generation()
	if renderer != null:
		renderer.queue_free()
		renderer = null
	map_data = null

func bake_scene(path: String) -> Error:
	if renderer == null:
		return ERR_UNCONFIGURED
	var root := renderer.native_copy()
	var tiles := renderer.tile_set.duplicate(true) as TileSet
	var asset_dir := path.get_basename() + "_assets"
	var result := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(asset_dir))
	if result != OK:
		root.free()
		return result
	result = ResourceSaver.save(tiles, asset_dir.path_join("tileset.res"), ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_CHANGE_PATH)
	if result == OK:
		for child: TileMapLayer in root.get_children():
			child.tile_set = tiles
		for source_index in tiles.get_source_count():
			var source := tiles.get_source(tiles.get_source_id(source_index)) as TileSetAtlasSource
			if source != null:
				source.texture.get_image().save_png(asset_dir.path_join("atlas_%d.png" % source_index))
		var packed := PackedScene.new()
		result = packed.pack(root)
		if result == OK:
			result = ResourceSaver.save(packed, path, ResourceSaver.FLAG_RELATIVE_PATHS)
	root.free()
	return result

func _exit_tree() -> void:
	_cancel_work()
	_serial += 1
	for task in _tasks:
		var thread: MapWork = task.thread
		if thread.is_started():
			thread.wait_to_finish()
	_tasks.clear()
