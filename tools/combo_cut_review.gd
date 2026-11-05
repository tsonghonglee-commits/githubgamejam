extends SceneTree
## Fixed-time real input evidence for the twelve styles, hilt-leading drag and metal sparks.
## These deliberately stationary fixtures are separate from normal combat and performance.

const STEP := 1.0 / 60.0
const END_FRAME := 830
const STYLE_START := 12
const STYLE_STRIDE := 28
const FAST_START := 366
const DRAG_START := 520
const CUT_FRAME := 735
const DIRECTIONS: Array[Vector2] = [Vector2.RIGHT, Vector2(0.70710678, 0.70710678), Vector2.DOWN, Vector2(-0.70710678, 0.70710678), Vector2.LEFT, Vector2(-0.70710678, -0.70710678), Vector2.UP, Vector2(0.70710678, -0.70710678)]

var game
var frame := -1
var label := "v070"
var output_dir := ""
var render_enabled := false
var running := false
var inputs: Array = []
var samples: Array = []
var attacks: Array = []
var drag_checks: Array = []
var particle_checks: Array = []
var captures: Array[String] = []
var overlay: Label
var target
var particle_grip := Vector2.ZERO
var cut_score := 0
var source_hashes: Dictionary = {}
var include_runner := false
var end_frame := END_FRAME
var particles_only := false
var first_frame := 0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--review-label="):
			label = argument.trim_prefix("--review-label=").validate_filename()
		elif argument.begins_with("--capture-dir="):
			output_dir = argument.trim_prefix("--capture-dir=")
		elif argument == "--include-runner":
			include_runner = true
			end_frame = 1190
		elif argument == "--particles-only":
			particles_only = true
			first_frame = 720
			frame = 719
	if output_dir.is_empty():
		output_dir = ProjectSettings.globalize_path("res://builds/combo-cut-review").path_join(label)
	if "--sheets-only" in OS.get_cmdline_user_args():
		call_deferred("_write_existing_sheets")
		return
	call_deferred("_begin")


func _begin() -> void:
	render_enabled = DisplayServer.get_name() != "headless"
	if render_enabled:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(output_dir)
	for path in ["res://scenes/main.tscn", "res://scripts/main.gd", "res://scripts/katana_view.gd", "res://scripts/voxel_enemy.gd", "res://scripts/voxel_debris.gd", "res://scripts/prototype_hud.gd", "res://scripts/prototype_audio.gd"]:
		source_hashes[path] = FileAccess.get_sha256(path)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.test_mode = true
	game.set_process(false)
	game.sword.set_process(false)
	_restart_fixture()
	var layer := CanvasLayer.new()
	layer.layer = 60
	root.add_child(layer)
	overlay = Label.new()
	overlay.position = Vector2(12, 686)
	overlay.add_theme_font_size_override("font_size", 16)
	overlay.add_theme_color_override("font_shadow_color", Color.BLACK)
	overlay.add_theme_constant_override("shadow_outline_size", 5)
	layer.add_child(overlay)
	RenderingServer.frame_post_draw.connect(_post_draw)
	running = true


func _restart_fixture() -> void:
	game._reset_input()
	game.start_game()
	game.training = true
	game.practice = false
	game.spawn_timer = 999.0
	game.speed = 48.0
	game.gear = 4
	game.camera.rotation = Vector3.ZERO
	game.camera.position = Vector3(0, 1.75, 0)
	game.camera.fov = 78.0
	game.aim_angles = Vector2.ZERO
	game.message_timer = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	var serial_before: int = game.cut_serial
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	inputs.append({"frame": frame, "kind": "button", "pressed": pressed})
	if pressed:
		var snapshot := _snapshot()
		snapshot["new_cut_on_press"] = game.cut_serial - serial_before
		snapshot["definition"] = game.sword.get_light_slash_definition(game.quick_slash_style)
		attacks.append(snapshot)


func _motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	var mapping: Transform2D = game.get_viewport().get_final_transform()
	event.relative = relative * mapping.get_scale()
	event.screen_relative = event.relative
	event.position = mapping * game.slash_cursor
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	inputs.append({"frame": frame, "kind": "motion", "relative": _v2(relative)})


