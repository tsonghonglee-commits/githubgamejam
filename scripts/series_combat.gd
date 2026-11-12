class_name SeriesCombat
extends RefCounted
## Owns new-series actor clocks and damage windows; geometry remains in the
## actual enemy. No HP, restored bodies, fake cuts or global random calls.

const Planner = preload("res://scripts/encounter_director.gd")
const EntryMotion = preload("res://scripts/series_entry_motion.gd")
const WeaponContact = preload("res://scripts/series_attack_contact.gd")
const TEAM_KINDS := ["cyber_captain","cyber_flanker","cyber_suppressor","cyber_spotter"]
const BOSSES := ["ink_master","cyber_captain","cyber_flanker","cyber_suppressor","cyber_spotter","cyber_helicopter","cyber_tank","cyber_gunship","sea_leviathan","empire_dreadnought"]
const MINION_BEHAVIORS := {
	"ink_swordsman":"feint_reverse_double_cut","ink_spear":"spear_throw_then_thrust","ink_talisman":"primed_seal",
	"ink_crane":"mirror_strafe_feathers","cyber_breacher":"side_breach_buckshot_rush","cyber_riot":"hinged_shield_smash",
	"cyber_sniper":"needle_relocate","cyber_drone":"stationary_cuttable_beacon","sea_skimmer":"submerge_leap_thrust",
	"sea_crab":"independent_staggered_claws","sea_eel":"serpentine_electric_tail","sea_ray":"preset_bent_torpedo",
	"empire_walker":"braced_dual_artillery","empire_lancer":"boosted_cross_lane_thrust",
	"empire_sentinel":"split_shield_plasma_charge","empire_fighter":"low_crossing_strafe",
}
var _game: Node
var _definitions: Script
var _team: Array = []
var _team_index := 0
var _team_owner: Node3D
var _team_lock := 0.0
var _relay_broken := false
var _clock := 0.0
var _last_team_frame := -1
var _counters := {"entries":0,"shots":0,"melee_contacts":0,"relay_staggers":0,"deaths":0}


func configure(game: Node) -> void:
	_game = game
	if ResourceLoader.exists("res://scripts/series_archetypes.gd"):
		_definitions = load("res://scripts/series_archetypes.gd")
	reset()


func reset() -> void:
	_team.clear()
	_team_index = 0
	_team_owner = null
	_team_lock = 0.0
	_relay_broken = false
	_clock = 0.0
	_last_team_frame = -1
	_counters = {"entries":0,"shots":0,"melee_contacts":0,"relay_staggers":0,"deaths":0}


func set_team_members(members: Array) -> void:
	for member: Variant in _team:
		if is_instance_valid(member): member.set_meta("series_team_member",false)
	_team.clear()
	for member: Variant in members:
		if not is_instance_valid(member): continue
		var team_member := str(member.enemy_kind) in TEAM_KINDS
		member.set_meta("series_team_member",team_member)
		if team_member: _team.append(member)
	_team_index = 0
	_team_owner = null
	_team_lock = 0.50 if not _team.is_empty() else 0.0
	_relay_broken = false


func _info(enemy: Node3D) -> Dictionary:
	if enemy.has_meta("series_combat_info"): return enemy.get_meta("series_combat_info")
	var kind := str(enemy.enemy_kind)
	var result: Dictionary = _definitions.info(kind).duplicate(true) if _definitions != null else Planner.kind_profile(kind)
	if not result.has("series"):
		result["series"] = 2 if kind.begins_with("ink_") else (3 if kind.begins_with("cyber_") else (4 if kind.begins_with("sea_") else 5))
	result["boss"] = bool(result.get("boss",kind in BOSSES))
	result["entry_duration"] = float(result.get("entry_duration",2.6))
	result["approach_speed"] = float(result.get("approach_speed",0.85 if str(result.get("role","melee")) == "heavy" else 1.0))
	result["shot_kind"] = str(result.get("shot_kind","bolt"))
	enemy.set_meta("series_combat_info",result)
	return result


func begin_entry(enemy: Node3D) -> void:
	var info := _info(enemy)
	var kind := str(enemy.enemy_kind)
	var duration: float = EntryMotion.DURATIONS.get(kind,info.entry_duration)
	enemy.set_meta("series_entry_authored",kind not in EntryMotion.ORDINARY_FLYERS)
	enemy.set_meta("series_entry_flash",0)
	enemy.set_meta("series_entry_cue",false)
	enemy.set_meta("series_landed",false)
	enemy.set_meta("series_behavior",str(MINION_BEHAVIORS.get(str(enemy.enemy_kind),"boss_"+str(enemy.enemy_kind))))
	enemy.set_meta("series_entry",true)
	enemy.set_meta("entry",true)
	enemy.set_meta("entry_active",true)
	enemy.set_meta("series_entry_age",0.0)
	enemy.set_meta("series_entry_duration",duration)
	if bool(info.boss): enemy.set_meta("series_core_mask",3)
	var anchor := enemy.position
	if not bool(info.boss):
		if enemy.has_meta("sky_lane"):
			anchor = enemy.get_meta("sky_anchor",Vector3(anchor.x,3.0,-22.0))
		elif bool(info.get("flying",false)): anchor.z = -26.0
		else: anchor.z = -40.0+float(enemy.get_meta("entry_depth_offset",0.0))
	enemy.set_meta("series_anchor",anchor)
	enemy.set_meta("entry_anchor",anchor)
	enemy.set_meta("series_action_age",0.0)
	enemy.set_meta("series_clock",0.0)
	enemy.set_meta("series_next_attack",0.60)
	enemy.set_meta("series_shot_mask",0)
	_counters.entries += 1
	_set_action(enemy,"entry",duration)
	if enemy.has_method("reset_entry_material_budget"): enemy.reset_entry_material_budget()
	_apply_entry(enemy,0.0)
	_event("enemy_entry",enemy,{"duration":duration,"series":int(info.series),"sky":enemy.has_meta("sky_lane")})


func update_actor(enemy: Node3D, sim_dt: float, _world_scale: float) -> void:
	if not is_instance_valid(enemy) or bool(enemy.dead) or _game == null: return
	if sim_dt <= 0.0:
		enemy.set_meta("root_motion_velocity",Vector3.ZERO)
		return
	if bool(enemy.get_meta("series_entry",false)):
		_update_entry(enemy,sim_dt)
		return
	_update_team(sim_dt)
	_update_integrity(enemy)
	_update_combat(enemy,sim_dt)


func begin_death(enemy: Node3D) -> void:
	if bool(enemy.get_meta("series_death_started",false)): return
	enemy.set_meta("series_death_started",true)
	enemy.set_meta("series_death_age",0.0)
	enemy.set_meta("series_death_duration",_death_duration(str(enemy.enemy_kind)))
	enemy.set_meta("series_death_done",false)
	enemy.set_meta("series_death_mask",0)
	enemy.set_meta("series_death_part_queue",[9,1,2,7,8,3,4,5,6,0])
	enemy.set_meta("series_death_part_cursor",0)
	enemy.set_meta("series_death_part_frame",-1)
	enemy.set_meta("series_death_origin",enemy.position)
	enemy.set_meta("series_death_rig",enemy._rig.transform)
	var retained: Array[Transform3D] = []
	for part: Variant in enemy._parts: retained.append(part.transform)
	enemy.set_meta("series_death_parts",retained)
	enemy.set_meta("boss_death_hold",true)
	enemy.set_meta("boss_death_stationary",true)
	enemy.set_meta("root_motion_velocity",Vector3.ZERO)
	enemy.set_meta("series_entry",false)
	enemy.set_meta("entry",false)
	enemy.set_meta("entry_active",false)
	enemy.set_meta("series_entry_authored",false)
	if enemy.has_method("set_entry_visibility"): enemy.set_entry_visibility(1.0)
	_counters.deaths += 1
	var death_sound := {2:"boss_ink_break",3:"boss_cyber_arc",4:"boss_sea_rupture",5:"boss_ship_collapse"}
	_game.audio.play_event(str(death_sound.get(int(_info(enemy).series),"explosion")),1.0)
	_event("series_death",enemy)


func update_death(enemy: Node3D, sim_dt: float) -> void:
	if bool(enemy.get_meta("series_death_done",false)): return
	if not bool(enemy.get_meta("series_death_started",false)): begin_death(enemy)
	var age := float(enemy.get_meta("series_death_age",0.0))+maxf(sim_dt,0.0)
	enemy.set_meta("series_death_age",age)
	var duration := float(enemy.get_meta("series_death_duration",2.8))
	enemy.position = enemy.get_meta("series_death_origin")
	enemy.set_meta("root_motion_velocity",Vector3.ZERO)
	enemy.set_action("death",clampf(age/duration,0.0,1.0))
	var blend := smoothstep(0.0,0.32,age)
	var retained_rig: Transform3D = enemy.get_meta("series_death_rig")
	enemy._rig.transform = retained_rig.interpolate_with(enemy._rig.transform,blend)
	var retained: Array = enemy.get_meta("series_death_parts",[])
	# part0 is the rig itself; do not blend it a second time.
	for index in range(1,mini(retained.size(),enemy._parts.size())):
		enemy._parts[index].transform = Transform3D(retained[index]).interpolate_with(enemy._parts[index].transform,blend)
	_update_death_effects(enemy,age)
	if sim_dt > 0.0 and bool(enemy.get_meta("series_death_released",false)):
		_release_next_death_part(enemy)
	var queue: Array = enemy.get_meta("series_death_part_queue",[])
	if age >= duration and int(enemy.get_meta("series_death_part_cursor",0)) >= queue.size(): enemy.set_meta("series_death_done",true)


