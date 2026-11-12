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
const EncounterScript = preload("res://scripts/encounter_director.gd")
const MotionScript = preload("res://scripts/enemy_motion.gd")
const CarrierScript = preload("res://scripts/carrier_archetype.gd")
const SeriesScript = preload("res://scripts/series_archetypes.gd")
const CampaignRuntimeScript = preload("res://scripts/campaign_runtime.gd")
const SeriesCombatScript = preload("res://scripts/series_combat.gd")
const SeriesSceneryScript = preload("res://scripts/series_scenery.gd")
const SeriesEffectsScript = preload("res://scripts/series_effects.gd")
const ENEMY_SERIES := "SERIES_01"
const ENEMY_SERIES_LABEL := "第一系列"
const BOSS_CARRIER_KIND := "boss_carrier"
const DEPLOYMENT_FADE_SECONDS := 0.5
const DEPLOYMENT_OPEN_SECONDS := 1.2
const DEPLOYMENT_APPROACH_SECONDS := 1.75
const DEPLOYMENT_RELEASE_SECONDS := DEPLOYMENT_APPROACH_SECONDS + 2.11
const DEPLOYMENT_CARRIER_ENTRY := Vector3(0,14.0,-64.0)
const DEPLOYMENT_DESCENT_START := Vector3(0,13.2,-26.0)
const DEPLOYMENT_MOUNT_POINT := Vector3(0,4.17,-0.45)
const DEPLOYMENT_FALL_SECONDS := 0.96
const DEPLOYMENT_SETTLE_SECONDS := 1.68
const DEPLOYMENT_SECONDS := DEPLOYMENT_RELEASE_SECONDS + DEPLOYMENT_FALL_SECONDS + DEPLOYMENT_SETTLE_SECONDS
const MAX_PROJECTILES := 24
const MAX_PROJECTILE_EVENTS := MAX_PROJECTILES*2
const MAX_BLASTS := 12
const ENEMY_RUN_SPEED := 2.8
const PLAYER_CUT_MIN_Z := -32.0
const PLAYER_CUT_MAX_Z := -0.5
const GROUND_ENTRY_Z := PLAYER_CUT_MIN_Z-8.0
const MELEE_STRIKE_SECONDS := 0.28
const MELEE_CONTACT_PHASE := 0.55
const BOSS_STRIKE_SECONDS := 0.46
const BOSS_FIRE_PHASE := 0.55
const BOSS_SHOCK_ORIGIN := Vector3(0, 1.75, -9.5)
const GUARD_IDEAL_AGE := 0.075
const GUARD_PRECISION_FALLOFF := 0.23
const GUARD_PRECISE_THRESHOLD := 0.83
const GUARD_TAP_WINDOW := GUARD_IDEAL_AGE+GUARD_PRECISION_FALLOFF*(1.0-GUARD_PRECISE_THRESHOLD)
const GUARD_RECOVERY_SECONDS := 0.15
const SHEATH_ALERT_LEAD := 0.60
const SHEATH_ALERT_PEAK_LEAD := 0.40
const SHEATH_BREATH_SECONDS := 1.35
const PROJECTILE_SPEED_SCALE: float = 2.0 / 3.0
const PROJECTILE_TARGET := Vector3(0, 1.65, -0.9)
const PROJECTILE_EVENT_TIE_EPSILON: float = 0.000001
const REFLECTED_BLAST_RADII := {"bolt":0.90,"shock":1.15,"missile":1.45,"mine":1.25,"sword_wave":1.1,"ink_spear":0.95,"seal":1.05,"buckshot":0.75,"needle":0.85,"beacon":0.9,"electric_wave":1.15,"torpedo":1.45,"plasma_lance":1.7,"cannon_orb":1.3}
const FLYING_ENEMIES := ["drone","missile_drone","shield_drone","interceptor","mine_layer"]
const RANGED_ENEMIES := ["ranged","drone","missile_drone","shield_drone","interceptor","mine_layer"]
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
const SKY_LANES: Array[float] = [-3.2, 0.0, 3.2]
const SKY_ROOT_Y := 3.0
const SKY_HOLD_Z := -22.0
const SKY_ENTRY_Z := -31.0
const MAX_SKY_ENEMIES := 1
const BOSS_DEATH_HOLD := 1.35
const BOSS_DEATH_TAIL := 1.05
const UI_PREFERENCES_FILE := "user://ui_preferences.cfg"

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
var invincible: bool = false
var shift_down: bool = false
var left_down: bool = false
var left_time: float = 0.0
var slashing: bool = false
var slash_lock: bool = false
var guard_active := false
var guard_age: float = 0.0
var guard_cooldown: float = 0.0
var _right_guard_down := false
var _guard_queued := false
var _guard_tap_released := false
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
var retiring_enemies: Array[Dictionary] = []
var wave_needs_clear := false
var wave_quiet_time := 0.0
var wave_recovery_time := 1.0
var boss_support_window := 0
var boss_support_side := -1
var projectiles: Array = []
var blasts: Array = []
var road_segments: Array[Node3D] = []
var wave_index: int = 0
var spawn_timer: float = 2.8
var boss_spawned: bool = false
var boss_enemy: Node3D
var boss_carrier: Node3D
var deployment_clearance: Array[Dictionary] = []
var deployment_clearance_age := 0.0
var landing_impact_age := 10.0
var landing_impact_strength := 0.0
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
var _sheath_breath_age := 0.0
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
var ui_settings := {"volume":1.0,"fullscreen":true,"vsync":true,"msaa":true}
var ui_settings_path := UI_PREFERENCES_FILE
var ui_quit_requested := false
var ui_quit_count := 0
var _ui_preferences_enabled := true
var _ui_settings_dirty := false
var _ui_settings_save_delay := 0.0
var _ui_pointer_capture_until_release := false
var campaign: RefCounted
var series_combat: RefCounted
var series_scenery: Node3D
var series_effects: Node3D
var _volley_damage: Dictionary = {}


