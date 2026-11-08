extends SceneTree
## Local material/input fixtures. Normal encounter timing is reviewed separately.

const STEP := 1.0/60.0
var game
var output_path := ""
var baseline_only := false
var checks: Array = []
var records: Array = []
var failures := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output_path = arg.trim_prefix("--output=")
		elif arg == "--baseline-only": baseline_only = true
	call_deferred("_run")


func expect(passed: bool, label: String) -> void:
	checks.append({"passed":passed,"label":label})
	if passed: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)


func _button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
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


func _step(delta: float = STEP) -> void:
	game._process(delta)
	game.sword._process(delta)
	for enemy in game.enemies:
		for node in enemy.get_children():
			if node.get_meta("voxel_piece",false) or node.get_meta("cut_particle_batch",false): node.set_process(false)


func _fresh(gear_value: int = 4):
	_button(false)
	for enemy in game.enemies:
		if is_instance_valid(enemy): enemy.free()
	game.enemies.clear()
	game._clear_projectiles()
	game.training = true
	game.start_game()
	game.training = true
	game.spawn_timer = 999.0
	game.speed = [18.0,28.0,40.0,56.0][gear_value-1]
	game.gear = gear_value
	game.camera.position = Vector3(0,1.75,0)
	game.camera.rotation = Vector3.ZERO
	game.camera.fov = 78.0
	var enemy = game._spawn_enemy("boss",0,-12.0)
	enemy.position.x = 0.0
	enemy.set_action("recover",1.0)
	# Keep the previous central view for the actual-PCK baseline comparison;
	# new aim helpers do not turn the test into an automatic reactor shot.
	game.camera.look_at(enemy.to_global(Vector3(0,2.97,0.39)))
	game.sword.set_pose("sheathed")
	game.sword._process(0.8)
	return enemy


func _reactors(enemy) -> Dictionary:
	if not enemy.has_method("get_boss_reactor_state"): return {"legacy":true}
	var state: Dictionary = enemy.get_boss_reactor_state()
	state.erase("world_positions")
	return state


func _local_line(enemy, y: float) -> Dictionary:
	var a: Vector2 = game.camera.unproject_position(enemy.to_global(Vector3(-1.8,y,0.32)))
	var b: Vector2 = game.camera.unproject_position(enemy.to_global(Vector3(1.8,y,0.32)))
	return enemy.cut_screen(game.camera,a,b,2.15)


func _steer_contact(target: Vector2) -> void:
	var size: Vector2 = game.get_viewport().get_visible_rect().size
	var current: Vector2 = game.slash_cursor
	var best := Vector2.ZERO
	var best_error := INF
	for radius in [4.0,14.0,36.0,65.0]:
		for index in range(16):
			var relative := Vector2.from_angle(float(index)*TAU/16.0)*float(radius)
			relative = (current+relative).clamp(Vector2(2,2),size-Vector2(2,2))-current
			var axis: Vector2 = game.sword.resolve_blade_axis(game.blade_direction,relative)
			var contact: Vector2 = game.sword.active_cut_point_for_grip(current+relative,axis,size)
			var error := contact.distance_squared_to(target)
			if error < best_error:
				best_error = error
				best = relative
	_motion(best/1.05)


