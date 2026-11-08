extends "combat_expansion_verify.gd"
## Controlled production transitions and attack scheduling. No rendered,
## performance, normal-difficulty or subjective-feel verdict is implied.

const DEPENDENCIES := [
	"res://scenes/main.tscn", "res://scripts/main.gd", "res://scripts/voxel_enemy.gd",
	"res://scripts/encounter_director.gd", "res://scripts/enemy_archetypes.gd",
	"res://scripts/enemy_motion.gd", "res://scripts/projectile_view.gd",
	"res://scripts/projectile_geometry.gd", "res://scripts/voxel_blast.gd",
]
const OLD_KINDS := ["normal","tank","ranged","drone","missile_drone","shield_drone","interceptor","mine_layer","barrier","beam"]
const STEP := 1.0/60.0
var require_packed := false
var manifests_before: Dictionary = {}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--flow-output="): output_path = argument.trim_prefix("--flow-output=")
		elif argument == "--require-packed": require_packed = true
	if output_path.is_empty(): output_path = ProjectSettings.globalize_path("res://builds/encounter-review-v098/flow.json")
	call_deferred("_run")


func _manifest() -> Dictionary:
	var result: Dictionary = {}
	for path: String in DEPENDENCIES:
		var raw := FileAccess.file_exists(path)
		var runtime: String = path if raw else ""
		if not raw and FileAccess.file_exists(path+".remap"):
			var mapping := ConfigFile.new()
			if mapping.load(path+".remap") == OK: runtime = str(mapping.get_value("remap","path",""))
		result[path] = {"raw_exists":raw,"runtime_path":runtime,"sha256":FileAccess.get_sha256(runtime) if not runtime.is_empty() and FileAccess.file_exists(runtime) else ""}
	return result


func _escorts() -> Array:
	var found: Array = []
	for enemy in game.enemies:
		if is_instance_valid(enemy) and not enemy.dead and bool(enemy.get_meta("boss_escort",false)): found.append(enemy)
	return found


func _ids(actors: Array) -> Array:
	var result: Array = []
	for actor in actors:
		if is_instance_valid(actor): result.append(actor.get_instance_id())
	result.sort()
	return result


func _new_events(start: int, name: String) -> Array:
	var result: Array = []
	for index in range(start,game.combat_events.size()):
		if str(game.combat_events[index].event)==name: result.append(game.combat_events[index])
	return result


func _retire_step(seconds: float) -> void:
	for _frame in range(int(ceil(seconds/STEP))): game._update_retiring_enemies(STEP,1.0)


