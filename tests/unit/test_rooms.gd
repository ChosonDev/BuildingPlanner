extends "res://addons/gut/test.gd"

var Room = ResourceLoader.load(ProjectSettings.globalize_path("res://").plus_file("../scripts/features/RoomBuilder.gd"))
var History = ResourceLoader.load(ProjectSettings.globalize_path("res://").plus_file("../scripts/tool/BuildingPlannerHistory.gd"))
var Registry = ResourceLoader.load(ProjectSettings.globalize_path("res://").plus_file("../scripts/features/MarkerObjectRegistry.gd"))
const TRIANGLE = [Vector2.ZERO, Vector2(50, 0), Vector2(0, 50)]
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
	var fail = false
	var received_texture = null
	var received_type = null
	var native_draw_calls = 0
	var fail_new_fills = false
	var wall_calls = 0
	var fail_wall_call = -1
	func create(data, path = false):
		var node = SavedPath.new() if path else SavedNode.new()
		node.data = data.duplicate(true)
		add_child(node)
		return node
	func LoadShape(data):
		if fail_new_fills and not data.has("original"):
			return null
		return create(data)
	func LoadPathway(data):
		return create(data, true)
	func LoadWall(data):
		create(data) # Actual host LoadWall returns void.
	func GetShapes():
		return get_children()
	func DrawPolygon(points, _unused):
		native_draw_calls += 1
		var node = create({"points": Array(points)})
		return node
	func AddWall(points, _texture, _color, _loop, _shadow, _type, _joint, _normalize):
		wall_calls += 1
		received_texture = _texture
		received_type = _type
		if fail or wall_calls == fail_wall_call:
			return null
		return create({"points": Array(points), "texture": _texture, "color": _color, "shadow": _shadow, "joint": _joint, "loop": _loop})


class Snapshot:
	extends Reference
	var api
	var before
	var after
	func _init(source, previous):
		api = source
		before = previous
		after = api.markers.duplicate(true)
	func undo():
		api.markers = before.duplicate(true)
	func redo():
		api.markers = after.duplicate(true)


class MarkerApi:
	extends Reference
	var markers = {1: [Vector2(1, 1)], 2: [Vector2(2, 2)]}
	var captured = null
	var reject_capture = false
	var consumed = false
	var fallback = false
	var no_overlap = false
	var fill_polygon = TRIANGLE
	var invalid_boolean_result = null
	var identical_merge = false
	var shape_result = null
	func is_ready():
		return true
	func begin_history_capture():
		if reject_capture or captured != null:
			return false
		captured = []
		return true
	func end_history_capture():
		var actions = captured
		captured = null
		return actions
	func remember(before):
		captured.append(Snapshot.new(self, before))
	func place_shape_marker(_pos, _radius, _angle, _sides, _color):
		var before = markers.duplicate(true)
		markers[3] = TRIANGLE.duplicate()
		remember(before)
		return 3
	func place_shape_marker_plain(pos, radius, angle, sides, color):
		return place_shape_marker(pos, radius, angle, sides, color)
	func delete_marker(id):
		var before = markers.duplicate(true)
		markers.erase(id)
		remember(before)
		return true
	func get_shape_polygon(_id):
		if shape_result != null:
			return shape_result
		return {"polygon": TRIANGLE.duplicate(), "marker_id": _id, "marker_type": "Shape"}

	func compute_fill_polygon(_coords):
		return {"polygon": fill_polygon.duplicate()}
	func place_shape_merge(_pos, _radius, _angle, _sides):
		if invalid_boolean_result != null:
			return invalid_boolean_result
		if identical_merge:
			return {"affected_markers": [{"marker_id": 1, "new_polygon": TRIANGLE}], "absorbed_marker_ids": []}
		if fallback:
			return {"affected_markers": [], "absorbed_marker_ids": []}
		var before = markers.duplicate(true)
		markers[1] = TRIANGLE.duplicate()
		markers.erase(2)
		remember(before)
		return {"affected_markers": [{"marker_id": 1, "new_polygon": TRIANGLE}], "absorbed_marker_ids": [2]}
	func place_shape_conforming(pos, radius, angle, sides, color):
		place_shape_marker(pos, radius, angle, sides, color)
		var before = markers.duplicate(true)
		markers[1] = TRIANGLE.duplicate()
		remember(before)
		return {"marker_id": 3, "marker_polygon": TRIANGLE, "affected_markers": [{"marker_id": 1, "new_polygon": TRIANGLE}]}
	func place_shape_wrapping(pos, radius, angle, sides, color):
		place_shape_marker(pos, radius, angle, sides, color)
		return {"marker_id": 3, "marker_polygon": TRIANGLE, "affected_markers": [{"marker_id": 1, "new_polygon": TRIANGLE}]}
	func apply_shape_difference(_pos, _radius, _angle, _sides):
		var before = markers.duplicate(true)
		if no_overlap:
			remember(before)
			return {"affected_markers": []}
		markers[1] = [] if consumed else TRIANGLE.duplicate()
		remember(before)
		return {"affected_markers": [{"marker_id": 1, "new_polygon": markers[1]}]}


