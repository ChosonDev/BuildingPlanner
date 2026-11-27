extends "res://addons/gut/test.gd"

var root = ProjectSettings.globalize_path("res://").plus_file("..")
var Tool = load(root.plus_file("scripts/tool/BuildingPlannerTool.gd"))
var UI = load(root.plus_file("scripts/tool/BuildingPlannerToolUI.gd"))
var Room = load(root.plus_file("scripts/features/RoomBuilder.gd"))
var Template = load(root.plus_file("scripts/features/RoomTemplate.gd"))
var Overlay = load(root.plus_file("scripts/overlay/BuildingPlannerOverlay.gd"))

const SQUARE = [Vector2(0, 0), Vector2(200, 0), Vector2(200, 200), Vector2(0, 200)]
var records = []


class SavedNode:
	extends Node2D
	var data = {}
	func Save(_copy = false):
		return data.duplicate(true)
	func SetOptions(_texture, color, rotation):
		data["color"] = color
		data["rotation"] = rotation
	func SetLayer(layer):
		data["layer"] = layer


class SavedPath:
	extends SavedNode
	func SetEditPoints(_points):
		pass


class NativeContainer:
	extends Node2D
	func create(data, path = false):
		var node = SavedPath.new() if path else SavedNode.new()
		node.data = data.duplicate(true)
		add_child(node)
		return node
	func LoadShape(data):
		return create(data)
	func LoadPathway(data):
		return create(data, true)
	func LoadWall(data):
		create(data)
	func AddWall(points, _texture, _color, _loop, _shadow, _type, _joint, _normalize):
		return create({"points": Array(points), "texture": _texture, "color": _color, "shadow": _shadow, "joint": _joint, "loop": _loop})


class ShapeApi:
	extends Reference
	var captured = null
	var template_markers = []
	func is_ready(): return true
	func get_shape_state():
		return {"ready": true, "active_shape_radius": 2.0, "active_shape_angle": 0.0,
			"active_shape_sides": 4, "active_color": Color.white, "active_marker_type": "Shape"}
	func begin_history_capture():
		captured = []
		return true
	func end_history_capture():
		var out = captured
		captured = null
		return out
	func place_shape_marker_plain(_pos, _r, _a, _s, _c): return 10
	func get_shape_polygon(id): return {"marker_id": id, "marker_type": "Shape", "polygon": SQUARE.duplicate()}
	func delete_marker(_id): return true
	func place_shape_merge(_pos, _r, _a, _s): return {"affected_markers": [], "absorbed_marker_ids": []}
	func place_shape_conforming(_pos, _r, _a, _s, _c): return {"marker_id": 11, "marker_polygon": SQUARE.duplicate(), "affected_markers": []}
	func place_shape_wrapping(_pos, _r, _a, _s, _c): return {"marker_id": 12, "marker_polygon": SQUARE.duplicate(), "affected_markers": []}
	func apply_shape_difference(_pos, _r, _a, _s): return {"affected_markers": []}
	func get_template_markers(_pos, _idx = -1, _rot = 0.0, _scale = 1.0): return template_markers.duplicate(true)
	func apply_marker_geometry(_marker, _mode = "Normal"): return {"marker_id": 13, "marker_polygon": SQUARE.duplicate()}


class Assets:
	extends Reference
	var textures = {"Walls": {}, "Paths": {}}
	func GetAssetList(category): return textures.get(category, {}).keys()
	func GetAssetTexture(category, path): return textures.get(category, {}).get(path)


func record(action, _limit):
	records.append(action)


func after_each():
	for action in records:
		action.dropped(0)
	records.clear()


func make_tex(path: String) -> Texture:
	var tex = GradientTexture.new()
	tex.resource_path = path
	return tex


func make_env():
	var fills = autofree(NativeContainer.new())
	var walls = autofree(NativeContainer.new())
	var paths = autofree(NativeContainer.new())
	var level = {"PatternShapes": fills, "Walls": walls, "Pathways": paths, "TileMap": {"CellSize": Vector2(100, 100)}}
	var world = {"Level": level}
	var api = ShapeApi.new()
	var assets = Assets.new()
	var mod = {"Script": assets, "Global": {"Root": root + "/", "World": world, "WorldUI": null,
		"Editor": {"Tools": {}, "SearchHasFocus": false}, "API": {"HistoryApi": self}, "ModMapData": {"UchideshiNodeData": {}}}}
	var tool = Tool.new(mod)
	tool._gl_api = api
	tool._room_builder = Room.new(api, null, mod)
	tool.cached_world = world
	return {"tool": tool, "room": tool._room_builder, "api": api, "level": level, "assets": assets, "mod": mod}


