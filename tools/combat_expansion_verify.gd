extends SceneTree
## Targeted production-logic fixture for physical shots, reflection and cuttable
## hazards. Uses injected actors and direct production stepping; no difficulty,
## wall-clock performance, rendered quality or subjective-feel verdict.

var game
var checks: Array[Dictionary] = []
var failures := 0
var output_path := ""
var observations: Dictionary = {}
var reflection_baseline_path := ""
var reflection_baseline_only := false
var candidate_radii := {"bolt":0.90,"shock":1.15,"missile":1.45}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--expansion-output="):
			output_path = argument.trim_prefix("--expansion-output=")
		elif argument.begins_with("--reflection-baseline="):
			reflection_baseline_path = argument.trim_prefix("--reflection-baseline=")
		elif argument == "--reflection-baseline-only":
			reflection_baseline_only = true
		elif argument.begins_with("--candidate-radii="):
			var values := argument.trim_prefix("--candidate-radii=").split(",")
			if values.size() == 3:
				candidate_radii = {"bolt":float(values[0]),"shock":float(values[1]),"missile":float(values[2])}
	if output_path.is_empty():
		output_path = ProjectSettings.globalize_path("res://builds/expansion-review/logic.json")
	call_deferred("_run")


func expect(condition: bool, label: String, detail: Dictionary = {}) -> void:
	checks.append({"label": label, "passed": condition, "detail": detail})
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _reset() -> void:
	for target in game.enemies:
		if is_instance_valid(target):
			target.free()
	game.enemies.clear()
	game._clear_projectiles()
	game._clear_blasts()
	game.start_game()
	game.test_mode = true
	game.set_process(false)
	game.sword.set_process(false)
	game.spawn_timer = 999.0
	game.camera.rotation = Vector3.ZERO
	game.camera.fov = 78.0
	game.aim_angles = Vector2.ZERO
	game.health = 5
	game.practice = false
	game.training = false
	game.speed = 30.0
	game.gear = game.gear_for_speed(game.speed)


func _mesh_bounds(node: Node3D) -> AABB:
	var result := AABB()
	var found := false
	var nodes: Array[Node] = [node]
	while not nodes.is_empty():
		var item: Node = nodes.pop_back()
		if item is MeshInstance3D and item.mesh != null:
			var bounds: AABB = node.global_transform.affine_inverse() * item.global_transform * item.mesh.get_aabb()
			result = result.merge(bounds) if found else bounds
			found = true
		nodes.append_array(item.get_children())
	return result


func _cut_shot(kind: String) -> void:
	_reset()
	var node: Node3D = game._spawn_projectile(Vector3(0.0, 1.65, -7.0), kind)
	var bounds := _mesh_bounds(node)
	expect(bounds.size.x > 0.01 and bounds.size.y > 0.01 and bounds.size.z > 0.01, kind + " has genuine three-dimensional mesh extent", {"extent": str(bounds.size)})
	var point: Vector2 = game.camera.unproject_position(node.global_position)
	var hit_path := PackedVector2Array([point - Vector2(16, 0), point + Vector2(16, 0)])
	var miss_path := PackedVector2Array([point + Vector2(85, -16), point + Vector2(85, 16)])
	expect(node.intersects_path(game.camera, hit_path) and not node.intersects_path(game.camera, miss_path), kind + " cut contact follows the visible solid instead of a broad screen radius")
	var health_before: int = game.health
	var cuts_before: int = int(game.combat_stats.get("projectiles_cut", 0))
	game._cut_path(hit_path, false)
	expect(game.projectiles.is_empty() and game.blasts.size() == 1, kind + " blade contact removes one shot and creates one blast")
	expect(game.health == health_before and int(game.combat_stats.get("projectiles_cut", 0)) == cuts_before + 1, kind + " cut explosion is safe for its player and counted once")
	game._cut_path(hit_path, false)
	expect(game.blasts.size() == 1 and int(game.combat_stats.get("projectiles_cut", 0)) == cuts_before + 1, kind + " repeated empty blade contact does not duplicate its explosion")


func _reflect_shot(kind: String) -> void:
	_reset()
	var node: Node3D = game._spawn_projectile(Vector3(0.0, 1.65, -1.0), kind)
	var incoming: Vector3 = game.projectiles[0].velocity
	var initial_speed: float = game.speed
	game._begin_guard()
	game.guard_age = 0.075
	game._update_projectiles(0.04)
	expect(game.projectiles.size() == 1 and is_instance_valid(node) and bool(game.projectiles[0].get("reflected", false)), kind + " parry preserves and reflects the physical shot")
	if game.projectiles.size() != 1:
		return
	var reflected: Vector3 = game.projectiles[0].velocity
	expect(reflected.normalized().dot(-incoming.normalized()) > 0.99999 and is_equal_approx(reflected.length(), incoming.length() * 1.4), kind + " return direction exactly reverses the incoming velocity", {"incoming": str(incoming), "reflected": str(reflected)})
	expect(game.health == 5 and game.speed > initial_speed and int(game.combat_stats.get("parries", 0)) == 1, kind + " parry prevents damage and rewards speed once")
	var before: Vector3 = node.global_position
	game._update_projectiles(0.1)
	expect(node.global_position.distance_to(before + reflected * 0.1) < 0.001, kind + " reflected flight remains a straight continuation")


func _chain_shot(kind: String, point: Vector3, velocity: Vector3, reflected: bool = false) -> Dictionary:
	var node: Node3D = game._spawn_projectile(point,kind)
	if node == null: return {}
	var shot: Dictionary = game.projectiles.back()
	shot.velocity = velocity
	shot.reflected = reflected
	if reflected: node.set_reflected()
	return shot


func _chain_explosions() -> Array:
	var result: Array = []
	for event: Dictionary in game.combat_events:
		if str(event.event)=="projectile_explosion": result.append(event)
	return result


func _verify_relative_interception() -> void:
	_reset()
	var returned: Dictionary = _chain_shot("bolt",Vector3(0,1.65,-5),Vector3(0,0,-100),true)
	var hostile: Dictionary = _chain_shot("missile",Vector3(0,1.65,-20),Vector3(0,0,500))
	var radius: float = returned.node.collision_radius+hostile.node.collision_radius
	var expected: float = (15.0-radius)/600.0
	var actual: float = game._projectile_pair_time(returned,hostile,0.05)
	var reverse: float = game._projectile_pair_time(hostile,returned,0.05)
	expect(absf(actual-expected)<0.00001 and absf(reverse-expected)<0.00001,"relative sphere sweep finds the same analytic high-speed contact time in either argument order",{"expected_seconds":expected,"actual_seconds":actual,"reverse_seconds":reverse})
	_reset()
	returned = _chain_shot("bolt",Vector3(-2,1.65,-10),Vector3(40,0,0),true)
	hostile = _chain_shot("missile",Vector3(0,1.65,-15),Vector3(0,0,40))
	var missed: float = game._projectile_pair_time(returned,hostile,0.2)
	var event: Dictionary = game._next_projectile_event(0.2)
	game._update_projectiles(0.2)
	expect(is_inf(missed) and event.is_empty() and game.projectiles.size()==2 and _chain_explosions().is_empty() and game.health==5,"crossing spatial paths at different times do not create a false interception")
	for reflected in [false,true]:
		_reset()
		_chain_shot("bolt",Vector3(0,1.65,-12),Vector3.ZERO,reflected)
		_chain_shot("missile",Vector3(0,1.65,-12),Vector3.ZERO,reflected)
		event = game._next_projectile_event(0.05)
		game._update_projectiles(0.05)
		expect(event.is_empty() and game.projectiles.size()==2 and _chain_explosions().is_empty(),("returned-returned" if reflected else "hostile-hostile")+" overlapping ammunition never collides with its own side")
	_reset()
	var target = _profile_target("normal")
	var before: PackedByteArray = _remaining_authored_cells(target)
	_chain_shot("missile",Vector3(0,1.65,-1),Vector3(0,0,-100),true)
	hostile = _chain_shot("bolt",Vector3(0,1.65,-20),Vector3.ZERO)
	event = game._next_projectile_event(0.2)
	var hit_first: bool = str(event.get("kind",""))=="enemy" and event.get("target")==target
	expect(hit_first,"a nearer real enemy surface wins before a later returned-shot versus hostile contact")
	if hit_first:
		game._update_projectiles(0.2)
		var material: Dictionary = _material_result(target,before,event.point,1.45)
		expect(bool(material.matches_full_scan) and int(material.removed)>0 and game.projectiles.size()==1 and game.projectiles[0]==hostile and int(game.combat_stats.get("projectile_chain_detonations",0))==0,"the earlier body impact retains its exact original sphere deletion and leaves the distant hostile unignited",{"material":material})


