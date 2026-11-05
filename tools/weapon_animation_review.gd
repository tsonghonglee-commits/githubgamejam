extends SceneTree
## Identical parsed pointer input and continuous frame evidence for weapon motion.
## The one timed melee fixture tests the parry reaction, not normal-play difficulty.
## Run with --write-movie <absolute .avi> --fixed-fps 60 for a continuous recording.

const FPS := 60.0
const END_FRAME := 510
const GRIP := Vector3(0.0, -0.11, 0.0)
const TIP := Vector3(0.0, 0.86, 0.0)
const CONTACT := Vector3(0.0, 0.52, 0.0)

var game
var review_label := "current"
var output_dir := ""
var frame := -1
var running := false
var render_enabled := false
var records: Array = []
var inputs: Array = []
var immediate_events: Array = []
var transitions: Array = []
var previous: Dictionary = {}
var keyframes := {29: "rest", 30: "single-press", 32: "single-033ms", 35: "single-083ms", 40: "single-167ms", 46: "single-recovery", 60: "combo-a", 72: "combo-b", 84: "combo-c", 126: "before-held", 127: "held-entry", 135: "held-slow", 154: "held-stop", 173: "held-retained", 182: "held-turn", 194: "held-return", 208: "held-before-release", 209: "held-release", 215: "held-recovery", 229: "held-sheath", 250: "empty-parry", 254: "empty-parry-lift", 261: "empty-parry-set", 268: "empty-parry-end", 280: "empty-parry-sheath", 360: "enemy-windup", 363: "contact-parry-press", 367: "contact-parry-contact", 370: "contact-parry-reaction", 374: "contact-parry-recoil", 382: "contact-parry-recovery", 398: "contact-parry-sheath", 430: "interrupt-slash", 432: "interrupt-held", 435: "interrupt-parry", 440: "interrupt-parry-set", 470: "final-sheath"}
var pending_capture := ""
var overlay: Label


func _initialize() -> void:
	keyframes[229] = "held-insert"
	keyframes[239] = "held-docked"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--animation-label="):
			review_label = arg.trim_prefix("--animation-label=").validate_filename()
		elif arg.begins_with("--capture-dir="):
			output_dir = arg.trim_prefix("--capture-dir=")
	if output_dir.is_empty():
		output_dir = ProjectSettings.globalize_path("res://builds/weapon-animation-review").path_join(review_label)
	call_deferred("_begin")


func _begin() -> void:
	render_enabled = DisplayServer.get_name() != "headless"
	if render_enabled:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DirAccess.make_dir_recursive_absolute(output_dir)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.test_mode = true
	game.set_process(false)
	game.sword.set_process(false)
	game.start_game()
	game.training = false
	game.practice = false
	game.spawn_timer = 999.0
	game.speed = 48.0
	game.gear = 4
	game.camera.rotation = Vector3.ZERO
	game.aim_angles = Vector2.ZERO
	game.camera.fov = 78.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var layer := CanvasLayer.new()
	layer.layer = 50
	root.add_child(layer)
	overlay = Label.new()
	overlay.position = Vector2(14, 690)
	overlay.add_theme_font_size_override("font_size", 16)
	overlay.add_theme_color_override("font_shadow_color", Color.BLACK)
	overlay.add_theme_constant_override("shadow_outline_size", 4)
	layer.add_child(overlay)
	RenderingServer.frame_post_draw.connect(_post_draw)
	running = true


func _motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	var mapping: Transform2D = game.get_viewport().get_final_transform()
	event.relative = relative * mapping.get_scale()
	event.screen_relative = event.relative
	event.position = mapping * game.slash_cursor
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	inputs.append({"frame": frame, "type": "motion", "logical_relative": _v2(relative)})


