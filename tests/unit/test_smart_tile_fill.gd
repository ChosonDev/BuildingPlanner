extends "res://addons/gut/test.gd"

var root = ProjectSettings.globalize_path("res://").plus_file("..")
var Fill = load(root.plus_file("scripts/features/SmartTileFill.gd"))
var UI = load(root.plus_file("scripts/tool/BuildingPlannerToolUI.gd"))
var Tool = load(root.plus_file("scripts/tool/BuildingPlannerTool.gd"))
var Renderer = load(root.plus_file("scripts/overlay/BuildingPlannerTexturePreview.gd"))
var Room = load(root.plus_file("scripts/features/RoomBuilder.gd"))
var RoomChecks = load("res://unit/test_rooms.gd")
var Template = load(root.plus_file("scripts/features/RoomTemplate.gd"))
var Overlay = load(root.plus_file("scripts/overlay/BuildingPlannerOverlay.gd"))

class CountingTiles:
	extends TileSet
	var scans = 0
	func get_tiles_ids():
		scans += 1
		return .get_tiles_ids()

class Diagnostic:
	extends Reference
	func error(message): print(message)
	func warn(message): print(message)
	func debug(_message): pass
	func info(_message): pass

class Api:
	extends Reference
	var polygon = [Vector2(1, 1), Vector2(65, 1), Vector2(65, 65), Vector2(1, 65)]
	func is_ready(): return true
	func compute_fill_polygon(_coords): return {"polygon": polygon}

class Floor:
	extends Reference
	var saves = 0
	var SuppressHistory = false
	var tilemap
	var data = {"polygons": [], "walls": []}
	var calls = []
	func Save():
		saves += 1
		return data.duplicate(true)
	func Restore(saved): data = saved.duplicate(true)
	func AddPolygon(points, _bounds, _invert): data.polygons.append(var2str(points))
	func DrawPolygon(points, invert):
		assert(SuppressHistory)
		calls.append([points, invert])
		data.polygons.append(var2str(points))
		var bounds = Rect2(points[0], Vector2.ZERO)
		for point in points: bounds = bounds.expand(point)
		tilemap.paint_native(bounds, invert)

class Tiles:
	extends TileMap
	var CellSize = Vector2(64, 64)
	var colors = {}
	var updates = []
	func get_cell_color(x, y): return colors.get(Vector2(x, y), Color.white)
	func set_cell_color(x, y, color): colors[Vector2(x, y)] = color
	func paint_native(bounds, invert = false):
		updates.append(bounds)
		# Emulate the host's ceil coverage, including partial boundary cells.
		for y in range(int(floor(bounds.position.y / cell_size.y)), int(ceil(bounds.end.y / cell_size.y))):
			for x in range(int(floor(bounds.position.x / cell_size.x)), int(ceil(bounds.end.x / cell_size.x))):
				set_cell(x, y, -1 if invert else 7)
				set_cell_color(x, y, Color.red)

class Brush:
	extends Reference
	var SmartTileId = 3
	var WallTexture = null
	var Controls = {}

class Master:
	extends Reference
	var IsBusy = false

class Editor:
	extends Reference
	var owner = Master.new()
	var Tools = {"FloorShapeTool": Brush.new()}

class History:
	extends Reference
	signal recorded(action)
	signal undo_end(action)
	signal redo_end(action)
	var records = []
	func record(action, _count):
		records.append(action)
		emit_signal("recorded", action)

func context():
	var tilemap = autofree(Tiles.new())
	tilemap.cell_size = Vector2(64, 64)
	tilemap.tile_set = TileSet.new()
	tilemap.tile_set.create_tile(7)
	var texture = ImageTexture.new()
	var image = Image.new()
	image.create(128, 128, false, Image.FORMAT_RGBA8)
	image.fill(Color.green)
	texture.create_from_image(image)
	texture.resource_path = "res://smart_tile_test_%d.png" % texture.get_instance_id()
	tilemap.tile_set.tile_set_texture(7, texture)
	var floor_shapes = Floor.new()
	floor_shapes.tilemap = tilemap
	var history = History.new()
	var editor = Editor.new()
	var theme = Theme.new()
	theme.set_icon("NullMin", "Icons", ImageTexture.new())
	var wall_menu = autofree(ItemList.new())
	wall_menu.theme = theme
	editor.Tools.FloorShapeTool.Controls.WallTexture = wall_menu
	# Match ModScript.AddVariables: there is no Theme in a mod's injected Global.
	var gl = {"World": {"Width": 4, "Height": 4, "Level": {"FloorShapes": floor_shapes, "TileMap": tilemap}}, "Editor": editor, "API": {"HistoryApi": history}, "ModMapData": {}}
	var api = Api.new()
	var feature = Fill.new(api, null, {"Global": gl})
	feature._trace_path = "res://results/smart-tile-fill.log"
	feature._trace_enabled = true
	feature.active_texture = texture
	feature.active_color = Color.red
	return {"feature": feature, "api": api, "gl": gl, "floor": floor_shapes, "tiles": tilemap, "history": history, "brush": editor.Tools.FloorShapeTool}

