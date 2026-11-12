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


func _baseline_contract() -> void:
	# Independent literals transcribed from df8c420:scripts/main.gd866-884.
	var sequence := ["normal","ranged","drone","normal","barrier","tank","missile_drone","ranged","beam","drone","normal","tank"]
	var lanes := [1,2,0,3,2,1,0,2]
	var core := true
	var cadence := true
	var shape := true
	var streaming := true
	var telegraph := true
	var shield_reserved := true
	var deterministic := true
	var samples := 0
	for elapsed in [0.0,20.0,39.99,40.0,50.0,75.0,75.01,90.0,130.0,180.0]:
		for speed in [4.0,18.0,60.0]:
			for index in range(48):
				var value: Dictionary = Director.plan(index,float(elapsed)/180.0,speed,180.0)
				deterministic = deterministic and value == Director.plan(index,float(elapsed)/180.0,speed,180.0)
				for item: Dictionary in value.spawns: shield_reserved = shield_reserved and item.kind != "shield_drone"
				for item: Dictionary in value.sky_spawns: shield_reserved = shield_reserved and item.kind != "shield_drone"
				var sky: bool = (index == 9 and elapsed >= 20.0) or (index == 26 and elapsed >= 90.0) or (index == 42 and elapsed >= 150.0)
				var special: bool = sky or (index == 22 and elapsed >= 75.0) or (index == 13 and elapsed >= 50.0) or (index == 25 and elapsed >= 90.0) or (index == 37 and elapsed >= 130.0)
				if special: continue
				samples += 1
				var kind: String = sequence[index%12]
				var lane: int = lanes[index%8]
				if kind == "tank": lane = 0 if index%2 == 0 else 2
				var first: Dictionary = value.spawns[0]
				core = core and first.kind == kind and int(first.lane) == lane and is_equal_approx(float(value.lead_seconds),2.0) and is_equal_approx(float(value.minimum_distance),40.0) and is_zero_approx(float(value.approach_speed_offset)) and is_equal_approx(float(value.distance_bias),12.0)
				cadence = cadence and is_equal_approx(float(value.interval),4.3 if elapsed < 40.0 else 3.5)
				streaming = streaming and not value.hold_until_clear and is_zero_approx(float(value.recovery_seconds))
				var follow: bool = elapsed > 75.0 and (index+1)%4 == 0 and kind not in ["barrier","beam"]
				shape = shape and value.spawns.size() == (2 if follow else 1) and is_zero_approx(float(first.z_offset)) and is_zero_approx(float(first.attack_delay))
				if follow and value.spawns.size() == 2:
					var second: Dictionary = value.spawns[1]
					shape = shape and second.kind == "normal" and int(second.lane) == (lane+2)%4 and is_equal_approx(float(second.z_offset),-14.0) and is_zero_approx(float(second.attack_delay))
				var first_delay := 0.25 if kind in ["ranged","drone","missile_drone"] else 0.0
				telegraph = telegraph and is_equal_approx(float(first.fire_delay),first_delay)
	expect(core,"unmodified slots preserve the exact095 kind/lane and speed-times-two-plus12 approach",{"sampled_unmodified_slots":samples})
	expect(cadence,"the0954.3s-before40/3.5s-after40 cadence stays intact outside the single row")
	expect(shape,"the095post75s every-fourth-wave normal follower retains lane-plus-two and minus14m offset")
	expect(streaming,"ordinary slots preserve a timed overlapping stream rather than waiting for global clearance")
	expect(telegraph,"legacy ranged slots request only the agreed0.25s first-shot notice")
	expect(shield_reserved,"all ordinary schedule slots reserve shield craft for Boss escorts")
	expect(deterministic,"the095-based schedule is deterministic across the sampled inputs")
	observations["baseline"] = {"commit":"df8c42099ad78f778b11ba8d8430cb1470f3a425","samples":samples,"sequence":sequence,"lanes":lanes}