func _key(code: Key) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _verify_boss_entry() -> void:
	_reset()
	# Earn a real pre-transition score and leave a dead owner with its debris.
	var slain = game._spawn_enemy("normal",1,-8.0)
	slain.blast_at(slain.get_aim_point(),12.0)
	var originals: Array = [slain]
	var retired_alive: Array = []
	var material: Dictionary = {}
	for kind: String in OLD_KINDS:
		var actor = game._spawn_enemy(kind,1,-2.1)
		originals.append(actor)
		retired_alive.append(actor)
		material[actor.get_instance_id()] = actor.get_remaining_voxel_count()
	var original_ids := _ids(originals)
	game._spawn_projectile(Vector3(0,1.65,-1.0),"bolt",originals[1])
	var returned = game._spawn_projectile(Vector3(0,1.65,-1.1),"mine",originals[2])
	game.projectiles[1].reflected = true
	returned.set_reflected()
	game._spawn_blast(Vector3(0,1.65,-1.0),1.0,true)
	var health: int = game.health
	var speed: float = game.speed
	var score: int = game.score
	var kills: int = game.kills
	var combo: int = game.combo
	game.hit_stop = 0.0
	game._spawn_boss()
	var active_ids := _ids(game.enemies)
	var old_active := false
	for identifier in original_ids: old_active = old_active or identifier in active_ids
	expect(not old_active and is_instance_valid(game.boss_enemy) and not game.boss_enemy.dead and _escorts().size()==2,"Boss entry removes every old lane actor from active combat and creates exactly two escorts",{"old_ids":original_ids,"active_ids":active_ids,"retiring":game.retiring_enemies.size()})
	expect(game.projectiles.is_empty() and game.health==health and is_equal_approx(game.speed,speed),"Boss entry cancels hostile and reflected pending shots without damage or an artificial speed loss")
	expect(game.score==score and game.kills==kills and game.combo==combo and game.victory_timer<0.0,"entry self-destruction never grants a ghost kill, combo, score or premature Boss victory")
	var all_disabled := true
	var material_preserved := true
	for actor in retired_alive:
		if not is_instance_valid(actor): continue
		all_disabled = all_disabled and bool(actor.get_meta("encounter_retired",false)) and not actor._configured and actor.resolved and not actor.dead
		material_preserved = material_preserved and actor.get_remaining_voxel_count()==int(material[actor.get_instance_id()])
	expect(all_disabled and material_preserved,"retirement disables old attacks immediately without pretending a structural death or deleting actual cells")
	var retired_normal = retired_alive[0]
	if is_instance_valid(retired_normal):
		var late: Dictionary = retired_normal.blast_at(retired_normal.get_aim_point(),12.0)
		expect(int(late.removed)==0 and game.score==score and game.kills==kills,"a late actual blast callback on a retired owner cannot farm damage or score")
	game._update_projectiles(1.0)
	_retire_step(2.0)
	await process_frame
	expect(game.retiring_enemies.is_empty() and game.health==health and game.score==score and game.kills==kills,"staggered retirement finishes with no late hit, score or lingering enemy queue")
	expect(game.blasts.size()<=game.MAX_BLASTS and VoxelDebris.CutVoxelBurst.global_active_count<=VoxelDebris.CUT_PARTICLE_GLOBAL_CAPACITY,"mass self-destruction respects the existing finite visual budgets")
	observations["boss_entry"] = {"old_actor_count":original_ids.size(),"score_before":score,"score_after":game.score,"kills_before":kills,"kills_after":game.kills,"health":game.health,"speed":game.speed,"active_ids":active_ids}


func _verify_f3_and_restart() -> void:
	_reset()
	game._spawn_enemy("mine_layer",1,-4.0)
	_key(KEY_F3)
	var first := _ids(game.enemies)
	var queued: int = game.retiring_enemies.size()
	for _press in range(4): _key(KEY_F3)
	expect(first.size()==3 and _ids(game.enemies)==first and game.retiring_enemies.size()==queued,"repeated real F3 input leaves the same one Boss and two escorts instead of duplicating or refreshing them")
	expect(game.health==5 and game.kills==0 and game.score==0,"the Boss shortcut never pays the player for clearing an uncut route actor")
	game.start_game()
	expect(game.enemies.is_empty() and game.retiring_enemies.is_empty() and game.projectiles.is_empty() and not game.boss_spawned and game.victory_timer<0.0,"restart clears a pending entry transition and all encounter ownership")
	game.spawn_timer = 999.0


