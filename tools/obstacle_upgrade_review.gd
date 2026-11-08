extends SceneTree
## Native, fixed-pose obstacle gallery in the actual game environment. Not
## normal combat, difficulty, wall-clock performance or subjective approval.

var game
var output_dir := ""
var captures: Array = []


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): output_dir = argument.trim_prefix("--capture-dir=")
	if output_dir.is_empty(): output_dir = ProjectSettings.globalize_path("res://builds/obstacle-upgrade/art")
	call_deferred("_run")


func _capture(label: String, target, result: Dictionary = {}) -> void:
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var path := output_dir.path_join(label+".png")
	root.get_texture().get_image().save_png(path)
	var shape: Dictionary = target.get_construct_debug_state()
	captures.append({"label":label,"path":path,"kind":target.enemy_kind,"variant":target.construct_variant,"name":shape.name,"remaining_cells":target.get_remaining_voxel_count(),"dead":target.dead,"result":result})


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Obstacle gallery needs a native display; use obstacle_upgrade_verify for headless logic.")
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
	for kind in ["barrier","beam"]:
		for variant in range(3):
			var target = game._spawn_enemy(kind,1,-6.6)
			target.configure(kind,1,variant)
			target.position.x = 0.0
			target.set_meta("simulation_scale",0.0)
			target.set_meta("flythrough_enabled",false)
			target.set_action("run",0.0)
			var label: String = "%s-%d" % [kind,variant]
			await _capture(label+"-intact",target)
			var aim: Vector2 = game.camera.unproject_position(target.get_aim_point())
			var result: Dictionary = target.cut_path(game.camera,PackedVector2Array([aim+Vector2(0,-60),aim+Vector2(0,60)]),1.0)
			await _capture(label+"-cut",target,result)
			target.free()
			game.enemies.clear()
	game._pause_game()
	await create_timer(1.1).timeout
	game.free()
	await process_frame
	var report := {"version":ProjectSettings.get_setting("application/config/version"),"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"rendered":true,"captures":captures,"tool_sha256":FileAccess.get_sha256(get_script().resource_path),"scope":"Actual native game renderer/environment; six fixed-pose obstacle forms and actual narrow central cuts. AI and debris simulation explicitly frozen for geometry inspection. No normal difficulty, performance or user visual approval."}
	var file := FileAccess.open(output_dir.path_join("obstacle-upgrade-review.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("OBSTACLE GALLERY: ",captures.size()," captures")
	quit()
