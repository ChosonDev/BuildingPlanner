extends Reference

# Independent room style snapshot; map data contains JSON values only.
const CLASS_NAME = "RoomTemplate"
const PANEL_FIELDS = [
	["texture", "color", "rotation", "layer", "outline"],
	["texture", "color", "shadow", "joint", "offset", "reverse_direction"],
	["texture", "color", "width", "offset", "reverse_direction", "smoothness", "layer", "sorting", "fade_in", "fade_out", "grow", "shrink", "block_light"]
]
var name = "Room template"
var sub_mode = 0
var outline_mode = 0
var fill_mode = 0
var tile_style = {"texture": "", "color": Color.white}
var angle = 0.0
var scale = 1.0
var state = {}
var geometry = []
var panels = []
var outlines = []

func save() -> Dictionary:
	var data = {"name": name, "sub_mode": sub_mode, "outline_mode": outline_mode,
		"fill_mode": fill_mode, "tile_style": encode(tile_style),
		"angle": angle, "scale": scale, "state": encode(state),
		"geometry": encode(geometry), "panels": encode(panels)}
	if not outlines.empty():
		data["outlines"] = encode(outlines)
	return data

static func number(value) -> bool:
	return (value is int or value is float) and not is_nan(value) and not is_inf(value)

# No Variant/object deserialization: only explicitly supported JSON value types.
static func encode(value):
	if value is Vector2: return {"$vector": [value.x, value.y]}
	if value is Color: return {"$color": value.to_html()}
	if value is Dictionary:
		var result = {}
		for key in value: result[key] = encode(value[key])
		return result
	if value is Array or value is PoolVector2Array:
		var result = []
		for item in value: result.append(encode(item))
		return result
	return value

static func valid_json(value, depth = 0) -> bool:
	if depth > 16: return false
	if value is Dictionary:
		if value.has("$vector"):
			return value.size() == 1 and value["$vector"] is Array and value["$vector"].size() == 2 and number(value["$vector"][0]) and number(value["$vector"][1])
		if value.has("$color"):
			return value.size() == 1 and value["$color"] is String and value["$color"].length() == 8 and value["$color"].is_valid_hex_number(false)
		for key in value:
			if not key is String or not valid_json(value[key], depth + 1): return false
		return true
	if value is Array:
		for item in value:
			if not valid_json(item, depth + 1): return false
		return true
	return value == null or value is String or value is bool or number(value)

static func decode(value):
	if value is Dictionary:
		if value.has("$vector"): return Vector2(value["$vector"][0], value["$vector"][1])
		if value.has("$color"): return Color(value["$color"])
		var result = {}
		for key in value: result[key] = decode(value[key])
		return result
	if value is Array:
		var result = []
		for item in value: result.append(decode(item))
		return result
	return value

static func _validate_panel_style(style, panel_index: int, default_style: Dictionary) -> bool:
	if not style is Dictionary or style.size() != PANEL_FIELDS[panel_index].size(): return false
	for field in PANEL_FIELDS[panel_index]:
		var value = style.get(field)
		if field == "texture":
			if not value is String: return false
		elif not default_style.has(field): return false
		elif default_style[field] is Color:
			if not value is Color: return false
		elif default_style[field] is bool:
			if not value is bool: return false
		elif not number(value): return false
		elif default_style[field] is int:
			if value != int(value): return false
			style[field] = int(value)
	if panel_index == 1 and (style.joint < 0 or style.joint > 2): return false
	if panel_index == 2 and (style.width <= 0 or style.smoothness < 0 or style.smoothness > 1 or not style.sorting in [0, 1]): return false
	return true

