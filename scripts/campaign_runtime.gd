class_name CampaignRuntime
extends RefCounted
## Main-scene adapter for immutable plans. Geometry is warmed before the run;
## only one actor is activated per frame and blocked slots never catch up.

const Director = preload("res://scripts/campaign_director.gd")
const Encounters = preload("res://scripts/encounter_director.gd")
const EntryMotion = preload("res://scripts/series_entry_motion.gd")
const BossEnvironment = preload("res://scripts/series_boss_environment.gd")
const CYBER_SQUAD := ["cyber_captain", "cyber_flanker", "cyber_suppressor", "cyber_spotter"]
# Indexed by the production squad order. The two front lines spread wider,
# leaving the two rear silhouettes visible between them from the road.
const CYBER_SLING_RELEASE := [0.45, 0.33, 0.41, 0.37]
const CYBER_SLING_RELEASE_ORDER := [1, 3, 2, 0]
const CYBER_SLING_SKIDS := [Vector3(-0.96,0.86,1.03), Vector3(-0.96,0.86,-0.90), Vector3(0.96,0.86,-0.90), Vector3(0.96,0.86,1.03)]
const CYBER_SLING_LINES := [Vector3(-1.80,-2.05,1.30), Vector3(-0.23,-1.80,-1.08), Vector3(0.23,-1.80,-1.08), Vector3(1.80,-2.05,1.30)]
const CYBER_SLING_HARNESS := Vector3(0,2.20,-0.205)
var game: Node3D
var boss_environment: Node3D
var run: Dictionary = {}
var active: bool = false
var assets_ready: bool = false
var preparing: bool = false
var consumed: bool = false
var pending_start: bool = false
var phase: String = "menu"
var current_level_index: int = 0
var current_series_id: int = 1
var run_time: float = 0.0
var warm_completed: int = 0
var warm_total: int = 0
var spawn_queue: Array[Dictionary] = []
var wave_cursor: int = 0
var skipped_waves: int = 0
var admitted_waves: int = 0
var maximum_activations_per_frame: int = 0
var _last_activation_frame: int = -1
var _next_wave_at: float = 0.0
var _boss_stage: int = -1
var _boss_units: Array = []
var _boss_pending: int = 0
var _legacy_boss: bool = false
var _stage_pause: float = 0.0
var _clearance_required: bool = false
var _clearance_quiet: float = 0.0
var _clearance_recovery: float = 0.0
var _breather_started: bool = false
var _cyber_transport: Node3D
var _cyber_transport_id := 0
var _cyber_sling_cables: Node3D
var _cyber_sling_material: StandardMaterial3D
var _cyber_sling_age := 0.0
var _cyber_sling_running := false


func configure(owner_game: Node3D) -> void:
	game = owner_game
	boss_environment = BossEnvironment.new()
	boss_environment.name = "BossEnvironment"
	game.series_scenery.add_child(boss_environment)
	boss_environment.configure(game)


func prepare_new_run(auto_start: bool = false) -> void:
	pending_start = pending_start or auto_start
	if preparing: return
	preparing = true
	assets_ready = false
	active = false
	phase = "preparing"
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var seed_value: int = rng.randi()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--campaign-seed="):
			seed_value = int(argument.trim_prefix("--campaign-seed="))
	run = Director.build_run(seed_value)
	warm_total = run.catalog.size()
	warm_completed = 0
	call_deferred("_warm_catalog")


