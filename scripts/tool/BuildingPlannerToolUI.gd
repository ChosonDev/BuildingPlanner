extends Reference

# BuildingPlanner - Dungeondraft Mod
# Sidebar UI panel and docked right-side resource panel for the BuildingPlanner tool.
#
# Layout
#   Left Sidebar (ToolPanel):
#     Title ("Building Planner")
#     Mode card (Floor Fill / Wall Builder / Path Builder / Room Builder / Roof Builder / Water Fill)
#     Active mode settings card(s) (color, rotation, layer, offsets, effects, room setup, water)
#   Right Floating/Docked Panel (inside Editor Content):
#     Active mode resource grid(s) with search bar & eyedropper Pick button
#     (Pattern / Smart Tiles / Wall / Path / Room Floor + Outline / Roof; hidden in Water Fill)

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
	var _editor         = null   # Host Editor supplied by the owning mod.

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
	func build(expand_vertical: bool = false) -> VBoxContainer:
		_container = VBoxContainer.new()
		_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if expand_vertical:
			_container.size_flags_vertical = Control.SIZE_EXPAND_FILL

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
		_scroll.rect_min_size = Vector2(0, 120 if expand_vertical else 160)
		_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if expand_vertical:
			_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

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
		if is_instance_valid(_editor):
			_editor.SearchHasFocus = true

	func _on_focus_exited() -> void:
		if is_instance_valid(_editor):
			_editor.SearchHasFocus = false

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
	var _controls = {}
	var sample_button = null
	var sample_category = ""

	func apply_sample(settings: Dictionary) -> void:
		var texture = settings.texture
		var path = texture.resource_path if texture is Texture else ""
		var index = _index_to_path.find(path)
		if index < 0 and texture is Texture and path != "":
			# Missing/filtered native catalog entries still have a usable map texture.
			_index_to_path = _index_to_path.duplicate()
			_index_to_path.append(path)
			_sg._all_items = _sg._all_items.duplicate()
			_sg._all_items.append({"icon": texture, "tooltip": path.get_file().get_basename()})
			_sg._search_texts.append(path.get_file().get_basename().to_lower())
			index = _index_to_path.size() - 1
		_sg._search_edit.text = ""
		_sg._selected_original = index
		_sg._rebuild_list("")
		_sg._grid_menu.ensure_current_is_visible()
		_selection_path = path
		_populated = true
		for setting in settings:
			var value = settings[setting]
			if _controls.has(setting):
				var control = _controls[setting]
				control.set_block_signals(true)
				if control is OptionButton:
					if setting == "layer":
						var found = false
						for i in range(control.get_item_count()):
							if control.get_item_id(i) == value: found = true
						if not found: control.add_item(str(value) + ": Sample layer", value)
						_select_layer_option(value)
					else: control.select(value)
				elif control is BaseButton: control.pressed = bool(value)
				elif control is Range:
					control.min_value = min(control.min_value, value)
					control.max_value = max(control.max_value, value)
					var step = control.step
					control.step = 0.0
					control.value = value
					control.step = step
					if control is SpinBox: control.get_line_edit().text = str(control.value)
					value = control.value
				control.set_block_signals(false)
			_set_field(setting, value)
		if color_picker and settings.has("color"): color_picker.color = settings.color
		if get("_shade_sub") != null: get("_shade_sub").visible = settings.get("shade", false)

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
		_controls["layer"] = layer_option
		parent.add_child(layer_option)

	func _add_option(parent, text: String, items: Array, setting: String):
		parent.add_child(_label(text))
		var control = OptionButton.new()
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for item in items:
			control.add_item(item)
		control.connect("item_selected", self, "_set_field_from_signal", [setting])
		_controls[setting] = control
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
		_controls[setting] = control
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
		_controls[setting] = control
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

	func _add_grid(parent, expand_vertical: bool = false):
		_sg = SearchableGrid.new()
		parent.add_child(_sg.build(expand_vertical))
		sample_button = Button.new()
		sample_button.text = "Pick"
		sample_button.toggle_mode = true
		sample_button.focus_mode = Control.FOCUS_NONE
		sample_button.hint_tooltip = "Pick a sample from the map. Left-click a matching object; any other key cancels."
		_sg._search_edit.get_parent().add_child(sample_button)
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

class SmartTilePanel:
	extends FeaturePanel
	var allow_empty = false
	var allow_erase = true

	func build(grid_parent = null) -> VBoxContainer:
		var sec = VBoxContainer.new()
		sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sec.add_constant_override("separation", 6)
		var note = _label("Hover previews up to 4096 cells.")
		note.autowrap = true
		if grid_parent != null:
			note.add_color_override("font_color", Color(0.75, 0.78, 0.84, 0.85))
			grid_parent.add_child(note)
			_add_grid(grid_parent, true)
		else:
			sec.add_child(_label("Smart Tiles:"))
			sec.add_child(note)
			_add_grid(sec)
		color_picker = _add_color_picker(sec)
		if allow_erase: _add_check(sec, "Erase native floor in region", "erase", false)
		return sec

	func try_build_grid_menu(gl) -> void:
		if _populated or not gl or not gl.World: return
		var level = gl.World.get("Level")
		if not level: return
		var tilemap = level.get("TileMap")
		if not is_instance_valid(tilemap) or not tilemap.tile_set: return
		var items = []
		_index_to_path = []
		var tools = gl.Editor.Tools if gl.Editor else {}
		var host_tool = tools.get("FloorShapeTool")
		var controls = host_tool.get("Controls") if is_instance_valid(host_tool) else null
		var source = controls.get("SmartTileId") if controls is Dictionary else null
		if allow_empty:
			_index_to_path.append("")
			items.append({"icon": null, "texture": null, "tooltip": "No fill", "modulate": Color.white})
		for id in tilemap.tile_set.get_tiles_ids():
			var texture = tilemap.tile_set.tile_get_texture(id)
			if not texture: continue
			_index_to_path.append(texture.resource_path)
			var icon = source.get_item_icon(id) if source is ItemList and id < source.get_item_count() else texture
			items.append({"icon": icon, "texture": texture, "tooltip": tilemap.tile_set.tile_get_name(id) if tilemap.tile_set.tile_get_name(id) != "" else texture.resource_path.get_file().get_basename(), "modulate": tilemap.tile_set.tile_get_modulate(id)})
		if items.empty(): return
		var selected = _index_to_path.find(_selection_path)
		_restoring = selected >= 0 or _keep_color_on_populate
		_keep_color_on_populate = false
		_sg.populate(items, selected)
		_restoring = false
		_populated = true

	func _on_texture_selected(index: int):
		if index >= 0 and index < _sg._all_items.size():
			_set_field("texture", _sg._all_items[index].get("texture", _sg._all_items[index].icon))
			_apply_default_color(index)

