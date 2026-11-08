extends SceneTree
## Behavioral regression checks for the prototype's agreed combat rules.

var failures: int = 0
var checks: int = 0
var game
var normal_precision_aims := {
	"arm": Vector3(0.54, 1.48, -9.0),
	"chest": Vector3(0.28, 1.48, -9.0),
	"waist": Vector3(-0.9, 1.27, -9.0),
}


func _initialize() -> void:
	call_deferred("_run")


func expect(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func clear_targets() -> void:
	for enemy in game.enemies:
		if is_instance_valid(enemy):
			enemy.free()
	game.enemies.clear()
	game._clear_projectiles()


func cut_right_hand(enemy) -> Dictionary:
	# Aim at the visible hand after its current arm pose, rather than its rest grid.
	if enemy.enemy_kind == "normal" and float(enemy._cell) < 0.075:
		# The rebuilt slasher is authored in metres at 5cm resolution. Its hand
		# is no longer old grid rows 12..14; cross its actual wrist instead of
		# slicing vertically down only the middle of a multi-cell palm.
		var low := Vector3(INF, INF, INF)
		var high := Vector3(-INF, -INF, -INF)
		for index in range(enemy._voxels.size()):
			if enemy._voxels[index] == 0 or enemy._part_for_index(index) != 2:
				continue
			var coordinate: Vector3i = enemy._coords(index)
			var local: Vector3 = enemy._point(coordinate.x, coordinate.y, coordinate.z)
			if local.y >= 1.14 and local.y <= 1.39 and local.x > 0.49 and local.z > 0.10:
				low = low.min(local)
				high = high.max(local)
		if not low.is_finite() or not high.is_finite():
			return {"removed": 0, "killed": false, "fixture_error": "normal hand region contains no cells"}
		var wrist_y: float = high.y + float(enemy._cell) * 0.5
		var middle_z: float = (low.z + high.z) * 0.5
		var pose: Transform3D = enemy._part_pose(2)
		var from: Vector2 = game.camera.unproject_position(enemy.to_global(pose * Vector3(low.x - 0.08, wrist_y, middle_z)))
		var to: Vector2 = game.camera.unproject_position(enemy.to_global(pose * Vector3(high.x + 0.08, wrist_y, middle_z)))
		return enemy.cut_screen(game.camera, from, to, 4.0)
	if enemy.enemy_kind in ["tank", "ranged", "boss"] and int(enemy.PART_COUNT) > 3:
		# Rebuilt models are authored in metres, with independent leg groups.
		# Cross the visible wrist above the actual palm, not obsolete grid rows.
		var palm_low := 1.02 if enemy.enemy_kind == "tank" else (1.92 if enemy.enemy_kind == "boss" else 1.70)
		var palm_high := 1.38 if enemy.enemy_kind == "tank" else (2.38 if enemy.enemy_kind == "boss" else 1.98)
		var palm_reach := 1.12 if enemy.enemy_kind == "tank" else (2.25 if enemy.enemy_kind == "boss" else 0.40)
		var wrist_y := 1.42 if enemy.enemy_kind == "tank" else (2.45 if enemy.enemy_kind == "boss" else 2.00)
		var palm_low_point := Vector3(INF,INF,INF)
		var palm_high_point := Vector3(-INF,-INF,-INF)
		for index in enemy._live_indices:
			var point: Vector3 = enemy._cell_points[index]
			if enemy._voxels[index] != 0 and enemy._part_ids[index] == 2 and point.y >= palm_low and point.y <= palm_high and point.x > palm_reach and point.z > 0.04:
				palm_low_point = palm_low_point.min(point)
				palm_high_point = palm_high_point.max(point)
		if not palm_low_point.is_finite():
			return {"removed":0,"killed":false,"fixture_error":"new right palm contains no real material"}
		var pose: Transform3D = enemy._part_pose(2)
		var middle_z := (palm_low_point.z+palm_high_point.z)*0.5
		var from: Vector2 = game.camera.unproject_position(enemy.to_global(pose*Vector3(palm_low_point.x-0.12,wrist_y,middle_z)))
		var to: Vector2 = game.camera.unproject_position(enemy.to_global(pose*Vector3(palm_high_point.x+0.12,wrist_y,middle_z)))
		var removed := 0
		var passes := 0
		# Thick wrists are actually layered material. Repeat the same wrist cut
		# while it still removes material; no HP, forced sever or fixed immunity.
		for pass_index in range(enemy._dimensions.z):
			var result: Dictionary = enemy.cut_screen(game.camera,from,to,4.0)
			removed += int(result.removed)
			passes += 1
			var palm_remains := false
			for index in enemy._live_indices:
				var point: Vector3 = enemy._cell_points[index]
				if enemy._voxels[index] != 0 and enemy._part_ids[index] == 2 and point.y >= palm_low and point.y <= palm_high and point.x > palm_reach and point.z > 0.04:
					palm_remains = true
					break
			if not palm_remains or int(result.removed) == 0 or enemy.dead:
				break
		print("WRIST MATERIAL CUT: ",enemy.enemy_kind," passes=",passes," removed=",removed," remaining=",enemy.get_remaining_voxel_count())
		return {"removed":removed,"killed":enemy.dead,"passes":passes}
	var left: float = INF
	var right: float = -INF
	var top: float = INF
	var bottom: float = -INF
	var hand_low: int = 6 if enemy.enemy_kind == "boss" else 12
	var hand_high: int = 8 if enemy.enemy_kind == "boss" else 14
	for index in range(enemy._voxels.size()):
		var coordinate: Vector3i = enemy._coords(index)
		if enemy._voxels[index] == 0 or enemy._part_for_index(index) != 2 or coordinate.y < hand_low or coordinate.y > hand_high:
			continue
		var point: Vector2 = game.camera.unproject_position(enemy._posed_world_point(index))
		left = minf(left, point.x)
		right = maxf(right, point.x)
		top = minf(top, point.y)
		bottom = maxf(bottom, point.y)
	if not is_finite(left) or not is_finite(right):
		return {"removed": 0, "killed": false, "fixture_error": "hand region contains no cells"}
	var middle_x: float = (left + right) * 0.5
	return enemy.cut_screen(game.camera, Vector2(middle_x, top), Vector2(middle_x, bottom), 4.0)


func configure_normal_fixture_anatomy() -> void:
	var probe = game._spawn_enemy("normal", 1, -9.0)
	probe.position.x = 0.0
	probe.set_action("recover", 1.0)
	if float(probe._cell) < 0.075:
		normal_precision_aims = {
			# The right arm crosses the chest in its new ready pose. The left
			# outer forearm gives an isolated noncritical skim; apply its actual
			# posed transform rather than aiming at an obsolete standing hand.
			"arm": probe.to_global(probe._part_pose(1) * Vector3(-0.725, 1.475, 0.275)),
			"chest": probe.to_global(probe._part_pose(0) * Vector3(0.225, 1.975, 0.35)),
			"waist": probe.to_global(probe._part_pose(0) * Vector3(-0.9, 1.425, 0.025)),
		}
	print("NORMAL FIXTURE ANATOMY: cell=", probe._cell, " points=", normal_precision_aims)
	game.enemies.erase(probe)
	probe.free()


func pointer_motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	var canvas_to_window: Transform2D = game.get_viewport().get_final_transform()
	event.relative = relative * canvas_to_window.get_scale()
	event.screen_relative = event.relative
	event.position = canvas_to_window * game.slash_cursor
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func pointer_button(pressed: bool, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func prepare_grip_input() -> void:
	clear_targets()
	game.start_game()
	game.camera.rotation = Vector3.ZERO
	game.camera.fov = 78.0
	game.speed = 48.0
	game.gear = 4
	game.spawn_timer = 999.0
	game.sword.set_pose("sheathed")
	game.sword._process(0.02)
	pointer_button(true)
	game._process(0.15)
	# The hilt leads horizontal motion and the blade trails to its left.
	# No private axis assignment or target/core auto-aim is used to settle it.
	var destination := Vector2(500, 430)
	pointer_motion((destination - game.slash_cursor) / 1.05)
	game._process(0.016)
	pointer_motion(Vector2(250.0 / 1.05, 0))
	game._process(0.016)
	game.sword._process(0.016)


func screen_voxel(owner_node: Node3D, screen_point: Vector2):
	var piece = load("res://scripts/voxel_debris.gd").new()
	owner_node.add_child(piece)
	piece.global_position = game.camera.project_position(screen_point, 9.0)
	var colors: Array[Color] = [Color.TRANSPARENT, Color.WHITE]
	piece.configure_voxels({Vector3i.ZERO: 1}, 0.18, colors, StandardMaterial3D.new(), Vector3.ZERO)
	piece.set_process(false)
	return piece


func prepare_precision_input(contact_world_point: Vector3) -> void:
	# Isolate wound geometry from enemy movement. Input still follows the real
	# parsed pointer chain; this fixture is not used as normal-play evidence.
	game.training = true
	prepare_grip_input()
	var size: Vector2 = game.get_viewport().get_visible_rect().size
	var contact_screen: Vector2 = game.camera.unproject_position(contact_world_point)
	var grip: Vector2 = game.sword.grip_for_active_cut_point(contact_screen, Vector2.LEFT, size)
	pointer_motion((grip - Vector2(520, 0) - game.slash_cursor) / 1.05)
	game._process(0.016)
	pointer_motion(Vector2(520.0 / 1.05, 0))
	game._process(0.016)
	game.sword._process(0.016)


func precision_target():
	var target = game._spawn_enemy("normal", 1, -9.0)
	target.position.x = 0.0
	target.set_action("recover", 1.0)
	return target


func verify_armored_light_contacts() -> void:
	# Reproduce the reported one-tap heavy kills through actual button events,
	# every authored ordinary cut and the four production power settings.
	var records: Array = []
	var sword_was_processing: bool = game.sword.is_processing()
	game.sword.set_process(false)
	for kind in ["tank", "boss"]:
		for gear_value in range(1, 5):
			var contacts_survive := true
			var all_contacted := true
			for style in range(12):
				clear_targets()
				game.start_game()
				game.training = false
				game.practice = false
				game.spawn_timer = 999.0
				game.speed = [18.0, 28.0, 40.0, 56.0][gear_value - 1]
				game.gear = gear_value
				game.camera.position = Vector3(0, 1.75, 0)
				game.camera.rotation = Vector3.ZERO
				game.camera.fov = 78.0
				var target = game._spawn_enemy(kind, 1, -16.0 if kind == "boss" else -9.0)
				target.position.x = 0.0
				target.set_action("recover", 1.0)
				game.camera.look_at(target.get_aim_point())
				game.sword.set_pose("sheathed")
				game.sword._process(0.8)
				game.quick_slash_index = style
				var before: int = target.get_remaining_voxel_count()
				pointer_button(true)
				pointer_button(false)
				var removed: int = before - target.get_remaining_voxel_count()
				all_contacted = all_contacted and removed > 0
				contacts_survive = contacts_survive and not target.dead and game.kills == 0
				records.append({"kind": kind, "gear": gear_value, "style": style, "removed": removed, "dead": target.dead, "kills": game.kills, "remaining": target.get_remaining_voxel_count()})
			expect(all_contacted and contacts_survive, kind + " gear " + str(gear_value) + " takes real local material damage from all twelve parsed first light attacks without an instant kill")
			await process_frame
	var version_label: String = str(ProjectSettings.get_setting("application/config/version", "development")).validate_filename()
	var report_dir := "res://builds/verification/".path_join(version_label)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report_dir))
	var report := FileAccess.open(report_dir.path_join("parsed-first-light.json"), FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify({"scope": "Stationary fresh heavy targets, real parsed left-button attacks; does not certify normal play or require a fixed number of hits.", "rows": records}, "\t"))
		report.close()
	clear_targets()
	game.sword.set_process(sword_was_processing)


