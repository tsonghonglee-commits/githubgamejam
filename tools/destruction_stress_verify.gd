extends SceneTree
## Deterministic public cut_path fixtures and inclusive production-method timing.
## Run the same unchanged tool against an old PCK and the candidate source/PCK.

const PROFILE_SOURCE := '''extends "res://scripts/voxel_enemy.gd"
var timings: Dictionary = {}
func _record(key: String, started: int) -> void:
	if not timings.has(key): timings[key] = []
	timings[key].append(Time.get_ticks_usec()-started)
func _build_fine_mesh(indices: PackedInt32Array, origin: Vector3, membership: Dictionary) -> ArrayMesh:
	var started := Time.get_ticks_usec()
	var result: ArrayMesh = super._build_fine_mesh(indices, origin, membership)
	_record("fine_mesh",started)
	return result
func _fine_components() -> Array[Dictionary]:
	var started := Time.get_ticks_usec()
	var result: Array[Dictionary] = super._fine_components()
	_record("components",started)
	return result
func _spawn_fragment(indices: PackedInt32Array, stroke: Vector2, lethal: bool) -> bool:
	var started := Time.get_ticks_usec()
	var result: bool = super._spawn_fragment(indices,stroke,lethal)
	_record("spawn_fragments",started)
	return result
func _rebuild_body() -> void:
	var started := Time.get_ticks_usec()
	super._rebuild_body()
	_record("rebuild_body",started)
func _select_coarse_cut(camera_node: Camera3D, points: PackedVector2Array, segments: PackedInt32Array, regions: Array[Dictionary], band: float, depth: int, armored: bool, poses: Array[Transform3D]) -> PackedInt32Array:
	var started := Time.get_ticks_usec()
	var result: PackedInt32Array = super._select_coarse_cut(camera_node,points,segments,regions,band,depth,armored,poses)
	_record("heavy_selection",started)
	return result
func _commit_material_cut(indices: PackedInt32Array, stroke: Vector2, camera_node: Camera3D, cut_started: int) -> Dictionary:
	var started := Time.get_ticks_usec()
	var result: Dictionary = super._commit_material_cut(indices,stroke,camera_node,cut_started)
	_record("commit",started)
	return result
func _cut_body(camera_node: Camera3D, points: PackedVector2Array, power: float, frames: Array = []) -> Dictionary:
	var started := Time.get_ticks_usec()
	var result: Dictionary = super._cut_body(camera_node,points,power,frames)
	_record("cut_body",started)
	return result
'''

var output_path := ""
var baseline_path := ""
var samples := 3
var quick := false
var mesh_check := false
var profile_script: GDScript
var world: Node3D
var camera: Camera3D
var observations: Array = []
var checks: Array = []
var failures := 0
var invalid_mesh_faces := 0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output_path = argument.trim_prefix("--output=")
		elif argument.begins_with("--baseline="): baseline_path = argument.trim_prefix("--baseline=")
		elif argument.begins_with("--samples="): samples = maxi(1,int(argument.trim_prefix("--samples=")))
		elif argument == "--quick": quick = true
		elif argument == "--mesh": mesh_check = true
	if output_path.is_empty(): output_path = ProjectSettings.globalize_path("res://builds/destruction-review-v095/stress.json")
	call_deferred("_run")


func _expect(passed: bool, label: String, detail: Dictionary = {}) -> void:
	checks.append({"passed":passed,"label":label,"detail":detail})
	if not passed:
		failures += 1
		push_error("DESTRUCTION FAIL: "+label)