func _ready() -> void:
	test_mode = "--verify-prototype" in OS.get_cmdline_user_args() or "--verify-ui" in OS.get_cmdline_user_args()
	_ui_preferences_enabled = ui_settings_path != UI_PREFERENCES_FILE or (not test_mode and DisplayServer.get_name() != "headless" and not "--ui-test-no-persist" in OS.get_cmdline_user_args())
	touch_mode = is_mobile_input_enabled()
	get_tree().quit_on_go_back = false
	if OS.has_feature("android") or OS.has_feature("ios"):
		Engine.max_fps = 60
	_build_world()
	series_scenery = SeriesSceneryScript.new()
	add_child(series_scenery)
	series_scenery.configure(self,road_segments)
	series_effects = SeriesEffectsScript.new()
	add_child(series_effects)
	series_effects.configure()
	series_combat = SeriesCombatScript.new()
	series_combat.configure(self)
	campaign = CampaignRuntimeScript.new()
	campaign.configure(self)
	_build_interface()
	sword.visible = false
	_load_ui_settings()
	ProjectileScript.prewarm()
	EnemyScript.prewarm_normal_model()
	EnemyScript.prewarm_models(["tank", "ranged", "boss", "drone", "missile_drone", "barrier", "beam", "shield_drone", "interceptor", "mine_layer", BOSS_CARRIER_KIND])
	_build_menu_showcase()
	campaign.prepare_new_run(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("Slay the highway / 杀路 v%s four-stage campaign ready | Godot " % ProjectSettings.get_setting("application/config/version"), Engine.get_version_info().string)
	if "--preview" in OS.get_cmdline_user_args():
		start_game()
		_spawn_enemy("normal", 1, -10.0)
		_spawn_enemy("tank", 2, -19.0)
		_spawn_enemy("ranged", 0, -32.0)


func _exit_tree() -> void:
	if _ui_settings_dirty:
		_save_ui_settings()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		_ui_pointer_capture_until_release = false
		if is_instance_valid(hud) and hud.has_method("cancel_menu_gesture"):
			hud.cancel_menu_gesture()
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
	if _ui_pointer_capture_until_release and event is InputEventMouse:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_ui_pointer_capture_until_release = false
			hud.cancel_menu_gesture()
		get_viewport().set_input_as_handled()
		return
	if state != "playing" and is_instance_valid(hud):
		_update_hud()
		if hud.handle_menu_input(event):
			get_viewport().set_input_as_handled()
			return
	if is_instance_valid(touch_controls) and touch_controls.handle_event(event):
		get_viewport().set_input_as_handled()
		return
	# Android native touch owns its gesture. Ignore the duplicate mouse event.
	if touch_mode and event is InputEventMouse and event.device == -1:
		return
	if event is InputEventKey:
		if event.keycode == KEY_SHIFT and state == "playing":
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
					if campaign != null and campaign.active:
						campaign.begin_boss()
						return
					if boss_spawned and is_instance_valid(boss_enemy) and not boss_enemy.dead:
						return
					training = false
					boss_spawned = false
					boss_enemy = null
					elapsed = route_duration
					_spawn_boss()
			KEY_F4:
				_start_cutting_lab()
			KEY_F5:
				show_timing = not show_timing
			KEY_F6:
				if state == "playing" and not touch_mode:
					invincible = not invincible
					_notice("无敌已开启" if invincible else "无敌已关闭")
					get_viewport().set_input_as_handled()
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
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if left_down:
					return
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
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed and not _right_guard_down:
				_right_guard_down = true
				_begin_guard()
			elif not event.pressed:
				_right_guard_down = false
				_release_guard()


func mobile_begin_blade() -> void:
	guard_active = false
	_guard_queued = false
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
	if campaign != null and not training and not campaign.ensure_ready_for_start():
		start_when_menu_prepared = true
		state = "menu"
		_reset_input()
		sword.visible = false
		for enemy in enemies:
			if is_instance_valid(enemy): enemy.set_meta("simulation_scale",0.0)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	_restore_deployment_clearance()
	boss_carrier = null
	landing_impact_age = 10.0
	landing_impact_strength = 0.0
	_clear_retiring_enemies()
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
	sword.visible = true
	_clear_sheath_alert()
	combat_events.clear()
	_volley_damage.clear()
	combat_stats = {"parries": 0, "perfects": 0, "hits_taken": 0, "projectiles_cut": 0, "windups": 0, "impacts": 0, "kills": 0, "slash_time": 0.0}
	speed = BASE_SPEED
	gear = 1
	health = 5
	invincible = false
	score = 0
	kills = 0
	combo = 0
	elapsed = 0.0
	game_clock = 0.0
	wave_index = 0
	spawn_timer = 2.8
	wave_needs_clear = false
	wave_quiet_time = 0.0
	wave_recovery_time = 1.0
	boss_support_window = 0
	boss_support_side = -1
	boss_spawned = false
	boss_enemy = null
	boss_timer = 2.5
	boss_pattern = 0
	left_down = false
	left_time = 0.0
	slashing = false
	slash_lock = false
	shift_down = false
	guard_active = false
	_right_guard_down = false
	_guard_queued = false
	guard_age = 0.0
	guard_cooldown = 0.0
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
	if campaign != null and not training: campaign.begin_run()
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
	back.name = "PreparationCover"
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var models: Array[Node3D] = []
	for kind in ["normal","tank","ranged","boss","drone","missile_drone","barrier","beam","normal","shield_drone","interceptor","mine_layer",BOSS_CARRIER_KIND]:
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
	portrait.name = "MenuPortrait"
	portrait.position = Vector3(3.42,-0.16,-5.7)
	portrait.scale = Vector3.ONE*1.6
	portrait.set_meta("simulation_scale",0.0)
	portrait.set_action("recover",1.0)
	# Warm the actual cut-particle variant from a real, noncritical material
	# cut on a hidden portrait copy. No gameplay actor or score is involved.
	var cut_point: Vector3 = models[0].to_global(models[0]._part_pose(1)*Vector3(-0.70,1.475,0.20))
	var screen := camera.unproject_position(cut_point)
	models[0].cut_screen(camera,screen-Vector2(4,0),screen+Vector2(4,0),0.4)
	# Render the ground-arrival shader variants behind the existing cover
	# during menu preparation rather than first creating them on the highway.
	for index in [1,2,8]:
		models[index].set_meta("entry_active",true)
		models[index].set_entry_visibility(0.5)
	for kind in ["bolt","missile","shock","mine"]:
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
	# Keep the highway and one portrait on the actual title screen. The other
	# already-rendered variants and their cover only prepare combat resources.
	if is_instance_valid(menu_showcase):
		for child in menu_showcase.get_children():
			if child.has_method("set_entry_visibility"):
				child.set_entry_visibility(1.0)
				child.set_meta("entry_active",false)
			if child is Node3D and child.name != "MenuPortrait": child.visible = false
	menu_prepared = true
	if start_when_menu_prepared and state == "menu" and (campaign == null or campaign.assets_ready):
		_start_game_from_ui()


func _start_cutting_lab() -> void:
	if campaign != null: campaign.suspend()
	if series_scenery != null: series_scenery.force_series(1)
	training = true
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
	guard_active = false
	_right_guard_down = false
	_guard_queued = false
	guard_age = 0.0
	guard_cooldown = 0.0
	pending_strokes.clear()
	sword.set_pose("sheathed")
	_clear_sheath_alert()


func _start_game_from_ui(reset_mode: bool = true) -> void:
	if reset_mode:
		practice = false
		training = false
	ui_quit_requested = false
	if training:
		_start_cutting_lab()
	else:
		start_game()
	_ui_pointer_capture_until_release = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_update_hud()


func _return_to_menu() -> void:
	if campaign != null: campaign.suspend()
	if series_scenery != null: series_scenery.force_series(1)
	_restore_deployment_clearance()
	boss_carrier = null
	_clear_retiring_enemies()
	if slashing:
		_consume_strokes()
	_reset_input()
	for enemy in enemies:
		if is_instance_valid(enemy): enemy.queue_free()
	enemies.clear()
	_clear_projectiles()
	_clear_blasts()
	for effect in impact_effects:
		if is_instance_valid(effect.node): effect.node.queue_free()
	impact_effects.clear()
	state = "menu"
	sword.visible = false
	practice = false
	training = false
	show_timing = false
	invincible = false
	boss_spawned = false
	boss_enemy = null
	boss_timer = 2.5
	boss_pattern = 0
	victory_timer = -1.0
	start_when_menu_prepared = false
	ui_quit_requested = false
	speed = BASE_SPEED
	gear = 1
	elapsed = 0.0
	game_clock = 0.0
	run_distance = 0.0
	effective_runner_speed = 0.0
	route_section = 0
	hit_stop = 0.0
	hurt_flash = 0.0
	shake = 0.0
	stroke_alpha = 0.0
	impact_strength = 0.0
	kill_pulse = 0.0
	parry_pulse = 0.0
	aim_angles = Vector2.ZERO
	camera.position = Vector3(0,1.75,0)
	camera.rotation = Vector3.ZERO
	camera.fov = 76.0
	for index in range(road_segments.size()):
		road_segments[index].position.z = ROAD_FIRST_TILE_Z-float(index)*ROAD_TILE_LENGTH
		_set_route_section(road_segments[index],0)
	_update_speed_flow()
	if is_instance_valid(menu_showcase):
		menu_showcase.queue_free()
		menu_showcase = null
	menu_prepared = true
	_build_menu_showcase()
	if campaign != null: campaign.prepare_new_run(false)
	audio.set_runner_motion(0.0,0.0,false,0.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_ui_pointer_capture_until_release = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_update_hud()


func _on_ui_feedback(_kind: StringName) -> void:
	if is_instance_valid(audio):
		audio.play_event("guard_release",0.32)


func _on_ui_action(action: StringName, value: Variant) -> void:
	match action:
		&"start":
			if state not in ["menu","dead","won"]: return
			if state == "menu" and (not menu_prepared or (campaign != null and not campaign.assets_ready)):
				start_when_menu_prepared = true
				_ui_pointer_capture_until_release = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
			else:
				_start_game_from_ui()
		&"restart":
			if state in ["paused","dead","won"]: _start_game_from_ui(false)
		&"resume":
			if state == "paused":
				_resume_game()
				_ui_pointer_capture_until_release = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		&"menu":
			if state != "playing": _return_to_menu()
		&"quit":
			if state == "playing" or ui_quit_requested: return
			ui_quit_requested = true
			ui_quit_count += 1
			_save_ui_settings()
			if not test_mode: _quit_from_ui()
		&"volume":
			if state == "playing" or not (value is float or value is int): return
			ui_settings.volume = clampf(float(value),0.0,1.0)
			_ui_setting_changed()
		&"fullscreen", &"vsync", &"msaa":
			if state == "playing" or not value is bool: return
			ui_settings[String(action)] = bool(value)
			_ui_setting_changed()
	_update_hud()


func _quit_from_ui() -> void:
	await get_tree().create_timer(0.04).timeout
	get_tree().quit()


func _load_ui_settings() -> void:
	if _ui_preferences_enabled and ui_settings_path.begins_with("user://"):
		var config := ConfigFile.new()
		if config.load(ui_settings_path) == OK:
			var volume: Variant = config.get_value("ui","volume",1.0)
			if volume is float or volume is int: ui_settings.volume = clampf(float(volume),0.0,1.0)
			for key in ["fullscreen","vsync","msaa"]:
				var saved: Variant = config.get_value("ui",key,true)
				if saved is bool: ui_settings[key] = saved
	_apply_ui_settings()


func _apply_ui_settings() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		var volume: float = float(ui_settings.volume)
		AudioServer.set_bus_mute(bus,volume <= 0.001)
		AudioServer.set_bus_volume_db(bus,linear_to_db(maxf(volume,0.0001)))
	get_viewport().msaa_3d = Viewport.MSAA_4X if bool(ui_settings.msaa) else Viewport.MSAA_DISABLED
	if DisplayServer.get_name() == "headless": return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if bool(ui_settings.fullscreen) else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
		if mode == DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_size(Vector2i(1280,720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(ui_settings.vsync) else DisplayServer.VSYNC_DISABLED)


func _ui_setting_changed() -> void:
	_apply_ui_settings()
	_ui_settings_dirty = true
	_ui_settings_save_delay = 0.35


func _save_ui_settings() -> void:
	_ui_settings_dirty = false
	if not _ui_preferences_enabled or not ui_settings_path.begins_with("user://"): return
	var config := ConfigFile.new()
	for key in ui_settings: config.set_value("ui",key,ui_settings[key])
	var error := config.save(ui_settings_path)
	if error != OK:
		push_warning("UI preferences could not be saved: "+error_string(error))


func _process(delta: float) -> void:
	if _ui_settings_dirty:
		_ui_settings_save_delay -= delta / maxf(Engine.time_scale,0.001)
		if _ui_settings_save_delay <= 0.0:
			_save_ui_settings()
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
		landing_impact_age += sim_dt
		effective_runner_speed = 0.0 if training else speed * world_scale
		audio.set_runner_motion(speed, sim_dt, not training, world_scale)
		if not training:
			run_distance += speed * sim_dt
		if slashing:
			combat_stats["slash_time"] = float(combat_stats.get("slash_time", 0.0)) + delta
		game_clock += sim_dt
		if not training:
			elapsed += sim_dt
		_update_guard(delta, sim_dt)
		_update_camera(delta)
		_update_impact_effects(sim_dt, 0.0 if stopped else delta)
		_update_blasts(sim_dt)
		if series_effects != null: series_effects.update(sim_dt)
		_update_retiring_enemies(sim_dt,world_scale)
		if not training:
			_update_road(sim_dt)
			if series_scenery != null: series_scenery.update(sim_dt,run_distance)
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
			var staged_death: bool = is_instance_valid(boss_enemy) and boss_enemy.has_meta("boss_death_age")
			if staged_death:
				victory_timer = maxf(0.0,BOSS_DEATH_HOLD+BOSS_DEATH_TAIL-float(boss_enemy.get_meta("boss_death_age")))
			else:
				victory_timer -= delta
			if victory_timer <= 0.0 and (not staged_death or bool(boss_enemy.get_meta("boss_death_exploded",false))):
				if campaign != null and campaign.active:
					campaign.legacy_boss_finished()
				else:
					_finish(true)
		if guard_active:
			sword.set_pose("parry", minf(1.0,guard_age / 0.30))
		elif slashing:
			sword.set_pose("held", 0.0, slash_cursor / get_viewport().get_visible_rect().size - Vector2(0.5, 0.5))
		elif guard_cooldown <= 0.0 and sword_time <= 0.0 and (not left_down or slash_lock):
			sword.set_pose("sheathed")
		sword.set_voxel_fx_simulation(stopped or hit_stop > 0.0,world_scale)
		_update_sheath_alert(delta,sim_dt)
	else:
		_clear_sheath_alert()
		sword.set_voxel_fx_simulation(true,0.0)
		effective_runner_speed = 0.0
		audio.set_runner_motion(speed, 0.0, false, 0.0)
		for enemy in enemies:
			if is_instance_valid(enemy):
				enemy.set_meta("simulation_scale", 0.0)
		for row in retiring_enemies:
			if is_instance_valid(row.enemy): row.enemy.set_meta("simulation_scale",0.0)
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
	if landing_impact_age < 0.85:
		var t: float = landing_impact_age
		var envelope: float = exp(-t*5.8)*landing_impact_strength
		camera.position += Vector3(sin(t*47.0)*0.075,-cos(t*34.0)*0.14,0)*envelope
		camera.rotation.x += sin(t*39.0)*0.045*envelope
		camera.rotation.z += sin(t*28.0)*0.025*envelope


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
	guard_active = false
	_guard_queued = false
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
	for enemy in enemies.duplicate():
		if not is_instance_valid(enemy):
			continue
		if bool(enemy.get_meta("campaign_staging",false)): continue
		if enemy.position.z < PLAYER_CUT_MIN_Z or enemy.position.z > PLAYER_CUT_MAX_Z:
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
	# A returned blast can remove several other shots. Keep this gesture's
	# identities stable rather than iterating indices into a shrinking array.
	for projectile: Dictionary in projectiles.duplicate():
		var node: Node3D = projectile.node
		var index := _projectile_index(node)
		if index < 0: continue
		if camera.is_position_behind(node.global_position) or node.position.z < PLAYER_CUT_MIN_Z:
			continue
		if node.intersects_path(camera, points):
			_cut_projectile(index)


func _feedback_contact(point: Vector3, strength: float, kind: String = "hit") -> void:
	contact_serial += 1
	contact_kind = kind
	impact_strength = maxf(impact_strength, clampf(strength, 0.0, 1.0))
	if not camera.is_position_behind(point):
		impact_point = camera.unproject_position(point)


func _clear_sheath_alert() -> void:
	_sheath_breath_age = 0.0
	if is_instance_valid(sword):
		sword.set_sheath_alert(0.0)


func _update_sheath_alert(real_delta: float, world_delta: float) -> void:
	if state != "playing":
		_clear_sheath_alert()
		return
	var cuttable := false
	var contact_time := INF if training else _sheath_projectile_contact_time()
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.dead or enemy.is_queued_for_deletion(): continue
		if bool(enemy.get_meta("campaign_staging",false)) or enemy.enemy_kind in ["barrier","beam"]: continue
		if not cuttable and enemy.position.z >= PLAYER_CUT_MIN_Z and enemy.position.z <= PLAYER_CUT_MAX_Z:
			cuttable = enemy.is_visible_in_tree() and not camera.is_position_behind(enemy.get_aim_point())
		if not training and victory_timer < 0.0 and contact_time > SHEATH_ALERT_PEAK_LEAD:
			var horizon := minf(SHEATH_ALERT_LEAD,contact_time)
			contact_time = minf(contact_time,_sheath_melee_contact_time(enemy,horizon))
			if contact_time > SHEATH_ALERT_PEAK_LEAD and projectiles.size() < MAX_PROJECTILES:
				contact_time = minf(contact_time,_sheath_ranged_contact_time(enemy,minf(horizon,contact_time)))
	var breathing := 0.0
	if cuttable:
		if world_delta > 0.0:
			_sheath_breath_age = fposmod(_sheath_breath_age+real_delta,SHEATH_BREATH_SECONDS)
		var wave := 0.5-0.5*cos(TAU*_sheath_breath_age/SHEATH_BREATH_SECONDS)
		breathing = lerpf(0.44,1.0,wave)
	else:
		_sheath_breath_age = 0.0
	var urgency := 1.0-smoothstep(SHEATH_ALERT_PEAK_LEAD,SHEATH_ALERT_LEAD,contact_time)
	sword.set_sheath_alert(lerpf(breathing,2.0,urgency))


func _sheath_melee_contact_time(enemy: Node3D, horizon: float) -> float:
	if enemy.resolved or bool(enemy.get_meta("entry_active",false)): return INF
	if SeriesScript.supports(str(enemy.enemy_kind)):
		return series_combat.time_to_guardable_melee(enemy,horizon)
	if enemy.enemy_kind in ["boss",BOSS_CARRIER_KIND] or enemy.has_meta("sky_lane") or bool(enemy.get_meta("boss_escort",false)):
		return INF
	var action := str(enemy.get_meta("action_state",""))
	if action not in ["windup","strike"] or bool(enemy.get_meta("impact_done",false)): return INF
	var duration := float(enemy.get_meta("action_duration",MELEE_STRIKE_SECONDS))
	var age := float(enemy.get_meta("action_time",0.0))
	var time := duration*MELEE_CONTACT_PHASE-age if action == "strike" else duration-age+MELEE_STRIKE_SECONDS*MELEE_CONTACT_PHASE
	return maxf(0.0,time) if time <= horizon and enemy.has_attack_limb() else INF


func _sheath_ranged_contact_time(enemy: Node3D, horizon: float) -> float:
	if bool(enemy.get_meta("entry_active",false)): return INF
	if SeriesScript.supports(str(enemy.enemy_kind)):
		return series_combat.time_to_guardable_ranged(enemy,horizon)
	var action := str(enemy.get_meta("action_state",""))
	var duration := float(enemy.get_meta("action_duration",1.0))
	var age := float(enemy.get_meta("action_time",0.0))
	if enemy.enemy_kind == "boss":
		if action not in ["boss_windup","boss_strike"] or bool(enemy.get_meta("impact_done",false)): return INF
		var release := (duration-age+BOSS_STRIKE_SECONDS*BOSS_FIRE_PHASE) if action == "boss_windup" else duration*BOSS_FIRE_PHASE-age
		var variant := int(enemy.get_meta("action_variant",0))
		if release >= horizon or not enemy.has_attack_limb(variant): return INF
		if variant != 1: return maxf(0.0,release)+_forecast_projectile_contact(BOSS_SHOCK_ORIGIN,"shock")
		var flight := INF
		for origin: Vector3 in enemy.get_ranged_origins():
			flight = minf(flight,_forecast_projectile_contact(origin,"missile"))
		return maxf(0.0,release)+flight
	if action not in ["ranged_charge","ranged_fire"]: return INF
	var kind := str(enemy.enemy_kind)
	var escort := bool(enemy.get_meta("boss_escort",false))
	var charge_left := maxf(0.0,duration-age) if action == "ranged_charge" else 0.0
	var fire_duration := (0.30 if escort else _ranged_fire_duration(kind)) if action == "ranged_charge" else duration
	var shot_index := int(enemy.get_meta("burst_shots",0)) if action == "ranged_fire" else 0
	if kind == "interceptor" and shot_index >= 3: return INF
	if kind != "interceptor" and bool(enemy.get_meta("impact_done",false)): return INF
	var release_phase := _ranged_release_phase(kind,shot_index)
	var release := charge_left+maxf(0.0,fire_duration*release_phase-(age if action == "ranged_fire" else 0.0))
	if release >= horizon: return INF
	if escort:
		if not is_instance_valid(boss_enemy) or boss_enemy.dead or str(boss_enemy.get_meta("action_state","")) != "recover": return INF
		var support_left := float(boss_enemy.get_meta("action_duration",0.0))-float(boss_enemy.get_meta("action_time",0.0))
		if int(boss_enemy.get_meta("escort_support_window",0)) <= 0 or support_left <= release: return INF
	var origins: Array[Vector3] = enemy.get_ranged_origins()
	if origins.is_empty(): return INF
	var advance := 0.0
	if not escort and not enemy.has_meta("sky_lane") and charge_left > 0.0:
		advance = _ranged_charge_z(enemy,charge_left)-enemy.position.z
	var offset := Vector3(0,0,advance)
	if kind == "interceptor":
		return release+_forecast_projectile_contact(origins[shot_index%origins.size()]+offset,"bolt")
	var flight := INF
	for origin in origins:
		if kind == "mine_layer":
			flight = minf(flight,_forecast_projectile_contact(origin+offset,"mine",_mine_aim_offset(enemy,origin),0.70))
		else:
			flight = minf(flight,_forecast_projectile_contact(origin+offset,"missile" if kind == "missile_drone" else "bolt"))
	return release+flight


func _sheath_projectile_contact_time() -> float:
	var earliest := INF
	for projectile: Dictionary in projectiles:
		if bool(projectile.reflected) or bool(projectile.get("player_plane_passed",false)): continue
		var node: Node3D = projectile.node
		var time := _projectile_player_plane_time(projectile,SHEATH_ALERT_LEAD)
		var behavior := str(projectile.get("series_behavior",""))
		if not behavior.is_empty():
			var delay := maxf(0.0,float(projectile.series_next)-float(projectile.age))
			if delay <= SHEATH_ALERT_LEAD and delay < time:
				var origin := node.global_position
				match behavior:
					"prime":
						earliest = minf(earliest,delay+_projectile_flight_contact(origin,projectile.launch_velocity,node.collision_radius))
					"beacon":
						var source: Node3D = projectile.source
						if projectiles.size() < MAX_PROJECTILES and is_instance_valid(source) and not source.dead and source.has_attack_limb():
							earliest = minf(earliest,delay+_forecast_projectile_contact(origin,"bolt"))
					"bend":
						origin += Vector3(projectile.velocity)*delay
						var target: Vector3 = projectile.series_options.get("target",PROJECTILE_TARGET)
						var velocity := (target-origin).normalized()*Vector3(projectile.launch_velocity).length()
						earliest = minf(earliest,delay+_projectile_flight_contact(origin,velocity,node.collision_radius))
				continue
		if not is_finite(time) or time >= earliest or not _projectile_touches_player(projectile,time): continue
		var volley := str(node.get_meta("volley_id",""))
		if not volley.is_empty() and float(_volley_damage.get(volley,-INF)) > game_clock+time:
			continue
		var intercepted := false
		for reflected: Dictionary in projectiles:
			if bool(reflected.reflected) and is_finite(_projectile_pair_time(reflected,projectile,time+PROJECTILE_EVENT_TIE_EPSILON)):
				# Only suppress the warning if the actual event order allows
				# this interception, including collisions with enemy material.
				var next := _next_projectile_event(time+PROJECTILE_EVENT_TIE_EPSILON)
				intercepted = next.get("kind","") == "intercept" and next.other.node == node
				break
		if not intercepted: earliest = time
	return earliest


func _begin_guard() -> void:
	if state != "playing":
		return
	if guard_active:
		# A new press can hold the current stance without refreshing its timing.
		_guard_tap_released = false
		return
	if guard_cooldown > 0.0:
		_guard_queued = true
		return
	_guard_queued = false
	if slashing:
		_consume_strokes()
	if left_down:
		slash_lock = true
	left_down = false
	slashing = false
	pending_strokes.clear()
	sword_time = 0.0
	guard_active = true
	guard_age = 0.0
	_guard_tap_released = false
	sword.set_pose("parry", 0.0)


func _release_guard(allow_tap: bool = true) -> void:
	_guard_queued = false
	if not guard_active: return
	if allow_tap and guard_age < GUARD_TAP_WINDOW:
		_guard_tap_released = true
		return
	guard_active = false
	sword.set_pose("sheathed")


func _update_guard(real_delta: float, world_delta: float) -> void:
	if guard_cooldown > 0.0:
		guard_cooldown = maxf(0.0,guard_cooldown-real_delta)
		if guard_cooldown <= 0.0:
			if not slashing and sword_time <= 0.0: sword.set_pose("sheathed")
			if _guard_queued: _begin_guard()
	if guard_active:
		guard_age += world_delta
		if _guard_tap_released and guard_age >= GUARD_TAP_WINDOW:
			guard_active = false
			sword.set_pose("sheathed")


func _try_guard(source: String = "incoming", enemy: Node3D = null) -> bool:
	if not guard_active:
		return false
	guard_active = false
	guard_cooldown = GUARD_RECOVERY_SECONDS
	var precision := clampf(1.0-absf(guard_age-GUARD_IDEAL_AGE)/GUARD_PRECISION_FALLOFF,0.0,1.0)
	var precise := precision > GUARD_PRECISE_THRESHOLD
	var gain := 0.0
	if precise:
		var speed_before := speed
		speed = minf(MAX_SPEED,speed+2.0*lerpf(5.0,17.0,precision))
		gain = speed-speed_before
		gear = gear_for_speed(speed)
	combo += 1
	score += int(100.0 * (1.0 + precision)) * gear
	shake = 0.85
	hit_stop = 0.065
	parry_pulse = 1.0
	combat_stats["parries"] = int(combat_stats.get("parries", 0)) + 1
	_record_combat("parry", enemy, {"source": source, "precision": precision, "speed_gain": gain})
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
	if precise:
		combat_stats["perfects"] = int(combat_stats.get("perfects", 0)) + 1
		audio.play_event("perfect")
		var displayed_gain := roundi(gain)
		_notice("完美振刀  +%d 速度" % displayed_gain if displayed_gain > 0 else "完美振刀", 1.4)
	else:
		audio.play_event("parry")
		_notice("格挡成功", 1.1)
	return true


func _hurt(amount: int = 1, source: String = "contact", enemy: Node3D = null) -> void:
	if state != "playing" or invincible:
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
	if campaign != null and campaign.active:
		campaign.update_spawning(sim_dt)
		return
	if elapsed >= route_duration:
		if not boss_spawned:
			_spawn_boss()
		return
	spawn_timer -= sim_dt
	if wave_needs_clear:
		if _has_pending_wave_enemies():
			wave_quiet_time = 0.0
		else:
			wave_quiet_time += sim_dt
	if spawn_timer > 0.0:
		return
	if wave_needs_clear and wave_quiet_time < wave_recovery_time:
		return
	var plan: Dictionary = EncounterScript.plan(wave_index,elapsed/maxf(route_duration,1.0),speed,route_duration)
	# Persistent air support must not hold up the authored clear row or the
	# advanced solo encounters. Retire its shots before admitting either.
	if str(plan.id) == "four_lane_row" or bool(plan.get("advanced_intro",false)):
		_retire_sky_enemies()
	# Most waves keep the continuous v0.9.5 cadence. Only the single authored
	# row gets a clear stage; ranged additions wait for a readable fire budget.
	if str(plan.id) == "four_lane_row" and _has_pending_wave_enemies():
		return
	if not _can_spawn_encounter_wave(plan):
		return
	_spawn_encounter_wave(plan)
	wave_index += 1
	spawn_timer = float(plan.interval)
	wave_needs_clear = bool(plan.hold_until_clear)
	wave_quiet_time = 0.0
	wave_recovery_time = float(plan.recovery_seconds)


func _has_pending_wave_enemies() -> bool:
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.dead and not enemy.resolved and not enemy.has_meta("sky_lane") and not bool(enemy.get_meta("encounter_retired",false)):
			return true
	return false


func _can_spawn_encounter_wave(plan: Dictionary) -> bool:
	var active_shooters := 0
	var active_advanced := false
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.dead or enemy.resolved or bool(enemy.get_meta("encounter_retired",false)):
			continue
		if enemy.enemy_kind in RANGED_ENEMIES and enemy.has_attack_limb():
			active_shooters += 1
			active_advanced = active_advanced or enemy.enemy_kind in ["interceptor","mine_layer"]
	for item: Dictionary in plan.spawns:
		if str(item.kind) in RANGED_ENEMIES:
			if str(item.kind) in ["interceptor","mine_layer"]:
				if active_shooters > 0:
					return false
			elif active_advanced or active_shooters >= 2:
				return false
	return true


func _spawn_encounter_wave(plan: Dictionary) -> void:
	var z_distance := -maxf(float(plan.minimum_distance),(speed+float(plan.approach_speed_offset))*float(plan.approach_seconds)+float(plan.distance_bias))
	for item: Dictionary in plan.spawns:
		var enemy = _spawn_enemy(str(item.kind),int(item.lane),z_distance+float(item.z_offset))
		enemy.set_meta("wave_id",str(plan.id))
		enemy.set_meta("encounter_role",str(item.role))
		enemy.set_meta("wave_attack_delay",float(item.attack_delay))
		enemy.set_meta("first_charge_extra",float(item.fire_delay))
		enemy.set_meta("entry_depth_offset",float(item.z_offset))
		_start_enemy_entry(enemy)
	var sky_count := 0
	for item: Dictionary in plan.get("sky_spawns",[]):
		if not _can_spawn_sky_enemy(str(item.kind),int(item.sky_lane)):
			_record_combat("sky_spawn_skipped",null,{"wave_index":wave_index,"kind":item.kind,"sky_lane":item.sky_lane})
			continue
		var enemy = _spawn_enemy(str(item.kind),LANES.size()+int(item.sky_lane),SKY_ENTRY_Z)
		if enemy == null: continue
		enemy.set_meta("wave_id",str(plan.id))
		enemy.set_meta("encounter_role","sky_support")
		enemy.position = enemy.get_meta("sky_anchor")
		_start_enemy_entry(enemy)
		sky_count += 1
	_record_combat("wave",null,{"wave_id":plan.id,"wave_index":wave_index,"count":plan.spawns.size()+sky_count,"sky_count":sky_count,"stage":plan.stage})


func _can_spawn_sky_enemy(kind: String, sky_lane: int) -> bool:
	if kind not in FLYING_ENEMIES or kind == "shield_drone" or sky_lane < 0 or sky_lane >= SKY_LANES.size():
		return false
	var sky_count := 0
	var shooters := 0
	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.dead or enemy.resolved or bool(enemy.get_meta("encounter_retired",false)): continue
		if enemy.has_meta("sky_lane"): sky_count += 1
		if enemy.enemy_kind in RANGED_ENEMIES and enemy.has_attack_limb():
			shooters += 1
			if enemy.enemy_kind in ["interceptor","mine_layer"]: return false
	return sky_count < MAX_SKY_ENEMIES and shooters < 2


func series_kind_info(kind: String) -> Dictionary:
	var result: Dictionary = SeriesScript.info(kind).duplicate() if SeriesScript.supports(kind) else {"series":1,"label":ENEMY_SERIES_LABEL,"flying":kind in FLYING_ENEMIES}
	result["series_label"] = str(EncounterScript.get_series_definition(int(result.series)).get("label",ENEMY_SERIES_LABEL))
	return result


func _is_flying_kind(kind: String) -> bool:
	return bool(SeriesScript.info(kind).get("flying",false)) if SeriesScript.supports(kind) else kind in FLYING_ENEMIES


func _ground_root_y(kind: String) -> float:
	if kind == "cyber_tank": return -0.355
	return -0.055


func _spawn_enemy(kind: String, lane: int, z_position: float) -> Node3D:
	var sky_lane := lane-LANES.size()
	if sky_lane >= 0 and (sky_lane >= SKY_LANES.size() or not _is_flying_kind(kind) or kind == "shield_drone"):
		return null
	var enemy = EnemyScript.new()
	enemy_root.add_child(enemy)
	enemy.configure(kind, lane)
	var x_position: float = LANES[clampi(lane, 0, 3)]
	if kind == "tank":
		x_position += 1.0
	elif kind in ["boss","barrier","beam",BOSS_CARRIER_KIND]:
		x_position = 0.0
	# The segmented deck's actual top is -0.055m. Grounded voxel soles and
	# obstacle bases meet that receiver instead of floating above its shadow.
	var floor_y := 0.0 if _is_flying_kind(kind) else _ground_root_y(kind)
	if sky_lane >= 0:
		x_position = SKY_LANES[sky_lane]
		floor_y = SKY_ROOT_Y
		enemy.set_meta("sky_lane",sky_lane)
		enemy.set_meta("sky_anchor",Vector3(x_position,SKY_ROOT_Y,SKY_HOLD_Z))
		enemy.fire_timer = 1.0
	enemy.position = Vector3(x_position, floor_y, z_position)
	enemy.set_meta("lane_x", x_position)
	enemy.set_meta("runner_speed", speed)
	enemy.set_meta("flythrough_enabled", not training)
	enemy.set_meta("root_motion_velocity", Vector3.ZERO)
	var series_info: Dictionary = series_kind_info(kind)
	enemy.set_meta("enemy_series","SERIES_%02d" % int(series_info.get("series",1)))
	enemy.set_meta("enemy_series_label",str(series_info.get("series_label",ENEMY_SERIES_LABEL)))
	enemy.severed.connect(_on_enemy_severed)
	enemy.damaged.connect(_on_enemy_damaged)
	enemies.append(enemy)
	_set_enemy_action(enemy, "run", 1.0)
	_record_combat("spawn", enemy)
	return enemy


func _start_enemy_entry(enemy, after_action: String = "run", after_duration: float = 1.0) -> void:
	if training or enemy.dead: return
	if SeriesScript.supports(str(enemy.enemy_kind)):
		series_combat.begin_entry(enemy)
		return
	var duration: float = MotionScript.entry_duration(str(enemy.enemy_kind))
	if bool(enemy.get_meta("deployment_carried",false)): duration = DEPLOYMENT_SECONDS
	if duration <= 0.0: return
	var anchor: Vector3 = enemy.position
	if enemy.has_meta("sky_lane"): anchor = enemy.get_meta("sky_anchor")
	elif enemy.enemy_kind in FLYING_ENEMIES:
		anchor.z = -minf(absf(anchor.z),26.0)
	elif enemy.enemy_kind in ["normal","tank","ranged"]:
		var depth_offset: float = float(enemy.get_meta("entry_depth_offset",0.0))
		# Finish the whole pose outside the sword's32m admission plane,
		# including an8m geometry margin. Run approaches from here afterward.
		# Formation followers keep their authored longitudinal separation.
		anchor.z = GROUND_ENTRY_Z+depth_offset
	if bool(enemy.get_meta("boss_escort",false)) and is_instance_valid(boss_enemy):
		anchor = Vector3(boss_enemy.get_meta("entry_anchor",boss_enemy.position))+Vector3(float(enemy.get_meta("escort_side",-1))*3.8,0,-1.5)
		anchor.y = 0.0
		enemy.set_meta("entry_follow_boss",true)
	enemy.set_meta("entry_active",true)
	enemy.set_meta("entry_age",0.0)
	enemy.set_meta("entry_duration",duration)
	enemy.set_meta("entry_anchor",anchor)
	enemy.set_meta("entry_after_action",after_action)
	enemy.set_meta("entry_after_duration",after_duration)
	enemy.reset_entry_material_budget()
	_set_enemy_action(enemy,"entry",duration)
	_apply_enemy_entry_pose(enemy,0.0)
	_record_combat("enemy_entry",enemy,{"duration":duration,"sky":enemy.has_meta("sky_lane")})


func _apply_enemy_entry_pose(enemy, phase: float) -> void:
	if bool(enemy.get_meta("deployment_carried",false)):
		_apply_boss_deployment_pose(enemy,phase)
		return
	if enemy.enemy_kind in FLYING_ENEMIES:
		_apply_flyby_entry_pose(enemy,phase)
		return
	var sample: Dictionary = MotionScript.sample_entry(str(enemy.enemy_kind),int(enemy.lane_index),phase)
	var offset: Vector3 = sample.offset
	var angles: Vector3 = sample.rotation
	var anchor: Vector3 = enemy.get_meta("entry_anchor")
	if bool(enemy.get_meta("entry_follow_boss",false)) and is_instance_valid(boss_enemy):
		anchor = boss_enemy.position+Vector3(float(enemy.get_meta("escort_side",-1))*3.8,0,-1.5)
		anchor.y = 0.0
		enemy.set_meta("entry_anchor",anchor)
	var inward: float = -signf(anchor.x)
	var lateral_limit: float = minf(absf(anchor.x)*0.40,1.0)
	offset.x = inward*clampf(offset.x,-0.10,lateral_limit)
	angles.y *= inward if not is_zero_approx(inward) else 1.0
	angles.z *= inward
	if enemy.enemy_kind not in FLYING_ENEMIES:
		angles.x = 0.0
		angles.z = 0.0
	# Root stays upright at its original ground/sky height. Real rigid poses
	# carry the lateral/vertical motion, so detached chunks never follow a bank.
	enemy.position = anchor+Vector3(0,0,offset.z)
	enemy.set_action("entry",phase)
	enemy.set_entry_visibility(MotionScript.entry_visibility(str(enemy.enemy_kind),phase))
	var basis := Basis.from_euler(angles)
	var pivot := Vector3(0,2.18,0)
	var entry_pose := Transform3D(basis,Vector3(offset.x,offset.y,0)+pivot-basis*pivot)
	enemy._rig.transform = entry_pose*enemy._rig.transform
	if enemy.enemy_kind == "tank" and phase >= 0.38 and not bool(enemy.get_meta("entry_impact_done",false)):
		enemy.set_meta("entry_impact_done",true)
		_actor_landing_impact(enemy,0.28)
	elif enemy.enemy_kind == "normal" and phase >= 0.34 and not bool(enemy.get_meta("entry_impact_done",false)):
		enemy.set_meta("entry_impact_done",true)
		audio.play_event("boss_release",0.32)


func _apply_flyby_entry_pose(enemy, phase: float) -> void:
	var p: float = clampf(phase,0.0,1.0)
	var anchor: Vector3 = enemy.get_meta("entry_anchor")
	if bool(enemy.get_meta("entry_follow_boss",false)) and is_instance_valid(boss_enemy):
		anchor = boss_enemy.position+Vector3(float(enemy.get_meta("escort_side",-1))*3.8,0,-1.5)
		anchor.y = 0.0
		enemy.set_meta("entry_anchor",anchor)
	var side: float = signf(anchor.x) if not is_zero_approx(anchor.x) else (-1.0 if int(enemy.lane_index)%2 == 0 else 1.0)
	var pose: Dictionary = MotionScript.sample_flyby(str(enemy.enemy_kind),anchor,side,p)
	enemy.position = pose.position
	enemy.set_action("entry",p)
	var basis := Basis.from_euler(pose.rotation)
	var pivot := Vector3(0,2.18,0)
	enemy._rig.transform = Transform3D(basis,pivot-basis*pivot)*enemy._rig.transform
	_apply_flyby_hardware(enemy,p)
	if p >= 0.12 and not bool(enemy.get_meta("flyby_cue_done",false)):
		enemy.set_meta("flyby_cue_done",true)
		audio.play_event("flyby",1.0 if enemy.enemy_kind == "interceptor" else 0.8)


func _apply_flyby_hardware(enemy, phase: float) -> void:
	var kind: String = enemy.enemy_kind
	if kind not in ["missile_drone","shield_drone","mine_layer"]: return
	for part in [1,2]:
		var sign := -1.0 if part == 1 else 1.0
		var pivot: Vector3
		var angles: Vector3
		match kind:
			"missile_drone":
				var delay := 0.075*float(part-1)
				var open: float = MotionScript._entry_pulse(phase,0.54+delay,0.70+delay,0.91+delay)
				pivot = Vector3(sign*0.60,2.12,0)
				angles = Vector3(-0.27*open,sign*0.24*open,sign*0.38*open)
			"shield_drone":
				var flare: float = MotionScript._entry_pulse(phase,0.30,0.50,0.78)
				pivot = Vector3(sign*0.30,2.24,-0.05)
				angles = Vector3(0,sign*0.43*flare,-sign*0.24*flare)
			_:
				var delay := 0.065*float(part-1)
				var extend: float = MotionScript._entry_pulse(phase,0.58+delay,0.74+delay,0.92+delay)
				pivot = Vector3(sign*0.40,2.16,-0.17)
				angles = Vector3(0.26*extend,sign*0.34*extend,sign*0.23*extend)
		var part_basis := Basis.from_euler(angles)
		enemy._parts[part].transform *= Transform3D(part_basis,pivot-part_basis*pivot)


func _finish_enemy_entry(enemy) -> void:
	if not bool(enemy.get_meta("entry_active",false)) or enemy.dead: return
	enemy.set_meta("entry_age",float(enemy.get_meta("entry_duration",1.0)))
	_apply_enemy_entry_pose(enemy,1.0)
	enemy.set_meta("entry_age",float(enemy.get_meta("entry_duration",1.0)))
	enemy.set_meta("entry_active",false)
	enemy.set_entry_visibility(1.0)
	enemy.reset_entry_material_budget()
	var action: String = str(enemy.get_meta("entry_after_action","run"))
	_set_enemy_action(enemy,action,float(enemy.get_meta("entry_after_duration",1.0)))
	if action == "run": enemy.set_action("run",fmod(enemy.age*2.2,1.0))
	_record_combat("enemy_entry_complete",enemy,{"sky":enemy.has_meta("sky_lane")})


func _update_enemy_entry(enemy, sim_dt: float) -> void:
	var before: Vector3 = enemy.position
	var duration: float = float(enemy.get_meta("entry_duration",1.0))
	var previous_age: float = float(enemy.get_meta("entry_age",0.0))
	if bool(enemy.get_meta("deployment_carried",false)) and not _deployment_corridor_open():
		# Respect actual roof clearance even if a long frame delays the opening.
		# An early cut releases the clamps at once and holds the fall above the roof.
		sim_dt = 0.0 if enemy.has_meta("deployment_release_age") else minf(sim_dt,maxf(0.0,DEPLOYMENT_APPROACH_SECONDS-previous_age))
	var age: float = minf(duration,previous_age+sim_dt)
	var phase: float = clampf(age/maxf(duration,0.001),0.0,1.0)
	enemy.set_meta("entry_age",age)
	enemy.set_meta("action_time",age)
	enemy.set_meta("action_phase",phase)
	enemy.set_meta("combat_phase",phase)
	_apply_enemy_entry_pose(enemy,phase)
	enemy.pulse_warning(0.0)
	if phase >= 1.0: _finish_enemy_entry(enemy)
	enemy.set_meta("root_motion_velocity",(enemy.position-before)/maxf(sim_dt,0.00001))


func _release_boss_payload(enemy, release_age: float) -> void:
	if enemy.has_meta("deployment_release_age") or enemy.dead: return
	enemy.set_meta("deployment_release_age",release_age)
	enemy.set_meta("deployment_release_z",enemy.position.z)
	enemy.set_meta("deployment_release_rig",enemy._rig.transform)
	enemy.set_meta("deployment_release_phase",0.56*minf(1.0,release_age/DEPLOYMENT_RELEASE_SECONDS))
	enemy.set_meta("entry_duration",minf(DEPLOYMENT_SECONDS,release_age+DEPLOYMENT_FALL_SECONDS+DEPLOYMENT_SETTLE_SECONDS))
	if is_instance_valid(boss_carrier):
		boss_carrier.set_meta("carrier_depart_age",float(boss_carrier.get_meta("carrier_age",0.0)))
		boss_carrier.set_meta("carrier_depart_origin",boss_carrier.position)
		boss_carrier.set_meta("carrier_depart_angles",boss_carrier._rig.basis.get_euler())
	audio.play_event("boss_release",1.4)
	_record_combat("boss_payload_release",enemy,{"early":release_age < DEPLOYMENT_RELEASE_SECONDS})


func _apply_boss_deployment_pose(enemy, phase: float) -> void:
	var age: float = float(enemy.get_meta("entry_age",0.0))
	var anchor: Vector3 = enemy.get_meta("entry_anchor")
	var force_end: bool = phase >= 1.0
	if not enemy.has_meta("deployment_release_age"):
		var supported: bool = is_instance_valid(boss_carrier) and not boss_carrier.dead
		if supported:
			var supports: Dictionary = boss_carrier.get_carrier_hanger_state()
			supported = bool(supports.connected[0]) and bool(supports.connected[1])
		if age >= DEPLOYMENT_RELEASE_SECONDS or not supported or force_end:
			_release_boss_payload(enemy,age)
	if not enemy.has_meta("deployment_release_age"):
		enemy.set_action("entry",0.56*age/DEPLOYMENT_RELEASE_SECONDS)
		var supports: Dictionary = boss_carrier.get_carrier_hanger_state()
		var mid: Vector3 = (Vector3(supports.world_positions[0])+Vector3(supports.world_positions[1]))*0.5
		var rig: Transform3D = enemy._rig.transform
		rig.basis = boss_carrier._rig.basis
		var mount: Vector3 = rig*DEPLOYMENT_MOUNT_POINT
		enemy.position = Vector3(anchor.x,anchor.y,mid.z-mount.z)
		rig.origin += Vector3(mid.x-enemy.position.x-mount.x,mid.y-enemy.position.y-mount.y,0)
		enemy._rig.transform = rig
		return
	var release_age: float = float(enemy.get_meta("deployment_release_age"))
	var fall: float = clampf((age-release_age)/DEPLOYMENT_FALL_SECONDS,0.0,1.0)
	if force_end: fall = 1.0
	var landed: bool = fall >= 1.0
	var body_phase: float
	if landed:
		body_phase = lerpf(0.72,1.0,clampf((age-release_age-DEPLOYMENT_FALL_SECONDS)/DEPLOYMENT_SETTLE_SECONDS,0.0,1.0))
	else:
		body_phase = lerpf(float(enemy.get_meta("deployment_release_phase",0.56)),0.72,fall)
	if force_end: body_phase = 1.0
	enemy.set_action("entry",body_phase)
	var released: Transform3D = enemy.get_meta("deployment_release_rig")
	enemy.position = Vector3(anchor.x,anchor.y,lerpf(float(enemy.get_meta("deployment_release_z")),anchor.z,smoothstep(0.0,1.0,fall)))
	if not landed:
		var rig: Transform3D = enemy._rig.transform
		rig.origin = released.origin.lerp(rig.origin,fall*fall)
		rig.basis = Basis(released.basis.get_rotation_quaternion().slerp(rig.basis.get_rotation_quaternion(),smoothstep(0.0,1.0,fall)))
		enemy._rig.transform = rig
	if landed and not bool(enemy.get_meta("deployment_landed",false)):
		enemy.set_meta("deployment_landed",true)
		_actor_landing_impact(enemy,1.0)
		_record_combat("boss_payload_landed",enemy)


func _actor_landing_impact(enemy, intensity: float) -> void:
	var point := Vector3(enemy.position.x,0.08,enemy.position.z)
	for side in [-1.0,1.0]:
		_spawn_blast(point+Vector3(side*(1.1 if intensity >= 1.0 else 0.7),0,0.25),0.85*intensity,false,true)
	if intensity >= 1.0:
		_spawn_blast(point+Vector3(0,0.25,0),1.35,true,true)
		_spawn_impact(point,"launch",1.7)
	landing_impact_age = 0.0
	landing_impact_strength = intensity
	shake = maxf(shake,intensity*0.9)
	audio.play_event("heavy_land",intensity*1.5)


func _begin_deployment_fade(enemy) -> void:
	enemy.set_meta("deployment_fade_age",0.0)
	enemy.set_entry_visibility(0.0)


func _update_deployment_fade(enemy, sim_dt: float) -> void:
	if not enemy.has_meta("deployment_fade_age"): return
	if enemy.dead:
		enemy.remove_meta("deployment_fade_age")
		return
	if sim_dt <= 0.0: return
	var age: float = minf(DEPLOYMENT_FADE_SECONDS,float(enemy.get_meta("deployment_fade_age"))+sim_dt)
	if is_equal_approx(age,DEPLOYMENT_FADE_SECONDS):
		enemy.set_entry_visibility(1.0)
		enemy.remove_meta("deployment_fade_age")
	else:
		enemy.set_meta("deployment_fade_age",age)
		enemy.set_entry_visibility(smoothstep(0.0,DEPLOYMENT_FADE_SECONDS,age))


func _update_carrier_actor(enemy, sim_dt: float) -> void:
	var before: Vector3 = enemy.position
	var previous_age: float = float(enemy.get_meta("carrier_age",0.0))
	if not enemy.dead and not enemy.has_meta("carrier_depart_age") and not _deployment_corridor_open():
		sim_dt = minf(sim_dt,maxf(0.0,DEPLOYMENT_APPROACH_SECONDS-previous_age))
	var age: float = previous_age+sim_dt
	enemy.set_meta("carrier_age",age)
	if enemy.dead:
		var plume = enemy.get_node_or_null("CarrierThrust")
		if is_instance_valid(plume): plume.visible = false
		var death_age: float = float(enemy.get_meta("carrier_death_age",0.0))+sim_dt
		enemy.set_meta("carrier_death_age",death_age)
		enemy.position += Vector3(0,-death_age*2.0,16.0)*sim_dt
		if death_age > 2.8 or enemy.position.z > 12.0:
			enemies.erase(enemy)
			enemy.queue_free()
			return
	else:
		var previous_angles: Vector3 = enemy._rig.basis.get_euler()
		enemy.set_action("carrier",0.0)
		if not enemy.has_meta("carrier_depart_age") and (not is_instance_valid(boss_enemy) or boss_enemy.dead or not bool(boss_enemy.get_meta("entry_active",false))):
			enemy.set_meta("carrier_depart_age",age)
			enemy.set_meta("carrier_depart_origin",enemy.position)
			enemy.set_meta("carrier_depart_angles",previous_angles)
		if enemy.has_meta("carrier_depart_age"):
			var depart: float = maxf(0.0,age-float(enemy.get_meta("carrier_depart_age")))
			var origin: Vector3 = enemy.get_meta("carrier_depart_origin")
			var origin_angles: Vector3 = enemy.get_meta("carrier_depart_angles",Vector3.ZERO)
			var unload := smoothstep(0.0,0.52,depart)
			var retreat := clampf((depart-0.50)/3.30,0.0,1.0)
			var bank := MotionScript._entry_pulse(depart,0.44,0.94,2.70)
			enemy.position = origin+Vector3(-0.72*bank,2.15*unload+11.5*retreat*retreat,-1.2*unload-280.0*retreat*retreat)
			var angles := origin_angles*(1.0-unload)+Vector3(-0.21*unload*(1.0-retreat),0.08*bank,-0.12*bank)
			enemy._rig.transform = Transform3D(Basis.from_euler(angles),Vector3.ZERO)
			enemy.set_carrier_release(smoothstep(0.0,0.65,depart))
			if depart > 4.0:
				enemies.erase(enemy)
				enemy.queue_free()
				return
		else:
			var approach := smoothstep(0.0,DEPLOYMENT_APPROACH_SECONDS,age)
			var descent := smoothstep(DEPLOYMENT_APPROACH_SECONDS,DEPLOYMENT_RELEASE_SECONDS,age)
			var approach_point := DEPLOYMENT_CARRIER_ENTRY.lerp(DEPLOYMENT_DESCENT_START,approach)
			enemy.position = approach_point.lerp(Vector3(0,5.3,-16.0),descent)
			var bank: float = 0.025*sin(age*1.5)*(1.0-descent)
			enemy._rig.transform = Transform3D(Basis.from_euler(Vector3(0.025*(1.0-descent),0,bank)),Vector3.ZERO)
		if age >= float(enemy.get_meta("carrier_next_sound",0.0)):
			audio.play_event("carrier_engine",1.1)
			enemy.set_meta("carrier_next_sound",age+3.1)
		_update_carrier_thrust(enemy,age)
	enemy.set_meta("root_motion_velocity",(enemy.position-before)/maxf(sim_dt,0.00001))


func _update_carrier_thrust(enemy, age: float) -> void:
	var visual = enemy.get_node_or_null("CarrierThrust")
	if visual == null:
		visual = MultiMeshInstance3D.new()
		visual.name = "CarrierThrust"
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.use_colors = true
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE
		instances.mesh = cube
		instances.instance_count = 24
		visual.multimesh = instances
		var material := _material(Color.WHITE,true)
		material.vertex_color_use_as_albedo = true
		visual.material_override = material
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		enemy.add_child(visual)
	var fade_age: float = float(enemy.get_meta("deployment_fade_age",DEPLOYMENT_FADE_SECONDS))
	var visibility: float = smoothstep(0.0,DEPLOYMENT_FADE_SECONDS,fade_age)
	for engine in range(4):
		var live: bool = enemy.carrier_lift_intact(engine)
		var origin := Vector3(-6.55 if engine < 2 else 6.55,1.24,-3.12 if engine%2 == 0 else 3.12)
		for layer in range(6):
			var index: int = engine*6+layer
			if not live:
				visual.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),Vector3.ZERO))
				continue
			var pulse: float = 0.88+0.12*sin(age*53.0+float(engine)*1.3+float(layer)*1.7)
			var width: float = (0.46-float(layer)*0.055)*pulse
			var point: Vector3 = origin+Vector3(sin(age*21.0+layer)*0.045,-float(layer)*0.27,cos(age*25.0+layer)*0.045)
			var basis := Basis.IDENTITY.scaled(Vector3(width,0.42*pulse,width)*visibility)
			visual.multimesh.set_instance_transform(index,enemy._rig.transform*Transform3D(basis,point))
			visual.multimesh.set_instance_color(index,Color(2.0,1.75,1.15).lerp(Color(1.0,0.27,0.035),float(layer)/5.0)*visibility)


