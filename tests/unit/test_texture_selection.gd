extends "res://addons/gut/test.gd"

var root = ProjectSettings.globalize_path("res://").plus_file("..")
var UI = ResourceLoader.load(root.plus_file("scripts/tool/BuildingPlannerToolUI.gd"))
var Tool = ResourceLoader.load(root.plus_file("scripts/tool/BuildingPlannerTool.gd"))


class HostTool:
	extends Reference
	var Texture = null
	var Controls = {}
	var color_queries = []
	func GetWallColor(_texture):
		color_queries.append(_texture)
		return Color("6b3834")


class Menu:
	extends Reference
	var target
	var textures = []
	var lookups = []
	func GetAssetTexture(category, path):
		lookups.append([category, path])
		return textures[int(path)]
	func OnItemSelected(index):
		target.Texture = textures[index]


class NativeCatalog:
	extends ItemList
	var Lookup = {}
	var selection_calls = 0
	func Load(_category):
		var previous = get_script().get_meta("load_count") if get_script().has_meta("load_count") else 0
		get_script().set_meta("load_count", previous + 1)
		for i in range(2):
			Lookup[str(i)] = i
			add_icon_item(GradientTexture.new())
	func OnItemSelected(_index):
		selection_calls += 1


class PatternHost:
	extends Reference
	var textureMenu
	var colorable_icon
	var queried = []
	func GetDefaultColor(icon):
		queried.append(icon)
		return Color("6b3834") if icon == colorable_icon else Color.white


func test_late_feature_binding_keeps_custom_color_for_first_catalog_then_uses_asset_defaults():
	var source = autofree(NativeCatalog.new())
	source.Load("Walls")
	var host = HostTool.new()
	host.Controls = {"Texture": source}
	var assets = Menu.new()
	assets.textures = [GradientTexture.new(), GradientTexture.new()]
	var panel = UI.WallPanel.new(assets)
	autofree(panel.build())
	panel.color_picker.color = Color.blue
	panel.color_picker.emit_signal("color_changed", Color.blue)
	var feature = load(root.plus_file("scripts/features/WallBuilder.gd")).new(null, null)
	panel.bind_feature(feature)
	panel.try_build_grid_menu({"Editor": {"Tools": {"WallTool": host}}})
	assert_eq(feature.active_color, Color.blue)
	assert_eq(panel.color_picker.color, Color.blue)
	assert_true(feature.active_texture == assets.textures[0])
	panel._sg._on_grid_item_selected(1)
	assert_eq(feature.active_color, Color("6b3834"), "Later deliberate selection uses the asset's default tint")


func test_shared_catalog_survives_panel_release_and_invalidates_with_ui_map_release():
	var source = autofree(NativeCatalog.new())
	source.get_script().set_meta("load_count", 0)
	var host = HostTool.new()
	host.Controls = {"Texture": source}
	var assets = Menu.new()
	assets.textures = [GradientTexture.new(), GradientTexture.new()]
	var global_ref = {"Editor": {"Tools": {"PathTool": host, "WallTool": host}}, "World": null, "API": {}, "ModMapData": {}}
	var tool = Tool.new({"Global": global_ref, "Script": assets})
	tool._path_builder = load(root.plus_file("scripts/features/PathBuilder.gd")).new(null, null)
	tool._wall_builder = load(root.plus_file("scripts/features/WallBuilder.gd")).new(null, null)
	tool._room_builder = load(root.plus_file("scripts/features/RoomBuilder.gd")).new(null, null)
	var ui = UI.new(tool, null)
	ui.build(autofree(VBoxContainer.new()))
	ui.try_build_grid_menus(ui.Mode.PATH_BUILDER)
	ui._rb_outline_mode_selector.selected = 1
	ui.try_build_grid_menus(ui.Mode.ROOM_BUILDER)
	assert_eq(source.get_script().get_meta("load_count"), 1, "Both Path panels share one unfiltered native catalog")
	assert_eq(ui._catalogs.Paths.items.size(), 2)
	ui._pb_path_panel._sg._on_grid_item_selected(1)
	assert_true(tool._path_builder.active_texture == assets.textures[1])
	assert_true(tool._room_builder._path_builder.active_texture == assets.textures[0])
	ui._pb_path_panel._sg._on_search_changed("1")
	assert_eq(ui._rb_path_panel._sg._grid_menu.get_item_count(), 2, "Search remains panel-local")
	ui._pb_path_panel.release()
	assert_eq(ui._catalogs.Paths.items.size(), 2, "Releasing one grid cannot empty shared data")
	assert_eq(ui._rb_path_panel._sg._all_items.size(), 2)
	ui.try_build_grid_menus(ui.Mode.PATH_BUILDER)
	assert_eq(source.get_script().get_meta("load_count"), 1)
	ui.release_all_grid_menus()
	assert_true(ui._catalogs.empty())
	assert_true(ui._rb_path_panel._sg._all_items.empty())
	ui.try_build_grid_menus(ui.Mode.PATH_BUILDER)
	assert_eq(source.get_script().get_meta("load_count"), 2, "New map rebuilds the catalog")
	ui._tool = null
	source.get_script().remove_meta("load_count")


