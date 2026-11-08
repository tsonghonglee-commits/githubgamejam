class_name PrototypeHUD
extends Control

const REFERENCE_SIZE := Vector2(1280.0, 720.0)
const INK := Color(0.025, 0.038, 0.052)
const WHITE := Color(0.9, 0.95, 0.96)
const MUTED := Color(0.49, 0.62, 0.66)
const CYAN := Color(0.32, 0.96, 0.86)
const AMBER := Color(1.0, 0.51, 0.24)
const RED := Color(1.0, 0.24, 0.25)
const GEAR_COLORS := [Color(0.35, 0.79, 0.76), Color(0.47, 0.94, 0.75), Color(1.0, 0.72, 0.31), Color(1.0, 0.35, 0.26)]

var _snapshot: Dictionary = {}
var _font: Font
var _animation_time := 0.0
var _trails: Array[Dictionary] = []
var _last_path := PackedVector2Array()
var _last_blade_alpha := 0.0
var _last_cut_serial := -1
var _last_impact_strength := 0.0
var _last_kill_pulse := 0.0
var _last_parry_pulse := 0.0
var _last_contact_serial := -1
var _contact_age := 10.0
var _contact_point := Vector2.ZERO
var _contact_direction := Vector2.RIGHT
var _contact_kind := "hit"


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	var real_delta := delta / maxf(Engine.time_scale, 0.001)
	_animation_time += real_delta
	_contact_age += real_delta
	for index in range(_trails.size() - 1, -1, -1):
		_trails[index].age += real_delta
		if float(_trails[index].age) >= 0.075:
			_trails.remove_at(index)
	queue_redraw()


func set_snapshot(data: Dictionary) -> void:
	_snapshot = data
	var alpha := float(data.get("blade_alpha", 0.0))
	var path: PackedVector2Array = data.get("blade_path", PackedVector2Array())
	var serial := int(data.get("cut_serial", 0))
	var impact := clampf(float(data.get("impact_strength", 0.0)), 0.0, 1.0)
	var kill := clampf(float(data.get("kill_pulse", 0.0)), 0.0, 1.0)
	var parry := clampf(float(data.get("parry_pulse", 0.0)), 0.0, 1.0)
	var contact_serial := int(data.get("contact_serial", -1))
	var new_contact: bool = contact_serial != -1 and contact_serial != _last_contact_serial
	if contact_serial == -1:
		new_contact = impact > _last_impact_strength + 0.025 or kill > _last_kill_pulse + 0.1 or parry > _last_parry_pulse + 0.1
	if new_contact and maxf(impact, maxf(kill, parry)) > 0.1 and data.has("impact_point"):
		_contact_age = 0.0
		_contact_point = Vector2(data.impact_point)
		_contact_direction = Vector2(data.get("impact_direction", Vector2.RIGHT)).normalized()
		if _contact_direction.length_squared() < 0.1:
			_contact_direction = Vector2.RIGHT
		_contact_kind = str(data.get("contact_kind", "parry" if parry > _last_parry_pulse + 0.1 else ("kill" if kill > _last_kill_pulse + 0.1 else "hit")))
	if path.size() < 2 and alpha > 0.15:
		path = PackedVector2Array([Vector2(data.get("blade_from", size * 0.5)), Vector2(data.get("blade_to", size * 0.5))])
	if str(data.get("state", "menu")) != "playing":
		_trails.clear()
		_contact_age = 10.0
	elif path.size() >= 2 and alpha > 0.15 and (serial != _last_cut_serial or path != _last_path or alpha > _last_blade_alpha + 0.15):
		# One contact path only. Blade root / tip trajectories are construction
		# data and must never turn into two parallel apparent attacks.
		_trails.append({"path": path.duplicate(), "age": 0.0})
		while _trails.size() > 8:
			_trails.pop_front()
	_last_path = path
	_last_blade_alpha = alpha
	_last_cut_serial = serial
	_last_impact_strength = impact
	_last_kill_pulse = kill
	_last_parry_pulse = parry
	_last_contact_serial = contact_serial
	queue_redraw()


