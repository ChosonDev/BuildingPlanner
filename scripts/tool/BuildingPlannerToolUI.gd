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
#     Sub-mode (Single/Merge/Conforming/Wrapping/Difference), wheel overrides/reset
#     PatternPanel  (pattern grid, color, rotation, layer, outline)
#     Outline (Wall/Path), WallPanel or PathPanel
#   ── section: Roof Builder ──────────────────────────────────────
#     RoofPanel  (roof style grid, width, type, sorting, shade)

const CLASS_NAME = "BuildingPlannerToolUI"
const BuildingPlannerUtils = preload("../utils/BuildingPlannerUtils.gd")

const Mode = preload("BuildingPlannerTool.gd").Mode

# ============================================================================
# SEARCHABLE GRID
# Reusable component: ItemList with a search field and a clear button.
#
# Usage:
#   var sg = SearchableGrid.new()
#   var node = sg.build()        # returns VBoxContainer to insert into UI
#   sg.on_item_selected = funcref(self, "_on_item_selected")
#
#   # After the source GridMenu is ready:
#   var items = []
#   for i in range(source.get_item_count()):
#       items.append({ "icon": source.get_item_icon(i),
#                      "tooltip": source.get_item_tooltip(i),
#                      "modulate": source.get_item_icon_modulate(i) })
#   sg.populate(items)
#
#   # In the selection callback:
#   func _on_item_selected(original_index: int): ...
#
#   # On teardown:
#   sg.clear()
# ============================================================================

class SearchableGrid:

	# ---- UI nodes ----
	var _container      = null   # VBoxContainer returned by build()
	var _search_edit    = null   # LineEdit
	var _grid_menu      = null   # ItemList
	var _scroll         = null   # ScrollContainer

	# ---- data ----
	var _all_items:     Array = []   # Array of { icon, tooltip, modulate }
	var _search_texts: Array = []
	var _filtered_map:  Array = []   # filtered_idx → original_idx
	var _selected_original: int = 0  # persists across populate/filter cycles

	# ---- public callback ----
	# Assign a FuncRef: func(original_index: int)
	var on_item_selected = null

	## Build and return a VBoxContainer containing the search bar + ItemList.
	## Call once; insert the returned node into your panel's layout.
	func build() -> VBoxContainer:
		_container = VBoxContainer.new()
		_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# ---- Search bar ----
		var hbox = HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		_search_edit = LineEdit.new()
		_search_edit.placeholder_text = "Search…"
		_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_search_edit.connect("text_changed",  self, "_on_search_changed")
		_search_edit.connect("focus_entered", self, "_on_focus_entered")
		_search_edit.connect("focus_exited",  self, "_on_focus_exited")
		hbox.add_child(_search_edit)

		var clear_btn = Button.new()
		clear_btn.text = "✕"
		clear_btn.hint_tooltip = "Clear search"
		clear_btn.flat = true
		clear_btn.connect("pressed", self, "_on_clear_pressed")
		hbox.add_child(clear_btn)

		_container.add_child(hbox)

		# ---- ItemList inside a ScrollContainer ----
		_scroll = ScrollContainer.new()
		_scroll.rect_min_size = Vector2(0, 160)
		_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		_grid_menu = ItemList.new()
		_grid_menu.icon_mode    = ItemList.ICON_MODE_TOP
		_grid_menu.fixed_icon_size    = Vector2(48, 48)
		_grid_menu.fixed_column_width = 56
		_grid_menu.max_columns        = 0
		_grid_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid_menu.size_flags_vertical   = Control.SIZE_EXPAND_FILL
		_grid_menu.connect("item_selected", self, "_on_grid_item_selected")

		_scroll.add_child(_grid_menu)
		_container.add_child(_scroll)

		return _container

	## Populate the ItemList from an array of dicts.
	## Each dict must have: "icon" (Texture|null), "tooltip" (String).
	## Optional key: "modulate" (Color).
	## Resets search text and rebuilds the visible list.
	func populate(items: Array, selected_index: int = 0) -> void:
		_all_items = items
		_search_texts = []
		for item in items:
			_search_texts.append(item.get("tooltip", "").to_lower().replace("-", " ").replace("_", " "))
		if _search_edit:
			_search_edit.set_block_signals(true)
			_search_edit.text = ""
			_search_edit.set_block_signals(false)
		_selected_original = selected_index if selected_index >= 0 and selected_index < items.size() else 0
		_rebuild_list("")
		if not _filtered_map.empty():
			_on_grid_item_selected(_filtered_map.find(_selected_original))

	## Remove all items and reset state. Call on panel teardown.
	func clear() -> void:
		release_search_focus()
		_all_items = []
		_search_texts.clear()
		_filtered_map.clear()
		_selected_original = 0
		if _search_edit:
			_search_edit.text = ""
		if _grid_menu:
			_grid_menu.clear()

	# ---- private ----

	## Match normalized catalog text against words split once per search.
	func _matches(text: String, words: PoolStringArray) -> bool:
		for word in words:
			if text.find(word) == -1:
				return false
		return true

	## Rebuild _grid_menu and _filtered_map for the given search text.
	func _rebuild_list(raw_query: String) -> void:
		if not _grid_menu:
			return
		var words = raw_query.strip_edges().to_lower().split(" ", false)
		var selected_visible = -1
		_grid_menu.clear()
		_filtered_map.clear()

		for orig_idx in range(_all_items.size()):
			var item = _all_items[orig_idx]
			var tooltip: String = item.get("tooltip", "")
			if not _matches(_search_texts[orig_idx], words):
				continue

			var icon = item.get("icon", null)
			if icon:
				_grid_menu.add_item("", icon)
			else:
				_grid_menu.add_item(tooltip)

			var fi = _grid_menu.get_item_count() - 1
			_grid_menu.set_item_tooltip(fi, tooltip)
			var mod_color = item.get("modulate", Color.white)
			_grid_menu.set_item_icon_modulate(fi, mod_color)

			_filtered_map.append(orig_idx)
			if orig_idx == _selected_original:
				selected_visible = fi

		# Restore selection
		if selected_visible >= 0:
			_grid_menu.select(selected_visible)
		elif _grid_menu.get_item_count() > 0:
			_grid_menu.select(0)
			_on_grid_item_selected(0)

	func _on_search_changed(text: String) -> void:
		_rebuild_list(text)

	func _on_clear_pressed() -> void:
		if _search_edit:
			_search_edit.text = ""
		_rebuild_list("")

	func _on_grid_item_selected(filtered_index: int) -> void:
		if filtered_index < 0 or filtered_index >= _filtered_map.size():
			return
		_selected_original = _filtered_map[filtered_index]
		if on_item_selected:
			on_item_selected.call_func(_selected_original)

	func release_search_focus() -> void:
		if is_instance_valid(_search_edit) and _search_edit.has_focus():
			_search_edit.release_focus()

	func _on_focus_entered() -> void:
		if Engine.has_singleton("Global"):
			Engine.get_singleton("Global").Editor.SearchHasFocus = true

	func _on_focus_exited() -> void:
		if Engine.has_singleton("Global"):
			Engine.get_singleton("Global").Editor.SearchHasFocus = false

