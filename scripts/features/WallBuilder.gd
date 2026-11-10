extends Reference

# BuildingPlanner - Dungeondraft Mod
# WallBuilder: traces a nearby Path marker or a filled Shape outline.
#
# Workflow:
#   1. User clicks on the map while Wall Builder mode is active.
#   2. BuildingPlannerTool.handle_canvas_click(world_pos) is called.
#   3. Resolve a nearby Path marker, falling back to compute_fill_polygon(coords).
#   4. Walls.AddWall(points, ..., closed, ...) creates the wall.
#
# Texture source: WallTool.Controls["Texture"] GridMenu (mirrored in our own ItemList).
# Color source:   active_color (set from UI color picker, default white).
# Requires GuidesLines >= 2.2.0 (compute_fill_polygon).

const CLASS_NAME = "WallBuilder"
const BuildingPlannerUtils = preload("../utils/BuildingPlannerUtils.gd")
const BuildingPlannerHistory = preload("../tool/BuildingPlannerHistory.gd")

# ============================================================================
# REFERENCES
# ============================================================================

var _gl_api = null
var LOGGER = null
var _parent_mod = null

# ============================================================================
# SETTINGS
# ============================================================================

# The feature owns its selection independently of the built-in tool.
var active_texture = null
var active_color:  Color = Color.white
var active_shadow: bool = true
var active_joint:  int  = 1    # 0 = Sharp, 1 = Bevel, 2 = Round
var active_offset: float = 0.0 # World pixels; positive outward, negative inward.
var active_reverse_direction: bool = false

# ============================================================================
# INIT
# ============================================================================

func _init(gl_api, logger, parent_mod = null):
	_gl_api = gl_api
	LOGGER = logger
	_parent_mod = parent_mod

# ============================================================================
# BUILD BY WORLD POSITION
# ============================================================================

## Traces a Path marker near [coords], or the enclosing Shape region (world-space).
## Requires GuidesLines >= 2.2.0. Returns true on success.
func build_at(coords: Vector2) -> bool:
	var outline = BuildingPlannerUtils.resolve_outline(_gl_api, coords, LOGGER)
	if outline.empty():
		return false

	var wall = _create_wall(outline.points, null, outline.closed, null, outline.get("polygon_validated", false))
	if not is_instance_valid(wall):
		return false
	BuildingPlannerHistory.record_action(_parent_mod, LOGGER, BuildingPlannerHistory.WallBuilderRecord.new(_parent_mod, wall))
	return true

## Snapshot the complete style; callers own the returned Dictionary.
func get_settings() -> Dictionary:
	return {
		"active_texture": active_texture,
		"active_color": active_color,
		"active_shadow": active_shadow,
		"active_joint": active_joint,
		"active_offset": active_offset,
		"active_reverse_direction": active_reverse_direction,
	}

## Explicit saved settings leave the live UI selection untouched.
func _create_wall(polygon: Array, level = null, closed: bool = true, settings = null, polygon_validated: bool = false):
	if settings == null:
		settings = get_settings()
	polygon = BuildingPlannerUtils.prepare_outline(polygon, closed, settings, LOGGER, polygon_validated)
	if polygon.empty():
		return null
	# --- Dungeondraft context ---
	level = BuildingPlannerUtils.resolve_level(_parent_mod, level)
	if not level:
		if LOGGER: LOGGER.error("%s: World/Level not loaded." % CLASS_NAME)
		return null
	var wall_texture = settings.active_texture
	if not wall_texture is Texture:
		if LOGGER: LOGGER.error("WallBuilder: select a valid texture before building.")
		return null

	var walls = level.Walls
	if not walls:
		if LOGGER: LOGGER.error("%s: Walls node not found in Level." % CLASS_NAME)
		return null

	# --- Create the wall ---
	var new_wall = walls.AddWall(
		PoolVector2Array(polygon),
		wall_texture,
		settings.active_color,
		closed,
		settings.active_shadow,
		1,               # type = Manual, as in the native WallTool
		settings.active_joint,
		true             # normalizeUV
	)

	if not new_wall:
		if LOGGER: LOGGER.warn("%s: AddWall returned null." % CLASS_NAME)
		return null

	if LOGGER: LOGGER.info("%s: wall built with %d points." % [CLASS_NAME, polygon.size()])
	return new_wall
