extends "res://addons/gut/test.gd"

var mod_root = ProjectSettings.globalize_path("res://").plus_file("..")
var Tool = ResourceLoader.load(mod_root.plus_file("scripts/tool/BuildingPlannerTool.gd"))
var UI = ResourceLoader.load(mod_root.plus_file("scripts/tool/BuildingPlannerToolUI.gd"))
var Room = ResourceLoader.load(mod_root.plus_file("scripts/features/RoomBuilder.gd"))
var selections = []


class WorldCanvas:
	extends Node2D
	var IsInsideBounds = true
	var MousePosition = Vector2(13, 27)
	func GetSnappedPosition(position):
		return position.snapped(Vector2(10, 10))


class ApiSource:
	extends Reference
	signal api_registered(id, api)
	signal layers_changed
	func has(_name):
		return false


class PanelState:
	extends Reference
	var _settings = {}
	var _sg = null
	var releases = 0
	var builds = 0
	func release():
		releases += 1
	func try_build_grid_menu(_global):
		builds += 1
	func refresh_layer_option(_global, _layer, _layers = null):
		pass
	func update_camt_color_state(_global):
		pass


class Preview:
	extends Reference
	var position = Vector2.ZERO
	var hidden = false
	var state = {}
	func update_preview(point, current_state):
		position = point
		hidden = false
		state = current_state
	func build_room_at(_point, current_state):
		state = current_state
	func stop_preview():
		hidden = true


class ShapeState:
	extends Reference
	var angle = 15
	var queries = 0
	func get_tool_state():
		queries += 1
		return {"active_shape_angle": angle}


class CanvasFeature:
	extends Reference
	var calls = []
	func build_at(position):
		calls.append(["build", position])
		return false
	func build_room_at(position, state):
		calls.append(["room", position, state])
		return false


func test_canvas_dispatch_routes_every_mode_and_only_snaps_rooms():
	var tool = Tool.new({"Global": {"Editor": {"IsSnapping": true}}})
	tool.cached_worldui = autofree(WorldCanvas.new())
	tool.cached_worldui.MousePosition = Vector2(99, 99) # Click coordinates, not the live cursor, drive placement.
	tool._gl_api = ShapeState.new()
	for field in ["_pattern_fill", "_wall_builder", "_path_builder", "_room_builder", "_roof_builder"]:
		tool.set(field, CanvasFeature.new())
	for mode in [tool.Mode.PATTERN_FILL, tool.Mode.WALL_BUILDER, tool.Mode.PATH_BUILDER, tool.Mode.ROOM_BUILDER, tool.Mode.ROOF_BUILDER]:
		tool._active_mode = mode
		assert_true(tool.handle_canvas_click(Vector2(13, 27)), "Loaded mode consumes even an unsuccessful placement")
	assert_eq_deep(tool._pattern_fill.calls, [["build", Vector2(13, 27)]])
	for feature in [tool._wall_builder, tool._path_builder, tool._roof_builder]:
		assert_eq_deep(feature.calls, [["build", Vector2(13, 27)]])
	assert_eq_deep(tool._room_builder.calls, [["room", Vector2(10, 30), {"active_shape_angle": 15}]])
	tool._active_mode = -1
	assert_false(tool.handle_canvas_click(Vector2.ZERO))
	tool._active_mode = tool.Mode.ROOF_BUILDER
	tool._roof_builder = null
	assert_false(tool.handle_canvas_click(Vector2.ZERO), "Missing feature does not consume a click")


