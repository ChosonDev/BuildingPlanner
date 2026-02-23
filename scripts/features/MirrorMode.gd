extends Reference

# BuildingPlanner - Dungeondraft Mod
# MirrorMode: intercepts object placement and duplicates objects mirrored
# across the axis defined by a selected Line marker.
# TODO: implement

const CLASS_NAME = "MirrorMode"

# ============================================================================
# REFERENCES
# ============================================================================

var _gl_api = null
var LOGGER = null

# ============================================================================
# STATE
# ============================================================================

var _active: bool = false

# ============================================================================
# INIT
# ============================================================================

func _init(gl_api, logger):
	_gl_api = gl_api
	LOGGER = logger

# ============================================================================
# ACTIVATION
# ============================================================================

## Activates mirror mode using Line marker [marker_id] as the axis.
## Returns true on success.
func activate(marker_id: int) -> bool:
	if LOGGER: LOGGER.warn("%s: activate() not implemented yet." % CLASS_NAME)
	return false

func deactivate():
	_active = false

func is_active() -> bool:
	return _active