func _hash(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	var bytes: PackedByteArray = value if value is PackedByteArray else var_to_bytes(value)
	if not bytes.is_empty(): context.update(bytes)
	return context.finish().hex_encode()


func _sum(values: Array) -> int:
	var result := 0
	for value in values: result += int(value)
	return result


func _timings(enemy) -> Dictionary:
	var result: Dictionary = {}
	for key in enemy.timings: result[key] = _sum(enemy.timings[key])
	result["selection_and_bounds"] = int(result.get("cut_body",0))-int(result.get("commit",0))
	result["commit_other"] = int(result.get("commit",0))-int(result.get("components",0))-int(result.get("spawn_fragments",0))-int(result.get("rebuild_body",0))
	return result


func _new_enemy(kind: String, offset := Vector3.ZERO):
	var enemy = profile_script.new()
	world.add_child(enemy)
	enemy.configure(kind,1)
	enemy._rng.seed = 628591
	enemy.position = Vector3(0.0,0.0,-8.0)+offset
	enemy.set_meta("held_cut_fx",true)
	enemy.set_action("recover",1.0)
	enemy.timings.clear()
	return enemy


func _fragment_signature(piece) -> Dictionary:
	var keys: Array[String] = []
	for coordinate: Vector3i in piece.cells:
		keys.append("%d/%d/%d/%d" % [coordinate.x,coordinate.y,coordinate.z,int(piece.cells[coordinate])])
	keys.sort()
	var result := {"cells":piece.cells.size(),"cell_hash":_hash(keys),"origin":_vector(piece._origin),"transform":str(piece.transform),"bounds":[_vector(piece._bounds.position),_vector(piece._bounds.size)]}
	if mesh_check: result["surface"] = _mesh_signature(piece._visual.mesh,piece.cell_size,piece._origin,piece._visual.transform)
	return result


func _vector(value: Vector3) -> Array:
	return [roundi(value.x*1000000.0),roundi(value.y*1000000.0),roundi(value.z*1000000.0)]


func _inside_triangle(point: Vector2,a: Vector2,b: Vector2,c: Vector2) -> bool:
	var first := (b-a).cross(point-a)
	var second := (c-b).cross(point-b)
	var third := (a-c).cross(point-c)
	return not ((first< -0.0000001 or second< -0.0000001 or third< -0.0000001) and (first>0.0000001 or second>0.0000001 or third>0.0000001))


func _mesh_signature(mesh: ArrayMesh, size: float, origin: Vector3, visual_pose := Transform3D.IDENTITY) -> Dictionary:
	# Canonical unit faces are read from actual submitted triangles, after the
	# visual transform. Shared body meshes translated within a real fragment
	# can therefore compare equal without demanding identical tessellation.
	var coverage: Dictionary = {}
	var invalid := 0
	var area := 0.0
	if mesh != null:
		for surface in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := indices.size() if not indices.is_empty() else vertices.size()
			if count%3!=0 or vertices.size()!=normals.size() or vertices.size()!=colors.size():
				invalid += 1
				continue
			for offset in range(0,count,3):
				var index0: int = indices[offset] if not indices.is_empty() else offset
				var index1: int = indices[offset+1] if not indices.is_empty() else offset+1
				var index2: int = indices[offset+2] if not indices.is_empty() else offset+2
				var a: Vector3 = visual_pose*vertices[index0]
				var b: Vector3 = visual_pose*vertices[index1]
				var c: Vector3 = visual_pose*vertices[index2]
				var normal: Vector3 = (visual_pose.basis*normals[index0]).normalized()
				var cross := (b-a).cross(c-a)
				var tint := colors[index0]
				area += cross.length()*0.5
				var axis := 0 if absf(normal.x)>0.5 else (1 if absf(normal.y)>0.5 else 2)
				var side := axis*2+(0 if normal[axis]>0.0 else 1)
				var u := 1 if axis==0 else 0
				var v := 2 if axis<2 else 1
				if cross.length_squared()<0.000000000001 or cross.normalized().dot(normal)> -0.999 or normals[index0]!=normals[index1] or normals[index0]!=normals[index2] or tint!=colors[index1] or tint!=colors[index2]: invalid += 1
				var low := a.min(b).min(c)
				var high := a.max(b).max(c)
				if absf(high[axis]-low[axis])>0.00001: invalid += 1
				var layer := roundi((a[axis]-origin[axis])/size-normal[axis]*0.5)
				var x0 := roundi((low[u]-origin[u])/size+0.5)
				var x1 := roundi((high[u]-origin[u])/size+0.5)
				var y0 := roundi((low[v]-origin[v])/size+0.5)
				var y1 := roundi((high[v]-origin[v])/size+0.5)
				var color_key := "%d,%d,%d,%d" % [roundi(tint.r*1000000),roundi(tint.g*1000000),roundi(tint.b*1000000),roundi(tint.a*1000000)]
				for y in range(y0,y1):
					for x in range(x0,x1):
						# Off-diagonal interior sample avoids shared triangle edges.
						var point := Vector2(origin[u]+(float(x)+0.173205)*size,origin[v]+(float(y)+0.193719)*size)
						if _inside_triangle(point,Vector2(a[u],a[v]),Vector2(b[u],b[v]),Vector2(c[u],c[v])):
							var key := "%d/%d/%d/%d/%s" % [side,layer,x,y,color_key]
							coverage[key] = int(coverage.get(key,0))+1
	var keys: Array = coverage.keys()
	keys.sort()
	for key in keys:
		if coverage[key]!=1: invalid += 1
	if absf(area-float(keys.size())*size*size)>0.00005: invalid += 1
	invalid_mesh_faces += invalid
	return {"unit_faces":keys.size(),"face_hash":_hash(keys),"invalid":invalid,"area_microunits":roundi(float(keys.size())*size*size*1000000.0)}


func _snapshot(enemy) -> Dictionary:
	var fragments: Array = []
	for child in enemy.get_children():
		if child.get_meta("voxel_piece",false) and not child.is_queued_for_deletion(): fragments.append(_fragment_signature(child))
	var result := {"body_hash":_hash(enemy._voxels),"tags_hash":_hash(enemy._tags),"remaining":enemy.get_remaining_voxel_count(),"dead":enemy.dead,"armed":enemy.has_attack_limb(),"cut_count":enemy.cut_count,"fragments":fragments}
	if mesh_check:
		var meshes: Array = []
		for part in enemy._part_meshes: meshes.append(_mesh_signature(part.mesh,enemy._cell,enemy._point(0,0,0)))
		result["body_surfaces"] = meshes
	return result


func _slice(enemy, from: Vector3, to: Vector3, power: float, path_override := PackedVector2Array()) -> Dictionary:
	var path := path_override
	if path.is_empty():
		path = PackedVector2Array([camera.unproject_position(enemy.to_global(enemy._part_pose(0)*from)),camera.unproject_position(enemy.to_global(enemy._part_pose(0)*to))])
	var before_count: int = enemy.get_remaining_voxel_count()
	enemy.timings.clear()
	var started := Time.get_ticks_usec()
	var result: Dictionary = enemy.cut_path(camera,path,power)
	var elapsed := Time.get_ticks_usec()-started
	var state := _snapshot(enemy)
	_expect(before_count-int(state.remaining)==int(result.removed),"reported removal equals actual body plus retained-fragment material difference",{"kind":enemy.enemy_kind,"before":before_count,"after":state.remaining,"removed":result.removed})
	return {"elapsed_usec":elapsed,"result":result,"timings_usec":_timings(enemy),"state":state}


func _paths(kind: String) -> Array:
	var waist := 1.43 if kind == "normal" else (1.62 if kind == "tank" else 2.72)
	var half_width := 0.82 if kind == "normal" else (1.20 if kind == "tank" else 1.90)
	var result: Array = []
	# Same narrow groove repeatedly: armor must genuinely yield surviving layers.
	for step in range(6 if quick else 12):
		result.append([Vector3(-half_width,waist,0.0),Vector3(half_width,waist,0.0)])
	# Slow curved and reversing strokes retain every supplied segment.
	result.append([Vector3(-half_width,waist+0.35,0.0),Vector3(half_width,waist+0.55,0.0),Vector3(0.0,waist+0.15,0.0),Vector3(-half_width,waist+0.35,0.0)])
	return result


func _case(kind: String, sample: int, power: float) -> Dictionary:
	var enemy = _new_enemy(kind)
	var initial := _snapshot(enemy)
	var rows: Array = []
	for path in _paths(kind):
		var screen_path := PackedVector2Array()
		for point in path: screen_path.append(camera.unproject_position(enemy.to_global(enemy._part_pose(0)*point)))
		rows.append(_slice(enemy,Vector3.ZERO,Vector3.ZERO,power,screen_path))
	var piece = null
	for child in enemy.get_children():
		if child.get_meta("voxel_piece",false) and not child.is_queued_for_deletion() and (piece == null or child.get_voxel_count()>piece.get_voxel_count()): piece = child
	var recut: Dictionary = {}
	if piece != null:
		var coordinate: Vector3i = piece.cells.keys()[piece.cells.size()/2]
		var center: Vector2 = camera.unproject_position(piece.to_global(piece._cell_point(coordinate)))
		recut = _slice(enemy,Vector3.ZERO,Vector3.ZERO,power,PackedVector2Array([center-Vector2(60,0),center+Vector2(60,0)]))
	var total_removed := 0
	for row in rows: total_removed += int(row.result.removed)
	_expect(total_removed>0,kind+" geometric fixture actually removes material",{"sample":sample,"power":power,"removed":total_removed})
	if kind in ["tank","boss"]: _expect(not bool(rows[0].state.dead),kind+" first shallow waist contact retains real critical material",{"power":power,"remaining":rows[0].state.remaining})
	if not recut.is_empty(): _expect(int(recut.result.removed)>0,kind+" actual retained fragment accepts another real cut",{"removed":recut.result.removed})
	var result := {"kind":kind,"sample":sample,"power":power,"initial":initial,"cuts":rows,"recut":recut}
	enemy.free()
	return result


func _dense(sample: int) -> Dictionary:
	var actors: Array = []
	for setup in [["normal",Vector3(-1.1,0,0)],["tank",Vector3(0,0,-0.5)],["normal",Vector3(1.1,0,-1.0)],["boss",Vector3(0,0,-3.0)]]:
		actors.append(_new_enemy(setup[0],setup[1]))
	var rows: Array = []
	for step in range(6 if quick else 12):
		var screen_y := 360.0+float(step%3)*10.0
		var path := PackedVector2Array([Vector2(200,screen_y),Vector2(1080,screen_y)])
		if step%2: path.reverse()
		var row: Array = []
		var started := Time.get_ticks_usec()
		for enemy in actors: row.append(_slice(enemy,Vector3.ZERO,Vector3.ZERO,1.8,path))
		var observed_wall := Time.get_ticks_usec()-started
		var cuts_only := 0
		for actor in row: cuts_only += int(actor.elapsed_usec)
		rows.append({"elapsed_usec":cuts_only,"observed_wall_usec":observed_wall,"actors":row})
	var final_states: Array = []
	for enemy in actors:
		final_states.append(_snapshot(enemy))
		enemy.free()
	return {"sample":sample,"kind":"dense","cuts":rows,"final":final_states}


func _summarize() -> Dictionary:
	var summary: Dictionary = {}
	for kind in ["normal","tank","boss","dense"]:
		var elapsed: Array = []
		var stages: Dictionary = {}
		for row in observations:
			if row.kind!=kind: continue
			for cut in row.cuts:
				elapsed.append(cut.elapsed_usec)
				if cut.has("timings_usec"):
					for key in cut.timings_usec:
						stages[key] = int(stages.get(key,0))+int(cut.timings_usec[key])
		elapsed.sort()
		summary[kind] = {"calls":elapsed.size(),"median_usec":elapsed[elapsed.size()/2],"p95_usec":elapsed[mini(elapsed.size()-1,ceili(elapsed.size()*0.95)-1)],"max_usec":elapsed[-1],"inclusive_stage_total_usec":stages}
	return summary


func _logical(rows: Array) -> Array:
	var result: Array = []
	for row in rows:
		if row.kind=="dense":
			var cuts: Array = []
			for cut in row.cuts:
				var actors: Array = []
				for actor in cut.actors: actors.append({"result":actor.result,"state":_state_for_hash(actor.state)})
				cuts.append(actors)
			var final: Array = []
			for state in row.final: final.append(_state_for_hash(state))
			result.append({"kind":row.kind,"sample":row.sample,"cuts":cuts,"final":final})
		else:
			var cuts: Array = []
			for cut in row.cuts: cuts.append({"result":cut.result,"state":_state_for_hash(cut.state)})
			var recut: Dictionary = {} if row.recut.is_empty() else {"result":row.recut.result,"state":_state_for_hash(row.recut.state)}
			result.append({"kind":row.kind,"sample":row.sample,"power":row.power,"initial":_state_for_hash(row.initial),"cuts":cuts,"recut":recut})
	return result


func _state_for_hash(state: Dictionary) -> Dictionary:
	var result: Dictionary = state.duplicate(true)
	# Occupancy, tags, transform and canonical actual unit faces remain exact.
	# AABB float arithmetic from an existing mesh versus cell bounds can differ
	# below a micrometre. Keep the recorded values, compare them separately.
	for fragment in result.fragments: fragment.erase("bounds")
	return result


func _bounds_delta(a: Variant,b: Variant) -> int:
	var worst := 0
	if a is Dictionary and b is Dictionary:
		for key in a:
			if not b.has(key): continue
			if key=="bounds":
				for corner in range(2):
					for axis in range(3): worst = maxi(worst,absi(int(a[key][corner][axis])-int(b[key][corner][axis])))
			else: worst = maxi(worst,_bounds_delta(a[key],b[key]))
	elif a is Array and b is Array:
		for index in range(mini(a.size(),b.size())): worst = maxi(worst,_bounds_delta(a[index],b[index]))
	return worst


func _run() -> void:
	profile_script = GDScript.new()
	profile_script.source_code = PROFILE_SOURCE
	var error := profile_script.reload()
	if error!=OK:
		push_error("Production method profiling subclass failed to compile")
		quit(2)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.own_world_3d = true
	root.add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0,1.75,0)
	camera.fov = 78.0
	camera.current = true
	await process_frame
	# Initial template construction is separated from cut timings.
	for kind in ["normal","tank","boss"]:
		var actor = _new_enemy(kind)
		actor.free()
	for sample in range(samples):
		for kind in ["normal","tank","boss"]:
			for power in ([1.8] if quick else [1.1,1.45,1.8,2.15]): observations.append(_case(kind,sample,power))
		observations.append(_dense(sample))
	var logical := _logical(observations)
	if mesh_check: _expect(invalid_mesh_faces==0,"actual submitted-mesh triangles retain valid winding, palette and exact unit face coverage",{"invalid":invalid_mesh_faces})
	if not baseline_path.is_empty():
		var file := FileAccess.open(baseline_path,FileAccess.READ)
		var baseline: Dictionary = JSON.parse_string(file.get_as_text())
		_expect(baseline.tool_sha256==FileAccess.get_sha256(get_script().resource_path),"same unchanged pressure tool",{})
		_expect(baseline.samples==samples and baseline.quick==quick and baseline.mesh_check==mesh_check,"same fixture settings and sample count",{})
		_expect(baseline.logical_sha256==_hash(logical),"all deterministic cut results, real masks, tags and fragment partitions match old actual PCK",{"old":baseline.logical_sha256,"new":_hash(logical)})
		var maximum_delta := _bounds_delta(baseline.observations,observations)
		_expect(maximum_delta<=2,"all retained-fragment bounds match within two micrometres",{"maximum_delta_micrometres":maximum_delta,"tolerance_micrometres":2,"note":"Recorded AABBs are kept; exact canonical actual-mesh faces are checked separately."})
	var report := {"version":ProjectSettings.get_setting("application/config/version"),"engine":Engine.get_version_info().string,"headless":DisplayServer.get_name()=="headless","tool_sha256":FileAccess.get_sha256(get_script().resource_path),"samples":samples,"quick":quick,"mesh_check":mesh_check,"failures":failures,"checks":checks,"scope":"Headless CPU fixtures call actual production cut_path with a profiling-only subclass; no copied slicing/connectivity/mesh implementation. Function times are inclusive and include profiling wrapper overhead. Dense elapsed sums actual actor cut calls; observer wall including snapshots is separate. No native GPU/VSync, actual input feel, full-route performance or 12-style pose acceptance. Initial author/template construction is excluded from cut samples. Snapshots and optional canonical actual-mesh triangle reads are after calls outside timed cut regions.","logical_sha256":_hash(logical),"summary":_summarize(),"observations":observations}
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var file := FileAccess.open(output_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("DESTRUCTION CPU SUMMARY: ",JSON.stringify(report.summary))
	print("DESTRUCTION CHECKS: ",checks.size()," / failures ",failures)
	world.free()
	viewport.free()
	profile_script = null
	await process_frame
	quit(0 if failures==0 else 1)
