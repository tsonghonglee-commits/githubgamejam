class_name PrototypeHUD
extends Control

signal ui_action(action: StringName, value: Variant)
signal ui_feedback(kind: StringName)

const REFERENCE_SIZE := Vector2(1280.0, 720.0)
const INK := Color(0.025, 0.038, 0.052)
const WHITE := Color(0.9, 0.95, 0.96)
const MUTED := Color(0.49, 0.62, 0.66)
const CYAN := Color(0.32, 0.96, 0.86)
const AMBER := Color(1.0, 0.51, 0.24)
const RED := Color(1.0, 0.24, 0.25)
const PAPER := Color("ede9df")
const ASH := Color("89918f")
const VERMILION := Color("e6523e")
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
var _ui_page := "home"
var _ui_focus := 0
var _ui_pointer := Vector2(640,360)
var _ui_pressed := false
var _ui_consumed := false
var _ui_must_release := false
var _ui_press_button := -1
var _ui_previous := Vector2.ZERO
var _ui_distance := 0.0
var _ui_slider_drag := false
var _ui_volume_preview := 1.0
var _ui_pending: Dictionary = {}
var _ui_split: Dictionary = {}
var _ui_trail: Array[Dictionary] = []
var _ui_action_count := 0
var _ui_last_action := ""
var _ui_last_activation_kind := ""


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
	for index in range(_ui_trail.size()-1,-1,-1):
		_ui_trail[index].age += real_delta
		if float(_ui_trail[index].age) > 0.16: _ui_trail.remove_at(index)
	if not _ui_split.is_empty():
		_ui_split.age += real_delta
		if float(_ui_split.age) > 0.24: _ui_split.clear()
	if not _ui_pending.is_empty():
		_ui_pending.age += real_delta
		if float(_ui_pending.age) >= 0.14:
			var request: Dictionary = _ui_pending.duplicate()
			_ui_pending.clear()
			_dispatch_ui_action(StringName(request.action),request.get("value"))
	queue_redraw()


func set_snapshot(data: Dictionary) -> void:
	if str(data.get("state","menu")) != str(_snapshot.get("state","menu")):
		_ui_page = "home"
		_ui_focus = 0
		cancel_menu_gesture()
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
	if state == "playing":
		_draw_telemetry()
		_draw_speed_bar()
		_draw_targets(scale_factor)
		_draw_aim(scale_factor)
		_draw_contact(scale_factor)
		_draw_combat_messages()
	else:
		_draw_menu()
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
	var health := clampi(int(_snapshot.get("health",5)),0,5)
	for index in range(5):
		var bar := Rect2(36+float(index)*28,34,20,6)
		draw_rect(bar,Color(PAPER,0.13))
		if index < health: draw_rect(bar,VERMILION if health <= 2 else PAPER)
	_text(Vector2(36,59),"生命",10,ASH)
	if bool(_snapshot.get("training",false)):
		_text(Vector2(36,81),"切割实验场",12,CYAN)
	elif bool(_snapshot.get("practice",false)):
		_text(Vector2(36,81),"练习模式",12,AMBER)
	_text_right(Vector2(1244,46),"%06d"%int(_snapshot.get("score",0)),24,PAPER)
	_text_right(Vector2(1244,65),"%02d 斩断"%int(_snapshot.get("kills",0)),11,ASH)
	var elapsed := float(_snapshot.get("time",0.0))
	var duration := maxf(1.0,float(_snapshot.get("duration",180.0)))
	var chapter := clampi(int(_snapshot.get("route_section",0)),0,3)
	var label: String = ["装配区","炉区","高架桥","核心长廊"][chapter]
	if bool(_snapshot.get("boss",false)): label = "核心守卫"
	if bool(_snapshot.get("training",false)): label = "自由切割"
	_text_center(Vector2(640,31),label,12,ASH)
	draw_rect(Rect2(540,42,200,2),Color(PAPER,0.13))
	draw_rect(Rect2(540,42,200*clampf(elapsed/duration,0,1),2),VERMILION)
	_text_center(Vector2(640,63),"%02d:%02d"%[int(elapsed)/60,int(elapsed)%60],11,ASH)


func _draw_speed_bar() -> void:
	_draw_compact_speed_bar()
	_text_right(Vector2(1244,687),"Esc  暂停",10,ASH)