func verify_weapon_motion_contracts() -> void:
	# These fixtures prevent the specific teleport / invisible-on-contact bugs.
	# Continuous motion quality is reviewed separately from the recorded video.
	clear_targets()
	game.start_game()
	game.training = true
	game.spawn_timer = 999.0
	game.speed = 48.0
	game.gear = 4
	game.sword.set_pose("sheathed")
	for sample in range(40):
		game.sword._process(1.0 / 60.0)
	var before_serial: int = game.cut_serial
	pointer_button(true)
	var debug: Dictionary = game.sword.get_animation_debug_state()
	expect(game.cut_serial == before_serial + 1 and game.sword._drawn.visible and not game.sword._handle.visible and debug.phase == "draw_contact", "ordinary press resolves with the physical blade already drawn in its contact phase")
	for sample in range(7):
		game._process(1.0 / 60.0)
		game.sword._process(1.0 / 60.0)
	# A visible impact can leave nonzero camera roll at the exact entry frame.
	game.camera.rotation.z = 0.08
	game.camera.position += Vector3(0.03, 0.01, 0.0)
	game.camera.fov = 81.3
	var entry_rotation: Vector3 = game.camera.rotation
	var entry_position: Vector3 = game.camera.position
	var entry_fov: float = game.camera.fov
	var before_grip: Vector2 = game.sword.get_grip_screen_position()
	var before_tip: Vector2 = game.camera.unproject_position(game.sword._drawn.to_global(Vector3(0, 0.86, 0)))
	var before_rotation: Quaternion = game.sword._drawn.transform.basis.get_rotation_quaternion()
	# The eighth held frame crosses the real long-press threshold. Observe
	# takeover before the next render update, with no synthetic centre pose.
	game._process(1.0 / 60.0)
	var after_tip: Vector2 = game.camera.unproject_position(game.sword._drawn.to_global(Vector3(0, 0.86, 0)))
	var after_rotation: Quaternion = game.sword._drawn.transform.basis.get_rotation_quaternion()
	expect(game.slashing and game.sword.get_grip_screen_position().distance_to(before_grip) < 0.1 and after_tip.distance_to(before_tip) < 0.1 and before_rotation.angle_to(after_rotation) < 0.01, "long-press takeover preserves the visible grip, blade tip and orientation across the input boundary")
	expect(game.camera.rotation.is_equal_approx(entry_rotation) and game.camera.position.is_equal_approx(entry_position) and is_equal_approx(game.camera.fov, entry_fov), "blade-mode entry locks the full current camera rotation including impact roll, position and FOV")
	game.sword._process(1.0 / 60.0)
	var maximum_inverse_error := 0.0
	var size: Vector2 = game.get_viewport().get_visible_rect().size
	for axis in [Vector2.UP, Vector2(0.6, -0.8), Vector2(-0.8, -0.6)]:
		for point in [Vector2(200, 180), Vector2(640, 360), Vector2(1080, 540)]:
			var inverse_grip: Vector2 = game.sword.grip_for_active_cut_point(point, axis, size)
			var projected: Vector2 = game.sword.active_cut_point_for_grip(inverse_grip, axis, size)
			maximum_inverse_error = maxf(maximum_inverse_error, projected.distance_to(point))
	expect(maximum_inverse_error < 0.01, "three-dimensional blade contact has an accurate grip inverse across the screen and tilted axes")
	pointer_button(false)
	game._process(1.0 / 60.0)
	game.sword._process(1.0 / 60.0)
	debug = game.sword.get_animation_debug_state()
	expect(not game.slashing and game.sword._drawn.visible and not game.sword._handle.visible and debug.sheathing, "release keeps rendering the same physical sword while it travels to the sheath")
	for sample in range(40):
		game._process(1.0 / 60.0)
		game.sword._process(1.0 / 60.0)
	debug = game.sword.get_animation_debug_state()
	var dock: Transform3D = game.sword._dock_transform()
	var returned: Transform3D = game.sword._drawn.transform
	expect(game.sword._drawn.visible and not game.sword._handle.visible and debug.phase == "docked" and returned.origin.distance_to(dock.origin) < 0.01 and returned.basis.get_rotation_quaternion().angle_to(dock.basis.get_rotation_quaternion()) < 0.01, "the same physical katana reaches its docked transform only after the sheath insertion completes")
	pointer_button(true, MOUSE_BUTTON_RIGHT)
	pointer_button(false, MOUSE_BUTTON_RIGHT)
	for sample in range(4):
		game._process(1.0 / 60.0)
		game.sword._process(1.0 / 60.0)
	var empty_guard_phase: String = game.sword.get_animation_debug_state().phase
	# A timed enemy contact invokes the production damage phase. This is a
	# deterministic parry fixture, not a normal-play or human-feel verdict.
	game.training = false
	var enemy = game._spawn_enemy("normal", 1, -7.2)
	enemy.position.x = 0.0
	game._set_enemy_action(enemy, "strike", 0.28)
	enemy.set_meta("action_time", 0.14)
	game._process(1.0 / 60.0)
	game.sword._process(1.0 / 60.0)
	debug = game.sword.get_animation_debug_state()
	expect(game.combat_stats.parries == 1 and debug.phase == "parry_compress" and debug.phase != empty_guard_phase, "successful enemy contact enters a distinct compression phase instead of repeating the empty guard lift")
	for sample in range(3):
		game._process(1.0 / 60.0)
		game.sword._process(1.0 / 60.0)
	debug = game.sword.get_animation_debug_state()
	expect(debug.phase == "parry_rebound", "parry compression progresses into a separate unloading rebound")
	clear_targets()
	game.start_game()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func step_input(seconds: float) -> void:
	game._process(seconds)
	game.sword._process(seconds)


