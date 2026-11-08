extends "held_fx_verify.gd"
## Small fixed-input rendered companion to the material / geometry comparison.
## Uses the same actual mouse route; AI is explicitly held for legible pictures.

var capture_dir := ""
var label := "held-fx"
var captures: Array = []
var images: Array = []
var clock := 0.0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
		elif argument.begins_with("--label="): label = argument.trim_prefix("--label=").validate_filename()
	if capture_dir.is_empty(): capture_dir = ProjectSettings.globalize_path("res://builds/held-fx-review-v094").path_join(label)
	call_deferred("_run")


func _frame(delta: float = STEP, advance_particles: bool = true) -> void:
	_step(delta,advance_particles)
	clock += delta
	await process_frame
	if rendered: await RenderingServer.frame_post_draw


func _brief_particles(enemy) -> Dictionary:
	var debug: Dictionary = enemy.get_cut_particle_debug_state()
	var brief: Dictionary = {}
	for key in ["active_count","capacity","global_active_count","global_capacity","emitted_total","emitted_body","emitted_sever","emitted_debris","held_emitted_total","standard_emitted_total","last_feedback_mode","last_burst_count","last_base_burst_count","last_requested_burst_count","last_layer_counts","active_layer_counts","size_min","size_max","shape_samples","simulation_scale"]:
		if debug.has(key): brief[key] = debug[key]
	return _plain(brief)


func _capture(stage: String, enemy = null) -> void:
	_manual_nodes()
	await process_frame
	if rendered: await RenderingServer.frame_post_draw
	var path := capture_dir.path_join(label+"-"+stage+".png")
	if rendered: images.append({"path":path,"image":game.get_viewport().get_texture().get_image()})
	var row := {"stage":stage,"path":path if rendered else "","clock":clock,"world_clock":game.game_clock,"state":game.state,"training_ai_freeze":game.training,"geometry":_geometry(stage),"blade_fx":_blade_fx(),"health":game.health,"kills":game.kills,"score":game.score}
	if is_instance_valid(enemy):
		row["material"] = _material(enemy)
		row["particles"] = _brief_particles(enemy)
	captures.append(row)