func get_debug_state() -> Dictionary:
	return {"team_members":_team.size(),"team_owner":str(_team_owner.enemy_kind) if is_instance_valid(_team_owner) else "","team_lock":_team_lock,"relay_broken":_relay_broken,"counters":_counters.duplicate(),"minion_behaviors":MINION_BEHAVIORS.duplicate()}


func _set_action(enemy: Node3D, action: String, duration: float) -> void:
	var previous := str(enemy.get_meta("action_state","run"))
	var retained_rig: Transform3D = enemy._rig.transform
	var retained_parts: Array[Transform3D] = []
	for part: Variant in enemy._parts: retained_parts.append(part.transform)
	_game._set_enemy_action(enemy,action,duration)
	if action != "entry" and previous != "entry":
		enemy.set_meta("series_pose_from_rig",retained_rig)
		enemy.set_meta("series_pose_from_parts",retained_parts)
		enemy.set_meta("series_pose_handoff_started",float(enemy.get_meta("series_clock",0.0)))
	else:
		for key in ["series_pose_from_rig","series_pose_from_parts","series_pose_handoff_started"]:
			if enemy.has_meta(key): enemy.remove_meta(key)
	enemy.set_meta("series_action_age",0.0)
	enemy.set_meta("series_action_duration",maxf(duration,0.01))
	enemy.set_meta("series_shot_mask",0)
	enemy.set_meta("series_contact_resolved",false)
	enemy.set_meta("series_cue_mask",0)
	if action == "strike":
		enemy.set_meta("series_swing_counted",false)
		WeaponContact.reset(enemy)
	if str(enemy.enemy_kind) == "ink_master" and action in ["windup","charge"]:
		enemy.set_meta("series_warp_told",false)
		enemy.set_meta("series_warp_done",false)
		var order := [0,2,3,1]
		var step := int(enemy.get_meta("series_warp_step",0))
		var lane := int(order[step%order.size()])
		var lanes := [-3.0,-1.0,1.0,3.0]
		if is_equal_approx(enemy.position.x,float(lanes[lane])):
			step += 1
			lane = int(order[step%order.size()])
		enemy.set_meta("series_warp_step",step)
		enemy.set_meta("series_warp_lane",lane)


func _event(event_name: String, enemy: Node3D, details: Dictionary = {}) -> void:
	_game._record_combat(event_name,enemy,details)


func _update_entry(enemy: Node3D, dt: float) -> void:
	var before := enemy.position
	var age := float(enemy.get_meta("series_entry_age",0.0))+maxf(dt,0.0)
	var duration := float(enemy.get_meta("series_entry_duration",2.0))
	var p := clampf(age/maxf(duration,0.01),0.0,1.0)
	enemy.set_meta("series_entry_age",age)
	enemy.set_meta("action_phase",p)
	enemy.set_meta("combat_phase",p)
	_apply_entry(enemy,p)
	enemy.set_meta("root_motion_velocity",(enemy.position-before)/maxf(dt,0.00001))
	if p < 1.0: return
	enemy.set_meta("series_entry_exit_rig",enemy._rig.transform)
	var retained: Array[Transform3D] = []
	for part: Variant in enemy._parts: retained.append(part.transform)
	enemy.set_meta("series_entry_exit_parts",retained)
	enemy.position = enemy.get_meta("series_anchor")
	enemy.set_meta("series_entry",false)
	enemy.set_meta("entry",false)
	enemy.set_meta("entry_active",false)
	enemy.set_meta("series_entry_authored",false)
	if enemy.has_method("set_entry_visibility"): enemy.set_entry_visibility(1.0)
	if enemy.has_method("reset_entry_material_budget"): enemy.reset_entry_material_budget()
	enemy.set_meta("series_next_attack",0.55+float(enemy.get_meta("wave_attack_delay",0.0)))
	_set_action(enemy,"recover",0.42 if bool(_info(enemy).boss) else 0.16)
	_blend_entry_exit(enemy,0.0)
	_keep_entry_clear(enemy)
	_event("enemy_entry_complete",enemy,{"series":int(_info(enemy).series),"sky":enemy.has_meta("sky_lane")})


func _apply_entry(enemy: Node3D, p: float) -> void:
	var info := _info(enemy)
	var anchor: Vector3 = enemy.get_meta("series_anchor")
	var kind := str(enemy.enemy_kind)
	var before_point: Vector3 = enemy.get_aim_point()
	var sample: Dictionary = EntryMotion.sample(kind,p,int(enemy.lane_index))
	var offset: Vector3 = sample.get("offset",Vector3.ZERO)
	var angles: Vector3 = sample.get("rotation",Vector3.ZERO)
	# Upright root preserves fragment-floor and root-motion compensation. The
	# actual rig carries jumps/ropes/turns; no alternate visual copy is made.
	enemy.position = anchor+Vector3(0,0,offset.z)
	enemy.set_action("entry",p)
	var basis := Basis.from_euler(angles)
	var pivot := Vector3(0,2.18,0)
	enemy._rig.transform = Transform3D(basis,Vector3(offset.x,offset.y,0)+pivot-basis*pivot)*Transform3D(sample.get("rig",Transform3D.IDENTITY))*enemy._rig.transform
	for part: int in sample.get("parts",{}):
		if part > 0 and part < enemy._parts.size(): enemy._parts[part].transform = Transform3D(sample.parts[part])*enemy._parts[part].transform
	_keep_entry_clear(enemy)
	if enemy.has_method("set_entry_visibility"): enemy.set_entry_visibility(float(sample.get("opacity",1.0)))
	var boss := bool(info.boss)
	var cue_phase := 0.24
	if boss: cue_phase = 0.23 if kind == "sea_leviathan" else (0.30 if kind == "empire_dreadnought" else 0.18)
	if p >= cue_phase and not bool(enemy.get_meta("series_entry_cue",false)):
		enemy.set_meta("series_entry_cue",true)
		if boss:
			_boss_entry_approach(enemy,int(info.series))
		elif bool(info.get("flying",false)):
			var point: Vector3 = enemy.get_aim_point()
			_burst(enemy,point,0.30,1)
			_game.audio.play_event("flyby",0.55)
	var flash := int(sample.get("flash_step",0))
	if flash > int(enemy.get_meta("series_entry_flash",0)):
		enemy.set_meta("series_entry_flash",flash)
		_burst(enemy,before_point,0.45,0)
		_burst(enemy,enemy.get_aim_point(),0.65,2)
		_event("ink_entry_flash",enemy,{"step":flash,"real_rig":true})
	var impact_phase := maxf(float(sample.get("impact_phase",-1.0)),float(sample.get("entry_climax_phase",-1.0)))
	if impact_phase >= 0.0 and p >= impact_phase and not bool(enemy.get_meta("series_landed",false)):
		enemy.set_meta("series_landed",true)
		if boss:
			_boss_entry_arrival(enemy,int(info.series))
			return
		var contact: Vector3 = enemy.global_position+Vector3(enemy._rig.position.x,0.12,0)
		contact.y = 0.065
		_burst(enemy,contact,0.35,0)
		if str(info.role) == "heavy":
			_game.audio.play_event("heavy_land",0.7)
			_game.shake = maxf(float(_game.shake),0.12)


func _boss_entry_approach(enemy: Node3D, series: int) -> void:
	var sound: String = ["entry_ink","entry_cyber","entry_sea","entry_empire"][series-2]
	_game.audio.play_event(sound,1.28)
	var fx = _game.series_effects
	var aim: Vector3 = enemy.get_aim_point()
	match series:
		2:
			_burst(enemy,aim,0.62,1)
			if is_instance_valid(fx): fx.emit_arc(aim+Vector3(0,0,-0.6),2.8,Vector3.BACK,Color(1.8,0.18,0.24),-0.4,PI*1.35,2.5,0.55)
		3:
			_burst(enemy,aim+Vector3(0,-0.6,-1.0),0.42,2)
		4:
			var wake := Vector3(aim.x,0.12,aim.z)
			_burst(enemy,wake+Vector3(-3.4,0,0),1.25,1)
			_burst(enemy,wake+Vector3(3.4,0,0),1.25,1)
			if is_instance_valid(fx): fx.emit_arc(wake,4.4,Vector3.UP,Color(0.62,1.7,2.3),0.0,TAU,6.0,0.74)
		5:
			if is_instance_valid(fx):
				for side in [-1.0,1.0]:
					var tail := aim+Vector3(side*4.2,-0.8,-4.0)
					fx.emit_trace(tail,tail+Vector3(0,0,-10.0),0.38,Color(0.36,1.65,2.6),0.64,Vector3(0,0,-5.0))
					_burst(enemy,tail,0.76,2)
	_event("series_boss_approach",enemy,{"series":series,"sound":sound})