func verify_light_styles_and_hilt_direction() -> void:
	clear_targets()
	game.start_game()
	game.training = true
	game.spawn_timer = 999.0
	game.speed = 48.0
	game.gear = 4
	var definitions: Dictionary = {}
	var names: Dictionary = {}
	var count: int = game.sword.get_light_slash_count()
	for index in range(count):
		var definition: Dictionary = game.sword.get_light_slash_definition(index)
		definitions[definition.id] = true
		names[definition.name] = true
	expect(count >= 12 and definitions.size() == count and names.size() == count, "at least twelve distinct named light slashes are exposed to real input")
	var styles: Array = []
	var trajectories: Dictionary = {}
	var all_immediate := true
	var all_finite := true
	var all_at_aim := true
	for index in range(24):
		var before_serial: int = game.cut_serial
		pointer_button(true)
		var style: int = game.quick_slash_style
		styles.append(style)
		all_immediate = all_immediate and game.cut_serial == before_serial + 1
		var trace: PackedVector2Array = game.last_cut_path
		var edge_start: Vector2 = game.camera.unproject_position(game.sword._drawn.to_global(game.sword.EDGE_BASE))
		var edge_end: Vector2 = game.camera.unproject_position(game.sword._drawn.to_global(game.sword.EDGE_TIP))
		for point in trace:
			all_finite = all_finite and Geometry2D.get_closest_point_to_segment(point, edge_start, edge_end).distance_to(point) < 0.1
		var aim: Vector2 = game.get_viewport().get_visible_rect().size * 0.5
		var contact: Vector2 = game.camera.unproject_position(game.sword.get_contact_world_position())
		var contact_distance: float = INF
		for point in trace:
			contact_distance = minf(contact_distance, point.distance_to(contact))
		all_at_aim = all_at_aim and contact.distance_to(aim) < 0.1 and contact_distance < 0.1
		var signature: Array = [edge_start.snapped(Vector2.ONE), edge_end.snapped(Vector2.ONE)]
		pointer_button(false)
		step_input(0.04)
		signature.append(game.camera.unproject_position(game.sword._drawn.to_global(game.sword.EDGE_TIP)).snapped(Vector2.ONE))
		step_input(0.04)
		signature.append(game.camera.unproject_position(game.sword.get_contact_world_position()).snapped(Vector2.ONE))
		if index < count:
			trajectories[str(signature)] = true
	var ordered := styles.size() == 24
	for index in range(styles.size()):
		ordered = ordered and styles[index] == index % count and (index == 0 or styles[index] != styles[index - 1])
	expect(all_immediate and game.quick_slash_index == 24 and int(game.combat_stats.light_slashes) == 24 and ordered, "twenty-four real 80ms press-release clicks all resolve immediately through two nonrepeating twelve-style cycles")
	expect(trajectories.size() >= 12, "twelve light slashes have different projected contact and follow-through trajectories rather than renamed IDs")
	expect(all_finite and all_at_aim, "each light slash submits only its actual finite blade centreline through the aim point")
	var serial_before_duplicate: int = game.cut_serial
	pointer_button(true)
	pointer_button(true)
	pointer_button(false)
	expect(game.cut_serial == serial_before_duplicate + 1, "a duplicate pressed notification without physical release cannot invent a second light slash")
	var worst_alignment := 1.0
	var max_grip_error := 0.0
	for direction in [Vector2.RIGHT, Vector2(1, 1).normalized(), Vector2.DOWN, Vector2(-1, 1).normalized(), Vector2.LEFT, Vector2(-1, -1).normalized(), Vector2.UP, Vector2(1, -1).normalized()]:
		prepare_grip_input()
		pointer_motion(direction * (260.0 / 1.05))
		step_input(0.016)
		var actual: Vector2 = game.sword.get_blade_screen_direction()
		worst_alignment = minf(worst_alignment, actual.dot(-direction))
		max_grip_error = maxf(max_grip_error, game.sword.get_grip_screen_position().distance_to(game.slash_cursor))
	expect(worst_alignment > 0.99 and max_grip_error < 0.1, "all eight parsed drag directions lead with the hilt and leave the blade trailing while preserving the grip anchor")
	prepare_grip_input()
	var before_reversal: Vector2 = game.blade_direction
	var before_tiny: int = game.cut_serial
	pointer_motion(Vector2(-1.0 / 1.05, 0))
	step_input(0.016)
	var after_tiny: Vector2 = game.blade_direction
	var tiny_turn: float = absf(wrapf(after_tiny.angle() - before_reversal.angle(), -PI, PI))
	expect(game.cut_serial == before_tiny + 1 and tiny_turn > 0.0001 and tiny_turn < 0.12, "one-pixel reverse drag is consumed and starts a continuous half-turn instead of a dead zone or instant flip")
	pointer_motion(Vector2(-260.0 / 1.05, 0))
	step_input(0.016)
	expect(game.sword.get_blade_screen_direction().dot(Vector2.RIGHT) > 0.99, "sustained reverse drag completes the directed half-turn with the hilt leading the return cut")
	var retained: Vector2 = game.sword.get_blade_screen_direction()
	step_input(0.30)
	expect(game.sword.get_blade_screen_direction().dot(retained) > 0.999 and game.sword.get_grip_screen_position().distance_to(game.slash_cursor) < 0.1, "directed trailing blade retains its last pose on stop without returning to a preferred side")
	pointer_button(false)
	clear_targets()
	game.training = false


