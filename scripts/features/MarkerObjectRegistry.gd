extends Reference

# BuildingPlanner - Dungeondraft Mod
# MarkerObjectRegistry: stores associations between GuidesLines marker ids
# and the Dungeondraft objects (PatternShapes, Wall) created for each marker.
# Used by RoomBuilder (Merge mode) to clean up stale fills/walls when a
# marker polygon is updated by a merge operation.

const CLASS_NAME = "MarkerObjectRegistry"

# ============================================================================
# REFERENCES
# ============================================================================

var LOGGER = null

# ============================================================================
# STORAGE
# ============================================================================

## { marker_id: int -> { "fills": Array[PatternShape], "walls": Array[Wall] } }
var _registry: Dictionary = {}

# ============================================================================
# INIT
# ============================================================================

func _init(logger):
	LOGGER = logger

# ============================================================================
# PUBLIC API
# ============================================================================

## Store the fills and walls created for [marker_id].
## Safe to call multiple times — later call overwrites the previous entry.
func register(marker_id: int, fills: Array, walls: Array) -> void:
	if marker_id < 0:
		return
	_registry[marker_id] = {
		"fills": fills.duplicate(),
		"walls": walls.duplicate()
	}
	if LOGGER:
		LOGGER.info("%s: registered marker %d — fills: %d, walls: %d." % [
			CLASS_NAME, marker_id, fills.size(), walls.size()])

## Remove all DD objects linked to [marker_id] from the scene and clear the entry.
## Returns a snapshot { "fills": [...], "walls": [...] } for History undo support.
func cleanup(marker_id: int) -> Dictionary:
	var snapshot: Dictionary = { "fills": [], "walls": [] }
	if not _registry.has(marker_id):
		return snapshot

	var entry: Dictionary = _registry[marker_id]

	for fill in entry["fills"]:
		if fill != null and is_instance_valid(fill):
			_free_node(fill)
			snapshot["fills"].append(fill)

	for wall in entry["walls"]:
		if wall != null and is_instance_valid(wall):
			_free_node(wall)
			snapshot["walls"].append(wall)

	_registry.erase(marker_id)

	if LOGGER:
		LOGGER.info("%s: cleaned up marker %d — removed fills: %d, walls: %d." % [
			CLASS_NAME, marker_id,
			snapshot["fills"].size(), snapshot["walls"].size()])

	return snapshot

## Completely wipe the registry without touching the scene.
## Call on tool deactivation / map close.
func clear() -> void:
	_registry.clear()
	if LOGGER:
		LOGGER.info("%s: registry cleared." % CLASS_NAME)

## Returns true when [marker_id] has registered objects.
func has_entry(marker_id: int) -> bool:
	return _registry.has(marker_id)

## Read-only snapshot of the entry, or empty dicts if not found.
func get_entry(marker_id: int) -> Dictionary:
	return _registry.get(marker_id, { "fills": [], "walls": [] })

# ============================================================================
# PRIVATE — NODE REMOVAL
# ============================================================================

## Removes [node] from its parent and frees it.
## Mirrors BuildingPlannerHistory._free_node().
static func _free_node(node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var p = node.get_parent()
	if p:
		p.remove_child(node)
	node.queue_free()
