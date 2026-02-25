# BuildingPlanner - Dungeondraft Mod
# Main mod entry point. Creates and manages the BuildingPlannerTool in Dungeondraft.
#
# File Structure:
#   - BuildingPlanner.gd: Main mod file (this file)
#   - scripts/tool/BuildingPlannerTool.gd: Tool logic — mode switching, GL API bridge
#   - scripts/tool/BuildingPlannerToolUI.gd: Sidebar UI panel
#   - scripts/tool/BuildingPlannerHistory.gd: Undo/redo history record classes
#   - scripts/features/PatternFill.gd: Feature — fill Shape marker area with pattern
#   - scripts/features/WallBuilder.gd: Feature — place walls along marker outline
#   - scripts/utils/BuildingPlannerUtils.gd: Shared geometry and helper functions

var script_class = "tool"

const CLASS_NAME = "BuildingPlanner"

# ============================================================================
# _LIB API
# ============================================================================

var LOGGER = null

# ============================================================================
# ICON PATHS
# ============================================================================

const TOOL_ICON_PATH = "icons/building_planner_icon.png"

# ============================================================================
# EXTERNAL CLASSES
# ============================================================================

var BuildingPlannerToolClass = null

# ============================================================================
# TOOL INSTANCE
# ============================================================================

var _tool = null
var _tool_created = false

# ============================================================================
# SNAPPY MOD
# ============================================================================

# Reference to Lievven.Snappy_Mod (optional custom snap mod).
# Detected once after the first map load; never changes during a session.
var _cached_snappy_mod = null
var _snappy_mod_checked = false

# ============================================================================
# LIFECYCLE
# ============================================================================

# Called by Dungeondraft when the mod is loaded.
# Registers with _Lib, initialises Logger, and loads script classes.
func start():
	if Engine.has_signal("_lib_register_mod"):
		Engine.emit_signal("_lib_register_mod", self)

		if self.Global.API and self.Global.API.has("Logger"):
			LOGGER = self.Global.API.Logger.for_class(CLASS_NAME)
			LOGGER.info("Mod starting - version 1.0.8")
		else:
			print("BuildingPlanner: _Lib registered but Logger not available")
	else:
		print("BuildingPlanner: _Lib not found — mod features unavailable!")
		return

	if not self.Global or not self.Global.has("Root"):
		if LOGGER: LOGGER.error("self.Global.Root not available!")
		else: print("BuildingPlanner: ERROR - self.Global.Root not available!")
		return

	BuildingPlannerToolClass = ResourceLoader.load(
		self.Global.Root + "scripts/tool/BuildingPlannerTool.gd", "GDScript", false)
	if not BuildingPlannerToolClass:
		if LOGGER: LOGGER.error("Failed to load BuildingPlannerTool.gd")
		else: print("BuildingPlanner: ERROR - Failed to load BuildingPlannerTool.gd")

# Called every frame by Dungeondraft.
# Creates the tool on first available frame after the Toolset is ready,
# then manages Enable/Disable/Update of the tool each frame.
func update(_delta):
	# Create tool once when Editor and Toolset are both ready
	if not _tool_created and Global.Editor != null and Global.Editor.Toolset != null:
		_create_tool()
		_tool_created = true

	# Require a loaded map before doing anything else
	if Global.World == null or Global.WorldUI == null:
		return

	# Detect Snappy Mod once after the map is loaded.
	# Mods are registered before map creation and do not change during a session,
	# so a single check per session is sufficient.
	if not _snappy_mod_checked:
		if Global.API and Global.API.has("ModRegistry"):
			var registered = Global.API.ModRegistry.get_registered_mods()
			if registered.has("Lievven.Snappy_Mod"):
				var mod_info = registered["Lievven.Snappy_Mod"]
				if mod_info.mod:
					_cached_snappy_mod = mod_info.mod
					if LOGGER:
						var mod_name = mod_info.mod_meta.get("name", "Snappy Mod")
						var mod_version = mod_info.mod_meta.get("version", "unknown")
						LOGGER.info("%s: Snappy Mod found (%s v%s)" % [CLASS_NAME, mod_name, mod_version])
			if not _cached_snappy_mod and LOGGER:
				LOGGER.debug("%s: Snappy Mod not found, using vanilla grid snapping" % CLASS_NAME)
		_snappy_mod_checked = true

	if _tool:
		# Refresh cached world references every frame
		_tool.cached_world = Global.World
		_tool.cached_worldui = Global.WorldUI
		_tool.cached_camera = Global.Camera
		_tool.cached_snappy_mod = _cached_snappy_mod

		# Drive Enable/Disable based on the active tool name
		var is_active = Global.Editor.ActiveToolName == "BuildingPlannerTool"
		if is_active and not _tool.is_enabled:
			_tool.Enable()
		elif not is_active and _tool.is_enabled:
			_tool.Disable()

		_tool.Update(_delta)

func unload():
	if LOGGER:
		LOGGER.info("%s: unloading." % CLASS_NAME)
	_tool = null

# ============================================================================
# TOOL CREATION
# ============================================================================

func _create_tool():
	if not BuildingPlannerToolClass:
		if LOGGER: LOGGER.error("Cannot create tool — BuildingPlannerToolClass not loaded")
		return

	_tool = BuildingPlannerToolClass.new(self)

	# Set LOGGER on the tool BEFORE calling setup(), so feature modules
	# receive a valid logger when they are instantiated inside setup().
	if LOGGER:
		_tool.LOGGER = LOGGER.for_class("BuildingPlannerTool")

	# Connect GuidesLinesApi and load feature modules now that LOGGER is ready.
	_tool.setup()

	# Cache world references at creation time
	_tool.cached_world = Global.World
	_tool.cached_worldui = Global.WorldUI
	_tool.cached_camera = Global.Camera

	var icon_path = self.Global.Root + TOOL_ICON_PATH

	var tool_panel = Global.Editor.Toolset.CreateModTool(
		self,            # Primary mod script (owner)
		"Design",        # Toolset category
		"BuildingPlannerTool",  # Unique tool ID
		"Building Planner",  # Display name
		icon_path
	)

	if tool_panel == null:
		if LOGGER: LOGGER.error("Failed to create tool panel!")
		else: print("BuildingPlanner: ERROR - Failed to create tool panel!")
		return

	_tool.tool_panel = tool_panel
	_tool.create_ui_panel()

	if LOGGER: LOGGER.info("BuildingPlanner tool created successfully")