func verify_cut_voxel_particles() -> void:
	prepare_precision_input(normal_precision_aims.waist)
	var enemy = precision_target()
	pointer_motion(Vector2(92.0 / 1.05, 0))
	step_input(0.016)
	var particle_state: Dictionary = enemy.get_cut_particle_debug_state()
	var manager = enemy.get_node_or_null("CutVoxelBurst")
	expect(enemy.dead and manager != null and particle_state.get("last_source_kind", "") == "sever" and int(particle_state.get("emitted_sever", 0)) > 0 and int(particle_state.get("emitted_body", 0)) == int(particle_state.get("emitted_sever", 0)) and int(particle_state.get("emitted_total", 0)) == int(particle_state.get("last_burst_count", -1)), "real parsed structural severing emits one classified sever burst while retaining the body counter")
	if manager == null:
		return
	var max_source_offset := 0.0
	var max_line_distance := 0.0
	var signs: Dictionary = {}
	var tangent: Vector3 = particle_state.cut_tangent
	var normal: Vector3 = particle_state.cut_normal
	for index in range(particle_state.last_origins.size()):
		var source: Vector3 = particle_state.last_source_points[index]
		max_source_offset = maxf(max_source_offset, Vector3(particle_state.last_origins[index]).distance_to(source))
		var projected: Vector2 = game.camera.unproject_position(source)
		var distance: float = INF
		for point_index in range(game.last_cut_path.size() - 1):
			distance = minf(distance, Geometry2D.get_closest_point_to_segment(projected, game.last_cut_path[point_index], game.last_cut_path[point_index + 1]).distance_to(projected))
		max_line_distance = maxf(max_line_distance, distance)
		var velocity: Vector3 = particle_state.last_velocities[index]
		signs[Vector2i(1 if velocity.dot(tangent) >= 0 else -1, 1 if velocity.dot(normal) >= 0 else -1)] = true
	var warm_only := true
	for color: Color in particle_state.palette:
		warm_only = warm_only and color.r >= color.g and color.g >= color.b
	var solid_shapes: bool = particle_state.shape == "tumbling_voxel_blocks" and manager.cores.mesh is BoxMesh and manager.halos.mesh is BoxMesh
	for sample in particle_state.shape_samples:
		var dimensions: Vector3 = sample.dimensions
		solid_shapes = solid_shapes and dimensions.is_finite() and minf(dimensions.x, minf(dimensions.y, dimensions.z)) > 0.0
	expect(particle_state.style == "metal_spark" and solid_shapes and int(particle_state.cube_count) > 0 and float(particle_state.primary_aspect_max) < 3.0 and warm_only and particle_state.brightness_output == "unshaded_albedo", "cut sparks have real compact three-dimensional box geometry and warm hot facets instead of long flat laser strips")
	var hot: Color = load("res://scripts/voxel_debris.gd").spark_heat_color(0.0)
	var cool: Color = load("res://scripts/voxel_debris.gd").spark_heat_color(0.9)
	expect(hot.g > cool.g and hot.b > cool.b and cool.r > cool.g and float(particle_state.max_lifetime) <= 0.33, "metal sparks cool quickly from warm white through gold to orange-red embers")
	# A visible spark starts at the camera-facing surface of its actual removed
	# cell: half a cell plus 2% separation, with at most 5% tangent jitter.
	expect(max_source_offset <= float(particle_state.source_cell_max) * 0.53 and max_line_distance < 8.0 and signs.size() == 4, "particle origins stay on actual cut-cell surfaces and velocities scatter along both sides of the cut tangent and normal")
	var first_slot: Dictionary = {}
	for slot in manager.slots:
		if not slot.is_empty():
			first_slot = slot
			break
	var before_position: Vector3 = first_slot.position
	var before_age: float = first_slot.age
	var before_orientation: Basis = first_slot.orientation
	enemy.set_meta("simulation_scale", 0.0)
	manager._process(0.2)
	expect(first_slot.position == before_position and first_slot.age == before_age and first_slot.orientation == before_orientation, "hit-stop freezes voxel spark movement, tumbling and aging with the world")
	var score_after_kill: int = game.score
	var kills_after_cut: int = game.kills
	var sever_sparks_after_cut: int = particle_state.emitted_sever
	var total_before_recut: int = particle_state.emitted_debris
	for piece in enemy.get_children():
		if piece.get_meta("voxel_piece", false) and not piece.is_queued_for_deletion():
			var bounds: Rect2 = piece.get_screen_bounds(game.camera)
			enemy.cut_screen(game.camera, Vector2(bounds.position.x - 4, bounds.get_center().y), Vector2(bounds.end.x + 4, bounds.get_center().y), 2.15)
			if int(enemy.get_cut_particle_debug_state().emitted_debris) > total_before_recut:
				break
	particle_state = enemy.get_cut_particle_debug_state()
	expect(int(particle_state.emitted_debris) > total_before_recut and int(particle_state.emitted_sever) == sever_sparks_after_cut and game.score == score_after_kill and game.kills == kills_after_cut, "recutting real detached cells emits debris sparks without another sever burst, kill or score reward")
	var repeat_sources: PackedVector3Array = PackedVector3Array(particle_state.last_source_points).duplicate()
	for burst in range(20):
		manager.emit_from_cut(repeat_sources, Vector2.RIGHT, 0.1, "debris")
	particle_state = enemy.get_cut_particle_debug_state()
	var bounded_repeats: bool = int(particle_state.active_count) <= int(particle_state.capacity) and int(particle_state.global_active_count) <= int(particle_state.global_capacity)
	enemy.set_meta("simulation_scale", 1.0)
	manager._process(0.8)
	expect(int(enemy.get_cut_particle_debug_state().active_count) == 0, "cut voxel burst slots are reclaimed after their finite lifetime")
	expect(bounded_repeats and verify_saturated_spark_replacement(), "repeated bursts stay within both budgets and a globally full pool can replace only its owner's cooling sparks")
	pointer_button(false)
	clear_targets()
	game.training = false


func verify_saturated_spark_replacement() -> bool:
	# Exercise the new full-global-budget branch rather than infer it from a
	# single saturated local pool. This is an isolated visual resource fixture.
	var owners: Array[Node3D] = []
	var pools: Array = []
	var source: Vector3 = game.camera.project_position(game.get_viewport().get_visible_rect().size * 0.5, 9.0)
	for owner_index in range(5):
		var owner_node := Node3D.new()
		owner_node.set_meta("simulation_scale", 0.0)
		game.add_child(owner_node)
		owners.append(owner_node)
		VoxelDebris.emit_cut_particles(owner_node, game.camera, PackedVector3Array([source]), Vector2.RIGHT, 0.1, "body")
		var pool = owner_node.get_node("CutVoxelBurst")
		pool.set_process(false)
		pools.append(pool)
		for burst in range(64 if owner_index == 4 else (20 if owner_index < 3 else 0)):
			var state: Dictionary = pool.get_debug_state()
			if int(state.global_active_count) >= int(state.global_capacity):
				break
			pool.emit_from_cut(PackedVector3Array([source]), Vector2.RIGHT, 0.1, "body")
	var candidate = pools[4]
	var before: Dictionary = candidate.get_debug_state()
	var empty_next: bool = candidate.slots[candidate.next_slot].is_empty()
	var partial_owner: bool = int(before.active_count) > 0 and int(before.active_count) < int(before.capacity)
	for slot in candidate.slots:
		if not slot.is_empty():
			slot.age = float(slot.life) * 0.2
	if not candidate.slots[0].is_empty():
		candidate.slots[0].age = float(candidate.slots[0].life) * 0.9
	var neighbour_counts: Array[int] = []
	var neighbour_slots: Array = []
	for pool_index in range(4):
		neighbour_counts.append(int(pools[pool_index].active_count))
		neighbour_slots.append(pools[pool_index].slots.duplicate(true))
	candidate.emit_from_cut(PackedVector3Array([source]), Vector2.RIGHT, 0.1, "sever")
	var after: Dictionary = candidate.get_debug_state()
	var neighbours_unchanged := true
	for pool_index in range(4):
		neighbours_unchanged = neighbours_unchanged and int(pools[pool_index].active_count) == neighbour_counts[pool_index] and pools[pool_index].slots == neighbour_slots[pool_index]
	var reused_oldest: bool = not candidate.slots[0].is_empty() and is_zero_approx(float(candidate.slots[0].age))
	var valid := empty_next and partial_owner and int(before.global_active_count) == int(before.global_capacity) and int(after.global_active_count) == int(before.global_active_count) and int(after.active_count) == int(before.active_count) and int(after.last_burst_count) > 0 and int(after.emitted_sever) > int(before.emitted_sever) and reused_oldest and neighbours_unchanged
	for owner_node in owners:
		owner_node.free()
	return valid and VoxelDebris.CutVoxelBurst.global_active_count == 0


func verify_wide_follow_through() -> void:
	clear_targets()
	game.start_game()
	game.training = true
	game.speed = 48.0
	game.gear = 4
	game.camera.position = Vector3(0, 1.75, 0)
	game.camera.rotation = Vector3.ZERO
	game.camera.fov = 78.0
	var view_size: Vector2 = game.get_viewport().get_visible_rect().size
	var screen := Rect2(Vector2.ZERO, view_size)
	var departing_styles := 0
	var style_geometry: Array[Dictionary] = []
	var finite_poses := true
	for style in range(game.sword.get_light_slash_count()):
		pointer_button(true)
		pointer_button(false)
		var previous: Vector2 = game.camera.unproject_position(game.sword._drawn.to_global(game.sword.EDGE_TIP))
		var tip_travel := 0.0
		var leaves_screen := not screen.has_point(previous)
		for sample in range(28):
			game.sword._process(1.0 / 120.0)
			var current: Vector2 = game.camera.unproject_position(game.sword._drawn.to_global(game.sword.EDGE_TIP))
			finite_poses = finite_poses and current.is_finite() and game.sword._drawn.transform.is_finite()
			tip_travel += ((current - previous) / view_size).length()
			leaves_screen = leaves_screen or not screen.has_point(current)
			previous = current
		if leaves_screen:
			departing_styles += 1
		style_geometry.append({"style": style, "tip_normalized_travel": tip_travel, "tip_leaves_viewport": leaves_screen})
	# Travel magnitude remains a diagnostic, not an automated feel grade.
	# The old proposed 0.75/8-style threshold had no user-defined basis.
	expect(departing_styles > 0 and finite_poses, "authored follow-through can carry the physical blade out of the viewport while its transforms stay finite")
	print("WIDE SWING GEOMETRY (diagnostics only): offscreen_styles=", departing_styles, " per_style=", JSON.stringify(style_geometry))
	game.training = false
	game.start_game()