func _boss_entry_arrival(enemy: Node3D, series: int) -> void:
	var kind := str(enemy.enemy_kind)
	var fx = _game.series_effects
	var aim: Vector3 = enemy.get_aim_point()
	var contact := Vector3(enemy.global_position.x+enemy._rig.position.x,0.08,enemy.global_position.z)
	var strength := 0.46
	var sound := "heavy_land"
	match kind:
		"ink_master":
			strength = 0.78
			_burst(enemy,contact,1.75,2)
			if is_instance_valid(fx):
				fx.emit_arc(contact,2.1,Vector3.UP,Color(1.7,0.18,0.24),0.0,TAU,10.0,0.58)
				fx.emit_arc(aim,2.2,Vector3(0.34,0.41,1.0),Color(2.1,1.94,1.73),-1.2,PI*1.23,3.0,0.43)
		"sea_leviathan":
			strength = 1.15
			for side in [-1.0,1.0]:
				var shore := contact+Vector3(side*3.5,0,1.45)
				_burst(enemy,shore,2.4,2)
				if is_instance_valid(fx): fx.emit_arc(shore,2.4,Vector3.UP,Color(0.85,2.0,2.5),side*PI*0.5,PI*1.28,11.0,0.76)
			_burst(enemy,contact,2.0,1)
		"empire_dreadnought":
			strength = 0.90
			sound = "boss_release"
			for side in [-1.0,1.0]:
				var bank := aim+Vector3(side*4.4,-1.25,-1.8)
				_burst(enemy,bank,1.75,2)
				if is_instance_valid(fx): fx.emit_arc(bank,2.1,Vector3.BACK,Color(0.25,1.7,2.6),0.0,TAU,5.5,0.68)
			if is_instance_valid(fx): fx.emit_arc(contact,4.5,Vector3.UP,Color(0.32,1.1,1.9),0.0,TAU,11.0,0.74)
		"cyber_tank":
			strength = 0.89
			for side in [-1.0,1.0]: _burst(enemy,contact+Vector3(side*2.1,0,-1.4),1.6,0)
			if is_instance_valid(fx): fx.emit_arc(contact,2.5,Vector3.UP,Color(1.5,0.73,0.31),0.0,TAU,9.0,0.62)
		"cyber_helicopter", "cyber_gunship":
			strength = 0.74 if kind == "cyber_gunship" else 0.58
			sound = "boss_release" if kind == "cyber_gunship" else "flyby"
			_burst(enemy,contact,1.35,2)
			if is_instance_valid(fx): fx.emit_arc(contact,3.5,Vector3.UP,Color(0.28,1.8,2.1),0.0,TAU,8.0,0.70)
		_:
			strength = 0.64 if kind == "cyber_captain" else 0.31
			_burst(enemy,contact,1.05 if kind == "cyber_captain" else 0.56,0)
			if is_instance_valid(fx): fx.emit_arc(contact,1.4,Vector3.UP,Color(0.24,1.65,2.1),0.0,TAU,6.0,0.42)
	_game.audio.play_event(sound,strength+0.50)
	_game.shake = maxf(float(_game.shake),strength*0.65)
	_game.landing_impact_age = 0.0
	_game.landing_impact_strength = strength*0.64
	_event("series_boss_arrival",enemy,{"series":series,"sound":sound,"strength":strength})


func _keep_entry_clear(enemy: Node3D) -> void:
	# Bound the current render/cut rig, including articulated weapons and rotors.
	# The road rails begin at |x|=5.05. Above them the broader flight aisle is free.
	var low := INF
	var high := -INF
	var over_rail_y := INF
	var left_shift := -INF
	var right_shift := INF
	var rig: Transform3D = enemy._rig.transform
	for part in range(enemy._part_meshes.size()):
		var mesh: Mesh = enemy._part_meshes[part].mesh
		if mesh == null: continue
		var posed := rig if part == 0 else rig*Transform3D(enemy._parts[part].transform)
		var bounds: AABB = posed*mesh.get_aabb()
		low = minf(low,bounds.position.y)
		high = maxf(high,bounds.end.y)
		var at_rail := bounds.position.y+enemy.position.y < 1.02
		var span := 5.04 if at_rail else 7.70
		if bounds.size.x > 10.08 or enemy.enemy_kind == "empire_dreadnought":
			over_rail_y = minf(over_rail_y,bounds.position.y)
		if bounds.size.x <= span*2.0:
			left_shift = maxf(left_shift,-span-enemy.position.x-bounds.position.x)
			right_shift = minf(right_shift,span-enemy.position.x-bounds.end.x)
	var correction := clampf(0.0,left_shift,right_shift) if left_shift <= right_shift else (left_shift+right_shift)*0.5
	var ceiling: float = {2:10.08,3:12.42,4:12.46,5:27.0}.get(int(_info(enemy).series),12.0)
	var floor_shift := maxf(-0.052-enemy.position.y-low,1.025-enemy.position.y-over_rail_y)
	rig.origin.x += correction
	rig.origin.y += clampf(0.0,floor_shift,ceiling-enemy.position.y-high)
	enemy._rig.transform = rig


func _blend_entry_exit(enemy: Node3D, clock: float) -> void:
	if not enemy.has_meta("series_entry_exit_rig"): return
	if clock >= 0.18:
		enemy.remove_meta("series_entry_exit_rig")
		enemy.remove_meta("series_entry_exit_parts")
		return
	var weight := smoothstep(0.0,0.18,clock)
	var rig: Transform3D = enemy.get_meta("series_entry_exit_rig")
	enemy._rig.transform = rig.interpolate_with(enemy._rig.transform,weight)
	var parts: Array = enemy.get_meta("series_entry_exit_parts",[])
	for part in range(1,mini(parts.size(),enemy._parts.size())):
		if str(enemy.enemy_kind) == "cyber_helicopter" and part == 9: continue
		enemy._parts[part].transform = Transform3D(parts[part]).interpolate_with(enemy._parts[part].transform,weight)
	_keep_entry_clear(enemy)


func _update_team(dt: float) -> void:
	var frame := Engine.get_process_frames()
	if _last_team_frame == frame: return
	_last_team_frame = frame
	_clock += maxf(dt,0.0)
	_team_lock = maxf(0.0,_team_lock-dt)
	for member: Variant in _team:
		# A single true cut can sever relay power and kill the captain together.
		# His retained corpse still carries that refreshed connectivity result.
		if not is_instance_valid(member): continue
		if str(member.enemy_kind) != "cyber_captain" or _relay_broken: continue
		var integrity: Dictionary = member.get_series_integrity_state()
		if bool(integrity.get("relay_intact",true)): continue
		_relay_broken = true
		_team_lock = maxf(_team_lock,0.90)
		_counters.relay_staggers += 1
		for teammate: Variant in _team:
			if not is_instance_valid(teammate) or bool(teammate.dead) or bool(teammate.get_meta("series_entry",false)): continue
			_set_action(teammate,"stagger",0.72)
			_burst(teammate,teammate.get_aim_point(),0.65,2)
		_event("series_relay_broken",member,{"team_stagger":true})
	if _team_lock > 0.0: return
	if is_instance_valid(_team_owner):
		if _hostile_shots_from(_team_owner): return
		var action := str(_team_owner.get_meta("action_state","run"))
		if not bool(_team_owner.dead) and action in ["windup","strike","charge","fire"]: return
		var old_index := _team.find(_team_owner)
		_team_index = (old_index+1)%maxi(_team.size(),1)
		_team_owner = null
	elif _team_owner != null:
		_team_index = (_team_index+1)%maxi(_team.size(),1)
		_team_owner = null


func _hostile_shots_from(source: Node3D) -> bool:
	for shot: Dictionary in _game.projectiles:
		if not bool(shot.get("reflected",false)) and shot.get("source") == source and is_instance_valid(shot.get("node")): return true
	return false


func _may_attack(enemy: Node3D) -> bool:
	if not bool(enemy.get_meta("series_team_member",false)): return true
	if is_instance_valid(_team_owner): return false
	if _team_lock > 0.0 or _team.is_empty(): return false
	for offset in range(_team.size()):
		var index := (_team_index+offset)%_team.size()
		var candidate: Variant = _team[index]
		if not is_instance_valid(candidate) or bool(candidate.dead) or bool(candidate.get_meta("series_entry",false)): continue
		if not candidate.has_attack_limb(): continue
		if candidate != enemy: return false
		_team_owner = enemy
		_team_index = index
		_team_lock = 1.2
		_event("series_team_token",enemy,{"order":index})
		return true
	return false