func record(action, _limit):
	records.append(action)


func make_room(mode):
	var fills = autofree(NativeContainer.new())
	var walls = autofree(NativeContainer.new())
	var paths = autofree(NativeContainer.new())
	var api = MarkerApi.new()
	var parent = {"Global": {"World": {"Level": {"PatternShapes": fills, "Walls": walls, "Pathways": paths}}, "Editor": {"Tools": {}}, "API": {"HistoryApi": self}, "ModMapData": {}}}
	var room = Room.new(api, null, parent)
	room._wall_builder.active_texture = GradientTexture.new()
	room._path_builder.active_texture = GradientTexture.new()
	room.active_sub_mode = mode
	for id in [1, 2]:
		var fill = fills.create({"original": id})
		var wall = walls.create({"original": id})
		var fill_settings = room._pattern_fill.get_settings()
		fill_settings.active_texture = GradientTexture.new()
		room._registry.register(id, [fill], [wall], [parent.Global.World.Level], {"outline_mode": 0, "fill": fill_settings, "outline": room._wall_builder.get_settings()})
	return room


func after_each():
	for action in records:
		action.dropped(0)
	records.clear()

func make_template_room(mode):
	# Test-only integration with the authored sibling checkout, through its public API.
	var root = ProjectSettings.globalize_path("res://").plus_file("../../GuidesLines").simplify_path()
	var level = {"PatternShapes": autofree(NativeContainer.new()), "Walls": autofree(NativeContainer.new()),
		"Pathways": autofree(NativeContainer.new()), "TileMap": {"CellSize": Vector2(100, 100)}}
	var world = {"Level": level, "WorldRect": Rect2(-4000, -4000, 8000, 8000)}
	var mod = {"markers_opacity": 0.7, "guides_lines_api": null, "Global": {"API": {}, "Editor": {"IsSnapping": false}}}
	var tool = load(root.plus_file("scripts/tool/GuidesLinesTool.gd")).new(mod)
	tool.GuideMarkerClass = load(root.plus_file("scripts/guides/GuideMarker.gd"))
	tool.cached_world = world
	mod["guides_tool"] = tool
	var api = load(root.plus_file("scripts/api/guides_lines_api.gd")).new(mod, null)
	mod.guides_lines_api = api
	var first = api.place_shape_marker_plain(Vector2.ZERO, 1.0, 45, 4)
	var second = api.place_shape_marker_plain(Vector2(300, 0), 1.0, 45, 4)
	tool.start_group_capture()
	tool.template_group_ids = {first: true, second: true}
	assert_true(tool.save_group_template())
	tool.set_marker_type("Template")
	var parent = {"Global": {"World": world, "Editor": {"Tools": {}}, "API": {"HistoryApi": self}, "ModMapData": {}}}
	var room = Room.new(api, null, parent)
	room._pattern_fill.active_texture = GradientTexture.new()
	room._wall_builder.active_texture = GradientTexture.new()
	room._path_builder.active_texture = GradientTexture.new()
	room.active_sub_mode = mode
	return {"room": room, "tool": tool, "api": api, "mod": mod}

func release_template_room(pair):
	pair.api._unload()
	pair.mod.guides_lines_api = null
	pair.mod.guides_tool = null
	pair.tool.ui.tool = null
	pair.tool.placement.tool = null
	pair.tool._fill_handler.tool = null
	pair.tool.parent_mod = null

func native_room_state(room):
	var level = room._parent_mod.Global.World.Level
	var state = []
	for container in [level.PatternShapes, level.Walls, level.Pathways]:
		var data = []
		for node in container.get_children(): data.append(node.data.duplicate(true))
		state.append(data)
	return state

func test_template_integration_group_single_uses_shared_transforms_and_one_compound_undo():
	var pair = make_template_room(Room.SubMode.SINGLE)
	var room = pair.room
	assert_true(pair.api.set_template_transform(30, 1.5))
	room.adjust_angle(60)
	room.adjust_scale(0.5)
	var pos = Vector2(1000, 1000)
	var expected = pair.api.get_template_markers(pos, -1, 60, 1.5)
	var before = pair.api.get_markers()
	room.update_preview(pos, pair.api.get_placement_state())
	assert_true(room._preview_active)
	assert_eq_deep(pair.tool._api_preview.markers, expected)
	assert_true(room.build_room_at(pos, pair.api.get_placement_state()))
	assert_eq(records.size(), 1)
	assert_eq_deep(pair.api.get_markers(), before)
	var level = room._parent_mod.Global.World.Level
	assert_eq(level.PatternShapes.get_child_count(), 2)
	assert_eq(level.Walls.get_child_count(), 2)
	for i in range(2):
		assert_eq_deep(level.Walls.get_child(i).data.points, expected[i].polygon)
	assert_almost_eq(expected[0].position.x, 1000.0, 0.001)
	assert_almost_eq(expected[0].position.y, 662.5, 0.001)
	var after = native_room_state(room)
	var action = records.back()
	for _cycle in range(2):
		action.undo()
		assert_eq_deep(native_room_state(room), [[], [], []])
		action.redo()
		assert_eq_deep(native_room_state(room), after)
	assert_eq_deep(pair.api.get_markers(), before)
	room.stop_preview()
	assert_true(pair.tool._api_preview.empty())
	release_template_room(pair)
	yield(get_tree(), "idle_frame")

