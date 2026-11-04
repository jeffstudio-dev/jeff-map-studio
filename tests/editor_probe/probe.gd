@tool
extends EditorPlugin

var failures: Array[String] = []
var checks: int = 0

func _enter_tree() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("EDITOR FAIL: ", message)

func find_plugin(node: Node) -> Node:
	var script: Script = node.get_script() as Script
	if script != null and script.resource_path == "res://addons/jeff_map_studio/editor/plugin.gd":
		return node
	for child in node.get_children():
		var found := find_plugin(child)
		if found != null:
			return found
	return null

func idle(map: JeffMap2D) -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while map.busy and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(not map.busy, "Editor job finishes")

func run() -> void:
	await get_tree().process_frame
	var plugin := find_plugin(get_tree().root)
	check(plugin != null, "Plugin installed in a clean project")
	if plugin == null:
		finish()
		return
	var panel: MapStudioPanel = plugin.panel
	panel.profile.width = 48
	panel.profile.height = 40
	plugin._make_visible(true)
	panel.generate_map()
	await idle(panel.canvas.map)
	check(panel.canvas.map.map_data != null, "Editor tool generation works")
	EditorInterface.open_scene_from_path("res://fixture.tscn")
	await get_tree().process_frame
	var root := EditorInterface.get_edited_scene_root()
	check(root != null, "Editable scene opens")
	if root == null or panel.canvas.map.map_data == null:
		finish()
		return
	var count := root.get_child_count()
	plugin._apply(panel.canvas.map.map_data.copy(), panel.library)
	await get_tree().process_frame
	var target := root.get_child(count) as JeffMap2D
	check(target != null and target.owner == root, "Apply creates an owned map node")
	if target != null:
		await idle(target)
		check(target.map_data.content_hash() == panel.canvas.map.map_data.content_hash(), "Applied map matches preview")
		var manager: EditorUndoRedoManager = plugin.get_undo_redo()
		var history := manager.get_history_undo_redo(manager.get_object_history_id(root))
		history.undo()
		check(root.get_child_count() == count, "Editor Undo removes application")
		history.redo()
		await idle(target)
		check(root.get_child_count() == count + 1, "Editor Redo restores application")
		if DisplayServer.get_name() == "headless":
			# The dummy renderer has no scene thumbnail texture to read back.
			var previous := FileAccess.get_file_as_string("res://fixture.tscn")
			EditorInterface.save_scene_as("res://fixture.tscn", false)
			check(FileAccess.get_file_as_string("res://fixture.tscn") != previous, "Applied scene saves without a thumbnail")
		else:
			check(EditorInterface.save_scene() == OK, "Applied scene saves")
		var saved := ResourceLoader.load("res://fixture.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		var instance := saved.instantiate()
		var reloaded := instance.get_child(count) as JeffMap2D
		check(reloaded != null and reloaded.map_data != null, "Applied map data survives scene reload")
		instance.free()
	EditorInterface.set_main_screen_editor("Map Studio")
	await get_tree().process_frame
	panel.canvas.fit_map()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://editor_probe.png")
	finish()

func finish() -> void:
	var file := FileAccess.open("res://editor_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures}, "\t"))
	print("EDITOR TESTS: ", checks, " checks, ", failures.size(), " failures")
	get_tree().quit(0 if failures.is_empty() else 1)
