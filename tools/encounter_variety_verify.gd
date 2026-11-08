extends "combat_expansion_verify.gd"
## Injected production-logic fixtures for three shoot-'em-up-derived machines.
## Uses the public cut/blast/shot and action APIs, not HP or a forced death flag.
## No rendered-quality, wall-clock performance or normal-difficulty verdict.

const NEW_KINDS := ["shield_drone", "interceptor", "mine_layer"]
const DEPENDENCIES := [
	"res://scenes/main.tscn", "res://scripts/main.gd", "res://scripts/voxel_enemy.gd",
	"res://scripts/enemy_archetypes.gd", "res://scripts/enemy_motion.gd",
	"res://scripts/projectile_view.gd", "res://scripts/projectile_geometry.gd",
]
var manifests_before: Dictionary = {}
var require_packed := false


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--encounter-output="):
			output_path = argument.trim_prefix("--encounter-output=")
		elif argument == "--require-packed":
			require_packed = true
	if output_path.is_empty():
		output_path = ProjectSettings.globalize_path("res://builds/encounter-review-v097/logic.json")
	call_deferred("_run")


func _manifest() -> Dictionary:
	var result: Dictionary = {}
	for path: String in DEPENDENCIES:
		var raw := FileAccess.file_exists(path)
		var runtime: String = path if raw else ""
		if not raw and FileAccess.file_exists(path+".remap"):
			var mapping := ConfigFile.new()
			if mapping.load(path+".remap") == OK:
				runtime = str(mapping.get_value("remap", "path", ""))
		result[path] = {"raw_exists":raw,"runtime_path":runtime,"sha256":FileAccess.get_sha256(runtime) if not runtime.is_empty() and FileAccess.file_exists(runtime) else ""}
	return result


func _target(kind: String, lane: int = 1, z: float = -18.0):
	var enemy = game._spawn_enemy(kind,lane,z)
	enemy.set_meta("simulation_scale",0.0)
	enemy.set_action("run",0.0)
	return enemy


func _verify_models() -> void:
	var signatures: Dictionary = {}
	var rows: Array = []
	for kind: String in NEW_KINDS:
		_reset()
		var enemy = _target(kind)
		var initial: int = enemy.get_remaining_voxel_count()
		var groups: Array = enemy._connected_components()
		var critical_connected := false
		var authored_cells := 0
		for group: Dictionary in groups:
			critical_connected = critical_connected or (int(group.flags)&7)==7
			authored_cells += group.indices.size()
		var signature: String = str(enemy._dimensions)+":"+str(enemy._cell)+":"+enemy._voxels.hex_encode().sha256_text()
		var unique: bool = not signatures.has(signature)
		signatures[signature] = kind
		var bounds: Rect2 = enemy.get_screen_bounds(game.camera)
		expect(initial > 600 and authored_cells == initial and enemy._is_flying() and bounds.size.x > 8.0 and bounds.size.y > 8.0,kind+" has a genuine occupied, visible flying voxel body",{"cells":initial,"groups":groups.size(),"screen_extent":str(bounds.size),"dimensions":str(enemy._dimensions),"cell":enemy._cell})
		expect(critical_connected and not enemy.dead and game.kills == 0,kind+" starts with head, core and anchor joined by real material")
		expect(unique,kind+" has its own occupied silhouette rather than a palette-only duplicate",{"occupancy_signature":signature})
		var emitted: Array = enemy.get_ranged_origins()
		expect(not emitted.is_empty() and enemy.has_attack_limb(),kind+" has actual surviving firing hardware")
		var before_count: int = game.projectiles.size()
		for action in ["run","ranged_charge","ranged_fire","windup","strike","recover","stagger"]:
			for phase in [0.0,0.25,0.5,0.75,1.0]:
				enemy.set_action(action,phase)
				for origin: Vector3 in enemy.get_ranged_origins():
					if not origin.is_finite():
						expect(false,kind+" action poses keep muzzle transforms finite")
		var finite := true
		for part in range(enemy.PART_COUNT):
			var pose: Transform3D = enemy._part_pose(part)
			finite = finite and pose.origin.is_finite() and pose.basis.x.is_finite() and pose.basis.y.is_finite() and pose.basis.z.is_finite()
		expect(finite and enemy.get_remaining_voxel_count() == initial and game.projectiles.size() == before_count,kind+" posing alone neither removes material nor fires an invisible attack")
		rows.append({"kind":kind,"cells":initial,"groups":groups.size(),"origins":emitted.size(),"signature":signature})
	observations["models"] = rows