class PatternPanel:
	extends FeaturePanel

	# ---- UI nodes ----
	var allow_empty = false

	var rotation_spin = null   # SpinBox
	var outline_check = null   # CheckButton

	## Build and return a VBoxContainer with all controls.
	## The pattern grid is built immediately via SearchableGrid; items are
	## populated lazily in try_build_grid_menu().
	func build(grid_parent = null) -> VBoxContainer:
		var sec = VBoxContainer.new()
		sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sec.add_constant_override("separation", 6)

		if grid_parent != null:
			_add_grid(grid_parent, true)
		else:
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
	var offset_spin  = null   # SpinBox
	var reverse_check = null # CheckButton

	func _init(asset_script = null):
		_asset_script = asset_script

	## Build and return a VBoxContainer with all controls.
	func build(grid_parent = null) -> VBoxContainer:
		var sec = VBoxContainer.new()
		sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sec.add_constant_override("separation", 6)

		if grid_parent != null:
			_add_grid(grid_parent, true)
		else:
			sec.add_child(_label("Wall:"))
			_add_grid(sec)
			sec.add_child(_spacer(6))

		color_picker = _add_color_picker(sec)

		offset_spin = _add_range(sec, "Offset (px):", "offset", -8192.0, 8192.0, 1.0, 0.0)
		offset_spin.hint_tooltip = "Closed outlines: + outward, - inward. Moves the wall, not its texture width. Open Paths/Lines require 0."
		reverse_check = _add_check(sec, "Reverse direction", "reverse_direction", false)
		reverse_check.hint_tooltip = "Reverse traversal after offset to swap texture sides. Closed outlines keep their starting vertex."

		shadow_check = _add_check(sec, "Shadow", "shadow", true)

		bevel_check = CheckButton.new()
		bevel_check.text = "Bevel corners"
		bevel_check.pressed = true
		bevel_check.connect("toggled", self, "_on_bevel_toggled")
		_controls["joint"] = bevel_check
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
	var offset_spin       = null   # SpinBox
	var reverse_check     = null   # CheckButton
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
	func build(grid_parent = null) -> VBoxContainer:
		var sec = VBoxContainer.new()
		sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sec.add_constant_override("separation", 6)

		if grid_parent != null:
			_add_grid(grid_parent, true)
		else:
			sec.add_child(_label("Path:"))
			_add_grid(sec)
			sec.add_child(_spacer(6))

		color_picker = _add_color_picker(sec)

		width_spin = _add_range(sec, "Width:", "width", 0.1, 10.0, 0.1, 1.0)
		offset_spin = _add_range(sec, "Offset (px):", "offset", -8192.0, 8192.0, 1.0, 0.0)
		offset_spin.hint_tooltip = "Closed outlines: + outward, - inward. Moves the path, not its width. Open Paths/Lines require 0."
		reverse_check = _add_check(sec, "Reverse direction", "reverse_direction", false)
		reverse_check.hint_tooltip = "Reverse traversal after offset to swap texture sides. Open paths start at the opposite end; fade and taper follow traversal."

		smoothness_slider = _add_range(sec, "Smoothness:", "smoothness", 0.0, 1.0, 0.01, 0.0, true)

		_add_layer_option(sec)

		sorting_option = _add_option(sec, "Sorting:", ["Over", "Under"], "sorting")

		sec.add_child(HSeparator.new())

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
	func build(grid_parent = null) -> VBoxContainer:
		var sec = VBoxContainer.new()
		sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sec.add_constant_override("separation", 6)

		# ---- Texture ----
		if grid_parent != null:
			_add_grid(grid_parent, true)
		else:
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

		# ---- Placement mode ----
		placement_mode_option = _add_option(sec, "Placement Mode:", ["Ridge along area", "Expand (eave at area, roof outside)", "Inset (eave at area, roof inside)"], "placement_mode")
		placement_mode_option.hint_tooltip = "Ridge: polygon edge is the ridge line, eave expands outward.\nExpand: polygon is the eave edge, ridge is outside the area.\nInset: polygon is the eave edge, ridge is inside the area."

		sec.add_child(HSeparator.new())

		# ---- Shade ----
		shade_check = CheckButton.new()
		shade_check.text = "Sunlight Shading (all roofs)"
		shade_check.hint_tooltip = "Applied to all roofs on this level when placing a roof."
		shade_check.connect("toggled", self, "_on_shade_toggled")
		_controls["shade"] = shade_check
		sec.add_child(shade_check)

		_shade_sub = VBoxContainer.new()
		_shade_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_shade_sub.add_constant_override("separation", 6)
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
# WATER FILL PANEL
# ============================================================================

class WaterPanel:
	extends FeaturePanel
	var deep_picker = null
	var shallow_picker = null
	var blend_spin = null
	var border_check = null
	var level_label = null
	var _mesh = null
	var _global = null
	var _style_mesh_id = 0

	func build() -> VBoxContainer:
		var sec = VBoxContainer.new()
		sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sec.add_constant_override("separation", 6)
		level_label = _label("Current map level | Water layer (0)")
		sec.add_child(level_label)
		deep_picker = _add_water_color(sec, "Deep water:", "deep_color", Color("3aa19a"))
		shallow_picker = _add_water_color(sec, "Shallow water:", "shallow_color", Color("8bceb0"))
		blend_spin = _add_range(sec, "Blend distance (tiles):", "blend_distance", 0.5, 4.0, 0.1, 1.5)
		border_check = CheckButton.new()
		border_check.text = "Disable border (entire level)"
		border_check.disabled = true
		border_check.connect("toggled", self, "_on_border_toggled")
		sec.add_child(border_check)
		var note = _label("Click inside a Shape marker to fill.\nTouching water regions merge.\nTextures: native water and shore.\nCustom water textures are not saved\nby Dungeondraft.")
		note.autowrap = true
		note.add_color_override("font_color", Color(0.75, 0.78, 0.84, 0.85))
		sec.add_child(note)
		return sec

	func _add_water_color(sec, text, setting, value):
		sec.add_child(_label(text))
		var picker = ColorPickerButton.new()
		picker.color = value
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.connect("color_changed", self, "_set_field_from_signal", [setting])
		sec.add_child(picker)
		return picker

	func bind_feature(value) -> void:
		if is_instance_valid(feature) and feature.is_connected("border_changed", self, "_on_border_changed"):
			feature.disconnect("border_changed", self, "_on_border_changed")
		.bind_feature(value)
		if feature:
			feature.connect("border_changed", self, "_on_border_changed")
		if border_check: border_check.disabled = feature == null or not is_instance_valid(_mesh)

	func sync_level_settings(gl, refresh_border = false) -> void:
		_global = gl
		var level = BuildingPlannerUtils.resolve_level({"Global": gl})
		var mesh = level.get("WaterMesh") if level != null else null
		border_check.disabled = feature == null or not is_instance_valid(mesh)
		level_label.text = "Level: %s | Water layer (0)" % str(level.get("Label")) if level != null else "Open a map to fill water."
		if mesh == _mesh:
			if refresh_border and is_instance_valid(mesh): _on_border_changed(mesh, mesh.Save().get("disable_border", false))
			return
		_mesh = mesh
		if not is_instance_valid(mesh): return
		if _style_mesh_id != 0 and _style_mesh_id != mesh.get_instance_id(): _settings.clear()
		_style_mesh_id = mesh.get_instance_id()
		# Native defaults belong to this level. Draft edits survive tool switches.
		for entry in [["deep_color", mesh.DeepColor, deep_picker], ["shallow_color", mesh.ShallowColor, shallow_picker], ["blend_distance", mesh.BlendDistance, blend_spin]]:
			var value = _settings.get(entry[0], entry[1])
			if entry[2] is ColorPickerButton: entry[2].color = value
			else: entry[2].value = value
			_set_field(entry[0], value)
		_on_border_changed(mesh, mesh.Save().get("disable_border", false))

	func _on_border_toggled(value):
		if _restoring: return
		var level = BuildingPlannerUtils.resolve_level({"Global": _global}) if _global != null else null
		# Reject an event targeting a level that changed before this frame's update.
		if feature and level != null and level.get("WaterMesh") == _mesh:
			feature.set_border_disabled(value)

	func _on_border_changed(mesh, disabled):
		if mesh != _mesh: return
		_restoring = true
		border_check.pressed = disabled
		_restoring = false

	func release() -> void:
		_mesh = null
		_global = null

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
var _pf_tile_panel = null
var _pf_fill_selector = null
var _pf_pattern_container = null
var _pf_tile_container = null

# Wall Builder section
var _wb_section    = null
var _wb_wall_panel = null   # WallPanel

# Path Builder section
var _pb_section    = null
var _pb_path_panel = null   # PathPanel

# Room Builder section
var _rb_section               = null
var _rb_templates = null
var _rb_template_add = null
var _rb_template_rename = null
var _rb_template_delete = null
var _rb_template_status = null
var _rb_name_dialog = null
var _rb_name_edit = null
var _rb_renaming_template = null
var _rb_sub_mode_selector     = null   # OptionButton
var _rb_floor_toggle          = null   # Button (collapsible Floor header)
var _rb_floor_body            = null   # VBoxContainer
var _rb_pattern_panel         = null   # PatternPanel
var _rb_tile_panel = null
var _rb_fill_selector = null
var _rb_pattern_container = null
var _rb_tile_container = null
var _rb_outlines_toggle       = null   # Button (collapsible Outlines header)
var _rb_outlines_body         = null   # VBoxContainer
var _rb_outline_selector      = null   # OptionButton (room outlines list)
var _rb_outline_add_wall      = null   # Button (+ Wall)
var _rb_outline_add_path      = null   # Button (+ Path)
var _rb_outline_rename        = null   # Button (Rename)
var _rb_outline_delete        = null   # Button (Delete)
var _rb_outline_name_dialog   = null   # ConfirmationDialog
var _rb_outline_name_edit     = null   # LineEdit
var _rb_renaming_outline_index = -1
var _rb_draft_outlines        = [{"name": "Wall Default", "mode": 0, "settings": {}}]
var _rb_draft_outline_index   = 0
var _rb_draft_outlines_dirty  = false
var _rb_wall_panel            = null   # WallPanel
var _rb_wall_container        = null   # VBoxContainer — shown when active outline = Wall
var _rb_path_panel            = null   # PathPanel
var _rb_path_container        = null   # VBoxContainer — shown when active outline = Path

