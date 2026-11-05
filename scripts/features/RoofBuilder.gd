extends Reference

# BuildingPlanner - Dungeondraft Mod
# RoofBuilder: places a roof over the Shape marker area under a click.
#
# Workflow:
#   1. User clicks on the map while Roof Builder mode is active.
#   2. BuildingPlannerTool.handle_canvas_click(world_pos) is called.
#   3. GuidesLinesApi.compute_fill_polygon(coords) resolves the polygon.
#   4. Roofs.CreateRoof(sorting) creates the roof node.
#   5. World.AssignNodeID(roof) assigns a persistent ID (required for map saving).
#   6. Apply tile texture and shared level sunlight before creating geometry.
#   7. roof.Set(polygon, width, type) builds geometry as in native Roof.Load().
#
# Placement modes  (active_placement_mode):
#   0 Ridge  — polygon defines the ridge line. Eave spreads outward by active_width
#              beyond the polygon. Default / classic roof.
#   1 Expand — polygon edge is the eave (outer edge). Ridge is OUTSIDE the polygon:
#              polygon is inflated outward by active_width, so the roof is drawn
#              around the marked area.
#   2 Inset  — polygon edge is the eave (outer edge). Ridge is INSIDE the polygon:
#              polygon is shrunk inward by active_width, so the roof fills the
#              interior of the marked area down to the polygon boundary.
#
# Texture source: active_texture, selected explicitly in RoofPanel.
#
# Requires GuidesLines >= 2.2.0 (compute_fill_polygon).

const CLASS_NAME = "RoofBuilder"
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

var active_texture = null           # Texture — selected in RoofPanel
var active_width: float = 50.0      # eave width in pixels
var active_type: int = 0            # 0 = Gable, 1 = Hip, 2 = Dormer
var active_sorting: int = 0         # 0 = Over, 1 = Under
# 0 = Ridge (ridge along polygon edge, eave expands outward)
# 1 = Expand (eave at polygon, ridge expands OUTWARD — roof wraps around area)
# 2 = Inset  (eave at polygon, ridge shrinks INWARD  — roof fills inside area)
var active_placement_mode: int = 0
var active_shade: bool = false
var active_sun_direction: float = 0.0    # degrees
var active_shade_contrast: float = 0.5

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

## Places a roof over the Shape marker area under [coords] (world-space).
## Requires GuidesLines >= 2.2.0. Returns true on success.
func build_at(coords: Vector2) -> bool:
	var polygon = BuildingPlannerUtils.resolve_fill_polygon(_gl_api, coords, LOGGER)
	if polygon.empty():
		return false
	if not _parent_mod:
		return false

	# --- Build the actual roof footprint ---
	var roof_polygon: Array = _build_roof_polygon(polygon)
	if roof_polygon.empty():
		if LOGGER: LOGGER.warn("%s: roof polygon is empty after processing." % CLASS_NAME)
		return false

	var level = BuildingPlannerUtils.resolve_level(_parent_mod)
	if not level:
		if LOGGER: LOGGER.error("RoofBuilder: World/Level not loaded.")
		return false
	if not active_texture is Texture:
		if LOGGER: LOGGER.error("RoofBuilder: select a valid texture before building.")
		return false
	var _global = _parent_mod.Global
	var roofs_node = BuildingPlannerUtils.get_roofs(level)
	if not roofs_node:
		if LOGGER: LOGGER.error("%s: Roofs node not found in Level." % CLASS_NAME)
		return false

	# --- Create the roof node ---
	var new_roof = roofs_node.CreateRoof(active_sorting)
	if not new_roof:
		if LOGGER: LOGGER.error("%s: CreateRoof returned null." % CLASS_NAME)
		return false

	# --- Assign persistent Node ID (required for correct map file saving) ---
	if not _global.World.has_method("AssignNodeID"):
		if LOGGER: LOGGER.error("%s: World.AssignNodeID not found — roof skipped." % CLASS_NAME)
		BuildingPlannerUtils.free_node(new_roof, _global.World)
		return false
	_global.World.AssignNodeID(new_roof)

	# Match Roof.Load: Hip edges must be created with the selected texture.
	new_roof.SetTileTexture(active_texture)

	# Dungeondraft persists sunlight on the level's Roofs container, in degrees.
	var sunlight_before = [roofs_node.Shade, roofs_node.SunDirection, roofs_node.ShadeContrast]
	roofs_node.UpdateSunlight(active_shade, active_sun_direction, active_shade_contrast)
	new_roof.Set(PoolVector2Array(roof_polygon), active_width, active_type)

	if LOGGER: LOGGER.info("%s: roof built with %d points (type=%d sorting=%d width=%.1f mode=%d)." % [
			CLASS_NAME, roof_polygon.size(), active_type, active_sorting, active_width, active_placement_mode])

	# --- Record undo/redo history ---
	BuildingPlannerHistory.record_action(_parent_mod, LOGGER, BuildingPlannerHistory.RoofBuilderRecord.new(_parent_mod, LOGGER, new_roof, sunlight_before))

	return true

# ============================================================================
# PRIVATE HELPERS
# ============================================================================

## Builds the final roof footprint from an already validated marker polygon.
##
## Mode 0 — Ridge: polygon as-is (ridge along the marker edge).
## Mode 1 — Expand: inflate polygon OUTWARD by active_width via offset_polygon_2d
##           (positive delta). Ridge is outside the marker, eave is at the marker.
## Mode 2 — Inset: shrink polygon INWARD by active_width via offset_polygon_2d
##           (negative delta). Ridge is inside the marker, eave is at the marker.
##
## Dungeondraft's native roof tool itself does not close the contour automatically.
## To cover the seam between the last and first segment we append out[0] and out[1]
## at the end, creating a two-point overlap: [A,B,C,D] → [A,B,C,D,A,B].
func _build_roof_polygon(polygon: Array) -> Array:
	var out: Array

	match active_placement_mode:
		1, 2: # Expand / Inset
			var result = Geometry.offset_polygon_2d(PoolVector2Array(polygon), active_width if active_placement_mode == 1 else -active_width)
			if result.empty():
				if LOGGER: LOGGER.warn("%s: roof offset returned empty; skipping roof." % CLASS_NAME)
				return []
			else:
				# ponytail: one offset contour; create multiple roofs if split footprints are needed.
				var best: PoolVector2Array = result[0]
				var best_area = abs(BuildingPlannerUtils.signed_area(best))
				for i in range(1, result.size()):
					var area = abs(BuildingPlannerUtils.signed_area(result[i]))
					if area > best_area:
						best = result[i]
						best_area = area
				out = BuildingPlannerUtils.sanitize_polygon(best)
		_: # Ridge (mode 0) — polygon as-is
			out = polygon.duplicate()

	# Append the first two points at the end to close the visible seam.
	# DD's roof renderer leaves a gap between the last and first segment;
	# the overlap [... D, A, B] covers it without creating degenerate geometry.
	if out.size() >= 2:
		out.append(out[0])
		out.append(out[1])

	return out
