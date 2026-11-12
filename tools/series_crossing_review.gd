extends SceneTree
## Drive the production road ring and crossing at runner speed with the real
## first-person camera. No enemies are inserted and no campaign clock is advanced.
const ROUTES := [[1,2],[1,3],[1,4],[2,3],[2,4],[3,2],[3,4],[4,2],[4,3],[2,5],[3,5],[4,5]]
const CHECKPOINTS := [0.0,74.0,114.0,133.0,175.0,223.9,224.1]
const INDUSTRIAL_CHECKPOINTS := [0.0,52.0,74.0,96.0,104.0,110.0,114.0,133.0,154.0,175.0,223.9,224.1]
var game: Node3D
var output_dir := "user://series-crossing-review"
var rendered := false
var failures: Array[Dictionary] = []
var records: Array[Dictionary] = []
var captures: Dictionary = {}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--review-output="): output_dir = argument.trim_prefix("--review-output=")
	rendered = DisplayServer.get_name() != "headless"
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	game.test_mode = true
	game.speed = 18.0
	game.sword.visible = false
	game.hud.visible = false
	if game.menu_showcase != null: game.menu_showcase.visible = false
	game.audio.process_mode = Node.PROCESS_MODE_DISABLED
	while game.campaign.preparing: await process_frame
	game.campaign.suspend()
	if rendered:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280,720)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for pair: Array in ROUTES: await _cross(pair)
	var file := FileAccess.open(output_dir.path_join("review.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"routes":records,"failures":failures,"captures":captures,"native":rendered},"\t"))
	file.close()
	print("SERIES CROSSINGS: ",records.size()," / ",failures.size()," failures; ",captures.size()," images")
	game.free()
	for frame in range(4): await process_frame
	quit(0 if failures.is_empty() else 1)


func _cross(pair: Array) -> void:
	var scenery: Node3D = game.series_scenery
	var start: float = game.run_distance
	scenery.force_series(pair[0])
	scenery.begin_transition(pair[1])
	var checkpoints: Array = INDUSTRIAL_CHECKPOINTS if pair[0] == 1 else CHECKPOINTS
	var active_landmark_z: float = 0.0
	var steps: Array[Dictionary] = []
	for meters: float in checkpoints:
		while game.run_distance < start+meters-0.00001:
			var dt := minf(1.0/60.0,(start+meters-game.run_distance)/game.speed)
			game.run_distance += dt*game.speed
			game._update_road(dt)
			scenery.update(dt,game.run_distance)
		var active: bool = scenery.is_transitioning()
		var landmark: MeshInstance3D = scenery._incoming_landmarks[pair[1]] if active else scenery._landmarks[pair[1]]
		var stable: bool = active == (meters < 224.0) and scenery.get_current_series() == (pair[0] if active else pair[1])
		if is_equal_approx(meters,223.9): active_landmark_z = landmark.position.z
		if not active: stable = stable and absf(landmark.position.z-active_landmark_z) < 0.001
		if active:
			var original_boundary: float = scenery._boundary
			scenery.update(0.0,game.run_distance+100.0)
			stable = stable and is_equal_approx(original_boundary,scenery._boundary)
		var row := {"route":pair,"meters":meters,"active":active,"destination_landmark_z":landmark.position.z,"stable":stable}
		steps.append(row)
		if not stable: failures.append(row)
		if rendered:
			var name := "%d-%d-%04d" % [pair[0],pair[1],roundi(meters*10.0)]
			if not await _capture(name): failures.append(row)
			if (meters in [104.0,133.0] and pair[0] == 1) or (meters in [114.0,133.0] and 4 in pair) or (meters == 175.0 and pair[1] == 3):
				for side in [-1,1]:
					game.camera.rotation_degrees = Vector3(-6,side*26.0,0)
					if not await _capture(name+("-left" if side > 0 else "-right")): failures.append(row)
				game.camera.rotation_degrees = Vector3.ZERO
	records.append({"pair":pair,"steps":steps})


func _capture(label: String) -> bool:
	await process_frame
	await RenderingServer.frame_post_draw
	var name := label+".png"
	var path := output_dir.path_join(name)
	if root.get_texture().get_image().save_png(path) != OK: return false
	captures[name] = FileAccess.get_sha256(path)
	return true
