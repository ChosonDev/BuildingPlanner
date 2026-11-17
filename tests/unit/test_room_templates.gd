extends "res://addons/gut/test.gd"

var root = ProjectSettings.globalize_path("res://").plus_file("..")
var Tool = load(root.plus_file("scripts/tool/BuildingPlannerTool.gd"))
var UI = load(root.plus_file("scripts/tool/BuildingPlannerToolUI.gd"))
var Room = load(root.plus_file("scripts/features/RoomBuilder.gd"))
var Template = load(root.plus_file("scripts/features/RoomTemplate.gd"))

class ShapeApi:
	extends Reference
	var radius = 4.0
	func is_ready(): return true
	func get_shape_state():
		return {"ready": true, "active_shape_radius": radius, "active_shape_angle": 30.0,
			"active_shape_sides": 6, "active_color": Color.orange}

class Editor:
	extends Node
	signal OnSaveBegin(path, backup)
	var Tools = {}
	var SearchHasFocus = false

class Assets:
	extends Reference
	var textures = {"Walls": {}, "Paths": {}}
	var lookups = []
	func GetAssetList(category): return textures.get(category, {}).keys()
	func GetAssetTexture(category, path):
		lookups.append([category, path])
		return textures.get(category, {}).get(path)

func asset(path):
	var texture = GradientTexture.new()
	texture.resource_path = path
	return texture

func context():
	var editor = autofree(Editor.new())
	var world = autofree(Node2D.new())
	var canvas = autofree(Node2D.new())
	var api = ShapeApi.new()
	var mod = {"Global": {"Root": root + "/", "World": world, "WorldUI": canvas,
		"Editor": editor, "API": null, "ModMapData": {}}}
	var tool = Tool.new(mod)
	tool._gl_api = api
	tool._room_builder = Room.new(api, null)
	tool.cached_world = world
	tool.update_room_templates()
	return tool

func finish(instance):
	if instance._ui: instance._ui._tool = null
	instance._ui = null
	instance.shutdown()

func test_room_templates_roundtrip_all_settings_and_preserve_independent_shape():
	var tool = context()
	var room = tool._room_builder
	room.active_sub_mode = 3
	room.active_outline_mode = 1
	room.shape_angle_offset = 15.0
	room.shape_scale_factor = 1.3
	room._pattern_fill.active_color = Color.purple
	room._wall_builder.active_offset = -7.0
	room._path_builder.active_width = 2.75
	room._path_builder.active_fade_out = true
	assert_true(tool.add_room_template())
	var saved = tool.room_templates[0].save()
	tool._gl_api.radius = 99.0
	room._path_builder.active_width = 100.0
	tool._refresh_shape_state()
	assert_eq(tool.gl_tool_state.active_shape_radius, 4.0)
	assert_eq(tool.room_templates[0].panels[2].width, 2.75)
	var parsed = JSON.parse(JSON.print(saved))
	assert_eq(parsed.error, OK)
	var restored = Template.new()
	assert_true(restored.load_data(parsed.result, tool._room_style_defaults()))
	assert_eq_deep(restored.save(), saved)
	assert_eq(typeof(restored.state.active_shape_sides), TYPE_INT)
	finish(tool)

func test_room_templates_map_save_reload_reset_and_invalid_data_preservation():
	var tool = context()
	assert_true(tool.add_room_template())
	tool.room_templates[0].name = "Stone room"
	var global = tool.parent_mod.Global
	global.Editor.emit_signal("OnSaveBegin", "map", true)
	var saved = JSON.parse(JSON.print(global.ModMapData)).result
	global.World = autofree(Node2D.new())
	global.ModMapData = {}
	tool.update_room_templates()
	assert_eq(tool.room_templates.size(), 0)
	assert_eq(tool.active_room_template, -1)
	assert_null(tool._room_builder.room_template)
	global.World = autofree(Node2D.new())
	global.ModMapData = saved
	tool.update_room_templates()
	assert_eq(tool.room_templates.size(), 1)
	assert_eq(tool.room_templates[0].name, "Stone room")
	global.World = autofree(Node2D.new())
	global.ModMapData = {Tool.ROOM_DATA_KEY: {"version": 999, "room_templates": "future"}}
	tool.update_room_templates()
	global.Editor.emit_signal("OnSaveBegin", "map", false)
	assert_eq(global.ModMapData[Tool.ROOM_DATA_KEY].version, 999)
	assert_false(tool.add_room_template())
	finish(tool)