func test_template_integration_all_boolean_modes_process_members_and_restore_original_room():
	for mode in [Room.SubMode.MERGE, Room.SubMode.CONFORM, Room.SubMode.WRAP, Room.SubMode.DIFFERENCE]:
		var pair = make_template_room(Room.SubMode.MERGE)
		var room = pair.room
		var pos = Vector2(1500, 1500)
		assert_true(room.build_room_at(pos, {"ready": true, "active_shape_radius": 2.5, "active_shape_angle": 45.0, "active_shape_sides": 4}))
		var before = native_room_state(room)
		var markers_before = pair.api.get_markers()
		var count = records.size()
		room.active_sub_mode = mode
		assert_true(room.build_room_at(pos, pair.api.get_placement_state()), "Template mode %d" % mode)
		assert_eq(records.size(), count + 1)
		var after = native_room_state(room)
		var markers_after = pair.api.get_markers()
		assert_eq(after[1].size(), 3 if mode in [Room.SubMode.CONFORM, Room.SubMode.WRAP] else 1)
		var action = records.back()
		for _cycle in range(2):
			action.undo()
			assert_eq_deep(native_room_state(room), before)
			assert_eq_deep(pair.api.get_markers(), markers_before)
			action.redo()
			assert_eq_deep(native_room_state(room), after)
			assert_eq_deep(pair.api.get_markers(), markers_after)
		release_template_room(pair)
		yield(get_tree(), "idle_frame")

func test_template_integration_mixed_paths_lines_and_closed_paths_share_room_settings():
	var pair = make_template_room(Room.SubMode.SINGLE)
	var room = pair.room
	var path = pair.api.place_path_marker([Vector2(600, 0), Vector2(800, 0)])
	var closed = pair.api.place_path_marker([Vector2(900, 0), Vector2(1000, 0), Vector2(900, 100)], true)
	var line = pair.api.place_line_marker(Vector2(1100, 0), 90, true)
	pair.tool.start_group_capture()
	pair.tool.template_group_ids = {0: true, path: true, closed: true, line: true}
	assert_true(pair.tool.save_group_template())
	room._wall_builder.active_color = Color.red
	var pos = Vector2(1500, 1500)
	assert_true(room.build_room_at(pos, pair.api.get_placement_state()))
	var level = room._parent_mod.Global.World.Level
	assert_eq(level.Walls.get_child_count(), 4)
	assert_eq(level.PatternShapes.get_child_count(), 2, "Only Shape and closed Path have floor areas")
	for wall in level.Walls.get_children(): assert_eq(wall.data.color, Color.red)
	assert_true(level.Walls.get_child(0).data.loop)
	assert_false(level.Walls.get_child(1).data.loop)
	assert_true(level.Walls.get_child(2).data.loop)
	assert_false(level.Walls.get_child(3).data.loop)
	records.back().undo()
	assert_eq(level.Walls.get_child_count(), 0)
	assert_eq(level.PatternShapes.get_child_count(), 0)
	records.back().redo()
	assert_eq(level.Walls.get_child_count(), 4)
	room.active_outline_mode = room.OutlineMode.PATH
	room._path_builder.active_color = Color.green
	var count = records.size()
	assert_true(room.build_room_at(pos + Vector2(1000, 0), pair.api.get_placement_state()))
	assert_eq(records.size(), count + 1)
	assert_eq(level.Pathways.get_child_count(), 4)
	for path_node in level.Pathways.get_children(): assert_eq(path_node.modulate, Color.green)
	records.back().undo()
	assert_eq(level.Pathways.get_child_count(), 0)
	records.back().redo()
	assert_eq(level.Pathways.get_child_count(), 4)
	release_template_room(pair)
	yield(get_tree(), "idle_frame")

func test_template_integration_partial_native_failure_rolls_back_entire_group_in_every_mode():
	for mode in range(5):
		var pair = make_template_room(Room.SubMode.MERGE)
		var room = pair.room
		var pos = Vector2(1500, 1500)
		assert_true(room.build_room_at(pos, {"ready": true, "active_shape_radius": 2.5, "active_shape_angle": 45.0, "active_shape_sides": 4}))
		var before = native_room_state(room)
		var markers = pair.api.get_markers()
		var count = records.size()
		var walls = room._parent_mod.Global.World.Level.Walls
		walls.wall_calls = 0
		walls.fail_wall_call = 2
		room.active_sub_mode = mode
		assert_false(room.build_room_at(pos, pair.api.get_placement_state()), "Rollback mode %d" % mode)
		assert_eq(records.size(), count)
		assert_eq_deep(native_room_state(room), before)
		assert_eq_deep(pair.api.get_markers(), markers)
		assert_null(pair.tool._captured_history)
		walls.fail_wall_call = -1
		release_template_room(pair)
		yield(get_tree(), "idle_frame")