func _verify_interception_order_and_guard_reward() -> void:
	var rows: Array = []
	for reverse in [false,true]:
		for earlier_hit in [false,true]:
			_reset()
			var specs: Array = [{"kind":"bolt","point":Vector3(0,1.65,-5),"velocity":Vector3(0,0,-100),"reflected":true},{"kind":"missile","point":Vector3(0,1.65,-20),"velocity":Vector3(0,0,500),"reflected":false}]
			if earlier_hit: specs.append({"kind":"bolt","point":Vector3(6,1.65,-1.9),"velocity":Vector3(0,0,100),"reflected":false})
			if reverse: specs.reverse()
			for spec: Dictionary in specs: _chain_shot(str(spec.kind),spec.point,spec.velocity,bool(spec.reflected))
			var first: Dictionary = game._next_projectile_event(0.05)
			expect(str(first.get("kind",""))==("player" if earlier_hit else "intercept") and (not earlier_hit or absf(float(first.time)-0.01)<0.00001),"global event selection follows physical time before projectile array order",{"reverse_array":reverse,"earlier_independent_hit":earlier_hit,"first_kind":first.get("kind",""),"time":first.get("time",-1.0)})
			game._update_projectiles(0.05)
			var count: int = 3 if earlier_hit else 2
			var children: int = 0
			for explosion: Dictionary in _chain_explosions():
				if bool(explosion.get("chain_reaction",false)) and int(explosion.get("chain_depth",0))==1 and not bool(explosion.get("was_reflected",true)): children += 1
			var conserved: bool = game.projectiles.is_empty() and _chain_explosions().size()==count and int(game.combat_stats.get("projectile_explosions",0))==count and int(game.combat_stats.get("projectile_interceptions",0))==1 and int(game.combat_stats.get("projectile_chain_detonations",0))==1 and children==1
			var no_reward: bool = int(game.combat_stats.get("parries",0))==0 and int(game.combat_stats.get("projectiles_reflected",0))==0 and int(game.combat_stats.get("projectiles_cut",0))==0 and game.score==0 and game.combo==0 and is_equal_approx(game.speed,30.0)
			expect(conserved and no_reward and game.health==(4 if earlier_hit else 5),"high-speed interception removes both shots before the threatened crossing, preserves an earlier unrelated hit and awards no invented parry or cut",{"reverse_array":reverse,"earlier_independent_hit":earlier_hit,"health":game.health,"explosions":count,"children":children})
			rows.append({"reverse_array":reverse,"earlier_independent_hit":earlier_hit,"health":game.health,"explosions":_chain_explosions().size()})
	_reset()
	game._begin_guard()
	game.guard_age = 0.075
	game._spawn_projectile(Vector3(-0.05,1.65,-1.0),"bolt")
	game._spawn_projectile(Vector3(0.05,1.65,-1.0),"missile")
	game._update_projectiles(0.05)
	expect(game.projectiles.is_empty() and _chain_explosions().size()==2 and game.health==5 and game.guard_chain_hits==1 and int(game.combat_stats.get("parries",0))==1 and int(game.combat_stats.get("projectiles_reflected",0))==1 and int(game.combat_stats.get("projectile_interceptions",0))==1 and int(game.combat_stats.get("projectile_chain_detonations",0))==1 and int(game.combat_stats.get("projectiles_cut",0))==0 and is_equal_approx(game.speed,47.0) and game.combo==1 and game.score==200*game.gear_for_speed(47.0),"a tightly clustered volley is consumed by one real parry plus interception, with exactly one perfect speed/combo/score reward and one explosion per shot")
	observations["interception_order"] = rows


func _verify_chain_payloads_and_callbacks() -> void:
	_reset()
	var root_shot: Dictionary = _chain_shot("bolt",Vector3(0,1.65,-12),Vector3.ZERO,true)
	_chain_shot("missile",Vector3(1.15,1.65,-12),Vector3.ZERO)
	_chain_shot("bolt",Vector3(2.65,1.65,-12),Vector3.ZERO)
	_chain_shot("shock",Vector3(3.8,1.65,-12),Vector3.ZERO)
	var far: Dictionary = _chain_shot("bolt",Vector3(8,1.65,-12),Vector3.ZERO)
	var other_return: Dictionary = _chain_shot("bolt",Vector3(0.3,1.65,-12),Vector3.ZERO,true)
	game._detonate_projectile(0,root_shot.node.global_position)
	var depths: Array = []
	var radii: Array = []
	var provenance: bool = true
	for explosion: Dictionary in _chain_explosions():
		depths.append(int(explosion.get("chain_depth",-1)))
		radii.append(float(explosion.get("blast_radius",-1.0)))
		provenance = provenance and bool(explosion.get("reflected",false)) and bool(explosion.get("was_reflected",false))==(int(explosion.get("chain_depth",-1))==0) and bool(explosion.get("chain_reaction",false))==(int(explosion.get("chain_depth",-1))>0)
	expect(depths==[0,1,2,3] and radii==[0.90,1.45,0.90,1.15] and provenance,"multi-hop ignition uses each original payload radius plus the next physical shot radius, with truthful reflected/child provenance",{"depths":depths,"radii":radii})
	var survivors: bool = game.projectiles.size()==2 and game.projectiles.has(far) and game.projectiles.has(other_return)
	expect(survivors and _chain_explosions().size()==4 and int(game.combat_stats.get("projectile_chain_detonations",0))==3 and int(game.combat_stats.get("projectile_explosions",0))==4 and game.health==5 and game.score==0 and game.kills==0 and int(game.combat_stats.get("projectiles_cut",0))==0 and int(game.combat_stats.get("projectiles_reflected",0))==0,"multi-hop blasts consume each claimed hostile once while preserving a far hostile, another returned shot and every player resource")
	_reset()
	_chain_shot("bolt",Vector3(0,1.65,-12),Vector3.ZERO)
	_chain_shot("missile",Vector3(1.15,1.65,-12),Vector3.ZERO)
	_chain_shot("bolt",Vector3(2.65,1.65,-12),Vector3.ZERO)
	game._cut_projectile(0)
	expect(game.projectiles.size()==2 and _chain_explosions().size()==1 and int(game.combat_stats.get("projectile_chain_detonations",0))==0 and int(game.combat_stats.get("projectiles_cut",0))==1 and game.score==30*game.gear and game.health==5 and game.kills==0,"ordinary unreflected blade detonation cannot seed a chain and pays only its one existing cut reward")
	_reset()
	var target = _profile_target("normal")
	var point: Vector3 = _posed_local(target,Vector3(0,1.86,0.30))
	game.boss_enemy = target
	game.boss_spawned = true
	_chain_shot("missile",point,Vector3.ZERO,true)
	_chain_shot("bolt",point+Vector3(1,0,0),Vector3.ZERO)
	_chain_shot("bolt",Vector3(4,1.65,-30),Vector3.ZERO)
	game._detonate_projectile(0,point)
	var kills: int = game.kills
	var score: int = game.score
	game._update_projectiles(0.2)
	game._update_projectiles(0.2)
	expect(target.dead and game.victory_timer>=0.0 and game.projectiles.is_empty() and _chain_explosions().size()==2 and int(game.combat_stats.get("projectile_chain_detonations",0))==1 and int(game.combat_stats.get("projectile_explosions",0))==2 and game.kills==1 and game.kills==kills and game.score==score and game.health==5,"the full chain is claimed before a real Boss-owner sever clears the live array, preserving the queued child exactly once and preventing duplicate score")
	observations["chain_payloads"] = {"depths":depths,"radii":radii,"boss_callback_explosions":_chain_explosions().size()}


func _verify_chain_freeze_and_capacity() -> void:
	_reset()
	_chain_shot("bolt",Vector3(0,1.65,-20),Vector3.ZERO,true)
	for index in range(39): _chain_shot("bolt",Vector3(float(index+1)*0.01,1.65,-20),Vector3.ZERO)
	var count: int = game.projectiles.size()
	var snapshots: Array = []
	for shot: Dictionary in game.projectiles: snapshots.append({"point":shot.node.global_position,"age":shot.age})
	game._update_projectiles(0.0)
	game.hit_stop = 1.0
	game._process(0.016)
	game._pause_game()
	game._process(0.02)
	var frozen: bool = game.projectiles.size()==count and _chain_explosions().is_empty()
	for index in range(game.projectiles.size()): frozen = frozen and game.projectiles[index].node.global_position==snapshots[index].point and game.projectiles[index].age==snapshots[index].age
	expect(count==24 and frozen,"a full touching mixed-ownership pool respects the24-shot cap and cannot ignite while world time, hitstop or pause is frozen")
	game._resume_game()
	game.hit_stop = 0.0
	game._update_projectiles(0.01)
	expect(game.projectiles.is_empty() and _chain_explosions().size()==count and int(game.combat_stats.get("projectile_chain_detonations",0))==count-1 and int(game.combat_stats.get("projectile_explosions",0))==count and int(game.combat_stats.get("projectile_interceptions",0))==1 and game.blasts.size()<=12 and game.health==5 and game.score==0 and int(game.combat_stats.get("parries",0))==0 and int(game.combat_stats.get("projectiles_cut",0))==0,"resuming a full contact chain consumes exactly the bounded pool once, keeps the12-blast budget and cannot farm parry or cut rewards")
	game._update_projectiles(1.0)
	expect(_chain_explosions().size()==count and game.projectiles.is_empty() and game.health==5,"an already consumed chain cannot detonate or damage again on a later update")


