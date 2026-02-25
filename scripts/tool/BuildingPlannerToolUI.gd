extends Reference

# BuildingPlanner - Dungeondraft Mod
# Sidebar UI panel for the BuildingPlanner tool.
#
# Layout
#   Title
#   Mode OptionButton  (Pattern Fill / Wall Builder / Room Builder)
#   ── section: Pattern Fill ──────────────────────────────────────
#     PatternPanel  (pattern grid, color, rotation, layer, outline)
#   ── section: Wall Builder ──────────────────────────────────────
#     WallPanel  (wall grid, shadow, bevel)
#   ── section: Room Builder ──────────────────────────────────────
#     PatternPanel  (pattern grid, color, rotation, layer, outline)
#     ──────────────────────────────────────────────────────────
#     WallPanel  (wall grid, shadow, bevel)

const CLASS_NAME = "BuildingPlannerToolUI"

# Mode constants mirror BuildingPlannerTool.Mode
const MODE_NONE         = 0
const MODE_PATTERN_FILL = 1
const MODE_WALL_BUILDER = 2
const MODE_ROOM_BUILDER = 3

# ============================================================================
# PATTERN PANEL
# Reusable panel: pattern texture grid + color / rotation / layer / outline.
# ============================================================================

class PatternPanel:

	var LOGGER = null

	# ---- UI nodes ----
	var _menu_container  = null   # VBoxContainer — placeholder for the scroll
	var _grid_menu       = null   # ItemList (owned)
	var _index_to_path   = {}     # { int index -> String resource_path }
	var _selected_index: int = 0  # persists across release/rebuild cycles

	var color_picker  = null   # ColorPickerButton
	var rotation_spin = null   # SpinBox
	var layer_spin    = null   # SpinBox
	var outline_check = null   # CheckButton

	# ---- callbacks (FuncRef) ----
	var _cb_texture  = null   # func(texture: Texture)
	var _cb_color    = null   # func(color: Color)
	var _cb_rotation = null   # func(value: float)
	var _cb_layer    = null   # func(value: int)
	var _cb_outline  = null   # func(pressed: bool)

	func _init(logger):
		LOGGER = logger

	## Assign all five callbacks at once.
	func set_callbacks(cb_tex, cb_col, cb_rot, cb_lay, cb_out):
		_cb_texture  = cb_tex
		_cb_color    = cb_col
		_cb_rotation = cb_rot
		_cb_layer    = cb_lay
		_cb_outline  = cb_out

	## Build and return a VBoxContainer with all controls.
	## The pattern grid slot is left empty — populate via try_build_grid_menu().
	func build() -> VBoxContainer:
		var sec = VBoxContainer.new()
		sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		sec.add_child(_label("Pattern:"))
		_menu_container = VBoxContainer.new()
		_menu_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sec.add_child(_menu_container)

		sec.add_child(_spacer(6))

		sec.add_child(_label("Color:"))
		color_picker = ColorPickerButton.new()
		color_picker.color = Color.white
		color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		color_picker.connect("color_changed", self, "_on_color_changed")
		sec.add_child(color_picker)

		sec.add_child(_label("Rotation (deg):"))
		rotation_spin = SpinBox.new()
		rotation_spin.min_value = 0
		rotation_spin.max_value = 360
		rotation_spin.step = 1
		rotation_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rotation_spin.connect("value_changed", self, "_on_rotation_changed")
		sec.add_child(rotation_spin)

		sec.add_child(_label("Layer:"))
		layer_spin = SpinBox.new()
		layer_spin.min_value = 0
		layer_spin.max_value = 9
		layer_spin.step = 1
		layer_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		layer_spin.connect("value_changed", self, "_on_layer_changed")
		sec.add_child(layer_spin)

		outline_check = CheckButton.new()
		outline_check.text = "Outline"
		outline_check.connect("toggled", self, "_on_outline_toggled")
		sec.add_child(outline_check)

		return sec

	## Lazily populate the pattern ItemList from PatternShapeTool.textureMenu.
	## Safe to call multiple times — exits early if already built.
	## Pass Global via tool.parent_mod.Global.
	func try_build_grid_menu(gl) -> void:
		if _grid_menu != null or _menu_container == null:
			return

		if not gl.Editor or not gl.Editor.Tools.has("PatternShapeTool"):
			if LOGGER: LOGGER.warn("PatternPanel: PatternShapeTool not in Tools[].")
			return

		# We read textureMenu only to copy icons and the Lookup dict.
		# We never reparent or call OnItemSelected on it — its C# lambda would
		# crash via Infobar.SetAssetInfo when PatternShapeTool is not active.
		var source_menu = gl.Editor.Tools["PatternShapeTool"].get("textureMenu")
		if not source_menu:
			if LOGGER: LOGGER.warn("PatternPanel: textureMenu is null.")
			return

		var count = source_menu.get_item_count()
		if count == 0:
			if LOGGER: LOGGER.warn("PatternPanel: textureMenu has 0 items.")
			return

		var lookup = source_menu.get("Lookup")   # { resource_path: index }
		if not lookup or lookup.empty():
			if LOGGER: LOGGER.warn("PatternPanel: GridMenu.Lookup is empty.")
			return

		# Invert to { index: resource_path }
		_index_to_path.clear()
		for path in lookup.keys():
			_index_to_path[lookup[path]] = path

		var scroll = ScrollContainer.new()
		scroll.rect_min_size = Vector2(0, 160)
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		_grid_menu = ItemList.new()
		_grid_menu.icon_mode = ItemList.ICON_MODE_TOP
		_grid_menu.fixed_icon_size = Vector2(48, 48)
		_grid_menu.fixed_column_width = 56
		_grid_menu.max_columns = 0
		_grid_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid_menu.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_grid_menu.connect("item_selected", self, "_on_texture_selected")

		for i in range(count):
			var icon = source_menu.get_item_icon(i)
			var tooltip = _index_to_path.get(i, str(i)).get_file().get_basename()
			if icon:
				_grid_menu.add_item("", icon)
			else:
				_grid_menu.add_item(tooltip)
			_grid_menu.set_item_tooltip(_grid_menu.get_item_count() - 1, tooltip)

		scroll.add_child(_grid_menu)
		_menu_container.add_child(scroll)

		var restore_idx: int = min(_selected_index, count - 1)
		_grid_menu.select(restore_idx)
		_on_texture_selected(restore_idx)

		if LOGGER: LOGGER.info("PatternPanel: ItemList built with %d items." % count)

	## Tear down the ItemList and free all child nodes from the container.
	func release() -> void:
		if not _grid_menu:
			return
		# Persist current selection before destroying the node
		var sel: Array = _grid_menu.get_selected_items()
		if not sel.empty():
			_selected_index = sel[0]
		if _grid_menu.is_connected("item_selected", self, "_on_texture_selected"):
			_grid_menu.disconnect("item_selected", self, "_on_texture_selected")
		for child in _menu_container.get_children():
			_menu_container.remove_child(child)
			child.queue_free()
		_grid_menu = null
		_index_to_path.clear()

	# ---- internal callbacks ----

	func _on_texture_selected(index: int):
		var path: String = _index_to_path.get(index, "")
		if path == "":
			return
		# no_cache=false: reuse Dungeondraft's cached texture instance so that the
		# asset-tag lookup in SelectTool and SetOptions works correctly.
		var tex = ResourceLoader.load(path, "Texture", false)
		if _cb_texture: _cb_texture.call_func(tex)

	func _on_color_changed(color: Color):
		if _cb_color: _cb_color.call_func(color)

	func _on_rotation_changed(value: float):
		if _cb_rotation: _cb_rotation.call_func(value)

	func _on_layer_changed(value: float):
		if _cb_layer: _cb_layer.call_func(int(value))

	func _on_outline_toggled(pressed: bool):
		if _cb_outline: _cb_outline.call_func(pressed)

	# ---- node helpers ----

	func _label(text: String) -> Label:
		var lbl = Label.new()
		lbl.text = text
		return lbl

	func _spacer(height: int) -> Control:
		var s = Control.new()
		s.rect_min_size = Vector2(0, height)
		return s


