extends SceneTree
## Structural fixture only: real occupied cells, connectivity, finite narrow
## screen cuts and retained debris. No native visual/performance acceptance.

var camera: Camera3D
var enemy_script
var output_path := ""
var checks: Array = []
var observations: Array = []
var failures := 0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output_path = argument.trim_prefix("--output=")
	if output_path.is_empty(): output_path = ProjectSettings.globalize_path("res://builds/obstacle-upgrade/verify.json")
	call_deferred("_run")


func expect(condition: bool, label: String, detail: Dictionary = {}) -> void:
	checks.append({"label":label,"passed":condition,"detail":detail})
	if condition: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)


func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _actor(kind: String, variant: int, lane: int = 1):
	var actor = enemy_script.new()
	root.add_child(actor)
	actor.configure(kind,lane,variant)
	actor.position = Vector3(0,-0.055,-9.0)
	actor.set_action("run",0.0)
	return actor


func _flags(groups: Array) -> Array:
	var flags: Array = []
	for group in groups: flags.append({"flags":group.flags,"cells":group.indices.size()})
	return flags


func _run() -> void:
	root.size = Vector2i(1280,720)
	camera = Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0,1.80,0)
	camera.fov = 76.0
	camera.current = true
	enemy_script = load("res://scripts/voxel_enemy.gd")
	# Prewarming every variant must not accidentally reuse a neighbouring
	# variant's voxel, tag or mesh template through the old kind-only key.
	enemy_script.prewarm_models(["barrier","beam"])
	await process_frame
	var distinct: Dictionary = {}
	for kind in ["barrier","beam"]:
		for variant in range(3):
			var label: String = "%s/%d" % [kind,variant]
			var actor = _actor(kind,variant)
			var cell_count: int = actor.get_remaining_voxel_count()
			var mask_hash := _hash(actor._voxels)
			var tags_hash := _hash(actor._tags)
			var groups: Array = actor._connected_components()
			var debug: Dictionary = actor.get_construct_debug_state()
			var all_flagged := groups.size() == 1 and int(groups[0].flags) == 7
			expect(all_flagged,label+" initially forms one actual anchor/core/hazard component",{"components":_flags(groups)})
			expect(cell_count >= 1000 and cell_count <= 3600,label+" bounded real material budget",{"cells":cell_count})
			expect(not distinct.has(mask_hash),label+" has a distinct real silhouette")
			distinct[mask_hash] = true
			var clone = _actor(kind,variant)
			expect(mask_hash == _hash(clone._voxels) and tags_hash == _hash(clone._tags),label+" cached template reproduces private occupancy and tags")
			var changed_index: int = actor._live_indices[0]
			var original: int = clone._voxels[changed_index]
			actor._voxels[changed_index] = 0
			expect(int(clone._voxels[changed_index]) == original and original != 0,label+" template instances never share mutable occupancy")
			actor.free()
			clone.free()
			await process_frame
			actor = _actor(kind,variant)
			# A shallow scrape across a side bracket removes actual material,
			# without rewarding a structural kill for merely touching the object.
			var scrape_local := Vector3(-1.60,2.40,0) if kind == "barrier" else (Vector3(-2.52,2.64,0) if variant == 1 else Vector3(-2.52,0.36 if variant == 0 else 0.66,0))
			var scrape: Vector2 = camera.unproject_position(actor.to_global(scrape_local))
			var scrape_offset_y := 0.0 if kind == "barrier" else -6.0
			var scrape_result: Dictionary = actor.cut_path(camera,PackedVector2Array([scrape+Vector2(-12,scrape_offset_y),scrape+Vector2(12,scrape_offset_y)]),1.0)
			expect(int(scrape_result.removed)>0 and not actor.dead,label+" shallow outer-bracket contact is damage rather than instant death",{"removed":scrape_result.removed,"alive":not actor.dead})
			actor.free()
			await process_frame
			actor = _actor(kind,variant)
			var initial: int = actor.get_remaining_voxel_count()
			var sever_calls: Array = [0]
			actor.severed.connect(func(_enemy,_point,_removed): sever_calls[0] += 1)
			var aim: Vector2 = camera.unproject_position(actor.get_aim_point())
			# One finite, narrow vertical line through the exposed coupling.
			# No rect/sweep fill, HP change, fake detachment or direct voxel erase.
			var result: Dictionary = actor.cut_path(camera,PackedVector2Array([aim+Vector2(0,-45),aim+Vector2(0,45)]),1.0)
			var removed: int = result.removed
			var retained: int = actor.get_remaining_voxel_count()
			expect(removed>0 and actor.dead and bool(result.killed) and sever_calls[0]==1,label+" exposed coupling is genuinely cut through",{"removed":removed,"retained":retained,"severs":sever_calls[0]})
			expect(retained == initial-removed,label+" every uncut cell remains in real debris",{"before":initial,"removed":removed,"retained":retained})
			var recut := 0
			var pieces := 0
			for piece in actor.get_children():
				if not piece.get_meta("voxel_piece",false) or piece.is_queued_for_deletion(): continue
				pieces += 1
				if recut > 0: continue
				var bounds: Rect2 = piece.get_screen_bounds(camera)
				var mid: float = bounds.get_center().y
				var second: Dictionary = actor.cut_path(camera,PackedVector2Array([Vector2(bounds.position.x-4,mid),Vector2(bounds.end.x+4,mid)]),1.0)
				recut += int(second.removed)
			expect(pieces >= 2 and recut > 0 and sever_calls[0] == 1,label+" separated halves can be recut without a second sever",{"pieces":pieces,"recut":recut,"severs":sever_calls[0]})
			observations.append({"kind":kind,"variant":variant,"name":debug.name,"template_key":debug.template_key,"cell_count":cell_count,"occupancy_sha256":mask_hash,"tags_sha256":tags_hash,"central_cut_removed":removed,"central_cut_retained":retained,"recut_removed":recut,"pieces":pieces})
			actor.free()
			await process_frame
		# Existing two-argument spawns are deterministic and cover all variants.
		var selected: Dictionary = {}
		for lane in range(4):
			var actor = _actor(kind,-1,lane)
			selected[actor.construct_variant] = true
			expect(actor.construct_variant==posmod(lane-1,3),"%s lane%d selects a deterministic form" % [kind,lane])
			actor.free()
		expect(selected.size()==3,kind+" normal lane spawns expose all three forms")
	camera.free()
	await process_frame
	var report := {"version":ProjectSettings.get_setting("application/config/version"),"engine":Engine.get_version_info().string,"failures":failures,"checks":checks,"observations":observations,"tool_sha256":FileAccess.get_sha256(get_script().resource_path),"scope":"Headless structural fixture using production voxel/mesh/connectivity/cut/debris. Not normal difficulty, native appearance, wall-clock performance or user feel approval."}
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var file := FileAccess.open(output_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("OBSTACLE UPGRADE: ",checks.size()," checks / ",failures," failures")
	quit(0 if failures==0 else 1)
