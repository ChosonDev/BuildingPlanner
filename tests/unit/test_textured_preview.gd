extends "res://addons/gut/test.gd"

var root = ProjectSettings.globalize_path("res://").plus_file("..")
var Renderer = load(root.plus_file("scripts/overlay/BuildingPlannerTexturePreview.gd"))
var hover = load("res://unit/test_hover_preview.gd")
var Utils = load(root.plus_file("scripts/utils/BuildingPlannerUtils.gd"))
const SQUARE = [Vector2.ZERO, Vector2(80, 0), Vector2(80, 80), Vector2(0, 80)]

class Assets:
	extends Reference
	var lists = {"Patterns Colorable": [], "Simple Tiles": [], "Wall Ends": []}
	var textures = {}
	var loads = []
	func GetAssetList(category): return lists[category]
	func GetAssetTexture(category, path):
		loads.append([category, path])
		return textures[path]

class PatchedLine:
	extends Line2D
	var loop = false
	var normalize_uv = false
	var Super = false
	var widths = {}
	func set_point_width(index, width): widths[index] = width

class CountingTiles:
	extends TileSet
	var scans = 0
	func get_tiles_ids():
		scans += 1
		return .get_tiles_ids()

func test_uniform_path_preview_needs_no_fallback_width_curve_and_clears_taper():
	var renderer = autofree(Renderer.new())
	var style = settings("PathBuilder")
	var points = []
	for i in range(12): points.append(Vector2(i * 10, 40))
	style.active_grow = true
	renderer.sync_preview({"points": points, "closed": false, "fill": false}, style, true)
	assert_not_null(renderer._line.width_curve)
	style.active_grow = false
	style.active_shrink = false
	renderer.sync_preview({"points": points, "closed": false, "fill": false}, style, true)
	assert_null(renderer._line.width_curve)
	for value in Renderer.path_widths(150, false, false): assert_eq(value, 1.0)

func test_textured_preview_known_colorable_assets_skip_tileset_scans():
	var renderer = autofree(Renderer.new())
	var tiles = CountingTiles.new()
	var tile_map = autofree(TileMap.new())
	tile_map.tile_set = tiles
	var assets = Assets.new()
	var parent = {"Global": {"World": {"Level": {"TileMap": tile_map}}}, "Script": assets}
	for path in ["res://pack/colorable_stone.png", "res://pack/catalog_stone.png"]:
		var texture = checker()
		texture.resource_path = path
		assets.lists["Patterns Colorable"].append(path)
		assert_true(renderer._get_pattern_style(texture, parent).colorable)
	assert_eq(tiles.scans, 0)

func checker() -> ImageTexture:
	var pixels = Image.new()
	pixels.create(8, 8, false, Image.FORMAT_RGBA8)
	pixels.lock()
	for y in range(8):
		for x in range(8):
			pixels.set_pixel(x, y, (Color.red if x < 4 else Color.green) if y < 4 else (Color.blue if x < 4 else Color.yellow))
	pixels.unlock()
	var texture = ImageTexture.new()
	texture.create_from_image(pixels, Texture.FLAG_REPEAT)
	return texture

func settings(name = "PatternFill") -> Dictionary:
	var feature = load(root.plus_file("scripts/features/" + name + ".gd")).new(null, null)
	feature.active_texture = checker()
	return feature.get_settings()

func view_with(renderer):
	var view = autofree(Viewport.new())
	view.size = Vector2(160, 160)
	view.disable_3d = true
	view.world_2d = World2D.new()
	view.transparent_bg = true
	view.render_target_update_mode = Viewport.UPDATE_ALWAYS
	view.add_child(renderer)
	add_child(view)
	return view

func sample(view, point: Vector2) -> Color:
	var image = view.get_texture().get_data()
	image.flip_y()
	image.lock()
	var color = image.get_pixelv(point)
	# Transparent Viewport readback is premultiplied; compare the source RGB separately.
	if color.a > 0:
		color.r /= color.a
		color.g /= color.a
		color.b /= color.a
	image.unlock()
	return color