# Roof Builder section
var _rf_section    = null
var _rf_roof_panel = null   # RoofPanel
var _wf_section = null
var _wf_water_panel = null   # WaterPanel

# Left sidebar root & docked right-side resource panel
var _root = null
var _right_panel = null
var _right_panel_attached_to_content = false
var _pf_pattern_resource = null
var _pf_tile_resource = null
var _wb_wall_resource = null
var _pb_path_resource = null
var _rb_resource = null
var _rb_floor_resource_header = null
var _rb_pattern_resource_slot = null
var _rb_tile_resource_slot = null
var _rb_outline_resource_header = null
var _rb_wall_resource_slot = null
var _rb_path_resource_slot = null
var _rf_roof_resource = null

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
	panel.rect_min_size.x += 50
	_pf_pattern_panel = PatternPanel.new()
	_pf_tile_panel = SmartTilePanel.new()
	_wb_wall_panel    = WallPanel.new( _tool.parent_mod.get("Script"))
	_pb_path_panel    = PathPanel.new( _tool.parent_mod.get("Script"))
	_rb_pattern_panel = PatternPanel.new()
	_rb_tile_panel = SmartTilePanel.new()
	_rb_tile_panel.allow_empty = true
	_rb_tile_panel.allow_erase = false
	_rb_pattern_panel.allow_empty = true
	_rb_wall_panel    = WallPanel.new( _tool.parent_mod.get("Script"))
	_rb_path_panel    = PathPanel.new( _tool.parent_mod.get("Script"))
	_rf_roof_panel    = RoofPanel.new(LOGGER, _tool.parent_mod.get("Script"))
	_wf_water_panel   = WaterPanel.new()

	bind_features()
	_all_panels = [_pf_pattern_panel, _wb_wall_panel, _pb_path_panel, _rb_pattern_panel, _rb_wall_panel, _rb_path_panel, _rf_roof_panel, _wf_water_panel]
	_all_panels.append(_pf_tile_panel)
	_all_panels.append(_rb_tile_panel)
	for section in _all_panels:
		section._catalogs = _catalogs
		section.LOGGER = LOGGER

	var root = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_constant_override("separation", 10)
	_root = root

	# ---- Title (matching GuidesLines sidebar header) ----
	var title = Label.new()
	title.text = "Building Planner"
	title.align = Label.ALIGN_CENTER
	title.add_color_override("font_color", Color(0.92, 0.95, 1.0, 1.0))
	root.add_child(title)
	root.add_child(HSeparator.new())

	# ---- Mode selector card ----
	var mode_card = _create_section_card("Mode")
	_mode_selector = OptionButton.new()
	_mode_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_selector.add_item("Floor Fill",  Mode.PATTERN_FILL)
	_mode_selector.add_item("Wall Builder",  Mode.WALL_BUILDER)
	_mode_selector.add_item("Path Builder",  Mode.PATH_BUILDER)
	_mode_selector.add_item("Room Builder",  Mode.ROOM_BUILDER)
	_mode_selector.add_item("Roof Builder",  Mode.ROOF_BUILDER)
	_mode_selector.add_item("Water Fill", Mode.WATER_FILL)
	_mode_selector.selected = 0
	_mode_selector.connect("item_selected", self, "_on_mode_selected")
	mode_card.body.add_child(_mode_selector)
	root.add_child(mode_card.card)

	# ---- Right-side resource panel (holds texture grids for all modes) ----
	var resource_slots = _build_right_resource_panel()

	# ---- Mode sections (settings cards in left sidebar) ----
	var pf_card = _create_section_card("Floor Fill")
	_pf_section = pf_card.card
	_pf_fill_selector = OptionButton.new()
	_pf_fill_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pf_fill_selector.add_item("Pattern")
	_pf_fill_selector.add_item("Smart Tiles")
	_pf_fill_selector.connect("item_selected", self, "_on_floor_fill_selected")
	pf_card.body.add_child(_pf_fill_selector)
	_pf_pattern_container = _pf_pattern_panel.build(resource_slots.pf_pattern)
	_pf_tile_container = _pf_tile_panel.build(resource_slots.pf_tile)
	pf_card.body.add_child(_pf_pattern_container)
	pf_card.body.add_child(_pf_tile_container)
	_pf_tile_container.hide()
	root.add_child(_pf_section)

	var wb_card = _create_section_card("Wall Settings")
	_wb_section = wb_card.card
	wb_card.body.add_child(_wb_wall_panel.build(resource_slots.wb_wall))
	root.add_child(_wb_section)

	var pb_card = _create_section_card("Path Settings")
	_pb_section = pb_card.card
	pb_card.body.add_child(_pb_path_panel.build(resource_slots.pb_path))
	root.add_child(_pb_section)

	_rb_section = _build_room_builder_section(resource_slots)
	root.add_child(_rb_section)

	var rf_card = _create_section_card("Roof Settings")
	_rf_section = rf_card.card
	rf_card.body.add_child(_rf_roof_panel.build(resource_slots.rf_roof))
	root.add_child(_rf_section)

	var wf_card = _create_section_card("Water Fill")
	_wf_section = wf_card.card
	wf_card.body.add_child(_wf_water_panel.build())
	root.add_child(_wf_section)

	var mod_root = _tool.parent_mod.Global.get("Root")
	var icon = Image.new()
	var sample_icon = null
	if mod_root != null and icon.load(mod_root + "icons/eyedropper.svg") == OK:
		sample_icon = ImageTexture.new()
		sample_icon.create_from_image(icon)
	for section in _all_panels:
		if not section._sg: continue
		section._sg._editor = _tool.parent_mod.Global.get("Editor")
		section.sample_category = "Tiles" if section is SmartTilePanel else ("Patterns" if section is PatternPanel else ("Walls" if section is WallPanel else ("Paths" if section is PathPanel else "Roofs")))
		if sample_icon:
			section.sample_button.icon = sample_icon
			section.sample_button.text = ""
		section.sample_button.connect("pressed", _tool, "start_sampling", [section])

	# Attach right-side resource panel to Editor Content when available,
	# or park it hidden inside root so headless tests free it with the panel.
	_attach_right_panel()

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
	update_resource_panel_state()

## Also called after late GuidesLines registration creates the feature instances.
func bind_features() -> void:
	_pf_pattern_panel.bind_feature(_tool._pattern_fill)
	if _pf_tile_panel: _pf_tile_panel.bind_feature(_tool._smart_tile_fill)
	_wb_wall_panel.bind_feature(_tool._wall_builder)
	_pb_path_panel.bind_feature(_tool._path_builder)
	_rb_pattern_panel.bind_feature(_tool._room_builder._pattern_fill if _tool._room_builder else null)
	if _rb_tile_panel: _rb_tile_panel.bind_feature(_tool._room_builder._smart_tile_fill if _tool._room_builder else null)
	_rb_wall_panel.bind_feature(_tool._room_builder._wall_builder if _tool._room_builder else null)
	_rb_path_panel.bind_feature(_tool._room_builder._path_builder if _tool._room_builder else null)
	_rf_roof_panel.bind_feature(_tool._roof_builder)
	_wf_water_panel.bind_feature(_tool._water_fill)
	if _rb_sub_mode_selector:
		_on_rb_sub_mode(_rb_sub_mode_selector.selected)
	if _tool._room_builder and _rb_draft_outlines_dirty:
		_save_draft_outline_from_panel()
		var entries = []
		for draft in _rb_draft_outlines:
			var settings = _tool._room_builder.default_outline_settings(draft.mode)
			for key in draft.settings:
				settings["active_" + key] = draft.settings[key]
			entries.append({"name": draft.name, "mode": draft.mode, "settings": settings})
		_tool._room_builder.set_outlines(entries, _rb_draft_outline_index)
		_rb_draft_outlines_dirty = false
	if _rb_outline_selector:
		_load_active_outline_into_ui()
	if _rb_fill_selector and _tool._room_builder:
		_tool._room_builder.active_fill_mode = _rb_fill_selector.selected
	update_room_overrides()

# ============================================================================
# SHARED CARD & RIGHT-SIDE RESOURCE PANEL HELPERS (GuidesLines UI style)
# ============================================================================

func _create_card_stylebox() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.11, 0.45)
	style.border_color = Color(1.0, 1.0, 1.0, 0.10)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style