func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.sword.set_process(false)
	var enemy = _fresh()
	var initial: int = enemy.get_remaining_voxel_count()
	var neck_removed := 0
	for i in range(20):
		neck_removed += int(_local_line(enemy,3.70).removed)
		if enemy.dead: break
	records.append({"case":"neck_repeated","initial":initial,"removed":neck_removed,"dead":enemy.dead,"reactors":_reactors(enemy)})
	if not baseline_only: expect(neck_removed > 0 and not enemy.dead and not bool(enemy.get_boss_reactor_state().sensor_connected),"real sensor-neck sever detaches material without killing two connected reactors")
	enemy = _fresh()
	initial = enemy.get_remaining_voxel_count()
	var blast: Dictionary = enemy.blast_at(enemy.to_global(Vector3(0,2.98,0.39)),1.45)
	records.append({"case":"original_central_missile_blast","initial":initial,"removed":blast.removed,"dead":enemy.dead,"reactors":_reactors(enemy)})
	if not baseline_only: expect(int(blast.removed) > 0 and not enemy.dead and enemy.get_remaining_voxel_count() == initial-int(blast.removed),"strong central missile still removes its exact real sphere without erasing both deep power cassettes")
	for gear_value in range(1,5):
		enemy = _fresh(gear_value)
		initial = enemy.get_remaining_voxel_count()
		var death_frame := -1
		for frame in range(60):
			if frame % 6 == 0:
				_button(true)
				_button(false)
			_step()
			if enemy.dead:
				death_frame = frame
				break
		var removed: int = initial-enemy.get_remaining_voxel_count()
		records.append({"case":"immediate_10hz_combo","gear":gear_value,"frames":60 if death_frame < 0 else death_frame+1,"removed":removed,"dead":enemy.dead,"light_inputs":game.combat_stats.get("light_slashes",0),"reactors":_reactors(enemy)})
		if not baseline_only: expect(removed > 0 and not enemy.dead,"gear"+str(gear_value)+" immediate one-second 10Hz real light combo damages armour and cannot skip both power cassettes")
	for gear_value in [1,4]:
		enemy = _fresh(gear_value)
		initial = enemy.get_remaining_voxel_count()
		_button(true)
		_step(0.15)
		var center: Vector2 = game.camera.unproject_position(enemy.to_global(Vector3(0,3.0,0.4)))
		var targets := [center+Vector2(-125,-50),center+Vector2(125,50),center+Vector2(-125,50),center+Vector2(125,-50)]
		var target_index := 0
		var death_frame := -1
		for frame in range(120):
			_steer_contact(targets[target_index])
			_step()
			var contact: Vector2 = game.sword.active_cut_point_for_grip(game.slash_cursor,game.blade_direction,game.get_viewport().get_visible_rect().size)
			if contact.distance_to(targets[target_index]) < 20.0: target_index = (target_index+1)%targets.size()
			if enemy.dead:
				death_frame = frame
				break
		_button(false)
		var removed: int = initial-enemy.get_remaining_voxel_count()
		records.append({"case":"immediate_two_second_held","gear":gear_value,"frames":120 if death_frame < 0 else death_frame+1,"removed":removed,"dead":enemy.dead,"held_seconds":game.combat_stats.slash_time,"reactors":_reactors(enemy)})
		if not baseline_only: expect(removed > 0 and not enemy.dead and float(game.combat_stats.slash_time) > 0.5,"gear"+str(gear_value)+" two-second real hilt-driven crossing slash carves material without a central instant kill")
	if not baseline_only:
		enemy = _fresh()
		initial = enemy.get_remaining_voxel_count()
		var state: Dictionary = enemy.get_boss_reactor_state()
		var first: Dictionary = enemy.blast_at(state.world_positions[0],0.80)
		var after_first: Dictionary = _reactors(enemy)
		expect(int(first.removed) > 0 and not enemy.dead and int(after_first.connected) == 1,"physical sphere destroying one entire real reactor leaves the independent connected reactor alive")
		expect(Vector2(enemy._material.get_shader_parameter("boss_reactor_power")) == Vector2(0,1),"one real reactor loss switches off only its actual inset port shader power")
		var second: Dictionary = enemy.blast_at(enemy.get_boss_reactor_state().world_positions[1],0.80)
		var remaining: int = enemy.get_remaining_voxel_count()
		expect(int(second.removed) > 0 and enemy.dead and int(enemy.get_boss_reactor_state().connected) == 0 and game.kills == 1,"destruction of both actual power regions ends the Boss and scores exactly once")
		expect(Vector2(enemy._material.get_shader_parameter("boss_reactor_power")) == Vector2.ZERO,"both inset port power flags follow actual disconnected material instead of a hit counter")
		expect(remaining == initial-int(first.removed)-int(second.removed),"dual-reactor structural defeat retains every uncut voxel as real re-cuttable debris")
		var score: int = game.score
		var recut := 0
		for i in range(10): recut += int(_local_line(enemy,2.90+float(i)*0.04).removed)
		expect(recut > 0 and game.kills == 1 and game.score == score and enemy.get_remaining_voxel_count() == remaining-recut,"Boss residual material can be cut again without another kill or reward")
		records.append({"case":"independent_reactors","first":after_first,"first_removed":first.removed,"second_removed":second.removed,"recut_removed":recut,"kills":game.kills})
	var report := {"version":ProjectSettings.get_setting("application/config/version"),"baseline_only":baseline_only,"checks":checks,"failures":failures,"records":records,"tool_sha256":FileAccess.get_sha256(get_script().resource_path),"scope":"Headless controlled stationary material and parsed-input fixtures. No practice health is used, training freezes translation only; not a normal-play/performance/human-feel verdict. Central view, input timing and contact steering stay the same in old/new packs."}
	if not output_path.is_empty():
		DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
		var file := FileAccess.open(output_path,FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"\t"))
	print("BOSS RESILIENCE: ",checks.size()," checks / ",failures," failures")
	game.free()
	await create_timer(1.0).timeout
	quit(0 if failures == 0 else 1)