func test_smart_tiles_partial_boundary_cells_colors_contours_and_map_guard():
	var f = context()
	f.tiles.set_cell(1, 1, 3)
	f.tiles.set_cell_color(1, 1, Color.blue)
	f.tiles.set_cell(3, 3, 3)
	assert_true(f.feature.build_at(Vector2(20, 20)))
	assert_eq(f.floor.calls.size(), 1)
	assert_eq(f.history.records.size(), 1)
	assert_eq(f.brush.SmartTileId, 3)
	assert_null(f.brush.WallTexture)
	assert_false(f.gl.has("Theme"), "Successful placement must not require an uninjected Global.Theme")
	assert_false(f.floor.SuppressHistory, "Restore native history policy after the call")
	assert_eq(f.tiles.get_cell(1, 1), 7)
	var trace = File.new()
	assert_eq(trace.open(f.feature._trace_path, File.READ), OK)
	assert_true(trace.get_as_text().ends_with("Fill completed\n"), "Checkpoint is written and closed before returning")
	trace.close()
	var record = f.history.records[0]
	record.undo()
	assert_true(f.floor.data.polygons.empty())
	assert_eq(f.tiles.get_cell(0, 0), -1)
	assert_eq(f.tiles.get_cell(1, 1), 3, "Undo includes the partially intersected last row and column")
	assert_eq(f.tiles.get_cell_color(1, 1), Color.blue)
	assert_eq(f.tiles.get_cell(3, 3), 3)
	record.redo()
	assert_eq(f.floor.data.polygons.size(), 1)
	assert_eq(f.tiles.get_cell_color(1, 1), Color.red)
	f.gl.World = {"Level": {}}
	record.undo()
	assert_eq(f.floor.data.polygons.size(), 1, "Do not restore another map")
	record.dropped(0)

func test_smart_tiles_rejects_automatic_walls_busy_host_missing_asset_and_outside_map():
	var f = context()
	f.floor.data.walls = [42]
	assert_false(f.feature.build_at(Vector2.ZERO))
	f.floor.data.walls = []
	f.gl.Editor.owner.IsBusy = true
	assert_false(f.feature.build_at(Vector2.ZERO))
	f.gl.Editor.owner.IsBusy = false
	f.feature.active_texture = ImageTexture.new()
	assert_false(f.feature.build_at(Vector2.ZERO))
	f.feature.active_texture = f.tiles.tile_set.tile_get_texture(7)
	f.api.polygon[0] = Vector2(-1, 0)
	assert_false(f.feature.build_at(Vector2.ZERO))
	assert_true(f.floor.calls.empty())
	assert_true(f.tiles.updates.empty())
	assert_true(f.history.records.empty())

func test_smart_tiles_panel_selects_loaded_tiles_and_switches_floor_fill_backend():
	var f = context()
	var tool = Tool.new({"Global": f.gl})
	tool._smart_tile_fill = f.feature
	var ui = UI.new(tool, null)
	ui.build(autofree(VBoxContainer.new()))
	ui._pf_tile_panel.try_build_grid_menu(f.gl)
	assert_eq(f.feature.active_texture, f.tiles.tile_set.tile_get_texture(7))
	ui._on_floor_fill_selected(1)
	assert_true(tool.smart_tiles_enabled)
	assert_true(ui._pf_tile_container.visible)
	assert_false(ui._pf_pattern_container.visible)
	ui._on_floor_fill_selected(0)
	assert_false(tool.smart_tiles_enabled)
	assert_true(ui._pf_pattern_container.visible)
	ui.shutdown()

