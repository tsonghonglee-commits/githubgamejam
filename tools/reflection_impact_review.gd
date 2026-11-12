extends SceneTree
## Fixed-step rendered inspection of a real incoming shot, parsed right-click,
## exact reverse return and first voxel impact. The shooter is deliberately held
## at its firing pose; this is not normal combat or a performance benchmark.

const STEP := 1.0/120.0
const SOURCE_FILES := ["res://scripts/main.gd","res://scripts/voxel_enemy.gd","res://scripts/projectile_view.gd","res://scripts/projectile_geometry.gd","res://scripts/voxel_blast.gd","res://scripts/prototype_audio.gd"]
var game
var source
var output_dir := ""
var label := "reflection-impact"
var enemy_kind := "boss"
var shot_kind := "missile"
var review_speed := 30.0
var source_distance := 12.0
var rendered := false
var clock := 0.0
var impact_time := -1.0
var guard_sent := false
var captures: Array = []
var checks: Array = []
var buffered_images: Array = []
var source_hashes: Dictionary = {}
var incoming := Vector3.ZERO
var reflected_velocity := Vector3.ZERO
var initial_material := 0
var material_at_impact := 0
var source_transform := Transform3D.IDENTITY


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): output_dir = argument.trim_prefix("--capture-dir=")
		elif argument.begins_with("--label="): label = argument.trim_prefix("--label=").validate_filename()
		elif argument.begins_with("--enemy-kind="): enemy_kind = argument.trim_prefix("--enemy-kind=")
		elif argument.begins_with("--projectile-kind="): shot_kind = argument.trim_prefix("--projectile-kind=")
		elif argument.begins_with("--speed="): review_speed = clampf(float(argument.trim_prefix("--speed=")),18.0,60.0)
		elif argument.begins_with("--distance="): source_distance = clampf(float(argument.trim_prefix("--distance=")),6.0,30.0)
	if output_dir.is_empty(): output_dir = ProjectSettings.globalize_path("res://builds/reflection-review").path_join(label)
	call_deferred("_run")


func _v3(value: Vector3) -> Array:
	return [value.x,value.y,value.z]


func _particle_nodes() -> Array:
	var result: Array = []
	for enemy in game.enemies:
		if not is_instance_valid(enemy): continue
		for child in enemy.get_children():
			if child.is_queued_for_deletion(): continue
			if child.get_meta("voxel_piece",false) or child.get_meta("cut_chip",false) or child.get_meta("cut_particle_batch",false):
				child.set_process(false)
				result.append(child)
	return result


func _step() -> void:
	var stopped: bool = game.hit_stop > 0.0
	game.hit_stop = maxf(0.0,game.hit_stop-STEP)
	var sim_dt := 0.0 if stopped else STEP
	clock += STEP
	game.real_clock += STEP
	game.game_clock += sim_dt
	if game.has_method("_update_guard"):
		game._update_guard(STEP,sim_dt)
	else:
		game.guard_cooldown = maxf(0.0,game.guard_cooldown-STEP)
		if game.guard_remaining > 0.0:
			game.guard_remaining = maxf(0.0,game.guard_remaining-sim_dt)
			game.guard_age += sim_dt
	game.run_distance += game.speed*sim_dt
	game._update_road(sim_dt)
	game._update_blasts(sim_dt)
	game._update_projectiles(sim_dt)
	game.sword._process(STEP)
	game.parry_pulse = maxf(0.0,game.parry_pulse-STEP*5.5)
	game.kill_pulse = maxf(0.0,game.kill_pulse-STEP*4.8)
	game.impact_strength = maxf(0.0,game.impact_strength-STEP*7.5)
	game._update_impact_effects(sim_dt,0.0 if stopped else STEP)
	for enemy in game.enemies:
		if not is_instance_valid(enemy): continue
		enemy.set_meta("simulation_scale",0.0 if stopped else 1.0)
		enemy.set_meta("runner_speed",game.speed)
		enemy.set_meta("flythrough_enabled",true)
		enemy.set_meta("root_motion_velocity",Vector3.ZERO)
	for child in _particle_nodes():
		if child.has_method("_process"): child._process(STEP)
	game.camera.position = Vector3(0,1.75,0)
	game.camera.rotation = Vector3.ZERO
	game.camera.fov = 78.0
	# The transform is held, not translated to catch the returning shot.
	if is_instance_valid(source): source.transform = source_transform
	if impact_time < 0.0:
		for event in game.combat_events:
			if event.event == "projectile_explosion" and bool(event.get("reflected",false)):
				impact_time = clock
				material_at_impact = source.get_remaining_voxel_count()
				break


