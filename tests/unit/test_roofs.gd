extends "res://addons/gut/test.gd"

var root = ProjectSettings.globalize_path("res://").plus_file("..")
var Roof = load(root.plus_file("scripts/features/RoofBuilder.gd"))
var UI = load(root.plus_file("scripts/tool/BuildingPlannerToolUI.gd"))
var actions = []

class RoofNode:
	extends Node2D
	var data = {}
	var sunlight = []
	var texture = null
	var hip_width = 0
	var lighting_at_set = []
	func Set(points, width, type):
		data = {"points": points, "width": width, "type": type}
		hip_width = 29 if type == 1 else 0
		lighting_at_set = sunlight.duplicate()
	func SetTileTexture(selected_texture):
		texture = selected_texture
		if hip_width > 0:
			hip_width = texture.get_height() # Native SetTileTexture changes existing Hip edges.
	func SetSunlight(enabled, radians, contrast):
		sunlight = [enabled, radians, contrast]
	func Save(copy):
		assert(not copy) # GDScript must explicitly preserve IDs when calling C# Save(bool).
		var saved = data.duplicate(true)
		saved.texture = texture
		return saved

class Roofs:
	extends Node2D
	var Shade = true
	var SunDirection = 45.0
	var ShadeContrast = 0.5
	func CreateRoof(sorting = 0):
		var roof = RoofNode.new()
		roof.SetSunlight(Shade, deg2rad(SunDirection), ShadeContrast)
		add_child(roof)
		if sorting == 1:
			move_child(roof, 0)
		return roof
	func UpdateSunlight(enabled, degrees, contrast):
		Shade = enabled
		SunDirection = degrees
		ShadeContrast = contrast
		for roof in get_children():
			roof.SetSunlight(enabled, deg2rad(degrees), contrast)
	func LoadRoof(data):
		var roof = CreateRoof()
		roof.SetTileTexture(data.texture)
		roof.Set(data.points, data.width, data.type)
		return roof

class HostWorld:
	extends Reference
	var Level
	var TileSize = 256
	func AssignNodeID(node):
		node.set_meta("node_id", 1)

class HostTool:
	extends Reference
	var Width
	var Sorting = 1
	var Type = 2
	var Controls = {}

class PolygonApi:
	extends Reference
	func is_ready():
		return true
	func compute_fill_polygon(_coords):
		return {"polygon": [Vector2.ZERO, Vector2(50, 0), Vector2(0, 50)]}

func record(action, _limit):
	actions.append(action)

func test_roof_placement_and_replay_preserve_level_lighting_in_degrees():
	var roofs = autofree(Roofs.new())
	var old_roof = roofs.CreateRoof()
	var world = HostWorld.new()
	world.Level = {"Roofs": roofs}
	var parent = {"Global": {"World": world, "Editor": {"Tools": {}}, "API": {"HistoryApi": self}}}
	var api = PolygonApi.new()
	var feature = Roof.new(api, null, parent)
	feature.active_texture = GradientTexture.new()
	feature.active_shade = false
	feature.active_sun_direction = 270.0
	feature.active_shade_contrast = 0.8
	feature.active_width = 384.0
	feature.active_type = 1
	feature.active_sorting = 1
	assert_true(feature.build_at(Vector2.ZERO))
	assert_eq(actions.size(), 1)
	assert_eq(old_roof.sunlight[0], false, "Disabling shading affects existing roofs too")
	assert_almost_eq(old_roof.sunlight[1], deg2rad(270), 0.00001)
	assert_eq(roofs.get_child(0).Save(false).width, 384.0)
	assert_eq(roofs.get_child(0).hip_width, 29, "Creation matches native Hip edge width after loading")
	assert_eq(roofs.get_child(0).texture, feature.active_texture)
	assert_eq_deep(roofs.get_child(0).lighting_at_set, [false, deg2rad(270), 0.8])
	for _iteration in range(2):
		actions[0].undo()
		assert_eq(roofs.get_child_count(), 1)
		assert_eq(old_roof.sunlight[0], true)
		assert_almost_eq(old_roof.sunlight[1], deg2rad(45), 0.00001)
		yield(get_tree(), "idle_frame")
		actions[0].redo()
		assert_eq(roofs.get_child_count(), 2)
		assert_eq(roofs.get_child(0).Save(false).width, 384.0, "Under sorting survives redo")
		assert_eq(roofs.get_child(0).hip_width, 29)
		for roof in roofs.get_children():
			assert_eq(roof.sunlight[0], false)
			assert_almost_eq(roof.sunlight[1], deg2rad(270), 0.00001)
	actions[0].dropped(0)
	actions.clear()

