extends Reference

# BuildingPlanner - Dungeondraft Mod
# Main tool class. Manages mode switching, GuidesLinesApi bridge,
# and delegates work to feature modules.

const CLASS_NAME = "BuildingPlannerTool"

# ============================================================================
# DEPENDENCIES
# ============================================================================

var LOGGER = null
var _gl_api = null  # GuidesLinesApi instance

# ============================================================================
# CACHED REFERENCES (updated every frame by BuildingPlanner.gd)
# ============================================================================

var parent_mod = null
var cached_world = null
var cached_worldui = null
var cached_camera = null
var cached_snappy_mod = null   # Lievven.Snappy_Mod reference (or null)

# ============================================================================
# FEATURE MODULES
# ============================================================================

var _pattern_fill = null   # PatternFill
var _wall_builder = null   # WallBuilder
var _room_builder = null   # RoomBuilder

# ============================================================================
# STATE
# ============================================================================

enum Mode { NONE, PATTERN_FILL, WALL_BUILDER, ROOM_BUILDER }

var _active_mode: int = Mode.PATTERN_FILL  # Default to first mode
var is_enabled: bool = false

# Snapshot of GuidesLines tool state captured on Enable().
# Refreshed once per activation cycle — both tools cannot be active simultaneously,
# so the state cannot change while BuildingPlanner is the active tool.
var gl_tool_state: Dictionary = {}

# ============================================================================
# INPUT OVERLAY
# ============================================================================

var _overlay = null   # BuildingPlannerOverlay Node2D instance

# ============================================================================
# UI
# ============================================================================

var tool_panel = null
var _ui = null

# ============================================================================
# INIT
# ============================================================================

# Store only the parent reference during construction.
# Call setup() explicitly after LOGGER has been assigned from outside.
func _init(mod):
	parent_mod = mod

# Called by BuildingPlanner.gd._create_tool() after LOGGER is assigned.
# Connects to GuidesLinesApi and loads feature modules.
func setup():
	_connect_gl_api()

func _connect_gl_api():
	var api = parent_mod.Global.API
	if not api:
		if LOGGER: LOGGER.error("%s: Global.API not available." % CLASS_NAME)
		return
	if api.has("GuidesLinesApi"):
		_gl_api = api.GuidesLinesApi
		_init_features()
	else:
		api.connect("api_registered", self, "_on_api_registered")

func _on_api_registered(api_id, _api):
	if api_id == "GuidesLinesApi":
		_gl_api = parent_mod.Global.API.GuidesLinesApi
		_init_features()
		if LOGGER:
			LOGGER.info("%s: GuidesLinesApi connected." % CLASS_NAME)

# Load and instantiate feature modules.
# Called once when GuidesLinesApi becomes available.
func _init_features():
	var root = parent_mod.Global.Root
	var PatternFillClass = ResourceLoader.load(root + "scripts/features/PatternFill.gd",  "GDScript", false)
	var WallBuilderClass = ResourceLoader.load(root + "scripts/features/WallBuilder.gd",  "GDScript", false)
	var RoomBuilderClass = ResourceLoader.load(root + "scripts/features/RoomBuilder.gd",  "GDScript", false)

	if PatternFillClass:
		_pattern_fill = PatternFillClass.new(_gl_api, LOGGER, parent_mod)
	elif LOGGER:
		LOGGER.warn("%s: Failed to load PatternFill.gd" % CLASS_NAME)

	if WallBuilderClass:
		_wall_builder = WallBuilderClass.new(_gl_api, LOGGER, parent_mod)
	elif LOGGER:
		LOGGER.warn("%s: Failed to load WallBuilder.gd" % CLASS_NAME)

	if RoomBuilderClass:
		_room_builder = RoomBuilderClass.new(_gl_api, LOGGER, parent_mod)
	elif LOGGER:
		LOGGER.warn("%s: Failed to load RoomBuilder.gd" % CLASS_NAME)

	if LOGGER:
		LOGGER.info("%s: features initialised." % CLASS_NAME)

# ============================================================================
# TOOL LIFECYCLE (called by BuildingPlanner.gd update loop)
# ============================================================================

# Called when this tool becomes active in the Dungeondraft toolset.
func Enable():
	is_enabled = true
	# Capture GuidesLines state once — it cannot change while we are the active tool
	if _gl_api:
		gl_tool_state = _gl_api.get_tool_state()
	# Lazily build all texture grid menus now that the Editor is definitely ready
	if _ui and _ui.has_method("try_build_all_grid_menus"):
		_ui.try_build_all_grid_menus()
	# Restore the active mode from the UI selector (was reset to NONE on Disable)
	if _ui and _ui._mode_selector:
		var mode = _ui._mode_selector.get_item_id(_ui._mode_selector.selected)
		_set_mode(mode)
	else:
		_set_mode(Mode.PATTERN_FILL)

