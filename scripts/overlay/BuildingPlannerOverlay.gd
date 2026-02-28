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

	if event.button_index != BUTTON_LEFT or not event.pressed:
		return

	# Ignore clicks outside the map canvas (e.g. over the left tool panel)
	var mouse_vp = get_viewport().get_mouse_position()
	if mouse_vp.x < 450:
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