func _move_team_cover(enemy: Node3D, dt: float) -> void:
	var anchor: Vector3 = enemy.get_meta("series_anchor",enemy.position)
	var slot := _team.find(enemy)
	var side := -1.0 if slot%2 == 0 else 1.0
	var lane_shift := 1.0 if _team_index%2 == 0 else -1.0
	var goal := anchor
	match str(enemy.enemy_kind):
		"cyber_flanker": goal = Vector3(side*4.8*lane_shift,anchor.y,-17.5 if _team_index == 2 else -25.0)
		"cyber_suppressor": goal = Vector3(-lane_shift*2.3,anchor.y,-26.0)
		"cyber_spotter": goal = Vector3(lane_shift*4.2,anchor.y,-29.0)
		_: goal = Vector3(lane_shift*1.4,anchor.y,-20.0)
	enemy.position = enemy.position.move_toward(goal,maxf(dt,0.0)*(4.5 if str(enemy.enemy_kind) == "cyber_flanker" else 2.0))


func _update_integrity(enemy: Node3D) -> void:
	var integrity: Dictionary = enemy.get_series_integrity_state()
	var cores: Array = integrity.get("core_active",[])
	if cores.size() == 2:
		var core_mask := int(cores[0])+2*int(cores[1])
		if core_mask != int(enemy.get_meta("series_core_mask",core_mask)):
			enemy.set_meta("series_core_mask",core_mask)
			if core_mask in [1,2]:
				var lost := 1 if core_mask == 1 else 0
				var point: Vector3 = integrity.core_world_points[lost]
				_burst(enemy,point,0.83,2)
				_game.audio.play_event("parry_clash",0.72)
				_event("series_core_lost",enemy,{"module":lost,"remaining":1})
	var active := int(integrity.get("active_supports",0))
	var previous := int(enemy.get_meta("series_supports",active))
	enemy.set_meta("series_supports",active)
	if active < previous:
		_burst(enemy,Vector3(integrity.get("core_world",enemy.get_aim_point())),0.55,1)
		_event("series_support_severed",enemy,{"remaining":active,"total":int(integrity.get("total_supports",0))})
		if str(enemy.enemy_kind) in ["cyber_riot","empire_sentinel"]: _set_action(enemy,"stagger",0.62)
		elif str(enemy.enemy_kind) == "empire_lancer" and str(enemy.get_meta("action_state","")) == "strike":
			# Slow the remaining real boost without rewinding the current pose.
			enemy.set_meta("action_time",float(enemy.get_meta("action_time",0.0))*1.65)
			enemy.set_meta("action_duration",float(enemy.get_meta("action_duration",0.3))*1.65)
	if bool(integrity.get("vulnerable",false)) and not bool(enemy.get_meta("series_vulnerable_seen",false)):
		enemy.set_meta("series_vulnerable_seen",true)
		if bool(_info(enemy).boss) and str(enemy.enemy_kind) not in TEAM_KINDS:
			_set_action(enemy,"stagger",1.0)
			_game.audio.play_event("parry_clash",0.8)
		_event("series_vulnerable",enemy,{"real_supports":active})


func _burst(enemy: Node3D, point: Vector3, strength: float, stage: int) -> void:
	if is_instance_valid(_game.series_effects):
		_game.series_effects.emit_burst(point,int(_info(enemy).series),strength,stage,true,0.0)


func _update_combat(enemy: Node3D, dt: float) -> void:
	var before := enemy.position
	var info := _info(enemy)
	var action := str(enemy.get_meta("action_state","run"))
	var phase: float = _game._advance_enemy_action(enemy,dt)
	var clock := float(enemy.get_meta("series_clock",0.0))+dt
	enemy.set_meta("series_clock",clock)
	var team_member := bool(enemy.get_meta("series_team_member",false))
	if team_member and _team_owner != enemy and action in ["run","recover"]:
		_move_team_cover(enemy,dt)
	match action:
		"run":
			_update_run(enemy,info,dt,clock)
		"windup":
			var advance := smoothstep(0.0,1.0,phase)
			var kind := str(enemy.enemy_kind)
			if kind in ["ink_swordsman","ink_spear"]: advance = smoothstep(0.38,0.93,phase)
			elif kind == "sea_skimmer": advance = smoothstep(0.25,0.86,phase)
			elif kind == "empire_lancer": advance = pow(smoothstep(0.20,1.0,phase),2.0)
			elif kind == "cyber_riot": advance = smoothstep(0.20,1.0,phase)
			enemy.position.z = lerpf(float(enemy.get_meta("action_start_z",-13.0)),-7.4,advance)
			_behavior_motion(enemy,dt,"windup",phase)
			if phase >= 1.0:
				if str(enemy.enemy_kind) == "ink_swordsman" and not bool(enemy.get_meta("series_feint_done",false)):
					enemy.set_meta("series_feint_done",true)
					enemy.set_meta("series_feint",true)
					_set_action(enemy,"feint",0.24)
					_event("series_feint",enemy,{"damaging":false})
				else:
					_set_action(enemy,"strike",_strike_duration(enemy,info))
					_game.audio.play_event("enemy_swing",1.1 if bool(info.boss) else 0.8)
		"feint":
			if phase >= 1.0:
				enemy.set_meta("series_feint",false)
				_set_action(enemy,"windup",0.36)
		"strike":
			_update_strike(enemy,info,phase)
		"charge":
			if phase >= 1.0: _set_action(enemy,"fire",_fire_duration(str(enemy.enemy_kind)))
		"fire":
			_fire_step(enemy,phase)
			if phase >= 1.0:
				enemy.set_meta("series_cycles",int(enemy.get_meta("series_cycles",0))+1)
				_finish_attack(enemy,info)
		"recover", "stagger":
			var anchor: Vector3 = enemy.get_meta("series_anchor",enemy.position)
			if bool(enemy.get_meta("series_melee",false)):
				var retreat := anchor.z if bool(info.boss) else -7.8
				enemy.position.z = lerpf(float(enemy.get_meta("action_start_z",-2.2)),retreat,smoothstep(0.0,1.0,phase))
				enemy.position.x = lerpf(float(enemy.get_meta("action_start_x",0.0)),anchor.x,smoothstep(0.0,1.0,phase))
			if phase >= 1.0:
				if not bool(info.boss) and bool(enemy.get_meta("series_melee",false)):
					var swings := int(enemy.get_meta("series_swings",0))
					if swings < _melee_limit(str(enemy.enemy_kind),info) and enemy.has_attack_limb(): _begin_melee(enemy,info)
					else: _set_action(enemy,"exit",1.0)
				else:
					enemy.set_meta("series_melee",false)
					_set_action(enemy,"run",1.0)
		"exit":
			enemy.position.z += (float(_game.speed)*0.9+6.0)*dt
			if enemy.position.z > 8.0:
				enemy.set_meta("series_retire_done",true)
				enemy.queue_free()
	var posed := str(enemy.get_meta("action_state","run"))
	var posed_phase := float(enemy.get_meta("action_phase",0.0))
	if posed == "run": posed_phase = fmod(float(enemy.age)*1.9,1.0)
	if posed == "stagger": posed = "recover"
	if posed == "feint":
		posed = "windup"
		posed_phase = 1.0-posed_phase*0.45
	if posed == "exit":
		posed = "recover"
		posed_phase = 1.0
	_behavior_motion(enemy,dt,action,phase)
	_apply_combat_pose(enemy,posed,posed_phase)
	_combat_cues(enemy,posed,posed_phase)
	_blend_entry_exit(enemy,clock)
	enemy.pulse_warning(phase if action in ["windup","charge"] else 0.0)
	enemy.set_meta("root_motion_velocity",(enemy.position-before)/maxf(dt,0.00001))


func _update_run(enemy: Node3D, info: Dictionary, dt: float, clock: float) -> void:
	var role := str(info.role)
	var boss := bool(info.boss)
	var in_team := bool(enemy.get_meta("series_team_member",false))
	var sky := enemy.has_meta("sky_lane")
	var cycles := int(enemy.get_meta("series_cycles",0))
	var kind := str(enemy.enemy_kind)
	var ranged := _ranged_pattern(kind,role,cycles)
	if kind == "empire_sentinel" and not _support_active(enemy,0): ranged = true
	if kind == "ink_master":
		var armed_blade: bool = enemy.has_series_melee_weapon(1) or enemy.has_series_melee_weapon(2)
		ranged = not enemy.get_ranged_origins().is_empty() and (cycles%2 == 1 or not armed_blade)
	elif kind == "cyber_captain": ranged = cycles%2 == 1
	var shooting := ranged and (boss or sky or cycles < 2)
	if not boss and not sky:
		if cycles >= 2 and (ranged or kind in ["ink_talisman","cyber_sniper","sea_eel","empire_walker"]):
			if kind == "cyber_drone" and _hostile_shots_from(enemy): return
			_set_action(enemy,"exit",1.0)
			return
		var standoff := (_ranged_standoff(kind)+minf(14.0,float(cycles)*8.0)) if shooting else _melee_trigger(kind)
		if enemy.position.z < standoff:
			enemy.position.z = minf(standoff,enemy.position.z+(float(_game.speed)*float(info.approach_speed)+2.8)*dt)
	if sky:
		var anchor: Vector3 = enemy.get_meta("series_anchor")
		enemy.position = anchor
	if clock < float(enemy.get_meta("series_next_attack",0.0)): return
	if not boss and enemy.position.z < (_ranged_trigger(kind) if shooting else _melee_trigger(kind)-0.01): return
	if not enemy.has_attack_limb():
		if not boss:
			_set_action(enemy,"exit",1.0)
			_event("disarmed",enemy)
		return
	if not _may_attack(enemy): return
	if shooting:
		enemy.set_meta("series_melee",false)
		var tell := _charge_duration(str(enemy.enemy_kind))
		if kind in ["ink_master","empire_dreadnought"] and int(enemy.get_meta("series_core_mask",3)) in [1,2]:
			tell -= 0.16
		tell += _consume_first_delay(enemy)
		tell += float(enemy.get_meta("first_charge_extra",0.0))
		enemy.set_meta("first_charge_extra",0.0)
		_set_action(enemy,"charge",tell)
		_game.audio.play_event("ranged_charge",1.0 if boss else 0.75)
		_event("series_charge",enemy,{"shot_kind":_shot_kind(enemy)})
	else: _begin_melee(enemy,info)
	if in_team: _team_lock = maxf(_team_lock,2.0)


