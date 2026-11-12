class_name EncounterDirector
extends RefCounted
## Preserve the v0.9.5 stream's order, lane cycle and timed cadence. The main
## scene owns admission limits and the one exceptional row's clear window.
## Three isolated flyer slots may use the separate sky lanes. Their admission
## is optional and must never delay the ground stream when the sky is busy.

const ROW_ATTACK_DELAYS := [0.0,0.12,0.64,0.76]
const COMPLEX_RANGED := ["ranged","drone","missile_drone","interceptor","mine_layer"]
const BASELINE_SEQUENCE := ["normal","ranged","drone","normal","barrier","tank","missile_drone","ranged","beam","drone","normal","tank"]
const BASELINE_LANES := [1,2,0,3,2,1,0,2]
const ROW_WAVE_INDEX := 22
const SKY_SLOTS := {
	9:{"kind":"drone","sky_lane":1,"earliest":20.0},
	26:{"kind":"drone","sky_lane":0,"earliest":90.0},
	42:{"kind":"missile_drone","sky_lane":2,"earliest":150.0},
}


static func plan(wave_index: int, progress: float, speed: float, route_seconds: float = 180.0) -> Dictionary:
	var index := maxi(wave_index,0)
	var elapsed := clampf(progress,0.0,1.0)*maxf(route_seconds,1.0)
	var original: String = BASELINE_SEQUENCE[index % BASELINE_SEQUENCE.size()]
	var lane: int = BASELINE_LANES[index % BASELINE_LANES.size()]
	if original == "tank": lane = 0 if index % 2 == 0 else 2
	# A single ordinary slot becomes the optional broad-cut moment. It does
	# not cycle, and shortened routes cannot pull it into their opening.
	if index == ROW_WAVE_INDEX and elapsed >= 75.0:
		return _row(index,elapsed,speed)
	var kind := original
	var advanced := false
	if (index == 13 and elapsed >= 50.0) or (index == 37 and elapsed >= 130.0):
		kind = "interceptor"
		advanced = true
	elif index == 25 and elapsed >= 90.0:
		kind = "mine_layer"
		advanced = true
	var first_delay := 0.25 if kind in ["ranged","drone","missile_drone"] else 0.0
	var sky_spawns: Array[Dictionary] = []
	var sky_replacement := _sky_replacement(index,elapsed,kind)
	var spawns: Array[Dictionary] = []
	if sky_replacement.is_empty():
		spawns.append(_spawn(kind,lane,0.0,0.0,first_delay,"advanced_intro" if advanced else "baseline"))
	else:
		sky_spawns.append(sky_replacement)
	# Match the old post-increment test: current zero-based slots3,7,11...
	# may add one ordinary follower after75s, fourteen metres behind.
	if not advanced and elapsed > 75.0 and (index+1) % 4 == 0 and kind not in ["barrier","beam"]:
		spawns.append(_spawn("normal",(lane+2)%4,-14.0,0.0,0.0,"baseline_follow"))
	var result := _group("advanced_"+kind if advanced else "baseline_"+kind,index,elapsed,spawns,4.3 if elapsed < 40.0 else 3.5,2.0,speed)
	if not sky_spawns.is_empty(): result["id"] = "sky_"+kind
	result["sky_spawns"] = sky_spawns
	result["baseline_kind"] = original
	result["advanced_intro"] = advanced
	return result


static func _sky_replacement(index: int, elapsed: float, kind: String) -> Dictionary:
	if not SKY_SLOTS.has(index): return {}
	var slot: Dictionary = SKY_SLOTS[index]
	if elapsed < float(slot.earliest) or kind != str(slot.kind): return {}
	# Return a fresh value so callers cannot mutate the fixed slot table.
	return {"kind":kind,"sky_lane":int(slot.sky_lane)}