func _verify_chain_and_crossing() -> void:
	_reset()
	game._begin_guard()
	game.guard_age = 0.075
	# Keep this a same-window multi-guard contract. The original0.1m cluster
	# is now covered separately by returned-shot interception and chain blast.
	game._spawn_projectile(Vector3(-1.2, 1.65, -4.9), "bolt")
	game.projectiles.back().velocity = Vector3(0,0,32)
	game._spawn_projectile(Vector3(1.2, 1.65, -4.9), "missile")
	game.projectiles.back().velocity = Vector3(0,0,32)
	var simultaneous_dt: float = (-0.9-float(game.projectiles[0].node.global_position.z))/32.0
	var boundary: Dictionary = game._next_projectile_event(simultaneous_dt)
	expect(str(boundary.get("kind",""))=="player" and float(boundary.get("time",-1.0))==simultaneous_dt,"the two separated guard contacts lie exactly on the requested frame-end TOI")
	game._update_projectiles(simultaneous_dt)
	var reflected := 0
	for projectile in game.projectiles:
		if bool(projectile.get("reflected", false)): reflected += 1
	expect(reflected == 2 and int(game.combat_stats.get("parries", 0)) == 1 and game.guard_chain_hits == 2 and is_equal_approx(game.speed,47.0) and game.combo==1 and game.score==200*game.gear_for_speed(47.0), "one parry window resolves both separated frame-end contacts and pays exactly one perfect speed/combo/score reward")
	_reset()
	var shot: Node3D = game._spawn_projectile(Vector3(0.0, 1.65, -20.0), "missile")
	game.projectiles[0].velocity = Vector3(0, 0, 120)
	var speed_before: float = game.speed
	game._update_projectiles(0.3)
	expect(game.projectiles.is_empty() and game.health == 4 and is_equal_approx(game.speed, speed_before), "a large time step crossing the player plane causes one hit without stealing speed")
	game._update_projectiles(0.3)
	expect(game.health == 4, "a consumed hostile shot cannot damage twice")
	_reset()
	shot = game._spawn_projectile(Vector3(0.0, 1.65, -20.0), "missile")
	game.projectiles[0].velocity = Vector3(0, 0, 120)
	game._begin_guard()
	game._update_projectiles(0.3)
	expect(game.projectiles.size() == 1 and bool(game.projectiles[0].get("reflected", false)) and game.health == 5 and shot.global_position.z < 0.0, "swept crossing can be parried without losing the shot behind the camera")
	_reset()
	var source = game._spawn_enemy("drone", 0, -80.0)
	shot = game._spawn_projectile(Vector3(0,1.65,-1),"bolt",source)
	game._begin_guard()
	game._update_projectiles(0.04)
	var returned_velocity: Vector3 = game.projectiles[0].velocity
	var returned_position: Vector3 = shot.global_position
	source.position = Vector3(9,4,-60)
	game._update_projectiles(0.1)
	expect(game.projectiles[0].velocity == returned_velocity and shot.global_position.distance_to(returned_position+returned_velocity*0.1) < 0.001, "a moved shooter does not steer its returned shot off the original reverse line")
	game.enemies.erase(source)
	source.free()
	game._update_projectiles(0.1)
	expect(game.projectiles.size() == 1 and game.projectiles[0].velocity == returned_velocity and game.health == 5, "a returned shot remains valid after its original shooter is freed")


func _verify_freeze_and_limits() -> void:
	_reset()
	var shot: Node3D = game._spawn_projectile(Vector3(0.0, 1.65, -6.0), "missile")
	var blast: Node3D = game._spawn_blast(Vector3(0, 1.65, -9), 1.0)
	var before: Vector3 = shot.global_position
	var shot_age: float = shot.age
	var blast_age: float = blast._ages
	game._update_projectiles(0.0)
	game._update_blasts(0.0)
	expect(shot.global_position == before and is_equal_approx(shot.age, shot_age) and is_equal_approx(blast._ages, blast_age), "zero world delta freezes physical shot and blast ages")
	game.hit_stop = 0.1
	game._process(0.016)
	expect(shot.global_position == before and is_equal_approx(blast._ages, blast_age), "production hit-stop freezes shot and explosion simulation")
	game._pause_game()
	game._process(0.2)
	expect(shot.global_position == before and is_equal_approx(blast._ages, blast_age), "production pause freezes shot and explosion simulation")
	_reset()
	for index in range(40):
		game._spawn_projectile(Vector3(float(index) * 0.02, 1.65, -20), "bolt" if index % 2 == 0 else "missile")
	expect(game.projectiles.size() <= game.MAX_PROJECTILES, "hostile shot count remains bounded under repeated launches", {"live": game.projectiles.size(), "cap": game.MAX_PROJECTILES})
	for index in range(20):
		game._spawn_blast(Vector3(0, 1.65, -8), 1.0)
	expect(game.blasts.size() <= game.MAX_BLASTS, "concurrent explosion count remains bounded", {"live": game.blasts.size(), "cap": game.MAX_BLASTS})
	game._update_projectiles(20.0)
	game._update_blasts(20.0)
	expect(game.blasts.is_empty() and game.projectiles.is_empty(), "consumed or expired physical shots and their explosions are reclaimed")


func _verify_obstacles() -> void:
	for kind in ["barrier", "beam"]:
		_reset()
		var obstacle = game._spawn_enemy(kind, 1, -2.1)
		game._begin_guard()
		var speed_before: float = game.speed
		game._update_enemies(0.02, 1.0)
		expect(game.health == 4 and obstacle.resolved and not obstacle.dead and int(game.combat_stats.get("parries", 0)) == 0 and is_equal_approx(game.speed, speed_before), kind + " uncut collision hurts once despite active parry and preserves speed")
		game._update_enemies(0.2, 1.0)
		expect(game.health == 4, kind + " resolved obstruction cannot repeatedly deal contact damage")


func _posed_local(enemy, point: Vector3, part: int = 0) -> Vector3:
	return enemy.to_global(enemy._part_pose(part) * point)


func _slice_local(enemy, from: Vector3, to: Vector3, part: int = 0) -> Dictionary:
	return enemy.cut_screen(game.camera, game.camera.unproject_position(_posed_local(enemy, from, part)), game.camera.unproject_position(_posed_local(enemy, to, part)), 1.8)


func _verify_new_voxels() -> void:
	for kind in ["drone", "missile_drone", "barrier", "beam"]:
		_reset()
		var enemy = game._spawn_enemy(kind, 1, -8.0)
		enemy.position.x = 0.0
		enemy.set_action("recover", 1.0)
		var initial: int = enemy.get_remaining_voxel_count()
		var groups: Array = enemy._connected_components()
		var all_connected := groups.size() == 1 and int(groups[0].flags) == 7
		expect(initial > 100 and all_connected, kind + " starts as connected real material containing all critical tags", {"cells": initial, "components": groups.size()})
		var index: int = enemy._live_indices[enemy._live_indices.size() / 2]
		var material_point: Vector3 = enemy._posed_world_point(index)
		var trace: Dictionary = enemy.trace_projectile(material_point + Vector3(0,0,2), material_point - Vector3(0,0,2), 0.0)
		expect(bool(trace.hit) and float(trace.fraction) >= 0.0 and float(trace.fraction) <= 1.0 and enemy._voxels[int(trace.voxel_index)] != 0, kind + " swept shot collision returns an actual surviving voxel")
		var empty_trace: Dictionary = enemy.trace_projectile(enemy.global_position + Vector3(9,4,2), enemy.global_position + Vector3(9,4,-2), 0.0)
		var empty_blast: Dictionary = enemy.blast_at(enemy.global_position + Vector3(9,4,0), 0.2)
		expect(not bool(empty_trace.hit) and int(empty_blast.removed) == 0 and enemy.get_remaining_voxel_count() == initial and not enemy.dead, kind + " empty space cannot intercept a shot, remove material or kill")
		var weak_y := 1.82 if kind in ["drone", "missile_drone"] else 1.50
		var result: Dictionary
		if kind in ["drone", "missile_drone"]:
			result = _slice_local(enemy, Vector3(-0.35, weak_y, 0), Vector3(0.35, weak_y, 0))
		else:
			result = _slice_local(enemy, Vector3(0,1.10,0), Vector3(0,2.10,0))
		var remaining: int = enemy.get_remaining_voxel_count()
		expect(int(result.removed) > 0 and enemy.dead and game.kills == 1 and remaining > initial / 2, kind + " only a real critical-connection cut severs it while retaining substantial material", {"initial": initial, "removed": result.removed, "remaining": remaining})
		var piece: Node3D = null
		for child in enemy.get_children():
			if child.get_meta("voxel_piece", false) and not child.is_queued_for_deletion() and (piece == null or child.get_voxel_count() > piece.get_voxel_count()):
				piece = child
		var recut_removed := 0
		if is_instance_valid(piece):
			var cell: Vector3i = piece.cells.keys()[piece.cells.size()/2]
			var point: Vector2 = game.camera.unproject_position(piece.to_global(piece._cell_point(cell)))
			var recut: Dictionary = enemy.cut_screen(game.camera,point-Vector2(32,0),point+Vector2(32,0),1.8)
			recut_removed = int(recut.removed)
		expect(recut_removed > 0 and game.kills == 1, kind + " separated real voxel chunks can be cut again without another kill", {"recut_removed": recut_removed})
		if kind in ["barrier", "beam"]:
			enemy.position.z = -2.1
			game._update_enemies(0.05, 1.0)
			expect(game.health == 5, kind + " a physically severed obstruction no longer deals crossing damage")
		observations[kind] = {"initial_cells": initial, "first_cut_removed": result.removed, "retained_cells": remaining, "recut_removed": recut_removed}
	_reset()
	var flyer = game._spawn_enemy("drone",1,-8.0)
	flyer.position.x = 0.0
	flyer.set_action("recover",1.0)
	var hole := Vector3(1.10,2.16,-0.02)
	var hole_trace: Dictionary = flyer.trace_projectile(_posed_local(flyer,hole+Vector3(0,0,1),2),_posed_local(flyer,hole-Vector3(0,0,1),2),0.0)
	expect(not bool(hole_trace.hit), "shot tracing passes through the flyer's visible duct aperture rather than its outer bounds")
	var skim: Dictionary = flyer.blast_at(_posed_local(flyer,Vector3(1.23,2.0,-0.02),2),0.13)
	expect(int(skim.removed) > 0 and not flyer.dead and game.kills == 0, "a localized wing blast removes real material while leaving the flyer alive", {"removed": skim.removed, "remaining": flyer.get_remaining_voxel_count()})
	_reset()
	var missile_flyer = game._spawn_enemy("missile_drone",1,-8.0)
	missile_flyer.position.x = 0.0
	missile_flyer.set_action("recover",1.0)
	var origins_before: int = missile_flyer.get_ranged_origins().size()
	var pod_cut: Dictionary = _slice_local(missile_flyer,Vector3(0.62,1.50,0),Vector3(0.62,2.85,0))
	expect(origins_before == 2 and int(pod_cut.removed) > 0 and not missile_flyer.dead and missile_flyer.get_ranged_origins().size() == 1, "cutting off one real missile pod cancels only that pod's launch", {"removed": pod_cut.removed, "origins_after": missile_flyer.get_ranged_origins().size()})


