extends Node2D

# BuildingPlanner - Dungeondraft Mod
# Geometry preview and input overlay. Added to WorldUI so it receives input
# while the BuildingPlanner tool is the active Dungeondraft tool.
#
# Intercepts left mouse clicks on the world canvas for all builder modes
# and forwards the world-space click position to BuildingPlannerTool.

# Injected by BuildingPlannerTool after instantiation
var tool = null

const CLASS_NAME = "BuildingPlannerOverlay"
const Utils = preload("../utils/BuildingPlannerUtils.gd")
const TexturePreview = preload("BuildingPlannerTexturePreview.gd")
var _texture_preview = null
var _room_previews = []
var _room_preview_state = []
# ponytail: synchronous marker scans; use indexed query candidates if dense maps stall.
const QUERY_INTERVAL = 1.0 / 15.0
var preview = {}
var _context = []
var _revision = -1
var _style = []
var _position = Vector2(INF, INF)
var _elapsed = 0.0
var _zone_hash = ""
var _style_hash = 0
var _geometry_style = []
var _prepared_points = []
var _prepared_contours = []
var _prepared_sources = []
var _geometry_reason = ""
var _resolved = {}
var _resolve_reason = ""
var _font = null
var _draw_state = []
const MAX_SOURCE_DASHES = 2048
var _source_dashes_left = MAX_SOURCE_DASHES
var _source_bounds = null

class PreviewDiagnostic:
	extends Reference
	var reason = ""
	func error(message):
		reason = message.replace("BuildingPlanner: ", "")
	func warn(message):
		error(message)

func clear_preview() -> void:
	for renderer in _room_previews: renderer.clear_preview()
	_room_preview_state = []
	if preview.empty() and _context.empty(): return
	if is_instance_valid(_texture_preview):
		_texture_preview.clear_preview()
	preview = {}
	_context = []
	_revision = -1
	_style = []
	_zone_hash = ""
	_style_hash = 0
	_geometry_style = []
	_prepared_points = []
	_prepared_contours = []
	_prepared_sources = []
	_geometry_reason = ""
	_resolved = {}
	_resolve_reason = ""
	_position = Vector2(INF, INF)
	_elapsed = QUERY_INTERVAL
	update()

func refresh_room_preview(room, position: Vector2, state: Dictionary) -> void:
	var geometry = room.get_preview_geometry(position, state)
	if geometry.empty():
		clear_preview()
		return
	var fill_settings = room._pattern_fill.get_settings()
	var path = room.active_outline_mode == room.OutlineMode.PATH
	var outline_settings = (room._path_builder if path else room._wall_builder).get_settings()
	var key = [geometry, fill_settings, outline_settings, path]
	if key == _room_preview_state: return
	if not preview.empty() or not _context.empty(): clear_preview()
	for j in range(geometry.size() * 2, _room_previews.size()):
		_room_previews[j].clear_preview()
	_room_preview_state = key
	for i in range(geometry.size()):
		while _room_previews.size() < (i + 1) * 2:
			var renderer = TexturePreview.new()
			add_child(renderer)
			_room_previews.append(renderer)
		var marker = geometry[i]
		var fill = marker.marker_type == "Shape" or marker.get("closed", false)
		var points = marker.polygon if marker.marker_type == "Shape" else marker.outline_points
		var outline = Utils.region_outline({"polygon": points, "source_polygons": [points]}) if fill else {"points": points, "closed": false}
		var contours = Utils.prepare_outlines(outline, outline_settings)
		if contours.empty():
			_room_previews[i * 2].clear_preview()
			_room_previews[i * 2 + 1].clear_preview()
			continue
		if fill:
			_room_previews[i * 2].sync_preview({"points": points, "fill": true, "closed": true}, fill_settings, false, room._parent_mod)
		else:
			_room_previews[i * 2].clear_preview()
		if path:
			for j in range(contours.size()):
				contours[j] = Utils.path_preview_points(contours[j], fill, outline_settings.active_smoothness)
		_room_previews[i * 2 + 1].sync_preview({"points": contours[0], "contours": contours, "closed": fill, "fill": false}, outline_settings, path, room._parent_mod)

