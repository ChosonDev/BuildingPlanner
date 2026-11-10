extends Reference

# BuildingPlanner - Dungeondraft Mod
# Shared geometry and helper utilities.

const CLASS_NAME = "BuildingPlannerUtils"

# ============================================================================
# LAYER CONSTANTS
# ============================================================================

## Default layer z_index for patterns and paths (User Layer 1).
## Used as fallback when LayerApi is unavailable or the stored layer is absent
## from the current map.
const DEFAULT_LAYER: int = 100

## Reverse a copy, keeping the closed contour's first vertex and explicit seam.
static func reverse_outline(points: Array, closed: bool) -> Array:
	var result = points.duplicate()
	result.invert()
	if closed and result.size() > 1 and points[0] != points[-1]:
		result.push_front(result.pop_back())
	return result

## Offset wall/path centerlines only; room floors and source markers stay unchanged.
static func offset_outline(points: Array, closed: bool, distance, logger = null, polygon_validated: bool = false) -> Array:
	if (typeof(distance) != TYPE_INT and typeof(distance) != TYPE_REAL) or is_nan(distance) or is_inf(distance) or abs(distance) > 8192.0:
		if logger: logger.error("BuildingPlanner: offset must be finite and within -8192..8192 pixels.")
		return []
	if distance == 0.0:
		return points.duplicate() # Preserve existing open/crossing Path behavior at zero.
	if not closed:
		if logger: logger.error("BuildingPlanner: nonzero offset requires a closed outline; use 0 for open Paths or Lines.")
		return []
	var polygon = points.duplicate() if polygon_validated else sanitize_polygon(points)
	if polygon.empty():
		if logger: logger.error("BuildingPlanner: offset requires a nondegenerate polygon.")
		return []
	var reversed = signed_area(polygon) < 0
	if reversed:
		polygon.invert()
	var contours = Geometry.offset_polygon_2d(PoolVector2Array(polygon), distance, Geometry.JOIN_MITER)
	# ponytail: each offset boundary must remain one loop; use region-level topology resolution to support offset splits or merging holes.
	if contours.size() != 1:
		if logger: logger.error("BuildingPlanner: offset collapses or splits the outline; choose a smaller offset or 0.")
		return []
	var result = sanitize_polygon(contours[0])
	if result.empty():
		if logger: logger.error("BuildingPlanner: offset produced invalid geometry.")
		return []
	if (signed_area(result) < 0) != reversed:
		result.invert()
	return result

## Prefer a nearby Path marker; older APIs keep the existing Shape fill behavior.
static func resolve_outline(api, coords: Vector2, logger = null) -> Dictionary:
	if not api or (api.has_method("is_ready") and not api.is_ready()):
		if logger: logger.error("BuildingPlanner: GuidesLinesApi is not ready.")
		return {}
	if is_nan(coords.x) or is_inf(coords.x) or is_nan(coords.y) or is_inf(coords.y):
		if logger: logger.error("BuildingPlanner: outline coordinates must be finite.")
		return {}
	if api.has_method("find_nearest_marker_by_geometry"):
		var marker = api.find_nearest_marker_by_geometry(coords, 100.0)
		if marker != null and typeof(marker) != TYPE_DICTIONARY:
			if logger: logger.error("BuildingPlanner: invalid nearest-marker response from GuidesLinesApi.")
			return {}
		if typeof(marker) == TYPE_DICTIONARY and marker.get("marker_type") == "Path":
			return parse_path_outline(marker, logger)
	var region = resolve_fill_region(api, coords, logger)
	if region.empty():
		return {}
	return region_outline(region)

## Fill bridges repeat vertices exactly. Peel closed walks; two-edge walks are bridges.
## Also separates tangent loops sharing a vertex, without changing the fill polygon.
static func split_outline(polygon: Array) -> Array:
	var contours = []
	var walk = []
	var indices = {}
	for point in polygon + [polygon[0]] if not polygon.empty() else []:
		if indices.has(point):
			var start = indices[point]
			var loop = walk.slice(start, walk.size() - 1)
			if loop.size() >= 3 and abs(signed_area(loop)) > 0.000001:
				contours.append(loop)
			while walk.size() > start + 1:
				indices.erase(walk.pop_back())
		else:
			indices[point] = walk.size()
			walk.append(point)
	return contours

static func region_outline(region: Dictionary) -> Dictionary:
	return {"points": region.polygon, "contours": split_outline(region.polygon), "closed": true, "source_polygons": region.source_polygons, "polygon_validated": true}

