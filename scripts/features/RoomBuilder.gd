extends Reference

# BuildingPlanner - Dungeondraft Mod
# RoomBuilder: one-click room creation.
#
# Workflow on left-click:
#   1. Capture GuidesLines history for the selected placement/boolean operation.
#   2. Snapshot old registered objects before replacing any geometry.
#   3. Fill each resulting polygon and build its Wall or Path outline.
#   4. Keep persistent markers, or delete the temporary Single marker.
#   5. Record marker edits and native objects as one undo/redo entry.
#
# While active, the public Shape or Template preview is refreshed each frame.
# BuildingPlannerTool refreshes the public GuidesLines state during preview and placement.

const CLASS_NAME = "RoomBuilder"
const PatternFill = preload("PatternFill.gd")
const WallBuilder = preload("WallBuilder.gd")
const PathBuilder = preload("PathBuilder.gd")
const BuildingPlannerHistory   = preload("../tool/BuildingPlannerHistory.gd")
const MarkerObjectRegistry     = preload("MarkerObjectRegistry.gd")
const BuildingPlannerUtils     = preload("../utils/BuildingPlannerUtils.gd")

# ============================================================================
# REFERENCES
# ============================================================================

var _gl_api     = null
var LOGGER      = null
var _parent_mod = null
var _registry   = null   # MarkerObjectRegistry
var _operation = null   # Active synchronous RoomBuilderRecord
var _difference_noop = false
var _preview_active = false
var _shape_parameters = [0.0, 0.0, 0]
var _supported_modes = []
var _supports_preview = false
var _supports_templates = false
const SUB_MODE_METHODS = ["place_shape_marker_plain", "place_shape_merge", "place_shape_conforming", "place_shape_wrapping", "apply_shape_difference"]
const REQUIRED_API_METHODS = ["delete_marker", "is_ready", "begin_history_capture", "end_history_capture"]

# Independent room settings use the same feature implementations as standalone tools.
var _pattern_fill = null
var _wall_builder = null
var _path_builder = null

enum OutlineMode { WALL = 0, PATH = 1 }
var active_outline_mode: int = OutlineMode.WALL

# ============================================================================
# SHAPE OVERRIDES (scroll wheel adjustments while Room Builder mode is active)
# ============================================================================

## Added to state.active_shape_angle (degrees).
var shape_angle_offset: float = 0.0
## Multiplied into state.active_shape_radius.
var shape_scale_factor: float = 1.0

const ANGLE_STEP: float = 5.0    # degrees per scroll tick
const SCALE_STEP: float = 0.1    # fraction per scroll tick
const SCALE_MIN: float  = 0.1    # minimum scale factor

## Rotate the preview / next placement by [delta_deg] degrees.
func adjust_angle(delta_deg: float) -> void:
	shape_angle_offset = fposmod(shape_angle_offset + delta_deg, 360.0)

## Scale the preview / next placement by [delta] (positive = larger, negative = smaller).
func adjust_scale(delta: float) -> void:
	shape_scale_factor = max(SCALE_MIN, shape_scale_factor + delta)

# ============================================================================
# INIT
# ============================================================================

func _init(gl_api, logger, parent_mod = null):
	_gl_api     = gl_api
	LOGGER      = logger
	_parent_mod = parent_mod
	_registry   = MarkerObjectRegistry.new(logger)
	var supported = gl_api != null
	for method in REQUIRED_API_METHODS:
		if not gl_api or not gl_api.has_method(method):
			supported = false
	for method in SUB_MODE_METHODS:
		_supported_modes.append(supported and gl_api.has_method(method))
	# Merge may place a new marker when no shapes overlap.
	for mode in [0, 1]:
		_supported_modes[mode] = _supported_modes[mode] and gl_api.has_method("get_shape_polygon")
	_supported_modes[1] = _supported_modes[1] and _supported_modes[0]
	_supports_preview = gl_api != null and gl_api.has_method("set_shape_preview") and gl_api.has_method("clear_shape_preview")
	_supports_templates = supported and gl_api.has_method("get_template_markers") and gl_api.has_method("apply_marker_geometry")
	_pattern_fill = PatternFill.new(gl_api, logger, parent_mod)
	_wall_builder = WallBuilder.new(gl_api, logger, parent_mod)
	_path_builder = PathBuilder.new(gl_api, logger, parent_mod)

