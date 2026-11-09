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
var _api_source = null

# ============================================================================
# CACHED REFERENCES (updated every frame by BuildingPlanner.gd)
# ============================================================================

var parent_mod = null
var cached_world = null
var cached_worldui = null
var cached_snappy_mod = null   # Lievven.Snappy_Mod reference (or null)

# ============================================================================
# FEATURE MODULES
# ============================================================================

var _pattern_fill = null   # PatternFill
var _wall_builder = null   # WallBuilder
var _path_builder = null   # PathBuilder
var _room_builder = null   # RoomBuilder
var _roof_builder = null   # RoofBuilder

# ============================================================================
# STATE
# ============================================================================

enum Mode { PATTERN_FILL = 1, WALL_BUILDER, PATH_BUILDER, ROOM_BUILDER, ROOF_BUILDER }

var _active_mode: int = Mode.PATTERN_FILL  # Default to first mode
var is_enabled: bool = false

# Public GuidesLines state refreshed on activation, Room preview and Room clicks.
var gl_tool_state: Dictionary = {}

# ============================================================================
# INPUT OVERLAY
# ============================================================================

var _overlay = null   # BuildingPlannerOverlay Node2D instance
var _overlay_class = null

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
	_api_source = api
	if api.has("GuidesLinesApi"):
		_gl_api = api.GuidesLinesApi
		_init_features()
	else:
		if not api.is_connected("api_registered", self, "_on_api_registered"):
			api.connect("api_registered", self, "_on_api_registered")

func _on_api_registered(api_id, _api):
	if api_id == "GuidesLinesApi" and not _gl_api:
		_gl_api = parent_mod.Global.API.GuidesLinesApi
		_init_features()
		if is_enabled:
			Enable()
		if LOGGER:
			LOGGER.info("%s: GuidesLinesApi connected." % CLASS_NAME)

# Load and instantiate feature modules.
# Called once when GuidesLinesApi becomes available.
func _init_features():
	for entry in [["PatternFill", "_pattern_fill"], ["WallBuilder", "_wall_builder"], ["PathBuilder", "_path_builder"], ["RoomBuilder", "_room_builder"], ["RoofBuilder", "_roof_builder"]]:
		var script = ResourceLoader.load(parent_mod.Global.Root + "scripts/features/" + entry[0] + ".gd", "GDScript", false)
		if script:
			set(entry[1], script.new(_gl_api, LOGGER, parent_mod))
		elif LOGGER:
			LOGGER.warn("%s: Failed to load %s.gd" % [CLASS_NAME, entry[0]])
	if _ui:
		_ui.release_all_grid_menus()
		_ui.bind_features()

	if LOGGER:
		LOGGER.info("%s: features initialised." % CLASS_NAME)

# ============================================================================
# TOOL LIFECYCLE (called by BuildingPlanner.gd update loop)
# ============================================================================

# Called when this tool becomes active in the Dungeondraft toolset.
func Enable():
	is_enabled = true
	# Refresh again during Room mode: GuidesLines may change through its public API.
	if _gl_api and _gl_api.has_method("get_tool_state"):
		gl_tool_state = _gl_api.get_tool_state()
	else:
		gl_tool_state = {}
	# Restore the active mode from the UI selector.
	_set_mode(_ui.get_selected_mode() if _ui else Mode.PATTERN_FILL)
	if _ui:
		_ui.try_build_grid_menus(_active_mode)

# Called when the user switches away from this tool.
func Disable():
	is_enabled = false
	if _ui:
		_ui.release_search_focus()
	# Do NOT reset _active_mode here — the overlay already guards on is_enabled,
	# and we need the mode to survive Disable/Enable cycles (e.g. SelectTool round-trip).
	# Keep our own grids and selections across tool switches.
	# Clear Room Builder preview — registry is intentionally kept alive so
	# Merge mode can still clean up stale fills/walls after a tool switch.
	if _room_builder:
		_room_builder.stop_preview()
	_destroy_overlay()

# Called every frame while the mod is loaded (from BuildingPlanner.gd).
func Update(_delta):
	if not is_enabled:
		return
	if _ui:
		_ui.update_active_mode(_active_mode, parent_mod.Global)
	if is_instance_valid(_overlay) and _overlay.get_parent() != cached_worldui:
		_destroy_overlay()
	if not is_instance_valid(_overlay) and is_instance_valid(cached_worldui):
		_create_overlay()

	# Drive Room Builder preview every frame while active
	if _active_mode == Mode.ROOM_BUILDER and _room_builder and cached_worldui:
		if not is_mouse_on_canvas():
			_room_builder.stop_preview()
			return
		_refresh_shape_state()
		_room_builder.update_preview(room_position(cached_worldui.MousePosition), gl_tool_state)

