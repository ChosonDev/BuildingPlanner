extends "res://addons/gut/test.gd"

var root = ProjectSettings.globalize_path("res://").plus_file("..")
var UI = ResourceLoader.load(root.plus_file("scripts/tool/BuildingPlannerToolUI.gd"))
var Tool = ResourceLoader.load(root.plus_file("scripts/tool/BuildingPlannerTool.gd"))
var Overlay = ResourceLoader.load(root.plus_file("scripts/overlay/BuildingPlannerOverlay.gd"))

class Pattern:
	extends Polygon2D
	var _Texture = null
	var _Rotation = PI / 3
	var HasOutline = true
	var hit = true
	var hit_tests = 0
	func GetLayer(): return get_parent().z_index
	func IsMouseWithin():
		hit_tests += 1
		return hit
	func Save(): return {}

class Wall:
	extends Node2D
	var wall_texture = null
	var wall_color = Color("3299dd")
	func _get(property):
		if property == "Texture": return wall_texture
		if property == "Color": return wall_color
	var HasShadow = false
	var Joint = 0
	func IsMouseWithin(_position): return true
	func Save(): return {}

class SamplePath:
	extends Line2D
	var Smoothness = 0.37
	var FadeIn = true
	var FadeOut = false
	var Grow = false
	var Shrink = true
	var BlockLight = true
	func IsMouseWithin(_position): return true
	func Save(): return {}

class Roof:
	extends Node2D
	var TilesTexture = null
	func IsMouseWithin(): return true
	func Save(): return {"width": 143.25, "type": 2}

class Roofs:
	extends Node2D
	var Shade = true
	var SunDirection = 123.0
	var ShadeContrast = 0.42

class Level:
	extends Node2D
	var PatternShapes = null
	var Walls = null
	var Pathways = null
	var Roofs = null

class SampleWorld:
	extends Node2D
	var Level = null

class Canvas:
	extends Node2D
	var IsInsideBounds = true
	var MousePosition = Vector2.ZERO

func texture():
	var image = Image.new()
	image.create(16, 32, false, Image.FORMAT_RGBA8)
	var result = ImageTexture.new()
	result.create_from_image(image)
	result.resource_path = "user://sample_%s.png" % result.get_instance_id()
	return result

func context():
	var world = autofree(SampleWorld.new())
	world.Level = Level.new()
	world.add_child(world.Level)
	for field in ["PatternShapes", "Walls", "Pathways", "Roofs"]:
		var container = Roofs.new() if field == "Roofs" else Node2D.new()
		world.Level.add_child(container)
		world.Level.set(field, container)
	add_child(world)
	var tool = Tool.new({"Global": {"Root": root + "/", "World": world, "API": null, "Editor": {"Tools": {}, "Windows": {}}, "ModMapData": {"UchideshiNodeData": {}}}})
	tool.cached_world = world
	tool.cached_worldui = autofree(Canvas.new())
	add_child(tool.cached_worldui)
	tool.is_enabled = true
	var ui = UI.new(tool, null)
	ui.build(autofree(VBoxContainer.new()))
	tool._ui = ui
	return tool

func test_sampling_pattern_selects_hidden_catalog_entry_and_keeps_room_panel_independent():
	var tool = context()
	var ui = tool._ui
	var layer = Node2D.new()
	layer.z_index = 200
	tool.cached_world.Level.PatternShapes.add_child(layer)
	var pattern = Pattern.new()
	layer.add_child(pattern)
	pattern._Texture = texture()
	pattern.color = Color.orange
	var panel = ui._pf_pattern_panel
	for section in ui._all_panels:
		if not section._sg: continue
		assert_true(section.sample_button.icon is Texture)
		assert_true(section.sample_button.is_connected("pressed", tool, "start_sampling"))
	panel.refresh_layer_option({100: "Base", 200: "Custom"}, [100, 200])
	assert_true(ui.sample_at(panel, tool.cached_world.Level, Vector2.ZERO))
	assert_true(panel._settings.texture == pattern._Texture)
	assert_almost_eq(panel.rotation_spin.value, 60.0, 0.001)
	assert_eq(panel.color_picker.color, Color.orange)
	assert_eq(panel.layer_option.get_selected_id(), 200)
	assert_true(panel.outline_check.pressed)
	assert_eq(panel._index_to_path[panel._sg._selected_original], pattern._Texture.resource_path)
	assert_false(ui._rb_pattern_panel._settings.has("texture"))
	panel.try_build_grid_menu(tool.parent_mod.Global)
	assert_true(panel._settings.texture == pattern._Texture, "Picking survives a late/empty native catalog")
	tool.start_sampling(panel)
	assert_true(tool.handle_canvas_click(Vector2.ZERO))
	assert_null(tool._sampling_panel)
	pattern.hit = false
	var before = panel._settings.duplicate()
	assert_false(ui.sample_at(panel, tool.cached_world.Level, Vector2.ZERO))
	assert_eq_deep(panel._settings, before)
	tool.shutdown()