static func _spawn(kind: String, lane: int, z_offset: float = 0.0, attack_delay: float = 0.0, fire_delay: float = 0.0, role: String = "lead") -> Dictionary:
	return {"kind":kind,"lane":lane,"z_offset":z_offset,"role":role,"fire_delay":fire_delay,"attack_delay":attack_delay}


static func _group(id: String, index: int, elapsed: float, spawns: Array, interval: float, lead: float, speed: float) -> Dictionary:
	return {
		"id":id,"stage":0 if elapsed < 40.0 else (1 if elapsed < 75.0 else (2 if elapsed < 130.0 else 3)),
		"spawns":spawns,"sky_spawns":[],"interval":interval,"lead_seconds":lead,
		"approach_seconds":lead,"minimum_distance":40.0,"approach_speed_offset":0.0,"distance_bias":12.0,
		"hold_until_clear":false,"heavy_ranged_cap":2,"recovery_seconds":0.0,
		"baseline_index":index,"route_elapsed":elapsed,"advanced_intro":false,
		"planned_speed":clampf(speed,4.0,60.0),
	}


static func _row(index: int, elapsed: float, speed: float) -> Dictionary:
	var spawns: Array[Dictionary] = []
	for lane in range(4):
		spawns.append(_spawn("normal",lane,0.0,float(ROW_ATTACK_DELAYS[lane]),0.0,"row"))
	var result := _group("four_lane_row",index,elapsed,spawns,4.8,2.4,speed)
	result["baseline_kind"] = "normal"
	result["hold_until_clear"] = true
	result["recovery_seconds"] = 1.2
	return result


# Campaign preparation is deliberately independent of the legacy plan() above.
# These tables describe combat admission, never geometry or actor inheritance.
const CAMPAIGN_ROLES := ["melee","heavy","ranged","support"]
const CAMPAIGN_INTERVALS := [4.3,4.0,3.7,3.4]
const CAMPAIGN_THREAT_CAPS := [3.6,4.2,4.8,5.4]
const SERIES_KINDS := {
	1:{"melee":["normal"],"heavy":["tank"],"ranged":["ranged"],"support":["drone","missile_drone"]},
	2:{"melee":["ink_swordsman"],"heavy":["ink_spear"],"ranged":["ink_talisman"],"support":["ink_crane"]},
	3:{"melee":["cyber_breacher"],"heavy":["cyber_riot"],"ranged":["cyber_sniper"],"support":["cyber_drone"]},
	4:{"melee":["sea_skimmer"],"heavy":["sea_crab"],"ranged":["sea_eel"],"support":["sea_ray"]},
	5:{"melee":["empire_lancer"],"heavy":["empire_walker"],"ranged":["empire_sentinel"],"support":["empire_fighter"]},
}
const SERIES_BOSSES := {
	1:[["boss"]],2:[["ink_master"]],
	3:[["cyber_captain","cyber_flanker","cyber_suppressor","cyber_spotter"],["cyber_helicopter"],["cyber_tank"],["cyber_gunship"]],
	4:[["sea_leviathan"]],5:[["empire_dreadnought"]],
}
const SERIES_LABELS := {1:"铸甲军团",2:"墨武宗门",3:"霓虹特勤",4:"深海群落",5:"星际帝国"}


static func stream_seed(run_seed: int, stream: int) -> int:
	# Integer arithmetic is stable for signed 64-bit inputs, including INT_MIN.
	var normalized := run_seed % 2147483647
	if normalized < 0: normalized += 2147483647
	var salt := stream % 2147483647
	if salt < 0: salt += 2147483647
	return (normalized*48271+salt*69621+907633385) % 2147483647


static func shuffle_with_rng(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size()-1,0,-1):
		var other := rng.randi_range(0,index)
		var saved: Variant = values[index]
		values[index] = values[other]
		values[other] = saved


static func freeze_tree(value: Variant) -> void:
	if value is Dictionary:
		for child: Variant in value.values(): freeze_tree(child)
		value.make_read_only()
	elif value is Array:
		for child: Variant in value: freeze_tree(child)
		value.make_read_only()