func _begin_melee(enemy: Node3D, info: Dictionary, followup: bool = false) -> void:
	enemy.set_meta("series_melee",true)
	var kind := str(enemy.enemy_kind)
	var swings := int(enemy.get_meta("series_swings",0))
	enemy.set_meta("series_attack_variant",swings%2)
	var duration := 0.86 if str(info.role) == "heavy" else 0.66
	if kind == "ink_master":
		enemy.set_meta("series_master_followup",followup)
		duration = 0.55 if followup else 0.78
	elif bool(info.boss): duration = 0.88
	elif kind == "ink_swordsman": duration = 0.74 if swings == 0 else 0.43
	elif kind == "sea_crab": duration = 0.94 if swings == 0 else 0.57
	elif kind == "sea_skimmer": duration = 1.20
	elif kind == "cyber_riot": duration = 1.04 if _support_active(enemy,0) else 0.62
	elif kind == "empire_sentinel": duration = 1.12
	elif kind == "empire_lancer": duration = 1.05 if _support_active(enemy,0) else 1.36
	duration += _consume_first_delay(enemy)
	_set_action(enemy,"windup",duration)
	_game.audio.play_event("windup",1.0)
	if followup: _event("series_combo_followup",enemy,{"windup":duration})


func _consume_first_delay(enemy: Node3D) -> float:
	if bool(enemy.get_meta("wave_attack_delay_used",false)): return 0.0
	enemy.set_meta("wave_attack_delay_used",true)
	return float(enemy.get_meta("wave_attack_delay",0.0))


func _support_active(enemy: Node3D, index: int) -> bool:
	var integrity: Dictionary = enemy.get_series_integrity_state()
	var supports: Array = integrity.get("support_active",[])
	return bool(supports[index]) if index >= 0 and index < supports.size() else true


func _part_armed(enemy: Node3D, part: int) -> bool:
	if enemy.has_method("has_series_melee_weapon") and enemy.has_series_melee_weapon(part): return true
	return bool(enemy._emitter_intact(part)) if enemy.has_method("_emitter_intact") else bool(enemy.has_attack_limb())


func _melee_limit(kind: String, info: Dictionary) -> int:
	if kind in ["ink_swordsman","sea_crab"]: return 2
	if kind in MINION_BEHAVIORS: return 1
	return 2 if str(info.role) == "heavy" else 1


func _strike_duration(enemy: Node3D, info: Dictionary) -> float:
	var kind := str(enemy.enemy_kind)
	if kind == "empire_lancer": return 0.26 if _support_active(enemy,0) else 0.48
	if kind == "sea_skimmer": return 0.40
	if kind == "sea_crab": return 0.38 if int(enemy.get_meta("series_swings",0)) == 0 else 0.29
	if kind == "empire_sentinel": return 0.46
	return 0.34 if str(info.role) == "heavy" else 0.28


func _ranged_pattern(kind: String, role: String, cycles: int) -> bool:
	if kind in ["ink_swordsman","ink_spear","cyber_breacher"]: return cycles == 0
	if kind == "empire_sentinel": return cycles == 0
	if kind == "empire_walker": return true
	return role in ["ranged","support"] or kind in ["sea_leviathan","empire_dreadnought"]


func _ranged_standoff(kind: String) -> float:
	if kind == "cyber_breacher": return -28.0
	if kind == "empire_walker": return -34.0
	if kind in ["sea_ray","empire_fighter"]: return -26.0
	if kind == "ink_crane": return -28.0
	if kind == "cyber_drone": return -30.0
	return -33.0


func _ranged_trigger(kind: String) -> float:
	return -37.5


func _melee_trigger(kind: String) -> float:
	match kind:
		"ink_swordsman","ink_spear": return -30.0
		"sea_skimmer": return -36.0
		"sea_crab": return -24.0
		"cyber_riot": return -29.0
		"empire_sentinel": return -24.0
		"empire_lancer": return -38.0
	return -19.0


func _behavior_motion(enemy: Node3D, _dt: float, action: String, phase: float) -> void:
	var kind := str(enemy.enemy_kind)
	var clock := float(enemy.get_meta("series_clock",0.0))
	var anchor: Vector3 = enemy.get_meta("series_anchor",enemy.position)
	if action == "exit": return
	match kind:
		"ink_master":
			if action in ["windup","charge"]: _ink_warp(enemy,phase)
		"ink_crane":
			# A real mirror pass, including the sky: the port travels with the hull.
			var inward := -signf(anchor.x) if not is_zero_approx(anchor.x) else (-1.0 if int(enemy.lane_index)%2 == 0 else 1.0)
			enemy.position.x = clampf(anchor.x+inward*sin(clock*1.45)*1.65,-5.5,5.5)
			if enemy.has_meta("sky_lane"): enemy.position.z = anchor.z+sin(clock*2.9)*0.85
		"cyber_breacher":
			if action == "charge": enemy.position.x = anchor.x-signf(anchor.x if not is_zero_approx(anchor.x) else 1.0)*1.2*sin(phase*PI)
		"cyber_riot":
			enemy.set_meta("series_shield_open",0.0 if _support_active(enemy,0) else 1.0)
			if action == "windup" and _support_active(enemy,0):
				enemy.position.z = lerpf(float(enemy.get_meta("action_start_z",-13.0)),-6.65,smoothstep(0.0,1.0,phase))
		"cyber_sniper":
			if action == "recover" and enemy.has_meta("series_relocate_to"):
				var goal := float(enemy.get_meta("series_relocate_to"))
				enemy.position.x = lerpf(float(enemy.get_meta("series_relocate_from",anchor.x)),goal,smoothstep(0.0,1.0,phase))
				enemy.position.z = lerpf(float(enemy.get_meta("action_start_z",-24.0)),float(enemy.get_meta("series_relocate_z",-28.0)),smoothstep(0.0,1.0,phase))
				if phase >= 1.0:
					anchor.x = goal
					enemy.set_meta("series_anchor",anchor)
					enemy.remove_meta("series_relocate_to")
		"cyber_drone":
			enemy.position.x = clampf(anchor.x+sin(clock*1.2)*0.90,-5.2,5.2)
		"sea_skimmer":
			enemy.set_meta("series_burrow",0.0)
			if action == "windup":
				var side := -1.0 if anchor.x < 0.0 else 1.0
				enemy.position.x = lerpf(anchor.x,side*0.55,smoothstep(0.25,0.86,phase))+side*sin(phase*PI)*1.8
		"sea_eel":
			enemy.position.x = clampf(anchor.x+sin(clock*1.9)*1.30,-5.4,5.4)
		"empire_lancer":
			if action == "windup" and _support_active(enemy,0):
				enemy.position.x = lerpf(anchor.x,-anchor.x*0.20,smoothstep(0.22,0.92,phase))
		"empire_sentinel":
			var opening := 1.0 if not _support_active(enemy,0) else 0.0
			if _support_active(enemy,0):
				if action == "charge": opening = smoothstep(0.08,0.64,phase)
				elif action == "fire": opening = 1.0
				elif action == "recover": opening = 1.0-smoothstep(0.25,1.0,phase)
			enemy.set_meta("series_shield_open",opening)
		"empire_fighter":
			enemy.position.x = clampf(anchor.x+sin(clock*1.10)*3.2,-4.8,4.8)
			if enemy.has_meta("sky_lane"): enemy.position.z = anchor.z+cos(clock*1.10)*1.8


