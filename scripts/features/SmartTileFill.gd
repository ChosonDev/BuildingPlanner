extends Reference

# BuildingPlanner - Dungeondraft Mod
# Shared native floor placement and material settings.
const CLASS_NAME = "SmartTileFill"
const Utils = preload("../utils/BuildingPlannerUtils.gd")
const History = preload("../tool/BuildingPlannerHistory.gd")

var _gl_api = null
var LOGGER = null
var _parent_mod = null
var active_texture = null
var active_color: Color = Color.white
var active_erase = false
var _trace_path = "user://buildingplanner-smart-tiles.log"
var _trace_enabled = false
var _tile_set_ref = null
var _tile_ids = {}
var _tile_ids_valid = false
var _history_ref = null
var _preview_revision = 0

func _init(gl_api, logger, parent_mod = null):
	_gl_api = gl_api
	LOGGER = logger
	_parent_mod = parent_mod

func build_at(coords: Vector2) -> bool:
	_trace("Begin fill")
	if not is_instance_valid(_gl_api) or not _gl_api.has_method("is_ready") or not _gl_api.is_ready(): return false
	var polygon = Utils.resolve_fill_polygon(_gl_api, coords, LOGGER)
	if polygon.size() < 3: return false
	var record = create_floor(polygon, null, get_style(), active_erase)
	if record == null: return false
	History.record_action(_parent_mod, LOGGER, record)
	_trace("Fill completed")
	return true

# Map objects and IDs are deliberately absent from saved room styles.
func get_style() -> Dictionary:
	return {"active_texture": active_texture, "active_color": active_color}

func preflight(level = null, settings = null, snapshot_context = null) -> Dictionary:
	level = Utils.resolve_level(_parent_mod, level)
	if level == null: return {}
	if settings == null: settings = get_style()
	var global = _parent_mod.Global
	var editor = global.Editor
	if not is_instance_valid(editor) or not is_instance_valid(editor.owner) or editor.owner.get("IsBusy") != false: return {}
	if not global.API or not global.API.has("HistoryApi"): return {}
	var floor_shapes = level.get("FloorShapes")
	var tilemap = level.get("TileMap")
	var host_tool = editor.Tools.get("FloorShapeTool")
	if not is_instance_valid(floor_shapes) or not is_instance_valid(tilemap) or not is_instance_valid(host_tool) or not tilemap.tile_set: return {}
	# ModScript.AddVariables does not inject Global.Theme. Use the native control's
	# inherited theme; calling get_icon on a missing Variant can crash release hosts.
	var controls = host_tool.get("Controls")
	var wall_menu = controls.get("WallTexture") if controls is Dictionary else null
	if not wall_menu is Control or not wall_menu.has_icon("NullMin", "Icons"):
		_trace("Rejected: native no-wall icon is unavailable")
		if LOGGER: LOGGER.error("Smart Tiles: native no-wall icon is unavailable; no changes made.")
		return {}
	var no_wall_texture = wall_menu.get_icon("NullMin", "Icons")
	if not no_wall_texture is Texture: return {}
	# Cell tint is an engine extension, exposed in snake_case to GDScript.
	if not tilemap.has_method("get_cell_color") or not tilemap.has_method("set_cell_color"):
		if LOGGER: LOGGER.error("Smart Tiles: native cell color API is unavailable.")
		return {}
	if not settings.get("active_texture") is Texture or not settings.get("active_color") is Color: return {}
	for channel in [settings.active_color.r, settings.active_color.g, settings.active_color.b, settings.active_color.a]:
		if is_nan(channel) or is_inf(channel) or channel < 0.0 or channel > 1.0: return {}
	for axis in [tilemap.cell_size.x, tilemap.cell_size.y]:
		if is_nan(axis) or is_inf(axis) or axis <= 0: return {}
	var tile_id = _resolve_tile_id(tilemap.tile_set, settings.active_texture)
	if tile_id == -1: return {}
	var saved_floor = snapshot_context.before if snapshot_context != null else floor_shapes.Save()
	if not saved_floor is Dictionary:
		_trace("Rejected: invalid native floor snapshot")
		return {}
	# Native Save creates a detached dictionary; callers duplicate only when
	# creating independently mutable ownership/history snapshots.
	var before = saved_floor
	# ponytail: existing automatic walls need native WallRecord/portal replay;
	# refuse those levels until a shared room-floor transaction supports it.
	if not before.get("walls", []).empty():
		if LOGGER: LOGGER.warn("Smart Tiles: levels with automatic building walls are not supported yet.")
		return {}
	return {"level": level, "floor": floor_shapes, "tiles": tilemap, "tool": host_tool,
		"no_wall": no_wall_texture, "tile_id": tile_id, "before": before}

func polygon_bounds(polygon: Array, tilemap):
	if polygon.size() < 3 or not polygon[0] is Vector2: return null
	var world = _parent_mod.Global.World
	var world_size = Vector2(world.Width, world.Height) * tilemap.cell_size
	var bounds = Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		if not point is Vector2 or is_nan(point.x) or is_inf(point.x) or is_nan(point.y) or is_inf(point.y): return null
		if point.x < 0 or point.y < 0 or point.x > world_size.x or point.y > world_size.y: return null
		bounds = bounds.expand(point)
	return bounds if abs(Utils.signed_area(polygon)) >= 0.001 else null