func _unavailable(reason: String) -> void:
	if preview.size() == 1 and preview.get("reason") == reason: return
	clear_preview()
	preview = {"reason": reason}
	update()

## Geometry queries are bounded during motion; context/style changes are immediate.
func refresh_preview(delta: float, feature, fill: bool, path: bool) -> void:
	if not feature or not feature.has_method("get_settings"):
		clear_preview()
		return
	var api = tool._gl_api
	if not is_instance_valid(api) or not api.has_method("is_ready") or not api.is_ready():
		_unavailable("GuidesLines is not ready.")
		return
	if not api.has_method("get_geometry_revision") or not api.has_method("get_build_preview_target"):
		_unavailable("Hover preview requires updated GuidesLines.")
		return
	var world = tool.cached_world
	var revision = api.get_geometry_revision()
	var revision_changed = revision != _revision
	_revision = revision
	var context = [api, world, world.Level, tool._active_mode]
	var changed = context != _context
	if changed:
		_zone_hash = ""
		_resolved = {}
	_context = context
	var position = tool.cached_worldui.MousePosition
	var moved = position != _position
	_elapsed += max(delta, 0.0)
	if not changed and not revision_changed and not moved and _resolved.empty():
		_redraw_if_camera_changed()
		return
	var settings = feature.get_settings()
	var style = settings.values()
	var style_hash = hash(style)
	# Exact equality also guards against a 32-bit parameter hash collision.
	var style_changed = style_hash != _style_hash or style != _style
	if not changed and not revision_changed and not moved and not style_changed:
		_redraw_if_camera_changed()
		return
	if moved and not changed and not revision_changed and not style_changed and _elapsed < QUERY_INTERVAL:
		_redraw_if_camera_changed()
		return
	var zone_changed = changed
	if changed or revision_changed or moved:
		var diagnostic = PreviewDiagnostic.new()
		var target = api.get_build_preview_target(position, not fill, _zone_hash)
		_elapsed = 0.0
		if not target is Dictionary or not target.get("zone_hash") is String:
			diagnostic.error("BuildingPlanner: invalid preview target response.")
			target = {"zone_hash": ""}
		zone_changed = changed or target.zone_hash != _zone_hash or diagnostic.reason != "" or (target.zone_hash == "" and diagnostic.reason != _resolve_reason)
		if zone_changed:
			_zone_hash = target.zone_hash
			_resolved = {}
			if _zone_hash != "":
				if target.get("kind") == "Fill":
					var region = Utils.parse_fill_region(target.get("fill"), diagnostic)
					if not region.empty():
						_resolved = {"points": region.polygon, "closed": true, "source_polygons": region.source_polygons, "polygon_validated": true} if fill else Utils.region_outline(region)
				elif target.get("kind") == "Path" and not fill:
					_resolved = Utils.parse_path_outline(target.get("marker"), diagnostic)
				if _resolved.empty() and diagnostic.reason == "":
					diagnostic.error("BuildingPlanner: invalid preview zone geometry.")
			_resolve_reason = diagnostic.reason
	_position = position
	if not zone_changed and not style_changed:
		_redraw_if_camera_changed()
		return
	_style = style
	_style_hash = style_hash
	var geometry_style = [settings.get("active_offset", 0.0), settings.get("active_reverse_direction", false), settings.get("active_smoothness", 0.0)]
	if zone_changed or geometry_style != _geometry_style:
		_geometry_style = geometry_style
		_prepared_points = []
		_prepared_contours = []
		var geometry_diagnostic = PreviewDiagnostic.new()
		geometry_diagnostic.reason = _resolve_reason
		if not _resolved.empty():
			_prepared_contours = [_resolved.points] if fill else Utils.prepare_outlines(_resolved, settings, geometry_diagnostic)
			if path:
				for i in range(_prepared_contours.size()):
					_prepared_contours[i] = Utils.path_preview_points(_prepared_contours[i], _resolved.closed, settings.active_smoothness)
			if not _prepared_contours.empty(): _prepared_points = _prepared_contours[0]
		_geometry_reason = geometry_diagnostic.reason
		_prepared_sources = []
		for source in _resolved.get("source_polygons", []):
			var sources = Utils.split_outline(source) if not fill and _resolved.has("contours") else [source]
			for boundary in sources:
				var same = false
				for contour in _prepared_contours:
					if _same_centerline(boundary, contour, _resolved.closed): same = true
				if not same:
					_prepared_sources.append(boundary)
	preview = {"reason": _geometry_reason, "zone_hash": _zone_hash, "parameter_hash": style_hash}
	if not _resolved.empty():
		preview.points = _prepared_points
		preview.contours = _prepared_contours
		preview.closed = _resolved.closed
		preview.fill = fill
		preview.sources = _prepared_sources
		preview.color = settings.active_color
		if not settings.active_texture is Texture:
			preview.reason = "Select a valid texture before building."
	if not is_instance_valid(_texture_preview):
		_texture_preview = TexturePreview.new()
		add_child(_texture_preview)
	_texture_preview.sync_preview(preview, settings, path, feature.get("_parent_mod"))
	_redraw_if_camera_changed(true)