func test_smart_tiles_rejects_missing_host_theme_before_any_map_or_brush_mutation():
	var f = context()
	f.brush.Controls.clear()
	assert_false(f.feature.build_at(Vector2(20, 20)))
	assert_true(f.floor.calls.empty())
	assert_true(f.tiles.updates.empty())
	assert_true(f.history.records.empty())
	assert_eq(f.brush.SmartTileId, 3)
	assert_null(f.brush.WallTexture)
	f.brush.Controls.WallTexture = autofree(ItemList.new())
	assert_false(f.feature.build_at(Vector2(20, 20)), "A control without the host icon must also fail safely")

func test_smart_tiles_preview_autotiles_clips_and_never_changes_native_floor():
	var f = context()
	f.feature.active_color = Color.white
	var tiles = f.tiles.tile_set
	tiles.tile_set_tile_mode(7, TileSet.AUTO_TILE)
	tiles.tile_set_region(7, Rect2(0, 0, 128, 128))
	tiles.autotile_set_size(7, Vector2(64, 64))
	tiles.autotile_set_bitmask_mode(7, TileSet.BITMASK_3X3)
	tiles.autotile_set_bitmask(7, Vector2(1, 0), TileSet.BIND_CENTER)
	var renderer = autofree(Renderer.new())
	var view = autofree(Viewport.new())
	view.size = Vector2(80, 80)
	view.disable_3d = true
	view.world_2d = World2D.new()
	view.transparent_bg = true
	view.render_target_update_mode = Viewport.UPDATE_ALWAYS
	view.add_child(renderer)
	add_child(view)
	var points = [Vector2(1, 1), Vector2(63, 1), Vector2(63, 63), Vector2(1, 63)]
	renderer.sync_preview({"points": points, "fill": true}, f.feature.get_settings(), false)
	assert_true(renderer.visible)
	assert_eq(renderer._tile_cells.size(), 1)
	assert_eq(renderer._autotile_map.get_cell_autotile_coord(0, 0), Vector2(1, 0), "Native TileMap chooses the isolated autotile")
	var polygon = renderer._tile_cells[0]
	for i in range(polygon.polygon.size()):
		assert_true(polygon.polygon[i].x >= 1 and polygon.polygon[i].x <= 63)
		assert_eq(polygon.uv[i], polygon.polygon[i] + Vector2(64, 0), "UV selects the native autotile, not the entire atlas")
	assert_eq(f.tiles.get_used_cells().size(), 0)
	assert_true(f.floor.calls.empty())
	assert_true(f.history.records.empty())
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

	var rendered = view.get_texture().get_data()
	rendered.flip_y()
	rendered.lock()
	assert_true(rendered.get_pixel(32, 32).g > 0.5, "Selected tile is visibly rendered")
	assert_eq(rendered.get_pixel(70, 70).a, 0.0, "Preview stays inside the marker contour")
	rendered.unlock()
	renderer.clear_preview()
	assert_false(renderer.visible)
	assert_true(renderer._tile_cells.empty())
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

func room_context():
	var f = context()
	var level = f.gl.World.Level
	level.PatternShapes = autofree(RoomChecks.NativeContainer.new())
	level.Walls = autofree(RoomChecks.NativeContainer.new())
	level.Pathways = autofree(RoomChecks.NativeContainer.new())
	f.gl.World.WorldRect = Rect2(0, 0, 256, 256)
	var gl_root = root.plus_file("../GuidesLines").simplify_path()
	var mod = {"markers_opacity": 0.7, "guides_lines_api": null, "Global": {"API": {}, "Editor": {"IsSnapping": false}}}
	var guides = load(gl_root.plus_file("scripts/tool/GuidesLinesTool.gd")).new(mod)
	guides.GuideMarkerClass = load(gl_root.plus_file("scripts/guides/GuideMarker.gd"))
	guides.cached_world = f.gl.World
	mod.guides_tool = guides
	var api = load(gl_root.plus_file("scripts/api/guides_lines_api.gd")).new(mod, null)
	mod.guides_lines_api = api
	var room = Room.new(api, Diagnostic.new(), f.feature._parent_mod)
	room._smart_tile_fill._trace_path = "res://results/smart-tile-room.log"
	room._smart_tile_fill.active_texture = f.feature.active_texture
	room._smart_tile_fill.active_color = Color.red
	room._wall_builder.active_texture = GradientTexture.new()
	room.active_fill_mode = 1
	room.active_sub_mode = 1
	f.room = room
	f.guides = guides
	f.guides_mod = mod
	f.guides_api = api
	return f