func verify_all_style_held_takeovers() -> void:
	# Wide follow-through may leave the blade outside the frame. Mode entry
	# must still adopt that actual pose rather than substitute a display pose.
	clear_targets()
	game.start_game()
	game.training = true
	game.speed = 48.0
	game.spawn_timer = 999.0
	game.camera.position = Vector3(0, 1.75, 0)
	game.camera.rotation = Vector3.ZERO
	game.camera.fov = 78.0
	var maximum_grip_jump := 0.0
	var maximum_tip_jump := 0.0
	var maximum_rotation_jump := 0.0
	var maximum_held_grip_error := 0.0
	var all_styles_adopted := true
	for style in range(game.sword.get_light_slash_count()):
		pointer_button(true)
		all_styles_adopted = all_styles_adopted and game.quick_slash_style == style
		for sample in range(7):
			step_input(1.0 / 60.0)
		var before_grip: Vector2 = game.sword.get_grip_screen_position()
		var before_tip: Vector2 = game.camera.unproject_position(game.sword._drawn.to_global(game.sword.EDGE_TIP))
		var before_rotation: Quaternion = game.sword._drawn.basis.get_rotation_quaternion()
		game._process(1.0 / 60.0)
		var after_tip: Vector2 = game.camera.unproject_position(game.sword._drawn.to_global(game.sword.EDGE_TIP))
		maximum_grip_jump = maxf(maximum_grip_jump, game.sword.get_grip_screen_position().distance_to(before_grip))
		maximum_tip_jump = maxf(maximum_tip_jump, after_tip.distance_to(before_tip))
		maximum_rotation_jump = maxf(maximum_rotation_jump, before_rotation.angle_to(game.sword._drawn.basis.get_rotation_quaternion()))
		all_styles_adopted = all_styles_adopted and game.slashing
		game.sword._process(1.0 / 60.0)
		maximum_held_grip_error = maxf(maximum_held_grip_error, game.sword.get_grip_screen_position().distance_to(game.slash_cursor))
		pointer_button(false)
		step_input(0.5)
	expect(all_styles_adopted and maximum_grip_jump < 0.1 and maximum_tip_jump < 0.1 and maximum_rotation_jump < 0.01 and maximum_held_grip_error < 0.1, "every wide light-slash style enters held mode from its real grip, blade tip and orientation and retains the precise grip on its next update")
	print("ALL-STYLE TAKEOVER GEOMETRY: grip_jump_px=", maximum_grip_jump, " tip_jump_px=", maximum_tip_jump, " rotation_jump_rad=", maximum_rotation_jump, " held_grip_error_px=", maximum_held_grip_error)
	game.training = false
	game.start_game()


func verify_runner_flow_and_audio() -> void:
	# RenderingServer's headless Dummy backend cannot read MultiMesh instance
	# transforms. Test actual Node3D travel and the material's distance input
	# here; production MultiMesh positions are recorded in the GPU review.
	clear_targets()
	game.start_game()
	game.spawn_timer = 999.0
	game.hit_stop = 0.0
	game.speed = 18.0
	game.gear = 1
	game.shift_down = false
	var slow_start: float = game.run_distance
	var road_start: float = game.road_segments[5].position.z
	game._process(0.1)
	var slow_distance: float = game.run_distance - slow_start
	var slow_audio: Dictionary = game.audio.get_runner_audio_debug_state()
	expect(is_equal_approx(slow_distance, 1.8) and is_equal_approx(game.road_segments[5].position.z - road_start, 1.8) and is_equal_approx(float(game.road_flow_material.get_shader_parameter("run_distance")), game.run_distance), "18-speed travel advances road geometry and procedural road material by the same real 1.8 metres")
	game.speed = 60.0
	game.gear = 4
	game.shift_down = true
	var fast_start: float = game.run_distance
	road_start = game.road_segments[5].position.z
	game._process(0.1)
	var fast_audio: Dictionary = game.audio.get_runner_audio_debug_state()
	expect(is_equal_approx(game.run_distance - fast_start, 6.0) and is_equal_approx(game.road_segments[5].position.z - road_start, 6.0) and is_equal_approx(float(game.road_flow_material.get_shader_parameter("run_distance")), game.run_distance), "60-speed travel moves physical road references and texture phase by 6 metres rather than only changing HUD speed")
	expect(float(fast_audio.wind_low_target) > float(slow_audio.wind_low_target) and float(fast_audio.wind_high_target) > float(slow_audio.wind_high_target) and is_equal_approx(float(fast_audio.distance) - float(slow_audio.distance), 6.0), "runner wind targets rise with effective speed and footfall distance follows actual world travel")
	game.shift_down = false
	game.speed = 48.0
	game.gear = 4
	pointer_button(true)
	game._enter_slash()
	var held_start: float = game.run_distance
	var held_phase: float = game.audio.get_runner_stride_phase()
	game._process(0.1)
	var held_audio: Dictionary = game.audio.get_runner_audio_debug_state()
	expect(is_equal_approx(game.run_distance - held_start, 47.0 * 0.022) and is_equal_approx(float(held_audio.effective_speed), 47.0 * 0.22) and float(held_audio.wind_high_target) < float(slow_audio.wind_high_target) and not is_equal_approx(game.audio.get_runner_stride_phase(), held_phase), "slow blade mode ties road and runner audio to slowed world distance while hand control uses real time")
	game.hit_stop = 0.2
	var frozen_distance: float = game.run_distance
	var frozen_road: float = game.road_segments[5].position.z
	var frozen_audio: Dictionary = game.audio.get_runner_audio_debug_state()
	game._process(0.05)
	var stopped_audio: Dictionary = game.audio.get_runner_audio_debug_state()
	expect(is_equal_approx(game.run_distance, frozen_distance) and is_equal_approx(game.road_segments[5].position.z, frozen_road) and is_equal_approx(float(stopped_audio.distance), float(frozen_audio.distance)) and is_equal_approx(float(stopped_audio.stride_phase), float(frozen_audio.stride_phase)) and is_zero_approx(float(stopped_audio.wind_low_target)), "hit-stop freezes road travel, texture phase and stride phase and silences effective runner wind")
	game._pause_game()
	game._process(0.2)
	var paused_audio: Dictionary = game.audio.get_runner_audio_debug_state()
	expect(is_equal_approx(game.run_distance, frozen_distance) and is_equal_approx(game.road_segments[5].position.z, frozen_road) and is_equal_approx(float(paused_audio.stride_phase), float(stopped_audio.stride_phase)) and not bool(paused_audio.active), "pause cannot keep scrolling the environment or advancing footfalls")
	game._start_cutting_lab()
	var lab_distance: float = game.run_distance
	var lab_road: float = game.road_segments[5].position.z
	var lab_audio: Dictionary = game.audio.get_runner_audio_debug_state()
	game._process(0.2)
	var after_lab_audio: Dictionary = game.audio.get_runner_audio_debug_state()
	expect(game.training and is_equal_approx(game.run_distance, lab_distance) and is_equal_approx(game.road_segments[5].position.z, lab_road) and is_equal_approx(float(after_lab_audio.stride_phase), float(lab_audio.stride_phase)) and not bool(after_lab_audio.active), "stationary cutting lab never fakes running motion or advances runner audio phase")
	clear_targets()
	game.training = false
	game.start_game()


