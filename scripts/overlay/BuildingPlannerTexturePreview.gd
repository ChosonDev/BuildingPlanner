extends Node2D

# Retained UI-only texture drawing. Never instantiate native map objects or call their Load/Set methods.
const CLASS_NAME = "BuildingPlannerTexturePreview"
const OPACITY = 0.6
var _polygon = null
var _line = null
var _shadow = null
var _caps = []
var _contour_previews = []
var _resources = {}
var _line_properties = {}
var _path_normalize_uv = false
var _asset_lists = {}
var _pattern_key = []
var _pattern_style = {}
var _cap_key = null
var _cap_texture = null
var _pattern_materials = {}
var _path_gradient = Gradient.new()

func _init():
	_path_gradient.offsets = PoolRealArray([0.0, 0.1, 0.9, 1.0])
	show_behind_parent = true
	modulate = Color(1, 1, 1, OPACITY)
	_polygon = Polygon2D.new()
	add_child(_polygon)
	_shadow = Line2D.new()
	add_child(_shadow)
	_line = Line2D.new()
	add_child(_line)
	for _i in range(2):
		var cap = Sprite.new()
		add_child(cap)
		_caps.append(cap)
	for property in _line.get_property_list():
		_line_properties[property.name] = true
	if _line_properties.has("normalize_uv"):
		_path_normalize_uv = _line.get("normalize_uv")
	clear_preview()

func clear_preview() -> void:
	hide()
	for renderer in _contour_previews: renderer.clear_preview()
	_polygon.hide()
	_polygon.texture = null
	_polygon.material = null
	_polygon.uv = PoolVector2Array()
	for line in [_line, _shadow]:
		line.hide()
		line.texture = null
		line.material = null
	for cap in _caps:
		cap.hide()
		cap.texture = null
		cap.material = null

## Cache only built-in resources. Asset textures stay owned by the existing host cache.
func _resource(path: String):
	if not _resources.has(path):
		_resources[path] = ResourceLoader.load(path) if ResourceLoader.exists(path) else null
	return _resources[path]

func sync_preview(preview: Dictionary, settings: Dictionary, path: bool, parent_mod = null) -> void:
	clear_preview()
	var points = preview.get("points", [])
	var texture = settings.get("active_texture")
	if points.size() < 2 or not texture is Texture or texture.get_width() <= 0 or texture.get_height() <= 0 or preview.get("reason", "") != "":
		return
	if preview.fill:
		_draw_pattern(points, settings, parent_mod)
	else:
		_draw_outline(points, preview.closed, settings, path, parent_mod)
		var contours = preview.get("contours", [points])
		for i in range(1, contours.size()):
			if _contour_previews.size() < i:
				var renderer = get_script().new()
				renderer.modulate = Color.white # Parent already supplies preview opacity.
				renderer._resources = _resources
				add_child(renderer)
				_contour_previews.append(renderer)
			var contour_preview = preview.duplicate()
			contour_preview.erase("contours")
			contour_preview.points = contours[i]
			_contour_previews[i - 1].sync_preview(contour_preview, settings, path, parent_mod)
	show()

func _draw_pattern(points: Array, settings: Dictionary, parent_mod) -> void:
	var texture = settings.active_texture
	var options = _get_pattern_style(texture, parent_mod)
	var name = "PatternCustomColor" if options.colorable else "Pattern"
	var source = _resource("res://materials/" + name + ".material")
	_polygon.polygon = PoolVector2Array(points)
	_polygon.color = settings.active_color
	if source is ShaderMaterial:
		# Per-preview parameters must never touch the shared host material.
		if not _pattern_materials.has(name):
			_pattern_materials[name] = source.duplicate()
		var material = _pattern_materials[name]
		material.set_shader_param("albedo", texture)
		material.set_shader_param("rotation", deg2rad(settings.active_rotation))
		# LoadShape receives raw texture paths, not Simple Tiles thumbnail keys used by the native wear branch.
		material.set_shader_param("use_wear", false)
		_polygon.material = material
	else:
		# ponytail: stock Godot lacks host materials; UV fallback supports standalone render checks.
		_polygon.texture = texture
		_polygon.uv = pattern_uv(points, texture.get_size(), deg2rad(settings.active_rotation))
	_polygon.show()
	if settings.active_outline:
		var border = _resource("res://textures/borders/default_border.png")
		if border is Texture:
			_set_line(_line, points, true, border, border.get_height(), Color.white, Line2D.LINE_JOINT_ROUND, false)

## Native PatternShape samples world-space vertices divided by the texture size,
## then rotates normalized UV clockwise around (0.5, 0.5).
static func pattern_uv(points: Array, size: Vector2, angle: float) -> PoolVector2Array:
	var uv = PoolVector2Array()
	for point in points:
		var p = point / size - Vector2(0.5, 0.5)
		uv.append((Vector2(cos(angle) * p.x + sin(angle) * p.y, cos(angle) * p.y - sin(angle) * p.x) + Vector2(0.5, 0.5)) * size)
	return uv

func _get_pattern_style(texture: Texture, parent_mod) -> Dictionary:
	var world = parent_mod.Global.World if parent_mod else null
	var level = world.Level if world else null
	var tile_map = level.get("TileMap") if level else null
	var tiles = tile_map.get("tile_set") if is_instance_valid(tile_map) else null
	var key = [texture, world.get_instance_id() if world is Object and is_instance_valid(world) else null, tiles]
	if key == _pattern_key:
		return _pattern_style
	var path = texture.resource_path
	var colorable = "colorable" in path
	var script = parent_mod.get("Script") if parent_mod else null
	if is_instance_valid(script) and script.has_method("GetAssetList"):
		if not _asset_lists.has("Patterns Colorable"):
			_asset_lists["Patterns Colorable"] = script.GetAssetList("Patterns Colorable")
		colorable = colorable or path in _asset_lists["Patterns Colorable"]
	if not colorable and tiles is TileSet:
		for id in tiles.get_tiles_ids():
			var tile_texture = tiles.tile_get_texture(id)
			if tile_texture != texture and (path == "" or tile_texture == null or tile_texture.resource_path != path):
				continue
			var material = tiles.tile_get_material(id)
			colorable = colorable or (material is ShaderMaterial and material.shader != null and "CustomColor" in material.shader.resource_path)
			break
	_pattern_key = key
	_pattern_style = {"colorable": colorable}
	return _pattern_style