static func get_series_definition(series_id: int) -> Dictionary:
	if not SERIES_KINDS.has(series_id): return {}
	var roles: Dictionary = SERIES_KINDS[series_id].duplicate(true)
	var actors: Dictionary = {}
	for role: String in CAMPAIGN_ROLES:
		for kind: String in roles[role]: actors[kind] = kind_profile(kind)
	if series_id == 1:
		for kind: String in ["barrier","beam","interceptor","mine_layer"]: actors[kind] = kind_profile(kind)
	var result := {"id":series_id,"label":str(SERIES_LABELS[series_id]),"roles":roles,"actors":actors,"boss_stages":SERIES_BOSSES[series_id].duplicate(true)}
	freeze_tree(result)
	return result


static func kind_profile(kind: String) -> Dictionary:
	var role := "melee"
	var flying := false
	for series_id: int in SERIES_KINDS:
		for candidate_role: String in CAMPAIGN_ROLES:
			if kind in SERIES_KINDS[series_id][candidate_role]: role = candidate_role
	if role == "support": flying = true
	if kind == "sea_eel": flying = true
	var advanced := kind in ["interceptor","mine_layer"]
	if advanced:
		role = "ranged"
		flying = true
	if kind in ["barrier","beam"]: role = "obstacle"
	var shooter := role in ["ranged","support"] or kind in ["ink_swordsman","ink_spear","cyber_breacher","empire_walker"]
	var threat := 1.0
	if role == "heavy": threat = 2.0
	elif role == "ranged": threat = 1.6
	elif role == "support": threat = 1.4
	elif role == "obstacle": threat = 0.5
	if kind == "missile_drone": threat = 1.8
	if advanced: threat = 2.6
	var burst := 1 if shooter else 0
	if kind == "missile_drone": burst = 2
	elif advanced: burst = 3
	elif kind in ["ink_crane","cyber_breacher","cyber_drone"]: burst = 3
	elif kind == "ink_talisman": burst = 3
	elif kind in ["sea_ray","empire_walker"]: burst = 2
	elif kind == "empire_fighter": burst = 4
	return {"kind":kind,"role":role,"flying":flying,"shooter":shooter,"heavy":role == "heavy","advanced":advanced,"threat":threat,"projectile_reservation":burst}


static func _take_from_bag(bag: Array, choices: Array, rng: RandomNumberGenerator, avoid: Variant = null) -> Variant:
	if bag.is_empty():
		bag.assign(choices)
		shuffle_with_rng(bag,rng)
	if bag.size() > 1 and bag.back() == avoid:
		var swap: Variant = bag[0]
		bag[0] = bag.back()
		bag[bag.size()-1] = swap
	return bag.pop_back()


static func _take_lane(bag: Array, rng: RandomNumberGenerator, used: Array, previous: int, sky: bool = false) -> int:
	var choices := [0,1,2] if sky else [0,1,2,3]
	if bag.is_empty():
		bag.assign(choices)
		shuffle_with_rng(bag,rng)
	# Take an available bag value; retain skipped values for the next wave.
	for index in range(bag.size()-1,-1,-1):
		var lane := int(bag[index])
		if lane in used or lane == previous: continue
		bag.remove_at(index)
		return lane
	# A partial bag can contain only lanes used by this wave. Refill uniquely.
	bag.assign(choices)
	shuffle_with_rng(bag,rng)
	for index in range(bag.size()-1,-1,-1):
		var lane := int(bag[index])
		if lane not in used and lane != previous:
			bag.remove_at(index)
			return lane
	for lane: int in choices:
		if lane not in used: return lane
	return -1


