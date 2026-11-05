extends "res://addons/gut/test.gd"

var History = ResourceLoader.load(ProjectSettings.globalize_path("res://").plus_file("../scripts/tool/BuildingPlannerHistory.gd"))


# Controlled Save/Load collaborators; native Dungeondraft serialization is excluded.
class SavedNode:
	extends Node2D
	var data = {"texture": "test", "layer": 100, "points": [1, 2, 3]}
	func Save(_copy = false):
		return data.duplicate(true)


class SavedPath:
	extends SavedNode
	func SetEditPoints(_points):
		pass


# Match the C# call boundary: optional C# parameters must be passed by GDScript.
class ExplicitCopyNode:
	extends Node2D
	var calls = []
	func Save(copy):
		calls.append(copy)
		return {} if copy else {"node_id": "2a"}


class ExplicitCopyPath:
	extends ExplicitCopyNode
	func SetEditPoints(_points):
		pass


class NoArgumentWall:
	extends Node2D
	func Save():
		return {"node_id": "2b"}


func test_native_history_passes_explicit_copy_false_and_keeps_wall_save_without_arguments():
	var fills = autofree(Node2D.new())
	var walls = autofree(Node2D.new())
	var paths = autofree(Node2D.new())
	var level = {"PatternShapes": fills, "Walls": walls, "Pathways": paths}
	var parent = {"Global": {"World": {"Level": level}}}
	var fill = ExplicitCopyNode.new()
	var path = ExplicitCopyPath.new()
	var wall = NoArgumentWall.new()
	fills.add_child(fill)
	paths.add_child(path)
	walls.add_child(wall)
	for kind in ["PatternFill", "PathBuilder", "RoofBuilder", "WallBuilder"]:
		var node = wall if kind == "WallBuilder" else (path if kind == "PathBuilder" else fill)
		var action = History.NativeObjectRecord.new(parent, node, kind)
		assert_eq(action._data.node_id, "2b" if kind == "WallBuilder" else "2a")
		if node != wall:
			assert_eq(node.calls.back(), false)
			node.calls.clear()
	var registry = load(ProjectSettings.globalize_path("res://").plus_file("../scripts/features/MarkerObjectRegistry.gd")).new(null)
	var room = History.RoomBuilderRecord.new(parent, registry)
	# Single rooms serialize loose objects; boolean rooms snapshot registry entries.
	room._loose = {"fills": [fill], "walls": [wall, path]}
	registry.register(1, [fill], [wall, path], [level])
	room.remember(1)
	room.finish([])
	assert_eq_deep(fill.calls, [false, false, false])
	assert_eq_deep(path.calls, [false, false, false])
	assert_eq(room._loose_data.fills[0].data.node_id, "2a")
	assert_eq(room._loose_data.walls[0].data.node_id, "2b")
	assert_eq(room._loose_data.walls[1].data.node_id, "2a")
	room.dropped(0)


class SavedContainer:
	extends Node
	var world = null
	var mutate_input = false
	func _restore(data, path = false):
		var node = SavedPath.new() if path else SavedNode.new()
		node.data = data.duplicate(true)
		if mutate_input:
			data.points.append(99)
		add_child(node)
		return node
	func LoadShape(data):
		return _restore(data)
	func LoadPathway(data):
		var node = _restore(data, true)
		if world:
			world.assign(node)
		return node
	func LoadRoof(data):
		return _restore(data)
	func LoadWall(data):
		_restore(data) # Native LoadWall returns void.


class IdentityWorld:
	extends Reference
	var Level
	var nodes = {}
	var next_id = 1
	func assign(node):
		node.set_meta("node_id", next_id)
		nodes[next_id] = node
		next_id += 1
	func HasNodeID(id):
		return nodes.has(id)
	func GetNodeByID(id):
		return nodes.get(id)
	func RemoveNodeID(id):
		nodes.erase(id)