func _spawn_boss() -> void:
	if campaign != null and campaign.active:
		campaign.begin_boss()
		return
	_spawn_legacy_boss()


func _spawn_legacy_boss() -> void:
	if boss_spawned:
		return
	victory_timer = -1.0
	# Retiring is a staged visual exit, never a player kill or a sphere that
	# might hit the player, sever the old Boss, or cascade through callbacks.
	_clear_projectiles()
	_clear_blasts()
	for effect in impact_effects:
		if is_instance_valid(effect.node): effect.node.queue_free()
	impact_effects.clear()
	_retire_route_enemies()
	boss_spawned = true
	boss_support_window = 0
	boss_support_side = -1
	boss_enemy = _spawn_enemy("boss", 0, -12.0)
	boss_timer = 3.2
	_prepare_deployment_clearance()
	boss_carrier = _spawn_enemy(BOSS_CARRIER_KIND,0,-26.0)
	boss_carrier.position = DEPLOYMENT_CARRIER_ENTRY
	boss_carrier.set_meta("carrier_age",0.0)
	boss_carrier.set_meta("carrier_next_sound",0.0)
	boss_carrier.set_meta("carrier_role",true)
	boss_enemy.set_meta("deployment_carried",true)
	_start_enemy_entry(boss_enemy,"recover",0.25)
	_begin_deployment_fade(boss_carrier)
	_begin_deployment_fade(boss_enemy)
	for side in [-1,1]:
		var escort = _spawn_enemy("shield_drone",0 if side < 0 else 3,-13.5)
		escort.scale = Vector3.ONE*0.70
		escort.position = Vector3(float(side)*3.8,0,-13.5)
		escort.set_meta("lane_x",escort.position.x)
		escort.set_meta("boss_escort",true)
		escort.set_meta("escort_side",side)
		escort.set_meta("escort_window_seen",0)
		escort.set_meta("encounter_role","boss_escort")
		_start_enemy_entry(escort)
	_record_combat("boss_formation",boss_enemy,{"escorts":2})
	_record_combat("boss_enter", boss_enemy)


