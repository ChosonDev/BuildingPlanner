extends "res://addons/gut/test.gd"

var root = ProjectSettings.globalize_path("res://").plus_file("..")
var Utils = load(root.plus_file("scripts/utils/BuildingPlannerUtils.gd"))
var hover = load("res://unit/test_hover_preview.gd")
var rooms = load("res://unit/test_rooms.gd")
const OUTER = [Vector2.ZERO, Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]
const HOLE = [Vector2(25, 25), Vector2(25, 75), Vector2(75, 75), Vector2(75, 25)]
const BRIDGED = [Vector2.ZERO, Vector2(25, 25), Vector2(25, 75), Vector2(75, 75), Vector2(75, 25), Vector2(25, 25), Vector2.ZERO, Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]

func test_nested_outlines_split_bridges_chains_tangencies_and_keep_winding():
	assert_eq_deep(Utils.split_outline(BRIDGED), [HOLE, OUTER])
	assert_eq_deep(Utils.split_outline(OUTER), [OUTER])
	assert_eq_deep(Utils.split_outline([]), [])
	# A second hole is bridged through the first, rather than directly to the outside.
	var second = [Vector2(10, 10), Vector2(10, 20), Vector2(20, 20), Vector2(20, 10)]
	var chained = [OUTER[0], HOLE[0]] + second + [second[0]] + HOLE + [HOLE[0]] + OUTER
	assert_eq_deep(Utils.split_outline(chained), [second, HOLE, OUTER])
	var reversed = BRIDGED.duplicate()
	reversed.invert()
	var loops = Utils.split_outline(reversed)
	var area = 0.0
	for loop in loops: area += Utils.signed_area(loop)
	assert_eq(area, -7500.0)
	var tangent = [Vector2.ZERO, Vector2(50, 0), Vector2(25, 50), Vector2.ZERO, Vector2(-25, 50), Vector2(-50, 0)]
	assert_eq(Utils.split_outline(tangent).size(), 2)
	assert_eq(BRIDGED[1], HOLE[0], "Source remains unchanged")

func test_nested_outlines_offset_expands_solid_and_shrinks_hole_before_reverse():
	var outline = Utils.region_outline({"polygon": BRIDGED, "source_polygons": [OUTER, HOLE]})
	var style = {"active_offset": 10.0, "active_reverse_direction": false}
	var loops = Utils.prepare_outlines(outline, style)
	assert_eq(abs(Utils.signed_area(loops[0])), 900.0)
	assert_eq(abs(Utils.signed_area(loops[1])), 14400.0)
	style.active_reverse_direction = true
	var reversed = Utils.prepare_outlines(outline, style)
	for i in range(loops.size()): assert_eq_deep(reversed[i], Utils.reverse_outline(loops[i], true))
	style.active_offset = 30.0
	assert_true(Utils.prepare_outlines(outline, style).empty(), "A collapsed hole rejects the entire build")
	# An explicit Path can deliberately retrace itself and must stay one object.
	var path = {"points": BRIDGED, "closed": true}
	assert_eq(Utils.prepare_outlines(path, {"active_offset": 0.0}).size(), 1)