func test_standalone_wall_records_one_action_and_restores_original_level_and_order():
	var fixture = load("res://unit/test_rooms.gd")
	var walls = autofree(fixture.NativeContainer.new())
	var other = autofree(fixture.NativeContainer.new())
	var parent = {"Global": {"World": {"Level": {"Walls": walls}}, "API": {"HistoryApi": self}}}
	var builder = load(ProjectSettings.globalize_path("res://").plus_file("../scripts/features/WallBuilder.gd")).new(fixture.MarkerApi.new(), null, parent)
	builder.active_texture = GradientTexture.new()
	_wall_actions.clear()
	assert_true(builder.build_at(Vector2.ZERO))
	assert_eq(_wall_actions.size(), 1)
	assert_eq(walls.received_type, 1, "Standalone walls use native Manual type")
	var action = _wall_actions[0]
	var saved = walls.get_child(0).Save()
	walls.add_child(Node.new())
	parent.Global.World.Level = {"Walls": other}
	for _iteration in range(2):
		action.undo()
		assert_eq(walls.get_child_count(), 1)
		yield(get_tree(), "idle_frame")
		action.redo()
		assert_eq(other.get_child_count(), 0)
		assert_eq(walls.get_child_count(), 2)
		assert_eq_deep(walls.get_child(0).Save(), saved)
	action.dropped(0)
	assert_eq(walls.get_child_count(), 2)
	other.fail = true
	assert_false(builder.build_at(Vector2.ZERO))
	assert_eq(_wall_actions.size(), 1, "Failed creation adds no history")
	_wall_actions.clear()


var _wall_actions = []
func record(action, _limit):
	_wall_actions.append(action)


func test_path_redo_restores_color_and_original_level_and_unregisters_old_world_id():
	var container = autofree(SavedContainer.new())
	var other_level = autofree(SavedContainer.new())
	var world = IdentityWorld.new()
	world.Level = {"Pathways": container}
	container.world = world
	var parent = {"Global": {"World": world, "ModMapData": {"UchideshiNodeData": {}}}}
	var node = SavedPath.new()
	container.add_child(node)
	world.assign(node)
	var old_id = node.get_meta("node_id")
	var color = Color(0.2, 0.4, 0.6, 0.8)
	node.modulate = color
	var action = History.PathBuilderRecord.new(parent, node)
	var utils = load(ProjectSettings.globalize_path("res://").plus_file("../scripts/utils/BuildingPlannerUtils.gd"))
	utils.store_path_color_for_camt(parent.Global, old_id, color)
	container.add_child(Node.new())
	action.undo()
	assert_false(world.HasNodeID(old_id))
	assert_true(parent.Global.ModMapData.UchideshiNodeData.data.empty())
	world.Level = {"Pathways": other_level}
	action.redo()
	assert_eq(other_level.get_child_count(), 0)
	assert_eq(container.get_child_count(), 2)
	var restored = container.get_child(0)
	assert_eq(restored.modulate, color)
	var key = "node-id-" + str(restored.get_meta("node_id"))
	assert_eq(parent.Global.ModMapData.UchideshiNodeData.data[key].colour, color.to_html())
	action.undo()
	assert_true(parent.Global.ModMapData.UchideshiNodeData.data.empty())
	for _cycle in range(3):
		action.redo()
		assert_eq(parent.Global.ModMapData.UchideshiNodeData.data.size(), 1)
		action.undo()
		assert_true(parent.Global.ModMapData.UchideshiNodeData.data.empty(), "Redo IDs must not accumulate orphan CAMT keys")
	action.dropped(1)
	assert_null(action._color)
	container.world = null
	yield(get_tree(), "idle_frame")


func test_fill_path_and_roof_history_undo_redo_and_drop():
	var container = autofree(SavedContainer.new())
	var parent_mod = {"Global": {"World": {"Level": {"PatternShapes": container, "Pathways": container, "Roofs": container}}}}
	for kind in ["PatternFill", "PathBuilder", "RoofBuilder"]:
		var node = SavedNode.new()
		container.add_child(node)
		var record
		match kind:
			"PatternFill":
				record = History.PatternFillRecord.new(parent_mod, node)
			"PathBuilder":
				record = History.PathBuilderRecord.new(parent_mod, node)
			"RoofBuilder":
				record = History.RoofBuilderRecord.new(parent_mod, null, node)
		assert_eq(record.record_type(), "BuildingPlanner." + kind)
		record.undo()
		assert_eq(container.get_child_count(), 0)
		assert_true(node.is_queued_for_deletion())
		yield(get_tree(), "idle_frame")
		assert_false(is_instance_valid(node))
		record.redo()
		assert_eq(container.get_child_count(), 1)
		var restored = container.get_child(0)
		assert_eq_deep(restored.Save(), {"texture": "test", "layer": 100, "points": [1, 2, 3]})
		record.dropped(0)
		assert_eq_deep(record._data, {})
		assert_null(record._node)
		assert_eq(container.get_child_count(), 1, "Dropping active history preserves map objects")
		assert_false(restored.is_queued_for_deletion())
		# Start a new record because dropped(0) deliberately releases live references.
		match kind:
			"PatternFill":
				record = History.PatternFillRecord.new(parent_mod, restored)
			"PathBuilder":
				record = History.PathBuilderRecord.new(parent_mod, restored)
			"RoofBuilder":
				record = History.RoofBuilderRecord.new(parent_mod, null, restored)
		record.undo()
		record.dropped(1)
		assert_eq_deep(record._data, {})
		yield(get_tree(), "idle_frame")


