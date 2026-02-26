extends Reference

# BuildingPlanner - Dungeondraft Mod
# RoomBuilder: one-click room creation.
#
# Workflow on left-click:
#   1. Place a temporary Shape marker at click position using GuidesLines state.
#   2. Fill the marker area with the selected pattern (via compute_fill_polygon).
#   3. Build a closed wall along the marker outline (via compute_fill_polygon).
#   4. Delete the temporary marker via the API.
#   5. Record a combined undo/redo history entry.
#
# While active, set_shape_preview() is called every frame to render a live
# preview polygon that mirrors the current GuidesLines Shape parameters.
# The gl_tool_state snapshot is captured once in BuildingPlannerTool.Enable()
# and passed in — both tools cannot be active simultaneously.

const CLASS_NAME = "RoomBuilder"
const BuildingPlannerHistory   = preload("../tool/BuildingPlannerHistory.gd")
const MarkerObjectRegistry     = preload("MarkerObjectRegistry.gd")

# ============================================================================
# REFERENCES
# ============================================================================

var _gl_api     = null
var LOGGER      = null
var _parent_mod = null
var _registry   = null   # MarkerObjectRegistry

# ============================================================================
# PATTERN SETTINGS
# ============================================================================

var active_texture   = null           # Texture
var active_color:    Color = Color.white
var active_rotation: float = 0.0      # degrees
var active_layer:    int   = 0
var active_outline:  bool  = false

# ============================================================================
# WALL SETTINGS
# ============================================================================

var active_shadow: bool = true
var active_joint:  int  = 1           # 0 = Sharp, 1 = Bevel, 2 = Round
var active_wall_color: Color = Color.white

# ============================================================================
# INIT
# ============================================================================

func _init(gl_api, logger, parent_mod = null):
	_gl_api     = gl_api
	LOGGER      = logger
	_parent_mod = parent_mod
	_registry   = MarkerObjectRegistry.new(logger)

# ============================================================================
# SUB-MODE
# ============================================================================

enum SubMode { SINGLE = 0, MERGE = 1 }

var active_sub_mode: int = SubMode.SINGLE

# ============================================================================
# PREVIEW
# ============================================================================

## Call every frame while RoomBuilder mode is active.
##
## Parameters:
##   world_pos    - MousePosition from WorldUI (world-space Vector2)
##   cursor_in_ui - true when the cursor is over the UI panel
##   state        - pre-fetched Dictionary from GuidesLinesApi.get_tool_state()
func update_preview(world_pos: Vector2, cursor_in_ui: bool, state: Dictionary) -> void:
	if not _gl_api:
		return

	if cursor_in_ui:
		_gl_api.clear_shape_preview()
		return

	if not state.get("ready", false):
		return

	if state.get("active_marker_type", "") != "Shape":
		_gl_api.clear_shape_preview()
		return

	_gl_api.set_shape_preview(
		world_pos,
		state.get("active_shape_radius", 1.0),
		state.get("active_shape_angle",  0.0),
		state.get("active_shape_sides",  6),
		state.get("active_color",        null)
	)

## Clears the preview immediately — call on mode switch or tool deactivation.
func stop_preview() -> void:
	if _gl_api:
		_gl_api.clear_shape_preview()

## Called when the tool is deactivated — purges the registry without touching the scene.
func on_disabled() -> void:
	_registry.clear()

# ============================================================================
# BUILD ROOM
# ============================================================================

## Dispatches to the active sub-mode.
## [state] is the gl_tool_state snapshot from BuildingPlannerTool.
## Returns true on success.
func build_room_at(coords: Vector2, state: Dictionary) -> bool:
	match active_sub_mode:
		SubMode.SINGLE:
			return _build_room_single(coords, state)
		SubMode.MERGE:
			return _build_room_merge(coords, state)
	return false

# ============================================================================
# PRIVATE — SUB-MODE IMPLEMENTATIONS
# ============================================================================

## Single mode: place temporary marker → fill → wall → delete marker.
func _build_room_single(coords: Vector2, state: Dictionary) -> bool:
	var result = _build_room_single_impl(coords, state, true)
	return result

## Single-no-delete: same as Single but the marker is kept (used as Merge fallback).
func _build_room_single_no_delete(coords: Vector2, state: Dictionary) -> bool:
	return _build_room_single_impl(coords, state, false)