func _warm_catalog() -> void:
	var stage: Node3D
	if DisplayServer.get_name() != "headless":
		stage = Node3D.new()
		stage.name = "CampaignPreparation"
		game.add_child(stage)
		var cover: MeshInstance3D = game._box(stage,Vector3(50,30,0.2),Vector3(0,3,-9),game._material(Color("14212b"),true))
		cover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		await game.series_scenery.warm_for_menu()
		await boss_environment.warm_for_menu()
	for kind: String in run.catalog:
		if not is_instance_valid(game) or not game.is_inside_tree(): return
		game.EnemyScript.prewarm_models([kind])
		if stage != null:
			var actor: Node3D = game.EnemyScript.new()
			stage.add_child(actor)
			actor.configure(kind,1)
			if game.SeriesScript.supports(kind):
				game.series_combat.WeaponContact.prepare(actor,game.SeriesScript.integrity_layout(kind))
			actor.position = Vector3(0,-0.055,-14)
			actor.set_process(false)
			actor.set_action("recover",1.0)
			var new_boss: bool = game.SeriesScript.supports(kind) and bool(game.SeriesScript.info(kind).boss)
			if kind not in ["boss","boss_carrier"] and (not game._is_flying_kind(kind) or new_boss):
				actor.set_meta("entry_active",true)
				actor.set_entry_visibility(0.5)
			await RenderingServer.frame_post_draw
			actor.queue_free()
		warm_completed += 1
		await game.get_tree().process_frame
	if stage != null:
		for kind in ["sword_wave","ink_spear","seal","buckshot","needle","beacon","electric_wave","torpedo","plasma_lance","cannon_orb"]:
			var shot: Node3D = game.ProjectileScript.new()
			stage.add_child(shot)
			shot.position = Vector3(0,1.65,-14)
			shot.configure(kind)
			shot.advance(0.01,Vector3.BACK)
		await RenderingServer.frame_post_draw
		stage.queue_free()
	preparing = false
	assets_ready = true
	consumed = false
	phase = "menu"
	print("CAMPAIGN prepared seed=",run.seed," route=",run.route," templates=",warm_completed," (no combat started)")
	if pending_start and is_instance_valid(game) and bool(game.menu_prepared):
		pending_start = false
		game.start_game()


func ensure_ready_for_start() -> bool:
	if preparing or not assets_ready:
		pending_start = true
		if not preparing: prepare_new_run(true)
		return false
	if consumed:
		game.state = "menu"
		game.sword.visible = false
		prepare_new_run(true)
		return false
	return true


func begin_run() -> void:
	active = true
	consumed = true
	pending_start = false
	current_level_index = 0
	current_series_id = 1
	run_time = 0.0
	skipped_waves = 0
	admitted_waves = 0
	_clear_cyber_deployment()
	spawn_queue.clear()
	_boss_units.clear()
	game.series_combat.reset()
	game.series_effects.clear()
	game.series_scenery.force_series(1)
	_begin_level()
	game._record_combat("campaign_start",null,{"seed":run.seed,"route":run.route.duplicate()})


func suspend() -> void:
	active = false
	pending_start = false
	boss_environment.reset()
	_clear_cyber_deployment()
	spawn_queue.clear()
	_boss_units.clear()
	phase = "suspended"


func _level() -> Dictionary:
	return run.levels[current_level_index] if not run.is_empty() else {}


func difficulty_tier() -> int:
	return current_level_index+1


func series_label() -> String:
	return str(Director.get_series_definition(current_series_id).get("label","第一系列"))


func _begin_level() -> void:
	_clear_cyber_deployment()
	boss_environment.reset()
	var level: Dictionary = _level()
	current_series_id = int(level.series_id)
	game.set_meta("current_series_id",current_series_id)
	game.elapsed = 0.0
	game.route_duration = float(level.duration)
	game.wave_index = 0
	game.spawn_timer = 2.8
	game.boss_spawned = false
	game.boss_enemy = null
	game.boss_carrier = null
	game.victory_timer = -1.0
	game.wave_needs_clear = false
	game.wave_quiet_time = 0.0
	game.series_combat.reset()
	wave_cursor = 0
	_next_wave_at = 0.0
	_boss_stage = -1
	_boss_pending = 0
	_boss_units.clear()
	_legacy_boss = false
	_clearance_required = false
	_clearance_quiet = 0.0
	_breather_started = false
	phase = "combat"
	game._notice("第%d关 / 4 · %s" % [current_level_index+1,series_label()],2.8)
	game._record_combat("campaign_level",null,{"level":current_level_index,"series":current_series_id,"tier":difficulty_tier()})


