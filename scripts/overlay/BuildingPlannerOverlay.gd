extends Node2D

# BuildingPlanner - Dungeondraft Mod
# Input overlay node. Added to WorldUI so it receives Godot input events
# while the BuildingPlanner tool is the active Dungeondraft tool.
#
# Pattern Fill mode: intercepts left mouse clicks on the world canvas
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

	# ---- Scroll wheel: Room Builder rotation / scale ----
	# Handled before bounds checks (same pattern as GuidesLines MarkerOverlay).
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

	# Ignore clicks outside the map canvas:
	#   x < 450              — left tool panel
	#   y < 100              — top UI bar
	#   y > height - 100     — bottom UI bar
	var mouse_vp = get_viewport().get_mouse_position()
	var viewport_size = get_viewport().size
	if mouse_vp.x < 450:
		return
	if mouse_vp.y < 100 or mouse_vp.y > viewport_size.y - 100:
		return

	if not tool.cached_worldui or not tool.cached_worldui.IsInsideBounds:
		return

	var world_pos: Vector2 = tool.cached_worldui.MousePosition

	# Dispatch to the active mode
	match tool._active_mode:
		tool.Mode.PATTERN_FILL:
			tool.handle_pattern_fill_click(world_pos)
			get_tree().set_input_as_handled()
		tool.Mode.WALL_BUILDER:
			tool.handle_wall_builder_click(world_pos)
			get_tree().set_input_as_handled()
		tool.Mode.PATH_BUILDER:
			tool.handle_path_builder_click(world_pos)
			get_tree().set_input_as_handled()
		tool.Mode.ROOM_BUILDER:
			# Apply grid snap when enabled — same logic as GuidesLines.
			# PatternFill and WallBuilder find shapes by position (compute_fill_polygon),
			# so snapping does not apply there.
			var final_pos = world_pos
			if tool.parent_mod.Global.Editor.IsSnapping:
				final_pos = tool.snap_position_to_grid(world_pos)
			tool.handle_room_builder_click(final_pos)
			get_tree().set_input_as_handled()
		tool.Mode.ROOF_BUILDER:
			tool.handle_roof_builder_click(world_pos)
			get_tree().set_input_as_handled()
