extends Node3D
## World time is explicit: mouse, sword and HUD remain responsive during slow motion.

const EnemyScript = preload("res://scripts/voxel_enemy.gd")
const HudScript = preload("res://scripts/prototype_hud.gd")
const SwordScript = preload("res://scripts/katana_view.gd")
const AudioScript = preload("res://scripts/prototype_audio.gd")
const TouchScript = preload("res://scripts/touch_controls.gd")
const ProjectileScript = preload("res://scripts/projectile_view.gd")
const BlastScript = preload("res://scripts/voxel_blast.gd")
const RouteScript = preload("res://scripts/route_sections.gd")
const MAX_PROJECTILES := 24
const MAX_BLASTS := 12
const ENEMY_RUN_SPEED := 2.8
const PROJECTILE_SPEED_SCALE: float = 2.0 / 3.0
const REFLECTED_BLAST_RADII := {"bolt":0.90,"shock":1.15,"missile":1.45}
const MIN_SPEED: float = 4.0
const BASE_SPEED: float = 18.0
const MAX_SPEED: float = 60.0
const ROUTE_DURATION: float = 180.0
const ROAD_TILE_LENGTH: float = 10.0
const ROAD_TILES_AHEAD: int = 28
const ROAD_TILES_BEHIND: int = 2
const ROAD_TILE_COUNT: int = ROAD_TILES_AHEAD + ROAD_TILES_BEHIND
const ROAD_FIRST_TILE_Z: float = 6.0 + ROAD_TILES_BEHIND * ROAD_TILE_LENGTH
const ROAD_RECYCLE_Z: float = 32.0
const ROAD_LOOP_LENGTH: float = ROAD_TILE_COUNT * ROAD_TILE_LENGTH
const LONG_PRESS: float = 0.13
const SLOW_SCALE: float = 0.22
const LANES: Array[float] = [-3.0, -1.0, 1.0, 3.0]

@export var route_duration: float = ROUTE_DURATION

var state: String = "menu"
var speed: float = BASE_SPEED
var gear: int = 1
var health: int = 5
var score: int = 0
var kills: int = 0
var combo: int = 0
var elapsed: float = 0.0
var game_clock: float = 0.0
var practice: bool = false
var training: bool = false
var shift_down: bool = false
var left_down: bool = false
var left_time: float = 0.0
var slashing: bool = false
var slash_lock: bool = false
var guard_remaining: float = 0.0
var guard_age: float = 0.0
var guard_cooldown: float = 0.0
var guard_rewarded: bool = false
var guard_chain_hits: int = 0
var hit_stop: float = 0.0
var hurt_flash: float = 0.0
var shake: float = 0.0
var stroke_alpha: float = 0.0
var sword_time: float = 0.0
var aim_angles: Vector2 = Vector2.ZERO
var slash_view_rotation: Vector3 = Vector3.ZERO
var slash_view_position: Vector3 = Vector3.ZERO
var slash_view_fov: float = 78.0
var slash_view_locked: bool = false
var slash_cursor: Vector2 = Vector2.ZERO
var stroke_from: Vector2 = Vector2.ZERO
var stroke_to: Vector2 = Vector2.ZERO
var blade_path: PackedVector2Array = PackedVector2Array()
var pending_strokes: Array = []
var enemies: Array = []
var projectiles: Array = []
var blasts: Array = []
var road_segments: Array[Node3D] = []
var wave_index: int = 0
var spawn_timer: float = 2.8
var boss_spawned: bool = false
var boss_enemy: Node3D
var boss_timer: float = 2.5
var boss_pattern: int = 0
var message: String = ""
var message_timer: float = 0.0
var camera: Camera3D
var hud: Control
var sword: Node3D
var audio: Node
var enemy_root: Node3D
var real_clock: float = 0.0
var test_mode: bool = false
var victory_timer: float = -1.0
var cut_serial: int = 0
var last_path: PackedVector2Array = PackedVector2Array()
var last_cut_path: PackedVector2Array = PackedVector2Array()
var press_drag: Vector2 = Vector2.ZERO
var show_timing: bool = false
var combat_events: Array[Dictionary] = []
var combat_stats: Dictionary = {}
var impact_effects: Array = []
var last_impact_feedback: float = -10.0
var blade_direction: Vector2 = Vector2(0.38, -0.925).normalized()
var last_blade_frames: Array = []
var blade_paths: Array = []
var impact_strength: float = 0.0
var kill_pulse: float = 0.0
var parry_pulse: float = 0.0
var slash_energy: float = 0.0
var impact_direction: Vector2 = Vector2(1.0, -0.6).normalized()
var impact_point: Vector2 = Vector2.ZERO
var contact_serial: int = 0
var contact_kind: String = "hit"
var quick_slash_index: int = 0
var quick_slash_style: int = -1
var light_slash_history: Array[int] = []
var last_light_slash: Dictionary = {}
var touch_mode: bool = false
var touch_controls: Control
var run_distance: float = 0.0
var route_section := 0
var effective_runner_speed: float = 0.0
var road_flow_material: ShaderMaterial
var speed_flow_batches: Array[Dictionary] = []
var forge_panel_shader: Shader
var forge_instanced_material: ShaderMaterial
var forge_unit_box: BoxMesh
var forge_emitters: Array[Dictionary] = []
var forge_lights: Array[SpotLight3D] = []
var menu_showcase: Node3D
var menu_prepared := true
var start_when_menu_prepared := false


func _ready() -> void:
	test_mode = "--verify-prototype" in OS.get_cmdline_user_args()
	touch_mode = is_mobile_input_enabled()
	get_tree().quit_on_go_back = false
	if OS.has_feature("android") or OS.has_feature("ios"):
		Engine.max_fps = 60
	_build_world()
	_build_interface()
	ProjectileScript.prewarm()
	EnemyScript.prewarm_normal_model()
	EnemyScript.prewarm_models(["tank", "ranged", "boss", "drone", "missile_drone", "barrier", "beam"])
	_build_menu_showcase()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("SHIFT//CUT v0.9.5 foundry reforged ready | Godot ", Engine.get_version_info().string)
	if "--preview" in OS.get_cmdline_user_args():
		start_game()
		_spawn_enemy("normal", 1, -10.0)
		_spawn_enemy("tank", 2, -19.0)
		_spawn_enemy("ranged", 0, -32.0)


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if state == "playing":
			_pause_game()
		elif state == "paused":
			_resume_game()
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED] and state == "playing" and (touch_mode or not test_mode):
		_pause_game()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED] and is_instance_valid(touch_controls):
		touch_controls.release_all()
		_reset_input()


func is_mobile_input_enabled() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios") or "--touch-preview" in OS.get_cmdline_user_args()


func _input(event: InputEvent) -> void:
	if state == "menu" and not menu_prepared:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER,KEY_KP_ENTER]:
			start_when_menu_prepared = true
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			start_when_menu_prepared = true
		return
	if is_instance_valid(touch_controls) and touch_controls.handle_event(event):
		get_viewport().set_input_as_handled()
		return
	# Android native touch owns its gesture. Ignore the duplicate mouse event.
	if touch_mode and event is InputEventMouse and event.device == -1:
		return
	if event is InputEventKey:
		if event.keycode == KEY_SHIFT:
			shift_down = event.pressed
		if not event.pressed or event.echo:
			return
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				if training:
					training = false
					practice = false
					start_game()
				elif state == "paused":
					_resume_game()
				elif state != "playing":
					start_game()
			KEY_ESCAPE:
				if state == "playing":
					_pause_game()
				elif state == "paused":
					_resume_game()
			KEY_R:
				if state == "dead" or state == "won":
					start_game()
			KEY_F2:
				practice = not practice
				if state != "playing":
					start_game()
				_notice("练习模式：生命保留至少一格" if practice else "标准模式：五格生命", 3.0)
			KEY_F3:
				if state == "playing":
					training = false
					for enemy in enemies:
						enemy.queue_free()
					enemies.clear()
					_clear_projectiles()
					boss_spawned = false
					boss_enemy = null
					elapsed = ROUTE_DURATION
					_spawn_boss()
			KEY_F4:
				_start_cutting_lab()
			KEY_F5:
				show_timing = not show_timing
	if event is InputEventMouseMotion and state == "playing":
		var movement: Vector2 = event.relative
		if left_down and not slashing and not slash_lock:
			press_drag += movement
			if press_drag.length() < 4.0:
				return
			if not _enter_slash():
				return
			movement = press_drag
			press_drag = Vector2.ZERO
		if slashing:
			var previous: Vector2 = slash_cursor
			slash_cursor += movement * 1.05
			var viewport_size: Vector2 = get_viewport().get_visible_rect().size
			slash_cursor = slash_cursor.clamp(Vector2(2, 2), viewport_size - Vector2(2, 2))
			if previous.distance_squared_to(slash_cursor) > 0.001:
				pending_strokes.append([previous, slash_cursor])
		else:
			aim_angles.x = clampf(aim_angles.x - event.relative.x * 0.0016, -0.36, 0.36)
			aim_angles.y = clampf(aim_angles.y - event.relative.y * 0.0016, -0.20, 0.20)
	if event is InputEventMouseButton:
		if state != "playing":
			if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				if state == "paused":
					_resume_game()
				else:
					start_game()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if left_down:
					return
				guard_remaining = 0.0
				left_down = true
				left_time = 0.0
				press_drag = Vector2.ZERO
				_short_slash()
			else:
				if slashing:
					_consume_strokes()
					sword_time = 0.0
					sword.set_pose("sheathed")
				left_down = false
				slashing = false
				slash_lock = false
				pending_strokes.clear()
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_begin_guard()


func mobile_begin_blade() -> void:
	guard_remaining = 0.0
	left_down = true
	left_time = LONG_PRESS
	slash_lock = false
	press_drag = Vector2.ZERO
	_enter_slash()


func mobile_end_blade() -> void:
	if slashing:
		_consume_strokes()
		sword_time = 0.0
		sword.set_pose("sheathed")
	left_down = false
	left_time = 0.0
	slashing = false
	slash_lock = false
	pending_strokes.clear()


func mobile_drag_blade(movement: Vector2) -> void:
	var previous: Vector2 = slash_cursor
	slash_cursor = (slash_cursor + movement * 1.05).clamp(Vector2(2, 2), get_viewport().get_visible_rect().size - Vector2(2, 2))
	if previous.distance_squared_to(slash_cursor) > 0.001:
		pending_strokes.append([previous, slash_cursor])