func _create_section_card(title_text: String, expand_vertical: bool = false) -> Dictionary:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if expand_vertical:
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_stylebox_override("panel", _create_card_stylebox())

	var body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if expand_vertical:
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_constant_override("separation", 6)

	var header = Label.new()
	header.text = title_text
	header.add_color_override("font_color", Color(0.75, 0.85, 0.96, 0.95))
	body.add_child(header)
	body.add_child(HSeparator.new())

	card.add_child(body)
	return {"card": card, "body": body, "header": header}

func _get_editor_content():
	if not _tool or not _tool.parent_mod or not _tool.parent_mod.Global:
		return null
	var editor = _tool.parent_mod.Global.get("Editor")
	if not editor is Node or not is_instance_valid(editor):
		return null
	var content = editor.get_node_or_null("VPartition/Panels/HSplit/Content")
	return content if content is Control and is_instance_valid(content) else null

func _create_floating_panel_container(panel_name: String) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.name = panel_name
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var style = StyleBoxFlat.new()
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_detail = 4
	var editor = _tool.parent_mod.Global.get("Editor") if _tool and _tool.parent_mod and _tool.parent_mod.Global else null
	var tools_node = editor.get_node_or_null("VPartition/Panels/Tools") if editor is Node and is_instance_valid(editor) else null
	if tools_node and tools_node.material:
		panel.material = tools_node.material
		style.bg_color = Color(1, 1, 1, 1)
	else:
		style.bg_color = Color(0.14, 0.14, 0.16, 0.92)
	panel.add_stylebox_override("panel", style)
	return panel

func _create_resource_slot() -> VBoxContainer:
	var slot = VBoxContainer.new()
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slot.add_constant_override("separation", 6)
	return slot

func _build_right_resource_panel() -> Dictionary:
	_right_panel = _create_floating_panel_container("BuildingPlannerResourcePanel")
	_right_panel.anchor_left = 1.0
	_right_panel.anchor_right = 1.0
	_right_panel.anchor_top = 0.0
	_right_panel.anchor_bottom = 1.0
	_right_panel.margin_left = -310.0
	_right_panel.margin_right = -10.0
	_right_panel.margin_top = 10.0
	_right_panel.margin_bottom = -10.0
	_right_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_right_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_right_panel.rect_min_size = Vector2(280, 0)
	_right_panel.visible = false

	var wrapper = VBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrapper.add_constant_override("separation", 8)
	_right_panel.add_child(wrapper)

	var title = Label.new()
	title.text = "Resources"
	title.align = Label.ALIGN_CENTER
	title.add_color_override("font_color", Color(0.92, 0.95, 1.0, 1.0))
	wrapper.add_child(title)
	wrapper.add_child(HSeparator.new())

	var pf_pattern_card = _create_section_card("Floor Pattern", true)
	_pf_pattern_resource = pf_pattern_card.card
	wrapper.add_child(_pf_pattern_resource)

	var pf_tile_card = _create_section_card("Smart Tiles", true)
	_pf_tile_resource = pf_tile_card.card
	_pf_tile_resource.visible = false
	wrapper.add_child(_pf_tile_resource)

	var wb_wall_card = _create_section_card("Wall Texture", true)
	_wb_wall_resource = wb_wall_card.card
	_wb_wall_resource.visible = false
	wrapper.add_child(_wb_wall_resource)

	var pb_path_card = _create_section_card("Path Texture", true)
	_pb_path_resource = pb_path_card.card
	_pb_path_resource.visible = false
	wrapper.add_child(_pb_path_resource)

	_rb_resource = VBoxContainer.new()
	_rb_resource.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rb_resource.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rb_resource.add_constant_override("separation", 8)
	_rb_resource.visible = false
	wrapper.add_child(_rb_resource)

	var rb_floor_card = _create_section_card("Floor Pattern", true)
	_rb_floor_resource_header = rb_floor_card.header
	_rb_pattern_resource_slot = _create_resource_slot()
	_rb_tile_resource_slot = _create_resource_slot()
	_rb_tile_resource_slot.visible = false
	rb_floor_card.body.add_child(_rb_pattern_resource_slot)
	rb_floor_card.body.add_child(_rb_tile_resource_slot)
	_rb_resource.add_child(rb_floor_card.card)

	var rb_outline_card = _create_section_card("Outline: Wall Default", true)
	_rb_outline_resource_header = rb_outline_card.header
	_rb_wall_resource_slot = _create_resource_slot()
	_rb_path_resource_slot = _create_resource_slot()
	_rb_path_resource_slot.visible = false
	rb_outline_card.body.add_child(_rb_wall_resource_slot)
	rb_outline_card.body.add_child(_rb_path_resource_slot)
	_rb_resource.add_child(rb_outline_card.card)

	var rf_roof_card = _create_section_card("Roof Style", true)
	_rf_roof_resource = rf_roof_card.card
	_rf_roof_resource.visible = false
	wrapper.add_child(_rf_roof_resource)

	return {
		"pf_pattern": pf_pattern_card.body,
		"pf_tile": pf_tile_card.body,
		"wb_wall": wb_wall_card.body,
		"pb_path": pb_path_card.body,
		"rb_pattern": _rb_pattern_resource_slot,
		"rb_tile": _rb_tile_resource_slot,
		"rb_wall": _rb_wall_resource_slot,
		"rb_path": _rb_path_resource_slot,
		"rf_roof": rf_roof_card.body,
	}

func _attach_right_panel() -> void:
	if not is_instance_valid(_right_panel):
		return
	var content = _get_editor_content()
	if content != null:
		if _right_panel.get_parent() != content:
			if _right_panel.get_parent() != null:
				_right_panel.get_parent().remove_child(_right_panel)
			content.add_child(_right_panel)
		_right_panel_attached_to_content = true
		return
	_right_panel_attached_to_content = false
	if is_instance_valid(_root) and _right_panel.get_parent() != _root:
		if _right_panel.get_parent() != null:
			_right_panel.get_parent().remove_child(_right_panel)
		_right_panel.visible = false
		_root.add_child(_right_panel)

func _destroy_right_panel() -> void:
	if is_instance_valid(_right_panel):
		var in_tree = _right_panel.is_inside_tree()
		if _right_panel.get_parent() != null:
			_right_panel.get_parent().remove_child(_right_panel)
		if in_tree:
			_right_panel.queue_free()
		else:
			_right_panel.free()
	_right_panel = null
	_right_panel_attached_to_content = false
	_pf_pattern_resource = null
	_pf_tile_resource = null
	_wb_wall_resource = null
	_pb_path_resource = null
	_rb_resource = null
	_rb_floor_resource_header = null
	_rb_pattern_resource_slot = null
	_rb_tile_resource_slot = null
	_rb_outline_resource_header = null
	_rb_wall_resource_slot = null
	_rb_path_resource_slot = null
	_rf_roof_resource = null

func update_resource_panel_state() -> void:
	if not is_instance_valid(_right_panel):
		return
	var content = _get_editor_content()
	if not _right_panel_attached_to_content or (content != null and _right_panel.get_parent() != content):
		_attach_right_panel()
	var mode = get_selected_mode()
	var smart_tiles = _pf_fill_selector != null and _pf_fill_selector.selected == 1
	var rb_tiles = _rb_fill_selector != null and _rb_fill_selector.selected == 1
	var rb_outline_mode = _active_rb_outline_mode()
	if is_instance_valid(_pf_pattern_resource):
		_pf_pattern_resource.visible = (mode == Mode.PATTERN_FILL and not smart_tiles)
	if is_instance_valid(_pf_tile_resource):
		_pf_tile_resource.visible = (mode == Mode.PATTERN_FILL and smart_tiles)
	if is_instance_valid(_wb_wall_resource):
		_wb_wall_resource.visible = (mode == Mode.WALL_BUILDER)
	if is_instance_valid(_pb_path_resource):
		_pb_path_resource.visible = (mode == Mode.PATH_BUILDER)
	if is_instance_valid(_rb_resource):
		_rb_resource.visible = (mode == Mode.ROOM_BUILDER)
	if is_instance_valid(_rb_pattern_resource_slot):
		_rb_pattern_resource_slot.visible = not rb_tiles
	if is_instance_valid(_rb_tile_resource_slot):
		_rb_tile_resource_slot.visible = rb_tiles
	if is_instance_valid(_rb_floor_resource_header):
		_rb_floor_resource_header.text = "Floor Smart Tiles" if rb_tiles else "Floor Pattern"
	if is_instance_valid(_rb_wall_resource_slot):
		_rb_wall_resource_slot.visible = (rb_outline_mode == 0)
	if is_instance_valid(_rb_path_resource_slot):
		_rb_path_resource_slot.visible = (rb_outline_mode == 1)
	if is_instance_valid(_rb_outline_resource_header):
		var list = _rb_outline_list()
		var idx = _rb_outline_index()
		var outline_name = list[idx].name if idx >= 0 and idx < list.size() else ("Wall" if rb_outline_mode == 0 else "Path")
		_rb_outline_resource_header.text = "Outline: %s" % outline_name
	if is_instance_valid(_rf_roof_resource):
		_rf_roof_resource.visible = (mode == Mode.ROOF_BUILDER)
	var enabled = _tool != null and _tool.is_enabled
	_right_panel.visible = enabled and _right_panel_attached_to_content and mode != Mode.WATER_FILL