func test_room_templates_load_late_map_data_with_same_world_and_refresh_dropdown():
	var source = context()
	assert_true(source.add_room_template())
	source.room_templates[0].name = "Saved room"
	source.parent_mod.Global.Editor.emit_signal("OnSaveBegin", "map", false)
	var path = "res://results/room_template_map_roundtrip.dungeondraft_map"
	var file = File.new()
	assert_eq(file.open(path, File.WRITE), OK)
	file.store_string(JSON.print({"mod": source.parent_mod.Global.ModMapData}))
	file.close()
	assert_eq(file.open(path, File.READ), OK)
	var parsed = JSON.parse(file.get_as_text())
	file.close()
	assert_eq(parsed.error, OK)
	finish(source)
	var restored = context()
	var ui = UI.new(restored, null)
	# Build controls without a host level; retain the observed World reference.
	var world = restored.parent_mod.Global.World
	restored.parent_mod.Global.World = null
	ui.build(autofree(VBoxContainer.new()))
	restored.parent_mod.Global.World = world
	restored._ui = ui
	assert_true(ui._rb_templates.disabled)
	restored.parent_mod.Global.ModMapData = parsed.result.mod
	restored.update_room_templates()
	assert_eq(restored.room_templates.size(), 1, "Map data can arrive after World is observed")
	assert_false(ui._rb_templates.disabled)
	assert_eq(ui._rb_templates.get_item_text(0), "Saved room")
	assert_eq(ui._rb_templates.get_item_text(1), "New template")
	assert_true(restored.select_room_template(0))
	restored.parent_mod.Global.Editor.emit_signal("OnSaveBegin", "map", true)
	restored.update_room_templates()
	assert_eq(restored.active_room_template, 0, "Our own save must not trigger another load")
	assert_eq(restored.room_templates.size(), 1)
	assert_eq(Directory.new().remove(path), OK)
	finish(restored)

func test_room_templates_saved_group_geometry_transforms_without_guideslines_selection():
	var tool = context()
	assert_true(tool.add_room_template())
	var template = tool.room_templates[0]
	template.state.active_marker_type = "Template"
	template.geometry = [{"marker_type": "Shape", "position": Vector2(1, 0), "color": Color.blue,
		"polygon": [Vector2.ZERO, Vector2(2, 0), Vector2(0, 2)],
		"shape_primitives": [{"type": "seg", "a": Vector2.ZERO, "b": Vector2(2, 0)}]}]
	var copy = Template.new()
	assert_true(copy.load_data(JSON.parse(JSON.print(template.save())).result, tool._room_style_defaults()))
	var transformed = copy.transformed_geometry(Vector2(10, 20), 90, 2)
	assert_almost_eq(transformed[0].position.x, 10.0, 0.001)
	assert_almost_eq(transformed[0].position.y, 22.0, 0.001)
	assert_almost_eq(transformed[0].shape_primitives[0].b.y, 24.0, 0.001)
	assert_eq(copy.geometry[0].position, Vector2(1, 0))
	var invalid = template.save()
	invalid.geometry[0].position = {"$vector": ["bad", 0]}
	assert_false(copy.load_data(invalid, tool._room_style_defaults()))
	invalid = template.save()
	invalid.state.active_shape_sides = 3.5
	assert_false(copy.load_data(invalid, tool._room_style_defaults()))
	invalid = template.save()
	invalid.geometry[0].outline_points = "invalid optional geometry"
	assert_false(copy.load_data(invalid, tool._room_style_defaults()))
	finish(tool)

func test_room_templates_dropdown_add_rename_new_and_delete():
	var tool = context()
	# No map is needed to construct UI controls; textures remain optional defaults.
	tool.parent_mod.Global.World = null
	var ui = UI.new(tool, null)
	ui.build(autofree(VBoxContainer.new()))
	tool._ui = ui
	assert_true(ui._rb_templates.disabled)
	assert_eq(ui._rb_templates.get_item_text(0), "New template")
	assert_true(ui._rb_template_add.visible)
	tool._room_builder.active_sub_mode = 2
	tool._room_builder.active_outline_mode = 1
	tool._room_builder._wall_builder.active_offset = 12.0
	tool._room_builder._path_builder.active_width = 2.5
	ui._on_room_template_add()
	assert_eq(tool.room_templates.size(), 1)
	assert_eq(ui._rb_templates.get_item_text(1), "New template")
	assert_false(ui._rb_templates.disabled)
	assert_true(ui._rb_template_rename.visible)
	assert_true(ui._rb_template_delete.visible)
	assert_false(ui._rb_template_add.visible)
	ui._rb_renaming_template = tool.room_templates[0]
	ui._rb_name_edit.text = "  Stone  "
	ui._on_room_name_confirmed()
	assert_eq(ui._rb_templates.get_item_text(0), "Stone")
	ui._on_room_template_selected(1)
	assert_eq(tool.active_room_template, -1)
	assert_true(ui._rb_template_add.visible)
	tool._room_builder._path_builder.active_width = 9.0
	ui._on_room_template_selected(0)
	assert_eq(tool.active_room_template, 0)
	assert_eq(ui._rb_sub_mode_selector.selected, 2)
	assert_eq(ui._rb_outline_mode_selector.selected, 1)
	assert_eq(tool._room_builder._wall_builder.active_offset, 12.0)
	assert_eq(tool._room_builder._path_builder.active_width, 2.5)
	var unavailable = Template.new()
	assert_true(unavailable.load_data(tool.room_templates[0].save(), tool._room_style_defaults()))
	unavailable.panels[0].texture = "res://missing_pack/floor.png"
	unavailable.panels[2].width = 99.0
	tool.room_templates.append(unavailable)
	ui._on_room_template_selected(1)
	assert_eq(tool.active_room_template, 0, "Missing texture keeps the selected style")
	assert_eq(tool._room_builder._path_builder.active_width, 2.5, "No partial application")
	tool.room_templates.remove(1)
	ui._on_room_template_delete()
	assert_eq(tool.room_templates.size(), 0)
	assert_true(ui._rb_templates.disabled)
	assert_true(ui._rb_template_add.visible)
	finish(tool)