func mobile_look_drag(movement: Vector2) -> void:
	aim_angles.x = clampf(aim_angles.x - movement.x * 0.0016, -0.36, 0.36)
	aim_angles.y = clampf(aim_angles.y - movement.y * 0.0016, -0.20, 0.20)


func start_game() -> void:
	start_when_menu_prepared = false
	if is_instance_valid(menu_showcase):
		menu_showcase.visible = false
		menu_showcase.queue_free()
		menu_showcase = null
	if is_instance_valid(touch_controls):
		touch_controls.release_all()
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	enemies.clear()
	_clear_projectiles()
	_clear_blasts()
	state = "playing"
	combat_events.clear()
	combat_stats = {"parries": 0, "perfects": 0, "hits_taken": 0, "projectiles_cut": 0, "windups": 0, "impacts": 0, "kills": 0, "slash_time": 0.0}
	speed = BASE_SPEED
	gear = 1
	health = 5
	score = 0
	kills = 0
	combo = 0
	elapsed = 0.0
	game_clock = 0.0
	wave_index = 0
	spawn_timer = 2.8
	boss_spawned = false
	boss_enemy = null
	boss_timer = 2.5
	boss_pattern = 0
	left_down = false
	left_time = 0.0
	slashing = false
	slash_lock = false
	shift_down = false
	guard_remaining = 0.0
	guard_cooldown = 0.0
	guard_rewarded = false
	guard_chain_hits = 0
	victory_timer = -1.0
	last_impact_feedback = -10.0
	impact_strength = 0.0
	contact_serial = 0
	contact_kind = "hit"
	impact_point = Vector2.ZERO
	kill_pulse = 0.0
	parry_pulse = 0.0
	slash_energy = 0.0
	last_blade_frames.clear()
	last_cut_path.clear()
	blade_paths.clear()
	blade_direction = Vector2(0.38, -0.925).normalized()
	quick_slash_index = 0
	run_distance = 0.0
	route_section = 0
	effective_runner_speed = 0.0
	for road_index in range(road_segments.size()):
		road_segments[road_index].position.z = ROAD_FIRST_TILE_Z - float(road_index) * ROAD_TILE_LENGTH
		_set_route_section(road_segments[road_index],0)
	_update_speed_flow()
	quick_slash_style = -1
	light_slash_history.clear()
	last_light_slash.clear()
	for effect in impact_effects:
		if is_instance_valid(effect.node):
			effect.node.queue_free()
	impact_effects.clear()
	hit_stop = 0.0
	hurt_flash = 0.0
	shake = 0.0
	aim_angles = Vector2.ZERO
	slash_view_locked = false
	pending_strokes.clear()
	press_drag = Vector2.ZERO
	blade_path.clear()
	stroke_alpha = 0.0
	slash_cursor = get_viewport().get_visible_rect().size * 0.5
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if touch_mode else Input.MOUSE_MODE_CAPTURED
	audio.play_event("start")
	_notice("斩断发光核心或颈腰连接 · 任意一道漏敌都会受伤", 6.0)
	_record_combat("start")


func _build_menu_showcase() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("android") or OS.has_feature("ios"):
		return
	menu_prepared = false
	# The menu portrait renders the same meshes and shaders used in combat.
	# The dark stage also covers the other asset variants while the renderer
	# uploads / compiles them, before the first timed enemy appears.
	menu_showcase = Node3D.new()
	menu_showcase.name = "MenuShowcase"
	add_child(menu_showcase)
	var back := _box(menu_showcase,Vector3(11,6,0.2),Vector3(0,3,-9),_material(Color("14212b"),true))
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var models: Array[Node3D] = []
	for kind in ["normal","tank","ranged","boss","drone","missile_drone","barrier","beam","normal"]:
		var actor = EnemyScript.new()
		menu_showcase.add_child(actor)
		actor.configure(kind,1)
		actor.position = Vector3(0,-0.055,-130.0 if models.size() == 8 else -14.0)
		actor.set_meta("simulation_scale",0.0)
		actor.set_meta("flythrough_enabled",false)
		actor.set_meta("root_motion_velocity",Vector3.ZERO)
		actor.set_meta("aim_target",camera.global_position)
		actor.set_action("recover",1.0)
		models.append(actor)
	# Draw every authored obstacle variant behind the portrait before timed
	# play. Their actual voxel meshes use the same combat material path.
	for kind in ["barrier","beam"]:
		for variant in [1,2]:
			var actor = EnemyScript.new()
			menu_showcase.add_child(actor)
			actor.configure(kind,1,variant)
			actor.position = Vector3(0,-0.055,-14.0)
			actor.set_meta("simulation_scale",0.0)
			actor.set_meta("flythrough_enabled",false)
			actor.set_action("recover",1.0)
	var portrait = EnemyScript.new()
	menu_showcase.add_child(portrait)
	portrait.configure("normal",1)
	portrait.position = Vector3(0,-0.055,-6.5)
	portrait.set_meta("simulation_scale",0.0)
	portrait.set_action("recover",1.0)
	# Warm the actual cut-particle variant from a real, noncritical material
	# cut on a hidden portrait copy. No gameplay actor or score is involved.
	var cut_point: Vector3 = models[0].to_global(models[0]._part_pose(1)*Vector3(-0.70,1.475,0.20))
	var screen := camera.unproject_position(cut_point)
	models[0].cut_screen(camera,screen-Vector2(4,0),screen+Vector2(4,0),0.4)
	for kind in ["bolt","missile","shock"]:
		var shot = ProjectileScript.new()
		menu_showcase.add_child(shot)
		shot.position = Vector3(0,1.65,-15)
		shot.configure(kind)
		shot.advance(0.01,Vector3.BACK)
	var burst = BlastScript.new()
	menu_showcase.add_child(burst)
	burst.position = Vector3(0,1.5,-15)
	burst.configure(0.65,0.0)
	burst.advance(0.06)
	_finish_menu_preparation()


func _finish_menu_preparation() -> void:
	await RenderingServer.frame_post_draw
	menu_prepared = true
	if start_when_menu_prepared and state == "menu":
		start_game()


func _start_cutting_lab() -> void:
	start_game()
	training = true
	practice = true
	speed = 48.0
	gear = 4
	spawn_timer = 999.0
	_spawn_enemy("normal", 0, -9.0)
	_spawn_enemy("tank", 2, -12.0)
	_spawn_enemy("boss", 0, -22.0)
	_notice("切割实验场 · 静止目标 / 持续切碎残骸 · F4 重置 · Enter 返回挑战", 999.0)


func _pause_game() -> void:
	if slashing:
		_consume_strokes()
	state = "paused"
	_reset_input()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _resume_game() -> void:
	state = "playing"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if touch_mode else Input.MOUSE_MODE_CAPTURED


func _reset_input() -> void:
	if is_instance_valid(touch_controls):
		touch_controls.release_all()
	left_down = false
	left_time = 0.0
	slash_lock = false
	shift_down = false
	slashing = false
	slash_view_locked = false
	guard_remaining = 0.0
	pending_strokes.clear()
	sword.set_pose("sheathed")


func _process(delta: float) -> void:
	real_clock += delta
	impact_strength = move_toward(impact_strength, 0.0, delta * 7.5)
	kill_pulse = move_toward(kill_pulse, 0.0, delta * 4.8)
	parry_pulse = move_toward(parry_pulse, 0.0, delta * 5.5)
	slash_energy = move_toward(slash_energy, 0.0, delta * 3.5)
	stroke_alpha = maxf(0.0, stroke_alpha - delta * 5.5)
	hurt_flash = maxf(0.0, hurt_flash - delta * 2.8)
	shake = move_toward(shake, 0.0, delta * 2.0)
	sword_time = maxf(0.0, sword_time - delta)
	message_timer = maxf(0.0, message_timer - delta)
	if state == "playing":
		if left_down:
			left_time += delta
			if left_time >= LONG_PRESS and not slashing and not slash_lock:
				_enter_slash()
		var stopped: bool = hit_stop > 0.0
		hit_stop = maxf(0.0, hit_stop - delta)
		_update_speed(delta)
		if training:
			speed = 48.0
			gear = 4
		var world_scale: float = 0.0 if stopped else (SLOW_SCALE if slashing else 1.0)
		var sim_dt: float = delta * world_scale
		effective_runner_speed = 0.0 if training else speed * world_scale
		audio.set_runner_motion(speed, sim_dt, not training, world_scale)
		if not training:
			run_distance += speed * sim_dt
		if slashing:
			combat_stats["slash_time"] = float(combat_stats.get("slash_time", 0.0)) + delta
		game_clock += sim_dt
		if not training:
			elapsed += sim_dt
		guard_cooldown = maxf(0.0, guard_cooldown - delta)
		if guard_remaining > 0.0:
			guard_remaining = maxf(0.0, guard_remaining - sim_dt)
			guard_age += sim_dt
		_update_camera(delta)
		_update_impact_effects(sim_dt, 0.0 if stopped else delta)
		_update_blasts(sim_dt)
		if not training:
			_update_road(sim_dt)
		if slashing:
			_consume_strokes()
		if not training:
			_update_spawning(sim_dt)
			_update_enemies(sim_dt, world_scale)
			_update_projectiles(sim_dt)
		else:
			for enemy in enemies:
				if is_instance_valid(enemy):
					enemy.set_meta("simulation_scale", world_scale)
					enemy.set_meta("flythrough_enabled", false)
					enemy.set_meta("root_motion_velocity", Vector3.ZERO)
		if victory_timer >= 0.0 and state == "playing":
			victory_timer -= delta
			if victory_timer <= 0.0:
				_finish(true)
		if guard_remaining > 0.0:
			sword.set_pose("parry", guard_age / 0.30)
		elif slashing:
			sword.set_pose("held", 0.0, slash_cursor / get_viewport().get_visible_rect().size - Vector2(0.5, 0.5))
		elif sword_time <= 0.0 and (not left_down or slash_lock):
			sword.set_pose("sheathed")
		sword.set_voxel_fx_simulation(stopped or hit_stop > 0.0,world_scale)
	else:
		sword.set_voxel_fx_simulation(true,0.0)
		effective_runner_speed = 0.0
		audio.set_runner_motion(speed, 0.0, false, 0.0)
		for enemy in enemies:
			if is_instance_valid(enemy):
				enemy.set_meta("simulation_scale", 0.0)
	_update_hud()