# ============================================================================
# WALL PANEL
# Reusable panel: wall texture grid + shadow / bevel.
# ============================================================================

class WallPanel:

	var LOGGER = null

	# ---- UI nodes ----
	var _menu_container  = null   # VBoxContainer — placeholder for the scroll
	var _grid_menu       = null   # ItemList (owned)
	var _index_to_path   = {}     # { int index -> String resource_path }
	var _source_menu     = null   # WallTool Controls["Texture"] GridMenu reference
	var _wall_tool       = null   # WallTool reference — used for GetWallColor()
	var _selected_index: int = 0  # persists across release/rebuild cycles

	var color_picker = null   # ColorPickerButton
	var shadow_check = null   # CheckButton
	var bevel_check  = null   # CheckButton

	# ---- callbacks (FuncRef) ----
	var _cb_color  = null   # func(color: Color)
	var _cb_shadow = null   # func(pressed: bool)
	var _cb_bevel  = null   # func(pressed: bool)

	func _init(logger):
		LOGGER = logger

	## Assign color, shadow and bevel callbacks.
	func set_callbacks(cb_col, cb_shad, cb_bev):
		_cb_color  = cb_col
		_cb_shadow = cb_shad
		_cb_bevel  = cb_bev

	## Build and return a VBoxContainer with all controls.
	## The wall grid slot is left empty — populate via try_build_grid_menu().
	func build() -> VBoxContainer:
		var sec = VBoxContainer.new()
		sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		sec.add_child(_label("Wall:"))
		_menu_container = VBoxContainer.new()
		_menu_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sec.add_child(_menu_container)

		sec.add_child(_spacer(6))

		sec.add_child(_label("Color:"))
		color_picker = ColorPickerButton.new()
		color_picker.color = Color.white
		color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		color_picker.connect("color_changed", self, "_on_color_changed")
		sec.add_child(color_picker)

		sec.add_child(_spacer(4))

		shadow_check = CheckButton.new()
		shadow_check.text = "Shadow"
		shadow_check.pressed = true
		shadow_check.connect("toggled", self, "_on_shadow_toggled")
		sec.add_child(shadow_check)

		bevel_check = CheckButton.new()
		bevel_check.text = "Bevel corners"
		bevel_check.pressed = true
		bevel_check.connect("toggled", self, "_on_bevel_toggled")
		sec.add_child(bevel_check)

		return sec

	## Lazily populate the wall ItemList from WallTool.Controls["Texture"].
	## Safe to call multiple times — exits early if already built.
	func try_build_grid_menu(gl) -> void:
		if _grid_menu != null or _menu_container == null:
			return

		if not gl.Editor or not gl.Editor.Tools.has("WallTool"):
			if LOGGER: LOGGER.warn("WallPanel: WallTool not in Tools[].")
			return

		# WallTool exposes its GridMenu via Controls["Texture"].
		var wt = gl.Editor.Tools["WallTool"]
		var controls = wt.get("Controls")
		if not controls or not controls.has("Texture"):
			if LOGGER: LOGGER.warn("WallPanel: WallTool.Controls[Texture] not found.")
			return

		_wall_tool = wt
		var source_menu = controls["Texture"]
		if not source_menu:
			if LOGGER: LOGGER.warn("WallPanel: WallTool Controls[Texture] is null.")
			return

		var count = source_menu.get_item_count()
		if count == 0:
			if LOGGER: LOGGER.warn("WallPanel: WallTool Controls[Texture] has 0 items.")
			return

		_source_menu = source_menu

		var lookup = source_menu.get("Lookup")   # { resource_path: index }
		if not lookup or lookup.empty():
			if LOGGER: LOGGER.warn("WallPanel: WallTool GridMenu.Lookup is empty.")
			return

		# Invert to { index: resource_path }
		_index_to_path.clear()
		for path in lookup.keys():
			_index_to_path[lookup[path]] = path

		var scroll = ScrollContainer.new()
		scroll.rect_min_size = Vector2(0, 160)
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		_grid_menu = ItemList.new()
		_grid_menu.icon_mode = ItemList.ICON_MODE_TOP
		_grid_menu.fixed_icon_size = Vector2(48, 48)
		_grid_menu.fixed_column_width = 56
		_grid_menu.max_columns = 0
		_grid_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid_menu.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_grid_menu.connect("item_selected", self, "_on_texture_selected")

		for i in range(count):
			var icon = source_menu.get_item_icon(i)
			var tooltip = _index_to_path.get(i, str(i)).get_file().get_basename()
			if icon:
				_grid_menu.add_item("", icon)
			else:
				_grid_menu.add_item(tooltip)
			_grid_menu.set_item_tooltip(_grid_menu.get_item_count() - 1, tooltip)

		scroll.add_child(_grid_menu)
		_menu_container.add_child(scroll)

		var restore_idx: int = min(_selected_index, count - 1)
		_grid_menu.select(restore_idx)
		_on_texture_selected(restore_idx)

		if LOGGER: LOGGER.info("WallPanel: ItemList built with %d items." % count)

	## Tear down the ItemList and free all child nodes from the container.
	func release() -> void:
		if not _grid_menu:
			return
		# Persist current selection before destroying the node
		var sel: Array = _grid_menu.get_selected_items()
		if not sel.empty():
			_selected_index = sel[0]
		if _grid_menu.is_connected("item_selected", self, "_on_texture_selected"):
			_grid_menu.disconnect("item_selected", self, "_on_texture_selected")
		for child in _menu_container.get_children():
			_menu_container.remove_child(child)
			child.queue_free()
		_grid_menu = null
		_source_menu = null
		_wall_tool = null
		_index_to_path.clear()

	# ---- internal callbacks ----

	# Wall texture selection drives WallTool directly via OnItemSelected —
	# same technique used by AdditionalSearchOptions. This avoids guessing the
	# resource path format (png vs tres) for ResourceLoader.
	# After selection, read back the default color for this wall style and
	# sync it to both the color picker and the active_color setting.
	func _on_texture_selected(index: int):
		if _source_menu and _source_menu.has_method("OnItemSelected"):
			_source_menu.OnItemSelected(index)
		if _wall_tool and _wall_tool.has_method("GetWallColor"):
			# Pass current texture so GetWallColor returns the style-specific default.
			# WallTool.Texture is already updated by OnItemSelected above.
			var wall_texture = _wall_tool.get("Texture")
			var default_color: Color = _wall_tool.GetWallColor(wall_texture)
			if color_picker:
				color_picker.color = default_color
			if _cb_color:
				_cb_color.call_func(default_color)

	func _on_color_changed(color: Color):
		if _cb_color: _cb_color.call_func(color)

	func _on_shadow_toggled(pressed: bool):
		if _cb_shadow: _cb_shadow.call_func(pressed)

	func _on_bevel_toggled(pressed: bool):
		if _cb_bevel: _cb_bevel.call_func(pressed)

	# ---- node helpers ----

	func _label(text: String) -> Label:
		var lbl = Label.new()
		lbl.text = text
		return lbl

	func _spacer(height: int) -> Control:
		var s = Control.new()
		s.rect_min_size = Vector2(0, height)
		return s