func _set_line(line: Line2D, points: Array, closed: bool, texture: Texture, width: float, color: Color, joint: int, normalize: bool) -> void:
	for property in ["super", "Super"]:
		if _line_properties.has(property):
			line.set(property, false)
	var vertices = points.duplicate()
	if _line_properties.has("loop"):
		line.set("loop", closed)
	elif closed and vertices[-1] != vertices[0]:
		# ponytail: stock Godot has no Loop; the host uses its native closed-line join.
		vertices.append(vertices[0])
	if _line_properties.has("normalize_uv"):
		line.set("normalize_uv", normalize)
	line.points = PoolVector2Array(vertices)
	line.texture = texture
	line.texture_mode = Line2D.LINE_TEXTURE_TILE
	line.width = width
	line.default_color = color
	line.self_modulate = Color.white
	line.joint_mode = joint
	line.begin_cap_mode = Line2D.LINE_CAP_NONE
	line.end_cap_mode = Line2D.LINE_CAP_NONE
	line.antialiased = false
	line.gradient = null
	line.width_curve = null
	line.show()

func _draw_outline(points: Array, closed: bool, settings: Dictionary, path: bool, parent_mod) -> void:
	var texture = settings.active_texture
	var color = settings.active_color
	var width = texture.get_height() * (settings.active_width if path else 1.0)
	var joint = Line2D.LINE_JOINT_SHARP if path else settings.active_joint
	_set_line(_line, points, closed, texture, width, Color.white if path else color, joint, _path_normalize_uv if path else true)
	for property in ["super", "Super"]:
		if _line_properties.has(property):
			_line.set(property, path)
	if path:
		# A Gradient overrides default_color. Native PathBuilder applies tint on the CanvasItem.
		_line.self_modulate = color
		_path_gradient.set_color(0, Color(1, 1, 1, 0) if settings.active_fade_in else Color.white)
		_path_gradient.set_color(3, Color(1, 1, 1, 0) if settings.active_fade_out else Color.white)
		_line.gradient = _path_gradient
		if not settings.active_grow and not settings.active_shrink:
			# Reset retained native taper widths; stock Line2D already uses its uniform width.
			if _line.has_method("set_point_width"):
				for i in range(points.size()): _line.call("set_point_width", i, width)
			return
		var widths = path_widths(points.size(), settings.active_grow, settings.active_shrink)
		if _line.has_method("set_point_width"):
			for i in range(widths.size()):
				_line.call("set_point_width", i, width * widths[i])
		else:
			# ponytail: stock Godot render checks use a Curve; Dungeondraft uses per-point widths above.
			var curve = Curve.new()
			var length = 0.0
			for i in range(1, points.size()): length += points[i - 1].distance_to(points[i])
			var travel = 0.0
			for i in range(points.size()):
				if i > 0: travel += points[i - 1].distance_to(points[i])
				curve.add_point(Vector2(travel / length if length > 0 else float(i) / (points.size() - 1), widths[i]))
			_line.width_curve = curve
		return
	var material = _resource("res://materials/Wall.material")
	_line.material = material
	if settings.active_shadow:
		var shadow = _resource("res://textures/shadows/wall_shadow_flat.png")
		if shadow is Texture:
			_set_line(_shadow, points, closed, shadow, width * 2.0, Color.white, joint, true)
			_shadow.material = material
	if not closed:
		var cap_path = texture.resource_path.get_basename() + "_end." + texture.resource_path.get_extension()
		if _cap_key != texture:
			_cap_key = texture
			_cap_texture = null
			if texture.resource_path == "":
				pass # Procedural textures have no sibling end-cap asset.
			elif ResourceLoader.has_cached(cap_path) or ResourceLoader.exists(cap_path, "Texture"):
				_cap_texture = ResourceLoader.load(cap_path, "Texture", false) as Texture
			elif File.new().file_exists(cap_path):
				var image = Image.new()
				if image.load(cap_path) == OK:
					_cap_texture = ImageTexture.new()
					_cap_texture.create_from_image(image, 6) # Native Wall repeat/filter flags.
					_cap_texture.take_over_path(cap_path)
		for i in range(2):
			_caps[i].texture = _cap_texture
			_caps[i].position = points[0] if i == 0 else points[-1]
			_caps[i].rotation = (points[1] - points[0]).angle() if i == 0 else (points[-1] - points[-2]).angle()
			_caps[i].flip_h = i == 0
			_caps[i].self_modulate = color
			_caps[i].material = material
			_caps[i].visible = _cap_texture != null

## Match Pathway.GrowShrinkEnds: point-count based ease, independent of arc length.
static func path_widths(count: int, grow: bool, shrink: bool) -> PoolRealArray:
	var widths = PoolRealArray()
	widths.resize(count)
	for i in range(count): widths[i] = 1.0
	if not grow and not shrink: return widths
	var distance = int(count / 3) if count < 100 else 50
	for i in range(1, distance + 1):
		var width = 1.0 - ease(float(i) / distance, -2.0)
		if grow: widths[distance - i] = width
		if shrink: widths[count - distance + i - 1] = width
	return widths
