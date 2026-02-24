extends Reference

# BuildingPlanner - Dungeondraft Mod
# Sidebar UI panel for the BuildingPlanner tool.
#
# Layout
#   Title
#   Mode OptionButton  (Pattern Fill / Wall Builder / Mirror Mode)
#   ── section: Pattern Fill ──────────────────────────────────────
#     Marker ID  SpinBox
#     [info] Texture: select in PatternShapeTool
#     Color      ColorPickerButton
#     Rotation   SpinBox  0–360 step 1
#     Layer      SpinBox  0–9  step 1
#     Outline    CheckButton
#     [Fill Shape] Button
#   ── section: Wall Builder ──────────────────────────────────────
#     Wall texture  GridMenu (mirrored from WallTool.Controls["Texture"])
#     Shadow        CheckButton
#     Bevel         CheckButton
#   ── section: Mirror Mode ───────────────────────────────────────
#     Marker ID  SpinBox
#     [Activate / Deactivate] ToggleButton

const CLASS_NAME = "BuildingPlannerToolUI"

# Mode constants mirror BuildingPlannerTool.Mode
const MODE_NONE          = 0
const MODE_PATTERN_FILL  = 1
const MODE_WALL_BUILDER  = 2
const MODE_MIRROR        = 3
const MODE_ROOM_BUILDER  = 4

# ============================================================================
# REFERENCES
# ============================================================================

var _tool   = null
var LOGGER  = null

# shared
var _mode_selector          = null

# Pattern Fill section
var _pf_section             = null
var _pf_grid_menu           = null   # Our mirror ItemList (owned)
var _pf_index_to_path       = {}     # {int index -> String resource_path} built from GridMenu.Lookup
var _pf_menu_container      = null   # VBoxContainer placeholder inside the section
var _pf_color_picker        = null
var _pf_rotation_spin       = null
var _pf_layer_spin          = null
var _pf_outline_check       = null

# Wall Builder section
var _wb_section             = null
var _wb_grid_menu           = null   # Our mirror ItemList (owned)
var _wb_index_to_path       = {}     # {int index -> String resource_path}
var _wb_menu_container      = null   # VBoxContainer placeholder inside the section
var _wb_source_menu         = null   # WallTool Controls["Texture"] GridMenu reference
var _wb_shadow_check        = null
var _wb_bevel_check         = null

# Mirror Mode section
var _mm_section             = null
var _mm_marker_spin         = null
var _mm_toggle_button       = null

# Room Builder section
var _rb_section               = null
var _rb_pattern_grid_menu     = null   # Our mirror ItemList for patterns (owned)
var _rb_pattern_index_to_path = {}     # {int index -> String resource_path}
var _rb_pattern_menu_container = null  # VBoxContainer placeholder
var _rb_color_picker          = null
var _rb_rotation_spin         = null
var _rb_layer_spin            = null
var _rb_outline_check         = null
var _rb_wall_grid_menu        = null   # Our mirror ItemList for walls (owned)
var _rb_wall_index_to_path    = {}     # {int index -> String resource_path}
var _rb_wall_menu_container   = null   # VBoxContainer placeholder
var _rb_wall_source_menu      = null   # WallTool Controls["Texture"] GridMenu reference
var _rb_shadow_check          = null
var _rb_bevel_check           = null

# ============================================================================
# INIT
# ============================================================================

func _init(tool_ref, logger):
	_tool  = tool_ref
	LOGGER = logger

# ============================================================================
# BUILD UI
# ============================================================================