func _capture(stage: String) -> void:
	_particle_nodes()
	await process_frame
	if rendered: await RenderingServer.frame_post_draw
	var path := output_dir.path_join(label+"-"+stage+".png")
	if rendered: buffered_images.append({"path":path,"image":game.get_viewport().get_texture().get_image()})
	var shots: Array = []
	for shot in game.projectiles:
		shots.append({"kind":shot.kind,"reflected":shot.reflected,"position":_v3(shot.node.global_position),"velocity":_v3(shot.velocity),"age":shot.age})
	var blasts: Array = []
	for blast in game.blasts:
		var info: Dictionary = blast.get_debug_state() if blast.has_method("get_debug_state") else {"age":blast._ages,"life":blast._life,"instance_count":blast._instances.instance_count}
		info["world_position"] = _v3(blast.global_position)
		blasts.append(info)
	var pieces: Array = []
	for child in source.get_children():
		if child.get_meta("voxel_piece",false) and not child.is_queued_for_deletion(): pieces.append({"cells":child.get_voxel_count(),"position":_v3(child.global_position)})
	var events: Array = []
	for index in range(maxi(0,game.combat_events.size()-12),game.combat_events.size()): events.append(game.combat_events[index])
	captures.append({"stage":stage,"path":path if rendered else "","clock":clock,"world_clock":game.game_clock,"impact_age":clock-impact_time if impact_time >= 0.0 else -1.0,"health":game.health,"kills":game.kills,"initial_material":initial_material,"remaining_material":source.get_remaining_voxel_count(),"remaining_body_material":source._voxels.size()-source._voxels.count(0),"dead":source.dead,"projectiles":shots,"blasts":blasts,"fragments":pieces,"recent_events":events})


