extends "res://addons/gut/test.gd"

var root = ProjectSettings.globalize_path("res://").plus_file("..")
var Utils = load(root.plus_file("scripts/utils/BuildingPlannerUtils.gd"))
var path_fixture = load("res://unit/test_path_creation.gd")
var room_fixture = load("res://unit/test_rooms.gd")


class MarkerApi:
	extends Reference
	var ready = true
	var nearest = null
	var queries = []
	var fills = 0
	func is_ready():
		return ready
	func find_nearest_marker_by_geometry(coords, radius):
		queries.append([coords, radius])
		return nearest
	func compute_fill_polygon(_coords):
		fills += 1
		return {"polygon": [Vector2.ZERO, Vector2(50, 0), Vector2(0, 50)]}


func test_open_and_closed_path_markers_create_wall_and_path_with_repeatable_history():
	for feature_name in ["WallBuilder", "PathBuilder"]:
		for closed in [false, true]:
			var api = MarkerApi.new()
			# Public marker.Save format: points are [x, y], not Vector2 values.
			api.nearest = {"id": 0, "marker_type": "Path", "marker_points": [[70, 80], [120, 80], [120, 130]], "path_closed": closed}
			var walls = autofree(room_fixture.NativeContainer.new())
			var paths = autofree(path_fixture.Pathways.new())
			var history = path_fixture.HistoryApi.new()
			var level = {"Walls": walls, "Pathways": paths}
			var parent = {"Global": {"World": {"Level": level}, "API": {"HistoryApi": history}, "ModMapData": {}}}
			var feature = load(root.plus_file("scripts/features/" + feature_name + ".gd")).new(api, null, parent)
			feature.active_texture = GradientTexture.new()
			feature.active_color = Color.red
			var input = api.nearest.duplicate(true)
			assert_true(feature.build_at(Vector2(100, 80)))
			assert_eq_deep(api.queries, [[Vector2(100, 80), 100.0]])
			assert_eq(api.fills, 0, "A nearby Path wins over the available Shape region")
			assert_eq_deep(api.nearest, input)
			assert_eq(history.records.size(), 1)
			var container = walls if feature_name == "WallBuilder" else paths
			var saved = container.get_child(0).Save()
			if feature_name == "WallBuilder":
				assert_eq(saved.loop, closed)
				assert_eq_deep(saved.points, [Vector2(70, 80), Vector2(120, 80), Vector2(120, 130)])
			else:
				var points = Array(str2var(saved.edit_points))
				assert_eq(points.size(), 3)
				assert_eq(points[-1], Vector2(50, 50))
				assert_eq(saved.loop, closed)
				assert_eq(str2var(saved.position), Vector2(70, 80))
			for _cycle in range(2):
				history.records[0].undo()
				assert_eq(container.get_child_count(), 0)
				yield(get_tree(), "idle_frame")
				history.records[0].redo()
				assert_eq(container.get_child_count(), 1)
				assert_eq_deep(container.get_child(0).Save(), saved)
			history.records.clear()


func test_outline_falls_back_to_shape_without_a_nearby_path_and_on_older_apis():
	var api = MarkerApi.new()
	for hit in [null, {"id": 1, "marker_type": "Shape"}, {"id": 2, "marker_type": "Line"}]:
		api.nearest = hit
		var outline = Utils.resolve_outline(api, Vector2.ZERO)
		assert_true(outline.closed)
		assert_eq(outline.points.size(), 3)
	assert_eq(api.fills, 3)
	var legacy = path_fixture.MarkerApi.new() # No geometry query on this public API substitute.
	assert_true(Utils.resolve_outline(legacy, Vector2.ZERO).closed)

func test_coincident_path_endpoints_create_native_loop_without_duplicate_seam_and_restore_history():
	var api = MarkerApi.new()
	var paths = autofree(path_fixture.Pathways.new())
	var history = path_fixture.HistoryApi.new()
	var parent = {"Global": {"World": {"Level": {"Pathways": paths}}, "API": {"HistoryApi": history}, "ModMapData": {}}}
	var builder = load(root.plus_file("scripts/features/PathBuilder.gd")).new(api, null, parent)
	builder.active_texture = GradientTexture.new()
	for end in [[70, 80], [70.00001, 80]]:
		api.nearest = {"id": 4, "marker_type": "Path", "path_closed": false, "marker_points": [[70, 80], [170, 80], [170, 180], end]}
		var before = api.nearest.duplicate(true)
		assert_true(builder.build_at(Vector2(100, 80)))
		var saved = paths.get_child(0).Save()
		assert_true(saved.loop)
		assert_eq(Array(str2var(saved.edit_points)).size(), 3)
		assert_eq_deep(api.nearest, before)
		var record = history.records.back()
		record.undo()
		yield(get_tree(), "idle_frame")
		record.redo()
		assert_eq_deep(paths.get_child(0).Save(), saved)
		record.undo()
		history.records.clear()
		yield(get_tree(), "idle_frame")


