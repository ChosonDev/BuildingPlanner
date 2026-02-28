extends Reference

# BuildingPlanner - Dungeondraft Mod
# Sidebar UI panel for the BuildingPlanner tool.
#
# Layout
#   Title
#   Mode OptionButton  (Pattern Fill / Wall Builder / Path Builder / Room Builder / Roof Builder)
#   ── section: Pattern Fill ──────────────────────────────────────
#     PatternPanel  (pattern grid, color, rotation, layer, outline)
#   ── section: Wall Builder ──────────────────────────────────────
#     WallPanel  (wall grid, color, shadow, bevel)
#   ── section: Path Builder ──────────────────────────────────────
#     PathPanel  (path grid, color, width, smoothness, layer, sorting, effects)
#   ── section: Room Builder ──────────────────────────────────────
#     PatternPanel  (pattern grid, color, rotation, layer, outline)
#     ──────────────────────────────────────────────────────────
#     WallPanel  (wall grid, color, shadow, bevel)
#   ── section: Roof Builder ──────────────────────────────────────
#     RoofPanel  (roof style grid, width, type, sorting, shade)

const CLASS_NAME = "BuildingPlannerToolUI"

# Mode constants mirror BuildingPlannerTool.Mode
const MODE_NONE         = 0
const MODE_PATTERN_FILL = 1
const MODE_WALL_BUILDER = 2
const MODE_PATH_BUILDER = 3
const MODE_ROOM_BUILDER = 4
const MODE_ROOF_BUILDER = 5

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
	var _pst             = null   # PatternShapeTool reference — used for GetDefaultColor()
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

		_pst = gl.Editor.Tools["PatternShapeTool"]

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

		# Build items and tint each icon with the DD default color.
		# ResourceLoader returns the cached texture so this is effectively free.
		for i in range(count):
			var icon = source_menu.get_item_icon(i)
			var tooltip = _index_to_path.get(i, str(i)).get_file().get_basename()
			if icon:
				_grid_menu.add_item("", icon)
			else:
				_grid_menu.add_item(tooltip)
			var item_idx: int = _grid_menu.get_item_count() - 1
			_grid_menu.set_item_tooltip(item_idx, tooltip)
			var path: String = _index_to_path.get(i, "")
			if path != "" and _pst and _pst.has_method("GetDefaultColor"):
				var tex = ResourceLoader.load(path, "Texture", false)
				if tex:
					_grid_menu.set_item_icon_modulate(item_idx, _pst.GetDefaultColor(tex))

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
		_pst = null
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
		# Sync color picker to the DD default color for this texture.
		# PatternShapeTool.GetDefaultColor(texture) is the pattern equivalent
		# of WallTool.GetWallColor(texture).
		if _pst and _pst.has_method("GetDefaultColor") and tex:
			var default_color: Color = _pst.GetDefaultColor(tex)
			if color_picker:
				color_picker.color = default_color
			if _cb_color:
				_cb_color.call_func(default_color)

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

		# Build items and tint each icon with the DD default color.
		# ResourceLoader returns the cached texture so this is effectively free.
		for i in range(count):
			var icon = source_menu.get_item_icon(i)
			var tooltip = _index_to_path.get(i, str(i)).get_file().get_basename()
			if icon:
				_grid_menu.add_item("", icon)
			else:
				_grid_menu.add_item(tooltip)
			var item_idx: int = _grid_menu.get_item_count() - 1
			_grid_menu.set_item_tooltip(item_idx, tooltip)
			var path: String = _index_to_path.get(i, "")
			if path != "" and _wall_tool and _wall_tool.has_method("GetWallColor"):
				var tex = ResourceLoader.load(path, "Texture", false)
				if tex:
					_grid_menu.set_item_icon_modulate(item_idx, _wall_tool.GetWallColor(tex))

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
# PATH PANEL
# Reusable panel: path texture grid + width / smoothness / effects.
# ============================================================================