## Direction changes and subdivision of a straight Path do not move its source.
func _same_centerline(source: Array, points: Array, closed: bool) -> bool:
	if source.size() == points.size() and (source == points or Utils.reverse_outline(source, closed) == points): return true
	if not closed and source.size() == 2 and points.size() >= 2:
		if not ((source[0] == points[0] and source[1] == points[-1]) or (source[1] == points[0] and source[0] == points[-1])): return false
		for point in points:
			if point.distance_squared_to(Geometry.get_closest_point_to_segment_2d(point, source[0], source[1])) > 0.000001: return false
		return true
	return false

func _redraw_if_camera_changed(force: bool = false) -> void:
	if not is_inside_tree():
		return
	var state = [get_canvas_transform(), tool.cached_worldui.MousePosition if preview.get("reason", "") != "" else Vector2.ZERO]
	if force or state != _draw_state:
		_draw_state = state
		update()

func _draw() -> void:
	if preview.empty() or not tool or not tool.is_enabled or not tool.is_mouse_on_canvas():
		return
	var inverse = get_canvas_transform().affine_inverse()
	var zoom = inverse.basis_xform(Vector2.RIGHT).length()
	var points = preview.get("points", [])
	var closed = preview.get("closed", false)
	var color = Color(1.0, 0.3, 0.2) if preview.get("reason", "") != "" else preview.get("color", Color.white)
	color.a = 0.95
	_source_dashes_left = MAX_SOURCE_DASHES
	var viewport = get_viewport_rect()
	_source_bounds = Rect2(inverse.xform(viewport.position), Vector2.ZERO)
	for corner in [Vector2(viewport.end.x, viewport.position.y), viewport.end, Vector2(viewport.position.x, viewport.end.y)]:
		_source_bounds = _source_bounds.expand(inverse.xform(corner))
	for source in preview.get("sources", []):
		_draw_source(source, closed, zoom)
	for contour in preview.get("contours", [points]):
		points = contour
		if points.size() < 2: continue
		if preview.get("fill", false) and not (is_instance_valid(_texture_preview) and _texture_preview.visible):
			draw_colored_polygon(PoolVector2Array(points), Color(color.r, color.g, color.b, 0.22))
		var line = points.duplicate()
		if closed and line[-1] != line[0]:
			line.append(line[0])
		draw_polyline(PoolVector2Array(line), color, 2.0 * zoom, true)
		if not preview.get("fill", false):
			_draw_direction(points, zoom, color)
			if not closed:
				draw_circle(points[0], 4.0 * zoom, Color(0.2, 1.0, 0.4))
				draw_circle(points[-1], 4.0 * zoom, Color(1.0, 0.5, 0.15))
	var reason = preview.get("reason", "")
	if reason != "" and _font:
		draw_set_transform(tool.cached_worldui.MousePosition + Vector2(16, 24) * zoom, 0.0, Vector2.ONE * zoom)
		draw_rect(Rect2(Vector2(-5, -_font.get_ascent() - 4), _font.get_string_size(reason) + Vector2(10, 8)), Color(0.08, 0.08, 0.08, 0.9))
		draw_string(_font, Vector2.ZERO, reason, Color.white)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_source(points: Array, closed: bool, zoom: float) -> void:
	var edges = []
	var cost = 0
	for i in range(points.size() if closed else points.size() - 1):
		var a = points[i]
		var b = points[(i + 1) % points.size()]
		if _source_bounds != null and not Rect2(a, Vector2.ZERO).expand(b).grow(zoom).intersects(_source_bounds, true):
			continue
		var length = a.distance_to(b)
		var step = max(12.0 * zoom, length / 256.0)
		var count = int(ceil(length / step))
		cost += count
		edges.append([a, b, length, step, count])
	if cost > _source_dashes_left:
		# ponytail: bound retained draw commands; dense sources use solid blue. Use shader dashes for unlimited detail.
		for edge in edges:
			draw_line(edge[0], edge[1], Color(0.3, 0.8, 1.0, 0.65), zoom, true)
		return
	_source_dashes_left -= cost
	for edge in edges:
		var direction = (edge[1] - edge[0]) / edge[2] if edge[2] > 0.0 else Vector2.ZERO
		for i in range(edge[4]):
			var a = edge[0]
			var distance = i * edge[3]
			draw_line(a + direction * distance, a + direction * min(distance + edge[3] * 0.5, edge[2]), Color(0.3, 0.8, 1.0, 0.65), zoom, true)