func test_sampling_wall_path_and_roof_copies_all_native_settings_without_map_edits():
	var tool = context()
	var ui = tool._ui
	var level = tool.cached_world.Level
	var wall = Wall.new()
	wall.wall_texture = texture()
	level.Walls.add_child(wall)
	assert_true(ui.sample_at(ui._rb_wall_panel, level, Vector2.ZERO))
	assert_false(ui._rb_wall_panel.shadow_check.pressed)
	assert_false(ui._rb_wall_panel.bevel_check.pressed)
	assert_eq(ui._rb_wall_panel.color_picker.color, wall.wall_color)
	var path = SamplePath.new()
	path.texture = texture()
	path.width = 32 * 12.345
	path.modulate = Color.red
	level.Pathways.add_child(path)
	var panel = ui._rb_path_panel
	panel.refresh_layer_option({0: "Native"}, [0])
	panel._set_field("offset", 45.0)
	assert_true(ui.sample_at(panel, level, Vector2.ZERO))
	assert_eq(panel.layer_option.get_selected_id(), path.z_index)
	assert_almost_eq(panel.width_spin.value, 12.345, 0.00001)
	assert_eq(panel.width_spin.step, 0.1)
	assert_eq(panel.width_spin.get_line_edit().text, str(panel.width_spin.value))
	assert_almost_eq(panel.smoothness_slider.value, 0.37, 0.00001)
	assert_eq(panel.color_picker.color, Color.red)
	assert_true(panel.fade_in_check.pressed)
	assert_false(panel.fade_out_check.pressed)
	assert_false(panel.grow_check.pressed)
	assert_true(panel.shrink_check.pressed)
	assert_true(panel.block_light_check.pressed)
	assert_eq(panel._settings.offset, 45.0, "Builder-only settings remain unchanged")
	var roof = Roof.new()
	roof.TilesTexture = texture()
	level.Roofs.add_child(roof)
	assert_true(ui.sample_at(ui._rf_roof_panel, level, Vector2.ZERO))
	assert_eq(ui._rf_roof_panel.width_spin.value, 143.25)
	assert_eq(ui._rf_roof_panel.width_spin.step, 1.0)
	assert_eq(ui._rf_roof_panel.width_spin.get_line_edit().text, "143.25")
	assert_eq(panel.smoothness_slider.step, 0.01)
	assert_eq(ui._rf_roof_panel.type_option.selected, 2)
	assert_true(ui._rf_roof_panel._shade_sub.visible)
	assert_eq(ui._rf_roof_panel.sun_dir_slider.value, 123.0)
	assert_almost_eq(ui._rf_roof_panel.contrast_slider.value, 0.42, 0.00001)
	assert_eq(level.Walls.get_child_count(), 1)
	assert_eq(level.Pathways.get_child_count(), 1)
	assert_eq(level.Roofs.get_child_count(), 1)
	tool.shutdown()

func test_sampling_input_cancels_on_miss_key_other_buttons_mode_level_and_disable():
	var tool = context()
	var overlay = Overlay.new()
	overlay.tool = tool
	tool.cached_worldui.add_child(overlay)
	tool._overlay = overlay
	var panel = tool._ui._pf_pattern_panel
	var click = InputEventMouseButton.new()
	click.pressed = true
	for button in [BUTTON_LEFT, BUTTON_RIGHT, BUTTON_WHEEL_UP]:
		tool.start_sampling(panel)
		assert_true(tool._sampling_panel == panel)
		click.button_index = button
		overlay._input(click)
		assert_null(tool._sampling_panel)
		assert_false(panel.sample_button.pressed)
	var key = InputEventKey.new()
	key.pressed = true
	key.scancode = KEY_SHIFT
	tool.start_sampling(panel)
	overlay._input(key)
	assert_null(tool._sampling_panel)
	tool.start_sampling(panel)
	tool._set_mode(tool.Mode.WALL_BUILDER)
	assert_null(tool._sampling_panel)
	tool.start_sampling(panel)
	tool.cached_world.Level = null
	tool.Update(0.0)
	assert_null(tool._sampling_panel)
	tool.Disable()
	assert_false(panel.sample_button.pressed)
	tool.shutdown()
	yield(get_tree(), "idle_frame")

