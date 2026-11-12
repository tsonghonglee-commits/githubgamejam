extends SceneTree
## Pure planner checks only. No game scene, actors, meshes, AI or battle steps.

const Campaign = preload("res://scripts/campaign_director.gd")
const Encounters = preload("res://scripts/encounter_director.gd")
var output_path := ""
var seed_count := 300
var checks: Array[Dictionary] = []
var failures := 0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--campaign-output="): output_path = argument.trim_prefix("--campaign-output=")
		elif argument.begins_with("--campaign-seeds="): seed_count = clampi(int(argument.trim_prefix("--campaign-seeds=")),1,10000)
	call_deferred("_run")


func _expect(passed: bool, label: String, detail: Dictionary = {}) -> void:
	checks.append({"passed":passed,"label":label,"detail":detail})
	if passed: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)


func _deep_frozen(value: Variant) -> bool:
	if value is Dictionary:
		if not value.is_read_only(): return false
		for child: Variant in value.values():
			if not _deep_frozen(child): return false
	elif value is Array:
		if not value.is_read_only(): return false
		for child: Variant in value:
			if not _deep_frozen(child): return false
	return true


func _run() -> void:
	var route_ok := true
	var deterministic := true
	var immutable := true
	var schedule := true
	var budgets := true
	var lanes := true
	var role_repeat := true
	var warmed := true
	var bosses := true
	var tier_rules := true
	var wave_count := 0
	var route_histogram: Dictionary = {}
	var first_failure: Dictionary = {}
	var sampled_seeds: Array[int] = [-9223372036854775807-1,-2147483647,-1,0,1,2147483647,9223372036854775807]
	for index in range(seed_count): sampled_seeds.append(index*7919+170917)
	for run_seed: int in sampled_seeds:
		var run: Dictionary = Campaign.build_run(run_seed)
		var route: Array = run.route
		route_ok = route_ok and route.size() == 4 and route[0] == 1 and route[3] == 5 and route[1] in [2,3,4] and route[2] in [2,3,4] and route[1] != route[2]
		var route_key := str(route)
		route_histogram[route_key] = int(route_histogram.get(route_key,0))+1
		if wave_count < 2000:
			deterministic = deterministic and run == Campaign.build_run(run_seed)
			immutable = immutable and _deep_frozen(run)
		for level_index in range(4):
			var level: Dictionary = run.levels[level_index]
			var previous_at := -1.0
			var previous_role := ""
			var previous_lane := -1
			var previous_sky := -1
			var rows := 0
			var row_index := -100
			var slots: Array = level.plans
			tier_rules = tier_rules and int(level.series_id) == int(route[level_index]) and int(level.level_index) == level_index and int(level.difficulty_tier) == level_index+1 and is_equal_approx(float(level.interval_base),float([4.3,4.0,3.7,3.4][level_index]))
			for slot_index in range(slots.size()):
				var value: Dictionary = slots[slot_index]
				wave_count += 1
				schedule = schedule and float(value.at_seconds) > previous_at and float(value.at_seconds) < float(level.duration) and float(value.interval) > 0.0 and float(value.minimum_distance) >= 40.0
				previous_at = float(value.at_seconds)
				var demand: Dictionary = Encounters.demand_for(value)
				var fit: bool = bool(Encounters.admission(value).allowed) and demand == value.demand
				if not fit and first_failure.is_empty(): first_failure = {"seed":run_seed,"level":level_index,"slot":slot_index,"plan":value}
				budgets = budgets and fit
				var used_ground: Array = []
				var used_sky: Array = []
				for item: Dictionary in value.spawns:
					var lane := int(item.lane)
					lanes = lanes and lane >= 0 and lane <= 3 and lane not in used_ground
					used_ground.append(lane)
					warmed = warmed and str(item.kind) in level.catalog and str(item.kind) in run.catalog
				for item: Dictionary in value.sky_spawns:
					var lane := int(item.sky_lane)
					lanes = lanes and lane >= 0 and lane <= 2 and lane not in used_sky and bool(Encounters.kind_profile(str(item.kind)).flying)
					used_sky.append(lane)
					warmed = warmed and str(item.kind) in level.catalog and str(item.kind) in run.catalog
				if value.id == "four_lane_row":
					rows += 1
					lanes = lanes and int(level.series_id) == 1 and slot_index-row_index > 4 and value.spawns.size() == 4 and value.sky_spawns.is_empty() and bool(value.exclusive) and bool(value.hold_until_clear)
					row_index = slot_index
				else:
					budgets = budgets and int(demand.ground) <= 3
					if not value.spawns.is_empty(): lanes = lanes and int(value.spawns[0].lane) != previous_lane
				if not value.sky_spawns.is_empty(): lanes = lanes and int(value.sky_spawns[0].sky_lane) != previous_sky
				if not str(value.lead_role).is_empty():
					role_repeat = role_repeat and str(value.lead_role) != previous_role
					previous_role = str(value.lead_role)
				if not value.spawns.is_empty(): previous_lane = int(value.spawns[0].lane)
				if not value.sky_spawns.is_empty(): previous_sky = int(value.sky_spawns[0].sky_lane)
			budgets = budgets and rows <= 1 and rows == int(level.rare_four_rows) and slots.back().phase == "breather"
			var expected_stages: Array = Encounters.get_series_definition(int(level.series_id)).boss_stages
			bosses = bosses and level.boss_stages == expected_stages and level.boss_stage_policies.size() == expected_stages.size()
			for stage_index in range(expected_stages.size()):
				var policy: Dictionary = level.boss_stage_policies[stage_index]
				bosses = bosses and bool(policy.ordered) and bool(policy.exclusive) and int(policy.max_active) == 1 and policy.max_active_semantics == "attacking" and int(policy.attack_budget) == 1 and int(policy.max_units) == expected_stages[stage_index].size() and policy.transition == "all_members_structurally_defeated"
				for kind: String in expected_stages[stage_index]: warmed = warmed and kind in level.catalog
	_expect(route_ok and route_histogram.size() == 6,"four-level routes use two distinct middle series and cover all six permutations",{"seeds":sampled_seeds.size(),"routes":route_histogram})
	_expect(deterministic,"equal seeds recreate equal complete run plans")
	_expect(immutable,"prepared dictionaries and every nested array are read-only")
	_expect(schedule,"all planned slots are finite and strictly within each level duration",{"waves":wave_count})
	_expect(budgets,"every slot fits ground/sky/shooter/heavy/threat/projectile budgets and rare-row exceptions",first_failure)
	_expect(lanes,"lanes are valid, unique within a group and avoid repeated lead-lane pressure")
	_expect(role_repeat,"successive lead roles do not repeat")
	_expect(warmed,"all minion, support and Boss kinds are present in prepared warm catalogs")
	_expect(bosses,"Boss groups permit the four-officer formation but one attacking member; heavy stages remain separate")
	_expect(tier_rules,"cadence and budgets follow appearance tier rather than series identity")
	_check_admission()
	_check_rng_isolation()
	_check_legacy()
	_check_public_boundaries()
	var result := {"scope":"pure immutable planner data only; no actors/mesh/AI/battle/clear simulation","engine":Engine.get_version_info(),"seed_samples":sampled_seeds.size(),"waves":wave_count,"checks":checks,"failures":failures,"source":{}}
	for path: String in ["res://scripts/campaign_director.gd","res://scripts/encounter_director.gd","res://tools/campaign_director_verify.gd"]:
		result.source[path] = FileAccess.get_sha256(path)
	if not output_path.is_empty():
		DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
		var file := FileAccess.open(output_path,FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(result,"\t"))
		else: failures += 1
	print("Campaign planner: ",checks.size()," checks, ",failures," failures, ",wave_count," pure slots")
	quit(0 if failures == 0 else 1)