func release_room(f):
	for record in f.history.records: record.dropped(0)
	f.history.records.clear()
	f.guides_api._unload()
	f.guides_mod.guides_lines_api = null
	f.guides_mod.guides_tool = null
	f.guides.ui.tool = null
	f.guides.placement.tool = null
	f.guides._fill_handler.tool = null
	f.guides.parent_mod = null

func room_state():
	return {"ready": true, "active_shape_radius": 0.75, "active_shape_angle": 45.0, "active_shape_sides": 4, "active_color": Color.white}

func tile_snapshot(tiles):
	var result = []
	for y in range(4):
		for x in range(4): result.append([tiles.get_cell(x, y), tiles.get_cell_color(x, y)])
	return result

func test_smart_tile_rooms_all_boolean_modes_replay_markers_floor_color_and_outline_as_one_action():
	for mode in range(5):
		var f = room_context()
		assert_true(f.room.build_room_at(Vector2(80, 80), room_state()))
		var before_tiles = tile_snapshot(f.tiles)
		var before_floor = f.floor.Save()
		var before_markers = f.guides_api.get_markers()
		f.room.active_sub_mode = mode
		f.room._smart_tile_fill.active_color = Color.blue
		assert_true(f.room.build_room_at(Vector2(110, 80), room_state()), "Mode %d must support tiles" % mode)
		assert_eq(f.history.records.size(), 2, "One compound action per room click")
		var after_tiles = tile_snapshot(f.tiles)
		var after_floor = f.floor.Save()
		var action = f.history.records.back()
		action.undo()
		assert_eq_deep(tile_snapshot(f.tiles), before_tiles)
		assert_eq_deep(f.floor.Save(), before_floor)
		assert_eq_deep(f.guides_api.get_markers(), before_markers)
		action.redo()
		assert_eq_deep(tile_snapshot(f.tiles), after_tiles)
		assert_eq_deep(f.floor.Save(), after_floor)
		assert_eq(f.gl.World.Level.PatternShapes.get_child_count(), 0, "Tile rooms create no PatternShape")
		release_room(f)
		yield(get_tree(), "idle_frame")

func test_smart_tile_room_removal_restores_underlying_native_floor_and_failed_outline_rolls_back():
	var f = room_context()
	f.floor.data.polygons = [var2str(PoolVector2Array([Vector2(64, 64), Vector2(128, 64), Vector2(128, 128), Vector2(64, 128)]))]
	f.tiles.set_cell(1, 1, 7)
	f.tiles.set_cell_color(1, 1, Color.green)
	var before = tile_snapshot(f.tiles)
	var floor_before = f.floor.Save()
	assert_true(f.room.build_room_at(Vector2(80, 80), room_state()))
	f.room.active_sub_mode = 4
	assert_true(f.room.build_room_at(Vector2(80, 80), room_state()))
	assert_eq_deep(tile_snapshot(f.tiles), before)
	assert_eq_deep(f.floor.Save(), floor_before)
	f.room.active_sub_mode = 1
	f.gl.World.Level.Walls.fail = true
	assert_false(f.room.build_room_at(Vector2(80, 80), room_state()))
	assert_eq_deep(tile_snapshot(f.tiles), before)
	assert_eq(f.history.records.size(), 2)
	release_room(f)
	yield(get_tree(), "idle_frame")

func test_smart_tiles_erase_preserves_undo_and_custom_tint_does_not_change_shared_tileset():
	var f = context()
	f.tiles.set_cell(0, 0, 7)
	f.tiles.set_cell_color(0, 0, Color.blue)
	f.feature.active_erase = true
	assert_true(f.feature.build_at(Vector2(20, 20)))
	assert_true(f.floor.calls[0][1], "Native subtract flag is passed through")
	assert_eq(f.tiles.get_cell(0, 0), -1)
	f.history.records[0].undo()
	assert_eq(f.tiles.get_cell(0, 0), 7)
	assert_eq(f.tiles.get_cell_color(0, 0), Color.blue)
	f.feature.active_erase = false
	f.feature.active_color = Color.orange
	assert_true(f.feature.build_at(Vector2(20, 20)))
	assert_eq(f.tiles.get_cell_color(0, 0), Color.orange)
	assert_eq(f.tiles.tile_set.tile_get_modulate(7), Color.white)
	f.feature.active_color = Color(NAN, 0, 0)
	assert_false(f.feature.build_at(Vector2(20, 20)))
	f.history.records.clear()

