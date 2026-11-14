extends RefCounted
## A separate practice run using the same blade, speed and projectile rules.

enum Lesson { LIGHT, HELD, REFLECT, BOOST, DRAIN, COMPLETE }

const LESSON_COUNT := 5
const TARGET_RETRY_SECONDS := 0.85
const SHOT_CHARGE_SECONDS := 0.95
const REFLECT_OBSERVE_SECONDS := 0.70

var active := false
var completed := false
var _game
var _lesson := Lesson.LIGHT
var _target: Node3D
var _shot: Node3D
var _light_hit_style := -1
var _held_contact := false
var _reflected_at_start := 0
var _reflected_age := 0.0
var _charge_age := 0.0
var _retry_age := 0.0
var _boost_age := 0.0
var _shot_fired := false


func begin(game: Node) -> void:
	stop()
	_game = game
	active = true
	_game.training = false
	_game.practice = false
	if _game.campaign != null:
		_game.campaign.suspend()
	if _game.series_scenery != null:
		_game.series_scenery.force_series(1)
	_game.start_game()
	_game.message_timer = 0.0
	_begin_lesson(Lesson.LIGHT)


func stop() -> void:
	_clear_target()
	_shot = null
	active = false
	completed = false
	_game = null


func observe_light_release(hold_time: float) -> void:
	if not active or _lesson != Lesson.LIGHT:
		return
	if hold_time < _game.LONG_PRESS and _light_hit_style == _game.quick_slash_index:
		_begin_lesson(Lesson.HELD)


func update(real_delta: float, world_delta: float) -> void:
	if not active or completed:
		return
	if is_instance_valid(_target):
		_target.set_meta("simulation_scale",world_delta/maxf(real_delta,0.00001))
		_target.set_meta("root_motion_velocity",Vector3.ZERO)
		_target.set_meta("flythrough_enabled",false)
		_target.set_meta("runner_speed",_game.speed)
		_target.set_meta("aim_target",_game.camera.global_position)
	match _lesson:
		Lesson.LIGHT:
			if _game.touch_mode and _light_hit_style == _game.quick_slash_index:
				_begin_lesson(Lesson.HELD)
			else:
				_retry_target(world_delta,"normal",-8.5)
		Lesson.HELD:
			if _held_contact and not _game.slashing:
				_begin_lesson(Lesson.REFLECT)
			elif not _held_contact:
				_retry_target(world_delta,"tank",-9.5)
		Lesson.REFLECT:
			_update_reflect(real_delta,world_delta)
		Lesson.BOOST:
			if _game.shift_down and not _game.slashing:
				_boost_age += real_delta
				if _boost_age >= 0.25 and _game.gear >= 2:
					_begin_lesson(Lesson.DRAIN)
			else:
				_boost_age = 0.0
		Lesson.DRAIN:
			if _game.left_down and _game.slash_lock and is_equal_approx(float(_game.speed),float(_game.MIN_SPEED)):
				_begin_lesson(Lesson.COMPLETE)


func snapshot() -> Dictionary:
	if not active:
		return {}
	var row := {"active":true,"step":mini(int(_lesson)+1,LESSON_COUNT),
		"total":LESSON_COUNT,"completed":completed,"target":Vector2.INF}
	var touch: bool = _game.touch_mode
	match _lesson:
		Lesson.LIGHT:
			row.merge({"title":"轻击",
				"prompt":"对准靶机，点按「普攻」" if touch else "对准靶机，轻点鼠标左键",
				"detail":"刀鞘上两道红灯缓慢明灭，表示有敌人可斩。\n刀刃只切到划过的体素。"})
		Lesson.HELD:
			row.merge({"title":"自由斩切",
				"prompt":("松开「斩击」收刀" if touch else "松开左键收刀") if _held_contact else ("按住「斩击」，拖过靶机" if touch else "按住左键，挥动鼠标切过靶机"),
				"detail":"黑边出现后，时间变慢。\n移动握点，让刀刃划过目标。"})
		Lesson.REFLECT:
			row.merge({"title":"振刀弹反",
				"prompt":"弹反成功" if _reflected_age > 0.0 else ("按住「振刀」，接住来弹" if touch else "按住鼠标右键，接住来弹"),
				"detail":"刀鞘红灯高亮，表示可弹反的攻击即将命中。\n来弹会沿原路反弹，精准振刀还能提速。"})
		Lesson.BOOST:
			row.merge({"title":"加速升档",
				"prompt":"按住「提速」，升到 II 档" if touch else "按住 Shift，升到 II 档",
				"detail":"24 / 36 / 48 m/s 依次升档。\n档位越高，切割越强，更容易切穿装甲。"})
		Lesson.DRAIN:
			row.merge({"title":"斩切耗速",
				"prompt":"持续按住「斩击」，等速度耗尽" if touch else "持续按住左键，等速度耗尽",
				"detail":"长斩持续消耗速度，跑得越快能斩越久。\n降到 4 m/s 会自动收刀。"})
		Lesson.COMPLETE:
			row.merge({"title":"训练完成","prompt":"打开暂停菜单，返回标题" if touch else "按 Enter 返回标题",
				"detail":"用 Shift 升档，留足速度再长斩。\n刀鞘红灯呼吸时有敌人可斩，高亮时准备振刀。"})
	if (_lesson == Lesson.LIGHT or (_lesson == Lesson.HELD and not _held_contact)) and is_instance_valid(_target) and not _target.get("dead"):
		var point: Vector3 = _target.call("get_aim_point")
		if not _game.camera.is_position_behind(point):
			row.target = _game.camera.unproject_position(point)
	return row


