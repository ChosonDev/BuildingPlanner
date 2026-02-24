extends Reference

# BuildingPlanner - Dungeondraft Mod
# Undo/redo history record classes for all BuildingPlanner actions.
#
# Usage in feature scripts:
#   const BuildingPlannerHistory = preload("../tool/BuildingPlannerHistory.gd")
#   _record_history(BuildingPlannerHistory.PatternFillRecord.new(...))
#
# All records implement the HistoryApi contract:
#   undo()        — removes the created objects from the scene
#   redo()        — restores them from serialised data
#   dropped(type) — called by HistoryApi when record leaves the stack:
#                   type UNDO  → record was pushed out while active (objects
#                                are still in scene; nothing to do)
#                   type REDO  → record was invalidated after a new action
#                                while in redo position (objects already freed;
#                                clear saved data to release memory)
#   record_type() → String key used by HistoryApi for max_count grouping

const CLASS_NAME = "BuildingPlannerHistory"

# ============================================================================
# SHARED HELPERS
# ============================================================================

# Safe node removal: removes [node] from its parent and frees it.
static func _free_node(node, _world = null) -> void:
	if node == null or not is_instance_valid(node):
		return
	var p = node.get_parent()
	if p:
		p.remove_child(node)
	node.queue_free()

# ============================================================================
# PATTERN FILL RECORD
# ============================================================================

# Undo/redo record for a single fill operation.
# Stores saved shape data for redo and live node refs for undo.
class PatternFillRecord:
	var _parent_mod
	var LOGGER
	var _shape_datas: Array   # Array of Dictionary from PatternShape.Save()
	var _shape_nodes: Array   # current live PatternShape node references

	func _init(p_mod, logger, shapes: Array):
		_parent_mod = p_mod
		LOGGER = logger
		_shape_nodes = shapes.duplicate()
		_shape_datas = []
		for s in _shape_nodes:
			if is_instance_valid(s):
				_shape_datas.append(s.Save())
		if LOGGER:
			LOGGER.debug("PatternFillRecord created for %d shape(s)." % [_shape_datas.size()])

	func undo():
		for s in _shape_nodes:
			_free_node(s)
		_shape_nodes = []
		if LOGGER:
			LOGGER.debug("PatternFillRecord.undo(): removed %d shape(s)." % [_shape_datas.size()])

	func redo():
		if not _parent_mod or not _parent_mod.Global.World or not _parent_mod.Global.World.Level:
			if LOGGER: LOGGER.error("PatternFillRecord.redo(): World/Level not available.")
			return
		var ps = _parent_mod.Global.World.Level.PatternShapes
		_shape_nodes = []
		for data in _shape_datas:
			var shape = ps.LoadShape(data)
			if shape and is_instance_valid(shape):
				_shape_nodes.append(shape)
		if LOGGER:
			LOGGER.debug("PatternFillRecord.redo(): restored %d shape(s)." % [_shape_nodes.size()])

	# Called by HistoryApi when record is evicted from history stack.
	# type 0 = UNDO (objects are live — nothing to do)
	# type 1 = REDO (objects already freed — release saved data)
	func dropped(type: int) -> void:
		if type == 1:   # REDO direction
			_shape_datas.clear()
			_shape_nodes.clear()

	func record_type() -> String:
		return "BuildingPlanner.PatternFill"

# ============================================================================
# MIRROR PLACEMENT RECORD
# ============================================================================

class MirrorPlacementRecord:
	var _parent_mod
	var LOGGER
	var axis_marker_id: int
	var original_object_id
	var mirrored_object_id

	func _init(p_mod, logger, axis_id: int, orig_id, mirror_id):
		_parent_mod = p_mod
		LOGGER = logger
		axis_marker_id = axis_id
		original_object_id = orig_id
		mirrored_object_id = mirror_id
		if LOGGER:
			LOGGER.debug("MirrorPlacementRecord created (axis=%d)." % [axis_id])

	func undo():
		pass  # TODO: remove both original and mirrored objects

	func redo():
		pass  # TODO: re-place both objects

	func dropped(_type: int) -> void:
		pass

	func record_type() -> String:
		return "BuildingPlanner.MirrorPlacement"