func is_mouse_over_right_panel() -> bool:
	if not is_instance_valid(_right_panel) or not _right_panel.is_visible_in_tree():
		return false
	return Rect2(Vector2.ZERO, _right_panel.rect_size).has_point(_right_panel.get_local_mouse_position())

# ============================================================================
# SECTION BUILDERS
# ============================================================================

func _build_room_builder_section(resource_slots: Dictionary = {}) -> VBoxContainer:
	var sec = VBoxContainer.new()
	sec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sec.add_constant_override("separation", 10)

	var setup_card = _create_section_card("Room Setup")
	var setup_body = setup_card.body
	var source_hint = Label.new()
	source_hint.text = "Uses the selected GuidesLines template/group, or its Shape settings."
	source_hint.autowrap = true
	source_hint.add_color_override("font_color", Color(0.75, 0.78, 0.84, 0.85))
	setup_body.add_child(source_hint)

	# ---- Sub-mode selector ----
	var sub_mode_label = Label.new()
	sub_mode_label.text = "Sub-mode:"
	setup_body.add_child(sub_mode_label)

	_rb_sub_mode_selector = OptionButton.new()
	_rb_sub_mode_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rb_sub_mode_selector.add_item("Single",     0)
	_rb_sub_mode_selector.add_item("Merge",      1)
	_rb_sub_mode_selector.add_item("Conforming", 2)
	_rb_sub_mode_selector.add_item("Wrapping",   3)
	_rb_sub_mode_selector.add_item("Difference", 4)
	_rb_sub_mode_selector.selected = 0
	_rb_sub_mode_selector.connect("item_selected", self, "_on_rb_sub_mode")
	setup_body.add_child(_rb_sub_mode_selector)
	_build_room_templates(setup_body)
	_rb_override_label = FeaturePanel._label("")
	setup_body.add_child(_rb_override_label)
	var reset = Button.new()
	reset.text = "Reset rotation / scale"
	reset.connect("pressed", self, "_reset_room_overrides")
	setup_body.add_child(reset)
	update_room_overrides()
	sec.add_child(setup_card.card)

	# ---- Collapsible Floor panel ----
	var floor_card = _build_collapsible_card("Floor", true)
	_rb_floor_toggle = floor_card.toggle
	_rb_floor_body = floor_card.body
	sec.add_child(floor_card.panel)

	_rb_fill_selector = OptionButton.new()
	_rb_fill_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rb_fill_selector.add_item("Pattern")
	_rb_fill_selector.add_item("Smart Tiles")
	_rb_fill_selector.connect("item_selected", self, "_on_rb_fill_selected")
	_rb_floor_body.add_child(_rb_fill_selector)
	_rb_pattern_container = _rb_pattern_panel.build(resource_slots.get("rb_pattern"))
	_rb_tile_container = _rb_tile_panel.build(resource_slots.get("rb_tile"))
	_rb_tile_container.hide()
	_rb_floor_body.add_child(_rb_pattern_container)
	_rb_floor_body.add_child(_rb_tile_container)

	# ---- Collapsible Walls & Outlines panel ----
	var outlines_card = _build_collapsible_card("Walls & Outlines", true)
	_rb_outlines_toggle = outlines_card.toggle
	_rb_outlines_body = outlines_card.body
	sec.add_child(outlines_card.panel)

	var outline_row = HBoxContainer.new()
	_rb_outlines_body.add_child(outline_row)

	_rb_outline_selector = OptionButton.new()
	_rb_outline_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rb_outline_selector.clip_text = true
	_rb_outline_selector.hint_tooltip = "Outlines built for this room. Add multiple walls or paths with independent settings."
	_rb_outline_selector.connect("item_selected", self, "_on_rb_outline_selected")
	outline_row.add_child(_rb_outline_selector)

	_rb_outline_rename = Button.new()
	_rb_outline_rename.text = "Rename"
	_rb_outline_rename.connect("pressed", self, "_on_rb_outline_rename")
	outline_row.add_child(_rb_outline_rename)

	_rb_outline_delete = Button.new()
	_rb_outline_delete.text = "Delete"
	_rb_outline_delete.connect("pressed", self, "_on_rb_outline_delete")
	outline_row.add_child(_rb_outline_delete)

	var outline_add_row = HBoxContainer.new()
	_rb_outlines_body.add_child(outline_add_row)

	_rb_outline_add_wall = Button.new()
	_rb_outline_add_wall.text = "+ Wall"
	_rb_outline_add_wall.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rb_outline_add_wall.connect("pressed", self, "_on_rb_outline_add", [0])
	outline_add_row.add_child(_rb_outline_add_wall)

	_rb_outline_add_path = Button.new()
	_rb_outline_add_path.text = "+ Path"
	_rb_outline_add_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rb_outline_add_path.connect("pressed", self, "_on_rb_outline_add", [1])
	outline_add_row.add_child(_rb_outline_add_path)

	_rb_outline_name_dialog = ConfirmationDialog.new()
	_rb_outline_name_dialog.window_title = "Rename room outline"
	_rb_outline_name_dialog.rect_min_size = Vector2(320, 100)
	_rb_outline_name_edit = LineEdit.new()
	_rb_outline_name_edit.max_length = 120
	_rb_outline_name_edit.connect("text_entered", self, "_on_rb_outline_name_entered")
	_rb_outline_name_edit.connect("focus_entered", self, "_on_room_name_focus", [true])
	_rb_outline_name_edit.connect("focus_exited", self, "_on_room_name_focus", [false])
	_rb_outline_name_dialog.add_child(_rb_outline_name_edit)
	_rb_outline_name_dialog.connect("confirmed", self, "_on_rb_outline_name_confirmed")
	sec.add_child(_rb_outline_name_dialog)

	_rb_outlines_body.add_child(HSeparator.new())

	# ---- Wall sub-panel (visible when active outline = Wall) ----
	_rb_wall_container = _rb_wall_panel.build(resource_slots.get("rb_wall"))
	_rb_outlines_body.add_child(_rb_wall_container)

	# ---- Path sub-panel (visible when active outline = Path) ----
	_rb_path_container = _rb_path_panel.build(resource_slots.get("rb_path"))
	_rb_path_container.visible = false
	_rb_outlines_body.add_child(_rb_path_container)

	rebuild_room_outlines()

	return sec

func _build_collapsible_card(title: String, expanded: bool = true) -> Dictionary:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_stylebox_override("panel", _create_card_stylebox())

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_constant_override("separation", 6)
	card.add_child(vbox)

	var toggle = Button.new()
	toggle.toggle_mode = true
	toggle.pressed = expanded
	toggle.flat = true
	toggle.align = Button.ALIGN_LEFT
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle.add_color_override("font_color", Color(0.75, 0.85, 0.96, 0.95))
	toggle.add_color_override("font_color_hover", Color(0.92, 0.95, 1.0, 1.0))
	toggle.add_color_override("font_color_pressed", Color(0.75, 0.85, 0.96, 0.95))
	toggle.set_meta("section_title", title)
	toggle.text = ("[-] " if expanded else "[+] ") + title
	vbox.add_child(toggle)

	var body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_constant_override("separation", 6)
	body.visible = expanded
	body.add_child(HSeparator.new())
	vbox.add_child(body)

	toggle.connect("toggled", self, "_on_collapsible_section_toggled", [toggle, body])
	return {"panel": card, "toggle": toggle, "body": body}