func _draw_direction(points: Array, zoom: float, color: Color) -> void:
	var longest = 0
	for i in range(points.size() - 1):
		if points[i].distance_squared_to(points[i + 1]) > points[longest].distance_squared_to(points[longest + 1]):
			longest = i
	if points[longest].distance_squared_to(points[longest + 1]) < 0.000001:
		return
	var direction = (points[longest + 1] - points[longest]).normalized()
	var center = (points[longest] + points[longest + 1]) * 0.5
	var back = center - direction * 8.0 * zoom
	var side = direction.tangent() * 4.0 * zoom
	draw_polyline(PoolVector2Array([back + side, center, back - side]), color, 2.0 * zoom, true)

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	set_process_input(true)
	if tool and tool.get("tool_panel") is Control and is_instance_valid(tool.tool_panel):
		_font = tool.tool_panel.get_font("font")
	if _font: return
	var control = Control.new()
	_font = control.get_font("font")
	control.free()

# ============================================================================
# INPUT
# ============================================================================

func _input(event: InputEvent) -> void:
	if not tool or not tool.is_enabled:
		return

	if not (event is InputEventMouseButton):
		return

	# Skip if any Dungeondraft window/popup is currently open.
	# _input fires before Control._gui_input, so is_input_handled() is not yet set —
	# we must check visible windows explicitly.
	var editor = tool.parent_mod.Global.Editor
	for window in editor.Windows.values():
		if is_instance_valid(window) and window.visible:
			return

	# Skip if Ctrl is held — reserved for camera zoom.
	if event.control:
		return

	# Canvas input must not consume Control scrolling in the sidebar.
	if not tool.is_mouse_on_canvas():
		return

	# ---- Scroll wheel: Room Builder rotation / scale ----
	if tool._active_mode == tool.Mode.ROOM_BUILDER and event.pressed:
		var direction = 0
		if event.button_index == BUTTON_WHEEL_UP:
			direction = 1
		elif event.button_index == BUTTON_WHEEL_DOWN:
			direction = -1
		if direction != 0:
			tool.handle_room_scroll(direction, event.alt)
			get_tree().set_input_as_handled()
			return

	# ---- Left click — apply canvas boundary guards ----
	if event.button_index != BUTTON_LEFT or not event.pressed:
		return

	var world_pos: Vector2 = tool.cached_worldui.MousePosition

	if tool.handle_canvas_click(world_pos):
		get_tree().set_input_as_handled()