## Prepare every boundary before creating anything. Positive offset expands the solid
## region, so holes (opposite winding) shrink. Explicit Path markers stay continuous.
static func prepare_outlines(outline: Dictionary, settings: Dictionary, logger = null) -> Array:
	var contours = outline.get("contours", [outline.points])
	var prepared = []
	var region_area = signed_area(outline.points) if outline.has("contours") else 0.0
	for contour in contours:
		var style = settings.duplicate()
		if outline.has("contours") and signed_area(contour) * region_area < 0:
			style.active_offset = -settings.get("active_offset", 0.0)
		var points = prepare_outline(contour, outline.closed, style, logger, outline.get("polygon_validated", false))
		if points.empty(): return []
		prepared.append(points)
	return prepared

## Validate a cached API Path snapshot once per target revision.
static func parse_path_outline(marker, logger = null) -> Dictionary:
	if not marker is Dictionary or marker.get("marker_type") != "Path":
		if logger: logger.error("BuildingPlanner: invalid Path marker response.")
		return {}
	var id = marker.get("id", -1)
	var closed = marker.get("path_closed")
	var raw = marker.get("marker_points")
	if typeof(id) != TYPE_INT or id < 0 or typeof(closed) != TYPE_BOOL or typeof(raw) != TYPE_ARRAY:
		if logger: logger.error("BuildingPlanner: invalid Path marker data from GuidesLinesApi (id=%s)." % str(marker.get("id")))
		return {}
	var points = []
	for pair in raw:
		# GuideMarker.Save serializes Path vertices as numeric [x, y] pairs.
		if typeof(pair) != TYPE_ARRAY or pair.size() != 2:
			if logger: logger.error("BuildingPlanner: invalid Path marker data from GuidesLinesApi (id=%s)." % str(marker.get("id")))
			return {}
		for coordinate in pair:
			if (typeof(coordinate) != TYPE_INT and typeof(coordinate) != TYPE_REAL) or is_nan(coordinate) or is_inf(coordinate):
				if logger: logger.error("BuildingPlanner: invalid Path marker data from GuidesLinesApi (id=%s)." % str(marker.get("id")))
				return {}
		# Finite Variant doubles may overflow Godot 3 Vector2 components.
		var point = Vector2(pair[0], pair[1])
		if is_nan(point.x) or is_inf(point.x) or is_nan(point.y) or is_inf(point.y):
			if logger: logger.error("BuildingPlanner: invalid Path marker data from GuidesLinesApi (id=%s)." % str(marker.get("id")))
			return {}
		if points.empty() or points[-1] != point:
			points.append(point)
	if closed and points.size() > 1 and points[-1] == points[0]:
		points.pop_back()
	if points.size() < 2:
		if logger: logger.error("BuildingPlanner: invalid Path marker data from GuidesLinesApi (id=%s)." % str(marker.get("id")))
		return {}
	return {"points": points, "closed": closed, "source_polygons": [points.duplicate()], "marker_ids": [id]}

## Resolve and validate the public API response before accessing native map objects.
static func resolve_fill_polygon(api, coords: Vector2, logger = null) -> Array:
	return resolve_fill_region(api, coords, logger).get("polygon", [])

## Keep source outlines and region identity for preview; click uses the same validation.
static func resolve_fill_region(api, coords: Vector2, logger = null) -> Dictionary:
	if not api or not api.has_method("compute_fill_polygon"):
		if logger: logger.error("BuildingPlanner: compute_fill_polygon requires GuidesLines 2.2.0+.")
		return {}
	if api.has_method("is_ready") and not api.is_ready():
		if logger: logger.warn("BuildingPlanner: GuidesLinesApi is not ready.")
		return {}
	if is_nan(coords.x) or is_inf(coords.x) or is_nan(coords.y) or is_inf(coords.y):
		if logger: logger.error("BuildingPlanner: fill coordinates must be finite.")
		return {}
	var result = api.compute_fill_polygon(coords)
	return parse_fill_region(result, logger)

## Validate only on a new zone; the API's unchanged-zone response contains no geometry.
static func parse_fill_region(result, logger = null) -> Dictionary:
	if result == null:
		return {} # A click outside Shape markers is an ordinary miss.
	if typeof(result) != TYPE_DICTIONARY or not result.has("polygon"):
		if logger: logger.error("BuildingPlanner: invalid fill response from GuidesLinesApi.")
		return {}
	var polygon = sanitize_polygon(result.polygon)
	if polygon.empty():
		if logger: logger.error("BuildingPlanner: GuidesLinesApi returned invalid fill geometry.")
		return {}
	var region = result.duplicate()
	region.polygon = polygon
	# Source outlines are optional API metadata; malformed metadata must never reach draw calls.
	region.source_polygons = []
	if result.get("source_polygons") is Array:
		for source in result.source_polygons:
			if not source is Array and not source is PoolVector2Array:
				continue
			var valid = source.size() >= 3
			for point in source:
				if not point is Vector2 or is_nan(point.x) or is_inf(point.x) or is_nan(point.y) or is_inf(point.y):
					valid = false
					break
			if valid:
				region.source_polygons.append(Array(source).duplicate())
	if region.source_polygons.empty():
		region.source_polygons = [polygon.duplicate()]
	return region

