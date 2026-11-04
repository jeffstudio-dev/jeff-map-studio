extends SceneTree
## Copied into the temporary clean-install project after editor validation.

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var scene := load("res://fixture.tscn").instantiate() as Node2D
	root.add_child(scene)
	var map := scene.get_node_or_null("JeffMap2D") as JeffMap2D
	if map == null:
		printerr("FAIL: Saved scene has no map")
		quit(1)
		return
	var deadline := Time.get_ticks_msec() + 60000
	while map.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	if map.busy or map.renderer == null or map.map_data == null:
		printerr("FAIL: Saved scene did not render at runtime")
		quit(1)
		return
	print("SAVED SCENE TESTS: 1 checks, 0 failures")
	quit(0)