func test_redo_loaders_cannot_mutate_saved_nested_snapshots():
	var container = autofree(SavedContainer.new())
	container.mutate_input = true
	var parent = {"Global": {"World": {"Level": {"PatternShapes": container, "Pathways": container, "Roofs": container}}}}
	for kind in ["PatternFill", "PathBuilder", "RoofBuilder"]:
		var node = SavedNode.new()
		container.add_child(node)
		var action
		if kind == "PatternFill":
			action = History.PatternFillRecord.new(parent, node)
		elif kind == "PathBuilder":
			action = History.PathBuilderRecord.new(parent, node)
		else:
			action = History.RoofBuilderRecord.new(parent, null, node)
		for _iteration in range(3):
			action.undo()
			yield(get_tree(), "idle_frame")
			action.redo()
			assert_eq_deep(container.get_child(0).Save().points, [1, 2, 3])
		action.undo()
		action.dropped(1)
		yield(get_tree(), "idle_frame")

func test_pattern_fill_redo_restores_original_order_between_untouched_siblings():
	var shapes = autofree(SavedContainer.new())
	shapes.add_child(Node.new())
	var shape = SavedNode.new()
	shapes.add_child(shape)
	shapes.add_child(Node.new())
	var parent = {"Global": {"World": {"Level": {"PatternShapes": shapes}}}}
	var action = History.PatternFillRecord.new(parent, shape)
	for _iteration in range(3):
		action.undo()
		assert_eq(shapes.get_child_count(), 2)
		yield(get_tree(), "idle_frame")
		action.redo()
		assert_eq(action._node.get_index(), 1)
		assert_eq(shapes.get_child_count(), 3)

func test_room_replay_restores_native_fill_wall_colors_without_extra_modulate():
	var fixture = load("res://unit/test_rooms.gd")
	var fills = autofree(fixture.NativeContainer.new())
	var walls = autofree(fixture.NativeContainer.new())
	var paths = autofree(fixture.NativeContainer.new())
	var level = {"PatternShapes": fills, "Walls": walls, "Pathways": paths}
	var parent = {"Global": {"World": {"Level": level}, "ModMapData": {}}}
	var registry = load(ProjectSettings.globalize_path("res://").plus_file("../scripts/features/MarkerObjectRegistry.gd")).new(null)
	var fill = fills.create({"color": "native fill tint"})
	var wall = walls.create({"color": "native wall tint"})
	var path = paths.create({"points": []}, true)
	for node in [fill, wall, path]:
		node.modulate = Color.blue
	registry.register(1, [fill], [wall, path])
	var action = History.RoomBuilderRecord.new(parent, registry)
	action.remember(1)
	action.finish([])
	action.undo()
	assert_eq(fills.get_child(0).data.color, "native fill tint")
	assert_eq(walls.get_child(0).data.color, "native wall tint")
	assert_eq(fills.get_child(0).modulate, Color.white)
	assert_eq(walls.get_child(0).modulate, Color.white)
	assert_eq(paths.get_child(0).modulate, Color.blue, "Paths still restore their separate tint")
	yield(get_tree(), "idle_frame")


class NativeLevel:
	extends Node
	var PatternShapes
	var Walls
	var Pathways


func test_cached_room_levels_guard_freed_secondary_level_before_replay():
	var first = autofree(NativeLevel.new())
	var second = NativeLevel.new()
	second.Walls = SavedContainer.new()
	second.add_child(second.Walls)
	var wall = SavedNode.new()
	second.Walls.add_child(wall)
	var parent = {"Global": {"World": {"Level": first}}}
	var registry = load(ProjectSettings.globalize_path("res://").plus_file("../scripts/features/MarkerObjectRegistry.gd")).new(null)
	registry.register(1, [], [wall], [second])
	var action = History.RoomBuilderRecord.new(parent, registry)
	action.remember(1)
	action.finish([])
	assert_true(action._is_current())
	second.free()
	assert_false(action._is_current())
	action.undo()
	action.redo()
	assert_true(registry.has_entry(1), "Invalid history must not clean the current registry")
	action.dropped(0)
	assert_true(action._levels.empty())
