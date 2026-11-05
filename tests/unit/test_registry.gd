extends "res://addons/gut/test.gd"

var Registry = ResourceLoader.load(ProjectSettings.globalize_path("res://").plus_file("../scripts/features/MarkerObjectRegistry.gd"))


class WorldLookup:
	extends Reference
	var nodes = {}
	func HasNodeID(id):
		return nodes.has(id)
	func GetNodeByID(id):
		return nodes.get(id)
	func RemoveNodeID(id):
		nodes.erase(id)


class PathNode:
	extends Node
	func SetEditPoints(_points):
		pass


func test_cleanup_removes_only_owned_world_ids_and_entry_snapshots_do_not_alias():
	var registry = Registry.new(null)
	var world = WorldLookup.new()
	var owned = PathNode.new()
	var stale = PathNode.new()
	var replacement = autofree(Node.new())
	owned.set_meta("node_id", 4)
	stale.set_meta("node_id", 5)
	world.nodes = {4: owned, 5: replacement}
	registry.register(1, [owned], [stale])
	var snapshot = registry.get_entry(1)
	snapshot.fills.clear()
	assert_eq(registry.get_entry(1).fills.size(), 1)
	var global_ref = {"ModMapData": {"UchideshiNodeData": {"data": {"node-id-4": {}, "node-id-5": {"keep": true}, "node-id-99": {"keep": true}}}}}
	registry.cleanup(1, world, global_ref)
	assert_false(world.HasNodeID(4))
	assert_true(world.GetNodeByID(5) == replacement, "Never unregister another node that reused the ID")
	assert_false(global_ref.ModMapData.UchideshiNodeData.data.has("node-id-4"))
	assert_eq_deep(global_ref.ModMapData.UchideshiNodeData.data["node-id-5"], {"keep": true})
	assert_true(global_ref.ModMapData.UchideshiNodeData.data.has("node-id-99"))
	yield(get_tree(), "idle_frame")
	assert_false(is_instance_valid(owned))
	assert_false(is_instance_valid(stale))


func test_registration_copies_input_arrays_and_replaces_entries():
	var registry = Registry.new(null)
	var fill = autofree(Node.new())
	var wall = autofree(Node.new())
	var fills = [fill]
	registry.register(-1, fills, [wall])
	assert_false(registry.has_entry(-1))
	registry.register(0, fills, [wall])
	fills.clear()
	assert_eq_deep(registry.get_entry(0), {"fills": [fill], "walls": [wall], "levels": [], "settings": {}})
	registry.register(0, [], [wall])
	assert_eq_deep(registry.get_entry(0), {"fills": [], "walls": [wall], "levels": [], "settings": {}})
	assert_eq_deep(registry.get_entry(99), {"fills": [], "walls": [], "levels": [], "settings": {}})


func test_cleanup_detaches_owned_objects_skips_invalid_nodes_and_erases_entry():
	var registry = Registry.new(null)
	var parent = autofree(Node.new())
	var fill = Node.new()
	var wall = Node.new()
	var stale = Node.new()
	stale.free()
	parent.add_child(fill)
	parent.add_child(wall)
	registry.register(8, [null, stale, fill], [wall])
	registry.cleanup(8)
	assert_eq(parent.get_child_count(), 0)
	assert_true(fill.is_queued_for_deletion())
	assert_true(wall.is_queued_for_deletion())
	assert_false(registry.has_entry(8))
	registry.cleanup(8) # Repeated cleanup is harmless.
	yield(get_tree(), "idle_frame")
	assert_false(is_instance_valid(fill))
	assert_false(is_instance_valid(wall))


func test_clear_forgets_associations_without_removing_scene_nodes():
	var registry = Registry.new(null)
	var parent = autofree(Node.new())
	var fill = Node.new()
	parent.add_child(fill)
	registry.register(1, [fill], [])
	registry.clear()
	assert_false(registry.has_entry(1))
	assert_eq(fill.get_parent(), parent)
	assert_false(fill.is_queued_for_deletion())

func test_level_only_snapshot_does_not_alias_registry_storage():
	var script = load(ProjectSettings.globalize_path("res://").plus_file("../scripts/features/MarkerObjectRegistry.gd"))
	var registry = script.new(null)
	var level = Reference.new()
	registry.register(1, [], [], [level])
	var levels = registry.get_levels(1)
	assert_eq_deep(levels, [level])
	levels.clear()
	assert_eq_deep(registry.get_levels(1), [level])
	assert_true(registry.get_levels(99).empty())


func test_settings_snapshots_isolate_dictionaries_but_share_texture_resources():
	var registry = Registry.new(null)
	var texture = GradientTexture.new()
	var settings = {"fill": {"active_texture": texture, "active_rotation": 20.0}}
	registry.register(1, [], [], [], settings)
	settings.fill.active_rotation = 40.0
	var entry = registry.get_entry(1)
	assert_eq(entry.settings.fill.active_rotation, 20.0)
	assert_eq(entry.settings.fill.active_texture.get_instance_id(), texture.get_instance_id())
	entry.settings.fill.active_rotation = 90.0
	var copy = registry.get_settings(1)
	assert_eq(copy.fill.active_rotation, 20.0)
	assert_eq(copy.fill.active_texture.get_instance_id(), texture.get_instance_id())