func _verify_escort_windows() -> void:
	_reset()
	game._spawn_boss()
	var boss = game.boss_enemy
	game._update_enemies(0.0,0.0)
	var escorts := _escorts()
	var initial_offsets: Dictionary = {}
	var visible := escorts.size()==2
	for escort in escorts:
		var side: int = int(escort.get_meta("escort_side",0))
		initial_offsets[side] = escort.position-boss.position
		var bounds: Rect2 = escort.get_screen_bounds(game.camera)
		visible = visible and escort.enemy_kind=="shield_drone" and side in [-1,1] and bounds.size.x>8 and bounds.size.y>8 and not game.camera.is_position_behind(escort.get_aim_point())
	expect(visible and initial_offsets.has(-1) and initial_offsets.has(1) and initial_offsets[-1].x<0.0 and initial_offsets[1].x>0.0,"two real cuttable shield escorts occupy the visible left and right Boss flanks")
	var start: int = game.combat_events.size()
	for _frame in range(120):
		game.game_clock += STEP
		game._update_enemies(STEP,1.0)
	expect(game.projectiles.is_empty(),"Boss escort introduction has an actual silent preparation interval")
	boss.position += Vector3(0.35,0,-1.5)
	game._update_enemies(STEP,1.0)
	var anchored := true
	for escort in escorts:
		var side: int = int(escort.get_meta("escort_side",0))
		anchored = anchored and (escort.position-boss.position).distance_to(initial_offsets[side])<0.01
	expect(anchored,"escort positions follow the Boss instead of advancing into a lane miss or melee lunge")
	var releases: Array = []
	var windows: Dictionary = {}
	var legal := true
	var last_side := 0
	var alternating := true
	var no_melee := true
	for _frame in range(4200):
		var before: int = game.combat_events.size()
		game.game_clock += STEP
		game._update_enemies(STEP,1.0)
		for event: Dictionary in _new_events(before,"projectile_spawn"):
			for escort in escorts:
				if int(event.enemy_id)!=escort.get_instance_id(): continue
				var pattern: int = game.boss_pattern
				var side: int = int(escort.get_meta("escort_side",0))
				legal = legal and str(boss.get_meta("action_state",""))=="recover" and pattern>0 and pattern%3==0 and str(event.projectile_kind)=="bolt"
				windows[pattern] = int(windows.get(pattern,0))+1
				alternating = alternating and (last_side==0 or side==-last_side)
				last_side = side
				releases.append({"world_time":game.game_clock,"side":side,"pattern":pattern,"action":str(boss.get_meta("action_state",""))})
		for escort in escorts:
			no_melee = no_melee and str(escort.get_meta("action_state","")) not in ["windup","strike","exit"] and escort.attack_done==0
		# Only examine dispatch scheduling here; flight, blade and reflection
		# are covered by their real ammunition fixtures, not this clock loop.
		game._clear_projectiles()
		if _frame%240==0: await process_frame
	var single_release := true
	for count in windows.values(): single_release = single_release and int(count)==1
	expect(releases.size()>=4 and legal and single_release,"escort fire occupies one dedicated recovery slot after every third Boss attack, never a stacked two-sided volley",{"releases":releases})
	expect(alternating,"surviving escorts alternate left and right support windows")
	expect(no_melee and game.health==5,"escort support never turns into an unavoidable near-player melee or lane-miss hit")
	observations["escort_windows"] = {"releases":releases,"relative_offsets":str(initial_offsets),"isolated_dispatch_scope":"Real production enemy phases and projectile spawning; shots cleared after each step to inspect scheduling independently of projectile flight."}


func _verify_escort_material_and_victory() -> void:
	_reset()
	game._spawn_boss()
	var boss = game.boss_enemy
	var escort = _escorts()[0]
	var initial: int = escort.get_remaining_voxel_count()
	var removed := 0
	for origin: Vector3 in escort.get_ranged_origins(): removed += int(escort.blast_at(origin,0.34).removed)
	expect(removed>0 and not escort.dead and escort.get_ranged_origins().is_empty() and not escort.has_attack_limb() and game.kills==0,"an escort's actual scaled launch mouth can be severed without a fake whole-machine kill",{"removed":removed,"initial":initial,"remaining":escort.get_remaining_voxel_count()})
	var boss_cells: int = boss.get_remaining_voxel_count()
	escort.blast_at(escort.get_aim_point(),12.0)
	expect(escort.dead and game.kills==1 and game.victory_timer<0 and boss.get_remaining_voxel_count()==boss_cells,"destroying one real escort awards only its own single kill while the Boss remains intact")
	for _frame in range(90): game._update_enemies(STEP,1.0)
	expect(_escorts().size()==1,"destroyed escorts do not respawn to invalidate the player's progress")
	var living_escort = _escorts()[0]
	game._spawn_projectile(Vector3(0,1.65,-1.0),"bolt",living_escort)
	var kills_before: int = game.kills
	game.health = 1
	var boss_kill: Dictionary = boss.blast_at(boss.get_aim_point(),12.0)
	expect(int(boss_kill.removed)>0 and boss.dead and game.kills==kills_before+1 and game.victory_timer>=0 and _escorts().is_empty() and game.projectiles.is_empty(),"real Boss destruction retires remaining support and clears its queued shot without an extra escort kill")
	var final_score: int = game.score
	for _frame in range(180): game._process(STEP)
	await process_frame
	expect(game.state=="won" and game.health==1 and game.kills==kills_before+1 and game.score==final_score and game.retiring_enemies.is_empty(),"Boss victory safely completes from one life without a late support hit, bonus score or residual retirement queue")