func load_data(data, defaults: Array) -> bool:
	if not data is Dictionary or not valid_json(data): return false
	if not data.get("name") is String or data.name.strip_edges().empty(): return false
	if not number(data.get("sub_mode")) or not data.sub_mode in [0, 1, 2, 3, 4]: return false
	if not number(data.get("outline_mode")) or not data.outline_mode in [0, 1]: return false
	if not data.get("fill_mode", 0) in [0, 1] or data.get("fill_mode", 0) is bool: return false
	var tile_settings = decode(data.get("tile_style", {"texture": "", "color": {"$color": "ffffffff"}}))
	if not tile_settings is Dictionary or tile_settings.size() != 2 or not tile_settings.get("texture") is String or not tile_settings.get("color") is Color: return false
	if not number(data.get("angle")) or not number(data.get("scale")) or data.scale < 0.1: return false
	var source = decode(data.get("state"))
	if not source is Dictionary or not number(source.get("active_shape_radius")) or source.active_shape_radius <= 0: return false
	if not number(source.get("active_shape_angle")) or not number(source.get("active_shape_sides")) or source.active_shape_sides != int(source.active_shape_sides) or source.active_shape_sides < 3 or source.active_shape_sides > 64: return false
	if not source.get("active_color") is Color or not source.get("active_marker_type") in ["Shape", "Template"]: return false
	var batch = decode(data.get("geometry"))
	if not batch is Array or (source.active_marker_type == "Template" and batch.empty()): return false
	for marker in batch:
		if not marker is Dictionary or not marker.get("position") is Vector2 or not marker.get("color") is Color: return false
		if not marker.get("marker_type") in ["Shape", "Line", "Path"]: return false
		var points = marker.get("polygon") if marker.marker_type == "Shape" else marker.get("outline_points")
		if not points is Array or points.size() < (3 if marker.marker_type == "Shape" else 2): return false
		for point in points:
			if not point is Vector2: return false
		if marker.marker_type != "Shape" and not marker.get("closed") is bool: return false
		for key in ["shape_radius", "shape_angle"]:
			if marker.has(key) and not number(marker[key]): return false
		for key in ["polygon", "outline_points", "marker_points"]:
			if marker.has(key):
				if not marker[key] is Array: return false
				for point in marker[key]:
					if not point is Vector2: return false
		if marker.has("shape_primitives"):
			if not marker.shape_primitives is Array: return false
			for segment in marker.shape_primitives:
				if not segment is Dictionary or not segment.get("a") is Vector2 or not segment.get("b") is Vector2 or segment.get("type", "seg") != "seg": return false
	var styles = decode(data.get("panels"))
	if not styles is Array or styles.size() != 3: return false
	for i in range(3):
		if not _validate_panel_style(styles[i], i, defaults[i]): return false
	var loaded_outlines = []
	if data.has("outlines"):
		var raw_outlines = decode(data.get("outlines"))
		if not raw_outlines is Array or raw_outlines.empty(): return false
		for item in raw_outlines:
			if not item is Dictionary or item.size() != 3: return false
			if not item.get("name") is String or item.name.strip_edges().empty(): return false
			var mode = item.get("mode")
			if mode is bool or not number(mode) or not mode in [0, 1]: return false
			var panel_index = 1 if int(mode) == 0 else 2
			if not _validate_panel_style(item.get("settings"), panel_index, defaults[panel_index]): return false
			loaded_outlines.append({"name": item.name.strip_edges(), "mode": int(mode), "settings": item.settings})
	else:
		var legacy_mode = int(data.outline_mode)
		loaded_outlines.append({
			"name": "Wall Default" if legacy_mode == 0 else "Path 1",
			"mode": legacy_mode,
			"settings": styles[1 if legacy_mode == 0 else 2].duplicate(true),
		})
	name = data.name.strip_edges()
	sub_mode = int(data.sub_mode)
	outline_mode = int(data.outline_mode)
	fill_mode = int(data.get("fill_mode", 0))
	tile_style = tile_settings
	angle = data.angle
	scale = data.scale
	state = source
	state.active_shape_sides = int(state.active_shape_sides)
	geometry = batch
	panels = styles
	outlines = loaded_outlines
	return true

func transformed_geometry(coords: Vector2, rotation: float, factor: float) -> Array:
	var batch = geometry.duplicate(true)
	for marker in batch:
		marker.position = coords + marker.position.rotated(deg2rad(rotation)) * factor
		for key in ["polygon", "outline_points", "marker_points"]:
			if marker.has(key):
				for i in range(marker[key].size()): marker[key][i] = coords + marker[key][i].rotated(deg2rad(rotation)) * factor
		if marker.has("shape_primitives"):
			for segment in marker.shape_primitives:
				segment.a = coords + segment.a.rotated(deg2rad(rotation)) * factor
				segment.b = coords + segment.b.rotated(deg2rad(rotation)) * factor
		if marker.has("shape_radius"): marker.shape_radius *= factor
		if marker.has("shape_angle"): marker.shape_angle += rotation
	return batch