func _verify_reflected_material_hit() -> void:
	_reset()
	var target = game._spawn_enemy("drone",1,-10.0)
	target.position.x = 0.0
	target.set_action("recover",1.0)
	var initial: int = target.get_remaining_voxel_count()
	var aim: Vector3 = _posed_local(target, Vector3(1.23,2.0,-0.02),2)
	var shot: Node3D = game._spawn_projectile(Vector3(aim.x,aim.y,-3.0),"bolt")
	game.projectiles[0].velocity = Vector3(0,0,-40)
	game.projectiles[0].reflected = true
	shot.set_reflected()
	game._update_projectiles(0.3)
	var remaining: int = target.get_remaining_voxel_count()
	expect(game.projectiles.is_empty() and game.blasts.size() == 1 and remaining < initial and remaining > 0 and not target.dead and game.health == 5, "a swept reflected bolt hits real wing material and creates local damage without contact-killing the flyer", {"initial": initial, "remaining": remaining})
	_reset()
	target = game._spawn_enemy("drone",1,-10.0)
	target.position.x = 0.0
	target.set_action("recover",1.0)
	game.boss_enemy = target
	game.boss_spawned = true
	# Designate this genuinely cuttable actor as the Boss callback owner. The
	# test isolates synchronous projectile-array clearing, not Boss balance.
	aim = _posed_local(target,Vector3(0,1.54,-0.03))
	game._spawn_projectile(Vector3(3,1.65,-30),"bolt")
	shot = game._spawn_projectile(aim-Vector3(0,2.0,0),"missile")
	game.projectiles[1].velocity = Vector3(0,40,0)
	game.projectiles[1].reflected = true
	shot.set_reflected()
	game._update_projectiles(0.3)
	expect(target.dead and game.projectiles.is_empty() and game.victory_timer >= 0.0 and game.kills == 1, "a real sever in a Boss-designated fixture safely clears all in-flight shots during the update callback", {"dead": target.dead, "shots": game.projectiles.size(), "victory_timer": game.victory_timer, "kills": game.kills})


func _verify_four_gear_ballistics() -> void:
	var rows: Array = []
	for gear_index in range(4):
		var exact_launch_ratio := true
		var reversed := true
		var slowed := true
		var frozen := true
		for kind in ["bolt","missile","shock"]:
			_reset()
			game.speed = [18.0,28.0,40.0,60.0][gear_index]
			game.gear = gear_index+1
			var enemy = game._spawn_enemy("normal",1,-60.0)
			var shot: Node3D = game._spawn_projectile(Vector3(3.0,2.6,-26.0),kind)
			var velocity: Vector3 = game.projectiles[0].velocity
			var previous_speed: float = game.speed+(38.0 if kind == "bolt" else 30.0)
			var previous_direction := (Vector3(0.0,1.65,-0.9)-Vector3(3.0,2.6,-26.0)).normalized()
			var expected_velocity := previous_direction*previous_speed*(2.0/3.0)
			var shot_z: float = shot.global_position.z
			var enemy_z: float = enemy.global_position.z
			game._update_enemies(0.02,1.0)
			game._update_projectiles(0.02)
			var shot_step: float = shot.global_position.z-shot_z
			var enemy_step: float = enemy.global_position.z-enemy_z
			# The latest request deliberately replaces the earlier faster-than-
			# enemies rule. Do not add a minimum speed that cancels this ratio.
			exact_launch_ratio = exact_launch_ratio and velocity.distance_to(expected_velocity) < 0.0001
			var frozen_position: Vector3 = shot.global_position
			game.hit_stop = 0.1
			game._process(0.016)
			frozen = frozen and shot.global_position == frozen_position
			game.hit_stop = 0.0
			game.slashing = true
			game.left_down = true
			game.left_time = 0.3
			var before_slow: Vector3 = shot.global_position
			var before_world: float = game.game_clock
			var before_walk: float = enemy._walk_distance
			game._process(0.1)
			var world_delta: float = game.game_clock-before_world
			slowed = slowed and is_equal_approx(world_delta,0.1*game.SLOW_SCALE) and shot.global_position.distance_to(before_slow+velocity*world_delta) < 0.0001 and is_equal_approx(enemy._walk_distance-before_walk,game.ENEMY_RUN_SPEED*world_delta)
			game.slashing = false
			game.left_down = false
			game.hit_stop = 0.0
			game._begin_guard()
			shot.global_position = Vector3(0,1.65,-1.0)
			game._update_projectiles(0.01)
			var returned: Vector3 = game.projectiles[0].velocity
			reversed = reversed and bool(game.projectiles[0].reflected) and returned.distance_to(-velocity*1.4) < 0.0001
			rows.append({"gear":gear_index+1,"kind":kind,"previous_v092_speed":previous_speed,"expected_two_thirds_speed":previous_speed*(2.0/3.0),"incoming_speed":velocity.length(),"incoming_forward_speed":velocity.z,"enemy_step":enemy_step,"shot_step":shot_step,"slow_world_delta":world_delta,"reflected_speed":returned.length()})
		expect(exact_launch_ratio,"gear %d all three physical shot launch vectors are exactly two thirds of v0.9.2 without a speed floor" % (gear_index+1))
		expect(reversed,"gear %d keeps exact reverse-line reflection after reduced-speed launches" % (gear_index+1))
		expect(slowed,"gear %d reduced-speed shots still obey the production slow world clock" % (gear_index+1))
		expect(frozen,"gear %d hit-stop freezes reduced-speed physical shots" % (gear_index+1))
	observations["four_gear_ballistics"] = rows


