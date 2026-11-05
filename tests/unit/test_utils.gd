extends "res://addons/gut/test.gd"

func test_level_resolution_rejects_missing_or_freed_context_and_keeps_original_level():
	assert_null(Utils.resolve_level(null))
	assert_null(Utils.resolve_level({"Global": {"World": null}}))
	var original = Node.new()
	var active = autofree(Node.new())
	var parent = {"Global": {"World": {"Level": active}}}
	assert_true(Utils.resolve_level(parent) == active)
	assert_true(Utils.resolve_level(parent, original) == original)
	original.free()
	assert_null(Utils.resolve_level(parent, original))
	var world = Node.new()
	parent.Global.World = world
	world.free()
	assert_null(Utils.resolve_level(parent))

var Utils = ResourceLoader.load(ProjectSettings.globalize_path("res://").plus_file("../scripts/utils/BuildingPlannerUtils.gd"))


func test_history_guard_preserves_original_levels_and_rejects_freed_host_objects():
	var world = Node.new()
	var level = Node.new()
	var parent = {"Global": {"World": world}}
	assert_true(Utils.is_current_world(parent, world, level))
	# The active level is deliberately not part of the guard: history owns its level.
	assert_false(Utils.is_current_world(parent, world, null))
	parent.Global.World = null
	assert_false(Utils.is_current_world(parent, world, level))
	parent.Global.World = world
	level.free()
	assert_false(Utils.is_current_world(parent, world, level))
	world.free()
	assert_false(Utils.is_current_world(parent, world, level))
	var freed_parent = Node.new()
	freed_parent.free()
	assert_false(Utils.is_current_world(freed_parent, world, level))
	assert_false(Utils.is_current_world(null, world, level))


func test_polygon_edge_bounds_preserve_near_contact_tolerance_and_large_contours():
	var circle = []
	for i in range(128):
		circle.append(Vector2(cos(TAU * i / 128), sin(TAU * i / 128)) * 100)
	assert_eq_deep(Utils.sanitize_polygon(circle), circle)
	var notch = [Vector2.ZERO, Vector2(10, 0), Vector2(10, 10), Vector2(5, 0.00005), Vector2(0, 10)]
	assert_eq_deep(Utils.sanitize_polygon(notch), [])


func test_polygon_sanitization_handles_closure_duplicates_winding_and_translation():
	var polygon = [Vector2.ZERO, Vector2(0.1, 0), Vector2(50, 0), Vector2(50, 50), Vector2(0, 50), Vector2.ZERO]
	var copy = polygon.duplicate()
	var expected = [Vector2.ZERO, Vector2(50, 0), Vector2(50, 50), Vector2(0, 50)]
	assert_eq_deep(Utils.sanitize_polygon(polygon), expected)
	assert_eq_deep(polygon, copy)
	expected.invert()
	assert_eq_deep(Utils.sanitize_polygon(PoolVector2Array(expected)), expected)
	for i in range(expected.size()):
		expected[i] += Vector2(100000, -200000)
	assert_eq_deep(Utils.sanitize_polygon(expected), expected)
	var concave = [Vector2.ZERO, Vector2(50, 0), Vector2(25, 10), Vector2(50, 50), Vector2(0, 50)]
	assert_eq_deep(Utils.sanitize_polygon(concave), concave)


func test_polygon_sanitization_rejects_malformed_nonfinite_flat_and_crossed_outlines():
	for polygon in [null, {}, "polygon", 42, [], [Vector2.ZERO],
		[Vector2.ZERO, 7, Vector2.ONE],
		[Vector2.ZERO, Vector2(INF, 0), Vector2.ONE],
		[Vector2.ZERO, Vector2(0, NAN), Vector2.ONE],
		[Vector2.ZERO, Vector2.ONE, Vector2(2, 2)],
		[Vector2.ZERO, Vector2(50, 50), Vector2(0, 50), Vector2(50, 0)],
		[Vector2.ZERO, Vector2(100, 0), Vector2(0, 100), Vector2(100, 100), Vector2(50, -20)],
		[Vector2.ZERO, Vector2(50, 0), Vector2(50, 50), Vector2(10, 0), Vector2(40, 0), Vector2(0, 50)]]:
		assert_eq_deep(Utils.sanitize_polygon(polygon), [])


func test_polygon_sanitization_preserves_guideslines_hole_bridges_and_tangent_loops():
	var bridged = [Vector2.ZERO, Vector2(25, 25), Vector2(25, 75), Vector2(75, 75), Vector2(75, 25), Vector2(25, 25), Vector2.ZERO, Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]
	assert_eq_deep(Utils.sanitize_polygon(bridged), bridged)
	var tangent = [Vector2.ZERO, Vector2(50, 0), Vector2(25, 50), Vector2.ZERO, Vector2(-25, 50), Vector2(-50, 0)]
	assert_eq_deep(Utils.sanitize_polygon(tangent), tangent)


func test_optional_camt_preserves_existing_data_and_round_trips_json():
	var absent = {"ModMapData": {"other_mod": {"keep": true}}}
	Utils.store_path_color_for_camt(absent, 12, Color.red)
	assert_eq_deep(absent.ModMapData, {"other_mod": {"keep": true}})
	var original = {"shader_type": "custom", "has_edge_blur": true, "extra": 42}
	var global_ref = {"ModMapData": {"UchideshiNodeData": {"data": {"node-id-12": original, "node-id-99": {"keep": true}}}}}
	Utils.store_path_color_for_camt(global_ref, 12, Color(0.2, 0.4, 0.6, 0.8))
	var restored = JSON.parse(JSON.print(global_ref.ModMapData)).result.UchideshiNodeData.data
	assert_eq(restored["node-id-12"].colour, "cc336699")
	assert_eq(restored["node-id-12"].type, "paths")
	assert_eq(restored["node-id-12"].shader_type, "custom")
	assert_true(restored["node-id-12"].has_edge_blur)
	assert_eq(restored["node-id-12"].extra, 42.0)
	assert_eq(restored["node-id-12"].start_point, 0.0)
	assert_false(restored["node-id-12"].path_flip_vertical)
	assert_eq_deep(restored["node-id-99"], {"keep": true})
	assert_false(original.has("colour"), "Updating CAMT replaces rather than mutates a shared record")
	global_ref.ModMapData.UchideshiNodeData = {}
	Utils.store_path_color_for_camt(global_ref, 7, Color.white)
	assert_eq_deep(global_ref.ModMapData.UchideshiNodeData, {})
	Utils.store_path_color_for_camt(global_ref, 7, Color.red)
	assert_eq(global_ref.ModMapData.UchideshiNodeData.data["node-id-7"].shader_type, "none")
	Utils.store_path_color_for_camt(global_ref, 7, Color.white)
	assert_eq(global_ref.ModMapData.UchideshiNodeData.data["node-id-7"].colour, "ffffffff", "Existing tint must reset to white")