func _ink_warp(enemy: Node3D, phase: float) -> void:
	var lanes := [-3.0,-1.0,1.0,3.0]
	var lane := clampi(int(enemy.get_meta("series_warp_lane",0)),0,3)
	var target_x := float(lanes[lane])
	if phase >= 0.08 and not bool(enemy.get_meta("series_warp_told",false)):
		enemy.set_meta("series_warp_told",true)
		var current: Vector3 = enemy.get_aim_point()
		_burst(enemy,current,0.30,0)
		_burst(enemy,current+Vector3(target_x-enemy.position.x,0,0),0.22,1)
		_event("ink_warp_tell",enemy,{"target_lane":lane,"target_x":target_x,"phase":phase})
	if phase < 0.34 or bool(enemy.get_meta("series_warp_done",false)): return
	enemy.set_meta("series_warp_done",true)
	var from := enemy.position
	_burst(enemy,enemy.get_aim_point(),0.65,0)
	enemy.position.x = target_x
	enemy.lane_index = lane
	enemy.set_meta("lane_x",target_x)
	enemy.set_meta("action_start_x",target_x)
	var anchor: Vector3 = enemy.get_meta("series_anchor",enemy.position)
	anchor.x = target_x
	enemy.set_meta("series_anchor",anchor)
	enemy.set_meta("series_warp_step",int(enemy.get_meta("series_warp_step",0))+1)
	_burst(enemy,enemy.get_aim_point(),0.72,2)
	_event("ink_warp",enemy,{"from":from,"to":enemy.position,"real_root":true})


func _behavior_bank(enemy: Node3D) -> void:
	var kind := str(enemy.enemy_kind)
	var clock := float(enemy.get_meta("series_clock",0.0))
	var bank := 0.0
	var lift := 0.0
	var ease := smoothstep(0.0,0.40,clock)
	if kind == "ink_crane":
		var anchor: Vector3 = enemy.get_meta("series_anchor",enemy.position)
		var inward := -signf(anchor.x) if not is_zero_approx(anchor.x) else (-1.0 if int(enemy.lane_index)%2 == 0 else 1.0)
		bank = -inward*cos(clock*1.45)*0.40*ease
	elif kind == "empire_fighter":
		bank = -cos(clock*1.10)*0.44*ease
		lift = -0.32*ease
	elif kind == "sea_eel": bank = sin(clock*1.9)*0.21
	elif kind == "sea_skimmer" and str(enemy.get_meta("action_state","")) == "windup":
		var p := float(enemy.get_meta("action_phase",0.0))
		lift = sin(smoothstep(0.22,0.94,p)*PI)*1.65
		bank = sin(p*TAU)*0.48
	elif kind == "cyber_breacher" and str(enemy.get_meta("action_state","")) == "charge":
		lift = 0.65*sin(float(enemy.get_meta("action_phase",0.0))*PI)
	if is_zero_approx(bank) and is_zero_approx(lift): return
	var basis := Basis(Vector3.FORWARD,bank)
	var pivot := Vector3(0,2.18,0)
	enemy._rig.transform = Transform3D(basis,Vector3(0,lift,0)+pivot-basis*pivot)*enemy._rig.transform


func _apply_combat_pose(enemy: Node3D, action: String, phase: float) -> void:
	enemy.set_action(action,phase)
	_behavior_bank(enemy)
	if not enemy.has_meta("series_pose_from_rig"): return
	var elapsed := float(enemy.get_meta("series_clock",0.0))-float(enemy.get_meta("series_pose_handoff_started",0.0))
	var weight := smoothstep(0.0,0.085,elapsed)
	var retained: Transform3D = enemy.get_meta("series_pose_from_rig")
	enemy._rig.transform = retained.interpolate_with(enemy._rig.transform,weight)
	var parts: Array = enemy.get_meta("series_pose_from_parts",[])
	for index in range(1,mini(parts.size(),enemy._parts.size())):
		enemy._parts[index].transform = Transform3D(parts[index]).interpolate_with(enemy._parts[index].transform,weight)
	if elapsed >= 0.085:
		for key in ["series_pose_from_rig","series_pose_from_parts","series_pose_handoff_started"]: enemy.remove_meta(key)


func _combat_cues(enemy: Node3D, action: String, phase: float) -> void:
	if not is_instance_valid(_game.series_effects): return
	var kind := str(enemy.enemy_kind)
	var series := int(_info(enemy).series)
	var tint: Color = {2:Color("e4ddd1"),3:Color("f28c48"),4:Color("a5e9e2"),5:Color("c8b9f1")}[series]
	var mask := int(enemy.get_meta("series_cue_mask",0))
	if action in ["charge","windup"]:
		for index in range(2):
			if phase < (0.12 if index == 0 else 0.78) or mask&(1<<index): continue
			mask |= 1<<index
			var ports: Array = enemy.get_ranged_origins()
			if kind in ["cyber_sniper","cyber_spotter"] and not ports.is_empty():
				_game.series_effects.emit_trace(ports[0],Vector3(0,1.65,-0.9),0.016 if index == 0 else 0.035,Color("b54440"),0.28)
			elif kind in ["ink_talisman","ink_master"]:
				_game.series_effects.emit_arc(enemy.get_aim_point()+Vector3(0,0,0.25),1.25 if kind == "ink_master" else 0.75,Vector3.BACK,Color("ba2930"),float(index)*PI*0.5,PI*1.65)
			elif kind == "empire_dreadnought":
				var battery: int = _dreadnought_battery_order(enemy)[0]
				var origin := _dreadnought_battery_origin(enemy,battery)
				if origin.is_finite():
					_game.series_effects.emit_arc(origin,0.94 if battery == 0 else 0.70,Vector3.BACK,tint,0,TAU)
			elif kind in ["empire_walker","empire_sentinel"]:
				for origin: Vector3 in ports: _game.series_effects.emit_arc(origin,0.42,Vector3.BACK,tint,0,TAU)
			elif kind == "sea_eel":
				for origin: Vector3 in ports: _game.series_effects.emit_arc(origin,0.65,Vector3.BACK,tint,-PI*0.5,PI*1.5)
			enemy.set_meta("series_cue_mask",mask)
	if kind == "empire_dreadnought" and action == "fire":
		var phases := _shot_phases(kind)
		var order := _dreadnought_battery_order(enemy)
		for index in range(1,phases.size()):
			if phase < float(phases[index])-0.12 or mask&(1<<index): continue
			mask |= 1<<index
			var origin := _dreadnought_battery_origin(enemy,int(order[index]))
			if origin.is_finite():
				_game.series_effects.emit_arc(origin,0.94 if order[index] == 0 else 0.70,Vector3.BACK,tint,0,TAU)
		enemy.set_meta("series_cue_mask",mask)
	var clock := float(enemy.get_meta("series_clock",0.0))
	if action == "strike" and clock >= float(enemy.get_meta("series_trace_at",0.0)):
		enemy.set_meta("series_trace_at",clock+0.035)
		var old: Dictionary = enemy.get_meta("series_trace_points",{})
		var points: Dictionary = {}
		for weapon: Dictionary in _definitions.integrity_layout(kind).get("melee_segments",[]):
			if not _part_armed(enemy,int(weapon.part)): continue
			var transform: Transform3D = enemy.global_transform*enemy._part_pose(int(weapon.part))
			var tip := transform*Vector3(weapon.b)
			points[int(weapon.part)] = tip
			if old.has(int(weapon.part)) and tip.distance_squared_to(old[int(weapon.part)]) < 25.0:
				_game.series_effects.emit_trace(old[int(weapon.part)],tip,0.045,tint,0.16)
			enemy.set_meta("series_trace_points",points)
	elif action != "strike": enemy.set_meta("series_trace_points",{})


func _update_strike(enemy: Node3D, info: Dictionary, phase: float) -> void:
	var master := str(enemy.enemy_kind) == "ink_master"
	var lunge := smoothstep(0.0,0.56,phase)
	var anchor: Vector3 = enemy.get_meta("series_anchor",enemy.position)
	enemy.position.z = lerpf(float(enemy.get_meta("action_start_z",-7.4)),-2.2,lunge)
	enemy.position.x = lerpf(float(enemy.get_meta("action_start_x",0.0)),anchor.x*0.06,lunge)
	_behavior_motion(enemy,0.0,"strike",phase)
	_apply_combat_pose(enemy,"strike",phase)
	var contact := WeaponContact.check(enemy,_definitions.integrity_layout(str(enemy.enemy_kind)))
	if bool(contact.get("hit",false)) and not bool(enemy.get_meta("series_contact_resolved",false)):
		enemy.set_meta("series_contact_resolved",true)
		_count_swing(enemy)
		var armed := _part_armed(enemy,int(contact.part))
		if armed:
			_counters.melee_contacts += 1
			enemy.attack_done += 1
			_event("attack_impact",enemy,{"series":int(info.series),"real_weapon":true,"occupied_cell":contact.cell,"world_point":contact.point})
			if _game._try_guard("melee",enemy):
				if master:
					# A clean parry ends the whole sequence and opens a punish window.
					enemy.set_meta("series_cycles",int(enemy.get_meta("series_cycles",0))+1)
					enemy.set_meta("series_next_attack",float(enemy.get_meta("series_clock",0.0))+1.15)
				_set_action(enemy,"stagger",0.68)
				return
			_game._hurt(1,"melee",enemy)
		else: _event("disarmed",enemy)
	if phase >= 1.0:
		_count_swing(enemy)
		if master:
			var both_blades: bool = enemy.has_series_melee_weapon(1) and enemy.has_series_melee_weapon(2)
			if both_blades and not bool(enemy.get_meta("series_master_followup",false)):
				_begin_melee(enemy,info,true)
				return
			enemy.set_meta("series_cycles",int(enemy.get_meta("series_cycles",0))+1)
		_finish_attack(enemy,info)