func test_empty_host_catalog_retries_and_pattern_variants_share_thumbnail_work():
	var source = autofree(NativeCatalog.new())
	var host = PatternHost.new()
	host.textureMenu = source
	var panel = UI.PatternPanel.new()
	var global_ref = {"Editor": {"Tools": {"PatternShapeTool": host}}}
	assert_true(panel._get_catalog(global_ref, "Patterns").empty())
	assert_true(panel._catalogs.empty(), "Late catalogs must not be cached empty")
	var icon = GradientTexture.new()
	source.add_icon_item(GradientTexture.new())
	source.add_icon_item(icon)
	source.Lookup = {"": 0, "stone.png": 1}
	host.colorable_icon = icon
	var plain = panel._get_catalog(global_ref, "Patterns")
	var room = panel._get_catalog(global_ref, "Patterns", true)
	assert_eq(plain.items.size(), 1)
	assert_eq(room.items.size(), 2)
	assert_eq(room.paths[0], "")
	assert_eq(room.paths[1], "stone.png")
	assert_eq_deep(host.queried, [icon])
	assert_eq(room.items[1].modulate, plain.items[0].modulate)


func test_panel_signals_bind_all_settings_to_independent_room_and_standalone_features():
	var tool = Tool.new({"Global": {"World": null, "API": {}}})
	for setting in ["pattern_fill", "wall_builder", "path_builder", "roof_builder", "room_builder"]:
		var script_name = {"pattern_fill": "PatternFill", "wall_builder": "WallBuilder", "path_builder": "PathBuilder", "roof_builder": "RoofBuilder", "room_builder": "RoomBuilder"}[setting]
		tool.set("_" + setting, load(root.plus_file("scripts/features/" + script_name + ".gd")).new(null, null))
	var ui = UI.new(tool, null)
	ui.build(autofree(VBoxContainer.new()))
	var pattern = [["color_picker", "color_changed", "color", Color.red], ["rotation_spin", "value_changed", "rotation", 35.0], ["outline_check", "toggled", "outline", true]]
	var wall = [["color_picker", "color_changed", "color", Color.blue], ["shadow_check", "toggled", "shadow", false], ["bevel_check", "toggled", "joint", false]]
	var path = [["color_picker", "color_changed", "color", Color.green], ["width_spin", "value_changed", "width", 2.5], ["smoothness_slider", "value_changed", "smoothness", 0.4], ["sorting_option", "item_selected", "sorting", 1]]
	for setting in ["fade_in", "fade_out", "grow", "shrink", "block_light"]:
		path.append([setting + "_check", "toggled", setting, true])
	var roof = [["width_spin", "value_changed", "width", 420.0], ["type_option", "item_selected", "type", 2], ["sorting_option", "item_selected", "sorting", 1], ["placement_mode_option", "item_selected", "placement_mode", 2], ["shade_check", "toggled", "shade", false], ["sun_dir_slider", "value_changed", "sun_direction", 270.0], ["contrast_slider", "value_changed", "shade_contrast", 0.7]]
	for group in [[ui._pf_pattern_panel, pattern], [ui._rb_pattern_panel, pattern], [ui._wb_wall_panel, wall], [ui._rb_wall_panel, wall], [ui._pb_path_panel, path], [ui._rb_path_panel, path], [ui._rf_roof_panel, roof]]:
		var panel = group[0]
		for change in group[1]:
			panel.get(change[0]).emit_signal(change[1], change[3])
			var expected = 0 if change[2] == "joint" else change[3]
			assert_eq(panel.feature.get("active_" + change[2]), expected, change[2] + " updates its feature")
	ui._rb_pattern_panel.color_picker.emit_signal("color_changed", Color.yellow)
	assert_eq(tool._pattern_fill.active_color, Color.red)
	assert_eq(tool._room_builder._pattern_fill.active_color, Color.yellow)
	ui._rb_wall_panel.bevel_check.emit_signal("toggled", true)
	assert_eq(tool._wall_builder.active_joint, 0)
	assert_eq(tool._room_builder._wall_builder.active_joint, 1)
	ui._rb_path_panel.width_spin.emit_signal("value_changed", 4.0)
	assert_eq(tool._path_builder.active_width, 2.5)
	assert_eq(tool._room_builder._path_builder.active_width, 4.0)
	for index in range(5):
		ui._mode_selector.emit_signal("item_selected", index)
		assert_eq(tool._active_mode, ui._mode_selector.get_item_id(index))
	ui._rb_sub_mode_selector.emit_signal("item_selected", 4)
	assert_eq(tool._room_builder.active_sub_mode, 4)
	ui._rb_outline_mode_selector.emit_signal("item_selected", 1)
	assert_eq(tool._room_builder.active_outline_mode, 1)
	assert_true(ui._rb_path_container.visible)
	assert_false(ui._rb_wall_container.visible)
	ui._tool = null


