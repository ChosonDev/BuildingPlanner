extends Reference

# BuildingPlanner - Dungeondraft Mod
# PathBuilder: places a path along the outline of a Shape marker under a click.
#
# Workflow:
#   1. User clicks on the map while Path Builder mode is active.
#   2. BuildingPlannerTool.handle_path_builder_click(world_pos) is called.
#   3. GuidesLinesApi.compute_fill_polygon(coords) resolves the polygon.
#   4. Pathways.CreatePath(texture, layer, sorting, ...) creates the path.
#   5. Pathway.SetEditPoints(points) + Smooth() + SetWidthScale() configure it.
#
# Texture source: PathTool.Texture (mirrored via Controls["Texture"] GridMenu).
# Width/Smoothness/Effects: controlled by PathPanel UI elements.
# Requires GuidesLines >= 2.2.0 (compute_fill_polygon).

const CLASS_NAME = "PathBuilder"
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

# Texture is always read from PathTool at click time (our GridMenu drives it via
# OnItemSelected). Other settings are stored here so the UI controls have effect.
var active_color:      Color = Color.white
var active_width:      float = 1.0          # path width
var active_smoothness: float = 0.0          # smoothness (0.0 - 1.0)
var active_layer:      int   = 0            # layer (0-9)
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

## Builds a path along the Shape marker outline under [coords] (world-space).
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

	# Close the polygon by adding first point at the end (Line2D doesn't have built-in closed property)
	if polygon.size() > 0:
		polygon.append(polygon[0])

	# --- Access Pathways for path creation ---
	var _global = _parent_mod.Global
	if not _global.World or not _global.World.Level:
		if LOGGER: LOGGER.error("%s: World/Level not loaded." % CLASS_NAME)
		return false

	var pathways = _global.World.Level.Pathways
	if not pathways:
		if LOGGER: LOGGER.error("%s: Pathways node not found in Level." % CLASS_NAME)
		return false

	# Get texture from PathTool
	var path_texture = null
	if _global.Editor and _global.Editor.Tools.has("PathTool"):
		var pt = _global.Editor.Tools["PathTool"]
		path_texture = pt.Texture
	else:
		if LOGGER: LOGGER.warn("%s: PathTool not found, using defaults." % CLASS_NAME)

	# Create path using CreatePath API
	var new_path = pathways.CreatePath(
		path_texture,
		active_layer,
		active_sorting,
		active_fade_in,
		active_fade_out,
		active_grow,
		active_shrink
	)
	
	if not new_path:
		if LOGGER: LOGGER.error("%s: CreatePath returned null." % CLASS_NAME)
		return false

	# Configure path properties
	new_path.position = Vector2.ZERO
	new_path.SetEditPoints(PoolVector2Array(polygon))
	new_path.Smoothness = active_smoothness
	new_path.Smooth()
	new_path.SetWidthScale(active_width)
	new_path.modulate = active_color
	
	if active_block_light:
		new_path.SetBlockLight(true)

	# Set metadata for SelectTool integration (lowercase "node_id" required by C# code)
	# Find max node_id from existing paths
	var max_node_id = 0  # Start from 1, not 0
	for child in pathways.get_children():
		if child == new_path:
			continue
		if child.has_meta("node_id"):
			var nid = child.get_meta("node_id")
			if typeof(nid) == TYPE_INT and nid > max_node_id:
				max_node_id = nid
	
	# Assign node_id and preview metadata
	var new_node_id = max_node_id + 1
	new_path.set_meta("node_id", new_node_id)
	new_path.set_meta("preview", false)

	# Register path via Save/Load cycle (mimics map loading for proper Editor registration)
	var path_data = new_path.Save(false)
	
	if not path_data or path_data.empty():
		if LOGGER: LOGGER.error("%s: Save() returned empty data!" % CLASS_NAME)
		return false
	
	# Get the path's position in parent before removing
	var path_index = new_path.get_index()
	
	# Remove the temporary path
	new_path.queue_free()
	
	# Load it back through LoadPathway (proper initialization)
	var loaded_path = pathways.LoadPathway(path_data)
	
	if not loaded_path:
		if LOGGER: LOGGER.error("%s: LoadPathway() returned null!" % CLASS_NAME)
		return false
	
	# Restore original position in tree
	pathways.move_child(loaded_path, path_index)

	if LOGGER: LOGGER.info("%s: path built with %d points." % [CLASS_NAME, polygon.size()])
	return true
