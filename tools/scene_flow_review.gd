extends SceneTree
## Empty-route scenery fixture. It advances production run_distance and world
## movement; it never relocates individual lights, floor meshes or shader patches.
## Rendered fixed-step frames and snapshots are not a performance benchmark.

const STEP := 1.0 / 60.0
const DISTANCES: Array[float] = [0.0, 13.0, 47.0, 101.0, 229.0, 231.0]
const SOURCE_FILES: Array[String] = ["res://scripts/main.gd", "res://scenes/main.tscn"]

var game
var label := "scene-flow"
var output_dir := ""
var review_speed := 18.0
var clean := false
var fixed_view := false
var render_enabled := false
var logical_time := 0.0
var steps := 0
var wall_started_usec := 0
var captures: Array = []
var buffered_images: Array = []
var wrap_events: Array = []
var source_hashes: Dictionary = {}
var fixed_camera_position := Vector3(0, 1.75, 0)
var fixed_camera_rotation := Vector3.ZERO
var fixed_camera_fov := 78.0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--review-label="):
			label = argument.trim_prefix("--review-label=").validate_filename()
		elif argument.begins_with("--capture-dir="):
			output_dir = argument.trim_prefix("--capture-dir=")
		elif argument.begins_with("--speed="):
			review_speed = clampf(float(argument.trim_prefix("--speed=")), 18.0, 60.0)
		elif argument == "--clean":
			clean = true
		elif argument == "--fixed-view":
			fixed_view = true
	if output_dir.is_empty():
		output_dir = ProjectSettings.globalize_path("res://builds/scene-flow-review").path_join(label)
	call_deferred("_run")


func _v3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _scene_inventory(node: Node, lights: Array, floor_meshes: Array) -> void:
	if node is Light3D:
		var entry := {
			"path": str(node.get_path()), "type": node.get_class(),
			"position": _v3(node.global_position), "rotation": _v3(node.global_rotation),
			"energy": node.light_energy, "shadow_enabled": node.shadow_enabled,
			"cull_mask": node.light_cull_mask, "visible": node.is_visible_in_tree(),
		}
		if node is OmniLight3D:
			entry["range"] = node.omni_range
		lights.append(entry)
	if node is GeometryInstance3D:
		var bounds: AABB = node.global_transform * node.get_aabb()
		if bounds.size.x > 7.0 and bounds.size.z > 0.5 and bounds.end.y < 0.2:
			floor_meshes.append({"path": str(node.get_path()), "position": _v3(node.global_position), "bounds_position": _v3(bounds.position), "bounds_size": _v3(bounds.size), "layers": node.layers, "cast_shadow": node.cast_shadow})
	for child in node.get_children():
		_scene_inventory(child, lights, floor_meshes)


func _step(delta: float) -> void:
	var before: Dictionary = {}
	for segment in game.road_segments:
		before[segment.get_instance_id()] = segment.position.z
	var before_distance: float = game.run_distance
	game._process(delta)
	game.sword._process(delta)
	logical_time += delta
	steps += 1
	for index in range(game.road_segments.size()):
		var segment: Node3D = game.road_segments[index]
		var old_z: float = before[segment.get_instance_id()]
		var shift: float = segment.position.z - old_z
		var travel: float = game.run_distance - before_distance
		if absf(shift - travel) > 0.05:
			wrap_events.append({"step": steps, "logical_time": logical_time, "run_distance": game.run_distance, "segment_index": index, "before_z": old_z, "after_z": segment.position.z, "expected_forward_delta": travel, "actual_delta": shift})
	if fixed_view:
		game.camera.position = fixed_camera_position
		game.camera.rotation = fixed_camera_rotation
		game.camera.fov = fixed_camera_fov


func _advance_to(distance: float) -> void:
	while float(game.run_distance) < distance - 0.00001:
		var delta := minf(STEP, (distance - float(game.run_distance)) / maxf(float(game.speed), 0.1))
		await process_frame
		_step(delta)
		if render_enabled:
			await RenderingServer.frame_post_draw