func test_late_api_registration_rebinds_existing_panels_and_invalidates_old_selections():
	var api = ShapeState.new()
	var tool = Tool.new({"Global": {"Root": mod_root + "/", "World": null, "API": {"GuidesLinesApi": api}}})
	var ui = UI.new(tool, null)
	ui.build(autofree(VBoxContainer.new()))
	tool._ui = ui
	assert_null(ui._pf_pattern_panel.feature)
	assert_null(ui._rb_path_panel.feature)
	ui._catalogs["Paths"] = {"items": [{"tooltip": "Old map"}]}
	ui._pb_path_panel._sg.populate(ui._catalogs.Paths.items)
	ui._pb_path_panel._populated = true
	ui._rb_sub_mode_selector.select(4)
	ui._on_rb_sub_mode(4)
	ui._rb_outline_mode_selector.select(1)
	ui._on_rb_outline_mode(1)
	ui._rb_pattern_panel.rotation_spin.value = 37
	ui._rb_pattern_panel.rotation_spin.emit_signal("value_changed", 37.0)
	ui._rb_pattern_panel.outline_check.pressed = true
	ui._rb_pattern_panel.color_picker.color = Color.blue
	ui._rb_pattern_panel.color_picker.emit_signal("color_changed", Color.blue)
	ui._rb_path_panel.width_spin.value = 2.3
	ui._rb_path_panel.width_spin.emit_signal("value_changed", 2.3)
	ui._rb_path_panel.smoothness_slider.value = 0.4
	ui._rb_path_panel.smoothness_slider.emit_signal("value_changed", 0.4)
	ui._rb_path_panel.fade_in_check.pressed = true
	ui._rb_path_panel.block_light_check.pressed = true
	ui._wb_wall_panel.bevel_check.pressed = false
	ui._pf_pattern_panel.rotation_spin.value = 11
	ui._pf_pattern_panel.rotation_spin.emit_signal("value_changed", 11.0)
	# API can arrive after the user has already opened and disabled the tool.
	tool._on_api_registered("GuidesLinesApi", api)
	assert_true(ui._catalogs.empty())
	assert_false(ui._pb_path_panel._populated)
	assert_true(ui._pf_pattern_panel.feature == tool._pattern_fill)
	assert_true(ui._wb_wall_panel.feature == tool._wall_builder)
	assert_true(ui._pb_path_panel.feature == tool._path_builder)
	assert_true(ui._rf_roof_panel.feature == tool._roof_builder)
	assert_true(ui._rb_pattern_panel.feature == tool._room_builder._pattern_fill)
	assert_true(ui._rb_wall_panel.feature == tool._room_builder._wall_builder)
	assert_true(ui._rb_path_panel.feature == tool._room_builder._path_builder)
	assert_eq(tool._room_builder.active_sub_mode, 4)
	assert_eq(tool._room_builder.active_outline_mode, 1)
	assert_eq(tool._room_builder._pattern_fill.active_rotation, 37.0)
	assert_true(tool._room_builder._pattern_fill.active_outline)
	assert_eq(tool._room_builder._pattern_fill.active_color, Color.blue)
	assert_almost_eq(tool._room_builder._path_builder.active_width, 2.3, 0.001)
	assert_almost_eq(tool._room_builder._path_builder.active_smoothness, 0.4, 0.001)
	assert_true(tool._room_builder._path_builder.active_fade_in)
	assert_true(tool._room_builder._path_builder.active_block_light)
	assert_eq(tool._wall_builder.active_joint, 0)
	assert_eq(tool._pattern_fill.active_rotation, 11.0)
	assert_false(ui._rb_wall_container.visible)
	assert_true(ui._rb_path_container.visible)
	ui._rb_pattern_panel.color_picker.emit_signal("color_changed", Color.red)
	assert_eq(tool._room_builder._pattern_fill.active_color, Color.red)
	assert_eq(tool._pattern_fill.active_color, Color.white)
	tool.shutdown()


func _selected(index):
	selections.append(index)


func test_active_tool_tracks_late_camt_without_reopening_a_panel():
	var global_ref = {"ModMapData": {}, "API": {}, "World": null}
	var tool = Tool.new({"Global": global_ref})
	var ui = UI.new(tool, null)
	ui.build(autofree(VBoxContainer.new()))
	tool._ui = ui
	tool.is_enabled = true
	tool.Update(0)
	assert_null(ui._pb_path_panel._camt_present, "Unrelated modes do not poll optional path integration")
	tool._active_mode = tool.Mode.PATH_BUILDER
	tool.Update(0)
	for panel in [ui._pb_path_panel, ui._rb_path_panel]:
		assert_true(panel.color_picker.disabled)
	global_ref.ModMapData["UchideshiNodeData"] = {}
	tool.Update(0)
	for panel in [ui._pb_path_panel, ui._rb_path_panel]:
		assert_false(panel.color_picker.disabled)
		panel.color_picker.emit_signal("color_changed", Color.blue)
	tool.Update(0)
	assert_eq(ui._pb_path_panel._settings.color, Color.blue, "Stable presence preserves user color")
	global_ref.ModMapData.clear()
	tool.Update(0)
	for panel in [ui._pb_path_panel, ui._rb_path_panel]:
		assert_true(panel.color_picker.disabled)
		assert_eq(panel._settings.color, Color.white)
	ui._tool = null
	tool._ui = null