func _draw_compact_speed_bar() -> void:
	var speed := float(_snapshot.get("speed",18.0))
	var gear := clampi(int(_snapshot.get("gear",1)),1,4)
	var limits: PackedFloat32Array = _snapshot.get("gear_limits",PackedFloat32Array([4,24,36,48,60]))
	if limits.size() < 5: limits = PackedFloat32Array([4,24,36,48,60])
	var rectangle := Rect2(372,628,536,74)
	var alpha := lerpf(1.0,0.22,_hilt_clearance(rectangle))
	draw_rect(rectangle,Color(INK,0.72*alpha))
	_text(Vector2(391,657),"%02d"%roundi(speed),27,Color(PAPER,alpha))
	_text(Vector2(432,657),"m/s",11,Color(ASH,alpha))
	_text_right(Vector2(888,655),["I","II","III","IV"][gear-1],20,Color(GEAR_COLORS[gear-1],alpha))
	_text_center(Vector2(640,654),"斩切中 · 消耗速度" if bool(_snapshot.get("slow",false)) else "Shift  持续提速",11,Color(ASH,alpha))
	var bar := Rect2(392,671,496,6)
	var span := maxf(limits[4]-limits[0],1.0)
	for index in range(4):
		var x := bar.position.x+(limits[index]-limits[0])/span*bar.size.x
		var width := (limits[index+1]-limits[index])/span*bar.size.x-3.0
		var fill := clampf((speed-limits[index])/maxf(limits[index+1]-limits[index],0.01),0,1)
		draw_rect(Rect2(x,bar.position.y,width,bar.size.y),Color(GEAR_COLORS[index],0.18*alpha))
		draw_rect(Rect2(x,bar.position.y,width*fill,bar.size.y),Color(GEAR_COLORS[index],0.92*alpha))
		_text(Vector2(x,693),"%s  %d–%d"%[["I","II","III","IV"][index],int(limits[index]),int(limits[index+1])],10,Color(GEAR_COLORS[index],alpha))
	var marker := bar.position.x+clampf((speed-limits[0])/span,0,1)*bar.size.x
	draw_line(Vector2(marker,668),Vector2(marker,681),Color(PAPER,alpha),1.5)


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
	var state := str(_snapshot.get("state","menu"))
	var home := _ui_page == "home"
	# The right half keeps the real combat portrait and highway visible.
	draw_rect(Rect2(Vector2.ZERO,REFERENCE_SIZE),Color(INK,0.64 if state == "menu" and home else 0.89))
	for index in range(18):
		draw_rect(Rect2(float(index)*40,0,40,720),Color(INK,0.34*(1.0-float(index)/18.0)))
	draw_line(Vector2(96,84),Vector2(132,84),VERMILION,3.0)
	_text(Vector2(144,89),"SLAY THE HIGHWAY",13,ASH)
	if not home:
		var title := "设置" if _ui_page == "settings" else ("怎么杀出这条路" if _ui_page == "controls" else "结束这趟路？")
		_text(Vector2(92,201),title,48,PAPER)
		if _ui_page == "settings": _draw_settings_page()
		elif _ui_page == "controls": _draw_controls_page()
		else:
			_text(Vector2(96,270),"确认后将关闭游戏。",20,ASH)
			_text(Vector2(96,305),"斩过「确认离开」，或按 Esc 返回。",14,ASH)
	elif state == "menu":
		_text(Vector2(88,247),"杀路",112,PAPER)
		_text(Vector2(96,291),"SLAY THE HIGHWAY",23,PAPER)
		_text(Vector2(96,330),"向前。出刀。",20,ASH)
		if not bool(_snapshot.get("menu_ready",true)):
			_text(Vector2(96,356),"场景准备中",12,VERMILION)
	else:
		var title := "暂停" if state == "paused" else ("断路" if state == "dead" else "突破完成")
		var subtitle := "PAUSED" if state == "paused" else ("RUN ENDED" if state == "dead" else "HIGHWAY CLEARED")
		_text(Vector2(92,216),title,72,PAPER)
		_text(Vector2(96,253),subtitle,17,VERMILION)
		if state == "paused":
			_text(Vector2(96,316),"这条路，等你继续。",21,ASH)
		_draw_result_stats()
	_draw_ui_buttons()
	_draw_menu_split()
	_draw_menu_trail()
	_text(Vector2(96,683),"按住左键划过选项  /  点击  /  Enter 确认",12,ASH)
	_text_right(Vector2(1184,683),"Esc  返回" if not home else ("Esc  继续" if state == "paused" else "杀路"),12,ASH)