# ============================================================================
# REFERENCES
# ============================================================================

var _tool  = null
var LOGGER = null

# shared
var _mode_selector = null

# Pattern Fill section
var _pf_section       = null
var _pf_pattern_panel = null   # PatternPanel

# Wall Builder section
var _wb_section    = null
var _wb_wall_panel = null   # WallPanel

# Room Builder section
var _rb_section            = null
var _rb_sub_mode_selector  = null   # OptionButton
var _rb_pattern_panel      = null   # PatternPanel
var _rb_wall_panel         = null   # WallPanel

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

	# ---- Create panel instances ----
	_pf_pattern_panel = PatternPanel.new(LOGGER)
	_wb_wall_panel    = WallPanel.new(LOGGER)
	_rb_pattern_panel = PatternPanel.new(LOGGER)
	_rb_wall_panel    = WallPanel.new(LOGGER)

	# ---- Wire callbacks — Pattern Fill ----
	_pf_pattern_panel.set_callbacks(
		funcref(self, "_on_pf_texture"),
		funcref(self, "_on_pf_color"),
		funcref(self, "_on_pf_rotation"),
		funcref(self, "_on_pf_layer"),
		funcref(self, "_on_pf_outline")
	)

	# ---- Wire callbacks — Wall Builder ----
	_wb_wall_panel.set_callbacks(
		funcref(self, "_on_wb_color"),
		funcref(self, "_on_wb_shadow"),
		funcref(self, "_on_wb_bevel")
	)

	# ---- Wire callbacks — Room Builder ----
	_rb_pattern_panel.set_callbacks(
		funcref(self, "_on_rb_texture"),
		funcref(self, "_on_rb_color"),
		funcref(self, "_on_rb_rotation"),
		funcref(self, "_on_rb_layer"),
		funcref(self, "_on_rb_outline")
	)
	_rb_wall_panel.set_callbacks(
		funcref(self, "_on_rb_wall_color"),
		funcref(self, "_on_rb_shadow"),
		funcref(self, "_on_rb_bevel")
	)

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
	return _pf_pattern_panel.build()