func _check_admission() -> void:
	var run := Campaign.build_run(170917)
	var ordinary: Dictionary = run.levels[0].plans[0]
	var queued := {"ground":3,"sky":0,"shooters":0,"heavy":0,"advanced":0,"threat":0.0,"projectiles":0}
	var boundaries := not bool(Encounters.admission(ordinary,queued).allowed)
	boundaries = boundaries and not bool(Encounters.admission(ordinary,{"advanced":1}).allowed)
	var advanced: Dictionary = {}
	for value: Dictionary in run.levels[0].plans:
		if bool(value.advanced_intro): advanced = value
	boundaries = boundaries and not advanced.is_empty() and not bool(Encounters.admission(advanced,{"sky":1}).allowed)
	var shooter: Dictionary = run.levels[0].plans[1]
	boundaries = boundaries and not bool(Encounters.admission(shooter,{"shooters":2}).allowed)
	boundaries = boundaries and not bool(Encounters.admission(shooter,{"projectiles":24}).allowed)
	boundaries = boundaries and not bool(Encounters.admission(shooter,{"projectiles":23,"projectile_reservation":1}).allowed)
	_expect(boundaries,"live actors plus queued reservations block over-budget and advanced overlap")


func _check_rng_isolation() -> void:
	seed(88170917)
	var first := randi()
	var second := randi()
	seed(88170917)
	var before := randi()
	Campaign.build_run(-170917)
	var after := randi()
	_expect(first == before and second == after,"preparing a campaign does not consume global weapon/particle RNG")