func _guard_button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _run() -> void:
	rendered = DisplayServer.get_name() != "headless"
	if rendered:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280,720)
	Engine.max_fps = 120
	Input.use_accumulated_input = false
	DirAccess.make_dir_recursive_absolute(output_dir)
	for path in SOURCE_FILES: source_hashes[path] = FileAccess.get_sha256(path)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.test_mode = true
	game.set_process(false)
	game.sword.set_process(false)
	while not game.menu_prepared:
		await process_frame
		if rendered: await RenderingServer.frame_post_draw
	game.start_game()
	game.practice = false
	game.training = false
	game.spawn_timer = 999.0
	game.speed = review_speed
	game.gear = game.gear_for_speed(review_speed)
	game.message_timer = 0.0
	game.hud.visible = false
	game.camera.position = Vector3(0,1.75,0)
	game.camera.rotation = Vector3.ZERO
	game.camera.fov = 78.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	source = game._spawn_enemy(enemy_kind,1,-source_distance)
	source.position.x = 0.0
	source.set_meta("aim_target",game.camera.global_position)
	for index in range(60):
		source.age += STEP
		source.set_action("ranged_charge",1.0)
	source_transform = source.transform
	initial_material = source.get_remaining_voxel_count()
	await _capture("00-before")
	var origins: Array = source.get_ranged_origins()
	if origins.is_empty():
		push_error("Review source has no actual ranged emitter")
		quit(2)
		return
	game._spawn_projectile(origins[0],shot_kind,source)
	incoming = game.projectiles[0].velocity
	await _capture("01-fired")
	var near_captured := false
	var reflected_captured := false
	while clock < 4.0 and impact_time < 0.0:
		if not game.projectiles.is_empty():
			var shot: Dictionary = game.projectiles[0]
			if not bool(shot.reflected):
				var time_to_plane: float = (-0.9-shot.node.global_position.z)/maxf(shot.velocity.z,0.001)
				if time_to_plane <= 0.075 and not guard_sent:
					await _capture("02-incoming-near")
					_guard_button(true)
					guard_sent = true
					if not game.has_method("_update_guard"): _guard_button(false)
			elif not reflected_captured:
				if game.has_method("_update_guard"): _guard_button(false)
				reflected_velocity = shot.velocity
				await _capture("03-parry-return")
				reflected_captured = true
			elif not near_captured and shot.node.global_position.z < -source_distance*0.5:
				await _capture("04-return-approach")
				near_captured = true
		_step()
		await process_frame
		if rendered: await RenderingServer.frame_post_draw
	await _capture("05-impact-initial")
	for milliseconds in [33,83,167,333,600,900]:
		while impact_time >= 0.0 and clock-impact_time < float(milliseconds)/1000.0-0.00001:
			_step()
			await process_frame
			if rendered: await RenderingServer.frame_post_draw
		await _capture("06-impact-%03dms" % milliseconds)
	checks.append({"label":"parsed right-click produced a physical reflected shot","passed":guard_sent and reflected_captured})
	checks.append({"label":"returned velocity exactly reverses incoming snapshot at 1.4","passed":reflected_velocity.distance_to(-incoming*1.4) < 0.0001})
	checks.append({"label":"returned shot detonated at real solid geometry without player harm","passed":impact_time >= 0.0 and game.health == 5})
	checks.append({"label":"held source was not relocated to intercept the return","passed":source.transform == source_transform})
	var after: Dictionary = {}
	for path in SOURCE_FILES: after[path] = FileAccess.get_sha256(path)
	checks.append({"label":"runtime sources unchanged","passed":after == source_hashes})
	for item in buffered_images: item.image.save_png(item.path)
	var failures := 0
	for check in checks:
		if not bool(check.passed): failures += 1
	var report := {"label":label,"version":ProjectSettings.get_setting("application/config/version"),"rendered":rendered,"engine":Engine.get_version_info().string,"fixed_step":STEP,"enemy_kind":enemy_kind,"shot_kind":shot_kind,"speed":review_speed,"source_distance":source_distance,"incoming":_v3(incoming),"returned":_v3(reflected_velocity),"impact_time":impact_time,"initial_material":initial_material,"material_at_impact":material_at_impact,"removed_at_impact":initial_material-material_at_impact,"source_hashes_before":source_hashes,"source_hashes_after":after,"tool_sha256":FileAccess.get_sha256(get_script().resource_path),"checks":checks,"failures":failures,"captures":captures,"scope":"Controlled held-source actual projectile flight and parsed right-click through production input / swept first-solid collision / production voxel blast. Manual fixed simulation stepping includes road, hit-stop, blast and actual fragment / particle nodes. Shooter position and firing pose are held; enemy AI and route spawns suppressed. Camera fixed forward / HUD hidden only for inspection. Rendered screenshots are for human review; CPU instance debug is not GPU visibility, normal combat, performance or subjective feedback acceptance."}
	var file := FileAccess.open(output_dir.path_join("reflection-impact.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("REFLECTION IMPACT REVIEW ",label," checks=",checks.size()," failures=",failures," removed=",initial_material-material_at_impact)
	game._pause_game()
	game.audio.set_runner_motion(0,0,false,0)
	await create_timer(0.25).timeout
	game.free()
	await process_frame
	quit(0 if failures == 0 else 1)
