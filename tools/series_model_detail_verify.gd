extends SceneTree
## Pure occupied-grid checks; no scene, mesh, action update, AI or battle.
const Enemy = preload("res://scripts/voxel_enemy.gd")
const Builder = preload("res://scripts/series_archetypes.gd")
const Detail = preload("res://scripts/series_model_detail.gd")
var failures := 0
var checks := 0
var records: Array[Dictionary] = []
var output_path := "res://.local/series-model-detail.json"


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--detail-output="): output_path = argument.trim_prefix("--detail-output=")
	create_timer(60.0).timeout.connect(_deadline)
	call_deferred("_run")


func _deadline() -> void:
	push_error("Material-only verification did not complete; refusing a partial result")
	quit(1)


func _expect(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(label)


func _groups(e) -> Array[Dictionary]:
	var seen := PackedByteArray()
	seen.resize(e._voxels.size())
	var result: Array[Dictionary] = []
	var row: int = e._dimensions.x
	var plane: int = row*e._dimensions.y
	for seed_index in range(e._voxels.size()):
		if e._voxels[seed_index] == 0 or seen[seed_index] != 0: continue
		var queue: Array[int] = [seed_index]
		seen[seed_index] = 1
		var head := 0
		var flags := 0
		while head < queue.size():
			var index := queue[head]
			head += 1
			flags |= int(e._tags[index])
			var x := index%row
			var y := int(index/row)%int(e._dimensions.y)
			var z := int(index/plane)
			var next: Array[int] = []
			if x+1<row: next.append(index+1)
			if x>0: next.append(index-1)
			if y+1<e._dimensions.y: next.append(index+row)
			if y>0: next.append(index-row)
			if z+1<e._dimensions.z: next.append(index+plane)
			if z>0: next.append(index-plane)
			for neighbor in next:
				if seen[neighbor] or e._voxels[neighbor] == 0: continue
				seen[neighbor] = 1
				queue.append(neighbor)
		result.append({"count":queue.size(),"flags":flags,"indices":queue})
	return result


func _run() -> void:
	for kind: String in Detail.CYBER_HUMANOIDS+Detail.EMPIRE_INFANTRY:
		var e = Enemy.new()
		e.enemy_kind = kind
		e._set_model_dimensions(kind)
		var total: int = e._dimensions.x*e._dimensions.y*e._dimensions.z
		e._voxels.resize(total)
		e._tags.resize(total)
		e._series_authored_parts.resize(total)
		if kind.begins_with("cyber_"): Builder._build_cyber(e)
		else: Builder._build_empire(e)
		var before: PackedByteArray = e._voxels.duplicate()
		var tags: PackedByteArray = e._tags.duplicate()
		var parts: PackedByteArray = e._series_authored_parts.duplicate()
		var before_groups := _groups(e)
		Detail.refine(e,Builder)
		var changed := 0
		var added := 0
		var removed := 0
		var tags_ok: bool = tags == e._tags
		var muzzle_ok := true
		var parts_ok := true
		var local_neighbors_ok := true
		var material_ok := true
		for index in range(total):
			if before[index] != e._voxels[index]: changed += 1
			if before[index] == 0 and e._voxels[index] != 0: added += 1
			if before[index] != 0 and e._voxels[index] == 0: removed += 1
			if before[index] != 0 and e._voxels[index] != 0: parts_ok = parts_ok and parts[index] == e._series_authored_parts[index]
			material_ok = material_ok and int(e._voxels[index]) <= 10 and int(e._series_authored_parts[index]) <= 9
			if tags[index] != 0:
				tags_ok = tags_ok and before[index] == e._voxels[index] and parts[index] == e._series_authored_parts[index]
				var c: Vector3i = e._coords(index)
				# Independent Manhattan-radius oracle, rather than replaying the
				# production frontier walk that protects two six-neighbor layers.
				for dz in range(-2,3):
					for dy in range(-2,3):
						for dx in range(-2,3):
							if absi(dx)+absi(dy)+absi(dz)>2 or not e._inside(c+Vector3i(dx,dy,dz)): continue
							var n: int = e._index(c.x+dx,c.y+dy,c.z+dz)
							local_neighbors_ok = local_neighbors_ok and before[n] == e._voxels[n] and parts[n] == e._series_authored_parts[n]
		for emitter: Dictionary in Builder.emitters(kind):
			var radius := float(emitter.get("radius",0.24))+float(e._cell)*2.0
			for index in range(total):
				var c: Vector3i = e._coords(index)
				if Vector3(e._point(c.x,c.y,c.z)).distance_squared_to(Vector3(emitter.point)) <= radius*radius:
					muzzle_ok = muzzle_ok and before[index] == e._voxels[index] and parts[index] == e._series_authored_parts[index]
		_expect(changed > 0 and added > 0 and removed > 0,kind+" actual shape changes")
		_expect(tags_ok and local_neighbors_ok,kind+" critical labels and nearby material remain exact")
		_expect(muzzle_ok,kind+" real emitter regions remain exact")
		_expect(parts_ok and material_ok,kind+" original part ownership and valid palette remain")
		var groups := _groups(e)
		_expect(groups.size() == 1 and int(groups[0].flags)&7 == 7,kind+" one real connected actor")
		var loose: Array = []
		if groups.size()>1:
			for group in groups:
				var low := Vector3.INF
				var high := -Vector3.INF
				for index: int in group.indices:
					var coords: Vector3i = e._coords(index)
					var point: Vector3 = e._point(coords.x,coords.y,coords.z)
					low = low.min(point)
					high = high.max(point)
				loose.append({"count":group.count,"low":low,"high":high,"flags":group.flags})
		records.append({"kind":kind,"added":added,"removed":removed,"changed":changed,"groups_before":before_groups.size(),"groups_after":groups.size(),"loose":loose})
		e.free()
	var result := {"scope":"pure occupied-grid builder refinement, no actors in tree/mesh/actions/AI/battle","checks":checks,"failures":failures,"records":records,"source":{"detail":FileAccess.get_sha256("res://scripts/series_model_detail.gd"),"builder":FileAccess.get_sha256("res://scripts/series_archetypes.gd"),"tool":FileAccess.get_sha256("res://tools/series_model_detail_verify.gd")}}
	var file := FileAccess.open(output_path,FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(result,"\t"))
	else: failures += 1
	print("Series material detail: ",checks," checks / ",failures," failures")
	quit(0 if failures == 0 else 1)