# Caller owns the returned record, including when used by a compound operation.
func create_floor(polygon: Array, level = null, settings = null, invert = false):
	if settings == null: settings = get_style()
	_trace("Before floor snapshot")
	var context = preflight(level, settings)
	if context.empty(): return null
	var tilemap = context.tiles
	var floor_shapes = context.floor
	var host_tool = context.tool
	var bounds = polygon_bounds(polygon, tilemap)
	if bounds == null: return null
	var start = tilemap.world_to_map(bounds.position)
	# FloorTileMap.UpdateRect uses ceil at the end; GetRect uses floor instead.
	var end = Vector2(ceil(bounds.end.x / tilemap.cell_size.x), ceil(bounds.end.y / tilemap.cell_size.y))
	_trace("Before cell snapshot")
	var record = History.SmartTileFillRecord.new(_parent_mod, context.level, start, end, context.before)
	var previous = [host_tool.SmartTileId, host_tool.WallTexture, floor_shapes.SuppressHistory]
	host_tool.SmartTileId = context.tile_id
	host_tool.WallTexture = context.no_wall
	# UpdateRect has Rect2 and TileRect C# overloads. Let the native entry point
	# select its overload internally instead of dispatching it from GDScript.
	floor_shapes.SuppressHistory = true
	_trace("Before native DrawPolygon")
	floor_shapes.DrawPolygon(PoolVector2Array(polygon), invert)
	_trace("Native DrawPolygon returned")
	floor_shapes.SuppressHistory = previous[2]
	host_tool.SmartTileId = previous[0]
	host_tool.WallTexture = previous[1]
	if not invert:
		for y in range(int(start.y), int(end.y)):
			for x in range(int(start.x), int(end.x)):
				if tilemap.get_cell(x, y) != -1: tilemap.set_cell_color(x, y, settings.active_color)
	record.finish()
	return record

# Flush each checkpoint before entering native code so a process crash leaves
# the last completed stage even when the console and host logging are disabled.
func _trace(stage: String) -> void:
	if not _trace_enabled: return
	var message = "SmartTileFill: " + stage
	print(message)
	var file = File.new()
	var mode = File.READ_WRITE if stage != "Begin fill" and file.file_exists(_trace_path) else File.WRITE
	if file.open(_trace_path, mode) != OK: return
	file.seek_end()
	file.store_line(message)
	file.close()

func get_settings() -> Dictionary:
	_sync_preview_history()
	var level = Utils.resolve_level(_parent_mod)
	var tilemap = level.get("TileMap") if level else null
	var tile_id = _resolve_tile_id(tilemap.tile_set, active_texture) if is_instance_valid(tilemap) and tilemap.tile_set else -1
	return {"active_texture": active_texture, "active_color": active_color,
		"smart_tile_id": tile_id, "smart_tilemap": tilemap, "erase": active_erase,
		"smart_tile_revision": _preview_revision}

func _invalidate_tile_ids():
	_tile_ids_valid = false
	_preview_revision += 1

func _invalidate_preview(_record = null):
	_preview_revision += 1

func _sync_preview_history():
	var api = _parent_mod.Global.API if _parent_mod else null
	var history = api.HistoryApi if api and api.has("HistoryApi") else null
	var previous = _history_ref.get_ref() if _history_ref != null else null
	if previous == history: return
	for event in ["recorded", "undo_end", "redo_end"]:
		if is_instance_valid(previous) and previous.is_connected(event, self, "_invalidate_preview"):
			previous.disconnect(event, self, "_invalidate_preview")
		if is_instance_valid(history) and history.has_signal(event):
			history.connect(event, self, "_invalidate_preview")
	_history_ref = weakref(history) if is_instance_valid(history) else null
	_preview_revision += 1

func _resolve_tile_id(tiles: TileSet, texture) -> int:
	if not texture is Texture: return -1
	var previous = _tile_set_ref.get_ref() if _tile_set_ref != null else null
	if previous != tiles:
		if previous and previous.is_connected("changed", self, "_invalidate_tile_ids"):
			previous.disconnect("changed", self, "_invalidate_tile_ids")
		_tile_set_ref = weakref(tiles)
		tiles.connect("changed", self, "_invalidate_tile_ids")
		_invalidate_tile_ids()
	if not _tile_ids_valid:
		_tile_ids.clear()
		for id in tiles.get_tiles_ids():
			var asset = tiles.tile_get_texture(id)
			if not asset: continue
			var instance_id = asset.get_instance_id()
			if not _tile_ids.has(instance_id): _tile_ids[instance_id] = id
			if asset.resource_path != "" and not _tile_ids.has(asset.resource_path): _tile_ids[asset.resource_path] = id
		_tile_ids_valid = true
	return _tile_ids.get(texture.get_instance_id(), _tile_ids.get(texture.resource_path, -1))