func test_textured_preview_pattern_tiles_rotates_and_keeps_world_phase_at_zoom():
	var renderer = Renderer.new()
	var view = view_with(renderer)
	var style = settings()
	var flags = style.active_texture.flags
	var preview = {"points": SQUARE, "fill": true, "closed": true}
	renderer.sync_preview(preview, style, false)
	yield(VisualServer, "frame_post_draw")
	yield(VisualServer, "frame_post_draw")
	assert_gt(sample(view, Vector2(2, 2)).r, 0.9)
	assert_gt(sample(view, Vector2(6, 2)).g, 0.9)
	assert_gt(sample(view, Vector2(10, 2)).r, 0.9, "Tiles repeat at texture pixel size, rather than stretching to polygon bounds")
	assert_almost_eq(sample(view, Vector2(2, 2)).a, Renderer.OPACITY, 0.02)
	style.active_rotation = 90.0
	renderer.sync_preview(preview, style, false)
	yield(VisualServer, "frame_post_draw")
	yield(VisualServer, "frame_post_draw")
	assert_gt(sample(view, Vector2(2, 2)).b, 0.9, "Native clockwise normalized UV rotation")
	view.canvas_transform = Transform2D(Vector2(2, 0), Vector2(0, 2), Vector2(20, 25))
	yield(VisualServer, "frame_post_draw")
	yield(VisualServer, "frame_post_draw")
	assert_gt(sample(view, Vector2(25, 30)).b, 0.9, "Camera does not change texture phase")
	assert_eq(style.active_texture.flags, flags, "Never mutate host texture wrapping/filtering")

func test_textured_preview_preserves_holes_and_clears_all_texture_nodes():
	var renderer = Renderer.new()
	var view = view_with(renderer)
	var points = [Vector2.ZERO, Vector2(30, 30), Vector2(30, 70), Vector2(70, 70), Vector2(70, 30), Vector2(30, 30), Vector2.ZERO, Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]
	renderer.sync_preview({"points": points, "closed": true, "fill": true}, settings(), false)
	yield(VisualServer, "frame_post_draw")
	yield(VisualServer, "frame_post_draw")
	assert_almost_eq(sample(view, Vector2(12, 50)).a, Renderer.OPACITY, 0.02)
	assert_eq(sample(view, Vector2(50, 50)).a, 0.0)
	renderer.clear_preview()
	yield(VisualServer, "frame_post_draw")
	yield(VisualServer, "frame_post_draw")
	assert_eq(sample(view, Vector2(12, 50)).a, 0.0)
	for node in renderer.get_children():
		assert_false(node.visible)
		assert_null(node.texture)
	assert_null(renderer._polygon.material)
	assert_true(renderer._polygon.uv.empty())

func test_textured_preview_native_material_is_private_and_catalog_metadata_selects_colorable():
	var renderer = autofree(Renderer.new())
	var source = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = "shader_type canvas_item; uniform sampler2D albedo; uniform float rotation; uniform bool use_wear; uniform sampler2D wear; void fragment(){COLOR *= texture(albedo, UV);}"
	source.shader = shader
	source.set_shader_param("rotation", 0.25)
	renderer._resources["res://materials/PatternCustomColor.material"] = source
	var style = settings()
	style.active_texture.resource_path = "res://pack/tiles/unmarked.png"
	style.active_rotation = 45.0
	var assets = Assets.new()
	assets.lists["Patterns Colorable"] = [style.active_texture.resource_path]
	assets.lists["Simple Tiles"] = [style.active_texture.resource_path]
	var parent = {"Global": {"World": null}, "Script": assets}
	renderer.sync_preview({"points": SQUARE, "fill": true, "closed": true}, style, false, parent)
	assert_ne(renderer._polygon.material, source)
	assert_eq(renderer._polygon.material.get_shader_param("albedo"), style.active_texture)
	assert_almost_eq(renderer._polygon.material.get_shader_param("rotation"), PI / 4.0, 0.00001)
	assert_false(renderer._polygon.material.get_shader_param("use_wear"), "Native LoadShape uses raw textures, not thumbnail keys for wear")
	assert_eq(source.get_shader_param("rotation"), 0.25, "Host material is unchanged")
	var retained = renderer._polygon.material
	style.active_rotation = 90.0
	renderer.sync_preview({"points": SQUARE, "fill": true, "closed": true}, style, false, parent)
	assert_eq(renderer._polygon.material, retained, "Reuse the private material across geometry and style updates")
	assert_almost_eq(retained.get_shader_param("rotation"), PI / 2.0, 0.00001)