func test_pattern_panel_offers_no_fill_and_uses_thumbnail_default_color():
	var filename = "res://results/colorable_pattern_probe.png"
	var image = Image.new()
	image.create(2, 2, false, Image.FORMAT_RGBA8)
	assert_eq(image.save_png(filename), OK)
	var menu = autofree(NativeCatalog.new())
	menu.add_icon_item(GradientTexture.new()) # Native Null icon.
	var icon = GradientTexture.new()
	menu.add_icon_item(icon)
	menu.Lookup = {"": 0, filename: 1}
	var host = PatternHost.new()
	host.textureMenu = menu
	host.colorable_icon = icon
	var panel = UI.PatternPanel.new()
	panel.allow_empty = true
	panel.feature = load(root.plus_file("scripts/features/PatternFill.gd")).new(null, null)
	autofree(panel.build())
	panel.try_build_grid_menu({"Editor": {"Tools": {"PatternShapeTool": host}}})
	assert_eq(panel._sg._all_items.size(), 2)
	assert_null(panel.feature.active_texture, "Initial No fill selection reaches RoomBuilder")
	panel._on_texture_selected(1)
	assert_true(panel.feature.active_texture is Texture)
	assert_eq(panel.feature.active_color, Color("6b3834"))
	assert_eq(panel.color_picker.color, Color("6b3834"))
	assert_eq_deep(host.queried, [icon])
	panel._sg._on_grid_item_selected(1)
	panel.color_picker.color = Color.blue
	panel.color_picker.emit_signal("color_changed", Color.blue)
	panel.release()
	assert_null(panel.feature.active_texture)
	panel._catalogs.clear()
	panel.try_build_grid_menu({"Editor": {"Tools": {"PatternShapeTool": host}}})
	assert_eq(panel._sg._selected_original, 1)
	assert_true(panel.feature.active_texture is Texture)
	assert_eq(panel.feature.active_color, Color.blue)
	assert_eq(panel.color_picker.color, Color.blue)
	panel._on_texture_selected(0)
	assert_null(panel.feature.active_texture, "User can return to outline-only rooms")
	panel.release()
	assert_eq(Directory.new().remove(filename), OK)


func test_path_catalog_is_complete_and_selection_survives_native_filter_changes():
	var source = autofree(NativeCatalog.new())
	source.add_icon_item(GradientTexture.new())
	source.Lookup = {"1": 0} # Host search currently shows only the second asset.
	var assets = Menu.new()
	assets.textures = [GradientTexture.new(), GradientTexture.new()]
	var panel = UI.PathPanel.new(assets)
	panel.feature = load(root.plus_file("scripts/features/PathBuilder.gd")).new(null, null)
	autofree(panel.build())
	var tool_fixture = HostTool.new()
	tool_fixture.Controls = {"Texture": source}
	panel.try_build_grid_menu({"Editor": {"Tools": {"PathTool": tool_fixture}}})
	assert_eq(panel._sg._all_items.size(), 2, "Owned catalog includes every installed path")
	assert_eq(source.get_item_count(), 1, "Native search remains untouched")
	source.clear()
	source.Lookup.clear()
	panel._on_texture_selected(1)
	assert_true(panel.feature.active_texture == assets.textures[1])
	assert_eq(source.selection_calls, 0)
	assert_null(tool_fixture.Texture)
	panel.release()


