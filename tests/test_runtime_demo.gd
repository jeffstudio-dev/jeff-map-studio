extends SceneTree

var failures: Array[String] = []
var checks: int = 0

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: ", message)

func idle(map: JeffMap2D) -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while map.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not map.busy, "Runtime operation completes")

func run() -> void:
	var demo := load("res://demo/runtime_demo.tscn").instantiate() as Node2D
	root.add_child(demo)
	var map := demo.get_node("Map") as JeffMap2D
	await idle(map)
	check(map.map_data != null and map.renderer != null, "Runtime demo generates on ready")
	if map.map_data == null:
		quit(1)
		return
	var structural_hash := map.map_data.content_hash()
	var old_projection := map.profile.projection
	for key in [KEY_TAB, KEY_T]:
		var event := InputEventKey.new()
		event.pressed = true
		event.keycode = key
		demo._unhandled_input(event)
		await idle(map)
		check(map.map_data.content_hash() == structural_hash, "Runtime display key preserves map data")
	check(map.profile.projection != old_projection, "Runtime projection shortcut applies")
	var grid_event := InputEventKey.new()
	grid_event.pressed = true
	grid_event.keycode = KEY_G
	demo._unhandled_input(grid_event)
	await idle(map)
	check(map.profile.grid == MapProfile.Grid.HEX, "Runtime grid shortcut generates hex map")
	var save_event := InputEventKey.new()
	save_event.pressed = true
	save_event.keycode = KEY_S
	demo._unhandled_input(save_event)
	check(FileAccess.file_exists("user://jeff_runtime_map.tres"), "Runtime save shortcut writes map")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://test_output/runtime_demo.png")
	print("RUNTIME DEMO TESTS: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