# ============================================================================
# SUB-MODE
# ============================================================================

enum SubMode { SINGLE = 0, MERGE = 1, CONFORM = 2, WRAP = 3, DIFFERENCE = 4 }

var active_sub_mode: int = SubMode.SINGLE

# ============================================================================
# PREVIEW
# ============================================================================

## Call every frame while RoomBuilder mode is active.
##
## Parameters:
##   world_pos    - MousePosition from WorldUI (world-space Vector2)
##   state        - public placement state (legacy Shape state also supported)
func update_preview(world_pos: Vector2, state: Dictionary) -> void:
	if not _gl_api:
		return
	if state.get("active_marker_type") == "Template":
		if not _can_build(world_pos, state, [1]) or not _gl_api.has_method("set_template_preview") or not _gl_api.has_method("clear_shape_preview"):
			stop_preview()
			return
		_preview_active = _gl_api.set_template_preview(world_pos, shape_angle_offset, shape_scale_factor)
		return

	var args = _shape_args(state)
	if not _supports_preview or not _can_build(world_pos, state, args):
		stop_preview()
		return

	_gl_api.set_shape_preview(
		world_pos,
		args[0], args[1], args[2],
		state.get("active_color",        null)
	)
	_preview_active = true

## Clears the preview immediately — call on mode switch or tool deactivation.
func stop_preview() -> void:
	if _gl_api and _preview_active:
		_gl_api.clear_shape_preview()
	_preview_active = false

## Map-scoped associations must survive tool switches but never map changes.
func on_map_changed() -> void:
	_registry.clear()

# ============================================================================
# BUILD ROOM
# ============================================================================

## Dispatches to the active sub-mode.
## [state] is the gl_tool_state snapshot from BuildingPlannerTool.
## Returns true on success.
func build_room_at(coords: Vector2, state: Dictionary) -> bool:
	# Snapshot click arguments; API signal callbacks may refresh the preview.
	var template = state.get("active_marker_type") == "Template"
	var args = [1] if template else _shape_args(state).duplicate()
	if not _can_build(coords, state, args):
		if LOGGER: LOGGER.error("RoomBuilder: placement cancelled; invalid shape settings, unsupported mode or GuidesLinesApi not ready.")
		return false
	if not BuildingPlannerUtils.resolve_level(_parent_mod):
		if LOGGER: LOGGER.error("RoomBuilder: World/Level not loaded.")
		return false
	var batch = _template_batch(coords) if template else []
	if template and batch.empty():
		if LOGGER: LOGGER.error("RoomBuilder: selected template has no buildable geometry; nothing was changed.")
		return false
	if not _gl_api.begin_history_capture():
		if LOGGER: LOGGER.error("RoomBuilder: GuidesLinesApi rejected begin_history_capture; room placement cancelled.")
		return false
	_operation = BuildingPlannerHistory.RoomBuilderRecord.new(_parent_mod, _registry)
	_difference_noop = false
	var success = true
	if template:
		var all_noop = true
		for marker in batch:
			if marker.marker_type == "Shape":
				success = _build_room(marker.position, [], marker.color, marker)
				all_noop = all_noop and _difference_noop
			else:
				success = _build_template_outline(marker)
				all_noop = false
			if not success: break
		_difference_noop = all_noop
	else:
		success = _build_room(coords, args, state.get("active_color", null))
	var marker_records = _gl_api.end_history_capture()
	if success and (_difference_noop or active_sub_mode == SubMode.SINGLE):
		marker_records = [] # Successful Single and non-overlapping Difference leave markers unchanged.
	if LOGGER: LOGGER.debug("RoomBuilder: capturing native object history (mode=%d, success=%s)." % [active_sub_mode, str(success)])
	_operation.finish(marker_records)
	if LOGGER: LOGGER.debug("RoomBuilder: native object history captured.")
	if not success:
		_operation.undo()
	elif _operation.has_changes():
		BuildingPlannerHistory.record_action(_parent_mod, LOGGER, _operation)
		if LOGGER: LOGGER.debug("RoomBuilder: compound history recorded.")
	_operation = null
	return success