func _retire_sky_enemies() -> void:
	for index in range(projectiles.size()-1,-1,-1):
		var source = projectiles[index].source
		if is_instance_valid(source) and source.has_meta("sky_lane"):
			_remove_projectile(index)
	_retire_route_enemies(false,true)


func _retire_route_enemies(escorts_only: bool = false, sky_only: bool = false) -> void:
	var order := 0
	for enemy in enemies.duplicate():
		if not is_instance_valid(enemy): continue
		if escorts_only and not bool(enemy.get_meta("boss_escort",false)): continue
		if sky_only and not enemy.has_meta("sky_lane"): continue
		if enemy.severed.is_connected(_on_enemy_severed): enemy.severed.disconnect(_on_enemy_severed)
		if enemy.damaged.is_connected(_on_enemy_damaged): enemy.damaged.disconnect(_on_enemy_damaged)
		enemy.resolved = true
		enemy._configured = false
		enemy.set_meta("encounter_retired",true)
		enemy.set_process(false)
		enemy.pulse_warning(1.0)
		enemies.erase(enemy)
		retiring_enemies.append({"enemy":enemy,"age":0.0,"delay":float(order)*0.10,"exploded":false,"was_dead":bool(enemy.dead)})
		_record_combat("encounter_retire",enemy,{"boss_cleanup":escorts_only,"sky_cleanup":sky_only})
		order += 1