class LayerSource:
	extends Reference
	var queries = 0
	var layers = {100: "Default", 200: "Custom"}
	func get_user_layers(_level):
		queries += 1
		return layers


class LayerWorld:
	extends Reference
	var Level = 1
	func GetCurrentLevel():
		return self


func test_layer_refresh_publishes_fallback_and_matches_visible_selection():
	var source = LayerSource.new()
	var global_ref = {"World": LayerWorld.new(), "API": {"LayerApi": source}}
	for kind in ["pattern", "path"]:
		var panel = UI.PatternPanel.new() if kind == "pattern" else UI.PathPanel.new()
		panel.layer_option = autofree(OptionButton.new())
		panel.feature = load(mod_root.plus_file("scripts/features/PatternFill.gd")).new(null, null)
		panel.feature.active_layer = 200
		source.layers = {100: "Default", 200: "Custom"}
		panel.refresh_layer_option(source.layers, source.layers.keys())
		assert_eq(panel.feature.active_layer, 200)
		source.layers = {100: "Default"}
		panel.refresh_layer_option(source.layers, source.layers.keys())
		assert_eq(panel.feature.active_layer, 100)
		assert_eq(panel.layer_option.get_item_id(panel.layer_option.selected), panel.feature.active_layer)
		source.layers = {300: "Only layer"}
		panel.refresh_layer_option(source.layers, source.layers.keys())
		assert_eq(panel.feature.active_layer, 300)


func test_late_layer_binding_preserves_the_visible_custom_layer():
	var source = LayerSource.new()
	var global_ref = {"World": LayerWorld.new(), "API": {"LayerApi": source}}
	var tool = Tool.new({"Global": global_ref})
	var ui = UI.new(tool, null)
	ui.build(autofree(VBoxContainer.new()))
	var panel = ui._rb_path_panel
	panel.layer_option.select(1)
	panel.layer_option.emit_signal("item_selected", 1)
	ui._refresh_all_layer_options(global_ref)
	assert_eq(panel.layer_option.get_item_id(panel.layer_option.selected), 200)
	tool._room_builder = Room.new(null, null)
	ui.bind_features()
	assert_eq(tool._room_builder._path_builder.active_layer, 200)
	ui._tool = null


func test_grid_initial_selection_and_filter_fallback_update_the_callback():
	selections = []
	var grid = UI.SearchableGrid.new()
	autofree(grid.build())
	grid.on_item_selected = funcref(self, "_selected")
	grid.populate([{"tooltip": "wood"}, {"tooltip": "stone"}])
	assert_eq_deep(selections, [0])
	grid._on_grid_item_selected(1)
	grid._on_search_changed("wood")
	assert_eq(grid._selected_original, 0, "Filter fallback must also update selection state")
	assert_eq_deep(selections, [0, 1, 0])
	grid._on_search_changed("")
	assert_eq_deep(selections, [0, 1, 0])
	grid._on_search_changed("missing")
	assert_eq(grid._grid_menu.get_item_count(), 0)
	assert_eq_deep(selections, [0, 1, 0])
	selections.clear()
	grid.populate([{"tooltip": "wood"}, {"tooltip": "stone"}], 1)
	assert_eq_deep(selections, [1])
	assert_eq(grid._selected_original, 1)
	assert_eq_deep(Array(grid._grid_menu.get_selected_items()), [1])