func test_room_outline_ui_defaults_add_switch_rename_delete_and_last_item_guard():
	var env = make_env()
	var tool = env.tool
	var room = env.room
	var ui = UI.new(tool, null)
	ui.build(autofree(VBoxContainer.new()))
	tool._ui = ui

	# Starts with Wall Default and cannot delete the last remaining outline.
	assert_eq(room.outlines.size(), 1)
	assert_eq(room.outlines[0].name, "Wall Default")
	assert_eq(ui._rb_outline_selector.get_item_count(), 1)
	assert_eq(ui._rb_outline_selector.get_item_text(0), "Wall Default")
	assert_true(ui._rb_outline_delete.disabled)
	assert_true(ui._rb_wall_container.visible)
	assert_false(ui._rb_path_container.visible)
	ui._on_rb_outline_delete()
	assert_eq(room.outlines.size(), 1, "Last outline cannot be deleted")

	# Customize Wall Default.
	ui._rb_wall_panel.offset_spin.emit_signal("value_changed", 12.0)
	ui._rb_wall_panel.shadow_check.emit_signal("toggled", false)

	# Add a Path outline and customize it.
	ui._rb_outline_add_path.emit_signal("pressed")
	assert_eq(room.outlines.size(), 2)
	assert_eq(ui._rb_outline_selector.get_item_text(1), "Path 1")
	assert_eq(ui._rb_outline_selector.selected, 1)
	assert_false(ui._rb_outline_delete.disabled)
	assert_false(ui._rb_wall_container.visible)
	assert_true(ui._rb_path_container.visible)
	ui._rb_path_panel.width_spin.emit_signal("value_changed", 2.5)
	ui._rb_path_panel.offset_spin.emit_signal("value_changed", -10.0)

	# Add a second Wall outline.
	ui._rb_outline_add_wall.emit_signal("pressed")
	assert_eq(room.outlines.size(), 3)
	assert_eq(ui._rb_outline_selector.get_item_text(2), "Wall 1")
	assert_eq(ui._rb_outline_selector.selected, 2)
	assert_true(ui._rb_wall_container.visible)
	assert_eq(room._wall_builder.active_offset, 0.0, "New Wall starts with default offset")
	ui._rb_wall_panel.offset_spin.emit_signal("value_changed", 24.0)

	# Rename Wall 1 -> Outer Trim.
	ui._rb_renaming_outline_index = 2
	ui._rb_outline_name_edit.text = "  Outer Trim  "
	ui._on_rb_outline_name_confirmed()
	assert_eq(ui._rb_outline_selector.get_item_text(2), "Outer Trim")

	# Switch back to Wall Default and verify independent settings are restored.
	ui._on_rb_outline_selected(0)
	assert_eq(room._wall_builder.active_offset, 12.0)
	assert_false(room._wall_builder.active_shadow)
	assert_eq(ui._rb_wall_panel.offset_spin.value, 12.0)
	assert_false(ui._rb_wall_panel.shadow_check.pressed)

	# Switch to Path 1 and verify independent settings are restored.
	ui._on_rb_outline_selected(1)
	assert_eq(room._path_builder.active_width, 2.5)
	assert_eq(room._path_builder.active_offset, -10.0)
	assert_true(ui._rb_path_container.visible)

	# Delete Path 1 -> falls back cleanly, Delete remains enabled while 2 items exist.
	ui._on_rb_outline_delete()
	assert_eq(room.outlines.size(), 2)
	assert_eq(ui._rb_outline_selector.get_item_text(1), "Outer Trim")
	assert_false(ui._rb_outline_delete.disabled)
	assert_eq(room._wall_builder.active_offset, 24.0)

	# Delete Outer Trim -> back to 1 item, Delete is disabled again.
	ui._on_rb_outline_delete()
	assert_eq(room.outlines.size(), 1)
	assert_true(ui._rb_outline_delete.disabled)
	assert_eq(room._wall_builder.active_offset, 12.0)
	ui._tool = null