func test_textured_preview_wall_width_joints_caps_shadow_and_direction():
	var renderer = autofree(Renderer.new())
	var style = settings("WallBuilder")
	style.active_texture.resource_path = "res://walls/test.png"
	style.active_joint = 1
	style.active_color = Color(0.2, 0.4, 0.8)
	var shadow = checker()
	renderer._resources["res://textures/shadows/wall_shadow_flat.png"] = shadow
	var assets = Assets.new()
	var cap = checker()
	cap.take_over_path("res://walls/test_end.png")
	var parent = {"Global": {"World": null}, "Script": assets}
	var preview = {"points": [Vector2(100, 20), Vector2(20, 20)], "closed": false, "fill": false}
	renderer.sync_preview(preview, style, false, parent)
	assert_eq(renderer._line.width, 8.0)
	assert_eq(renderer._line.joint_mode, Line2D.LINE_JOINT_BEVEL)
	assert_eq(renderer._line.default_color, style.active_color)
	assert_eq_deep(Array(renderer._line.points), preview.points)
	assert_eq(renderer._shadow.width, 16.0)
	assert_eq(renderer._shadow.texture, shadow)
	assert_eq(renderer._caps[0].position, Vector2(100, 20))
	assert_almost_eq(abs(renderer._caps[0].rotation), PI, 0.00001)
	assert_true(renderer._caps[0].flip_h)
	assert_false(renderer._caps[1].flip_h)
	assert_true(renderer._caps[0].visible)
	style.active_shadow = false
	preview.closed = true
	renderer.sync_preview(preview, style, false, parent)
	assert_false(renderer._shadow.visible)
	assert_false(renderer._caps[0].visible)
	assert_eq(renderer._line.points[-1], renderer._line.points[0])
	assert_eq(assets.loads.size(), 0, "The host does not populate a Wall Ends asset catalog")
	assert_eq(renderer._cap_texture, cap)

func test_textured_preview_raw_wall_caps_load_without_import_and_missing_caps_are_safe():
	var renderer = autofree(Renderer.new())
	var style = settings("WallBuilder")
	var path = "user://preview_raw_wall_end.png"
	assert_eq(style.active_texture.get_data().save_png(path), OK)
	style.active_texture.resource_path = "user://preview_raw_wall.png"
	var preview = {"points": [Vector2.ZERO, Vector2(100, 0)], "closed": false, "fill": false}
	assert_false(ResourceLoader.exists(path, "Texture"))
	renderer.sync_preview(preview, style, false)
	assert_true(renderer._cap_texture is ImageTexture)
	assert_eq(renderer._cap_texture.flags, 6)
	assert_eq(renderer._cap_texture.resource_path, path)
	assert_true(renderer._caps[0].visible)
	var cap = renderer._cap_texture
	renderer._cap_key = null
	renderer.sync_preview(preview, style, false)
	assert_eq(renderer._cap_texture, cap, "Raw caps use the native resource cache")
	assert_eq(Directory.new().remove(path), OK)
	style.active_texture = checker()
	style.active_texture.resource_path = "user://preview_missing_wall.png"
	renderer.sync_preview(preview, style, false)
	assert_null(renderer._cap_texture)
	assert_false(renderer._caps[0].visible)
	style.active_texture = checker()
	renderer.sync_preview(preview, style, false)
	assert_null(renderer._cap_texture, "Procedural textures have no sibling cap path")
	assert_false(renderer._caps[0].visible)

func test_textured_preview_path_reuses_gradient_and_resets_fades():
	var renderer = autofree(Renderer.new())
	var style = settings("PathBuilder")
	var preview = {"points": [Vector2.ZERO, Vector2(100, 0)], "closed": false, "fill": false}
	style.active_fade_in = true
	renderer.sync_preview(preview, style, true)
	var gradient = renderer._line.gradient
	assert_eq(gradient.get_color(0).a, 0.0)
	style.active_fade_in = false
	style.active_fade_out = true
	renderer.sync_preview(preview, style, true)
	assert_eq(renderer._line.gradient, gradient)
	assert_eq(gradient.get_color(0), Color.white)
	assert_eq(gradient.get_color(3).a, 0.0)

