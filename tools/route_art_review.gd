extends SceneTree
## Static production chapter variants; this deliberately selects every tile's
## chapter for art review, and is not proof of normal transition timing.

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280,720)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.test_mode = true
	game.start_game()
	game.set_process(false)
	game.sword.set_process(false)
	game.sword._process(0.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.hud.visible = false
	var output := ProjectSettings.globalize_path("res://builds/expansion-review/route-art")
	DirAccess.make_dir_recursive_absolute(output)
	for chapter in range(4):
		for tile in game.road_segments: game._set_route_section(tile,chapter)
		game._update_forge_lights()
		for frame in range(8): await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("chapter-%d.png"%chapter))
	game.free()
	quit()
