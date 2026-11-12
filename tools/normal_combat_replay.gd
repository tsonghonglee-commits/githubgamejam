extends SceneTree
## Production combat replay: no practice health, no target injection, no direct damage calls.
## The controller reacts to visible action poses and moves the same mouse/key inputs as a player.

const STEP := 1.0 / 60.0
const MOUSE_GAIN := 0.55
const REVIEW_SOURCE_PATHS: Array[String] = [
	"res://scenes/main.tscn", "res://assets/icon.svg", "res://scripts/main.gd", "res://scripts/katana_view.gd",
	"res://scripts/voxel_enemy.gd", "res://scripts/voxel_debris.gd",
	"res://scripts/prototype_hud.gd", "res://scripts/prototype_audio.gd",
	"res://scripts/projectile_view.gd", "res://scripts/voxel_blast.gd",
	"res://scripts/route_sections.gd", "res://scripts/projectile_geometry.gd",
	"res://scripts/enemy_motion.gd", "res://scripts/touch_controls.gd", "res://scripts/enemy_archetypes.gd", "res://scripts/encounter_director.gd",
]

var game
var policy := "basic"
var route_seconds := 60.0
var output_dir := ""
var fast_mode := false
var buffer_captures := false
var buffered_captures: Array[Dictionary] = []
var capture_readback_ms: Array[float] = []
var run_label := ""
var max_seconds := 0.0
var output: Dictionary = {}
var actions_seen: Dictionary = {}
var attack_pose_ready: Dictionary = {}
var types_seen: Dictionary = {}
var transitions: Array = []
var previous_states: Dictionary = {}
var previous_projectiles: Dictionary = {}
var screenshots_taken: Dictionary = {}
var capture_queue: Array[String] = []
var clock := 0.0
var next_decision := 0.0
var attack_after := 0.0
var block_after := 0.0
var parry_held := false
var left_held := false
var shift_held := false
var release_at := 0.0
var sweep_index := 0
var sweep_step_after := 0.0
var sweep_path: Array[Vector2] = []
var boss_strikes_seen := 0
var last_boss_strike := -999.0
var health_before := 5
var damage_samples: Array = []
var input_counts: Dictionary = {"short_presses": 0, "long_sweeps": 0, "parry_presses": 0, "mouse_events": 0, "shift_presses": 0}
var min_speed := INF
var max_speed := 0.0
var frames := 0
var frame_times_ms: Array[float] = []
var last_wall_usec := 0
var forbidden_mode_seen := false
var timed_out := false
var run_seed := 73001
var parry_decisions: Array = []
var attack_decisions: Array = []
var slash_started_at := -1.0
var slash_start_mouse_events := 0
var first_sever_at := -1.0
var first_sever_world := -1.0
var first_sever_real_clock := -1.0
var first_sever_enemy_id := 0
var sever_samples: Array = []
var enemy_spawn_cells: Dictionary = {}
var observed_enemies: Dictionary = {}
var observed_cut_counts: Dictionary = {}
var observed_cut_times_ms: Array[float] = []
var fragment_records: Dictionary = {}
var chip_ids_seen: Dictionary = {}
var fragments_spawned_seen := 0
var max_live_fragments := 0
var largest_fragment_cells_seen := 0
var fragment_motion_samples: Array = []
var dead_motion_records: Dictionary = {}
var grip_errors: Array[float] = []
var blade_errors: Array[float] = []
var grip_samples: Array = []
var next_grip_sample := 0.0
var capture_timing: Dictionary = {}
var largest_grip_error_observed := -1.0
var contact_motion_samples: Array = []
var last_contact_serial := -1
var previous_contact_grip := Vector2(INF, INF)
var previous_contact_point := Vector2(INF, INF)
var max_live_cut_particles := 0
var cut_particle_records: Dictionary = {}
var section_transitions: Array[Dictionary] = []
var long_frames: Array[Dictionary] = []
var observed_route_section := -1
var observes_sections := false
var observes_blasts := false
var runtime_manifest_before: Dictionary = {}
var review_tool_hash_before := ""


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--combat-round="):
			policy = argument.trim_prefix("--combat-round=")
		elif argument.begins_with("--route-duration="):
			route_seconds = float(argument.trim_prefix("--route-duration="))
		elif argument.begins_with("--output-root="):
			output_dir = argument.trim_prefix("--output-root=")
		elif argument.begins_with("--run-label="):
			run_label = argument.trim_prefix("--run-label=")
		elif argument == "--fast":
			fast_mode = true
		elif argument == "--buffer-captures":
			buffer_captures = true
	if not policy in ["basic", "speed", "mixed"]:
		policy = "basic"
	run_seed = 73001 + ["basic", "speed", "mixed"].find(policy)
	if run_label.is_empty():
		run_label = policy + ("-fast" if fast_mode else "-realtime")
	run_label = run_label.validate_filename()
	if output_dir.is_empty():
		output_dir = ProjectSettings.globalize_path("res://builds/normal-combat")
	route_seconds = clampf(route_seconds, 20.0, 180.0)
	max_seconds = route_seconds * 2.8 + 65.0
	call_deferred("_run")


func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if property.name == property_name:
			return true
	return false