func _verify_grounded_walk() -> void:
	var rows: Array = []
	for runner_speed in [18.0,60.0]:
		_reset()
		game.speed = runner_speed
		game.gear = game.gear_for_speed(game.speed)
		var enemy = game._spawn_enemy("normal",1,-500.0)
		var feet: Array = [PackedInt32Array(),PackedInt32Array()]
		var leg_samples := PackedInt32Array()
		var leg_sample_counts: Dictionary = {}
		for index in enemy._live_indices:
			var part: int = enemy._part_ids[index]
			if part in [7,8]: feet[part-7].append(index)
			if part in [3,4,5,6,7,8] and int(leg_sample_counts.get(part,0)) < 10:
				leg_samples.append(index)
				leg_sample_counts[part] = int(leg_sample_counts.get(part,0))+1
		var previous_z := [0.0,0.0]
		var previous_contact := [false,false]
		var min_floor := INF
		var max_lift := 0.0
		var max_ground_error := 0.0
		var max_mesh_cut_error := 0.0
		var support_samples := 0
		var step := 1.0/120.0
		for frame in range(401):
			var old_z: float = enemy.position.z
			game.run_distance += runner_speed*step
			game._update_enemies(step,1.0)
			var root_step: float = enemy.position.z-old_z
			for leg in range(2):
				var sole_y := INF
				var centre_z := 0.0
				for index in feet[leg]:
					var posed: Vector3 = enemy._part_pose(7+leg)*enemy._cell_points[index]
					sole_y = minf(sole_y,enemy.global_position.y+posed.y-enemy._cell*0.5)
					centre_z += posed.z
				centre_z /= float(feet[leg].size())
				min_floor = minf(min_floor,sole_y)
				max_lift = maxf(max_lift,sole_y-enemy.position.y)
				var contact := absf(sole_y-enemy.position.y) < 0.00001
				if frame > 0 and contact and previous_contact[leg]:
					var world_foot_speed: float = (centre_z-previous_z[leg]+root_step)/step
					max_ground_error = maxf(max_ground_error,absf(world_foot_speed-runner_speed))
					support_samples += 1
				previous_z[leg] = centre_z
				previous_contact[leg] = contact
			if frame % 20 == 0:
				for index in leg_samples:
					var part: int = enemy._part_ids[index]
					var visual_point: Vector3 = enemy._part_meshes[part].to_global(enemy._cell_points[index])
					max_mesh_cut_error = maxf(max_mesh_cut_error,visual_point.distance_to(enemy._posed_world_point(index)))
		expect(min_floor >= enemy.position.y-0.00001 and max_lift > 0.10,"speed %.0f actual walking sole material stays above the deck and lifts through swing" % runner_speed,{"floor":enemy.position.y,"min_sole_y":min_floor,"max_lift":max_lift})
		expect(support_samples > 200 and max_ground_error < 0.02,"speed %.0f planted foot material travels with the moving road instead of sliding" % runner_speed,{"support_samples":support_samples,"max_world_ground_speed_error":max_ground_error})
		expect(max_mesh_cut_error < 0.0001,"speed %.0f animated leg mesh and real voxel-cut coordinates agree" % runner_speed,{"max_error":max_mesh_cut_error})
		var frozen_poses: Array = []
		for part in range(enemy.PART_COUNT): frozen_poses.append(enemy._part_pose(part))
		var frozen_root: Transform3D = enemy.transform
		game.hit_stop = 0.1
		game._process(0.016)
		var same_poses: bool = enemy.transform == frozen_root
		for part in range(enemy.PART_COUNT): same_poses = same_poses and enemy._part_pose(part) == frozen_poses[part]
		expect(same_poses,"speed %.0f hit-stop freezes the real torso, leg and sole poses" % runner_speed)
		rows.append({"runner_speed":runner_speed,"frames":401,"support_samples":support_samples,"min_sole_y":min_floor,"max_lift":max_lift,"max_ground_speed_error":max_ground_error,"max_mesh_cut_error":max_mesh_cut_error})
	_reset()
	var enemy = game._spawn_enemy("normal",1,-8.0)
	enemy.position.x = 0.0
	enemy.age = 0.90*0.8/(game.ENEMY_RUN_SPEED*0.6)
	enemy.set_meta("ground_run_speed",game.ENEMY_RUN_SPEED)
	enemy.set_action("run",0.0)
	var foot_index := -1
	for index in enemy._live_indices:
		if enemy._part_ids[index] == 7:
			foot_index = index
			break
	var point: Vector3 = enemy._posed_world_point(foot_index)
	var screen: Vector2 = game.camera.unproject_position(point)
	var trace: Dictionary = enemy.trace_projectile(point+Vector3(0,0,1),point-Vector3(0,0,1),0.0)
	var result: Dictionary = enemy.cut_screen(game.camera,screen-Vector2(10,0),screen+Vector2(10,0),1.8)
	expect(bool(trace.hit) and int(result.removed) > 0 and not enemy.dead,"a visibly lifted walking foot is traced and cut at its actual pose without killing the torso",{"foot_y":point.y,"removed":result.removed})
	observations["grounded_walk"] = rows


func _verify_gunner_orientation() -> void:
	_reset()
	var gunner = game._spawn_enemy("ranged",1,-24.0)
	gunner.position.x = 0.0
	gunner.set_meta("aim_target",Vector3(0,1.75,0))
	var gun: Node3D = gunner._weapons[0]
	var rows: Array = []
	var frame := 0
	for z in [-24.0,-8.0,-2.0,2.0]:
		gunner.position.z = z
		var min_forward := 1.0
		var min_continuity := 1.0
		var max_grip_gap := 0.0
		var max_support_gap := 0.0
		var max_shoulder_gap := 0.0
		var max_elbow_gap := 0.0
		var previous := Vector3.ZERO
		var actions := ["run","ranged_charge","ranged_fire"] if z < 0.0 else ["exit"]
		for action in actions:
			for sample in range(21):
				gunner.age = float(frame)/60.0
				gunner.set_action(action,float(sample)/20.0)
				frame += 1
				var forward := gun.global_basis.z.normalized()
				min_forward = minf(min_forward,forward.dot(Vector3.BACK))
				if previous.length_squared() > 0.5:
					min_continuity = minf(min_continuity,previous.dot(forward))
				previous = forward
				max_grip_gap = maxf(max_grip_gap,gun.to_global(Vector3(0,0,0.02)).distance_to(_posed_local(gunner,Vector3(0.53,1.84,0.22),2)))
				max_support_gap = maxf(max_support_gap,gun.to_global(Vector3(-0.16,-0.01,0.24)).distance_to(_posed_local(gunner,Vector3(0.37,1.83,0.44),1)))
				var shoulder := Vector3(-0.37,2.42,0)
				var elbow := Vector3(-0.55,2.04,0.04)
				max_shoulder_gap = maxf(max_shoulder_gap,_posed_local(gunner,shoulder,9).distance_to(_posed_local(gunner,shoulder,0)))
				max_elbow_gap = maxf(max_elbow_gap,_posed_local(gunner,elbow,9).distance_to(_posed_local(gunner,elbow,1)))
		expect(min_forward > 0.2 and min_continuity > 0.0 and max_grip_gap < 0.0001 and max_support_gap < 0.0001 and max_shoulder_gap < 0.0001 and max_elbow_gap < 0.0001,"gunner at z %.0f keeps the gun forward with continuous aim, both actual grips and connected shoulder / elbow poses" % z,{"min_forward_z":min_forward,"min_step_dot":min_continuity,"max_grip_gap":max_grip_gap,"max_support_gap":max_support_gap,"max_shoulder_gap":max_shoulder_gap,"max_elbow_gap":max_elbow_gap})
		rows.append({"z":z,"min_forward_z":min_forward,"min_step_dot":min_continuity,"max_grip_gap":max_grip_gap,"max_support_gap":max_support_gap,"max_shoulder_gap":max_shoulder_gap,"max_elbow_gap":max_elbow_gap,"scope":"World-fixed camera target; z>0 tests an exited actor with the target behind, not an incoming actor. Joint points and real part transforms; not an all-cell SAT contact proof."})
	gunner.position.z = -16.0
	gunner.set_meta("aim_target",Vector3(-6,1.75,0))
	for sample in range(45):
		gunner.age += 1.0/60.0
		gunner.set_action("ranged_charge",1.0)
	var left_forward := gun.global_basis.z.normalized()
	var left_target_dot := left_forward.dot((Vector3(-6,1.75,0)-gun.global_position).normalized())
	gunner.set_meta("aim_target",Vector3(6,1.75,0))
	for sample in range(45):
		gunner.age += 1.0/60.0
		gunner.set_action("ranged_charge",1.0)
	var right_forward := gun.global_basis.z.normalized()
	var right_target_dot := right_forward.dot((Vector3(6,1.75,0)-gun.global_position).normalized())
	expect(left_forward.x < -0.1 and right_forward.x > 0.1 and left_target_dot > 0.75 and right_target_dot > 0.75,"gunner aims at the supplied world camera target rather than a hard-coded origin",{"left_dot":left_target_dot,"right_dot":right_target_dot,"left_forward":str(left_forward),"right_forward":str(right_forward)})
	observations["gunner_orientation"] = rows


func _hash_bytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _remaining_authored_cells(enemy) -> PackedByteArray:
	var cells: PackedByteArray = enemy._voxels.duplicate()
	for child in enemy.get_children():
		if not child.get_meta("voxel_piece",false) or child.is_queued_for_deletion(): continue
		for coord: Vector3i in child.cells:
			cells[enemy._index(coord.x,coord.y,coord.z)] = int(child.cells[coord])
	return cells


func _material_result(enemy, before: PackedByteArray, point: Vector3, radius: float) -> Dictionary:
	var remaining := _remaining_authored_cells(enemy)
	var actual_mask := PackedByteArray()
	var expected_mask := PackedByteArray()
	actual_mask.resize(before.size())
	expected_mask.resize(before.size())
	actual_mask.fill(0)
	expected_mask.fill(0)
	var actual_count := 0
	var expected_count := 0
	for index in range(before.size()):
		if before[index] == 0: continue
		if remaining[index] == 0:
			actual_mask[index] = 1
			actual_count += 1
		if radius > 0.0 and enemy._posed_world_point(index).distance_squared_to(point) <= radius*radius:
			expected_mask[index] = 1
			expected_count += 1
	return {"removed":actual_count,"remaining":enemy.get_remaining_voxel_count(),"dead":enemy.dead,"actual_removed_mask_sha256":_hash_bytes(actual_mask),"full_scan_sphere_mask_sha256":_hash_bytes(expected_mask),"full_scan_sphere_count":expected_count,"matches_full_scan":actual_mask == expected_mask}