# Called when the user switches away from this tool.
func Disable():
	is_enabled = false
	# Do NOT reset _active_mode here — the overlay already guards on is_enabled,
	# and we need the mode to survive Disable/Enable cycles (e.g. SelectTool round-trip).
	# Return all borrowed texture grid menus before we disappear
	if _ui and _ui.has_method("release_all_grid_menus"):
		_ui.release_all_grid_menus()
	# Clear Room Builder preview and purge object registry
	if _room_builder:
		_room_builder.stop_preview()
		_room_builder.on_disabled()
	_destroy_overlay()

# Called every frame while the mod is loaded (from BuildingPlanner.gd).
func Update(_delta):
	# Create the input overlay once WorldUI is available (even before Enable)
	if not _overlay and cached_worldui:
		_create_overlay()

	# Drive Room Builder preview every frame while active
	if is_enabled and _active_mode == Mode.ROOM_BUILDER and _room_builder and cached_worldui:
		# Match GuidesLines MarkerOverlay logic: IsInsideBounds alone is not enough —
		# viewport x < 450 means the cursor is over the left tool panel (UI area).
		var vp_mouse: Vector2 = cached_worldui.get_viewport().get_mouse_position()
		var cursor_in_ui: bool = not cached_worldui.IsInsideBounds or vp_mouse.x < 450
		_room_builder.update_preview(cached_worldui.MousePosition, cursor_in_ui, gl_tool_state)

# ============================================================================
# OVERLAY
# ============================================================================

func _create_overlay():
	var root = parent_mod.Global.Root
	var OverlayClass = ResourceLoader.load(
		root + "scripts/overlay/BuildingPlannerOverlay.gd", "GDScript", false)
	if not OverlayClass:
		if LOGGER: LOGGER.warn("%s: failed to load BuildingPlannerOverlay.gd" % CLASS_NAME)
		return
	_overlay = OverlayClass.new()
	_overlay.tool = self
	cached_worldui.add_child(_overlay)

func _destroy_overlay():
	if _overlay:
		_overlay.queue_free()
		_overlay = null

# ============================================================================
# UI PANEL
# ============================================================================

# Creates and populates the tool's sidebar UI panel.
# Called once after tool_panel is assigned in BuildingPlanner.gd.
func create_ui_panel():
	if not tool_panel:
		return

	var root = parent_mod.Global.Root
	var UIClass = ResourceLoader.load(root + "scripts/tool/BuildingPlannerToolUI.gd", "GDScript", false)
	if not UIClass:
		if LOGGER: LOGGER.warn("%s: Failed to load BuildingPlannerToolUI.gd" % CLASS_NAME)
		return

	_ui = UIClass.new(self, LOGGER)
	_ui.build(tool_panel)

# ============================================================================
# MODE
# ============================================================================

func _set_mode(mode: int):
	# Clear Room Builder preview when leaving that mode
	if _active_mode == Mode.ROOM_BUILDER and mode != Mode.ROOM_BUILDER and _room_builder:
		_room_builder.stop_preview()
	_active_mode = mode

# ============================================================================
# EXECUTE ACTIONS (called from UI)
# ============================================================================

## Called by BuildingPlannerOverlay when the user left-clicks in Pattern Fill mode.
func handle_pattern_fill_click(world_pos: Vector2) -> void:
	if not _pattern_fill:
		if LOGGER: LOGGER.error("%s: PatternFill module not loaded." % CLASS_NAME)
		return
	_pattern_fill.fill_at(world_pos)

## Called by BuildingPlannerOverlay when the user left-clicks in Wall Builder mode.
func handle_wall_builder_click(world_pos: Vector2) -> void:
	if not _wall_builder:
		if LOGGER: LOGGER.error("%s: WallBuilder module not loaded." % CLASS_NAME)
		return
	_wall_builder.build_at(world_pos)

## Called by BuildingPlannerOverlay when the user left-clicks in Room Builder mode.
func handle_room_builder_click(world_pos: Vector2) -> void:
	if not _room_builder:
		if LOGGER: LOGGER.error("%s: RoomBuilder module not loaded." % CLASS_NAME)
		return
	_room_builder.build_room_at(world_pos, gl_tool_state)

# ============================================================================
# SNAP
# ============================================================================

## Snaps [position] to the grid.
## Uses Snappy Mod (get_snapped_position) when available,
## otherwise falls back to vanilla WorldUI.GetSnappedPosition.
func snap_position_to_grid(position: Vector2) -> Vector2:
	if cached_snappy_mod and cached_snappy_mod.has_method("get_snapped_position"):
		return cached_snappy_mod.get_snapped_position(position)
	if cached_worldui:
		return cached_worldui.GetSnappedPosition(position)
	return position