func test_smart_tiles_sampling_and_room_template_json_preserve_independent_material_and_color():
	var f = room_context()
	var tool = Tool.new(f.feature._parent_mod)
	tool.cached_world = f.gl.World
	tool._gl_api = f.guides_api
	tool._smart_tile_fill = f.feature
	tool._room_builder = f.room
	var ui = UI.new(tool, null)
	ui.build(autofree(VBoxContainer.new()))
	ui._rb_tile_panel.try_build_grid_menu(f.gl)
	ui._on_rb_fill_selected(1)
	ui._rb_tile_panel._on_texture_selected(1)
	ui._rb_tile_panel.color_picker.emit_signal("color_changed", Color.orange)
	assert_eq(f.room._smart_tile_fill.active_color, Color.orange)
	assert_eq(f.feature.active_color, Color.red, "Room material controls are independent")
	f.tiles.set_cell(0, 0, 7)
	f.tiles.set_cell_color(0, 0, Color.blue)
	assert_true(ui.sample_at(ui._pf_tile_panel, f.gl.World.Level, Vector2(20, 20)))
	assert_eq(f.feature.active_color, Color.blue)
	assert_eq(f.room._smart_tile_fill.active_color, Color.orange)
	assert_true(tool.add_room_template())
	var json = JSON.parse(JSON.print({Tool.ROOM_DATA_KEY: {"version": 1, "room_templates": [tool.room_templates[0].save()]}})).result
	assert_true(tool.load_room_templates(json))
	var template = tool.room_templates[0]
	assert_eq(template.fill_mode, 1)
	assert_eq(template.tile_style.color, Color(Color.orange.to_html()))
	assert_true(ui.apply_room_template(template))
	assert_eq(f.room.active_fill_mode, 1)
	assert_eq(f.room._smart_tile_fill.active_texture, f.tiles.tile_set.tile_get_texture(7))
	assert_eq(f.room._smart_tile_fill.active_color, Color(Color.orange.to_html()))
	var legacy = template.save()
	legacy.erase("fill_mode")
	legacy.erase("tile_style")
	var old = Template.new()
	assert_true(old.load_data(legacy, tool._room_style_defaults()))
	assert_eq(old.fill_mode, 0, "Old templates retain Pattern behavior")
	template.tile_style.texture = "res://missing_tile.png"
	assert_false(ui.apply_room_template(template))
	assert_eq(f.room._smart_tile_fill.active_texture, f.tiles.tile_set.tile_get_texture(7), "Missing assets never partially apply a template")
	ui.shutdown()
	release_room(f)

func test_smart_tile_room_external_floor_edits_are_preserved_and_two_levels_replay_without_switching():
	var f = room_context()
	assert_true(f.room.build_room_at(Vector2(80, 80), room_state()))
	var lower = f.gl.World.Level
	var upper_fixture = context()
	var upper = upper_fixture.gl.World.Level
	upper.TileMap.tile_set = f.tiles.tile_set
	upper.PatternShapes = autofree(RoomChecks.NativeContainer.new())
	upper.Walls = autofree(RoomChecks.NativeContainer.new())
	upper.Pathways = autofree(RoomChecks.NativeContainer.new())
	f.gl.World.Level = upper
	f.room._smart_tile_fill.active_color = Color.blue
	assert_true(f.room.build_room_at(Vector2(110, 80), room_state()))
	assert_eq(f.history.records.size(), 2)
	assert_eq(upper.TileMap.get_cell_color(1, 1), Color.blue)
	assert_eq(lower.TileMap.get_cell_color(1, 1), Color.blue)
	var action = f.history.records.back()
	action.undo()
	assert_eq(lower.TileMap.get_cell_color(1, 1), Color.red)
	assert_eq(upper.TileMap.get_cell(1, 1), -1)
	assert_true(f.gl.World.Level == upper, "Undo must not switch the active level")
	action.redo()
	assert_eq(upper.TileMap.get_cell_color(1, 1), Color.blue)
	lower.TileMap.set_cell_color(1, 1, Color.green)
	var markers = f.guides_api.get_markers()
	assert_false(f.room.build_room_at(Vector2(110, 80), room_state()))
	assert_eq(lower.TileMap.get_cell_color(1, 1), Color.green, "External edits must never be lost")
	assert_eq_deep(f.guides_api.get_markers(), markers)
	release_room(f)
	yield(get_tree(), "idle_frame")

