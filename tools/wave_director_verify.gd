extends SceneTree
## Pure schedule contracts. These do not instantiate enemies or prove the
## main scene's live budget, attack timing, rendered layout or difficulty.

const Director = preload("res://scripts/encounter_director.gd")
var output_path := ""
var require_packed := false
var checks: Array[Dictionary] = []
var observations: Dictionary = {}
var failures := 0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--wave-output="): output_path = argument.trim_prefix("--wave-output=")
		elif argument == "--require-packed": require_packed = true
	if output_path.is_empty(): output_path = ProjectSettings.globalize_path("res://builds/wave-review-v098/data.json")
	call_deferred("_run")


func expect(passed: bool, label: String, detail: Dictionary = {}) -> void:
	checks.append({"passed":passed,"label":label,"detail":detail})
	if passed: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)


func _manifest() -> Dictionary:
	var path := "res://scripts/encounter_director.gd"
	var raw := FileAccess.file_exists(path)
	var runtime := path if raw else ""
	if not raw and FileAccess.file_exists(path+".remap"):
		var config := ConfigFile.new()
		if config.load(path+".remap") == OK: runtime = str(config.get_value("remap","path",""))
	return {path:{"raw_exists":raw,"runtime_path":runtime,"sha256":FileAccess.get_sha256(runtime) if not runtime.is_empty() else ""}}


func _opening_contract() -> void:
	var first: Dictionary = Director.plan(0,0.01,18.0)
	var pair: Dictionary = Director.plan(1,0.10,18.0)
	var row: Dictionary = Director.plan(2,0.20,18.0)
	expect(first.id == "opening_single" and first.spawns.size() == 1 and first.spawns[0].kind == "normal","the opening teaches one ordinary melee enemy")
	expect(pair.id == "staggered_pair" and pair.spawns.size() == 2 and pair.spawns[0].z_offset != pair.spawns[1].z_offset,"the second group separates two ordinary enemies in depth")
	var lanes: Array = []
	var delays: Array = []
	var all_normal := true
	var all_aligned := true
	for spawn: Dictionary in row.spawns:
		lanes.append(int(spawn.lane))
		delays.append(float(spawn.attack_delay))
		all_normal = all_normal and spawn.kind == "normal"
		all_aligned = all_aligned and is_zero_approx(float(spawn.z_offset))
	expect(row.id == "four_lane_row" and all_normal and all_aligned and lanes == [0,1,2,3],"the third group is four real lane slots at exactly the same depth",{"lanes":lanes,"offsets":row.spawns})
	# Two actual guard windows can cover the two attack pairs. The main-scene
	# fixture separately verifies these offsets reach real damage phases.
	var first_guard := float(delays[0])-0.06
	var second_guard := float(delays[2])-0.06
	var guardable := second_guard-first_guard >= 0.40
	for index in range(4):
		var start := first_guard if index < 2 else second_guard
		guardable = guardable and float(delays[index]) >= start and float(delays[index]) <= start+0.30
	expect(guardable,"four-row proposals fit two 0.30s guard windows separated by the 0.40s cooldown",{"delays":delays,"guard_starts":[first_guard,second_guard]})
	expect(is_equal_approx(float(first.interval),6.0) and is_equal_approx(float(pair.interval),6.0) and float(row.interval) >= 8.0 and float(row.lead_seconds) >= 3.0 and float(row.recovery_seconds) >= 1.2,"the row has a longer approach and a recovery gap after its two simple opening lessons")
	observations["opening"] = [first,pair,row]