func test_room_builder_builds_multiple_outlines_with_compound_undo_redo_and_open_guides():
	var env = make_env()
	var room = env.room
	var level = env.level
	var fill_tex = make_tex("user://floor.png")
	var wall_tex_a = make_tex("user://wall_a.png")
	var wall_tex_b = make_tex("user://wall_b.png")
	var path_tex = make_tex("user://path_a.png")

	room._pattern_fill.active_texture = fill_tex
	room._wall_builder.active_texture = wall_tex_a
	room._wall_builder.active_color = Color.red
	room._wall_builder.active_offset = 0.0

	var p_idx = room.add_outline(Room.OutlineMode.PATH, "Trim Path")
	assert_eq(p_idx, 1)
	room._path_builder.active_texture = path_tex
	room._path_builder.active_width = 1.5
	room._path_builder.active_offset = 10.0

	var w_idx = room.add_outline(Room.OutlineMode.WALL, "Outer Wall")
	assert_eq(w_idx, 2)
	room._wall_builder.active_texture = wall_tex_b
	room._wall_builder.active_color = Color.blue
	room._wall_builder.active_offset = 20.0

	assert_true(room.build_room_at(Vector2.ZERO, env.api.get_shape_state()))
	assert_eq(records.size(), 1)
	assert_eq(level.PatternShapes.get_child_count(), 1)
	assert_eq(level.Walls.get_child_count(), 2)
	assert_eq(level.Pathways.get_child_count(), 1)
	assert_eq(level.Walls.get_child(0).data.color, Color.red)
	assert_eq(level.Walls.get_child(1).data.color, Color.blue)
	assert_eq(level.Pathways.get_child(0).data.texture, path_tex.resource_path)

	# Undo removes all 1 fill + 2 walls + 1 path; redo restores all of them.
	records[0].undo()
	assert_eq(level.PatternShapes.get_child_count(), 0)
	assert_eq(level.Walls.get_child_count(), 0)
	assert_eq(level.Pathways.get_child_count(), 0)
	records[0].redo()
	assert_eq(level.PatternShapes.get_child_count(), 1)
	assert_eq(level.Walls.get_child_count(), 2)
	assert_eq(level.Pathways.get_child_count(), 1)

	# Open template guide builds all outlines even when closed offsets are non-zero.
	env.api.template_markers = [{
		"marker_type": "Path",
		"position": Vector2.ZERO,
		"color": Color.white,
		"closed": false,
		"outline_points": [Vector2(0, 0), Vector2(150, 0)],
	}]
	var tpl_state = env.api.get_shape_state()
	tpl_state["active_marker_type"] = "Template"
	assert_true(room.build_room_at(Vector2.ZERO, tpl_state))
	assert_eq(level.Walls.get_child_count(), 4)
	assert_eq(level.Pathways.get_child_count(), 2)
	assert_false(level.Walls.get_child(2).data.loop)
	assert_false(level.Pathways.get_child(1).data.loop)


