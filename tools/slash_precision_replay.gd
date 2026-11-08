extends SceneTree
## Parsed pointer gestures against stationary precision fixtures, not a difficulty bot.

var game
var label := "current"
var output_dir := ""
var results: Array = []
var render_enabled := false
var heavy_enabled := false
var heavy_fixture := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--precision-label="):
			label = arg.trim_prefix("--precision-label=").validate_filename()
		elif arg.begins_with("--capture-dir="):
			output_dir = arg.trim_prefix("--capture-dir=")
		elif arg == "--heavy-precision":
			heavy_enabled = true
	if output_dir.is_empty():
		output_dir = ProjectSettings.globalize_path("res://builds/slash-precision-review")
	call_deferred("_run")


func _motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	var mapping: Transform2D = game.get_viewport().get_final_transform()
	event.relative = relative * mapping.get_scale()
	event.screen_relative = event.relative
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _step(seconds: float = 0.016) -> void:
	if heavy_fixture:
		# Keep the already-entered held mode at the requested gear. Advancing
		# F4/training would force gear 4; these are stationary material fixtures,
		# not normal combat. Parsed input still uses the production consumer.
		game._consume_strokes()
	else:
		game._process(seconds)
	game.sword._process(seconds)


func _active_point(grip: Vector2, axis: Vector2) -> Vector2:
	var view_size: Vector2 = game.get_viewport().get_visible_rect().size
	if game.sword.has_method("active_cut_point_for_grip"):
		return game.sword.active_cut_point_for_grip(grip, axis, view_size)
	if game.sword.has_method("blade_segment_for_grip"):
		# Historical v0.4 has the same physical edge but no narrowed contact helper.
		var segment: PackedVector2Array = game.sword.blade_segment_for_grip(grip, axis, view_size)
		return segment[0].lerp(segment[1], (0.52 - 0.025) / (0.86 - 0.025))
	return grip # Historical v0.3 cursor was the actual narrow cut point.


func _settled_axis() -> Vector2:
	# A rightward stroke now leads with the hilt. Keep the old horizontal
	# warm-up convention only when loading the actual historical packages.
	return Vector2.LEFT if game.sword.has_method("get_light_slash_count") else Vector2.UP


func _contact_after_motion(grip: Vector2) -> Vector2:
	var axis: Vector2 = game.sword.resolve_blade_axis(game.blade_direction, grip - game.slash_cursor)
	return _active_point(grip, axis)


func _grip_for_next_contact(contact: Vector2) -> Vector2:
	# A reversed hilt gesture turns the blade and does not retrace its kerf.
	# Invert that same live geometry for this stationary precision fixture,
	# then send real pointer motion; no cut or voxel operation is injected.
	var grip: Vector2 = game.slash_cursor + contact - _contact_after_motion(game.slash_cursor)
	for iteration in range(12):
		var at: Vector2 = _contact_after_motion(grip)
		var error: Vector2 = at - contact
		if error.length() < 0.001:
			break
		var dx: Vector2 = _contact_after_motion(grip + Vector2.RIGHT) - at
		var dy: Vector2 = _contact_after_motion(grip + Vector2.DOWN) - at
		var determinant: float = dx.cross(dy)
		if absf(determinant) < 0.00001:
			break
		var correction := Vector2(error.cross(dy), dx.cross(error)) / determinant
		grip -= correction.limit_length(24.0)
	return grip


func _prepare(grip_start: Vector2) -> void:
	_button(false)
	game.training = true
	game.start_game()
	game.training = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.spawn_timer = 999.0
	game.speed = 48.0
	game.gear = 4
	game.camera.rotation = Vector3.ZERO
	game.camera.position = Vector3(0, 1.75, 0)
	game.camera.fov = 78.0
	game.sword.set_pose("sheathed")
	game.sword._process(0.02)
	_button(true)
	_step(0.15)
	_motion((grip_start - Vector2(260, 0) - game.slash_cursor) / 1.05)
	_step()
	_motion(Vector2(260.0 / 1.05, 0))
	_step()


func _capture(name: String) -> void:
	if not render_enabled:
		return
	await process_frame
	await RenderingServer.frame_post_draw
	game.get_viewport().get_texture().get_image().save_png(output_dir.path_join(label + "-" + name + ".png"))


