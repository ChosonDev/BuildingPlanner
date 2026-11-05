extends "res://addons/gut/test.gd"

var mod_root = ProjectSettings.globalize_path("res://").plus_file("..")

class LegacyApi:
	extends Reference
	var previews = 0
	func is_ready():
		return true
	func set_shape_preview(_position, _radius, _angle, _sides, _color):
		previews += 1
	func clear_shape_preview():
		pass
	func place_shape_marker(_position, _radius, _angle, _sides, _color):
		return 1
	func compute_fill_polygon(_coords):
		return {}
	func delete_marker(_id):
		return true


# Narrow public API substitute: readiness, polygon response and preview calls only.
class CapturingLegacyApi:
	extends LegacyApi
	func begin_history_capture():
		return true
	func end_history_capture():
		return []


class MarkerApi:
	extends Reference
	var ready = false
	var result = null
	var queries = 0
	var preview = []
	var clears = 0
	func is_ready():
		return ready
	func get_shape_polygon(_id):
		return {"polygon": [Vector2.ZERO, Vector2(50, 0), Vector2(0, 50)], "marker_id": _id, "marker_type": "Shape"}

	func compute_fill_polygon(_coords):
		queries += 1
		return result
	func set_shape_preview(position, radius, angle, sides, color):
		preview = [position, radius, angle, sides, color]
	func place_shape_marker_plain(_position, _radius, _angle, _sides, _color):
		return 1
	func delete_marker(_id):
		return true
	func begin_history_capture():
		return true
	func end_history_capture():
		return []
	func clear_shape_preview():
		clears += 1


func test_builders_reject_missing_old_and_unready_api_before_map_access():
	for name in ["PatternFill", "WallBuilder", "PathBuilder", "RoofBuilder"]:
		var script = ResourceLoader.load(mod_root.plus_file("scripts/features/" + name + ".gd"))
		var method = "build_at"
		assert_false(script.new(null, null).call(method, Vector2.ZERO), name + ": absent API")
		assert_false(script.new(Reference.new(), null).call(method, Vector2.ZERO), name + ": old API")
		var api = MarkerApi.new()
		assert_false(script.new(api, null).call(method, Vector2.ZERO), name + ": loading map")
		assert_eq(api.queries, 0, "No polygon queries until ready")


func test_builders_reject_invalid_polygon_responses_without_map_objects():
	for name in ["PatternFill", "WallBuilder", "PathBuilder", "RoofBuilder"]:
		var script = ResourceLoader.load(mod_root.plus_file("scripts/features/" + name + ".gd"))
		var method = "build_at"
		var api = MarkerApi.new()
		api.ready = true
		var builder = script.new(api, null, {"Global": {"World": null}})
		var responses = [null, [], {}, {"polygon": []}, {"polygon": null}, {"polygon": "bad"}, {"polygon": [Vector2.ZERO, Vector2.ONE]}, {"polygon": [Vector2.ZERO, Vector2(50, 0), Vector2(INF, 2)]}]
		for response in responses:
			api.result = response
			assert_false(builder.call(method, Vector2(12, 34)), name + ": invalid polygon")
		assert_eq(api.queries, responses.size(), "Each ready request resolves its polygon")


func test_room_preview_applies_overrides_independently_of_guideslines_marker_tab():
	var script = ResourceLoader.load(mod_root.plus_file("scripts/features/RoomBuilder.gd"))
	var api = MarkerApi.new()
	var room = script.new(api, null)
	api.ready = true
	room.adjust_angle(365)
	room.adjust_scale(0.5)
	room.update_preview(Vector2(12, 34), {"ready": true, "active_marker_type": "Shape", "active_shape_radius": 2.0, "active_shape_angle": 90.0, "active_shape_sides": 4, "active_color": Color.red})
	assert_eq_deep(api.preview, [Vector2(12, 34), 3.0, 95.0, 4, Color.red])
	room.adjust_angle(-10)
	assert_eq(room.shape_angle_offset, 355.0)
	room.adjust_angle(360)
	assert_eq(room.shape_angle_offset, 355.0, "Rotation always uses the same positive range")
	room.adjust_scale(-100)
	assert_almost_eq(room.shape_scale_factor, 0.1, 0.0001)
	room.stop_preview()
	room.update_preview(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true, "active_marker_type": "Line"})
	assert_false(api.preview.empty(), "Room uses shape settings even when another marker tab is active")
	room.stop_preview()
	room.stop_preview()
	assert_eq(api.clears, 2, "Idle UI frames clear a preview only once")
	api.preview = []
	room.update_preview(Vector2.ZERO, {})
	assert_eq_deep(api.preview, [])
	room.update_preview(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true, "active_marker_type": "Shape"})
	api.preview = [] # GuidesLines consumes the preview after each draw.
	room.update_preview(Vector2.ZERO, {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true, "active_marker_type": "Shape"})
	assert_false(api.preview.empty(), "Unchanged active preview must still be submitted each frame")
	room.update_preview(Vector2.ZERO, {})
	assert_eq(api.clears, 3, "Readiness loss clears a pending preview")


func test_all_room_modes_fail_safely_without_api():
	var room = ResourceLoader.load(mod_root.plus_file("scripts/features/RoomBuilder.gd")).new(null, null)
	for mode in range(5):
		room.active_sub_mode = mode
		assert_false(room.build_room_at(Vector2.ZERO, {}))


