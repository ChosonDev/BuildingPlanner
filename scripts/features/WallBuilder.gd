extends Reference

# BuildingPlanner - Dungeondraft Mod
# WallBuilder: places a closed wall along the outline of a Shape marker under a click.
#
# Workflow:
#   1. User clicks on the map while Wall Builder mode is active.
#   2. BuildingPlannerTool.handle_wall_builder_click(world_pos) is called.
#   3. GuidesLinesApi.compute_fill_polygon(coords) resolves the polygon.
#   4. Walls.AddWall(polygon, ...) creates the closed wall outline.
#
# Texture source: WallTool.Controls["Texture"] GridMenu (mirrored in our own ItemList).
# Color source:   WallTool.Color (read at click time).
# Requires GuidesLines >= 2.2.0 (compute_fill_polygon).

const CLASS_NAME = "WallBuilder"

# ============================================================================
# REFERENCES
# ============================================================================

var _gl_api = null
var LOGGER = null
var _parent_mod = null

# ============================================================================
# SETTINGS
# ============================================================================

# Texture and color are always read from WallTool at click time,
# so selecting in our GridMenu drives WallTool.Texture via OnItemSelected.
var active_shadow: bool = true
var active_joint: int = 1    # 0 = Sharp, 1 = Bevel, 2 = Round

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

## Builds a closed wall along the Shape marker outline under [coords] (world-space).
## Requires GuidesLines >= 2.2.0. Returns true on success.
func build_at(coords: Vector2) -> bool:
	if not _gl_api:
		if LOGGER: LOGGER.error("%s: GuidesLinesApi not available." % CLASS_NAME)
		return false

	if not _gl_api.has_method("compute_fill_polygon"):
		if LOGGER: LOGGER.error(
			"%s: compute_fill_polygon not found in GuidesLinesApi." % CLASS_NAME + "\n" +
			"  Update GuidesLines to v2.2.0+ in your Dungeondraft mods folder.")
		return false

	if _gl_api.has_method("is_ready") and not _gl_api.is_ready():
		if LOGGER: LOGGER.warn("%s: GuidesLinesApi not ready yet (map still loading?)" % CLASS_NAME)
		return false

	if not _parent_mod:
		if LOGGER: LOGGER.error("%s: parent_mod not set." % CLASS_NAME)
		return false

	# --- Resolve polygon via GuidesLinesApi ---
	var result = _gl_api.compute_fill_polygon(coords)
	if typeof(result) != TYPE_DICTIONARY:
		return false

	var polygon: Array = result.get("polygon", [])
	if polygon.empty():
		if LOGGER: LOGGER.warn("%s: empty polygon returned at %s." % [CLASS_NAME, str(coords)])
		return false

	# --- Read current WallTool state ---
	var _global = _parent_mod.Global
	if not _global.World or not _global.World.Level:
		if LOGGER: LOGGER.error("%s: World/Level not loaded." % CLASS_NAME)
		return false

	var wall_texture = null
	var wall_color: Color = Color.white
	if _global.Editor and _global.Editor.Tools.has("WallTool"):
		var wt = _global.Editor.Tools["WallTool"]
		wall_texture = wt.Texture
		wall_color = wt.Color
	else:
		if LOGGER: LOGGER.warn("%s: WallTool not found, using defaults." % CLASS_NAME)

	var walls = _global.World.Level.Walls
	if not walls:
		if LOGGER: LOGGER.error("%s: Walls node not found in Level." % CLASS_NAME)
		return false

	# --- Create the closed wall ---
	var new_wall = walls.AddWall(
		PoolVector2Array(polygon),
		wall_texture,
		wall_color,
		true,            # loop = true → closed contour
		active_shadow,
		0,               # type = Auto
		active_joint,
		true             # normalizeUV
	)

	if not new_wall:
		if LOGGER: LOGGER.warn("%s: AddWall returned null." % CLASS_NAME)
		return false

	if LOGGER: LOGGER.info("%s: wall built with %d points." % [CLASS_NAME, polygon.size()])
	return true
