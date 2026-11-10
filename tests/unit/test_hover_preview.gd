extends "res://addons/gut/test.gd"

var root = ProjectSettings.globalize_path("res://").plus_file("..")
var Overlay = load(root.plus_file("scripts/overlay/BuildingPlannerOverlay.gd"))
var Utils = load(root.plus_file("scripts/utils/BuildingPlannerUtils.gd"))
var rooms = load("res://unit/test_rooms.gd")
var paths = load("res://unit/test_path_creation.gd")
const SQUARE = [Vector2.ZERO, Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]

class DrawTool:
	extends Reference
	var is_enabled = true
	var on_canvas = true
	var cached_worldui = {"MousePosition": Vector2(20, 20)}
	var tool_panel = null
	func is_mouse_on_canvas(): return on_canvas

func test_overlay_font_uses_attached_panel_theme_with_engine_fallback():
	var panel = autofree(Control.new())
	var themed_font = DynamicFont.new()
	panel.theme = Theme.new()
	panel.theme.default_font = themed_font
	add_child(panel)
	var tool = DrawTool.new()
	tool.tool_panel = panel
	var painter = autofree(Overlay.new())
	painter.tool = tool
	add_child(painter)
	assert_true(painter._font == themed_font)
	var fallback = autofree(Overlay.new())
	add_child(fallback)
	assert_not_null(fallback._font)

func test_hover_preview_real_drawing_preserves_holes_camera_transform_and_clears():
	var view = autofree(Viewport.new())
	view.size = Vector2(256, 256)
	view.disable_3d = true
	view.world_2d = World2D.new()
	view.transparent_bg = true
	view.render_target_update_mode = Viewport.UPDATE_ALWAYS
	var painter = Overlay.new()
	var tool = DrawTool.new()
	painter.tool = tool
	view.add_child(painter)
	add_child(view)
	# Same paired zero-width bridge representation returned by GuidesLines Fill.
	var polygon = [Vector2.ZERO, Vector2(30, 30), Vector2(30, 70), Vector2(70, 70), Vector2(70, 30), Vector2(30, 30), Vector2.ZERO, Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]
	painter.preview = {"points": polygon, "closed": true, "fill": true, "color": Color.white}
	for scale in [0.5, 1.0, 2.0]:
		var transform = Transform2D(Vector2(scale, 0), Vector2(0, scale), Vector2(20, 25))
		view.canvas_transform = transform
		painter.update()
		yield(VisualServer, "frame_post_draw")
		yield(VisualServer, "frame_post_draw")
		var image = view.get_texture().get_data()
		image.flip_y()
		image.lock()
		var inside = transform.xform(Vector2(15, 50))
		var hole = transform.xform(Vector2(50, 50))
		assert_almost_eq(image.get_pixelv(inside).a, 0.22, 0.02)
		assert_eq(image.get_pixelv(hole).a, 0.0, "Hole must stay transparent at every zoom")
		image.unlock()
	view.canvas_transform = Transform2D.IDENTITY
	painter.preview = {"points": [Vector2(20, 100), Vector2(180, 100)], "closed": false, "fill": false, "sources": [[Vector2(20, 80), Vector2(180, 80)]], "color": Color.white}
	painter.update()
	yield(VisualServer, "frame_post_draw")
	yield(VisualServer, "frame_post_draw")
	var path_image = view.get_texture().get_data()
	path_image.flip_y()
	path_image.lock()
	assert_gt(path_image.get_pixel(20, 100).g, 0.9, "Open start is green")
	assert_gt(path_image.get_pixel(180, 100).r, 0.9, "Open end is orange")
	assert_gt(path_image.get_pixel(22, 80).b, 0.6, "Different source is blue and dashed")
	assert_eq(path_image.get_pixel(29, 80).a, 0.0, "Source dash gap remains visible")
	path_image.unlock()
	tool.on_canvas = false
	painter.update()
	yield(VisualServer, "frame_post_draw")
	yield(VisualServer, "frame_post_draw")
	var cleared = view.get_texture().get_data()
	cleared.flip_y()
	cleared.lock()
	assert_eq(cleared.get_pixel(20, 100).a, 0.0)
	cleared.unlock()

