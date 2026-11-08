extends SceneTree
## Native fixed-view chapter gallery. Explicitly frozen scene, not normal
## combat or performance evidence. Output path supplied by the review caller.

var game
var output_dir := ""
var captures: Array = []

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): output_dir = argument.trim_prefix("--capture-dir=")
	if output_dir.is_empty(): output_dir = ProjectSettings.globalize_path("res://builds/foundry-review-v095")
	call_deferred("_run")

func _capture(label: String) -> void:
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var path := output_dir.path_join(label+".png")
	root.get_texture().get_image().save_png(path)
	captures.append({"label":label,"path":path,"camera_rotation":str(game.camera.rotation),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280,720)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.test_mode = true
	game.start_game()
	game.set_process(false)
	game.sword.set_process(false)
	game.sword.visible = false
	game.hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for chapter in range(4):
		for tile in game.road_segments: game._set_route_section(tile,chapter)
		game._update_forge_lights()
		for view in [Vector3.ZERO,Vector3(-0.15,0.36,0),Vector3(-0.12,-0.36,0)]:
			game.camera.rotation = view
			await _capture("chapter-%d-view-%d"%[chapter,captures.size()%3])
	game._pause_game()
	await create_timer(1.1).timeout
	game.free()
	await process_frame
	var report := {"version":ProjectSettings.get_setting("application/config/version"),"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"rendered":true,"captures":captures,"tool_sha256":FileAccess.get_sha256(get_script().resource_path),"scope":"Native actual scene fixed views, four chapter roots manually selected and simulation frozen. Mixed final drawcall samples, not strict performance or full route/human approval."}
	var file := FileAccess.open(output_dir.path_join("foundry-art-review.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("FOUNDRY ART captures=",captures.size())
	quit()