func test_sampling_rejects_missing_texture_and_nonfinite_parameters():
	var pattern = autofree(Pattern.new())
	pattern._Texture = texture()
	for rotation in [null, "60", INF, NAN]:
		pattern._Rotation = rotation
		assert_true(UI.read_sample("Patterns", pattern).empty(), "Invalid rotation must be rejected before conversion")
	var wall = autofree(Wall.new())
	assert_true(UI.read_sample("Walls", wall).empty())
	var path = autofree(SamplePath.new())
	path.texture = texture()
	path.Smoothness = INF
	assert_true(UI.read_sample("Paths", path).empty())

func click_button(button):
	var position = button.rect_global_position + button.rect_size * 0.5
	var motion = InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	Input.parse_input_event(motion)
	for pressed in [true, false]:
		var click = InputEventMouseButton.new()
		click.position = position
		click.global_position = position
		click.button_index = BUTTON_LEFT
		click.pressed = pressed
		click.button_mask = BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(click)

func test_sampling_real_button_input_toggles_off_and_can_be_rearmed():
	var tool = context()
	tool.cached_worldui.IsInsideBounds = false
	var overlay = Overlay.new()
	overlay.tool = tool
	tool.cached_worldui.add_child(overlay)
	tool._overlay = overlay
	var panel = tool._ui._pf_pattern_panel
	var button = panel.sample_button
	button.get_parent().remove_child(button)
	var surface = autofree(Control.new())
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(surface)
	surface.add_child(button)
	button.rect_position = Vector2(20, 20)
	button.rect_size = Vector2(50, 30)
	yield(get_tree(), "idle_frame")
	click_button(button)
	assert_true(tool._sampling_panel == panel, "Native Button release arms picker")
	assert_true(button.pressed)
	click_button(button)
	assert_null(tool._sampling_panel, "Second native press/release cancels picker")
	assert_false(button.pressed)
	click_button(button)
	assert_true(tool._sampling_panel == panel)
	tool.shutdown()
	yield(get_tree(), "idle_frame")

func test_sampling_modal_input_is_not_consumed_and_lower_layers_skip_hit_tests():
	var tool = context()
	var overlay = Overlay.new()
	overlay.tool = tool
	tool.cached_worldui.add_child(overlay)
	tool._overlay = overlay
	var panel = tool._ui._pf_pattern_panel
	var window = autofree(Control.new())
	tool.parent_mod.Global.Editor.Windows["Test"] = window
	# Godot registers new input/modal controls on the next frame.
	yield(get_tree(), "idle_frame")
	var key = InputEventKey.new()
	key.pressed = true
	key.scancode = KEY_A
	tool.start_sampling(panel)
	# Viewport.input resets handled state before calling _input on the overlay.
	get_viewport().input(key)
	assert_null(tool._sampling_panel)
	assert_false(get_tree().is_input_handled(), "Visible host windows retain keyboard input")
	window.hide()
	var popup = autofree(PopupPanel.new())
	add_child(popup)
	popup.popup(Rect2(20, 20, 40, 40))
	yield(get_tree(), "idle_frame")
	tool.start_sampling(panel)
	get_viewport().input(key)
	assert_null(tool._sampling_panel, "Native modal stack also cancels sampling")
	popup.hide()
	var high = Node2D.new()
	high.z_index = 200
	tool.cached_world.Level.PatternShapes.add_child(high)
	var low = Node2D.new()
	low.z_index = 100
	tool.cached_world.Level.PatternShapes.add_child(low)
	var a = Pattern.new()
	a._Texture = texture()
	high.add_child(a)
	var b = Pattern.new()
	b._Texture = texture()
	low.add_child(b)
	assert_true(tool._ui.sample_at(panel, tool.cached_world.Level, Vector2.ZERO))
	assert_true(panel._settings.texture == a._Texture)
	assert_eq(a.hit_tests, 1)
	assert_eq(b.hit_tests, 0, "Lower layers need no geometric hit test after a higher hit")
	tool.shutdown()
	yield(get_tree(), "idle_frame")