func _begin_lesson(next: Lesson) -> void:
	_clear_target()
	_lesson = next
	_retry_age = 0.0
	_charge_age = 0.0
	_boost_age = 0.0
	_shot_fired = false
	_light_hit_style = -1
	_held_contact = false
	match _lesson:
		Lesson.LIGHT:
			_spawn_target("normal",-8.5)
		Lesson.HELD:
			_spawn_target("tank",-9.5)
		Lesson.REFLECT:
			_reflected_at_start = int(_game.combat_stats.get("projectiles_reflected",0))
			_reflected_age = 0.0
			_spawn_target("ranged",-22.0)
		Lesson.COMPLETE:
			completed = true


func _spawn_target(kind: String, depth: float) -> void:
	_target = _game._spawn_enemy(kind,1,depth)
	_target.position.x = 0.0
	_target.set_meta("lane_x",0.0)
	_target.set_meta("flythrough_enabled",false)
	_target.set_meta("aim_target",_game.camera.global_position)
	_target.connect("damaged",_on_target_contact)
	_target.connect("severed",_on_target_contact)


func _clear_target() -> void:
	if is_instance_valid(_target):
		_game.enemies.erase(_target)
		_target.hide()
		_target.queue_free()
	_target = null


func _on_target_contact(enemy: Node3D, _point: Vector3, removed: int) -> void:
	if removed <= 0 or enemy != _target or not enemy.has_meta("held_cut_fx"):
		return
	var held := bool(enemy.get_meta("held_cut_fx"))
	if _lesson == Lesson.LIGHT and not held:
		_light_hit_style = _game.quick_slash_index
	elif _lesson == Lesson.HELD and held:
		_held_contact = true


func _retry_target(world_delta: float, kind: String, depth: float) -> void:
	if is_instance_valid(_target) and not _target.get("dead"):
		_retry_age = 0.0
		return
	_retry_age += world_delta
	if _retry_age >= TARGET_RETRY_SECONDS:
		_clear_target()
		_spawn_target(kind,depth)
		_retry_age = 0.0


func _update_reflect(real_delta: float, world_delta: float) -> void:
	if int(_game.combat_stats.get("projectiles_reflected",0)) > _reflected_at_start:
		_reflected_age += real_delta
		if _reflected_age >= REFLECT_OBSERVE_SECONDS:
			_game._clear_projectiles()
			_begin_lesson(Lesson.BOOST)
		return
	if is_instance_valid(_shot) and not _shot.is_queued_for_deletion():
		return
	if not is_instance_valid(_target) or _target.get("dead"):
		_retry_target(world_delta,"ranged",-22.0)
		return
	if _shot_fired:
		_shot_fired = false
		_charge_age = -0.60
	_charge_age += world_delta
	if _charge_age <= 0.0:
		return
	if _charge_age <= world_delta:
		_game.audio.play_event("ranged_charge",0.8)
	_target.call("set_action","ranged_charge",clampf(_charge_age/SHOT_CHARGE_SECONDS,0.0,1.0))
	if _charge_age < SHOT_CHARGE_SECONDS:
		return
	_target.call("set_action","ranged_fire",0.25)
	var origins: Array[Vector3] = _target.call("get_ranged_origins")
	if origins.is_empty():
		_clear_target()
		_retry_age = TARGET_RETRY_SECONDS
		return
	_shot = _game._spawn_projectile(origins[0],"bolt",_target)
	_shot_fired = true
	_game.audio.play_event("ranged_fire",0.8)