func _move_grip_to(point: Vector2) -> void:
	_motion((point - game.slash_cursor) / 1.05)


func _process(_delta: float) -> bool:
	if not running:
		return false
	frame += 1
	if frame >= end_frame:
		running = false
		_finish.call_deferred()
		return false
	if frame >= STYLE_START and frame < STYLE_START + 12 * STYLE_STRIDE:
		var local := (frame - STYLE_START) % STYLE_STRIDE
		var style := (frame - STYLE_START) / STYLE_STRIDE
		if local == 0:
			_button(true)
			_capture("style-%02d-000ms" % style)
		if local == 1:
			_button(false)
		if local == 2:
			_capture("style-%02d-033ms" % style)
		if local == 1:
			_capture("style-%02d-017ms" % style)
		if local == 3:
			_capture("style-%02d-050ms" % style)
		if local == 5:
			_capture("style-%02d-083ms" % style)
		if local == 9:
			_capture("style-%02d-150ms" % style)
	if frame == 360:
		_restart_fixture()
	if frame >= FAST_START and frame < FAST_START + 24 * 5:
		var local := (frame - FAST_START) % 5
		if local == 0:
			_button(true)
		elif local == 1:
			_button(false)
		if frame in [FAST_START, FAST_START + 11 * 5, FAST_START + 23 * 5]:
			_capture("fast-click-%02d" % ((frame - FAST_START) / 5))
	if frame == 500 or frame == 720:
		_restart_fixture()
		_button(true)
	if frame >= DRAG_START and frame < DRAG_START + DIRECTIONS.size() * 18:
		var local := (frame - DRAG_START) % 18
		var index := (frame - DRAG_START) / 18
		if local == 0:
			_move_grip_to(Vector2(640, 400))
		elif local == 1:
			_motion(DIRECTIONS[index] * (260.0 / 1.05))
		elif local == 2:
			_capture("drag-%02d-moving" % index)
		elif local == 10:
			drag_checks.append({"frame": frame, "direction": _v2(DIRECTIONS[index]), "tip_trailing_dot": game.sword.get_blade_screen_direction().dot(-DIRECTIONS[index]), "grip_error": game.sword.get_grip_screen_position().distance_to(game.slash_cursor)})
			_capture("drag-%02d-stopped" % index)
	if frame == 666:
		_move_grip_to(Vector2(640, 400))
	elif frame == 667:
		_motion(Vector2(260.0 / 1.05, 0))
	elif frame == 668:
		_motion(Vector2(-1.0 / 1.05, 0))
		_capture("reverse-001px")
	elif frame == 669:
		_motion(Vector2(-260.0 / 1.05, 0))
	elif frame == 670:
		_capture("reverse-complete")
	elif frame == 690:
		_capture("reverse-stop-retained")
	elif frame == 700:
		_button(false)
	if frame == 730:
		var point: Vector2 = game.camera.unproject_position(Vector3(-0.9, 1.27, -5.0))
		particle_grip = game.sword.grip_for_active_cut_point(point, Vector2.LEFT, game.get_viewport().get_visible_rect().size)
		_move_grip_to(particle_grip - Vector2(520, 0))
	elif frame == 732:
		_move_grip_to(particle_grip)
	elif frame == 733:
		target = game._spawn_enemy("normal", 1, -5.0)
		target.position.x = 0.0
		target.set_action("recover", 1.0)
		_capture("cut-before")
	elif frame == CUT_FRAME:
		_motion(Vector2(180.0 / 1.05, 0))
	elif frame in [CUT_FRAME + 2, CUT_FRAME + 6, CUT_FRAME + 12, CUT_FRAME + 20, CUT_FRAME + 38]:
		_capture("cut-after-%03dms" % roundi(float(frame - CUT_FRAME) * STEP * 1000.0))
	elif frame == 780 and is_instance_valid(target):
		cut_score = game.score
		# A deterministic, explicitly guided debris fixture. Normal combat uses
		# a separate controller and never reads these private piece bounds.
		for piece in target.get_children():
			if piece.get_meta("voxel_piece", false) and not piece.is_queued_for_deletion() and piece.get_voxel_count() > 100:
				var bounds: Rect2 = piece.get_screen_bounds(game.camera)
				var grip: Vector2 = game.sword.grip_for_active_cut_point(Vector2(bounds.position.x - 8, bounds.get_center().y), Vector2.LEFT, game.get_viewport().get_visible_rect().size)
				_move_grip_to(grip - Vector2(180, 0))
				_move_grip_to(grip)
				_motion(Vector2((bounds.size.x + 16.0) / 1.05, 0))
				break
	elif frame in [782, 786, 792]:
		_capture("recut-after-%03dms" % roundi(float(frame - 780) * STEP * 1000.0))
	if include_runner and frame in [830, 1010]:
		_restart_fixture()
		game.training = false
		game.speed = 18.0 if frame == 830 else 60.0
		game.gear = game.gear_for_speed(game.speed)
		game.shift_down = frame == 1010
		inputs.append({"frame": frame, "kind": "runner_showcase", "speed": game.speed, "scope": "No enemies; actual world-distance scenery and sound comparison, not a difficulty run."})
	if include_runner and frame in [830, 860, 890, 950, 1010, 1040, 1070, 1130, 1180]:
		_capture("run-%02d-frame-%04d" % [int(game.speed), frame])
	game._process(STEP)
	game.sword._process(STEP)
	for enemy in game.enemies:
		for child in enemy.get_children():
			if child.get_meta("voxel_piece", false) or child.get_meta("cut_chip", false) or child.get_meta("cut_particle_batch", false):
				child.set_process(false)
				if child.has_method("_process"):
					child._process(STEP)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if frame == CUT_FRAME:
		cut_score = game.score
	if is_instance_valid(target) and frame in [CUT_FRAME, CUT_FRAME + 2, CUT_FRAME + 6, CUT_FRAME + 12, CUT_FRAME + 38, 782, 786, 792]:
		var particle_state: Dictionary = target.get_cut_particle_debug_state()
		particle_state["frame"] = frame
		particle_state["dead"] = target.dead
		particle_state["remaining_cells"] = target.get_remaining_voxel_count()
		particle_state["score"] = game.score
		particle_state["score_at_first_cut"] = cut_score
		particle_checks.append(_serializable(particle_state))
	samples.append(_snapshot())
	overlay.text = "%s | %0.2fs | %s" % [label, float(frame - first_frame) * STEP, _section_label()]
	return false