func test_path_validation_keeps_open_collinear_crossing_and_closed_bridge_geometry():
	var api = MarkerApi.new()
	api.nearest = {"id": 7, "marker_type": "Path", "path_closed": false, "marker_points": [[0, 0], [50, 0]]}
	assert_eq(Utils.resolve_outline(api, Vector2.ZERO).points.size(), 2)
	api.nearest.path_closed = true
	assert_true(Utils.resolve_outline(api, Vector2.ZERO).closed, "Native walls also accept two-point loops")
	api.nearest.path_closed = false
	api.nearest.marker_points = [[0, 0], [50, 0], [100, 0]]
	assert_eq(Utils.resolve_outline(api, Vector2.ZERO).points.size(), 3, "Paths need no polygon area")
	api.nearest.marker_points = [[0, 0], [50, 50], [0, 50], [50, 0]]
	assert_eq(Utils.resolve_outline(api, Vector2.ZERO).points.size(), 4, "Crossing polylines are valid")
	api.nearest.path_closed = true
	api.nearest.marker_points = [[0, 0], [0, 0], [50, 0], [50, 50], [0, 0]]
	assert_eq_deep(Utils.resolve_outline(api, Vector2.ZERO).points, [Vector2.ZERO, Vector2(50, 0), Vector2(50, 50)])
	assert_eq(api.fills, 0)


func test_invalid_path_data_never_creates_nodes_history_or_falls_back_to_shape():
	var api = MarkerApi.new()
	var history = path_fixture.HistoryApi.new()
	var walls = autofree(room_fixture.NativeContainer.new())
	var paths = autofree(path_fixture.Pathways.new())
	var parent = {"Global": {"World": {"Level": {"Walls": walls, "Pathways": paths}}, "API": {"HistoryApi": history}, "ModMapData": {}}}
	for name in ["WallBuilder", "PathBuilder"]:
		var logger = room_fixture.DiagnosticLogger.new()
		var feature = load(root.plus_file("scripts/features/" + name + ".gd")).new(api, logger, parent)
		feature.active_texture = GradientTexture.new()
		for change in [{"id": -1}, {"id": "bad"}, {"path_closed": 1}, {"marker_points": null}, {"marker_points": []}, {"marker_points": [[0, 0]]}, {"marker_points": [[0, 0], [0, 0]]}, {"marker_points": [[0, 0], [INF, 20]]}, {"marker_points": [[0, 0], [NAN, 20]]}, {"marker_points": [[0, 0], ["bad", 20]]}, {"marker_points": [[0, 0], [20]]}]:
			api.nearest = {"id": 1, "marker_type": "Path", "marker_points": [[0, 0], [50, 50]], "path_closed": false}
			for key in change:
				api.nearest[key] = change[key]
			var errors_before = logger.errors.size()
			assert_false(feature.build_at(Vector2.ZERO))
			assert_eq(logger.errors.size(), errors_before + 1, "Malformed Path must report its contract failure")
		assert_false(feature.build_at(Vector2(INF, 0)))
		api.ready = false
		assert_false(feature.build_at(Vector2.ZERO))
		api.ready = true
	assert_eq(walls.get_child_count(), 0)
	assert_eq(paths.get_child_count(), 0)
	assert_eq(history.records.size(), 0)
	assert_eq(api.fills, 0)


func test_invalid_nearest_response_never_falls_back_to_a_different_shape():
	var api = MarkerApi.new()
	var logger = room_fixture.DiagnosticLogger.new()
	for response in [false, [], "bad"]:
		api.nearest = response
		assert_eq_deep(Utils.resolve_outline(api, Vector2.ZERO, logger), {})
	assert_eq(api.fills, 0)
	assert_eq(logger.errors.size(), 3)
	assert_eq_deep(Utils.resolve_outline(api, Vector2(INF, 0), logger), {})
	assert_eq(logger.errors.size(), 4)
	assert_eq(api.queries.size(), 3)