func _update_speed(real_dt: float) -> void:
	var previous_gear: int = gear
	if slashing:
		speed -= (10.0 - (2.0 if shift_down else 0.0)) * real_dt
		if speed <= MIN_SPEED:
			_consume_strokes()
			speed = MIN_SPEED
			slashing = false
			slash_lock = true
			sword.set_pose("sheathed")
			pending_strokes.clear()
			_notice("速度耗尽 · 已收刀", 1.8)
	elif shift_down:
		speed += 11.0 * real_dt
	else:
		speed = move_toward(speed, BASE_SPEED, (5.0 if speed < BASE_SPEED else 2.8) * real_dt)
	speed = clampf(speed, MIN_SPEED, MAX_SPEED)
	gear = gear_for_speed(speed)
	if previous_gear != gear:
		audio.play_event("gear", float(gear) / 4.0)


func gear_for_speed(value: float) -> int:
	if value < 24.0:
		return 1
	return clampi(2 + int((value - 24.0) / 12.0), 2, 4)


func _update_camera(delta: float) -> void:
	# Preserve the actual entry view and projection: no recenter, bob or FOV tug in blade mode.
	if slashing:
		if not slash_view_locked:
			slash_view_rotation = camera.rotation
			slash_view_position = camera.position
			slash_view_fov = camera.fov
			slash_view_locked = true
		camera.rotation = slash_view_rotation
		camera.position = slash_view_position
		camera.fov = slash_view_fov
		return
	slash_view_locked = false
	var rush: float = clampf((speed - BASE_SPEED) / (MAX_SPEED - BASE_SPEED), 0.0, 1.0)
	var stride: float = audio.get_runner_gait_phase() * TAU
	var body: float = 0.0 if training else lerpf(0.014, 0.027, rush)
	camera.rotation = Vector3(aim_angles.y, aim_angles.x, sin(real_clock * 37.0) * shake * 0.015 + sin(stride * 0.5) * body * 0.10)
	camera.position = Vector3(sin(stride * 0.5) * body * 0.32, 1.75 + cos(stride) * body, 0.0)
	camera.fov = lerpf(camera.fov, 78.0 + pow(rush, 0.7) * 12.0, 1.0 - exp(-delta * 5.5))


func _consume_strokes() -> void:
	if pending_strokes.is_empty():
		return
	var points: PackedVector2Array = PackedVector2Array([pending_strokes[0][0]])
	var distance: float = 0.0
	for segment in pending_strokes:
		distance += Vector2(segment[0]).distance_to(segment[1])
		points.append(segment[1])
	if distance < 0.0001:
		return
	pending_strokes.clear()
	# One contact on the real cutting edge traces a thin kerf. Sweeping the
	# entire projected sword area erased a whole torso from a tiny wrist turn.
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	var frames: Array = [sword.blade_segment_for_grip(points[0], blade_direction, view_size)]
	var cut_points: PackedVector2Array = PackedVector2Array([sword.active_cut_point_for_grip(points[0], blade_direction, view_size)])
	for index in range(1, points.size()):
		var motion: Vector2 = points[index] - points[index - 1]
		var travel: float = motion.length()
		if travel < 0.0001:
			continue
		var before: Vector2 = blade_direction
		var after: Vector2 = sword.resolve_blade_axis(before, motion)
		var turn: float = wrapf(after.angle() - before.angle(), -PI, PI)
		var samples: int = maxi(1, maxi(int(ceil(travel / 8.0)), int(ceil(absf(turn) / 0.08))))
		for sample in range(1, samples + 1):
			var fraction: float = float(sample) / float(samples)
			var grip: Vector2 = points[index - 1].lerp(points[index], fraction)
			var axis: Vector2 = sword.resolve_blade_axis(before, motion * fraction)
			frames.append(sword.blade_segment_for_grip(grip, axis, view_size))
			cut_points.append(sword.active_cut_point_for_grip(grip, axis, view_size))
		blade_direction = after
		impact_direction = motion / travel
	last_blade_frames = frames
	sword.set_grip_motion(points[-1], blade_direction, distance, view_size)
	slash_energy = maxf(slash_energy, clampf(distance / 70.0, 0.15, 1.0))
	_cut_path(cut_points, true)
	last_path = points


func _cut_projectile(index: int) -> void:
	var point: Vector3 = projectiles[index].node.global_position
	_detonate_projectile(index, point)
	_feedback_contact(point, 0.95, "blast")
	score += 30 * gear
	combat_stats["projectiles_cut"] = int(combat_stats.get("projectiles_cut", 0)) + 1
	_record_combat("projectile_cut")
	hit_stop = maxf(hit_stop, 0.045)
	shake = maxf(shake, 0.7)
	sword.impact(1.1)


func _enter_slash() -> bool:
	if speed < MIN_SPEED + 0.8 and not training:
		slash_lock = true
		_notice("速度耗尽 · 松开左键恢复后再斩", 1.0)
		return false
	slash_view_rotation = camera.rotation
	slash_view_position = camera.position
	slash_view_fov = camera.fov
	slash_view_locked = true
	slashing = true
	var size: Vector2 = get_viewport().get_visible_rect().size
	if not blade_direction.is_finite() or blade_direction.length_squared() < 0.001:
		blade_direction = Vector2(0.38, -0.925).normalized()
	# Hand control takes over the physical sword already on screen. Moving
	# it back to a synthetic centre pose would teleport the wrist and blade.
	var takeover: Dictionary = sword.adopt_current_held_pose(size)
	slash_cursor = takeover.grip
	blade_direction = takeover.axis
	sword.set_pose("held", 0.0, slash_cursor / size - Vector2(0.5, 0.5))
	sword.set_grip_motion(slash_cursor, blade_direction, 0.0, size)
	if not training:
		_notice("斩击模式 · 保持当前视角 · 自由划动切割", 1.0)
	return true


func _short_slash() -> void:
	slash_energy = 1.0
	quick_slash_style = quick_slash_index % sword.get_light_slash_count()
	var definition: Dictionary = sword.get_light_slash_definition(quick_slash_style)
	quick_slash_index += 1
	light_slash_history.append(quick_slash_style)
	if light_slash_history.size() > 64:
		light_slash_history.pop_front()
	var swing: Vector2 = definition.swing
	impact_direction = swing.normalized()
	sword_time = float(definition.duration) + 0.035
	sword.play_slash(swing, quick_slash_style)
	# Resolve on press with the contact pose already visible, including when
	# a hit-stop starts synchronously inside the cut callback. Each independent
	# press advances the style immediately; fast clicks are never discarded.
	var path: PackedVector2Array = sword.get_light_slash_cut_path(get_viewport().get_visible_rect().size)
	last_light_slash = {"index": quick_slash_style, "id": definition.id, "name": definition.name, "swing": swing, "path": path, "time": real_clock}
	combat_stats["light_slashes"] = int(combat_stats.get("light_slashes", 0)) + 1
	_record_combat("light_slash", null, {"style": quick_slash_style, "style_id": definition.id})
	_cut_path(path, false)


func _cut(from: Vector2, to: Vector2, continuous: bool) -> void:
	_cut_path(PackedVector2Array([from, to]), continuous)


func _cut_path(points: PackedVector2Array, continuous: bool) -> void:
	if points.size() < 2:
		return
	stroke_from = points[0]
	stroke_to = points[-1]
	blade_path = points
	blade_paths = [points]
	last_path = points
	last_cut_path = points
	cut_serial += 1
	stroke_alpha = 1.0
	var power: float = 0.75 + float(gear) * 0.35
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.position.z < -32.0 or enemy.position.z > -0.5:
			continue
		# Snapshot this input's visual style only. Last held segments consumed
		# on release / guard / speed exhaustion still get held-cut feedback.
		var had_held_fx: bool = enemy.has_meta("held_cut_fx")
		var previous_held_fx: Variant = enemy.get_meta("held_cut_fx",false)
		enemy.set_meta("held_cut_fx",continuous)
		var result: Dictionary = enemy.cut_path(camera, points, power)
		if had_held_fx:
			enemy.set_meta("held_cut_fx",previous_held_fx)
		else:
			enemy.remove_meta("held_cut_fx")
		if int(result.get("removed", 0)) > 0:
			enemy.set_meta("last_cut", real_clock)
			if enemy.dead:
				enemy.set_meta("dead_time", 0.0)
	for index in range(projectiles.size() - 1, -1, -1):
		if index >= projectiles.size():
			continue
		var projectile = projectiles[index]
		var node: Node3D = projectile.node
		if camera.is_position_behind(node.global_position) or node.position.z < -32.0:
			continue
		if node.intersects_path(camera, points):
			_cut_projectile(index)


func _feedback_contact(point: Vector3, strength: float, kind: String = "hit") -> void:
	contact_serial += 1
	contact_kind = kind
	impact_strength = maxf(impact_strength, clampf(strength, 0.0, 1.0))
	if not camera.is_position_behind(point):
		impact_point = camera.unproject_position(point)


func _begin_guard() -> void:
	if guard_cooldown > 0.0:
		_notice("振刀回收中 %.2fs" % guard_cooldown, 0.35)
		return
	if slashing:
		_consume_strokes()
	if left_down:
		slash_lock = true
	left_down = false
	slashing = false
	pending_strokes.clear()
	guard_remaining = 0.30
	guard_age = 0.0
	guard_cooldown = 0.40
	guard_rewarded = false
	guard_chain_hits = 0
	sword.set_pose("parry", 0.0)


func _try_guard(source: String = "incoming", enemy: Node3D = null) -> bool:
	if guard_remaining <= 0.0:
		return false
	guard_chain_hits += 1
	if guard_rewarded:
		_record_combat("parry_chain", enemy, {"source": source})
		return true
	guard_rewarded = true
	var precision: float = clampf(1.0 - absf(guard_age - 0.075) / 0.23, 0.0, 1.0)
	var gain: float = lerpf(5.0, 17.0, precision)
	speed = minf(MAX_SPEED, speed + gain)
	gear = gear_for_speed(speed)
	combo += 1
	score += int(100.0 * (1.0 + precision)) * gear
	shake = 0.85
	hit_stop = 0.065
	parry_pulse = 1.0
	combat_stats["parries"] = int(combat_stats.get("parries", 0)) + 1
	_record_combat("parry", enemy, {"source": source, "precision": precision})
	if sword.has_method("impact"):
		sword.impact(1.3, true)
	var contact: Vector3 = sword.get_contact_world_position()
	_feedback_contact(contact, 1.0, "parry")
	_spawn_impact(contact, "parry", 1.0)
	audio.play_event("parry_clash", 1.2)
	# A block makes one local contact, not a fictitious full-screen slash.
	stroke_alpha = 0.0
	blade_path.clear()
	blade_paths.clear()
	if precision > 0.83:
		combat_stats["perfects"] = int(combat_stats.get("perfects", 0)) + 1
		audio.play_event("perfect")
		_notice("完美振刀  +%d 速度" % int(gain), 1.4)
	else:
		audio.play_event("parry")
		_notice("振刀成功  +%d 速度" % int(gain), 1.1)
	return true


