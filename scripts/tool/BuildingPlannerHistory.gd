extends Reference

# BuildingPlanner - Dungeondraft Mod
# Undo/redo history record classes for all BuildingPlanner actions.
#
# Usage in feature scripts:
#   const BuildingPlannerHistory = preload("../tool/BuildingPlannerHistory.gd")
#   _record_history(BuildingPlannerHistory.PatternFillRecord.new(...))

const CLASS_NAME = "BuildingPlannerHistory"

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
			if is_instance_valid(s):
				s.queue_free()
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

	func record_type() -> String:
		return "BuildingPlanner.PatternFill"

# ============================================================================
# WALL BUILD RECORD
# ============================================================================

# Undo/redo record for a single wall-build operation.
# Stores the serialised wall data for redo and the live node ref for undo.
class WallBuildRecord:
	var _parent_mod
	var LOGGER
	var _wall_data: Dictionary   # from Wall.Save()
	var _wall_node               # current live Wall node reference

	func _init(p_mod, logger, wall):
		_parent_mod = p_mod
		LOGGER = logger
		_wall_node = wall
		_wall_data = wall.Save()
		if LOGGER:
			LOGGER.debug("WallBuildRecord created.")

	func undo():
		if is_instance_valid(_wall_node):
			_wall_node.queue_free()
		_wall_node = null
		if LOGGER:
			LOGGER.debug("WallBuildRecord.undo(): removed wall.")

	func redo():
		if not _parent_mod or not _parent_mod.Global.World or not _parent_mod.Global.World.Level:
			if LOGGER: LOGGER.error("WallBuildRecord.redo(): World/Level not available.")
			return
		var walls = _parent_mod.Global.World.Level.Walls
		# Snapshot child count so we can identify the newly added wall node.
		var count_before: int = walls.get_child_count()
		walls.LoadWall(_wall_data)
		var children: Array = walls.get_children()
		if children.size() > count_before:
			_wall_node = children[children.size() - 1]
		else:
			_wall_node = null
		if LOGGER:
			LOGGER.debug("WallBuildRecord.redo(): restored wall.")

	func record_type() -> String:
		return "BuildingPlanner.WallBuild"

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

	func record_type() -> String:
		return "BuildingPlanner.MirrorPlacement"