func _build_wall_builder_section() -> VBoxContainer:
	return _wb_wall_panel.build()

func _build_room_builder_section() -> VBoxContainer:
	var sec = VBoxContainer.new()
	sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ---- Sub-mode selector ----
	var sub_mode_label = Label.new()
	sub_mode_label.text = "Sub-mode:"
	sec.add_child(sub_mode_label)

	_rb_sub_mode_selector = OptionButton.new()
	_rb_sub_mode_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rb_sub_mode_selector.add_item("Single", 0)
	_rb_sub_mode_selector.add_item("Merge",  1)
	_rb_sub_mode_selector.selected = 0
	_rb_sub_mode_selector.connect("item_selected", self, "_on_rb_sub_mode")
	sec.add_child(_rb_sub_mode_selector)

	sec.add_child(_separator())
	sec.add_child(_rb_pattern_panel.build())
	sec.add_child(_separator())
	sec.add_child(_rb_wall_panel.build())
	return sec

# ============================================================================
# GRID MENU LIFECYCLE
# ============================================================================

## Called once on Enable() — lazily populates all grid menus.
func try_build_all_grid_menus() -> void:
	if not _tool or not _tool.parent_mod:
		return
	var gl = _tool.parent_mod.Global
	_pf_pattern_panel.try_build_grid_menu(gl)
	_wb_wall_panel.try_build_grid_menu(gl)
	_rb_pattern_panel.try_build_grid_menu(gl)
	_rb_wall_panel.try_build_grid_menu(gl)