# ============================================================================
# PATTERN PANEL
# Reusable panel: pattern texture grid + color / rotation / layer / outline.
# ============================================================================

# Shared panel controls and immutable per-map asset snapshots.
class FeaturePanel:
	const TOOL_NAMES = {"Patterns": "PatternShapeTool", "Walls": "WallTool", "Paths": "PathTool", "Roofs": "RoofTool"}
	var LOGGER = null
	var feature = null
	var _settings = {} # Retain edits made before late API registration.
	var _keep_color_on_populate = false

	func bind_feature(value) -> void:
		_keep_color_on_populate = feature == null and _settings.has("color")
		feature = value
		if feature:
			for setting in _settings:
				feature.set("active_" + setting, _settings[setting])
	var _asset_script = null
	var _catalogs = {}
	var layer_option = null
	var color_picker = null
	var _index_to_path = []
	var _sg = null
	var _populated = false
	var _selection_path = null
	var _restoring = false

	# Catalogs are shared read-only by panels and cleared by UI on map change/unload.
	# Do not cache an empty/late host catalog: the next activation must retry it.
	func _get_catalog(gl, category: String, allow_empty = false) -> Dictionary:
		var key = category + ("Empty" if allow_empty else "")
		if _catalogs.has(key):
			return _catalogs[key]
		if allow_empty:
			var full = _get_catalog(gl, category)
			if full.empty():
				return {}
			var items = [{"icon": full.empty_icon, "tooltip": "No fill", "modulate": Color.white}] + full.items
			var paths = [""] + full.paths
			_catalogs[key] = {"items": items, "paths": paths}
			return _catalogs[key]
		var tool_name = TOOL_NAMES[category]
		if not gl or not gl.Editor or not gl.Editor.Tools.has(tool_name):
			return {}
		var host_tool = gl.Editor.Tools[tool_name]
		var source = host_tool.get("textureMenu") if category == "Patterns" else null
		if category != "Patterns":
			var controls = host_tool.get("Controls")
			if controls:
				source = controls.get("Texture")
		if not is_instance_valid(source):
			return {}
		var owned = null
		if category == "Paths":
			# PathTool's visible menu may be filtered by its library/search panel.
			owned = source.get_script().new()
			owned.Load(category)
			source = owned
		var lookup = source.get("Lookup")
		var items = []
		var paths = []
		var empty_icon = null
		if source.get_item_count() > 0 and lookup and not lookup.empty():
			var inverse = {}
			for path in lookup:
				inverse[lookup[path]] = path
			if category == "Patterns":
				empty_icon = source.get_item_icon(lookup.get("", 0))
			for i in range(source.get_item_count()):
				var path: String = inverse.get(i, "")
				if path == "":
					continue
				var icon = source.get_item_icon(i)
				var color = Color.white
				if icon and category == "Patterns" and host_tool.has_method("GetDefaultColor"):
					color = host_tool.GetDefaultColor(icon)
				elif icon and category == "Walls" and host_tool.has_method("GetWallColor"):
					color = host_tool.GetWallColor(icon)
				paths.append(path)
				items.append({"icon": icon, "tooltip": path.get_file().get_basename(), "modulate": color})
		if owned:
			owned.free()
		if items.empty():
			return {}
		_catalogs[key] = {"items": items, "paths": paths, "empty_icon": empty_icon}
		return _catalogs[key]

	func _populate_catalog(gl, category: String, allow_empty = false) -> void:
		var data = _get_catalog(gl, category, allow_empty)
		if data.empty():
			return
		_index_to_path = data.paths
		var selected = _index_to_path.find(_selection_path)
		_restoring = selected >= 0 or _keep_color_on_populate
		_keep_color_on_populate = false
		_sg.populate(data.items, selected)
		_restoring = false
		_populated = true

	func release() -> void:
		_set_field("texture", null)
		if _sg:
			_sg.release_search_focus()
		if not _populated:
			return
		_selection_path = _index_to_path[_sg._selected_original] if _sg._selected_original >= 0 and _sg._selected_original < _index_to_path.size() else null
		_sg.clear()
		_populated = false
		_index_to_path = []

	func _add_layer_option(parent):
		parent.add_child(_label("Layer:"))
		layer_option = OptionButton.new()
		layer_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		layer_option.connect("item_selected", self, "_on_layer_changed")
		parent.add_child(layer_option)

	func _add_option(parent, text: String, items: Array, setting: String):
		parent.add_child(_label(text))
		var control = OptionButton.new()
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for item in items:
			control.add_item(item)
		control.connect("item_selected", self, "_set_field_from_signal", [setting])
		parent.add_child(control)
		return control

	func _apply_default_color(original_index: int):
		if not _restoring:
			var color: Color = _sg._all_items[original_index].modulate
			if color_picker: color_picker.color = color
			_set_field("color", color)

	func _add_check(parent, text: String, setting: String, pressed = false):
		var control = CheckButton.new()
		control.text = text
		control.pressed = pressed
		control.connect("toggled", self, "_set_field_from_signal", [setting])
		parent.add_child(control)
		return control

	func _add_range(parent, text: String, setting: String, minimum, maximum, step, value, slider = false):
		parent.add_child(_label(text))
		var control = HSlider.new() if slider else SpinBox.new()
		control.min_value = minimum
		control.max_value = maximum
		control.step = step
		control.value = value
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.connect("value_changed", self, "_set_field_from_signal", [setting])
		parent.add_child(control)
		return control

	func _add_color_picker(parent):
		parent.add_child(_label("Color:"))
		var control = ColorPickerButton.new()
		control.color = Color.white
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.connect("color_changed", self, "_set_field_from_signal", ["color"])
		parent.add_child(control)
		return control

	func _add_grid(parent):
		_sg = SearchableGrid.new()
		parent.add_child(_sg.build())
		_sg.on_item_selected = funcref(self, "_on_texture_selected")

	func _set_field_from_signal(value, setting: String) -> void:
		_set_field(setting, value)

	func _set_field(setting: String, value) -> void:
		_settings[setting] = value
		if feature:
			feature.set("active_" + setting, value)

	func _asset_texture(category: String, index: int):
		var path: String = _index_to_path[index] if index >= 0 and index < _index_to_path.size() else ""
		if path == "":
			return null
		if not _asset_script or not _asset_script.has_method("GetAssetTexture"):
			if LOGGER: LOGGER.error("BuildingPlanner: asset loader unavailable for %s: %s" % [category, path])
			return null
		var texture = _asset_script.GetAssetTexture(category, path)
		if not texture is Texture:
			if LOGGER: LOGGER.error("BuildingPlanner: could not load %s texture: %s" % [category, path])
			return null
		return texture

	func _on_layer_changed(index: int):
		if layer_option and index >= 0:
			_set_field("layer", layer_option.get_item_id(index))

	static func _label(text: String) -> Label:
		var lbl = Label.new()
		lbl.text = text
		return lbl

	static func _spacer(height: int) -> Control:
		var s = Control.new()
		s.rect_min_size = Vector2(0, height)
		return s

	## Rebuild layers and retain this panel's current feature/early UI selection.
	## Call on panel show, on mode switch, and on layers_changed signal.
	func refresh_layer_option(user_layers: Dictionary, keys: Array) -> void:
		if not layer_option:
			return
		if keys.empty():
			if LOGGER: LOGGER.error("BuildingPlanner: layer list is empty; keeping current selection.")
			return
		var current_z_index = feature.active_layer if feature else _settings.get("layer", BuildingPlannerUtils.DEFAULT_LAYER)
		layer_option.clear()
		for z in keys:
			layer_option.add_item(str(z) + ": " + user_layers[z])
			layer_option.set_item_id(layer_option.get_item_count() - 1, z)
		var target: int = current_z_index if user_layers.has(current_z_index) else BuildingPlannerUtils.DEFAULT_LAYER
		if not user_layers.has(target):
			target = keys[0]
		_select_layer_option(target)
		_on_layer_changed(layer_option.selected)

	## Select the OptionButton item whose id matches [z_index].
	func _select_layer_option(z_index: int) -> void:
		if not layer_option:
			return
		for i in range(layer_option.get_item_count()):
			if layer_option.get_item_id(i) == z_index:
				layer_option.select(i)
				return

