@tool
class_name StudioUI
extends RefCounted

static func logo() -> Texture2D:
	var path := "res://addons/jeff_map_studio/icon.svg"
	if ResourceLoader.exists(path, "Texture2D"):
		return load(path) as Texture2D
	# A freshly copied plugin can initialize before its SVG importer has run.
	var image := Image.new()
	if image.load_svg_from_string(FileAccess.get_file_as_string(path)) == OK:
		return ImageTexture.create_from_image(image)
	return null

static func label(text: String, size: int = 14, color: Color = Color("cbd9d9")) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", color)
	return result

static func button(text: String, action: Callable, accent: bool = false) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size.y = 34
	result.pressed.connect(action)
	if accent:
		result.add_theme_stylebox_override("normal", box(Color("356a5c"), 6))
		result.add_theme_stylebox_override("hover", box(Color("438775"), 6))
		result.add_theme_stylebox_override("pressed", box(Color("285347"), 6))
	return result

static func box(color: Color, radius: int = 6) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.set_corner_radius_all(radius)
	result.content_margin_left = 10
	result.content_margin_right = 10
	result.content_margin_top = 7
	result.content_margin_bottom = 7
	return result

static func heading(parent: Control, title: String, subtitle: String = "") -> void:
	parent.add_child(label(title, 16, Color("a8d7bc")))
	if not subtitle.is_empty():
		var sub := label(subtitle, 12, Color("80999f"))
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parent.add_child(sub)
	parent.add_child(HSeparator.new())

static func choice(parent: Control, title: String, items: Array, selected: int, changed: Callable) -> OptionButton:
	parent.add_child(label(title, 12, Color("9fb1b6")))
	var result := OptionButton.new()
	for item in items:
		result.add_item(str(item))
	result.select(selected)
	result.item_selected.connect(changed)
	result.custom_minimum_size.y = 30
	parent.add_child(result)
	return result

static func number(parent: Control, title: String, value: float, minimum: float, maximum: float, step: float, changed: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	var text := label(title, 13)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	spin.custom_minimum_size.x = 112
	spin.value_changed.connect(changed)
	row.add_child(spin)
	parent.add_child(row)
	return spin

static func scroll_column(parent: Control, minimum_width: int) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = minimum_width
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 10)
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(column)
	return column

static func theme() -> Theme:
	var result := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC", "Arial"])
	result.default_font = font
	result.default_font_size = 14
	result.set_color("font_color", "Label", Color("cbd9d9"))
	result.set_color("font_color", "Button", Color("dce8df"))
	result.set_stylebox("normal", "Button", box(Color("253941")))
	result.set_stylebox("hover", "Button", box(Color("34505a")))
	result.set_stylebox("pressed", "Button", box(Color("356a5c")))
	result.set_stylebox("disabled", "Button", box(Color("1b2a33")))
	result.set_stylebox("panel", "TabContainer", box(Color("182832"), 8))
	result.set_stylebox("tab_selected", "TabContainer", box(Color("2b4b47"), 6))
	result.set_stylebox("tab_unselected", "TabContainer", box(Color("1b2d38"), 6))
	return result