func _hurt(amount: int = 1, source: String = "contact", enemy: Node3D = null) -> void:
	if state != "playing":
		return
	health = maxi(1 if practice else 0, health - amount)
	combo = 0
	combat_stats["hits_taken"] = int(combat_stats.get("hits_taken", 0)) + amount
	_record_combat("hurt", enemy, {"source": source, "amount": amount})
	hurt_flash = 0.70
	shake = 0.75
	audio.play_event("hurt")
	_spawn_impact(Vector3(0, 1.5, -1.5), "hurt", 0.65)
	if health <= 0:
		_finish(false)


func _finish(won: bool) -> void:
	state = "won" if won else "dead"
	_record_combat(state)
	_reset_input()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	audio.play_event("win" if won else "lose")


func _notice(text: String, duration: float = 1.5) -> void:
	message = text
	message_timer = duration


func _update_spawning(sim_dt: float) -> void:
	if elapsed >= route_duration:
		if not boss_spawned:
			_spawn_boss()
		return
	spawn_timer -= sim_dt
	if spawn_timer > 0.0:
		return
	var sequence := ["normal","ranged","drone","normal","barrier","tank","missile_drone","ranged","beam","drone","normal","tank"]
	var kind: String = sequence[wave_index % sequence.size()]
	var lane: int = [1, 2, 0, 3, 2, 1, 0, 2][wave_index % 8]
	if kind == "tank":
		lane = 0 if wave_index % 2 == 0 else 2
	var z_distance: float = -maxf(40.0, speed * 2.0 + 12.0)
	_spawn_enemy(kind, lane, z_distance)
	wave_index += 1
	spawn_timer = 4.3 if elapsed < 40.0 else 3.5
	if elapsed > 75.0 and wave_index % 4 == 0 and kind not in ["barrier","beam"]:
		_spawn_enemy("normal", (lane + 2) % 4, z_distance - 14.0)


func _spawn_enemy(kind: String, lane: int, z_position: float) -> Node3D:
	var enemy = EnemyScript.new()
	enemy_root.add_child(enemy)
	enemy.configure(kind, lane)
	var x_position: float = LANES[clampi(lane, 0, 3)]
	if kind == "tank":
		x_position += 1.0
	elif kind in ["boss","barrier","beam"]:
		x_position = 0.0
	# The segmented deck's actual top is -0.055m. Grounded voxel soles and
	# obstacle bases meet that receiver instead of floating above its shadow.
	var floor_y := 0.0 if kind in ["drone","missile_drone"] else -0.055
	enemy.position = Vector3(x_position, floor_y, z_position)
	enemy.set_meta("lane_x", x_position)
	enemy.set_meta("runner_speed", speed)
	enemy.set_meta("flythrough_enabled", not training)
	enemy.set_meta("root_motion_velocity", Vector3.ZERO)
	enemy.severed.connect(_on_enemy_severed)
	enemy.damaged.connect(_on_enemy_damaged)
	enemies.append(enemy)
	_set_enemy_action(enemy, "run", 1.0)
	_record_combat("spawn", enemy)
	return enemy


func _spawn_boss() -> void:
	if boss_spawned:
		return
	boss_spawned = true
	boss_enemy = _spawn_enemy("boss", 0, -12.0)
	boss_timer = 3.2
	_set_enemy_action(boss_enemy, "recover", 1.4)
	_record_combat("boss_enter", boss_enemy)


func _set_enemy_action(enemy, action: String, duration: float) -> void:
	enemy.set_meta("action_state", action)
	enemy.set_meta("combat_state", action)
	enemy.set_meta("action_time", 0.0)
	enemy.set_meta("action_duration", maxf(duration, 0.001))
	enemy.set_meta("action_phase", 0.0)
	enemy.set_meta("combat_phase", 0.0)
	enemy.set_meta("action_start_z", enemy.position.z)
	enemy.set_meta("action_start_x", enemy.position.x)
	enemy.set_meta("impact_done", false)
	if enemy.has_method("set_action"):
		enemy.set_action(action, 0.0)
	if action == "windup" or action == "boss_windup":
		combat_stats["windups"] = int(combat_stats.get("windups", 0)) + 1
		_record_combat("windup", enemy, {"action": action})
	elif action == "strike" or action == "boss_strike":
		_record_combat("strike", enemy, {"action": action})
	elif action == "recover" or action == "stagger":
		_record_combat(action, enemy)


func _advance_enemy_action(enemy, sim_dt: float) -> float:
	var age: float = float(enemy.get_meta("action_time", 0.0)) + sim_dt
	var duration: float = float(enemy.get_meta("action_duration", 1.0))
	var phase: float = clampf(age / maxf(duration, 0.001), 0.0, 1.0)
	enemy.set_meta("action_time", age)
	enemy.set_meta("action_phase", phase)
	enemy.set_meta("combat_phase", phase)
	return phase


func _start_melee(enemy, second: bool = false) -> void:
	var duration: float = 0.82 if enemy.enemy_kind == "tank" else (0.56 if enemy.enemy_kind == "ranged" else 0.68)
	if second:
		duration = 0.50
	duration *= 1.0 - float(gear - 1) * 0.05
	enemy.set_meta("action_variant", 1 if second else 0)
	if enemy.has_method("set_action_variant"):
		enemy.set_action_variant(1 if second else 0)
	_set_enemy_action(enemy, "windup", duration)
	audio.play_event("windup", 1.2 if enemy.enemy_kind == "tank" else 0.8)


func _update_enemies(sim_dt: float, world_scale: float) -> void:
	for index in range(enemies.size() - 1, -1, -1):
		var enemy = enemies[index]
		if not is_instance_valid(enemy):
			enemies.remove_at(index)
			continue
		enemy.set_meta("simulation_scale", world_scale)
		enemy.set_meta("runner_speed", speed)
		enemy.set_meta("runner_distance",run_distance)
		enemy.set_meta("ground_run_speed",ENEMY_RUN_SPEED)
		enemy.set_meta("aim_target",camera.global_position)
		enemy.set_meta("flythrough_enabled", not training)
		var position_before: Vector3 = enemy.position
		if enemy.dead:
			var dead_time: float = float(enemy.get_meta("dead_time", 0.0)) + sim_dt
			enemy.set_meta("dead_time", dead_time)
			if not training:
				enemy.position.z += maxf(48.0, speed * 1.35) * sim_dt
				enemy.set_meta("root_motion_velocity", (enemy.position - position_before) / maxf(sim_dt, 0.00001))
			if (enemy.position.z > 12.0 or dead_time > 7.5) and not training:
				enemy.queue_free()
				enemies.remove_at(index)
			continue
		if victory_timer >= 0.0:
			enemy.set_meta("simulation_scale", 0.0)
			enemy.set_meta("root_motion_velocity", Vector3.ZERO)
			continue
		enemy.age += sim_dt
		if enemy.enemy_kind == "boss":
			enemy.set_meta("root_motion_velocity", Vector3.ZERO)
			_update_boss(enemy, sim_dt)
			continue
		if enemy.enemy_kind in ["barrier","beam"]:
			# Static route fixtures must be cut, rather than parried like attacks.
			enemy.position.z += speed * sim_dt
			enemy.set_action("run",0.0)
			if enemy.position.z >= -2.0 and not enemy.resolved:
				enemy.resolved = true
				_hurt(1,"obstacle",enemy)
				audio.play_event("hit",1.1)
				enemy.set_meta("impact_done",true)
			enemy.set_meta("root_motion_velocity",(enemy.position-position_before)/maxf(sim_dt,0.00001))
			if enemy.position.z > 5.0:
				enemy.queue_free()
				enemies.remove_at(index)
			continue
		var action: String = str(enemy.get_meta("action_state", "run"))
		var phase: float = _advance_enemy_action(enemy, sim_dt)
		match action:
			"run":
				enemy.position.z += (speed + ENEMY_RUN_SPEED) * sim_dt
				enemy.fire_timer -= sim_dt
				if not enemy.resolved and enemy.position.z >= -13.0:
					_start_melee(enemy)
				elif enemy.enemy_kind in ["ranged","drone","missile_drone"] and enemy.position.z >= -34.0 and enemy.fire_timer <= 0.0:
					_set_enemy_action(enemy, "ranged_charge", 0.85 if enemy.enemy_kind == "missile_drone" else 0.65)
					audio.play_event("ranged_charge", 0.8)
					_record_combat("ranged_charge", enemy)
			"windup":
				enemy.position.z = lerpf(float(enemy.get_meta("action_start_z", -13.0)), -7.2, smoothstep(0.0, 1.0, phase))
				if phase >= 1.0:
					_set_enemy_action(enemy, "strike", 0.28)
					audio.play_event("enemy_swing", 1.15 if enemy.enemy_kind == "tank" else 0.8)
			"strike":
				# The weapon reaches the player's space at the damage phase, from every lane.
				var lunge: float = smoothstep(0.0, 0.55, phase)
				enemy.position.z = lerpf(float(enemy.get_meta("action_start_z", -7.2)), -2.2, lunge)
				enemy.position.x = lerpf(float(enemy.get_meta("action_start_x", 0.0)), float(enemy.get_meta("lane_x", 0.0)) * 0.18, lunge)
				if phase >= 0.55 and not bool(enemy.get_meta("impact_done", false)):
					enemy.set_meta("impact_done", true)
					enemy.attack_done += 1
					var armed: bool = enemy.has_attack_limb()
					var blocked: bool = false
					if armed:
						combat_stats["impacts"] = int(combat_stats.get("impacts", 0)) + 1
						_record_combat("attack_impact", enemy, {"attack_number": enemy.attack_done})
						blocked = _try_guard("melee", enemy)
						if not blocked:
							_hurt(1, "melee", enemy)
					else:
						_record_combat("disarmed", enemy, {"attack_number": enemy.attack_done})
					enemy.resolved = enemy.attack_done >= (2 if enemy.enemy_kind == "tank" else 1)
					if blocked:
						_set_enemy_action(enemy, "stagger", 0.48)
						enemy.set_meta("root_motion_velocity", (enemy.position - position_before) / maxf(sim_dt, 0.00001))
						continue
				if phase >= 1.0:
					_set_enemy_action(enemy, "recover", 0.30 if enemy.enemy_kind == "tank" and not enemy.resolved else 0.42)
			"recover", "stagger":
				var retreat: float = -8.0 if action == "stagger" else -6.0
				enemy.position.z = lerpf(float(enemy.get_meta("action_start_z", -4.8)), retreat, smoothstep(0.0, 1.0, phase))
				enemy.position.x = lerpf(float(enemy.get_meta("action_start_x", 0.0)), float(enemy.get_meta("lane_x", 0.0)), smoothstep(0.0, 1.0, phase))
				if phase >= 1.0:
					if enemy.enemy_kind == "tank" and enemy.attack_done == 1:
						_start_melee(enemy, true)
					else:
						_set_enemy_action(enemy, "exit", 1.0)
			"ranged_charge":
				enemy.position.z += (speed * 0.25 + 2.0) * sim_dt
				if phase >= 1.0:
					_set_enemy_action(enemy, "ranged_fire", 0.22)
			"ranged_fire":
				if phase >= 0.25 and not bool(enemy.get_meta("impact_done", false)):
					enemy.set_meta("impact_done", true)
					if enemy.has_attack_limb():
						for origin in enemy.get_ranged_origins():
							_spawn_projectile(origin,"missile" if enemy.enemy_kind == "missile_drone" else "bolt",enemy)
						audio.play_event("ranged_fire", 1.0)
						_record_combat("ranged_fire", enemy)
					else:
						_record_combat("disarmed", enemy)
				if phase >= 1.0:
					enemy.fire_timer = 2.5
					_set_enemy_action(enemy, "run", 1.0)
			"exit":
				enemy.position.z += (speed * 0.9 + 6.0) * sim_dt
		var posed_action: String = str(enemy.get_meta("action_state", "run"))
		var posed_phase: float = float(enemy.get_meta("action_phase", 0.0))
		if posed_action == "run":
			posed_phase = fmod(enemy.age * 2.2, 1.0)
		elif posed_action == "exit":
			posed_action = "recover"
			posed_phase = 1.0
		enemy.set_action(posed_action, posed_phase)
		enemy.set_meta("root_motion_velocity", (enemy.position - position_before) / maxf(sim_dt, 0.00001))
		var warning: float = clampf(phase, 0.0, 1.0) if action == "windup" or action == "strike" else 0.0
		enemy.pulse_warning(warning)
		if enemy.position.z > 4.0:
			enemy.queue_free()
			enemies.remove_at(index)