## Called on Disable() — tears down all grid menus.
func release_all_grid_menus() -> void:
	_pf_pattern_panel.release()
	_wb_wall_panel.release()
	_rb_pattern_panel.release()
	_rb_wall_panel.release()

# ============================================================================
# SECTION VISIBILITY
# ============================================================================

func _show_section(mode: int):
	if _pf_section: _pf_section.visible = (mode == MODE_PATTERN_FILL)
	if _wb_section: _wb_section.visible = (mode == MODE_WALL_BUILDER)
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

func _on_pf_texture(texture):
	if _tool._pattern_fill:
		_tool._pattern_fill.active_texture = texture

func _on_pf_color(color: Color):
	if _tool._pattern_fill:
		_tool._pattern_fill.active_color = color

func _on_pf_rotation(value: float):
	if _tool._pattern_fill:
		_tool._pattern_fill.active_rotation = value

func _on_pf_layer(value: int):
	if _tool._pattern_fill:
		_tool._pattern_fill.active_layer = value

func _on_pf_outline(pressed: bool):
	if _tool._pattern_fill:
		_tool._pattern_fill.active_outline = pressed

# ============================================================================
# CALLBACKS — WALL BUILDER
# ============================================================================

func _on_wb_color(color: Color):
	if _tool._wall_builder:
		_tool._wall_builder.active_color = color

func _on_wb_shadow(pressed: bool):
	if _tool._wall_builder:
		_tool._wall_builder.active_shadow = pressed

func _on_wb_bevel(pressed: bool):
	if _tool._wall_builder:
		# 0 = Sharp, 1 = Bevel, 2 = Round
		_tool._wall_builder.active_joint = 1 if pressed else 0

# ============================================================================
# CALLBACKS — ROOM BUILDER
# ============================================================================

func _on_rb_texture(texture):
	if _tool._room_builder:
		_tool._room_builder.active_texture = texture

func _on_rb_color(color: Color):
	if _tool._room_builder:
		_tool._room_builder.active_color = color

func _on_rb_rotation(value: float):
	if _tool._room_builder:
		_tool._room_builder.active_rotation = value

func _on_rb_layer(value: int):
	if _tool._room_builder:
		_tool._room_builder.active_layer = value

func _on_rb_outline(pressed: bool):
	if _tool._room_builder:
		_tool._room_builder.active_outline = pressed

func _on_rb_wall_color(color: Color):
	if _tool._room_builder:
		_tool._room_builder.active_wall_color = color

func _on_rb_shadow(pressed: bool):
	if _tool._room_builder:
		_tool._room_builder.active_shadow = pressed

func _on_rb_bevel(pressed: bool):
	if _tool._room_builder:
		# 0 = Sharp, 1 = Bevel, 2 = Round
		_tool._room_builder.active_joint = 1 if pressed else 0

func _on_rb_sub_mode(index: int):
	if _tool._room_builder:
		var RoomBuilderScript = _tool._room_builder
		RoomBuilderScript.active_sub_mode = index

# ============================================================================
# HELPERS
# ============================================================================

func _spacer(height: int) -> Control:
	var s = Control.new()
	s.rect_min_size = Vector2(0, height)
	return s

func _separator() -> HSeparator:
	return HSeparator.new()
