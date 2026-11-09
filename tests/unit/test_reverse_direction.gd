extends "res://addons/gut/test.gd"

var root = ProjectSettings.globalize_path("res://").plus_file("..")
var Utils = load(root.plus_file("scripts/utils/BuildingPlannerUtils.gd"))
var rooms = load("res://unit/test_rooms.gd")
var paths = load("res://unit/test_path_creation.gd")
var markers = load("res://unit/test_path_markers.gd")
const POINTS = [Vector2(70, 80), Vector2(170, 80), Vector2(170, 180), Vector2(70, 180)]


func test_reverse_direction_copy_open_closed_and_explicit_seam():
	for points in [[], [POINTS[0]], POINTS, POINTS + [POINTS[0]]]:
		var original = points.duplicate()
		for closed in [false, true]:
			var expected = original.duplicate()
			if closed and points.size() > 1 and points[0] != points[-1]:
				expected = [points[0], points[3], points[2], points[1]]
			else:
				expected.invert()
			var reversed = Utils.reverse_outline(points, closed)
			assert_eq_deep(reversed, expected)
			assert_eq_deep(Utils.reverse_outline(reversed, closed), original)
			if not reversed.empty(): reversed[0] = Vector2.ZERO
			assert_eq_deep(points, original)


func test_reverse_direction_builders_after_offset_and_saved_style_history():
	for name in ["WallBuilder", "PathBuilder"]:
		for closed in [false, true]:
			for distance in ([0.0, -10.0, 10.0] if closed else [0.0]):
				var api = markers.MarkerApi.new()
				api.nearest = {"id": 0, "marker_type": "Path", "marker_points": [[70, 80], [170, 80], [170, 180], [70, 180]], "path_closed": closed}
				var original = api.nearest.duplicate(true)
				var walls = autofree(rooms.NativeContainer.new())
				var pathways = autofree(paths.Pathways.new())
				var history = paths.HistoryApi.new()
				var parent = {"Global": {"World": {"Level": {"Walls": walls, "Pathways": pathways}}, "API": {"HistoryApi": history}}}
				var builder = load(root.plus_file("scripts/features/" + name + ".gd")).new(api, null, parent)
				builder.active_texture = GradientTexture.new()
				assert_false(builder.active_reverse_direction)
				builder.active_offset = distance
				builder.active_reverse_direction = true
				var settings = builder.get_settings()
				assert_true(settings.active_reverse_direction)
				assert_true(builder.build_at(Vector2(100, 80)))
				assert_eq_deep(api.nearest, original)
				var container = walls if name == "WallBuilder" else pathways
				var saved = container.get_child(0).Save()
				var actual = saved.points if name == "WallBuilder" else Array(str2var(saved.edit_points))
				if name == "PathBuilder":
					if closed:
						assert_eq(actual[0], actual[-1])
						actual.pop_back()
					for i in range(actual.size()): actual[i] += str2var(saved.position)
				var offset = Utils.offset_outline(POINTS, closed, distance)
				var expected = [offset[0], offset[3], offset[2], offset[1]] if closed else [POINTS[3], POINTS[2], POINTS[1], POINTS[0]]
				assert_eq_deep(actual, expected)
				builder.active_reverse_direction = false
				history.records[0].undo()
				history.records[0].redo()
				assert_eq_deep(container.get_child(0).Save(), saved)
				# Explicit room/preset settings override the current UI; older styles default to false.
				var create = "_create_wall" if name == "WallBuilder" else "_create_path"
				assert_not_null(builder.call(create, POINTS, null, closed, settings))
				assert_eq_deep(container.get_child(1).Save(), saved)
				settings.erase("active_reverse_direction")
				builder.active_reverse_direction = true
				assert_not_null(builder.call(create, POINTS, null, closed, settings))
				var legacy = container.get_child(2).Save()
				if name == "WallBuilder":
					assert_eq_deep(legacy.points, offset)
				else:
					assert_eq(str2var(legacy.position), offset[0])
					assert_eq(Array(str2var(legacy.edit_points))[1], offset[1] - offset[0])
				history.records.clear()
	yield(get_tree(), "idle_frame")


func test_reverse_direction_panels_default_false_and_bind_independently():
	var UI = load(root.plus_file("scripts/tool/BuildingPlannerToolUI.gd"))
	for name in ["WallBuilder", "PathBuilder"]:
		var builder_script = load(root.plus_file("scripts/features/" + name + ".gd"))
		var first = builder_script.new(null, null)
		var second = builder_script.new(null, null)
		for feature in [first, second]:
			var panel = UI.WallPanel.new() if name == "WallBuilder" else UI.PathPanel.new()
			autofree(panel.build())
			assert_false(panel.reverse_check.pressed)
			panel.reverse_check.pressed = feature == first
			panel.bind_feature(feature)
		assert_true(first.active_reverse_direction)
		assert_false(second.active_reverse_direction)