func test_hover_preview_canvas_dialog_panel_mode_level_and_map_lifecycle():
	var f = setup_preview()
	var fixture = load("res://unit/test_tool_lifecycle.gd")
	var editor_script = GDScript.new()
	editor_script.source_code = "extends CanvasLayer\nvar Windows = {}\nvar IsSnapping = false\n"
	assert_eq(editor_script.reload(), OK)
	var editor = autofree(editor_script.new())
	add_child(editor)
	var parent = editor
	for name in ["VPartition", "Panels", "HSplit"]:
		var node = Control.new()
		node.name = name
		parent.add_child(node)
		parent = node
	var content_script = GDScript.new()
	content_script.source_code = "extends Control\nvar test_mouse = Vector2.ZERO\nfunc get_local_mouse_position():\n\treturn get_global_transform_with_canvas().affine_inverse().xform(test_mouse)\n"
	assert_eq(content_script.reload(), OK)
	var content = content_script.new()
	content.name = "Content"
	content.rect_position = Vector2(300, 50)
	content.rect_size = Vector2(700, 400)
	parent.add_child(content)
	var canvas = autofree(fixture.WorldCanvas.new())
	add_child(canvas)
	var tool = load(root.plus_file("scripts/tool/BuildingPlannerTool.gd")).new({"Global": {"Editor": editor}})
	tool.cached_worldui = canvas
	tool.cached_world = f.world
	tool._pattern_fill = f.feature
	tool._gl_api = f.api
	tool.is_enabled = true
	tool._overlay = f.overlay
	f.overlay.tool = tool
	canvas.add_child(f.overlay)
	for scale in [1.0, 1.5, 2.0]:
		content.rect_scale = Vector2.ONE * scale
		content.test_mouse = content.get_global_transform_with_canvas().xform(Vector2(100, 100))
		tool.Update(1.0)
		assert_true(f.overlay.preview.has("points"))
		content.test_mouse = content.get_global_transform_with_canvas().xform(Vector2(-1, 100))
		tool.Update(0.0)
		assert_true(f.overlay.preview.empty(), "Sidebar clears the hover overlay")
		assert_false(f.overlay._texture_preview.visible, "Sidebar also hides retained texture nodes")
	content.test_mouse = content.get_global_transform_with_canvas().xform(Vector2(100, 100))
	var panel = content_script.new()
	panel.rect_position = Vector2(350, 70)
	panel.rect_size = Vector2(200, 200)
	editor.add_child(panel)
	tool.tool_panel = panel
	panel.test_mouse = panel.get_global_transform_with_canvas().xform(Vector2(20, 20))
	tool.Update(0.0)
	assert_true(f.overlay.preview.empty(), "Panel overlapping Content must clear preview")
	panel.hide()
	tool.Update(0.0)
	assert_true(f.overlay.preview.has("points"), "A hidden panel must not block the canvas")
	tool.tool_panel = null
	var dialog = WindowDialog.new()
	editor.add_child(dialog)
	editor.Windows["test"] = dialog
	dialog.show()
	tool.Update(0.0)
	assert_true(f.overlay.preview.empty(), "A visible host dialog clears preview")
	assert_false(f.overlay._texture_preview.visible)
	dialog.hide()
	tool.Update(0.0)
	assert_true(f.overlay.preview.has("points"))
	var popup = Popup.new()
	editor.add_child(popup)
	popup.popup(Rect2(10, 10, 100, 100))
	yield(get_tree(), "idle_frame")
	assert_true(canvas.get_viewport().gui_has_modal_stack())
	tool.Update(0.0)
	assert_true(f.overlay.preview.empty(), "Unregistered modal popups also hide preview")
	popup.hide()
	yield(get_tree(), "idle_frame")
	tool.Update(0.0)
	assert_true(f.overlay.preview.has("points"))
	tool.cached_world.Level = {"PatternShapes": null}
	var queries = f.api.target_queries
	tool.Update(0.0)
	assert_gt(f.api.target_queries, queries, "Level changes bypass the throttle")
	tool._room_builder = fixture.Preview.new()
	tool._set_mode(tool.Mode.ROOM_BUILDER)
	assert_true(f.overlay.preview.empty())
	assert_false(f.overlay._texture_preview.visible, "Room does not inherit the textured hover preview")
	tool.Update(0.0)
	assert_false(tool._room_builder.hidden, "Room owns the only preview in Room mode")
	tool._set_mode(tool.Mode.PATTERN_FILL)
	assert_true(tool._room_builder.hidden)
	tool.Update(0.0)
	canvas.IsInsideBounds = false
	tool.Update(0.0)
	assert_true(f.overlay.preview.empty(), "Leaving the map clears the overlay")
	tool._room_builder = null # Narrow lifecycle double has no registry.
	tool.set_world_references(null, null)
	assert_null(tool._overlay)
	assert_null(f.overlay.get_parent(), "Map change detaches the old overlay immediately")
	tool.shutdown()