func build(panel):
	if not panel:
		if LOGGER: LOGGER.warn("%s: build() called with null panel" % CLASS_NAME)
		return

	var root = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ---- Title ----
	var title = Label.new()
	title.text = "Building Planner"
	title.align = Label.ALIGN_CENTER
	root.add_child(title)

	root.add_child(_spacer(6))

	# ---- Mode selector ----
	var mode_label = Label.new()
	mode_label.text = "Mode:"
	root.add_child(mode_label)

	_mode_selector = OptionButton.new()
	_mode_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_selector.add_item("Pattern Fill",  MODE_PATTERN_FILL)
	_mode_selector.add_item("Wall Builder",  MODE_WALL_BUILDER)
	_mode_selector.add_item("Mirror Mode",   MODE_MIRROR)
	_mode_selector.add_item("Room Builder",  MODE_ROOM_BUILDER)
	_mode_selector.selected = 0
	_mode_selector.connect("item_selected", self, "_on_mode_selected")
	root.add_child(_mode_selector)

	root.add_child(_separator())

	# ---- Mode sections ----
	_pf_section = _build_pattern_fill_section()
	root.add_child(_pf_section)

	_wb_section = _build_wall_builder_section()
	root.add_child(_wb_section)

	_mm_section = _build_mirror_mode_section()
	root.add_child(_mm_section)

	_rb_section = _build_room_builder_section()
	root.add_child(_rb_section)

	# Show only the first mode's section
	_show_section(MODE_PATTERN_FILL)

	# Attach to panel
	var attach_target = panel.get_node_or_null("Align")
	if attach_target:
		attach_target.add_child(root)
	else:
		panel.add_child(root)

	# Sync tool state
	_tool._set_mode(MODE_PATTERN_FILL)

# ============================================================================
# SECTION BUILDERS
# ============================================================================

func _build_pattern_fill_section() -> VBoxContainer:
	var sec = VBoxContainer.new()
	sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# --- Pattern grid menu slot (filled lazily on first show) ---
	sec.add_child(_row_label("Pattern:"))
	_pf_menu_container = VBoxContainer.new()
	_pf_menu_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec.add_child(_pf_menu_container)

	sec.add_child(_spacer(6))

	# Color
	sec.add_child(_row_label("Color:"))
	_pf_color_picker = ColorPickerButton.new()
	_pf_color_picker.color = Color.white
	_pf_color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pf_color_picker.connect("color_changed", self, "_on_pf_color_changed")
	sec.add_child(_pf_color_picker)

	# Rotation
	sec.add_child(_row_label("Rotation (deg):"))
	_pf_rotation_spin = SpinBox.new()
	_pf_rotation_spin.min_value = 0
	_pf_rotation_spin.max_value = 360
	_pf_rotation_spin.step = 1
	_pf_rotation_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pf_rotation_spin.connect("value_changed", self, "_on_pf_rotation_changed")
	sec.add_child(_pf_rotation_spin)

	# Layer
	sec.add_child(_row_label("Layer:"))
	_pf_layer_spin = SpinBox.new()
	_pf_layer_spin.min_value = 0
	_pf_layer_spin.max_value = 9
	_pf_layer_spin.step = 1
	_pf_layer_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pf_layer_spin.connect("value_changed", self, "_on_pf_layer_changed")
	sec.add_child(_pf_layer_spin)

	# Outline
	_pf_outline_check = CheckButton.new()
	_pf_outline_check.text = "Outline"
	_pf_outline_check.connect("toggled", self, "_on_pf_outline_toggled")
	sec.add_child(_pf_outline_check)

	return sec

# ============================================================================
# GRID MENU FACTORY
# ============================================================================

