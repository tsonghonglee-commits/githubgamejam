extends "combat_expansion_verify.gd"
## Controlled production transitions and attack scheduling. No rendered,
## performance, normal-difficulty or subjective-feel verdict is implied.

const DEPENDENCIES := [
	"res://scenes/main.tscn", "res://scripts/main.gd", "res://scripts/voxel_enemy.gd",
	"res://scripts/encounter_director.gd", "res://scripts/enemy_archetypes.gd",
	"res://scripts/enemy_motion.gd", "res://scripts/projectile_view.gd",
	"res://scripts/projectile_geometry.gd", "res://scripts/voxel_blast.gd", "res://scripts/voxel_debris.gd",
	"res://scripts/carrier_archetype.gd",
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


func _sky_actors() -> Array:
	var found: Array = []
	for enemy in game.enemies:
		if is_instance_valid(enemy) and not enemy.dead and enemy.has_meta("sky_lane"): found.append(enemy)
	return found


func _owned_shots(source) -> Array:
	var found: Array = []
	for shot: Dictionary in game.projectiles:
		if shot.source == source: found.append(shot)
	return found


func _finish_entries() -> void:
	# Existing geometry/attack fixtures isolate their original contract. The
	# new production entry itself is covered separately below, never skipped.
	# Finish the payload first so escort anchors follow its settled placement.
	if is_instance_valid(game.boss_enemy) and bool(game.boss_enemy.get_meta("entry_active",false)): game._finish_enemy_entry(game.boss_enemy)
	for enemy in game.enemies.duplicate():
		if is_instance_valid(enemy) and bool(enemy.get_meta("entry_active",false)): game._finish_enemy_entry(enemy)


func _isolate_carrier_for_material(scope: String) -> void:
	# The carrier's own destruction is covered separately; do not let its
	# transport lifecycle change legacy single-Boss/escort material accounting.
	if is_instance_valid(game.boss_carrier):
		var carrier = game.boss_carrier
		carrier.retire_for_encounter(game.camera)
		game.enemies.erase(carrier)
		carrier.free()
		game.boss_carrier = null
	if not observations.has("carrier_material_isolation"): observations["carrier_material_isolation"] = []
	observations["carrier_material_isolation"].append(scope)


func _true_chunks(enemy) -> Array:
	var chunks: Array = []
	for child in enemy.get_children():
		if bool(child.get_meta("voxel_piece",false)) and not child.is_queued_for_deletion() and child.get_voxel_count()>0: chunks.append(child)
	return chunks


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
	var sky = game._spawn_enemy("missile_drone",game.LANES.size()+2,game.SKY_HOLD_Z)
	originals.append(sky)
	retired_alive.append(sky)
	material[sky.get_instance_id()] = sky.get_remaining_voxel_count()
	var original_ids := _ids(originals)
	game._spawn_projectile(Vector3(0,1.65,-1.0),"bolt",originals[1])
	var returned = game._spawn_projectile(Vector3(0,1.65,-1.1),"mine",originals[2])
	game.projectiles[1].reflected = true
	returned.set_reflected()
	game._spawn_projectile(Vector3(sky.position.x,5.0,-1.0),"missile",sky)
	var sky_return = game._spawn_projectile(Vector3(sky.position.x,5.0,-1.1),"missile",sky)
	game.projectiles.back().reflected = true
	sky_return.set_reflected()
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
	expect(_sky_actors().is_empty() and bool(sky.get_meta("encounter_retired",false)) and not sky._configured,"Boss entry also disables the resident sky craft before installing its two ground-flank escorts")
	var formation_entering: bool = bool(game.boss_enemy.get_meta("entry_active",false))
	for escort in _escorts(): formation_entering = formation_entering and bool(escort.get_meta("entry_active",false))
	expect(formation_entering and is_instance_valid(game.boss_carrier) and bool(game.boss_carrier.get_meta("carrier_role",false)) and bool(game.boss_enemy.get_meta("deployment_carried",false)),"production Boss placement creates one new real carrier and explicitly starts its carried payload and both shield arrivals")
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
	expect(first.size()==4 and is_instance_valid(game.boss_carrier) and _ids(game.enemies)==first and game.retiring_enemies.size()==queued,"repeated real F3 input leaves the same carrier, Boss and two escorts instead of duplicating or refreshing them")
	expect(game.health==5 and game.kills==0 and game.score==0,"the Boss shortcut never pays the player for clearing an uncut route actor")
	game.start_game()
	expect(game.enemies.is_empty() and game.retiring_enemies.is_empty() and game.projectiles.is_empty() and not game.boss_spawned and game.victory_timer<0.0,"restart clears a pending entry transition and all encounter ownership")
	game.spawn_timer = 999.0


func _verify_escort_windows() -> void:
	_reset()
	game._spawn_boss()
	_finish_entries()
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
	_finish_entries()
	_isolate_carrier_for_material("escort material and single-Boss victory")
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
	var plan: Dictionary = director.plan(22,87.0/180.0,30.0,180.0)
	game._spawn_encounter_wave(plan)
	_finish_entries()
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
			var extra := 0.0
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
			var minimum := (0.52 if kind=="interceptor" else 0.96)+extra
			var actual_charge := charge_ended-charge_started
			expect(exited_fire and charge_started>=0 and declared_charge>=minimum-0.001 and actual_charge>=minimum-DT*2.0 and is_zero_approx(float(enemy.get_meta("first_charge_extra",-1.0))),kind+" gear"+str(gear_value)+" first attack gives its real full charge plus one-time formation tell",{"declared":declared_charge,"observed":actual_charge,"minimum":minimum})
			var advancing_release := releases.size()==3
			var actual_mouths := releases.size()==3
			for release: Dictionary in releases:
				advancing_release = advancing_release and float(release.actor_z)>-34.0 and float(release.actor_z)<-13.0
				actual_mouths = actual_mouths and bool(release.source_matches) and float(release.mouth_distance)<0.04 and release.velocity.is_finite() and release.velocity.z>0 and str(release.kind)==("bolt" if kind=="interceptor" else "mine")
			expect(advancing_release,kind+" gear"+str(gear_value)+" restores its original advancing charge instead of the22m hold",{"releases":releases})
			expect(actual_mouths and game.health==5,kind+" gear"+str(gear_value)+" releases three tangible rounds from surviving real mouths without animation damage")
			if kind=="interceptor":
				var gap: float = float(releases[1].time)-float(releases[0].time) if releases.size()==3 else 0.0
				var second_gap: float = float(releases[2].time)-float(releases[1].time) if releases.size()==3 else 0.0
				expect(gap>=0.09 and gap<=0.11 and second_gap>=0.09 and second_gap<=0.11,kind+" gear"+str(gear_value)+" restores all three timed releases about0.10s apart",{"gaps":[gap,second_gap]})
			else:
				var distinct := releases.size()==3
				for first in range(releases.size()):
					for second in range(first+1,releases.size()):
						distinct = distinct and Vector3(releases[first].origin).distance_to(Vector3(releases[second].origin))>0.1 and Vector3(releases[first].velocity).normalized().distance_to(Vector3(releases[second].velocity).normalized())>0.01
				expect(distinct,kind+" gear"+str(gear_value)+" restores all three distinct surviving physical launch bays and approach lines")
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


func _verify_sky_admission() -> void:
	_reset()
	var director = load("res://scripts/encounter_director.gd")
	var rejected := true
	for kind in ["normal","tank","ranged","boss","barrier","beam","shield_drone"]:
		rejected = rejected and not game._can_spawn_sky_enemy(kind,0) and game._spawn_enemy(kind,game.LANES.size(),game.SKY_HOLD_Z) == null
	rejected = rejected and not game._can_spawn_sky_enemy("drone",-1) and not game._can_spawn_sky_enemy("drone",3) and game._spawn_enemy("drone",game.LANES.size()+3,game.SKY_HOLD_Z) == null
	expect(rejected and game.enemies.is_empty(),"sky creation rejects ground kinds, Boss shields and every lane outside the three authored sky slots")
	var ordinary: Dictionary = director.plan(2,11.4/180.0,18.0,180.0)
	game._spawn_encounter_wave(ordinary)
	var old_flyer = game.enemies[0]
	expect(ordinary.sky_spawns.is_empty() and game.enemies.size()==1 and old_flyer.enemy_kind=="drone" and old_flyer.lane_index==0 and not old_flyer.has_meta("sky_lane") and is_zero_approx(old_flyer.position.y) and bool(old_flyer.get_meta("entry_active",false)),"the original opening drone slot retains its ground-lane path and explicitly uses the shared aircraft arrival")
	_reset()
	game.wave_index = 9
	game.elapsed = 41.5
	game.spawn_timer = 0.0
	game._update_spawning(0.0)
	var resident = _sky_actors()[0]
	expect(game.wave_index==10 and game.enemies.size()==1 and resident.enemy_kind=="drone" and int(resident.get_meta("sky_lane",-1))==1 and resident.lane_index==5 and bool(resident.get_meta("entry_active",false)) and is_equal_approx(game.spawn_timer,3.5),"the production ninth slot creates one centre-sky drone with the common entry and advances the ordinary timed stream")
	expect(not game._has_pending_wave_enemies(),"a resident sky craft never holds the ground all-clear predicate open indefinitely")
	game.wave_index = 26
	game.elapsed = 101.0
	game.spawn_timer = 0.0
	var start: int = game.combat_events.size()
	game._update_spawning(0.0)
	var skipped := _new_events(start,"sky_spawn_skipped")
	expect(_sky_actors().size()==1 and _sky_actors()[0]==resident and game.wave_index==27 and is_equal_approx(game.spawn_timer,3.5) and skipped.size()==1 and int(skipped[0].sky_lane)==0,"an occupied sky slot is logged and skipped without duplicating its ground flyer or blocking wave advancement")
	var normal: Dictionary = director.plan(10,102.0/180.0,30.0,180.0)
	var ranged: Dictionary = director.plan(7,102.0/180.0,30.0,180.0)
	expect(game._can_spawn_encounter_wave(normal) and game._can_spawn_encounter_wave(ranged),"one sky shooter still permits ordinary melee and one ordinary ground shooter")
	game._spawn_encounter_wave(ranged)
	expect(not game._can_spawn_encounter_wave(ranged) and game._can_spawn_encounter_wave(normal) and not game._can_spawn_sky_enemy("drone",2),"one sky plus one ground shooter exhausts the shared two-shooter budget while ordinary melee remains eligible")
	_reset()
	game._spawn_enemy("ranged",1,-40.0)
	game._spawn_enemy("drone",2,-40.0)
	game.wave_index = 9
	game.elapsed = 41.5
	game.spawn_timer = 0.0
	start = game.combat_events.size()
	game._update_spawning(0.0)
	expect(_sky_actors().is_empty() and game.enemies.size()==2 and game.wave_index==10 and _new_events(start,"sky_spawn_skipped").size()==1,"two active ground shooters skip optional sky support and leave both original actors and stream cadence intact")
	for kind in ["interceptor","mine_layer"]:
		_reset()
		game._spawn_enemy(kind,1,-40.0)
		expect(not game._can_spawn_sky_enemy("drone",0),kind+" solo pressure rejects optional sky support")
	observations["sky_admission"] = {"resident_cap":1,"shared_shooter_cap":2,"sky_slots":[9,26,42],"ordinary_opening_drone_index":2}


func _verify_sky_residency_and_fire() -> void:
	var rows: Array = []
	for lane in range(3):
		for kind in ["drone","missile_drone"]:
			_reset()
			game.speed = 18.0 if lane%2==0 else 60.0
			game.gear = game.gear_for_speed(game.speed)
			var enemy = game._spawn_enemy(kind,game.LANES.size()+lane,game.SKY_HOLD_Z)
			var anchor := Vector3(float(game.SKY_LANES[lane]),3.0,-22.0)
			expect(enemy.position.distance_to(anchor)<0.001 and enemy.lane_index==4+lane and int(enemy.get_meta("sky_lane",-1))==lane and not bool(enemy.get_meta("entry_active",false)),kind+" raw factory uses the elevated sky anchor"+str(lane)+" without silently starting a second entry")
			game._start_enemy_entry(enemy)
			expect(enemy.position.z>0.0 and is_equal_approx(enemy.position.y,anchor.y) and enemy._rig.basis.z.z < -0.9,kind+" sky lane"+str(lane)+" begins behind the camera facing along its outbound fly-by")
			for _frame in range(int(ceil(float(enemy.get_meta("entry_duration",0.0))/STEP))+1): game._update_enemies(STEP,1.0)
			var held: bool = enemy.position.distance_to(anchor)<0.001 and not bool(enemy.get_meta("entry_active",false))
			var mouth_matches := true
			var shot_count := 0
			var start: int = game.combat_events.size()
			for _frame in range(660):
				var mouths: Array = enemy.get_ranged_origins().duplicate()
				game.game_clock += STEP
				game._update_enemies(STEP,1.0)
				held = held and enemy.position.distance_to(anchor)<0.001 and str(enemy.get_meta("action_state","")) not in ["windup","strike","exit"] and enemy.attack_done==0 and not enemy.resolved
				for shot: Dictionary in _owned_shots(enemy):
					var nearest := INF
					for mouth: Vector3 in mouths: nearest = minf(nearest,mouth.distance_to(shot.node.global_position))
					mouth_matches = mouth_matches and nearest<0.05 and str(shot.kind)==("missile" if kind=="missile_drone" else "bolt") and shot.velocity.is_finite() and shot.velocity.z>0.0
					shot_count += 1
				# Isolate dispatch from projectile travel, as with escort windows.
				game._clear_projectiles()
			var fires := _new_events(start,"ranged_fire")
			var spaced := true
			for index in range(1,fires.size()): spaced = spaced and float(fires[index].world_time)-float(fires[index-1].world_time)>=2.5
			var expected_mouths := 2 if kind=="missile_drone" else 1
			expect(held and game.health==5 and _sky_actors().has(enemy),kind+" sky lane"+str(lane)+" remains at its player-relative anchor through repeated cycles without melee or lane-miss damage")
			expect(fires.size()>=3 and spaced and mouth_matches and shot_count==fires.size()*expected_mouths,kind+" sky lane"+str(lane)+" repeats its original single-action physical payload using only its live launch mouths",{"fire_actions":fires.size(),"shots":shot_count,"anchor":anchor,"runner_speed":game.speed})
			rows.append({"kind":kind,"lane":lane,"anchor":anchor,"fires":fires.size(),"shots":shot_count})
			await process_frame
	observations["sky_residency"] = {"rows":rows,"scope":"Injected production enemy dispatch only; shots cleared after each step, no flight/difficulty/performance verdict."}


func _verify_sky_slow_and_freeze() -> void:
	_reset()
	var enemy = game._spawn_enemy("drone",game.LANES.size()+1,game.SKY_HOLD_Z)
	game._set_enemy_action(enemy,"ranged_charge",2.0)
	var shot: Node3D = game._spawn_projectile(Vector3(0,5.0,-15.0),"bolt",enemy)
	var incoming: Vector3 = game.projectiles[0].velocity
	var origin: Vector3 = shot.global_position
	game.slashing = true
	game.hit_stop = 0.0
	game._process(STEP)
	var slow_dt: float = STEP*0.22
	expect(absf(float(enemy.get_meta("action_time",-1.0))-slow_dt)<0.00001 and absf(enemy.age-slow_dt)<0.00001 and absf(game.game_clock-slow_dt)<0.00001 and shot.global_position.distance_to(origin+incoming*slow_dt)<0.00002,"actual held-mode processing advances the resident sky phase, age and shot by the shared0.22 world scale")
	var before := {"position":enemy.position,"age":enemy.age,"action_time":enemy.get_meta("action_time"),"fire_timer":enemy.fire_timer,"shot_position":shot.global_position,"shot_age":game.projectiles[0].age,"clock":game.game_clock}
	game.hit_stop = 1.0
	game._process(STEP)
	var stopped: bool = enemy.position==before.position and enemy.age==before.age and enemy.get_meta("action_time")==before.action_time and enemy.fire_timer==before.fire_timer and shot.global_position==before.shot_position and game.projectiles[0].age==before.shot_age and game.game_clock==before.clock
	expect(stopped and is_zero_approx(float(enemy.get_meta("simulation_scale",-1.0))),"real hitstop freezes the resident anchor, attack, cooldown and its physical projectile together")
	game._pause_game()
	game._process(STEP)
	expect(game.state=="paused" and enemy.position==before.position and enemy.age==before.age and enemy.get_meta("action_time")==before.action_time and shot.global_position==before.shot_position and game.projectiles[0].age==before.shot_age,"pause leaves resident sky timers and ammunition frozen")


func _verify_sky_disarm_and_special_clear() -> void:
	for kind in ["drone","missile_drone"]:
		_reset()
		var enemy = game._spawn_enemy(kind,game.LANES.size()+1,game.SKY_HOLD_Z)
		enemy.set_action("recover",1.0)
		var removed := 0
		for origin: Vector3 in enemy.get_ranged_origins().duplicate(): removed += int(enemy.blast_at(origin,0.34 if kind=="missile_drone" else 0.22).removed)
		expect(removed>0 and not enemy.dead and enemy.get_remaining_voxel_count()>0 and enemy.get_ranged_origins().is_empty() and not enemy.has_attack_limb() and game.kills==0,kind+" sky weapon removal deletes actual launch material while preserving the living central machine",{"removed":removed,"remaining":enemy.get_remaining_voxel_count()})
		game._set_enemy_action(enemy,"ranged_fire",0.22)
		game._update_enemies(STEP,1.0)
		expect(enemy.resolved and str(enemy.get_meta("action_state",""))=="exit" and game.projectiles.is_empty() and _new_events(0,"sky_disarmed").size()==1,kind+" with every real mouth removed aborts firing and begins its harmless retreat")
		for _frame in range(90): game._update_enemies(STEP,1.0)
		expect(not game.enemies.has(enemy) and game.health==5 and game.kills==0 and game.score==0 and game.projectiles.is_empty(),kind+" disarmed sky retreat finishes without a ghost shot, lane miss or unearned kill")
		await process_frame
	var transitions: Array = []
	for item in [{"index":13,"time":50.0},{"index":22,"time":90.0},{"index":25,"time":90.0},{"index":37,"time":130.0}]:
		_reset()
		var sky = game._spawn_enemy("drone",game.LANES.size()+1,game.SKY_HOLD_Z)
		var ground = game._spawn_enemy("normal",1,-40.0)
		var ground_shot = game._spawn_projectile(Vector3(-1,1.65,-40.0),"bolt",ground)
		game._spawn_projectile(Vector3(0,5.0,-1.0),"bolt",sky)
		var returned = game._spawn_projectile(Vector3(0,5.0,-1.1),"bolt",sky)
		game.projectiles.back().reflected = true
		returned.set_reflected()
		var cells: int = sky.get_remaining_voxel_count()
		game.wave_index = int(item.index)
		game.elapsed = float(item.time)
		game.spawn_timer = 0.0
		game._update_spawning(0.0)
		var cleared: bool = _sky_actors().is_empty() and _owned_shots(sky).is_empty() and bool(sky.get_meta("encounter_retired",false)) and not sky._configured and not sky.dead and sky.get_remaining_voxel_count()==cells
		expect(cleared and game.enemies.has(ground) and _owned_shots(ground).size()==1 and _owned_shots(ground)[0].node==ground_shot and game.health==5 and game.kills==0 and game.score==0,"special slot"+str(item.index)+" retires only sky ownership and both hostile/returned source shots before admission, preserving the ground actor and its pending shot")
		if int(item.index)==22:
			expect(game.wave_index==22,"the exceptional row still waits for a real remaining ground enemy after sky retirement")
			ground.blast_at(ground.get_aim_point(),12.0)
			game._update_spawning(0.0)
		var admitted: int = game.wave_index
		expect(admitted==int(item.index)+1 and game.spawn_timer>0.0,"special slot"+str(item.index)+" can enter after sky removal without a persistent support deadlock")
		transitions.append({"index":item.index,"retired_cells":cells,"next_index":admitted,"remaining_ground_shots":_owned_shots(ground).size()})
	observations["sky_special_clear"] = transitions


func _verify_common_enemy_entry() -> void:
	var motion = load("res://scripts/enemy_motion.gd")
	var kinds: Array = ["normal","tank","ranged","drone","missile_drone","shield_drone","interceptor","mine_layer","boss"]
	var durations: Array = [2.20,2.50,2.30,3.20*2.0/3.0,3.60*2.0/3.0,3.60*2.0/3.0,2.80*2.0/3.0,3.80*2.0/3.0,6.00]
	for index in range(kinds.size()):
		_reset()
		var kind: String = str(kinds[index])
		var duration: float = float(motion.entry_duration(kind))
		var final_sample: Dictionary = motion.sample_entry(kind,1,1.0)
		var enemy = game._spawn_enemy(kind,1,-60.0)
		var cells: PackedByteArray = _remaining_authored_cells(enemy)
		expect(not bool(enemy.get_meta("entry_active",false)) and is_equal_approx(duration,float(durations[index])) and final_sample.offset==Vector3.ZERO and final_sample.rotation==Vector3.ZERO and str(enemy.get_meta("enemy_series",""))=="SERIES_01" and str(enemy.get_meta("enemy_series_label",""))=="第一系列",kind+" has its first-series identity, bounded duration, zero final sample and raw factory free of automatic arrival")
		game._start_enemy_entry(enemy,"recover" if kind=="boss" else "run",2.1 if kind=="boss" else 1.0)
		var anchor: Vector3 = enemy.get_meta("entry_anchor")
		var behind: bool = game.camera.is_position_behind(enemy.position) and enemy._rig.basis.z.z < -0.9
		game._update_enemies(duration*0.5,1.0)
		var path_valid: bool = enemy.position.y==anchor.y and enemy.basis==Basis.IDENTITY
		if kind in game.FLYING_ENEMIES:
			path_valid = path_valid and behind and enemy.position.z>=-14.001 and enemy.position.z<=-11.999 and enemy._rig.basis.z.z < -0.8 and is_equal_approx(anchor.z,-26.0)
		elif kind in ["normal","tank","ranged"]:
			path_valid = path_valid and enemy.position.x==anchor.x and is_equal_approx(anchor.z,-40.0) and enemy.position.z<=-40.0
		else: path_valid = path_valid and enemy.position.x==anchor.x
		expect(bool(enemy.get_meta("entry_active",false)) and str(enemy.get_meta("action_state",""))=="entry" and path_valid and game.projectiles.is_empty() and game.health==5 and _remaining_authored_cells(enemy)==cells,kind+" keeps true cuttable material and silent dispatch while following its ground pose or real behind-to-front aircraft turn")
		if kind in game.FLYING_ENEMIES:
			game._apply_enemy_entry_pose(enemy,0.82)
			expect(absf(enemy.position.z+12.0)<0.001 and enemy._rig.basis.z.z>0.9 and enemy.position!=anchor,kind+" completes its visible turn at12m through phase0.82 before the final retreat to its26m ground anchor")
		game._update_enemies(duration*0.5,1.0)
		var final_root: Transform3D = enemy.transform
		game._finish_enemy_entry(enemy)
		expect(not bool(enemy.get_meta("entry_active",true)) and enemy.position==anchor and enemy.transform==final_root and enemy._rig.basis.z.z>0.9 and str(enemy.get_meta("action_state",""))==("recover" if kind=="boss" else "run") and game.projectiles.is_empty() and _remaining_authored_cells(enemy)==cells,kind+" finishes facing the player at its exact anchor without duplicate motion, dispatch or cell changes")
	var ground_curve: Dictionary = motion.sample_entry("drone",1,0.5)
	var sky_curve: Dictionary = motion.sample_entry("drone",5,0.5)
	expect(ground_curve==sky_curve and float(motion.entry_duration("barrier"))==0.0 and float(motion.entry_duration("beam"))==0.0,"aircraft use one height-independent entry sampler on original and sky lanes while static hazards stay outside actor arrivals")
	_reset()
	var director = load("res://scripts/encounter_director.gd")
	game._spawn_encounter_wave(director.plan(3,100.0/180.0,30.0,180.0))
	var followers: Array = game.enemies
	expect(followers.size()==2 and is_equal_approx(Vector3(followers[0].get_meta("entry_anchor")).z,-40.0) and is_equal_approx(Vector3(followers[1].get_meta("entry_anchor")).z,-54.0) and is_equal_approx(float(followers[1].get_meta("entry_depth_offset",0.0)),-14.0),"production ground staging stays outside32m and retains its true14m follower gap at40/54m")
	_reset()
	var resident = game._spawn_enemy("drone",5,game.SKY_HOLD_Z)
	game._start_enemy_entry(resident)
	game.slashing = true
	game.hit_stop = 0.0
	game._process(STEP)
	var age: float = float(resident.get_meta("entry_age",-1.0))
	var root_pose: Transform3D = resident.transform
	var rig_pose: Transform3D = resident._rig.transform
	expect(absf(age-STEP*0.22)<0.00001,"production held mode advances the common arrival on the shared slow world clock")
	game.hit_stop = 1.0
	game._process(STEP)
	game._pause_game()
	game._process(STEP)
	expect(float(resident.get_meta("entry_age",-1.0))==age and resident.transform==root_pose and resident._rig.transform==rig_pose,"hitstop and pause freeze entry time, true root approach and actual part pose together")


func _verify_ground_entry_safety() -> void:
	for kind in ["normal","tank","ranged"]:
		_reset()
		var enemy = game._spawn_enemy(kind,1,-8.0)
		game._start_enemy_entry(enemy)
		var initial: int = enemy.get_remaining_voxel_count()
		var safe: bool = is_equal_approx(game.PLAYER_CUT_MIN_Z,-32.0) and is_equal_approx(game.GROUND_ENTRY_Z,-40.0)
		for phase in [0.0,0.5,0.999]:
			game._apply_enemy_entry_pose(enemy,float(phase))
			var occupied: int = int(enemy._live_indices[int(enemy._live_indices.size()/2)])
			var contact: Vector2 = game.camera.unproject_position(enemy._posed_world_point(occupied))
			game._cut_path(PackedVector2Array([contact-Vector2(12,0),contact+Vector2(12,0)]),false)
			safe = safe and enemy.position.z<=-40.0 and enemy.get_remaining_voxel_count()==initial
		game._finish_enemy_entry(enemy)
		expect(safe and not bool(enemy.get_meta("entry_active",true)) and is_equal_approx(enemy.position.z,-40.0),kind+" production blade admission ignores the entire remote entry and completion keeps its40m anchor without a jump")
		game._update_enemies(8.5/(game.speed+game.ENEMY_RUN_SPEED),1.0)
		var occupied: int = int(enemy._live_indices[int(enemy._live_indices.size()/2)])
		var contact: Vector2 = game.camera.unproject_position(enemy._posed_world_point(occupied))
		game._cut_path(PackedVector2Array([contact-Vector2(12,0),contact+Vector2(12,0)]),false)
		expect(enemy.position.z>=-32.0 and enemy.get_remaining_voxel_count()<initial and game.kills==(1 if enemy.dead else 0),kind+" becomes genuinely cuttable only after its original run crosses the32m player plane")


func _verify_ground_entry_fade() -> void:
	var motion = load("res://scripts/enemy_motion.gd")
	var kinds: Array = ["normal","tank","ranged"]
	var first_z: Array = [-75.5,-74.6,-75.0]
	var stops: Array = [0.34,0.38,0.30]
	var contact_z: Array = [-0.8,0.0,-0.45]
	for index in range(kinds.size()):
		_reset()
		var kind: String = str(kinds[index])
		var enemy = game._spawn_enemy(kind,1,-8.0)
		var cells: PackedByteArray = _remaining_authored_cells(enemy)
		var original_shader: Shader = (enemy._material as ShaderMaterial).shader
		var props: Array = []
		var pending: Array[Node] = [enemy]
		while not pending.is_empty():
			var node: Node = pending.pop_back()
			pending.append_array(node.get_children())
			if not node is MeshInstance3D: continue
			var mesh: MeshInstance3D = node as MeshInstance3D
			if mesh.material_override is StandardMaterial3D:
				props.append({"mesh":mesh,"material":mesh.material_override,"transparency":mesh.transparency})
		game._start_enemy_entry(enemy)
		expect(is_equal_approx(float(motion.GROUND_ENTRY_EXTRA_DEPTH),30.0) and absf(enemy.position.z-float(first_z[index]))<0.00001 and is_zero_approx(float(motion.entry_visibility(kind,0.0))) and enemy._entry_visibility_active and not enemy.visible and (enemy._material as ShaderMaterial).shader!=original_shader,kind+" starts fully hidden another30m behind its original approach while retaining the40m final anchor")
		var previous: float = -1.0
		var valid: bool = true
		for phase in [0.0,0.10,0.21,0.30,0.42,0.75,1.0]:
			var visibility: float = float(motion.entry_visibility(kind,float(phase)))
			var sample: Dictionary = motion.sample_entry(kind,1,float(phase))
			valid = valid and visibility>=previous and visibility>=0.0 and visibility<=1.0 and Vector3(sample.offset).z<=0.0
			previous = visibility
		var contact: Dictionary = motion.sample_entry(kind,1,float(stops[index]))
		expect(valid and is_equal_approx(float(motion.entry_visibility(kind,0.42)),1.0) and absf(Vector3(contact.offset).z-float(contact_z[index]))<0.00001,kind+" fades monotonically to full visibility atphase0.42 and consumes the extra depth before its authored planted contact")
		game._apply_enemy_entry_pose(enemy,0.21)
		var proxy_fade: bool = enemy.visible and enemy._entry_visibility_active and absf(float((enemy._material as ShaderMaterial).get_shader_parameter("entry_visibility"))-0.5)<0.00001 and not props.is_empty()
		for row: Dictionary in props:
			var proxy: ShaderMaterial = row.mesh.material_override as ShaderMaterial
			proxy_fade = proxy_fade and proxy!=null and absf(float(proxy.get_shader_parameter("entry_visibility"))-0.5)<0.00001 and row.mesh.transparency==row.transparency
		expect(proxy_fade,kind+" drives body and actual weapon/prop dither uniforms together without relying on GeometryInstance transparency")
		game._apply_enemy_entry_pose(enemy,0.42)
		var opaque_restored: bool = not enemy._entry_visibility_active and enemy.visible and (enemy._material as ShaderMaterial).shader==original_shader and enemy._entry_visibility_bindings.is_empty() and enemy._entry_visibility_props.is_empty()
		for row: Dictionary in props: opaque_restored = opaque_restored and row.mesh.material_override==row.material and row.mesh.transparency==row.transparency
		expect(absf(enemy.position.z-(-40.0+float(contact_z[index])))<0.00001 and _remaining_authored_cells(enemy)==cells and opaque_restored,kind+" restores the exact original opaque body shader and prop overrides on its unchanged late entry path")
		game._finish_enemy_entry(enemy)
		expect(is_equal_approx(enemy.position.z,-40.0) and not bool(enemy.get_meta("entry_active",true)) and not enemy._entry_visibility_active and (enemy._material as ShaderMaterial).shader==original_shader and _remaining_authored_cells(enemy)==cells,kind+" finishes opaque at the original safe anchor without altering cuttable occupancy or retaining fade state")
	var unaffected: bool = true
	for kind in ["drone","missile_drone","shield_drone","interceptor","mine_layer","boss","boss_carrier","barrier","beam"]:
		for phase in [0.0,0.21,0.42,1.0]: unaffected = unaffected and is_equal_approx(float(motion.entry_visibility(str(kind),float(phase))),1.0)
	expect(unaffected,"all aircraft, Boss, carrier and hazards retain full visibility independently of the three ground arrivals")


func _verify_entry_material_budget() -> void:
	var kinds: Array = ["normal","tank","ranged","drone","missile_drone","shield_drone","interceptor","mine_layer","boss","boss_carrier","barrier","beam"]
	for kind in kinds:
		_reset()
		var enemy = game._spawn_enemy(str(kind),1,-22.0)
		enemy.set_meta("entry_active",true)
		var candidates := PackedInt32Array()
		for index in range(12): candidates.append(int(enemy._live_indices[index]))
		var initial: PackedByteArray = _remaining_authored_cells(enemy)
		var selected: PackedInt32Array = enemy._entry_material_budget(candidates,game.camera.global_position,false)
		var protected: bool = kind in game.FLYING_ENEMIES
		expect(selected.size()==(3 if protected else 12) and (protected or selected==candidates) and _remaining_authored_cells(enemy)==initial,str(kind)+" entry budget selects exactly25% only for the five live aircraft, preserving raw order for every ground/Boss/carrier/hazard exception")
		if not protected: continue
		enemy.reset_entry_material_budget()
		var first: PackedInt32Array = enemy._entry_material_budget(candidates.slice(0,1),game.camera.global_position,false)
		var empty: PackedInt32Array = enemy._entry_material_budget(PackedInt32Array(),game.camera.global_position,true)
		var second: PackedInt32Array = enemy._entry_material_budget(candidates.slice(0,3),game.camera.global_position,true)
		expect(first.is_empty() and empty.is_empty() and second.size()==1 and candidates.has(second[0]) and enemy._entry_material_remainder==0,str(kind)+" accumulates one plus three real sword/blast candidates into one removed-cell credit without a min-one shortcut")
		enemy._entry_material_budget(candidates.slice(0,3),game.camera.global_position,false)
		game._start_enemy_entry(enemy)
		var reset_at_start: bool = enemy._entry_material_remainder==0
		enemy._entry_material_budget(candidates.slice(0,3),game.camera.global_position,true)
		game._finish_enemy_entry(enemy)
		var restored: PackedInt32Array = enemy._entry_material_budget(candidates,game.camera.global_position,false)
		expect(reset_at_start and enemy._entry_material_remainder==0 and restored==candidates,str(kind)+" clears fractional credit at both entry boundaries and restores full unchanged candidate order after completion")
		enemy.set_meta("entry_active",true)
		enemy.dead = true
		var corpse: PackedInt32Array = enemy._entry_material_budget(candidates,game.camera.global_position,true)
		expect(corpse==candidates and enemy._entry_material_remainder==0,str(kind)+" dead material bypasses entry protection instead of inheriting a corpse shield")
	for radial in [false,true]:
		_reset()
		var full = game._spawn_enemy("drone",1,-22.0)
		var reduced = game._spawn_enemy("drone",1,-22.0)
		full.set_action("recover",1.0)
		reduced.set_action("recover",1.0)
		reduced.set_meta("entry_active",true)
		var initial: int = reduced.get_remaining_voxel_count()
		var occupied: int = int(full._live_indices[int(full._live_indices.size()/2)])
		var point: Vector3 = full._posed_world_point(occupied)
		var screen: Vector2 = game.camera.unproject_position(point)
		# Raw geometry pair deliberately isolates the shared material selector;
		# player-distance admission is covered by the production-path fixture.
		var baseline: Dictionary = full.blast_at(point,0.40) if radial else full.cut_screen(game.camera,screen-Vector2(12,0),screen+Vector2(12,0),1.8)
		var result: Dictionary = reduced.blast_at(point,0.40) if radial else reduced.cut_screen(game.camera,screen-Vector2(12,0),screen+Vector2(12,0),1.8)
		var count: int = int(baseline.removed)
		expect(count>=4 and int(result.removed)==int(count/4) and reduced._entry_material_remainder==count%4 and reduced.get_remaining_voxel_count()==initial-int(result.removed),("sphere" if radial else "blade")+" production commit removes exactly the quarter-budget real cells and conserves every uncut body/fragment cell")
	observations["entry_material_scope"] = "Finite selector and raw posed-geometry pairs; living five-aircraft entry only, shared blade/blast remainder, full damage after finish or death. No HP, player-distance, difficulty or performance inference from raw geometry pairs."


func _verify_carrier_deployment() -> void:
	var layout = load("res://scripts/carrier_archetype.gd")
	var rows: Array = []
	for side in range(2):
		_reset()
		game._spawn_boss()
		var boss = game.boss_enemy
		var carrier = game.boss_carrier
		var initial: int = carrier.get_remaining_voxel_count()
		var boss_cells: int = boss.get_remaining_voxel_count()
		expect(carrier.enemy_kind=="boss_carrier" and str(carrier.get_meta("enemy_series",""))=="SERIES_01" and not carrier.has_attack_limb() and carrier.get_ranged_origins().is_empty() and _escorts().size()==2 and is_equal_approx(float(boss.get_meta("entry_duration",0.0)),game.DEPLOYMENT_SECONDS),"a first-series real-material transport owns no weapon and carries the Boss with exactly two escorts")
		game._update_enemies(1.0,1.0)
		var supports: Dictionary = carrier.get_carrier_hanger_state()
		var mid: Vector3 = (Vector3(supports.world_positions[0])+Vector3(supports.world_positions[1]))*0.5
		var mount: Vector3 = boss.to_global(boss._rig.transform*game.DEPLOYMENT_MOUNT_POINT)
		expect(supports.connected==[true,true] and mount.distance_to(mid)<0.0001 and not boss.has_meta("deployment_release_age") and game.projectiles.is_empty() and game.health==5,"the suspended Boss uses the two actual posed suspension ends without premature fire or release")
		if side==0:
			var members: Array = game.deployment_clearance.duplicate(true)
			game._update_deployment_clearance(1.2)
			var opened: bool = not members.is_empty()
			for member: Dictionary in members:
				var moved: Transform3D = member.mesh.get_instance_transform(int(member.index))
				var original: Transform3D = member.original
				opened = opened and moved.origin.distance_to(original.origin+Vector3(member.offset))<0.0001 and moved.basis==original.basis
			game._restore_deployment_clearance()
			var restored: bool = game.deployment_clearance.is_empty() and is_zero_approx(game.deployment_clearance_age)
			for member: Dictionary in members: restored = restored and member.mesh.get_instance_transform(int(member.index))==member.original
			expect(opened and restored,"the lifting corridor moves actual saved gantry members and restores their exact original transforms without editing route geometry")
		var cut: Dictionary = carrier.blast_at(Vector3(supports.world_positions[side]),0.95)
		var severed: Dictionary = carrier.get_carrier_hanger_state()
		expect(int(cut.removed)>0 and not carrier.dead and not bool(severed.connected[side]) and carrier.get_remaining_voxel_count()==initial-int(cut.removed) and game.kills==0 and game.score==0,"suspension"+str(side)+" can be genuinely severed while conserving all uncut ship material and keeping the transport alive")
		game._update_enemy_entry(boss,0.10)
		var release_age: float = float(boss.get_meta("deployment_release_age",-1.0))
		var releases: Array = _new_events(0,"boss_payload_release")
		expect(release_age>=0.0 and release_age<game.DEPLOYMENT_RELEASE_SECONDS and releases.size()==1 and bool(releases[0].early) and boss.has_meta("deployment_release_rig") and boss.has_meta("deployment_release_phase") and is_equal_approx(float(boss.get_meta("entry_duration")),release_age+game.DEPLOYMENT_FALL_SECONDS+game.DEPLOYMENT_SETTLE_SECONDS),"either cut hanger triggers one early release from the retained real pose followed by the authored fall and rise")
		game._update_deployment_clearance(game.DEPLOYMENT_OPEN_SECONDS)
		game._update_enemy_entry(boss,1.0)
		game._update_enemy_entry(boss,0.01)
		expect(bool(boss.get_meta("deployment_landed",false)) and _new_events(0,"boss_payload_landed").size()==1 and is_zero_approx(game.landing_impact_age) and game.landing_impact_strength>=1.0 and game.shake>=0.9 and boss.get_remaining_voxel_count()==boss_cells and game.kills==0 and game.victory_timer<0.0,"landing dispatches one physical impact and camera-shake envelope without deleting Boss material or granting victory")
		game._finish_enemy_entry(boss)
		expect(not bool(boss.get_meta("entry_active",true)) and boss.position==Vector3(boss.get_meta("entry_anchor")) and str(boss.get_meta("action_state",""))=="recover" and _new_events(0,"boss_payload_release").size()==1,"finishing a released payload preserves its settled anchor and cannot release it a second time")
		rows.append({"hanger":side,"removed":cut.removed,"release_age":release_age})
	_reset()
	game._spawn_boss()
	var boss = game.boss_enemy
	var carrier = game.boss_carrier
	var initial: int = carrier.get_remaining_voxel_count()
	var boss_cells: int = boss.get_remaining_voxel_count()
	var core: Vector3 = carrier.to_global(carrier._part_pose(0)*Vector3(layout.CORE_POINT))
	var kills_before: int = game.kills
	var score_before: int = game.score
	var combo_before: int = game.combo
	var cut: Dictionary = carrier.blast_at(core,1.20)
	expect(int(cut.removed)>0 and carrier.dead and carrier.get_remaining_voxel_count()==initial-int(cut.removed) and game.kills==kills_before and game.score==score_before and game.combo==combo_before and not boss.dead and boss.get_remaining_voxel_count()==boss_cells and boss.has_meta("deployment_release_age") and game.victory_timer<0.0 and _new_events(0,"carrier_destroyed").size()==1,"destroying the auxiliary carrier core conserves its remaining cells and releases the living Boss without any extra kill, combo, score or victory")
	carrier.blast_at(core,1.20)
	expect(game.kills==kills_before and game.score==score_before and game.combo==combo_before and game.victory_timer<0.0 and _new_events(0,"carrier_destroyed").size()==1,"re-cutting auxiliary transport wreckage cannot farm a kill, combo, score or victory or repeat its destruction callback")
	observations["carrier_deployment"] = {"hangers":rows,"scope":"Finite injected cut/entry/gantry contracts only; transport is explicitly removed from the separate legacy Boss material and death fixtures."}


func _verify_boss_death_sequence() -> void:
	_reset()
	game._spawn_boss()
	_finish_entries()
	_isolate_carrier_for_material("dual-reactor conservation, corpse re-cut and one-score death sequence")
	var boss = game.boss_enemy
	var initial: int = boss.get_remaining_voxel_count()
	var first: Dictionary = boss.blast_at(boss.get_boss_reactor_state().world_positions[0],0.80)
	var second: Dictionary = boss.blast_at(boss.get_boss_reactor_state().world_positions[1],0.80)
	var retained: int = boss.get_remaining_voxel_count()
	var anchor: Vector3 = boss.position
	var score: int = game.score
	var chunks: Array = _true_chunks(boss)
	expect(int(first.removed)>0 and int(second.removed)>0 and boss.dead and game.kills==1 and retained==initial-int(first.removed)-int(second.removed) and retained>0 and not chunks.is_empty(),"real destruction of both Boss reactors starts the sequence once while conserving every uncut cell as actual remaining material")
	if chunks.is_empty(): return
	expect(bool(boss.get_meta("boss_death_hold",false)) and bool(boss.get_meta("boss_death_stationary",false)) and not bool(boss.get_meta("boss_death_exploded",true)) and _new_events(0,"boss_death_hold").size()==1 and _escorts().is_empty() and game.projectiles.is_empty(),"structural Boss death immediately clears support and holds the real carcass instead of replacing it or awarding another kill")
	var poses: Dictionary = {}
	for piece in chunks: poses[piece.get_instance_id()] = {"pose":piece.global_transform,"age":piece.elapsed}
	game.hit_stop = 0.0
	game._process(0.50)
	var held: bool = boss.position==anchor
	for piece in chunks:
		piece._process(0.50)
		held = held and piece.global_transform==poses[piece.get_instance_id()].pose and piece.elapsed==poses[piece.get_instance_id()].age
	expect(held and absf(float(boss.get_meta("boss_death_age",-1.0))-0.50)<0.00001 and game.state=="playing","the first death stage holds true chunks and the Boss root while its independent world clock advances")
	var first_chunk = chunks[0]
	var coordinates: Array = first_chunk.cells.keys()
	var cell: Vector3i = coordinates[int(coordinates.size()/2)]
	var screen: Vector2 = game.camera.unproject_position(first_chunk.to_global(first_chunk._cell_point(cell)))
	var cut: Dictionary = boss.cut_screen(game.camera,screen-Vector2(2,0),screen+Vector2(2,0),2.15)
	var after_cut: int = boss.get_remaining_voxel_count()
	expect(int(cut.removed)>0 and after_cut==retained-int(cut.removed) and game.kills==1 and game.score==score and absf(float(boss.get_meta("boss_death_age",-1.0))-0.50)<0.00001,"a real corpse re-cut removes conserved material without resetting the Boss death clock, repeating the kill or changing score")
	game.hit_stop = 0.0
	game._process(0.84)
	var before_freeze: float = float(boss.get_meta("boss_death_age",-1.0))
	expect(absf(before_freeze-1.34)<0.00001 and not bool(boss.get_meta("boss_death_exploded",true)) and game.state=="playing","re-cutting the held carcass does not postpone the authored1.35s explosion threshold")
	game.hit_stop = 1.0
	game._process(STEP)
	game._pause_game()
	game._process(0.5)
	expect(float(boss.get_meta("boss_death_age",-1.0))==before_freeze and not bool(boss.get_meta("boss_death_exploded",true)) and boss.position==anchor,"hitstop and pause freeze the staged Boss death instead of finishing it on real elapsed time")
	game._resume_game()
	game.hit_stop = 0.0
	game._process(0.02)
	var scatter: bool = not _true_chunks(boss).is_empty()
	var retained_pose: Transform3D = boss.get_meta("boss_death_rig")
	for chunk in _true_chunks(boss):
		var radial: Vector3 = chunk.position-retained_pose*Vector3(0,2.6,0.2)
		if radial.length_squared()>0.0001: scatter = scatter and (chunk.velocity-Vector3(0,2.6,1.5)).dot(radial)>0.0
	expect(bool(boss.get_meta("boss_death_exploded",false)) and not bool(boss.get_meta("boss_death_hold",true)) and _new_events(0,"boss_death_explosion").size()==1 and scatter and boss.get_remaining_voxel_count()==after_cut and boss.position==anchor and game.state=="playing","the threshold releases existing real chunks radially exactly once, preserving material and keeping victory pending through the tail")
	game._process(1.03)
	expect(game.state=="playing" and _new_events(0,"boss_death_explosion").size()==1,"the1.05s post-explosion tail cannot be skipped by the real-time victory countdown")
	game._process(0.02)
	expect(game.state=="won" and game.kills==1 and game.score==score and game.health==5 and _new_events(0,"boss_death_explosion").size()==1,"victory completes only after the full independent2.4s death sequence with one explosion and the original single score")
	observations["boss_death_sequence"] = {"initial":initial,"first_removed":first.removed,"second_removed":second.removed,"recut_removed":cut.removed,"retained_after_cut":after_cut,"explosions":_new_events(0,"boss_death_explosion").size(),"death_age":boss.get_meta("boss_death_age")}


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
	if not game.has_method("_spawn_encounter_wave") or not game.has_method("_update_retiring_enemies") or not game.has_method("_can_spawn_sky_enemy") or not game.has_method("_update_sky_enemy") or not game.has_method("_start_enemy_entry") or not game.has_method("_finish_enemy_entry") or not game.has_method("_update_boss_death") or not game.has_method("_release_boss_payload") or not game.has_method("_update_carrier_actor"):
		expect(false,"production encounter transition and wave APIs exist before fixtures run")
		await _finish()
		return
	_verify_common_enemy_entry()
	await process_frame
	_verify_ground_entry_safety()
	await process_frame
	_verify_ground_entry_fade()
	await process_frame
	_verify_entry_material_budget()
	await process_frame
	_verify_carrier_deployment()
	await process_frame
	_verify_boss_death_sequence()
	await process_frame
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
	_verify_sky_admission()
	await process_frame
	await _verify_sky_residency_and_fire()
	await process_frame
	_verify_sky_slow_and_freeze()
	await process_frame
	await _verify_sky_disarm_and_special_clear()
	await process_frame
	_verify_four_lane_row()
	expect(_manifest()==manifests_before,"flow runtime resources remain unchanged through all transition and timing fixtures")
	await _finish()


func _finish() -> void:
	_reset()
	game._pause_game()
	game.audio.set_runner_motion(0.0,0.0,false,0.0)
	await create_timer(1.0).timeout
	var report := {"engine":Engine.get_version_info().string,"version":ProjectSettings.get_setting("application/config/version"),"checks":checks,"failures":failures,"observations":observations,"tool_sha256":FileAccess.get_sha256(get_script().resource_path),"base_tool_sha256":FileAccess.get_sha256(get_script().get_base_script().resource_path),"runtime_manifest_before":manifests_before,"runtime_manifest_after":_manifest(),"scope":"Injected production contracts for first-series identities, real behind-to-front aircraft turns, cuttable suspension/core release, gantry restoration and landing dispatch, plus the unchanged strict held-material Boss death sequence. If executed, only controlled injected cases are reported; no rendered quality, normal-difficulty, performance or subjective acceptance."}
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var file := FileAccess.open(output_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("ENCOUNTER FLOW VERIFY: ",checks.size()," checks, ",failures," failures")
	game.free()
	await process_frame
	quit(0 if failures==0 else 1)