func update_spawning(sim_dt: float) -> void:
	if not active or sim_dt <= 0.0: return
	run_time += sim_dt
	boss_environment.sync_road()
	if phase == "transition":
		if game.series_scenery.transition_ready():
			# The outgoing gantries stay open while they are still on screen.
			# Scenery has hidden the industrial district before we reset its instances.
			if current_series_id == 1: game._restore_deployment_clearance()
			current_level_index += 1
			_begin_level()
		return
	if phase == "boss":
		_drain_activation_queue()
		boss_environment.update(sim_dt)
		update_cyber_deployment(sim_dt)
		_update_boss_stage(sim_dt)
		return
	if phase != "combat": return
	var approach_start := float(game.route_duration)-6.5
	if float(game.elapsed) >= float(game.route_duration):
		begin_boss()
		return
	if float(game.elapsed) >= approach_start:
		if not _breather_started:
			_breather_started = true
			spawn_queue.clear()
			_clearance_required = false
			game._clear_projectiles()
			game._retire_route_enemies()
			game._record_combat("campaign_breather",null,{"series":current_series_id,"seconds":6.5})
		_preview_boss_entry(0,float(game.route_duration)-float(game.elapsed))
		if current_series_id > 1:
			var stages: Array = _level().boss_stages
			if boss_environment.ready_for_early_entry(_boss_mechanism(stages[0])): begin_boss()
		return
	_drain_activation_queue()
	if _clearance_required:
		var occupancy: Dictionary = _live_and_reserved()
		if int(occupancy.ground)+int(occupancy.sky)+int(occupancy.projectiles)>0:
			_clearance_quiet = 0.0
			return
		_clearance_quiet += sim_dt
		if _clearance_quiet < _clearance_recovery: return
		_clearance_required = false
	var plans: Array = _level().plans
	if wave_cursor >= plans.size(): return
	var plan: Dictionary = plans[wave_cursor]
	if float(game.elapsed) < maxf(float(plan.at_seconds),_next_wave_at): return
	if float(game.elapsed) > float(plan.get("latest_seconds",float(plan.at_seconds)+3.0)):
		wave_cursor += 1
		skipped_waves += 1
		game._record_combat("campaign_wave_skipped",null,{"plan":plan.id,"reason":"expired"})
		return
	if str(plan.get("phase","")) == "breather":
		game._clear_projectiles()
		game._retire_route_enemies()
	if bool(plan.get("retire_sky",false)): game._retire_sky_enemies()
	var admission: Dictionary = Encounters.admission(plan,_live_and_reserved())
	if not bool(admission.allowed):
		if float(game.elapsed) > float(plan.get("latest_seconds",float(plan.at_seconds)+3.0)):
			wave_cursor += 1
			skipped_waves += 1
			game._record_combat("campaign_wave_skipped",null,{"plan":plan.id,"reason":admission.reason})
		return
	_enqueue_plan(plan)
	if bool(plan.get("hold_until_clear",false)):
		_clearance_required = true
		_clearance_quiet = 0.0
		_clearance_recovery = float(plan.get("recovery_seconds",0.0))
	wave_cursor += 1
	game.wave_index = wave_cursor
	admitted_waves += 1
	_next_wave_at = float(game.elapsed)+float(plan.interval)
	game._record_combat("wave",null,{"wave_id":plan.id,"count":plan.spawns.size()+plan.sky_spawns.size(),"series":current_series_id,"tier":difficulty_tier()})


func _live_and_reserved() -> Dictionary:
	var counts := {"ground":0,"sky":0,"shooters":0,"heavy":0,"advanced":0,"threat":0.0,"projectiles":game.projectiles.size(),"projectile_reservation":0}
	for enemy in game.enemies:
		if not is_instance_valid(enemy) or enemy.dead or enemy.resolved or bool(enemy.get_meta("encounter_retired",false)): continue
		var profile: Dictionary = Encounters.kind_profile(str(enemy.enemy_kind))
		counts["sky" if enemy.has_meta("sky_lane") else "ground"] += 1
		counts.shooters += int(bool(profile.shooter) and enemy.has_attack_limb())
		counts.heavy += int(profile.heavy)
		counts.advanced += int(profile.advanced)
		counts.threat += float(profile.threat)
	for job in spawn_queue:
		if bool(job.get("boss",false)): continue
		var profile: Dictionary = Encounters.kind_profile(str(job.kind))
		counts["sky" if int(job.get("sky_lane",-1)) >= 0 else "ground"] += 1
		counts.shooters += int(profile.shooter)
		counts.heavy += int(profile.heavy)
		counts.advanced += int(profile.advanced)
		counts.threat += float(profile.threat)
		counts.projectile_reservation += int(profile.projectile_reservation)
	return counts