func _update_boss(enemy, sim_dt: float) -> void:
	var action: String = str(enemy.get_meta("action_state", "recover"))
	var phase: float = _advance_enemy_action(enemy, sim_dt)
	enemy.set_action(action, phase)
	boss_timer = maxf(0.0, float(enemy.get_meta("action_duration", 1.0)) - float(enemy.get_meta("action_time", 0.0)))
	enemy.pulse_warning(phase if action == "boss_windup" else 0.0)
	match action:
		"run", "recover", "stagger":
			if phase >= 1.0:
				boss_pattern += 1
				var variant: int = boss_pattern % 3
				enemy.set_meta("action_variant", variant)
				if enemy.has_method("set_action_variant"):
					enemy.set_action_variant(variant)
				_set_enemy_action(enemy, "boss_windup", 1.05 - float(gear - 1) * 0.05)
				audio.play_event("boss_charge", 1.2)
		"boss_windup":
			if phase >= 1.0:
				_set_enemy_action(enemy, "boss_strike", 0.46)
				audio.play_event("enemy_swing", 1.5)
		"boss_strike":
			if phase >= 0.55 and not bool(enemy.get_meta("impact_done", false)):
				enemy.set_meta("impact_done", true)
				var variant: int = int(enemy.get_meta("action_variant", 0))
				if not enemy.has_attack_limb(variant):
					_record_combat("disarmed", enemy, {"variant": variant})
				elif variant == 1:
					for origin in enemy.get_ranged_origins():
						_spawn_projectile(origin, "missile",enemy)
					audio.play_event("ranged_fire", 1.2)
				else:
					_spawn_projectile(Vector3(0, 1.75, -9.5), "shock",enemy)
					_spawn_impact(Vector3(0, 0.2, -9.0), "launch", 0.8)
				if enemy.has_attack_limb(variant):
					_record_combat("attack_impact", enemy, {"variant": variant, "projectile": true})
			if phase >= 1.0:
				_set_enemy_action(enemy, "recover", 1.25 - float(gear - 1) * 0.12)


func _record_combat(event_name: String, enemy: Node3D = null, details: Dictionary = {}) -> void:
	var kind: String = str(enemy.get("enemy_kind")) if is_instance_valid(enemy) else "player"
	var entry: Dictionary = {
		"event": event_name, "type": event_name,
		"time": game_clock, "world_time": game_clock, "real_time": real_clock,
		"health": health, "speed": speed, "kind": kind, "source_kind": kind,
		"lane": int(enemy.get("lane_index")) if is_instance_valid(enemy) else -1,
		"enemy_id": enemy.get_instance_id() if is_instance_valid(enemy) else 0,
	}
	entry.merge(details, true)
	combat_events.append(entry)
	if combat_events.size() > 1600:
		combat_events.pop_front()


func _spawn_projectile(origin: Vector3, kind: String, source: Node3D = null) -> Node3D:
	if projectiles.size() >= MAX_PROJECTILES:
		return null
	var node = ProjectileScript.new()
	add_child(node)
	node.global_position = origin
	node.configure(kind)
	# Apply the requested reduction to the entire previous launch speed.
	# Once launched, the straight projectile keeps this velocity snapshot.
	var travel_speed := (speed + (38.0 if kind == "bolt" else 30.0)) * PROJECTILE_SPEED_SCALE
	var velocity := (Vector3(0.0, 1.65, -0.9) - origin).normalized() * travel_speed
	node.advance(0.00001, velocity)
	projectiles.append({"node":node, "velocity":velocity, "kind":kind, "source":source, "reflected":false, "age":0.0})
	_record_combat("projectile_spawn", source, {"projectile_kind":kind})
	return node


func _update_projectiles(sim_dt: float) -> void:
	if sim_dt <= 0.0:
		return
	for index in range(projectiles.size() - 1, -1, -1):
		# A real blast may sever the Boss and synchronously clear all other shots.
		if index >= projectiles.size():
			continue
		var projectile = projectiles[index]
		var node: Node3D = projectile.node
		var from := node.global_position
		var to: Vector3 = from + projectile.velocity * sim_dt
		projectile.age += sim_dt
		node.advance(sim_dt, projectile.velocity)
		if bool(projectile.reflected):
			var earliest := 2.0
			var hit_enemy: Node3D = null
			var hit_point := to
			for enemy in enemies:
				if not is_instance_valid(enemy) or enemy.dead:
					continue
				var hit: Dictionary = enemy.trace_projectile(from, to, node.collision_radius)
				if bool(hit.get("hit",false)) and float(hit.fraction) < earliest:
					earliest = float(hit.fraction)
					hit_enemy = enemy
					hit_point = hit.point
			if is_instance_valid(hit_enemy):
				_detonate_projectile(index, hit_point, hit_enemy)
				continue
		elif to.z >= -0.9:
			var crossing := clampf((-0.9-from.z)/maxf(to.z-from.z,0.00001),0.0,1.0)
			node.global_position = from.lerp(to,crossing)
			var source: Node3D = projectile.source if is_instance_valid(projectile.source) else null
			if _try_guard("projectile", source):
				var incoming: Vector3 = projectile.velocity
				projectile.velocity = -incoming * 1.4
				projectile.reflected = true
				node.set_reflected()
				node.advance(0.00001,projectile.velocity)
				combat_stats["projectiles_reflected"] = int(combat_stats.get("projectiles_reflected",0))+1
				_record_combat("projectile_reflected",source,{"projectile_kind":projectile.kind,"reverse_dot":incoming.normalized().dot(projectile.velocity.normalized())})
				continue
			_detonate_projectile(index,node.global_position)
			_hurt(1,"projectile",source)
			continue
		node.global_position = to
		if projectile.age > 9.0 or to.z < -140.0 or to.z > 8.0:
			_remove_projectile(index)


func _detonate_projectile(index: int, point: Vector3, target: Node3D = null) -> void:
	var projectile: Dictionary = projectiles[index]
	var kind: String = projectile.kind
	var reflected: bool = projectile.reflected
	# Remove before emitting a cut callback: Boss death clears the array.
	_remove_projectile(index)
	var strength := 1.35 if kind == "missile" else (1.0 if kind == "shock" else 0.75)
	_spawn_blast(point,strength,reflected)
	audio.play_event("explosion_reflected" if reflected else "explosion",strength)
	combat_stats["projectile_explosions"] = int(combat_stats.get("projectile_explosions",0))+1
	var radius: float = float(REFLECTED_BLAST_RADII.get(kind,0.90)) if reflected else 0.0
	var hit_count := 0
	var removed_total := 0
	var strongest_stop := hit_stop
	if reflected:
		# Both a real solid impact and a deliberate blade detonation keep the
		# returned payload's blast. No actor-distance or abstract HP damage.
		# Snapshot before callbacks, which may sever the Boss and clear shots.
		var victims: Array = []
		if is_instance_valid(target):
			victims.append(target)
		for enemy in enemies:
			if enemy != target:
				victims.append(enemy)
		for enemy in victims:
			if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or enemy.dead:
				continue
			var result: Dictionary = enemy.blast_at(point,radius)
			strongest_stop = maxf(strongest_stop,hit_stop)
			var removed := int(result.get("removed",0))
			if removed <= 0:
				continue
			hit_count += 1
			removed_total += removed
			_record_combat("reflected_hit",enemy,{"removed":removed,"killed":bool(result.get("killed",false)),"direct_hit":enemy == target,"blast_radius":radius,"projectile_kind":kind})
		if removed_total > 0:
			# The blast owns a stronger local impact. Continuous sword input and
			# held-mode camera locking still use the normal world-freeze path.
			hit_stop = maxf(strongest_stop,0.065 if kind == "missile" else 0.045)
			shake = maxf(shake,0.72)
			_feedback_contact(point,1.0,"blast")
	_record_combat("projectile_explosion",target,{"projectile_kind":kind,"reflected":reflected,"blast_radius":radius,"hit_target_count":hit_count,"removed_total":removed_total,"world_point":[point.x,point.y,point.z]})


func _remove_projectile(index: int) -> void:
	projectiles[index].node.queue_free()
	projectiles.remove_at(index)


