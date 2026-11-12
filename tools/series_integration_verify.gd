extends SceneTree
## Isolated adapters and fixed projectile state checks only. No actor AI,
## wave progression, route completion, input controller or gameplay replay.

var checks := 0
var failures: Array[String] = []
var game: Node3D
var output := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--series-output="): output = arg.trim_prefix("--series-output=")
	call_deferred("_run")

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _shot(node: Node3D) -> Dictionary:
	var index: int = game._projectile_index(node)
	return game.projectiles[index] if index >= 0 else {}

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	while not game.campaign.assets_ready: await process_frame
	expect(game.state == "menu" and not game.campaign.active,"preparation never starts combat")
	expect(game.campaign.run.route.size() == 4,"exactly four prepared levels")
	var route: Array = game.campaign.run.route
	expect(route[0] == 1 and route[3] == 5 and route[1] != route[2],"fixed endpoints and unique middle levels")
	game._clear_projectiles()
	var node: Node3D = game._spawn_projectile(Vector3(-3,2,-20),"seal",null)
	var shot: Dictionary = _shot(node)
	var launch: Vector3 = shot.velocity
	game._configure_series_projectile(node,"prime",{"delay":0.65})
	expect(Vector3(shot.velocity) == Vector3.ZERO,"seal actually remains stationary during priming")
	shot.age = 0.64
	game._update_series_projectile_behaviors(0.0)
	expect(Vector3(shot.velocity) == Vector3.ZERO,"seal cannot launch before priming deadline")
	shot.age = 0.66
	game._update_series_projectile_behaviors(0.0)
	expect(Vector3(shot.velocity) == launch,"priming restores exact saved velocity")
	game._clear_projectiles()
	node = game._spawn_projectile(Vector3(-3,2,-20),"torpedo",null)
	shot = _shot(node)
	launch = shot.velocity
	game._configure_series_projectile(node,"bend",{"delay":0.35,"target":Vector3(0,1.65,-0.9)})
	expect(is_equal_approx(Vector3(shot.velocity).length(),launch.length()),"torpedo outbound leg preserves speed")
	shot.age = 0.36
	game._update_series_projectile_behaviors(0.0)
	var bent: Vector3 = shot.velocity
	expect(bent.normalized().dot((Vector3(0,1.65,-0.9)-node.position).normalized()) > 0.99999,"torpedo uses one preset bend target")
	expect(not shot.has("series_behavior"),"torpedo bend executes only once")
	game._configure_series_projectile(node,"bend",{"delay":0.35})
	shot.reflected = true
	shot.velocity = -launch*1.4
	shot.age = 1.0
	game._update_series_projectile_behaviors(0.0)
	expect(Vector3(shot.velocity) == -launch*1.4,"reflected projectile can never be steered by a delayed behavior")
	game._clear_projectiles()
	var source: Node3D = game._spawn_enemy("cyber_drone",0,-22)
	source.set_process(false)
	node = game._spawn_projectile(Vector3(-3,2,-20),"beacon",source)
	shot = _shot(node)
	game._configure_series_projectile(node,"beacon",{"interval":0.55,"shots":2})
	shot.age = 0.56
	game._update_series_projectile_behaviors(0.0)
	expect(game.projectiles.size() == 2 and int(shot.series_emitted) == 1,"cuttable beacon emits one physical shot")
	var first: Dictionary = game.projectiles.back()
	expect(Vector3(first.node.position).distance_to(node.position) < 0.000001,"beacon shot starts from its actual position")
	shot.age = 1.12
	game._update_series_projectile_behaviors(0.0)
	expect(game._projectile_index(node) == -1 and game.projectiles.size() == 2,"beacon stops after exactly two physical emissions")
	game._clear_projectiles()
	node = game._spawn_projectile(Vector3(-3,2,-20),"beacon",source)
	shot = _shot(node)
	game._configure_series_projectile(node,"beacon",{"interval":0.55,"shots":2})
	source.dead = true
	shot.age = 0.56
	game._update_series_projectile_behaviors(0.0)
	expect(game.projectiles.is_empty(),"destroyed source cancels beacon without a phantom shot")
	game.enemies.erase(source)
	source.queue_free()
	await process_frame
	var before_nodes := game.get_child_count()
	var fx_nodes: int = game.series_effects.get_child_count()
	for i in range(25): game.series_effects.emit_burst(Vector3(0,2,-15),2+i%4,2.0,2)
	var fx: Dictionary = game.series_effects.get_debug_state()
	expect(int(fx.active_slots) <= 8 and int(fx.visible_particles) <= 1024,"new effects keep fixed slot and particle caps")
	expect(game.get_child_count() == before_nodes and game.series_effects.get_child_count() == fx_nodes,"burst submission allocates no extra scene nodes")
	var serial: int = fx.serial
	game.series_effects.update(0.0)
	expect(game.series_effects.get_debug_state().serial == serial,"frozen visual update cannot re-emit effects")
	game.series_effects.clear()
	var runtime: RefCounted = game.campaign
	runtime.spawn_queue.assign([{"kind":"ink_swordsman","lane":0,"z":-50.0,"boss":false},{"kind":"ink_spear","lane":2,"z":-50.0,"boss":false}])
	var initial: int = game.enemies.size()
	runtime._drain_activation_queue()
	runtime._drain_activation_queue()
	expect(game.enemies.size() == initial+1 and runtime.spawn_queue.size() == 1,"same-frame activation is limited to one actor")
	await process_frame
	runtime._drain_activation_queue()
	expect(game.enemies.size() == initial+2 and runtime.spawn_queue.is_empty(),"next frame consumes one remaining reservation")
	for actor: Node3D in game.enemies:
		expect(bool(actor.get_meta("entry_active",false)) and actor.position.z < -40.0,"explicitly spawned ground actors begin outside cut range")
	var counts: Dictionary = runtime._live_and_reserved()
	expect(int(counts.ground) == 2 and int(counts.shooters) == 2,"live swordsman and spear both count against the shooter budget")
	expect(game.elapsed == 0.0 and game.kills == 0 and game.health == 5,"adapter checks never advance a wave, attack, kill or route")
	var result := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"scope":"Static scene adapters; fixed projectile state transitions; explicit two-actor activation only. No actor AI, wave progression, player input, route completion or performance claim.","engine":Engine.get_version_info().string}
	if not output.is_empty():
		var file := FileAccess.open(output,FileAccess.WRITE)
		file.store_string(JSON.stringify(result,"\t"))
	game.queue_free()
	await process_frame
	await process_frame
	print("SERIES_ADAPTERS: ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