func test_smart_tile_group_template_with_path_outlines_is_one_undoable_room_action():
	var f = room_context()
	var first = f.guides_api.place_shape_marker_plain(Vector2(80, 80), 0.3, 45, 4)
	var second = f.guides_api.place_shape_marker_plain(Vector2(160, 80), 0.3, 45, 4)
	f.guides.start_group_capture()
	f.guides.template_group_ids = {first: true, second: true}
	assert_true(f.guides.save_group_template())
	f.guides.set_marker_type("Template")
	f.room.active_sub_mode = 0
	f.room.active_outline_mode = 1
	f.room._path_builder.active_texture = GradientTexture.new()
	var before = f.guides_api.get_markers()
	assert_true(f.room.build_room_at(Vector2(128, 128), f.guides_api.get_placement_state()))
	assert_eq(f.history.records.size(), 1)
	assert_eq(f.gl.World.Level.Pathways.get_child_count(), 2)
	assert_eq(f.room._floor_state.levels[f.gl.World.Level].rooms.size(), 2)
	assert_eq_deep(f.guides_api.get_markers(), before)
	f.history.records[0].undo()
	assert_true(f.tiles.get_used_cells().empty())
	assert_eq(f.gl.World.Level.Pathways.get_child_count(), 0)
	f.history.records[0].redo()
	assert_eq(f.gl.World.Level.Pathways.get_child_count(), 2)
	assert_false(f.tiles.get_used_cells().empty())
	release_room(f)
	yield(get_tree(), "idle_frame")

func test_smart_tiles_native_thumbnails_keep_full_material_selection_and_hole_cells_stay_empty():
	var f = context()
	var catalog = autofree(ItemList.new())
	var thumbnail = GradientTexture.new()
	for _i in range(8): catalog.add_icon_item(thumbnail)
	f.brush.Controls.SmartTileId = catalog
	var panel = UI.SmartTilePanel.new()
	panel.bind_feature(f.feature)
	autofree(panel.build())
	panel.try_build_grid_menu(f.gl)
	assert_eq(panel._sg._all_items[0].icon, thumbnail)
	assert_eq(f.feature.active_texture, f.tiles.tile_set.tile_get_texture(7))
	var ring = [Vector2.ZERO, Vector2(64, 64), Vector2(64, 128), Vector2(128, 128), Vector2(128, 64), Vector2(64, 64), Vector2.ZERO, Vector2(192, 0), Vector2(192, 192), Vector2(0, 192)]
	assert_false(Room.RoomFloorState.overlaps_cell(ring, Vector2(1, 1), f.tiles))
	assert_true(Room.RoomFloorState.overlaps_cell(ring, Vector2(0, 1), f.tiles))

func test_smart_tile_room_merge_can_switch_between_pattern_and_tiles_without_leaving_stale_floor():
	var f = room_context()
	assert_true(f.room.build_room_at(Vector2(80, 80), room_state()))
	f.room.active_fill_mode = 0
	f.room._pattern_fill.active_texture = GradientTexture.new()
	assert_true(f.room.build_room_at(Vector2(110, 80), room_state()))
	assert_true(f.tiles.get_used_cells().empty())
	assert_eq(f.gl.World.Level.PatternShapes.get_child_count(), 1)
	f.history.records.back().undo()
	assert_false(f.tiles.get_used_cells().empty())
	assert_eq(f.gl.World.Level.PatternShapes.get_child_count(), 0)
	f.history.records.back().redo()
	f.room.active_fill_mode = 1
	assert_true(f.room.build_room_at(Vector2(140, 80), room_state()))
	assert_eq(f.gl.World.Level.PatternShapes.get_child_count(), 0)
	assert_false(f.tiles.get_used_cells().empty())
	release_room(f)
	yield(get_tree(), "idle_frame")