# Borrows textureMenu from PatternShapeTool to read its items, then builds
# an independent mirror ItemList in our panel.  We never reparent the original,
# so the C# lambda registered by ToolPanel.CreateTextureGridMenu never fires
# in our context (which would crash via Infobar.SetAssetInfo when PST is inactive).
func _try_build_grid_menu():
	if _pf_grid_menu != null or _pf_menu_container == null:
		return

	if not _tool or not _tool.parent_mod:
		if LOGGER: LOGGER.warn("%s: parent_mod not available." % CLASS_NAME)
		return

	# Global is only accessible in tool scripts (script_class = "tool").
	# Sub-scripts access it via parent_mod.Global — the same pattern used by GuidesLines.
	var gl = _tool.parent_mod.Global
	if not gl.Editor or not gl.Editor.Tools.has("PatternShapeTool"):
		if LOGGER: LOGGER.warn("%s: PatternShapeTool not in Tools[]." % CLASS_NAME)
		return

	var source_menu = gl.Editor.Tools["PatternShapeTool"].get("textureMenu")
	if not source_menu:
		if LOGGER: LOGGER.warn("%s: textureMenu is null." % CLASS_NAME)
		return

	var count = source_menu.get_item_count()
	if count == 0:
		if LOGGER: LOGGER.warn("%s: textureMenu has 0 items." % CLASS_NAME)
		return

	# Build our own ItemList — copy icons from source_menu and store index→path
	# from GridMenu.Lookup so we NEVER call select()/OnItemSelected on source_menu
	# (its C# lambda crashes via Infobar when PatternShapeTool is not active).
	var lookup = source_menu.get("Lookup")  # Dictionary {resource_path: index}
	if not lookup or lookup.empty():
		if LOGGER: LOGGER.warn("%s: GridMenu.Lookup is empty." % CLASS_NAME)
		return

	# Invert: {index: resource_path}
	_pf_index_to_path.clear()
	for path in lookup.keys():
		_pf_index_to_path[lookup[path]] = path

	var scroll = ScrollContainer.new()
	scroll.rect_min_size = Vector2(0, 160)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_pf_grid_menu = ItemList.new()
	_pf_grid_menu.icon_mode = ItemList.ICON_MODE_TOP
	_pf_grid_menu.fixed_icon_size = Vector2(48, 48)
	_pf_grid_menu.fixed_column_width = 56
	_pf_grid_menu.max_columns = 0
	_pf_grid_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pf_grid_menu.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pf_grid_menu.connect("item_selected", self, "_on_pf_texture_selected")

	for i in range(count):
		var icon = source_menu.get_item_icon(i)
		var tooltip = _pf_index_to_path.get(i, str(i)).get_file().get_basename()
		if icon:
			_pf_grid_menu.add_item("", icon)
		else:
			_pf_grid_menu.add_item(tooltip)
		_pf_grid_menu.set_item_tooltip(_pf_grid_menu.get_item_count() - 1, tooltip)

	scroll.add_child(_pf_grid_menu)
	_pf_menu_container.add_child(scroll)

	# Pre-select first item — pure GDScript ItemList select(), no C# handler
	_pf_grid_menu.select(0)
	_on_pf_texture_selected(0)

	if LOGGER: LOGGER.info("%s: mirror ItemList built with %d items." % [CLASS_NAME, _pf_grid_menu.get_item_count()])

# Destroys the mirror ItemList (owned by us).
func release_grid_menu():
	if not _pf_grid_menu:
		return
	if _pf_grid_menu.is_connected("item_selected", self, "_on_pf_texture_selected"):
		_pf_grid_menu.disconnect("item_selected", self, "_on_pf_texture_selected")
	for child in _pf_menu_container.get_children():
		_pf_menu_container.remove_child(child)
		child.queue_free()
	_pf_grid_menu = null
	_pf_index_to_path.clear()


func _build_wall_builder_section() -> VBoxContainer:
	var sec = VBoxContainer.new()
	sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# --- Wall texture grid menu slot (filled lazily on Enable) ---
	sec.add_child(_row_label("Wall:"))
	_wb_menu_container = VBoxContainer.new()
	_wb_menu_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec.add_child(_wb_menu_container)

	sec.add_child(_spacer(6))

	# Shadow
	_wb_shadow_check = CheckButton.new()
	_wb_shadow_check.text = "Shadow"
	_wb_shadow_check.pressed = true
	_wb_shadow_check.connect("toggled", self, "_on_wb_shadow_toggled")
	sec.add_child(_wb_shadow_check)

	# Bevel
	_wb_bevel_check = CheckButton.new()
	_wb_bevel_check.text = "Bevel corners"
	_wb_bevel_check.pressed = true
	_wb_bevel_check.connect("toggled", self, "_on_wb_bevel_toggled")
	sec.add_child(_wb_bevel_check)

	return sec

# ============================================================================
# WALL BUILDER GRID MENU FACTORY
# ============================================================================