func _snapshot() -> Dictionary:
	var debug: Dictionary = game.sword.get_animation_debug_state()
	var contact: Vector2 = game.camera.unproject_position(game.sword.get_contact_world_position())
	var result := {"frame": frame, "mode": debug.mode, "phase": debug.phase, "style": debug.light_slash_style, "style_name": debug.light_slash_name, "quick_slashes": game.quick_slash_index, "cut_serial": game.cut_serial, "grip": _v2(game.sword.get_grip_screen_position()), "cursor": _v2(game.slash_cursor), "tip": _v2(game.camera.unproject_position(game.sword._drawn.to_global(game.sword.EDGE_TIP))), "contact": _v2(contact), "axis": _v2(game.sword.get_blade_screen_direction()), "slashing": game.slashing}
	result["blade_tip_offscreen"] = not game.get_viewport().get_visible_rect().has_point(Vector2(result.tip[0], result.tip[1]))
	result["ordinary_contact_hold"] = debug.get("ordinary_contact_hold", 0.0)
	result["camera_fov"] = game.camera.fov
	if game.audio.has_method("get_runner_audio_debug_state"):
		result["run_distance"] = game.run_distance
		result["effective_runner_speed"] = game.effective_runner_speed
		result["runner_audio"] = game.audio.get_runner_audio_debug_state()
		if render_enabled and include_runner and frame in [830, 860, 890, 950, 1010, 1040, 1070, 1130, 1180]:
			var positions: Array = []
			for index in [0, 8, 20]:
				var pose: Transform3D = game.speed_flow_batches[0].multimesh.get_instance_transform(index)
				positions.append(_serializable(pose.origin))
			result["actual_near_scenery_positions"] = positions
	if game.slashing:
		result["grip_error"] = game.sword.get_grip_screen_position().distance_to(game.slash_cursor)
		result["contact_error"] = contact.distance_to(game.sword.active_cut_point_for_grip(game.slash_cursor, game.blade_direction, game.get_viewport().get_visible_rect().size))
	return result