class PatternPanel:
	extends FeaturePanel

	# ---- UI nodes ----
	var allow_empty = false

	var rotation_spin = null   # SpinBox
	var outline_check = null   # CheckButton

	## Build and return a VBoxContainer with all controls.
	## The pattern grid is built immediately via SearchableGrid; items are
	## populated lazily in try_build_grid_menu().
	func build() -> VBoxContainer:
		var sec = VBoxContainer.new()
		sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		sec.add_child(_label("Pattern:"))

		_add_grid(sec)

		sec.add_child(_spacer(6))

		color_picker = _add_color_picker(sec)

		rotation_spin = _add_range(sec, "Rotation (deg):", "rotation", 0, 360, 1, 0)

		_add_layer_option(sec)

		outline_check = _add_check(sec, "Outline", "outline", false)

		return sec

	## Lazily populate the pattern grid from PatternShapeTool.textureMenu.
	## Safe to call multiple times — exits early if already built.
	## Pass Global via tool.parent_mod.Global.
	func try_build_grid_menu(gl) -> void:
		if not _populated and _sg:
			_populate_catalog(gl, "Patterns", allow_empty)

	# ---- internal callbacks ----

	func _load_texture_safe(path: String) -> Texture:
		if path == "":
			return null
		if ResourceLoader.has_cached(path) or ResourceLoader.exists(path, "Texture"):
			var texture = ResourceLoader.load(path, "Texture", false) as Texture
			if not texture and LOGGER: LOGGER.error("BuildingPlanner: could not load pattern texture: %s" % path)
			return texture
		
		# Fallback for custom packs (raw .png without .import)
		var img = Image.new()
		var err = img.load(path)
		if err == OK:
			var tex = ImageTexture.new()
			tex.create_from_image(img, 6) # Host RepeatFlags: repeat + filter, no mipmaps.
			tex.take_over_path(path)
			return tex
			
		if LOGGER: LOGGER.error("BuildingPlanner: could not load pattern texture: %s (error %d)" % [path, err])
		return null

	func _on_texture_selected(original_index: int):
		if original_index < 0 or original_index >= _index_to_path.size():
			return
		var path: String = _index_to_path[original_index]
		if path == "":
			_set_field("texture", null)
			return
		var tex = _load_texture_safe(path)
		_set_field("texture", tex)
		if not tex:
			return
		_apply_default_color(original_index)

