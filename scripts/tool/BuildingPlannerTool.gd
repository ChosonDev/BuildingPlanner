extends Reference

# BuildingPlanner - Dungeondraft Mod
# Main tool class. Manages mode switching, GuidesLinesApi bridge,
# and delegates work to feature modules.

const CLASS_NAME = "BuildingPlannerTool"
const RoomTemplate = preload("../features/RoomTemplate.gd")
const ROOM_DATA_KEY = "Choson.BuildingPlanner"
var room_templates = []
var active_room_template = -1
var _templates_world = null
var _templates_source = null
var _templates_editor = null
var _templates_writable = true

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
var _smart_tile_fill = null
var smart_tiles_enabled = false
var _wall_builder = null   # WallBuilder
var _path_builder = null   # PathBuilder
var _room_builder = null   # RoomBuilder
var _roof_builder = null   # RoofBuilder
var _water_fill = null   # WaterFill

# ============================================================================
# STATE
# ============================================================================

enum Mode { PATTERN_FILL = 1, WALL_BUILDER, PATH_BUILDER, ROOM_BUILDER, ROOF_BUILDER, WATER_FILL }

var _active_mode: int = Mode.PATTERN_FILL  # Default to first mode
var is_enabled: bool = false

# Public GuidesLines state refreshed on activation, Room preview and Room clicks.
var gl_tool_state: Dictionary = {}

# ============================================================================
# INPUT OVERLAY
# ============================================================================

var _overlay = null   # BuildingPlannerOverlay Node2D instance
var _overlay_class = null
var _preview_level = null

# ============================================================================
# UI
# ============================================================================

var tool_panel = null
var _ui = null
var _sampling_panel = null
var _sampling_level = null

func start_sampling(panel) -> void:
	var was_sampling = _sampling_panel == panel
	cancel_sampling()
	if was_sampling or not is_enabled or not is_instance_valid(cached_world) or not is_instance_valid(cached_world.Level): return
	_sampling_panel = panel
	_sampling_level = cached_world.Level
	panel.sample_button.pressed = true
	if _ui: _ui.release_search_focus()
	_clear_previews()
	Input.set_default_cursor_shape(Input.CURSOR_CROSS)

func cancel_sampling() -> void:
	if _sampling_panel == null: return
	if is_instance_valid(_sampling_panel.sample_button): _sampling_panel.sample_button.pressed = false
	_sampling_panel = null
	_sampling_level = null
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

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
	var floor_script = ResourceLoader.load(parent_mod.Global.Root + "scripts/features/SmartTileFill.gd", "GDScript", false)
	if floor_script: _smart_tile_fill = floor_script.new(_gl_api, LOGGER, parent_mod)
	for entry in [["PatternFill", "_pattern_fill"], ["WallBuilder", "_wall_builder"], ["PathBuilder", "_path_builder"], ["RoomBuilder", "_room_builder"], ["RoofBuilder", "_roof_builder"], ["WaterFill", "_water_fill"]]:
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
	cancel_sampling()
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
	var level = cached_world.Level if cached_world != null else null
	if _sampling_panel != null:
		if level != _sampling_level: cancel_sampling()
		return
	if level != _preview_level:
		_clear_previews()
		_preview_level = level
	if level == null or not is_mouse_on_canvas():
		_clear_previews()
		return

	# Drive Room Builder preview every frame while active
	if _active_mode == Mode.ROOM_BUILDER and _room_builder and cached_worldui:
		_refresh_shape_state()
		_room_builder.update_preview(room_position(cached_worldui.MousePosition), gl_tool_state)
		if is_instance_valid(_overlay):
			_overlay.refresh_room_preview(_room_builder, room_position(cached_worldui.MousePosition), gl_tool_state)
	elif is_instance_valid(_overlay):
		var feature = null
		match _active_mode:
			Mode.PATTERN_FILL:
				feature = _smart_tile_fill if smart_tiles_enabled else _pattern_fill
			Mode.WALL_BUILDER: feature = _wall_builder
			Mode.PATH_BUILDER: feature = _path_builder
		_overlay.refresh_preview(_delta, feature, _active_mode == Mode.PATTERN_FILL, _active_mode == Mode.PATH_BUILDER)

