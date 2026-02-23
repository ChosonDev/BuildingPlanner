extends Reference

# BuildingPlanner - Dungeondraft Mod
# WallBuilder: places walls along the outline of a Shape or Path marker.
# TODO: implement

const CLASS_NAME = "WallBuilder"

# ============================================================================
# REFERENCES
# ============================================================================

var _gl_api = null
var LOGGER = null

# ============================================================================
# INIT
# ============================================================================

func _init(gl_api, logger):
	_gl_api = gl_api
	LOGGER = logger

# ============================================================================
# BUILD
# ============================================================================

## Places walls along the outline of marker [marker_id].
## Returns an Array of created Wall nodes on success, or [] on failure.
func build(marker_id: int, wall_node) -> Array:
	if LOGGER: LOGGER.warn("%s: build() not implemented yet." % CLASS_NAME)
	return []
