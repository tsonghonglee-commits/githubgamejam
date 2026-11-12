class_name CampaignRuntime
extends RefCounted
## Main-scene adapter for immutable plans. Geometry is warmed before the run;
## only one actor is activated per frame and blocked slots never catch up.

const Director = preload("res://scripts/campaign_director.gd")
const Encounters = preload("res://scripts/encounter_director.gd")
var game: Node3D
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


func configure(owner_game: Node3D) -> void:
	game = owner_game


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
		_update_boss_stage(sim_dt)
		return
	if phase != "combat": return
	if float(game.elapsed) >= float(game.route_duration):
		begin_boss()
		return
	if float(game.elapsed) >= float(game.route_duration)-6.5:
		if not _breather_started:
			_breather_started = true
			spawn_queue.clear()
			_clearance_required = false
			game._clear_projectiles()
			game._retire_route_enemies()
			game._record_combat("campaign_breather",null,{"series":current_series_id,"seconds":6.5})
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
	var enemy: Variant = game._spawn_enemy(str(job.kind),int(job.get("lane",0)),float(job.get("z",-40.0)))
	if not is_instance_valid(enemy):
		if bool(job.get("boss",false)): _boss_pending = maxi(0,_boss_pending-1)
		return
	maximum_activations_per_frame = maxi(maximum_activations_per_frame,1)
	if job.has("position"): enemy.position = job.position
	enemy.set_meta("lane_x",enemy.position.x)
	enemy.set_meta("wave_id",str(job.get("wave_id","campaign_boss")))
	enemy.set_meta("wave_attack_delay",float(job.get("attack_delay",0.0)))
	enemy.set_meta("first_charge_extra",float(job.get("fire_delay",0.0)))
	enemy.set_meta("entry_depth_offset",float(job.get("z_offset",0.0)))
	if bool(job.get("boss",false)):
		_boss_pending = maxi(0,_boss_pending-1)
		_boss_units.append(enemy)
		if bool(job.get("legacy",false)):
			enemy.visible = false
			enemy.set_meta("campaign_staging",true)
			enemy.set_meta("legacy_role",str(job.legacy_role))
		else:
			enemy.set_meta("campaign_boss_unit",true)
			enemy.set_meta("team_index",int(job.get("member_index",0)))
			if not is_instance_valid(game.boss_enemy): game.boss_enemy = enemy
			game._start_enemy_entry(enemy)
	else:
		game._start_enemy_entry(enemy)
	if phase == "boss" and _boss_pending == 0:
		if _legacy_boss: _activate_legacy_formation()
		else: game.series_combat.set_team_members(_boss_units)


func begin_boss() -> void:
	if not active or phase in ["boss","transition","finished"]: return
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
	_boss_pending = members.size()
	for index in range(members.size()):
		var kind: String = str(members[index])
		spawn_queue.append({"kind":kind,"boss":true,"lane":index%4,"z":-40.0,"member_index":index,"position":_boss_position(kind,index)})
	game._record_combat("campaign_boss_stage",null,{"series":current_series_id,"stage":_boss_stage,"members":members.duplicate()})
	var title: String = "四人战术小队" if members.size() == 4 else str(game.series_kind_info(str(members[0])).get("label","守关者"))
	var tip: String = {"ink_master":"斩双腕剑匣连接，掀开护胸","cyber_captain":"先断队长中继架，打乱全队轮攻","cyber_helicopter":"尾旋翼支架失连，会打开机腹装甲","cyber_tank":"切断左右悬挂，让核心护甲错位","cyber_gunship":"斩双升力舱承力颈，暴露内部核心","sea_leviathan":"逐一斩断四足，让巨兽倾倒露腹","empire_dreadnought":"斩外露电容支架，掀开舰艏装甲"}.get(str(members[0]),"")
	var objective := "切断两组机组"
	if not tip.is_empty(): objective += " · "+tip
	game._notice(title+" · "+objective,5.0)


func _update_boss_stage(sim_dt: float) -> void:
	if _legacy_boss or _boss_pending>0 or _boss_units.is_empty(): return
	var complete := true
	var first_live: Node3D = null
	for enemy in _boss_units:
		if not is_instance_valid(enemy): continue
		if not enemy.dead:
			complete = false
			if first_live == null: first_live = enemy
		elif not bool(enemy.get_meta("series_death_done",false)):
			complete = false
	if first_live != null: game.boss_enemy = first_live
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
	return {"active":active,"assets_ready":assets_ready,"preparing":preparing,"phase":phase,"seed":run.get("seed",0),"route":run.get("route",[]),"level":current_level_index,"series":current_series_id,"run_time":run_time,"warm_completed":warm_completed,"warm_total":warm_total,"wave_cursor":wave_cursor,"admitted":admitted_waves,"skipped":skipped_waves,"reserved":spawn_queue.size(),"max_activations_per_frame":maximum_activations_per_frame,"boss_stage":_boss_stage,"boss_pending":_boss_pending}