class PathPanel:

	var LOGGER = null

	# ---- UI nodes ----
	var _menu_container  = null   # VBoxContainer — placeholder for the scroll
	var _grid_menu       = null   # ItemList (owned)
	var _index_to_path   = {}     # { int index -> String resource_path }
	var _source_menu     = null   # PathTool Controls["Texture"] GridMenu reference  
	var _path_tool       = null   # PathTool reference
	var _selected_index: int = 0  # persists across release/rebuild cycles

	var color_picker      = null   # ColorPickerButton
	var width_spin        = null   # SpinBox
	var smoothness_slider = null   # HSlider
	var layer_spin        = null   # SpinBox
	var sorting_option    = null   # OptionButton
	
	# Effects
	var fade_in_check     = null   # CheckButton
	var fade_out_check    = null   # CheckButton
	var grow_check        = null   # CheckButton
	var shrink_check      = null   # CheckButton
	var block_light_check = null   # CheckButton

	# ---- callbacks (FuncRef) ----
	var _cb_color      = null
	var _cb_width      = null
	var _cb_smoothness = null
	var _cb_layer      = null
	var _cb_sorting    = null
	var _cb_fade_in    = null
	var _cb_fade_out   = null
	var _cb_grow       = null
	var _cb_shrink     = null
	var _cb_block_light = null

	func _init(logger):
		LOGGER = logger

	## Assign all ten callbacks at once.
	func set_callbacks(cb_col, cb_wid, cb_smooth, cb_lay, cb_sort, 
			cb_fade_in, cb_fade_out, cb_grow, cb_shrink, cb_block):
		_cb_color       = cb_col
		_cb_width       = cb_wid
		_cb_smoothness  = cb_smooth
		_cb_layer       = cb_lay
		_cb_sorting     = cb_sort
		_cb_fade_in     = cb_fade_in
		_cb_fade_out    = cb_fade_out
		_cb_grow        = cb_grow
		_cb_shrink      = cb_shrink
		_cb_block_light = cb_block

	## Build and return a VBoxContainer with all controls.
	## The path grid slot is left empty — populate via try_build_grid_menu().
	func build() -> VBoxContainer:
		var sec = VBoxContainer.new()
		sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		sec.add_child(_label("Path:"))
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

		sec.add_child(_label("Width:"))
		width_spin = SpinBox.new()
		width_spin.min_value = 0.1
		width_spin.max_value = 10.0
		width_spin.step = 0.1
		width_spin.value = 1.0
		width_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		width_spin.connect("value_changed", self, "_on_width_changed")
		sec.add_child(width_spin)

		sec.add_child(_label("Smoothness:"))
		smoothness_slider = HSlider.new()
		smoothness_slider.min_value = 0.0
		smoothness_slider.max_value = 1.0
		smoothness_slider.step = 0.01
		smoothness_slider.value = 0.0
		smoothness_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		smoothness_slider.connect("value_changed", self, "_on_smoothness_changed")
		sec.add_child(smoothness_slider)

		sec.add_child(_label("Layer:"))
		layer_spin = SpinBox.new()
		layer_spin.min_value = 0
		layer_spin.max_value = 9
		layer_spin.step = 1
		layer_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		layer_spin.connect("value_changed", self, "_on_layer_changed")
		sec.add_child(layer_spin)

		sec.add_child(_label("Sorting:"))
		sorting_option = OptionButton.new()
		sorting_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sorting_option.add_item("Over", 0)
		sorting_option.add_item("Under", 1)
		sorting_option.connect("item_selected", self, "_on_sorting_selected")
		sec.add_child(sorting_option)

		sec.add_child(_spacer(4))

		fade_in_check = CheckButton.new()
		fade_in_check.text = "Fade In"
		fade_in_check.connect("toggled", self, "_on_fade_in_toggled")
		sec.add_child(fade_in_check)

		fade_out_check = CheckButton.new()
		fade_out_check.text = "Fade Out"
		fade_out_check.connect("toggled", self, "_on_fade_out_toggled")
		sec.add_child(fade_out_check)

		grow_check = CheckButton.new()
		grow_check.text = "Grow (Taper Start)"
		grow_check.connect("toggled", self, "_on_grow_toggled")
		sec.add_child(grow_check)

		shrink_check = CheckButton.new()
		shrink_check.text = "Shrink (Taper End)"
		shrink_check.connect("toggled", self, "_on_shrink_toggled")
		sec.add_child(shrink_check)

		block_light_check = CheckButton.new()
		block_light_check.text = "Block Light"
		block_light_check.connect("toggled", self, "_on_block_light_toggled")
		sec.add_child(block_light_check)

		return sec

	## Lazily populate the path ItemList from PathTool.Controls["Texture"].
	## Safe to call multiple times — exits early if already built.
	func try_build_grid_menu(gl) -> void:
		if _grid_menu != null or _menu_container == null:
			return

		if not gl.Editor or not gl.Editor.Tools.has("PathTool"):
			if LOGGER: LOGGER.warn("PathPanel: PathTool not in Tools[].")
			return

		# PathTool exposes its GridMenu via Controls["Texture"] (same as WallTool).
		var pt = gl.Editor.Tools["PathTool"]
		var controls = pt.get("Controls")
		if not controls or not controls.has("Texture"):
			if LOGGER: LOGGER.warn("PathPanel: PathTool.Controls[Texture] not found.")
			return

		_path_tool = pt
		var source_menu = controls["Texture"]
		if not source_menu:
			if LOGGER: LOGGER.warn("PathPanel: PathTool Controls[Texture] is null.")
			return

		var count = source_menu.get_item_count()
		if count == 0:
			if LOGGER: LOGGER.warn("PathPanel: PathTool Controls[Texture] has 0 items.")
			return

		_source_menu = source_menu

		var lookup = source_menu.get("Lookup")   # { resource_path: index }
		if not lookup or lookup.empty():
			if LOGGER: LOGGER.warn("PathPanel: PathTool GridMenu.Lookup is empty.")
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

		# Build items — paths don't have a GetPathColor() equivalent,
		# so we use default white modulation for all icons.
		for i in range(count):
			var icon = source_menu.get_item_icon(i)
			var tooltip = _index_to_path.get(i, str(i)).get_file().get_basename()
			if icon:
				_grid_menu.add_item("", icon)
			else:
				_grid_menu.add_item(tooltip)
			var item_idx: int = _grid_menu.get_item_count() - 1
			_grid_menu.set_item_tooltip(item_idx, tooltip)

		scroll.add_child(_grid_menu)
		_menu_container.add_child(scroll)

		var restore_idx: int = min(_selected_index, count - 1)
		_grid_menu.select(restore_idx)
		_on_texture_selected(restore_idx)

		if LOGGER: LOGGER.info("PathPanel: ItemList built with %d items." % count)

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
		_path_tool = null
		_index_to_path.clear()

	## Enables or disables the color picker based on CAMT presence.
	## ColourAndModifyThings is detected via the "UchideshiNodeData" key it
	## creates in ModMapData. Without CAMT the color cannot persist past a
	## map reload, so the picker is disabled and reset to white.
	## Call from try_build_all_grid_menus() once Global is available.
	func update_camt_color_state(gl) -> void:
		if not color_picker:
			return
		var camt_present: bool = gl.ModMapData.has("UchideshiNodeData")
		color_picker.disabled = not camt_present
		if camt_present:
			color_picker.hint_tooltip = ""
		else:
			color_picker.color = Color.white
			color_picker.hint_tooltip = "Requires ColourAndModifyThings mod (color won't persist without it)"
			if _cb_color:
				_cb_color.call_func(Color.white)

	# ---- internal callbacks ----

	# Path texture selection drives PathTool directly via OnItemSelected —
	# same technique used by WallPanel. Color picker stays at user-set value
	# since PathTool doesn't have GetPathColor() equivalent.
	func _on_texture_selected(index: int):
		if _source_menu and _source_menu.has_method("OnItemSelected"):
			_source_menu.OnItemSelected(index)

	func _on_color_changed(color: Color):
		if _cb_color: _cb_color.call_func(color)

	func _on_width_changed(value: float):
		if _cb_width: _cb_width.call_func(value)

	func _on_smoothness_changed(value: float):
		if _cb_smoothness: _cb_smoothness.call_func(value)

	func _on_layer_changed(value: float):
		if _cb_layer: _cb_layer.call_func(int(value))

	func _on_sorting_selected(index: int):
		if _cb_sorting: _cb_sorting.call_func(index)

	func _on_fade_in_toggled(pressed: bool):
		if _cb_fade_in: _cb_fade_in.call_func(pressed)

	func _on_fade_out_toggled(pressed: bool):
		if _cb_fade_out: _cb_fade_out.call_func(pressed)

	func _on_grow_toggled(pressed: bool):
		if _cb_grow: _cb_grow.call_func(pressed)

	func _on_shrink_toggled(pressed: bool):
		if _cb_shrink: _cb_shrink.call_func(pressed)

	func _on_block_light_toggled(pressed: bool):
		if _cb_block_light: _cb_block_light.call_func(pressed)

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
# ROOF PANEL
# Panel: roof texture grid (from RoofTool) + width / type / sorting / shade.
# ============================================================================