func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.test_mode = true
	configure_normal_fixture_anatomy()
	game.start_game()
	expect(game.state == "playing" and game.health == 5, "start with five health slots")
	game.shift_down = true
	game._update_speed(10.0)
	expect(game.speed == 60.0 and game.gear == 4, "Shift caps at fourth gear")
	expect(game.gear_for_speed(12) == 1 and game.gear_for_speed(24) == 2 and game.gear_for_speed(36) == 3 and game.gear_for_speed(48) == 4, "four labeled gear boundaries")
	game.slashing = true
	game._update_speed(1.0)
	expect(game.speed < 60.0, "Shift plus long slash still drains speed")
	game._update_speed(10.0)
	expect(game.speed == 4.0 and not game.slashing and game.slash_lock, "minimum speed forces sheath and locks held input")
	game.slash_lock = false
	game.speed = 40.0
	game.shift_down = false
	game._update_speed(1.0)
	expect(game.speed < 40.0 and game.speed > 12.0, "releasing Shift decelerates gradually")
	var saved_speed: float = game.speed
	game._hurt()
	expect(game.health == 4 and game.speed == saved_speed, "damage removes health without changing speed")
	game._short_slash()
	expect(game.speed == saved_speed, "ordinary slash does not grant speed")
	game.guard_cooldown = 0.0
	game._begin_guard()
	game.guard_age = 0.075
	game.speed = 12.0
	expect(game._try_guard(), "active parry blocks an incoming attack")
	var perfect_gain: float = game.speed - 12.0
	var guard_speed: float = game.speed
	expect(game._try_guard() and game.speed == guard_speed, "same parry window blocks overlapping attacks without farming speed")
	game.guard_cooldown = 0.0
	game._begin_guard()
	game.guard_age = 0.27
	game.speed = 12.0
	game._try_guard()
	expect(perfect_gain > game.speed - 12.0, "more precise parry grants more speed")
	game.guard_remaining = 0.0
	game.guard_rewarded = false
	game.hit_stop = 0.0
	game.health = 5
	var enemy = game._spawn_enemy("normal", 0, -4.4)
	game._update_enemies(0.0, 1.0)
	expect(game.health == 5 and str(enemy.get_meta("action_state")) == "windup", "crossing engagement range starts a visible windup without instant damage")
	game._update_enemies(0.85, 1.0)
	expect(game.health == 5 and str(enemy.get_meta("action_state")) == "strike", "windup completes before the striking damage window")
	game._update_enemies(0.17, 1.0)
	expect(game.health == 4 and enemy.resolved, "miss in far-left lane damages fixed player")
	expect(is_equal_approx(enemy.position.z, -2.2) and absf(enemy.position.x) < 0.6, "melee damage phase physically lunges from its lane into player space")
	game._update_enemies(0.05, 1.0)
	expect(game.health == 4, "resolved contact does not repeatedly damage")
	clear_targets()
	game.health = 5
	enemy = game._spawn_enemy("normal", 3, -4.4)
	game._update_enemies(0.0, 1.0)
	game._update_enemies(0.85, 1.0)
	game.guard_remaining = 0.25
	game.guard_age = 0.075
	game.guard_rewarded = false
	game._update_enemies(0.17, 1.0)
	expect(str(enemy.get_meta("action_state")) == "stagger", "successful parry visibly interrupts enemy into recoil")
	game._update_enemies(0.55, 1.0)
	expect(game.health == 5 and enemy.resolved, "right-lane parry has no deferred duplicate damage")
	clear_targets()
	game.guard_remaining = 0.0
	game.health = 5
	enemy = game._spawn_enemy("tank", 0, -4.4)
	game._update_enemies(0.0, 1.0)
	for frame in range(46):
		game._update_enemies(0.05, 1.0)
	expect(game.health == 3 and enemy.attack_done == 2, "tank resolves two separately timed hits")
	clear_targets()
	game.health = 5
	game.speed = 48.0
	game.gear = 4
	game.hit_stop = 0.0
	game.slash_lock = false
	game.left_down = true
	game.left_time = 0.3
	game.slashing = true
	game.spawn_timer = 999.0
	game.elapsed = 0.0
	game.game_clock = 0.0
	enemy = game._spawn_enemy("normal", 1, -30.0)
	var start_z: float = enemy.position.z
	game._spawn_projectile(Vector3(0, 1.7, -20), "bolt")
	var projectile_z: float = game.projectiles[0].node.position.z
	var slow_shot_velocity: Vector3 = game.projectiles[0].velocity
	game._process(0.1)
	expect(is_equal_approx(game.elapsed, 0.022), "slow slash scales world clock to 22 percent")
	expect(is_equal_approx(game.speed, 47.0), "slow slash spends speed using actual elapsed time")
	expect(is_equal_approx(enemy.position.z-start_z,(game.speed+game.ENEMY_RUN_SPEED)*0.022) and is_equal_approx(game.projectiles[0].node.position.z-projectile_z,slow_shot_velocity.z*0.022), "enemies and faster physical projectiles share the same slow world delta")
	game._pause_game()
	var paused_elapsed: float = game.elapsed
	game._process(0.2)
	expect(game.elapsed == paused_elapsed and not game.left_down and not game.slashing and not game.shift_down, "pause freezes world and clears held inputs")
	game._resume_game()
	clear_targets()
	game.camera.rotation = Vector3.ZERO
	game.camera.fov = 76.0
	enemy = game._spawn_enemy("normal", 1, -9.0)
	enemy.position.x = 0.0
	var arm_start: Vector2 = game.camera.unproject_position(enemy.to_global(Vector3(0.6, 1.32, 0.0)))
	var arm_end: Vector2 = game.camera.unproject_position(enemy.to_global(Vector3(0.6, 1.65, 0.0)))
	if float(enemy._cell) < 0.075:
		arm_start = game.camera.unproject_position(enemy.to_global(enemy._part_pose(1) * Vector3(-0.63, 1.36, 0.20)))
		arm_end = game.camera.unproject_position(enemy.to_global(enemy._part_pose(1) * Vector3(-0.63, 1.60, 0.15)))
	var arm_result: Dictionary = enemy.cut_screen(game.camera, arm_start, arm_end, 1.0)
	expect(int(arm_result.removed) > 0 and not enemy.dead, "noncritical arm damage does not count as a kill")
	clear_targets()
	enemy = game._spawn_enemy("normal", 1, -9.0)
	enemy.position.x = 0.0
	var hand_result: Dictionary = cut_right_hand(enemy)
	expect(int(hand_result.removed) > 0 and not enemy.dead and not enemy.has_attack_limb() and not enemy._weapons[0].visible, "real hand cut disarms surviving enemy and removes attached weapon")
	game.health = 5
	game.guard_remaining = 0.0
	game._start_melee(enemy)
	game._update_enemies(0.85, 1.0)
	game._update_enemies(0.17, 1.0)
	expect(game.health == 5 and enemy.attack_done == 1 and enemy.resolved and not enemy._trail.visible, "disarmed melee attack completes without health damage or phantom trail")
	clear_targets()
	enemy = game._spawn_enemy("ranged", 1, -9.0)
	enemy.position.x = 0.0
	hand_result = cut_right_hand(enemy)
	expect(int(hand_result.removed) > 0 and not enemy.dead and not enemy.has_attack_limb(), "actual hand cut disables gun while ranged enemy stays alive")
	enemy.position.z = -26.0
	game._set_enemy_action(enemy, "ranged_charge", 0.65)
	game._update_enemies(0.70, 1.0)
	game._update_enemies(0.06, 1.0)
	expect(game.projectiles.is_empty(), "disarmed ranged firing release emits no projectile")
	clear_targets()
	enemy = game._spawn_enemy("tank", 1, -9.0)
	enemy.position.x = 0.0
	hand_result = cut_right_hand(enemy)
	expect(int(hand_result.removed) > 0 and not enemy.dead and not enemy.has_attack_limb(0) and enemy.has_attack_limb(1), "tank right-hand severing preserves only its left-hand second attack")
	clear_targets()
	enemy = game._spawn_enemy("boss", 0, -12.0)
	hand_result = cut_right_hand(enemy)
	expect(int(hand_result.removed) > 0 and not enemy.dead and enemy.get_ranged_origins().size() == 1, "boss severed hand removes only its own projectile origin")
	enemy.set_action_variant(1)
	enemy.set_meta("action_variant", 1)
	game._set_enemy_action(enemy, "boss_strike", 0.46)
	game._update_boss(enemy, 0.26)
	expect(game.projectiles.size() == 1, "one-handed boss dual-shot releases one real projectile without a phantom second shot")
	clear_targets()
	enemy = game._spawn_enemy("normal", 1, -9.0)
	enemy.position.x = 0.0
	var path_bounds: Rect2 = enemy.get_screen_bounds(game.camera)
	var path_aim: Vector2 = game.camera.unproject_position(enemy.get_aim_point())
	var left: Vector2 = Vector2(path_bounds.position.x - 30, path_aim.y)
	var right: Vector2 = Vector2(path_bounds.end.x + 30, path_aim.y)
	var high_y: float = path_bounds.position.y - 30
	var around: PackedVector2Array = PackedVector2Array([left, Vector2(left.x, high_y), Vector2(right.x, high_y), right])
	var around_result: Dictionary = enemy.cut_path(game.camera, around, 1.0)
	expect(int(around_result.removed) == 0, "curved mouse path does not cut across its endpoint chord")
	var return_result: Dictionary = enemy.cut_path(game.camera, PackedVector2Array([left, right, left]), 1.0)
	expect(int(return_result.removed) > 0 and enemy.dead, "back-and-forth stroke still cuts when endpoints coincide")
	clear_targets()
	for kind in ["normal", "tank", "ranged", "boss"]:
		enemy = game._spawn_enemy(kind, 1, -9.0)
		enemy.position.x = 0.0
		var aim: Vector2 = game.camera.unproject_position(enemy.get_aim_point())
		var bounds: Rect2 = enemy.get_screen_bounds(game.camera)
		var cut_start: Vector2 = Vector2(bounds.position.x - 20, aim.y)
		var cut_end: Vector2 = Vector2(bounds.end.x + 20, aim.y)
		var removed: int = 0
		var material_before: int = enemy.get_remaining_voxel_count()
		var maximum_usec: int = 0
		# A larger authored depth can require more real layers than the old
		# six-pass fixture. Bound work by the grid depth and require progress.
		for cut_index in range(enemy._dimensions.z + 1):
			var result: Dictionary = enemy.cut_screen(game.camera, cut_start, cut_end, 2.15)
			removed += int(result.removed)
			maximum_usec = maxi(maximum_usec, enemy.last_cut_usec)
			if enemy.dead or int(result.removed) == 0:
				break
		expect(removed > 0 and enemy.cut_count > 0, kind + " removes real voxel material")
		expect(enemy.dead, kind + " dies from actual core/structural severing")
		expect(enemy.get_remaining_voxel_count() == material_before - removed, kind + " retains all uncut material in re-cuttable fragments")
		var re_cut: int = 0
		var score_after_kill: int = game.score
		for piece in enemy.get_children():
			if not piece.get_meta("voxel_piece", false) or piece.is_queued_for_deletion():
				continue
			var piece_bounds: Rect2 = piece.get_screen_bounds(game.camera)
			var piece_y: float = piece_bounds.get_center().y
			var piece_result: Dictionary = enemy.cut_screen(game.camera, Vector2(piece_bounds.position.x - 4, piece_y), Vector2(piece_bounds.end.x + 4, piece_y), 2.15)
			re_cut += int(piece_result.removed)
			if re_cut > 0:
				break
		expect(re_cut > 0 and game.score == score_after_kill, kind + " fragments can be cut again without duplicate kill rewards")
		print("CUT PROFILE: ", kind, " max_us=", maximum_usec, " cuts=", enemy.cut_count)
		clear_targets()
		game.state = "playing"
	game.boss_spawned = false
	game.elapsed = 180.0
	game._update_spawning(0.0)
	expect(game.boss_spawned and is_instance_valid(game.boss_enemy), "fixed route reaches boss encounter")
	for frame in range(80):
		game._update_boss(game.boss_enemy, 0.05)
	expect(game.projectiles.size() > 0, "boss produces counterable projectile attack")
	var boss_key: InputEventKey = InputEventKey.new()
	boss_key.keycode = KEY_F3
	boss_key.pressed = true
	game._input(boss_key)
	game._input(boss_key)
	expect(game.enemies.size() == 1 and is_instance_valid(game.boss_enemy) and not game.boss_enemy.is_queued_for_deletion(), "repeated boss shortcut always leaves a live encounter")
	clear_targets()
	# Boss severing has already earned the win; a surviving strike cannot damage
	# the player during the short, re-cuttable debris showcase.
	game.state = "playing"
	game.elapsed = 0.0
	game.spawn_timer = 999.0
	game.hit_stop = 0.0
	game.guard_remaining = 0.0
	game.health = 1
	game.victory_timer = 0.001
	enemy = game._spawn_enemy("normal", 1, -2.2)
	game._set_enemy_action(enemy, "strike", 0.28)
	enemy.set_meta("action_time", 0.14)
	game._process(0.016)
	expect(game.state == "won" and game.health == 1, "boss victory showcase freezes surviving enemy strike before damage")
	game.state = "dead"
	game.victory_timer = 0.0
	game._process(0.016)
	expect(game.state == "dead", "expired victory timer cannot overwrite an existing death")
	game.state = "playing"
	game.victory_timer = -1.0
	clear_targets()
	game.slashing = true
	game.left_down = true
	game.shift_down = true
	game.health = 1
	game._hurt()
	expect(game.state == "dead" and not game.slashing and not game.left_down and not game.shift_down, "death ends combat and clears held inputs")
	game.start_game()
	expect(game.health == 5 and game.speed == 18.0 and game.enemies.is_empty() and not game.boss_spawned, "restart resets the complete encounter")
	var strafe: InputEventKey = InputEventKey.new()
	strafe.keycode = KEY_A
	strafe.pressed = true
	var before_strafe_x: float = game.camera.position.x
	game._input(strafe)
	expect(is_equal_approx(game.camera.position.x, before_strafe_x), "movement key cannot switch lanes or move the view sideways independently of its running gait")
	# Input-chain regressions: these go through the exact event handler used by mouse input.
	var mouse_down: InputEventMouseButton = InputEventMouseButton.new()
	mouse_down.button_index = MOUSE_BUTTON_LEFT
	mouse_down.pressed = true
	game.aim_angles = Vector2(0.25, 0.07)
	game.camera.fov = 80.0
	game._input(mouse_down)
	var serial_on_press: int = game.cut_serial
	expect(game.sword_time > 0.0 and serial_on_press > 0, "ordinary slash responds on mouse press")
	game._process(0.15)
	expect(game.slashing and not game.slash_lock, "base-speed held input enters blade mode without Shift preparation")
	expect(game.aim_angles.is_equal_approx(Vector2(0.25, 0.07)) and is_equal_approx(game.camera.fov, 80.0), "blade mode preserves entry view and FOV")
	for sample in range(40):
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.relative = Vector2(1, 0)
		game._input(motion)
	expect(game.pending_strokes.size() == 40, "sub-four-pixel motion is retained and long queues are not truncated")
	game._process(0.016)
	expect(game.cut_serial > serial_on_press and game.last_path.size() == 41, "slow mouse movement produces the actual sampled blade path")
	var return_origin: Vector2 = game.slash_cursor
	pointer_motion(Vector2(80, 0))
	pointer_motion(Vector2(-80, 0))
	game._process(0.016)
	expect(game.last_path.size() == 3 and game.last_path[0].distance_to(game.last_path[-1]) < 0.1 and game.last_path[1].distance_to(return_origin) > 80.0, "real parsed same-frame return gesture preserves both directions even when endpoints coincide")
	expect(game.last_blade_frames.size() >= 15, "same-frame return gesture retains all finite-blade sweep samples")
	var release_serial: int = game.cut_serial
	var release_motion: InputEventMouseMotion = InputEventMouseMotion.new()
	release_motion.relative = Vector2(-60, 10)
	game._input(release_motion)
	var mouse_up: InputEventMouseButton = InputEventMouseButton.new()
	mouse_up.button_index = MOUSE_BUTTON_LEFT
	mouse_up.pressed = false
	game._input(mouse_up)
	expect(game.cut_serial > release_serial and not game.slashing, "release flushes the final stroke before exiting blade mode")
	game.speed = 4.05
	game.slashing = true
	game.left_down = true
	game.slash_lock = false
	game.pending_strokes.append([Vector2(610, 350), Vector2(670, 350)])
	var exhaustion_serial: int = game.cut_serial
	game._process(0.02)
	expect(game.cut_serial > exhaustion_serial and not game.slashing and game.slash_lock, "exhaustion frame flushes its last stroke before sheathing")
	game._reset_input()
	game.speed = 30.0
	game.guard_cooldown = 0.0
	game._begin_guard()
	game._process(0.1)
	game._input(mouse_down)
	game._input(release_motion)
	game._process(0.5)
	game._begin_guard()
	expect(game.guard_remaining > 0.0 and not game.slashing, "parry cooldown uses actual time and remains responsive after slow mode")
	prepare_grip_input()
	var carrier = game._spawn_enemy("normal", 0, -9.0)
	carrier.position.x = 100.0
	# The actual contact point cuts a narrow line. Neither the rest of the
	# projected sword area nor the grip cursor becomes a second damaging wave.
	var size: Vector2 = game.get_viewport().get_visible_rect().size
	var contact: Vector2 = game.sword.active_cut_point_for_grip(game.slash_cursor, game.blade_direction, size)
	var blade_probe = screen_voxel(carrier, contact + Vector2(16, 0))
	var far_edge_probe = screen_voxel(carrier, contact + Vector2(-85, 0))
	var grip_probe = screen_voxel(carrier, game.slash_cursor + Vector2(16, 0))
	pointer_motion(Vector2(32.0 / 1.05, 0))
	game._process(0.016)
	game.sword._process(0.016)
	var projected_grip: Vector2 = game.sword.get_grip_screen_position()
	expect(projected_grip.distance_to(game.slash_cursor) < 1.0 and game.slash_cursor.distance_to(contact) > 100.0, "physical trailing-blade handle remains anchored to its actual grip cursor")
	expect(blade_probe.get_voxel_count() == 0 and game.last_path[0].distance_to(contact) > 100.0, "actual narrow blade contact removes a voxel never crossed by the grip cursor")
	expect(far_edge_probe.get_voxel_count() == 1, "projected blade area away from the contact line cannot erase a voxel")
	expect(grip_probe.get_voxel_count() == 1, "grip cursor passing through a voxel cannot cut it without blade contact")
	expect(game.blade_paths.size() == 1 and game.blade_paths[0] == game.last_cut_path, "only the actual cut line is submitted as a visible sword trail")
	game.sword.impact(1.6, true)
	game.sword._process(0.025)
	expect(game.sword.get_grip_screen_position().distance_to(game.slash_cursor) < 1.0, "strong contact feedback cannot pull the handle away from the grip cursor")
	var retained_axis: Vector2 = game.blade_direction
	game._process(0.4)
	game.sword._process(0.4)
	expect(game.sword.get_blade_screen_direction().dot(retained_axis) > 0.999 and game.sword.get_grip_screen_position().distance_to(game.slash_cursor) < 1.0, "stopped grip keeps its physical blade direction and position without recentering")
	clear_targets()
	prepare_precision_input(normal_precision_aims.arm)
	var precision_enemy = precision_target()
	var material_before: int = precision_enemy.get_remaining_voxel_count()
	pointer_motion(Vector2(5.0 / 1.05, 0))
	game._process(0.016)
	var material_after: int = precision_enemy.get_remaining_voxel_count()
	var skim_particles: Dictionary = precision_enemy.get_cut_particle_debug_state()
	expect(material_after < material_before and not precision_enemy.dead and float(material_after) / float(material_before) >= 0.90 and skim_particles.get("last_source_kind", "") == "body" and int(skim_particles.get("emitted_sever", 0)) == 0, "parsed arm-edge skim damages only the contacted limb, stays alive and never emits a sever burst")
	prepare_precision_input(normal_precision_aims.chest)
	precision_enemy = precision_target()
	material_before = precision_enemy.get_remaining_voxel_count()
	pointer_motion(Vector2(18.0 / 1.05, 0))
	game._process(0.016)
	material_after = precision_enemy.get_remaining_voxel_count()
	expect(material_after < material_before and not precision_enemy.dead and float(material_after) / float(material_before) >= 0.85, "parsed short armor stroke makes a thin wound instead of wiping half a torso")
	prepare_precision_input(normal_precision_aims.waist)
	precision_enemy = precision_target()
	material_before = precision_enemy.get_remaining_voxel_count()
	pointer_motion(Vector2(92.0 / 1.05, 0))
	game._process(0.016)
	material_after = precision_enemy.get_remaining_voxel_count()
	var large_chunks: int = 0
	var upper_chunks := 0
	var lower_limb_chunks := 0
	var lower_material_volume := 0.0
	var waist_y: float = normal_precision_aims.waist.y
	for piece in precision_enemy.get_children():
		# Preserve the original 100 * (0.1m)^3 physical minimum after changing
		# the normal's voxel resolution; 100 fine cells would be a tiny plate.
		if piece.get_meta("voxel_piece", false) and not piece.is_queued_for_deletion() and float(piece.get_voxel_count()) * pow(float(piece.cell_size), 3.0) >= 0.1 - 0.000001:
			large_chunks += 1
		if piece.get_meta("voxel_piece",false) and not piece.is_queued_for_deletion():
			var volume := float(piece.get_voxel_count())*pow(float(piece.cell_size),3.0)
			if piece.get_aim_point().y < waist_y:
				lower_material_volume += volume
				if volume >= 0.025-0.000001:
					lower_limb_chunks += 1
			elif volume >= 0.1-0.000001:
				upper_chunks += 1
	# Nine independently posed parts naturally separate the two legs, shins
	# and feet. Require a substantial torso and multiple substantial lower
	# limb chunks, plus the original lower-body aggregate volume, not crumbs.
	var large_anatomy_retained := large_chunks >= 2 if int(precision_enemy.PART_COUNT) <= 3 else (upper_chunks >= 1 and lower_limb_chunks >= 2 and lower_material_volume >= 0.1-0.000001)
	print("WAIST MATERIAL RETAINED: ",JSON.stringify({"before":material_before,"after":material_after,"dead":precision_enemy.dead,"upper_chunks":upper_chunks,"lower_limb_chunks":lower_limb_chunks,"lower_volume":lower_material_volume}))
	expect(precision_enemy.dead and material_after < material_before and float(material_after) / float(material_before) >= 0.65 and large_anatomy_retained, "aimed parsed waist cut severs the real connection while preserving substantial upper and independently posed lower chunks")
	game.training = false
	clear_targets()
	for exit_kind in ["release", "parry", "exhaustion"]:
		prepare_grip_input()
		var before_tiny: int = game.cut_serial
		pointer_motion(Vector2(1.0 / 1.05, 0))
		if exit_kind == "release":
			pointer_button(false)
		elif exit_kind == "parry":
			pointer_button(true, MOUSE_BUTTON_RIGHT)
			pointer_button(false, MOUSE_BUTTON_RIGHT)
		else:
			game.speed = 4.05
			game._process(0.02)
		expect(game.cut_serial > before_tiny and game.pending_strokes.is_empty(), "one-pixel parsed grip stroke is submitted before " + exit_kind)
	prepare_grip_input()
	game.hit_stop = 0.1
	var stopped_world: float = game.game_clock
	var stopped_speed: float = game.speed
	var stopped_serial: int = game.cut_serial
	pointer_motion(Vector2(20.0 / 1.05, 0))
	game._process(0.016)
	game.sword._process(0.016)
	expect(game.cut_serial == stopped_serial + 1 and game.pending_strokes.is_empty() and game.sword.get_grip_screen_position().distance_to(game.slash_cursor) < 1.0 and is_equal_approx(game.game_clock, stopped_world) and is_equal_approx(game.speed, stopped_speed - 0.16), "hit-stop freezes world time while real parsed blade input, grip and actual-time speed drain remain responsive")
	game._start_cutting_lab()
	var target_z: float = game.enemies[0].position.z
	game._process(1.0)
	expect(game.training and game.speed == 48.0 and game.enemies[0].position.z == target_z, "cutting lab provides stationary targets and practice speed")
	game.training = false
	game.start_game()
	game.practice = true
	game.shift_down = true
	for frame in range(8000):
		if game.state != "playing":
			break
		game._process(1.0 / 30.0)
		for target in game.enemies.duplicate():
			if target.dead or target.position.z < -12.5 or target.position.z > -4.8:
				continue
			var target_aim: Vector2 = game.camera.unproject_position(target.get_aim_point())
			var target_bounds: Rect2 = target.get_screen_bounds(game.camera)
			game._cut(Vector2(target_bounds.position.x - 16, target_aim.y), Vector2(target_bounds.end.x + 16, target_aim.y), false)
		if frame % 90 == 0:
			await process_frame
	expect(game.elapsed >= 180.0 and game.kills > 20 and game.state == "won", "full scripted route reaches and defeats boss through real slicing")
	verify_weapon_motion_contracts()
	verify_light_styles_and_hilt_direction()
	verify_cut_voxel_particles()
	verify_wide_follow_through()
	verify_all_style_held_takeovers()
	verify_runner_flow_and_audio()
	await verify_armored_light_contacts()
	game._pause_game()
	# The route above advances manually while native audio keeps real time.
	# Let its longest 0.7s event tail (including pitch variation) and wind
	# release finish in the tree before freeing their playback owners.
	game.audio.set_runner_motion(0.0, 0.0, false, 0.0)
	await create_timer(1.0).timeout
	var playing_voices := 0
	for voice in game.audio.get_children():
		if voice is AudioStreamPlayer and voice.playing:
			playing_voices += 1
	expect(playing_voices == 0, "runner wind release and final event tails finish on the real audio clock before their owners are freed")
	print("PROTOTYPE VERIFICATION: ", checks, " checks, ", failures, " failures")
	game.free()
	await create_timer(0.15).timeout
	quit(0 if failures == 0 else 1)