func test_template_integration_single_template_and_invalid_group_fail_before_mutation():
	var pair = make_template_room(Room.SubMode.SINGLE)
	var room = pair.room
	pair.tool.capture_marker_as_template(Vector2.ZERO)
	assert_true(pair.api.select_template(pair.tool.templates.back().id))
	assert_true(pair.api.set_template_transform(25, 1.5))
	var pos = Vector2(1200, 1200)
	assert_true(room.build_room_at(pos, pair.api.get_placement_state()))
	assert_eq(room._parent_mod.Global.World.Level.Walls.get_child_count(), 1)
	var before = native_room_state(room)
	var count = records.size()
	assert_true(pair.api.select_template(pair.tool.templates[0].id))
	# A legitimate empty boolean outline cannot define a room floor.
	pair.tool.templates[0].items[1].shape_primitives.clear()
	assert_false(room.build_room_at(pos, pair.api.get_placement_state()))
	assert_eq(records.size(), count)
	assert_eq_deep(native_room_state(room), before)
	assert_null(pair.tool._captured_history)
	release_template_room(pair)
	yield(get_tree(), "idle_frame")

func test_merge_adds_current_level_without_losing_old_levels_or_undo_data():
	var room = make_room(Room.SubMode.MERGE)
	var original = room._parent_mod.Global.World.Level
	var current = {"PatternShapes": autofree(NativeContainer.new()), "Walls": autofree(NativeContainer.new()), "Pathways": autofree(NativeContainer.new())}
	room._parent_mod.Global.World.Level = current
	assert_true(room.build_room_at(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true, "active_marker_type": "Path"}))
	assert_eq(original.Walls.get_child_count(), 1)
	assert_eq(current.Walls.get_child_count(), 1, "Merge places a room on the clicked level too")
	assert_eq(room._registry.get_levels(1).size(), 2)
	var action = records.back()
	action.undo()
	assert_eq(original.Walls.get_child_count(), 2)
	assert_eq(current.Walls.get_child_count(), 0)
	yield(get_tree(), "idle_frame")
	action.redo()
	assert_eq(original.Walls.get_child_count(), 1)
	assert_eq(current.Walls.get_child_count(), 1)


func test_boolean_rooms_and_history_preserve_all_original_levels():
	for mode in [Room.SubMode.MERGE, Room.SubMode.CONFORM, Room.SubMode.WRAP, Room.SubMode.DIFFERENCE]:
		var room = make_room(mode)
		var first = room._parent_mod.Global.World.Level
		room._pattern_fill.active_texture = GradientTexture.new()
		var second = {"PatternShapes": autofree(NativeContainer.new()), "Walls": autofree(NativeContainer.new()), "Pathways": autofree(NativeContainer.new())}
		# Marker 2 belongs to another level; merging must retain both levels' geometry.
		room._registry.cleanup(2)
		room._registry.register(2, [second.PatternShapes.create({"original": 2})], [second.Walls.create({"original": 2})], [second], room._registry.get_settings(1))
		room._parent_mod.Global.World.Level = second
		assert_true(room.build_room_at(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true, "active_marker_type": "Shape"}))
		var action = records.back()
		for _iteration in range(2):
			action.undo()
			assert_eq(first.Walls.get_child_count(), 1)
			assert_eq(second.Walls.get_child_count(), 1)
			assert_eq(first.Walls.get_child(0).Save().original, 1)
			assert_eq(second.Walls.get_child(0).Save().original, 2)
			yield(get_tree(), "idle_frame")
			action.redo()
			assert_eq(first.Walls.get_child_count(), 1, "Existing room stays on its original level")
			assert_eq(first.PatternShapes.get_child_count(), 1)
			assert_eq(second.Walls.get_child_count(), 1 if mode == Room.SubMode.MERGE or mode == Room.SubMode.DIFFERENCE else 2)
			if mode == Room.SubMode.MERGE:
				assert_eq(room._registry.get_entry(1).walls.size(), 2)
				assert_eq(room._registry.get_entry(1).levels.size(), 2)
			yield(get_tree(), "idle_frame")


func test_all_room_modes_group_markers_and_wall_outlines_in_one_undo_step():
	for mode in range(5):
		var room = make_room(mode)
		var before = room._gl_api.markers.duplicate(true)
		assert_true(room.build_room_at(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true, "active_marker_type": "Shape"}))
		assert_eq(records.size(), mode + 1, "Exactly one compound history step per room")
		var action = records.back()
		var after = room._gl_api.markers.duplicate(true)
		if mode == 0:
			assert_eq(action._loose.walls.size(), 1)
			assert_true(action._marker_records.empty(), "Single undo/redo never replays temporary marker edits")
		elif mode == 1:
			assert_false(room._registry.has_entry(2), "Absorbed room is removed")
		for _cycle in range(2):
			action.undo()
			assert_eq_deep(room._gl_api.markers, before)
			for id in [1, 2]:
				assert_eq(room._registry.get_entry(id).walls[0].Save().original, id)
			action.redo()
			assert_eq_deep(room._gl_api.markers, after)
		assert_null(room._gl_api.captured)
	yield(get_tree(), "idle_frame")