# Borrows WallTool.Controls["Texture"] to read its items, then builds
# an independent mirror ItemList in our panel.
# WallTool exposes its grid via Controls dict, not a textureMenu property.
func _try_build_wb_grid_menu():
	if _wb_grid_menu != null or _wb_menu_container == null:
		return

	if not _tool or not _tool.parent_mod:
		if LOGGER: LOGGER.warn("%s: parent_mod not available." % CLASS_NAME)
		return

	var gl = _tool.parent_mod.Global
	if not gl.Editor or not gl.Editor.Tools.has("WallTool"):
		if LOGGER: LOGGER.warn("%s: WallTool not in Tools[]." % CLASS_NAME)
		return

	# WallTool exposes its GridMenu via Controls["Texture"] (same pattern as other tools)
	var controls = gl.Editor.Tools["WallTool"].get("Controls")
	if not controls or not controls.has("Texture"):
		if LOGGER: LOGGER.warn("%s: WallTool.Controls[Texture] not found." % CLASS_NAME)
		return

	var source_menu = controls["Texture"]
	if not source_menu:
		if LOGGER: LOGGER.warn("%s: WallTool Controls[Texture] is null." % CLASS_NAME)
		return

	var count = source_menu.get_item_count()
	if count == 0:
		if LOGGER: LOGGER.warn("%s: WallTool Controls[Texture] has 0 items." % CLASS_NAME)
		return

	_wb_source_menu = source_menu

	var lookup = source_menu.get("Lookup")  # Dictionary {resource_path: index}
	if not lookup or lookup.empty():
		if LOGGER: LOGGER.warn("%s: WallTool GridMenu.Lookup is empty." % CLASS_NAME)
		return

	# Invert: {index: resource_path}
	_wb_index_to_path.clear()
	for path in lookup.keys():
		_wb_index_to_path[lookup[path]] = path

	var scroll = ScrollContainer.new()
	scroll.rect_min_size = Vector2(0, 160)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_wb_grid_menu = ItemList.new()
	_wb_grid_menu.icon_mode = ItemList.ICON_MODE_TOP
	_wb_grid_menu.fixed_icon_size = Vector2(48, 48)
	_wb_grid_menu.fixed_column_width = 56
	_wb_grid_menu.max_columns = 0
	_wb_grid_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wb_grid_menu.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_wb_grid_menu.connect("item_selected", self, "_on_wb_texture_selected")

	for i in range(count):
		var icon = source_menu.get_item_icon(i)
		var tooltip = _wb_index_to_path.get(i, str(i)).get_file().get_basename()
		if icon:
			_wb_grid_menu.add_item("", icon)
		else:
			_wb_grid_menu.add_item(tooltip)
		_wb_grid_menu.set_item_tooltip(_wb_grid_menu.get_item_count() - 1, tooltip)

	scroll.add_child(_wb_grid_menu)
	_wb_menu_container.add_child(scroll)

	# Pre-select first item
	_wb_grid_menu.select(0)
	_on_wb_texture_selected(0)

	if LOGGER: LOGGER.info("%s: wall ItemList built with %d items." % [CLASS_NAME, _wb_grid_menu.get_item_count()])

# Destroys the wall mirror ItemList (owned by us).
func release_wb_grid_menu():
	if not _wb_grid_menu:
		return
	if _wb_grid_menu.is_connected("item_selected", self, "_on_wb_texture_selected"):
		_wb_grid_menu.disconnect("item_selected", self, "_on_wb_texture_selected")
	for child in _wb_menu_container.get_children():
		_wb_menu_container.remove_child(child)
		child.queue_free()
	_wb_grid_menu = null
	_wb_source_menu = null
	_wb_index_to_path.clear()


func _build_mirror_mode_section() -> VBoxContainer:
	var sec = VBoxContainer.new()
	sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	sec.add_child(_row_label("Line Marker ID:"))
	_mm_marker_spin = SpinBox.new()
	_mm_marker_spin.min_value = 0
	_mm_marker_spin.max_value = 99999
	_mm_marker_spin.step = 1
	_mm_marker_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mm_marker_spin.connect("value_changed", self, "_on_mm_marker_changed")
	sec.add_child(_mm_marker_spin)

	sec.add_child(_spacer(6))

	_mm_toggle_button = Button.new()
	_mm_toggle_button.text = "Activate Mirror"
	_mm_toggle_button.toggle_mode = true
	_mm_toggle_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mm_toggle_button.connect("toggled", self, "_on_mm_toggle_pressed")
	sec.add_child(_mm_toggle_button)

	return sec