func _on_collapsible_section_toggled(expanded: bool, toggle: Button, body: Control) -> void:
	if not expanded:
		release_search_focus()
	if is_instance_valid(body):
		body.visible = expanded
	if is_instance_valid(toggle):
		var title = str(toggle.get_meta("section_title")) if toggle.has_meta("section_title") else ""
		toggle.text = ("[-] " if expanded else "[+] ") + title

func _build_room_templates(sec):
	var row = HBoxContainer.new()
	sec.add_child(row)
	_rb_templates = OptionButton.new()
	_rb_templates.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rb_templates.clip_text = true
	_rb_templates.hint_tooltip = "Room styles saved with this map. Select New template to capture the current settings."
	_rb_templates.connect("item_selected", self, "_on_room_template_selected")
	row.add_child(_rb_templates)
	for entry in [["Add", "_on_room_template_add"], ["Rename", "_on_room_template_rename"], ["Delete", "_on_room_template_delete"]]:
		var button = Button.new()
		button.text = entry[0]
		button.connect("pressed", self, entry[1])
		row.add_child(button)
		match entry[0]:
			"Add": _rb_template_add = button
			"Rename": _rb_template_rename = button
			"Delete": _rb_template_delete = button
	_rb_template_status = FeaturePanel._label("")
	_rb_template_status.autowrap = true
	sec.add_child(_rb_template_status)
	_rb_name_dialog = ConfirmationDialog.new()
	_rb_name_dialog.window_title = "Rename room template"
	_rb_name_dialog.rect_min_size = Vector2(320, 100)
	_rb_name_edit = LineEdit.new()
	_rb_name_edit.max_length = 120
	_rb_name_edit.connect("text_entered", self, "_on_room_name_entered")
	_rb_name_edit.connect("focus_entered", self, "_on_room_name_focus", [true])
	_rb_name_edit.connect("focus_exited", self, "_on_room_name_focus", [false])
	_rb_name_dialog.add_child(_rb_name_edit)
	_rb_name_dialog.connect("confirmed", self, "_on_room_name_confirmed")
	sec.add_child(_rb_name_dialog)
	rebuild_room_templates()

func rebuild_room_templates():
	if not _rb_templates: return
	_rb_templates.clear()
	for template in _tool.room_templates: _rb_templates.add_item(template.name)
	_rb_templates.add_item("New template")
	_rb_templates.select(_tool.active_room_template if _tool.active_room_template >= 0 else _tool.room_templates.size())
	_rb_templates.disabled = _tool.room_templates.empty()
	var existing = _tool.active_room_template >= 0
	_rb_template_add.visible = not existing
	_rb_template_add.disabled = not _tool._templates_writable
	_rb_template_rename.visible = existing
	_rb_template_delete.visible = existing
	_rb_template_status.text = "" if _tool._templates_writable else "Room templates could not be loaded; original map data is preserved."
	if _rb_name_dialog: _rb_name_dialog.hide()

func _on_room_template_add():
	# Include defaults of hidden outline panels before taking the snapshot.
	var gl = _tool.parent_mod.Global
	for panel in [_rb_pattern_panel, _rb_tile_panel, _rb_wall_panel, _rb_path_panel]: panel.try_build_grid_menu(gl)
	if _tool.add_room_template(): rebuild_room_templates()
	else: _rb_template_status.text = "Cannot save template: select a valid GuidesLines shape or template first."

func _on_room_template_selected(index):
	if _tool.select_room_template(index): rebuild_room_templates()
	else:
		_rb_templates.select(_tool.active_room_template if _tool.active_room_template >= 0 else _tool.room_templates.size())
		_rb_template_status.text = "Cannot load template: a required texture is unavailable. See the log."

func _on_room_template_delete():
	var index = _tool.active_room_template
	if index < 0 or index >= _tool.room_templates.size(): return
	_tool.room_templates.remove(index)
	_tool.select_room_template(-1)
	rebuild_room_templates()

func _on_room_template_rename():
	var index = _tool.active_room_template
	if index < 0 or index >= _tool.room_templates.size(): return
	_rb_renaming_template = _tool.room_templates[index]
	_rb_name_edit.text = _rb_renaming_template.name
	_rb_name_dialog.popup_centered()
	_rb_name_edit.grab_focus()
	_rb_name_edit.select_all()

func _on_room_name_entered(_text):
	_on_room_name_confirmed()

func _on_room_name_focus(focused):
	if _tool and _tool.parent_mod and is_instance_valid(_tool.parent_mod.Global.Editor):
		_tool.parent_mod.Global.Editor.SearchHasFocus = focused

func _on_room_name_confirmed():
	var text = _rb_name_edit.text.strip_edges()
	if text.empty() or not _rb_renaming_template in _tool.room_templates: return
	_rb_renaming_template.name = text
	if _rb_name_edit.has_focus(): _rb_name_edit.release_focus()
	_rb_renaming_template = null
	rebuild_room_templates()

func apply_room_template(template) -> bool:
	var panels = [_rb_pattern_panel, _rb_wall_panel, _rb_path_panel]
	var restored = []
	var asset_script = _tool.parent_mod.get("Script")
	var tile_style = template.tile_style.duplicate(true)
	var tile_texture = null
	if tile_style.texture != "":
		var world = _tool.parent_mod.Global.World
		var tilemap = world.Level.get("TileMap") if world and world.Level else null
		if is_instance_valid(tilemap) and tilemap.tile_set:
			for id in tilemap.tile_set.get_tiles_ids():
				var texture = tilemap.tile_set.tile_get_texture(id)
				if texture and texture.resource_path == tile_style.texture: tile_texture = texture
		if tile_texture == null: return false
	tile_style.texture = tile_texture
	var resolved_assets = {}
	# Resolve every asset before touching settings, so missing packs cannot apply half a style.
	for i in range(3):
		var settings = template.panels[i].duplicate(true)
		var path = settings.texture
		settings.texture = null
		if path != "":
			if i == 0:
				# Patterns include colorable/custom-pack assets outside Library["Patterns"].
				if ResourceLoader.has_cached(path) or ResourceLoader.exists(path, "Texture") or File.new().file_exists(path):
					settings.texture = _rb_pattern_panel._load_texture_safe(path)
			else:
				if not asset_script or not asset_script.has_method("GetAssetList") or not asset_script.has_method("GetAssetTexture"): return false
				var category = "Walls" if i == 1 else "Paths"
				var cache_key = category + ":" + path
				if resolved_assets.has(cache_key):
					settings.texture = resolved_assets[cache_key]
				# Native GetAssetTexture indexes Reverse[path] and throws for a missing asset.
				elif path in asset_script.GetAssetList(category):
					settings.texture = asset_script.GetAssetTexture(category, path)
					resolved_assets[cache_key] = settings.texture
			if not settings.texture is Texture:
				if LOGGER: LOGGER.warn("Room template texture is unavailable: %s" % path)
				return false
		restored.append(settings)
	var restored_outlines = []
	for entry in template.outlines:
		var settings = entry.settings.duplicate(true)
		var path = settings.texture
		settings.texture = null
		if path != "":
			if not asset_script or not asset_script.has_method("GetAssetList") or not asset_script.has_method("GetAssetTexture"): return false
			var category = "Walls" if entry.mode == 0 else "Paths"
			var cache_key = category + ":" + path
			if resolved_assets.has(cache_key):
				settings.texture = resolved_assets[cache_key]
			elif path in asset_script.GetAssetList(category):
				settings.texture = asset_script.GetAssetTexture(category, path)
				resolved_assets[cache_key] = settings.texture
			if not settings.texture is Texture:
				if LOGGER: LOGGER.warn("Room template outline texture is unavailable: %s" % path)
				return false
		var active_settings = {}
		for key in settings:
			active_settings["active_" + key] = settings[key]
		restored_outlines.append({"name": entry.name, "mode": entry.mode, "settings": active_settings})
	for i in range(3):
		panels[i].try_build_grid_menu(_tool.parent_mod.Global)
		panels[i].apply_sample(restored[i])
	_rb_tile_panel.try_build_grid_menu(_tool.parent_mod.Global)
	_rb_tile_panel.apply_sample(tile_style)
	_rb_fill_selector.select(template.fill_mode)
	_on_rb_fill_selected(template.fill_mode)
	_rb_path_panel.update_camt_color_state(_tool.parent_mod.Global)
	if _rb_path_panel.color_picker.disabled:
		_rb_path_panel.color_picker.color = Color.white
		_rb_path_panel._set_field("color", Color.white)
		for entry in restored_outlines:
			if entry.mode == 1:
				entry.settings["active_color"] = Color.white
	_rb_sub_mode_selector.select(template.sub_mode)
	_on_rb_sub_mode(template.sub_mode)
	if not restored_outlines.empty():
		_tool._room_builder.set_outlines(restored_outlines, 0)
	_load_active_outline_into_ui()
	_tool._room_builder.shape_angle_offset = template.angle
	_tool._room_builder.shape_scale_factor = template.scale
	update_room_overrides()
	return true