func test_roof_panel_converts_tiles_once_and_keeps_user_settings_on_reentry():
	var roofs = autofree(Roofs.new())
	var world = HostWorld.new()
	world.Level = {"Roofs": roofs}
	var host = HostTool.new()
	host.Width = autofree(SpinBox.new())
	host.Width.step = 0.1
	host.Width.value = 1.5
	var panel = UI.RoofPanel.new(null)
	autofree(panel.build())
	var global = {"Editor": {"Tools": {"RoofTool": host}}, "World": world}
	panel.try_build_grid_menu(global)
	assert_eq(panel.width_spin.value, 384.0)
	assert_eq(panel.type_option.selected, 2)
	assert_eq(panel.sorting_option.selected, 1)
	assert_true(panel.shade_check.pressed)
	panel.width_spin.value = 600.0
	panel.type_option.selected = 1
	panel.sorting_option.selected = 0
	panel.try_build_grid_menu(global)
	assert_eq(panel.width_spin.value, 600.0)
	assert_eq(panel.type_option.selected, 1)
	assert_eq(panel.sorting_option.selected, 0)

	panel.release()
	host.Width.value = 0.25
	host.Type = 0
	host.Sorting = 1
	panel.try_build_grid_menu(global)
	assert_eq(panel.width_spin.value, 600.0, "Map changes preserve user width")
	assert_eq(panel.type_option.selected, 1)
	assert_eq(panel.sorting_option.selected, 0)

func test_missing_roof_texture_never_changes_nodes_lighting_or_history():
	var roofs = autofree(Roofs.new())
	var world = HostWorld.new()
	world.Level = {"Roofs": roofs}
	var parent = {"Global": {"World": world, "Editor": {"Tools": {"RoofTool": {"Texture": GradientTexture.new()}}}, "API": {"HistoryApi": self}}}
	var feature = Roof.new(PolygonApi.new(), null, parent)
	feature.active_shade = false
	for texture in [null, "invalid"]:
		feature.active_texture = texture
		assert_false(feature.build_at(Vector2.ZERO))
		assert_eq(roofs.get_child_count(), 0)
		assert_true(roofs.Shade)
		assert_eq(roofs.SunDirection, 45.0)
		assert_true(actions.empty())


func test_roof_panel_reads_lighting_on_level_change_and_width_on_map_change():
	var first = autofree(Roofs.new())
	var second = autofree(Roofs.new())
	second.UpdateSunlight(false, 270.0, 0.8)
	var world = HostWorld.new()
	world.Level = {"Roofs": first}
	var host = HostTool.new()
	host.Width = autofree(SpinBox.new())
	host.Width.step = 0.1
	host.Width.value = 1.5
	var global_ref = {"Editor": {"Tools": {"RoofTool": host}}, "World": world}
	var feature = Roof.new(null, null, {"Global": global_ref})
	var panel = UI.RoofPanel.new(null)
	panel.bind_feature(feature)
	autofree(panel.build())
	panel.try_build_grid_menu(global_ref)
	assert_eq(feature.active_width, 384.0)
	assert_eq(feature.active_sun_direction, 45.0)
	panel.sun_dir_slider.value = 90
	panel.sun_dir_slider.emit_signal("value_changed", 90.0)
	panel.width_spin.value = 600
	panel.width_spin.emit_signal("value_changed", 600.0)
	panel.try_build_grid_menu(global_ref)
	assert_eq(feature.active_sun_direction, 90.0, "Tool reentry retains intentional lighting edits")
	first.UpdateSunlight(false, 180.0, 0.3)
	panel.sync_level_settings(global_ref)
	assert_false(panel.shade_check.pressed)
	assert_eq(feature.active_sun_direction, 180.0, "Native edits on the same level replace stale drafts")
	assert_almost_eq(feature.active_shade_contrast, 0.3, 0.001)
	first.UpdateSunlight(true, 45.0, 0.5) # Undo restores the same level's earlier sunlight.
	panel.sync_level_settings(global_ref)
	assert_true(feature.active_shade)
	assert_eq(feature.active_sun_direction, 45.0, "History changes refresh feature settings too")
	world.Level = {"Roofs": second}
	panel.sync_level_settings(global_ref)
	assert_false(panel.shade_check.pressed)
	assert_false(feature.active_shade)
	assert_eq(feature.active_sun_direction, 270.0)
	assert_almost_eq(feature.active_shade_contrast, 0.8, 0.001)
	assert_eq(feature.active_width, 600.0, "Changing level keeps style width")
	assert_eq(second.SunDirection, 270.0, "Reading controls never mutates native lighting")
	var next_world = HostWorld.new()
	next_world.TileSize = 128
	next_world.Level = {"Roofs": first}
	global_ref.World = next_world
	panel.release()
	panel.try_build_grid_menu(global_ref)
	assert_eq(feature.active_width, 192.0, "New map converts native tile width using its tile size")
	assert_eq(feature.active_sun_direction, 45.0)
	assert_true(feature.active_shade)
