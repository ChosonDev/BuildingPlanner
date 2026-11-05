extends Reference

# BuildingPlanner - Dungeondraft Mod
# PathBuilder: traces a nearby Path marker or a filled Shape outline.
#
# Workflow:
#   1. User clicks on the map while Path Builder mode is active.
#   2. BuildingPlannerTool.handle_canvas_click(world_pos) is called.
#   3. Resolve a nearby Path marker, falling back to compute_fill_polygon(coords).
#   4. Pathways.LoadPathway(data) creates and initializes the native path.
#
# Texture source: active_texture, captured by this feature's PathPanel.
# Width/Smoothness/Effects: controlled by PathPanel UI elements.
# Requires GuidesLines >= 2.2.0 (compute_fill_polygon).

const CLASS_NAME = "PathBuilder"
const BuildingPlannerHistory = preload("../tool/BuildingPlannerHistory.gd")
const BuildingPlannerUtils   = preload("../utils/BuildingPlannerUtils.gd")

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
var active_color:      Color = Color.white
var active_width:      float = 1.0          # path width
var active_smoothness: float = 0.0          # smoothness (0.0 - 1.0)
var active_layer:      int   = BuildingPlannerUtils.DEFAULT_LAYER          # layer z_index — 100 = User Layer 1
var active_sorting:    int   = 0            # 0 = Over, 1 = Under
var active_fade_in:    bool  = false        # fade in effect
var active_fade_out:   bool  = false        # fade out effect
var active_grow:       bool  = false        # grow (taper start)
var active_shrink:     bool  = false        # shrink (taper end)
var active_block_light: bool = false        # block light

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

	var path = _create_path(outline.points, null, outline.closed)
	if not is_instance_valid(path):
		return false
	BuildingPlannerHistory.record_action(_parent_mod, LOGGER, BuildingPlannerHistory.PathBuilderRecord.new(_parent_mod, path))
	return true

## Snapshot the complete style; callers own the returned Dictionary.
func get_settings() -> Dictionary:
	return {
		"active_texture": active_texture,
		"active_color": active_color,
		"active_width": active_width,
		"active_smoothness": active_smoothness,
		"active_layer": active_layer,
		"active_sorting": active_sorting,
		"active_fade_in": active_fade_in,
		"active_fade_out": active_fade_out,
		"active_grow": active_grow,
		"active_shrink": active_shrink,
		"active_block_light": active_block_light,
	}

## Explicit saved settings leave the live UI selection untouched.
func _create_path(polygon: Array, level = null, closed: bool = true, settings = null):
	if settings == null:
		settings = get_settings()
	# --- Access Pathways for path creation ---
	level = BuildingPlannerUtils.resolve_level(_parent_mod, level)
	if not level:
		if LOGGER: LOGGER.error("%s: World/Level not loaded." % CLASS_NAME)
		return null
	var pathways = level.Pathways
	if not pathways:
		if LOGGER: LOGGER.error("%s: Pathways node not found in Level." % CLASS_NAME)
		return null

	# Use this feature's selected texture
	var path_texture = settings.active_texture
	if not path_texture is Texture:
		if LOGGER: LOGGER.error("PathBuilder: select a valid texture before building.")
		return null

	# Match Pathway.Save / DictionaryEx; native Load initializes IDs, preview,
	# gradient and occlusion without constructing a temporary path first.
	var origin = polygon[0]
	var local_points = PoolVector2Array()
	for point in polygon:
		local_points.append(point - origin)
	if closed:
		local_points.append(Vector2.ZERO) # Preserve the explicit seam without copying the input.
	var path_data = {
		"position": var2str(origin),
		"rotation": 0.0,
		"scale": var2str(Vector2.ONE),
		"edit_points": var2str(local_points),
		"texture": path_texture.resource_path,
		"width": path_texture.get_height() * settings.active_width,
		"smoothness": settings.active_smoothness,
		"layer": settings.active_layer,
		"fade_in": settings.active_fade_in,
		"fade_out": settings.active_fade_out,
		"grow": settings.active_grow,
		"shrink": settings.active_shrink,
		"block_light": settings.active_block_light,
		"loop": false,
	}
	var path_index = 0 if settings.active_sorting == 1 else -1
	var loaded_path = BuildingPlannerUtils.load_path(_parent_mod.Global, pathways, path_data, settings.active_color, path_index)
	if not loaded_path and LOGGER:
		LOGGER.error("%s: LoadPathway() returned null!" % CLASS_NAME)
	return loaded_path