func test_nested_outlines_build_preview_and_grouped_history_match_for_walls_and_paths():
	var helper = autofree(hover.new())
	helper.gut = gut
	for mode in ["WallBuilder", "PathBuilder"]:
		var f = helper.setup_preview(mode)
		f.api.polygon = BRIDGED.duplicate()
		f.api.sources = [OUTER, HOLE]
		f.feature.active_offset = 10.0
		f.feature.active_reverse_direction = true
		if mode == "PathBuilder": f.feature.active_sorting = 1
		helper.refresh(f)
		assert_eq(f.overlay.preview.contours.size(), 2)
		assert_eq(f.overlay.preview.reason, "")
		assert_true(f.feature.build_at(Vector2(10, 50)))
		var container = f.world.Level.Walls if mode == "WallBuilder" else f.world.Level.Pathways
		assert_eq(container.get_child_count(), 2)
		assert_eq(f.history.records.size(), 1)
		var snapshots = []
		for node in container.get_children():
			var data = node.Save(false)
			snapshots.append(data)
			var points = data.get("points", [])
			if mode == "PathBuilder":
				points = Array(str2var(data.edit_points))
				assert_true(data.loop)
				for i in range(points.size()): points[i] += str2var(data.position)
			var expected = Utils.prepare_outlines(Utils.resolve_outline(f.api, Vector2.ZERO), f.feature.get_settings())
			assert_true(points in expected, "Every native object is one prepared boundary")
			var visible = Utils.path_preview_points(points, true, f.feature.active_smoothness) if mode == "PathBuilder" else points
			assert_true(visible in f.overlay.preview.contours, "Preview matches each created object")
		var renderer = f.overlay._texture_preview
		assert_eq(renderer._contour_previews.size(), 1)
		assert_true(renderer._contour_previews[0].visible)
		f.history.records[0].undo()
		assert_eq(container.get_child_count(), 0)
		f.history.records[0].redo()
		for i in range(2): assert_eq_deep(container.get_child(i).Save(false), snapshots[i])
		f.history.records[0].dropped(0)
		f.history.records.clear()
		f.overlay.clear_preview()
		assert_false(renderer._contour_previews[0].visible)
	yield(get_tree(), "idle_frame")

func test_nested_outlines_native_failure_rolls_back_all_walls_and_records_nothing():
	var helper = autofree(hover.new())
	helper.gut = gut
	var f = helper.setup_preview("WallBuilder")
	f.api.polygon = BRIDGED.duplicate()
	f.world.Level.Walls.fail_wall_call = 2
	assert_false(f.feature.build_at(Vector2.ZERO))
	assert_eq(f.world.Level.Walls.get_child_count(), 0)
	assert_eq(f.history.records.size(), 0)
	yield(get_tree(), "idle_frame")

func test_nested_outlines_room_keeps_one_fill_and_two_boundaries_in_compound_history():
	var helper = autofree(rooms.new())
	helper.gut = gut
	for mode in [0, 1]:
		var room = helper.make_room(0)
		room.active_outline_mode = mode
		room._pattern_fill.active_texture = GradientTexture.new()
		room._gl_api.shape_result = {"marker_id": 3, "marker_type": "Shape", "polygon": BRIDGED}
		var level = room._parent_mod.Global.World.Level
		var container = level.Walls if mode == 0 else level.Pathways
		var before = container.get_child_count()
		var fills_before = level.PatternShapes.get_child_count()
		assert_true(room.build_room_at(Vector2.ZERO, {"ready": true, "active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 4}))
		assert_eq(container.get_child_count(), before + 2)
		assert_eq(level.PatternShapes.get_child_count(), fills_before + 1)
		assert_eq_deep(Array(str2var(level.PatternShapes.get_child(fills_before).Save().points)), BRIDGED)
		var record = helper.records.back()
		record.undo()
		assert_eq(container.get_child_count(), before)
		record.redo()
		assert_eq(container.get_child_count(), before + 2)
		record.dropped(0)
		helper.records.clear()
	yield(get_tree(), "idle_frame")

func test_nested_outlines_source_preview_also_removes_bridges():
	var helper = autofree(hover.new())
	helper.gut = gut
	var f = helper.setup_preview("WallBuilder")
	f.api.polygon = BRIDGED.duplicate()
	f.api.sources = [BRIDGED.duplicate()]
	f.feature.active_offset = 10.0
	helper.refresh(f)
	assert_eq_deep(f.overlay.preview.sources, [HOLE, OUTER])
	f.api.polygon = OUTER.duplicate()
	f.api.revision += 1
	helper.refresh(f)
	assert_false(f.overlay._texture_preview._contour_previews[0].visible, "Unused retained renderers are hidden")
