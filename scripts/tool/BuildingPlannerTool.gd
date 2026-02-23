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

# ============================================================================
# FEATURE MODULES
# ============================================================================

var _pattern_fill = null   # PatternFill
var _wall_builder = null   # WallBuilder
var _mirror_mode  = null   # MirrorMode

# ============================================================================
# STATE
# ============================================================================

enum Mode { NONE, PATTERN_FILL, WALL_BUILDER, MIRROR }

var _active_mode: int = Mode.PATTERN_FILL  # Default to first mode
var is_enabled: bool = false

# Active marker id used by Wall Builder and Mirror Mode (entered via UI SpinBox)
var active_marker_id: int = -1

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
	var PatternFillClass = ResourceLoader.load(root + "scripts/features/PatternFill.gd", "GDScript", false)
	var WallBuilderClass = ResourceLoader.load(root + "scripts/features/WallBuilder.gd", "GDScript", false)
	var MirrorModeClass  = ResourceLoader.load(root + "scripts/features/MirrorMode.gd",  "GDScript", false)

	if PatternFillClass:
		_pattern_fill = PatternFillClass.new(_gl_api, LOGGER, parent_mod)
	elif LOGGER:
		LOGGER.warn("%s: Failed to load PatternFill.gd" % CLASS_NAME)

	if WallBuilderClass:
		_wall_builder = WallBuilderClass.new(_gl_api, LOGGER)
	elif LOGGER:
		LOGGER.warn("%s: Failed to load WallBuilder.gd" % CLASS_NAME)

	if MirrorModeClass:
		_mirror_mode = MirrorModeClass.new(_gl_api, LOGGER)
	elif LOGGER:
		LOGGER.warn("%s: Failed to load MirrorMode.gd" % CLASS_NAME)

	if LOGGER:
		LOGGER.info("%s: features initialised." % CLASS_NAME)

# ============================================================================
# TOOL LIFECYCLE (called by BuildingPlanner.gd update loop)
# ============================================================================

# Called when this tool becomes active in the Dungeondraft toolset.
func Enable():
	is_enabled = true
	# Lazily build the pattern GridMenu now that the Editor is definitely ready
	if _ui and _ui.has_method("_try_build_grid_menu"):
		_ui._try_build_grid_menu()
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
	# Return the borrowed GridMenu to PatternShapeTool before we disappear
	if _ui and _ui.has_method("release_grid_menu"):
		_ui.release_grid_menu()
	_destroy_overlay()

# Called every frame while the mod is loaded (from BuildingPlanner.gd).
func Update(_delta):
	# Create the input overlay once WorldUI is available (even before Enable)
	if not _overlay and cached_worldui:
		_create_overlay()

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

## Executes Wall Builder on the active marker.
func execute_wall_build() -> bool:
	if active_marker_id < 0:
		if LOGGER: LOGGER.warn("%s: no marker selected for Wall Builder." % CLASS_NAME)
		return false
	if not _wall_builder:
		if LOGGER: LOGGER.error("%s: WallBuilder module not loaded." % CLASS_NAME)
		return false
	if not cached_world or not cached_world.Level:
		if LOGGER: LOGGER.error("%s: World/Level not loaded." % CLASS_NAME)
		return false
	var wall_node = cached_world.Level.get_node_or_null("Walls")
	return not _wall_builder.build(active_marker_id, wall_node).empty()

## Activates or deactivates Mirror Mode on the active marker.
func execute_mirror_toggle() -> bool:
	if not _mirror_mode:
		if LOGGER: LOGGER.error("%s: MirrorMode module not loaded." % CLASS_NAME)
		return false
	if _mirror_mode.is_active():
		_mirror_mode.deactivate()
		return false
	if active_marker_id < 0:
		if LOGGER: LOGGER.warn("%s: no marker selected for Mirror Mode." % CLASS_NAME)
		return false
	return _mirror_mode.activate(active_marker_id)