func _verify_four_lane_row() -> void:
	_reset()
	var director = load("res://scripts/encounter_director.gd")
	var plan: Dictionary = director.plan(2,0.15,game.speed)
	game._spawn_encounter_wave(plan)
	var actors: Array = game.enemies.duplicate()
	var lanes: Array = []
	var delays: Array[float] = []
	var line_z := INF
	var aligned := actors.size()==4
	for actor in actors:
		lanes.append(int(actor.lane_index))
		delays.append(float(actor.get_meta("wave_attack_delay",-1.0)))
		if line_z==INF: line_z = actor.position.z
		aligned = aligned and actor.enemy_kind=="normal" and is_equal_approx(actor.position.z,line_z) and is_equal_approx(actor.position.x,float(game.LANES[actor.lane_index]))
	lanes.sort()
	expect(aligned and lanes==[0,1,2,3],"the normal production wave creates four actual small enemies aligned across all four lanes",{"lanes":lanes,"z":line_z,"wave":plan.id})
	var starts: Array[float] = []
	for actor in actors:
		actor.position.z = -13.0
		game._start_melee(actor)
		starts.append(float(actor.get_meta("action_duration",0)))
	starts.sort()
	delays.sort()
	var phased := delays.size()==4 and starts.size()==4
	if phased:
		phased = delays[0]>=0 and starts[1]-starts[0]<0.30 and starts[2]-starts[1]>0.40 and starts[3]-starts[2]<0.30
	expect(phased,"the row's actual windup durations split damage into two readable parryable pairs rather than four simultaneous hits",{"configured_delays":delays,"windups":starts})
	var hp: int = game.health
	var impacts := 0
	for _frame in range(180):
		var before: int = game.health
		game._update_enemies(STEP,1.0)
		if game.health<before: impacts += before-game.health
	expect(impacts==4 and game.health==hp-4,"all four lanes still carry one real unblocked miss each; formation staging does not silently grant invulnerability",{"damage":impacts,"remaining_life":game.health})
	observations["four_lane_row"] = {"plan":plan,"lanes":lanes,"windups":starts,"miss_damage":impacts}