static func campaign_budgets(difficulty_tier: int) -> Dictionary:
	var tier := clampi(difficulty_tier,1,4)
	return {"ground":3,"sky":1 if tier <= 2 else 2,"shooters":2,"heavy":1,"advanced":1,"threat":float(CAMPAIGN_THREAT_CAPS[tier-1]),"projectiles":24}


static func demand_for(plan_data: Dictionary) -> Dictionary:
	var result := {"ground":0,"sky":0,"shooters":0,"heavy":0,"advanced":0,"threat":0.0,"projectile_reservation":0}
	for key: String in ["spawns","sky_spawns"]:
		for item: Dictionary in plan_data.get(key,[]):
			var profile := kind_profile(str(item.kind))
			result["ground" if key == "spawns" else "sky"] += 1
			result.shooters += int(profile.shooter)
			result.heavy += int(profile.heavy)
			result.advanced += int(profile.advanced)
			result.threat += float(profile.threat)
			result.projectile_reservation += int(profile.projectile_reservation)
	return result


static func admission(plan_data: Dictionary, live_and_reserved: Dictionary = {}) -> Dictionary:
	var budgets: Dictionary = plan_data.get("budgets",campaign_budgets(int(plan_data.get("difficulty_tier",1))))
	var demand := demand_for(plan_data)
	var occupied := int(live_and_reserved.get("ground",0))+int(live_and_reserved.get("sky",0))
	if bool(plan_data.get("exclusive",false)) and occupied > 0: return {"allowed":false,"reason":"exclusive_clearance","demand":demand}
	if int(live_and_reserved.get("advanced",0)) > 0 and int(demand.ground)+int(demand.sky) > 0:
		return {"allowed":false,"reason":"advanced_active","demand":demand}
	for key: String in ["ground","sky","shooters","heavy","advanced","threat"]:
		if float(live_and_reserved.get(key,0))+float(demand[key]) > float(budgets[key])+0.00001:
			return {"allowed":false,"reason":key+"_budget","demand":demand}
	if int(live_and_reserved.get("projectiles",0))+int(live_and_reserved.get("projectile_reservation",0))+int(demand.projectile_reservation) > int(budgets.projectiles):
		return {"allowed":false,"reason":"projectile_budget","demand":demand}
	return {"allowed":true,"reason":"ready","demand":demand}


static func _campaign_group(series_id: int, tier: int, index: int, at: float, phase: String, interval: float, speed: float) -> Dictionary:
	var result := _group("series_%d_wave_%02d" % [series_id,index],index,at,[],interval,2.0,speed)
	result.merge({"series_id":series_id,"difficulty_tier":tier,"at_seconds":at,"phase":phase,"lead_role":"","exclusive":false,"retire_sky":false,"budgets":campaign_budgets(tier),"optional_sky":true},true)
	result["latest_seconds"] = at+interval*0.85
	result["skip_if_blocked"] = true
	return result


static func _try_member(result: Dictionary, kind: String, use_sky: bool, ground_bag: Array, sky_bag: Array, lane_rng: RandomNumberGenerator, previous_lane: int, previous_sky: int) -> bool:
	var key := "sky_spawns" if use_sky else "spawns"
	var used: Array = []
	for item: Dictionary in result[key]: used.append(int(item.get("sky_lane",item.get("lane",-1))))
	var lane := _take_lane(sky_bag if use_sky else ground_bag,lane_rng,used,previous_sky if use_sky else previous_lane,use_sky)
	if lane < 0: return false
	var profile := kind_profile(kind)
	if use_sky and not bool(profile.flying): return false
	var item := _spawn(kind,lane,-14.0 if result.spawns.size() > 0 and not use_sky else 0.0,0.32*float(result.spawns.size()),0.25 if bool(profile.shooter) else 0.0,str(profile.role))
	if use_sky:
		item["sky_lane"] = lane
		item["z_offset"] = 0.0
	result[key].append(item)
	if not bool(admission(result).allowed):
		result[key].pop_back()
		return false
	return true