func _enqueue_plan(plan: Dictionary) -> void:
	var z := -maxf(float(plan.get("minimum_distance",40.0)),float(game.speed)*float(plan.get("approach_seconds",2.0))+float(plan.get("distance_bias",12.0)))
	for item: Dictionary in plan.spawns:
		var job := item.duplicate(true)
		job.merge({"wave_id":plan.id,"z":z+float(item.get("z_offset",0.0)),"sky_lane":-1,"boss":false},true)
		spawn_queue.append(job)
	for item: Dictionary in plan.sky_spawns:
		var job := item.duplicate(true)
		job.merge({"wave_id":plan.id,"z":game.SKY_ENTRY_Z,"lane":4+int(item.sky_lane),"boss":false},true)
		spawn_queue.append(job)


func _drain_activation_queue() -> void:
	if spawn_queue.is_empty() or float(game.hit_stop)>0.0: return
	var frame := Engine.get_process_frames()
	if frame == _last_activation_frame: return
	_last_activation_frame = frame
	var job: Dictionary = spawn_queue.pop_front()
	var returning := bool(job.get("returning_cyber_transport",false)) and is_instance_valid(_cyber_transport)
	var enemy: Node3D = _cyber_transport if returning else game._spawn_enemy(str(job.kind),int(job.get("lane",0)),float(job.get("z",-40.0)))
	if not is_instance_valid(enemy):
		if bool(job.get("boss",false)):
			_boss_pending = maxi(0,_boss_pending-1)
			_finish_boss_activation()
		return
	maximum_activations_per_frame = maxi(maximum_activations_per_frame,1)
	if returning:
		_cyber_transport = null
		enemy.set_meta("campaign_staging",false)
		enemy.visible = true
		game._record_combat("cyber_transport_return",enemy,{"transport_id":_cyber_transport_id})
	if job.has("position"): enemy.position = job.position
	enemy.set_meta("lane_x",enemy.position.x)
	enemy.set_meta("wave_id",str(job.get("wave_id","campaign_boss")))
	enemy.set_meta("wave_attack_delay",float(job.get("attack_delay",0.0)))
	enemy.set_meta("first_charge_extra",float(job.get("fire_delay",0.0)))
	enemy.set_meta("entry_depth_offset",float(job.get("z_offset",0.0)))
	if bool(job.get("boss",false)):
		_boss_pending = maxi(0,_boss_pending-1)
		if bool(job.get("cyber_transport",false)):
			_cyber_transport = enemy
			_cyber_transport_id = enemy.get_instance_id()
			enemy.visible = false
			enemy.set_meta("campaign_staging",true)
		else:
			_boss_units.append(enemy)
			if bool(job.get("legacy",false)):
				enemy.visible = false
				enemy.set_meta("campaign_staging",true)
				enemy.set_meta("legacy_role",str(job.legacy_role))
			else:
				enemy.set_meta("campaign_boss_unit",true)
				enemy.set_meta("team_index",int(job.get("member_index",0)))
				if not is_instance_valid(game.boss_enemy): game.boss_enemy = enemy
				if bool(job.get("cyber_sling_member",false)):
					enemy.visible = false
					enemy.set_meta("campaign_staging",true)
					enemy.set_meta("cyber_sling_attached",true)
				else:
					game._start_enemy_entry(enemy)
		_finish_boss_activation()
	else:
		game._start_enemy_entry(enemy)


func _finish_boss_activation() -> void:
	if phase != "boss" or _boss_pending != 0: return
	if _legacy_boss:
		_activate_legacy_formation()
		return
	game.series_combat.set_team_members(_boss_units)
	if current_series_id == 3 and _boss_stage == 0:
		_start_cyber_deployment()