# ============================================================================
# GRID MENU LIFECYCLE
# ============================================================================

func get_selected_mode() -> int:
	return _mode_selector.get_item_id(_mode_selector.selected) if _mode_selector else Mode.PATTERN_FILL

## Native hit tests use the current mouse and respect transformed object geometry.
func sample_at(panel, level, position: Vector2) -> bool:
	if panel.sample_category == "Tiles":
		var tilemap = level.get("TileMap")
		if not is_instance_valid(tilemap) or not tilemap.tile_set or not tilemap.has_method("get_cell_color"): return false
		var cell = tilemap.world_to_map(position)
		var id = tilemap.get_cellv(cell)
		if id < 0 or not id in tilemap.tile_set.get_tiles_ids(): return false
		panel.try_build_grid_menu(_tool.parent_mod.Global)
		panel.apply_sample({"texture": tilemap.tile_set.tile_get_texture(id), "color": tilemap.get_cell_color(int(cell.x), int(cell.y))})
		return true
	var containers = {"Patterns": "PatternShapes", "Walls": "Walls", "Paths": "Pathways", "Roofs": "Roofs"}
	var container = level.get(containers[panel.sample_category])
	if not is_instance_valid(container): return false
	var patterns = panel.sample_category == "Patterns"
	var takes_position = panel.sample_category == "Walls" or panel.sample_category == "Paths"
	var groups = container.get_children() if patterns else [container]
	# ponytail: one scan per click, like SelectTool; use a spatial index for very large maps.
	var chosen = null
	var chosen_layer = -INF
	for group in groups:
		for node in group.get_children():
			if not is_instance_valid(node) or node.is_queued_for_deletion() or not node is Node2D: continue
			if not node.is_visible_in_tree() or not node.has_method("IsMouseWithin") or not node.has_method("Save"): continue
			if node.has_meta("preview") and node.get_meta("preview"): continue
			var layer = node.GetLayer() if patterns else node.z_index
			if layer < chosen_layer: continue
			var hit = node.IsMouseWithin(position) if takes_position else node.IsMouseWithin()
			if hit:
				chosen = node
				chosen_layer = layer
	if chosen == null: return false
	var settings = read_sample(panel.sample_category, chosen)
	if settings.empty(): return false
	if panel.sample_category == "Paths" and panel.color_picker.disabled: settings.color = Color.white
	panel.apply_sample(settings)
	return true

static func read_sample(category: String, node) -> Dictionary:
	var settings = {}
	match category:
		"Patterns":
			var rotation = node.get("_Rotation")
			if not (rotation is float or rotation is int) or is_nan(float(rotation)) or is_inf(float(rotation)): return {}
			settings = {"texture": node.get("_Texture"), "color": node.color, "rotation": fposmod(rad2deg(rotation), 360.0), "layer": node.GetLayer(), "outline": node.get("HasOutline")}
		"Walls":
			settings = {"texture": node.get("Texture"), "color": node.get("Color"), "shadow": node.get("HasShadow"), "joint": node.get("Joint")}
		"Paths":
			var texture = node.texture
			if not texture is Texture or texture.get_height() <= 0: return {}
			settings = {"texture": texture, "color": node.modulate, "width": node.width / texture.get_height(), "smoothness": node.get("Smoothness"), "layer": node.z_index, "fade_in": node.get("FadeIn"), "fade_out": node.get("FadeOut"), "grow": node.get("Grow"), "shrink": node.get("Shrink"), "block_light": node.get("BlockLight")}
		"Roofs":
			var data = node.Save()
			var roofs = node.get_parent()
			settings = {"texture": node.get("TilesTexture"), "width": data.get("width"), "type": data.get("type"), "shade": roofs.get("Shade"), "sun_direction": roofs.get("SunDirection"), "shade_contrast": roofs.get("ShadeContrast")}
	# Native nodes do not retain builder offset/reversal/placement or Over/Under intent.
	# Keep those draft settings rather than guessing them from the resulting geometry.
	if not settings.get("texture") is Texture or settings.texture.resource_path == "": return {}
	for value in settings.values():
		if value == null: return {}
		if (value is float or value is int) and (is_nan(float(value)) or is_inf(float(value))): return {}
	return settings

func update_active_mode(mode: int, gl) -> void:
	if mode == Mode.PATH_BUILDER or mode == Mode.ROOM_BUILDER:
		_pb_path_panel.update_camt_color_state(gl)
		_rb_path_panel.update_camt_color_state(gl)
	elif mode == Mode.ROOF_BUILDER:
		sync_roof_settings(gl)
	elif mode == Mode.WATER_FILL:
		_wf_water_panel.sync_level_settings(gl)

func sync_roof_settings(gl) -> void:
	_rf_roof_panel.sync_level_settings(gl)

func shutdown() -> void:
	release_all_grid_menus()
	_destroy_right_panel()
	if _wf_water_panel: _wf_water_panel.bind_feature(null)
	_root = null
	_tool = null

## Populate only the active section; owned grids retain their data until map change.
func try_build_grid_menus(mode: int) -> void:
	if not _tool or not _tool.parent_mod:
		return
	var gl = _tool.parent_mod.Global
	match mode:
		Mode.PATTERN_FILL:
			if _tool.smart_tiles_enabled:
				_pf_tile_panel.try_build_grid_menu(gl)
			else:
				_pf_pattern_panel.try_build_grid_menu(gl)
		Mode.WALL_BUILDER:
			_wb_wall_panel.try_build_grid_menu(gl)
		Mode.PATH_BUILDER:
			_pb_path_panel.try_build_grid_menu(gl)
			_pb_path_panel.update_camt_color_state(gl)
		Mode.ROOM_BUILDER:
			if _tool._room_builder and _tool._room_builder.active_fill_mode == 1:
				_rb_tile_panel.try_build_grid_menu(gl)
			else:
				_rb_pattern_panel.try_build_grid_menu(gl)
			if _active_rb_outline_mode() == 0:
				_rb_wall_panel.try_build_grid_menu(gl)
			else:
				_rb_path_panel.try_build_grid_menu(gl)
				_rb_path_panel.update_camt_color_state(gl)
		Mode.ROOF_BUILDER:
			_rf_roof_panel.try_build_grid_menu(gl)
		Mode.WATER_FILL:
			_wf_water_panel.sync_level_settings(gl, true)
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
	if is_instance_valid(_rb_name_edit) and _rb_name_edit.has_focus():
		_rb_name_edit.release_focus()
	if is_instance_valid(_rb_outline_name_edit) and _rb_outline_name_edit.has_focus():
		_rb_outline_name_edit.release_focus()
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
	if _wf_section: _wf_section.visible = (mode == Mode.WATER_FILL)
	update_resource_panel_state()
	if _tool and _tool.is_enabled:
		try_build_grid_menus(mode)
	elif _tool and _tool.parent_mod:
		_refresh_all_layer_options(_tool.parent_mod.Global)

# ============================================================================
# CALLBACKS — MODE
# ============================================================================

func _on_floor_fill_selected(index):
	_tool.cancel_sampling()
	_tool._clear_previews()
	_tool.smart_tiles_enabled = index == 1
	_pf_pattern_container.visible = index == 0
	_pf_tile_container.visible = index == 1
	update_resource_panel_state()
	if _tool.is_enabled: try_build_grid_menus(Mode.PATTERN_FILL)

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

func _on_rb_fill_selected(index: int):
	_tool.cancel_sampling()
	_tool._clear_previews()
	if _tool._room_builder: _tool._room_builder.active_fill_mode = index
	_rb_pattern_container.visible = index == 0
	_rb_tile_container.visible = index == 1
	update_resource_panel_state()
	if _tool.is_enabled: try_build_grid_menus(Mode.ROOM_BUILDER)

func _active_rb_outline_mode() -> int:
	if _tool and _tool._room_builder:
		return _tool._room_builder.active_outline_mode
	if _rb_draft_outline_index >= 0 and _rb_draft_outline_index < _rb_draft_outlines.size():
		return _rb_draft_outlines[_rb_draft_outline_index].mode
	return 0