func _enter_fire(enemy) -> bool:
	for _frame in range(480):
		if str(enemy.get_meta("action_state","")) == "ranged_fire":
			return true
		game._update_enemies(1.0/240.0,1.0)
	return false


func _verify_firing(kind: String) -> void:
	_reset()
	var enemy = _target(kind,1,-31.0)
	game._update_enemies(0.001,1.0)
	expect(str(enemy.get_meta("action_state","")) == "ranged_charge" and game.projectiles.is_empty() and game.health == 5,kind+" visibly charges before it produces a physical shot")
	if not _enter_fire(enemy):
		expect(false,kind+" reaches its authored fire action")
		return
	expect(game.projectiles.is_empty(),kind+" fire pose starts before any release contact")
	var times: Array[float] = []
	var releases: Array[int] = []
	var previous := 0
	var elapsed := 0.0
	for _frame in range(360):
		game._update_enemies(1.0/240.0,1.0)
		elapsed += 1.0/240.0
		if game.projectiles.size() > previous:
			times.append(elapsed)
			releases.append(game.projectiles.size()-previous)
			previous = game.projectiles.size()
		if str(enemy.get_meta("action_state","")) != "ranged_fire":
			break
	var expected_count := 1 if kind == "shield_drone" else 2
	var valid_payload := true
	var trajectories: Array[Vector3] = []
	for shot: Dictionary in game.projectiles:
		valid_payload = valid_payload and is_instance_valid(shot.node) and str(shot.kind) == ("mine" if kind == "mine_layer" else "bolt") and shot.velocity.is_finite() and shot.velocity.z > 0.0 and shot.source == enemy
		trajectories.append(shot.velocity.normalized())
	expect(game.projectiles.size() == expected_count and valid_payload,kind+" releases its own finite three-dimensional payload from the firing state",{"shots":game.projectiles.size(),"release_times":times,"release_sizes":releases})
	if kind == "interceptor":
		var spacing := times[1]-times[0] if times.size() == 2 else -1.0
		expect(times.size() == 2 and spacing >= 0.15 and spacing <= 0.18,kind+" point fire has two readable releases about 0.16s apart instead of a stacked volley",{"release_times":times,"spacing":spacing})
	elif kind == "mine_layer":
		var launch_origins: Array[Vector3] = []
		for shot: Dictionary in game.projectiles: launch_origins.append(shot.node.global_position)
		var spread := trajectories.size() == 2 and trajectories[0].distance_to(trajectories[1]) > 0.01
		var distinct_sources := launch_origins.size() == 2 and launch_origins[0].distance_to(launch_origins[1]) > 0.1
		expect(spread and distinct_sources,kind+" releases two solid mines from distinct real launch mouths along different flight directions",{"directions":trajectories.map(func(value): return str(value)),"launch_origins":launch_origins.map(func(value): return str(value))})
	expect(game.health == 5 and enemy.get_remaining_voxel_count() > 600,kind+" firing animation itself does not damage the player or consume its body")


func _verify_disarm(kind: String) -> void:
	_reset()
	var enemy = _target(kind,1,-24.0)
	var initial: int = enemy.get_remaining_voxel_count()
	var originals: Array = enemy.get_ranged_origins().duplicate()
	var removed := 0
	for origin: Vector3 in originals:
		var cut: Dictionary = enemy.blast_at(origin,0.34)
		removed += int(cut.removed)
	var surviving: Array = enemy.get_ranged_origins()
	expect(removed > 0 and not enemy.dead and surviving.is_empty() and not enemy.has_attack_limb() and game.kills == 0,kind+" real muzzle cuts disarm it without pretending the noncritical gun is a whole-body kill",{"initial":initial,"removed":removed,"remaining":enemy.get_remaining_voxel_count(),"before_origins":originals.size(),"after_origins":surviving.size(),"dead":enemy.dead})
	game._set_enemy_action(enemy,"run",1.0)
	game._update_enemies(0.001,1.0)
	if _enter_fire(enemy):
		for _frame in range(360):
			game._update_enemies(1.0/240.0,1.0)
			if str(enemy.get_meta("action_state","")) != "ranged_fire": break
	expect(game.projectiles.is_empty(),kind+" severed firing hardware cannot launch a phantom volley")