# ============================================================================
# WALL PANEL
# Reusable panel: wall texture grid + shadow / bevel.
# ============================================================================

class WallPanel:
	extends FeaturePanel

	# ---- UI nodes ----

	var shadow_check = null   # CheckButton
	var bevel_check  = null   # CheckButton

	func _init(asset_script = null):
		_asset_script = asset_script

	## Build and return a VBoxContainer with all controls.
	func build() -> VBoxContainer:
		var sec = VBoxContainer.new()
		sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		sec.add_child(_label("Wall:"))

		_add_grid(sec)

		sec.add_child(_spacer(6))

		color_picker = _add_color_picker(sec)

		sec.add_child(_spacer(4))

		shadow_check = _add_check(sec, "Shadow", "shadow", true)

		bevel_check = CheckButton.new()
		bevel_check.text = "Bevel corners"
		bevel_check.pressed = true
		bevel_check.connect("toggled", self, "_on_bevel_toggled")
		sec.add_child(bevel_check)

		return sec

	## Lazily populate the wall grid from WallTool.Controls["Texture"].
	## Safe to call multiple times — exits early if already built.
	func try_build_grid_menu(gl) -> void:
		if not _populated and _sg:
			_populate_catalog(gl, "Walls")

	# ---- internal callbacks ----

	func _on_texture_selected(original_index: int):
		var tex = _asset_texture("Walls", original_index)
		_set_field("texture", tex)
		if not tex:
			return
		_apply_default_color(original_index)

	func _on_bevel_toggled(pressed: bool):
		_set_field("joint", 1 if pressed else 0)

# ============================================================================
# PATH PANEL
# Reusable panel: path texture grid + width / smoothness / effects.
# ============================================================================