func _build_room_builder_section() -> VBoxContainer:
	var sec = VBoxContainer.new()
	sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# --- Pattern subsection ---
	sec.add_child(_row_label("Pattern:"))
	_rb_pattern_menu_container = VBoxContainer.new()
	_rb_pattern_menu_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec.add_child(_rb_pattern_menu_container)

	sec.add_child(_spacer(4))

	sec.add_child(_row_label("Color:"))
	_rb_color_picker = ColorPickerButton.new()
	_rb_color_picker.color = Color.white
	_rb_color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rb_color_picker.connect("color_changed", self, "_on_rb_color_changed")
	sec.add_child(_rb_color_picker)

	sec.add_child(_row_label("Rotation (deg):"))
	_rb_rotation_spin = SpinBox.new()
	_rb_rotation_spin.min_value = 0
	_rb_rotation_spin.max_value = 360
	_rb_rotation_spin.step = 1
	_rb_rotation_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rb_rotation_spin.connect("value_changed", self, "_on_rb_rotation_changed")
	sec.add_child(_rb_rotation_spin)

	sec.add_child(_row_label("Layer:"))
	_rb_layer_spin = SpinBox.new()
	_rb_layer_spin.min_value = 0
	_rb_layer_spin.max_value = 9
	_rb_layer_spin.step = 1
	_rb_layer_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rb_layer_spin.connect("value_changed", self, "_on_rb_layer_changed")
	sec.add_child(_rb_layer_spin)

	_rb_outline_check = CheckButton.new()
	_rb_outline_check.text = "Outline"
	_rb_outline_check.connect("toggled", self, "_on_rb_outline_toggled")
	sec.add_child(_rb_outline_check)

	sec.add_child(_separator())

	# --- Wall subsection ---
	sec.add_child(_row_label("Wall:"))
	_rb_wall_menu_container = VBoxContainer.new()
	_rb_wall_menu_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec.add_child(_rb_wall_menu_container)

	sec.add_child(_spacer(4))

	_rb_shadow_check = CheckButton.new()
	_rb_shadow_check.text = "Shadow"
	_rb_shadow_check.pressed = true
	_rb_shadow_check.connect("toggled", self, "_on_rb_shadow_toggled")
	sec.add_child(_rb_shadow_check)

	_rb_bevel_check = CheckButton.new()
	_rb_bevel_check.text = "Bevel corners"
	_rb_bevel_check.pressed = true
	_rb_bevel_check.connect("toggled", self, "_on_rb_bevel_toggled")
	sec.add_child(_rb_bevel_check)

	return sec

# ============================================================================
# SECTION VISIBILITY
# ============================================================================

func _show_section(mode: int):
	if _pf_section: _pf_section.visible = (mode == MODE_PATTERN_FILL)
	if _wb_section: _wb_section.visible = (mode == MODE_WALL_BUILDER)
	if _mm_section: _mm_section.visible = (mode == MODE_MIRROR)
	if _rb_section: _rb_section.visible = (mode == MODE_ROOM_BUILDER)

# ============================================================================
# CALLBACKS — MODE
# ============================================================================

func _on_mode_selected(index):
	var mode = _mode_selector.get_item_id(index)
	_tool._set_mode(mode)
	_show_section(mode)

# ============================================================================
# CALLBACKS — PATTERN FILL
# ============================================================================

func _on_pf_texture_selected(index: int):
	if not _tool._pattern_fill:
		return
	var path: String = _pf_index_to_path.get(index, "")
	if path == "":
		if LOGGER: LOGGER.warn("%s: no path for index=%d" % [CLASS_NAME, index])
		return
	# no_cache=false: reuse Dungeondraft's cached texture instance so that the
	# asset-tag lookup in SelectTool and SetOptions works correctly.
	var tex = ResourceLoader.load(path, "Texture", false)
	_tool._pattern_fill.active_texture = tex

func _on_pf_color_changed(color: Color):
	if _tool._pattern_fill:
		_tool._pattern_fill.active_color = color

func _on_pf_rotation_changed(value: float):
	if _tool._pattern_fill:
		_tool._pattern_fill.active_rotation = value

func _on_pf_layer_changed(value: float):
	if _tool._pattern_fill:
		_tool._pattern_fill.active_layer = int(value)

func _on_pf_outline_toggled(pressed: bool):
	if _tool._pattern_fill:
		_tool._pattern_fill.active_outline = pressed

# ============================================================================
# CALLBACKS — WALL BUILDER
# ============================================================================

func _on_wb_texture_selected(index: int):
	# Drive WallTool.Texture via its own GridMenu — same technique AdditionalSearchOptions uses.
	# This avoids guessing the resource path format (png vs tres) for ResourceLoader.
	if _wb_source_menu and _wb_source_menu.has_method("OnItemSelected"):
		_wb_source_menu.OnItemSelected(index)

