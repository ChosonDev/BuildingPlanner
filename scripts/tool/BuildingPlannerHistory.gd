extends Reference

# BuildingPlanner - Dungeondraft Mod
# Undo/redo history record classes for all BuildingPlanner actions.
#
# Usage in feature scripts:
#   const BuildingPlannerHistory = preload("../tool/BuildingPlannerHistory.gd")
#   BuildingPlannerHistory.record_action(parent_mod, logger, record)
#
# All records implement the HistoryApi contract:
#   undo()        — removes the created objects from the scene
#   redo()        — restores them from serialised data
#   dropped(type) — called by HistoryApi when record leaves the stack:
#                   type UNDO → evicted while objects remain in the scene
#                   type REDO → invalidated after undo (objects already freed)
#                   Both release record-owned data without deleting live nodes.
#   record_type() → String key used by HistoryApi for max_count grouping

const CLASS_NAME = "BuildingPlannerHistory"
const Utils = preload("../utils/BuildingPlannerUtils.gd")

static func record_action(parent_mod, logger, action) -> void:
	var api = parent_mod.Global.API if parent_mod else null
	if api and api.has("HistoryApi"):
		api.HistoryApi.record(action, 100)
	elif logger:
		logger.warn("BuildingPlanner: HistoryApi not available — action will not be undoable.")

# Single native objects share ownership, map guards and snapshot lifetime.
# Kind-specific loading keeps native IDs, path tint and roof lighting semantics.
class NativeObjectRecord:
	var _parent_mod
	var _world
	var _level
	var _node
	var _data
	var _index
	var _color
	var _kind

	func _init(parent_mod, node, kind):
		assert(is_instance_valid(node), "History requires a live native object.")
		_parent_mod = parent_mod
		_world = parent_mod.Global.World
		_level = _world.Level
		_node = node
		# C# optional arguments are not supplied by GDScript; keep native IDs.
		_data = (node.Save() if kind == "WallBuilder" else node.Save(false)).duplicate(true)
		_index = node.get_index()
		_color = node.modulate
		_kind = kind

	func undo():
		if Utils.is_current_world(_parent_mod, _world, _level):
			Utils.free_node(_node, _world, _parent_mod.Global)
			_node = null

	func redo():
		if not Utils.is_current_world(_parent_mod, _world, _level):
			return
		match _kind:
			"WallBuilder":
				_node = Utils.load_wall(_level.Walls, _data)
			"PatternFill":
				_node = _level.PatternShapes.LoadShape(_data.duplicate(true))
			"PathBuilder":
				_node = Utils.load_path(_parent_mod.Global, _level.Pathways, _data.duplicate(true), _color)
			"RoofBuilder":
				_node = Utils.get_roofs(_level).LoadRoof(_data.duplicate(true))
		if is_instance_valid(_node):
			Utils.restore_order(_node, _index)
		elif _parent_mod.get("LOGGER"):
			_parent_mod.LOGGER.error("%s: failed to restore native object; snapshot retained." % record_type())

	func dropped(_direction):
		_node = null
		_data.clear()
		_color = null

	func record_type():
		return "BuildingPlanner." + _kind

## One click owns all boundaries, while native records retain IDs, tint and order.
class OutlineGroupRecord:
	var _records
	func _init(records):
		_records = records
	func undo():
		for i in range(_records.size() - 1, -1, -1): _records[i].undo()
	func redo():
		for record in _records: record.redo()
		# Under-sorted paths are inserted at index zero; restore final sibling order.
		for i in range(_records.size() - 1, -1, -1):
			var record = _records[i]
			if Utils.is_current_world(record._parent_mod, record._world, record._level):
				Utils.restore_order(record._node, record._index)
	func dropped(direction):
		for record in _records: record.dropped(direction)
	func record_type():
		return _records[0].record_type()

class WallBuilderRecord:
	extends NativeObjectRecord
	func _init(parent_mod, wall).(parent_mod, wall, "WallBuilder"):
		pass

class PatternFillRecord:
	extends NativeObjectRecord
	func _init(parent_mod, shape).(parent_mod, shape, "PatternFill"):
		pass

class PathBuilderRecord:
	extends NativeObjectRecord
	func _init(parent_mod, path).(parent_mod, path, "PathBuilder"):
		pass

# Roof lighting belongs to the whole level and is replayed with the native roof.
class RoofBuilderRecord:
	extends NativeObjectRecord
	var LOGGER
	var _sunlight_before = null
	var _sunlight_after = null

	func _init(parent_mod, logger, roof, sunlight_before = null).(parent_mod, roof, "RoofBuilder"):
		LOGGER = logger
		_sunlight_before = sunlight_before
		if sunlight_before != null:
			var roofs = Utils.get_roofs(_level)
			_sunlight_after = [roofs.Shade, roofs.SunDirection, roofs.ShadeContrast]

	func undo():
		if not Utils.is_current_world(_parent_mod, _world, _level):
			return
		.undo()
		if _sunlight_before != null:
			var roofs = Utils.get_roofs(_level)
			if roofs:
				roofs.UpdateSunlight(_sunlight_before[0], _sunlight_before[1], _sunlight_before[2])

	func redo():
		if not Utils.is_current_world(_parent_mod, _world, _level):
			return
		var roofs = Utils.get_roofs(_level)
		if not roofs:
			if LOGGER: LOGGER.error("RoofBuilderRecord: Roofs node not found.")
			return
		if _sunlight_after != null:
			roofs.UpdateSunlight(_sunlight_after[0], _sunlight_after[1], _sunlight_after[2])
		.redo()

	func dropped(direction):
		.dropped(direction)
		_sunlight_before = null
		_sunlight_after = null