func _draw() -> void:
	if _font == null or size.x < 1.0 or size.y < 1.0:
		return
	var scale_factor := size / REFERENCE_SIZE
	draw_set_transform(Vector2.ZERO, 0.0, scale_factor)
	var state := str(_snapshot.get("state", "menu"))
	var flash := clampf(float(_snapshot.get("flash", 0.0)), 0.0, 1.0)
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, REFERENCE_SIZE), Color(1.0, 0.14, 0.08, flash * 0.22))
	if bool(_snapshot.get("slow", false)):
		draw_rect(Rect2(0, 0, 1280, 3), Color(CYAN, 0.75))
		draw_rect(Rect2(0, 717, 1280, 3), Color(CYAN, 0.75))
	if state == "playing":
		_draw_kinetics()
	_draw_telemetry()
	_draw_speed_bar()
	if state == "playing":
		_draw_targets(scale_factor)
		_draw_aim(scale_factor)
		_draw_contact(scale_factor)
		_draw_combat_messages()
	elif state == "menu":
		_draw_menu()
	elif state == "paused":
		_draw_overlay("已暂停", "PAUSED", "Esc / Enter / 点击继续", MUTED)
	elif state == "dead":
		_draw_overlay("信号中断", "RUN TERMINATED", "Enter 或点击重新开始", RED)
	elif state == "won":
		_draw_overlay("突破完成", "CORE SEVERED", "Enter 或点击再次挑战", CYAN)
	draw_set_transform(Vector2.ZERO)


func _draw_kinetics() -> void:
	var effective: float = float(_snapshot.get("effective_runner_speed", 0.0))
	var pressure: float = clampf((effective - 26.0) / 34.0, 0.0, 1.0) * 0.44
	if pressure < 0.03:
		return
	# Real moving floor / near scenery carry the run. These sparse edge traces
	# only accent high-speed air flow, using world distance rather than HUD time.
	var distance: float = float(_snapshot.get("run_distance", 0.0))
	for index in range(12):
		var angle: float = float(index) * TAU / 12.0 + 0.11 * sin(float(index) * 2.4)
		var ray := Vector2(cos(angle), sin(angle))
		var travel: float = fposmod(distance / 18.0 + float(index) * 0.381, 1.0)
		var outer := Vector2(640, 360) + ray * Vector2(700, 420) * lerpf(0.72, 1.13, travel)
		var length: float = (20.0 + pressure * 75.0) * (0.4 + travel * 0.6)
		var fade: float = sin(travel * PI) * pressure
		var tint := Color(0.79, 0.87, 0.89, fade * 0.16)
		draw_line(outer - ray * length, outer, tint, 1.0 + pressure * 1.25, true)


func _draw_contact(scale_factor: Vector2) -> void:
	var is_parry := _contact_kind == "parry"
	var lifetime := 0.075 if is_parry else 0.038
	if _contact_age >= lifetime:
		return
	var strength: float = pow(1.0 - _contact_age / lifetime, 1.5)
	var point := _contact_point / scale_factor
	# A hit that happened outside the view should not flash the opposite edge.
	if not Rect2(0, 0, 1280, 720).has_point(point):
		return
	var direction := _contact_direction
	var across := Vector2(-direction.y, direction.x)
	var accent := AMBER if is_parry else WHITE
	# A brief blade-aligned glint marks the actual contact. The physical sparks,
	# deflection and recoil belong to the 3D scene, not a screen-space explosion.
	for side in [-1.0, 1.0]:
		var near: Vector2 = point + direction * side * 3.0
		var far: Vector2 = point + direction * side * (14.0 if is_parry else 10.0)
		draw_line(near, far, Color(accent, strength * 0.8), 1.3, true)
	if is_parry:
		var travel := _contact_age / lifetime
		for side in [-1.0, 1.0]:
			var ray: Vector2 = (across * side - direction * 0.45).normalized()
			var near := point + ray * (4.0 + travel * 16.0)
			draw_line(near, near + ray * 5.0, Color(AMBER, strength * 0.9), 1.2, true)