func _clear_previews() -> void:
	if is_instance_valid(_overlay):
		_overlay.clear_preview()
	if _room_builder:
		_room_builder.stop_preview()

func _refresh_shape_state() -> void:
	if active_room_template >= 0 and active_room_template < room_templates.size():
		gl_tool_state = room_templates[active_room_template].state.duplicate(true)
		gl_tool_state["ready"] = is_instance_valid(_gl_api) and _gl_api.has_method("is_ready") and _gl_api.is_ready()
		return
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
	_disconnect_template_editor()
	if _ui:
		_ui.shutdown()
		_ui = null
	if is_instance_valid(_api_source) and _api_source.is_connected("api_registered", self, "_on_api_registered"):
		_api_source.disconnect("api_registered", self, "_on_api_registered")
	_api_source = null
	if _room_builder:
		_room_builder.on_map_changed()
	parent_mod = null

func _room_style_defaults() -> Array:
	var result = []
	for feature in [_room_builder._pattern_fill, _room_builder._wall_builder, _room_builder._path_builder]:
		var settings = {}
		for key in feature.get_settings(): settings[key.trim_prefix("active_")] = feature.get(key)
		result.append(settings)
	return result

func _disconnect_template_editor():
	if is_instance_valid(_templates_editor) and _templates_editor.is_connected("OnSaveBegin", self, "_save_room_templates"):
		_templates_editor.disconnect("OnSaveBegin", self, "_save_room_templates")
	_templates_editor = null

# Poll even while another tool is active: autosave and map changes still apply.
func update_room_templates():
	var global = parent_mod.Global
	if global.Editor != _templates_editor:
		_disconnect_template_editor()
		_templates_editor = global.Editor
		if is_instance_valid(_templates_editor) and _templates_editor.has_signal("OnSaveBegin"):
			_templates_editor.connect("OnSaveBegin", self, "_save_room_templates")
	var world = global.World if global.WorldUI != null else null
	var source = global.ModMapData.get(ROOM_DATA_KEY) if world != null else null
	# Map data may arrive after World; do not cache an early empty load forever.
	if world == _templates_world and source == _templates_source: return
	if world != null and _room_builder == null: return
	_templates_world = world
	_templates_source = source
	room_templates = []
	active_room_template = -1
	_templates_writable = true
	if _room_builder: _room_builder.room_template = null
	if world != null:
		load_room_templates(global.ModMapData)
	if _ui: _ui.rebuild_room_templates()

func load_room_templates(map_data: Dictionary) -> bool:
	_templates_source = map_data.get(ROOM_DATA_KEY)
	room_templates = []
	active_room_template = -1
	if _room_builder: _room_builder.room_template = null
	_templates_writable = true
	if not map_data.has(ROOM_DATA_KEY): return true
	var data = map_data[ROOM_DATA_KEY]
	if not data is Dictionary or data.get("version") != 1 or not data.get("room_templates") is Array:
		_templates_writable = false
	else:
		for saved in data.room_templates:
			var template = RoomTemplate.new()
			if not template.load_data(saved, _room_style_defaults()):
				_templates_writable = false
				break
			room_templates.append(template)
	if not _templates_writable:
		room_templates = []
		if LOGGER: LOGGER.warn("Room templates could not be loaded. Original map data will be preserved.")
	return _templates_writable

func _save_room_templates(_path = "", _backup = false):
	update_room_templates()
	if _templates_world == null or not _templates_writable: return
	var saved = []
	for template in room_templates: saved.append(template.save())
	var data = {"version": 1, "room_templates": saved}
	parent_mod.Global.ModMapData[ROOM_DATA_KEY] = data
	_templates_source = data # An owned save is not an external map load.

