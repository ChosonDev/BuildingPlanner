extends Reference

# BuildingPlanner - Dungeondraft Mod
# Undo/redo history record classes for all BuildingPlanner actions.

const CLASS_NAME = "BuildingPlannerHistory"

# ============================================================================
# PATTERN FILL RECORD
# ============================================================================

class PatternFillRecord:
	var marker_id: int
	var pattern_name: String

	func _init(id: int, pattern: String):
		marker_id = id
		pattern_name = pattern

	func undo():
		pass  # TODO: remove placed pattern

	func redo():
		pass  # TODO: re-apply placed pattern

# ============================================================================
# WALL BUILD RECORD
# ============================================================================

class WallBuildRecord:
	var marker_id: int
	var wall_ids: Array  # IDs of placed wall segments

	func _init(id: int):
		marker_id = id
		wall_ids = []

	func undo():
		pass  # TODO: remove placed walls

	func redo():
		pass  # TODO: re-place walls

# ============================================================================
# MIRROR PLACEMENT RECORD
# ============================================================================

class MirrorPlacementRecord:
	var axis_marker_id: int
	var original_object_id
	var mirrored_object_id

	func _init(axis_id: int, orig_id, mirror_id):
		axis_marker_id = axis_id
		original_object_id = orig_id
		mirrored_object_id = mirror_id

	func undo():
		pass  # TODO: remove both original and mirrored objects

	func redo():
		pass  # TODO: re-place both objects