func test_wall_grid_tints_thumbnails_without_loading_each_full_texture():
	var source = autofree(NativeCatalog.new())
	source.Load("Walls")
	var host = HostTool.new()
	host.Controls = {"Texture": source}
	var assets = Menu.new()
	assets.textures = [GradientTexture.new(), GradientTexture.new()]
	var panel = UI.WallPanel.new(assets)
	autofree(panel.build())
	panel.try_build_grid_menu({"Editor": {"Tools": {"WallTool": host}}})
	assert_eq_deep(host.color_queries, [source.get_item_icon(0), source.get_item_icon(1)])
	assert_eq(panel._sg._all_items[1].modulate, Color("6b3834"))
	assert_eq(assets.lookups.size(), 1, "Only the selected full texture is resolved")
	assert_eq(source.selection_calls, 0)
	assert_null(host.Texture)
	panel.release()


func test_wall_and_path_panel_selections_remain_independent_between_features():
	var tool = Tool.new({"Global": {"API": {}, "Editor": {"Tools": {}}}})
	tool._wall_builder = load(root.plus_file("scripts/features/WallBuilder.gd")).new(null, null)
	tool._path_builder = load(root.plus_file("scripts/features/PathBuilder.gd")).new(null, null)
	tool._room_builder = load(root.plus_file("scripts/features/RoomBuilder.gd")).new(null, null)
	var ui = UI.new(tool, null)
	var panel = autofree(VBoxContainer.new())
	ui.build(panel)
	var texture_a = GradientTexture.new()
	var texture_b = GradientTexture.new()
	for panels in [[ui._wb_wall_panel, ui._rb_wall_panel], [ui._pb_path_panel, ui._rb_path_panel]]:
		var host = HostTool.new()
		var menu = Menu.new()
		menu.target = host
		menu.textures = [texture_a, texture_b]
		for item in panels:
			item._asset_script = menu
			item._index_to_path = ["0", "1"]
			item._sg._all_items = [{"modulate": Color.white}, {"modulate": Color.white}]
		panels[0]._on_texture_selected(0)
		panels[1]._on_texture_selected(1)
		assert_null(host.Texture, "Selection never changes the native tool")
		assert_eq(menu.lookups.size(), 2)
	assert_true(tool._wall_builder.active_texture == texture_a)
	assert_true(tool._path_builder.active_texture == texture_a)
	assert_true(tool._room_builder._wall_builder.active_texture == texture_b)
	assert_true(tool._room_builder._path_builder.active_texture == texture_b)
	ui._tool = null
	tool.parent_mod = null


func test_raw_pattern_texture_reuses_godot_cache_without_import_files():
	var panel = UI.PatternPanel.new()
	var filename = "res://results/raw_pattern_cache_probe.png"
	var image = Image.new()
	image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.red)
	assert_eq(image.save_png(filename), OK)
	var first = panel._load_texture_safe(filename)
	assert_true(first is Texture)
	assert_true(ResourceLoader.has_cached(filename))
	var second = panel._load_texture_safe(filename)
	assert_true(first == second, "Existing raw textures reuse the native cache")
	assert_eq(first.get_width(), 2)
	assert_eq(first.flags, 6, "Raw patterns use the host's repeat flags")
	assert_eq(Directory.new().remove(filename), OK)