func _draw_telemetry() -> void:
	_panel(Rect2(28, 25, 236, 95), 0.8)
	_text(Vector2(43, 48), "SHIFT / CUT", 21, WHITE)
	_text(Vector2(43, 67), "FIRST PERSON / VOXEL PROTOTYPE", 10, MUTED)
	var health := clampi(int(_snapshot.get("health", 5)), 0, 5)
	for index in range(5):
		var rectangle := Rect2(44 + index * 39, 83, 30, 12)
		draw_rect(rectangle, Color(0.17, 0.24, 0.27))
		if index < health:
			draw_rect(rectangle, CYAN if health > 2 else RED)
		else:
			draw_line(rectangle.position, rectangle.end, Color(0.35, 0.4, 0.42), 1.0)
	var duration := maxf(float(_snapshot.get("duration", 180.0)), 1.0)
	var elapsed := float(_snapshot.get("time", 0.0))
	var progress := clampf(elapsed / duration, 0.0, 1.0)
	_text_center(Vector2(640, 40), "CUTTING LAB / FREE SLICING" if bool(_snapshot.get("training", false)) else ("CORE APPROACH" if bool(_snapshot.get("boss", false)) else str(_snapshot.get("section_name","ASSEMBLY LINE / 01"))), 13, MUTED)
	draw_rect(Rect2(480, 53, 320, 3), Color(0.19, 0.27, 0.29))
	draw_rect(Rect2(480, 53, 320 * progress, 3), AMBER if bool(_snapshot.get("boss", false)) else CYAN)
	_text_center(Vector2(640, 74), "%02d:%02d / %02d:%02d" % [int(elapsed) / 60, int(elapsed) % 60, int(duration) / 60, int(duration) % 60], 11, MUTED)
	_panel(Rect2(1062, 25, 190, 95), 0.8)
	_text_right(Vector2(1236, 49), "SCORE", 11, MUTED)
	_text_right(Vector2(1236, 82), "%06d" % int(_snapshot.get("score", 0)), 27, WHITE)
	_text_right(Vector2(1236, 103), "%02d TARGETS SEVERED" % int(_snapshot.get("kills", 0)), 10, CYAN)
	if bool(_snapshot.get("training", false)):
		draw_rect(Rect2(28, 129, 270, 26), Color(INK, 0.88))
		_text(Vector2(42, 148), "切割实验场 · 无限切割 · F4 重置靶", 13, CYAN)
	elif bool(_snapshot.get("practice", false)):
		draw_rect(Rect2(28, 129, 236, 26), Color(INK, 0.88))
		_text(Vector2(42, 148), "练习模式 · 生命不低于 1 格", 13, AMBER)


func _draw_speed_bar() -> void:
	_draw_compact_speed_bar()
	if not bool(_snapshot.get("touch_mode", false)):
		_text(Vector2(28, 709), "LMB 普攻 / 长按切割   RMB 振刀   SHIFT 提速   F2 练习   F3 BOSS   F4 实验场   F5 调试提示", 10, MUTED)
		_text_right(Vector2(1250, 709), "ESC 暂停", 11, MUTED)


func _draw_compact_speed_bar() -> void:
	var speed := float(_snapshot.get("speed", 18.0))
	var gear := clampi(int(_snapshot.get("gear", 1)), 1, 4)
	var limits: PackedFloat32Array = _snapshot.get("gear_limits", PackedFloat32Array([4, 24, 36, 48, 60]))
	var accent: Color = GEAR_COLORS[gear - 1]
	_panel(Rect2(408, 92, 465, 68), 0.8)
	var bar_alpha: float = lerpf(1.0, 0.20, _hilt_clearance(Rect2(408, 92, 465, 68)))
	_text(Vector2(421, 117), "%02d m/s" % int(speed), 22, WHITE)
	_text_right(Vector2(858, 117), "斩击耗速" if bool(_snapshot.get("slow", false)) else ("按住提速" if bool(_snapshot.get("touch_mode", false)) else "SHIFT 提速"), 13, accent)
	var bar := Rect2(527, 135, 330, 10)
	for index in range(4):
		var x: float = bar.position.x + (float(limits[index]) - 4.0) / 56.0 * bar.size.x
		var width: float = (float(limits[index + 1]) - float(limits[index])) / 56.0 * bar.size.x - 3.0
		var fill: float = clampf((speed - float(limits[index])) / (float(limits[index + 1]) - float(limits[index])), 0.0, 1.0)
		draw_rect(Rect2(x, bar.position.y, width, bar.size.y), Color(GEAR_COLORS[index], 0.16 * bar_alpha))
		draw_rect(Rect2(x, bar.position.y, width * fill, bar.size.y), Color(GEAR_COLORS[index], 0.95 * bar_alpha))
		_text(Vector2(x, 130), ["I", "II", "III", "IV"][index] + "  " + str(int(limits[index])), 10, GEAR_COLORS[index])
	_text_right(Vector2(858, 130), str(int(limits[4])), 10, MUTED)
	_text(Vector2(422, 145), "档位 " + ["I", "II", "III", "IV"][gear - 1], 15, accent)
	var marker: float = bar.position.x + clampf((speed - 4.0) / 56.0, 0.0, 1.0) * bar.size.x
	draw_line(Vector2(marker, 132), Vector2(marker, 148), Color(WHITE, maxf(0.4, bar_alpha)), 2.0)