## Internal implementation for the Single logic.
## [delete_marker_after] — when false the temporary marker is kept.
func _build_room_single_impl(coords: Vector2, state: Dictionary,
		delete_marker_after: bool) -> bool:
	if not _gl_api:
		if LOGGER: LOGGER.error("%s: GuidesLinesApi not available." % CLASS_NAME)
		return false

	if not _parent_mod:
		if LOGGER: LOGGER.error("%s: parent_mod not set." % CLASS_NAME)
		return false

	if not _gl_api.has_method("compute_fill_polygon"):
		if LOGGER: LOGGER.error(
			"%s: compute_fill_polygon not found — update GuidesLines to v2.2.0+." % CLASS_NAME)
		return false

	if _gl_api.has_method("is_ready") and not _gl_api.is_ready():
		if LOGGER: LOGGER.warn("%s: GuidesLinesApi not ready yet." % CLASS_NAME)
		return false

	if not state.get("ready", false) or state.get("active_marker_type", "") != "Shape":
		if LOGGER: LOGGER.warn("%s: GuidesLines is not in Shape mode." % CLASS_NAME)
		return false

	# ---- 1. Place temporary Shape marker ----
	var marker_id: int = _gl_api.place_shape_marker(
		coords,
		state.get("active_shape_radius", 1.0),
		state.get("active_shape_angle",  0.0),
		state.get("active_shape_sides",  6),
		state.get("active_color",        null)
	)
	if marker_id < 0:
		if LOGGER: LOGGER.error("%s: place_shape_marker failed." % CLASS_NAME)
		return false

	# ---- 2. Resolve polygon ----
	var fill_result = _gl_api.compute_fill_polygon(coords)
	if typeof(fill_result) != TYPE_DICTIONARY or fill_result.get("polygon", []).empty():
		if LOGGER: LOGGER.warn("%s: compute_fill_polygon returned empty polygon." % CLASS_NAME)
		if delete_marker_after:
			_gl_api.delete_marker(marker_id)
		return false

	var polygon: Array = _sanitize_polygon(fill_result["polygon"])
	if polygon.empty():
		if LOGGER: LOGGER.warn("%s: polygon is degenerate after sanitize." % CLASS_NAME)
		if delete_marker_after:
			_gl_api.delete_marker(marker_id)
		return false

	# ---- 3. Fill with pattern ----
	var new_shapes: Array = _fill_pattern(polygon)

	# ---- 4. Build wall ----
	var new_wall = _build_wall(polygon)

	# ---- 5. Register objects when keeping the marker (potential future merge target) ----
	if not delete_marker_after:
		_registry.register(marker_id, new_shapes,
			[new_wall] if new_wall != null else [])

	# ---- 6. Optionally delete temporary marker ----
	if delete_marker_after:
		_gl_api.delete_marker(marker_id)

	# ---- 7. Record history (patterns only; wall undo not supported) ----
	if not new_shapes.empty():
		_record_history(BuildingPlannerHistory.PatternFillRecord.new(
			_parent_mod, LOGGER, new_shapes))

	if LOGGER: LOGGER.info("%s: room built at %s with %d polygon points." % [
		CLASS_NAME, str(coords), polygon.size()])
	return true

## Merge mode: call place_shape_merge and fill/wall every affected marker.
## Falls back to Single-no-delete when there are no overlapping markers.
func _build_room_merge(coords: Vector2, state: Dictionary) -> bool:
	if not _gl_api:
		if LOGGER: LOGGER.error("%s: GuidesLinesApi not available." % CLASS_NAME)
		return false

	if not _parent_mod:
		if LOGGER: LOGGER.error("%s: parent_mod not set." % CLASS_NAME)
		return false

	if not _gl_api.has_method("place_shape_merge"):
		if LOGGER: LOGGER.error(
			"%s: place_shape_merge not found — update GuidesLines." % CLASS_NAME)
		return false

	if _gl_api.has_method("is_ready") and not _gl_api.is_ready():
		if LOGGER: LOGGER.warn("%s: GuidesLinesApi not ready yet." % CLASS_NAME)
		return false

	if not state.get("ready", false) or state.get("active_marker_type", "") != "Shape":
		if LOGGER: LOGGER.warn("%s: GuidesLines is not in Shape mode." % CLASS_NAME)
		return false

	# ---- 1. Attempt merge ----
	var merge_result: Dictionary = _gl_api.place_shape_merge(
		coords,
		state.get("active_shape_radius", 1.0),
		state.get("active_shape_angle",  0.0),
		state.get("active_shape_sides",  6)
	)

	if merge_result.empty():
		if LOGGER: LOGGER.error("%s: place_shape_merge returned internal failure." % CLASS_NAME)
		return false

	var affected: Array = merge_result.get("affected_markers", [])

	# ---- 2. Fallback — no overlapping markers: run Single without deleting ----
	if affected.empty():
		if LOGGER: LOGGER.info(
			"%s: Merge found no overlapping markers — falling back to Single (keep marker)." % CLASS_NAME)
		return _build_room_single_no_delete(coords, state)

	# ---- 3. Clean up absorbed markers (deleted during merge) ----
	var absorbed_ids: Array = merge_result.get("absorbed_marker_ids", [])
	for absorbed_id in absorbed_ids:
		_registry.cleanup(absorbed_id)

	# ---- 4. Fill + Wall for every merged marker ----
	# Use compute_fill_polygon at the updated marker position instead of the raw
	# new_polygon vertices — this ensures the same world-space format that
	# DrawPolygon / AddWall expect (identical to Single mode).
	var all_new_shapes: Array = []
	for entry in affected:
		var m_id: int = entry.get("marker_id", -1)
		var fill_coords: Vector2 = entry.get("new_position", Vector2.ZERO)

		# Remove stale fills and walls that belong to this marker
		_registry.cleanup(m_id)

		var fill_result = _gl_api.compute_fill_polygon(fill_coords)
		var polygon: Array
		if typeof(fill_result) == TYPE_DICTIONARY and not fill_result.get("polygon", []).empty():
			polygon = fill_result["polygon"]
		else:
			polygon = entry.get("new_polygon", [])
		polygon = _sanitize_polygon(polygon)
		if polygon.empty():
			if LOGGER: LOGGER.warn("%s: could not resolve polygon for merged marker %d (degenerate after sanitize)." % [
				CLASS_NAME, m_id])
			continue
		var new_shapes: Array = _fill_pattern(polygon)
		if not new_shapes.empty():
			all_new_shapes += new_shapes
		var new_wall = _build_wall(polygon)

		# Register the freshly created objects for this marker
		_registry.register(m_id, new_shapes,
			[new_wall] if new_wall != null else [])

	# ---- 5. Record history ----
	if not all_new_shapes.empty():
		_record_history(BuildingPlannerHistory.PatternFillRecord.new(
			_parent_mod, LOGGER, all_new_shapes))

	if LOGGER: LOGGER.info("%s: Merge built %d rooms at %s." % [
		CLASS_NAME, affected.size(), str(coords)])
	return true