func _button(pressed: bool, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var before_serial: int = game.cut_serial
	var before := _snapshot()
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	inputs.append({"frame": frame, "type": "button", "button": button, "pressed": pressed})
	var instant := _snapshot()
	instant["button"] = button
	instant["pressed"] = pressed
	instant["new_cut_on_input"] = game.cut_serial - before_serial
	instant["before_drawn_visible"] = before.drawn_visible
	instant["input_grip_step_px"] = Vector2(instant.grip[0], instant.grip[1]).distance_to(Vector2(before.grip[0], before.grip[1]))
	instant["input_tip_step_px"] = Vector2(instant.tip[0], instant.tip[1]).distance_to(Vector2(before.tip[0], before.tip[1]))
	immediate_events.append(instant)


func _segment() -> String:
	if frame < 55:
		return "single press / follow-through / sheath"
	if frame < 115:
		return "alternating repeated normal slashes"
	if frame < 240:
		return "held: slow curve / stop / reverse / release"
	if frame < 325:
		return "empty parry: lift / guard / recover"
	if frame < 425:
		return "timed melee fixture: successful parry reaction"
	return "ordinary -> held -> parry interruption -> sheath"


func _process(_delta: float) -> bool:
	if not running:
		return false
	frame += 1
	if frame >= END_FRAME:
		running = false
		_finish.call_deferred()
		return false
	if frame in [30, 60, 72, 84, 120, 430]:
		_button(true)
	if frame in [31, 61, 73, 85, 209, 436]:
		_button(false)
	if frame == 110:
		_motion(Vector2(35, -12))
	if frame >= 132 and frame <= 154:
		_motion(Vector2(2.2, sin(float(frame - 132) * 0.26) * 1.4))
	if frame >= 175 and frame <= 192:
		var phase := float(frame - 175) / 17.0 * TAU
		_motion(Vector2(cos(phase) * 10.0, sin(phase) * 8.0))
	if frame >= 193 and frame <= 204:
		_motion(Vector2(-5, 1.5))
	if frame == 432:
		_motion(Vector2(-12, -8))
	if frame in [250, 363, 435]:
		_button(true, MOUSE_BUTTON_RIGHT)
	if frame in [251, 364, 436]:
		_button(false, MOUSE_BUTTON_RIGHT)
	if frame == 330:
		var enemy = game._spawn_enemy("normal", 1, -13.0)
		enemy.position.x = 0.0
		enemy.set_meta("lane_x", 0.0)
		game._set_enemy_action(enemy, "windup", 0.45)
		inputs.append({"frame": frame, "type": "fixture", "description": "One normal enemy, centered, fixed 0.45s windup. No auto-aim or direct damage."})
	game._process(1.0 / FPS)
	game.sword._process(1.0 / FPS)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var record := _snapshot()
	if not previous.is_empty():
		record["grip_step_px"] = Vector2(record.grip[0], record.grip[1]).distance_to(Vector2(previous.grip[0], previous.grip[1]))
		record["tip_step_px"] = Vector2(record.tip[0], record.tip[1]).distance_to(Vector2(previous.tip[0], previous.tip[1]))
		record["contact_step_px"] = Vector2(record.contact[0], record.contact[1]).distance_to(Vector2(previous.contact[0], previous.contact[1]))
		var old_q := Quaternion(previous.quaternion[0], previous.quaternion[1], previous.quaternion[2], previous.quaternion[3])
		var q := Quaternion(record.quaternion[0], record.quaternion[1], record.quaternion[2], record.quaternion[3])
		record["angular_step_degrees"] = rad_to_deg(old_q.angle_to(q))
		if record.mode != previous.mode or record.drawn_visible != previous.drawn_visible:
			transitions.append({"frame": frame, "from": previous.mode, "to": record.mode, "visible_before": previous.drawn_visible, "visible_after": record.drawn_visible, "grip_step_px": record.grip_step_px, "tip_step_px": record.tip_step_px, "contact_step_px": record.contact_step_px, "angular_step_degrees": record.angular_step_degrees})
	records.append(record)
	previous = record
	overlay.text = "%s | %0.3fs | frame %03d | %s" % [review_label, float(frame) / FPS, frame, _segment()]
	if keyframes.has(frame):
		pending_capture = "%s-%03d-%s.png" % [review_label, frame, keyframes[frame]]
	return false


func _snapshot() -> Dictionary:
	var sword = game.sword
	var drawn: Node3D = sword._drawn
	var q := drawn.transform.basis.get_rotation_quaternion()
	var size: Vector2 = game.get_viewport().get_visible_rect().size
	var actual_grip: Vector2 = sword.get_grip_screen_position()
	var contact: Vector2 = game.camera.unproject_position(drawn.to_global(CONTACT))
	var entry := {"frame": frame, "time": float(frame) / FPS, "mode": sword._mode, "drawn_visible": drawn.visible, "handle_visible": sword._handle.visible, "position": _v3(drawn.position), "quaternion": [q.x, q.y, q.z, q.w], "grip": _v2(actual_grip), "drawn_grip": _v2(game.camera.unproject_position(drawn.to_global(GRIP))), "tip": _v2(game.camera.unproject_position(drawn.to_global(TIP))), "contact": _v2(contact), "cursor": _v2(game.slash_cursor), "blade_axis": _v2(sword.get_blade_screen_direction()), "slashing": game.slashing, "camera_rotation": _v3(game.camera.rotation), "fov": game.camera.fov, "cut_serial": game.cut_serial, "speed": game.speed, "health": game.health, "parries": game.combat_stats.get("parries", 0)}
	if game.slashing:
		entry["grip_error_px"] = actual_grip.distance_to(game.slash_cursor)
		entry["contact_helper_error_px"] = contact.distance_to(sword.active_cut_point_for_grip(game.slash_cursor, game.blade_direction, size))
		entry["blade_axis_dot"] = sword.get_blade_screen_direction().dot(game.blade_direction)
	if sword.has_method("get_animation_debug_state"):
		entry["animation"] = sword.get_animation_debug_state()
	return entry


func _post_draw() -> void:
	if not render_enabled or pending_capture.is_empty():
		return
	game.get_viewport().get_texture().get_image().save_png(output_dir.path_join(pending_capture))
	pending_capture = ""


func _v2(value: Vector2) -> Array:
	return [value.x, value.y]


func _v3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _write_contact_sheet(sheet_name: String, chosen_frames: Array) -> void:
	if not render_enabled:
		return
	var sheet := Image.create(1280, 720, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.015, 0.02, 0.03))
	for index in chosen_frames.size():
		var selected: int = chosen_frames[index]
		var filename := "%s-%03d-%s.png" % [review_label, selected, keyframes[selected]]
		var frame_image := Image.load_from_file(output_dir.path_join(filename))
		if frame_image == null:
			continue
		frame_image.resize(426, 240, Image.INTERPOLATE_LANCZOS)
		frame_image.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(frame_image, Rect2i(0, 0, 426, 240), Vector2i((index % 3) * 426, (index / 3) * 240))
	sheet.save_png(output_dir.path_join(review_label + "-" + sheet_name + ".png"))