func begin_boss() -> void:
	if not active or phase in ["boss","transition","finished"]: return
	_clear_cyber_deployment()
	spawn_queue.clear()
	game._clear_projectiles()
	game._clear_blasts()
	game._retire_route_enemies()
	game.boss_spawned = true
	game.boss_enemy = null
	game.boss_carrier = null
	game.victory_timer = -1.0
	phase = "boss"
	_boss_stage = -1
	_boss_units.clear()
	_legacy_boss = current_series_id == 1
	if _legacy_boss:
		_boss_pending = 4
		for item in [
			{"kind":"boss","legacy_role":"payload","position":Vector3(0,-0.055,-12)},
			{"kind":"boss_carrier","legacy_role":"carrier","position":game.DEPLOYMENT_CARRIER_ENTRY},
			{"kind":"shield_drone","legacy_role":"escort_left","position":Vector3(-3.8,0,-13.5)},
			{"kind":"shield_drone","legacy_role":"escort_right","position":Vector3(3.8,0,-13.5)},
		]:
			var job: Dictionary = item.duplicate()
			job.merge({"boss":true,"legacy":true,"lane":0,"z":-40.0})
			spawn_queue.append(job)
	else:
		_begin_boss_stage()


func _activate_legacy_formation() -> void:
	for enemy in _boss_units:
		if not is_instance_valid(enemy): continue
		var role: String = enemy.get_meta("legacy_role","")
		enemy.visible = true
		enemy.set_meta("campaign_staging",false)
		match role:
			"payload":
				game.boss_enemy = enemy
				enemy.set_meta("deployment_carried",true)
			"carrier":
				game.boss_carrier = enemy
				enemy.set_meta("carrier_age",0.0)
				enemy.set_meta("carrier_next_sound",0.0)
				enemy.set_meta("carrier_role",true)
			_:
				var side := -1 if role == "escort_left" else 1
				enemy.scale = Vector3.ONE*0.70
				enemy.set_meta("boss_escort",true)
				enemy.set_meta("escort_side",side)
				enemy.set_meta("escort_window_seen",0)
				enemy.set_meta("encounter_role","boss_escort")
	game.boss_timer = 3.2
	game.boss_support_window = 0
	game.boss_support_side = -1
	game._prepare_deployment_clearance()
	for enemy in _boss_units:
		if not is_instance_valid(enemy): continue
		if enemy == game.boss_enemy:
			game._start_enemy_entry(enemy,"recover",0.25)
			game._begin_deployment_fade(enemy)
		elif enemy == game.boss_carrier:
			game._begin_deployment_fade(enemy)
		else:
			game._start_enemy_entry(enemy)
	game._record_combat("boss_formation",game.boss_enemy,{"escorts":2,"staged_activations":4})
	game._record_combat("boss_enter",game.boss_enemy)


func _boss_position(kind: String, member_index: int) -> Vector3:
	match kind:
		"ink_master": return Vector3(0,-0.055,-16)
		"cyber_helicopter": return Vector3(0,3.0,-22)
		"cyber_tank": return Vector3(0,-0.355,-18)
		"cyber_gunship": return Vector3(0,4.0,-24)
		"sea_leviathan": return Vector3(0,-0.055,-16.8)
		"empire_dreadnought": return Vector3(0,1.74,-28)
	return Vector3([-3.5,-1.2,1.2,3.5][member_index%4],-0.055,[-18.0,-22.0,-24.0,-20.0][member_index%4])


func _preview_boss_entry(stage: int, lead_seconds: float) -> void:
	if current_series_id == 1 or lead_seconds > (2.6 if stage == 0 else 0.65): return
	var stages: Array = _level().boss_stages
	if stage >= stages.size(): return
	boss_environment.preview(current_series_id,_boss_mechanism(stages[stage]),lead_seconds)


func _boss_mechanism(members: Array) -> String:
	return "cyber_delivery" if members == CYBER_SQUAD else str(members[0])