func _shape_args(state: Dictionary) -> Array:
	var radius = state.get("active_shape_radius")
	var angle = state.get("active_shape_angle")
	var sides = state.get("active_shape_sides")
	if (typeof(radius) != TYPE_INT and typeof(radius) != TYPE_REAL) or (typeof(angle) != TYPE_INT and typeof(angle) != TYPE_REAL):
		return []
	if is_nan(radius) or is_inf(radius) or radius <= 0 or is_nan(angle) or is_inf(angle) or typeof(sides) != TYPE_INT or sides < 3:
		return []
	if is_nan(shape_scale_factor) or is_inf(shape_scale_factor) or shape_scale_factor <= 0 or is_nan(shape_angle_offset) or is_inf(shape_angle_offset):
		return []
	radius *= shape_scale_factor
	angle += shape_angle_offset
	if radius <= 0 or is_inf(radius) or is_inf(angle):
		return []
	_shape_parameters[0] = radius
	_shape_parameters[1] = angle
	_shape_parameters[2] = sides
	return _shape_parameters

func _can_build(coords: Vector2, state: Dictionary, args: Array) -> bool:
	if args.empty() or not state.get("ready", false):
		return false
	if is_nan(shape_scale_factor) or is_inf(shape_scale_factor) or shape_scale_factor <= 0 or is_nan(shape_angle_offset) or is_inf(shape_angle_offset):
		return false
	var template = state.get("active_marker_type") == "Template"
	if template and (not _supports_templates or state.get("template_capture_mode", false)):
		return false
	if active_sub_mode < 0 or active_sub_mode >= _supported_modes.size() or (not template and not _supported_modes[active_sub_mode]):
		return false
	if active_outline_mode != OutlineMode.WALL and active_outline_mode != OutlineMode.PATH:
		return false
	return not (is_nan(coords.x) or is_nan(coords.y) or is_inf(coords.x) or is_inf(coords.y)) and _gl_api.is_ready()

func _template_batch(coords: Vector2) -> Array:
	var batch = _gl_api.get_template_markers(coords, -1, shape_angle_offset, shape_scale_factor)
	if not batch is Array: return []
	batch = batch.duplicate(true)
	for marker in batch:
		if not marker is Dictionary or not marker.get("position") is Vector2 or not marker.get("color") is Color: return []
		if is_nan(marker.position.x) or is_inf(marker.position.x) or is_nan(marker.position.y) or is_inf(marker.position.y): return []
		if marker.get("marker_type") == "Shape":
			marker["polygon"] = BuildingPlannerUtils.sanitize_polygon(marker.get("polygon"))
			if marker.polygon.empty(): return []
		elif marker.get("marker_type") in ["Line", "Path"]:
			if not marker.get("outline_points") is Array or not marker.get("closed") is bool: return []
			var points = []
			for point in marker.outline_points:
				if not point is Vector2 or is_nan(point.x) or is_inf(point.x) or is_nan(point.y) or is_inf(point.y): return []
				if points.empty() or points.back() != point: points.append(point)
			if points.size() < 2: return []
			marker.outline_points = BuildingPlannerUtils.sanitize_polygon(points) if marker.closed else points
			if marker.outline_points.empty(): return []
		else:
			return []
	return batch

# Open guides have no floor region or boolean area; reuse the existing native
# Wall/Path creation with closed=false. Closed Paths also receive the chosen fill.
func _build_template_outline(marker: Dictionary) -> bool:
	if marker.closed:
		return _populate_marker_geometry(-1, marker.outline_points, false)
	var level = BuildingPlannerUtils.resolve_level(_parent_mod)
	var outline = _wall_builder._create_wall(marker.outline_points, level, false) if active_outline_mode == OutlineMode.WALL else _path_builder._create_path(marker.outline_points, level, false)
	if not is_instance_valid(outline): return false
	_operation._loose.walls.append(outline)
	return true

