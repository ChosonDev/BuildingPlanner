extends Reference

# BuildingPlanner - Dungeondraft Mod
# MarkerObjectRegistry: stores associations between GuidesLines marker ids
# and the Dungeondraft objects (PatternShape, Wall or Pathway) created for each marker.
# Used by RoomBuilder (Merge mode) to clean up stale fills/walls when a
# marker polygon is updated by a merge operation.

const CLASS_NAME = "MarkerObjectRegistry"
const Utils = preload("../utils/BuildingPlannerUtils.gd")

# ============================================================================
# REFERENCES
# ============================================================================

var LOGGER = null

# ============================================================================
# STORAGE
# ============================================================================

## marker_id -> fills, walls (Wall/Pathway), owning levels and copied feature settings.
var _registry: Dictionary = {}
var generation = 0

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
func register(marker_id: int, fills: Array, walls: Array, levels: Array = [], settings: Dictionary = {}) -> void:
	if marker_id < 0:
		return
	_registry[marker_id] = {
		"fills": fills.duplicate(),
		"walls": walls.duplicate(),
		"levels": levels.duplicate(),
		"settings": settings.duplicate(true)
	}
	if LOGGER:
		LOGGER.info("%s: registered marker %d — fills: %d, walls: %d." % [
			CLASS_NAME, marker_id, fills.size(), walls.size()])

## Remove all DD objects linked to [marker_id] from the scene and clear the entry.
## History must serialize an entry BEFORE cleanup; these nodes are queued for deletion.
func cleanup(marker_id: int, world = null, global_ref = null) -> void:
	if not _registry.has(marker_id):
		return
	var entry: Dictionary = _registry[marker_id]
	for key in ["fills", "walls"]:
		for node in entry[key]:
			Utils.free_node(node, world, global_ref)
	_registry.erase(marker_id)
	if LOGGER:
		LOGGER.info("%s: cleaned up marker %d." % [CLASS_NAME, marker_id])

## Completely wipe the registry without touching the scene.
## Call on map close/unload only — do NOT call on tool deactivation,
## otherwise Merge mode loses its marker→object associations.
func clear() -> void:
	_registry.clear()
	generation += 1
	if LOGGER:
		LOGGER.info("%s: registry cleared." % CLASS_NAME)

## Returns true when [marker_id] has registered objects.
func has_entry(marker_id: int) -> bool:
	return _registry.has(marker_id)

## Copy of the node arrays, or empty arrays if not found.
func get_entry(marker_id: int) -> Dictionary:
	if not _registry.has(marker_id):
		return {"fills": [], "walls": [], "levels": [], "settings": {}}
	var entry = _registry[marker_id]
	return {"fills": entry.fills.duplicate(), "walls": entry.walls.duplicate(), "levels": entry.levels.duplicate(), "settings": entry.settings.duplicate(true)}

## Copy only level ownership when room rebuilding does not need node arrays.
func get_levels(marker_id: int) -> Array:
	return _registry[marker_id].levels.duplicate() if _registry.has(marker_id) else []


func get_settings(marker_id: int) -> Dictionary:
	return _registry[marker_id].settings.duplicate(true) if _registry.has(marker_id) else {}