func _begin_boss_stage() -> void:
	_boss_stage += 1
	var stages: Array = _level().boss_stages
	if _boss_stage >= stages.size():
		complete_level()
		return
	game._clear_projectiles()
	game.boss_enemy = null
	_boss_units.clear()
	_stage_pause = 0.0
	var members: Array = stages[_boss_stage]
	var sling_delivery := current_series_id == 3 and members == CYBER_SQUAD
	boss_environment.begin(current_series_id,_boss_mechanism(members))
	_boss_pending = members.size()+int(sling_delivery)
	if sling_delivery:
		spawn_queue.append({"kind":"cyber_helicopter","boss":true,"cyber_transport":true,"lane":0,"z":-56.0})
	for index in range(members.size()):
		var kind: String = str(members[index])
		spawn_queue.append({"kind":kind,"boss":true,"lane":index%4,"z":-40.0,"member_index":index,"position":_boss_position(kind,index),
			"cyber_sling_member":sling_delivery,"returning_cyber_transport":current_series_id == 3 and kind == "cyber_helicopter"})
	game._record_combat("campaign_boss_stage",null,{"series":current_series_id,"stage":_boss_stage,"members":members.duplicate()})
	var title: String = "四人战术小队" if members.size() == 4 else str(game.series_kind_info(str(members[0])).get("label","守关者"))
	var tip: String = {"ink_master":"斩双腕剑匣连接，掀开护胸","cyber_captain":"先断队长中继架，打乱全队轮攻","cyber_helicopter":"尾旋翼支架失连，会打开机腹装甲","cyber_tank":"切断左右悬挂，让核心护甲错位","cyber_gunship":"斩双升力舱承力颈，暴露内部核心","sea_leviathan":"逐一斩断四足，让巨兽倾倒露腹","empire_dreadnought":"斩外露电容支架，掀开舰艏装甲"}.get(str(members[0]),"")
	var objective := "切断两组机组"
	if not tip.is_empty(): objective += " · "+tip
	game._notice(title+" · "+objective,5.0)


func _start_cyber_deployment() -> void:
	if not is_instance_valid(_cyber_transport) or _boss_units.size() != CYBER_SQUAD.size():
		for member in _boss_units:
			if not is_instance_valid(member) or not bool(member.get_meta("cyber_sling_attached",false)): continue
			member.remove_meta("cyber_sling_attached")
			member.set_meta("campaign_staging",false)
			member.visible = true
			game._start_enemy_entry(member)
		return
	_cyber_sling_running = true
	_cyber_sling_age = 0.0
	_cyber_transport.visible = true
	_cyber_transport.set_meta("entry_active",true)
	_cyber_sling_cables = Node3D.new()
	_cyber_sling_cables.name = "CyberSlingCables"
	game.enemy_root.add_child(_cyber_sling_cables)
	_cyber_sling_material = game._material(Color("e6b569"),true)
	_cyber_sling_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var line := CylinderMesh.new()
	line.top_radius = 0.035
	line.bottom_radius = 0.035
	line.height = 1.0
	line.radial_segments = 6
	line.rings = 0
	for index in range(CYBER_SQUAD.size()):
		var cable := MeshInstance3D.new()
		cable.name = "Sling%d" % (index+1)
		cable.mesh = line
		cable.material_override = _cyber_sling_material
		cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_cyber_sling_cables.add_child(cable)
		var member: Node3D = _boss_units[index]
		member.visible = true
		member.set_meta("entry_active",true)
		member.set_meta("series_entry_authored",true)
	update_cyber_deployment(0.0)


func update_cyber_deployment(sim_dt: float) -> void:
	if not _cyber_sling_running: return
	var duration: float = EntryMotion.DURATIONS["cyber_captain"]
	var previous := _cyber_sling_age
	_cyber_sling_age = minf(previous+boss_environment.entry_delta("cyber_delivery",sim_dt),duration)
	var p := _cyber_sling_age/duration
	if not is_instance_valid(_cyber_transport):
		# A cleanup during staging must not strand real squad actors out of combat.
		for index: int in CYBER_SLING_RELEASE_ORDER:
			var member: Node3D = _boss_units[index]
			if is_instance_valid(member) and bool(member.get_meta("cyber_sling_attached",false)):
				_release_cyber_sling_member(member,index,minf(previous,CYBER_SLING_RELEASE[index]*duration))
		_park_cyber_transport()
		return
	var arrive := smoothstep(0.0,0.32,p)
	var brake := smoothstep(0.20,0.32,p)
	var retreat := smoothstep(0.47,0.88,p)
	var reveal := smoothstep(0.0,0.10,p)*(1.0-smoothstep(0.77,0.88,p))
	_cyber_transport.age = _cyber_sling_age
	var road_offset: float = boss_environment.approach_offset("cyber_delivery",p)
	_cyber_transport.position = Vector3(lerpf(-1.45,0.0,arrive)+2.15*retreat,lerpf(7.55,6.35,arrive)+1.30*retreat,-56.0+31.5*arrive-30.0*retreat+road_offset)
	_cyber_transport.set_action("entry",p)
	var bank := Basis.from_euler(Vector3(-0.15*(1.0-arrive)+0.12*(brake-arrive)-0.13*retreat,0.46*(1.0-arrive)-0.62*retreat,-0.13*(arrive-brake)+0.14*retreat))
	var hub := Vector3(0,2.1,0)
	_cyber_transport._rig.transform = Transform3D(bank,hub-bank*hub)
	game.series_combat._keep_entry_clear(_cyber_transport)
	_cyber_transport.set_entry_visibility(reveal)
	_cyber_sling_material.albedo_color.a = reveal
	if previous < duration*0.10 and p >= 0.10:
		game.audio.play_event("entry_cyber",1.15)
		game._record_combat("cyber_transport_arrival",_cyber_transport,{"transport_id":_cyber_transport_id,"sling_count":4})
	boss_environment.observe_pass(_cyber_transport)
	for index: int in CYBER_SLING_RELEASE_ORDER:
		var member: Node3D = _boss_units[index]
		if not is_instance_valid(member) or not bool(member.get_meta("cyber_sling_attached",false)): continue
		_pose_cyber_sling_member(member,index,p,reveal)
		if p >= CYBER_SLING_RELEASE[index]:
			# Main advances the released actor once later this frame. Starting at
			# the preceding clock keeps its authored landing on the group timeline.
			_release_cyber_sling_member(member,index,minf(previous,CYBER_SLING_RELEASE[index]*duration))
	if p >= 0.88: _park_cyber_transport()