func _case(case_name: String, start: Vector2, deltas: Array, aimed_point: Vector3 = Vector3.INF, kind: String = "normal", gear: int = 4, stop_on_death: bool = false) -> void:
	heavy_fixture = false
	_prepare(start)
	var target_z := -16.0 if kind == "boss" else -9.0
	if aimed_point.is_finite():
		var cut_screen: Vector2 = game.camera.unproject_position(Vector3(aimed_point.x, aimed_point.y, target_z + aimed_point.z))
		var grip: Vector2
		if game.sword.has_method("grip_for_active_cut_point"):
			# The current blade has true depth and lean, so a constant planar
			# screen offset cannot align the same contact point at every grip.
			grip = game.sword.grip_for_active_cut_point(cut_screen, _settled_axis(), game.get_viewport().get_visible_rect().size)
		else:
			grip = cut_screen - _active_point(Vector2.ZERO, _settled_axis())
		# Calibrate this already-adopted pose without restarting an attack: a
		# restart can legitimately inherit a different wrist angle mid-combo.
		# No target exists during the approach, and all travel is parsed input.
		_motion((grip - Vector2(520, 0) - game.slash_cursor) / 1.05)
		_step()
		_motion(Vector2(520.0 / 1.05, 0))
		_step()
	heavy_fixture = kind != "normal"
	if heavy_fixture:
		game.training = false
		game.gear = gear
		game.speed = [18.0, 30.0, 42.0, 54.0][gear - 1]
	var enemy = game._spawn_enemy(kind, 1, target_z)
	enemy.position.x = 0
	if enemy.has_method("set_action"):
		enemy.set_action("recover", 1.0)
	if heavy_fixture:
		enemy._pose(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
		enemy.set_meta("simulation_scale", 0.0)
		enemy.set_meta("flythrough_enabled", false)
	var before: int = enemy.get_remaining_voxel_count()
	var initial_grip: Vector2 = game.slash_cursor
	var initial_contact: Vector2 = _active_point(initial_grip, _settled_axis())
	await _capture(case_name + "-before")
	var cut_steps: Array = []
	var first_damage_captured := false
	for delta in deltas:
		var desired_contact := Vector2.INF
		if delta is Dictionary:
			desired_contact = initial_contact + Vector2(delta.contact_offset)
			var grip: Vector2 = _grip_for_next_contact(desired_contact)
			if _contact_after_motion(grip).distance_to(desired_contact) > 0.01:
				push_error("Precision pointer inversion did not converge: " + case_name)
				break
			_motion((grip - game.slash_cursor) / 1.05)
		else:
			_motion(Vector2(delta) / 1.05)
		_step()
		var contact_error := -1.0
		if desired_contact.is_finite():
			contact_error = _active_point(game.slash_cursor, game.blade_direction).distance_to(desired_contact)
		cut_steps.append({"remaining": enemy.get_remaining_voxel_count(), "removed": enemy.last_removed_count, "dead": enemy.dead, "gear": game.gear, "contact_error": contact_error})
		if render_enabled and heavy_fixture and stop_on_death and enemy.last_removed_count > 0:
			if not first_damage_captured or cut_steps.size() % 8 == 0 or enemy.dead:
				await _capture(case_name + "-groove-%03d" % cut_steps.size())
				first_damage_captured = true
		if stop_on_death and enemy.dead:
			break
	var chunks := 0
	var largest := 0
	for child in enemy.get_children():
		if child.get_meta("voxel_piece", false) and not child.is_queued_for_deletion():
			chunks += 1
			largest = maxi(largest, child.get_voxel_count())
	var remaining: int = enemy.get_remaining_voxel_count()
	var actual_path = game.get("last_cut_path")
	if actual_path == null:
		actual_path = game.last_path
	var entry := {"case": case_name, "kind": kind, "gear": gear, "before": before, "remaining": remaining, "removed": before - remaining, "dead": enemy.dead, "chunks": chunks, "largest_chunk": largest, "grip_from": [initial_grip.x, initial_grip.y], "grip_to": [game.slash_cursor.x, game.slash_cursor.y], "contact_start": [initial_contact.x, initial_contact.y], "actual_cut_samples": actual_path.size(), "cut_steps": cut_steps}
	results.append(entry)
	print("SLASH PRECISION ", label, " ", JSON.stringify(entry))
	await _capture(case_name + "-after")
	_button(false)
	heavy_fixture = false


func _run() -> void:
	render_enabled = DisplayServer.get_name() != "headless"
	if render_enabled:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DirAccess.make_dir_recursive_absolute(output_dir)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.test_mode = true
	game.set_process(false)
	game.sword.set_process(false)
	# Keep historical package review coordinates while locating the rebuilt
	# fine slasher by its real hand/plate/waist anatomy in metres.
	var probe = game._spawn_enemy("normal", 1, -9.0)
	var fine_normal: bool = float(probe._cell) < 0.075
	if probe.has_method("set_action"):
		probe.set_action("recover", 1.0)
	var normal_arm: Vector3 = probe._part_pose(1) * Vector3(-0.725, 1.475, 0.275) if fine_normal else Vector3(0.54, 1.48, 0)
	var normal_armor: Vector3 = probe._part_pose(0) * Vector3(0.225, 1.975, 0.35) if fine_normal else Vector3(0.28, 1.48, 0)
	var normal_waist: Vector3 = probe._part_pose(0) * Vector3(-0.9, 1.425, 0.025) if fine_normal else Vector3(-0.9, 1.27, 0)
	game.enemies.erase(probe)
	probe.free()
	await _case("same-grip-18px", Vector2(640,540), [Vector2(18,0)])
	await _case("same-grip-180px", Vector2(550,540), [Vector2(180,0)])
	await _case("same-grip-curve", Vector2(560,540), [Vector2(35,-10),Vector2(35,10),Vector2(-70,0)])
	await _case("aimed-arm-skim", Vector2.ZERO, [Vector2(5,0)], normal_arm)
	await _case("aimed-armor-18px", Vector2.ZERO, [Vector2(18,0)], normal_armor)
	await _case("aimed-waist", Vector2.ZERO, [Vector2(92,0)], normal_waist)
	if heavy_enabled:
		for kind in ["tank", "boss"]:
			for gear in [1, 4]:
				var prefix: String = kind + "-g" + str(gear)
				var core := Vector3(0, 1.925, 0.385) if kind == "tank" else Vector3(0, 2.76, 0.60)
				var neck := Vector3(0, 2.365, 0.275) if kind == "tank" else Vector3(0, 3.48, 0.36)
				var edge := Vector3(0.80, 1.925, 0.275) if kind == "tank" else Vector3(1.60, 2.76, 0.60)
				var arm := Vector3(1.14, 1.595, 0) if kind == "tank" else Vector3(2.88, 2.04, 0)
				await _case(prefix + "-core-5px", Vector2.ZERO, [Vector2(5,0)], core, kind, gear)
				await _case(prefix + "-neck-5px", Vector2.ZERO, [Vector2(5,0)], neck, kind, gear)
				await _case(prefix + "-chest-18px", Vector2.ZERO, [Vector2(18,0)], edge, kind, gear)
				await _case(prefix + "-arm-5px", Vector2.ZERO, [Vector2(5,0)], arm, kind, gear)
				var groove: Array = []
				for pass_index in range(4):
					for sample in range(1, 121):
						var offset := 150.0 * float(sample) / 120.0
						groove.append({"contact_offset": Vector2(offset if pass_index % 2 == 0 else 150.0 - offset, 0)})
				var waist := Vector3(-1.8, 1.375, 0) if kind == "tank" else Vector3(-2.2, 2.04, 0)
				await _case(prefix + "-waist-repeated", Vector2.ZERO, groove, waist, kind, gear, true)
	var file := FileAccess.open(output_dir.path_join(label + "-precision.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":label,"fixtures":results,"scope":"Actual parsed pointer gestures against stationary fixtures; not a normal-play difficulty or human feel verdict."}, "\t"))
	game._pause_game()
	game.audio.set_runner_motion(0.0, 0.0, false, 0.0)
	await create_timer(1.0).timeout
	game.free()
	game = null
	await create_timer(0.15).timeout
	quit()