func test_textured_preview_tileset_material_metadata_and_pattern_border():
	var renderer = autofree(Renderer.new())
	var style = settings()
	style.active_texture.resource_path = "res://tiles/plain_name.png"
	style.active_outline = true
	var tiles = TileSet.new()
	tiles.create_tile(7)
	tiles.tile_set_texture(7, style.active_texture)
	var shader = Shader.new()
	shader.code = "shader_type canvas_item;"
	shader.resource_path = "res://shaders/TilesetCustomColor.shader"
	var material = ShaderMaterial.new()
	material.shader = shader
	tiles.tile_set_material(7, material)
	var tile_map = autofree(TileMap.new())
	tile_map.tile_set = tiles
	var assets = Assets.new()
	assets.lists["Simple Tiles"] = [style.active_texture.resource_path]
	var parent = {"Global": {"World": {"Level": {"TileMap": tile_map}}}, "Script": assets}
	var border = checker()
	renderer._resources["res://textures/borders/default_border.png"] = border
	renderer.sync_preview({"points": SQUARE, "fill": true, "closed": true}, style, false, parent)
	assert_true(renderer._pattern_style.colorable, "Tile metadata is authoritative even without colorable in the filename")
	assert_eq(tiles.tile_get_material(7), material, "Native tileset stays untouched")
	assert_eq(renderer._line.texture, border)
	assert_eq(renderer._line.width, 8.0)
	assert_eq(renderer._line.joint_mode, Line2D.LINE_JOINT_ROUND)
	assert_eq(renderer._line.points[0], renderer._line.points[-1])
	style.active_outline = false
	renderer.sync_preview({"points": SQUARE, "fill": true, "closed": true}, style, false, parent)
	assert_false(renderer._line.visible)

func test_textured_preview_path_renders_texture_width_fade_and_resets_wall_state():
	var renderer = Renderer.new()
	var view = view_with(renderer)
	var style = settings("PathBuilder")
	style.active_width = 2.0
	style.active_fade_in = true
	var preview = {"points": Utils.path_preview_points([Vector2(16, 40), Vector2(112, 40)], false, 0.0), "closed": false, "fill": false}
	renderer.sync_preview(preview, style, true)
	yield(VisualServer, "frame_post_draw")
	yield(VisualServer, "frame_post_draw")
	assert_eq(renderer._line.width, 16.0)
	assert_lt(sample(view, Vector2(17, 40)).a, sample(view, Vector2(64, 40)).a)
	assert_gt(sample(view, Vector2(64, 35)).a, 0.5)
	assert_eq(sample(view, Vector2(64, 28)).a, 0.0)
	assert_ne(sample(view, Vector2(66, 40)), sample(view, Vector2(74, 40)), "Chosen texture is visible along the path")
	assert_eq(renderer._line.gradient.get_color(0), Color(1, 1, 1, 0))
	assert_eq(renderer._line.gradient.get_color(3), Color.white)
	var untinted = sample(view, Vector2(66, 40))
	style.active_color = Color(0.25, 0.5, 0.75, 0.8)
	renderer.sync_preview(preview, style, true)
	yield(VisualServer, "frame_post_draw")
	yield(VisualServer, "frame_post_draw")
	var tinted = sample(view, Vector2(66, 40))
	assert_almost_eq(tinted.r, untinted.r * 0.25, 0.02)
	assert_almost_eq(tinted.g, untinted.g * 0.5, 0.02)
	assert_almost_eq(tinted.b, untinted.b * 0.75, 0.02)
	assert_almost_eq(tinted.a, untinted.a * 0.8, 0.02)
	style.active_fade_in = false
	style.active_fade_out = true
	renderer.sync_preview(preview, style, true)
	assert_eq(renderer._line.gradient.get_color(0), Color.white)
	assert_eq(renderer._line.gradient.get_color(3), Color(1, 1, 1, 0))
	renderer.sync_preview(preview, settings("WallBuilder"), false)
	assert_null(renderer._line.gradient)
	assert_null(renderer._line.width_curve)
	assert_eq(renderer._line.self_modulate, Color.white, "Path tint must not leak into walls or pattern borders")