func test_failed_outline_rolls_back_markers_and_restores_deleted_room_nodes():
	var room = make_room(1)
	var before = room._gl_api.markers.duplicate(true)
	room._parent_mod.Global.World.Level.Walls.fail = true
	assert_false(room.build_room_at(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true, "active_marker_type": "Shape"}))
	assert_eq_deep(room._gl_api.markers, before)
	assert_eq(records.size(), 0)
	for id in [1, 2]:
		assert_eq(room._registry.get_entry(id).walls[0].Save().original, id)
	assert_null(room._gl_api.captured)
	yield(get_tree(), "idle_frame")


func test_path_room_outlines_are_registered_and_restored_in_every_mode():
	var fixture = load("res://unit/test_path_creation.gd")
	for mode in range(5):
		var room = make_room(mode)
		room.active_outline_mode = room.OutlineMode.PATH
		var pathways = autofree(fixture.Pathways.new())
		room._parent_mod.Global.World.Level.Pathways = pathways
		for id in [1, 2]:
			var entry = room._registry.get_entry(id)
			var settings = entry.settings
			settings.outline_mode = room.OutlineMode.PATH
			settings.outline = room._path_builder.get_settings()
			room._registry.register(id, entry.fills, entry.walls, entry.levels, settings)
		assert_true(room.build_room_at(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true, "active_marker_type": "Shape"}))
		var action = records.back()
		assert_true(pathways.get_child_count() > 0)
		if mode != 0:
			var id = 3 if mode in [2, 3] else 1
			assert_eq(room._registry.get_entry(id).walls.size(), 1)
		action.undo()
		assert_eq(pathways.get_child_count(), 0)
		action.redo()
		assert_true(pathways.get_child_count() > 0)
	yield(get_tree(), "idle_frame")


func test_room_record_tracks_recreated_path_instances_across_adjacent_actions():
	var room = make_room(4)
	var registry = room._registry
	var paths = room._parent_mod.Global.World.Level.Pathways
	var before = registry.get_entry(1)
	var first = History.RoomBuilderRecord.new(room._parent_mod, registry)
	first.remember(1)
	registry.cleanup(1)
	registry.register(1, [], [paths.create({"step": 1}, true)])
	first.finish([])
	var second = History.RoomBuilderRecord.new(room._parent_mod, registry)
	second.remember(1)
	registry.cleanup(1)
	registry.register(1, [], [paths.create({"step": 2}, true)])
	second.finish([])
	second.undo()
	assert_eq(registry.get_entry(1).walls[0].Save().step, 1)
	first.undo()
	assert_eq(registry.get_entry(1).walls[0].Save().original, 1)
	first.redo()
	second.redo()
	assert_eq(registry.get_entry(1).walls[0].Save().step, 2)
	assert_eq(paths.get_child_count(), 1, "History must remove current instances, not stale original references")
	first.dropped(0)
	second.dropped(0)
	yield(get_tree(), "idle_frame")


func test_fill_and_wall_single_room_undo_removes_both_and_redo_restores_settings():
	var room = make_room(0)
	room._pattern_fill.active_texture = GradientTexture.new()
	room._pattern_fill.active_color = Color(0.2, 0.4, 0.6)
	room._pattern_fill.active_layer = 300
	assert_true(room.build_room_at(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true, "active_marker_type": "Shape"}))
	var action = records.back()
	assert_eq(action._loose.fills.size(), 1)
	assert_eq(action._loose.walls.size(), 1)
	assert_eq(room._parent_mod.Global.World.Level.PatternShapes.native_draw_calls, 0, "Native DrawPolygon would add an independent history record")
	action.undo()
	yield(get_tree(), "idle_frame")
	action.redo()
	assert_eq(action._loose.fills[0].Save().color, room._pattern_fill.active_color.to_html())
	assert_eq(action._loose.fills[0].Save().layer, 300)
	assert_eq(action._loose.fills[0].Save().points, var2str(PoolVector2Array(TRIANGLE)))


func test_consumed_difference_and_merge_fallback_are_reversible():
	var room = make_room(4)
	room._gl_api.consumed = true
	var before = room._gl_api.markers.duplicate(true)
	assert_true(room.build_room_at(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true, "active_marker_type": "Shape"}))
	assert_false(room._registry.has_entry(1))
	var action = records.back()
	action.undo()
	assert_eq_deep(room._gl_api.markers, before)
	assert_eq(room._registry.get_entry(1).walls[0].Save().original, 1)
	action.redo()
	assert_false(room._registry.has_entry(1))
	room = make_room(1)
	room._gl_api.fallback = true
	assert_true(room.build_room_at(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true, "active_marker_type": "Shape"}))
	assert_true(room._registry.has_entry(3))
	action = records.back()
	action.undo()
	assert_false(room._registry.has_entry(3))
	assert_false(room._gl_api.markers.has(3))
	action.redo()
	assert_true(room._registry.has_entry(3))
	assert_true(room._gl_api.markers.has(3))
	yield(get_tree(), "idle_frame")