func _on_wb_shadow_toggled(pressed: bool):
	if _tool._wall_builder:
		_tool._wall_builder.active_shadow = pressed

func _on_wb_bevel_toggled(pressed: bool):
	if _tool._wall_builder:
		# 0 = Sharp, 1 = Bevel, 2 = Round
		_tool._wall_builder.active_joint = 1 if pressed else 0

# ============================================================================
# CALLBACKS — MIRROR MODE
# ============================================================================

func _on_mm_marker_changed(value: float):
	_tool.active_marker_id = int(value)

func _on_mm_toggle_pressed(pressed: bool):
	_mm_toggle_button.text = "Deactivate Mirror" if pressed else "Activate Mirror"
	var ok = _tool.execute_mirror_toggle()
	# If activation failed, un-press the button
	if pressed and not ok:
		_mm_toggle_button.pressed = false
		_mm_toggle_button.text = "Activate Mirror"

# ============================================================================
# ROOM BUILDER PATTERN GRID MENU FACTORY
# ============================================================================

func _try_build_rb_pattern_grid_menu():
	if _rb_pattern_grid_menu != null or _rb_pattern_menu_container == null:
		return
	if not _tool or not _tool.parent_mod:
		return
	var gl = _tool.parent_mod.Global
	if not gl.Editor or not gl.Editor.Tools.has("PatternShapeTool"):
		return
	var source_menu = gl.Editor.Tools["PatternShapeTool"].get("textureMenu")
	if not source_menu:
		return
	var count = source_menu.get_item_count()
	if count == 0:
		return
	var lookup = source_menu.get("Lookup")
	if not lookup or lookup.empty():
		return
	_rb_pattern_index_to_path.clear()
	for path in lookup.keys():
		_rb_pattern_index_to_path[lookup[path]] = path
	var scroll = ScrollContainer.new()
	scroll.rect_min_size = Vector2(0, 160)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rb_pattern_grid_menu = ItemList.new()
	_rb_pattern_grid_menu.icon_mode = ItemList.ICON_MODE_TOP
	_rb_pattern_grid_menu.fixed_icon_size = Vector2(48, 48)
	_rb_pattern_grid_menu.fixed_column_width = 56
	_rb_pattern_grid_menu.max_columns = 0
	_rb_pattern_grid_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rb_pattern_grid_menu.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rb_pattern_grid_menu.connect("item_selected", self, "_on_rb_pattern_selected")
	for i in range(count):
		var icon = source_menu.get_item_icon(i)
		var tooltip = _rb_pattern_index_to_path.get(i, str(i)).get_file().get_basename()
		if icon:
			_rb_pattern_grid_menu.add_item("", icon)
		else:
			_rb_pattern_grid_menu.add_item(tooltip)
		_rb_pattern_grid_menu.set_item_tooltip(_rb_pattern_grid_menu.get_item_count() - 1, tooltip)
	scroll.add_child(_rb_pattern_grid_menu)
	_rb_pattern_menu_container.add_child(scroll)
	_rb_pattern_grid_menu.select(0)
	_on_rb_pattern_selected(0)
	if LOGGER: LOGGER.info("%s: RB pattern ItemList built with %d items." % [CLASS_NAME, count])

func release_rb_pattern_grid_menu():
	if not _rb_pattern_grid_menu:
		return
	if _rb_pattern_grid_menu.is_connected("item_selected", self, "_on_rb_pattern_selected"):
		_rb_pattern_grid_menu.disconnect("item_selected", self, "_on_rb_pattern_selected")
	for child in _rb_pattern_menu_container.get_children():
		_rb_pattern_menu_container.remove_child(child)
		child.queue_free()
	_rb_pattern_grid_menu = null
	_rb_pattern_index_to_path.clear()

# ============================================================================
# ROOM BUILDER WALL GRID MENU FACTORY
# ============================================================================