func test_disabled_update_does_not_recreate_overlay_and_freed_overlay_recovers():
	var canvas = autofree(WorldCanvas.new())
	add_child(canvas)
	var tool = Tool.new({"Global": {"Root": mod_root + "/"}})
	tool.cached_worldui = canvas
	tool.Update(0)
	assert_null(tool._overlay)
	tool.is_enabled = true
	tool.Update(0)
	assert_true(is_instance_valid(tool._overlay))
	var first = tool._overlay
	first.free()
	tool.Update(0)
	assert_true(is_instance_valid(tool._overlay), "Freed WorldUI child must be replaced")
	var overlay = tool._overlay
	tool.Disable()
	assert_null(tool._overlay)
	assert_null(overlay.tool, "Break the overlay to tool reference cycle")
	assert_eq(canvas.get_child_count(), 0, "Detach before deferred deletion")
	tool.Update(0)
	assert_null(tool._overlay)
	yield(get_tree(), "idle_frame")
	assert_false(is_instance_valid(overlay))


func test_map_change_clears_registry_but_tool_switch_preserves_it():
	var tool = Tool.new(null)
	var room = Room.new(null, null)
	tool._room_builder = room
	var world = autofree(Node.new())
	var other_world = autofree(Node.new())
	var node = autofree(Node.new())
	tool.cached_world = world
	room._registry.register(4, [node], [])
	tool.Disable()
	assert_true(room._registry.has_entry(4))
	tool.set_world_references(world, null)
	assert_true(room._registry.has_entry(4), "Repeated frame in the same map preserves registry")
	tool.gl_tool_state = {"ready": true}
	tool.set_world_references(other_world, null)
	assert_false(room._registry.has_entry(4))
	assert_eq_deep(tool.gl_tool_state, {})
	assert_false(node.is_queued_for_deletion(), "Changing maps must not delete map objects")
	room._registry.register(4, [node], [])
	tool.set_world_references(null, null)
	assert_false(room._registry.has_entry(4), "Map close also resets associations")


func test_shutdown_disconnects_owned_api_signal():
	var source = ApiSource.new()
	var tool = Tool.new(null)
	tool._api_source = source
	source.connect("api_registered", tool, "_on_api_registered")
	tool.shutdown()
	assert_false(source.is_connected("api_registered", tool, "_on_api_registered"))
	assert_null(tool.parent_mod)
	tool.shutdown()
	assert_null(tool._api_source, "Repeated teardown is safe")


func test_tool_switch_retains_grids_and_unload_disconnects_the_original_layer_source():
	var source = ApiSource.new()
	var tool = Tool.new(null)
	var ui = UI.new(tool, null)
	var panel = PanelState.new()
	ui._pf_pattern_panel = panel
	ui._all_panels = [panel]
	ui._layer_signaling = source
	source.connect("layers_changed", ui, "_on_layers_changed")
	tool._ui = ui
	tool.Disable()
	assert_eq(panel.releases, 0, "Owned grids survive tool switches")
	assert_true(source.is_connected("layers_changed", ui, "_on_layers_changed"))
	tool.shutdown()
	assert_eq(panel.releases, 1)
	assert_false(source.is_connected("layers_changed", ui, "_on_layers_changed"))
	assert_null(ui._tool)
	assert_null(tool._ui)


func test_grid_initialization_only_visits_the_visible_mode_and_room_outline():
	var tool = Tool.new({"Global": {"API": {}}})
	var ui = UI.new(tool, null)
	var panels = []
	for key in ["_pf_pattern_panel", "_wb_wall_panel", "_pb_path_panel", "_rb_pattern_panel", "_rb_wall_panel", "_rb_path_panel", "_rf_roof_panel"]:
		var state = PanelState.new()
		ui.set(key, state)
		panels.append(state)
	ui._rb_outline_mode_selector = autofree(OptionButton.new())
	ui._rb_outline_mode_selector.add_item("Wall")
	ui._rb_outline_mode_selector.add_item("Path")
	ui.try_build_grid_menus(ui.Mode.WALL_BUILDER)
	for i in range(panels.size()):
		assert_eq(panels[i].builds, 1 if i == 1 else 0)
	ui.try_build_grid_menus(ui.Mode.ROOM_BUILDER)
	assert_eq(panels[3].builds, 1)
	assert_eq(panels[4].builds, 1)
	assert_eq(panels[5].builds, 0)
	ui._rb_outline_mode_selector.selected = 1
	tool.is_enabled = true
	ui._on_rb_outline_mode(1)
	assert_eq(panels[4].builds, 1)
	assert_eq(panels[5].builds, 1)
	assert_eq(panels[6].builds, 0)
	ui._tool = null


