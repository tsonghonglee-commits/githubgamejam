extends SceneTree
## Guided stationary art fixtures. This does not replace normal combat or GPU profiling.
## The actual game, enemy rig and parsed mouse inputs provide every visible pose and cut.

const STEP := 1.0 / 60.0
const SOURCE_FILES: Array[String] = [
	"res://scenes/main.tscn", "res://scripts/main.gd", "res://scripts/voxel_enemy.gd",
	"res://scripts/voxel_debris.gd", "res://scripts/katana_view.gd",
]

var game
var target
var label := "stage1"
var output_dir := ""
var render_enabled := false
var inputs: Array = []
var captures: Array = []
var buffered_images: Array = []
var source_hashes: Dictionary = {}
var logical_time := 0.0
var initial_cells := 0
var max_grip_error := 0.0
var closeup := false
var poses_only := false


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--review-label="):
			label = argument.trim_prefix("--review-label=").validate_filename()
		elif argument.begins_with("--capture-dir="):
			output_dir = argument.trim_prefix("--capture-dir=")
		elif argument == "--closeup":
			closeup = true
		elif argument == "--poses-only":
			poses_only = true
	if output_dir.is_empty():
		output_dir = ProjectSettings.globalize_path("res://builds/art-stage-review").path_join(label)
	call_deferred("_run")


func _button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	inputs.append({"time": logical_time, "button": "left", "pressed": pressed})


func _motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	var mapping: Transform2D = game.get_viewport().get_final_transform()
	event.relative = relative * mapping.get_scale()
	event.screen_relative = event.relative
	event.position = mapping * game.slash_cursor
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	inputs.append({"time": logical_time, "motion": [relative.x, relative.y]})


func _step(delta: float = STEP) -> void:
	logical_time += delta
	game._process(delta)
	game.sword._process(delta)
	for enemy in game.enemies:
		if not is_instance_valid(enemy):
			continue
		for child in enemy.get_children():
			if child.get_meta("voxel_piece", false) or child.get_meta("cut_chip", false) or child.get_meta("cut_particle_batch", false):
				child.set_process(false)
				child._process(delta)
	if game.slashing:
		max_grip_error = maxf(max_grip_error, game.sword.get_grip_screen_position().distance_to(game.slash_cursor))


func _reset_fixture() -> void:
	game._reset_input()
	game.start_game()
	game.training = true
	game.practice = false
	game.spawn_timer = 999.0
	game.speed = 48.0
	game.gear = 4
	game.camera.position = Vector3(0, 1.75, 0)
	game.camera.rotation = Vector3.ZERO
	game.camera.fov = 78.0
	game.aim_angles = Vector2.ZERO
	game.message_timer = 0.0
	game.sword.set_pose("sheathed")
	game.sword._process(0.8)
	game._update_hud()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	target = null
	initial_cells = 0
	await process_frame


func _spawn_target(distance: float) -> void:
	target = game._spawn_enemy("normal", 1, -distance)
	target.position.x = 0.0
	target.set_action("recover", 1.0)
	target.set_meta("simulation_scale", 0.0)
	target.set_meta("flythrough_enabled", false)
	initial_cells = target.get_remaining_voxel_count()
	game._update_hud()