func test_room_templates_switch_real_textures_and_all_visible_controls_a_b_a():
	var tool = context()
	tool.parent_mod.Global.World = null
	tool.parent_mod.Global.ModMapData["UchideshiNodeData"] = {}
	var assets = Assets.new()
	tool.parent_mod.Script = assets
	var ui = UI.new(tool, null)
	ui.build(autofree(VBoxContainer.new()))
	tool._ui = ui
	var raw_path = "res://results/room_template_raw.png"
	var image = Image.new()
	image.create(2, 2, false, Image.FORMAT_RGBA8)
	assert_eq(image.save_png(raw_path), OK)
	var floors = [asset("user://colorable_room_floor.png"), ui._rb_pattern_panel._load_texture_safe(raw_path)]
	assert_eq(floors[1].flags, 6, "Raw pack patterns retain repeat/filter flags")
	for i in range(2):
		tool.select_room_template(-1)
		tool._gl_api.radius = 3.0 + i
		var room = tool._room_builder
		room.active_sub_mode = i + 1
		room.active_outline_mode = i
		room.shape_angle_offset = 15.0 + i * 20
		room.shape_scale_factor = 1.0 + i
		var wall = asset("user://room_wall_%s.png" % i)
		var path = asset("user://room_path_%s.png" % i)
		assets.textures.Walls[wall.resource_path] = wall
		assets.textures.Paths[path.resource_path] = path
		room._pattern_fill.active_texture = floors[i]
		room._wall_builder.active_texture = wall
		room._path_builder.active_texture = path
		var panels = [room._pattern_fill, room._wall_builder, room._path_builder]
		for feature in panels: feature.active_color = Color.red if i == 0 else Color.blue
		room._pattern_fill.active_rotation = 30.0 + 60 * i
		room._pattern_fill.active_outline = i == 1
		room._wall_builder.active_shadow = i == 0
		room._wall_builder.active_joint = i
		room._wall_builder.active_offset = -12.0 + 24 * i
		room._wall_builder.active_reverse_direction = i == 1
		room._path_builder.active_width = 1.5 + i
		room._path_builder.active_smoothness = 0.25 + 0.25 * i
		room._path_builder.active_sorting = i
		for field in ["fade_in", "fade_out", "grow", "shrink", "block_light", "reverse_direction"]:
			room._path_builder.set("active_" + field, i == 1)
		assert_true(tool.add_room_template())
	for index in [0, 1, 0]:
		ui._rb_templates.emit_signal("item_selected", index)
		assert_eq(tool.active_room_template, index)
		var template = tool.room_templates[index]
		assert_eq(ui._rb_sub_mode_selector.selected, template.sub_mode)
		assert_eq(ui._rb_outline_mode_selector.selected, template.outline_mode)
		assert_eq(tool.gl_tool_state.active_shape_radius, 3.0 + index)
		assert_eq(tool._room_builder.shape_angle_offset, template.angle)
		assert_eq(tool._room_builder.shape_scale_factor, template.scale)
		var panels = [ui._rb_pattern_panel, ui._rb_wall_panel, ui._rb_path_panel]
		for i in range(3):
			var panel = panels[i]
			for field in Template.PANEL_FIELDS[i]:
				var expected = template.panels[i][field]
				var actual = panel.feature.get("active_" + field)
				if field == "texture": actual = actual.resource_path
				assert_eq(actual, expected, "Selected template %s panel %s field %s" % [index, i, field])
				if panel._controls.has(field):
					var control = panel._controls[field]
					if control is Range: assert_eq(control.value, float(expected))
					elif control is OptionButton: assert_eq(control.get_selected_id() if field == "layer" else control.selected, expected)
					elif control is BaseButton: assert_eq(control.pressed, bool(expected))
			assert_eq(panel.color_picker.color, template.panels[i].color)
			assert_eq(panel._index_to_path[panel._sg._selected_original], template.panels[i].texture)
	assert_eq(assets.lookups.size(), 6, "Only Wall/Path textures use the native library index")
	var current = tool._room_builder._path_builder.get_settings()
	assets.textures.Walls.erase(tool.room_templates[1].panels[1].texture)
	ui._on_room_template_selected(1)
	assert_eq(tool.active_room_template, 0)
	assert_eq_deep(tool._room_builder._path_builder.get_settings(), current)
	assert_eq(assets.lookups.size(), 6, "Missing native entries never reach Reverse[path]")
	tool.parent_mod.Global.ModMapData.erase("UchideshiNodeData")
	assert_true(tool.select_room_template(0))
	assert_true(ui._rb_path_panel.color_picker.disabled)
	assert_eq(tool._room_builder._path_builder.active_color, Color.white)
	assert_eq(Directory.new().remove(raw_path), OK)
	finish(tool)