class RoofPanel:

	var LOGGER = null

	# ---- UI nodes ----
	var _menu_container  = null   # VBoxContainer — placeholder for the scroll/label
	var _grid_menu       = null   # ItemList (owned; null when RoofTool has no Controls)
	var _index_to_path   = {}     # { int index -> String resource_path }
	var _source_menu     = null   # RoofTool Controls["Texture"] GridMenu reference
	var _roof_tool       = null   # RoofTool reference
	var _selected_index: int = 0  # persists across release/rebuild cycles
	var _no_grid_label   = null   # shown when texture grid is unavailable

	var width_spin          = null   # SpinBox
	var type_option         = null   # OptionButton  (Gable/Hip/Dormer)
	var sorting_option      = null   # OptionButton  (Over/Under)
	var placement_mode_option = null # OptionButton  (Ridge/Expand/Inset)
	var shade_check         = null   # CheckButton
	var _shade_sub     = null   # VBoxContainer — visible only when shade = true
	var sun_dir_slider = null   # HSlider
	var contrast_slider = null  # HSlider

	var _cb_texture        = null   # func(texture: Texture)
	var _cb_width          = null   # func(value: float)
	var _cb_type           = null   # func(index: int)  0=Gable 1=Hip 2=Dormer
	var _cb_sorting        = null   # func(index: int)  0=Over  1=Under
	var _cb_placement_mode = null   # func(index: int)  0=Ridge 1=Expand 2=Inset
	var _cb_shade          = null   # func(pressed: bool)
	var _cb_sun_dir        = null   # func(value: float)
	var _cb_contrast       = null   # func(value: float)

	func _init(logger):
		LOGGER = logger

	## Assign all eight callbacks at once.
	func set_callbacks(cb_tex, cb_wid, cb_typ, cb_sort, cb_place, cb_shade, cb_sun, cb_con):
		_cb_texture        = cb_tex
		_cb_width          = cb_wid
		_cb_type           = cb_typ
		_cb_sorting        = cb_sort
		_cb_placement_mode = cb_place
		_cb_shade          = cb_shade
		_cb_sun_dir        = cb_sun
		_cb_contrast       = cb_con

	## Build and return a VBoxContainer with all controls.
	## The texture slot shows a fallback label until try_build_grid_menu() succeeds.
	func build() -> VBoxContainer:
		var sec = VBoxContainer.new()
		sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# ---- Texture ----
		sec.add_child(_label("Roof Style:"))
		_menu_container = VBoxContainer.new()
		_menu_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sec.add_child(_menu_container)

		_no_grid_label = Label.new()
		_no_grid_label.text = "(Select style in RoofTool panel)"
		_no_grid_label.modulate = Color(0.7, 0.7, 0.7, 1.0)
		_no_grid_label.autowrap = true
		_menu_container.add_child(_no_grid_label)

		sec.add_child(_spacer(6))

		# ---- Width ----
		sec.add_child(_label("Width (px):"))
		width_spin = SpinBox.new()
		width_spin.min_value = 5.0
		width_spin.max_value = 500.0
		width_spin.step = 1.0
		width_spin.value = 50.0
		width_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		width_spin.connect("value_changed", self, "_on_width_changed")
		sec.add_child(width_spin)

		# ---- Type ----
		sec.add_child(_label("Type:"))
		type_option = OptionButton.new()
		type_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		type_option.add_item("Gable",  0)
		type_option.add_item("Hip",    1)
		type_option.add_item("Dormer", 2)
		type_option.connect("item_selected", self, "_on_type_selected")
		sec.add_child(type_option)

		# ---- Sorting ----
		sec.add_child(_label("Layer:"))
		sorting_option = OptionButton.new()
		sorting_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sorting_option.add_item("Over",  0)
		sorting_option.add_item("Under", 1)
		sorting_option.connect("item_selected", self, "_on_sorting_selected")
		sec.add_child(sorting_option)

		sec.add_child(_spacer(4))

		# ---- Placement mode ----
		sec.add_child(_label("Placement Mode:"))
		placement_mode_option = OptionButton.new()
		placement_mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		placement_mode_option.add_item("Ridge along area",  0)
		placement_mode_option.add_item("Expand (eave at area, roof outside)", 1)
		placement_mode_option.add_item("Inset  (eave at area, roof inside)",  2)
		placement_mode_option.hint_tooltip = "Ridge: polygon edge is the ridge line, eave expands outward.\nExpand: polygon is the eave edge, ridge is outside the area.\nInset: polygon is the eave edge, ridge is inside the area."
		placement_mode_option.connect("item_selected", self, "_on_placement_mode_selected")
		sec.add_child(placement_mode_option)

		sec.add_child(_spacer(4))

		# ---- Shade ----
		shade_check = CheckButton.new()
		shade_check.text = "Sunlight Shading"
		shade_check.connect("toggled", self, "_on_shade_toggled")
		sec.add_child(shade_check)

		_shade_sub = VBoxContainer.new()
		_shade_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_shade_sub.visible = false

		_shade_sub.add_child(_label("Sun Direction (deg):"))
		sun_dir_slider = HSlider.new()
		sun_dir_slider.min_value = 0.0
		sun_dir_slider.max_value = 360.0
		sun_dir_slider.step = 1.0
		sun_dir_slider.value = 0.0
		sun_dir_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sun_dir_slider.connect("value_changed", self, "_on_sun_dir_changed")
		_shade_sub.add_child(sun_dir_slider)

		_shade_sub.add_child(_label("Shade Contrast:"))
		contrast_slider = HSlider.new()
		contrast_slider.min_value = 0.0
		contrast_slider.max_value = 1.0
		contrast_slider.step = 0.01
		contrast_slider.value = 0.5
		contrast_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		contrast_slider.connect("value_changed", self, "_on_contrast_changed")
		_shade_sub.add_child(contrast_slider)

		sec.add_child(_shade_sub)

		return sec

	## Lazily populate the texture ItemList from RoofTool.Controls["Texture"].
	## Also syncs width/type/sorting defaults from the current RoofTool state.
	## Safe to call multiple times — exits early if already built.
	func try_build_grid_menu(gl) -> void:
		if _menu_container == null:
			return

		if not gl.Editor or not gl.Editor.Tools.has("RoofTool"):
			if LOGGER: LOGGER.warn("RoofPanel: RoofTool not in Tools[].")
			return

		var rt = gl.Editor.Tools["RoofTool"]
		_roof_tool = rt

		# Sync defaults from current RoofTool state (always, even without grid)
		var rt_width = rt.get("Width")
		if rt_width and rt_width.get("value") != null and width_spin:
			width_spin.value = rt_width.value
			if _cb_width: _cb_width.call_func(rt_width.value)

		var rt_sorting = rt.get("Sorting")
		if rt_sorting != null and sorting_option:
			sorting_option.selected = rt_sorting
			if _cb_sorting: _cb_sorting.call_func(rt_sorting)

		var rt_type = rt.get("Type")
		if rt_type != null and type_option:
			type_option.selected = rt_type
			if _cb_type: _cb_type.call_func(rt_type)

		# Guard: don't rebuild grid if already done
		if _grid_menu != null:
			return

		# Try to get the texture GridMenu from RoofTool
		var controls = rt.get("Controls")
		if not controls or not controls.has("Texture"):
			if LOGGER: LOGGER.info("RoofPanel: RoofTool.Controls[Texture] not available — using RoofTool selection.")
			return

		var source_menu = controls["Texture"]
		if not source_menu:
			return

		var count = source_menu.get_item_count()
		if count == 0:
			return

		_source_menu = source_menu

		var lookup = source_menu.get("Lookup")
		if not lookup or lookup.empty():
			return

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

		# Hide fallback label and show the real grid
		if _no_grid_label:
			_no_grid_label.visible = false
		_menu_container.add_child(scroll)

		var restore_idx: int = min(_selected_index, count - 1)
		_grid_menu.select(restore_idx)
		_on_texture_selected(restore_idx)

		if LOGGER: LOGGER.info("RoofPanel: ItemList built with %d items." % count)

	## Tear down the ItemList and free all child nodes from the container.
	func release() -> void:
		if _grid_menu:
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
			_index_to_path.clear()
			# Restore fallback label
			if _no_grid_label and not _no_grid_label.get_parent():
				_menu_container.add_child(_no_grid_label)
				_no_grid_label.visible = true
		_roof_tool = null

	# ---- internal callbacks ----

	func _on_texture_selected(index: int):
		if _source_menu and _source_menu.has_method("OnItemSelected"):
			_source_menu.OnItemSelected(index)
		if _roof_tool:
			var tex = _roof_tool.get("Texture")
			if tex and _cb_texture:
				_cb_texture.call_func(tex)

	func _on_width_changed(value: float):
		if _cb_width: _cb_width.call_func(value)

	func _on_type_selected(index: int):
		if _cb_type: _cb_type.call_func(index)

	func _on_sorting_selected(index: int):
		if _cb_sorting: _cb_sorting.call_func(index)

	func _on_placement_mode_selected(index: int):
		if _cb_placement_mode: _cb_placement_mode.call_func(index)

	func _on_shade_toggled(pressed: bool):
		if _shade_sub:
			_shade_sub.visible = pressed
		if _cb_shade: _cb_shade.call_func(pressed)

	func _on_sun_dir_changed(value: float):
		if _cb_sun_dir: _cb_sun_dir.call_func(value)

	func _on_contrast_changed(value: float):
		if _cb_contrast: _cb_contrast.call_func(value)

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