func _special_slots() -> void:
	var gated := true
	var rare := true
	var notice := true
	for item in [{"index":13,"time":50.0,"kind":"interceptor"},{"index":25,"time":90.0,"kind":"mine_layer"},{"index":37,"time":130.0,"kind":"interceptor"}]:
		var before: Dictionary = Director.plan(int(item.index),(float(item.time)-0.01)/180.0,18.0,180.0)
		var after: Dictionary = Director.plan(int(item.index),float(item.time)/180.0,18.0,180.0)
		gated = gated and before.spawns[0].kind == "ranged" and not before.advanced_intro and after.spawns[0].kind == item.kind and after.advanced_intro
		rare = rare and after.spawns.size() == 1 and not after.hold_until_clear and is_equal_approx(float(after.interval),3.5)
		notice = notice and is_zero_approx(float(after.spawns[0].fire_delay))
	for index in [1,49,61,73]:
		var value: Dictionary = Director.plan(index,1.0,18.0,180.0)
		rare = rare and not value.advanced_intro
	expect(gated,"only the13/25/37 ranged slots become advanced craft after50/90/130seconds")
	expect(rare,"advanced replacements are single-slot substitutions and do not recur each sequence loop")
	expect(notice,"restored craft do not receive the post097 extra first-shot delay")
	var row: Dictionary = Director.plan(22,0.5,18.0,180.0)
	var lanes: Array = []
	var delays: Array = []
	var aligned: bool = row.spawns.size() == 4
	for item: Dictionary in row.spawns:
		lanes.append(int(item.lane));delays.append(float(item.attack_delay))
		aligned = aligned and item.kind == "normal" and is_zero_approx(float(item.z_offset))
	for index in [2,10,34,46,58]: aligned = aligned and Director.plan(index,1.0,18.0,180.0).id != "four_lane_row"
	aligned = aligned and Director.plan(22,74.99/180.0,18.0,180.0).id != "four_lane_row"
	expect(aligned and lanes == [0,1,2,3],"one post75s normal slot22 becomes the only four-lane aligned row",{"lanes":lanes,"delays":delays})
	var guardable := delays.size() == 4
	if guardable:
		var first := float(delays[0])-0.06
		var second := float(delays[2])-0.06
		guardable = second-first >= 0.40
		for index in range(4):
			var start := first if index < 2 else second
			guardable = guardable and float(delays[index]) >= start and float(delays[index]) <= start+0.30
	expect(guardable,"the exceptional row still fits two0.30s guards separated by the0.40s cooldown")
	expect(row.hold_until_clear and is_equal_approx(float(row.interval),4.8) and is_equal_approx(float(row.recovery_seconds),1.2) and is_equal_approx(float(row.lead_seconds),2.4),"only that row requests a clear window and its explicit recovery")
	observations["exceptions"] = {"row":row,"advanced_indices":[13,25,37]}