func test_native_wall_and_path_creation_use_feature_texture_after_global_tool_changes():
	var room_fixture = load("res://unit/test_rooms.gd")
	var path_fixture = load("res://unit/test_path_creation.gd")
	var walls = autofree(room_fixture.NativeContainer.new())
	var paths = autofree(path_fixture.Pathways.new())
	var host = HostTool.new()
	var texture_a = GradientTexture.new()
	var texture_b = GradientTexture.new()
	texture_a.resource_path = "res://path_a.png"
	texture_b.resource_path = "res://path_b.png"
	host.Texture = texture_b
	var parent = {"Global": {"API": {}, "Editor": {"Tools": {"WallTool": host, "PathTool": host}}, "World": {"Level": {"Walls": walls, "Pathways": paths}}}}
	var api = room_fixture.MarkerApi.new()
	var wall = load(root.plus_file("scripts/features/WallBuilder.gd")).new(api, null, parent)
	var path = load(root.plus_file("scripts/features/PathBuilder.gd")).new(api, null, parent)
	wall.active_texture = texture_a
	path.active_texture = texture_a
	assert_true(wall.build_at(Vector2.ZERO))
	assert_true(walls.received_texture == texture_a)
	assert_true(path.build_at(Vector2.ZERO))
	assert_true(paths.received_data.texture == texture_a.resource_path)
	var room = load(root.plus_file("scripts/features/RoomBuilder.gd")).new(api, null, parent)
	room._wall_builder.active_texture = texture_b
	room._path_builder.active_texture = texture_b
	host.Texture = texture_a
	assert_true(is_instance_valid(room._wall_builder._create_wall(room_fixture.TRIANGLE)))
	assert_true(walls.received_texture == texture_b)
	assert_true(is_instance_valid(room._path_builder._create_path(room_fixture.TRIANGLE)))
	assert_true(paths.received_data.texture == texture_b.resource_path)
	yield(get_tree(), "idle_frame")

func test_map_release_clears_all_feature_textures_before_any_panel_reopens():
	var tool = Tool.new({"Global": {"API": {}, "World": null}})
	for entry in [["PatternFill", "_pattern_fill"], ["WallBuilder", "_wall_builder"], ["PathBuilder", "_path_builder"], ["RoofBuilder", "_roof_builder"], ["RoomBuilder", "_room_builder"]]:
		tool.set(entry[1], load(root.plus_file("scripts/features/" + entry[0] + ".gd")).new(null, null))
	var ui = UI.new(tool, null)
	ui.build(autofree(VBoxContainer.new()))
	var panels = [ui._pf_pattern_panel, ui._wb_wall_panel, ui._pb_path_panel, ui._rf_roof_panel, ui._rb_pattern_panel, ui._rb_wall_panel, ui._rb_path_panel]
	for panel in panels:
		panel.feature.active_texture = GradientTexture.new()
	ui.release_all_grid_menus()
	for panel in panels:
		assert_null(panel.feature.active_texture, "Hidden/unpopulated panels cannot retain old map textures")
	ui._tool = null

func test_wall_map_reload_preserves_asset_path_and_color_and_falls_back_if_missing():
	var source = autofree(NativeCatalog.new())
	source.Load("Walls")
	var host = HostTool.new()
	host.Controls = {"Texture": source}
	var assets = Menu.new()
	assets.textures = [GradientTexture.new(), GradientTexture.new()]
	var panel = UI.WallPanel.new(assets)
	panel.feature = load(root.plus_file("scripts/features/WallBuilder.gd")).new(null, null)
	autofree(panel.build())
	var global_ref = {"Editor": {"Tools": {"WallTool": host}}}
	panel.try_build_grid_menu(global_ref)
	panel._sg._on_grid_item_selected(1)
	panel.color_picker.color = Color.blue
	panel.color_picker.emit_signal("color_changed", Color.blue)
	panel.release()
	assert_null(panel.feature.active_texture)
	panel._catalogs.clear()
	assets.textures = [GradientTexture.new(), GradientTexture.new()]
	assets.lookups.clear()
	panel.try_build_grid_menu(global_ref)
	assert_true(panel.feature.active_texture == assets.textures[1], "Resolve stable path against new catalog")
	assert_eq_deep(assets.lookups, [["Walls", "1"]])
	assert_eq(panel._sg._selected_original, 1)
	assert_eq(panel.feature.active_color, Color.blue)
	assert_eq(panel.color_picker.color, Color.blue)
	panel.release()
	panel._catalogs.clear()
	source.remove_item(1)
	source.Lookup = {"0": 0}
	panel.try_build_grid_menu(global_ref)
	assert_true(panel.feature.active_texture == assets.textures[0])
	assert_eq(panel._sg._selected_original, 0)
	assert_eq(panel.feature.active_color, Color("6b3834"))
	assert_eq(panel.color_picker.color, Color("6b3834"))
	assets.textures[0] = null
	panel._on_texture_selected(0)
	assert_null(panel.feature.active_texture, "An unreadable selected asset cannot reuse the previous texture")
