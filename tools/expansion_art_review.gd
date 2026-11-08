extends SceneTree
## Rendered pose/contact fixture; scripted close targets are not normal combat.

var output_dir := ""
var game

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): output_dir = arg.trim_prefix("--capture-dir=")
	if output_dir.is_empty(): output_dir = ProjectSettings.globalize_path("res://builds/expansion-review/art")
	call_deferred("_run")

func _capture(name: String) -> void:
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_dir.path_join(name+".png"))

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output_dir)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280,720)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.test_mode = true
	game.start_game()
	game.set_process(false)
	game.sword.set_process(false)
	game.sword._process(0.0)
	game.hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for kind in ["normal","tank","ranged","boss","drone","missile_drone","barrier","beam"]:
		var distance := 9.0 if kind == "boss" else (6.6 if kind in ["tank","beam","barrier"] else 5.2)
		var target = game._spawn_enemy(kind,1,-distance)
		target.position.x = 0.0
		target.rotation.y = -0.18
		target.set_action("run",0.0)
		await _capture(kind+"-rest")
		target.set_action("ranged_charge" if kind in ["drone","missile_drone","ranged"] else "windup",0.8)
		await _capture(kind+"-charge")
		target.free()
		game.enemies.clear()
	for kind in ["bolt","missile","shock"]:
		var shot = game._spawn_projectile(Vector3(0,1.75,-2.6),kind)
		await _capture(kind+"-solid")
		shot.set_reflected()
		await _capture(kind+"-reflected")
		game._cut_projectile(0)
		for frame in range(4): game._update_blasts(1.0/60.0)
		await _capture(kind+"-cut-blast")
		game._clear_blasts()
	game.free()
	quit()
