extends "res://addons/gut/test.gd"

var root = ProjectSettings.globalize_path("res://").plus_file("..")
var Wall = load(root.plus_file("scripts/features/WallBuilder.gd"))
var Path = load(root.plus_file("scripts/features/PathBuilder.gd"))
var Utils = load(root.plus_file("scripts/utils/BuildingPlannerUtils.gd"))
var rooms = load("res://unit/test_rooms.gd")
var paths = load("res://unit/test_path_creation.gd")
const SQUARE = [Vector2(100, 200), Vector2(200, 200), Vector2(200, 300), Vector2(100, 300)]


func test_wall_offset_bounds_winding_and_input_ownership():
	var wall = Wall.new(null, null)
	assert_eq(wall.active_offset, 0.0)
	for reverse in [false, true]:
		var points = SQUARE.duplicate()
		if reverse: points.invert()
		for distance in [0, 10, -10]:
			var result = Utils.offset_outline(points, true, distance)
			assert_eq(result.size(), 4)
			assert_eq(Utils.signed_area(result) < 0, reverse)
			for point in result:
				assert_true(point.x == 100 - distance or point.x == 200 + distance)
				assert_true(point.y == 200 - distance or point.y == 300 + distance)
		assert_eq_deep(points, [SQUARE[3], SQUARE[2], SQUARE[1], SQUARE[0]] if reverse else SQUARE)
	var copy = Utils.offset_outline(SQUARE, true, 0)
	copy[0] = Vector2.ZERO
	assert_eq(SQUARE[0], Vector2(100, 200))
	var concave = [Vector2.ZERO, Vector2(100, 0), Vector2(100, 40), Vector2(40, 40), Vector2(40, 100), Vector2(0, 100)]
	var expanded = Utils.offset_outline(concave, true, 10)
	assert_eq(expanded.size(), 6)
	assert_almost_eq(abs(Utils.signed_area(expanded)), 10800.0, 0.01)


func test_wall_offset_rejects_collapse_split_open_and_invalid_values_before_native_calls():
	var logger = rooms.DiagnosticLogger.new()
	var container = autofree(rooms.NativeContainer.new())
	var parent = {"Global": {"World": {"Level": {"Walls": container}}}}
	var wall = Wall.new(null, logger, parent)
	wall.active_texture = GradientTexture.new()
	for distance in [NAN, INF, -INF, 8193, -8193, -50, -100]:
		wall.active_offset = distance
		assert_null(wall._create_wall(SQUARE))
	wall.active_offset = 10
	assert_null(wall._create_wall([Vector2.ZERO, Vector2(100, 0)], null, false))
	assert_null(wall._create_wall([Vector2.ZERO, Vector2(100, 0)], null, true))
	var split = [Vector2(0, 0), Vector2(100, 0), Vector2(100, 40), Vector2(200, 40), Vector2(200, 0), Vector2(300, 0), Vector2(300, 100), Vector2(200, 100), Vector2(200, 60), Vector2(100, 60), Vector2(100, 100), Vector2(0, 100)]
	assert_eq(Geometry.offset_polygon_2d(PoolVector2Array(split), -15).size(), 2)
	wall.active_offset = -15
	assert_null(wall._create_wall(split))
	assert_eq(container.wall_calls, 0)
	assert_eq(logger.errors.size(), 10)


func test_wall_offset_standalone_history_restores_actual_geometry_after_setting_changes():
	var api = rooms.MarkerApi.new()
	api.fill_polygon = SQUARE.duplicate()
	var container = autofree(rooms.NativeContainer.new())
	var history = paths.HistoryApi.new()
	var parent = {"Global": {"World": {"Level": {"Walls": container}}, "API": {"HistoryApi": history}}}
	var wall = Wall.new(api, null, parent)
	wall.active_texture = GradientTexture.new()
	wall.active_offset = -10
	assert_true(wall.build_at(Vector2(150, 250)))
	assert_eq(history.records.size(), 1)
	var saved = container.get_child(0).Save()
	assert_almost_eq(abs(Utils.signed_area(saved.points)), 6400.0, 0.01)
	assert_eq_deep(api.fill_polygon, SQUARE)
	wall.active_offset = 25
	history.records[0].undo()
	assert_eq(container.get_child_count(), 0)
	history.records[0].redo()
	assert_eq_deep(container.get_child(0).Save(), saved)
	history.records[0].dropped(0)
	history.records.clear()
	yield(get_tree(), "idle_frame")