class PathPanel:
	extends FeaturePanel
	var _camt_present = null

	# ---- UI nodes ----

	var width_spin        = null   # SpinBox
	var smoothness_slider = null   # HSlider
	var sorting_option    = null   # OptionButton

	# Effects
	var fade_in_check     = null   # CheckButton
	var fade_out_check    = null   # CheckButton
	var grow_check        = null   # CheckButton
	var shrink_check      = null   # CheckButton
	var block_light_check = null   # CheckButton

	func _init(asset_script = null):
		_asset_script = asset_script

	## Build and return a VBoxContainer with all controls.
	func build() -> VBoxContainer:
		var sec = VBoxContainer.new()
		sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		sec.add_child(_label("Path:"))

		_add_grid(sec)

		sec.add_child(_spacer(6))

		color_picker = _add_color_picker(sec)

		width_spin = _add_range(sec, "Width:", "width", 0.1, 10.0, 0.1, 1.0)

		smoothness_slider = _add_range(sec, "Smoothness:", "smoothness", 0.0, 1.0, 0.01, 0.0, true)

		_add_layer_option(sec)

		sorting_option = _add_option(sec, "Sorting:", ["Over", "Under"], "sorting")

		sec.add_child(_spacer(4))

		fade_in_check = _add_check(sec, "Fade In", "fade_in", false)

		fade_out_check = _add_check(sec, "Fade Out", "fade_out", false)

		grow_check = _add_check(sec, "Grow (Taper Start)", "grow", false)

		shrink_check = _add_check(sec, "Shrink (Taper End)", "shrink", false)

		block_light_check = _add_check(sec, "Block Light", "block_light", false)

		return sec

	## Lazily populate the path grid from PathTool.Controls["Texture"].
	## Safe to call multiple times — exits early if already built.
	func try_build_grid_menu(gl) -> void:
		if not _populated and _sg:
			_populate_catalog(gl, "Paths")

	## Enables or disables the color picker based on CAMT presence.
	## ColourAndModifyThings is detected via the "UchideshiNodeData" key it
	## creates in ModMapData. Without CAMT the color cannot persist past a
	## map reload, so the picker is disabled and reset to white.
	## Called on activation and during active updates for late CAMT readiness.
	func update_camt_color_state(gl) -> void:
		if not color_picker:
			return
		var camt_present: bool = gl.ModMapData.has("UchideshiNodeData")
		if _camt_present == camt_present:
			return
		_camt_present = camt_present
		color_picker.disabled = not camt_present
		if camt_present:
			color_picker.hint_tooltip = ""
		else:
			color_picker.color = Color.white
			color_picker.hint_tooltip = "Requires ColourAndModifyThings mod (color won't persist without it)"
			_set_field("color", Color.white)

	# ---- internal callbacks ----

	func _on_texture_selected(original_index: int):
		var tex = _asset_texture("Paths", original_index)
		_set_field("texture", tex)

# ============================================================================
# ROOF PANEL
# Panel: roof texture grid (from RoofTool) + width / type / sorting / shade.
# ============================================================================