func _build_room(coords, args, color, marker: Dictionary = {}) -> bool:
	if active_sub_mode == SubMode.SINGLE:
		return _place_single(coords, args, color, false, marker)
	var result
	if not marker.empty():
		result = _gl_api.apply_marker_geometry(marker, ["Normal", "Merge", "Conform", "Wrap", "Difference"][active_sub_mode])
	else:
		match active_sub_mode:
			SubMode.MERGE:
				result = _gl_api.place_shape_merge(coords, args[0], args[1], args[2])
			SubMode.CONFORM:
				result = _gl_api.place_shape_conforming(coords, args[0], args[1], args[2], color)
			SubMode.WRAP:
				result = _gl_api.place_shape_wrapping(coords, args[0], args[1], args[2], color)
			SubMode.DIFFERENCE:
				result = _gl_api.apply_shape_difference(coords, args[0], args[1], args[2])
	if typeof(result) != TYPE_DICTIONARY or result.empty():
		if LOGGER: LOGGER.error("RoomBuilder: Invalid boolean operation result from GuidesLinesApi.")
		return false
	var affected = result.get("affected_markers", [])
	var absorbed = result.get("absorbed_marker_ids", [])
	if typeof(affected) != TYPE_ARRAY or typeof(absorbed) != TYPE_ARRAY:
		if LOGGER: LOGGER.error("RoomBuilder: Invalid affected_markers or absorbed_marker_ids from GuidesLinesApi.")
		return false
	# Existing rooms must retain their ownership and style; never repaint from live UI.
	var touched_ids = absorbed.duplicate()
	if active_sub_mode != SubMode.WRAP:
		for entry in affected:
			if typeof(entry) == TYPE_DICTIONARY:
				touched_ids.append(entry.get("marker_id", -1))
	for id in touched_ids:
		if typeof(id) == TYPE_INT and _registry.has_entry(id) and (_registry.get_levels(id).empty() or _registry.get_settings(id).empty()):
			if LOGGER: LOGGER.error("RoomBuilder: registered room %s is missing level or style metadata; placement cancelled." % str(id))
			return false
	_difference_noop = active_sub_mode == SubMode.DIFFERENCE and affected.empty()
	# Capture every old node/index before removing any entry or inserting new geometry.
	for id in absorbed:
		if typeof(id) != TYPE_INT or id < 0:
			if LOGGER: LOGGER.error("RoomBuilder: Invalid absorbed marker ID from GuidesLinesApi.")
			return false
		if _registry.has_entry(id):
			_operation.remember(id)
	for entry in affected:
		if typeof(entry) != TYPE_DICTIONARY or typeof(entry.get("marker_id")) != TYPE_INT or entry.marker_id < 0:
			if LOGGER: LOGGER.error("RoomBuilder: Invalid affected marker ID from GuidesLinesApi.")
			return false
		if active_sub_mode != SubMode.WRAP and _registry.has_entry(entry.marker_id):
			_operation.remember(entry.marker_id)
	if active_sub_mode == SubMode.MERGE and affected.empty():
		return _place_single(coords, args, color, true, marker)
	# Markers are map-wide: preserve geometry on every level that owned an affected room.
	var levels_by_id = {}
	var settings_by_id = {}
	var merged_levels = [_parent_mod.Global.World.Level]
	for entry in affected:
		if active_sub_mode == SubMode.WRAP or not _registry.has_entry(entry.marker_id):
			continue
		var levels = _registry.get_levels(entry.marker_id)
		if active_sub_mode == SubMode.MERGE:
			for level in levels:
				if not level in merged_levels:
					merged_levels.append(level)
		else:
			levels_by_id[entry.marker_id] = levels
			settings_by_id[entry.marker_id] = _registry.get_settings(entry.marker_id)
	if active_sub_mode == SubMode.MERGE:
		for id in absorbed:
			for level in _registry.get_levels(id):
				if not level in merged_levels:
					merged_levels.append(level)
	for id in absorbed:
		_registry.cleanup(id, _parent_mod.Global.World, _parent_mod.Global)
	if active_sub_mode == SubMode.CONFORM or active_sub_mode == SubMode.WRAP:
		var id = result.get("marker_id", -1)
		var polygon = BuildingPlannerUtils.sanitize_polygon(result.get("marker_polygon", []))
		if typeof(id) != TYPE_INT or id < 0 or polygon.empty():
			if LOGGER: LOGGER.error("RoomBuilder: invalid new marker ID or polygon from GuidesLinesApi.")
			return false
		if not _populate_marker_geometry(id, polygon):
			return false
	# Wrap reports unchanged neighbors; rebuilding them would overwrite their settings.
	if active_sub_mode != SubMode.WRAP:
		for entry in affected:
			var id = entry.get("marker_id", -1)
			var raw_polygon = entry.get("new_polygon", [])
			if typeof(raw_polygon) != TYPE_ARRAY and typeof(raw_polygon) != TYPE_VECTOR2_ARRAY:
				if LOGGER: LOGGER.error("RoomBuilder: Invalid affected polygon type from GuidesLinesApi.")
				return false
			var polygon = BuildingPlannerUtils.sanitize_polygon(raw_polygon)
			if not raw_polygon.empty() and polygon.empty():
				if LOGGER: LOGGER.error("RoomBuilder: Invalid affected polygon geometry from GuidesLinesApi.")
				return false
			# Boolean cuts edit GuidesLines markers; only existing rooms own native objects.
			if active_sub_mode != SubMode.MERGE and not _registry.has_entry(id):
				continue
			_registry.cleanup(id, _parent_mod.Global.World, _parent_mod.Global)
			# An empty outline is the valid result of a fully consumed marker.
			var levels = merged_levels if active_sub_mode == SubMode.MERGE else levels_by_id[id]
			var settings = {} if active_sub_mode == SubMode.MERGE else settings_by_id[id]
			if not polygon.empty() and not _populate_marker_geometry(id, polygon, true, levels, settings):
				return false
	return true

