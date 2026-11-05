extends "res://addons/gut/test.gd"

var Builder = ResourceLoader.load(ProjectSettings.globalize_path("res://").plus_file("../scripts/features/PathBuilder.gd"))


class MarkerApi:
	extends Reference
	func is_ready():
		return true
	func compute_fill_polygon(_coords):
		return {"polygon": [Vector2.ZERO, Vector2(50, 0), Vector2(0, 50)]}


class PathNode:
	extends Node2D
	var data = {}
	var points = PoolVector2Array()
	func Save(_copy = false):
		return data.duplicate(true)
	func SetEditPoints(_value):
		pass


class Pathways:
	extends Node
	var fail_load = false
	var received_data = {}
	var load_calls = 0
	func LoadPathway(data):
		load_calls += 1
		received_data = data.duplicate(true)
		if fail_load:
			return null
		var node = PathNode.new()
		node.data = data.duplicate(true)
		node.points = str2var(data.edit_points)
		add_child(node)
		return node


class HistoryApi:
	extends Reference
	var records = []
	func record(action, maximum):
		records.append(action)
		assert(maximum == 100)


func test_successful_path_records_the_loaded_node_and_undo_redo_works():
	var pathways = autofree(Pathways.new())
	var history = HistoryApi.new()
	var parent = {"Global": {"API": {"HistoryApi": history}, "Editor": {"Tools": {}}, "World": {"Level": {"Pathways": pathways}}}}
	var builder = Builder.new(MarkerApi.new(), null, parent)
	builder.active_texture = GradientTexture.new()
	builder.active_color = Color.blue
	assert_true(builder.build_at(Vector2.ZERO))
	assert_eq(pathways.get_child(0).modulate, Color.blue, "Only the final native path receives tint")
	assert_eq(pathways.load_calls, 1, "One native load creates the final path directly")
	assert_eq(pathways.get_child_count(), 1)
	assert_eq(history.records.size(), 1, "A successful build must be undoable")
	var record = history.records[0]
	assert_true(record._node == pathways.get_child(0))
	assert_eq(pathways.get_child(0).points.size(), 4, "Outline is closed")
	record.undo()
	assert_eq(pathways.get_child_count(), 0)
	yield(get_tree(), "idle_frame")
	record.redo()
	assert_eq(pathways.get_child_count(), 1)
	assert_eq(pathways.get_child(0).points.size(), 4)
	# Release the test's parent -> history -> record -> parent cycle.
	history.records.clear()


func test_failed_path_load_leaves_no_nodes_or_history():
	var pathways = autofree(Pathways.new())
	pathways.fail_load = true
	var history = HistoryApi.new()
	var parent = {"Global": {"API": {"HistoryApi": history}, "Editor": {"Tools": {}}, "World": {"Level": {"Pathways": pathways}}}}
	var builder = Builder.new(MarkerApi.new(), null, parent)
	builder.active_texture = GradientTexture.new()
	assert_false(builder.build_at(Vector2.ZERO))
	assert_eq(pathways.get_child_count(), 0)
	assert_eq(history.records.size(), 0)


func test_direct_path_data_keeps_geometry_options_and_under_sorting():
	var pathways = autofree(Pathways.new())
	var sibling = Node2D.new()
	pathways.add_child(sibling)
	var parent = {"Global": {"World": {"Level": {"Pathways": pathways}}}}
	var builder = Builder.new(MarkerApi.new(), null, parent)
	var texture = ImageTexture.new()
	var pixels = Image.new()
	pixels.create(16, 24, false, Image.FORMAT_RGBA8)
	texture.create_from_image(pixels)
	texture.resource_path = "res://test_path.png"
	builder.active_texture = texture
	builder.active_width = 2.5
	builder.active_sorting = 1
	builder.active_layer = 300
	builder.active_smoothness = 0.4
	builder.active_fade_in = true
	builder.active_grow = true
	builder.active_block_light = true
	var polygon = [Vector2(70, 80), Vector2(110, 80), Vector2(70, 120)]
	var path = builder._create_path(polygon)
	assert_eq(path.get_index(), 0, "Under places the final node before existing siblings")
	assert_eq_deep(Array(str2var(pathways.received_data.edit_points)), [Vector2.ZERO, Vector2(40, 0), Vector2(0, 40), Vector2.ZERO])
	assert_eq(str2var(pathways.received_data.position), polygon[0], "Keep the native SetEditPoints origin")
	assert_eq(str2var(pathways.received_data.scale), Vector2.ONE)
	assert_eq(pathways.received_data.rotation, 0.0)
	assert_eq(pathways.received_data.width, 60.0, "Width scale uses the selected texture height")
	assert_eq(pathways.received_data.texture, texture.resource_path)
	assert_eq(pathways.received_data.layer, 300)
	assert_eq(pathways.received_data.smoothness, 0.4)
	assert_true(pathways.received_data.fade_in)
	assert_false(pathways.received_data.fade_out)
	assert_true(pathways.received_data.grow)
	assert_false(pathways.received_data.shrink)
	assert_true(pathways.received_data.block_light)
	assert_false(pathways.received_data.loop)
	assert_false(pathways.received_data.has("node_id"), "Native loader allocates a new world ID")
	builder.active_sorting = 0
	assert_eq(builder._create_path(polygon).get_index(), 2, "Over appends after existing siblings")