func test_smart_tile_rooms_preserve_disjoint_external_floor_contours_and_gap_cells_through_history():
	var f = room_context()
	f.gl.World.Width = 8
	f.gl.World.Height = 8
	f.gl.World.WorldRect = Rect2(0, 0, 512, 512)
	assert_true(f.room.build_room_at(Vector2(80, 80), room_state()))
	f.room.active_sub_mode = 0
	assert_true(f.room.build_room_at(Vector2(400, 80), room_state()))
	var external = var2str(PoolVector2Array([Vector2(180, 64), Vector2(240, 64), Vector2(240, 128), Vector2(180, 128)]))
	f.floor.data.polygons.append(external)
	f.tiles.set_cell(3, 1, 7)
	f.tiles.set_cell_color(3, 1, Color.green)
	assert_true(f.room.build_room_at(Vector2(80, 200), room_state()), "An independent native floor edit must not block room placement")
	assert_true(external in f.floor.Save().polygons)
	assert_eq(f.tiles.get_cell(3, 1), 7)
	assert_eq(f.tiles.get_cell_color(3, 1), Color.green)
	var action = f.history.records.back()
	action.undo()
	assert_true(external in f.floor.Save().polygons)
	assert_eq(f.tiles.get_cell_color(3, 1), Color.green)
	action.redo()
	assert_true(external in f.floor.Save().polygons)
	assert_eq(f.tiles.get_cell_color(3, 1), Color.green)
	release_room(f)
	yield(get_tree(), "idle_frame")

func test_smart_tile_preview_idle_frames_skip_catalog_scans_and_reuse_cell_nodes():
	var f = room_context()
	var tiles = CountingTiles.new()
	tiles.create_tile(7)
	tiles.tile_set_texture(7, f.feature.active_texture)
	f.tiles.tile_set = tiles
	var overlay = autofree(Overlay.new())
	var probe = GDScript.new()
	probe.source_code = 'extends "' + root.plus_file("scripts/overlay/BuildingPlannerTexturePreview.gd") + '"\nvar builds = 0\nfunc _draw_smart_tiles(points, settings):\n\tbuilds += 1\n\t._draw_smart_tiles(points, settings)\n'
	assert_eq(probe.reload(), OK)
	var counter = probe.new()
	var outline = Renderer.new()
	overlay.add_child(counter)
	overlay.add_child(outline)
	overlay._room_previews = [counter, outline]
	var state = room_state()
	overlay.refresh_room_preview(f.room, Vector2(80, 80), state)
	var cell = overlay._room_previews[0]._tile_cells[0]
	var first_id = cell.get_instance_id()
	for _frame in range(120): overlay.refresh_room_preview(f.room, Vector2(80, 80), state.duplicate())
	assert_eq(tiles.scans, 1, "Idle preview must resolve the tile catalog only once")
	assert_eq(counter.builds, 1, "Idle frames do not clip cells or rebuild the preview")
	assert_eq(overlay._room_previews[0]._tile_cells[0].get_instance_id(), first_id)
	f.room._smart_tile_fill.active_color = Color.blue
	overlay.refresh_room_preview(f.room, Vector2(80, 80), state)
	assert_eq(overlay._room_previews[0]._tile_cells[0].get_instance_id(), first_id, "Tint changes reuse existing clipped cell nodes")
	assert_eq(overlay._room_previews[0]._tile_cells[0].color, Color.blue)
	assert_eq(counter.builds, 1, "Tint-only changes do not rerun clipping or autotiling")
	f.history.emit_signal("undo_end", null)
	overlay.refresh_room_preview(f.room, Vector2(80, 80), state)
	assert_eq(counter.builds, 2, "Native history invalidates neighboring autotile connections")
	var renderer = overlay._room_previews[0]
	renderer.clear_preview()
	overlay.clear_preview()
	overlay.refresh_room_preview(f.room, Vector2(80, 80), state)
	assert_eq(renderer._tile_cells[0].get_instance_id(), first_id, "Returning to the canvas reuses the retained cells")
	release_room(f)
	yield(get_tree(), "idle_frame")