func _update_retiring_enemies(sim_dt: float, world_scale: float) -> void:
	for index in range(retiring_enemies.size()-1,-1,-1):
		var row: Dictionary = retiring_enemies[index]
		var enemy = row.enemy
		if not is_instance_valid(enemy):
			retiring_enemies.remove_at(index)
			continue
		row.age += sim_dt
		enemy.set_meta("simulation_scale",world_scale)
		enemy.set_meta("runner_speed",speed)
		enemy.set_meta("root_motion_velocity",Vector3(0,0,speed) if sim_dt > 0.0 else Vector3.ZERO)
		enemy.position.z += speed*sim_dt
		if not bool(row.exploded) and float(row.age) >= float(row.delay):
			row.exploded = true
			var point: Vector3 = enemy.get_aim_point()
			enemy.retire_for_encounter(camera)
			if not bool(row.was_dead):
				if SeriesScript.supports(str(enemy.enemy_kind)):
					series_effects.emit_burst(point,int(SeriesScript.info(str(enemy.enemy_kind)).series),0.65,0,false,speed)
				else: _spawn_blast(point,0.65,false)
				audio.play_event("explosion",0.40)
		if float(row.age) >= float(row.delay)+0.45:
			enemy.queue_free()
			retiring_enemies.remove_at(index)


func _clear_retiring_enemies() -> void:
	for row in retiring_enemies:
		if is_instance_valid(row.enemy): row.enemy.queue_free()
	retiring_enemies.clear()


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
	if action == "ranged_fire": enemy.set_meta("burst_shots",0)
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
	if not second and not bool(enemy.get_meta("wave_attack_delay_used",false)):
		duration += float(enemy.get_meta("wave_attack_delay",0.0))
		enemy.set_meta("wave_attack_delay_used",true)
	enemy.set_meta("action_variant", 1 if second else 0)
	if enemy.has_method("set_action_variant"):
		enemy.set_action_variant(1 if second else 0)
	_set_enemy_action(enemy, "windup", duration)
	audio.play_event("windup", 1.2 if enemy.enemy_kind == "tank" else 0.8)


func _ranged_charge_duration(kind: String) -> float:
	match kind:
		"shield_drone": return 1.15
		"interceptor": return 0.52
		"mine_layer": return 0.96
		"missile_drone": return 0.85
	return 0.65


func _ranged_fire_duration(kind: String) -> float:
	return 0.50 if kind == "interceptor" else (0.30 if kind == "mine_layer" else 0.22)


func _ranged_release_phase(kind: String, shot_index: int = 0) -> float:
	return 0.18+float(shot_index)*0.20 if kind == "interceptor" else 0.25


func _ranged_charge_z(enemy: Node3D, sim_dt: float) -> float:
	if enemy.enemy_kind == "shield_drone" or bool(enemy.get_meta("ranged_standoff",false)):
		return minf(-22.0,enemy.position.z+(speed*0.10+0.7)*sim_dt)
	return enemy.position.z+(speed*0.25+2.0)*sim_dt