func test_wall_offset_panel_defaults_and_late_independent_binding():
	var UI = load(root.plus_file("scripts/tool/BuildingPlannerToolUI.gd"))
	var first = Wall.new(null, null)
	var second = Wall.new(null, null)
	for feature in [first, second]:
		var panel = UI.WallPanel.new()
		autofree(panel.build())
		assert_eq(panel.offset_spin.value, 0.0)
		panel.offset_spin.value = -12 if feature == first else 24
		panel.offset_spin.emit_signal("value_changed", panel.offset_spin.value)
		panel.bind_feature(feature)
	assert_eq(first.active_offset, -12.0)
	assert_eq(second.active_offset, 24.0)


func test_path_offset_preserves_width_and_replays_actual_world_geometry():
	for distance in [-10.0, 10.0]:
		var api = rooms.MarkerApi.new()
		api.fill_polygon = SQUARE.duplicate()
		var container = autofree(paths.Pathways.new())
		var history = paths.HistoryApi.new()
		var parent = {"Global": {"World": {"Level": {"Pathways": container}}, "API": {"HistoryApi": history}}}
		var path = Path.new(api, null, parent)
		path.active_texture = GradientTexture.new()
		path.active_width = 2.5
		path.active_offset = distance
		assert_true(path.build_at(Vector2(150, 250)))
		var saved = container.get_child(0).Save(false)
		var points = Array(str2var(saved.edit_points))
		assert_eq(points[0], points[-1], "Native path has an explicit closing seam")
		points.pop_back()
		var origin = str2var(saved.position)
		for i in range(points.size()): points[i] += origin
		assert_eq_deep(points, Utils.offset_outline(SQUARE, true, distance))
		assert_eq(saved.width, path.active_texture.get_height() * 2.5)
		assert_eq_deep(api.fill_polygon, SQUARE)
		assert_eq(history.records.size(), 1)
		path.active_offset = 25.0
		history.records[0].undo()
		assert_eq(container.get_child_count(), 0)
		history.records[0].redo()
		assert_eq_deep(container.get_child(0).Save(false), saved)
		history.records[0].dropped(0)
		history.records.clear()
	yield(get_tree(), "idle_frame")


func test_path_offset_rejection_precedes_native_creation_and_panel_binding_is_independent():
	var UI = load(root.plus_file("scripts/tool/BuildingPlannerToolUI.gd"))
	var container = autofree(paths.Pathways.new())
	var history = paths.HistoryApi.new()
	var parent = {"Global": {"World": {"Level": {"Pathways": container}}, "API": {"HistoryApi": history}}}
	var path = Path.new(rooms.MarkerApi.new(), null, parent)
	path.active_texture = GradientTexture.new()
	for distance in [-100.0, NAN, INF, 8193.0]:
		path.active_offset = distance
		assert_false(path.build_at(Vector2.ZERO))
	path.active_offset = 10.0
	assert_null(path._create_path([Vector2.ZERO, Vector2(100, 0)], null, false))
	assert_eq(container.load_calls, 0)
	assert_eq(history.records.size(), 0)
	var first = Path.new(null, null)
	var second = Path.new(null, null)
	for feature in [first, second]:
		var panel = UI.PathPanel.new()
		autofree(panel.build())
		assert_eq(panel.offset_spin.value, 0.0)
		panel.offset_spin.emit_signal("value_changed", -12.0 if feature == first else 24.0)
		panel.bind_feature(feature)
	assert_eq(first.active_offset, -12.0)
	assert_eq(second.active_offset, 24.0)
