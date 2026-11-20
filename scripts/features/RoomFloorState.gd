extends Reference

# Room-owned contributions to a level's shared native floor.
# ponytail: recomposition scans all owned cells/contours on an affected level;
# use affected-region deltas if large room sessions make placement expensive.
const CLASS_NAME = "RoomFloorState"
const History = preload("../tool/BuildingPlannerHistory.gd")
const Utils = preload("../utils/BuildingPlannerUtils.gd")
var levels = {}
var _fill
var _next_loose_id = -1
var _contexts = {}

func _init(fill):
	_fill = fill

func allocate_id() -> int:
	var id = _next_loose_id
	_next_loose_id -= 1
	return id

func clear():
	levels.clear()
	_contexts.clear()

func reset_contexts():
	_contexts.clear()

func remove(id: int):
	for level in levels: levels[level].rooms.erase(id)

func stage(id: int, polygon: Array, level, settings: Dictionary) -> bool:
	var context = _fill.preflight(level, settings, _contexts.get(level))
	if context.empty() or _fill.polygon_bounds(polygon, context.tiles) == null: return false
	_contexts[level] = context
	if not levels.has(level):
		levels[level] = {"base_floor": context.before.duplicate(true), "base_cells": {},
			"expected_floor": context.before.duplicate(true), "expected_cells": [], "rooms": {}, "style": settings.duplicate(true)}
	levels[level].rooms[id] = {"polygon": polygon.duplicate(), "style": settings.duplicate(true)}
	return true

func _rebase_external_edits(state, context, previous_rooms: Dictionary) -> bool:
	# ponytail: rebase disjoint native contours; changes to contours shared with
	# owned rooms need region-aware ownership and are rejected instead of guessed.
	var removed = []
	var added = []
	for polygon in state.expected_floor.polygons:
		if not polygon in context.before.polygons: removed.append(polygon)
	for polygon in context.before.polygons:
		if not polygon in state.expected_floor.polygons: added.append(polygon)
	for polygon in removed:
		if not polygon in state.base_floor.polygons: return false
	for polygon in removed + added:
		var points = str2var(polygon) # Native FloorShapes.Save strings, not mod input.
		if not points is PoolVector2Array or points.size() < 3: return false
		for room in previous_rooms.values():
			for fragment in Geometry.intersect_polygons_2d(points, PoolVector2Array(room.polygon)):
				if abs(Utils.signed_area(fragment)) > 0.001: return false
	for cell in state.expected_cells:
		var id = context.tiles.get_cell(cell[0], cell[1])
		var color = context.tiles.get_cell_color(cell[0], cell[1])
		if id == cell[2] and color == cell[3]: continue
		var coords = Vector2(cell[0], cell[1])
		for room in previous_rooms.values():
			if overlaps_cell(room.polygon, coords, context.tiles): return false
		state.base_cells[coords] = [id, color]
	for polygon in removed: state.base_floor.polygons.erase(polygon)
	for polygon in added: state.base_floor.polygons.append(polygon)
	return true

func _same_rooms(current: Dictionary, previous: Dictionary) -> bool:
	if current.size() != previous.size(): return false
	for id in current:
		if not previous.has(id): return false
		var a = current[id]
		var b = previous[id]
		if a.polygon != b.polygon or a.style.active_texture != b.style.active_texture or a.style.active_color != b.style.active_color: return false
	return true

# Preflight every affected level/material before the first native mutation.
func commit(operation) -> bool:
	var plans = []
	for level in levels:
		var state = levels[level]
		var previous = operation._floor_before.get(level, {})
		if _same_rooms(state.rooms, previous.get("rooms", {})): continue
		var context = _fill.preflight(level, state.style)
		if context.empty(): return false
		if not _rebase_external_edits(state, context, previous.get("rooms", {})):
			if _fill.LOGGER: _fill.LOGGER.error("Room Builder: native floor changed outside room history; placement cancelled to preserve it. Reopen the map to start new floor ownership.")
			return false
		var rooms = []
		for id in state.rooms:
			var room = state.rooms[id]
			var brush = _fill.preflight(level, room.style, context)
			if brush.empty(): return false
			var bounds = _fill.polygon_bounds(room.polygon, context.tiles)
			if bounds == null: return false
			rooms.append({"polygon": room.polygon, "bounds": bounds, "style": room.style, "tile_id": brush.tile_id})
			var start = context.tiles.world_to_map(bounds.position)
			var end = Vector2(ceil(bounds.end.x / context.tiles.cell_size.x), ceil(bounds.end.y / context.tiles.cell_size.y))
			for y in range(int(start.y), int(end.y)):
				for x in range(int(start.x), int(end.x)):
					var cell = Vector2(x, y)
					if not state.base_cells.has(cell): state.base_cells[cell] = [context.tiles.get_cell(x, y), context.tiles.get_cell_color(x, y)]
		if state.base_cells.empty(): continue
		plans.append({"context": context, "state": state, "rooms": rooms, "cells": state.base_cells.keys()})
	for plan in plans:
		var context = plan.context
		var state = plan.state
		var record = History.SmartTileFillRecord.new(_fill._parent_mod, context.level, Vector2.ZERO, Vector2.ZERO, context.before, plan.cells)
		operation._floor_records.append(record)
		# Rebuild native contours with native clipping, but paint the target level
		# directly: FloorTileMap.UpdateRect reads the globally active World.Level.
		context.floor.Restore(state.base_floor.duplicate(true))
		for cell in state.base_cells:
			context.tiles.set_cellv(cell, state.base_cells[cell][0])
			context.tiles.set_cell_color(int(cell.x), int(cell.y), state.base_cells[cell][1])
		var wall_texture = context.tool.WallTexture
		context.tool.WallTexture = context.no_wall
		for room in plan.rooms:
			context.floor.AddPolygon(PoolVector2Array(room.polygon), room.bounds, false)
			var packed_polygon = PoolVector2Array(room.polygon)
			var start = context.tiles.world_to_map(room.bounds.position)
			var end = Vector2(ceil(room.bounds.end.x / context.tiles.cell_size.x), ceil(room.bounds.end.y / context.tiles.cell_size.y))
			for y in range(int(start.y), int(end.y)):
				for x in range(int(start.x), int(end.x)):
					if overlaps_cell(packed_polygon, Vector2(x, y), context.tiles):
						context.tiles.set_cell(x, y, room.tile_id)
						context.tiles.set_cell_color(x, y, room.style.active_color)
		context.tool.WallTexture = wall_texture
		for cell in state.base_cells: context.tiles.update_bitmask_area(cell)
		record.finish()
		state.expected_floor = record._after.floor.duplicate(true)
		state.expected_cells = record._after.cells.duplicate(true)
	return true

static func overlaps_cell(polygon, cell: Vector2, tilemap) -> bool:
	var p = tilemap.map_to_world(cell) + Vector2(0.5, 0.5)
	var size = tilemap.cell_size - Vector2.ONE
	var rect = PoolVector2Array([p, p + Vector2(size.x, 0), p + size, p + Vector2(0, size.y)])
	for fragment in Geometry.intersect_polygons_2d(polygon if polygon is PoolVector2Array else PoolVector2Array(polygon), rect):
		if abs(Utils.signed_area(fragment)) > 0.001: return true
	return false