func _draw_result_stats() -> void:
	var state := str(_snapshot.get("state","menu"))
	var y := 391.0 if state == "paused" else 339.0
	_text(Vector2(96,y-27),"本次行程",12,ASH)
	_text(Vector2(92,y+24),"%06d"%int(_snapshot.get("score",0)),49,PAPER)
	_text(Vector2(96,y+50),"得分",12,ASH)
	_text(Vector2(96,y+104),"%02d"%int(_snapshot.get("kills",0)),30,PAPER)
	_text(Vector2(160,y+103),"目标斩断",14,ASH)
	var time := float(_snapshot.get("time",0))
	_text(Vector2(96,y+151),"%02d:%02d"%[int(time)/60,int(time)%60],30,PAPER)
	_text(Vector2(215,y+150),"行程时间",14,ASH)


func _draw_controls_page() -> void:
	var rows := [["鼠标移动","有限转头；长斩时控制刀路"],["左键短按","十二式轻击，连按衔接"],["左键保持 / 拖动","慢动作自由斩切，持续消耗速度"],["右键","振刀；精准抵挡提速，弹药原路反射"],["Shift","持续提速，四档伤害与风险"]]
	for index in range(rows.size()):
		var y := 278.0+float(index)*51.0
		_text(Vector2(96,y),str(rows[index][0]),17,PAPER)
		_text(Vector2(330,y),str(rows[index][1]),16,ASH)
	_text(Vector2(96,553),"自动前进 · 无法换道 · 任意跑道漏敌都会受伤",16,VERMILION)
	_text(Vector2(96,582),"斩断关键连接；残骸仍可再切。五格生命耗尽时行程结束。",15,ASH)


func _setting(key: String, fallback: Variant) -> Variant:
	var settings: Dictionary = _snapshot.get("ui_settings",{})
	return settings.get(key,fallback)


func _draw_settings_page() -> void:
	var volume := _ui_volume_preview if _ui_slider_drag else clampf(float(_setting("volume",1.0)),0,1)
	_text(Vector2(96,280),"主音量",18,PAPER)
	_text_right(Vector2(672,280),"%d%%"%roundi(volume*100.0),18,ASH)
	var track := Rect2(96,309,576,4)
	draw_rect(track,Color(PAPER,0.17))
	draw_rect(Rect2(track.position,Vector2(track.size.x*volume,track.size.y)),VERMILION)
	draw_rect(Rect2(92+track.size.x*volume,303,8,16),PAPER)
	if _ui_focus == 0: draw_line(Vector2(96,329),Vector2(672,329),Color(VERMILION,0.45),1.0)


func _ui_button(action: StringName, label: String, subtitle: String, rect: Rect2, value: Variant = null, kind: String = "button") -> Dictionary:
	return {"id":str(action),"action":str(action),"label":label,"subtitle":subtitle,"rect":rect,"value":value,"kind":kind,"enabled":true}


func _ui_buttons() -> Array[Dictionary]:
	var buttons: Array[Dictionary] = []
	var state := str(_snapshot.get("state","menu"))
	if state == "playing": return buttons
	if _ui_page == "controls":
		buttons.append(_ui_button(&"back","返回","BACK",Rect2(940,598,244,48)))
	elif _ui_page == "settings":
		buttons.append(_ui_button(&"volume","主音量","",Rect2(88,291,592,40),float(_setting("volume",1.0)),"slider"))
		for index in range(3):
			var action: StringName = [&"fullscreen",&"vsync",&"msaa"][index]
			var enabled := bool(_setting(str(action),true))
			var label: String = ["全屏","垂直同步","4× 抗锯齿"][index]
			buttons.append(_ui_button(action,label,"开启 ON" if enabled else "关闭 OFF",Rect2(96,365+float(index)*70.0,576,50),not enabled))
		buttons.append(_ui_button(&"back","返回","BACK",Rect2(940,598,244,48)))
	elif _ui_page == "quit_confirm":
		buttons.append(_ui_button(&"quit","确认离开","QUIT GAME",Rect2(96,386,380,54)))
		buttons.append(_ui_button(&"back","留在这里","BACK",Rect2(96,458,380,54)))
	elif state == "menu":
		buttons.append(_ui_button(&"start","斩入公路","START",Rect2(96,386,380,54)))
		buttons.append(_ui_button(&"settings","设置","OPTIONS",Rect2(96,448,380,48)))
		buttons.append(_ui_button(&"controls","操作","CONTROLS",Rect2(96,506,380,48)))
		buttons.append(_ui_button(&"quit_confirm","离开","QUIT",Rect2(96,564,380,48)))
	else:
		var actions: Array = [&"resume",&"restart",&"settings",&"controls",&"menu"] if state == "paused" else [&"restart",&"settings",&"controls",&"menu"]
		var labels := {"resume":["继续杀路","RESUME"],"restart":["重新开始","RESTART"],"settings":["设置","OPTIONS"],"controls":["操作","CONTROLS"],"menu":["返回标题","TITLE"]}
		for index in range(actions.size()):
			var action: StringName = actions[index]
			buttons.append(_ui_button(action,str(labels[str(action)][0]),str(labels[str(action)][1]),Rect2(850,286+float(index)*63,334,50)))
	return buttons


