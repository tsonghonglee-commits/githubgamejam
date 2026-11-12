extends SceneTree
## Production entry poses on the actual cuttable meshes. Optional capture uses
## the first-person camera and the district's moving production scenery.
const Models = preload("res://scripts/series_archetypes.gd")
const PHASES := [0.16,0.33,0.52,0.69,0.88,1.0]
var game: Node3D
var output_dir := "user://series-entry-clearance"
var render := false
var records: Array[Dictionary] = []
var failures: Array[Dictionary] = []
var captures: Dictionary = {}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--review-output="): output_dir = argument.trim_prefix("--review-output=")
	render = DisplayServer.get_name() != "headless"
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	game.test_mode = true
	game.state = "menu"
	game.speed = 18.0
	game.sword.visible = false
	game.hud.visible = false
	if game.menu_showcase != null: game.menu_showcase.visible = false
	game.audio.process_mode = Node.PROCESS_MODE_DISABLED
	while game.campaign.preparing: await process_frame
	game.campaign.suspend()
	if render:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280,720)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for kind: String in Models.KINDS:
		var info: Dictionary = Models.info(kind)
		game.series_scenery.force_series(int(info.series))
		var cases := [0,1,2,3] if not bool(info.boss) else [0]
		if bool(info.flying) and not bool(info.boss): cases.append_array([4,5,6])
		for lane: int in cases:
			var actor: Node3D = game._spawn_enemy(kind,lane,-40.0)
			if bool(info.boss):
				var member := maxi(0,["cyber_captain","cyber_flanker","cyber_suppressor","cyber_spotter"].find(kind))
				actor.position = game.campaign._boss_position(kind,member)
			actor.set_process(false)
			game.series_combat.begin_entry(actor)
			await _verify_entry(actor,info,render and lane == (0 if bool(info.boss) else 2))
			game.enemies.erase(actor)
			actor.free()
			game.series_effects.clear()
	var file := FileAccess.open(output_dir.path_join("review.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"records":records,"failures":failures,"captures":captures,"rendered":render},"\t"))
	file.close()
	print("ENTRY CLEARANCE: ",records.size()," placements, ",failures.size()," failures, ",captures.size()," captures")
	game.free()
	for frame in range(4): await process_frame
	quit(0 if failures.is_empty() else 1)


func _verify_entry(actor: Node3D, info: Dictionary, capture: bool) -> void:
	var duration: float = actor.get_meta("series_entry_duration")
	var ceiling: float = [0.0,0.0,10.08,12.42,12.46,27.0][int(info.series)]
	var minimum_y := INF
	var maximum_y := -INF
	var outside_rail := 0.0
	var worst_part := -1
	var worst_phase := -1.0
	var elapsed := 0.0
	for tick in range(1,101):
		var goal := duration*tick/100.0
		var delta := goal-elapsed
		actor.age = goal
		game.series_combat._update_entry(actor,delta)
		elapsed = goal
		for part in range(actor._part_meshes.size()):
			var visual: MeshInstance3D = actor._part_meshes[part]
			if visual.mesh == null: continue
			var bounds: AABB = visual.global_transform*visual.mesh.get_aabb()
			minimum_y = minf(minimum_y,bounds.position.y)
			maximum_y = maxf(maximum_y,bounds.end.y)
			if bounds.position.y < 0.99:
				var excess := maxf(-bounds.position.x,bounds.end.x)-5.05
				if excess > outside_rail:
					outside_rail = excess
					worst_part = part
					worst_phase = tick/100.0
		if capture:
			game.run_distance += delta*game.speed
			game._update_road(delta)
			game.series_scenery.update(delta,game.run_distance)
			game.series_effects.update(delta)
			if tick/100.0 in PHASES:
				await process_frame
				await RenderingServer.frame_post_draw
				var path := output_dir.path_join("%s-%03d.png" % [actor.enemy_kind,tick])
				if root.get_texture().get_image().save_png(path) == OK: captures[path.get_file()] = FileAccess.get_sha256(path)
	var complete: bool = not bool(actor.get_meta("series_entry",false)) and actor.position.is_equal_approx(Vector3(actor.get_meta("series_anchor")))
	var result := {"kind":actor.enemy_kind,"lane":actor.lane_index,"minimum_y":minimum_y,"maximum_y":maximum_y,"rail_excess":outside_rail,"worst_rail_part":worst_part,"worst_rail_phase":worst_phase,"complete":complete}
	records.append(result)
	if not complete or minimum_y < -0.055 or maximum_y > ceiling+0.003 or outside_rail > 0.004:
		failures.append(result)
