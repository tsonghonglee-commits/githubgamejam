extends SceneTree
## Static genuine-material death adapter. No AI, combat, waves or completion.
const Enemy = preload("res://scripts/voxel_enemy.gd")
const Series = preload("res://scripts/series_archetypes.gd")
var checks := 0
var failures: Array[String] = []
var rows: Array = []
var output := ""
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--death-output="): output = arg.trim_prefix("--death-output=")
	call_deferred("_run")
func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)
func _run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	for kind: String in Series.BOSSES:
		var actor = Enemy.new()
		holder.add_child(actor)
		actor.configure(kind,1)
		actor.set_meta("simulation_scale",0.0)
		actor.position.y = 3.0 if kind == "cyber_helicopter" else 0.0
		var removed := PackedInt32Array()
		for index: int in actor._live_indices:
			if int(actor._tags[index])&2: removed.append(index)
		actor._commit_material_cut(removed,Vector2.RIGHT,null,Time.get_ticks_usec())
		expect(actor.dead,kind+" genuine core removal enters dead state")
		var count: int = actor.get_remaining_voxel_count(true)
		var released := 0
		var maximum_ms := 0.0
		for part in [1,2,3,4,5,6,7,8,9,0]:
			var before: int = actor.get_remaining_voxel_count(true)
			var start := Time.get_ticks_usec()
			if actor.release_series_death_part(part): released += 1
			maximum_ms = maxf(maximum_ms,float(Time.get_ticks_usec()-start)/1000.0)
			expect(actor.get_remaining_voxel_count(true) == before,kind+" part %d preserves every remaining cell" % part)
		expect(actor.get_remaining_voxel_count(true) == count,kind+" final death material conserved")
		var fragments := 0
		for piece in actor.get_children():
			if bool(piece.get_meta("voxel_piece",false)) and not piece.is_queued_for_deletion(): fragments += 1
		expect(fragments <= 24,kind+" finite actual debris budget")
		var body_count: int = actor.get_remaining_voxel_count(false)
		expect(body_count == 0 or fragments == 24,kind+" original body sheds or is retained by real budget")
		rows.append({"kind":kind,"remaining_cells":count,"released_parts":released,"body_cells":body_count,"fragments":fragments,"max_isolated_release_ms":maximum_ms})
		actor.queue_free()
		await process_frame
	var result := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"rows":rows,"scope":"Static real core removal then individual actual part releases; conserved occupied material and finite recuttable debris. No actor AI, wave progression, gameplay or whole-frame performance claim."}
	if not output.is_empty():
		var file := FileAccess.open(output,FileAccess.WRITE)
		file.store_string(JSON.stringify(result,"\t"))
	holder.queue_free()
	await process_frame
	await process_frame
	print("DEATH_MATERIAL: ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
