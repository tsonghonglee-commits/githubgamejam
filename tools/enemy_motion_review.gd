extends SceneTree
## Tracking-camera gait closeup, using production enemy stepping and deck
## material. It is a pose fixture, not the player's camera or a difficulty test.
const STEP := 1.0/60.0
var game
var output_dir := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): output_dir=arg.trim_prefix("--capture-dir=")
	if output_dir.is_empty(): output_dir=ProjectSettings.globalize_path("res://builds/expansion-review/motion-v091")
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output_dir)
	root.mode=Window.MODE_WINDOWED
	root.size=Vector2i(1280,720)
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.test_mode=true
	game.start_game()
	game.set_process(false)
	game.sword.set_process(false)
	game.sword.visible=false
	game.hud.visible=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	# Extend the same receiver for the moving review camera; production wraps
	# around the player, so it cannot surround a tracking camera on its own.
	game._box(game,Vector3(10.5,0.35,1000),Vector3(0,-0.23,200),game.road_flow_material)
	for kind in ["normal","tank","ranged"]:
		game.start_game()
		var target=game._spawn_enemy(kind,1,-8.0)
		target.position.x=0.0
		target.resolved=true
		target.fire_timer=999.0
		var sheet:=Image.create(960,480,false,Image.FORMAT_RGB8)
		var capture_index:=0
		for frame in range(90):
			game.run_distance += game.speed*STEP
			game._update_enemies(STEP,1.0)
			# Keep the resolved walker in the fixture beyond the normal cull plane.
			if not is_instance_valid(target): break
			game._update_road(STEP)
			game.camera.position=Vector3(1.5,1.7,target.position.z+6.0)
			game.camera.look_at(target.global_position+Vector3(0,1.4,0))
			game.camera.fov=68.0
			await process_frame
			await RenderingServer.frame_post_draw
			if frame in [0,4,8,12,16,20,24,28]:
				var picture:=root.get_texture().get_image()
				picture.save_png(output_dir.path_join("%s-%03d.png"%[kind,frame]))
				var crop:=picture.get_region(Rect2i(430,150,400,510))
				crop.convert(Image.FORMAT_RGB8)
				crop.resize(240,240,Image.INTERPOLATE_LANCZOS)
				sheet.blit_rect(crop,Rect2i(0,0,240,240),Vector2i((capture_index%4)*240,(capture_index/4)*240))
				capture_index+=1
			if frame >= 28: break
		sheet.save_png(output_dir.path_join(kind+"-contact-sheet.png"))
	game.free()
	quit()
