extends SceneTree

var failures: Array[String] = []
var checks: int = 0
var panel: MapStudioPanel
var output := "res://test_output"
var metrics: Array = []
var frame_count: int = 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func wait_idle(map: JeffMap2D, limit: float = 90.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(limit * 1000)
	while map.busy and Time.get_ticks_msec() < deadline:
		await process_frame
		frame_count += 1
	check(not map.busy, "Generation completed within timeout")
	return not map.busy

func screenshot(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image != null and not image.is_empty(), "Viewport image exists")
	if image != null:
		image.save_png(output.path_join(filename + ".png"))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var scene := load("res://demo/studio.tscn").instantiate() as Control
	root.add_child(scene)
	panel = scene.get_node("Margin/Studio") as MapStudioPanel
	var p := MapProfile.new()
	p.width = 40
	p.height = 36
	p.max_height = 5
	p.seed_value = 7342
	panel.profile = p
	panel.generate_map()
	await wait_idle(panel.canvas.map)
	check(panel.canvas.map.map_data != null, "Studio generates preview")
	if panel.canvas.map.map_data == null:
		quit(1)
		return
	var map := panel.canvas.map
	panel.canvas.fit_map()
	await screenshot("01_square_isometric")
	metrics.append(map.map_data.metadata.duplicate())
	var original_hash := map.map_data.content_hash()
	for grid in 2:
		for orientation in (2 if grid == 1 else 1):
			for projection in 2:
				var profile := p.copy()
				profile.grid = grid
				profile.hex_orientation = orientation
				profile.projection = projection
				profile.style = orientation
				panel.profile = profile
				panel.generate_map()
				await wait_idle(map)
				check(map.map_data != null and map.map_data.validate().is_empty(), "Preview data valid")
				panel.canvas.fit_map()
				var tops := 0
				for key: String in map.renderer.layers:
					if key.begins_with("top_"):
						tops += map.renderer.layers[key].get_used_cells().size()
				check(tops == profile.width * profile.height, "Exactly one top per cell")
				for cell in [Vector2i(3, 3), Vector2i(10, 12), Vector2i(20, 20)]:
					var picked := map.local_to_cell(map.cell_to_local(cell))
					check(picked == cell, "Elevated pick %s got %s, grid=%d projection=%d" % [cell, picked, grid, projection])
				await screenshot("grid_%d_orientation_%d_projection_%d" % [grid, orientation, projection])
	# Native canvas input closes a whole stroke as a single history transaction.
	var history_before := panel._history.size()
	panel.canvas.tool = MapEdits.Tool.LOCK
	var pressed := InputEventMouseButton.new()
	pressed.button_index = MOUSE_BUTTON_LEFT
	pressed.pressed = true
	pressed.position = panel.canvas.map.position + panel.canvas.map.cell_to_local(Vector2i(2, 2)) * panel.canvas.map.scale
	panel.canvas._gui_input(pressed)
	var released := pressed.duplicate() as InputEventMouseButton
	released.pressed = false
	panel.canvas._gui_input(released)
	check(map.get_cell(Vector2i(2, 2)).locked, "Mouse stroke locks the picked cell")
	check(panel._history.size() == history_before + 1, "Mouse stroke creates one undo entry")
	# Undo/redo snapshots include hand-painted data.
	var before := map.map_data.copy()
	var cell := Vector2i(6, 6)
	MapEdits.brush(map.map_data, cell, MapEdits.Tool.TERRAIN, MapData.Terrain.SNOW, 1, 0)
	MapEdits.brush(map.map_data, cell, MapEdits.Tool.LOCK, 0, 1, 0)
	map.refresh_cells([cell])
	var after_hash := map.map_data.content_hash()
	panel._push_history(map.map_data)
	panel.undo()
	await wait_idle(map)
	check(map.map_data.content_hash() == before.content_hash(), "UI undo")
	panel.redo()
	await wait_idle(map)
	check(map.map_data.content_hash() == after_hash, "UI redo")
	# Changing presentation must leave cell contents unchanged.
	panel.profile.style = 1 - panel.profile.style
	var draft_seed := panel.profile.seed_value + 100
	panel.profile.seed_value = draft_seed
	panel._refresh_presentation()
	await wait_idle(map)
	check(map.map_data.content_hash() == after_hash, "Style switch preserves painted cells")
	check(panel.profile.seed_value == draft_seed, "Style changes preserve ungenerated draft parameters")
	# Cancel a large worker and keep the committed map.
	var large := panel.profile.copy()
	large.width = 512
	large.height = 512
	map.generate(large)
	await process_frame
	var cancel_started := Time.get_ticks_msec()
	map.cancel_generation()
	await process_frame
	check(not map.busy and Time.get_ticks_msec() - cancel_started < 1000, "Cancellation responds in under 1 second")
	check(map.map_data.content_hash() == after_hash, "Cancelled request preserves map")
	# Native bake must instantiate without JeffMap2D or a renderer script.
	var path := output.path_join("baked_test.tscn")
	check(map.bake_scene(path) == OK, "Scene bake succeeds")
	var packed := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	check(packed != null, "Baked scene loads")
	if packed != null:
		var baked := packed.instantiate()
		check(baked.get_script() == null and baked.get_child_count() > 0, "Baked map is native nodes")
		baked.free()
	check(map.save_map(output.path_join("map_test.tres")) == OK, "Save current map")
	var loaded := ResourceLoader.load(output.path_join("map_test.tres"), "", ResourceLoader.CACHE_MODE_IGNORE) as MapData
	check(loaded != null and loaded.content_hash() == after_hash, "Current map reload")
	# Runtime data and editor preview data share exactly the same generator.
	var comparison := MapProfile.new()
	comparison.width = 32
	comparison.height = 32
	comparison.grid = MapProfile.Grid.SQUARE
	map.clear_map()
	map.generate(comparison)
	await wait_idle(map)
	var pure := MapGenerator.generate(comparison)
	check(map.map_data.content_hash() == pure.content_hash(), "Runtime and pure data generator agree")
	for generator in [MapProfile.Generator.DUNGEON, MapProfile.Generator.CAVE]:
		var sample := comparison.copy()
		sample.generator = generator
		sample.width = 48
		sample.height = 40
		sample.room_count = 8
		sample.room_max_size = 7
		sample.max_height = 2
		sample.decoration_density = 0.02
		panel.profile = sample
		panel.generate_map()
		await wait_idle(map)
		check(MapGenerator.floor_regions(map.map_data).size() == 1, "Rendered dungeon/cave connected")
		panel.canvas.fit_map()
		await screenshot("generator_%d" % generator)
	panel._tabs.current_tab = 1
	await create_timer(0.5).timeout
	await screenshot("02_texture_workbench")
	var report := {"checks": checks, "failures": failures, "initial_hash": original_hash, "render_frames": frame_count, "metrics": metrics, "engine": Engine.get_version_info().string}
	var file := FileAccess.open(output.path_join("integration_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("INTEGRATION TESTS: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