func _section_label() -> String:
	if include_runner and frame >= 830:
		return "runner environment / %s / no enemies in this showcase" % ("base 18" if frame < 1010 else "gear IV 60")
	if frame < 350:
		return "12 light styles / %s" % game.sword.get_animation_debug_state().light_slash_name
	if frame < 500:
		return "24 rapid press-release clicks / 83ms per click"
	if frame < 720:
		return "hilt leads / eight directions / reverse / stop"
	return "stationary cut-cell particle fixture / not normal combat"


func _capture(name: String) -> void:
	if render_enabled:
		captures.append(name)


func _post_draw() -> void:
	if not render_enabled or captures.is_empty():
		return
	var picture: Image = game.get_viewport().get_texture().get_image()
	for name in captures:
		picture.save_png(output_dir.path_join(label + "-" + name + ".png"))
	captures.clear()


func _v2(value: Vector2) -> Array:
	return [value.x, value.y]


func _serializable(value: Variant) -> Variant:
	if value is Vector2:
		return [value.x, value.y]
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is Color:
		return value.to_html()
	if value is Dictionary:
		var result := {}
		for key in value:
			result[key] = _serializable(value[key])
		return result
	if value is Array or value is PackedVector3Array or value is PackedVector2Array:
		var result := []
		for item in value:
			result.append(_serializable(item))
		return result
	return value


func _finish() -> void:
	var hashes_after: Dictionary = {}
	for path in source_hashes:
		hashes_after[path] = FileAccess.get_sha256(path)
	var report := {"version": label, "frames": samples.size(), "fixed_fps": 60, "scope": "Fixed-time parsed InputEvents with deliberately guided stationary cutting fixtures. Use continuous video and actual normal combat separately; this is not a frame-rate benchmark or human feel approval.", "inputs": inputs, "immediate_attacks": _serializable(attacks), "drag_checks": drag_checks, "particle_checks": particle_checks, "frames_data": samples, "source_hashes_before": source_hashes, "source_hashes_after": hashes_after, "sources_unchanged": source_hashes == hashes_after}
	var file := FileAccess.open(output_dir.path_join(label + "-combo-cut.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	if render_enabled and not particles_only:
		for suffix in ["000ms", "017ms", "033ms", "050ms", "083ms", "150ms"]:
			_write_style_sheet(suffix)
	print("COMBO CUT REVIEW ", label, " frames=", samples.size(), " attacks=", attacks.size(), " drag_checks=", drag_checks.size(), " particle_samples=", particle_checks.size(), " sources_unchanged=", source_hashes == hashes_after)
	await process_frame
	game.free()
	await create_timer(0.2).timeout
	quit()


func _write_style_sheet(suffix: String) -> void:
	var sheet := Image.create(1280, 540, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.02, 0.03, 0.04))
	for style in range(12):
		var path := output_dir.path_join(label + "-style-%02d-%s.png" % [style, suffix])
		if not FileAccess.file_exists(path):
			continue
		var thumbnail := Image.load_from_file(path)
		thumbnail.convert(Image.FORMAT_RGB8)
		thumbnail.resize(320, 180, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(thumbnail, Rect2i(0, 0, 320, 180), Vector2i((style % 4) * 320, (style / 4) * 180))
	sheet.save_png(output_dir.path_join(label + "-twelve-styles-" + suffix + ".png"))


func _write_existing_sheets() -> void:
	for suffix in ["000ms", "033ms", "083ms"]:
		_write_style_sheet(suffix)
	quit()
