extends "res://addons/gut/test.gd"

var root = ProjectSettings.globalize_path("res://").plus_file("..")
var Water = load(root.plus_file("scripts/features/WaterFill.gd"))
var UI = load(root.plus_file("scripts/tool/BuildingPlannerToolUI.gd"))
const RING = [Vector2.ZERO, Vector2(25, 25), Vector2(25, 75), Vector2(75, 75), Vector2(75, 25), Vector2(25, 25), Vector2.ZERO, Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]

# Check the GDScript/C# call boundary; native triangulation remains a host check.
class WaterMeshFake:
	extends Reference
	var DeepColor = Color.blue
	var ShallowColor = Color.cyan
	var BlendDistance = 2.0
	var disabled = false
	var calls = []
	var saves = 0
	func DrawPolygon(points, inverted):
		calls.append([points, inverted, DeepColor, ShallowColor, BlendDistance])
	func Save():
		saves += 1
		return {"disable_border": disabled}
	func DisableBorder(value):
		disabled = value

class Master:
	extends Reference
	var IsBusy = false

class Editor:
	extends Reference
	var owner = null

class Api:
	extends Reference
	func is_ready():
		return true
	func compute_fill_polygon(_position):
		return {"polygon": RING.duplicate()}

class History:
	extends Reference
	var records = []
	func record(action, _count):
		records.append(action)

func context():
	var mesh = WaterMeshFake.new()
	var master = Master.new()
	var editor = Editor.new()
	editor.owner = master
	var history = History.new()
	var gl = {"World": {"Level": {"WaterMesh": mesh, "Label": "Ground"}}, "Editor": editor, "API": {"HistoryApi": history}}
	var water = Water.new(Api.new(), null, {"Global": gl})
	return {"mesh": mesh, "master": master, "history": history, "gl": gl, "water": water}

func test_water_fill_submits_one_native_call_with_bridged_hole_and_restores_brush_defaults():
	var f = context()
	f.water.active_deep_color = Color.red
	f.water.active_shallow_color = Color.yellow
	f.water.active_blend_distance = 0.7
	assert_true(f.water.build_at(Vector2(10, 50)))
	assert_eq(f.mesh.calls.size(), 1, "One native call owns the whole region and its history")
	assert_eq_deep(f.mesh.calls[0], [PoolVector2Array(RING), false, Color.red, Color.yellow, 0.7])
	assert_eq_deep([f.mesh.DeepColor, f.mesh.ShallowColor, f.mesh.BlendDistance], [Color.blue, Color.cyan, 2.0])
	assert_true(f.history.records.empty(), "Do not add a duplicate custom fill record")

func test_water_fill_rejects_busy_host_invalid_style_and_missing_mesh_without_mutation():
	var f = context()
	f.master.IsBusy = true
	assert_false(f.water.build_at(Vector2.ZERO))
	f.master.IsBusy = false
	for value in [NAN, INF, 0.0, 4.1]:
		f.water.active_blend_distance = value
		assert_false(f.water.build_at(Vector2.ZERO))
	f.water.active_blend_distance = 1.5
	f.water.active_deep_color = Color(NAN, 0, 0)
	assert_false(f.water.build_at(Vector2.ZERO))
	f.water.active_deep_color = Color.red
	f.gl.World.Level.WaterMesh = null
	assert_false(f.water.build_at(Vector2.ZERO))
	assert_true(f.mesh.calls.empty())
	assert_eq(f.mesh.DeepColor, Color.blue)

func test_water_panel_preserves_drafts_and_resets_from_native_defaults_on_level_change():
	var f = context()
	var panel = UI.WaterPanel.new()
	autofree(panel.build())
	panel.bind_feature(f.water)
	panel.sync_level_settings(f.gl)
	assert_eq(panel.deep_picker.color, Color.blue)
	panel.deep_picker.emit_signal("color_changed", Color.red)
	panel.sync_level_settings(f.gl)
	assert_eq(f.water.active_deep_color, Color.red, "A frame must not replace draft settings")
	assert_eq(f.mesh.saves, 1, "Do not serialize the water tree every frame")
	panel.release()
	panel.sync_level_settings(f.gl)
	assert_eq(f.water.active_deep_color, Color.red, "Rebinding on the same map keeps edits")
	var other = WaterMeshFake.new()
	other.DeepColor = Color.green
	other.disabled = true
	f.gl.World.Level = {"WaterMesh": other, "Label": "Upper"}
	panel.sync_level_settings(f.gl)
	assert_eq(f.water.active_deep_color, Color.green)
	assert_true(panel.border_check.pressed)
	assert_true("Upper" in panel.level_label.text)
	panel.bind_feature(null)

func test_water_border_has_independent_history_restores_panel_and_never_changes_geometry():
	var f = context()
	var panel = UI.WaterPanel.new()
	autofree(panel.build())
	panel.bind_feature(f.water)
	panel.sync_level_settings(f.gl)
	panel.border_check.pressed = true
	assert_true(f.mesh.disabled)
	assert_eq(f.history.records.size(), 1)
	var record = f.history.records[0]
	record.undo()
	assert_false(f.mesh.disabled)
	assert_false(panel.border_check.pressed)
	record.redo()
	assert_true(panel.border_check.pressed)
	assert_true(f.mesh.calls.empty())
	assert_true(f.water.set_border_disabled(true))
	assert_eq(f.history.records.size(), 1, "An unchanged checkbox creates no history")
	f.gl.World = {"Level": {}}
	record.undo()
	assert_true(f.mesh.disabled, "Old records cannot mutate another map")
	record.dropped(0)
	panel.bind_feature(null)

func test_water_panel_rejects_stale_border_events_and_accepts_late_feature_binding():
	var f = context()
	var panel = UI.WaterPanel.new()
	autofree(panel.build())
	panel.deep_picker.emit_signal("color_changed", Color.yellow)
	panel.sync_level_settings(f.gl)
	assert_true(panel.border_check.disabled)
	panel.bind_feature(f.water)
	assert_eq(f.water.active_deep_color, Color.yellow)
	assert_false(panel.border_check.disabled)
	f.gl.World.Level = {"WaterMesh": WaterMeshFake.new(), "Label": "Other"}
	panel.border_check.pressed = true
	assert_false(f.mesh.disabled)
	assert_true(f.history.records.empty())
	panel.bind_feature(null)