func _mine_aim_offset(enemy: Node3D, origin: Vector3) -> Vector3:
	return Vector3(clampf((origin.x-enemy.global_position.x)*0.16,-0.18,0.18),clampf((origin.y-2.0)*0.30,-0.10,0.10),0)


func _fire_ranged_payload(enemy, burst_index: int = 0) -> bool:
	# Re-read the actual surviving launch mouths for every burst. Cutting a
	# weapon during its animation cancels the remaining shots from that part.
	var origins: Array[Vector3] = enemy.get_ranged_origins()
	if origins.is_empty():
		_record_combat("disarmed",enemy)
		return false
	match enemy.enemy_kind:
		"interceptor":
			_spawn_projectile(origins[burst_index % origins.size()],"bolt",enemy)
		"mine_layer":
			for origin in origins:
				# Separate approach lines converge inside the player's physical
				# near-body zone; none appears to miss sideways and still hits.
				_spawn_projectile(origin,"mine",enemy,_mine_aim_offset(enemy,origin),0.70)
		_:
			for origin in origins:
				_spawn_projectile(origin,"missile" if enemy.enemy_kind == "missile_drone" else "bolt",enemy)
	audio.play_event("ranged_fire",1.0)
	_record_combat("ranged_fire",enemy,{"burst_index":burst_index,"live_emitters":origins.size()})
	return true


func _update_enemies(sim_dt: float, world_scale: float) -> void:
	for index in range(enemies.size() - 1, -1, -1):
		if index >= enemies.size(): continue
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
		if bool(enemy.get_meta("campaign_staging",false)):
			enemy.set_meta("simulation_scale",0.0)
			continue
		_update_deployment_fade(enemy,sim_dt)
		if bool(enemy.get_meta("carrier_role",false)):
			_update_carrier_actor(enemy,sim_dt)
			continue
		if enemy.dead:
			if SeriesScript.supports(str(enemy.enemy_kind)) and bool(enemy.get_meta("campaign_boss_unit",false)):
				if not bool(enemy.get_meta("series_death_done",false)):
					series_combat.update_death(enemy,sim_dt)
				else:
					enemy.position.z += maxf(18.0,speed)*sim_dt
					if enemy.position.z > 40.0:
						enemy.queue_free()
						enemies.remove_at(index)
				continue
			if enemy == boss_enemy and enemy.has_meta("boss_death_age"):
				_update_boss_death(enemy,sim_dt)
				continue
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
		if SeriesScript.supports(str(enemy.enemy_kind)):
			series_combat.update_actor(enemy,sim_dt,world_scale)
			continue
		if bool(enemy.get_meta("entry_active",false)):
			_update_enemy_entry(enemy,sim_dt)
			continue
		if enemy.enemy_kind == "boss":
			enemy.set_meta("root_motion_velocity", Vector3.ZERO)
			_update_boss(enemy, sim_dt)
			continue
		if bool(enemy.get_meta("boss_escort",false)):
			_update_boss_escort(enemy,sim_dt)
			continue
		if enemy.has_meta("sky_lane"):
			_update_sky_enemy(enemy,sim_dt)
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
				var advance_scale := 0.80 if enemy.enemy_kind == "shield_drone" else (1.12 if enemy.enemy_kind == "interceptor" else (0.62 if enemy.enemy_kind == "mine_layer" else 1.0))
				enemy.position.z += (speed * advance_scale + ENEMY_RUN_SPEED) * sim_dt
				enemy.fire_timer -= sim_dt
				if not enemy.resolved and enemy.position.z >= -13.0:
					_start_melee(enemy)
				elif enemy.enemy_kind in RANGED_ENEMIES and enemy.position.z >= -34.0 and enemy.fire_timer <= 0.0:
					var first_extra: float = float(enemy.get_meta("first_charge_extra",0.0))
					enemy.set_meta("first_charge_extra",0.0)
					enemy.set_meta("ranged_standoff",first_extra > 0.0)
					_set_enemy_action(enemy, "ranged_charge", _ranged_charge_duration(enemy.enemy_kind)+first_extra)
					audio.play_event("ranged_charge", 0.8)
					_record_combat("ranged_charge", enemy)
			"windup":
				enemy.position.z = lerpf(float(enemy.get_meta("action_start_z", -13.0)), -7.2, smoothstep(0.0, 1.0, phase))
				if phase >= 1.0:
					_set_enemy_action(enemy, "strike", MELEE_STRIKE_SECONDS)
					audio.play_event("enemy_swing", 1.15 if enemy.enemy_kind == "tank" else 0.8)
			"strike":
				# The weapon reaches the player's space at the damage phase, from every lane.
				var lunge: float = smoothstep(0.0, MELEE_CONTACT_PHASE, phase)
				enemy.position.z = lerpf(float(enemy.get_meta("action_start_z", -7.2)), -2.2, lunge)
				enemy.position.x = lerpf(float(enemy.get_meta("action_start_x", 0.0)), float(enemy.get_meta("lane_x", 0.0)) * 0.18, lunge)
				if phase >= MELEE_CONTACT_PHASE and not bool(enemy.get_meta("impact_done", false)):
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
				enemy.position.z = _ranged_charge_z(enemy,sim_dt)
				if phase >= 1.0:
					_set_enemy_action(enemy, "ranged_fire", _ranged_fire_duration(str(enemy.enemy_kind)))
			"ranged_fire":
				_update_ranged_fire(enemy,phase)
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


func _update_ranged_fire(enemy, phase: float) -> void:
	if enemy.enemy_kind == "interceptor":
		var shot_index: int = int(enemy.get_meta("burst_shots",0))
		while shot_index < 3 and phase >= _ranged_release_phase("interceptor",shot_index):
			_fire_ranged_payload(enemy,shot_index)
			shot_index += 1
			enemy.set_meta("burst_shots",shot_index)
	elif phase >= _ranged_release_phase(str(enemy.enemy_kind)) and not bool(enemy.get_meta("impact_done",false)):
		enemy.set_meta("impact_done",true)
		_fire_ranged_payload(enemy)
	if phase >= 1.0:
		enemy.fire_timer = 4.2 if enemy.enemy_kind == "shield_drone" else (3.1 if enemy.enemy_kind == "mine_layer" else 2.5)
		_set_enemy_action(enemy,"run",1.0)


func _update_sky_enemy(enemy, sim_dt: float) -> void:
	var before: Vector3 = enemy.position
	var action: String = str(enemy.get_meta("action_state","run"))
	var phase: float = _advance_enemy_action(enemy,sim_dt)
	if action == "exit":
		enemy.position += Vector3(0,0,-12.0)*sim_dt
		if phase >= 1.0:
			enemies.erase(enemy)
			enemy.queue_free()
			return
	elif not enemy.has_attack_limb():
		enemy.resolved = true
		_set_enemy_action(enemy,"exit",1.0)
		_record_combat("sky_disarmed",enemy)
	else:
		var anchor: Vector3 = enemy.get_meta("sky_anchor")
		enemy.position = anchor
		match action:
			"run":
				enemy.fire_timer -= sim_dt
				if enemy.fire_timer <= 0.0:
					_set_enemy_action(enemy,"ranged_charge",_ranged_charge_duration(enemy.enemy_kind))
					audio.play_event("ranged_charge",0.8)
					_record_combat("ranged_charge",enemy)
			"ranged_charge":
				if phase >= 1.0:
					_set_enemy_action(enemy,"ranged_fire",_ranged_fire_duration(str(enemy.enemy_kind)))
			"ranged_fire":
				_update_ranged_fire(enemy,phase)
			"stagger", "recover":
				if phase >= 1.0: _set_enemy_action(enemy,"run",1.0)
	# The runner moves the scenery; keeping this anchor fixed makes the craft
	# fly alongside the player at every speed, without a ground melee lunge.
	var posed_action: String = str(enemy.get_meta("action_state","run"))
	var posed_phase: float = float(enemy.get_meta("action_phase",0.0))
	if posed_action == "run": posed_phase = fmod(enemy.age*2.2,1.0)
	if posed_action == "exit": posed_action = "recover"
	enemy.set_action(posed_action,posed_phase)
	enemy.pulse_warning(float(enemy.get_meta("action_phase",0.0)) if posed_action == "ranged_charge" else 0.0)
	enemy.set_meta("root_motion_velocity",(enemy.position-before)/maxf(sim_dt,0.00001))


func _armed_boss_escort(side: int):
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.dead and bool(enemy.get_meta("boss_escort",false)) and int(enemy.get_meta("escort_side",0)) == side and enemy.has_attack_limb():
			return enemy
	return null


func _update_boss_escort(enemy, sim_dt: float) -> void:
	if not is_instance_valid(boss_enemy) or boss_enemy.dead or victory_timer >= 0.0:
		_retire_route_enemies(true)
		return
	var side: int = int(enemy.get_meta("escort_side",-1))
	enemy.position = boss_enemy.position+Vector3(float(side)*3.8,0,-1.5)
	enemy.set_meta("root_motion_velocity",Vector3.ZERO)
	enemy.set_meta("flythrough_enabled",false)
	var action: String = str(enemy.get_meta("action_state","run"))
	var phase: float = _advance_enemy_action(enemy,sim_dt)
	var window: int = int(boss_enemy.get_meta("escort_support_window",0))
	var window_open: bool = str(boss_enemy.get_meta("action_state","")) == "recover" and window > 0
	match action:
		"run":
			if window_open and window > int(enemy.get_meta("escort_window_seen",0)):
				enemy.set_meta("escort_window_seen",window)
				if int(boss_enemy.get_meta("escort_support_side",0)) == side and enemy.has_attack_limb():
					_set_enemy_action(enemy,"ranged_charge",1.15)
					_record_combat("escort_charge",enemy,{"support_window":window})
		"ranged_charge":
			if not window_open:
				_set_enemy_action(enemy,"recover",0.80)
			elif phase >= 1.0:
				_set_enemy_action(enemy,"ranged_fire",0.30)
		"ranged_fire":
			if window_open and phase >= 0.25 and not bool(enemy.get_meta("impact_done",false)):
				enemy.set_meta("impact_done",true)
				_fire_ranged_payload(enemy)
			if phase >= 1.0 or not window_open:
				_set_enemy_action(enemy,"recover",0.80)
		"recover", "stagger":
			if phase >= 1.0: _set_enemy_action(enemy,"run",1.0)
	enemy.set_action(str(enemy.get_meta("action_state","run")),float(enemy.get_meta("action_phase",0.0)))
	enemy.pulse_warning(phase if action == "ranged_charge" else 0.0)


func _update_boss(enemy, sim_dt: float) -> void:
	var reactor_state: Dictionary = enemy.get_boss_reactor_state() if enemy.has_method("get_boss_reactor_state") else {}
	var connected: int = int(reactor_state.get("connected",2))
	var enraged := connected == 1
	if bool(enemy.get_meta("boss_enraged",false)) != enraged:
		enemy.set_meta("boss_enraged",enraged)
		_record_combat("boss_reactor_phase",enemy,{"connected_reactors":connected,"enraged":enraged})
	var action: String = str(enemy.get_meta("action_state", "recover"))
	var phase: float = _advance_enemy_action(enemy, sim_dt)
	enemy.set_action(action, phase)
	boss_timer = maxf(0.0, float(enemy.get_meta("action_duration", 1.0)) - float(enemy.get_meta("action_time", 0.0)))
	enemy.pulse_warning(phase if action == "boss_windup" else 0.0)
	match action:
		"run", "recover", "stagger":
			if phase >= 1.0:
				enemy.set_meta("escort_support_window",0)
				boss_pattern += 1
				var variant: int = boss_pattern % 3
				enemy.set_meta("action_variant", variant)
				if enemy.has_method("set_action_variant"):
					enemy.set_action_variant(variant)
				_set_enemy_action(enemy, "boss_windup", 1.05 - float(gear - 1) * 0.05 - (0.18 if enraged else 0.0))
				audio.play_event("boss_charge", 1.2)
		"boss_windup":
			if phase >= 1.0:
				_set_enemy_action(enemy, "boss_strike", BOSS_STRIKE_SECONDS)
				audio.play_event("enemy_swing", 1.5)
		"boss_strike":
			if phase >= BOSS_FIRE_PHASE and not bool(enemy.get_meta("impact_done", false)):
				enemy.set_meta("impact_done", true)
				var variant: int = int(enemy.get_meta("action_variant", 0))
				if not enemy.has_attack_limb(variant):
					_record_combat("disarmed", enemy, {"variant": variant})
				elif variant == 1:
					for origin in enemy.get_ranged_origins():
						_spawn_projectile(origin, "missile",enemy)
					audio.play_event("ranged_fire", 1.2)
				else:
					_spawn_projectile(BOSS_SHOCK_ORIGIN, "shock",enemy)
					_spawn_impact(Vector3(0, 0.2, -9.0), "launch", 0.8)
				if enemy.has_attack_limb(variant):
					_record_combat("attack_impact", enemy, {"variant": variant, "projectile": true})
			if phase >= 1.0:
				var recovery := 1.25-float(gear-1)*0.12-(0.18 if enraged else 0.0)
				enemy.set_meta("escort_support_window",0)
				if boss_pattern % 3 == 0:
					var selected_side := boss_support_side
					if _armed_boss_escort(selected_side) == null: selected_side = -selected_side
					if _armed_boss_escort(selected_side) != null:
						boss_support_window += 1
						enemy.set_meta("escort_support_window",boss_support_window)
						enemy.set_meta("escort_support_side",selected_side)
						boss_support_side = -selected_side
						recovery = 2.40
						_record_combat("boss_support_window",enemy,{"support_window":boss_support_window,"side":selected_side})
				_set_enemy_action(enemy,"recover",recovery)


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