func _pose_cyber_sling_member(member: Node3D, index: int, phase_value: float, reveal: float) -> void:
	var skid := 4 if index < 2 else 5
	var top: Vector3 = _cyber_transport.to_global(_cyber_transport._part_pose(skid)*CYBER_SLING_SKIDS[index])
	var swing := sin(_cyber_sling_age*5.4+float(index)*0.94)*(1.0-smoothstep(0.24,0.36,phase_value))
	var line_offset: Vector3 = CYBER_SLING_LINES[index]+Vector3(0.12*swing,0,0.07*swing)
	var bottom: Vector3 = top+line_offset
	var side := -1.0 if index < 2 else 1.0
	member.age = _cyber_sling_age
	member.set_action("entry",phase_value)
	var tilt := Basis.from_euler(Vector3(0.17,-side*0.22,side*0.11+0.10*swing))
	member._rig.transform = Transform3D(tilt,Vector3.ZERO)
	for arm in [1,2]:
		var sign := -1.0 if arm == 1 else 1.0
		var shoulder := Vector3(sign*0.57,2.36,0)
		var arms := Basis.from_euler(Vector3(-0.21,sign*-0.45,sign*0.14))
		member._parts[arm].transform = Transform3D(arms,shoulder-arms*shoulder)
		var hip := Vector3(sign*0.27,1.30,0)
		var legs := Basis.from_euler(Vector3(-0.31+sign*(0.18+0.10*swing),0,sign*0.10))
		var leg_pose := Transform3D(legs,hip-legs*hip)
		member._parts[arm+2].transform = leg_pose
		member._parts[arm+4].transform = leg_pose
	member.global_position = bottom-(member.global_basis*(tilt*CYBER_SLING_HARNESS))
	game.series_combat._keep_entry_clear(member)
	member.set_entry_visibility(reveal)
	bottom = member._rig.to_global(CYBER_SLING_HARNESS)
	var cable := _cyber_sling_cables.get_child(index) as MeshInstance3D
	var direction := top-bottom
	var up := direction.normalized()
	var right := up.cross(Vector3.FORWARD).normalized()
	cable.global_transform = Transform3D(Basis(right,direction,right.cross(up)),(top+bottom)*0.5)
	cable.visible = reveal > 0.0


func _release_cyber_sling_member(member: Node3D, index: int, start_age: float) -> void:
	member.remove_meta("cyber_sling_attached")
	member.set_meta("campaign_staging",false)
	member.set_entry_visibility(1.0)
	member.visible = true
	if is_instance_valid(_cyber_sling_cables): _cyber_sling_cables.get_child(index).visible = false
	game.series_combat.begin_sling_release(member,_boss_position(str(member.enemy_kind),index),start_age)
	game.audio.play_event("guard_release",0.55)
	game._record_combat("cyber_sling_unhook",member,{"transport_id":_cyber_transport_id,"phase":CYBER_SLING_RELEASE[index]})