func _clear_projectiles() -> void:
	for projectile in projectiles:
		if is_instance_valid(projectile.node):
			projectile.node.queue_free()
	projectiles.clear()


func _spawn_blast(point: Vector3, strength: float, reflected_impact: bool = false) -> Node3D:
	while blasts.size() >= MAX_BLASTS:
		var oldest: Node3D = blasts.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var blast = BlastScript.new()
	add_child(blast)
	blast.global_position = point
	blast.configure(strength,0.0 if training else speed,reflected_impact)
	blasts.append(blast)
	return blast


func _update_blasts(sim_dt: float) -> void:
	for index in range(blasts.size()-1,-1,-1):
		if not is_instance_valid(blasts[index]) or not blasts[index].advance(sim_dt):
			blasts.remove_at(index)


func _clear_blasts() -> void:
	for blast in blasts:
		if is_instance_valid(blast):
			blast.queue_free()
	blasts.clear()


func _spawn_impact(point: Vector3, kind: String, strength: float) -> void:
	if impact_effects.size() >= 18:
		impact_effects[0].node.queue_free()
		impact_effects.pop_front()
	var node: Node3D = Node3D.new()
	add_child(node)
	node.global_position = point
	var visual: MultiMeshInstance3D = MultiMeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(0.009, 0.009, 0.22)
	var particles: MultiMesh = MultiMesh.new()
	particles.transform_format = MultiMesh.TRANSFORM_3D
	particles.use_colors = true
	particles.mesh = mesh
	particles.instance_count = 20 if kind == "parry" else (18 if strength > 1.0 else 10)
	visual.multimesh = particles
	visual.material_override = _material(Color.WHITE, true)
	visual.material_override.vertex_color_use_as_albedo = true
	visual.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	node.add_child(visual)
	var velocities: Array[Vector3] = []
	var bases: Array[Basis] = []
	var colors: Array[Color] = []
	var tangent: Vector3 = (camera.global_basis * Vector3(impact_direction.x, -impact_direction.y, 0.0)).normalized()
	var across: Vector3 = tangent.cross(camera.global_basis.z).normalized()
	for index in range(particles.instance_count):
		# Metal throws a narrow, broken spray along the stroke. A radial star
		# obscured the blade and made every touch look like an explosion.
		var side: float = -1.0 if index % 4 == 0 else 1.0
		var velocity: Vector3 = (tangent * randf_range(0.55, 1.0) * side + across * randf_range(-0.38, 0.38) + camera.global_basis.z * randf_range(0.12, 0.65)).normalized() * randf_range(3.0, 7.0 + strength * 5.0)
		velocities.append(velocity)
		var basis: Basis = Basis.looking_at(velocity.normalized(), Vector3.UP)
		bases.append(basis)
		particles.set_instance_transform(index, Transform3D(basis, Vector3.ZERO))
		var color: Color = Color(1.0, 0.83, 0.44)
		if kind == "parry" or kind == "launch":
			color = Color(1.0, 0.72, 0.25) if index % 3 == 0 else Color(1.0, 0.97, 0.78)
		elif kind == "hurt":
			color = Color(1.0, 0.22, 0.10)
		colors.append(color)
		particles.set_instance_color(index, color)
	impact_effects.append({"node": node, "particles": particles, "velocities": velocities, "bases": bases, "colors": colors, "age": 0.0, "motion_age": 0.0, "life": 0.15 if kind == "parry" else 0.12})


func _update_impact_effects(sim_dt: float, visual_dt: float = -1.0) -> void:
	var fade_dt: float = sim_dt if visual_dt < 0.0 else visual_dt
	for index in range(impact_effects.size() - 1, -1, -1):
		var effect = impact_effects[index]
		effect.age += fade_dt
		effect.motion_age += sim_dt
		if effect.age >= effect.life:
			effect.node.queue_free()
			impact_effects.remove_at(index)
			continue
		var fraction: float = clampf(1.0 - effect.age / effect.life, 0.01, 1.0)
		for particle in range(effect.velocities.size()):
			var age: float = effect.motion_age
			var position: Vector3 = effect.velocities[particle] * age + Vector3.DOWN * age * age * 3.0
			var basis: Basis = effect.bases[particle].scaled(Vector3(fraction * 0.65, fraction * 0.65, fraction))
			effect.particles.set_instance_transform(particle, Transform3D(basis, position))
			var color: Color = effect.colors[particle]
			color.a = fraction * fraction
			effect.particles.set_instance_color(particle, color)


func _on_enemy_severed(enemy: Node3D, point: Vector3, removed_count: int) -> void:
	kills += 1
	combat_stats["kills"] = kills
	_record_combat("severed", enemy, {"removed": removed_count})
	combo += 1
	score += (150 + mini(removed_count, 100)) * gear
	hit_stop = 0.10 if enemy.enemy_kind == "boss" else (0.075 if enemy.enemy_kind == "tank" else 0.055)
	shake = 0.9
	kill_pulse = 1.0
	_feedback_contact(point, 1.0, "kill")
	if sword.has_method("impact"):
		sword.impact(1.6)
	audio.play_event("kill", 0.8 + float(gear) * 0.15)
	if show_timing:
		_notice("关键结构斩断  ×%d" % combo, 0.85)
	if enemy == boss_enemy:
		victory_timer = 2.4
		_clear_projectiles()
		_notice("核心已断 · 继续斩碎残骸", 2.4)


func _on_enemy_damaged(enemy: Node3D, point: Vector3, removed_count: int) -> void:
	if real_clock - last_impact_feedback < 0.075:
		return
	last_impact_feedback = real_clock
	shake = maxf(shake, 0.38)
	hit_stop = maxf(hit_stop, 0.025 if enemy.enemy_kind == "tank" else 0.018)
	_feedback_contact(point, 0.65)
	if sword.has_method("impact"):
		sword.impact(clampf(float(removed_count) / 45.0, 0.55, 1.0))
	audio.play_event("hit", 0.95)
	if not show_timing:
		return
	if bool(enemy.get("dead")):
		_notice("残骸切碎", 0.45)
	else:
		_notice("装甲剥离 · 切断发光核心连接", 0.6)


func _update_hud() -> void:
	if hud == null:
		return
	var targets: Array = []
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.dead or enemy.resolved or camera.is_position_behind(enemy.get_aim_point()):
			continue
		var time_left: float = maxf(0.0, (-enemy.position.z - 4.5) / (speed + ENEMY_RUN_SPEED))
		var kind: String = enemy.enemy_kind
		var action: String = str(enemy.get_meta("action_state", "run"))
		var action_time: float = float(enemy.get_meta("action_time", 0.0))
		var duration: float = float(enemy.get_meta("action_duration", 1.0))
		if action == "windup" or action == "boss_windup":
			time_left = maxf(0.0, duration - action_time) + (0.253 if kind == "boss" else 0.154)
		elif action == "strike" or action == "boss_strike":
			time_left = maxf(0.0, duration * 0.55 - action_time)
		elif kind == "boss":
			time_left = maxf(0.0, boss_timer) + 1.3
		var target_label: String = {"tank":"肉盾 · 二连击","ranged":"射手","boss":"核心守卫","drone":"巡飞机","missile_drone":"双弹舱重机","barrier":"斩断锁梁","beam":"切断斜撑"}.get(kind,"迎面攻击")
		if training:
			time_left = -1.0
			target_label = "切割靶"
		if not training and enemy.position.z < -32.0 and time_left > 2.5:
			continue
		targets.append({"screen": camera.unproject_position(enemy.get_aim_point()), "progress": clampf(1.0 - time_left / 1.8, 0.0, 1.0), "kind": kind, "can_cut": enemy.position.z >= -32.0, "label": target_label, "time_left": time_left, "action": action})
	for projectile in projectiles:
		var projectile_node: Node3D = projectile.node
		if bool(projectile.reflected) or projectile_node.position.z < -25.0 or camera.is_position_behind(projectile_node.global_position):
			continue
		var impact_time: float = maxf(0.0, (-projectile_node.position.z - 0.9) / maxf(projectile.velocity.z, 0.1))
		targets.append({"screen": camera.unproject_position(projectile_node.global_position), "progress": clampf(1.0 - impact_time / 1.2, 0.0, 1.0), "kind": "projectile", "can_cut": true, "label": "斩爆 / 反射", "time_left": impact_time})
	hud.set_snapshot({
		"state": state, "speed": speed, "gear": gear, "health": health,
		"score": score, "kills": kills, "combo": combo, "time": elapsed,
		"duration": route_duration, "slow": slashing, "parry": guard_remaining / 0.30,
		"cursor": slash_cursor if slashing else get_viewport().get_visible_rect().size * 0.5,
		"blade_from": stroke_from, "blade_to": stroke_to, "blade_alpha": stroke_alpha,
		"blade_path": blade_path,
		"blade_paths": blade_paths,
		"impact_strength": impact_strength, "kill_pulse": kill_pulse, "parry_pulse": parry_pulse,
		"contact_serial": contact_serial, "contact_kind": contact_kind,
		"slash_energy": slash_energy, "impact_direction": impact_direction, "impact_point": impact_point,
		"flash": hurt_flash, "message": message if message_timer > 0.0 else "",
		"boss": boss_spawned, "practice": practice,
		"training": training, "targets": targets, "cut_serial": cut_serial,
		"show_timing": show_timing,
		"touch_mode": touch_mode,
		"min_speed": MIN_SPEED, "max_speed": MAX_SPEED,
		"run_distance": run_distance, "effective_runner_speed": effective_runner_speed,
		"route_section": route_section,
		"section_name": ["ASSEMBLY LINE / 01","FURNACE HALL / 02","OPEN CAUSEWAY / 03","CORE GALLERY / 04"][route_section],
		"gear_limits": PackedFloat32Array([MIN_SPEED, 24.0, 36.0, 48.0, MAX_SPEED]),
	})


func _material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.65
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		material.metallic = 0.35
	return material


