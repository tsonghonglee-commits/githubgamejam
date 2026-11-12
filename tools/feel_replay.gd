extends SceneTree
## Real-time input replay. Attacks go through InputEvent rather than direct damage calls.

var game
var output_dir: String
var label: String = "before"
var observations: Dictionary = {}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			output_dir = argument.trim_prefix("--capture-dir=")
		elif argument.begins_with("--replay-label="):
			label = argument.trim_prefix("--replay-label=")
	call_deferred("_run")


func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func button(pressed: bool, which: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = which
	event.pressed = pressed
	Input.parse_input_event(event)


func motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.screen_relative = relative
	event.position = game.get_viewport().get_visible_rect().size * 0.5
	Input.parse_input_event(event)


func setup_targets() -> void:
	game.start_game()
	game.practice = true
	game.spawn_timer = 999.0
	game._spawn_enemy("normal", 1, -26.0)
	game._spawn_enemy("ranged", 3, -37.0)
	game._spawn_enemy("tank", 0, -48.0)


func capture(name: String) -> void:
	if output_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	await RenderingServer.frame_post_draw
	game.get_viewport().get_texture().get_image().save_png(output_dir.path_join(label + "-" + name + ".png"))


func _run() -> void:
	Engine.max_fps = 60
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.test_mode = true
	DisplayServer.window_set_title("SHIFT CUT - " + label + " - input replay")
	setup_targets()
	# First attempt: holding the advertised button straight from the starting state.
	button(true)
	await create_timer(0.25).timeout
	observations["base_speed_long_slash"] = game.slashing
	var has_serial: bool = false
	for property in game.get_property_list():
		if property.name == "cut_serial":
			has_serial = true
	var serial_before: int = int(game.get("cut_serial")) if has_serial else 0
	for sample in range(45):
		motion(Vector2(2.0, 0.0))
		await create_timer(0.008).timeout
	observations["processed_slow_paths"] = int(game.get("cut_serial")) - serial_before if has_serial else -1
	await capture("01-base-hold")
	button(false)
	await create_timer(0.15).timeout
	# Second attempt: turn toward an off-centre target before entering blade mode.
	setup_targets()
	key(KEY_SHIFT, true)
	await create_timer(1.6).timeout
	key(KEY_SHIFT, false)
	motion(Vector2(-155.0, -36.0))
	await create_timer(0.08).timeout
	observations["yaw_before_hold"] = game.aim_angles.x
	button(true)
	await create_timer(0.28).timeout
	observations["yaw_during_hold"] = game.aim_angles.x
	await capture("02-side-view")
	for relative in [Vector2(-150, 50), Vector2(300, -80), Vector2(-300, 80), Vector2(150, -50)]:
		motion(relative)
		await create_timer(0.09).timeout
	await capture("03-cross-cut")
	button(false)
	await create_timer(0.3).timeout
	# Third attempt: use real mouse strokes in the boss encounter, then try re-cutting.
	setup_targets()
	key(KEY_F3, true)
	key(KEY_F3, false)
	key(KEY_SHIFT, true)
	await create_timer(1.1).timeout
	key(KEY_SHIFT, false)
	button(true)
	await create_timer(0.23).timeout
	for stroke in range(3):
		motion(Vector2(-320, -45))
		await create_timer(0.10).timeout
		motion(Vector2(640, 0))
		await create_timer(0.10).timeout
		motion(Vector2(-320, 45))
		await create_timer(0.10).timeout
	await capture("04-boss-cut")
	button(false)
	button(true, MOUSE_BUTTON_RIGHT)
	await create_timer(0.5).timeout
	button(false, MOUSE_BUTTON_RIGHT)
	observations["boss_attempt_kills"] = game.kills
	observations["boss_attempt_health"] = game.health
	observations["boss_attempt_speed"] = game.speed
	game._pause_game()
	print("FEEL INPUT REPLAY ", label, ": ", JSON.stringify(observations))
	if not output_dir.is_empty():
		var report = FileAccess.open(output_dir.path_join(label + "-report.json"), FileAccess.WRITE)
		report.store_string(JSON.stringify(observations, "\t"))
		report.close()
	game.free()
	await create_timer(0.15).timeout
	quit()