func _profile_target(kind: String):
	var enemy = game._spawn_enemy(kind,0,-12.0 if kind == "boss" else -9.0)
	enemy.position.x = 0.0
	enemy.set_action("recover",1.0)
	return enemy


func _profile_site(kind: String, site: String) -> Dictionary:
	var authored := {
		"normal":{"hand":[Vector3(0.61,1.23,0.22),2],"chest_side":[Vector3(-0.225,1.975,0.30),0],"core":[Vector3(0,1.86,0.30),0]},
		"tank":{"hand":[Vector3(1.30,1.18,0.22),2],"chest_side":[Vector3(0.85,2.25,0.30),0],"core":[Vector3(0,2.17,0.43),0]},
		"boss":{"hand":[Vector3(2.65,2.15,0.23),2],"chest_side":[Vector3(1.18,3.12,0.60),0],"core":[Vector3(0,2.97,0.39),0]},
		"drone":{"hand":[Vector3(1.23,2.0,-0.02),2],"chest_side":[Vector3(0.30,2.14,0),0],"core":[Vector3(0,2.12,0.25),0]},
	}
	var value: Array = authored[kind][site]
	return {"point":value[0],"part":value[1]}


func _direct_sphere_profile(kind: String, point: Vector3, radius: float) -> Dictionary:
	_reset()
	var enemy = _profile_target(kind)
	var before: PackedByteArray = enemy._voxels.duplicate()
	var result: Dictionary = enemy.blast_at(point,radius)
	var material := _material_result(enemy,before,point,radius)
	material["reported_removed"] = int(result.removed)
	material["radius"] = radius
	return material


func _verify_reflection_profiles() -> void:
	var old_rows: Dictionary = {}
	if not reflection_baseline_path.is_empty():
		var file := FileAccess.open(reflection_baseline_path,FileAccess.READ)
		var old: Dictionary = JSON.parse_string(file.get_as_text())
		file.close()
		for row in old.observations.reflection_profiles: old_rows[row.key] = row
	var rows: Array = []
	for kind in ["normal","tank","boss","drone"]:
		for site in ["hand","chest_side","core"]:
			for shot_kind in ["bolt","shock","missile"]:
				_reset()
				var enemy = _profile_target(kind)
				var before: PackedByteArray = enemy._voxels.duplicate()
				var initial_tags := _hash_bytes(enemy._tags)
				var initial_dimensions: Vector3i = enemy._dimensions
				var reactor_regions := [0,0]
				for tag: int in enemy._tags:
					if tag&8: reactor_regions[0] += 1
					if tag&16: reactor_regions[1] += 1
				var double_reactor_model: bool = enemy.has_method("get_boss_reactor_state")
				var connected_reactors := int(enemy.get_boss_reactor_state().connected) if double_reactor_model else 0
				var definition := _profile_site(kind,site)
				var aim: Vector3 = _posed_local(enemy,definition.point,int(definition.part))
				var from := aim+Vector3(0,0,4)
				var to := aim-Vector3(0,0,6)
				var shot: Node3D = game._spawn_projectile(from,shot_kind,enemy)
				var trace: Dictionary = enemy.trace_projectile(from,to,shot.collision_radius)
				var key: String = kind+":"+site+":"+shot_kind
				if not bool(trace.hit):
					expect(false,"reflection material fixture has a real first contact: "+key)
					continue
				var point: Vector3 = trace.point
				var radius: float = float({"bolt":0.27,"shock":0.48,"missile":0.70}[shot_kind]) if reflection_baseline_only else float(game.REFLECTED_BLAST_RADII[shot_kind])
				game.projectiles[0].velocity = Vector3(0,0,-40)
				game.projectiles[0].reflected = true
				shot.set_reflected()
				game._update_projectiles(0.25)
				var material := _material_result(enemy,before,point,radius)
				var row := {"key":key,"enemy_kind":kind,"site":site,"shot_kind":shot_kind,"impact_point":[point.x,point.y,point.z],"trace_voxel_index":trace.voxel_index,"initial_cells_sha256":_hash_bytes(before),"initial_tags_sha256":initial_tags,"initial_material":before.size()-before.count(0),"initial_dimensions":[initial_dimensions.x,initial_dimensions.y,initial_dimensions.z],"initial_array_size":before.size(),"initial_reactor_regions":reactor_regions,"initial_connected_reactors":connected_reactors,"radius":radius,"actual":material,"kills":game.kills}
				expect(material.matches_full_scan and material.removed == int(row.initial_material)-int(material.remaining),"reflected sphere removes exactly real cell-centres and retains every other cell: "+key)
				if kind in ["tank","boss"] and site == "hand":
					expect(not enemy.dead and (reflection_baseline_only or int(material.removed) > 0),"off-core heavy hand impact remains structural rather than contact-killing: "+key)
				if reflection_baseline_only:
					row["candidate_direct_sphere"] = _direct_sphere_profile(kind,point,float(candidate_radii[shot_kind]))
				else:
					var direct := _direct_sphere_profile(kind,point,radius)
					expect(material.actual_removed_mask_sha256 == direct.actual_removed_mask_sha256 and material.dead == direct.dead,"return damage / sever result matches the actual local sphere primitive: "+key)
					if old_rows.has(key):
						var old: Dictionary = old_rows[key]
						if kind == "boss" and double_reactor_model:
							# The097 Boss deliberately changes its occupied grid and tags.
							# Compare current-world spheres against an independent full
							# scan, never differently sized old092 index-mask hashes or
							# differently traced contacts as if they were a damage A/B.
							row["comparison_scope"] = "Revised double-reactor Boss: current full-sphere and direct-primitive oracles only. Old092 model/point identity and damage A/B are inapplicable."
							row["old092_initial_material"] = old.initial_material
							if site == "hand" and shot_kind == "bolt":
								expect(row.initial_cells_sha256 != old.initial_cells_sha256 and initial_tags != old.initial_tags_sha256 and int(row.initial_material) > int(old.initial_material) and initial_dimensions.z > 28 and reactor_regions[0] > 0 and reactor_regions[1] > 0 and connected_reactors == 2,"revised Boss explicitly changes occupied depth/material/tags and begins with two real connected reactor regions",{"dimensions":row.initial_dimensions,"material":row.initial_material,"old_material":old.initial_material,"reactor_tag_cells":reactor_regions,"connected":connected_reactors})
							expect(direct.matches_full_scan and int(direct.reported_removed) == int(material.removed) and material.actual_removed_mask_sha256 == direct.full_scan_sphere_mask_sha256,"revised Boss current first-contact blast matches independent full-sphere cells and the direct primitive exactly: "+key)
						else:
							expect(row.initial_cells_sha256 == old.initial_cells_sha256 and initial_tags == old.initial_tags_sha256 and point.distance_to(Vector3(old.impact_point[0],old.impact_point[1],old.impact_point[2])) < 0.00001,"old092 / current reflection comparison uses identical real material and first-contact point: "+key)
							row["v092_removed"] = old.actual.removed
							row["removed_increase"] = int(material.removed)-int(old.actual.removed)
							expect(int(material.removed) >= maxi(int(old.actual.removed)+5,int(ceil(float(old.actual.removed)*1.5))),"returned blast makes materially more real damage than old092 at the same contact: "+key)
							if is_equal_approx(radius,float(old.candidate_direct_sphere.radius)):
								expect(material.actual_removed_mask_sha256 == old.candidate_direct_sphere.actual_removed_mask_sha256 and material.dead == old.candidate_direct_sphere.dead,"new broad rejection preserves old092 exact same-radius cut cells / sever result: "+key)
				rows.append(row)
	observations["reflection_profiles"] = rows


