extends Reference

# BuildingPlanner - Dungeondraft Mod
# PatternFill: fills the Shape marker area under a click with the selected pattern.
#
# Workflow:
#   1. User clicks on the map while Pattern Fill mode is active.
#   2. BuildingPlannerTool.handle_pattern_fill_click(world_pos) is called.
#   3. GuidesLinesApi.compute_fill_polygon(coords) resolves the polygon.
#   4. PatternShapes.DrawPolygon(polygon) creates the shape.
#   5. SetOptions / SetLayer / SetPoints apply texture, color, layer, outline.
#
# Requires GuidesLines >= 2.2.0 (compute_fill_polygon, get_shape_polygon).

const CLASS_NAME = "PatternFill"

# ============================================================================
# REFERENCES
# ============================================================================

var _gl_api = null
var LOGGER = null
var _parent_mod = null

# ============================================================================
# SETTINGS  (mirrored to PatternShapeTool before each fill)
# ============================================================================

var active_texture = null    # Texture — selected in our own GridMenu
var active_color: Color = Color.white
var active_rotation: float = 0.0   # degrees
var active_outline: bool = false
var active_layer: int = 0

# ============================================================================
# INIT
# ============================================================================

func _init(gl_api, logger, parent_mod = null):
	_gl_api = gl_api
	LOGGER = logger
	_parent_mod = parent_mod

# ============================================================================
# FILL BY WORLD POSITION
# ============================================================================

## Fills the Shape marker area under [coords] (world-space) with the active texture.
## Requires GuidesLines >= 2.2.0. Returns true on success.
func fill_at(coords: Vector2) -> bool:
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

	# --- Resolve polygon via GuidesLinesApi ---
	var result = _gl_api.compute_fill_polygon(coords)
	if typeof(result) != TYPE_DICTIONARY:
		return false

	var polygon: Array = result.get("polygon", [])
	if polygon.empty():
		if LOGGER: LOGGER.warn("%s: empty polygon returned at %s." % [CLASS_NAME, str(coords)])
		return false


	# --- Dungeondraft context ---
	if not _parent_mod:
		if LOGGER: LOGGER.error("%s: parent_mod not set." % CLASS_NAME)
		return false
	var _global = _parent_mod.Global
	if not _global.World or not _global.World.Level:
		if LOGGER: LOGGER.error("%s: World/Level not loaded." % CLASS_NAME)
		return false

	var pattern_shapes = _global.World.Level.PatternShapes

	# --- Snapshot existing shapes to identify newly created ones ---
	var shapes_before: Array = pattern_shapes.GetShapes()
	var count_before: int = shapes_before.size()

	# --- Create the PatternShape ---
	pattern_shapes.DrawPolygon(PoolVector2Array(polygon), false)

	# --- Apply settings to newly created shape(s) ---
	var shapes_after: Array = pattern_shapes.GetShapes()
	for i in range(count_before, shapes_after.size()):
		var shape = shapes_after[i]
		if not shape or not is_instance_valid(shape):
			continue
		if active_texture:
			shape.SetOptions(active_texture, active_color, deg2rad(active_rotation))
		shape.SetLayer(active_layer)
		if active_outline:
			shape.SetPoints(shape.polygon, true)

	return true