func test_room_preview_uses_click_snap_and_canvas_boundaries():
	var canvas = autofree(WorldCanvas.new())
	add_child(canvas)
	var editor = {"IsSnapping": true}
	var controlled_tool = GDScript.new()
	controlled_tool.source_code = 'extends "' + mod_root.plus_file("scripts/tool/BuildingPlannerTool.gd") + '"\nvar on_canvas = true\nfunc _init(mod).(mod):\n\tpass\nfunc is_mouse_on_canvas() -> bool:\n\treturn on_canvas\n'
	assert_eq(controlled_tool.reload(), OK)
	var tool = controlled_tool.new({"Global": {"Editor": editor}})
	tool.cached_worldui = canvas
	tool.is_enabled = true
	tool._active_mode = tool.Mode.ROOM_BUILDER
	tool._room_builder = Preview.new()
	tool._gl_api = ShapeState.new()
	# Supply an existing overlay so this check only exercises preview/input policy.
	var overlay = autofree(Node2D.new())
	canvas.add_child(overlay)
	tool._overlay = overlay
	for point in [Vector2(449, 200), Vector2(500, 99), Vector2(500, 701), Vector2(450, 100), Vector2(500, 700)]:
		assert_eq(tool.is_canvas_position(point, Vector2(1200, 800)), point.x >= 450 and point.y >= 100 and point.y <= 700)
		tool.Update(0)
		assert_eq(tool._room_builder.state.active_shape_angle, tool._gl_api.angle)
		tool._gl_api.angle += 5
		assert_eq(tool._room_builder.position, tool.room_position(canvas.MousePosition))
		assert_eq(tool._room_builder.position, Vector2(10, 30))
		assert_eq(tool._room_builder.hidden, not tool.is_mouse_on_canvas())
	assert_false(tool.is_canvas_position(Vector2(499, 200), Vector2(1200, 800), 500), "Wider sidebar does not receive canvas actions")
	assert_true(tool.is_canvas_position(Vector2(500, 200), Vector2(1200, 800), 500))
	editor.IsSnapping = false
	assert_eq(tool.room_position(canvas.MousePosition), canvas.MousePosition)
	tool.on_canvas = false
	var queries = tool._gl_api.queries
	tool.Update(0)
	assert_eq(tool._gl_api.queries, queries, "Sidebar preview does not fetch tool state")
	assert_true(tool._room_builder.hidden)
	tool.on_canvas = true
	tool._gl_api.angle = 90
	tool.handle_canvas_click(Vector2.ZERO)
	assert_eq(tool._room_builder.state.active_shape_angle, 90, "Click uses fresh state even before the next preview frame")
	tool._overlay = null

func test_mode_switch_reads_layer_api_once_and_all_panels_share_sorted_layers():
	var source = LayerSource.new()
	source.layers = {300: "Last", 100: "First", 200: "Middle"}
	var tool = Tool.new({"Global": {"API": {"LayerApi": source}, "World": LayerWorld.new(), "Editor": {"Tools": {}}}})
	var ui = UI.new(tool, null)
	ui.build(autofree(VBoxContainer.new()))
	source.queries = 0
	tool.is_enabled = true
	ui._show_section(tool.Mode.WALL_BUILDER)
	assert_eq(source.queries, 1)
	for panel in [ui._pf_pattern_panel, ui._pb_path_panel, ui._rb_pattern_panel, ui._rb_path_panel]:
		assert_eq(panel.layer_option.get_item_count(), 3)
		for i in range(3):
			assert_eq(panel.layer_option.get_item_id(i), 100 * (i + 1))
	ui._tool = null

class EditorState:
	extends Reference
	var Tools = {}
	var SearchHasFocus = false