func test_smart_tile_catalog_cache_invalidates_on_tileset_changes_and_disconnects_old_resources():
	var f = context()
	var tiles = CountingTiles.new()
	tiles.create_tile(7)
	tiles.tile_set_texture(7, f.feature.active_texture)
	f.tiles.tile_set = tiles
	for _frame in range(120): assert_eq(f.feature.get_settings().smart_tile_id, 7)
	assert_eq(tiles.scans, 1)
	var replacement = GradientTexture.new()
	tiles.create_tile(9)
	tiles.tile_set_texture(9, replacement)
	f.feature.active_texture = replacement
	assert_eq(f.feature.get_settings().smart_tile_id, 9)
	assert_eq(tiles.scans, 2)
	var other = CountingTiles.new()
	other.create_tile(2)
	other.tile_set_texture(2, replacement)
	f.tiles.tile_set = other
	assert_eq(f.feature.get_settings().smart_tile_id, 2)
	tiles.emit_signal("changed")
	f.feature.get_settings()
	assert_eq(other.scans, 1, "Old tilesets cannot invalidate the current cache")

func test_smart_tiles_disabled_diagnostics_do_not_create_a_trace_file():
	var f = context()
	f.feature._trace_enabled = false
	f.feature._trace_path = "res://results/disabled-trace-%d.log" % f.feature.get_instance_id()
	assert_true(f.feature.build_at(Vector2(20, 20)))
	assert_false(File.new().file_exists(f.feature._trace_path))
	for record in f.history.records: record.dropped(0)
	f.history.records.clear()

func test_smart_tile_room_history_does_not_capture_the_empty_gap_between_distant_rooms():
	var f = room_context()
	f.gl.World.Width = 64
	f.gl.World.Height = 64
	f.gl.World.WorldRect = Rect2(0, 0, 4096, 4096)
	assert_true(f.room.build_room_at(Vector2(80, 80), room_state()))
	f.room.active_sub_mode = 0
	assert_true(f.room.build_room_at(Vector2(4000, 4000), room_state()))
	var action = f.history.records.back()
	assert_true(action._floor_records[0]._before.cells.size() <= 16, "History stores owned cells, not the 63x63 gap")
	assert_true(f.floor.saves <= 8, "A placement must not serialize the floor again for every existing room")
	assert_true(f.room._floor_state._contexts.empty(), "Transaction snapshots must not be retained while idle")
	print("Audit: distant room snapshot cells=%d, native floor Save calls for two placements=%d" % [action._floor_records[0]._before.cells.size(), f.floor.saves])
	release_room(f)
	yield(get_tree(), "idle_frame")

func test_smart_tile_room_template_idle_reuses_geometry_but_transform_changes_refresh_it():
	var f = room_context()
	var first = f.guides_api.place_shape_marker_plain(Vector2(80, 80), 0.3, 45, 4)
	var second = f.guides_api.place_shape_marker_plain(Vector2(160, 80), 0.3, 45, 4)
	f.guides.start_group_capture()
	f.guides.template_group_ids = {first: true, second: true}
	assert_true(f.guides.save_group_template())
	f.guides.set_marker_type("Template")
	var probe = GDScript.new()
	probe.source_code = 'extends "' + root.plus_file("scripts/features/RoomBuilder.gd") + '"\nvar batches = 0\nfunc _init(api, logger, parent).(api, logger, parent):\n\tpass\nfunc _template_batch(coords):\n\tbatches += 1\n\treturn ._template_batch(coords)\n'
	assert_eq(probe.reload(), OK)
	var room = probe.new(f.guides_api, null, f.feature._parent_mod)
	room._smart_tile_fill.active_texture = f.feature.active_texture
	room._wall_builder.active_texture = GradientTexture.new()
	var overlay = autofree(Overlay.new())
	var state = f.guides_api.get_placement_state()
	overlay.refresh_room_preview(room, Vector2(128, 128), state)
	for _frame in range(120): overlay.refresh_room_preview(room, Vector2(128, 128), state.duplicate())
	assert_eq(room.batches, 1, "Idle template previews do not transform, duplicate or sanitize the group each frame")
	assert_true(f.guides_api.set_template_transform(45, 1.0))
	overlay.refresh_room_preview(room, Vector2(128, 128), f.guides_api.get_placement_state())
	assert_eq(room.batches, 2)
	overlay.refresh_room_preview(room, Vector2(129, 128), f.guides_api.get_placement_state())
	assert_eq(room.batches, 3)
	release_room(f)
	yield(get_tree(), "idle_frame")