func add_room_template() -> bool:
	if not _templates_writable or _room_builder == null or cached_world == null: return false
	_refresh_shape_state()
	if not gl_tool_state.get("ready", false): return false
	var template = RoomTemplate.new()
	template.name = "Room template %d" % (room_templates.size() + 1)
	template.sub_mode = _room_builder.active_sub_mode
	template.outline_mode = _room_builder.active_outline_mode
	template.fill_mode = _room_builder.active_fill_mode
	var tile_style = _room_builder._smart_tile_fill.get_style()
	template.tile_style = {"texture": tile_style.active_texture.resource_path if tile_style.active_texture is Texture else "", "color": tile_style.active_color}
	template.angle = _room_builder.shape_angle_offset
	template.scale = _room_builder.shape_scale_factor
	for key in ["active_shape_radius", "active_shape_angle", "active_shape_sides", "active_color"]:
		template.state[key] = gl_tool_state.get(key)
	template.state["active_marker_type"] = "Template" if gl_tool_state.get("active_marker_type") == "Template" else "Shape"
	if template.state.active_marker_type == "Template":
		if not _gl_api.has_method("get_template_markers"): return false
		template.geometry = _gl_api.get_template_markers(Vector2.ZERO)
	template.panels = _room_style_defaults()
	for settings in template.panels:
		settings.texture = settings.texture.resource_path if settings.texture is Texture else ""
	# Validate captured state with the same boundary used for map loading.
	if not template.load_data(template.save(), _room_style_defaults()):
		if LOGGER: LOGGER.warn("Room template could not be captured; check the current shape and assets.")
		return false
	room_templates.append(template)
	active_room_template = room_templates.size() - 1
	_room_builder.room_template = template
	return true

func select_room_template(index: int) -> bool:
	if index < 0 or index >= room_templates.size():
		cancel_sampling()
		_clear_previews()
		active_room_template = -1
		if _room_builder: _room_builder.room_template = null
		_refresh_shape_state()
		return true
	if not _room_builder or not _ui: return false
	if not _ui.apply_room_template(room_templates[index]): return false
	cancel_sampling()
	_clear_previews()
	active_room_template = index
	_room_builder.room_template = room_templates[index]
	_refresh_shape_state()
	return true

func is_mouse_on_canvas() -> bool:
	if not is_instance_valid(cached_worldui) or not cached_worldui.IsInsideBounds:
		return false
	var viewport = cached_worldui.get_viewport()
	if viewport.gui_has_modal_stack():
		return false
	if is_instance_valid(tool_panel) and tool_panel.is_visible_in_tree() and Rect2(Vector2.ZERO, tool_panel.rect_size).has_point(tool_panel.get_local_mouse_position()):
		return false
	var editor = parent_mod.Global.Editor
	if editor is Node and is_instance_valid(editor):
		var windows = editor.get("Windows")
		if windows != null:
			for window in windows.values():
				if is_instance_valid(window) and window.visible:
					return false
		# Use the host's real canvas bounds, including UI scale and resized panels.
		var content = editor.get_node_or_null("VPartition/Panels/HSplit/Content")
		if content is Control:
			return content.is_visible_in_tree() and Rect2(Vector2.ZERO, content.rect_size).has_point(content.get_local_mouse_position())
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
	cancel_sampling()
	if mode != _active_mode:
		_clear_previews()
	_active_mode = mode

# ============================================================================
# EXECUTE ACTIONS (called from UI)
# ============================================================================

## Dispatch canvas actions here so the overlay only owns input guards.
## Return whether a loaded mode accepted the click, independently of build success.
func handle_canvas_click(world_pos: Vector2) -> bool:
	if _sampling_panel != null:
		var panel = _sampling_panel
		var level = _sampling_level
		cancel_sampling()
		if is_instance_valid(cached_world) and cached_world.Level == level:
			_ui.sample_at(panel, level, world_pos)
		return true
	var feature = null
	match _active_mode:
		Mode.PATTERN_FILL:
			feature = _smart_tile_fill if smart_tiles_enabled else _pattern_fill
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
		Mode.WATER_FILL:
			if _ui:
				_ui._wf_water_panel.sync_level_settings(parent_mod.Global)
			feature = _water_fill
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