class RoofPanel:
	extends FeaturePanel


	# ---- UI nodes ----
	var _defaults_world = null
	var _lighting_level = null
	var _lighting_values = []

	var width_spin            = null   # SpinBox
	var type_option           = null   # OptionButton  (Gable/Hip/Dormer)
	var sorting_option        = null   # OptionButton  (Over/Under)
	var placement_mode_option = null   # OptionButton  (Ridge/Expand/Inset)
	var shade_check           = null   # CheckButton
	var _shade_sub            = null   # VBoxContainer — visible only when shade = true
	var sun_dir_slider        = null   # HSlider
	var contrast_slider       = null   # HSlider

	func _init(logger, asset_script = null):
		LOGGER = logger
		_asset_script = asset_script

	## Build and return a VBoxContainer with all controls.
	## The style grid is populated when the host catalog becomes available.
	func build() -> VBoxContainer:
		var sec = VBoxContainer.new()
		sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# ---- Texture ----
		sec.add_child(_label("Roof Style:"))

		_add_grid(sec)

		sec.add_child(_spacer(6))

		# ---- Width ----
		width_spin = _add_range(sec, "Width (px):", "width", 1.0, 8192.0, 1.0, 50.0)
		width_spin.allow_greater = true

		# ---- Type ----
		type_option = _add_option(sec, "Type:", ["Gable", "Hip", "Dormer"], "type")

		# ---- Sorting ----
		sorting_option = _add_option(sec, "Sorting:", ["Over", "Under"], "sorting")

		sec.add_child(_spacer(4))

		# ---- Placement mode ----
		placement_mode_option = _add_option(sec, "Placement Mode:", ["Ridge along area", "Expand (eave at area, roof outside)", "Inset (eave at area, roof inside)"], "placement_mode")
		placement_mode_option.hint_tooltip = "Ridge: polygon edge is the ridge line, eave expands outward.\nExpand: polygon is the eave edge, ridge is outside the area.\nInset: polygon is the eave edge, ridge is inside the area."

		sec.add_child(_spacer(4))

		# ---- Shade ----
		shade_check = CheckButton.new()
		shade_check.text = "Sunlight Shading (all roofs)"
		shade_check.hint_tooltip = "Applied to all roofs on this level when placing a roof."
		shade_check.connect("toggled", self, "_on_shade_toggled")
		sec.add_child(shade_check)

		_shade_sub = VBoxContainer.new()
		_shade_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_shade_sub.visible = false

		sun_dir_slider = _add_range(_shade_sub, "Sun Direction (deg):", "sun_direction", 0.0, 360.0, 1.0, 0.0, true)

		contrast_slider = _add_range(_shade_sub, "Shade Contrast:", "shade_contrast", 0.0, 1.0, 0.01, 0.5, true)

		sec.add_child(_shade_sub)

		return sec

	## Lazily populate the texture grid from RoofTool.Controls["Texture"].
	## Initializes width/type/sorting defaults per map from RoofTool state.
	## Safe to call multiple times.
	func try_build_grid_menu(gl) -> void:
		if _sg == null:
			return

		if not gl.Editor or not gl.Editor.Tools.has("RoofTool"):
			if LOGGER: LOGGER.warn("RoofPanel: RoofTool not in Tools[].")
			return

		var rt = gl.Editor.Tools["RoofTool"]

		# Initialize style defaults per map; tool switches keep the user's settings.
		if gl.World and gl.World.Level and _defaults_world != gl.World:
			var rt_width = rt.get("Width")
			if rt_width and width_spin:
				width_spin.value = rt_width.value * gl.World.TileSize
				_set_field("width", width_spin.value)
			if rt.get("Sorting") != null:
				sorting_option.selected = rt.get("Sorting")
				_set_field("sorting", sorting_option.selected)
			if rt.get("Type") != null:
				type_option.selected = rt.get("Type")
				_set_field("type", type_option.selected)
			_defaults_world = gl.World
		sync_level_settings(gl)

		# Guard: don't rebuild grid if already populated.
		if _populated:
			return

		_populate_catalog(gl, "Roofs")

	## Lighting belongs to the current level; never carry another level's values into it.
	func sync_level_settings(gl) -> void:
		if not gl.World or not gl.World.Level or not shade_check:
			_lighting_level = null
			return
		var level = gl.World.Level
		var roofs = BuildingPlannerUtils.get_roofs(level)
		if not roofs:
			return
		if _lighting_level == level and _lighting_values.size() == 3 and _lighting_values[0] == roofs.Shade and _lighting_values[1] == roofs.SunDirection and _lighting_values[2] == roofs.ShadeContrast:
			return # Preserve draft edits until the native level lighting changes.
		_lighting_level = level
		_lighting_values = [roofs.Shade, roofs.SunDirection, roofs.ShadeContrast]
		shade_check.pressed = roofs.Shade
		_on_shade_toggled(roofs.Shade)
		sun_dir_slider.value = roofs.SunDirection
		_set_field("sun_direction", sun_dir_slider.value)
		contrast_slider.value = roofs.ShadeContrast
		_set_field("shade_contrast", contrast_slider.value)

	# ---- internal callbacks ----

	func _on_texture_selected(original_index: int):
		var tex = _asset_texture("Roofs", original_index)
		_set_field("texture", tex)

	func _on_shade_toggled(pressed: bool):
		if _shade_sub:
			_shade_sub.visible = pressed
		_set_field("shade", pressed)

# ============================================================================
# REFERENCES
# ============================================================================

var _tool  = null
var LOGGER = null
var _layer_signaling = null
var _catalogs = {}
var _all_panels = []
var _rb_override_label = null

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
	_pf_pattern_panel = PatternPanel.new()
	_wb_wall_panel    = WallPanel.new( _tool.parent_mod.get("Script"))
	_pb_path_panel    = PathPanel.new( _tool.parent_mod.get("Script"))
	_rb_pattern_panel = PatternPanel.new()
	_rb_pattern_panel.allow_empty = true
	_rb_wall_panel    = WallPanel.new( _tool.parent_mod.get("Script"))
	_rb_path_panel    = PathPanel.new( _tool.parent_mod.get("Script"))
	_rf_roof_panel    = RoofPanel.new(LOGGER, _tool.parent_mod.get("Script"))

	bind_features()
	_all_panels = [_pf_pattern_panel, _wb_wall_panel, _pb_path_panel, _rb_pattern_panel, _rb_wall_panel, _rb_path_panel, _rf_roof_panel]
	for section in _all_panels:
		section._catalogs = _catalogs
		section.LOGGER = LOGGER

	var root = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ---- Title ----
	var title = Label.new()
	title.text = "Building Planner"
	title.align = Label.ALIGN_CENTER
	root.add_child(title)

	root.add_child(FeaturePanel._spacer(6))

	# ---- Mode selector ----
	var mode_label = Label.new()
	mode_label.text = "Mode:"
	root.add_child(mode_label)

	_mode_selector = OptionButton.new()
	_mode_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_selector.add_item("Pattern Fill",  Mode.PATTERN_FILL)
	_mode_selector.add_item("Wall Builder",  Mode.WALL_BUILDER)
	_mode_selector.add_item("Path Builder",  Mode.PATH_BUILDER)
	_mode_selector.add_item("Room Builder",  Mode.ROOM_BUILDER)
	_mode_selector.add_item("Roof Builder",  Mode.ROOF_BUILDER)
	_mode_selector.selected = 0
	_mode_selector.connect("item_selected", self, "_on_mode_selected")
	root.add_child(_mode_selector)

	root.add_child(HSeparator.new())

	# ---- Mode sections ----
	_pf_section = _pf_pattern_panel.build()
	root.add_child(_pf_section)

	_wb_section = _wb_wall_panel.build()
	root.add_child(_wb_section)

	_pb_section = _pb_path_panel.build()
	root.add_child(_pb_section)

	_rb_section = _build_room_builder_section()
	root.add_child(_rb_section)

	_rf_section = _rf_roof_panel.build()
	root.add_child(_rf_section)

	# Show only the first mode's section
	_show_section(Mode.PATTERN_FILL)

	# Attach to panel
	var attach_target = panel.get_node_or_null("Align")
	if attach_target:
		attach_target.add_child(root)
	else:
		panel.add_child(root)

	# Sync tool state
	_tool._set_mode(Mode.PATTERN_FILL)

