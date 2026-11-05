extends Node2D

# BuildingPlanner - Dungeondraft Mod
# Input overlay node. Added to WorldUI so it receives Godot input events
# while the BuildingPlanner tool is the active Dungeondraft tool.
#
# Intercepts left mouse clicks on the world canvas for all builder modes
# and forwards the world-space click position to BuildingPlannerTool.

# Injected by BuildingPlannerTool after instantiation
var tool = null

# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	set_process_input(true)

# ============================================================================
# INPUT
# ============================================================================

func _input(event: InputEvent) -> void:
	if not tool or not tool.is_enabled:
		return

	if not (event is InputEventMouseButton):
		return

	# Skip if any Dungeondraft window/popup is currently open.
	# _input fires before Control._gui_input, so is_input_handled() is not yet set —
	# we must check visible windows explicitly.
	var editor = tool.parent_mod.Global.Editor
	for window in editor.Windows.values():
		if window.visible:
			return

	# Skip if Ctrl is held — reserved for camera zoom.
	if event.control:
		return

	# Canvas input must not consume Control scrolling in the sidebar.
	if not tool.is_mouse_on_canvas():
		return

	# ---- Scroll wheel: Room Builder rotation / scale ----
	if tool._active_mode == tool.Mode.ROOM_BUILDER and event.pressed:
		var direction = 0
		if event.button_index == BUTTON_WHEEL_UP:
			direction = 1
		elif event.button_index == BUTTON_WHEEL_DOWN:
			direction = -1
		if direction != 0:
			tool.handle_room_scroll(direction, event.alt)
			get_tree().set_input_as_handled()
			return

	# ---- Left click — apply canvas boundary guards ----
	if event.button_index != BUTTON_LEFT or not event.pressed:
		return

	var world_pos: Vector2 = tool.cached_worldui.MousePosition

	if tool.handle_canvas_click(world_pos):
		get_tree().set_input_as_handled()
