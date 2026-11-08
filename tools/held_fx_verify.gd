extends SceneTree
## Controlled real-input / real-material comparison. Optional baseline is an
## actual previous PCK, not a second implementation of sword or damage logic.

const STEP := 1.0/60.0
const SOURCE_FILES := ["res://scripts/main.gd","res://scripts/katana_view.gd","res://scripts/voxel_debris.gd","res://scripts/voxel_enemy.gd"]
var game
var output_path := ""
var baseline_path := ""
var baseline_only := false
var checks: Array = []
var observations: Dictionary = {}
var geometry_samples: Array = []
var failures := 0
var rendered := false
var source_hashes: Dictionary = {}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output_path = argument.trim_prefix("--output=")
		elif argument.begins_with("--baseline="): baseline_path = argument.trim_prefix("--baseline=")
		elif argument == "--baseline-only": baseline_only = true
	if output_path.is_empty(): output_path = ProjectSettings.globalize_path("res://builds/held-fx-review-v094/verify.json")
	call_deferred("_run")


func expect(condition: bool, label: String, detail: Dictionary = {}) -> void:
	checks.append({"label":label,"passed":condition,"detail":_plain(detail)})
	if condition: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)


func _plain(value: Variant) -> Variant:
	if value is Vector2: return [value.x,value.y]
	if value is Vector3 or value is Vector3i: return [value.x,value.y,value.z]
	if value is Color: return [value.r,value.g,value.b,value.a]
	if value is Basis: return [_plain(value.x),_plain(value.y),_plain(value.z)]
	if value is Transform3D: return [_plain(value.basis),_plain(value.origin)]
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[str(key)] = _plain(value[key])
		return result
	if value is Array or value is PackedVector2Array or value is PackedVector3Array or value is PackedFloat32Array:
		var result: Array = []
		for item in value: result.append(_plain(item))
		return result
	return value