class Api:
	extends Reference
	var revision = 0
	var unrelated_revision = 0
	var ready = true
	var queries = 0
	var nearest_queries = 0
	var noisy_queries = 0
	var nearest = null
	var polygon = SQUARE.duplicate()
	var sources = [SQUARE.duplicate()]
	var target_queries = 0
	var _cached_revision = -1
	var _regions = []
	func is_ready(): return ready
	func get_geometry_revision(): return revision + unrelated_revision
	func get_build_preview_target(coords, outline = false, known = ""):
		target_queries += 1
		if _cached_revision != revision:
			_regions.clear()
			_cached_revision = revision
		var marker = find_nearest_marker_by_geometry_quiet(coords, 100.0) if outline else null
		if marker is Dictionary and marker.get("marker_type") == "Path":
			var path_key = var2bytes([revision, marker]).hex_encode().sha256_text()
			return {"zone_hash": path_key} if path_key == known else {"zone_hash": path_key, "kind": "Path", "marker": marker}
		for entry in _regions:
			if entry.fill.polygon.size() >= 3 and Geometry.is_point_in_polygon(coords, PoolVector2Array(entry.fill.polygon)):
				return {"zone_hash": entry.zone_hash} if entry.zone_hash == known else entry.duplicate(true)
		var fill = compute_fill_polygon_quiet(coords)
		if fill == null: return {"zone_hash": ""}
		var key = var2bytes([revision, fill]).hex_encode().sha256_text()
		var entry = {"zone_hash": key, "kind": "Fill", "fill": fill}
		_regions.append(entry)
		return entry.duplicate(true)
	func compute_fill_polygon_quiet(_coords):
		queries += 1
		return null if polygon.empty() else {"polygon": polygon, "source_polygons": sources}
	func find_nearest_marker_by_geometry_quiet(_coords, _radius):
		nearest_queries += 1
		return nearest
	func compute_fill_polygon(coords):
		noisy_queries += 1
		return compute_fill_polygon_quiet(coords)
	func find_nearest_marker_by_geometry(coords, radius):
		noisy_queries += 1
		return find_nearest_marker_by_geometry_quiet(coords, radius)

func setup_preview(name = "PatternFill"):
	var api = Api.new()
	var walls = autofree(rooms.NativeContainer.new())
	var fills = autofree(rooms.NativeContainer.new())
	var pathways = autofree(paths.Pathways.new())
	var history = paths.HistoryApi.new()
	var world = {"Level": {"Walls": walls, "PatternShapes": fills, "Pathways": pathways}}
	var parent = {"Global": {"World": world, "API": {"HistoryApi": history}, "ModMapData": {}}}
	var feature = load(root.plus_file("scripts/features/" + name + ".gd")).new(api, null, parent)
	feature.active_texture = GradientTexture.new()
	var overlay = autofree(Overlay.new())
	overlay.tool = {"_gl_api": api, "cached_world": world, "_active_mode": name, "cached_worldui": {"MousePosition": Vector2(20, 20)}}
	return {"api": api, "feature": feature, "overlay": overlay, "world": world, "history": history}

func refresh(f, delta = 1.0):
	f.overlay.refresh_preview(delta, f.feature, f.feature.get_script().resource_path.ends_with("PatternFill.gd"), f.feature.get_script().resource_path.ends_with("PathBuilder.gd"))

class SettingsProbe:
	extends Reference
	var calls = 0
	var feature
	var _parent_mod = null
	func get_settings():
		calls += 1
		return feature.get_settings()