func test_hiding_sections_and_disabling_release_only_owned_search_focus():
	var editor = EditorState.new()
	var tool = Tool.new({"Global": {"API": {}, "World": null, "Editor": editor}})
	var ui = UI.new(tool, null)
	var panel = autofree(VBoxContainer.new())
	add_child(panel)
	ui.build(panel)
	tool._ui = ui
	var search = ui._pf_pattern_panel._sg._search_edit
	search.grab_focus()
	assert_true(search.has_focus())
	assert_true(editor.SearchHasFocus, "Owned search focus suppresses host shortcuts")
	ui._show_section(tool.Mode.WALL_BUILDER)
	assert_false(search.has_focus())
	assert_false(editor.SearchHasFocus, "Changing modes restores host shortcuts")
	ui._show_section(tool.Mode.ROOM_BUILDER)
	ui._rb_pattern_panel._sg._search_edit.grab_focus()
	ui._rb_wall_panel._sg._search_edit.grab_focus()
	assert_true(editor.SearchHasFocus, "Moving between searches keeps shortcuts suppressed")
	ui._show_section(tool.Mode.PATTERN_FILL)
	search.grab_focus()
	assert_true(search.has_focus())
	tool.Disable()
	assert_false(search.has_focus())
	assert_false(editor.SearchHasFocus, "Disabling the tool restores host shortcuts")
	var unrelated = autofree(LineEdit.new())
	add_child(unrelated)
	unrelated.grab_focus()
	editor.SearchHasFocus = true
	tool.Disable()
	assert_true(unrelated.has_focus(), "Other tools keep ownership of their focus")
	assert_true(editor.SearchHasFocus, "Other tools keep ownership of shortcut suppression")
	tool.shutdown()
	assert_true(editor.SearchHasFocus, "Unloading does not reset another tool's suppression")


func test_all_searches_suppress_shortcuts_and_release_on_map_change():
	var editor = EditorState.new()
	var tool = Tool.new({"Global": {"API": {}, "World": null, "Editor": editor}})
	var ui = UI.new(tool, null)
	var panel = autofree(VBoxContainer.new())
	add_child(panel)
	ui.build(panel)
	tool._ui = ui
	for section in ui._all_panels:
		# Exercise every search independently of section visibility.
		section._sg._search_edit.emit_signal("focus_entered")
		assert_true(editor.SearchHasFocus)
		section._sg._search_edit.emit_signal("focus_exited")
		assert_false(editor.SearchHasFocus)
	ui._pf_pattern_panel._sg._search_edit.grab_focus()
	assert_true(editor.SearchHasFocus)
	ui.release_all_grid_menus()
	assert_false(editor.SearchHasFocus, "Map changes restore host shortcuts")
	tool.shutdown()


class OverlayTool:
	extends Reference
	enum Mode { ROOM_BUILDER }
	var _active_mode = Mode.ROOM_BUILDER
	var is_enabled = true
	var parent_mod = {"Global": {"Editor": {"Windows": {}}}}
	var on_canvas = false
	var scrolls = []
	func is_mouse_on_canvas():
		return on_canvas
	func handle_room_scroll(direction, scale):
		scrolls.append([direction, scale])


func test_room_wheel_input_ignores_sidebar_and_keeps_canvas_rotation_and_scale():
	var overlay = autofree(load(mod_root.plus_file("scripts/overlay/BuildingPlannerOverlay.gd")).new())
	add_child(overlay)
	var tool = OverlayTool.new()
	overlay.tool = tool
	var event = InputEventMouseButton.new()
	event.pressed = true
	for button in [BUTTON_WHEEL_UP, BUTTON_WHEEL_DOWN]:
		event.button_index = button
		overlay._input(event)
	assert_true(tool.scrolls.empty(), "Sidebar wheel reaches Control instead of changing room overrides")
	tool.on_canvas = true
	event.button_index = BUTTON_WHEEL_UP
	overlay._input(event)
	event.alt = true
	event.button_index = BUTTON_WHEEL_DOWN
	overlay._input(event)
	assert_eq_deep(tool.scrolls, [[1, false], [-1, true]])
	event.control = true
	overlay._input(event)
	assert_eq(tool.scrolls.size(), 2, "Ctrl wheel remains reserved for camera zoom")
	overlay.tool = null


class Toolbar:
	extends Reference
	var panel = null
	var attempts = 0
	func CreateModTool(_owner, _category, _id, _label, _icon):
		attempts += 1
		return panel