func _hash(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	var bytes: PackedByteArray = value if value is PackedByteArray else var_to_bytes(_plain(value))
	if not bytes.is_empty(): context.update(bytes)
	return context.finish().hex_encode()


func _error(a: Variant,b: Variant) -> float:
	if (a is float or a is int) and (b is float or b is int): return absf(float(a)-float(b))
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return INF
		var error := 0.0
		for key in a:
			if not b.has(key): return INF
			error = maxf(error,_error(a[key],b[key]))
		return error
	if a is Array and b is Array:
		if a.size() != b.size(): return INF
		var error := 0.0
		for index in range(a.size()): error = maxf(error,_error(a[index],b[index]))
		return error
	return 0.0 if a == b else INF


func _button(pressed: bool, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	var canvas: Transform2D = game.get_viewport().get_final_transform()
	event.relative = relative*canvas.get_scale()
	event.screen_relative = event.relative
	event.position = canvas*game.slash_cursor
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = InputEventKey.new()
	event.keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _manual_nodes() -> Array:
	var result: Array = []
	for enemy in game.enemies:
		if not is_instance_valid(enemy): continue
		for child in enemy.get_children():
			if child.is_queued_for_deletion(): continue
			if child.get_meta("voxel_piece",false) or child.get_meta("cut_chip",false) or child.get_meta("cut_particle_batch",false):
				child.set_process(false)
				result.append(child)
	return result


func _step(delta: float = STEP, advance_particles: bool = false) -> void:
	game._process(delta)
	game.sword._process(delta)
	for node in _manual_nodes():
		if advance_particles and node.has_method("_process"): node._process(delta)


func _reset() -> void:
	for enemy in game.enemies:
		if is_instance_valid(enemy): enemy.free()
	game.enemies.clear()
	game.training = true
	game.start_game()
	game.practice = false
	game.spawn_timer = 999.0
	game.speed = 48.0
	game.gear = 4
	game.camera.position = Vector3(0,1.75,0)
	game.camera.rotation = Vector3.ZERO
	game.camera.fov = 78.0
	game.sword.set_pose("sheathed")
	for index in range(48): _step()
	seed(94723)


func _geometry(label: String) -> Dictionary:
	return _plain({"label":label,"grip":game.sword.get_grip_screen_position(),"contact":game.sword.get_contact_world_position(),"axis":game.sword.get_blade_screen_direction(),"drawn_transform":game.sword._drawn.transform,"camera_transform":game.camera.transform,"fov":game.camera.fov,"animation":game.sword.get_animation_debug_state(),"cursor":game.slash_cursor,"damage_path":game.last_cut_path,"speed":game.speed,"gear":game.gear})


func _blade_fx() -> Dictionary:
	return _plain(game.sword.get_held_voxel_fx_debug_state()) if game.sword.has_method("get_held_voxel_fx_debug_state") else {"available":false}


func _target(kind: String = "normal"):
	var enemy = game._spawn_enemy(kind,1,-9.0)
	enemy.position.x = 0.0
	enemy.set_action("recover",1.0)
	return enemy


func _material(enemy) -> Dictionary:
	var all: PackedByteArray = enemy._voxels.duplicate()
	var pieces: Array = []
	for child in enemy.get_children():
		if child.get_meta("voxel_piece",false) and not child.is_queued_for_deletion():
			var cells: Array = []
			for coord: Vector3i in child.cells:
				all[enemy._index(coord.x,coord.y,coord.z)] = int(child.cells[coord])
				cells.append([coord.x,coord.y,coord.z,int(child.cells[coord])])
			cells.sort_custom(func(a,b): return str(a) < str(b))
			pieces.append({"cells":cells.size(),"sha256":_hash(cells)})
	pieces.sort_custom(func(a,b): return a.sha256 < b.sha256)
	return {"remaining":enemy.get_remaining_voxel_count(),"all_authored_cells_sha256":_hash(all),"body_sha256":_hash(enemy._voxels),"pieces":pieces,"dead":enemy.dead,"kills":game.kills,"score":game.score}


func _held_ready() -> void:
	_reset()
	_button(true)
	_step(0.15)
	_motion((Vector2(500,430)-game.slash_cursor)/1.05)
	_step(0.016)
	_motion(Vector2(250.0/1.05,0))
	_step(0.016)


func _precision_ready(point: Vector3) -> void:
	_held_ready()
	var size: Vector2 = game.get_viewport().get_visible_rect().size
	var contact: Vector2 = game.camera.unproject_position(point)
	var grip: Vector2 = game.sword.grip_for_active_cut_point(contact,Vector2.LEFT,size)
	_motion((grip-Vector2(520,0)-game.slash_cursor)/1.05)
	_step(0.016)
	_motion(Vector2(520.0/1.05,0))
	_step(0.016)


func _source_summary(enemy) -> Dictionary:
	var debug: Dictionary = enemy.get_cut_particle_debug_state()
	var batch = enemy.get_node_or_null("CutVoxelBurst")
	var signature: Array = []
	if is_instance_valid(batch):
		for index in range(batch.slots.size()):
			var slot: Dictionary = batch.slots[index]
			if slot.is_empty(): continue
			var item: Dictionary = {}
			for key in ["position","velocity","age","life","dimensions","orientation","angular_velocity","source_cell","head_pixels","tail_phase","drag"]: item[key] = slot[key]
			# Read submitted CPU color, not rendered pixel / GPU memory.
			item["color"] = batch.cores.get_instance_color(index)
			signature.append(_plain(item))
	return {"active":int(debug.get("active_count",0)),"emitted_total":int(debug.get("emitted_total",0)),"emitted_body":int(debug.get("emitted_body",0)),"emitted_sever":int(debug.get("emitted_sever",0)),"emitted_debris":int(debug.get("emitted_debris",0)),"last_source_kind":debug.get("last_source_kind",""),"last_source_points":_plain(debug.get("last_source_points",[])),"random_state":str(batch.random.state) if is_instance_valid(batch) else "","standard_slot_signature":_hash(signature),"debug":_plain(debug)}


func _verify_motion() -> void:
	_reset()
	var lights: Array = []
	for style in range(12):
		_button(true)
		for index in range(6):
			_step()
			geometry_samples.append(_geometry("light-%d-%d" % [style,index]))
		_button(false)
		_step(0.02)
		lights.append(int(game.sword.get_animation_debug_state().light_slash_style))
	expect(lights == range(12),"all twelve real button contacts retain their authored nonrepeating light sequence",{"styles":lights})
	_held_ready()
	geometry_samples.append(_geometry("held-entry"))
	var camera: Transform3D = game.camera.transform
	var fov: float = game.camera.fov
	for index in range(24):
		var movement := Vector2(6.0,-sin(float(index)*0.20)*2.0)
		if index >= 12: movement = Vector2(-9.0,cos(float(index)*0.24)*3.0)
		_motion(movement/1.05)
		_step()
		geometry_samples.append(_geometry("curve-%d" % index))
	var stopped_axis: Vector2 = game.sword.get_blade_screen_direction()
	var stopped_grip: Vector2 = game.sword.get_grip_screen_position()
	for index in range(18): _step()
	geometry_samples.append(_geometry("held-still"))
	expect(stopped_axis.dot(game.sword.get_blade_screen_direction()) > 0.999 and stopped_grip.distance_to(game.sword.get_grip_screen_position()) < 0.1,"stopped real held cursor preserves its last blade axis and hilt")
	expect(camera == game.camera.transform and is_equal_approx(fov,game.camera.fov),"curve, reversal and stopped held input preserve the complete entry camera and FOV")
	var before := _blade_fx()
	game.hit_stop = 0.20
	var grip: Vector2 = game.sword.get_grip_screen_position()
	_motion(Vector2(-28,14)/1.05)
	_step()
	var after := _blade_fx()
	geometry_samples.append(_geometry("hit-stop-input"))
	expect(grip.distance_to(game.sword.get_grip_screen_position()) > 10.0,"hit-stop still consumes actual pointer motion into physical hilt movement")
	if not baseline_only:
		expect(before.cpu_instance_sha256 == after.cpu_instance_sha256 and before.phase == after.phase and before.uploads == after.uploads,"production hit-stop freezes only held FX local phase, submitted poses and uploads")
	game.hit_stop = 0.0
	var old_phase: float = float(_blade_fx().get("phase",0.0))
	_step(0.05)
	if not baseline_only:
		var fx := _blade_fx()
		expect(game.slashing and absf(float(fx.phase)-old_phase-0.05*(0.35+0.65*game.SLOW_SCALE)) < 0.000001,"held voxel effect clock follows the intended cosmetic slow-world rate",{"before_phase":old_phase,"after_phase":fx.phase,"world_scale":fx.world_scale})
	_key(KEY_ESCAPE)
	_step()
	before = _blade_fx()
	for index in range(5): _step()
	after = _blade_fx()
	geometry_samples.append(_geometry("paused"))
	expect(game.state == "paused","parsed Escape actually pauses the controlled held fixture")
	if not baseline_only: expect(before.cpu_instance_sha256 == after.cpu_instance_sha256 and before.phase == after.phase and before.uploads == after.uploads,"production pause freezes held voxel local state")
	_key(KEY_ESCAPE)
	game.hit_stop = 0.0
	_step()
	_button(false)
	_step()
	geometry_samples.append(_geometry("released"))
	observations["geometry_samples"] = geometry_samples


func _verify_input_cuts() -> void:
	var rows: Array = []
	for site in ["arm","chest","waist"]:
		_reset()
		var probe = _target()
		var bind := {"arm":Vector3(-0.725,1.475,0.275),"chest":Vector3(0.225,1.975,0.35),"waist":Vector3(-0.9,1.425,0.025)}
		var point: Vector3 = probe.to_global(probe._part_pose(1 if site == "arm" else 0)*bind[site])
		_precision_ready(point)
		var enemy = _target()
		var initial: int = enemy.get_remaining_voxel_count()
		_motion(Vector2(float({"arm":5,"chest":18,"waist":92}[site])/1.05,0))
		_step(0.016)
		var material := _material(enemy)
		var particles := _source_summary(enemy)
		expect(int(material.remaining) < initial and (enemy.dead if site == "waist" else not enemy.dead),"actual parsed "+site+" stroke keeps its narrow structural material result",material)
		if not baseline_only:
			expect(particles.debug.get("last_feedback_mode","") == "held" and int(particles.debug.get("held_emitted_total",0)) > 0 and not enemy.has_meta("held_cut_fx"),site+" real cut snapshots held particle mode and restores absent owner metadata")
		var row := {"site":site,"material":material,"initial":initial,"input":_geometry("input-"+site),"particles":particles}
		if enemy.dead:
			var kills: int = game.kills
			var score: int = game.score
			var emitted_sever: int = int(particles.emitted_sever)
			var recut := 0
			for piece in enemy.get_children():
				if not piece.get_meta("voxel_piece",false) or piece.is_queued_for_deletion(): continue
				var bounds: Rect2 = piece.get_screen_bounds(game.camera)
				var before: int = enemy.get_remaining_voxel_count()
				game._cut_path(PackedVector2Array([Vector2(bounds.position.x-4,bounds.get_center().y),Vector2(bounds.end.x+4,bounds.get_center().y)]),true)
				recut = before-enemy.get_remaining_voxel_count()
				if recut > 0: break
			var after := _source_summary(enemy)
			expect(recut > 0 and game.kills == kills and game.score == score and int(after.emitted_sever) == emitted_sever,"held debris recut removes real cells without another sever burst, kill or score")
			if not baseline_only: expect(after.debug.last_feedback_mode == "held" and int(after.debug.held_emitted_total) > int(particles.debug.held_emitted_total),"real detached-material recut receives its own held particle snapshot")
			row["recut_material"] = _material(enemy)
			row["recut_removed"] = recut
		rows.append(row)
	observations["input_cuts"] = rows


func _primed_target():
	_reset()
	var enemy = _target()
	var point: Vector3 = enemy._posed_world_point(enemy._live_indices[0])
	enemy.blast_at(point,0.01)
	var batch = enemy.get_node("CutVoxelBurst")
	batch._process(10.0)
	batch.random.seed = 384716
	if batch.get("held_random") != null: batch.held_random.seed = 824761
	return enemy


func _verify_standard_and_rng() -> void:
	var rows: Array = []
	for continuous in [false,true]:
		var enemy = _primed_target()
		var point: Vector3 = enemy.to_global(enemy._part_pose(0)*Vector3(0,1.425,0.025))
		var screen: Vector2 = game.camera.unproject_position(point)
		game._cut_path(PackedVector2Array([screen-Vector2(105,0),screen+Vector2(105,0)]),continuous)
		var state := _source_summary(enemy)
		rows.append({"continuous":continuous,"material":_material(enemy),"particles":state})
		if not baseline_only:
			expect(state.debug.last_feedback_mode == ("held" if continuous else "standard"),"committed "+("held" if continuous else "ordinary")+" cut selects only its own particle profile")
			if continuous:
				var layers: Dictionary = state.debug.last_layer_counts
				expect(int(layers.hot_jet) > 0 and int(layers.hot_plate) > 0 and int(layers.cut_flash) > 0 and int(layers.standard) == 0,"held material cut commits three solid warm particle layers")
			else: expect(int(state.debug.held_emitted_total) == 0,"ordinary cut does not inherit the held effect")
	observations["seeded_profiles"] = rows


func _verify_fx_contract() -> void:
	_held_ready()
	var fx := _blade_fx()
	var visual: MultiMeshInstance3D = game.sword._held_voxel_visual
	var material: StandardMaterial3D = visual.material_override
	expect(bool(fx.active) and int(fx.capacity) == 96 and int(fx.visible_instance_count) == 96 and int(fx.noncollapsed_instances) > 0 and int(fx.noncollapsed_instances) <= 96 and visual.get_parent() == game.sword._drawn,"held blade effect is a bounded 96-instance drawn-sword child")
	expect(material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and not material.no_depth_test and material.use_z_clip_scale and is_equal_approx(material.z_clip_scale,0.9) and visual.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"held cubes keep opaque viewmodel depth 0.9, real depth testing and no world shadows")
	var idle_hash: String = fx.cpu_instance_sha256
	for index in range(8): _step()
	expect(_blade_fx().cpu_instance_sha256 != idle_hash,"held blade voxels evolve while the cursor is still without recentering the sword")
	_button(true,MOUSE_BUTTON_RIGHT)
	_step()
	fx = _blade_fx()
	expect(not bool(fx.active) and int(fx.visible_instance_count) == 0,"parry immediately hides the held-only blade voxels")
	_button(false)
	_reset()
	_button(true)
	_step(0.02)
	fx = _blade_fx()
	expect(not bool(fx.active) and int(fx.visible_instance_count) == 0,"a light attack never shows held-only blade voxels")
	observations["blade_fx_contract"] = {"held":_plain(game.sword.get_held_voxel_fx_debug_state()),"material":{"depth_scale":material.z_clip_scale,"opaque":material.transparency == 0}}


func _verify_mode_scope_and_sources() -> void:
	var rows: Array = []
	for prior in [null,false,true,"preserved-value"]:
		_reset()
		var enemy = _target()
		if prior != null: enemy.set_meta("held_cut_fx",prior)
		var before: PackedByteArray = enemy._voxels.duplicate()
		var from: Vector2 = game.camera.unproject_position(enemy.to_global(enemy._part_pose(1)*Vector3(-0.81,1.475,0.275)))
		var to: Vector2 = game.camera.unproject_position(enemy.to_global(enemy._part_pose(1)*Vector3(-0.64,1.475,0.275)))
		game._cut_path(PackedVector2Array([from,to]),true)
		var debug: Dictionary = enemy.get_cut_particle_debug_state()
		var restored: bool = (not enemy.has_meta("held_cut_fx")) if prior == null else enemy.has_meta("held_cut_fx") and enemy.get_meta("held_cut_fx") == prior
		expect(restored and debug.get("last_feedback_mode","") == "held","a held cut snapshots its visual mode then restores owner metadata exactly: "+str(prior))
		var removed_points := PackedVector3Array()
		for index in range(before.size()):
			if before[index] != 0 and enemy._voxels[index] == 0: removed_points.append(enemy._posed_world_point(index))
		var genuine: bool = not debug.get("last_source_points",[]).is_empty()
		var max_origin_offset := 0.0
		var sources: PackedVector3Array = debug.get("last_source_points",PackedVector3Array())
		var origins: PackedVector3Array = debug.get("last_origins",PackedVector3Array())
		for index in range(sources.size()):
			var nearest := INF
			for point in removed_points: nearest = minf(nearest,point.distance_to(sources[index]))
			genuine = genuine and nearest < 0.00001
			max_origin_offset = maxf(max_origin_offset,origins[index].distance_to(sources[index]))
		expect(genuine and max_origin_offset <= enemy._cell*0.53,"held sparks originate at actually removed posed cells with only a bounded surface separation: "+str(prior),{"source_samples":sources.size(),"max_surface_offset":max_origin_offset})
		rows.append({"prior":prior,"metadata_restored":restored,"source_samples":sources.size(),"max_surface_offset":max_origin_offset})
		var blast_index: int = enemy._live_indices[0]
		enemy.blast_at(enemy._posed_world_point(blast_index),0.01)
		debug = enemy.get_cut_particle_debug_state()
		var blast_restored: bool = (not enemy.has_meta("held_cut_fx")) if prior == null else enemy.has_meta("held_cut_fx") and enemy.get_meta("held_cut_fx") == prior
		expect(debug.last_feedback_mode == "standard" and blast_restored,"real blast always uses standard particles and restores prior owner metadata: "+str(prior))
		if prior == null:
			var batch = enemy.get_node("CutVoxelBurst")
			var slot_hash := _hash(batch.slots)
			game.hit_stop = 0.2
			_step(0.016,true)
			expect(_hash(batch.slots) == slot_hash,"production hit-stop freezes all held impact particle ages, positions and cached submitted render transforms")
			var index: int = enemy._live_indices[0]
			enemy.blast_at(enemy._posed_world_point(index),0.01)
			debug = enemy.get_cut_particle_debug_state()
			expect(debug.last_feedback_mode == "standard" and not enemy.has_meta("held_cut_fx"),"a subsequent real blast cannot inherit the previous held cut's temporary profile")
			var standard_before: int = int(debug.standard_emitted_total)
			var held_before: int = int(debug.held_emitted_total)
			game._spawn_projectile(enemy.global_position+Vector3(0,1.7,0.1),"bolt",enemy)
			game._cut_projectile(0)
			debug = enemy.get_cut_particle_debug_state()
			expect(int(debug.standard_emitted_total) == standard_before and int(debug.held_emitted_total) == held_before,"ordinary projectile slash explosion adds no held enemy particles")
			var shot: Node3D = game._spawn_projectile(enemy.global_position+Vector3(0,1.7,0.1),"bolt",enemy)
			game.projectiles[0].reflected = true
			shot.set_reflected()
			game._cut_projectile(0)
			debug = enemy.get_cut_particle_debug_state()
			expect(debug.last_feedback_mode == "standard" and int(debug.held_emitted_total) == held_before and int(debug.standard_emitted_total) > standard_before,"returned projectile blast creates standard real cut particles without held-mode leakage")
	observations["metadata_and_sources"] = rows


func _verify_pool_limits() -> void:
	_reset()
	var debris_script = load("res://scripts/voxel_debris.gd")
	var owners: Array = []
	var source_points: Array = []
	for owner_index in range(5):
		var enemy = _target()
		enemy.position.x = float(owner_index)*2.0
		var point: Vector3 = enemy._posed_world_point(enemy._live_indices[0])
		enemy.blast_at(point,0.01)
		var batch = enemy.get_node("CutVoxelBurst")
		batch._process(10.0)
		enemy.set_meta("held_cut_fx",true)
		owners.append(enemy)
		source_points.append(PackedVector3Array([point]))
	var first_hash := ""
	for owner_index in range(5):
		for burst in range(10): debris_script.emit_cut_particles(owners[owner_index],game.camera,source_points[owner_index],Vector2.RIGHT,0.05,"body")
		if owner_index == 0: first_hash = _hash(owners[0].get_node("CutVoxelBurst").slots)
	var total := 0
	var bounded := true
	for owner in owners:
		var state: Dictionary = owner.get_cut_particle_debug_state()
		total += int(state.active_count)
		bounded = bounded and int(state.capacity) == 576 and int(state.global_capacity) == 2304 and int(state.active_count) <= 576 and int(state.global_active_count) <= 2304
	expect(bounded and total == 2304,"held impact pools retain the existing 576 local and 2304 global limits under saturation",{"active":total,"owners":owners.size()})
	expect(_hash(owners[0].get_node("CutVoxelBurst").slots) == first_hash,"saturated held bursts neither steal another owner's slots nor overwrite the first owner's hot particles")
	for owner in owners: owner.get_node("CutVoxelBurst")._process(10.0)
	var final: Dictionary = owners[0].get_cut_particle_debug_state()
	expect(int(final.global_active_count) == 0,"expired held particles return every occupied global slot")
	observations["pool_limits"] = {"owners":owners.size(),"peak_active":total,"local_capacity":576,"global_capacity":2304,"final_active":final.global_active_count,"source_scope":"Repeated emission stress uses points from genuine preceding one-cell material removal; not repeated damage or a combat benchmark."}


func _compare_baseline() -> void:
	if baseline_path.is_empty(): return
	var file := FileAccess.open(baseline_path,FileAccess.READ)
	var old: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	var error := _error(observations.geometry_samples,old.observations.geometry_samples)
	expect(error < 0.00001,"actual093 / current full light and held geometry, contact, camera and unchanged animation debug agree",{"maximum_numeric_error":error})
	for index in range(observations.input_cuts.size()):
		var row: Dictionary = observations.input_cuts[index]
		var previous: Dictionary = old.observations.input_cuts[index]
		expect(_error(row.material,previous.material) == 0.0 and _error(row.input,previous.input) < 0.00001,"actual093 / current parsed "+row.site+" damage mask, fragment partition, score and physical blade agree")
		if row.has("recut_material"): expect(_error(row.recut_material,previous.recut_material) == 0.0,"actual093 / current detached-material recut masks and score agree")
	for index in range(observations.seeded_profiles.size()):
		var row: Dictionary = observations.seeded_profiles[index]
		var previous: Dictionary = old.observations.seeded_profiles[index]
		expect(row.particles.random_state == previous.particles.random_state,"held extras do not change the original private random stream: "+str(row.continuous))
		if not bool(row.continuous): expect(row.particles.standard_slot_signature == previous.particles.standard_slot_signature and row.particles.emitted_total == previous.particles.emitted_total,"default particle profile keeps the old actual093 poses, speeds, sizes, heat colors and count")


func _setup_game() -> void:
	rendered = DisplayServer.get_name() != "headless"
	for path in SOURCE_FILES: source_hashes[path] = FileAccess.get_sha256(path)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.test_mode = true
	game.set_process(false)
	game.sword.set_process(false)
	while not game.menu_prepared:
		await process_frame
		if rendered: await RenderingServer.frame_post_draw
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _run() -> void:
	await _setup_game()
	_verify_motion()
	_verify_input_cuts()
	_verify_standard_and_rng()
	if not baseline_only:
		_verify_fx_contract()
		_verify_mode_scope_and_sources()
		_verify_pool_limits()
	_compare_baseline()
	await _finish()


func _finish() -> void:
	var after: Dictionary = {}
	for path in SOURCE_FILES: after[path] = FileAccess.get_sha256(path)
	expect(after == source_hashes,"runtime owning sources remain unchanged during the fixture")
	var report := {"engine":Engine.get_version_info().string,"version":ProjectSettings.get_setting("application/config/version"),"baseline_only":baseline_only,"baseline_reference":baseline_path,"baseline_sha256":FileAccess.get_sha256(baseline_path) if not baseline_path.is_empty() else "","checks":checks,"failures":failures,"observations":_plain(observations),"source_hashes_before":source_hashes,"source_hashes_after":after,"tool_sha256":FileAccess.get_sha256(get_script().resource_path),"scope":"Controlled actual parsed mouse / Escape inputs, fixed-pose real actor material and production cut APIs. Training-style AI freeze is explicit; no F4, normal combat, GPU visibility, performance or subjective effect-quality acceptance. Particle signatures are CPU state / submitted colors, not physical GPU memory or rendered pixels."}
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var file := FileAccess.open(output_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("HELD FX VERIFY ",checks.size()," checks, ",failures," failures")
	game._pause_game()
	game.audio.set_runner_motion(0,0,false,0)
	await create_timer(1.1).timeout
	game.free()
	await process_frame
	await process_frame
	quit(0 if failures == 0 else 1)