func test_hover_idle_empty_target_skips_settings_and_style_changes_reuse_source_filter():
	var f = setup_preview()
	var probe = SettingsProbe.new()
	probe.feature = f.feature
	f.api.polygon = []
	f.overlay.refresh_preview(1.0, probe, true, false)
	for _frame in range(30): f.overlay.refresh_preview(0.016, probe, true, false)
	assert_eq(probe.calls, 1, "Stationary misses do not allocate settings every frame")
	f.api.polygon = SQUARE.duplicate()
	f.api.revision += 1
	f.overlay.refresh_preview(0.0, probe, true, false)
	assert_eq(probe.calls, 2)
	# Probe the cached array: visual-only updates must reuse it; geometry must rebuild it.
	f.overlay._prepared_sources.append([Vector2(-1, -1), Vector2(-2, -2)])
	f.feature.active_color = Color.blue
	f.overlay.refresh_preview(0.0, probe, true, false)
	assert_eq(f.overlay.preview.sources.size(), 1)
	f.api.revision += 1
	f.api.polygon = [Vector2.ZERO, Vector2(110, 0), Vector2(110, 110), Vector2(0, 110)]
	f.overlay.refresh_preview(0.0, probe, true, false)
	assert_eq(f.overlay.preview.sources, [SQUARE])

class CountingRenderer:
	extends Node2D
	var builds = 0
	func clear_preview(): hide()
	func sync_preview(_preview, _settings, _path, _parent):
		builds += 1
		show()

func test_hover_preview_zone_and_parameter_hashes_prevent_render_rebuilds():
	for mode in ["PatternFill", "WallBuilder"]:
		var f = setup_preview(mode)
		var renderer = CountingRenderer.new()
		f.overlay.add_child(renderer)
		f.overlay._texture_preview = renderer
		refresh(f)
		var zone = f.overlay.preview.zone_hash
		var parameters = f.overlay.preview.parameter_hash
		for _i in range(30):
			f.overlay.tool.cached_worldui.MousePosition += Vector2(0.1, 0)
			refresh(f, 0.1)
		assert_eq(renderer.builds, 1, "Pointer movement must not rebuild materials/meshes in the same zone")
		assert_eq(f.api.queries, 1, "The target protocol also avoids repeated clipping")
		assert_eq(f.api.target_queries, 31)
		f.feature.active_color = Color.blue
		refresh(f, 0.0)
		assert_eq(renderer.builds, 2)
		assert_eq(f.overlay.preview.zone_hash, zone)
		assert_ne(f.overlay.preview.parameter_hash, parameters)
		f.api.unrelated_revision += 1
		refresh(f, 0.0)
		assert_eq(renderer.builds, 2, "An unrelated marker mutation does not invalidate this zone's mesh")
		f.api.revision += 1
		refresh(f, 0.0)
		assert_eq(renderer.builds, 3)
		assert_ne(f.overlay.preview.zone_hash, zone)

func test_hover_preview_source_dashes_cull_offscreen_edges_and_bound_retained_commands():
	var probe_script = GDScript.new()
	probe_script.source_code = 'extends "' + root.plus_file("scripts/overlay/BuildingPlannerOverlay.gd") + '"\nvar dashes = 0\nvar outlines = 0\nfunc draw_line(_a, _b, _color, _width = 1.0, _aa = false):\n\tdashes += 1\nfunc draw_polyline(_points, _color, _width = 1.0, _aa = false):\n\toutlines += 1\n'
	assert_eq(probe_script.reload(), OK)
	var probe = autofree(probe_script.new())
	var points = []
	for i in range(64): points.append(Vector2(cos(TAU * i / 64), sin(TAU * i / 64)) * 1000000)
	probe._source_bounds = Rect2(-100, -100, 200, 200)
	probe._draw_source(points, true, 0.01)
	assert_eq(probe.dashes, 0)
	assert_eq(probe.outlines, 0)
	probe._source_bounds = null
	for _i in range(6): probe._draw_source(points, true, 0.01)
	assert_eq(probe.dashes, 6 * 64, "Dense rings use one solid command per visible edge")
	assert_eq(probe.outlines, 0, "Do not redraw the full uncropped source as a polyline")
	probe.dashes = 0
	probe._source_bounds = Rect2(999000, -1000, 2000, 2000)
	probe._source_dashes_left = 0
	probe._draw_source(points, true, 0.01)
	assert_eq(probe.dashes, 2, "The solid fallback also omits all offscreen edges")