## Shared by native creation and hover; never change the source array or settings.
static func prepare_outline(points: Array, closed: bool, settings: Dictionary, logger = null, polygon_validated: bool = false) -> Array:
	var result = offset_outline(points, closed, settings.get("active_offset", 0.0), logger, polygon_validated)
	if settings.get("active_reverse_direction", false):
		result = reverse_outline(result, closed)
	return result

## Match Pathway.Smooth / LineSmoothing.SmoothLineChaikin, including the explicit seam.
## Grow/Shrink and fade affect width/alpha, not this centerline.
static func path_preview_points(points: Array, closed: bool, smoothness: float) -> Array:
	var count = points.size() + (1 if closed else 0)
	if count < 2:
		return []
	var iterations = 1 if count > 100 else (2 if count > 30 else (3 if count > 10 else 4))
	var origin = points[0]
	var result = []
	for point in points:
		result.append(point - origin) # Native smoothing operates on local float coordinates.
	if closed:
		result.append(Vector2.ZERO)
	if result.size() == 2:
		result.insert(1, (result[0] + result[1]) * 0.5)
	var cut = 0.05 + clamp(smoothness * 0.5, 0.0, 1.0) * 0.4
	for _iteration in range(iterations):
		var next = [result[0]]
		for i in range(result.size() - 1):
			next.append((1.0 - cut) * result[i] + cut * result[i + 1])
			next.append(cut * result[i] + (1.0 - cut) * result[i + 1])
		next.append(result[-1])
		result = next
	for i in range(result.size()):
		result[i] += origin
	return result

# The host's void LoadWall appends exactly one child after loading it.
static func load_wall(walls, data):
	var count = walls.get_child_count()
	walls.LoadWall(data.duplicate(true))
	return walls.get_child(count) if walls.get_child_count() == count + 1 else null

static func is_valid_obj(value) -> bool:
	return value != null and (typeof(value) != TYPE_OBJECT or is_instance_valid(value))

static func is_current_world(parent_mod, world, level) -> bool:
	return is_valid_obj(parent_mod) and is_valid_obj(world) and is_valid_obj(level) and parent_mod.Global.World == world

static func resolve_level(parent_mod, level = null):
	if not is_valid_obj(parent_mod):
		return null
	var world = parent_mod.Global.World
	if not is_valid_obj(world):
		return null
	if level == null:
		level = world.Level
	return level if is_valid_obj(level) else null

static func get_roofs(level):
	return level.Roofs if level.Roofs else level.get_node_or_null("Roofs")

static func restore_order(node, index: int) -> void:
	if not is_instance_valid(node) or index < 0:
		return
	var parent = node.get_parent()
	if parent:
		parent.move_child(node, min(index, parent.get_child_count() - 1))

## Native LoadPathway resets tint; restore it and its optional CAMT persistence together.
## Caller owns data; history must pass a copy of its retained snapshot.
static func load_path(global_ref, pathways, data, color: Color, index: int = -1):
	var path = pathways.LoadPathway(data)
	if not is_instance_valid(path):
		return null
	path.modulate = color
	restore_order(path, index)
	if path.has_meta("node_id"):
		store_path_color_for_camt(global_ref, path.get_meta("node_id"), color)
	return path

## Fan area avoids cancellation from a large translation of the whole polygon.
static func signed_area(points) -> float:
	var area = 0.0
	for i in range(1, points.size() - 1):
		area += (points[i] - points[0]).cross(points[i + 1] - points[0])
	return area * 0.5

