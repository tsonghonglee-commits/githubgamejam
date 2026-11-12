extends SceneTree
## Mobile acceptance checks send real multi-touch events through the production input route.
## Optional --capture-dir=... records the same touch UI in an actual rendered viewport.

var game
var controls: Control
var checks: int = 0
var failures: int = 0
var capture_dir: String = ""
var contacts: Dictionary = {}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture_dir = argument.trim_prefix("--capture-dir=")
	if not "--touch-preview" in OS.get_cmdline_user_args():
		push_error("Mobile verification requires -- --touch-preview.")
		quit(2)
		return
	call_deferred("_run")


func expect(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func button_center(action: String) -> Vector2:
	return controls.get_button_rect(action).get_center()


func send_touch(index: int, pressed: bool, point: Vector2, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.canceled = canceled
	event.position = game.get_viewport().get_final_transform() * point
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	if pressed:
		contacts[index] = point
	else:
		contacts.erase(index)


func send_drag(index: int, point: Vector2) -> void:
	var previous: Vector2 = contacts.get(index, point)
	var canvas_to_window: Transform2D = game.get_viewport().get_final_transform()
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = canvas_to_window * point
	event.relative = (point - previous) * canvas_to_window.get_scale()
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	contacts[index] = point


func tap(action: String, index: int = 9) -> void:
	var point := button_center(action)
	send_touch(index, true, point)
	send_touch(index, false, point)


func step(delta: float) -> void:
	game._process(delta)
	game.sword._process(delta)


func release_all() -> void:
	for index in contacts.keys():
		send_touch(index, false, contacts[index])


func capture(name: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(capture_dir)
	game._update_hud()
	await process_frame
	await RenderingServer.frame_post_draw
	game.get_viewport().get_texture().get_image().save_png(capture_dir.path_join(name + ".png"))


func restart_fixture() -> void:
	release_all()
	game.start_game()
	game.spawn_timer = 999.0
	game.speed = 40.0
	game.guard_cooldown = 0.0
	game.hit_stop = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _run() -> void:
	Input.use_accumulated_input = false
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.test_mode = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	controls = game.get("touch_controls")
	if controls == null:
		push_error("Production touch controls were not created.")
		game.free()
		quit(2)
		return
	expect(game.touch_mode and controls.visible, "touch preview creates the visible production mobile controls")
	var layout_valid: bool = true
	var viewport_rect: Rect2 = game.get_viewport().get_visible_rect()
	for action in ["boost", "attack", "parry", "blade", "pause"]:
		var rectangle: Rect2 = controls.get_button_rect(action)
		layout_valid = layout_valid and rectangle.size.x >= 64.0 and rectangle.size.y >= 64.0 and viewport_rect.encloses(rectangle)
	expect(layout_valid, "all five mobile buttons have usable hit areas inside the current landscape viewport")
	await capture("01-menu")
	var start_point := viewport_rect.size * 0.5
	send_touch(0, true, start_point)
	send_touch(0, false, start_point)
	game.spawn_timer = 999.0
	expect(game.state == "playing" and not game.left_down and not game.slashing, "menu tap starts normal combat without turning its release into a blade hold")
	var before_attack: int = game.cut_serial
	var speed_before_attack: float = game.speed
	send_touch(0, true, button_center("attack"))
	expect(game.cut_serial == before_attack + 1 and game.speed == speed_before_attack, "attack button cuts immediately once and grants no speed")
	step(0.20)
	expect(not game.slashing and not game.left_down, "holding the separate attack button cannot accidentally enter continuous slash")
	send_touch(0, false, button_center("attack"))
	var duplicate_serial: int = game.cut_serial
	var emulated_mouse := InputEventMouseButton.new()
	emulated_mouse.device = -1
	emulated_mouse.button_index = MOUSE_BUTTON_LEFT
	emulated_mouse.pressed = true
	Input.parse_input_event(emulated_mouse)
	Input.flush_buffered_events()
	emulated_mouse = emulated_mouse.duplicate()
	emulated_mouse.pressed = false
	Input.parse_input_event(emulated_mouse)
	Input.flush_buffered_events()
	expect(game.cut_serial == duplicate_serial, "touch-emulated mouse events cannot produce duplicate attacks")
	restart_fixture()
	var look_point: Vector2 = viewport_rect.size * Vector2(0.70, 0.42)
	var look_before: Vector2 = game.aim_angles
	send_touch(5, true, look_point)
	send_drag(5, look_point + Vector2(30, -10))
	send_touch(5, false, contacts[5])
	expect(game.aim_angles.distance_to(look_before) > 0.01 and not game.slashing, "right-side blank drag turns the normal view without starting a blade attack")
	var view_before: Vector2 = game.aim_angles
	send_touch(1, true, button_center("boost"))
	step(0.10)
	expect(game.shift_down and game.speed > 40.0, "left boost finger accelerates while held")
	send_touch(2, true, button_center("blade"))
	expect(game.shift_down and game.left_down and game.slashing, "independent blade finger enters held slash without releasing boost")
	var grip_before: Vector2 = game.slash_cursor
	var serial_before_drag: int = game.cut_serial
	var blade_start: Vector2 = contacts[2]
	send_drag(2, blade_start + Vector2(-70, -35))
	step(0.016)
	expect(game.cut_serial > serial_before_drag and game.last_blade_frames.size() >= 2 and game.slash_cursor.distance_to(grip_before) > 20.0 and game.aim_angles == view_before and game.sword.get_grip_screen_position().distance_to(game.slash_cursor) < 1.0, "screen drag moves the anchored grip and finite blade path without recentering the locked view")
	var slash_speed: float = game.speed
	step(0.10)
	expect(game.speed < slash_speed and game.shift_down, "boost plus mobile held slash still drains real-time speed")
	await capture("02-combat-multitouch")
	send_touch(1, false, Vector2(10, 10))
	expect(not game.shift_down and game.slashing, "boost release outside its button leaves the independent blade finger active")
	var tiny_before: int = game.cut_serial
	send_drag(2, contacts[2] + Vector2(1, 0))
	send_touch(2, false, contacts[2])
	expect(game.cut_serial > tiny_before and game.pending_strokes.is_empty() and not game.slashing, "blade release flushes a one-pixel final touch path")
	restart_fixture()
	send_touch(2, true, button_center("blade"))
	var parry_flush_serial: int = game.cut_serial
	send_drag(2, contacts[2] + Vector2(-1, 0))
	send_touch(3, true, button_center("parry"))
	expect(game.cut_serial > parry_flush_serial and game.guard_active and not game.slashing and game.pending_strokes.is_empty(), "separate parry finger flushes the last blade motion before interrupting slash")
	send_touch(3, false, button_center("parry"))
	send_drag(2, contacts[2] + Vector2(70, 0))
	step(0.35)
	expect(not game.slashing and not game.left_down, "interrupted held blade finger cannot re-enter slash until released")
	send_touch(2, false, contacts[2])
	send_touch(2, true, button_center("blade"))
	expect(game.slashing, "a released and newly pressed blade finger can enter slash again")
	send_touch(2, false, contacts[2], true)
	expect(not game.left_down and not game.slashing, "Android canceled blade touch releases its held action")
	restart_fixture()
	send_touch(2, true, button_center("blade"))
	game.speed = 4.05
	step(0.02)
	game.speed = 20.0
	send_drag(2, contacts[2] + Vector2(30, 0))
	step(0.20)
	expect(not game.slashing and game.slash_lock, "resource exhaustion locks the still-held blade touch even after speed recovers")
	send_touch(2, false, contacts[2])
	send_touch(2, true, button_center("blade"))
	expect(game.slashing and not game.slash_lock, "release and re-press unlock mobile blade after exhaustion")
	send_touch(1, true, button_center("boost"))
	tap("pause", 4)
	expect(game.state == "paused" and not game.left_down and not game.shift_down and not game.slashing, "pause button clears all held touch actions")
	await capture("03-paused")
	release_all()
	var resume_point := viewport_rect.size * 0.5
	send_touch(0, true, resume_point)
	send_touch(0, false, resume_point)
	expect(game.state == "playing" and not game.left_down and not game.shift_down, "resume tap returns to combat with no stale held inputs")
	game.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	expect(game.state == "paused", "Android back request pauses combat instead of leaving a held action running")
	send_touch(0, true, resume_point)
	send_touch(0, false, resume_point)
	send_touch(1, true, button_center("boost"))
	send_touch(2, true, button_center("blade"))
	game.test_mode = false
	game.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	game.test_mode = true
	expect(game.state == "paused" and not game.shift_down and not game.left_down and not game.slashing, "focus loss pauses and releases every active touch")
	release_all()
	send_touch(0, true, resume_point)
	send_touch(0, false, resume_point)
	game.health = 1
	game._hurt(1, "mobile-verification-fixture")
	send_touch(0, true, resume_point)
	send_touch(0, false, resume_point)
	expect(game.state == "playing" and game.health == 5 and not game.left_down and not game.shift_down, "death overlay tap restarts with fresh health and cleared touch state")
	print("MOBILE INPUT VERIFICATION: ", checks, " checks, ", failures, " failures; viewport=", viewport_rect.size)
	release_all()
	# The checks advance gameplay much faster than the real audio mixer. Let the
	# final start/lose tails retire before destroying their AudioStreamPlayers.
	game.state = "paused"
	await create_timer(0.65).timeout
	game.free()
	controls = null
	game = null
	await process_frame
	await create_timer(0.30).timeout
	quit(0 if failures == 0 else 1)
