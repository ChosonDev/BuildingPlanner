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
#     Marker ID  SpinBox
#     [Build Walls] Button
#   ── section: Mirror Mode ───────────────────────────────────────
#     Marker ID  SpinBox
#     [Activate / Deactivate] ToggleButton

const CLASS_NAME = "BuildingPlannerToolUI"

# Mode constants mirror BuildingPlannerTool.Mode
const MODE_NONE          = 0
const MODE_PATTERN_FILL  = 1
const MODE_WALL_BUILDER  = 2
const MODE_MIRROR        = 3

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
var _wb_marker_spin         = null
var _wb_build_button        = null

# Mirror Mode section
var _mm_section             = null
var _mm_marker_spin         = null
var _mm_toggle_button       = null

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

	# Usage hint
	var hint = Label.new()
	hint.text = "Click on a Shape marker to fill it with the selected pattern."
	hint.modulate = Color(1,1,1,0.75)
	hint.autowrap = true
	sec.add_child(hint)

	sec.add_child(_spacer(4))

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

	sec.add_child(_row_label("Marker ID:"))
	_wb_marker_spin = SpinBox.new()
	_wb_marker_spin.min_value = 0
	_wb_marker_spin.max_value = 99999
	_wb_marker_spin.step = 1
	_wb_marker_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wb_marker_spin.connect("value_changed", self, "_on_wb_marker_changed")
	sec.add_child(_wb_marker_spin)

	sec.add_child(_spacer(6))

	_wb_build_button = Button.new()
	_wb_build_button.text = "Build Walls"
	_wb_build_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wb_build_button.connect("pressed", self, "_on_wb_build_pressed")
	sec.add_child(_wb_build_button)

	return sec


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

# ============================================================================
# SECTION VISIBILITY
# ============================================================================

func _show_section(mode: int):
	if _pf_section: _pf_section.visible = (mode == MODE_PATTERN_FILL)
	if _wb_section: _wb_section.visible = (mode == MODE_WALL_BUILDER)
	if _mm_section: _mm_section.visible = (mode == MODE_MIRROR)

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

func _on_wb_marker_changed(value: float):
	_tool.active_marker_id = int(value)

func _on_wb_build_pressed():
	var ok = _tool.execute_wall_build()
	if not ok and LOGGER:
		LOGGER.warn("%s: Wall Build did not complete." % CLASS_NAME)

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