func _draw_ui_buttons() -> void:
	var buttons := _ui_buttons()
	for index in range(buttons.size()):
		var button: Dictionary = buttons[index]
		if str(button.kind) == "slider": continue
		var rect: Rect2 = button.rect
		if not _ui_split.is_empty() and _ui_split.rect == rect and float(_ui_split.age)<0.24: continue
		var selected := index == _ui_focus
		var accent: Color = VERMILION if selected else ASH
		draw_rect(rect,Color(PAPER,0.055 if selected else 0.018))
		draw_line(rect.position+Vector2(0,rect.size.y),rect.end,Color(accent,0.6 if selected else 0.26),1.0)
		if selected: draw_line(rect.position,rect.position+Vector2(0,rect.size.y),VERMILION,3.0)
		_text(rect.position+Vector2(17,rect.size.y*0.5+7),str(button.label),21,PAPER)
		_text_right(rect.position+Vector2(rect.size.x-16,rect.size.y*0.5+4),str(button.subtitle),11,accent)


func _half_polygon(points: PackedVector2Array, origin: Vector2, normal: Vector2, sign_value: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in range(points.size()):
		var a := points[index]
		var b := points[(index+1)%points.size()]
		var da := (a-origin).dot(normal)*sign_value
		var db := (b-origin).dot(normal)*sign_value
		if da>=0.0: result.append(a)
		if (da>=0.0) != (db>=0.0): result.append(a.lerp(b,da/(da-db)))
	return result


func _draw_menu_split() -> void:
	if _ui_split.is_empty(): return
	var rect: Rect2 = _ui_split.rect
	var age := float(_ui_split.age)
	var progress := clampf(age/0.24,0,1)
	var normal: Vector2 = _ui_split.normal
	var origin: Vector2 = _ui_split.origin
	var corners := PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
	for side: float in [-1.0,1.0]:
		var polygon := _half_polygon(corners,origin,normal,side)
		if polygon.size()<3: continue
		var offset := normal*side*(3.0+progress*18.0)+Vector2(progress*3.0,progress*progress*8.0)
		for index in range(polygon.size()): polygon[index]+=offset
		draw_colored_polygon(polygon,Color(PAPER,(1.0-progress)*0.14))
		var outline := polygon.duplicate()
		outline.append(polygon[0])
		draw_polyline(outline,Color(PAPER,(1.0-progress)*0.6),1.0,true)
	var text_offset := normal*(1.0 if (rect.get_center()-origin).dot(normal)>=0 else -1.0)*progress*18.0
	_text(rect.position+Vector2(17,rect.size.y*0.5+7)+text_offset,str(_ui_split.label),21,Color(PAPER,1.0-progress))
	var direction := Vector2(-normal.y,normal.x)
	var half := maxf(rect.size.x,rect.size.y)*0.65
	draw_line(origin-direction*half,origin+direction*half,Color(PAPER,maxf(0,1.0-age/0.12)),2.2,true)


func _draw_menu_trail() -> void:
	for index in range(1,_ui_trail.size()):
		var entry: Dictionary = _ui_trail[index]
		var alpha := clampf(1.0-float(entry.age)/0.16,0,1)
		draw_line(_ui_trail[index-1].point,entry.point,Color(PAPER,alpha*0.85),1.6+alpha*1.5,true)


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


func cancel_menu_gesture() -> void:
	_ui_pressed = false
	_ui_consumed = false
	_ui_must_release = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_ui_press_button = -1
	_ui_slider_drag = false
	_ui_distance = 0.0
	_ui_pending.clear()
	_ui_split.clear()
	_ui_trail.clear()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:
		cancel_menu_gesture()


func _ui_point(event: InputEventMouse) -> Vector2:
	var local := get_global_transform_with_canvas().affine_inverse()*event.position
	return local*REFERENCE_SIZE/size.max(Vector2.ONE)


func _button_at(point: Vector2, buttons: Array[Dictionary]) -> int:
	for index in range(buttons.size()):
		if bool(buttons[index].enabled) and Rect2(buttons[index].rect).has_point(point): return index
	return -1


func _segment_rect_entry(from: Vector2, to: Vector2, rect: Rect2) -> float:
	var entry := 0.0
	var exit := 1.0
	var direction := to-from
	for axis in range(2):
		if absf(direction[axis])<0.000001:
			if from[axis]<rect.position[axis] or from[axis]>rect.end[axis]: return INF
			continue
		var near: float = (rect.position[axis]-from[axis])/direction[axis]
		var far: float = (rect.end[axis]-from[axis])/direction[axis]
		entry = maxf(entry,minf(near,far))
		exit = minf(exit,maxf(near,far))
		if entry>exit: return INF
	return entry


func _set_menu_volume(point: Vector2) -> void:
	_ui_volume_preview = clampf((point.x-96.0)/576.0,0,1)
	ui_action.emit(&"volume",_ui_volume_preview)


func handle_menu_input(event: InputEvent) -> bool:
	if str(_snapshot.get("state","menu")) == "playing": return false
	var buttons := _ui_buttons()
	if event is InputEventKey:
		if not event.pressed or event.echo: return false
		if event.keycode == KEY_ESCAPE:
			cancel_menu_gesture()
			if _ui_page != "home": _open_ui_page("home")
			elif str(_snapshot.get("state","menu")) == "paused": ui_action.emit(&"resume",null)
			elif str(_snapshot.get("state","menu")) in ["dead","won"]: ui_action.emit(&"menu",null)
			ui_feedback.emit(&"back")
			return true
		if event.keycode in [KEY_TAB,KEY_UP,KEY_DOWN]:
			var step := -1 if event.keycode == KEY_UP or (event.keycode == KEY_TAB and event.shift_pressed) else 1
			_ui_focus = posmod(_ui_focus+step,maxi(buttons.size(),1))
			return true
		if event.keycode in [KEY_LEFT,KEY_RIGHT] and not buttons.is_empty() and str(buttons[clampi(_ui_focus,0,buttons.size()-1)].kind) == "slider":
			var value := clampf(float(_setting("volume",1.0))+(0.05 if event.keycode == KEY_RIGHT else -0.05),0,1)
			ui_action.emit(&"volume",value)
			return true
		if event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE]:
			if _ui_pending.is_empty() and not buttons.is_empty():
				var button: Dictionary = buttons[clampi(_ui_focus,0,buttons.size()-1)]
				if str(button.kind) != "slider": _queue_ui_action(button,"key",Rect2(button.rect).get_center(),Vector2(1,-0.3))
			return true
		return false
	if not event is InputEventMouse: return false
	var point := _ui_point(event)
	_ui_pointer = point
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			# Release may carry the last coalesced pointer segment. Consume it
			# before deciding whether this was a click and clearing the gesture.
			if not _ui_must_release and _ui_pressed and not _ui_consumed and not _ui_slider_drag:
				_advance_menu_stroke(point,buttons)
			if _ui_must_release:
				_ui_must_release = false
			elif _ui_slider_drag:
				_set_menu_volume(point)
			elif _ui_pressed and not _ui_consumed and _ui_distance < 24.0 and _ui_press_button >= 0 and _ui_press_button < buttons.size():
				var button: Dictionary = buttons[_ui_press_button]
				if Rect2(button.rect).has_point(point): _queue_ui_action(button,"click",Rect2(button.rect).get_center(),Vector2(1,-0.3))
			_ui_pressed = false
			_ui_slider_drag = false
			_ui_press_button = -1
			_ui_consumed = false
			return true
		if _ui_must_release: return true
		if _ui_pressed: return true
		if not _ui_pending.is_empty():
			_ui_must_release = true
			return true
		_ui_pressed = true
		_ui_consumed = false
		_ui_distance = 0.0
		_ui_previous = point
		_ui_press_button = _button_at(point,buttons)
		_ui_trail.clear()
		_ui_trail.append({"point":point,"age":0.0})
		if _ui_press_button >= 0:
			_ui_focus = _ui_press_button
			if str(buttons[_ui_press_button].kind) == "slider":
				_ui_slider_drag = true
				_ui_consumed = true
				ui_feedback.emit(&"click")
				_set_menu_volume(point)
		return true
	if event is InputEventMouseMotion:
		if _ui_must_release: return true
		if _ui_slider_drag:
			_set_menu_volume(point)
			return true
		if _ui_pressed:
			_advance_menu_stroke(point,buttons)
		else:
			var hover := _button_at(point,buttons)
			if hover >= 0: _ui_focus = hover
		return true
	# Menu mouse events are never allowed to fall through into game attacks.
	return true