func _spawn_projectile(origin: Vector3, kind: String, source: Node3D = null, aim_offset: Vector3 = Vector3.ZERO, speed_multiplier: float = 1.0) -> Node3D:
	if projectiles.size() >= MAX_PROJECTILES:
		return null
	var node = ProjectileScript.new()
	add_child(node)
	node.global_position = origin
	node.configure(kind)
	# Apply the requested reduction to the entire previous launch speed.
	# Once launched, the straight projectile keeps this velocity snapshot.
	var velocity := _projectile_launch_velocity(origin,kind,aim_offset,speed_multiplier)
	node.advance(0.00001, velocity)
	projectiles.append({"node":node, "velocity":velocity, "kind":kind, "source":source, "reflected":false, "age":0.0})
	_record_combat("projectile_spawn", source, {"projectile_kind":kind})
	return node


func _projectile_launch_velocity(origin: Vector3, kind: String, aim_offset: Vector3, speed_multiplier: float) -> Vector3:
	var travel_speed := (speed+(38.0 if kind in ["bolt","needle","buckshot"] else 30.0))*PROJECTILE_SPEED_SCALE*speed_multiplier
	return (PROJECTILE_TARGET+aim_offset-origin).normalized()*travel_speed


func _forecast_projectile_contact(origin: Vector3, kind: String, aim_offset: Vector3 = Vector3.ZERO, speed_multiplier: float = 1.0) -> float:
	var radius := float(ProjectileScript.GeometryScript.get_template(kind).radius)
	return _projectile_flight_contact(origin,_projectile_launch_velocity(origin,kind,aim_offset,speed_multiplier),radius)


func _projectile_flight_contact(origin: Vector3, velocity: Vector3, radius: float) -> float:
	if origin.z < PROJECTILE_TARGET.z and velocity.z <= 0.0: return INF
	var time := maxf(0.0,(PROJECTILE_TARGET.z-origin.z)/maxf(velocity.z,0.00001))
	return time if _projectile_point_touches_player(origin+velocity*time,radius) else INF


func _update_projectiles(sim_dt: float) -> void:
	if sim_dt <= 0.0:
		return
	_update_series_projectile_behaviors(sim_dt)
	var remaining := sim_dt
	var events := 0
	# Each event removes at least one shot or reflects one hostile shot once.
	# Recompute after callbacks: Boss death may synchronously clear the array.
	while not projectiles.is_empty() and events < MAX_PROJECTILE_EVENTS:
		var event: Dictionary = _next_projectile_event(remaining)
		if event.is_empty():
			_advance_projectiles(remaining)
			remaining = 0.0
			break
		var step: float = clampf(float(event.time),0.0,remaining)
		_advance_projectiles(step)
		remaining = maxf(0.0,remaining-step)
		events += 1
		var projectile: Dictionary = event.projectile
		var node: Node3D = projectile.node
		var index := _projectile_index(node)
		if index < 0: continue
		match str(event.kind):
			"miss":
				projectile["player_plane_passed"] = true
				_record_combat("projectile_passed",projectile.source if is_instance_valid(projectile.source) else null,{"projectile_kind":projectile.kind})
			"intercept":
				combat_stats["projectile_interceptions"] = int(combat_stats.get("projectile_interceptions",0))+1
				var point: Vector3 = node.global_position
				_record_combat("projectile_interception",null,{"projectile_kind":projectile.kind,"other_kind":event.other.kind,"world_point":[point.x,point.y,point.z]})
				_detonate_projectile(index,node.global_position)
			"enemy":
				_detonate_projectile(index,event.point,event.target)
			"player":
				var source: Node3D = projectile.source if is_instance_valid(projectile.source) else null
				if _try_guard("projectile",source):
					var incoming: Vector3 = projectile.velocity
					projectile.velocity = -incoming*1.4
					projectile.reflected = true
					node.set_reflected()
					node.advance(0.00001,projectile.velocity)
					combat_stats["projectiles_reflected"] = int(combat_stats.get("projectiles_reflected",0))+1
					_record_combat("projectile_reflected",source,{"projectile_kind":projectile.kind,"reverse_dot":incoming.normalized().dot(projectile.velocity.normalized())})
				else:
					var volley: String = str(node.get_meta("volley_id",""))
					var already_hit: bool = not volley.is_empty() and _volley_damage.has(volley)
					if not volley.is_empty() and not already_hit: _volley_damage[volley] = game_clock+1.5
					_detonate_projectile(index,node.global_position)
					if not already_hit: _hurt(1,"projectile",source)
	if remaining > 0.0:
		_advance_projectiles(remaining)
	for index in range(projectiles.size()-1,-1,-1):
		var projectile: Dictionary = projectiles[index]
		var node: Node3D = projectile.node
		if float(projectile.age) > 9.0 or node.global_position.z < -140.0 or node.global_position.z > 8.0:
			_remove_projectile(index)


func _configure_series_projectile(node: Node3D, behavior: String, options: Dictionary = {}) -> void:
	var index := _projectile_index(node)
	if index < 0: return
	var shot: Dictionary = projectiles[index]
	shot["series_behavior"] = behavior
	shot["series_options"] = options.duplicate()
	shot["launch_velocity"] = Vector3(shot.velocity)
	shot["series_next"] = float(options.get("delay",options.get("interval",0.55)))
	shot["series_emitted"] = 0
	if behavior in ["prime","beacon"]:
		shot.velocity = Vector3.ZERO
	elif behavior == "bend":
		var side := float(options.get("side",signf(node.position.x)))
		if absf(side) < 0.1: side = 1.0
		shot.velocity = Vector3(side*2.8,0.35,4.0).normalized()*Vector3(shot.launch_velocity).length()
	node.set_meta("series_behavior",behavior)


func _update_series_projectile_behaviors(_sim_dt: float) -> void:
	for key in _volley_damage.keys():
		if float(_volley_damage[key]) <= game_clock: _volley_damage.erase(key)
	while _volley_damage.size() > 64: _volley_damage.erase(_volley_damage.keys()[0])
	for shot: Dictionary in projectiles.duplicate():
		if bool(shot.get("reflected",false)) or not shot.has("series_behavior"): continue
		var node: Node3D = shot.get("node")
		if not is_instance_valid(node) or _projectile_index(node)<0: continue
		var behavior: String = shot.series_behavior
		var options: Dictionary = shot.get("series_options",{})
		var age: float = shot.age
		if age < float(shot.get("series_next",0.0)): continue
		match behavior:
			"prime":
				shot.velocity = Vector3(shot.launch_velocity)
				shot.erase("series_behavior")
				audio.play_event("ranged_fire",0.6)
			"bend":
				var target: Vector3 = options.get("target",Vector3(0,1.65,-0.9))
				shot.velocity = (target-node.global_position).normalized()*Vector3(shot.launch_velocity).length()
				shot.erase("series_behavior")
			"beacon":
				var source: Node3D = shot.get("source") if is_instance_valid(shot.get("source")) else null
				if source == null or source.dead or not source.has_attack_limb():
					series_effects.emit_burst(node.global_position,3,0.3,1)
					_remove_projectile(_projectile_index(node))
					continue
				if projectiles.size() < MAX_PROJECTILES:
					_spawn_projectile(node.global_position,"bolt",source)
					shot.series_emitted = int(shot.series_emitted)+1
					audio.play_event("ranged_fire",0.65)
				shot.series_next = age+maxf(0.2,float(options.get("interval",0.55)))
				if int(shot.series_emitted) >= int(options.get("shots",2)):
					series_effects.emit_burst(node.global_position,3,0.25,1)
					_remove_projectile(_projectile_index(node))


func _projectile_index(node: Node3D) -> int:
	for index in range(projectiles.size()):
		if projectiles[index].node == node: return index
	return -1


func _advance_projectiles(sim_dt: float) -> void:
	if sim_dt <= 0.0: return
	for projectile: Dictionary in projectiles:
		projectile.age = float(projectile.age)+sim_dt
		var node: Node3D = projectile.node
		node.global_position += Vector3(projectile.velocity)*sim_dt
		node.advance(sim_dt,projectile.velocity)


func _projectile_pair_time(a: Dictionary, b: Dictionary, sim_dt: float) -> float:
	# Relative-motion sphere sweep over the SAME time interval. A spatial
	# intersection of two unrelated paths would also catch near misses in time.
	var offset: Vector3 = a.node.global_position-b.node.global_position
	var delta: Vector3 = (Vector3(a.velocity)-Vector3(b.velocity))*sim_dt
	var radius: float = float(a.node.collision_radius)+float(b.node.collision_radius)
	var c: float = offset.length_squared()-radius*radius
	if c <= 0.0: return 0.0
	var aa: float = delta.length_squared()
	if aa <= 0.000000000001: return INF
	var bb: float = offset.dot(delta)
	var discriminant: float = bb*bb-aa*c
	if discriminant < 0.0: return INF
	var fraction: float = (-bb-sqrt(discriminant))/aa
	return fraction*sim_dt if fraction >= 0.0 and fraction <= 1.0 else INF


func _projectile_player_plane_time(projectile: Dictionary, sim_dt: float) -> float:
	if bool(projectile.reflected) or bool(projectile.get("player_plane_passed",false)): return INF
	var from_z: float = float(projectile.node.global_position.z)
	var delta_z: float = float(projectile.velocity.z)*sim_dt
	if from_z+delta_z < -0.90001: return INF
	return clampf((-0.9-from_z)/maxf(delta_z,0.00001),0.0,1.0)*sim_dt


func _projectile_touches_player(projectile: Dictionary, time: float) -> bool:
	var point: Vector3 = projectile.node.global_position+Vector3(projectile.velocity)*time
	return _projectile_point_touches_player(point,float(projectile.node.collision_radius))


func _projectile_point_touches_player(point: Vector3, radius: float) -> bool:
	var body_point := Vector2(0,clampf(point.y,0.9,1.65))
	var reach := 0.31+radius
	return Vector2(point.x,point.y).distance_squared_to(body_point) <= reach*reach


func _next_projectile_event(sim_dt: float) -> Dictionary:
	var earliest := sim_dt+1.0
	var event: Dictionary = {}
	# Interceptions win an exact tie with a player-plane hit. Both shots share
	# one timeline, regardless of their order in the projectiles array.
	for projectile: Dictionary in projectiles:
		if not bool(projectile.reflected): continue
		for other: Dictionary in projectiles:
			if bool(other.reflected): continue
			var time: float = _projectile_pair_time(projectile,other,sim_dt)
			if time <= sim_dt and time < earliest:
				earliest = time
				event = {"kind":"intercept","time":time,"projectile":projectile,"other":other}
	for projectile: Dictionary in projectiles:
		if not bool(projectile.reflected): continue
		var node: Node3D = projectile.node
		var from: Vector3 = node.global_position
		var to: Vector3 = from+Vector3(projectile.velocity)*sim_dt
		for enemy in enemies:
			if not is_instance_valid(enemy) or enemy.dead: continue
			var hit: Dictionary = enemy.trace_projectile(from,to,node.collision_radius)
			var time: float = float(hit.get("fraction",2.0))*sim_dt
			if bool(hit.get("hit",false)) and time >= 0.0 and time <= sim_dt and time < earliest-PROJECTILE_EVENT_TIE_EPSILON:
				earliest = time
				event = {"kind":"enemy","time":time,"projectile":projectile,"target":enemy,"point":hit.point}
	for projectile: Dictionary in projectiles:
		var time := _projectile_player_plane_time(projectile,sim_dt)
		if time <= sim_dt and time < earliest-PROJECTILE_EVENT_TIE_EPSILON:
			earliest = time
			var touches := _projectile_touches_player(projectile,time)
			event = {"kind":"player" if touches else "miss","time":time,"projectile":projectile}
	return event


func _detonate_projectile(index: int, point: Vector3, target: Node3D = null) -> void:
	var projectile: Dictionary = projectiles[index]
	var friendly: bool = bool(projectile.reflected)
	var payloads: Array[Dictionary] = [{"kind":projectile.kind,"point":point,"target":target,"friendly":friendly,"was_reflected":friendly,"chain_depth":0}]
	# Claim the entire chain before material callbacks: the first explosion can
	# kill the Boss, which synchronously clears all still-active projectiles.
	_remove_projectile(index)
	var cursor := 0
	while friendly and cursor < payloads.size() and payloads.size() < MAX_PROJECTILES:
		var parent: Dictionary = payloads[cursor]
		cursor += 1
		var radius: float = float(REFLECTED_BLAST_RADII.get(str(parent.kind),0.90))
		for other_index in range(projectiles.size()-1,-1,-1):
			var other: Dictionary = projectiles[other_index]
			if bool(other.reflected): continue
			var other_node: Node3D = other.node
			var reach: float = radius+float(other_node.collision_radius)
			if Vector3(parent.point).distance_squared_to(other_node.global_position) > reach*reach: continue
			payloads.append({"kind":other.kind,"point":other_node.global_position,"target":null,"friendly":true,"was_reflected":false,"chain_depth":int(parent.chain_depth)+1})
			_remove_projectile(other_index)
			combat_stats["projectile_chain_detonations"] = int(combat_stats.get("projectile_chain_detonations",0))+1
	for payload: Dictionary in payloads:
		_apply_projectile_explosion(payload)