func test_room_template_saves_restores_multiple_outlines_and_loads_legacy_format():
	var env = make_env()
	var tool = env.tool
	var room = env.room
	var assets = env.assets
	var wall_a = make_tex("user://tpl_wall_a.png")
	var path_a = make_tex("user://tpl_path_a.png")
	assets.textures.Walls[wall_a.resource_path] = wall_a
	assets.textures.Paths[path_a.resource_path] = path_a

	var ui = UI.new(tool, null)
	tool.parent_mod.Global.World = null
	ui.build(autofree(VBoxContainer.new()))
	tool._ui = ui

	room._wall_builder.active_texture = wall_a
	room._wall_builder.active_offset = 6.0
	room.add_outline(Room.OutlineMode.PATH, "Inner Trim")
	room._path_builder.active_texture = path_a
	room._path_builder.active_width = 2.2
	room._path_builder.active_offset = -8.0

	assert_true(tool.add_room_template())
	var saved = tool.room_templates[0].save()
	assert_eq(saved.outlines.size(), 2)
	assert_eq(saved.outlines[0].name, "Wall Default")
	assert_eq(saved.outlines[1].name, "Inner Trim")

	# Mutate live state and re-select template to confirm full multi-outline restore.
	room.set_outlines([{"name": "Only", "mode": 0, "settings": room.default_outline_settings(0)}], 0)
	assert_true(tool.select_room_template(0))
	assert_eq(room.outlines.size(), 2)
	assert_eq(ui._rb_outline_selector.get_item_count(), 2)
	assert_eq(ui._rb_outline_selector.get_item_text(0), "Wall Default")
	assert_eq(ui._rb_outline_selector.get_item_text(1), "Inner Trim")
	assert_eq(room.outlines[0].settings.active_offset, 6.0)
	assert_eq(room.outlines[1].settings.active_width, 2.2)
	assert_eq(room.outlines[1].settings.active_offset, -8.0)

	# Legacy saved template without "outlines" key still loads cleanly.
	var legacy_data = saved.duplicate(true)
	legacy_data.erase("outlines")
	legacy_data["outline_mode"] = 1
	var legacy = Template.new()
	assert_true(legacy.load_data(legacy_data, tool._room_style_defaults()))
	assert_eq(legacy.outlines.size(), 1)
	assert_eq(legacy.outlines[0].mode, 1)
	assert_eq(legacy.outlines[0].name, "Path 1")
	ui._tool = null


func test_room_overlay_preview_renders_one_fill_plus_all_outlines():
	var env = make_env()
	var room = env.room
	room._pattern_fill.active_texture = make_tex("user://prev_floor.png")
	room._wall_builder.active_texture = make_tex("user://prev_wall.png")
	room.add_outline(Room.OutlineMode.PATH, "Path 1")
	room._path_builder.active_texture = make_tex("user://prev_path.png")

	var overlay = autofree(Overlay.new())
	add_child(overlay)
	overlay.refresh_room_preview(room, Vector2.ZERO, env.api.get_shape_state())
	assert_eq(overlay._room_previews.size(), 3, "1 fill + 2 outlines = 3 preview renderers")
	assert_true(overlay._room_previews[0].visible)
	assert_true(overlay._room_previews[1].visible)
	assert_true(overlay._room_previews[2].visible)


func test_room_builder_floor_and_outlines_sections_are_framed_and_collapsible():
	var env = make_env()
	var tool = env.tool
	var ui = UI.new(tool, null)
	ui.build(autofree(VBoxContainer.new()))
	tool._ui = ui

	# Both sections start expanded inside dedicated PanelContainer cards.
	assert_true(ui._rb_floor_body.visible)
	assert_true(ui._rb_outlines_body.visible)
	assert_true(ui._rb_floor_toggle.get_parent().get_parent() is PanelContainer)
	assert_true(ui._rb_outlines_toggle.get_parent().get_parent() is PanelContainer)
	assert_eq(ui._rb_floor_toggle.text, "[-] Floor")
	assert_eq(ui._rb_outlines_toggle.text, "[-] Walls & Outlines (1)")

	# Collapsing Floor hides only Floor body and updates indicator.
	ui._rb_floor_toggle.pressed = false
	assert_false(ui._rb_floor_body.visible)
	assert_eq(ui._rb_floor_toggle.text, "[+] Floor")
	assert_true(ui._rb_outlines_body.visible)

	# Adding an outline updates the count in the Walls & Outlines header even when collapsed.
	ui._rb_outlines_toggle.pressed = false
	assert_false(ui._rb_outlines_body.visible)
	assert_eq(ui._rb_outlines_toggle.text, "[+] Walls & Outlines (1)")
	ui._rb_outline_add_path.emit_signal("pressed")
	assert_eq(ui._rb_outlines_toggle.text, "[+] Walls & Outlines (2)")

	# Expanding restores body visibility.
	ui._rb_floor_toggle.pressed = true
	ui._rb_outlines_toggle.pressed = true
	assert_true(ui._rb_floor_body.visible)
	assert_true(ui._rb_outlines_body.visible)
	assert_eq(ui._rb_outlines_toggle.text, "[-] Walls & Outlines (2)")
	ui._tool = null