func _snapshot(name: String, clean: bool) -> Dictionary:
	var fragments := 0
	var fragment_cells := 0
	if is_instance_valid(target):
		for child in target.get_children():
			if child.get_meta("voxel_piece", false) and not child.is_queued_for_deletion():
				fragments += 1
				fragment_cells += child.get_voxel_count()
	var pose := {
		"name": name, "logical_time": logical_time, "hud_hidden_for_capture_only": clean,
		"camera_position": _v3(game.camera.position), "camera_rotation": _v3(game.camera.rotation),
		"fov": game.camera.fov, "gear": game.gear, "slashing": game.slashing,
		"score": game.score, "kills": game.kills, "initial_cells": initial_cells,
		"fragment_count": fragments, "fragment_cells": fragment_cells,
		"viewport": [game.get_viewport().get_visible_rect().size.x, game.get_viewport().get_visible_rect().size.y],
	}
	if game.slashing:
		pose["grip_error_px"] = game.sword.get_grip_screen_position().distance_to(game.slash_cursor)
	if is_instance_valid(target):
		var bounds: Rect2 = target.get_screen_bounds(game.camera)
		pose.merge({"target_position": _v3(target.position), "target_rotation": _v3(target.rotation), "action": target.action_name, "action_phase": target.action_phase, "remaining_cells": target.get_remaining_voxel_count(), "dead": target.dead, "attack_limb_intact": target.has_attack_limb(), "body_screen_bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y]})
	return pose


func _capture(name: String, clean: bool = false) -> void:
	var old_hud_visible: bool = game.hud.visible
	if clean:
		game.hud.visible = false
	if render_enabled:
		await process_frame
		await RenderingServer.frame_post_draw
		buffered_images.append({"image": game.get_viewport().get_texture().get_image(), "path": output_dir.path_join(label + "-" + name + ".png")})
	captures.append(_snapshot(name, clean))
	game.hud.visible = old_hud_visible


func _v3(point: Vector3) -> Array:
	return [point.x, point.y, point.z]


func _capture_closeups() -> void:
	for distance in [8.0, 5.0, 2.8]:
		target.position.z = -distance
		var distance_name := "28dm" if distance == 2.8 else "%dm" % int(distance)
		for degrees in [0.0, -35.0]:
			target.rotation.y = deg_to_rad(degrees)
			target.set_action("recover", 1.0)
			var view_name := "front" if degrees == 0.0 else "threequarter"
			await _capture("closeup-%s-%s-hud" % [distance_name, view_name])
			await _capture("closeup-%s-%s-clean" % [distance_name, view_name], true)
		target.rotation.y = 0.0
		if distance == 5.0:
			target.set_action("windup", 0.80)
			await _capture("closeup-5m-windup-clean", true)
			target.set_action("strike", 0.35)
			await _capture("closeup-5m-strike-clean", true)
			target.set_action("recover", 1.0)


func _finish(actual_damage: bool, cut_fixture_run: bool) -> void:
	var hashes_after: Dictionary = {}
	for path in SOURCE_FILES:
		hashes_after[path] = FileAccess.get_sha256(path)
	for capture in buffered_images:
		capture.image.save_png(capture.path)
	var report := {
		"label": label, "rendered": render_enabled,
		"scope": "Guided stationary art and optional actual parsed mouse cut fixtures. Fixed manual steps; not normal difficulty, human quality approval, or a performance benchmark. Clean captures hide only HUD, restore it immediately, and retain actual camera/materials/mesh. Compare closeup poses with the concept separately; this script does not judge likeness.",
		"inputs": inputs, "captures": captures, "actual_material_damage": actual_damage,
		"cut_fixture_run": cut_fixture_run, "closeup_mode": closeup,
		"max_grip_error_px": max_grip_error, "hud_restored": game.hud.visible,
		"source_hashes_before": source_hashes, "source_hashes_after": hashes_after,
		"sources_unchanged": source_hashes == hashes_after,
	}
	var file := FileAccess.open(output_dir.path_join(label + "-art-review.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("ART STAGE REVIEW ", label, " captures=", captures.size(), " cut_run=", cut_fixture_run, " damage=", actual_damage, " grip_error=", max_grip_error, " unchanged=", source_hashes == hashes_after)
	game._pause_game()
	game.audio.set_runner_motion(0.0, 0.0, false, 0.0)
	await create_timer(1.0).timeout
	game.free()
	await process_frame
	quit(0 if (actual_damage or not cut_fixture_run) and max_grip_error < 1.0 and source_hashes == hashes_after else 1)


func _run() -> void:
	render_enabled = DisplayServer.get_name() != "headless"
	if render_enabled:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(output_dir)
	for path in SOURCE_FILES:
		source_hashes[path] = FileAccess.get_sha256(path)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.test_mode = true
	game.set_process(false)
	game.sword.set_process(false)
	await _reset_fixture()
	_spawn_target(18.0)
	await _capture("normal-18m-front")
	await _capture("normal-18m-clean", true)
	target.position.z = -8.0
	await _capture("normal-8m-front")
	target.set_action("windup", 0.80)
	await _capture("normal-8m-windup")
	target.set_action("strike", 0.35)
	await _capture("normal-8m-strike")
	target.set_action("recover", 1.0)
	target.rotation.y = deg_to_rad(-18.0)
	await _capture("normal-8m-threequarter")
	if closeup:
		await _capture_closeups()
	if poses_only:
		await _finish(false, false)
		return

	# Adopt held mode before spawning the target so the mandatory initial light
	# attack cannot pre-damage this cut fixture. All following travel is input.
	var waist_y := 1.425 if float(target._cell) < 0.075 else 1.27
	var waist_z := -7.975 if float(target._cell) < 0.075 else -8.0
	await _reset_fixture()
	_button(true)
	_step(0.15)
	var contact: Vector2 = game.camera.unproject_position(Vector3(-0.9, waist_y, waist_z))
	var grip: Vector2 = game.sword.grip_for_active_cut_point(contact, Vector2.LEFT, game.get_viewport().get_visible_rect().size)
	_motion((grip - Vector2(520, 0) - game.slash_cursor) / 1.05)
	_step()
	_motion(Vector2(520.0 / 1.05, 0))
	_step()
	_spawn_target(8.0)
	await _capture("long-cut-before")
	_motion(Vector2(190.0 / 1.05, 0))
	_step()
	await _capture("long-cut-after-000ms")
	for frame in range(1, 21):
		_step()
		if frame in [2, 6, 12, 20]:
			await _capture("long-cut-after-%03dms" % roundi(frame * STEP * 1000.0))
	_button(false)
	_step()
	var final_cells: int = target.get_remaining_voxel_count()
	var actual_damage: bool = final_cells < initial_cells
	await _finish(actual_damage, true)