func test_textured_preview_host_per_point_taper_and_loop_normalization_are_used():
	var renderer = autofree(Renderer.new())
	renderer._line.free()
	renderer._line = PatchedLine.new()
	renderer.add_child(renderer._line)
	for property in renderer._line.get_property_list(): renderer._line_properties[property.name] = true
	var style = settings("PathBuilder")
	style.active_width = 2.0
	style.active_grow = true
	style.active_shrink = true
	var points = []
	for i in range(12): points.append(Vector2(i * 10, 40))
	renderer.sync_preview({"points": points, "closed": true, "fill": false}, style, true)
	assert_true(renderer._line.Super)
	assert_false(renderer._line.loop, "Native paths use explicit smoothed seam, not Loop")
	assert_false(renderer._line.normalize_uv)
	assert_eq(renderer._line.widths[0], 0.0)
	assert_eq(renderer._line.widths[3], 14.0) # 1 - ease(1/4, -2) = 0.875 of width 16.
	assert_eq(renderer._line.widths[6], 16.0)
	assert_eq(renderer._line.widths[11], 0.0)
	style.active_grow = false
	style.active_shrink = false
	renderer.sync_preview({"points": points, "closed": true, "fill": false}, style, true)
	for width in renderer._line.widths.values(): assert_eq(width, 16.0)
	assert_null(renderer._line.width_curve, "Uniform native paths need no fallback Curve")
	var border_style = settings()
	border_style.active_outline = true
	renderer._resources["res://textures/borders/default_border.png"] = checker()
	renderer.sync_preview({"points": SQUARE, "closed": true, "fill": true}, border_style, false)
	assert_false(renderer._line.Super, "Path per-point width mode must not leak into the pattern border")
	assert_true(renderer._line.loop)
	assert_null(renderer._line.width_curve)
	assert_null(renderer._line.gradient)
	assert_eq(renderer._line.width, 8.0)

func test_textured_preview_pattern_cache_does_not_retain_deleted_world_nodes():
	var renderer = autofree(Renderer.new())
	var world_script = GDScript.new()
	world_script.source_code = "extends Node\nvar Level = null\n"
	assert_eq(world_script.reload(), OK)
	var world = world_script.new()
	var parent = {"Global": {"World": world}}
	var texture = checker()
	renderer._get_pattern_style(texture, parent)
	assert_eq(renderer._pattern_key[1], world.get_instance_id())
	world.free()
	parent.Global.World = world_script.new()
	renderer._get_pattern_style(texture, parent)
	assert_eq(renderer._pattern_key[1], parent.Global.World.get_instance_id())
	parent.Global.World.free()

func test_textured_preview_overlay_reuses_nodes_updates_stationary_texture_and_removes_invalid_preview():
	var api = hover.Api.new()
	var target_container = autofree(Node2D.new())
	var world = {"Level": {"PatternShapes": target_container}}
	var feature = load(root.plus_file("scripts/features/PatternFill.gd")).new(api, null, {"Global": {"World": world}})
	feature.active_texture = checker()
	var overlay = autofree(load(root.plus_file("scripts/overlay/BuildingPlannerOverlay.gd")).new())
	overlay.tool = {"_gl_api": api, "cached_world": world, "_active_mode": 1, "cached_worldui": {"MousePosition": Vector2(20, 20)}}
	var f = {"feature": feature, "overlay": overlay, "api": api, "world": world}
	overlay.refresh_preview(1.0, feature, true, false)
	var renderer = f.overlay._texture_preview
	var node_ids = []
	for node in renderer.get_children(): node_ids.append(node.get_instance_id())
	f.feature.active_texture = checker()
	f.feature.active_rotation = 90.0
	overlay.refresh_preview(0.0, feature, true, false)
	assert_eq(renderer._polygon.texture, f.feature.active_texture)
	assert_lt(renderer._polygon.uv[1].distance_to(Vector2(0, -92)), 0.00001)
	for i in range(renderer.get_child_count()): assert_eq(renderer.get_child(i).get_instance_id(), node_ids[i])
	assert_eq(f.api.queries, 1)
	assert_eq(api.noisy_queries, 0)
	for container in f.world.Level.values(): assert_eq(container.get_child_count(), 0)
	f.feature.active_texture = null
	overlay.refresh_preview(0.0, feature, true, false)
	assert_false(renderer.visible)
	f.overlay.clear_preview()
	assert_null(renderer._polygon.texture)