func test_hover_preview_reuses_region_and_style_changes_without_map_mutations():
	var f = setup_preview()
	refresh(f)
	assert_eq_deep(f.overlay.preview.points, SQUARE)
	for i in range(20):
		f.overlay.tool.cached_worldui.MousePosition += Vector2(1, 0)
		refresh(f)
	assert_eq(f.api.queries, 1, "Motion inside the same boolean region reuses its polygon")
	f.feature.active_color = Color.blue
	refresh(f, 0.0)
	assert_eq(f.overlay.preview.color, Color.blue, "Stationary style changes update immediately")
	f.feature.active_texture = null
	refresh(f, 0.0)
	assert_true(f.overlay.preview.reason.find("texture") >= 0)
	assert_eq(f.api.queries, 1)
	assert_eq(f.api.noisy_queries, 0)
	assert_false(f.feature.build_at(Vector2(20, 20)), "Click rechecks a texture removed after preview")
	assert_eq(f.history.records.size(), 0)
	for container in f.world.Level.values(): assert_eq(container.get_child_count(), 0)

func test_hover_preview_requeries_edits_deletion_level_and_disconnected_boolean_regions():
	var f = setup_preview()
	refresh(f)
	f.api.polygon = [Vector2(60, 0), Vector2(100, 0), Vector2(100, 100), Vector2(60, 100)]
	f.overlay.tool.cached_worldui.MousePosition = Vector2(80, 20)
	f.api.revision += 1
	refresh(f, 0.0)
	assert_eq_deep(f.overlay.preview.points, f.api.polygon)
	assert_eq_deep(f.overlay.preview.sources, [SQUARE])
	f.api.polygon = [Vector2.ZERO, Vector2(40, 0), Vector2(40, 100), Vector2(0, 100)]
	f.overlay.tool.cached_worldui.MousePosition = Vector2(20, 20)
	refresh(f)
	assert_eq_deep(f.overlay.preview.points, f.api.polygon)
	f.api.polygon = []
	f.api.revision += 1
	refresh(f, 0.0)
	assert_false(f.overlay.preview.has("points"), "Deletion clears stale geometry immediately")
	f.api.polygon = SQUARE.duplicate()
	f.world.Level = {"Walls": null}
	refresh(f, 0.0)
	assert_eq_deep(f.overlay.preview.points, SQUARE)
	f.api.ready = false
	refresh(f, 0.0)
	assert_false(f.overlay.preview.has("points"))
	f.overlay.clear_preview()
	assert_true(f.overlay.preview.empty())

func test_hover_preview_path_priority_throttle_offset_reverse_and_fresh_click():
	for name in ["WallBuilder", "PathBuilder"]:
		var f = setup_preview(name)
		f.api.nearest = {"id": 7, "marker_type": "Path", "marker_points": [[10, 20], [90, 20]], "path_closed": false}
		f.feature.active_reverse_direction = true
		refresh(f)
		assert_eq(f.overlay.preview.points[0], Vector2(90, 20))
		assert_eq(f.overlay.preview.points[-1], Vector2(10, 20))
		assert_false(f.overlay.preview.closed)
		assert_eq(f.api.queries, 0)
		for i in range(10):
			f.overlay.tool.cached_worldui.MousePosition += Vector2(1, 0)
			refresh(f, 0.001)
		assert_eq(f.api.nearest_queries, 1, "Moving pointer is throttled")
		f.feature.active_offset = 10.0
		refresh(f, 0.0)
		assert_true(f.overlay.preview.points.empty())
		assert_true(f.overlay.preview.reason.find("closed") >= 0)
		f.feature.active_offset = 0.0
		refresh(f, 0.0)
		f.api.nearest.marker_points = [[30, 40], [80, 40]] # Change after preview, before update.
		assert_true(f.feature.build_at(Vector2(50, 40)))
		if name == "WallBuilder":
			assert_eq_deep(f.world.Level.Walls.get_child(0).data.points, [Vector2(80, 40), Vector2(30, 40)])
		else:
			assert_eq(str2var(f.world.Level.Pathways.received_data.position), Vector2(80, 40))
		assert_eq(f.history.records.size(), 1)
		f.history.records.clear()

func test_hover_preview_fill_matches_fresh_click_geometry():
	var f = setup_preview()
	refresh(f)
	assert_true(f.feature.build_at(Vector2(20, 20)))
	assert_eq_deep(Array(str2var(f.world.Level.PatternShapes.get_child(0).data.points)), f.overlay.preview.points)
	f.history.records.clear()