func test_entry_toolbar_failure_disconnects_partial_tool_and_retries_cleanly():
	var file = File.new()
	assert_eq(file.open(mod_root.plus_file("BuildingPlanner.gd"), File.READ), OK)
	var script = GDScript.new()
	script.source_code = "var Global = {}\nvar Script = null\n" + file.get_as_text()
	script.resource_path = mod_root.plus_file("BuildingPlanner.gd")
	file.close()
	assert_eq(script.reload(), OK)
	var entry = script.new()
	var api = ApiSource.new()
	var toolbar = Toolbar.new()
	entry.Global = {"Root": mod_root + "/", "Editor": {"Toolset": toolbar, "Tools": {}}, "API": api, "World": null, "WorldUI": null, "Camera": null}
	entry.BuildingPlannerToolClass = Tool
	entry.update(0)
	assert_null(entry._tool)
	assert_false(entry._tool_created)
	assert_eq(api.get_signal_connection_list("api_registered").size(), 0, "Failed tool must release API subscription")
	toolbar.panel = autofree(VBoxContainer.new())
	toolbar.panel.rect_min_size.x = 244
	entry.update(0)
	assert_eq(toolbar.panel.rect_min_size.x, 294.0, "Only the mod panel gains 50 pixels")
	assert_eq(toolbar.attempts, 2)
	assert_true(entry._tool_created)
	assert_true(entry._tool._ui != null)
	assert_eq(api.get_signal_connection_list("api_registered").size(), 1)
	entry.update(0)
	assert_eq(toolbar.attempts, 2, "A successful toolbar is never created twice")
	assert_eq(toolbar.panel.rect_min_size.x, 294.0, "Updates do not accumulate panel width")
	entry.unload()
	assert_eq(api.get_signal_connection_list("api_registered").size(), 0)
	entry.BuildingPlannerToolClass = null


func test_enable_without_tool_state_method_clears_stale_snapshot():
	var tool = Tool.new(null)
	tool._gl_api = Reference.new()
	tool.gl_tool_state = {"ready": true}
	tool.Enable()
	assert_true(tool.gl_tool_state.empty())
	assert_true(tool.is_enabled)
	tool.shutdown()


func test_room_overrides_are_visible_and_reset_without_changing_guideslines():
	var tool = Tool.new({"Global": {"World": null, "API": {}}})
	tool._room_builder = Room.new(null, null)
	var ui = UI.new(tool, null)
	ui.build(autofree(VBoxContainer.new()))
	tool._ui = ui
	tool.handle_room_scroll(1, false)
	tool.handle_room_scroll(1, true)
	assert_true(ui._rb_override_label.text.find("5.0 deg") >= 0)
	assert_true(ui._rb_override_label.text.find("1.10x") >= 0)
	ui._reset_room_overrides()
	assert_eq(tool._room_builder.shape_angle_offset, 0.0)
	assert_eq(tool._room_builder.shape_scale_factor, 1.0)
	assert_true(ui._rb_override_label.text.find("0.0 deg") >= 0)
	assert_true(ui._rb_override_label.text.find("1.00x") >= 0)
	tool.shutdown()


func test_grid_search_matches_all_words_case_and_separators_and_preserves_selection():
	selections = []
	var grid = UI.SearchableGrid.new()
	autofree(grid.build())
	grid.on_item_selected = funcref(self, "_selected")
	grid.populate([{"tooltip": "Red-Brick_Wall"}, {"tooltip": "Blue_stone"}, {"tooltip": "Stone_RED"}], 2)
	grid._on_search_changed("  ReD  stone ")
	assert_eq_deep(grid._filtered_map, [2])
	assert_eq_deep(selections, [2])
	grid._on_search_changed("brick red")
	assert_eq_deep(grid._filtered_map, [0])
	assert_eq_deep(selections, [2, 0])
	grid._on_search_changed("missing")
	assert_true(grid._filtered_map.empty())
	grid._on_clear_pressed()
	assert_eq_deep(grid._filtered_map, [0, 1, 2])
	assert_eq_deep(selections, [2, 0])
	grid.clear()
	grid.populate([{"tooltip": "New wood"}])
	grid._on_search_changed("wood")
	assert_eq_deep(grid._filtered_map, [0])