func _verify_new_flyer_pressure() -> void:
	var rows: Array = []
	const DT := 1.0/240.0
	for gear_value in [1,4]:
		for kind: String in ["interceptor","mine_layer"]:
			_reset()
			game.speed = 18.0 if gear_value==1 else 60.0
			game.gear = gear_value
			var enemy = game._spawn_enemy(kind,1,-34.0)
			var extra := 0.65 if kind=="interceptor" else 0.85
			enemy.set_meta("first_charge_extra",extra)
			var clock := 0.0
			var charge_started := -1.0
			var charge_ended := -1.0
			var declared_charge := 0.0
			var releases: Array = []
			var seen: Dictionary = {}
			var exited_fire := false
			for _frame in range(1920):
				var mouths: Array = enemy.get_ranged_origins().duplicate()
				clock += DT
				game.game_clock += DT
				game._update_enemies(DT,1.0)
				var action: String = str(enemy.get_meta("action_state",""))
				if action=="ranged_charge" and charge_started<0.0:
					charge_started = clock
					declared_charge = float(enemy.get_meta("action_duration",0.0))
				if action=="ranged_fire" and charge_ended<0.0: charge_ended = clock
				for shot: Dictionary in game.projectiles:
					var identifier: int = shot.node.get_instance_id()
					if seen.has(identifier): continue
					seen[identifier] = true
					var origin: Vector3 = shot.node.global_position
					var mouth_distance := INF
					for mouth: Vector3 in mouths: mouth_distance = minf(mouth_distance,mouth.distance_to(origin))
					releases.append({"time":clock,"actor_z":enemy.position.z,"origin":origin,"origin_z":origin.z,"source_matches":shot.source==enemy,"kind":str(shot.kind),"mouth_distance":mouth_distance,"velocity":shot.velocity})
				if charge_ended>=0.0 and action!="ranged_fire":
					exited_fire = true
					break
			var minimum := (0.85 if kind=="interceptor" else 1.25)+extra
			var actual_charge := charge_ended-charge_started
			expect(exited_fire and charge_started>=0 and declared_charge>=minimum-0.001 and actual_charge>=minimum-DT*2.0 and is_zero_approx(float(enemy.get_meta("first_charge_extra",-1.0))),kind+" gear"+str(gear_value)+" first attack gives its real full charge plus one-time formation tell",{"declared":declared_charge,"observed":actual_charge,"minimum":minimum})
			var far_release := releases.size()==2
			var actual_mouths := releases.size()==2
			for release: Dictionary in releases:
				far_release = far_release and float(release.actor_z)<=-22.0+0.001 and float(release.origin_z)<=-21.0
				actual_mouths = actual_mouths and bool(release.source_matches) and float(release.mouth_distance)<0.04 and release.velocity.is_finite() and release.velocity.z>0 and str(release.kind)==("bolt" if kind=="interceptor" else "mine")
			expect(far_release,kind+" gear"+str(gear_value)+" holds its body at least22m away and its actual muzzle at least21m away throughout release",{"releases":releases})
			expect(actual_mouths and game.health==5,kind+" gear"+str(gear_value)+" releases only two tangible rounds from surviving real mouths without animation damage")
			if kind=="interceptor":
				var gap: float = float(releases[1].time)-float(releases[0].time) if releases.size()==2 else 0.0
				expect(gap>=0.14 and gap<=0.19,kind+" gear"+str(gear_value)+" two short shots are separated rather than a stacked or phantom third release",{"gap":gap})
			else:
				var distinct := releases.size()==2 and Vector3(releases[0].origin).distance_to(Vector3(releases[1].origin))>0.1 and Vector3(releases[0].velocity).normalized().distance_to(Vector3(releases[1].velocity).normalized())>0.01
				expect(distinct,kind+" gear"+str(gear_value)+" uses two distinct physical launch bays and approach lines")
			rows.append({"kind":kind,"gear":gear_value,"extra":extra,"declared_charge":declared_charge,"actual_charge":actual_charge,"releases":releases})
			await process_frame
	observations["new_flyer_pressure"] = rows


