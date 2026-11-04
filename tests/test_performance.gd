extends SceneTree

var results: Array = []
var failures: Array[String] = []
var max_gap: float = 0
var last_frame: int = 0
var peak_memory: int = 0
var frame_total: int = 0

func _init() -> void:
	call_deferred("run")

func sample_frame() -> void:
	var now := Time.get_ticks_usec()
	if last_frame > 0:
		max_gap = maxf(max_gap, (now - last_frame) / 1000.0)
	last_frame = now
	peak_memory = maxi(peak_memory, OS.get_static_memory_usage())
	frame_total += 1

func run() -> void:
	var map := JeffMap2D.new()
	root.add_child(map)
	map.generation_failed.connect(func(message: String) -> void: failures.append(message))
	var camera := Camera2D.new()
	root.add_child(camera)
	camera.zoom = Vector2.ONE * 0.025
	for grid in 2:
		var p := MapProfile.new()
		p.width = 512
		p.height = 512
		p.base_thickness = 16
		p.grid = grid
		camera.position = MapGrid.cell_to_local(Vector2i(256, 256), p)
		last_frame = 0
		max_gap = 0
		frame_total = 0
		var started := Time.get_ticks_usec()
		map.generate(p)
		while map.busy and Time.get_ticks_usec() - started < 180000000:
			await process_frame
			sample_frame()
		for _frame in 5:
			await process_frame
			sample_frame()
		if map.busy or map.map_data == null or map.map_data.terrain.size() != 512 * 512:
			failures.append("512 x 512 did not complete")
		var result := {"grid": "square" if grid == 0 else "hex", "cells": 512 * 512, "wall_time_ms": (Time.get_ticks_usec() - started) / 1000.0, "max_frame_interval_ms": max_gap, "frames": frame_total, "peak_static_memory_bytes": peak_memory}
		results.append(result)
		print(JSON.stringify(result))
		var previous_hash := map.map_data.content_hash()
		var reached_render := [false]
		var connection := func(value: float, stage: String) -> void:
			if value > 0.55 and stage.begins_with("铺设"):
				reached_render[0] = true
		map.generation_progress.connect(connection)
		p.seed_value += 1
		map.generate(p)
		while map.busy and not reached_render[0]:
			await process_frame
		var cancel_at := Time.get_ticks_usec()
		map.cancel_generation()
		for _frame in 3:
			await process_frame
		if map.map_data.content_hash() != previous_hash:
			failures.append("Render cancellation replaced committed map")
		result["render_cancel_ms"] = (Time.get_ticks_usec() - cancel_at) / 1000.0
		map.generation_progress.disconnect(connection)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://test_output"))
	var file := FileAccess.open("res://test_output/performance_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"results": results, "failures": failures, "engine": Engine.get_version_info().string, "renderer": RenderingServer.get_video_adapter_name()}, "\t"))
	print("PERFORMANCE: ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