func _capture(distance: float) -> void:
	var old_visible: bool = game.hud.visible
	game.hud.visible = not clean
	var picture: Image
	if render_enabled:
		await process_frame
		await RenderingServer.frame_post_draw
		picture = game.get_viewport().get_texture().get_image()
		buffered_images.append({"image": picture, "path": output_dir.path_join(label + "-distance-%03dm.png" % roundi(distance))})
	var lights: Array = []
	var floor_meshes: Array = []
	_scene_inventory(game, lights, floor_meshes)
	var segments: Array = []
	for index in range(game.road_segments.size()):
		segments.append({"index": index, "position": _v3(game.road_segments[index].position)})
	var probes: Array = []
	var logical_size: Vector2 = game.get_viewport().get_visible_rect().size
	for z in [-4.0, -10.0, -22.0]:
		for x in [-4.35, 0.0, 4.35]:
			var world_point := Vector3(x, -0.052, z)
			var screen_point: Vector2 = game.camera.unproject_position(world_point)
			var probe := {"world": _v3(world_point), "logical_pixel": [screen_point.x, screen_point.y]}
			if picture != null and Rect2(Vector2.ZERO, logical_size).has_point(screen_point):
				var pixel := Vector2i(screen_point * Vector2(picture.get_size()) / logical_size)
				var color := picture.get_pixelv(pixel)
				probe["rendered_rgb"] = [color.r, color.g, color.b]
			probes.append(probe)
	var shader_distance: Variant = null
	if game.road_flow_material != null:
		for parameter in game.road_flow_material.shader.get_shader_uniform_list():
			if parameter.name == "run_distance":
				shader_distance = game.road_flow_material.get_shader_parameter("run_distance")
	var wall_time := float(Time.get_ticks_usec() - wall_started_usec) / 1000000.0
	captures.append({
		"requested_distance": distance, "run_distance": game.run_distance,
		"road_shader_run_distance": shader_distance, "logical_time": logical_time,
		"world_time": game.game_clock, "wall_time": wall_time, "simulation_step": steps,
		"render_frame": Engine.get_frames_drawn(), "camera_position": _v3(game.camera.position),
		"camera_rotation": _v3(game.camera.rotation), "fov": game.camera.fov,
		"speed": game.speed, "gear": game.gear, "practice": game.practice,
		"training": game.training, "hud_hidden_for_capture_only": clean,
		"road_segments": segments, "lights": lights, "floor_meshes": floor_meshes,
		"rendered_ground_probes": probes,
	})
	game.hud.visible = old_visible


func _run() -> void:
	render_enabled = DisplayServer.get_name() != "headless"
	if render_enabled:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280, 720)
	Engine.max_fps = 60
	Input.use_accumulated_input = false
	DirAccess.make_dir_recursive_absolute(output_dir)
	for path in SOURCE_FILES:
		source_hashes[path] = FileAccess.get_sha256(path)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.test_mode = true
	game.set_process(false)
	game.sword.set_process(false)
	game.start_game()
	game.practice = false
	game.training = false
	game.spawn_timer = 999.0
	game.message_timer = 0.0
	game.speed = review_speed
	game.gear = game.gear_for_speed(game.speed)
	if review_speed > 18.0:
		var shift := InputEventKey.new()
		shift.keycode = KEY_SHIFT
		shift.physical_keycode = KEY_SHIFT
		shift.pressed = true
		Input.parse_input_event(shift)
		Input.flush_buffered_events()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_step(0.0)
	wall_started_usec = Time.get_ticks_usec()
	for distance in DISTANCES:
		await _advance_to(distance)
		await _capture(distance)
	var hashes_after: Dictionary = {}
	for path in SOURCE_FILES:
		hashes_after[path] = FileAccess.get_sha256(path)
	for capture in buffered_images:
		capture.image.save_png(capture.path)
	var report := {
		"label": label, "rendered": render_enabled, "fixed_step": STEP,
		"scope": "Empty production-route scenery fixture. Spawns are suppressed, but production _process advances run_distance, road/lights and shader inputs. Fixed simulated steps with rendered frames; not normal combat, human quality approval or a performance benchmark. Ground RGB probes are final mixed pixels, not separated light contributions.",
		"fixed_view_camera_override": fixed_view, "requested_speed": review_speed,
		"clean_capture_hides_only_hud": clean, "captures": captures,
		"wrap_events": wrap_events, "source_hashes_before": source_hashes,
		"source_hashes_after": hashes_after, "sources_unchanged": source_hashes == hashes_after,
	}
	var file := FileAccess.open(output_dir.path_join(label + "-scene-flow.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SCENE FLOW REVIEW ", label, " captures=", captures.size(), " distance=", game.run_distance, " wraps=", wrap_events.size(), " unchanged=", source_hashes == hashes_after)
	game._pause_game()
	game.audio.set_runner_motion(0.0, 0.0, false, 0.0)
	await create_timer(1.0).timeout
	game.free()
	await process_frame
	quit(0 if captures.size() == DISTANCES.size() and source_hashes == hashes_after else 1)