func test_empty_layers_keep_selection_and_asset_loader_failures_are_logged():
	var fixture = load("res://unit/test_rooms.gd")
	var logger = fixture.DiagnosticLogger.new()
	var panel = UI.FeaturePanel.new()
	panel.LOGGER = logger
	panel.layer_option = autofree(OptionButton.new())
	panel.refresh_layer_option({100: "Default"}, [100])
	panel.refresh_layer_option({}, [])
	assert_eq(panel.layer_option.get_item_count(), 1)
	assert_eq(panel.layer_option.get_item_id(panel.layer_option.selected), 100)
	assert_eq(logger.errors.size(), 1)
	panel._index_to_path = ["", "res://missing.png"]
	assert_null(panel._asset_texture("Walls", 0))
	assert_eq(logger.errors.size(), 1, "Empty selection is not a loader failure")
	assert_null(panel._asset_texture("Walls", 1))
	assert_eq(logger.errors.size(), 2)
	assert_true("res://missing.png" in logger.errors.back())


class EmptyLayerSource:
	extends Reference
	var layers = {}
	var queried_level = null
	func get_user_layers(level):
		queried_level = level
		return layers


func test_real_layer_refresh_preserves_selection_after_empty_api_response():
	var fixture = load("res://unit/test_rooms.gd")
	var logger = fixture.DiagnosticLogger.new()
	var tool = Tool.new({"Global": {"World": null, "API": {}}})
	var ui = UI.new(tool, logger)
	ui.build(autofree(VBoxContainer.new()))
	for panel in [ui._pf_pattern_panel, ui._pb_path_panel, ui._rb_pattern_panel, ui._rb_path_panel]:
		panel.refresh_layer_option({300: "Existing"}, [300])
	var source = EmptyLayerSource.new()
	var level = autofree(Node.new())
	ui._refresh_all_layer_options({"API": {"LayerApi": source}, "World": {"Level": level}})
	assert_true(source.queried_level == level)
	for panel in [ui._pf_pattern_panel, ui._pb_path_panel, ui._rb_pattern_panel, ui._rb_path_panel]:
		assert_eq(panel.layer_option.get_item_id(panel.layer_option.selected), 300)
	assert_eq(logger.errors.size(), 4)
	ui._refresh_all_layer_options({"API": {}, "World": null})
	assert_eq(ui._pf_pattern_panel.layer_option.get_item_id(0), 100)
	tool.shutdown()


class ShapeOnlyState:
	extends ShapeState
	var shape_queries = 0
	func get_shape_state():
		shape_queries += 1
		return {"active_shape_angle": angle}

class PlacementState:
	extends ShapeOnlyState
	var placement_queries = 0
	func get_placement_state():
		placement_queries += 1
		return {"ready": true, "active_marker_type": "Template", "template_scale": 2.0}

func test_room_template_source_prefers_placement_snapshot_over_legacy_shape_state():
	var api = PlacementState.new()
	var tool = Tool.new({"Global": {"Editor": {"IsSnapping": false}}})
	tool._gl_api = api
	tool._active_mode = tool.Mode.ROOM_BUILDER
	tool._room_builder = Preview.new()
	assert_true(tool.handle_canvas_click(Vector2.ZERO))
	assert_eq(tool._room_builder.state.active_marker_type, "Template")
	assert_eq(tool._room_builder.state.template_scale, 2.0)
	assert_eq(api.placement_queries, 1)
	assert_eq(api.shape_queries, 0)
	assert_eq(api.queries, 0)
	tool._room_builder = null
	tool.shutdown()


func test_room_click_prefers_shape_snapshot_and_keeps_full_state_compatibility():
	var api = ShapeOnlyState.new()
	var tool = Tool.new({"Global": {"Editor": {"IsSnapping": false}}})
	tool._gl_api = api
	tool._active_mode = tool.Mode.ROOM_BUILDER
	tool._room_builder = Preview.new()
	for angle in [15, 35]:
		api.angle = angle
		assert_true(tool.handle_canvas_click(Vector2.ZERO))
		assert_eq(tool._room_builder.state.active_shape_angle, angle)
	assert_eq(api.shape_queries, 2)
	assert_eq(api.queries, 0)
	tool._gl_api = ShapeState.new()
	tool.handle_canvas_click(Vector2.ZERO)
	assert_eq(tool._gl_api.queries, 1)
	tool._room_builder = null
	tool.shutdown()