func _schedule_matrix() -> void:
	var valid_lanes := true
	var readable_groups := true
	var single_complex := true
	var lessons_gated := true
	var shields_reserved := true
	var recovery := true
	var deterministic := true
	var samples := 0
	var kinds: Dictionary = {}
	for progress in [0.0,0.10,0.29,0.30,0.49,0.50,0.74,0.75,0.99]:
		for speed in [4.0,18.0,60.0]:
			for wave in range(36):
				var proposed: Dictionary = Director.plan(wave,progress,speed)
				samples += 1
				deterministic = deterministic and proposed == Director.plan(wave,progress,speed)
				readable_groups = readable_groups and proposed.spawns.size() > 0 and proposed.spawns.size() <= 4
				recovery = recovery and float(proposed.interval) >= 6.0 and float(proposed.recovery_seconds) >= 1.0 and proposed.hold_until_clear and int(proposed.heavy_ranged_cap) == 1
				var complex_count := 0
				for spawn: Dictionary in proposed.spawns:
					kinds[str(spawn.kind)] = true
					valid_lanes = valid_lanes and int(spawn.lane) >= 0 and int(spawn.lane) < 4 and float(spawn.z_offset) <= 0.0 and float(spawn.attack_delay) >= 0.0
					if spawn.kind in Director.COMPLEX_RANGED:
						complex_count += 1
						readable_groups = readable_groups and float(spawn.fire_delay) >= 0.65
					if spawn.kind == "interceptor": lessons_gated = lessons_gated and float(progress) >= 0.30
					if spawn.kind == "mine_layer": lessons_gated = lessons_gated and float(progress) >= 0.50
					shields_reserved = shields_reserved and spawn.kind != "shield_drone"
				single_complex = single_complex and complex_count <= 1
	expect(valid_lanes,"all sampled groups stay on four legal lane slots and preserve explicit depth/attack offsets",{"samples":samples})
	expect(readable_groups,"all sampled groups contain at most four enemies and ranged lessons request extra first-shot notice")
	expect(single_complex,"no proposed ordinary group stacks more than one complex shooter")
	expect(lessons_gated,"interceptors wait until 30 percent and miners until 50 percent of the route")
	expect(shields_reserved,"ordinary waves reserve shield craft for the Boss's separate escort encounter")
	expect(recovery,"all groups request live-clearance, one-shooter cap and real recovery time")
	expect(deterministic,"the proposal is deterministic across progress, speed and index samples")
	expect(kinds.has("normal") and kinds.has("ranged") and kinds.has("drone") and kinds.has("interceptor") and kinds.has("mine_layer") and kinds.has("missile_drone") and kinds.has("tank") and kinds.has("beam") and kinds.has("barrier"),"later proposals still cover the established enemy and obstacle roles",{"kinds":kinds.keys()})
	observations["matrix"] = {"samples":samples,"kinds":kinds.keys()}


func _timeline_contract() -> void:
	var routes: Array = []
	for duration in [20.0,60.0,180.0]:
		var time := 2.8
		var wave := 0
		var timeline: Array = []
		var saw_row := false
		var gated := true
		while time < duration and wave < 100:
			var progress: float = time / duration
			var proposed: Dictionary = Director.plan(wave,progress,18.0)
			saw_row = saw_row or proposed.id == "four_lane_row"
			for spawn: Dictionary in proposed.spawns:
				if spawn.kind == "interceptor": gated = gated and progress >= 0.30
				if spawn.kind == "mine_layer": gated = gated and progress >= 0.50
			timeline.append({"time":time,"wave":wave,"id":proposed.id,"kinds":proposed.spawns.map(func(row: Dictionary): return row.kind)})
			time += float(proposed.interval)
			wave += 1
		expect(saw_row and gated,"the "+str(int(duration))+"s nominal schedule exposes a row and respects progressive lessons",{"waves":wave})
		routes.append({"duration":duration,"timeline":timeline,"scope":"Nominal schedule only. The actual main-scene live-clearance budget can postpone proposals."})
	observations["nominal_routes"] = routes


func _run() -> void:
	var before := _manifest()
	if require_packed:
		var row: Dictionary = before["res://scripts/encounter_director.gd"]
		expect(not row.raw_exists and not str(row.runtime_path).is_empty() and str(row.runtime_path) != "res://scripts/encounter_director.gd" and not str(row.sha256).is_empty(),"standalone schedule uses its exported compiled resource without raw source fallback",row)
	_opening_contract()
	_schedule_matrix()
	_timeline_contract()
	var changed: Dictionary = Director.plan(2,0.20,18.0)
	changed.spawns[0].lane = 99
	expect(Director.plan(2,0.20,18.0).spawns[0].lane == 0,"mutating one returned proposal cannot corrupt future waves")
	expect(Director.plan(-8,-0.5,-10.0) == Director.plan(0,0.0,4.0),"out-of-range scheduling inputs clamp to the safe opening")
	var after := _manifest()
	expect(before == after,"the runtime director stays unchanged during schedule verification")
	var report := {"version":ProjectSettings.get_setting("application/config/version"),"checks":checks,"failures":failures,"observations":observations,"tool_sha256":FileAccess.get_sha256(get_script().resource_path),"runtime_manifest_before":before,"runtime_manifest_after":after,"scope":"Pure deterministic proposal data. No instantiated actors, collision/attack/budget integration, native pixels, real-time performance or human difficulty acceptance."}
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var file := FileAccess.open(output_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("WAVE DIRECTOR VERIFY: ",checks.size()," checks / ",failures," failures")
	quit(0 if failures == 0 else 1)