func _park_cyber_transport() -> void:
	_cyber_sling_running = false
	_clear_cyber_sling_cables()
	if not is_instance_valid(_cyber_transport): return
	_cyber_transport.set_entry_visibility(1.0)
	_cyber_transport.set_meta("entry_active",false)
	_cyber_transport.visible = false
	game._record_combat("cyber_transport_parked",_cyber_transport,{"transport_id":_cyber_transport_id})


func _clear_cyber_sling_cables() -> void:
	if is_instance_valid(_cyber_sling_cables):
		_cyber_sling_cables.visible = false
		_cyber_sling_cables.queue_free()
	_cyber_sling_cables = null
	_cyber_sling_material = null


func _clear_cyber_deployment() -> void:
	_cyber_sling_running = false
	_cyber_sling_age = 0.0
	_clear_cyber_sling_cables()
	if is_instance_valid(_cyber_transport):
		game.enemies.erase(_cyber_transport)
		_cyber_transport.visible = false
		_cyber_transport.queue_free()
	_cyber_transport = null
	_cyber_transport_id = 0


func _update_boss_stage(sim_dt: float) -> void:
	if _legacy_boss or _boss_pending>0 or _boss_units.is_empty() or _cyber_sling_running: return
	var complete := true
	var first_live: Node3D = null
	var remaining_death := 0.0
	for enemy in _boss_units:
		if not is_instance_valid(enemy): continue
		if not enemy.dead:
			complete = false
			if first_live == null: first_live = enemy
		elif not bool(enemy.get_meta("series_death_done",false)):
			complete = false
			remaining_death = maxf(remaining_death,float(enemy.get_meta("series_death_duration",0.0))-float(enemy.get_meta("series_death_age",0.0)))
	if first_live != null:
		game.boss_enemy = first_live
	else:
		_preview_boss_entry(_boss_stage+1,remaining_death+0.65-_stage_pause)
	if not complete: return
	_stage_pause += sim_dt
	if _stage_pause >= 0.65: _begin_boss_stage()


func legacy_boss_finished() -> void:
	if active and phase == "boss" and _legacy_boss:
		game.victory_timer = -1.0
		complete_level()


func complete_level() -> void:
	if phase in ["transition","finished"]: return
	game._record_combat("campaign_level_clear",game.boss_enemy,{"level":current_level_index,"series":current_series_id})
	game._clear_projectiles()
	spawn_queue.clear()
	_clear_cyber_deployment()
	game._retire_route_enemies()
	game.victory_timer = -1.0
	if current_level_index >= run.route.size()-1:
		phase = "finished"
		game._finish(true)
		return
	phase = "transition"
	game.boss_spawned = false
	game.boss_enemy = null
	game.boss_carrier = null
	# A single capped checkpoint recovery supports the longer four-stage run;
	# this is never invoked for a partial Boss group or a debug-key repeat.
	game.health = mini(5,int(game.health)+1)
	var next_series: int = run.route[current_level_index+1]
	game.series_scenery.begin_transition(next_series)
	game._notice("区域突破 · 前往%s" % str(Director.get_series_definition(next_series).label),3.0)


func get_debug_state() -> Dictionary:
	var attached := 0
	for member in _boss_units:
		if is_instance_valid(member) and bool(member.get_meta("cyber_sling_attached",false)): attached += 1
	return {"active":active,"assets_ready":assets_ready,"preparing":preparing,"phase":phase,"seed":run.get("seed",0),"route":run.get("route",[]),"level":current_level_index,"series":current_series_id,"run_time":run_time,"warm_completed":warm_completed,"warm_total":warm_total,"wave_cursor":wave_cursor,"admitted":admitted_waves,"skipped":skipped_waves,"reserved":spawn_queue.size(),"max_activations_per_frame":maximum_activations_per_frame,"boss_stage":_boss_stage,"boss_pending":_boss_pending,
		"cyber_transport_id":_cyber_transport_id,"cyber_transport_visible":is_instance_valid(_cyber_transport) and _cyber_transport.visible,
		"cyber_sling_age":_cyber_sling_age,"cyber_sling_running":_cyber_sling_running,"cyber_sling_attached":attached}