func _verify_safe_blasts_and_area() -> void:
	var rows: Array = []
	for kind in ["bolt","shock","missile"]:
		_reset()
		var enemy = _profile_target("normal")
		var point := _posed_local(enemy,Vector3(0,1.86,0.30))
		var before: PackedByteArray = _remaining_authored_cells(enemy)
		game._spawn_projectile(point,kind,enemy)
		game._cut_projectile(0)
		expect(_remaining_authored_cells(enemy) == before and game.health == 5 and game.kills == 0 and game.projectiles.is_empty(),kind+" unreflected cut blast cannot damage nearby real enemy material or its player")
		_reset()
		enemy = game._spawn_enemy("normal",1,-1.0)
		enemy.position.x = 0.0
		before = _remaining_authored_cells(enemy)
		game._spawn_projectile(Vector3(0,1.65,-1.0),kind,enemy)
		game._update_projectiles(0.1)
		expect(_remaining_authored_cells(enemy) == before and game.health == 4 and game.kills == 0,kind+" failed hostile crossing causes only its single player hit, without area enemy damage")
	_reset()
	var target = _profile_target("normal")
	var near = _profile_target("normal")
	near.position += Vector3(0.55,0,-0.35)
	var far = _profile_target("normal")
	far.position += Vector3(5,0,-3)
	var actors: Array = [target,near,far]
	var before_cells: Array = []
	for enemy in actors: before_cells.append(_remaining_authored_cells(enemy))
	var aim := _posed_local(target,Vector3(0,1.86,0.30))
	var from := aim+Vector3(0,0,4)
	var to := aim-Vector3(0,0,6)
	var shot: Node3D = game._spawn_projectile(from,"missile",target)
	var first = null
	var first_hit: Dictionary = {"fraction":2.0}
	for enemy in actors:
		var trace: Dictionary = enemy.trace_projectile(from,to,shot.collision_radius)
		if bool(trace.hit) and float(trace.fraction) < float(first_hit.fraction):
			first = enemy
			first_hit = trace
	game.projectiles[0].reflected = true
	game.projectiles[0].velocity = Vector3(0,0,-40)
	shot.set_reflected()
	game._update_projectiles(0.25)
	var removed_total := 0
	var hit_count := 0
	var all_exact := true
	for index in range(actors.size()):
		var enemy = actors[index]
		var result := _material_result(enemy,before_cells[index],first_hit.point,float(game.REFLECTED_BLAST_RADII.missile))
		removed_total += int(result.removed)
		if int(result.removed) > 0: hit_count += 1
		all_exact = all_exact and bool(result.matches_full_scan)
		rows.append({"actor":index,"enemy_id":enemy.get_instance_id(),"direct_hit":enemy == first,"material":result})
	var direct_events := 0
	var direct_id := 0
	var explosion: Dictionary = {}
	for event in game.combat_events:
		if event.event == "reflected_hit" and bool(event.direct_hit):
			direct_events += 1
			direct_id = int(event.enemy_id)
		if event.event == "projectile_explosion": explosion = event
	expect(all_exact and int(rows[0].material.removed) > 0 and int(rows[1].material.removed) > 0 and int(rows[2].material.removed) == 0,"reflected impact removes only actual sphere material from nearby actors and leaves a distant actor untouched",{"actors":rows})
	expect(direct_events == 1 and direct_id == first.get_instance_id() and int(explosion.get("hit_target_count",-1)) == hit_count and int(explosion.get("removed_total",-1)) == removed_total,"one first-solid detonation records each real area victim once and exact removed totals",{"event":explosion,"first_enemy_id":first.get_instance_id()})
	observations["reflection_area"] = rows


func _verify_return_interception() -> void:
	var rows: Array = []
	for release_source in [false,true]:
		_reset()
		var source = _profile_target("tank")
		source.position = Vector3(0,-0.055,-18)
		var interceptor = _profile_target("normal")
		interceptor.position = Vector3(0,-0.055,-7)
		var source_cells: PackedByteArray = _remaining_authored_cells(source)
		var shot: Node3D = game._spawn_projectile(Vector3(0,1.65,-1.0),"missile",source)
		var incoming: Vector3 = game.projectiles[0].velocity
		game._begin_guard()
		game.guard_age = 0.075
		game._update_projectiles(0.02)
		var returned: Vector3 = game.projectiles[0].velocity
		source.position.x = 4.5
		if release_source:
			game.enemies.erase(source)
			source.free()
		var start: Vector3 = shot.global_position
		var trace: Dictionary = interceptor.trace_projectile(start,start+returned*0.5,shot.collision_radius)
		var before: PackedByteArray = _remaining_authored_cells(interceptor)
		game._update_projectiles(0.5)
		var result := _material_result(interceptor,before,trace.point,float(game.REFLECTED_BLAST_RADII.missile))
		var direct_id := 0
		for event in game.combat_events:
			if event.event == "reflected_hit" and bool(event.direct_hit): direct_id = int(event.enemy_id)
		expect(returned.distance_to(-incoming*1.4) < 0.0001 and game.projectiles.is_empty() and direct_id == interceptor.get_instance_id() and int(result.removed) > 0 and bool(result.matches_full_scan) and (release_source or _remaining_authored_cells(source) == source_cells),"real parry hits the first solid on its original reverse line after its source is "+("freed" if release_source else "moved"),{"material":result,"incoming":str(incoming),"returned":str(returned)})
		rows.append({"source_freed":release_source,"material":result,"incoming":str(incoming),"returned":str(returned)})
	observations["source_interception"] = rows


func _verify_cut_return_detonation() -> void:
	var rows: Array = []
	for reflected in [true,false]:
		_reset()
		var target = _profile_target("normal")
		var near = _profile_target("normal")
		near.position += Vector3(0.55,0,-0.35)
		var far = _profile_target("normal")
		far.position += Vector3(5,0,-3)
		var actors: Array = [target,near,far]
		var before: Array = []
		for enemy in actors: before.append(_remaining_authored_cells(enemy))
		var point := _posed_local(target,Vector3(0,1.86,0.30))
		# Synchronous sever of this real body invokes the actual Boss owner
		# callback, which clears another shot while the blast is iterating.
		game.boss_enemy = target
		game.boss_spawned = true
		game._spawn_projectile(Vector3(3,1.65,-30),"bolt")
		var shot: Node3D = game._spawn_projectile(point,"missile",target)
		if reflected:
			game.projectiles[1].reflected = true
			shot.set_reflected()
		game._cut_projectile(1)
		var materials: Array = []
		var total := 0
		for index in range(actors.size()):
			var material := _material_result(actors[index],before[index],point,float(game.REFLECTED_BLAST_RADII.missile) if reflected else 0.0)
			materials.append(material)
			total += int(material.removed)
		var explosions: Array = []
		var cuts := 0
		var direct_hits := 0
		for event in game.combat_events:
			if event.event == "projectile_explosion": explosions.append(event)
			if event.event == "projectile_cut": cuts += 1
			if event.event == "reflected_hit" and bool(event.direct_hit): direct_hits += 1
		if reflected:
			expect(materials[0].matches_full_scan and materials[1].matches_full_scan and int(materials[0].removed) > 0 and int(materials[1].removed) > 0 and int(materials[2].removed) == 0 and game.health == 5,"blade detonation of an already reflected shot uses its real sphere on multiple nearby actors without far-target or player damage",{"materials":materials})
			var explosion: Dictionary = explosions[0] if explosions.size() == 1 else {}
			expect(explosions.size() == 1 and cuts == 1 and int(game.combat_stats.get("projectile_explosions",0)) == 1 and int(game.combat_stats.get("projectiles_cut",0)) == 1 and int(explosion.get("removed_total",-1)) == total and int(explosion.get("hit_target_count",-1)) == 2 and explosion.get("world_point",[]) == [point.x,point.y,point.z] and direct_hits == 0,"cut return records one target-less area detonation, exact material totals and its actual world point",{"event":explosion})
			var score: int = game.score
			var kills: int = game.kills
			game._update_projectiles(0.2)
			game._update_projectiles(0.2)
			expect(target.dead and game.victory_timer >= 0.0 and game.projectiles.is_empty() and game.blasts.size() == 1 and game.kills == kills and game.score == score,"cut return removes its shot before a real Boss-owner sever clears the other shot and cannot repeat its kill or score",{"kills":kills,"score":score,"shots":game.projectiles.size()})
		else:
			expect(total == 0 and _remaining_authored_cells(target) == before[0] and _remaining_authored_cells(near) == before[1] and _remaining_authored_cells(far) == before[2] and game.health == 5 and game.kills == 0 and game.score == 30*game.gear and explosions.size() == 1 and cuts == 1 and game.projectiles.size() == 1,"cutting an unreflected shot at the identical point leaves every enemy intact and pays only one safe projectile-cut reward")
		rows.append({"reflected":reflected,"point":[point.x,point.y,point.z],"materials":materials,"explosions":explosions,"cuts":cuts,"kills":game.kills,"score":game.score})
	observations["cut_return_detonation"] = rows


func _verify_sphere_edges_and_holes() -> void:
	var rows: Array = []
	for kind in ["normal","tank","boss","drone"]:
		for offset in [-0.0001,0.0001]:
			_reset()
			var enemy = _profile_target(kind)
			var before: PackedByteArray = enemy._voxels.duplicate()
			var front_index := -1
			var front_z := -INF
			for index in enemy._live_indices:
				var point: Vector3 = enemy._posed_world_point(index)
				if point.z > front_z:
					front_z = point.z
					front_index = index
			var radius := 0.12
			var point: Vector3 = enemy._posed_world_point(front_index)+Vector3(0,0,radius+offset)
			var blast: Dictionary = enemy.blast_at(point,radius)
			var material := _material_result(enemy,before,point,radius)
			expect(material.matches_full_scan and int(blast.removed) == int(material.removed) and ((int(material.removed) > 0) if offset < 0.0 else int(material.removed) == 0),kind+" sphere boundary "+("inside" if offset < 0.0 else "outside")+" conservatively rejects bounds without changing exact live-cell distance tests",material)
			rows.append({"kind":kind,"edge_offset":offset,"material":material})
		_reset()
		var enemy = _profile_target(kind)
		var index: int = enemy._live_indices[enemy._live_indices.size()/2]
		var point: Vector3 = enemy._posed_world_point(index)
		var first: Dictionary = enemy.blast_at(point,0.01)
		var remaining: int = enemy.get_remaining_voxel_count()
		var repeat: Dictionary = enemy.blast_at(point,0.01)
		var shifted: Dictionary = enemy.blast_at(point+Vector3(0.003,0,0),0.01)
		expect(int(first.removed) == 1 and int(repeat.removed) == 0 and int(shifted.removed) == 0 and enemy.get_remaining_voxel_count() == remaining,kind+" a true one-cell hole remains empty for repeated and shifted local blasts",{"initial_removed":first.removed,"repeat_removed":repeat.removed,"shifted_removed":shifted.removed})
	observations["sphere_boundaries"] = rows


