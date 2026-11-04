extends Node2D

@onready var map: JeffMap2D = $Map
@onready var camera: Camera2D = $Camera2D
var label: Label
var dragging: bool = false

func _ready() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	label = StudioUI.label("", 16)
	label.theme = StudioUI.theme()
	label.position = Vector2(24, 20)
	hud.add_child(label)
	map.generation_progress.connect(func(value: float, stage: String) -> void: label.text = "%s  %d%%" % [stage, value * 100])
	map.generation_failed.connect(func(message: String) -> void: label.text = message)
	map.generation_completed.connect(_generated)
	map.profile.width = 64
	map.profile.height = 64
	map.generate(map.profile)

func _generated(data: MapData) -> void:
	var p := data.profile
	var bounds := Rect2(map.cell_to_local(Vector2i.ZERO, false), Vector2.ZERO)
	for cell in [Vector2i(p.width - 1, 0), Vector2i(0, p.height - 1), Vector2i(p.width - 1, p.height - 1)]:
		bounds = bounds.expand(map.cell_to_local(cell, false))
	bounds = bounds.grow(200)
	camera.position = bounds.get_center()
	var viewport := get_viewport_rect().size - Vector2(80, 100)
	camera.zoom = Vector2.ONE * minf(viewport.x / bounds.size.x, viewport.y / bounds.size.y)
	label.text = "Jeff Map Studio · 运行时示例\nR 换种子  /  G 方形与六角  /  Tab 俯视与等角  /  T 纹理风格  /  S 保存到 user://\n滚轮缩放 · 右键拖动  |  seed %d" % p.seed_value

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom *= 1.1
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom /= 1.1
	elif event is InputEventMouseMotion and dragging:
		camera.position -= event.relative / camera.zoom
	elif event is InputEventKey and event.pressed and not event.echo and not map.busy:
		var p := map.profile.copy()
		match event.keycode:
			KEY_R:
				p.seed_value += 1
				map.generate(p)
			KEY_G:
				p.grid = 1 - p.grid
				map.generate(p)
			KEY_TAB, KEY_T:
				var data := map.map_data.copy()
				if event.keycode == KEY_TAB:
					data.profile.projection = 1 - data.profile.projection
				else:
					data.profile.style = 1 - data.profile.style
				map.apply_data(data)
			KEY_S:
				var error := map.save_map("user://jeff_runtime_map.tres")
				label.text = "保存成功：user://jeff_runtime_map.tres" if error == OK else error_string(error)