static func build_level(series_id: int, difficulty_tier: int, level_seed: int, options: Dictionary = {}) -> Dictionary:
	if not SERIES_KINDS.has(series_id): return {}
	var tier := clampi(difficulty_tier,1,4)
	var duration := clampf(float(options.get("duration",75.0 if tier == 1 else (100.0 if tier == 4 else 90.0))),45.0,180.0)
	var speed := clampf(float(options.get("planned_speed",18.0)),4.0,60.0)
	var rng := RandomNumberGenerator.new()
	var lane_rng := RandomNumberGenerator.new()
	rng.seed = stream_seed(level_seed,211)
	lane_rng.seed = stream_seed(level_seed,307)
	var roles: Dictionary = SERIES_KINDS[series_id]
	var role_bag: Array = []
	var kind_bags: Dictionary = {}
	var ground_bag: Array = []
	var sky_bag: Array = []
	var previous_role := ""
	var previous_lane := -1
	var previous_sky := -1
	var plans: Array[Dictionary] = []
	var base_interval := float(CAMPAIGN_INTERVALS[tier-1])
	var elapsed := 2.8 if tier == 1 else 2.2
	var intro_count := 4 if tier == 1 else 2
	var intro_roles := ["melee","ranged","heavy","support"]
	var index := 0
	var special_index := maxi(7,int((duration-12.0)/base_interval*0.56))
	var row_index := special_index+3
	var offer_row := series_id == 1 and rng.randf() < 0.60
	var advanced_kind := "interceptor" if rng.randi_range(0,1) == 0 else "mine_layer"
	var row_count := 0
	while elapsed < duration-9.0:
		var progress := elapsed/duration
		var phase := "intro" if index < intro_count else ("light_mix" if progress < 0.46 else ("contrast" if progress < 0.82 else "closing"))
		var interval := base_interval+rng.randf_range(-0.10,0.16)
		var value := _campaign_group(series_id,tier,index,elapsed,phase,interval,speed)
		var lead_role := str(intro_roles[index]) if index < intro_count else str(_take_from_bag(role_bag,CAMPAIGN_ROLES,rng,previous_role))
		if lead_role == previous_role:
			lead_role = str(_take_from_bag(role_bag,CAMPAIGN_ROLES,rng,previous_role))
		if phase == "closing": lead_role = "heavy" if previous_role != "heavy" else "ranged"
		if series_id == 1 and index == special_index-1 and lead_role == "ranged":
			lead_role = "heavy" if previous_role != "heavy" else "support"
		if series_id == 1 and index == special_index:
			lead_role = "ranged"
			value["exclusive"] = true
			value["hold_until_clear"] = true
			value["retire_sky"] = true
			value["advanced_intro"] = true
			value["id"] = "advanced_"+advanced_kind
			value.spawns.append(_spawn(advanced_kind,_take_lane(ground_bag,lane_rng,[],previous_lane),0.0,0.0,0.0,"advanced_intro"))
		elif offer_row and index == row_index and previous_role != "melee" and elapsed >= 42.0:
			lead_role = "melee"
			value = _campaign_group(series_id,tier,index,elapsed,"contrast",4.8,speed)
			value["id"] = "four_lane_row"
			value["exclusive"] = true
			value["hold_until_clear"] = true
			value["retire_sky"] = true
			value["recovery_seconds"] = 1.2
			value.budgets.ground = 4
			value.budgets.threat = maxf(float(value.budgets.threat),4.0)
			for lane in range(4): value.spawns.append(_spawn("normal",lane,0.0,float(ROW_ATTACK_DELAYS[lane]),0.0,"row"))
			row_count += 1
		else:
			if not kind_bags.has(lead_role): kind_bags[lead_role] = []
			var kind := str(_take_from_bag(kind_bags[lead_role],roles[lead_role],rng))
			var flying := bool(kind_profile(kind).flying)
			var in_sky := flying and index >= intro_count and rng.randf() < 0.58
			_try_member(value,kind,in_sky,ground_bag,sky_bag,lane_rng,previous_lane,previous_sky)
			var combo_chance := 0.28+0.08*float(tier)+ (0.12 if phase == "contrast" else 0.0)
			if index >= intro_count and (phase == "closing" or rng.randf() < combo_chance):
				var companions := CAMPAIGN_ROLES.duplicate()
				companions.erase(lead_role)
				shuffle_with_rng(companions,rng)
				for companion_role: String in companions:
					var companion_kind: String = roles[companion_role][rng.randi_range(0,roles[companion_role].size()-1)]
					var companion_sky := bool(kind_profile(companion_kind).flying) and rng.randf() < 0.65
					if _try_member(value,companion_kind,companion_sky,ground_bag,sky_bag,lane_rng,previous_lane,previous_sky): break
			if tier >= 3 and phase == "contrast" and index % 5 == 2:
				var third_role := "melee" if lead_role != "melee" else "ranged"
				_try_member(value,str(roles[third_role][0]),false,ground_bag,sky_bag,lane_rng,previous_lane,previous_sky)
		value["lead_role"] = lead_role
		value["latest_seconds"] = minf(float(value.latest_seconds),duration-6.5)
		value["demand"] = demand_for(value)
		if not value.spawns.is_empty(): previous_lane = int(value.spawns[0].lane)
		if not value.sky_spawns.is_empty(): previous_sky = int(value.sky_spawns[0].sky_lane)
		previous_role = lead_role
		plans.append(value)
		elapsed += float(value.interval)
		index += 1
	var breather := _campaign_group(series_id,tier,index,duration-6.5,"breather",6.5,speed)
	breather["id"] = "before_boss_breather"
	breather["retire_sky"] = true
	breather["latest_seconds"] = duration
	breather["demand"] = demand_for(breather)
	plans.append(breather)
	var definition := get_series_definition(series_id)
	var catalog: Array[String] = []
	for kind: String in definition.actors: catalog.append(kind)
	var stages: Array = SERIES_BOSSES[series_id].duplicate(true)
	var policies: Array[Dictionary] = []
	for stage_index in range(stages.size()):
		for kind: String in stages[stage_index]:
			if not catalog.has(kind): catalog.append(kind)
		policies.append({
			"ordered":true,"max_active":1,"max_active_semantics":"attacking","attack_budget":1,
			"max_units":4 if series_id == 3 and stage_index == 0 else 1,
			"shooter_tokens":1,"exclusive":true,"transition":"all_members_structurally_defeated",
			"retire_projectiles_before_next":true,
		})
	if series_id == 1:
		catalog.append("boss_carrier")
		catalog.append("shield_drone")
	var result := {
		"series_id":series_id,"level_index":int(options.get("level_index",tier-1)),"difficulty_tier":tier,"seed":level_seed,
		"duration":duration,"duration_seconds":duration,"plans":plans,"waves":plans,"catalog":catalog,
		"boss_stages":stages,"boss_stage_policies":policies,"budgets":campaign_budgets(tier),
		"interval_base":base_interval,"intro_slots":intro_count,"rare_four_rows":row_count,
	}
	freeze_tree(result)
	return result


static func plan_for_series(series_id: int, wave_index: int, progress: float, speed: float, route_seconds: float = 90.0, difficulty_tier: int = 1, run_seed: int = 0) -> Dictionary:
	# Compatibility convenience, not a per-frame API. Main caches build_run().
	var prepared := build_level(series_id,difficulty_tier,run_seed,{"duration":route_seconds,"planned_speed":speed})
	if prepared.is_empty(): return {}
	var plans: Array = prepared.plans
	if wave_index < 0 or wave_index >= plans.size(): return {}
	# progress is retained in the compatibility signature; it never rerolls a slot.
	if not is_finite(progress): return {}
	return plans[wave_index]