func _verify_structural_kill(kind: String) -> void:
	_reset()
	var enemy = _target(kind,1,-14.0)
	var initial: int = enemy.get_remaining_voxel_count()
	var center: Vector2 = game.camera.unproject_position(enemy.get_aim_point())
	var bounds: Rect2 = enemy.get_screen_bounds(game.camera)
	var removed := 0
	var passes := 0
	for _pass in range(int(enemy._dimensions.z)+4):
		var cut: Dictionary = enemy.cut_screen(game.camera,Vector2(bounds.position.x-4.0,center.y),Vector2(bounds.end.x+4.0,center.y),2.15)
		removed += int(cut.removed)
		passes += 1
		if enemy.dead or int(cut.removed)==0: break
	expect(enemy.dead and game.kills == 1 and removed > 0 and enemy.get_remaining_voxel_count() == initial-removed,kind+" dies only after an actual central material connection is cut",{"passes":passes,"initial":initial,"removed":removed,"remaining":enemy.get_remaining_voxel_count()})
	var retained: int = enemy.get_remaining_voxel_count()
	var score: int = game.score
	var recut := 0
	for piece in enemy.get_children():
		if not piece.get_meta("voxel_piece",false) or piece.is_queued_for_deletion(): continue
		var rectangle: Rect2 = piece.get_screen_bounds(game.camera)
		var cut: Dictionary = enemy.cut_screen(game.camera,Vector2(rectangle.position.x-4,rectangle.get_center().y),Vector2(rectangle.end.x+4,rectangle.get_center().y),2.15)
		recut += int(cut.removed)
		if recut > 0: break
	expect(recut > 0 and enemy.get_remaining_voxel_count() == retained-recut and game.kills == 1 and game.score == score,kind+" retained voxel wreckage can be cut again without another kill or reward",{"recut":recut,"retained":retained})


func _verify_lanes(kind: String) -> void:
	for lane in range(4):
		_reset()
		var enemy = _target(kind,lane,-13.0)
		# Prevent the ranged phase so this fixture isolates the same visible
		# close-contact attack from each occupied enemy lane.
		enemy.fire_timer = 999.0
		var speed_before: float = game.speed
		for _frame in range(240):
			game._update_enemies(1.0/120.0,1.0)
			if enemy.resolved: break
		expect(enemy.resolved and enemy.attack_done == 1 and game.health == 4 and game.speed == speed_before,kind+" armed miss in lane "+str(lane)+" hurts once without dropping speed",{"lane":lane,"health":game.health,"attack_done":enemy.attack_done})


func _verify_mine_return_material() -> void:
	_reset()
	var target = _target("tank",1,-18.0)
	var original: int = target.get_remaining_voxel_count()
	var point: Vector3 = target.get_aim_point()+Vector3(1.0,0.40,0.40)
	var node: Node3D = game._spawn_projectile(point,"mine",target)
	game.projectiles[0].reflected = true
	node.set_reflected()
	game._detonate_projectile(0,point,target)
	var event: Dictionary = {}
	for entry: Dictionary in game.combat_events:
		if entry.event == "projectile_explosion": event=entry
	expect(target.get_remaining_voxel_count() < original and game.projectiles.is_empty() and game.blasts.size() == 1 and game.health == 5, "returned mine explosion removes real nearby enemy material without self-damage",{"before":original,"after":target.get_remaining_voxel_count(),"event":event})
	expect(float(event.get("blast_radius",0.0)) > 0.0 and int(event.get("removed_total",0)) == original-target.get_remaining_voxel_count(),"mine blast report and actual retained material agree exactly")