func _contact_motion_window(first_frame: int, last_frame: int) -> Dictionary:
	var left := INF
	var right := -INF
	var top := INF
	var bottom := -INF
	for record in records + immediate_events:
		if int(record.frame) < first_frame or int(record.frame) > last_frame or not record.drawn_visible:
			continue
		left = minf(left, float(record.contact[0]))
		right = maxf(right, float(record.contact[0]))
		top = minf(top, float(record.contact[1]))
		bottom = maxf(bottom, float(record.contact[1]))
	return {"first_frame": first_frame, "last_frame": last_frame, "contact_left": left, "contact_right": right, "contact_top": top, "contact_bottom": bottom, "contact_horizontal_span_px": right - left, "contact_vertical_span_px": bottom - top}


func _finish() -> void:
	var max_grip_error := 0.0
	var max_contact_error := 0.0
	var min_axis_dot := 1.0
	for record in records:
		if record.has("grip_error_px"):
			max_grip_error = maxf(max_grip_error, float(record.grip_error_px))
			max_contact_error = maxf(max_contact_error, float(record.contact_helper_error_px))
			min_axis_dot = minf(min_axis_dot, float(record.blade_axis_dot))
	var report := {"version": review_label, "fps": FPS, "frames": records.size(), "scope": "Parsed real InputEvent sequence, fixed-60fps Movie Maker weapon-motion fixture; exactly one scripted timed enemy. The video plays at real action duration, but encoding is not a wall-clock performance test. No auto-aim, direct damage or normal-difficulty verdict. Inspect full video and transition keyframes; these metrics do not grade subjective feel.", "tool_sha256": FileAccess.get_sha256(get_script().resource_path), "max_held_grip_error_px": max_grip_error, "max_contact_helper_error_px": max_contact_error, "min_blade_axis_dot": min_axis_dot, "parries": game.combat_stats.get("parries", 0), "normal_slash_projection_windows": [_contact_motion_window(30, 42), _contact_motion_window(60, 71), _contact_motion_window(72, 83), _contact_motion_window(84, 96)], "inputs": inputs, "immediate_events": immediate_events, "transitions": transitions, "frames_data": records}
	var file := FileAccess.open(output_dir.path_join(review_label + "-animation.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	_write_contact_sheet("normal-slash-phases", [29, 30, 32, 35, 40, 46, 60, 72, 84])
	_write_contact_sheet("held-transitions", [126, 127, 135, 154, 173, 194, 208, 209, 239])
	_write_contact_sheet("parry-comparison", [250, 254, 261, 363, 367, 370, 374, 382, 398])
	print("WEAPON ANIMATION REVIEW ", review_label, " frames=", records.size(), " held_grip_error_px=", max_grip_error, " contact_error_px=", max_contact_error, " min_axis_dot=", min_axis_dot, " parries=", report.parries)
	await process_frame
	game.free()
	game = null
	await process_frame
	quit()
