extends SceneTree
## Fixed blade paths and localized real material damage on isolated bosses.
const Enemy = preload("res://scripts/voxel_enemy.gd")
const Series = preload("res://scripts/series_archetypes.gd")
const Projectiles = preload("res://scripts/projectile_geometry.gd")
const LOCAL_BLAST := 0.36
const REFLECTED_SHOTS := {
	"ink_master":"sword_wave", "cyber_captain":"bolt", "cyber_flanker":"bolt", "cyber_suppressor":"bolt",
	"cyber_spotter":"shock", "cyber_helicopter":"missile", "cyber_tank":"shock", "cyber_gunship":"missile",
	"sea_leviathan":"torpedo", "empire_dreadnought":"plasma_lance",
}
var baseline := false
var output := ""
var failures: Array[String] = []
var camera: Camera3D


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--baseline": baseline = true
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	call_deferred("_run")


func _expect(condition: bool, label: String) -> void:
	if condition: return
	failures.append(label)
	push_error(label)


func _actor(kind: String) -> Node3D:
	var actor := Enemy.new()
	root.add_child(actor)
	actor.position = Vector3(0, 0, -14)
	actor.configure(kind, 1)
	actor.set_process(false)
	actor.set_meta("simulation_scale", 0.0)
	return actor


func _slash(center: Vector3, actor: Node3D, reach: float) -> Dictionary:
	var a := camera.unproject_position(center + Vector3.LEFT * reach)
	var b := camera.unproject_position(center + Vector3.RIGHT * reach)
	return actor.cut_screen(camera, a, b, 2.15)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	camera = Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 1.75, 0)
	camera.current = true
	var records: Array[Dictionary] = []
	var game_script: Script = load("res://scripts/main.gd")
	var blast_radii: Dictionary = game_script.get_script_constant_map().REFLECTED_BLAST_RADII
	# Keep the tool parseable against the old PCK's Series script.
	var builder: Variant = Series
	for kind: String in Series.BOSSES:
		camera.position = Vector3(0, 1.75, 0)
		camera.rotation = Vector3.ZERO
		var actor = _actor(kind)
		var initial: Dictionary = actor.get_series_integrity_state()
		var center: Vector3 = initial.core_world
		var initial_count: int = actor.get_remaining_voxel_count()
		var groups: Array[Dictionary] = actor._connected_components()
		var largest_group := 0
		for group: Dictionary in groups:
			largest_group = maxi(largest_group,group.indices.size())
		var central: Dictionary = actor.blast_at(center, LOCAL_BLAST)
		var after_center: Dictionary = actor.get_series_integrity_state()
		var record := {"kind":kind,"initial_cells":initial_count,"initial_component_count":groups.size(),"unattached_cells":initial_count-largest_group,"old_core_blast":central}
		if not baseline:
			_expect(initial.core_active == [true, true], kind + " starts with two connected physical modules")
			_expect(not initial.support_active.is_empty() and not initial.support_active.has(false), kind + " starts with connected shortcut assemblies")
			_expect(central.removed > 0 and not actor.dead, kind + " survives localized damage at the old single core")
			_expect(after_center.support_active == initial.support_active, kind + " old core shot did not take out a shortcut assembly")
		actor.free()
		actor = _actor(kind)
		var shot: String = REFLECTED_SHOTS[kind]
		var collision_radius: float = Projectiles.get_template(shot).radius
		var contact: Dictionary = actor.trace_projectile(center+Vector3.BACK*20.0,center+Vector3.FORWARD*10.0,collision_radius)
		_expect(bool(contact.hit), kind + " reflected projectile intersects actual facing material")
		var returned_shot: Dictionary = actor.blast_at(contact.get("point",center),blast_radii[shot])
		record["center_returned_shot"] = returned_shot
		if not baseline:
			_expect(not actor.dead, kind + " survives a single straight centered own projectile blast")
		actor.free()
		actor = _actor(kind)
		var line_hits: Array[Dictionary] = []
		for repeat in range(4):
			line_hits.append(_slash(center, actor, 2.1))
			if actor.dead: break
		record["fixed_crosses"] = line_hits
		if not baseline:
			_expect(int(line_hits[0].removed) > 0 and not actor.dead, kind + " survives four fixed center slashes")
			var modules: Array = initial.core_world_points
			var tested: Array[Dictionary] = []
			for first in [0, 1]:
				actor.free()
				actor = _actor(kind)
				var count_before: int = actor.get_remaining_voxel_count()
				var first_hit: Dictionary = actor.blast_at(modules[first], LOCAL_BLAST)
				var active: Array = actor.get_series_integrity_state().core_active
				_expect(first_hit.removed > 0 and not actor.dead and not active[first] and active[1-first], kind + " survives losing just module %d" % first)
				var second_hit: Dictionary = actor.blast_at(modules[1-first], LOCAL_BLAST)
				_expect(second_hit.removed > 0 and second_hit.killed and actor.dead, kind + " dies when the other module is actually destroyed")
				_expect(actor.get_remaining_voxel_count() == count_before - first_hit.removed - second_hit.removed, kind + " conserves material through both breaks")
				tested.append({"first_module":first,"first_hit":first_hit,"core_active_after_first":active,"second_hit":second_hit})
			record["targeted_modules"] = tested
			actor.free()
			actor = _actor(kind)
			var modules_data: Array = builder.boss_modules(kind)
			var blade_steps: Array[int] = []
			for index in range(modules.size()):
				var cuts := 0
				var half_tag: float = float(modules_data[index].tag_size)*0.5+float(actor._cell)
				for pass_index in range(18):
					if not actor.get_series_integrity_state().core_active[index]: break
					camera.position.x = [0.0, -3.3, 3.3][floori(pass_index/6.0)]
					camera.look_at(modules[index])
					for row in [-1.5,-1.0,-0.5,0.0,0.5,1.0,1.5]:
						var result := _slash(modules[index] + Vector3.UP * half_tag * float(row), actor, half_tag * 2.0)
						if result.removed > 0: cuts += 1
						if not actor.get_series_integrity_state().core_active[index]: break
				var active: Array = actor.get_series_integrity_state().core_active
				_expect(cuts > 0 and not active[index], kind + " can sever module %d with real screen cuts" % index)
				_expect(actor.dead == (index == 1), kind + " dies after both blade targets are actually cut")
				blade_steps.append(cuts)
			record["targeted_blade_cuts"] = blade_steps
			actor.free()
			actor = _actor(kind)
			var supports: Array = initial.world_points
			var support_hits: Array[int] = []
			for index in range(supports.size()):
				var hit_count := 0
				for radius in [0.26,0.42,0.58]:
					var result: Dictionary = actor.blast_at(supports[index], radius)
					hit_count += int(result.removed)
					if not actor.get_series_integrity_state().support_active[index]: break
				_expect(hit_count > 0 and not actor.get_series_integrity_state().support_active[index], kind + " physical support %d can still break" % index)
				support_hits.append(hit_count)
			_expect(not actor.dead and actor.get_series_integrity_state().vulnerable, kind + " loses armor supports and stays alive with exposed modules")
			record["support_material_removed"] = support_hits
		records.append(record)
		print(kind, " center blast ", central, " center crosses ", line_hits)
		actor.free()
		await process_frame
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify({"passed":failures.is_empty(),"failures":failures,"bosses":records,"scope":"Isolated production material cuts and fixed-point spheres. No campaign pacing or human difficulty result."}, "\t"))
		else:
			_expect(false, "could not write verification result")
	quit(0 if failures.is_empty() else 1)
