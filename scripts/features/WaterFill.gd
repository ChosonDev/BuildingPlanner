extends Reference

# BuildingPlanner - Dungeondraft Mod
# Fill a marker region using the native water mesh and its native history.

const CLASS_NAME = "WaterFill"
const Utils = preload("../utils/BuildingPlannerUtils.gd")
const History = preload("../tool/BuildingPlannerHistory.gd")

signal border_changed(mesh, disabled)

var _gl_api = null
var LOGGER = null
var _parent_mod = null
var active_deep_color: Color = Color("3aa19a")
var active_shallow_color: Color = Color("8bceb0")
var active_blend_distance: float = 1.5

func _init(gl_api, logger, parent_mod = null):
	_gl_api = gl_api
	LOGGER = logger
	_parent_mod = parent_mod

func set_border_disabled(disabled: bool) -> bool:
	var level = Utils.resolve_level(_parent_mod)
	var mesh = level.get("WaterMesh") if level != null else null
	if not is_instance_valid(mesh) or not mesh.has_method("DisableBorder") or not mesh.has_method("Save"):
		return false
	var before = mesh.Save().get("disable_border", false)
	if before != disabled:
		mesh.DisableBorder(disabled)
		History.record_action(_parent_mod, LOGGER, History.WaterBorderRecord.new(_parent_mod, self, mesh, before, disabled))
	emit_signal("border_changed", mesh, disabled)
	return true

func build_at(coords: Vector2) -> bool:
	if not is_instance_valid(_gl_api) or not _gl_api.has_method("is_ready") or not _gl_api.is_ready():
		return false
	var polygon = Utils.resolve_fill_polygon(_gl_api, coords, LOGGER)
	if polygon.empty(): return false
	var level = Utils.resolve_level(_parent_mod)
	var mesh = level.get("WaterMesh") if level != null else null
	if not is_instance_valid(mesh) or not mesh.has_method("DrawPolygon"):
		if LOGGER: LOGGER.error("WaterFill: native WaterMesh is not available.")
		return false
	if is_nan(active_blend_distance) or is_inf(active_blend_distance) or active_blend_distance < 0.5 or active_blend_distance > 4.0:
		if LOGGER: LOGGER.error("WaterFill: blend distance must be within 0.5..4 tiles.")
		return false
	for color in [active_deep_color, active_shallow_color]:
		for channel in [color.r, color.g, color.b, color.a]:
			if is_nan(channel) or is_inf(channel) or channel < 0.0 or channel > 1.0:
				return false
	# AddPolygon may wait for an active native stroke; do not enqueue a fill whose
	# level or style could change while the host is busy.
	var editor = _parent_mod.Global.Editor
	if not is_instance_valid(editor) or not is_instance_valid(editor.owner) or editor.owner.get("IsBusy") != false:
		return false
	var previous = [mesh.DeepColor, mesh.ShallowColor, mesh.BlendDistance]
	mesh.DeepColor = active_deep_color
	mesh.ShallowColor = active_shallow_color
	mesh.BlendDistance = active_blend_distance
	# One native ChangeWaterMesh record, also recognized by _Lib HistoryApi.
	# Bridged hole contours stay in one call so islands and undo remain atomic.
	mesh.DrawPolygon(PoolVector2Array(polygon), false)
	mesh.DeepColor = previous[0]
	mesh.ShallowColor = previous[1]
	mesh.BlendDistance = previous[2]
	return true