func _verify_boss_phase_tempo() -> void:
	var rows: Array = []
	for gear_value in range(1,5):
		_reset()
		game.gear = gear_value
		var boss = _target("boss",1,-12.0)
		var before: Dictionary = boss.get_boss_reactor_state()
		game._set_enemy_action(boss,"recover",0.001)
		game._update_boss(boss,0.002)
		var full_windup: float = boss.get_meta("action_duration",0.0)
		game._update_boss(boss,full_windup)
		game._update_boss(boss,0.47)
		var full_recovery: float = boss.get_meta("action_duration",0.0)
		game._clear_projectiles()
		var real_cut: Dictionary = boss.blast_at(before.world_positions[0],0.80)
		var after: Dictionary = boss.get_boss_reactor_state()
		expect(int(before.connected)==2 and int(after.connected)==1 and int(real_cut.removed)>0 and not boss.dead and game.kills==0,"gear"+str(gear_value)+" Boss phase transition is earned by cutting one actual connected reactor",{"removed":real_cut.removed,"connected":after.connected})
		game._set_enemy_action(boss,"recover",0.001)
		game._update_boss(boss,0.002)
		var damaged_windup: float = boss.get_meta("action_duration",0.0)
		game._update_boss(boss,damaged_windup)
		game._update_boss(boss,0.47)
		var damaged_recovery: float = boss.get_meta("action_duration",0.0)
		var phase_event := false
		for event: Dictionary in game.combat_events:
			if event.event=="boss_reactor_phase" and int(event.get("connected_reactors",0))==1 and bool(event.get("enraged",false)):
				phase_event = true
		expect(damaged_windup>0.0 and damaged_recovery>0.0 and damaged_windup<full_windup and damaged_recovery<full_recovery and phase_event,"gear"+str(gear_value)+" real single-reactor Boss attacks and recovers faster while retaining readable positive phases",{"full_windup":full_windup,"damaged_windup":damaged_windup,"full_recovery":full_recovery,"damaged_recovery":damaged_recovery})
		rows.append({"gear":gear_value,"cut":real_cut,"connected_before":before.connected,"connected_after":after.connected,"full_windup":full_windup,"damaged_windup":damaged_windup,"full_recovery":full_recovery,"damaged_recovery":damaged_recovery})
	observations["boss_phase_tempo"] = rows


func _run() -> void:
	manifests_before = _manifest()
	for path: String in DEPENDENCIES:
		var row: Dictionary = manifests_before[path]
		expect(not str(row.sha256).is_empty() and (not require_packed or (not bool(row.raw_exists) and str(row.runtime_path)!=path)),"current encounter runtime dependency: "+path,row)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.test_mode = true
	game.set_process(false)
	game.sword.set_process(false)
	_verify_models()
	for kind: String in NEW_KINDS:
		_verify_firing(kind)
		_verify_disarm(kind)
		_verify_structural_kill(kind)
		_verify_lanes(kind)
		await process_frame
	_cut_shot("mine")
	_reflect_shot("mine")
	_verify_mine_return_material()
	_verify_boss_phase_tempo()
	expect(_manifest() == manifests_before,"encounter production resources remain unchanged through all material and action fixtures")
	await _finish()


func _finish() -> void:
	_reset()
	game._pause_game()
	game.audio.set_runner_motion(0.0,0.0,false,0.0)
	await create_timer(1.0).timeout
	var report := {"engine":Engine.get_version_info().string,"version":ProjectSettings.get_setting("application/config/version"),"checks":checks,"failures":failures,"observations":observations,"tool_sha256":FileAccess.get_sha256(get_script().resource_path),"base_tool_sha256":FileAccess.get_sha256(get_script().get_base_script().resource_path),"runtime_manifest_before":manifests_before,"runtime_manifest_after":_manifest(),"scope":"Injected production-logic fixtures for new enemy bodies, firing, genuine muzzle cuts, actual structural sever / wreck recut, four enemy lanes and physical mine counterplay. Direct production stepping; no GPU image, real-time performance, normal difficulty or subjective-feel verdict."}
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var file := FileAccess.open(output_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("ENCOUNTER VARIETY VERIFY: ",checks.size()," checks, ",failures," failures")
	game.free()
	await process_frame
	quit(0 if failures==0 else 1)