func _verify_reflection_feedback() -> void:
	_reset()
	var blast: Node3D = game._spawn_blast(Vector3(0,1.7,-8),1.35,true)
	var initial: Dictionary = blast.get_debug_state()
	game._update_blasts(0.083)
	var active: Dictionary = blast.get_debug_state()
	game.hit_stop = 0.1
	game._process(0.016)
	var frozen: Dictionary = blast.get_debug_state()
	expect(bool(initial.reflected_impact) and int(initial.instance_count) > 0 and bool(initial.pose_initialized) and active == frozen,"reflected CPU particle poses initialize, expand and freeze with production hit-stop",{"initial":initial,"active":active,"scope":"CPU submitted instance poses; no GPU visibility or subjective visual verdict"})
	var audio = game.audio
	audio._last_event_msec.clear()
	audio.play_event("explosion_reflected",1.35)
	var reserved: Array = []
	for player in audio._players:
		if player.get_meta("event","") == "explosion_reflected": reserved.append({"player":player,"stream":player.stream,"event":player.get_meta("event")})
	for kind in ["kill","hit","explosion","parry_clash","slash","hurt"]:
		for index in range(8):
			audio._last_event_msec.erase(kind)
			audio.play_event(kind,1.35)
	var preserved: bool = not reserved.is_empty() and audio._players.size() == 24
	for item in reserved: preserved = preserved and item.player.stream == item.stream and item.player.get_meta("event") == item.event
	expect(preserved,"finite independent reflected-explosion audio voices are not stolen by dense kill, impact and sword cues",{"reserved_voice_count":reserved.size(),"total_voice_count":audio._players.size(),"scope":"Voice ownership and stream identity; not an audible quality verdict"})


func _verify_reflection_residue() -> void:
	var rows: Array = []
	for kind in ["normal","tank","boss"]:
		_reset()
		var enemy = _profile_target(kind)
		var site := "core" if kind == "normal" else "hand"
		var definition := _profile_site(kind,site)
		var aim := _posed_local(enemy,definition.point,int(definition.part))
		var initial: int = enemy.get_remaining_voxel_count()
		var shot: Node3D = game._spawn_projectile(aim+Vector3(0,0,4),"missile",enemy)
		game.projectiles[0].velocity = Vector3(0,0,-40)
		game.projectiles[0].reflected = true
		shot.set_reflected()
		game._update_projectiles(0.25)
		var after_blast: int = enemy.get_remaining_voxel_count()
		var dead_after_blast: bool = enemy.dead
		expect(after_blast < initial and ((enemy.dead and game.kills == 1) if kind == "normal" else (not enemy.dead and game.kills == 0)),kind+" strong returned missile still resolves death from the actually struck connection",{"initial":initial,"after_blast":after_blast,"dead_after_blast":dead_after_blast})
		var further_removed := 0
		var passes := 0
		if not enemy.dead:
			var centre: Vector2 = game.camera.unproject_position(enemy.get_aim_point())
			var bounds: Rect2 = enemy.get_screen_bounds(game.camera)
			# Genuine visible material is cut layer by layer. The Boss now has
			# two deep cassettes, not the old single shallow central core. Sweep
			# explicit narrow lines over both visible ports as their layers recede
			# in perspective; never erase tags or call the material commit helper.
			if kind == "boss" and enemy.has_method("get_boss_reactor_state"):
				for pass_index in range(enemy._dimensions.z+1):
					var pass_removed := 0
					for side in [-1.0,1.0]:
						for row in range(13):
							var y := 2.56+float(row)*0.08
							var a: Vector2 = game.camera.unproject_position(enemy.to_global(enemy._part_pose(0)*Vector3(side*1.08-0.62,y,0.84)))
							var b: Vector2 = game.camera.unproject_position(enemy.to_global(enemy._part_pose(0)*Vector3(side*1.08+0.62,y,0.84)))
							var cut: Dictionary = enemy.cut_screen(game.camera,a,b,2.15)
							pass_removed += int(cut.removed)
							passes += 1
							if enemy.dead: break
						if enemy.dead: break
					further_removed += pass_removed
					if enemy.dead or pass_removed == 0: break
			else:
				for pass_index in range(enemy._dimensions.z+1):
					var cut: Dictionary = enemy.cut_screen(game.camera,Vector2(bounds.position.x-4,centre.y),Vector2(bounds.end.x+4,centre.y),2.15)
					further_removed += int(cut.removed)
					passes += 1
					if enemy.dead or int(cut.removed) == 0: break
			expect(enemy.dead and game.kills == 1 and further_removed > 0 and enemy.get_remaining_voxel_count() == after_blast-further_removed,kind+" surviving off-core blast damage remains available for subsequent real layer cuts and exactly one structural kill",{"passes":passes,"further_removed":further_removed,"remaining":enemy.get_remaining_voxel_count()})
		var score_after: int = game.score
		var retained_before: int = enemy.get_remaining_voxel_count()
		var recut_removed := 0
		for piece in enemy.get_children():
			if not piece.get_meta("voxel_piece",false) or piece.is_queued_for_deletion(): continue
			var bounds: Rect2 = piece.get_screen_bounds(game.camera)
			var result: Dictionary = enemy.cut_screen(game.camera,Vector2(bounds.position.x-4,bounds.get_center().y),Vector2(bounds.end.x+4,bounds.get_center().y),2.15)
			recut_removed += int(result.removed)
			if recut_removed > 0: break
		var dead_blast: Dictionary = enemy.blast_at(aim,1.45)
		expect(recut_removed > 0 and enemy.get_remaining_voxel_count() == retained_before-recut_removed and game.kills == 1 and game.score == score_after and int(dead_blast.removed) == 0,kind+" blast-then-cut debris retains real recuttable cells without duplicate sever, kill or score",{"recut_removed":recut_removed,"remaining":enemy.get_remaining_voxel_count()})
		rows.append({"kind":kind,"initial":initial,"after_reflected_blast":after_blast,"dead_after_blast":dead_after_blast,"further_cut_passes":passes,"further_removed":further_removed,"recut_removed":recut_removed,"kills":game.kills})
	observations["reflection_residue"] = rows


func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.test_mode = true
	game.set_process(false)
	game.sword.set_process(false)
	if reflection_baseline_only:
		_verify_reflection_profiles()
		await _finish()
		return
	for kind in ["bolt", "missile"]:
		_cut_shot(kind)
		_reflect_shot(kind)
	_verify_chain_and_crossing()
	_verify_relative_interception()
	_verify_interception_order_and_guard_reward()
	_verify_chain_payloads_and_callbacks()
	_verify_chain_freeze_and_capacity()
	_verify_freeze_and_limits()
	_verify_obstacles()
	_verify_new_voxels()
	_verify_reflected_material_hit()
	_verify_four_gear_ballistics()
	_verify_grounded_walk()
	_verify_gunner_orientation()
	_verify_reflection_profiles()
	_verify_safe_blasts_and_area()
	_verify_return_interception()
	_verify_cut_return_detonation()
	_verify_sphere_edges_and_holes()
	_verify_reflection_feedback()
	_verify_reflection_residue()
	await _finish()


func _finish() -> void:
	_reset()
	game._pause_game()
	game.audio.set_runner_motion(0.0, 0.0, false, 0.0)
	await create_timer(1.0).timeout
	var report := {"engine":Engine.get_version_info().string,"version":ProjectSettings.get_setting("application/config/version"),"checks":checks,"failures":failures,"observations":observations,"baseline_only":reflection_baseline_only,"baseline_reference":reflection_baseline_path,"baseline_sha256":FileAccess.get_sha256(reflection_baseline_path) if not reflection_baseline_path.is_empty() else "","candidate_radii":candidate_radii,"tool_sha256":FileAccess.get_sha256(get_script().resource_path),"runtime_main_sha256":FileAccess.get_sha256("res://scripts/main.gd"),"runtime_enemy_sha256":FileAccess.get_sha256("res://scripts/voxel_enemy.gd"),"scope":"Injected deterministic production-logic fixture. Actual projectile meshes and APIs, direct production blade paths and simulation stepping. No GPU rendering, real-time performance, normal-difficulty or subjective-feel acceptance."}
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("COMBAT EXPANSION VERIFY: ", checks.size(), " checks, ", failures, " failures")
	game.free()
	await process_frame
	quit(0 if failures == 0 else 1)
