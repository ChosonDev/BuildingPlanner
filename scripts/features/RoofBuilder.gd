extends Reference

# BuildingPlanner - Dungeondraft Mod
# RoofBuilder: places a roof over the Shape marker area under a click.
#
# Workflow:
#   1. User clicks on the map while Roof Builder mode is active.
#   2. BuildingPlannerTool.handle_roof_builder_click(world_pos) is called.
#   3. GuidesLinesApi.compute_fill_polygon(coords) resolves the polygon.
#   4. Roofs.CreateRoof(sorting) creates the roof node.
#   5. World.AssignNodeID(roof) assigns a persistent ID (required for map saving).
#   6. roof.Set(polygon, width, type) sets the geometry.
#   7. roof.SetTileTexture(texture) applies the tile style.
#   8. roof.SetSunlight() applies shade settings when enabled.
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
# Texture source: active_texture (set from our RoofPanel), with automatic
# fallback to the currently selected RoofTool.Texture when active_texture is null.
#
# Requires GuidesLines >= 2.2.0 (compute_fill_polygon).

const CLASS_NAME = "RoofBuilder"
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

var active_texture = null           # Texture — from RoofPanel or null (uses RoofTool)
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

	# --- Build the actual roof footprint ---
	var roof_polygon: Array = _build_roof_polygon(polygon)
	if roof_polygon.empty():
		if LOGGER: LOGGER.warn("%s: roof polygon is empty after processing." % CLASS_NAME)
		return false

	# --- Dungeondraft context ---
	if not _parent_mod:
		if LOGGER: LOGGER.error("%s: parent_mod not set." % CLASS_NAME)
		return false

	var _global = _parent_mod.Global
	if not _global.World or not _global.World.Level:
		if LOGGER: LOGGER.error("%s: World/Level not loaded." % CLASS_NAME)
		return false

	# --- Resolve texture: prefer active_texture, fall back to RoofTool ---
	var tex = active_texture
	if not tex and _global.Editor and _global.Editor.Tools.has("RoofTool"):
		tex = _global.Editor.Tools["RoofTool"].Texture

	# --- Get Roofs container (Level property first, child node fallback) ---
	var roofs_node = _global.World.Level.Roofs
	if not roofs_node:
		roofs_node = _global.World.Level.get_node_or_null("Roofs")
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
		_free_roof(new_roof)
		return false
	_global.World.AssignNodeID(new_roof)

	# --- Set geometry (must be called after AssignNodeID) ---
	new_roof.Set(PoolVector2Array(roof_polygon), active_width, active_type)

	# --- Apply texture ---
	if tex:
		new_roof.SetTileTexture(tex)

	# --- Apply sunlight / shade ---
	if active_shade:
		new_roof.SetSunlight(true, active_sun_direction, active_shade_contrast)

	if LOGGER: LOGGER.info("%s: roof built with %d points (type=%d sorting=%d width=%.1f mode=%d)." % [
			CLASS_NAME, roof_polygon.size(), active_type, active_sorting, active_width, active_placement_mode])

	# --- Record undo/redo history ---
	_record_history(BuildingPlannerHistory.RoofBuilderRecord.new(_parent_mod, LOGGER, new_roof))

	return true

# ============================================================================
# PRIVATE HELPERS
# ============================================================================

## Builds the final roof footprint polygon from the raw marker polygon.
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
		1: # Expand — inflate outward
			var result = Geometry.offset_polygon_2d(PoolVector2Array(polygon), active_width)
			if result.empty():
				if LOGGER: LOGGER.warn("%s: Expand offset returned empty; using plain polygon." % CLASS_NAME)
				out = polygon.duplicate()
			else:
				var best: PoolVector2Array = result[0]
				for i in range(1, result.size()):
					if result[i].size() > best.size():
						best = result[i]
				out = Array(best)
		2: # Inset — shrink inward
			var result = Geometry.offset_polygon_2d(PoolVector2Array(polygon), -active_width)
			if result.empty():
				if LOGGER: LOGGER.warn("%s: Inset offset returned empty; using plain polygon." % CLASS_NAME)
				out = polygon.duplicate()
			else:
				var best: PoolVector2Array = result[0]
				for i in range(1, result.size()):
					if result[i].size() > best.size():
						best = result[i]
				out = Array(best)
		_: # Ridge (mode 0) — polygon as-is
			out = polygon.duplicate()

	# Append the first two points at the end to close the visible seam.
	# DD's roof renderer leaves a gap between the last and first segment;
	# the overlap [... D, A, B] covers it without creating degenerate geometry.
	if out.size() >= 2:
		out.append(out[0])
		out.append(out[1])

	return out

## Safely removes [roof] from the scene tree and frees it.
func _free_roof(roof) -> void:
	if roof == null or not is_instance_valid(roof):
		return
	var p = roof.get_parent()
	if p:
		p.remove_child(roof)
	roof.queue_free()

# ============================================================================
# HISTORY HELPERS
# ============================================================================

## Records [record] into the HistoryApi (undo/redo stack) if available.
func _record_history(record) -> void:
	if not _parent_mod:
		return
	var api = _parent_mod.Global.API
	if api and api.has("HistoryApi"):
		api.HistoryApi.record(record, 100)
	elif LOGGER:
		LOGGER.warn("%s: HistoryApi not available — action will not be undoable." % CLASS_NAME)