func _refresh_shape_state() -> void:
	if _gl_api and _gl_api.has_method("get_placement_state"):
		gl_tool_state = _gl_api.get_placement_state()
	elif _gl_api and _gl_api.has_method("get_shape_state"):
		gl_tool_state = _gl_api.get_shape_state()
	elif _gl_api and _gl_api.has_method("get_tool_state"):
		gl_tool_state = _gl_api.get_tool_state()
	else:
		gl_tool_state = {}

func set_world_references(world, worldui):
	if cached_world != world or cached_worldui != worldui:
		Disable()
		gl_tool_state.clear()
		if _room_builder:
			_room_builder.on_map_changed()
		if _ui:
			_ui.release_all_grid_menus()
	cached_world = world
	cached_worldui = worldui

func shutdown():
	Disable()
	if _ui:
		_ui.shutdown()
		_ui = null
	if is_instance_valid(_api_source) and _api_source.is_connected("api_registered", self, "_on_api_registered"):
		_api_source.disconnect("api_registered", self, "_on_api_registered")
	_api_source = null
	if _room_builder:
		_room_builder.on_map_changed()
	parent_mod = null

func is_mouse_on_canvas() -> bool:
	if not is_instance_valid(cached_worldui) or not cached_worldui.IsInsideBounds:
		return false
	var viewport = cached_worldui.get_viewport()
	var sidebar_right = max(450.0, tool_panel.get_global_rect().end.x) if is_instance_valid(tool_panel) else 450.0
	return is_canvas_position(viewport.get_mouse_position(), viewport.size, sidebar_right)

static func is_canvas_position(mouse: Vector2, viewport_size: Vector2, sidebar_right: float = 450.0) -> bool:
	return mouse.x >= sidebar_right and mouse.y >= 100 and mouse.y <= viewport_size.y - 100

func room_position(position: Vector2) -> Vector2:
	if parent_mod.Global.Editor.IsSnapping:
		return snap_position_to_grid(position)
	return position

# ============================================================================
# OVERLAY
# ============================================================================

func _create_overlay():
	if not _overlay_class:
		_overlay_class = ResourceLoader.load(
			parent_mod.Global.Root + "scripts/overlay/BuildingPlannerOverlay.gd", "GDScript", false)
	if not _overlay_class:
		if LOGGER: LOGGER.warn("%s: failed to load BuildingPlannerOverlay.gd" % CLASS_NAME)
		return
	_overlay = _overlay_class.new()
	_overlay.tool = self
	cached_worldui.add_child(_overlay)

func _destroy_overlay():
	if is_instance_valid(_overlay):
		_overlay.tool = null
		var owner = _overlay.get_parent()
		if owner:
			owner.remove_child(_overlay)
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

## Dispatch canvas actions here so the overlay only owns input guards.
## Return whether a loaded mode accepted the click, independently of build success.
func handle_canvas_click(world_pos: Vector2) -> bool:
	var feature = null
	match _active_mode:
		Mode.PATTERN_FILL:
			feature = _pattern_fill
		Mode.WALL_BUILDER:
			feature = _wall_builder
		Mode.PATH_BUILDER:
			feature = _path_builder
		Mode.ROOM_BUILDER:
			if not _room_builder:
				return false
			_refresh_shape_state()
			_room_builder.build_room_at(room_position(world_pos), gl_tool_state)
			return true
		Mode.ROOF_BUILDER:
			if _ui:
				_ui.sync_roof_settings(parent_mod.Global)
			feature = _roof_builder
	if not feature:
		return false
	feature.build_at(world_pos)
	return true

## Called by BuildingPlannerOverlay on scroll wheel while in Room Builder mode.
## [direction]: +1 = wheel up, -1 = wheel down.
## [alt_held]:  true when Alt is held — adjusts scale instead of rotation.
func handle_room_scroll(direction: int, alt_held: bool) -> void:
	if not _room_builder:
		return
	if alt_held:
		_room_builder.adjust_scale(direction * _room_builder.SCALE_STEP)
	else:
		_room_builder.adjust_angle(direction * _room_builder.ANGLE_STEP)
	if _ui:
		_ui.update_room_overrides()

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