func test_roof_ridge_closes_seam_without_changing_source_polygon():
	var roof = ResourceLoader.load(mod_root.plus_file("scripts/features/RoofBuilder.gd")).new(null, null)
	var polygon = [Vector2.ZERO, Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]
	roof.active_placement_mode = 0
	assert_eq_deep(roof._build_roof_polygon(polygon), polygon + [polygon[0], polygon[1]])
	assert_eq(polygon.size(), 4)
	assert_eq_deep(roof._build_roof_polygon([]), [])


func test_roof_expand_and_inset_have_known_square_bounds():
	var roof = ResourceLoader.load(mod_root.plus_file("scripts/features/RoofBuilder.gd")).new(null, null)
	var polygon = [Vector2.ZERO, Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]
	roof.active_width = 10.0
	for mode in [1, 2]:
		roof.active_placement_mode = mode
		var points = roof._build_roof_polygon(polygon)
		assert_true(points.size() >= 6)
		var bounds = Rect2(points[0], Vector2.ZERO)
		for point in points:
			bounds = bounds.expand(point)
		assert_eq(bounds, Rect2(-10, -10, 120, 120) if mode == 1 else Rect2(10, 10, 80, 80))
		assert_eq(points[-2], points[0])
		assert_eq(points[-1], points[1])

func test_preview_rejects_the_same_invalid_shapes_and_missing_capabilities_as_build():
	var room_script = load(mod_root.plus_file("scripts/features/RoomBuilder.gd"))
	var api = MarkerApi.new()
	api.ready = true
	var room = room_script.new(api, null)
	var valid = {"active_shape_radius": 1.0, "active_shape_angle": 0.0, "active_shape_sides": 6, "ready": true, "active_marker_type": "Shape"}
	for change in [{"active_shape_radius": 0}, {"active_shape_radius": INF}, {"active_shape_angle": NAN}, {"active_shape_sides": 2}, {"active_shape_sides": 3.5}]:
		var state = valid.duplicate()
		for key in change:
			state[key] = change[key]
		room.update_preview(Vector2.ZERO, state)
		assert_true(api.preview.empty())
		assert_false(room.build_room_at(Vector2.ZERO, state))
	room.active_sub_mode = room.SubMode.MERGE # Fake API deliberately lacks merge.
	room.update_preview(Vector2.ZERO, valid)
	assert_true(api.preview.empty())
	room.active_sub_mode = room.SubMode.SINGLE
	room.update_preview(Vector2(INF, 0), valid)
	assert_true(api.preview.empty())
	room.shape_scale_factor = INF
	room.update_preview(Vector2.ZERO, valid)
	assert_true(api.preview.empty())
	var legacy = LegacyApi.new()
	room = room_script.new(legacy, null)
	room.update_preview(Vector2.ZERO, valid)
	assert_eq(legacy.previews, 0, "An API without history capture must not advertise a buildable preview")
	legacy = CapturingLegacyApi.new()
	room = room_script.new(legacy, null)
	room.update_preview(Vector2.ZERO, valid)
	assert_eq(legacy.previews, 0, "Single requires explicit placement without inherited Conform/Wrap modes")

func test_split_inset_roof_chooses_area_instead_of_vertex_count():
	var roof = load(mod_root.plus_file("scripts/features/RoofBuilder.gd")).new(null, null)
	roof.active_placement_mode = 2
	roof.active_width = 15
	var outline = [Vector2(0, 0), Vector2(200, 0), Vector2(200, 90), Vector2(260, 90), Vector2(260, 80), Vector2(280, 60), Vector2(300, 60), Vector2(320, 80), Vector2(320, 120), Vector2(300, 140), Vector2(280, 140), Vector2(260, 120), Vector2(260, 110), Vector2(200, 110), Vector2(200, 200), Vector2(0, 200)]
	var contours = Geometry.offset_polygon_2d(PoolVector2Array(outline), -15)
	assert_eq(contours.size(), 2, "Test really splits the footprint")
	var points = roof._build_roof_polygon(outline)
	assert_false(points.empty())
	for point in points:
		assert_true(point.x <= 200, "Keep the large rectangular lobe")


func test_fill_contract_errors_are_distinct_from_an_ordinary_miss():
	var Utils = ResourceLoader.load(mod_root.plus_file("scripts/utils/BuildingPlannerUtils.gd"))
	var fixture = load("res://unit/test_rooms.gd")
	var logger = fixture.DiagnosticLogger.new()
	var api = MarkerApi.new()
	api.ready = true
	assert_eq_deep(Utils.resolve_fill_polygon(api, Vector2.ZERO, logger), [])
	assert_true(logger.errors.empty(), "Null means no Shape under the click")
	for response in [[], {}, {"polygon": [Vector2.ZERO, Vector2.ONE]}]:
		api.result = response
		assert_eq_deep(Utils.resolve_fill_polygon(api, Vector2.ZERO, logger), [])
	assert_eq(logger.errors.size(), 3)
	var script = ResourceLoader.load(mod_root.plus_file("scripts/features/PatternFill.gd"))
	var builder = script.new(api, logger)
	assert_null(builder._create_shape([Vector2.ZERO, Vector2(50, 0), Vector2(0, 50)]))
	assert_eq(logger.errors.size(), 4, "Standalone No texture is a placement error")


func test_explicit_settings_cover_active_fields_without_aliasing_builder_state():
	for name in ["PatternFill", "WallBuilder", "PathBuilder"]:
		var builder = load(mod_root.plus_file("scripts/features/" + name + ".gd")).new(null, null)
		var settings = builder.get_settings()
		for property in builder.get_property_list():
			if property.name.begins_with("active_"):
				assert_true(settings.has(property.name), name + ": " + property.name)
				assert_eq(settings[property.name], builder.get(property.name))
		settings.active_color = Color.red
		assert_eq(builder.active_color, Color.white)