func test_old_room_history_cannot_touch_new_map_registry():
	var room = make_room(1)
	assert_true(room.build_room_at(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true, "active_marker_type": "Shape"}))
	var action = records.back()
	room.on_map_changed()
	var new_node = room._parent_mod.Global.World.Level.Walls.create({"new_map": true})
	room._registry.register(1, [], [new_node])
	action.undo()
	action.redo()
	assert_true(room._registry.get_entry(1).walls[0] == new_node)
	assert_false(new_node.is_queued_for_deletion())
	yield(get_tree(), "idle_frame")


func test_room_path_reload_failure_rolls_back_all_marker_and_registry_changes():
	var fixture = load("res://unit/test_path_creation.gd")
	for mode in [0, 1]:
		var room = make_room(mode)
		room.active_outline_mode = room.OutlineMode.PATH
		var pathways = autofree(fixture.Pathways.new())
		pathways.fail_load = true
		room._parent_mod.Global.World.Level.Pathways = pathways
		var before = room._gl_api.markers.duplicate(true)
		assert_false(room.build_room_at(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true, "active_marker_type": "Shape"}))
		assert_eq_deep(room._gl_api.markers, before)
		assert_eq(pathways.get_child_count(), 0)
		assert_eq(records.size(), 0)
		assert_eq(room._registry.get_entry(1).walls[0].Save().original, 1)
		assert_null(room._gl_api.captured)
	yield(get_tree(), "idle_frame")


func test_room_history_restores_path_tree_order_even_when_entries_are_touched_out_of_order():
	var room = make_room(4)
	var paths = room._parent_mod.Global.World.Level.Pathways
	var registry = room._registry
	for i in range(5):
		var node = paths.create({"order": i}, true)
		if i in [1, 3]:
			registry.register(i + 10, [], [node])
	var action = History.RoomBuilderRecord.new(room._parent_mod, registry)
	for id in [13, 11]:
		action.remember(id)
	# Snapshot all touched entries before changing any ordering.
	for id in [13, 11]:
		registry.cleanup(id)
		registry.register(id, [], [paths.create({"replacement": id}, true)])
	action.finish([])
	action.undo()
	for i in range(5):
		assert_eq(paths.get_child(i).Save().order, i)
	action.redo()
	assert_eq(paths.get_child_count(), 5)
	action.dropped(0)
	yield(get_tree(), "idle_frame")


func test_room_path_settings_reach_shared_native_creation_without_resetting_to_defaults():
	var fixture = load("res://unit/test_path_creation.gd")
	var room = make_room(0)
	var pathways = autofree(fixture.Pathways.new())
	room._parent_mod.Global.World.Level.Pathways = pathways
	room.active_outline_mode = room.OutlineMode.PATH
	room._path_builder.active_layer = 300
	room._path_builder.active_sorting = 1
	room._path_builder.active_fade_in = true
	room._path_builder.active_grow = true
	room._path_builder.active_block_light = true
	room._path_builder.active_smoothness = 0.4
	room._path_builder.active_width = 2.5
	room._path_builder.active_color = Color.red
	assert_true(room.build_room_at(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true, "active_marker_type": "Shape"}))
	assert_eq_deep([pathways.received_data.layer, pathways.received_data.fade_in, pathways.received_data.fade_out, pathways.received_data.grow, pathways.received_data.shrink], [300, true, false, true, false])
	var path = records.back()._loose.walls[0]
	assert_eq(path.data.smoothness, 0.4)
	assert_eq(path.data.width, room._path_builder.active_texture.get_height() * 2.5)
	assert_true(path.data.block_light)
	assert_eq(path.modulate, Color.red)
	yield(get_tree(), "idle_frame")


func test_failed_new_fill_rolls_back_every_room_mode_without_losing_old_objects():
	for mode in range(5):
		var room = make_room(mode)
		room._pattern_fill.active_texture = GradientTexture.new()
		var level = room._parent_mod.Global.World.Level
		level.PatternShapes.fail_new_fills = true
		var before = room._gl_api.markers.duplicate(true)
		assert_false(room.build_room_at(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true, "active_marker_type": "Shape"}))
		assert_eq_deep(room._gl_api.markers, before)
		assert_eq(level.PatternShapes.get_child_count(), 2)
		assert_eq(level.Walls.get_child_count(), 2)
		assert_eq(records.size(), 0)
		for id in [1, 2]:
			assert_eq(room._registry.get_entry(id).fills[0].Save().original, id)
		assert_null(room._gl_api.captured)
	yield(get_tree(), "idle_frame")