func _draw_aim(scale_factor: Vector2) -> void:
	var center := Vector2(640, 360)
	var slow := bool(_snapshot.get("slow", false))
	if slow:
		center = Vector2(_snapshot.get("cursor", size * 0.5)) / scale_factor
		# The cursor is the grip, while the bright trails belong to the cutting edge.
		draw_arc(center, 5.5, 0.12, PI - 0.12, 12, Color(WHITE, 0.85), 1.3, true)
		draw_arc(center, 5.5, PI + 0.12, TAU - 0.12, 12, Color(CYAN, 0.85), 1.3, true)
		draw_line(center - Vector2(11, 0), center - Vector2(8, 0), Color(CYAN, 0.8), 1.0, true)
		draw_line(center + Vector2(8, 0), center + Vector2(11, 0), Color(CYAN, 0.8), 1.0, true)
		if bool(_snapshot.get("show_timing", false)):
			_text_center(Vector2(640, 131), "SLASH / 自由刀路 · 视角保持", 13, CYAN)
	else:
		for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(center + direction * 5.0, center + direction * 12.0, Color(WHITE, 0.7), 1.0, true)
		draw_circle(center, 1.5, CYAN)
	for trail in _trails:
		var blade_alpha := pow(clampf(1.0 - float(trail.age) / 0.075, 0.0, 1.0), 1.5)
		var blade_path: PackedVector2Array = trail.path
		var render_path := PackedVector2Array()
		for point in blade_path:
			render_path.append(point / scale_factor)
		draw_polyline(render_path, Color(0.76, 0.95, 0.95, blade_alpha * 0.62), 1.1, true)
	var parry := clampf(float(_snapshot.get("parry", 0.0)), 0.0, 1.0)
	if parry > 0.0 and bool(_snapshot.get("show_timing", false)):
		draw_arc(Vector2(640, 360), 37.0, -PI * 0.9, -PI * 0.1, 32, Color(AMBER, parry * 0.55), 1.0, true)