# Path Builder section
var _pb_section    = null
var _pb_path_panel = null   # PathPanel

# Room Builder section
var _rb_section               = null
var _rb_sub_mode_selector     = null   # OptionButton
var _rb_pattern_panel         = null   # PatternPanel
var _rb_outline_mode_selector = null   # OptionButton (Wall / Path)
var _rb_wall_panel            = null   # WallPanel
var _rb_wall_container        = null   # VBoxContainer — shown when outline mode = Wall
var _rb_path_panel            = null   # PathPanel
var _rb_path_container        = null   # VBoxContainer — shown when outline mode = Path

# Roof Builder section
var _rf_section    = null
var _rf_roof_panel = null   # RoofPanel

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
	_pb_path_panel    = PathPanel.new(LOGGER)
	_rb_pattern_panel = PatternPanel.new(LOGGER)
	_rb_wall_panel    = WallPanel.new(LOGGER)
	_rb_path_panel    = PathPanel.new(LOGGER)
	_rf_roof_panel    = RoofPanel.new(LOGGER)

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

	# ---- Wire callbacks — Path Builder ----
	_pb_path_panel.set_callbacks(
		funcref(self, "_on_pb_color"),
		funcref(self, "_on_pb_width"),
		funcref(self, "_on_pb_smoothness"),
		funcref(self, "_on_pb_layer"),
		funcref(self, "_on_pb_sorting"),
		funcref(self, "_on_pb_fade_in"),
		funcref(self, "_on_pb_fade_out"),
		funcref(self, "_on_pb_grow"),
		funcref(self, "_on_pb_shrink"),
		funcref(self, "_on_pb_block_light")
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
	_rb_path_panel.set_callbacks(
		funcref(self, "_on_rb_path_color"),
		funcref(self, "_on_rb_path_width"),
		funcref(self, "_on_rb_path_smoothness"),
		funcref(self, "_on_rb_path_layer"),
		funcref(self, "_on_rb_path_sorting"),
		funcref(self, "_on_rb_path_fade_in"),
		funcref(self, "_on_rb_path_fade_out"),
		funcref(self, "_on_rb_path_grow"),
		funcref(self, "_on_rb_path_shrink"),
		funcref(self, "_on_rb_path_block_light")
	)

	# ---- Wire callbacks — Roof Builder ----
	_rf_roof_panel.set_callbacks(
		funcref(self, "_on_rf_texture"),
		funcref(self, "_on_rf_width"),
		funcref(self, "_on_rf_type"),
		funcref(self, "_on_rf_sorting"),
		funcref(self, "_on_rf_placement_mode"),
		funcref(self, "_on_rf_shade"),
		funcref(self, "_on_rf_sun_direction"),
		funcref(self, "_on_rf_shade_contrast")
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
	_mode_selector.add_item("Path Builder",  MODE_PATH_BUILDER)
	_mode_selector.add_item("Room Builder",  MODE_ROOM_BUILDER)
	_mode_selector.add_item("Roof Builder",  MODE_ROOF_BUILDER)
	_mode_selector.selected = 0
	_mode_selector.connect("item_selected", self, "_on_mode_selected")
	root.add_child(_mode_selector)

	root.add_child(_separator())

	# ---- Mode sections ----
	_pf_section = _build_pattern_fill_section()
	root.add_child(_pf_section)

	_wb_section = _build_wall_builder_section()
	root.add_child(_wb_section)

	_pb_section = _build_path_builder_section()
	root.add_child(_pb_section)

	_rb_section = _build_room_builder_section()
	root.add_child(_rb_section)

	_rf_section = _build_roof_builder_section()
	root.add_child(_rf_section)

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

func _build_path_builder_section() -> VBoxContainer:
	return _pb_path_panel.build()

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

	# ---- Outline mode selector ----
	var outline_label = Label.new()
	outline_label.text = "Outline:"
	sec.add_child(outline_label)

	_rb_outline_mode_selector = OptionButton.new()
	_rb_outline_mode_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rb_outline_mode_selector.add_item("Wall", 0)
	_rb_outline_mode_selector.add_item("Path", 1)
	_rb_outline_mode_selector.selected = 0
	_rb_outline_mode_selector.connect("item_selected", self, "_on_rb_outline_mode")
	sec.add_child(_rb_outline_mode_selector)

	sec.add_child(_spacer(4))

	# ---- Wall sub-panel (visible when Outline = Wall) ----
	_rb_wall_container = VBoxContainer.new()
	_rb_wall_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rb_wall_container.add_child(_rb_wall_panel.build())
	sec.add_child(_rb_wall_container)

	# ---- Path sub-panel (visible when Outline = Path) ----
	_rb_path_container = VBoxContainer.new()
	_rb_path_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rb_path_container.add_child(_rb_path_panel.build())
	_rb_path_container.visible = false
	sec.add_child(_rb_path_container)

	return sec

func _build_roof_builder_section() -> VBoxContainer:
	return _rf_roof_panel.build()

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
	_pb_path_panel.try_build_grid_menu(gl)
	_rb_pattern_panel.try_build_grid_menu(gl)
	_rb_wall_panel.try_build_grid_menu(gl)
	_rb_path_panel.try_build_grid_menu(gl)
	_rf_roof_panel.try_build_grid_menu(gl)
	# Enable path color pickers only when ColourAndModifyThings is installed
	_pb_path_panel.update_camt_color_state(gl)
	_rb_path_panel.update_camt_color_state(gl)

## Called on Disable() — tears down all grid menus.
func release_all_grid_menus() -> void:
	_pf_pattern_panel.release()
	_wb_wall_panel.release()
	_pb_path_panel.release()
	_rb_pattern_panel.release()
	_rb_wall_panel.release()
	_rb_path_panel.release()
	_rf_roof_panel.release()

# ============================================================================
# SECTION VISIBILITY
# ============================================================================

func _show_section(mode: int):
	if _pf_section: _pf_section.visible = (mode == MODE_PATTERN_FILL)
	if _wb_section: _wb_section.visible = (mode == MODE_WALL_BUILDER)
	if _pb_section: _pb_section.visible = (mode == MODE_PATH_BUILDER)
	if _rb_section: _rb_section.visible = (mode == MODE_ROOM_BUILDER)
	if _rf_section: _rf_section.visible = (mode == MODE_ROOF_BUILDER)

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
# CALLBACKS — PATH BUILDER
# ============================================================================

func _on_pb_color(color: Color):
	if _tool._path_builder:
		_tool._path_builder.active_color = color

func _on_pb_width(value: float):
	if _tool._path_builder:
		_tool._path_builder.active_width = value

func _on_pb_smoothness(value: float):
	if _tool._path_builder:
		_tool._path_builder.active_smoothness = value

func _on_pb_layer(value: int):
	if _tool._path_builder:
		_tool._path_builder.active_layer = value

func _on_pb_sorting(index: int):
	if _tool._path_builder:
		_tool._path_builder.active_sorting = index

func _on_pb_fade_in(pressed: bool):
	if _tool._path_builder:
		_tool._path_builder.active_fade_in = pressed

func _on_pb_fade_out(pressed: bool):
	if _tool._path_builder:
		_tool._path_builder.active_fade_out = pressed

func _on_pb_grow(pressed: bool):
	if _tool._path_builder:
		_tool._path_builder.active_grow = pressed

func _on_pb_shrink(pressed: bool):
	if _tool._path_builder:
		_tool._path_builder.active_shrink = pressed

func _on_pb_block_light(pressed: bool):
	if _tool._path_builder:
		_tool._path_builder.active_block_light = pressed

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
		_tool._room_builder.active_sub_mode = index

func _on_rb_outline_mode(index: int):
	if _tool._room_builder:
		_tool._room_builder.active_outline_mode = index
	if _rb_wall_container:
		_rb_wall_container.visible = (index == 0)
	if _rb_path_container:
		_rb_path_container.visible = (index == 1)

# ============================================================================
# CALLBACKS — ROOM BUILDER (PATH)
# ============================================================================

func _on_rb_path_color(color: Color):
	if _tool._room_builder:
		_tool._room_builder.active_path_color = color

func _on_rb_path_width(value: float):
	if _tool._room_builder:
		_tool._room_builder.active_path_width = value

func _on_rb_path_smoothness(value: float):
	if _tool._room_builder:
		_tool._room_builder.active_path_smoothness = value

func _on_rb_path_layer(value: int):
	if _tool._room_builder:
		_tool._room_builder.active_path_layer = value

func _on_rb_path_sorting(index: int):
	if _tool._room_builder:
		_tool._room_builder.active_path_sorting = index

func _on_rb_path_fade_in(pressed: bool):
	if _tool._room_builder:
		_tool._room_builder.active_path_fade_in = pressed

func _on_rb_path_fade_out(pressed: bool):
	if _tool._room_builder:
		_tool._room_builder.active_path_fade_out = pressed

func _on_rb_path_grow(pressed: bool):
	if _tool._room_builder:
		_tool._room_builder.active_path_grow = pressed

func _on_rb_path_shrink(pressed: bool):
	if _tool._room_builder:
		_tool._room_builder.active_path_shrink = pressed

func _on_rb_path_block_light(pressed: bool):
	if _tool._room_builder:
		_tool._room_builder.active_path_block_light = pressed

# ============================================================================
# CALLBACKS — ROOF BUILDER
# ============================================================================

func _on_rf_texture(texture):
	if _tool._roof_builder:
		_tool._roof_builder.active_texture = texture

func _on_rf_width(value: float):
	if _tool._roof_builder:
		_tool._roof_builder.active_width = value

func _on_rf_type(index: int):
	if _tool._roof_builder:
		_tool._roof_builder.active_type = index

func _on_rf_sorting(index: int):
	if _tool._roof_builder:
		_tool._roof_builder.active_sorting = index

func _on_rf_placement_mode(index: int):
	if _tool._roof_builder:
		_tool._roof_builder.active_placement_mode = index

func _on_rf_shade(pressed: bool):
	if _tool._roof_builder:
		_tool._roof_builder.active_shade = pressed

func _on_rf_sun_direction(value: float):
	if _tool._roof_builder:
		_tool._roof_builder.active_sun_direction = value

func _on_rf_shade_contrast(value: float):
	if _tool._roof_builder:
		_tool._roof_builder.active_shade_contrast = value

# ============================================================================
# HELPERS
# ============================================================================

func _spacer(height: int) -> Control:
	var s = Control.new()
	s.rect_min_size = Vector2(0, height)
	return s

func _separator() -> HSeparator:
	return HSeparator.new()