func _rb_outline_list() -> Array:
	if _tool and _tool._room_builder:
		return _tool._room_builder.outlines
	return _rb_draft_outlines

func _rb_outline_index() -> int:
	if _tool and _tool._room_builder:
		return _tool._room_builder.active_outline_index
	return _rb_draft_outline_index

func _next_draft_outline_name(mode: int) -> String:
	var prefix = "Wall" if mode == 0 else "Path"
	var used = {}
	for entry in _rb_draft_outlines:
		used[entry.name] = true
	var n = 1
	while used.has("%s %d" % [prefix, n]):
		n += 1
	return "%s %d" % [prefix, n]

func _save_draft_outline_from_panel() -> void:
	if _rb_draft_outline_index < 0 or _rb_draft_outline_index >= _rb_draft_outlines.size():
		return
	var entry = _rb_draft_outlines[_rb_draft_outline_index]
	var panel = _rb_wall_panel if entry.mode == 0 else _rb_path_panel
	if panel:
		entry.settings = panel._settings.duplicate()

func rebuild_room_outlines() -> void:
	if not _rb_outline_selector:
		return
	var list = _rb_outline_list()
	var selected = _rb_outline_index()
	_rb_outline_selector.clear()
	for entry in list:
		_rb_outline_selector.add_item(entry.name)
	if selected >= 0 and selected < list.size():
		_rb_outline_selector.select(selected)
	if _rb_outline_delete:
		_rb_outline_delete.disabled = list.size() <= 1
	if _rb_outline_rename:
		_rb_outline_rename.disabled = list.empty()
	if _rb_outlines_toggle:
		var title = "Walls & Outlines (%d)" % list.size()
		_rb_outlines_toggle.set_meta("section_title", title)
		_rb_outlines_toggle.text = ("[-] " if _rb_outlines_toggle.pressed else "[+] ") + title
	if _rb_outline_name_dialog:
		_rb_outline_name_dialog.hide()
	update_resource_panel_state()

func _sync_panel_from_outline(panel, active_settings: Dictionary) -> void:
	if not panel or not panel.has_method("apply_sample") or active_settings.empty():
		return
	var panel_settings = {}
	for key in active_settings:
		panel_settings[key.trim_prefix("active_")] = active_settings[key]
	if panel._populated:
		panel.apply_sample(panel_settings)
		return
	var texture = panel_settings.get("texture")
	if texture is Texture:
		panel._selection_path = texture.resource_path
	for setting in panel_settings:
		var value = panel_settings[setting]
		if panel._controls.has(setting):
			var control = panel._controls[setting]
			control.set_block_signals(true)
			if control is OptionButton:
				if setting == "layer":
					var found = false
					for i in range(control.get_item_count()):
						if control.get_item_id(i) == value: found = true
					if not found: control.add_item(str(value) + ": Layer", value)
					panel._select_layer_option(value)
				else: control.select(value)
			elif control is BaseButton: control.pressed = bool(value)
			elif control is Range:
				control.min_value = min(control.min_value, value)
				control.max_value = max(control.max_value, value)
				var step = control.step
				control.step = 0.0
				control.value = value
				control.step = step
				if control is SpinBox: control.get_line_edit().text = str(control.value)
				value = control.value
			control.set_block_signals(false)
		panel._set_field(setting, value)
	if panel.color_picker and panel_settings.has("color"):
		panel.color_picker.color = panel_settings.color

func _load_active_outline_into_ui(build_grids: bool = true) -> void:
	rebuild_room_outlines()
	var list = _rb_outline_list()
	var idx = _rb_outline_index()
	var mode = _active_rb_outline_mode()
	if _rb_wall_container:
		_rb_wall_container.visible = (mode == 0)
	if _rb_path_container:
		_rb_path_container.visible = (mode == 1)
	var panel = _rb_wall_panel if mode == 0 else _rb_path_panel
	if build_grids and _tool and _tool.is_enabled:
		try_build_grid_menus(Mode.ROOM_BUILDER)
	if idx >= 0 and idx < list.size() and panel:
		var entry = list[idx]
		if _tool and _tool._room_builder:
			_sync_panel_from_outline(panel, entry.settings)
		else:
			var prefixed = {}
			for key in entry.settings:
				prefixed["active_" + key] = entry.settings[key]
			_sync_panel_from_outline(panel, prefixed)
	var gl = _tool.parent_mod.Global if _tool and _tool.parent_mod else null
	if mode == 1 and gl and gl.get("ModMapData") is Dictionary and _rb_path_panel and _rb_path_panel.has_method("update_camt_color_state"):
		_rb_path_panel.update_camt_color_state(gl)
		var picker = _rb_path_panel.get("color_picker")
		if picker and picker.disabled:
			picker.color = Color.white
			_rb_path_panel._set_field("color", Color.white)

func _on_rb_outline_selected(index: int):
	release_search_focus()
	_tool.cancel_sampling()
	if _tool and _tool._room_builder:
		if not _tool._room_builder.select_outline(index):
			return
	else:
		if index < 0 or index >= _rb_draft_outlines.size():
			return
		_save_draft_outline_from_panel()
		_rb_draft_outline_index = index
		_rb_draft_outlines_dirty = true
	_load_active_outline_into_ui()

func _on_rb_outline_add(mode: int):
	release_search_focus()
	_tool.cancel_sampling()
	var gl = _tool.parent_mod.Global if _tool and _tool.parent_mod else null
	var built_target_grid = false
	if _tool and _tool._room_builder:
		_tool._room_builder.sync_active_outline_from_builder()
		var target_panel = _rb_wall_panel if mode == 0 else _rb_path_panel
		if gl and gl.get("Editor") != null and target_panel and not target_panel.get("_populated"):
			target_panel.try_build_grid_menu(gl)
			built_target_grid = true
			if mode == 1 and gl.get("ModMapData") is Dictionary and target_panel.has_method("update_camt_color_state"):
				target_panel.update_camt_color_state(gl)
		if _tool._room_builder.add_outline(mode) < 0:
			return
	else:
		_save_draft_outline_from_panel()
		_rb_draft_outlines.append({"name": _next_draft_outline_name(mode), "mode": mode, "settings": {}})
		_rb_draft_outline_index = _rb_draft_outlines.size() - 1
		_rb_draft_outlines_dirty = true
	_load_active_outline_into_ui(not built_target_grid)

func _on_rb_outline_delete():
	release_search_focus()
	_tool.cancel_sampling()
	if _tool and _tool._room_builder:
		if not _tool._room_builder.remove_outline(_tool._room_builder.active_outline_index):
			return
	else:
		if _rb_draft_outlines.size() <= 1:
			return
		_rb_draft_outlines.remove(_rb_draft_outline_index)
		if _rb_draft_outline_index >= _rb_draft_outlines.size():
			_rb_draft_outline_index = _rb_draft_outlines.size() - 1
		_rb_draft_outlines_dirty = true
	_load_active_outline_into_ui()

func _on_rb_outline_rename():
	var list = _rb_outline_list()
	var index = _rb_outline_index()
	if index < 0 or index >= list.size():
		return
	_rb_renaming_outline_index = index
	_rb_outline_name_edit.text = list[index].name
	_rb_outline_name_dialog.popup_centered()
	_rb_outline_name_edit.grab_focus()
	_rb_outline_name_edit.select_all()

func _on_rb_outline_name_entered(_text):
	_on_rb_outline_name_confirmed()

func _on_rb_outline_name_confirmed():
	var text = _rb_outline_name_edit.text.strip_edges()
	var index = _rb_renaming_outline_index
	if text.empty():
		return
	if _tool and _tool._room_builder:
		if not _tool._room_builder.rename_outline(index, text):
			return
	else:
		if index < 0 or index >= _rb_draft_outlines.size():
			return
		_rb_draft_outlines[index].name = text
		_rb_draft_outlines_dirty = true
	if _rb_outline_name_edit.has_focus():
		_rb_outline_name_edit.release_focus()
	_rb_renaming_outline_index = -1
	rebuild_room_outlines()

func update_room_overrides() -> void:
	if _rb_override_label:
		var room = _tool._room_builder
		_rb_override_label.text = "Rotation offset: %.1f deg | Scale: %.2fx" % [room.shape_angle_offset if room else 0.0, room.shape_scale_factor if room else 1.0]

func _reset_room_overrides() -> void:
	if _tool._room_builder:
		_tool._room_builder.shape_angle_offset = 0.0
		_tool._room_builder.shape_scale_factor = 1.0
	update_room_overrides()