func _box(parent: Node3D, dimensions: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance


func _forge_material(tint: Color, roughness: float = 0.7, metal: float = 0.5) -> ShaderMaterial:
	if forge_panel_shader == null:
		forge_panel_shader = Shader.new()
		forge_panel_shader.code = """shader_type spatial;
uniform vec4 tint : source_color = vec4(0.2, 0.23, 0.28, 1.0);
uniform float base_roughness = 0.7;
uniform float metalness = 0.5;
uniform bool use_instance_material = false;
varying flat vec3 instance_surface;
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() {
	instance_surface = INSTANCE_CUSTOM.rgb;
}
void fragment() {
	vec3 surface_tint = use_instance_material ? COLOR.rgb : tint.rgb;
	float surface_roughness = use_instance_material ? instance_surface.x : base_roughness;
	float surface_metalness = use_instance_material ? instance_surface.y : metalness;
	if (use_instance_material && instance_surface.z > 0.5) {
		ALBEDO = surface_tint;
		ROUGHNESS = surface_roughness;
		METALLIC = surface_metalness;
	} else {
	vec2 uv = UV;
	float edge = min(min(uv.x, 1.0-uv.x), min(uv.y, 1.0-uv.y));
	float rim = 1.0 - smoothstep(0.006, 0.022, edge);
	float grain = hash21(floor(uv*320.0));
	float wear = smoothstep(0.68, 0.96, hash21(floor(uv*vec2(17.0, 31.0)))) * rim;
	vec3 paint = surface_tint * (0.97 + grain*0.035);
	paint = mix(paint, vec3(0.23, 0.26, 0.29), wear*0.45);
	paint = mix(paint, surface_tint*0.38, rim*0.45);
	ALBEDO = paint;
	ROUGHNESS = clamp(surface_roughness + (grain-0.5)*0.05, 0.3, 1.0);
	METALLIC = surface_metalness;
	}
}
"""
	var material := ShaderMaterial.new()
	material.shader = forge_panel_shader
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("base_roughness", roughness)
	material.set_shader_parameter("metalness", metal)
	return material


func _forge_piece(groups: Dictionary, material: Material, size: Vector3, at: Vector3, angle: Vector3 = Vector3.ZERO) -> void:
	if not groups.has(material):
		groups[material] = []
	groups[material].append(Transform3D(Basis.from_euler(angle).scaled(size), at))


func _forge_batch(parent: Node3D, groups: Dictionary) -> void:
	if forge_unit_box == null:
		forge_unit_box = BoxMesh.new()
		forge_unit_box.size = Vector3.ONE
	var solid_transforms: Array[Transform3D] = []
	var solid_colors: Array[Color] = []
	var solid_surfaces: Array[Color] = []
	for material: Material in groups:
		var transforms: Array = groups[material]
		var forge_pbr: bool = material is ShaderMaterial and material.shader == forge_panel_shader
		var plain_pbr: bool = material is StandardMaterial3D and material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL
		if (forge_pbr or plain_pbr) and not material.get_meta("no_shadow", false):
			var color: Color = material.get_shader_parameter("tint") if forge_pbr else material.albedo_color
			var roughness: float = material.get_shader_parameter("base_roughness") if forge_pbr else material.roughness
			var metal: float = material.get_shader_parameter("metalness") if forge_pbr else material.metallic
			for transform: Transform3D in transforms:
				solid_transforms.append(transform)
				solid_colors.append(color)
				solid_surfaces.append(Color(roughness, metal, 0.0 if forge_pbr else 1.0, 0.0))
			continue
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.mesh = forge_unit_box
		instances.instance_count = transforms.size()
		for index in range(transforms.size()):
			instances.set_instance_transform(index, transforms[index])
		var visual := MultiMeshInstance3D.new()
		visual.multimesh = instances
		visual.material_override = material
		if material is BaseMaterial3D and material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if material.get_meta("no_shadow", false):
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(visual)
	if solid_transforms.is_empty():
		return
	if forge_instanced_material == null:
		forge_instanced_material = _forge_material(Color.WHITE)
		forge_instanced_material.set_shader_parameter("use_instance_material", true)
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_colors = true
	instances.use_custom_data = true
	instances.mesh = forge_unit_box
	instances.instance_count = solid_transforms.size()
	for index in range(solid_transforms.size()):
		instances.set_instance_transform(index, solid_transforms[index])
		instances.set_instance_color(index, solid_colors[index])
		instances.set_instance_custom_data(index, solid_surfaces[index])
	var visual := MultiMeshInstance3D.new()
	visual.multimesh = instances
	visual.material_override = forge_instanced_material
	parent.add_child(visual)


func _build_world() -> void:
	var environment: Environment = Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("101d35")
	sky_material.sky_horizon_color = Color("334c69")
	sky_material.ground_bottom_color = Color("10151c")
	sky_material.ground_horizon_color = Color("263948")
	sky_material.sky_curve = 0.23
	sky_material.sun_angle_max = 1.2
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.67, 0.74)
	environment.ambient_light_energy = 0.40
	environment.ambient_light_sky_contribution = 0.3
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.0
	environment.ssao_enabled = true
	environment.ssao_radius = 0.42
	environment.ssao_intensity = 1.35
	environment.glow_enabled = true
	environment.glow_intensity = 0.16
	environment.glow_hdr_threshold = 1.4
	environment.fog_enabled = true
	environment.fog_light_color = Color("263b50")
	environment.fog_density = 0.0035
	environment.fog_sky_affect = 0.2
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var key_light: DirectionalLight3D = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-46, -32, 0)
	key_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	key_light.light_color = Color(0.88, 0.92, 1.0)
	key_light.light_energy = 1.05
	key_light.shadow_enabled = not (OS.has_feature("android") or OS.has_feature("ios"))
	key_light.directional_shadow_max_distance = 60.0
	key_light.shadow_bias = 0.035
	add_child(key_light)
	var rim_light: DirectionalLight3D = DirectionalLight3D.new()
	rim_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	rim_light.rotation_degrees = Vector3(-24, 145, 0)
	rim_light.light_color = Color(1.0, 0.56, 0.25)
	rim_light.light_energy = 0.0
	add_child(rim_light)
	camera = Camera3D.new()
	camera.name = "FirstPersonCamera"
	camera.position = Vector3(0.0, 1.75, 0.0)
	camera.near = 0.04
	camera.far = 120.0 if OS.has_feature("android") or OS.has_feature("ios") else 230.0
	camera.fov = 76.0
	camera.current = true
	add_child(camera)
	var road_material: Material = _make_road_flow_material()
	var steel := _forge_material(Color("2c3034"), 0.73, 0.55)
	var casing := _forge_material(Color("404448"), 0.79, 0.3)
	var concrete := _forge_material(Color("454749"), 0.94, 0.02)
	var copper := _forge_material(Color("725440"), 0.68, 0.55)
	var yellow := _forge_material(Color("8f753e"), 0.79, 0.12)
	var soot := _forge_material(Color("121a22"), 0.85, 0.25)
	var stripe_material := _material(Color("307e8b"))
	var work_light := _material(Color(1.0, 0.77, 0.40), true)
	var furnace := ShaderMaterial.new()
	var heat_shader := Shader.new()
	heat_shader.code = """shader_type spatial;
render_mode unshaded;
void fragment() {
	vec2 cell = floor(UV*vec2(9.0, 7.0));
	float heat = fract(sin(dot(cell, vec2(127.1, 311.7)))*43758.5453);
	float core = clamp(1.0-abs(UV.y-0.4)*1.7, 0.0, 1.0);
	ALBEDO = mix(vec3(0.75, 0.10, 0.005), vec3(1.0, 0.88, 0.43), core*(0.50+heat*0.50));
}
"""
	furnace.shader = heat_shader
	furnace.set_meta("no_shadow", true)
	var section_materials := {"steel":steel,"casing":casing,"concrete":concrete,"copper":copper,"yellow":yellow,"soot":soot,"stripe":stripe_material,"work_light":work_light,"furnace":furnace}
	for lane_edge in [-4.0, -2.0, 0.0, 2.0, 4.0]:
		_box(self, Vector3(0.035, 0.015, 225), Vector3(lane_edge, -0.045, -105), stripe_material)
	for side in [-1.0, 1.0]:
		_box(self, Vector3(0.48, 0.72, 230), Vector3(side * 5.5, 0.21, -105), concrete)
		_box(self, Vector3(0.16, 0.12, 230), Vector3(side * 5.32, 0.63, -105), steel)
	# Keep two extra bays behind the camera from the first frame. A 20m tower
	# still projects onto the visible road after its body has passed the player.
	# The forward reserve also places new bays beyond the 230m far plane,
	# including the wider forward reach of the permitted turned camera.
	for i in range(-ROAD_TILES_BEHIND, ROAD_TILES_AHEAD):
		var segment: Node3D = Node3D.new()
		segment.name = "RoadTile%d" % (i + ROAD_TILES_BEHIND)
		segment.position.z = 6.0 - float(i) * ROAD_TILE_LENGTH
		segment.set_meta("layout_index",i)
		add_child(segment)
		road_segments.append(segment)
		# Each receiver follows its own nearby lamps and occluders. The route
		# coordinate in the shader remains continuous across these 10m tiles.
		var deck := _box(segment, Vector3(10.5, 0.35, 10.001), Vector3(0, -0.23, -5.0), road_material)
		deck.name = "DeckReceiver"
		deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var markers: Dictionary = {}
		for x in LANES:
			_forge_piece(markers,stripe_material,Vector3(0.55,0.01,0.12),Vector3(x,-0.035,0))
		_forge_batch(segment,markers)
		var assembly: Dictionary = RouteScript.build_assembly(self,segment,i,section_materials)
		var base_bay: Node3D = assembly.root
		forge_emitters.append_array(assembly.emitters)
		var variants: Dictionary = RouteScript.build_variants(self,segment,i,section_materials)
		var section_roots: Array = [base_bay]
		section_roots.append_array(variants.roots)
		segment.set_meta("section_roots",section_roots)
		segment.set_meta("route_section",0)
		forge_emitters.append_array(variants.emitters)
	# A distant furnace crane anchors the view above the repeating service bays.
	var skyline: Dictionary = {}
	for side in [-1.0, 1.0]:
		_forge_piece(skyline, steel, Vector3(2.5, 43.0, 3.0), Vector3(side*18.0, 21.5, -145.0))
		_forge_piece(skyline, casing, Vector3(5.0, 2.0, 7.0), Vector3(side*18.0, 39.0, -145.0))
		for level in range(5):
			_forge_piece(skyline, yellow, Vector3(0.12, 0.12, 6.0), Vector3(side*15.6, 6.0+float(level)*4.0, -145.0))
	_forge_piece(skyline, steel, Vector3(40.0, 1.6, 4.0), Vector3(0, 42.0, -145.0))
	_forge_piece(skyline, copper, Vector3(0.3, 6.0, 0.3), Vector3(0, 38.5, -145.0))
	_forge_piece(skyline, steel, Vector3(5.0, 3.4, 4.0), Vector3(0, 34.3, -145.0))
	_forge_piece(skyline, furnace, Vector3(4.2, 1.3, 3.4), Vector3(0, 36.0, -145.0))
	_forge_batch(self, skyline)
	RouteScript.build_backdrop(self,section_materials)
	for index in range(4):
		var lamp := SpotLight3D.new()
		lamp.name = "FurnaceSpot%d" % index
		lamp.light_color = Color(1.0, 0.60, 0.28)
		lamp.light_specular = 0.2
		lamp.spot_range = 12.0
		lamp.spot_angle = 42.0
		lamp.spot_attenuation = 1.4
		lamp.shadow_enabled = true
		lamp.shadow_bias = 0.025
		add_child(lamp)
		forge_lights.append(lamp)
	_build_speed_flow()
	enemy_root = Node3D.new()
	enemy_root.name = "Enemies"
	add_child(enemy_root)