func _apply_projectile_explosion(payload: Dictionary) -> void:
	var kind: String = str(payload.kind)
	var point: Vector3 = payload.point
	var target: Node3D = payload.target if is_instance_valid(payload.target) else null
	var reflected: bool = bool(payload.friendly)
	var strength := 1.35 if kind == "missile" else (1.20 if kind == "mine" else (1.0 if kind == "shock" else 0.75))
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
			hit_stop = maxf(strongest_stop,0.065 if kind in ["missile","mine"] else 0.045)
			shake = maxf(shake,0.72)
			_feedback_contact(point,1.0,"blast")
	_record_combat("projectile_explosion",target,{"projectile_kind":kind,"reflected":reflected,"was_reflected":bool(payload.was_reflected),"chain_reaction":int(payload.chain_depth)>0,"chain_depth":int(payload.chain_depth),"blast_radius":radius,"hit_target_count":hit_count,"removed_total":removed_total,"world_point":[point.x,point.y,point.z]})


func _remove_projectile(index: int) -> void:
	projectiles[index].node.queue_free()
	projectiles.remove_at(index)


func _clear_projectiles() -> void:
	for projectile in projectiles:
		if is_instance_valid(projectile.node):
			projectile.node.queue_free()
	projectiles.clear()


func _spawn_blast(point: Vector3, strength: float, reflected_impact: bool = false, stationary: bool = false) -> Node3D:
	while blasts.size() >= MAX_BLASTS:
		var oldest: Node3D = blasts.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var blast = BlastScript.new()
	add_child(blast)
	blast.global_position = point
	blast.configure(strength,0.0 if training or stationary else speed,reflected_impact)
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
	if enemy.enemy_kind == BOSS_CARRIER_KIND:
		var plume = enemy.get_node_or_null("CarrierThrust")
		if is_instance_valid(plume): plume.visible = false
		_spawn_blast(enemy.get_aim_point(),1.7,true,true)
		audio.play_event("explosion_reflected",1.2)
		_feedback_contact(point,1.0,"blast")
		shake = maxf(shake,0.8)
		if is_instance_valid(boss_enemy) and not boss_enemy.dead and bool(boss_enemy.get_meta("entry_active",false)):
			_release_boss_payload(boss_enemy,float(boss_enemy.get_meta("entry_age",0.0)))
		_record_combat("carrier_destroyed",enemy,{"removed":removed_count})
		return
	kills += 1
	combat_stats["kills"] = kills
	_record_combat("severed", enemy, {"removed": removed_count})
	combo += 1
	score += (150 + mini(removed_count, 100)) * gear
	hit_stop = 0.10 if enemy.enemy_kind == "boss" or bool(enemy.get_meta("campaign_boss_unit",false)) else (0.075 if enemy.enemy_kind == "tank" else 0.055)
	shake = 0.9
	kill_pulse = 1.0
	_feedback_contact(point, 1.0, "kill")
	if sword.has_method("impact"):
		sword.impact(1.6)
	audio.play_event("kill", 0.8 + float(gear) * 0.15)
	if show_timing:
		_notice("关键结构斩断  ×%d" % combo, 0.85)
	if bool(enemy.get_meta("campaign_boss_unit",false)) and SeriesScript.supports(str(enemy.enemy_kind)):
		series_combat.begin_death(enemy)
		var survivors := false
		for member in enemies:
			if is_instance_valid(member) and member != enemy and not member.dead and bool(member.get_meta("campaign_boss_unit",false)):
				survivors = true
		if not survivors: _clear_projectiles()
	elif enemy == boss_enemy:
		_begin_boss_death(enemy)
		_clear_projectiles()
		_retire_route_enemies(true)
		_notice("核心已断 · 失稳爆破", 2.4)


func _begin_boss_death(enemy) -> void:
	if enemy.has_meta("boss_death_age"): return
	enemy.set_meta("entry_active",false)
	enemy.set_meta("boss_death_age",0.0)
	enemy.set_meta("boss_death_anchor",enemy.position)
	enemy.set_meta("boss_death_rig",enemy._rig.transform)
	enemy.set_meta("boss_death_hold",true)
	enemy.set_meta("boss_death_stationary",true)
	enemy.set_meta("boss_death_exploded",false)
	enemy.set_meta("boss_death_cracks",0)
	enemy.set_meta("root_motion_velocity",Vector3.ZERO)
	victory_timer = BOSS_DEATH_HOLD+BOSS_DEATH_TAIL
	_record_combat("boss_death_hold",enemy)


func _update_boss_death(enemy, sim_dt: float) -> void:
	var age: float = float(enemy.get_meta("boss_death_age",0.0))+sim_dt
	var retained_pose: Transform3D = enemy.get_meta("boss_death_rig")
	enemy.set_meta("boss_death_age",age)
	enemy.position = enemy.get_meta("boss_death_anchor")
	enemy.set_meta("root_motion_velocity",Vector3.ZERO)
	var cracks: int = int(enemy.get_meta("boss_death_cracks",0))
	while cracks < 2 and age >= 0.42*float(cracks+1):
		var point: Vector3 = enemy.to_global(retained_pose*Vector3(-1.08 if cracks == 0 else 1.08,3.0,0.45))
		_spawn_blast(point,0.40,false,true)
		audio.play_event("explosion",0.45)
		cracks += 1
		enemy.set_meta("boss_death_cracks",cracks)
		_record_combat("boss_death_crack",enemy,{"stage":cracks})
	if age >= BOSS_DEATH_HOLD and not bool(enemy.get_meta("boss_death_exploded",false)):
		enemy.set_meta("boss_death_hold",false)
		enemy.set_meta("boss_death_exploded",true)
		var count := 0
		for piece in enemy.get_children():
			if not piece.get_meta("voxel_piece",false) or piece.is_queued_for_deletion(): continue
			var radial: Vector3 = piece.position-retained_pose*Vector3(0,2.6,0.2)
			var direction: Vector3 = radial.normalized() if radial.length_squared() > 0.0001 else Vector3.UP
			piece.velocity = direction*(7.0+float(count%4)*1.2)+Vector3(0,2.6,1.5)
			piece.spin = Vector3(float(count%3)-1.0,signf(radial.x)*1.8,signf(radial.x)*2.6)
			piece.lifetime = maxf(piece.lifetime,piece.elapsed+BOSS_DEATH_TAIL+0.6)
			count += 1
		for side in [-1.0,0.0,1.0]:
			_spawn_blast(enemy.to_global(retained_pose*Vector3(side*1.05,2.6,0.2)),1.9 if side == 0.0 else 1.05,true,true)
		audio.play_event("explosion_reflected",1.8)
		shake = maxf(shake,0.9)
		_record_combat("boss_death_explosion",enemy,{"true_fragments":count})
	if bool(enemy.get_meta("boss_death_exploded",false)):
		# A full fragment budget may retain real cells in the original body.
		# Move that existing rig gently; never replace it with a restored hull.
		var tail: float = clampf((age-BOSS_DEATH_HOLD)/BOSS_DEATH_TAIL,0.0,1.0)
		var base: Transform3D = enemy.get_meta("boss_death_rig")
		enemy._rig.transform = Transform3D(Basis(Vector3.FORWARD,0.09*tail),Vector3(0,-0.22*tail*tail,0.35*tail))*base


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
		if not is_instance_valid(enemy) or enemy.dead or enemy.resolved or bool(enemy.get_meta("campaign_staging",false)) or camera.is_position_behind(enemy.get_aim_point()):
			continue
		if enemy.has_meta("deployment_fade_age") and not enemy.visible: continue
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
		if kind == BOSS_CARRIER_KIND: target_label = "吊装运兵船 · 可斩"
		if SeriesScript.supports(kind):
			target_label = str(SeriesScript.info(kind).label)
			if action in ["charge","fire","recover","stagger","exit","run","feint"]: time_left = -1.0
			if bool(enemy.get_series_integrity_state().get("vulnerable",false)): target_label += " · 核心暴露"
		if show_timing: target_label = str(series_kind_info(kind).get("series_label",ENEMY_SERIES_LABEL))+" · "+target_label
		var sky: bool = enemy.has_meta("sky_lane")
		var entering: bool = bool(enemy.get_meta("entry_active",false))
		var auxiliary_carrier: bool = kind == BOSS_CARRIER_KIND
		if auxiliary_carrier: time_left = -1.0
		if sky:
			time_left = -1.0
			target_label = "天空 · "+target_label
		if entering:
			time_left = -1.0
			target_label = "入场 · "+target_label
		if training:
			time_left = -1.0
			target_label = "切割靶"
		if not training and enemy.position.z < PLAYER_CUT_MIN_Z and time_left > 2.5:
			continue
		targets.append({"screen": camera.unproject_position(enemy.get_aim_point()), "progress": 0.0 if time_left < 0.0 or sky or entering or auxiliary_carrier else clampf(1.0 - time_left / 1.8, 0.0, 1.0), "kind": kind, "can_cut": enemy.position.z >= PLAYER_CUT_MIN_Z, "label": target_label, "time_left": time_left, "action": action})
	for projectile in projectiles:
		var projectile_node: Node3D = projectile.node
		if bool(projectile.reflected) or projectile_node.position.z < -25.0 or camera.is_position_behind(projectile_node.global_position):
			continue
		var impact_time: float = maxf(0.0, (-projectile_node.position.z - 0.9) / maxf(projectile.velocity.z, 0.1))
		targets.append({"screen": camera.unproject_position(projectile_node.global_position), "progress": clampf(1.0 - impact_time / 1.2, 0.0, 1.0), "kind": "projectile", "can_cut": true, "label": "斩爆 / 反射", "time_left": impact_time})
	hud.set_snapshot({
		"menu_ready":menu_prepared and (campaign == null or campaign.assets_ready),"ui_settings":ui_settings.duplicate(),
		"warm_completed":campaign.warm_completed if campaign != null else 0,"warm_total":campaign.warm_total if campaign != null else 0,
		"campaign_active":campaign.active if campaign != null else false,"campaign_level":campaign.current_level_index+1 if campaign != null else 1,
		"series_label":campaign.series_label() if campaign != null and not campaign.run.is_empty() else "第一系列",
		"campaign_phase":campaign.phase if campaign != null else "menu","run_time":campaign.run_time if campaign != null else elapsed,
		"state": state, "speed": speed, "gear": gear, "health": health,
		"score": score, "kills": kills, "combo": combo, "time": elapsed,
		"duration": route_duration, "slow": slashing, "parry": 1.0 if guard_active else 0.0,
		"cursor": slash_cursor if slashing else get_viewport().get_visible_rect().size * 0.5,
		"blade_from": stroke_from, "blade_to": stroke_to, "blade_alpha": stroke_alpha,
		"blade_path": blade_path,
		"blade_paths": blade_paths,
		"impact_strength": impact_strength, "kill_pulse": kill_pulse, "parry_pulse": parry_pulse,
		"contact_serial": contact_serial, "contact_kind": contact_kind,
		"slash_energy": slash_energy, "impact_direction": impact_direction, "impact_point": impact_point,
		"flash": hurt_flash, "message": message if message_timer > 0.0 else "",
		"boss": boss_spawned, "practice": practice,
		"invincible": invincible,
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


func _prepare_deployment_clearance() -> void:
	if not deployment_clearance.is_empty(): return
	deployment_clearance_age = 0.0
	# Existing gantry members slide laterally out of the lifting corridor.
	# Save exact instance transforms so restarting restores the original route.
	for segment in road_segments:
		for root in segment.get_meta("section_roots",[]):
			for visual in root.get_children():
				if not visual is MultiMeshInstance3D or visual.multimesh == null: continue
				var mesh: MultiMesh = visual.multimesh
				for index in range(mesh.instance_count):
					var original: Transform3D = mesh.get_instance_transform(index)
					var bounds: AABB = original*AABB(Vector3.ONE*-0.5,Vector3.ONE)
					if bounds.end.y < 5.4 or bounds.position.x > 9.4 or bounds.end.x < -9.4: continue
					var side: float = signf(original.origin.x)
					if absf(original.origin.x) < 1.8: side = -1.0 if index%2 == 0 else 1.0
					var distance: float = 16.0 if absf(original.origin.x) < 1.8 else 10.0
					distance = maxf(distance,9.4-bounds.position.x if side > 0.0 else bounds.end.x+9.4)
					deployment_clearance.append({"mesh":mesh,"index":index,"original":original,"offset":Vector3(side*distance,0,0)})
	_record_combat("deployment_gantry_open",null,{"members":deployment_clearance.size()})


func _deployment_corridor_open() -> bool:
	return deployment_clearance.is_empty() or deployment_clearance_age >= DEPLOYMENT_OPEN_SECONDS


func _update_deployment_clearance(sim_dt: float) -> void:
	if _deployment_corridor_open(): return
	# Road updates precede actor updates, so the full reveal frame still has a closed roof.
	for actor in [boss_enemy,boss_carrier]:
		if is_instance_valid(actor) and actor.has_meta("deployment_fade_age"): return
	deployment_clearance_age = minf(DEPLOYMENT_OPEN_SECONDS,deployment_clearance_age+sim_dt)
	var phase: float = smoothstep(0.0,DEPLOYMENT_OPEN_SECONDS,deployment_clearance_age)
	for member: Dictionary in deployment_clearance:
		var transform: Transform3D = member.original
		transform.origin += Vector3(member.offset)*phase
		member.mesh.set_instance_transform(int(member.index),transform)


func _restore_deployment_clearance() -> void:
	for member: Dictionary in deployment_clearance:
		if is_instance_valid(member.mesh): member.mesh.set_instance_transform(int(member.index),member.original)
	deployment_clearance.clear()
	deployment_clearance_age = 0.0


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
	_update_deployment_clearance(sim_dt)
	_update_speed_flow()


func _set_route_section(segment: Node3D, section: int) -> void:
	var roots: Array = segment.get_meta("section_roots",[])
	for index in range(roots.size()):
		roots[index].visible = index == section and int(segment.get_meta("scenery_series_id",1)) == 1
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
	hud.ui_action.connect(_on_ui_action)
	hud.ui_feedback.connect(_on_ui_feedback)
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