## Returns an open outline, or [] for malformed/degenerate geometry.
## Adjacent vertices within half a world pixel are merged; the input is untouched.
## Preserve GuidesLines' paired hole bridges and tangent-loop contact vertices.
static func sanitize_polygon(value, epsilon: float = 0.5) -> Array:
	if is_nan(epsilon) or is_inf(epsilon) or epsilon < 0:
		return []
	if typeof(value) != TYPE_ARRAY and typeof(value) != TYPE_VECTOR2_ARRAY:
		return []
	var points = []
	for point in value:
		if typeof(point) != TYPE_VECTOR2 or is_nan(point.x) or is_nan(point.y) or is_inf(point.x) or is_inf(point.y):
			return []
		if points.empty() or point.distance_squared_to(points[-1]) > epsilon * epsilon:
			points.append(point)
	if points.size() > 1 and points[0].distance_squared_to(points[-1]) <= epsilon * epsilon:
		points.pop_back()
	if points.size() < 3:
		return []
	var area = signed_area(points) * 2.0
	if is_nan(area) or is_inf(area) or abs(area) <= epsilon * epsilon:
		return []
	# ponytail: O(n^2) edge checks; use a spatial index if large marker outlines need it.
	var count = points.size()
	if count == 3:
		return points # Nonzero-area triangles have no non-adjacent edges.
	for i in range(count):
		var a = points[i]
		var b = points[(i + 1) % count]
		var min_x = min(a.x, b.x)
		var max_x = max(a.x, b.x)
		var min_y = min(a.y, b.y)
		var max_y = max(a.y, b.y)
		for j in range(i + 2, count):
			if i == 0 and j == count - 1:
				continue
			var c = points[j]
			var d = points[(j + 1) % count]
			# Keep the same 0.0001-pixel contact tolerance as the interior test.
			if max_x + 0.0001 < min(c.x, d.x) or max(c.x, d.x) + 0.0001 < min_x or max_y + 0.0001 < min(c.y, d.y) or max(c.y, d.y) + 0.0001 < min_y:
				continue
			if a == d and b == c:
				continue # Paired outward/return bridge around a hole.
			var intersection = Geometry.segment_intersects_segment_2d(a, b, c, d)
			if intersection != null and not ((intersection == a or intersection == b) and (intersection == c or intersection == d)):
				return []
			# Reject collinear overlap and a vertex touching another edge's interior.
			if _point_on_edge_interior(a, c, d) or _point_on_edge_interior(b, c, d) or _point_on_edge_interior(c, a, b) or _point_on_edge_interior(d, a, b):
				return []
	return points

static func _point_on_edge_interior(point, start, end) -> bool:
	return point != start and point != end and point.x >= min(start.x, end.x) - 0.0001 and point.x <= max(start.x, end.x) + 0.0001 and point.y >= min(start.y, end.y) - 0.0001 and point.y <= max(start.y, end.y) + 0.0001 and point.distance_squared_to(Geometry.get_closest_point_to_segment_2d(point, start, end)) <= 0.00000001

# ============================================================================
# OPTIONAL COLOR PERSISTENCE
# ============================================================================

## Stores a path color into ColourAndModifyThings' ModMapData so the color
## survives map save/reload when CAMT is installed.
## Safe to call when CAMT is not installed — no-op in that case.
## [global_ref] — parent_mod.Global
## [node_id]    — integer node_id meta from the Pathway node
## [color]      — Color chosen in PathPanel / RoomBuilder path settings
static func store_path_color_for_camt(global_ref, node_id: int, color: Color) -> void:
	if not global_ref.ModMapData.has("UchideshiNodeData"):
		return  # CAMT not installed — nothing to do
	var store: Dictionary = global_ref.ModMapData["UchideshiNodeData"]
	var key: String = "node-id-" + str(node_id)
	# White needs no new persistence entry; existing shader/tint records still update.
	if color == Color.white and not store.get("data", {}).has(key):
		return
	if not store.has("data"):
		store["data"] = {}
	# Merge into any existing CAMT record (preserves shader, edge blur, etc.)
	var entry: Dictionary = store["data"].get(key, {}).duplicate()
	entry["type"]   = "paths"
	entry["colour"] = color.to_html()  # AARRGGBB (Godot 3) — same format CAMT uses
	if not entry.has("shader_type"):        entry["shader_type"]       = "none"
	if not entry.has("start_point"):        entry["start_point"]       = 0.0
	if not entry.has("has_edge_blur"):      entry["has_edge_blur"]     = false
	if not entry.has("path_flip_vertical"): entry["path_flip_vertical"] = false
	store["data"][key] = entry

## Remove native IDs and owned path persistence before deferring scene deletion.
static func free_node(node, world = null, global_ref = null) -> void:
	if node == null or not is_instance_valid(node):
		return
	if world != null and node.has_meta("node_id") and world.has_method("HasNodeID"):
		var id = node.get_meta("node_id")
		if world.HasNodeID(id) and world.GetNodeByID(id) == node:
			world.RemoveNodeID(id)
			if global_ref != null and node.has_method("SetEditPoints"):
				var store = global_ref.ModMapData.get("UchideshiNodeData", {})
				if typeof(store) == TYPE_DICTIONARY and typeof(store.get("data")) == TYPE_DICTIONARY:
					store.data.erase("node-id-" + str(id))
	var p = node.get_parent()
	if p:
		p.remove_child(node)
	node.queue_free()
