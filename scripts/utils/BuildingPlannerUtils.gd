extends Reference

# BuildingPlanner - Dungeondraft Mod
# Shared geometry and helper utilities.

const CLASS_NAME = "BuildingPlannerUtils"

# ============================================================================
# GEOMETRY
# ============================================================================

## Reflects [point] across a line defined by [line_point] and [angle] (radians).
static func reflect_point_across_line(point: Vector2, line_point: Vector2, angle: float) -> Vector2:
	# Direction vector of the axis line
	var dir = Vector2(cos(angle), sin(angle))
	# Translate point relative to line origin
	var translated = point - line_point
	# Reflect using formula: 2*(v·d)*d - v  (where d is unit direction)
	var dot = translated.dot(dir)
	var reflected = 2.0 * dot * dir - translated
	return reflected + line_point

## Returns true if [polygon] (Array[Vector2]) contains [point].
static func polygon_contains_point(polygon: Array, point: Vector2) -> bool:
	return Geometry.is_point_in_polygon(point, polygon)

## Returns the centroid of [points] (Array[Vector2]).
static func centroid(points: Array) -> Vector2:
	if points.empty():
		return Vector2.ZERO
	var sum = Vector2.ZERO
	for p in points:
		sum += p
	return sum / points.size()

# ============================================================================
# DUNGEONDRAFT HELPERS
# ============================================================================

## Returns the grid cell size (Vector2) from [world] (Global.World).
## Reads world.Level.TileMap.CellSize, matching the GuidesLines approach.
## Returns null if the world or level is not yet loaded.
static func get_cell_size(world):
	if not world:
		return null
	if not world.Level or not world.Level.TileMap:
		return null
	return world.Level.TileMap.CellSize

## Returns the polygon (Array[Vector2]) for a Shape marker dict in world space.
##
## [marker_dict]  — dict returned by GuidesLinesApi.get_marker();
##                  must have keys: position (Vector2), shape_radius (float),
##                  shape_sides (int, default 6), shape_angle (float degrees).
## [cell_size]    — Vector2 from get_cell_size(); used to convert radius
##                  from grid cells to world pixels.
##
## shape_radius is the circumradius in grid cells.
## shape_angle is the rotation of the first vertex in degrees.
## Returns an empty Array on invalid input.
static func get_shape_polygon(marker_dict: Dictionary, cell_size: Vector2) -> Array:
	var position   = marker_dict.get("position",    Vector2.ZERO)
	var radius_cells = marker_dict.get("shape_radius", 1.0)
	var sides      = int(marker_dict.get("shape_sides",  6))
	var angle_deg  = marker_dict.get("shape_angle",  0.0)

	if sides < 3:
		return []

	# Use the smaller cell dimension to avoid distortion on non-square grids
	var cell_px = min(cell_size.x, cell_size.y)
	var radius_px = radius_cells * cell_px

	var points = []
	for i in range(sides):
		var a = deg2rad(angle_deg + i * 360.0 / float(sides))
		points.append(position + Vector2(cos(a), sin(a)) * radius_px)
	return points

## Returns the points for a Path marker dict.
## For Path markers, the dict key is "marker_points" (Array[Vector2]).
## Returns an empty Array if the key is missing.
static func get_path_points(marker_dict: Dictionary) -> Array:
	return marker_dict.get("marker_points", [])