## Also called after late GuidesLines registration creates the feature instances.
func bind_features() -> void:
	_pf_pattern_panel.bind_feature(_tool._pattern_fill)
	_wb_wall_panel.bind_feature(_tool._wall_builder)
	_pb_path_panel.bind_feature(_tool._path_builder)
	_rb_pattern_panel.bind_feature(_tool._room_builder._pattern_fill if _tool._room_builder else null)
	_rb_wall_panel.bind_feature(_tool._room_builder._wall_builder if _tool._room_builder else null)
	_rb_path_panel.bind_feature(_tool._room_builder._path_builder if _tool._room_builder else null)
	_rf_roof_panel.bind_feature(_tool._roof_builder)
	if _rb_sub_mode_selector:
		_on_rb_sub_mode(_rb_sub_mode_selector.selected)
	if _rb_outline_mode_selector and _tool._room_builder:
		_tool._room_builder.active_outline_mode = _rb_outline_mode_selector.selected
	update_room_overrides()

# ============================================================================
# SECTION BUILDERS
# ============================================================================

func _build_room_builder_section() -> VBoxContainer:
	var sec = VBoxContainer.new()
	sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ---- Sub-mode selector ----
	var sub_mode_label = Label.new()
	sub_mode_label.text = "Sub-mode:"
	sec.add_child(sub_mode_label)

	_rb_sub_mode_selector = OptionButton.new()
	_rb_sub_mode_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rb_sub_mode_selector.add_item("Single",     0)
	_rb_sub_mode_selector.add_item("Merge",      1)
	_rb_sub_mode_selector.add_item("Conforming", 2)
	_rb_sub_mode_selector.add_item("Wrapping",   3)
	_rb_sub_mode_selector.add_item("Difference", 4)
	_rb_sub_mode_selector.selected = 0
	_rb_sub_mode_selector.connect("item_selected", self, "_on_rb_sub_mode")
	sec.add_child(_rb_sub_mode_selector)
	_rb_override_label = FeaturePanel._label("")
	sec.add_child(_rb_override_label)
	var reset = Button.new()
	reset.text = "Reset rotation / scale"
	reset.connect("pressed", self, "_reset_room_overrides")
	sec.add_child(reset)
	update_room_overrides()

	sec.add_child(HSeparator.new())
	sec.add_child(_rb_pattern_panel.build())

	sec.add_child(HSeparator.new())

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

	sec.add_child(FeaturePanel._spacer(4))

	# ---- Wall sub-panel (visible when Outline = Wall) ----
	_rb_wall_container = _rb_wall_panel.build()
	sec.add_child(_rb_wall_container)

	# ---- Path sub-panel (visible when Outline = Path) ----
	_rb_path_container = _rb_path_panel.build()
	_rb_path_container.visible = false
	sec.add_child(_rb_path_container)

	return sec

# ============================================================================
# GRID MENU LIFECYCLE
# ============================================================================

func get_selected_mode() -> int:
	return _mode_selector.get_item_id(_mode_selector.selected) if _mode_selector else Mode.PATTERN_FILL

func update_active_mode(mode: int, gl) -> void:
	if mode == Mode.PATH_BUILDER or mode == Mode.ROOM_BUILDER:
		_pb_path_panel.update_camt_color_state(gl)
		_rb_path_panel.update_camt_color_state(gl)
	elif mode == Mode.ROOF_BUILDER:
		sync_roof_settings(gl)

func sync_roof_settings(gl) -> void:
	_rf_roof_panel.sync_level_settings(gl)

func shutdown() -> void:
	release_all_grid_menus()
	_tool = null