func _advance_menu_stroke(point: Vector2, buttons: Array[Dictionary]) -> void:
	var previous := _ui_previous
	if previous.distance_squared_to(point)<0.0001: return
	_ui_previous = point
	_ui_distance += previous.distance_to(point)
	_ui_trail.append({"point":point,"age":0.0})
	while _ui_trail.size()>28: _ui_trail.pop_front()
	if _ui_consumed or not _ui_pending.is_empty() or _ui_distance<24.0: return
	var earliest := INF
	var selected := -1
	for index in range(buttons.size()):
		var button: Dictionary = buttons[index]
		if str(button.kind) == "slider": continue
		var rect: Rect2 = button.rect
		var entry := _segment_rect_entry(previous,point,rect.grow(-8.0))
		if entry<earliest:
			earliest = entry
			selected = index
	if selected >= 0:
		# A long coalesced segment can cross several choices. Resolve the
		# first real entry along its direction, independent of button order.
		var button: Dictionary = buttons[selected]
		var rect: Rect2 = button.rect
		_ui_focus = selected
		var direction := (point-previous).normalized()
		var origin := Geometry2D.get_closest_point_to_segment(rect.get_center(),previous,point)
		_queue_ui_action(button,"slice",origin,direction)


func _queue_ui_action(button: Dictionary, activation_kind: String, origin: Vector2, direction: Vector2) -> void:
	if not _ui_pending.is_empty(): return
	if direction.length_squared()<0.01: direction = Vector2(1,-0.3).normalized()
	var action := str(button.action)
	_ui_action_count += 1
	_ui_last_action = action
	_ui_last_activation_kind = activation_kind
	_ui_consumed = true
	_ui_pending = {"action":action,"value":button.get("value"),"age":0.0}
	_ui_split = {"rect":button.rect,"label":button.label,"origin":origin,"normal":Vector2(-direction.y,direction.x).normalized(),"age":0.0}
	ui_feedback.emit(&"back" if action == "back" else (&"slice" if activation_kind == "slice" else &"click"))