func _sky_slots() -> void:
	# Independent expected slots, not the production constant. This contract
	# covers proposal data only; live admission, safe retirement and sustained
	# fire remain main-scene responsibilities and are not simulated here.
	var expected := [{"index":9,"time":20.0,"kind":"drone","lane":1},{"index":26,"time":90.0,"kind":"drone","lane":0},{"index":42,"time":150.0,"kind":"missile_drone","lane":2}]
	var gated := true
	var substitution := true
	var cadence := true
	var isolated := true
	for item: Dictionary in expected:
		var before: Dictionary = Director.plan(int(item.index),(float(item.time)-0.01)/180.0,18.0,180.0)
		var after: Dictionary = Director.plan(int(item.index),float(item.time)/180.0,18.0,180.0)
		gated = gated and before.sky_spawns.is_empty() and before.spawns.size() == 1 and before.spawns[0].kind == item.kind
		var correct: bool = after.sky_spawns.size() == 1
		if correct:
			var sky: Dictionary = after.sky_spawns[0]
			correct = sky.kind == item.kind and int(sky.sky_lane) == int(item.lane)
		substitution = substitution and correct and after.spawns.is_empty() and not after.advanced_intro and after.baseline_kind == item.kind
		cadence = cadence and not after.hold_until_clear and is_zero_approx(float(after.recovery_seconds)) and is_equal_approx(float(after.interval),4.3 if item.time < 40.0 else 3.5) and is_equal_approx(float(after.lead_seconds),2.0)
	for elapsed in [0.0,19.99,20.0,75.0,90.0,149.99,150.0,180.0]:
		for index in range(96):
			var value: Dictionary = Director.plan(index,float(elapsed)/180.0,18.0,180.0)
			isolated = isolated and value.has("sky_spawns") and value.sky_spawns.size() <= 1
			for sky: Dictionary in value.sky_spawns:
				isolated = isolated and sky.kind in ["drone","missile_drone"] and int(sky.sky_lane) in [0,1,2] and index in [9,26,42] and elapsed >= 20.0
	var changed: Dictionary = Director.plan(9,20.0/180.0,18.0,180.0)
	changed.sky_spawns[0].sky_lane = 99
	var fresh := int(Director.plan(9,20.0/180.0,18.0,180.0).sky_spawns[0].sky_lane) == 1
	expect(gated,"only sky slots9/26/42 activate after their20/90/150second gates")
	expect(substitution,"each sky slot substitutes one original flyer and uses lanes1/0/2 without a ground duplicate")
	expect(cadence,"optional sky substitutions keep the ordinary timed cadence and never request an all-clear hold")
	expect(isolated,"every proposal has sky_spawns and only the three one-time flyer slots can use sky lanes0..2")
	expect(fresh,"mutating a returned sky spawn cannot corrupt the fixed sky schedule")
	observations["sky_slots"] = expected


func _timeline_contract() -> void:
	var routes: Array = []
	for duration in [20.0,60.0,180.0]:
		var time := 2.8
		var index := 0
		var row_count := 0
		var advanced := 0
		var sky_count := 0
		var gated := true
		var timeline: Array = []
		while time < float(duration)-0.00001 and index < 100:
			var value: Dictionary = Director.plan(index,time/float(duration),18.0,float(duration))
			if value.id == "four_lane_row": row_count += 1
			if value.advanced_intro:
				advanced += 1
				gated = gated and ((index == 13 and time >= 50.0) or (index == 25 and time >= 90.0) or (index == 37 and time >= 130.0))
			sky_count += value.sky_spawns.size()
			timeline.append({"time":time,"index":index,"id":value.id,"count":value.spawns.size(),"sky_count":value.sky_spawns.size()})
			time += float(value.interval)
			index += 1
		var correct := row_count == (1 if duration == 180.0 else 0) and gated and advanced <= (3 if duration == 180.0 else (1 if duration == 60.0 else 0))
		expect(correct,"the "+str(int(duration))+"s nominal stream has no forced opening row and at most the agreed rare substitutions",{"waves":index,"rows":row_count,"advanced":advanced})
		expect(sky_count == (3 if duration == 180.0 else (1 if duration == 60.0 else 0)),"the "+str(int(duration))+"s nominal stream adds only its eligible sparse sky substitutions",{"sky_proposals":sky_count})
		routes.append({"duration":duration,"timeline":timeline,"scope":"Nominal timed proposals only; main-scene admission limits can postpone a slot."})
	observations["nominal_routes"] = routes

func _run() -> void:
	var before := _manifest()
	if require_packed:
		var row: Dictionary = before["res://scripts/encounter_director.gd"]
		expect(not row.raw_exists and not str(row.runtime_path).is_empty() and str(row.runtime_path) != "res://scripts/encounter_director.gd" and not str(row.sha256).is_empty(),"standalone schedule uses its exported compiled resource without raw source fallback",row)
	_baseline_contract()
	_special_slots()
	_sky_slots()
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