func test_difference_without_overlap_preserves_scene_and_does_not_record_an_undo_step():
	var room = make_room(4)
	room._gl_api.no_overlap = true
	var before = room._gl_api.markers.duplicate(true)
	var original = room._registry.get_entry(1).walls[0]
	assert_true(room.build_room_at(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true, "active_marker_type": "Shape"}))
	assert_eq(records.size(), 0)
	assert_eq_deep(room._gl_api.markers, before)
	assert_true(room._registry.get_entry(1).walls[0] == original)
	assert_null(room._gl_api.captured)


func test_single_and_merge_fallback_use_new_marker_outline_despite_other_fill_regions():
	for mode in [0, 1]:
		var room = make_room(mode)
		room._gl_api.fallback = true
		room._gl_api.fill_polygon = [Vector2.ZERO, Vector2(5, 0), Vector2(0, 5)]
		assert_true(room.build_room_at(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true, "active_marker_type": "Shape"}))
		var node = records.back()._loose.walls[0] if mode == 0 else room._registry.get_entry(3).walls[0]
		assert_eq_deep(node.Save().points, TRIANGLE)
	yield(get_tree(), "idle_frame")


func test_single_rejects_malformed_or_mismatched_marker_geometry_and_rolls_back():
	for result in [[], {"polygon": TRIANGLE}, {"marker_id": 99, "marker_type": "Shape", "polygon": TRIANGLE}, {"marker_id": 3, "marker_type": "Path", "polygon": TRIANGLE}, {"marker_id": 3, "marker_type": "Shape", "polygon": "bad"}]:
		var room = make_room(0)
		room._gl_api.shape_result = result
		var before = room._gl_api.markers.duplicate(true)
		assert_false(room.build_room_at(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true, "active_marker_type": "Shape"}))
		assert_eq_deep(room._gl_api.markers, before)
		assert_true(records.empty())
		assert_eq(room._parent_mod.Global.World.Level.Walls.get_child_count(), 2)
	yield(get_tree(), "idle_frame")


func test_repeated_merge_result_replaces_existing_room_without_duplicate_objects():
	var room = make_room(1)
	room._gl_api.identical_merge = true
	var level = room._parent_mod.Global.World.Level
	for _repeat in range(3):
		assert_true(room.build_room_at(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true, "active_marker_type": "Shape"}))
		assert_false(room._gl_api.markers.has(3), "Current GuidesLines returns the surviving marker, not a new placement")
		assert_eq(level.Walls.get_child_count(), 2)
		assert_eq(room._registry.get_entry(1).walls.size(), 1)
		records.back().undo()
		records.back().redo()
		assert_eq(level.Walls.get_child_count(), 2)
	yield(get_tree(), "idle_frame")


func test_conform_and_difference_do_not_build_native_rooms_for_plain_markers():
	for mode in [2, 4]:
		var room = make_room(mode)
		room._registry.cleanup(1)
		var level = room._parent_mod.Global.World.Level
		assert_true(room.build_room_at(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true, "active_marker_type": "Shape"}))
		assert_false(room._registry.has_entry(1))
		assert_false(records.back()._before.has(1), "Plain marker history needs no native-object snapshot")
		assert_false(records.back()._after.has(1))
		assert_eq(level.Walls.get_child_count(), 2 if mode == 2 else 1)
		for _cycle in range(2):
			records.back().undo()
			records.back().redo()
			assert_false(room._registry.has_entry(1))
	yield(get_tree(), "idle_frame")


func test_boolean_cuts_preserve_room_style_and_outline_across_undo_redo():
	var fixture = load("res://unit/test_path_creation.gd")
	for outline in [0, 1]:
		for mode in [2, 4]:
			var room = make_room(1)
			var level = room._parent_mod.Global.World.Level
			level.Pathways = autofree(fixture.Pathways.new())
			room.active_outline_mode = outline
			room._pattern_fill.active_texture = GradientTexture.new()
			room._pattern_fill.active_color = Color.red
			room._pattern_fill.active_layer = 300
			room._pattern_fill.active_rotation = 45
			room._wall_builder.active_color = Color.green
			room._wall_builder.active_joint = 0
			room._path_builder.active_color = Color.green
			room._path_builder.active_width = 2.5
			assert_true(room.build_room_at(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true, "active_marker_type": "Shape"}))
			var original_settings = room._registry.get_settings(1)
			# A different room style in the UI must not repaint the dented neighbor.
			room.active_outline_mode = 1 - outline
			room._pattern_fill.active_color = Color.blue
			room._pattern_fill.active_layer = 100
			room._pattern_fill.active_rotation = 90
			room._wall_builder.active_color = Color.blue
			room._path_builder.active_color = Color.blue
			room.active_sub_mode = mode
			assert_true(room.build_room_at(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true, "active_marker_type": "Shape"}))
			var action = records.back()
			for _cycle in range(3):
				var entry = room._registry.get_entry(1)
				assert_eq_deep(entry.settings, original_settings)
				assert_eq(entry.fills[0].Save().color, Color.red.to_html())
				assert_eq(entry.fills[0].Save().layer, 300)
				assert_eq(entry.fills[0].Save().rotation, deg2rad(45))
				assert_eq(entry.walls[0].has_method("SetEditPoints"), outline == 1)
				if outline == 1:
					assert_eq(entry.walls[0].modulate, Color.green)
					assert_eq(entry.walls[0].Save().width, original_settings.outline.active_texture.get_height() * 2.5)
				else:
					assert_eq(entry.walls[0].Save().color, Color.green)
					assert_eq(entry.walls[0].Save().joint, 0)
				action.undo()
				action.redo()
			assert_eq(room._pattern_fill.active_color, Color.blue, "Neighbor replay leaves current UI choices intact")
			# A second cut after replay must still use the original settings.
			assert_true(room.build_room_at(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true, "active_marker_type": "Shape"}))
			assert_eq_deep(room._registry.get_settings(1), original_settings)
	yield(get_tree(), "idle_frame")