func _open_ui_page(page: String) -> void:
	var held := _ui_pressed or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	cancel_menu_gesture()
	_ui_must_release = held
	_ui_page = page
	_ui_focus = 0


func _dispatch_ui_action(action: StringName, value: Variant) -> void:
	match action:
		&"settings",&"controls",&"quit_confirm": _open_ui_page(str(action))
		&"back": _open_ui_page("home")
		_: ui_action.emit(action,value)


func get_ui_debug_state() -> Dictionary:
	return {"page":_ui_page,"state":str(_snapshot.get("state","menu")),"reference_size":REFERENCE_SIZE,"buttons":_ui_buttons(),"gesture_pressed":_ui_pressed,"gesture_consumed":_ui_consumed,"must_release":_ui_must_release,"gesture_distance":_ui_distance,"action_count":_ui_action_count,"last_action":_ui_last_action,"last_activation_kind":_ui_last_activation_kind,"pending_action":_ui_pending.get("action",""),"pending_age":_ui_pending.get("age",-1.0),"split_age":_ui_split.get("age",-1.0),"split_duration":0.24,"activation_delay":0.14,"focus":_ui_focus,"pointer":_ui_pointer,"volume_slider_rect":Rect2(88,291,592,40),"slider_dragging":_ui_slider_drag,"menu_ready":bool(_snapshot.get("menu_ready",true))}