func _draw_targets(scale_factor: Vector2) -> void:
	var targets: Array = _snapshot.get("targets", [])
	for target in targets:
		var screen := Vector2(target.get("screen", Vector2(-1000, -1000))) / scale_factor
		if screen.x < 25.0 or screen.x > 1255.0 or screen.y < 110.0 or screen.y > 580.0:
			continue
		var kind := str(target.get("kind", "normal"))
		var progress := clampf(float(target.get("progress", 0.0)), 0.0, 1.0)
		var can_cut := bool(target.get("can_cut", false))
		var time_left := float(target.get("time_left", 99.0))
		if not bool(_snapshot.get("show_timing", false)):
			# Reading the weapon animation comes first. Only a small last-moment icon remains.
			if bool(_snapshot.get("training", false)):
				for direction in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
					var corner: Vector2 = screen + direction * 12.0
					draw_line(corner, corner - Vector2(direction.x * 4.0, 0.0), Color(CYAN, 0.35), 1.0, true)
			elif progress > 0.80 and time_left >= 0.0:
				var accent := AMBER if progress < 0.95 else RED
				var tip := screen - Vector2(0, 33)
				draw_line(tip + Vector2(-6, -7), tip, Color(accent, 0.86), 2.0, true)
				draw_line(tip + Vector2(6, -7), tip, Color(accent, 0.86), 2.0, true)
			continue
		var accent := CYAN if can_cut else MUTED
		if progress >= 0.84:
			accent = RED if int(_animation_time * 12.0) % 2 == 0 else AMBER
		var radius := 29.0 if kind != "boss" else 38.0
		draw_arc(screen, radius, -PI * 0.5, PI * 1.5, 40, Color(INK, 0.65), 4.0, true)
		draw_arc(screen, radius, -PI * 0.5, -PI * 0.5 + TAU * maxf(progress, 0.005), 40, Color(accent, 0.85), 2.5, true)
		for direction in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var corner: Vector2 = screen + direction * 18.0
			draw_line(corner, corner - Vector2(direction.x * 5.0, 0.0), Color(accent, 0.7), 1.0, true)
			draw_line(corner, corner - Vector2(0.0, direction.y * 5.0), Color(accent, 0.7), 1.0, true)
		var label := str(target.get("label", ""))
		if label.is_empty():
			label = {"normal": "近战", "tank": "重装", "ranged": "射手", "boss": "守卫", "bolt": "弹体", "shock": "冲击", "debris": "残骸"}.get(kind, "目标")
		_text_center(screen - Vector2(0, radius + 9), label + (" · 可斩" if can_cut else " · 接近中"), 12, accent)
		if time_left >= 0.0 and time_left < 5.0:
			var counter := "振刀 %.1fs" % time_left if time_left < 0.65 else "%.1fs" % time_left
			_text_center(screen + Vector2(0, radius + 16), counter, 12, accent)


func _draw_combat_messages() -> void:
	var message := str(_snapshot.get("message", ""))
	var guided := bool(_snapshot.get("training", false)) or bool(_snapshot.get("show_timing", false)) or float(_snapshot.get("time", 0.0)) < 3.0
	if guided and not message.is_empty():
		var width := minf(_font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 30.0, 800.0)
		_panel(Rect2(640 - width * 0.5, 163, width, 31), 0.8)
		_text_center(Vector2(640, 184), message, 16, WHITE)
	var combo := int(_snapshot.get("combo", 0))
	if combo > 1:
		_text(Vector2(32, 176), "%02d" % combo, 38, CYAN)
		_text(Vector2(35, 195), "CHAIN / 连斩", 11, MUTED)


func _draw_menu() -> void:
	draw_rect(Rect2(Vector2.ZERO, REFERENCE_SIZE), Color(INK, 0.73))
	_text(Vector2(110, 191), "GAME OFF 2026  //  PLAYABLE PROTOTYPE", 13, CYAN)
	_text(Vector2(103, 285), "SHIFT", 94, WHITE)
	_text(Vector2(110, 342), "/ CUT", 49, CYAN)
	_text(Vector2(113, 390), "以速度换锋芒。用刀路切断核心。", 22, WHITE)
	_text(Vector2(113, 423), "自动前进 · 无法换道 · 漏掉任何敌人都会受伤", 15, MUTED)
	_panel(Rect2(772, 189, 397, 286), 0.92)
	_text(Vector2(797, 222), "COMBAT INTERFACE", 12, CYAN)
	var mobile := bool(_snapshot.get("touch_mode", false))
	if mobile:
		_draw_control_row(261, "右侧空白", "拖动转头")
		_draw_control_row(301, "按住斩击", "拖动操刀 · 松手收刀")
		_draw_control_row(341, "普攻按钮", "立即拔刀挥砍")
		_draw_control_row(381, "振刀按钮", "精准抵挡可提升速度")
		_draw_control_row(421, "按住提速", "与操刀可同时按住")
	else:
		_draw_control_row(261, "鼠标移动", "有限转头 / 长斩锁定当前朝向")
		_draw_control_row(301, "左键短按", "按下出刀 · 无须等待松开")
		_draw_control_row(341, "左键长按", "慢动作切割 · 持续消耗速度")
		_draw_control_row(381, "右键短按", "振刀 · 精准抵挡可提升速度")
		_draw_control_row(421, "按住 Shift", "持续提速 · 四档风险与收益")
	_text(Vector2(797, 454), "观察举刃、蓄力和枪口；挥击瞬间振刀。", 12, AMBER)
	var pulse := 0.7 + sin(_animation_time * 3.0) * 0.16
	draw_rect(Rect2(110, 480, 305, 53), Color(CYAN, pulse * 0.12))
	draw_rect(Rect2(110, 480, 305, 53), Color(CYAN, pulse), false, 1.0)
	_text(Vector2(131, 514), "点击屏幕开始" if mobile else "ENTER / 点击开始", 21, WHITE)
	_text(Vector2(113, 560), "五格生命  /  三分钟路线  /  核心守卫战", 12, MUTED)
	if mobile:
		_text(Vector2(113, 588), "横屏操作 · 左手攻防提速 · 右手按住斩击拖动", 15, CYAN)
		_text(Vector2(113, 614), "点击暂停或系统返回键可暂停，切到后台自动暂停", 13, MUTED)
	else:
		_text(Vector2(113, 582), "F2 开始 / 切换练习模式，生命至少保留一格", 12, AMBER)
		_text(Vector2(113, 603), "进入游戏后按 F3 直达 Boss，验证切割与防御", 12, MUTED)
		_text(Vector2(113, 624), "F4 切割实验场 · 静止靶 / 无限速度 / 反复碎切", 12, CYAN)