func _place_single(coords, args, color, keep_marker, marker: Dictionary = {}) -> bool:
	var placed = _gl_api.apply_marker_geometry(marker) if not marker.empty() else {}
	if not placed is Dictionary: return false
	var id = placed.get("marker_id", -1) if not marker.empty() else _gl_api.place_shape_marker_plain(coords, args[0], args[1], args[2], color)
	if typeof(id) != TYPE_INT or id < 0:
		if LOGGER: LOGGER.error("RoomBuilder: plain marker placement failed.")
		return false
	var result = {"marker_id": id, "marker_type": "Shape", "polygon": placed.get("marker_polygon", [])} if not marker.empty() else _gl_api.get_shape_polygon(id)
	if typeof(result) != TYPE_DICTIONARY or result.get("marker_id") != id or result.get("marker_type") != "Shape":
		if LOGGER: LOGGER.error("RoomBuilder: get_shape_polygon returned a mismatched marker ID or type.")
		return false
	var polygon = BuildingPlannerUtils.sanitize_polygon(result.get("polygon", []))
	if polygon.empty():
		if LOGGER: LOGGER.error("RoomBuilder: get_shape_polygon returned invalid geometry.")
		return false
	if not _populate_marker_geometry(id, polygon, keep_marker):
		return false
	return keep_marker or _gl_api.delete_marker(id)

func _populate_marker_geometry(id, polygon, keep_marker = true, levels: Array = [], settings: Dictionary = {}) -> bool:
	if keep_marker:
		_operation.remember(id)
	if levels.empty():
		levels = [_parent_mod.Global.World.Level]
	if settings.empty():
		var outline = _wall_builder if active_outline_mode == OutlineMode.WALL else _path_builder
		settings = {"outline_mode": active_outline_mode, "fill": _pattern_fill.get_settings(), "outline": outline.get_settings()}
	var shapes = []
	var outlines = []
	var success = true
	for level in levels:
		var fill = _pattern_fill._create_shape(polygon, level, settings.fill) if settings.fill.active_texture != null else null
		var outline = _wall_builder._create_wall(polygon, level, true, settings.outline) if settings.outline_mode == OutlineMode.WALL else _path_builder._create_path(polygon, level, true, settings.outline)
		if is_instance_valid(fill):
			shapes.append(fill)
		if is_instance_valid(outline):
			outlines.append(outline)
		else:
			success = false
		if settings.fill.active_texture != null and not is_instance_valid(fill):
			success = false
	if keep_marker:
		_registry.register(id, shapes, outlines, levels, settings)
	else:
		_operation._loose.fills += shapes
		_operation._loose.walls += outlines
	return success