# ============================================================================
# PRIVATE — POLYGON SANITIZE
# ============================================================================

## Removes consecutive duplicate vertices (distance < epsilon) and validates
## the result has at least 3 distinct points.
## Returns an empty Array when the polygon is degenerate.
func _sanitize_polygon(polygon: Array, epsilon: float = 0.5) -> Array:
	if polygon.size() < 3:
		return []
	var result: Array = []
	var n: int = polygon.size()
	for i in range(n):
		var p: Vector2 = polygon[i]
		var prev: Vector2 = polygon[(i - 1 + n) % n]
		if p.distance_to(prev) > epsilon:
			result.append(p)
	if result.size() < 3:
		return []
	return result

# ============================================================================
# PRIVATE — PATTERN FILL
# ============================================================================

func _fill_pattern(polygon: Array) -> Array:
	if not active_texture:
		if LOGGER: LOGGER.warn("%s: no pattern texture selected, skipping fill." % CLASS_NAME)
		return []

	var _global = _parent_mod.Global
	if not _global.World or not _global.World.Level:
		if LOGGER: LOGGER.error("%s: World/Level not loaded." % CLASS_NAME)
		return []

	var pattern_shapes = _global.World.Level.PatternShapes
	var shapes_before: Array = pattern_shapes.GetShapes()
	var count_before: int = shapes_before.size()

	pattern_shapes.DrawPolygon(PoolVector2Array(polygon), false)

	var shapes_after: Array = pattern_shapes.GetShapes()
	var new_shapes: Array = []
	for i in range(count_before, shapes_after.size()):
		var shape = shapes_after[i]
		if not shape or not is_instance_valid(shape):
			continue
		shape.SetOptions(active_texture, active_color, deg2rad(active_rotation))
		shape.SetLayer(active_layer)
		if active_outline:
			shape.SetPoints(shape.polygon, true)
		new_shapes.append(shape)

	return new_shapes

# ============================================================================
# PRIVATE — WALL BUILD
# ============================================================================

func _build_wall(polygon: Array):
	var _global = _parent_mod.Global
	if not _global.World or not _global.World.Level:
		if LOGGER: LOGGER.error("%s: World/Level not loaded." % CLASS_NAME)
		return null

	var wall_texture = null
	if _global.Editor and _global.Editor.Tools.has("WallTool"):
		var wt = _global.Editor.Tools["WallTool"]
		wall_texture = wt.Texture
	else:
		if LOGGER: LOGGER.warn("%s: WallTool not found, using defaults." % CLASS_NAME)

	var walls = _global.World.Level.Walls
	if not walls:
		if LOGGER: LOGGER.error("%s: Walls node not found in Level." % CLASS_NAME)
		return null

	var new_wall = walls.AddWall(
		PoolVector2Array(polygon),
		wall_texture,
		active_wall_color,
		true,           # loop = closed contour
		active_shadow,
		0,              # type = Auto
		active_joint,
		true            # normalizeUV
	)

	if not new_wall:
		if LOGGER: LOGGER.warn("%s: AddWall returned null." % CLASS_NAME)
		return null

	return new_wall

# ============================================================================
# PRIVATE — HISTORY
# ============================================================================

func _record_history(record) -> void:
	if not _parent_mod:
		return
	var api = _parent_mod.Global.API
	if api and api.has("HistoryApi"):
		api.HistoryApi.record(record, 100)
	elif LOGGER:
		LOGGER.warn("%s: HistoryApi not available — action will not be undoable." % CLASS_NAME)