func _update_road(sim_dt: float) -> void:
	for segment in road_segments:
		segment.position.z += speed * sim_dt
		# Include the caster's ground projection, not just its visible body.
		# All four chapters project at most 26m forward of the tile origin;
		# retaining 32m leaves the full shadow behind every allowed view.
		if segment.position.z > ROAD_RECYCLE_Z:
			segment.position.z -= ROAD_LOOP_LENGTH * ceilf((segment.position.z - ROAD_RECYCLE_Z) / ROAD_LOOP_LENGTH)
			var phase := elapsed / maxf(route_duration,1.0)
			var section := 3 if phase >= 0.82 else (2 if phase >= 0.55 else (1 if phase >= 0.26 else 0))
			_set_route_section(segment,section)
		if segment.position.z >= 0.0 and segment.position.z < 10.0:
			route_section = int(segment.get_meta("route_section",0))
	_update_speed_flow()


func _set_route_section(segment: Node3D, section: int) -> void:
	var roots: Array = segment.get_meta("section_roots",[])
	for index in range(roots.size()):
		roots[index].visible = index == section
	segment.set_meta("route_section",section)


func _make_road_flow_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
uniform float run_distance = 0.0;
varying vec3 world_position;
float route_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float route_noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
	return mix(mix(route_hash(i), route_hash(i+vec2(1,0)), f.x), mix(route_hash(i+vec2(0,1)), route_hash(i+vec2(1,1)), f.x), f.y);
}
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float z = world_position.z - run_distance;
	float x = world_position.x;
	float aa = max(fwidth(z), 0.008);
	float seam_distance = min(mod(z, 2.4), 2.4 - mod(z, 2.4));
	float seam = 1.0 - smoothstep(0.012, 0.012 + aa, seam_distance);
	float grain = fract(sin(dot(floor(vec2(x, z) * 5.0), vec2(12.9898, 78.233))) * 43758.5453);
	float panel = fract(sin(dot(floor(vec2(x / 1.2, z / 2.4)), vec2(73.3, 129.7))) * 3719.83);
	vec3 deck = vec3(0.103, 0.112, 0.118) * (0.92 + panel * 0.10 + grain * 0.03);
	deck = mix(deck, vec3(0.025, 0.032, 0.042), seam * 0.72);
	float centre_seam = 1.0 - smoothstep(0.012, 0.035 + max(fwidth(x), 0.004), abs(mod(x + 0.6, 1.2) - 0.6));
	deck *= 1.0 - centre_seam * 0.18;
	float shoulder = smoothstep(4.15, 4.28, abs(x)) * (1.0 - smoothstep(4.78, 4.91, abs(x)));
	float chevron = smoothstep(0.44, 0.56, fract((z + abs(x) * 1.35) / 4.8));
	deck = mix(deck, mix(vec3(0.045, 0.055, 0.065), vec3(0.32, 0.26, 0.14), chevron), shoulder * 0.75);
	float paint = (1.0 - smoothstep(0.025, 0.045, abs(abs(x) - 1.0))) * (1.0 - smoothstep(0.22, 0.28, abs(mod(z + 3.0, 6.0) - 3.0)));
	vec2 route = vec2(x, z);
	vec2 warp = vec2(route_noise(route*0.13+vec2(7.3, 19.1)), route_noise(route*0.11-vec2(27.7, 4.2)))*3.2;
	float moisture = route_noise(route*0.21+warp)*0.62 + route_noise(route*0.59-warp)*0.26 + route_noise(route*1.71)*0.12;
	float edge_bias = smoothstep(2.4, 5.0, abs(x))*0.12;
	float damp = smoothstep(0.73, 0.88, moisture+edge_bias);
	vec2 bolt = vec2(abs(mod(x+0.6, 1.2)-0.6)-0.48, abs(mod(z+1.2, 2.4)-1.2)-1.06);
	float rivet_aa = max(fwidth(x), fwidth(z));
	float rivet = (1.0-smoothstep(0.009, 0.013+rivet_aa, length(bolt)))*(1.0-smoothstep(0.02, 0.055, rivet_aa));
	deck = mix(deck, vec3(0.055, 0.063, 0.073), rivet*0.7);
	deck *= 1.0-damp*0.18;
	ALBEDO = mix(deck, vec3(0.28, 0.48, 0.51), paint);
	ROUGHNESS = mix(0.86, 0.66, damp);
	METALLIC = 0.06;
	SPECULAR = 0.25;
}
"""
	road_flow_material = ShaderMaterial.new()
	road_flow_material.shader = shader
	return road_flow_material


func _add_speed_batch(entries: Array[Dictionary], unshaded: bool) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = entries.size()
	var visual := MultiMeshInstance3D.new()
	visual.name = "PassingReflectors" if unshaded else "NearScaffolding"
	visual.multimesh = multimesh
	var material := _material(Color.WHITE, unshaded)
	material.vertex_color_use_as_albedo = true
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	var buffer := PackedFloat32Array()
	buffer.resize(entries.size() * 16)
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		var dimensions: Vector3 = entry.size
		var position: Vector3 = entry.position
		var color: Color = entry.color
		var offset := index * 16
		buffer[offset] = dimensions.x
		buffer[offset + 3] = position.x
		buffer[offset + 5] = dimensions.y
		buffer[offset + 7] = position.y
		buffer[offset + 10] = dimensions.z
		buffer[offset + 11] = position.z
		buffer[offset + 12] = color.r
		buffer[offset + 13] = color.g
		buffer[offset + 14] = color.b
		buffer[offset + 15] = color.a
	multimesh.buffer = buffer
	speed_flow_batches.append({"multimesh": multimesh, "entries": entries, "buffer": buffer})


func _build_speed_flow() -> void:
	var supports: Array[Dictionary] = []
	var reflectors: Array[Dictionary] = []
	for index in range(58):
		var z: float = 8.0 - float(index) * 4.0
		for side in [-1.0, 1.0]:
			supports.append({"position": Vector3(side * 4.97, 0.5725, z), "size": Vector3(0.13, 1.295, 0.18), "color": Color(0.19, 0.25, 0.28)})
			reflectors.append({"position": Vector3(side * 4.88, 1.10, z), "size": Vector3(0.09, 0.18, 0.055), "color": Color(0.93, 0.72, 0.38) if index % 3 == 0 else Color(0.40, 0.43, 0.43)})
			reflectors.append({"position": Vector3(side * 4.88, 0.36, z), "size": Vector3(0.11, 0.055, 0.42), "color": Color(0.31, 0.20, 0.09)})
	for index in range(12):
		var z: float = -6.0 - float(index) * 20.0
		for side in [-1.0, 1.0]:
			supports.append({"position": Vector3(side * 5.05, 1.8325, z), "size": Vector3(0.16, 3.815, 0.24), "color": Color(0.19, 0.25, 0.27)})
			# A real cantilever and housing connect every luminous underside to
			# its mast. All four pieces share Z, so recycling cannot separate them.
			supports.append({"position": Vector3(side * 4.68, 3.72, z), "size": Vector3(1.02, 0.10, 0.14), "color": Color(0.19, 0.25, 0.27)})
			supports.append({"position": Vector3(side * 4.2, 3.66, z), "size": Vector3(0.62, 0.10, 0.14), "color": Color(0.14, 0.18, 0.22)})
			reflectors.append({"position": Vector3(side * 4.2, 3.60, z), "size": Vector3(0.52, 0.025, 0.08), "color": Color(0.62, 0.75, 0.77)})
	_add_speed_batch(supports, false)
	_add_speed_batch(reflectors, true)
	_update_speed_flow()


func _update_speed_flow() -> void:
	if is_instance_valid(road_flow_material):
		road_flow_material.set_shader_parameter("run_distance", run_distance)
	for batch in speed_flow_batches:
		var entries: Array = batch.entries
		var buffer: PackedFloat32Array = batch.buffer
		for index in range(entries.size()):
			var entry: Dictionary = entries[index]
			var position: Vector3 = entry.position
			buffer[index * 16 + 11] = wrapf(position.z + run_distance, -222.0, 10.0)
		batch.multimesh.buffer = buffer
		batch.buffer = buffer
	_update_forge_lights()


func _update_forge_lights() -> void:
	var candidates: Array[Dictionary] = []
	for emitter in forge_emitters:
		if emitter.has("visual_root") and not emitter.visual_root.is_visible_in_tree():
			continue
		var segment: Node3D = emitter.segment
		var point: Vector3 = segment.to_global(Vector3(emitter.local))
		if point.z < -42.0 or point.z > 9.0:
			continue
		var weight: float = smoothstep(-42.0, -26.0, point.z) * (1.0-smoothstep(3.0, 9.0, point.z))
		candidates.append({"point": point, "side": emitter.side, "weight": weight, "score": absf(point.z+8.0)})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) < float(b.score))
	for index in range(forge_lights.size()):
		var lamp: SpotLight3D = forge_lights[index]
		lamp.visible = index < candidates.size()
		if not lamp.visible:
			continue
		var entry: Dictionary = candidates[index]
		var point: Vector3 = entry.point
		lamp.global_position = point
		lamp.look_at(point+Vector3(-float(entry.side)*4.0, -3.35, -0.4), Vector3.UP)
		lamp.light_energy = 12.0*float(entry.weight)


func _build_interface() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	hud = HudScript.new()
	layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_controls = TouchScript.new()
	layer.add_child(touch_controls)
	touch_controls.configure(self, touch_mode)
	sword = SwordScript.new()
	camera.add_child(sword)
	audio = AudioScript.new()
	add_child(audio)
	sword.animation_event.connect(_on_weapon_animation_event)


func _on_weapon_animation_event(event: StringName, intensity: float) -> void:
	if state == "playing" and is_instance_valid(audio):
		audio.play_event(String(event), intensity)