## Populate only the active section; owned grids retain their data until map change.
func try_build_grid_menus(mode: int) -> void:
	if not _tool or not _tool.parent_mod:
		return
	var gl = _tool.parent_mod.Global
	match mode:
		Mode.PATTERN_FILL:
			_pf_pattern_panel.try_build_grid_menu(gl)
		Mode.WALL_BUILDER:
			_wb_wall_panel.try_build_grid_menu(gl)
		Mode.PATH_BUILDER:
			_pb_path_panel.try_build_grid_menu(gl)
			_pb_path_panel.update_camt_color_state(gl)
		Mode.ROOM_BUILDER:
			_rb_pattern_panel.try_build_grid_menu(gl)
			if _rb_outline_mode_selector.selected == 0:
				_rb_wall_panel.try_build_grid_menu(gl)
			else:
				_rb_path_panel.try_build_grid_menu(gl)
				_rb_path_panel.update_camt_color_state(gl)
		Mode.ROOF_BUILDER:
			_rf_roof_panel.try_build_grid_menu(gl)
	# Populate layer dropdowns with current map's user layers
	_refresh_all_layer_options(gl)
	# Subscribe to layers_changed so dropdowns stay in sync if ManageLayers
	# adds/renames/removes a layer while the tool is active.
	if gl.API and gl.API.has("ModSignalingApi"):
		var msa = gl.API.ModSignalingApi
		if msa.has_user_signal("layers_changed") and \
				not msa.is_connected("layers_changed", self, "_on_layers_changed"):
			msa.connect("layers_changed", self, "_on_layers_changed")
			_layer_signaling = msa

## Release only owned search edits, preserving focus in other tools.
func release_search_focus() -> void:
	for panel in _all_panels:
		if panel and panel._sg:
			panel._sg.release_search_focus()

## Called on map change or unload; tool switches retain these owned grids.
func release_all_grid_menus() -> void:
	if is_instance_valid(_layer_signaling) and _layer_signaling.is_connected("layers_changed", self, "_on_layers_changed"):
		_layer_signaling.disconnect("layers_changed", self, "_on_layers_changed")
	_layer_signaling = null
	_catalogs.clear()
	for panel in _all_panels:
		if panel:
			panel.release()

# ============================================================================
# SECTION VISIBILITY
# ============================================================================

func _show_section(mode: int):
	release_search_focus()
	if _pf_section: _pf_section.visible = (mode == Mode.PATTERN_FILL)
	if _wb_section: _wb_section.visible = (mode == Mode.WALL_BUILDER)
	if _pb_section: _pb_section.visible = (mode == Mode.PATH_BUILDER)
	if _rb_section: _rb_section.visible = (mode == Mode.ROOM_BUILDER)
	if _rf_section: _rf_section.visible = (mode == Mode.ROOF_BUILDER)
	if _tool and _tool.is_enabled:
		try_build_grid_menus(mode)
	elif _tool and _tool.parent_mod:
		_refresh_all_layer_options(_tool.parent_mod.Global)

# ============================================================================
# CALLBACKS — MODE
# ============================================================================

func _on_mode_selected(index):
	var mode = _mode_selector.get_item_id(index)
	_tool._set_mode(mode)
	_show_section(mode)

# ============================================================================
# LAYER REFRESH HELPERS
# ============================================================================

## Refreshes all four layer OptionButtons from the current map's LayerApi data.
func _refresh_all_layer_options(gl) -> void:
	if not gl:
		return
	var layers = {BuildingPlannerUtils.DEFAULT_LAYER: "User Layer 1"}
	if gl.API and gl.API.has("LayerApi") and gl.World and gl.World.Level:
		layers = gl.API.LayerApi.get_user_layers(gl.World.Level)
	var keys = layers.keys()
	keys.sort()
	for panel in [_pf_pattern_panel, _pb_path_panel, _rb_pattern_panel, _rb_path_panel]:
		panel.refresh_layer_option(layers, keys)

## Signal handler: fired by ManageLayers / LayerApi when layers change.
func _on_layers_changed() -> void:
	if _tool and _tool.parent_mod:
		_refresh_all_layer_options(_tool.parent_mod.Global)

# ============================================================================
# CALLBACKS — ROOM BUILDER
# ============================================================================

func _on_rb_sub_mode(index: int):
	if _tool._room_builder:
		_tool._room_builder.active_sub_mode = index

func _on_rb_outline_mode(index: int):
	release_search_focus()
	if _tool._room_builder:
		_tool._room_builder.active_outline_mode = index
	if _rb_wall_container:
		_rb_wall_container.visible = (index == 0)
	if _rb_path_container:
		_rb_path_container.visible = (index == 1)
	if _tool.is_enabled:
		try_build_grid_menus(Mode.ROOM_BUILDER)

func update_room_overrides() -> void:
	if _rb_override_label:
		var room = _tool._room_builder
		_rb_override_label.text = "Rotation offset: %.1f deg | Scale: %.2fx" % [room.shape_angle_offset if room else 0.0, room.shape_scale_factor if room else 1.0]

func _reset_room_overrides() -> void:
	if _tool._room_builder:
		_tool._room_builder.shape_angle_offset = 0.0
		_tool._room_builder.shape_scale_factor = 1.0
	update_room_overrides()