func _verify_old_ranged_standoff() -> void:
	# The director's extra tell also applies to the older shooters. Waiting
	# longer must hold the firing body at range instead of advancing into the
	# player's face. This is checked separately from their unchanged damage.
	var rows: Array = []
	const DT := 1.0/240.0
	for kind: String in ["ranged","drone","missile_drone"]:
		_reset()
		game.speed = 60.0
		game.gear = 4
		var enemy = game._spawn_enemy(kind,1,-34.0)
		enemy.set_meta("first_charge_extra",0.85)
		var clock := 0.0
		var charge_started := -1.0
		var charge_ended := -1.0
		var declared_charge := 0.0
		var releases: Array = []
		var seen: Dictionary = {}
		var exited_fire := false
		for _frame in range(1920):
			var mouths: Array = enemy.get_ranged_origins().duplicate()
			clock += DT
			game.game_clock += DT
			game._update_enemies(DT,1.0)
			var action: String = str(enemy.get_meta("action_state",""))
			if action=="ranged_charge" and charge_started<0.0:
				charge_started = clock
				declared_charge = float(enemy.get_meta("action_duration",0.0))
			if action=="ranged_fire" and charge_ended<0.0: charge_ended = clock
			for shot: Dictionary in game.projectiles:
				var identifier: int = shot.node.get_instance_id()
				if seen.has(identifier): continue
				seen[identifier] = true
				var origin: Vector3 = shot.node.global_position
				var mouth_distance := INF
				for mouth: Vector3 in mouths: mouth_distance = minf(mouth_distance,mouth.distance_to(origin))
				releases.append({"time":clock,"actor_z":enemy.position.z,"origin_z":origin.z,"origin":origin,"source_matches":shot.source==enemy,"kind":str(shot.kind),"mouth_distance":mouth_distance,"velocity":shot.velocity})
			if charge_ended>=0.0 and action!="ranged_fire":
				exited_fire = true
				break
		var minimum := (0.85 if kind=="missile_drone" else 0.65)+0.85
		var actual_charge := charge_ended-charge_started
		var expected_count := 2 if kind=="missile_drone" else 1
		expect(exited_fire and charge_started>=0 and declared_charge>=minimum-0.001 and actual_charge>=minimum-DT*2.0 and is_zero_approx(float(enemy.get_meta("first_charge_extra",-1.0))),kind+" gear4 honours the director's one-time longer charge",{"declared":declared_charge,"observed":actual_charge,"minimum":minimum})
		var far_release := releases.size()==expected_count
		var actual_mouths := releases.size()==expected_count
		for release: Dictionary in releases:
			far_release = far_release and float(release.actor_z)<=-22.0+0.001 and float(release.origin_z)<=-21.0
			actual_mouths = actual_mouths and bool(release.source_matches) and float(release.mouth_distance)<0.05 and release.velocity.is_finite() and release.velocity.z>0 and str(release.kind)==("missile" if kind=="missile_drone" else "bolt")
		expect(far_release,kind+" gear4 stays at range during an extended lesson rather than releasing beside the player",{"releases":releases})
		var fires := _new_events(0,"ranged_fire")
		expect(actual_mouths and fires.size()==1 and game.health==5,kind+" gear4 uses one actual firing action and only its surviving physical launch mouths",{"projectile_count":releases.size(),"fire_actions":fires.size()})
		rows.append({"kind":kind,"gear":4,"extra":0.85,"declared_charge":declared_charge,"actual_charge":actual_charge,"releases":releases})
	observations["old_ranged_standoff"] = rows


func _run() -> void:
	manifests_before = _manifest()
	for path: String in DEPENDENCIES:
		var row: Dictionary = manifests_before[path]
		expect(not str(row.sha256).is_empty() and (not require_packed or (not bool(row.raw_exists) and str(row.runtime_path)!=path)),"current flow runtime dependency: "+path,row)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.test_mode = true
	game.set_process(false)
	game.sword.set_process(false)
	if not game.has_method("_spawn_encounter_wave") or not game.has_method("_update_retiring_enemies"):
		expect(false,"production encounter transition and wave APIs exist before fixtures run")
		await _finish()
		return
	await _verify_boss_entry()
	await process_frame
	_verify_f3_and_restart()
	await process_frame
	await _verify_escort_windows()
	await process_frame
	await _verify_escort_material_and_victory()
	await process_frame
	await _verify_new_flyer_pressure()
	await process_frame
	_verify_old_ranged_standoff()
	await process_frame
	_verify_four_lane_row()
	expect(_manifest()==manifests_before,"flow runtime resources remain unchanged through all transition and timing fixtures")
	await _finish()


func _finish() -> void:
	_reset()
	game._pause_game()
	game.audio.set_runner_motion(0.0,0.0,false,0.0)
	await create_timer(1.0).timeout
	var report := {"engine":Engine.get_version_info().string,"version":ProjectSettings.get_setting("application/config/version"),"checks":checks,"failures":failures,"observations":observations,"tool_sha256":FileAccess.get_sha256(get_script().resource_path),"base_tool_sha256":FileAccess.get_sha256(get_script().get_base_script().resource_path),"runtime_manifest_before":manifests_before,"runtime_manifest_after":_manifest(),"scope":"Injected deterministic production transition/dispatch/material fixtures. Actual clear, F3 input, escort positioning/phases, real material cuts and four-lane impacts; no rendered quality, normal-difficulty, performance or subjective acceptance."}
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var file := FileAccess.open(output_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("ENCOUNTER FLOW VERIFY: ",checks.size()," checks, ",failures," failures")
	game.free()
	await process_frame
	quit(0 if failures==0 else 1)
