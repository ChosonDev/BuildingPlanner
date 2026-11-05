extends Reference

# BuildingPlanner - Dungeondraft Mod
# PatternFill: fills the Shape marker area under a click with the selected pattern.
#
# Workflow:
#   1. User clicks on the map while Pattern Fill mode is active.
#   2. BuildingPlannerTool.handle_canvas_click(world_pos) is called.
#   3. GuidesLinesApi.compute_fill_polygon(coords) resolves the polygon.
#   4. PatternShapes.LoadShape() creates the configured shape without native history.
#   5. A custom history record owns the operation.
#
# Requires GuidesLines >= 2.2.0 (compute_fill_polygon, get_shape_polygon).

const CLASS_NAME = "PatternFill"
const BuildingPlannerUtils = preload("../utils/BuildingPlannerUtils.gd")
const BuildingPlannerHistory = preload("../tool/BuildingPlannerHistory.gd")

# ============================================================================
# REFERENCES
# ============================================================================

var _gl_api = null
var LOGGER = null
var _parent_mod = null

# ============================================================================
# SETTINGS (owned by this feature)
# ============================================================================

var active_texture = null    # Texture — selected in our own GridMenu
var active_color: Color = Color.white
var active_rotation: float = 0.0   # degrees
var active_outline: bool = false
var active_layer: int = BuildingPlannerUtils.DEFAULT_LAYER  # layer z_index — 100 = User Layer 1

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
func build_at(coords: Vector2) -> bool:
	var polygon = BuildingPlannerUtils.resolve_fill_polygon(_gl_api, coords, LOGGER)
	if polygon.empty():
		return false


	var shape = _create_shape(polygon)
	if not is_instance_valid(shape):
		return false
	BuildingPlannerHistory.record_action(_parent_mod, LOGGER, BuildingPlannerHistory.PatternFillRecord.new(_parent_mod, shape))
	return true

## Snapshot the complete style; callers own the returned Dictionary.
func get_settings() -> Dictionary:
	return {
		"active_texture": active_texture,
		"active_color": active_color,
		"active_rotation": active_rotation,
		"active_outline": active_outline,
		"active_layer": active_layer,
	}

## Explicit saved settings leave the live UI selection untouched.
func _create_shape(polygon: Array, level = null, settings = null):
	if settings == null:
		settings = get_settings()
	if not settings.active_texture is Texture:
		if LOGGER: LOGGER.error("PatternFill: select a valid texture before building.")
		return null
	# --- Dungeondraft context ---
	level = BuildingPlannerUtils.resolve_level(_parent_mod, level)
	if not level:
		if LOGGER: LOGGER.error("%s: World/Level not loaded." % CLASS_NAME)
		return null
	if not level.PatternShapes:
		if LOGGER: LOGGER.error("PatternFill: PatternShapes node not found in Level.")
		return null

	# Native DrawPolygon records its own history. LoadShape creates the same native
	# node without adding an independent undo step or using PatternShapeTool state.
	# Dictionary values match the host's PatternShape.Save / DictionaryEx format.
	var data = {
		"points": var2str(PoolVector2Array(polygon)),
		"position": var2str(Vector2.ZERO),
		"scale": var2str(Vector2.ONE),
		"shape_rotation": 0.0,
		"layer": settings.active_layer,
		"color": settings.active_color.to_html(),
		"outline": settings.active_outline,
		"rotation": deg2rad(settings.active_rotation),
		"texture": settings.active_texture.resource_path,
	}
	var shape = level.PatternShapes.LoadShape(data)
	if not is_instance_valid(shape):
		if LOGGER: LOGGER.error("PatternFill: LoadShape() returned null.")
		return null
	return shape
