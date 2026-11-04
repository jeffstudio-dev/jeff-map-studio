@tool
extends EditorPlugin

var panel: MapStudioPanel
var margin: MarginContainer
var target: JeffMap2D

func _enter_tree() -> void:
	margin = MarginContainer.new()
	margin.name = "JeffMapStudioWorkspace"
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	panel = MapStudioPanel.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(panel)
	EditorInterface.get_editor_main_screen().add_child(margin)
	panel.apply_requested.connect(_apply)
	panel.files_saved.connect(func() -> void: EditorInterface.get_resource_filesystem().scan())
	_make_visible(false)

func _exit_tree() -> void:
	if margin != null:
		margin.queue_free()

func _has_main_screen() -> bool:
	return true

func _get_plugin_name() -> String:
	return "Map Studio"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("TileMapLayer", "EditorIcons")

func _make_visible(visible: bool) -> void:
	if margin != null:
		margin.visible = visible
		if visible and panel.is_node_ready():
			panel.ensure_initialized()

func _handles(object: Object) -> bool:
	return object is JeffMap2D

func _edit(object: Object) -> void:
	target = object as JeffMap2D

func _apply(data: MapData, library: TileLibrary) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		panel._set_status("请先创建或打开一个场景，再应用地图。")
		return
	var undo := get_undo_redo()
	data.tile_library = library
	if is_instance_valid(target) and (root == target or root.is_ancestor_of(target)):
		var old_data := target.map_data.copy() if target.map_data != null else null
		undo.create_action("应用 Jeff 地图", UndoRedo.MERGE_DISABLE, target)
		undo.add_do_method(target, "apply_data", data)
		if old_data != null:
			undo.add_undo_method(target, "apply_data", old_data)
		else:
			undo.add_undo_method(target, "clear_map")
	else:
		var node := JeffMap2D.new()
		node.name = "JeffMap2D"
		node.tile_library = library
		undo.create_action("添加 Jeff 地图", UndoRedo.MERGE_DISABLE, root)
		undo.add_do_method(root, "add_child", node, true)
		undo.add_do_property(node, "owner", root)
		undo.add_do_method(node, "apply_data", data)
		undo.add_undo_method(root, "remove_child", node)
		undo.add_do_reference(node)
		target = node
	undo.commit_action()
	panel._set_status("地图已应用到当前场景，可通过编辑器撤销。")