func _send_key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _set_shift(pressed: bool) -> void:
	if pressed == shift_held:
		return
	shift_held = pressed
	if pressed:
		input_counts.shift_presses += 1
	_send_key(KEY_SHIFT, pressed)


func _send_button(pressed: bool, which: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = which
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _move_mouse(relative: Vector2) -> void:
	if relative.length_squared() < 0.01:
		return
	var event := InputEventMouseMotion.new()
	# parse_input_event receives window pixels; Godot converts them to stretched canvas pixels.
	# Headless windows are 64x64 even when the logical gameplay viewport is 1280x720.
	var canvas_to_window: Transform2D = game.get_viewport().get_final_transform()
	event.relative = relative * canvas_to_window.get_scale()
	event.screen_relative = event.relative
	event.position = canvas_to_window * (game.get_viewport().get_visible_rect().size * 0.5)
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	input_counts.mouse_events += 1


func _release_left() -> void:
	if not left_held:
		return
	_send_button(false)
	left_held = false
	sweep_path.clear()


func _press_short() -> void:
	if left_held or clock < attack_after:
		return
	_send_button(true)
	left_held = true
	release_at = clock + 0.045
	attack_after = clock + 0.21
	input_counts.short_presses += 1


func _press_parry(threat: Dictionary) -> void:
	if clock < block_after:
		return
	var decision: Dictionary = {"time": clock, "world": game.game_clock, "type": threat.get("type", "unknown")}
	if threat.has("enemy"):
		var enemy = threat.enemy
		decision.merge({"kind": enemy.enemy_kind, "action": enemy.get_meta("action_state", "run"), "phase": enemy.get_meta("action_phase", 0.0)})
	else:
		decision["time_to_contact"] = threat.get("time_left", -1.0)
	parry_decisions.append(decision)
	_release_left()
	_send_button(true, MOUSE_BUTTON_RIGHT)
	parry_held = true
	block_after = clock + 0.42
	attack_after = maxf(attack_after, clock + 0.22)
	input_counts.parry_presses += 1


func _visible_body(enemy) -> Vector2:
	# Follow the projected visible silhouette as new models crouch, stride or
	# hover. No private core/tag coordinates feed normal-play targeting.
	var bounds: Rect2 = enemy.get_screen_bounds(game.camera)
	if bounds.size == Vector2.ZERO:
		return Vector2(INF, INF)
	return bounds.get_center()


func _in_view(screen: Vector2) -> bool:
	var size: Vector2 = game.get_viewport().get_visible_rect().size
	return screen.is_finite() and screen.x > 30.0 and screen.x < size.x - 30.0 and screen.y > 65.0 and screen.y < size.y - 90.0


func _aim_at(enemy) -> float:
	var point := _visible_body(enemy)
	var size: Vector2 = game.get_viewport().get_visible_rect().size
	var error: Vector2 = point - size * 0.5
	_move_mouse((error * MOUSE_GAIN).clamp(Vector2(-70.0, -38.0), Vector2(70.0, 38.0)))
	return error.length()


func _begin_sweep() -> void:
	if left_held or clock < attack_after or game.speed < 13.0:
		return
	_send_button(true)
	left_held = true
	release_at = clock + 0.94
	sweep_index = 0
	sweep_step_after = clock + 0.15
	var size: Vector2 = game.get_viewport().get_visible_rect().size
	# These are preplanned contact gestures around the aim point, not enemy
	# voxel/core locations. The hilt-leading blade rotates behind the hand,
	# so a fixed upright inverse from older versions no longer describes it.
	var center: Vector2 = size * 0.5
	if policy == "speed":
		sweep_path = [Vector2(-145, -18), Vector2(145, -18), Vector2(-145, 18), Vector2(130, -30), Vector2(-120, 24)]
	else:
		sweep_path = [Vector2(-130, -18), Vector2(130, -18), Vector2(-130, 16), Vector2(120, -30), Vector2(-110, 25)]
	for index in range(sweep_path.size()):
		sweep_path[index] = center + sweep_path[index] * size / Vector2(1280, 720)
	attack_after = release_at + 0.24
	input_counts.long_sweeps += 1


func _step_sweep() -> void:
	if sweep_path.is_empty() or not game.slashing or clock < sweep_step_after:
		return
	if sweep_index >= sweep_path.size():
		return
	var size: Vector2 = game.get_viewport().get_visible_rect().size
	var current: Vector2 = game.slash_cursor
	var target: Vector2 = sweep_path[sweep_index]
	var contact: Vector2 = game.sword.active_cut_point_for_grip(current, game.blade_direction, size)
	if contact.distance_to(target) < 22.0:
		sweep_index += 1
		sweep_step_after = clock + 0.035
		return
	# Pick a bounded real mouse step using only the player's own sword model.
	# Every turn and intermediate cut is still consumed by production input.
	var best: Vector2 = (target - contact).limit_length(54.0)
	var best_error := INF
	for radius in [2.0, 8.0, 24.0, 54.0]:
		for index in range(16):
			var candidate: Vector2 = Vector2.from_angle(float(index) * TAU / 16.0) * float(radius)
			candidate = (current + candidate).clamp(Vector2(2, 2), size - Vector2(2, 2)) - current
			var axis: Vector2 = game.sword.resolve_blade_axis(game.blade_direction, candidate)
			var predicted: Vector2 = game.sword.active_cut_point_for_grip(current + candidate, axis, size)
			var error := predicted.distance_squared_to(target)
			if error < best_error:
				best_error = error
				best = candidate
	_move_mouse(best / 1.05)


func _observe(dt: float) -> void:
	frames += 1
	_observe_route_section()
	min_speed = minf(min_speed, float(game.speed))
	max_speed = maxf(max_speed, float(game.speed))
	if game.practice or game.training:
		forbidden_mode_seen = true
	if game.health != health_before:
		damage_samples.append({"at": clock, "world": game.game_clock, "before": health_before, "after": game.health, "speed": game.speed, "guard_active": game.guard_active, "guard_age": game.guard_age, "guard_cooldown": game.guard_cooldown, "since_last_parry_input": clock - block_after + 0.42})
		health_before = game.health
	_observe_fragments()
	if fast_mode:
		_observe_grip()
		_observe_contact_path()
	if first_sever_at >= 0.0:
		for offset in [0.12, 0.30, 0.55]:
			if clock - first_sever_at >= offset:
				_queue_capture("first-sever-plus-%03dms" % int(offset * 1000.0), true)
	for enemy in game.enemies:
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		var identifier := str(enemy.get_instance_id())
		if not observed_enemies.has(identifier):
			observed_enemies[identifier] = true
			if enemy.has_method("get_remaining_voxel_count"):
				enemy_spawn_cells[identifier] = enemy.get_remaining_voxel_count()
			enemy.severed.connect(_on_observed_sever)
		if enemy.dead:
			continue
		var screen := _visible_body(enemy)
		if not _in_view(screen):
			continue
		var kind: String = enemy.enemy_kind
		types_seen[kind] = true
		var action: String = str(enemy.get_meta("action_state", "run"))
		var phase: float = float(enemy.get_meta("action_phase", 0.0))
		if (kind == "normal" and action in ["stagger", "recover"]) or (kind == "tank" and enemy.attack_done >= 2 and action in ["stagger", "recover"]) or (action == "ranged_fire" and phase >= 0.3):
			attack_pose_ready[kind] = true
		var previous: String = str(previous_states.get(identifier, ""))
		if previous != action:
			previous_states[identifier] = action
			var key_name := kind + ":" + action
			actions_seen[key_name] = int(actions_seen.get(key_name, 0)) + 1
			transitions.append({"time": clock, "world": game.game_clock, "kind": kind, "state": action, "phase": phase})
			if kind == "boss" and action == "boss_strike" and clock - last_boss_strike > 0.2:
				boss_strikes_seen += 1
				last_boss_strike = clock
		if action in ["windup", "ranged_charge", "boss_windup"] and phase > 0.25 and phase < 0.72:
			_queue_capture(kind + "-" + action)
		if kind in ["normal", "tank"] and action == "windup" and phase >= 0.72 and phase <= 0.95:
			_queue_capture(kind + "-late-windup")
		if action in ["strike", "boss_strike"] and phase > 0.35:
			_queue_capture(kind + "-" + action)
		if kind == "tank" and action == "strike" and int(enemy.get_meta("action_variant", 0)) == 1 and phase > 0.35:
			_queue_capture("tank-second-strike")
		if action == "ranged_fire" and phase > 0.3:
			_queue_capture("ranged-fire")
	if game.slashing:
		_queue_capture("long-slash")
		if slash_started_at < 0.0:
			slash_started_at = clock
			slash_start_mouse_events = int(input_counts.mouse_events)
		if clock - slash_started_at >= 0.25 and int(input_counts.mouse_events) > slash_start_mouse_events:
			_queue_capture("long-slash-settled")
	else:
		slash_started_at = -1.0
	for projectile in game.projectiles:
		var node: Node3D = projectile.node
		if is_instance_valid(node):
			var identifier := str(node.get_instance_id())
			var point: Vector3 = node.global_position
			var before: Dictionary = previous_projectiles.get(identifier, {})
			var velocity_z := 0.0
			if not before.is_empty() and dt > 0.00001:
				velocity_z = (point.z - float(before.z)) / maxf(game.game_clock - float(before.world), 0.00001)
			previous_projectiles[identifier] = {"z": point.z, "world": game.game_clock, "velocity_z": velocity_z}
			if point.z > -17.0:
				_queue_capture("projectile-" + str(projectile.kind) + ("-reflected" if bool(projectile.get("reflected", false)) else "-incoming"))
	if observes_blasts and not game.blasts.is_empty():
		_queue_capture("projectile-explosion")


func _observe_route_section() -> void:
	if not observes_sections:
		return
	var section: int = int(game.route_section)
	if section == observed_route_section:
		return
	section_transitions.append({"controller_time":clock,"world_time":game.game_clock,"route_time":game.elapsed,"run_distance":game.run_distance,"from":observed_route_section,"section":section})
	observed_route_section = section
	_queue_capture("section-%02d" % section)


func _record_long_frame(interval_ms: float) -> void:
	if interval_ms <= 50.0:
		return
	var active_enemies := 0
	var enemy_nodes := 0
	for enemy in game.enemies:
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			enemy_nodes += 1
			if not enemy.dead and not enemy.resolved:
				active_enemies += 1
	var active_projectiles := 0
	for projectile in game.projectiles:
		if is_instance_valid(projectile.node) and not projectile.node.is_queued_for_deletion():
			active_projectiles += 1
	var active_blasts := 0
	if observes_blasts:
		for blast in game.blasts:
			if is_instance_valid(blast) and not blast.is_queued_for_deletion():
				active_blasts += 1
	var event_tail: Array = []
	var events: Array = game.combat_events
	for index in range(maxi(0, events.size()-3), events.size()):
		event_tail.append(events[index].duplicate(true))
	# The interval ends at this process_frame resume, before new controller
	# input. Captures and all prior-frame work remain inside that interval.
	long_frames.append({"interval_ms":interval_ms,"controller_time":clock,"world_time":game.game_clock,"route_time":game.elapsed,"run_distance":game.run_distance,"route_section":int(game.route_section) if observes_sections else -1,"active_enemies":active_enemies,"enemy_nodes":enemy_nodes,"active_projectiles":active_projectiles,"active_blasts":active_blasts,"event_tail":event_tail,"sample_phase":"process_frame resume before next controller input"})


func _runtime_manifest() -> Dictionary:
	var result: Dictionary = {}
	for path in REVIEW_SOURCE_PATHS:
		var raw_exists := FileAccess.file_exists(path)
		var runtime_path: String = path if raw_exists else ""
		if not raw_exists and FileAccess.file_exists(path+".remap"):
			var remap := ConfigFile.new()
			if remap.load(path+".remap") == OK:
				runtime_path = str(remap.get_value("remap","path",""))
		result[path] = {"raw_sha256":FileAccess.get_sha256(path) if raw_exists else "","runtime_path":runtime_path,"runtime_sha256":FileAccess.get_sha256(runtime_path) if not runtime_path.is_empty() and FileAccess.file_exists(runtime_path) else ""}
	return result


func _on_observed_sever(enemy: Node3D, _point: Vector3, removed: int) -> void:
	# Read-only observation after production severing. None of this data is used to aim.
	var identifier := str(enemy.get_instance_id())
	var fragment_cells := 0
	var fragment_count := 0
	var largest := 0
	for child in enemy.get_children():
		if child.get_meta("voxel_piece", false) and not child.is_queued_for_deletion():
			var count: int = child.get_voxel_count()
			fragment_cells += count
			fragment_count += 1
			largest = maxi(largest, count)
	var initial: int = int(enemy_spawn_cells.get(identifier, 0))
	var remaining: int = enemy.get_remaining_voxel_count()
	sever_samples.append({"time": clock, "world": game.game_clock, "enemy_id": enemy.get_instance_id(), "kind": enemy.get("enemy_kind"), "initial_cells_observed": initial, "last_cut_removed": removed, "remaining_cells": remaining, "retained_fraction": float(remaining) / maxf(initial, 1.0), "fragment_count": fragment_count, "fragment_cells": fragment_cells, "largest_fragment_cells": largest})
	if first_sever_at < 0.0:
		first_sever_at = clock
		first_sever_world = game.game_clock
		first_sever_real_clock = game.real_clock
		first_sever_enemy_id = enemy.get_instance_id()
		_queue_capture("first-sever", true)


func _observe_fragments() -> void:
	var live_count := 0
	var particle_count := 0
	for enemy in game.enemies:
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		var enemy_key := str(enemy.get_instance_id())
		var cut_count: int = int(enemy.cut_count)
		if cut_count > int(observed_cut_counts.get(enemy_key, 0)):
			observed_cut_counts[enemy_key] = cut_count
			observed_cut_times_ms.append(float(enemy.last_cut_usec) * 0.001)
		if enemy.has_method("get_cut_particle_debug_state"):
			var burst: Dictionary = enemy.get_cut_particle_debug_state()
			particle_count += int(burst.get("active_count", 0))
			if int(burst.get("emitted_total", 0)) > 0:
				cut_particle_records[enemy_key] = {"body": burst.get("emitted_body", 0), "debris": burst.get("emitted_debris", 0), "size_min": burst.get("size_min", 0.0), "size_max": burst.get("size_max", 0.0), "emitted_total": burst.get("emitted_total", 0), "max_active_observed": maxi(int(cut_particle_records.get(enemy_key, {}).get("max_active_observed", 0)), int(burst.get("active_count", 0)))}
		if enemy.dead:
			var root_record: Dictionary = dead_motion_records.get(enemy_key, {})
			if root_record.is_empty():
				root_record = {"enemy_id": enemy.get_instance_id(), "kind": enemy.enemy_kind, "first_time": clock, "first_world": game.game_clock, "first_z": enemy.global_position.z, "last_z": enemy.global_position.z, "last_time": clock, "last_world": game.game_clock, "forward_distance": 0.0}
			root_record["last_z"] = enemy.global_position.z
			root_record["last_time"] = clock
			root_record["last_world"] = game.game_clock
			root_record["forward_distance"] = float(root_record.last_z) - float(root_record.first_z)
			dead_motion_records[enemy_key] = root_record
		for child in enemy.get_children():
			if child.is_queued_for_deletion():
				continue
			var child_key := str(child.get_instance_id())
			if child.get_meta("cut_chip", false):
				chip_ids_seen[child_key] = true
			if not child.get_meta("voxel_piece", false):
				continue
			live_count += 1
			var record: Dictionary = fragment_records.get(child_key, {})
			if record.is_empty():
				var count: int = child.get_voxel_count()
				fragments_spawned_seen += 1
				largest_fragment_cells_seen = maxi(largest_fragment_cells_seen, count)
				record = {"id": child.get_instance_id(), "enemy_id": enemy.get_instance_id(), "kind": enemy.enemy_kind, "initial_cells": count, "first_time": clock, "first_world": game.game_clock, "first_z": child.global_position.z, "last_z": child.global_position.z, "last_time": clock, "last_world": game.game_clock, "max_forward_world_speed": 0.0, "observations": 0}
			var world_step: float = game.game_clock - float(record.last_world)
			if world_step > 0.00001:
				var forward_speed: float = (child.global_position.z - float(record.last_z)) / world_step
				record["max_forward_world_speed"] = maxf(float(record.max_forward_world_speed), forward_speed)
			record["last_z"] = child.global_position.z
			record["last_time"] = clock
			record["last_world"] = game.game_clock
			record["observations"] = int(record.observations) + 1
			fragment_records[child_key] = record
			if fragment_motion_samples.size() < 180 and enemy.get_instance_id() == first_sever_enemy_id:
				fragment_motion_samples.append({"time_after_sever": clock - first_sever_at, "world_after_sever": game.game_clock - first_sever_world, "fragment_id": child.get_instance_id(), "z": child.global_position.z, "cells": child.get_voxel_count()})
	max_live_fragments = maxi(max_live_fragments, live_count)
	max_live_cut_particles = maxi(max_live_cut_particles, particle_count)


func _observe_grip() -> void:
	if not game.slashing or not game.sword.has_method("get_grip_screen_position"):
		return
	# Visual pose only; this never feeds the targeting or input policy.
	if str(game.sword.get("_mode")) != "held" or not game.sword.get("_drawn").visible:
		return
	var actual: Vector2 = game.sword.get_grip_screen_position()
	var error: float = actual.distance_to(game.slash_cursor)
	grip_errors.append(error)
	var blade_error := 0.0
	if game.sword.has_method("blade_segment_for_grip") and _has_property(game, "blade_direction"):
		var expected: PackedVector2Array = game.sword.blade_segment_for_grip(game.slash_cursor, game.blade_direction, game.get_viewport().get_visible_rect().size)
		var drawn: Node3D = game.sword.get("_drawn")
		var actual_base: Vector2 = game.camera.unproject_position(drawn.to_global(game.sword.EDGE_BASE))
		var actual_tip: Vector2 = game.camera.unproject_position(drawn.to_global(game.sword.EDGE_TIP))
		blade_error = maxf(actual_base.distance_to(expected[0]), actual_tip.distance_to(expected[1]))
		blade_errors.append(blade_error)
	var new_maximum: bool = error > largest_grip_error_observed + 0.01
	largest_grip_error_observed = maxf(largest_grip_error_observed, error)
	if (clock >= next_grip_sample or new_maximum) and grip_samples.size() < 140:
		next_grip_sample = clock + 0.12
		grip_samples.append({"time": clock, "sample_phase": "pre_manual_update" if fast_mode else "frame_post_draw", "frame": Engine.get_process_frames(), "pending_strokes": game.pending_strokes.size(), "grip_error_px": error, "blade_error_px": blade_error, "cursor_x": game.slash_cursor.x, "cursor_y": game.slash_cursor.y, "grip_x": actual.x, "grip_y": actual.y})


func _step_fast_fragments() -> void:
	# A fast run advances the root manually. Advance its debris by the same
	# production process too, instead of letting one real frame represent 120 ticks.
	for enemy in game.enemies:
		if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		for child in enemy.get_children():
			if child.is_queued_for_deletion() or not (child.get_meta("voxel_piece", false) or child.get_meta("cut_chip", false)):
				continue
			child.set_process(false)
			child._process(STEP)


func _observe_contact_path() -> void:
	if not game.slashing:
		previous_contact_grip = Vector2(INF, INF)
		previous_contact_point = Vector2(INF, INF)
		last_contact_serial = game.cut_serial
		return
	if game.cut_serial == last_contact_serial:
		return
	last_contact_serial = game.cut_serial
	var drawn: Node3D = game.sword.get("_drawn")
	if not is_instance_valid(drawn) or not drawn.visible:
		return
	var grip: Vector2 = game.sword.get_grip_screen_position()
	var contact: Vector2 = game.camera.unproject_position(drawn.to_global(game.sword.ACTIVE_CUT_POINT))
	if previous_contact_grip.is_finite() and contact_motion_samples.size() < 90:
		var grip_delta: Vector2 = grip - previous_contact_grip
		var active_delta: Vector2 = contact - previous_contact_point
		var path: PackedVector2Array = game.blade_path
		var preview: Array = []
		var stride: int = maxi(1, int(ceil(float(path.size()) / 6.0)))
		for index in range(0, path.size(), stride):
			preview.append([path[index].x, path[index].y])
		contact_motion_samples.append({"time": clock, "cut_serial": game.cut_serial, "grip_delta": [grip_delta.x, grip_delta.y], "active_delta": [active_delta.x, active_delta.y], "last_cut_path_count": path.size(), "last_cut_path": preview})
	previous_contact_grip = grip
	previous_contact_point = contact


func _imminent_threat() -> Dictionary:
	for enemy in game.enemies:
		if not is_instance_valid(enemy) or enemy.dead or enemy.resolved or not _in_view(_visible_body(enemy)):
			continue
		var action: String = str(enemy.get_meta("action_state", "run"))
		var phase: float = float(enemy.get_meta("action_phase", 0.0))
		var guard_now: bool = (action == "windup" and phase >= 0.92) or (action == "strike" and phase < 0.52)
		if policy != "basic":
			guard_now = action == "strike" and phase >= 0.2 and phase < 0.52
		if guard_now:
			if not bool(enemy.get_meta("impact_done", false)):
				return {"type": "melee", "enemy": enemy}
	for projectile in game.projectiles:
		var node: Node3D = projectile.node
		if not is_instance_valid(node) or node.position.z < -5.0 or bool(projectile.get("reflected", false)):
			continue
		var identifier := str(node.get_instance_id())
		var observation: Dictionary = previous_projectiles.get(identifier, {})
		var approach_speed := float(observation.get("velocity_z", 0.0))
		if approach_speed <= 0.0:
			continue
		var time_left := (-node.position.z - 0.9) / maxf(approach_speed, 1.0)
		var response_lead := 0.19 if policy == "basic" else 0.10
		if time_left > -0.05 and time_left < response_lead:
			return {"type": "projectile", "node": node, "time_left": time_left}
	return {}


func _target() -> Node3D:
	# Let both opening Boss attacks finish without a collateral sweep at another enemy.
	if game.boss_spawned and boss_strikes_seen < 2:
		return null
	var selected: Node3D
	var best := INF
	for enemy in game.enemies:
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		var action: String = str(enemy.get_meta("action_state", "run"))
		if enemy.resolved and not action in ["recover", "stagger"]:
			continue
		if enemy.position.z < -31.0 or enemy.position.z > -3.5 or not _in_view(_visible_body(enemy)):
			continue
		if enemy.enemy_kind == "boss" and boss_strikes_seen < 2:
			continue
		if enemy.enemy_kind not in ["boss", "barrier", "beam"] and not attack_pose_ready.has(enemy.enemy_kind):
			# The first member of each kind must complete a real strike or fire a shot.
			continue
		if policy == "basic" and enemy.enemy_kind == "normal" and game.kills == 0:
			# Observe and defend one normal attack instead of erasing every enemy at spawn.
			if not action in ["recover", "stagger", "exit"]:
				continue
		var distance: float = -enemy.position.z
		if enemy.enemy_kind in ["barrier", "beam"]:
			# A physical obstruction has no attack windup to wait for and cannot
			# be answered by parrying. Start cutting its visible span on approach.
			distance -= 24.0
		if action in ["windup", "ranged_charge"]:
			distance -= 10.0
		if distance < best:
			best = distance
			selected = enemy
	return selected


func _control(dt: float) -> void:
	clock += dt
	_observe(dt)
	if clock > max_seconds:
		timed_out = true
		return
	if game.state != "playing":
		return
	if parry_held:
		if game.guard_active and clock < block_after: return
		_send_button(false,MOUSE_BUTTON_RIGHT)
		parry_held = false
	if game.boss_spawned and boss_strikes_seen < 2:
		_release_left()
	if left_held:
		if clock >= release_at or (game.slash_lock and not game.slashing):
			_release_left()
		else:
			_step_sweep()
	var wants_shift := false
	if policy == "speed":
		wants_shift = true
	elif policy == "mixed":
		wants_shift = game.speed < (37.0 if shift_held else 33.0)
	else:
		wants_shift = game.speed < (23.0 if shift_held else 20.0)
	_set_shift(wants_shift)
	if clock < next_decision:
		return
	next_decision = clock + 0.025
	var threat := _imminent_threat()
	if not threat.is_empty():
		_press_parry(threat)
		return
	if first_sever_at >= 0.0 and clock - first_sever_at < 0.62:
		# Let the first actual kill fly past for observation; defense remains active.
		_release_left()
		return
	if left_held or clock < attack_after:
		return
	var target := _target()
	if target == null:
		return
	var action: String = str(target.get_meta("action_state", "run"))
	var use_long: bool = policy == "speed" or (policy == "mixed" and target.enemy_kind in ["tank", "boss", "barrier", "beam", "missile_drone", "shield_drone", "mine_layer"])
	if target.enemy_kind == "boss" and action in ["boss_windup", "boss_strike"]:
		# Let the pose finish; answer its shot, then attack the recovery opening.
		return
	var error := _aim_at(target)
	if error < 48.0:
		attack_decisions.append({"time": clock, "world": game.game_clock, "kind": target.enemy_kind, "enemy_id": target.get_instance_id(), "action": action, "screen_error": error, "distance": -target.position.z, "long": use_long and game.speed > 18.0})
		if use_long and game.speed > 18.0:
			_begin_sweep()
		else:
			_press_short()


func _queue_capture(name: String, priority: bool = false) -> void:
	if fast_mode or DisplayServer.get_name() == "headless" or screenshots_taken.has(name):
		return
	if capture_queue.has(name):
		return
	if priority:
		capture_queue.push_front(name)
	else:
		capture_queue.append(name)


func _capture_next(after_render: bool = false) -> void:
	if capture_queue.is_empty():
		return
	var name: String = capture_queue.pop_front()
	screenshots_taken[name] = true
	if not after_render:
		await RenderingServer.frame_post_draw
	var started := Time.get_ticks_usec()
	var image: Image = game.get_viewport().get_texture().get_image()
	capture_readback_ms.append(float(Time.get_ticks_usec() - started) * 0.001)
	var path := output_dir.path_join(run_label + "-" + name + ".png")
	if buffer_captures:
		buffered_captures.append({"image": image, "path": path})
	else:
		image.save_png(path)
	capture_timing[name] = {"controller_time": clock, "world_time": game.game_clock, "since_first_sever_real": game.real_clock - first_sever_real_clock if first_sever_real_clock >= 0.0 else -1.0}


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output_dir)
	seed(run_seed)
	Engine.max_fps = 60
	Input.use_accumulated_input = false
	runtime_manifest_before = _runtime_manifest()
	review_tool_hash_before = FileAccess.get_sha256(get_script().resource_path)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	if not fast_mode and DisplayServer.get_name() != "headless":
		# Match an actual menu presentation before Enter; this permits the
		# production showcase to render its assets before combat timing starts.
		await RenderingServer.frame_post_draw
	game.test_mode = true
	# Menu preparation may create cosmetic particles; reset the combat seed
	# after it so those draws do not consume the replay's gameplay sequence.
	seed(run_seed)
	if not _has_property(game, "route_duration"):
		push_error("Normal combat replay requires the production route_duration property.")
		game.free()
		quit(2)
		return
	game.route_duration = route_seconds
	game.practice = false
	game.training = false
	observes_sections = _has_property(game,"route_section")
	observes_blasts = _has_property(game,"blasts")
	DisplayServer.window_set_title("Slay the highway / 杀路 - normal combat - " + run_label)
	_send_key(KEY_ENTER, true)
	_send_key(KEY_ENTER, false)
	# Enter still follows the real menu action. A sliceable button now presents
	# its split before dispatch, and warm-up may queue the same action, so wait
	# for the production transition instead of assuming it fits in one frame.
	var menu_wait_started := Time.get_ticks_usec()
	while game.state == "menu" and Time.get_ticks_usec()-menu_wait_started < 5000000:
		await process_frame
	if game.state == "menu":
		timed_out = true
		push_error("Normal combat replay menu action did not start within five real seconds.")
	_observe_route_section()
	await process_frame
	# Synthetic relative input does not require OS pointer capture or native focus.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	health_before = game.health
	if fast_mode:
		game.set_process(false)
		game.sword.set_process(false)
	last_wall_usec = Time.get_ticks_usec()
	while game.state == "playing" and not timed_out and not forbidden_mode_seen:
		if fast_mode:
			_control(STEP)
			game._process(STEP)
			game.sword._process(STEP)
			_step_fast_fragments()
			if frames % 120 == 0:
				await process_frame
		else:
			await process_frame
			var now := Time.get_ticks_usec()
			var delta := maxf(float(now - last_wall_usec) / 1000000.0, 0.001)
			last_wall_usec = now
			frame_times_ms.append(delta * 1000.0)
			_record_long_frame(delta * 1000.0)
			_control(delta)
			# process_frame resumes before the nodes consume new mouse input.
			# Measure the pose that was actually rendered, not the queued cursor
			# against the previous frame's sword, and reuse this draw for captures.
			await RenderingServer.frame_post_draw
			_observe_grip()
			_observe_contact_path()
			if not capture_queue.is_empty():
				await _capture_next(true)
			if game.kills > 0:
				_queue_capture("first-sever")
	_release_left()
	_set_shift(false)
	var source_events: Array = game.get("combat_events") if _has_property(game, "combat_events") else []
	var source_stats: Dictionary = game.get("combat_stats") if _has_property(game, "combat_stats") else {}
	frame_times_ms.sort()
	observed_cut_times_ms.sort()
	grip_errors.sort()
	blade_errors.sort()
	var p95_frame_ms := frame_times_ms[int(floor(float(frame_times_ms.size() - 1) * 0.95))] if not frame_times_ms.is_empty() else 0.0
	var runtime_manifest_after := _runtime_manifest()
	var review_tool_hash_after := FileAccess.get_sha256(get_script().resource_path)
	var source_hashes: Dictionary = {}
	for path in REVIEW_SOURCE_PATHS:
		source_hashes[path] = runtime_manifest_after[path].raw_sha256
	output = {
		"grip_observation_phase": "pre_manual_update" if fast_mode else "frame_post_draw",
		"source_hashes": source_hashes,
		"runtime_manifest_before": runtime_manifest_before, "runtime_manifest_after": runtime_manifest_after,
		"sources_unchanged": runtime_manifest_before == runtime_manifest_after,
		"review_tool_sha256_before":review_tool_hash_before,"review_tool_sha256_after":review_tool_hash_after,"review_tool_unchanged":review_tool_hash_before == review_tool_hash_after,
		"manifest_scope":"Raw source hashes when available; exported PCKs use remapped compiled-resource hashes. Compiled bytes are not claimed byte-equal to GDScript source.",
		"label": run_label, "policy": policy, "mode": "fast-screening" if fast_mode else "real-time",
		"seed": run_seed, "parry_decisions": parry_decisions, "attack_decisions": attack_decisions,
		"route_duration": route_seconds, "outcome": game.state, "controller_time": clock,
		"world_time": game.game_clock, "route_time": game.elapsed, "health_remaining": game.health,
		"score": game.score, "kills": game.kills, "boss_attack_cycles_observed": boss_strikes_seen,
		"practice": game.practice, "training": game.training, "forbidden_mode_seen": forbidden_mode_seen,
		"timed_out": timed_out, "inputs": input_counts, "enemy_types_seen": types_seen.keys(),
		"actions_seen": actions_seen, "action_transitions": transitions, "damage_samples": damage_samples,
		"section_transitions": section_transitions, "long_frames": long_frames,
		"combat_stats": source_stats, "combat_events": source_events,
		"speed_min": min_speed, "speed_max": max_speed, "sampled_frame_p95_ms": p95_frame_ms,
		"sampled_frame_count": frame_times_ms.size(),
		"sampled_frame_p50_ms": frame_times_ms[frame_times_ms.size() / 2] if not frame_times_ms.is_empty() else 0.0,
		"sampled_frames_over_25ms": _slow_frame_count(25.0),
		"sampled_frames_over_50ms": _slow_frame_count(50.0),
		"sampled_frames_over_100ms": _slow_frame_count(100.0),
		"sampled_frame_p99_ms": frame_times_ms[int(float(frame_times_ms.size()-1)*0.99)] if not frame_times_ms.is_empty() else 0.0,
		"sampled_frame_max_ms": frame_times_ms[-1] if not frame_times_ms.is_empty() else 0.0,
		"observed_cut_time_max_ms": observed_cut_times_ms[-1] if not observed_cut_times_ms.is_empty() else 0.0,
		"observed_cut_time_p95_ms": observed_cut_times_ms[int(float(observed_cut_times_ms.size()-1)*0.95)] if not observed_cut_times_ms.is_empty() else 0.0,
		"cut_timing_scope": "Latest successful cut per enemy per observed frame; may omit earlier cuts in that same frame. CPU function timing, not GPU time.",
		"fragments_spawned_seen": fragments_spawned_seen, "cut_chips_seen": chip_ids_seen.size(), "max_live_fragments": max_live_fragments, "largest_fragment_cells_seen": largest_fragment_cells_seen,
		"max_live_cut_particles": max_live_cut_particles, "cut_particle_records": cut_particle_records,
		"sever_material_observations": sever_samples, "fragment_records": fragment_records.values(), "dead_root_motion_records": dead_motion_records.values(), "first_sever_fragment_motion_samples": fragment_motion_samples,
		"grip_error_max_px": grip_errors[-1] if not grip_errors.is_empty() else -1.0, "blade_error_max_px": blade_errors[-1] if not blade_errors.is_empty() else -1.0,
		"grip_error_p95_px": grip_errors[int(float(grip_errors.size() - 1) * 0.95)] if not grip_errors.is_empty() else -1.0,
		"grip_samples": grip_samples, "capture_timing": capture_timing,
		"capture_png_writes_deferred": buffer_captures,
		"capture_readback_ms": capture_readback_ms,
		"frame_timing_scope":"Start-to-start process_frame intervals include game/controller/observation work, screenshots' Image readback, and PNG writes unless deferred. Long-frame context is sampled at interval end before the next controller input; it identifies nearby activity, not a proved cause.",
		"single_contact_motion_samples": contact_motion_samples,
		"last_cut_path": _point_pairs(game.blade_path),
		"screenshots": screenshots_taken.keys(),
		"limitations": "Reactive input bot observes visible action state and silhouette centres; not a human playability verdict. Fast screening does not measure rendered frame performance. Route override only shortens normal production progression.",
	}
	var report := FileAccess.open(output_dir.path_join(run_label + ".json"), FileAccess.WRITE)
	report.store_string(JSON.stringify(output, "\t"))
	report.close()
	print("NORMAL COMBAT REPLAY: ", JSON.stringify({"label":run_label,"outcome":game.state,"health":game.health,"kills":game.kills,"time":clock,"boss_cycles":boss_strikes_seen,"stats":source_stats,"forbidden":forbidden_mode_seen,"timeout":timed_out}))
	var succeeded: bool = game.state == "won" and not forbidden_mode_seen and not timed_out
	if fast_mode:
		game.audio.set_runner_motion(0.0, 0.0, false, 0.0)
		await create_timer(1.5).timeout
	for capture in buffered_captures:
		capture.image.save_png(capture.path)
	buffered_captures.clear()
	game.free()
	await create_timer(0.2).timeout
	quit(0 if succeeded else 1)


func _slow_frame_count(threshold: float) -> int:
	var count := 0
	for interval in frame_times_ms:
		if interval > threshold:
			count += 1
	return count


func _point_pairs(points: PackedVector2Array) -> Array:
	var result: Array = []
	for point in points:
		result.append([point.x, point.y])
	return result