func _check_legacy() -> void:
	var baseline := Encounters.plan(0,0.0,18.0,180.0)
	var row := Encounters.plan(22,75.0/180.0,18.0,180.0)
	var advanced := Encounters.plan(13,50.0/180.0,18.0,180.0)
	_expect(baseline.spawns[0].kind == "normal" and baseline.spawns[0].lane == 1 and is_equal_approx(float(baseline.interval),4.3) and row.id == "four_lane_row" and advanced.spawns[0].kind == "interceptor","the legacy plan API retains its baseline and exceptional slots")


func _check_public_boundaries() -> void:
	var seed_value := 170917
	var run := Campaign.build_run(seed_value)
	var changed := Campaign.build_run(seed_value,{"durations":[180.0,90.0,90.0,100.0]})
	var independent: bool = run.route == changed.route
	for index in range(1,4): independent = independent and run.levels[index] == changed.levels[index]
	_expect(independent,"changing one level duration cannot reroll the route or later levels")
	var valid := true
	for duration in [45.0,180.0]:
		for series_id in range(1,6):
			for tier in range(1,5):
				var level: Dictionary = Encounters.build_level(series_id,tier,seed_value,{"duration":duration})
				var previous := -1.0
				for value: Dictionary in level.plans:
					valid = valid and float(value.at_seconds) > previous and float(value.at_seconds) < duration and float(value.latest_seconds) >= float(value.at_seconds) and float(value.latest_seconds) <= duration and bool(Encounters.admission(value).allowed)
					previous = float(value.at_seconds)
	_expect(valid,"minimum and maximum duration options retain finite admissible schedules for every series and tier")
	var director := Campaign.new()
	var prepared: Dictionary = director.prepare_run(seed_value)
	var getters: bool = prepared == run and director.get_route() == run.route and director.get_level_plans() == run.levels and director.get_catalog() == run.catalog and director.get_level_plan(-1).is_empty() and director.get_level_plan(4).is_empty()
	getters = getters and Encounters.build_level(0,1,seed_value).is_empty() and Encounters.plan_for_series(2,-1,0.0,18.0).is_empty() and Encounters.plan_for_series(2,10000,1.0,18.0).is_empty()
	getters = getters and Encounters.plan_for_series(2,4,0.1,18.0,90.0,2,seed_value) == Encounters.plan_for_series(2,4,0.9,18.0,90.0,2,seed_value)
	_expect(getters,"public getters and compatibility queries preserve prepared slots and reject invalid indices")