# A room action owns marker edits and only the registry entries it touches.
# Entries are serialized before cleanup; undo/redo resolve current registry nodes,
# since a later boolean action may already have replaced the original instances.
class RoomBuilderRecord:
	var _parent_mod
	var _registry
	var _world
	var _level
	var _generation
	var _before = {}
	var _after = {}
	var _marker_records = []
	var _loose = {"fills": [], "walls": []}
	var _loose_data = {}
	var _pending_order = []
	var _levels = []

	func _init(parent_mod, registry):
		_parent_mod = parent_mod
		_registry = registry
		_world = parent_mod.Global.World
		_level = _world.Level
		_generation = registry.generation

	func remember(marker_id):
		if not _before.has(marker_id):
			_before[marker_id] = _save_entry(_registry.get_entry(marker_id))

	func finish(records):
		_marker_records = records
		for id in _before:
			_after[id] = _save_entry(_registry.get_entry(id))
		_loose_data = _save_entry(_loose)

	func _save_entry(entry):
		var saved = {"fills": [], "walls": []}
		var levels = entry.get("levels", [])
		for key in saved:
			for node in entry[key]:
				if is_instance_valid(node):
					var owner_level = null
					for level in levels if not levels.empty() else [_level]:
						var container = level.PatternShapes if key == "fills" else (level.Pathways if node.has_method("SetEditPoints") else level.Walls)
						if container.is_a_parent_of(node):
							owner_level = level
							break
					assert(owner_level != null, "RoomBuilderRecord: native object has no matching owner level.")
					if not owner_level in _levels:
						_levels.append(owner_level)
					var is_path = key == "walls" and node.has_method("SetEditPoints")
					var data = node.Save() if key == "walls" and not is_path else node.Save(false)
					saved[key].append({"data": data.duplicate(true),
						"level": owner_level,
						"index": node.get_index(),
						"color": node.modulate,
						"path": is_path})
		saved["settings"] = entry.get("settings", {}) # Takes ownership of the detached registry snapshot.
		return saved

	func _clear_current():
		for id in _before:
			_registry.cleanup(id, _world, _parent_mod.Global)
		for key in _loose:
			for node in _loose[key]:
				Utils.free_node(node, _world, _parent_mod.Global)
		_loose = {"fills": [], "walls": []}

	func _restore_entry(saved):
		var entry = {"fills": [], "walls": []}
		for key in entry:
			for item in saved.get(key, []):
				var node = null
				var level = item.level
				if key == "fills":
					node = level.PatternShapes.LoadShape(item.data.duplicate(true))
				elif item.path:
					node = Utils.load_path(_parent_mod.Global, level.Pathways, item.data.duplicate(true), item.color)
				else:
					node = Utils.load_wall(level.Walls, item.data)
				if is_instance_valid(node):
					_pending_order.append({"node": node, "index": item.index})
					entry[key].append(node)
				elif _parent_mod.get("LOGGER"):
					_parent_mod.LOGGER.error("RoomBuilderRecord: could not restore saved %s object; serialized data retained." % key)
		return entry

	func _restore(entries):
		for id in entries:
			var saved = entries[id]
			var entry = _restore_entry(saved)
			if not entry.fills.empty() or not entry.walls.empty():
				var levels = []
				for key in ["fills", "walls"]:
					for item in saved[key]:
						if not item.level in levels:
							levels.append(item.level)
				_registry.register(id, entry.fills, entry.walls, levels, saved.get("settings", {}))
		_apply_order()

	func _order_less(a, b):
		return a.index < b.index

	func _apply_order():
		_pending_order.sort_custom(self, "_order_less")
		for item in _pending_order:
			Utils.restore_order(item.node, item.index)
		_pending_order.clear()

	func undo():
		if not _is_current():
			return
		_clear_current()
		for i in range(_marker_records.size() - 1, -1, -1):
			_marker_records[i].undo()
		_restore(_before)

	func redo():
		if not _is_current():
			return
		_clear_current()
		for record in _marker_records:
			record.redo()
		_restore(_after)
		_loose = _restore_entry(_loose_data)
		_apply_order()

	func _is_current():
		if _registry.generation != _generation or not Utils.is_current_world(_parent_mod, _world, _level):
			return false
		for level in _levels:
			if not Utils.is_valid_obj(level):
				return false
		return true

	func has_changes():
		return not _marker_records.empty() or not _before.empty() or not _loose.fills.empty() or not _loose.walls.empty()

	func dropped(direction):
		for record in _marker_records:
			if record.has_method("dropped"):
				record.dropped(direction)
		_marker_records.clear()
		_before.clear()
		_after.clear()
		_loose.clear()
		_loose_data.clear()
		_levels.clear()

	func record_type():
		return "BuildingPlanner.RoomBuilder"