class DiagnosticLogger:
	extends Reference
	func debug(_message):
		pass
	var errors = []
	func error(message):
		errors.append(message)


func test_rejected_capture_and_mismatched_shape_log_errors_without_committing():
	var room = make_room(Room.SubMode.SINGLE)
	var logger = DiagnosticLogger.new()
	room.LOGGER = logger
	room._gl_api.reject_capture = true
	assert_false(room.build_room_at(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true}))
	assert_eq(logger.errors.size(), 1)
	assert_true("begin_history_capture" in logger.errors.back())
	room._gl_api.reject_capture = false
	room._gl_api.shape_result = {"marker_id": 999, "marker_type": "Shape", "polygon": TRIANGLE}
	var before = room._gl_api.markers.duplicate(true)
	assert_false(room.build_room_at(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true}))
	assert_eq(logger.errors.size(), 2)
	assert_true("get_shape_polygon" in logger.errors.back())
	assert_eq_deep(room._gl_api.markers, before)
	assert_true(records.empty())


func test_invalid_boolean_contracts_log_and_preserve_existing_rooms():
	var room = make_room(Room.SubMode.MERGE)
	var logger = DiagnosticLogger.new()
	room.LOGGER = logger
	for result in [false, {}, {"affected_markers": false}, {"affected_markers": [], "absorbed_marker_ids": [-1]}, {"affected_markers": [{"marker_id": "bad"}]}, {"affected_markers": [{"marker_id": 1, "new_polygon": false}]}, {"affected_markers": [{"marker_id": 1, "new_polygon": [Vector2.ZERO]}]}]:
		room._gl_api.invalid_boolean_result = result
		var count = logger.errors.size()
		assert_false(room.build_room_at(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true}))
		assert_eq(logger.errors.size(), count + 1)
		assert_eq(room._parent_mod.Global.World.Level.Walls.get_child_count(), 2)
		assert_eq(room._parent_mod.Global.World.Level.PatternShapes.get_child_count(), 2)
		assert_true(records.empty())


func test_missing_shape_settings_and_room_metadata_fail_without_mutation():
	var room = make_room(Room.SubMode.CONFORM)
	var logger = DiagnosticLogger.new()
	room.LOGGER = logger
	var valid = {"ready": true, "active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6}
	for field in ["active_shape_radius", "active_shape_angle", "active_shape_sides"]:
		var state = valid.duplicate()
		state.erase(field)
		assert_false(room.build_room_at(Vector2.ZERO, state))
	assert_eq(logger.errors.size(), 3)
	var before = room._gl_api.markers.duplicate(true)
	var entry = room._registry.get_entry(1)
	for missing in ["levels", "settings"]:
		room._registry.register(1, entry.fills, entry.walls, [] if missing == "levels" else entry.levels, {} if missing == "settings" else entry.settings)
		assert_false(room.build_room_at(Vector2.ZERO, valid))
		assert_eq_deep(room._gl_api.markers, before)
		assert_true(room._registry.get_entry(1).walls[0] == entry.walls[0])
	assert_eq(logger.errors.size(), 5)
	assert_true(records.empty())


func test_history_owns_settings_snapshots_across_registry_replacement_and_replay():
	var room = make_room(Room.SubMode.DIFFERENCE)
	var original = room._registry.get_entry(1)
	var action = History.RoomBuilderRecord.new(room._parent_mod, room._registry)
	action.remember(1)
	var changed = original.settings.duplicate(true)
	changed.fill.active_color = Color.red
	room._registry.register(1, original.fills, original.walls, original.levels, changed)
	action.finish([])
	changed.fill.active_color = Color.blue
	for _cycle in range(2):
		action.undo()
		assert_eq(room._registry.get_settings(1).fill.active_color, Color.white)
		action.redo()
		assert_eq(room._registry.get_settings(1).fill.active_color, Color.red)
		var current = room._registry.get_entry(1)
		current.settings.fill.active_color = Color.green
		room._registry.register(1, current.fills, current.walls, current.levels, current.settings)
	assert_eq(action._before[1].settings.fill.active_color, Color.white)
	assert_eq(action._after[1].settings.fill.active_color, Color.red)
	action.dropped(0)
	yield(get_tree(), "idle_frame")