func _count_swing(enemy: Node3D) -> void:
	if bool(enemy.get_meta("series_swing_counted",false)): return
	enemy.set_meta("series_swing_counted",true)
	enemy.set_meta("series_swings",int(enemy.get_meta("series_swings",0))+1)
	if str(enemy.enemy_kind) != "ink_master":
		enemy.set_meta("series_cycles",int(enemy.get_meta("series_cycles",0))+1)


func _finish_attack(enemy: Node3D, info: Dictionary) -> void:
	var integrity: Dictionary = enemy.get_series_integrity_state()
	var vulnerable := bool(integrity.get("vulnerable",false))
	var recover := 1.30 if vulnerable else (0.92 if bool(info.boss) else 0.55)
	var kind := str(enemy.enemy_kind)
	if kind in ["ink_master","empire_dreadnought"]:
		# Keep the exposed-core opening noticeably longer than a normal reset.
		recover = 1.16 if vulnerable else (0.66 if kind == "ink_master" else 0.60)
		_set_action(enemy,"recover",recover)
		enemy.set_meta("series_next_attack",float(enemy.get_meta("series_clock",0.0))+recover+(0.62 if vulnerable else 0.36))
		return
	if kind == "cyber_sniper":
		recover = 1.15
		enemy.set_meta("series_relocate_from",enemy.position.x)
		enemy.set_meta("series_relocate_to",(-3.0 if enemy.position.x >= 0.0 else 3.0))
		enemy.set_meta("series_relocate_z",minf(enemy.position.z-4.0,-28.0))
	elif str(enemy.enemy_kind) == "sea_crab": recover = 0.40 if int(enemy.get_meta("series_swings",0)) == 1 else 0.75
	elif str(enemy.enemy_kind) == "ink_swordsman": recover = 0.30 if int(enemy.get_meta("series_swings",0)) == 1 else 0.62
	_set_action(enemy,"recover",recover)
	var tier := 1
	if _game.campaign != null: tier = int(_game.campaign.difficulty_tier())
	enemy.set_meta("series_next_attack",float(enemy.get_meta("series_clock",0.0))+recover+maxf(0.85,1.7-float(tier-1)*0.13))


func _charge_duration(kind: String) -> float:
	if kind == "cyber_breacher": return 0.64
	if kind == "ink_spear": return 0.88
	if kind == "ink_talisman": return 0.92
	if kind == "empire_walker": return 1.18
	if kind == "empire_sentinel": return 1.14
	if kind == "empire_fighter": return 0.74
	if kind == "cyber_sniper": return 1.18
	if kind == "cyber_spotter": return 1.28
	if kind == "cyber_tank": return 1.32
	if kind == "empire_dreadnought": return 1.00
	if kind == "ink_master": return 0.94
	if kind == "sea_leviathan": return 1.14
	if kind in ["cyber_helicopter","cyber_gunship"]: return 1.08
	return 0.94 if kind in ["ink_talisman","sea_eel","empire_sentinel"] else 0.82


func _fire_duration(kind: String) -> float:
	if kind == "empire_fighter": return 1.04
	if kind == "ink_crane": return 0.86
	if kind == "ink_talisman": return 1.10
	if kind == "cyber_drone": return 0.48
	if kind == "empire_walker": return 1.24
	if kind == "sea_ray": return 1.02
	if kind == "ink_master": return 1.28
	if kind == "empire_dreadnought": return 1.72
	return 0.82 if kind in ["cyber_suppressor","cyber_gunship"] else 0.56


func _shot_kind(enemy: Node3D) -> String:
	var kind := str(enemy.enemy_kind)
	match kind:
		"ink_spear": return "ink_spear"
		"ink_talisman": return "seal"
		"cyber_breacher": return "buckshot"
		"cyber_sniper": return "needle"
		"cyber_drone": return "beacon"
		"sea_eel": return "electric_wave"
		"empire_walker": return "cannon_orb"
	if kind.begins_with("ink_"): return "sword_wave"
	if kind.begins_with("sea_"): return "torpedo"
	if kind.begins_with("empire_"): return "plasma_lance"
	if kind in ["cyber_helicopter","cyber_gunship"]: return "missile"
	if kind in ["cyber_tank","cyber_spotter"]: return "shock"
	return "bolt"


func _shot_phases(kind: String) -> Array:
	match kind:
		"ink_spear": return [0.40]
		"ink_talisman": return [0.12,0.40,0.68]
		"ink_crane": return [0.16,0.48,0.80]
		"cyber_breacher": return [0.26]
		"cyber_drone": return [0.32]
		"sea_eel": return [0.36]
		"sea_ray": return [0.20,0.68]
		"empire_walker": return [0.24,0.72]
		"empire_fighter": return [0.12,0.36,0.60,0.84]
		"ink_master": return [0.10,0.48,0.90]
		"empire_dreadnought": return [0.08,0.37,0.65,0.94]
	if kind in ["cyber_sniper","cyber_spotter","cyber_tank","empire_sentinel"]: return [0.38]
	if kind in ["cyber_suppressor","cyber_gunship"]: return [0.18,0.48,0.78]
	if kind in ["ink_talisman","cyber_helicopter","sea_leviathan","empire_fighter"]: return [0.24,0.70]
	return [0.32]


func _fire_step(enemy: Node3D, phase: float) -> void:
	var kind := str(enemy.enemy_kind)
	var phases := _shot_phases(kind)
	var mask := int(enemy.get_meta("series_shot_mask",0))
	# Submit from the current actual pose, after every cut has refreshed emitter
	# connectivity. A marker/old muzzle position can never stand in for a port.
	_behavior_motion(enemy,0.0,"fire",phase)
	_apply_combat_pose(enemy,"fire",phase)
	for index in range(phases.size()):
		if phase < float(phases[index]) or mask & (1<<index): continue
		mask |= 1<<index
		enemy.set_meta("series_shot_mask",mask)
		if kind == "empire_dreadnought":
			_fire_dreadnought_battery(enemy,index)
			continue
		var origins: Array = enemy.get_ranged_origins()
		if origins.is_empty():
			_event("disarmed",enemy,{"cancelled_burst":index})
			continue
		var ports := mini(origins.size(),2 if kind in ["sea_leviathan","cyber_gunship"] else 1)
		if kind == "cyber_breacher": ports = 3
		var cycles := int(enemy.get_meta("series_cycles",0))
		for port in range(ports):
			var origin: Vector3 = origins[(index+port+cycles)%origins.size()]
			var spread := Vector3((float(port)-float(ports-1)*0.5)*0.36,0,0)
			if kind == "cyber_breacher": spread.x *= 2.0
			if kind == "ink_talisman":
				origin += Vector3((float(index)-1.0)*0.75,0.5*sin(float(index)*PI*0.5),0.3)
				spread = Vector3((float(index)-1.0)*0.55,0,0)
			var node: Node3D = _game._spawn_projectile(origin,_shot_kind(enemy),enemy,spread,1.0)
			if not is_instance_valid(node): continue
			if _shot_kind(enemy) == "sword_wave": node.set_meta("roll",(-0.58 if index%2 == 0 else 0.58))
			if kind == "ink_master":
				var plane := (cycles+index)%3
				node.set_meta("roll",0.0 if plane == 0 else ((PI*0.25 if cycles%2 == 0 else -PI*0.25) if plane == 1 else PI*0.5))
			if kind == "sea_eel": node.set_meta("roll",sin(float(enemy.get_meta("series_clock",0.0))*1.9)*0.46)
			if kind == "cyber_breacher":
				node.set_meta("volley_id","%d:%d:%d" % [enemy.get_instance_id(),cycles,index])
				node.set_meta("pellet_index",port)
			elif kind == "ink_talisman": _game._configure_series_projectile(node,"prime",{"delay":0.82-float(index)*0.12})
			elif kind == "cyber_drone": _game._configure_series_projectile(node,"beacon",{"interval":0.55,"shots":2})
			elif kind == "sea_ray": _game._configure_series_projectile(node,"bend",{"delay":0.28+float(index)*0.10,"target":Vector3(0,1.65,-0.9),"side":-1.0 if index%2 == 0 else 1.0})
			_counters.shots += 1
			_hold_for_projectile(enemy,node,origin)
			_burst(enemy,origin,0.16,0)
		_game.audio.play_event("ranged_fire",1.1 if bool(_info(enemy).boss) else 0.7)
		_event("series_burst",enemy,{"burst":index,"live_ports":origins.size(),"projectile_kind":_shot_kind(enemy)})