func _try_build_rb_wall_grid_menu():
	if _rb_wall_grid_menu != null or _rb_wall_menu_container == null:
		return
	if not _tool or not _tool.parent_mod:
		return
	var gl = _tool.parent_mod.Global
	if not gl.Editor or not gl.Editor.Tools.has("WallTool"):
		return
	var controls = gl.Editor.Tools["WallTool"].get("Controls")
	if not controls or not controls.has("Texture"):
		return
	var source_menu = controls["Texture"]
	if not source_menu:
		return
	var count = source_menu.get_item_count()
	if count == 0:
		return
	_rb_wall_source_menu = source_menu
	var lookup = source_menu.get("Lookup")
	if not lookup or lookup.empty():
		return
	_rb_wall_index_to_path.clear()
	for path in lookup.keys():
		_rb_wall_index_to_path[lookup[path]] = path
	var scroll = ScrollContainer.new()
	scroll.rect_min_size = Vector2(0, 160)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rb_wall_grid_menu = ItemList.new()
	_rb_wall_grid_menu.icon_mode = ItemList.ICON_MODE_TOP
	_rb_wall_grid_menu.fixed_icon_size = Vector2(48, 48)
	_rb_wall_grid_menu.fixed_column_width = 56
	_rb_wall_grid_menu.max_columns = 0
	_rb_wall_grid_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rb_wall_grid_menu.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rb_wall_grid_menu.connect("item_selected", self, "_on_rb_wall_texture_selected")
	for i in range(count):
		var icon = source_menu.get_item_icon(i)
		var tooltip = _rb_wall_index_to_path.get(i, str(i)).get_file().get_basename()
		if icon:
			_rb_wall_grid_menu.add_item("", icon)
		else:
			_rb_wall_grid_menu.add_item(tooltip)
		_rb_wall_grid_menu.set_item_tooltip(_rb_wall_grid_menu.get_item_count() - 1, tooltip)
	scroll.add_child(_rb_wall_grid_menu)
	_rb_wall_menu_container.add_child(scroll)
	_rb_wall_grid_menu.select(0)
	_on_rb_wall_texture_selected(0)
	if LOGGER: LOGGER.info("%s: RB wall ItemList built with %d items." % [CLASS_NAME, count])

func release_rb_wall_grid_menu():
	if not _rb_wall_grid_menu:
		return
	if _rb_wall_grid_menu.is_connected("item_selected", self, "_on_rb_wall_texture_selected"):
		_rb_wall_grid_menu.disconnect("item_selected", self, "_on_rb_wall_texture_selected")
	for child in _rb_wall_menu_container.get_children():
		_rb_wall_menu_container.remove_child(child)
		child.queue_free()
	_rb_wall_grid_menu = null
	_rb_wall_source_menu = null
	_rb_wall_index_to_path.clear()

# ============================================================================
# CALLBACKS — ROOM BUILDER
# ============================================================================

func _on_rb_pattern_selected(index: int):
	if not _tool._room_builder:
		return
	var path: String = _rb_pattern_index_to_path.get(index, "")
	if path == "":
		return
	var tex = ResourceLoader.load(path, "Texture", false)
	_tool._room_builder.active_texture = tex

func _on_rb_color_changed(color: Color):
	if _tool._room_builder:
		_tool._room_builder.active_color = color

func _on_rb_rotation_changed(value: float):
	if _tool._room_builder:
		_tool._room_builder.active_rotation = value

func _on_rb_layer_changed(value: float):
	if _tool._room_builder:
		_tool._room_builder.active_layer = int(value)

func _on_rb_outline_toggled(pressed: bool):
	if _tool._room_builder:
		_tool._room_builder.active_outline = pressed

func _on_rb_wall_texture_selected(index: int):
	if _rb_wall_source_menu and _rb_wall_source_menu.has_method("OnItemSelected"):
		_rb_wall_source_menu.OnItemSelected(index)

func _on_rb_shadow_toggled(pressed: bool):
	if _tool._room_builder:
		_tool._room_builder.active_shadow = pressed

func _on_rb_bevel_toggled(pressed: bool):
	if _tool._room_builder:
		_tool._room_builder.active_joint = 1 if pressed else 0

# ============================================================================
# HELPERS
# ============================================================================

func _row_label(text: String) -> Label:
	var lbl = Label.new()
	lbl.text = text
	return lbl

func _spacer(height: int) -> Control:
	var s = Control.new()
	s.rect_min_size = Vector2(0, height)
	return s

func _separator() -> HSeparator:
	return HSeparator.new()