func _run() -> void:
	rendered = DisplayServer.get_name() != "headless"
	if rendered:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280,720)
	Engine.max_fps = 60
	DirAccess.make_dir_recursive_absolute(capture_dir)
	await _setup_game()
	_reset()
	game.hud.visible = false
	_button(true)
	await _frame(0.04)
	await _capture("00-light")
	await _frame(0.12)
	await _capture("01-held-takeover")
	for index in range(12):
		_motion(Vector2(10,-4.0*sin(float(index)*0.28))/1.05)
		await _frame()
	await _capture("02-curve")
	for index in range(12):
		_motion(Vector2(-12,4.0*cos(float(index)*0.28))/1.05)
		await _frame()
	await _capture("03-reversal")
	var axis: Vector2 = game.sword.get_blade_screen_direction()
	for index in range(12): await _frame()
	await _capture("04-stopped-cursor")
	expect(axis.dot(game.sword.get_blade_screen_direction()) > 0.999,"review stopped hilt retains its last physical blade direction")
	game.hit_stop = 0.12
	var fx_before := _blade_fx()
	var grip_before: Vector2 = game.sword.get_grip_screen_position()
	_motion(Vector2(28,14)/1.05)
	await _frame()
	var fx_after := _blade_fx()
	await _capture("05-hit-stop-input")
	expect(game.sword.get_grip_screen_position().distance_to(grip_before) > 10.0,"review actual mouse input still moves the hilt during hit-stop")
	if game.sword.has_method("get_held_voxel_fx_debug_state"):
		expect(fx_before.cpu_instance_sha256 == fx_after.cpu_instance_sha256 and fx_before.phase == fx_after.phase,"review hit-stop freezes submitted local blade voxels while its parent follows input")
	_key(KEY_ESCAPE)
	await _frame()
	await _capture("06-paused")
	fx_before = _blade_fx()
	for index in range(5): await _frame()
	fx_after = _blade_fx()
	if game.sword.has_method("get_held_voxel_fx_debug_state"):
		expect(fx_before.cpu_instance_sha256 == fx_after.cpu_instance_sha256 and fx_before.phase == fx_after.phase,"review pause freezes blade voxel phase and local submission")
	_key(KEY_ESCAPE)
	_button(false)
	await _frame()
	# The next scenes use the same actual parsed precision gestures as the
	# regression fixture; no F4, hidden critical-tag aim or forced death flag.
	_reset()
	var probe = _target()
	var arm_point: Vector3 = probe.to_global(probe._part_pose(1)*Vector3(-0.725,1.475,0.275))
	_precision_ready(arm_point)
	var enemy = _target()
	var before: int = enemy.get_remaining_voxel_count()
	_motion(Vector2(5.0/1.05,0))
	await _frame(0.016,false)
	await _capture("07-held-arm-contact",enemy)
	expect(enemy.get_remaining_voxel_count() < before and not enemy.dead,"review held arm contact is a real shallow wound")
	for index in range(5): await _frame()
	await _capture("08-contact-83ms",enemy)
	_reset()
	probe = _target()
	var waist_point: Vector3 = probe.to_global(probe._part_pose(0)*Vector3(-0.9,1.425,0.025))
	_precision_ready(waist_point)
	enemy = _target()
	_motion(Vector2(92.0/1.05,0))
	await _frame(0.016,false)
	await _capture("09-real-sever",enemy)
	expect(enemy.dead and game.kills == 1,"review waist gesture really severs the material connection exactly once")
	for index in range(5): await _frame()
	await _capture("10-sever-83ms",enemy)
	var before_recut: int = enemy.get_remaining_voxel_count()
	var score: int = game.score
	var largest = null
	for piece in enemy.get_children():
		if piece.get_meta("voxel_piece",false) and not piece.is_queued_for_deletion() and (largest == null or piece.get_voxel_count() > largest.get_voxel_count()): largest = piece
	if is_instance_valid(largest):
		var screen: Vector2 = game.camera.unproject_position(largest.get_aim_point())
		var desired: Vector2 = game.sword.grip_for_active_cut_point(screen,Vector2.LEFT,game.get_viewport().get_visible_rect().size)
		_motion((desired-Vector2(120,0)-game.slash_cursor)/1.05)
		await _frame(0.016,false)
		_motion(Vector2(180.0/1.05,0))
		await _frame(0.016,false)
	await _capture("11-parsed-debris-recut",enemy)
	expect(enemy.get_remaining_voxel_count() < before_recut and game.kills == 1 and game.score == score,"review parsed mouse gesture recuts true debris without another kill or score")
	for index in range(5): await _frame()
	await _capture("12-recut-83ms",enemy)
	var after: Dictionary = {}
	for path in SOURCE_FILES: after[path] = FileAccess.get_sha256(path)
	expect(source_hashes == after,"review runtime source hashes stay unchanged")
	for item in images: item.image.save_png(item.path)
	var report := {"label":label,"version":ProjectSettings.get_setting("application/config/version"),"engine":Engine.get_version_info().string,"rendered":rendered,"fixed_step":STEP,"checks":checks,"failures":failures,"captures":captures,"source_hashes_before":source_hashes,"source_hashes_after":after,"tool_sha256":FileAccess.get_sha256(get_script().resource_path),"base_tool_sha256":FileAccess.get_sha256(get_script().resource_path.get_base_dir().path_join("held_fx_verify.gd")),"scope":"Fixed-pose / suppressed-AI actual parsed light-to-held, curved and reversed input, stopped cursor, hit-stop, Escape pause, actual shallow material hit, structural sever and parsed debris recut. No F4; training-style simulation freeze is explicit and is not normal combat or a performance run. Limited rendered frames require human visual assessment; CPU debug signatures are not GPU visibility or subjective luxury approval."}
	var file := FileAccess.open(capture_dir.path_join("held-fx-review.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("HELD FX REVIEW ",label," captures=",captures.size()," checks=",checks.size()," failures=",failures)
	game._pause_game()
	game.audio.set_runner_motion(0,0,false,0)
	await create_timer(0.5).timeout
	game.free()
	await process_frame
	await process_frame
	quit(0 if failures == 0 else 1)