func _dreadnought_battery_order(enemy: Node3D) -> Array:
	var cycles := int(enemy.get_meta("series_cycles",0))
	return [1,2,0,1] if cycles%2 == 0 else [0,2,1,0]


func _dreadnought_battery_origin(enemy: Node3D, part: int) -> Vector3:
	if not enemy._emitter_intact(part): return Vector3.INF
	for emitter: Dictionary in _definitions.emitters(str(enemy.enemy_kind)):
		if int(emitter.part) == part:
			return enemy.to_global(enemy._part_pose(part)*Vector3(emitter.point))
	return Vector3.INF


func _fire_dreadnought_battery(enemy: Node3D, index: int) -> void:
	# Aim each beat separately. Missing batteries leave real gaps in the salvo.
	var part: int = _dreadnought_battery_order(enemy)[index]
	var origin := _dreadnought_battery_origin(enemy,part)
	if not origin.is_finite():
		_event("disarmed",enemy,{"cancelled_burst":index,"battery":part})
		return
	var projectile_kind := "cannon_orb" if part == 0 else "plasma_lance"
	var node: Node3D = _game._spawn_projectile(origin,projectile_kind,enemy,Vector3.ZERO,0.96 if part == 0 else 1.0)
	if not is_instance_valid(node): return
	_counters.shots += 1
	_burst(enemy,origin,0.52 if part == 0 else 0.28,1)
	_game.audio.play_event("ranged_fire",1.45 if part == 0 else 0.95)
	_event("series_battery_shot",enemy,{"burst":index,"battery":part,"projectile_kind":projectile_kind})


func _hold_for_projectile(enemy: Node3D, node: Node3D, origin: Vector3) -> void:
	if not bool(enemy.get_meta("series_team_member",false)): return
	for shot: Dictionary in _game.projectiles:
		if shot.get("node") != node: continue
		var velocity: Vector3 = shot.get("velocity",Vector3.ZERO)
		var flight := (-0.9-origin.z)/velocity.z if velocity.z > 0.0001 else 2.0
		_team_lock = maxf(_team_lock,maxf(flight,0.0)+0.32)
		break


func _death_duration(kind: String) -> float:
	match kind:
		"ink_master": return 3.10
		"cyber_helicopter": return 3.60
		"cyber_tank": return 3.40
		"cyber_gunship": return 3.85
		"sea_leviathan": return 3.65
		"empire_dreadnought": return 4.60
	return 2.50


func _death_cues(kind: String) -> Array:
	# time/strength/stage/point index; stages select each series' opaque palette
	# and distribution in the preallocated pool, not a replacement death mesh.
	match kind:
		"ink_master": return [[0.12,0.42,0,0],[0.38,0.50,0,1],[0.66,0.68,0,2],[0.94,0.45,1,0],[1.30,0.85,0,1],[1.72,1.10,2,0],[2.10,0.75,1,2],[2.45,0.45,0,0]]
		"cyber_helicopter": return [[0.18,0.40,0,1],[0.48,0.60,1,1],[0.91,0.50,2,0],[1.38,0.72,1,2],[1.95,1.15,2,0],[2.55,0.65,1,1],[2.94,0.45,0,0]]
		"cyber_tank": return [[0.18,0.48,1,1],[0.47,0.48,1,2],[0.96,0.72,0,0],[1.45,1.05,2,0],[1.86,0.90,2,1],[2.26,0.85,1,2],[2.72,0.55,0,0]]
		"cyber_gunship": return [[0.12,0.42,0,1],[0.44,0.55,1,2],[0.82,0.62,1,1],[1.20,0.65,0,2],[1.65,1.00,2,0],[2.04,0.70,1,1],[2.48,1.12,2,2],[3.05,0.65,0,0]]
		"sea_leviathan": return [[0.12,0.52,0,1],[0.40,0.52,0,2],[0.71,0.52,0,3],[1.04,0.58,0,4],[1.45,0.85,1,0],[1.90,1.12,2,0],[2.32,0.95,1,2],[2.85,0.72,0,0]]
		"empire_dreadnought": return [[0.15,0.55,0,1],[0.43,0.62,1,2],[0.74,0.66,1,3],[1.08,0.72,0,1],[1.47,0.80,2,2],[1.88,0.90,1,3],[2.28,0.95,2,1],[2.72,1.12,2,0],[3.18,0.82,1,2],[3.76,0.70,0,0]]
	return [[0.10,0.42,0,0],[0.40,0.55,1,1],[0.82,0.68,2,0],[1.25,0.46,1,2],[1.82,0.35,0,0]]


func _death_point(enemy: Node3D, index: int) -> Vector3:
	var integrity: Dictionary = enemy.get_series_integrity_state()
	var points: Array = integrity.get("world_points",[])
	if index > 0 and not points.is_empty(): return Vector3(points[(index-1)%points.size()])
	return enemy.get_aim_point()


func _update_death_effects(enemy: Node3D, age: float) -> void:
	var kind := str(enemy.enemy_kind)
	var cues := _death_cues(kind)
	var mask := int(enemy.get_meta("series_death_mask",0))
	for index in range(cues.size()):
		var cue: Array = cues[index]
		if age < float(cue[0]) or mask & (1<<index): continue
		mask |= 1<<index
		enemy.set_meta("series_death_mask",mask)
		var point := _death_point(enemy,int(cue[3]))
		_burst(enemy,point,float(cue[1]),int(cue[2]))
		if kind == "cyber_tank" and index in [3,4,5]: _game._spawn_blast(point,0.75 if index != 3 else 1.10,false,true)
		elif kind == "empire_dreadnought" and index == 7: _game._spawn_blast(point,1.45,true,true)
		if int(cue[2]) == 2:
			_game.shake = maxf(float(_game.shake),0.65 if bool(_info(enemy).boss) else 0.2)
			_game.audio.play_event("explosion" if kind != "ink_master" else "parry_clash",0.65)
		_event("series_death_cue",enemy,{"cue":index,"palette_stage":int(cue[2]),"point":point})
	var release := 0.72 if kind in ["cyber_helicopter","cyber_gunship"] else 0.40
	if age >= release and bool(enemy.get_meta("boss_death_hold",false)):
		enemy.set_meta("boss_death_hold",false)
		_release_death_fragments(enemy,0.60)
	var climax := 2.72 if kind == "empire_dreadnought" else (1.90 if kind == "sea_leviathan" else 1.65)
	if age >= climax and not bool(enemy.get_meta("series_death_released",false)):
		enemy.set_meta("series_death_released",true)
		_release_death_fragments(enemy,1.0)


func _release_death_fragments(enemy: Node3D, strength: float) -> void:
	var center := enemy.to_local(enemy.get_aim_point())
	var kind := str(enemy.enemy_kind)
	var count := 0
	for piece: Variant in enemy.get_children():
		if not bool(piece.get_meta("voxel_piece",false)) or piece.is_queued_for_deletion(): continue
		var radial: Vector3 = piece.position-center
		var direction := radial.normalized() if radial.length_squared() > 0.0001 else Vector3.UP
		var impulse := 3.8 if kind == "ink_master" else (5.0 if kind == "sea_leviathan" else 7.2)
		piece.velocity = direction*impulse*strength+Vector3(0,2.0*strength,0.8)
		piece.spin = Vector3(float(count%3)-1.0,signf(radial.x)*1.6,signf(radial.x)*1.1)*strength
		piece.lifetime = maxf(float(piece.lifetime),float(piece.elapsed)+float(enemy.get_meta("series_death_duration",3.0))+0.5)
		count += 1
	_event("series_death_fragments",enemy,{"true_fragments":count,"strength":strength})


func _release_next_death_part(enemy: Node3D) -> void:
	var frame := Engine.get_process_frames()
	if int(enemy.get_meta("series_death_part_frame",-1)) == frame: return
	var queue: Array = enemy.get_meta("series_death_part_queue",[])
	var cursor := int(enemy.get_meta("series_death_part_cursor",0))
	while cursor < queue.size():
		var candidate := int(queue[cursor])
		if candidate >= 0 and candidate < enemy._mesh_cell_counts.size() and int(enemy._mesh_cell_counts[candidate]) > 0: break
		cursor += 1
	enemy.set_meta("series_death_part_cursor",cursor)
	if cursor >= queue.size(): return
	enemy.set_meta("series_death_part_frame",frame)
	enemy.set_meta("series_death_part_cursor",cursor+1)
	var part := int(queue[cursor])
	var point: Vector3 = enemy.get_aim_point()
	if part < enemy._part_meshes.size():
		var visual: MeshInstance3D = enemy._part_meshes[part]
		if visual.mesh != null: point = visual.to_global(visual.mesh.get_aabb().get_center())
	var released := bool(enemy.release_series_death_part(part))
	if released:
		_burst(enemy,point,0.28+float(cursor%3)*0.06,2 if cursor%3 == 0 else 1)
		_release_death_fragments(enemy,0.72)
	_event("series_death_part",enemy,{"part":part,"released":released,"remaining_attempts":queue.size()-cursor-1,"world_point":point})