func _draw_control_row(y: float, key: String, description: String) -> void:
	_text(Vector2(797, y), key, 15, WHITE)
	_text(Vector2(902, y), description, 13, MUTED)


func _draw_overlay(title: String, subtitle: String, hint: String, accent: Color) -> void:
	draw_rect(Rect2(Vector2.ZERO, REFERENCE_SIZE), Color(INK, 0.83))
	draw_line(Vector2(420, 230), Vector2(860, 230), accent, 2.0)
	_text_center(Vector2(640, 273), subtitle, 15, accent)
	_text_center(Vector2(640, 344), title, 54, WHITE)
	_text_center(Vector2(640, 392), "%06d 分  /  切断 %d 个目标" % [int(_snapshot.get("score", 0)), int(_snapshot.get("kills", 0))], 19, MUTED)
	_text_center(Vector2(640, 458), ("点击屏幕继续" if str(_snapshot.get("state", "")) == "paused" else "点击屏幕重新挑战") if bool(_snapshot.get("touch_mode", false)) else hint, 21, accent)
	_text_center(Vector2(640, 497), "短斩不加速 · 精准振刀加速 · 长斩消耗速度", 13, MUTED)
	_text_center(Vector2(640, 527), "左侧提速与攻防 · 右侧按住斩击后拖动" if bool(_snapshot.get("touch_mode", false)) else "F2 练习  /  F3 直达 Boss  /  F4 切割实验场", 13, AMBER)
	if bool(_snapshot.get("practice", false)):
		_text_center(Vector2(640, 556), "当前为练习模式 · 生命至少保留一格", 13, AMBER)


func _panel(rectangle: Rect2, alpha: float) -> void:
	# UI backing yields to the physical handle; speed and gear glyphs stay
	# readable without restricting free hand travel through the upper screen.
	draw_rect(rectangle, Color(INK, alpha * lerpf(1.0, 0.08, _hilt_clearance(rectangle))))
	draw_line(rectangle.position, rectangle.position + Vector2(28, 0), CYAN, 1.5)
	draw_line(rectangle.end - Vector2(28, 0), rectangle.end, Color(MUTED, 0.6), 1.0)


func _hilt_clearance(rectangle: Rect2) -> float:
	if not bool(_snapshot.get("slow", false)) or size.x < 1.0 or size.y < 1.0:
		return 0.0
	var grip: Vector2 = Vector2(_snapshot.get("cursor", size * 0.5)) * REFERENCE_SIZE / size
	var nearest: Vector2 = grip.clamp(rectangle.position, rectangle.end)
	return 1.0 - smoothstep(0.0, 48.0, grip.distance_to(nearest))


func _text(at: Vector2, value: String, font_size: int, color: Color) -> void:
	draw_string(_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _text_center(at: Vector2, value: String, font_size: int, color: Color) -> void:
	var width := _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	_text(at - Vector2(width * 0.5, 0), value, font_size, color)


func _text_right(at: Vector2, value: String, font_size: int, color: Color) -> void:
	var width := _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	_text(at - Vector2(width, 0), value, font_size, color)