func test_hover_preview_source_annotations_ignore_direction_and_straight_subdivision():
	var f = setup_preview("WallBuilder")
	f.feature.active_reverse_direction = true
	refresh(f)
	assert_true(f.overlay.preview.sources.empty(), "Reversing a wall does not move its source")
	f.feature.active_offset = 10.0
	refresh(f, 0.0)
	assert_eq_deep(f.overlay.preview.sources, [SQUARE])
	f = setup_preview("PathBuilder")
	f.api.nearest = {"marker_type": "Path", "id": 1, "marker_points": [[0, 40], [100, 40]], "path_closed": false}
	f.feature.active_reverse_direction = true
	refresh(f)
	assert_true(f.overlay.preview.sources.empty(), "Smoothed straight Paths occupy the same centerline")
	assert_gt(f.overlay.preview.points.size(), 2)

func test_hover_preview_unavailable_state_does_not_redraw_every_frame():
	var script = GDScript.new()
	script.source_code = 'extends "' + root.plus_file("scripts/overlay/BuildingPlannerOverlay.gd") + '"\nvar redraws = 0\nfunc update():\n\tredraws += 1\n'
	assert_eq(script.reload(), OK)
	var overlay = autofree(script.new())
	overlay.tool = {"_gl_api": null}
	var feature = setup_preview().feature
	for _i in range(30): overlay.refresh_preview(0.1, feature, true, false)
	assert_eq(overlay.redraws, 1)
	assert_eq(overlay.preview.reason, "GuidesLines is not ready.")
	overlay.clear_preview()
	assert_eq(overlay.redraws, 2)
	overlay.clear_preview()
	assert_eq(overlay.redraws, 2, "Clearing an already empty overlay is a no-op")

func test_hover_preview_closed_wall_offset_and_reverse_match_native_click_geometry():
	var f = setup_preview("WallBuilder")
	f.feature.active_offset = 10.0
	f.feature.active_reverse_direction = true
	refresh(f)
	assert_true(f.feature.build_at(Vector2(20, 20)))
	assert_eq_deep(f.overlay.preview.points, f.world.Level.Walls.get_child(0).data.points)
	var bounds = Rect2(f.overlay.preview.points[0], Vector2.ZERO)
	for point in f.overlay.preview.points: bounds = bounds.expand(point)
	assert_eq(bounds, Rect2(-10, -10, 120, 120))
	assert_eq_deep(f.api.polygon, SQUARE)
	f.history.records.clear()

func test_hover_preview_smoothing_matches_known_host_chaikin_coordinates_and_seam():
	# Three points and four host iterations: first cut produces Q=(5,0), R=(95,0).
	var points = [Vector2.ZERO, Vector2(100, 0), Vector2(100, 100)]
	var smooth = Utils.path_preview_points(points, false, 0.0)
	assert_eq(smooth.size(), 48)
	assert_eq(smooth[0], points[0])
	assert_eq(smooth[-1], points[-1])
	assert_almost_eq(smooth[1].x, 0.000625, 0.000001)
	assert_eq(smooth[1].y, 0.0)
	var closed = Utils.path_preview_points(points, true, 1.0)
	assert_eq(closed[0], points[0])
	assert_eq(closed[-1], points[0])
	assert_eq(points.size(), 3)

func test_hover_preview_rejects_degenerate_geometry_and_ignores_malformed_source_metadata():
	var region = Utils.parse_fill_region({"polygon": SQUARE.duplicate()})
	region.polygon[0] = Vector2(15, 15)
	assert_eq_deep(region.source_polygons, [SQUARE])
	var f = setup_preview()
	f.api.polygon = [Vector2.ZERO, Vector2.ONE]
	refresh(f)
	var reason = f.overlay.preview.reason
	assert_true(reason.find("invalid fill geometry") >= 0)
	f.feature.active_color = Color.red
	refresh(f, 0.0)
	assert_eq(f.overlay.preview.reason, reason, "Style edits retain the geometry diagnostic")
	f.api.polygon = SQUARE.duplicate()
	for sources in [null, "bad", [null], [[Vector2.ZERO, Vector2.ONE, Vector2(INF, 0)]]]:
		f.api.sources = sources
		f.api.revision += 1
		refresh(f, 0.0)
		assert_eq_deep(f.overlay._resolved.source_polygons, [SQUARE])
		assert_true(f.overlay.preview.sources.empty(), "Identical source geometry needs no extra outline")
	assert_eq(f.api.noisy_queries, 0)
