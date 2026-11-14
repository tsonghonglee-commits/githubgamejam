class_name PrototypeHUD
extends Control

const Locale = preload("res://scripts/game_locale.gd")
const StorePreview = preload("res://scripts/weapon_store_preview.gd")

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
const UI_PAPER := Color("f2ede5")
const MENU_MUTED := Color("b9b5ae")
const UI_ACCENT := Color("ff704f")
const UI_INK := Color("101319")
const MENU_RED := Color("ed5241")
const MENU_VOLUME_RECT := Rect2(108, 255, 548, 40)
const MENU_NAV_RECT := Rect2(90, 312, 342, 43)
const MENU_NAV_STEP := 51.0
const MENU_ACTION_DELAY := 0.10
const TITLE_GATE_TRACK := Rect2(384,582,512,3)
const GEAR_COLORS := [Color(0.35, 0.79, 0.76), Color(0.47, 0.94, 0.75), Color(1.0, 0.72, 0.31), Color(1.0, 0.35, 0.26)]
const LETTERBOX_HEIGHT := 88.0
const CUT_SHAKE_LIFETIME := 0.28
const REFLECT_KICK_LIFETIME := 0.54
const CUT_POPUP_LIFETIME := 0.55
const NUMBER_GLYPH_SIZE := 96
const POPUP_ECHOES := 8
const POPUP_QUAD := [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]
const POPUP_NEAR := [Vector2(255,195),Vector2(106,365),Vector2(249,532)]
const POPUP_VANISH := [Vector2(520,344),Vector2(515,365),Vector2(510,416)]
const POPUP_SPACING := [0.38,0.29,0.38]
const POPUP_HEIGHT := [132.0,174.0,132.0]

var _snapshot: Dictionary = {}
var _font: Font
var _number_font: FontVariation
var _title_font: FontVariation
var _number_transform := Transform2D.IDENTITY
var _popup_canvas: Node2D
var _popup_glyphs: Array[Dictionary] = []
var _animation_time := 0.0
var _letterbox := 0.0
var _cut_shake_age := CUT_SHAKE_LIFETIME
var _cut_shake_force := 0.0
var _reflect_kick_age := REFLECT_KICK_LIFETIME
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
var _ui_press_button := -1
var _ui_touch_index := -1
var _ui_slider_drag := false
var _ui_volume_preview := 1.0
var _ui_pending: Dictionary = {}
var _ui_focus_amounts := PackedFloat32Array([0,0,0,0,0,0])
var _title_entered := false
var _title_age := 0.0
var _ui_action_count := 0
var _ui_last_action := ""
var _ui_last_activation_kind := ""
var _store_family := ""
var _store_skin := ""
var _store_preview: SubViewport


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_number_font = FontVariation.new()
	_number_font.base_font = _font
	_number_font.variation_embolden = 0.75
	_title_font = FontVariation.new()
	_title_font.base_font = _font
	_title_font.variation_embolden = 0.22
	_prepare_popup_digits()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _prepare_popup_digits() -> void:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
render_mode unshaded;
varying vec3 projected_uv;
varying float glyph_alpha;
varying float front_glyph;
void vertex() {
	projected_uv = vec3(UV, COLOR.r);
	glyph_alpha = COLOR.a;
	front_glyph = COLOR.g;
}
void fragment() {
	vec2 atlas_uv = projected_uv.xy / projected_uv.z;
	vec3 ink = mix(vec3(1.0), vec3(216.0, 52.0, 67.0) / 255.0, front_glyph);
	COLOR = vec4(ink, texture(TEXTURE, atlas_uv).a * glyph_alpha);
}
"""
	var popup_material := ShaderMaterial.new()
	popup_material.shader = shader
	_popup_canvas = Node2D.new()
	_popup_canvas.name = "CutNumberPerspective"
	_popup_canvas.material = popup_material
	add_child(_popup_canvas)

	var server := TextServerManager.get_primary_interface()
	var font := _number_font.get_rids()[0]
	var cache_size := Vector2i(NUMBER_GLYPH_SIZE,0)
	for digit in range(10):
		var index := server.font_get_glyph_index(font,NUMBER_GLYPH_SIZE,48+digit,0)
		server.font_render_glyph(font,cache_size,index)
		var texture := server.font_get_glyph_texture_rid(font,cache_size,index)
		var texture_size := server.font_get_glyph_texture_size(font,cache_size,index)
		var uv := server.font_get_glyph_uv_rect(font,cache_size,index)
		_popup_glyphs.append({"texture":texture,"uv":Rect2(uv.position/texture_size,uv.size/texture_size),
			"size":server.font_get_glyph_size(font,cache_size,index),
			"offset":server.font_get_glyph_offset(font,cache_size,index),
			"advance":server.font_get_glyph_advance(font,NUMBER_GLYPH_SIZE,index).x})


func _process(delta: float) -> void:
	var real_delta := delta / maxf(Engine.time_scale, 0.001)
	_animation_time += real_delta
	_contact_age += real_delta
	var cutting := str(_snapshot.get("state","menu")) == "playing" and bool(_snapshot.get("slow",false))
	_letterbox = move_toward(_letterbox,1.0 if cutting else 0.0,real_delta/(0.17 if cutting else 0.22))
	_cut_shake_age = minf(CUT_SHAKE_LIFETIME,_cut_shake_age+real_delta)
	_reflect_kick_age = minf(REFLECT_KICK_LIFETIME,_reflect_kick_age+real_delta)
	for index in range(_trails.size() - 1, -1, -1):
		_trails[index].age += real_delta
		if float(_trails[index].age) >= 0.075:
			_trails.remove_at(index)
	if _title_entered:
		_title_age = minf(1.0,_title_age+real_delta)
	for index in _ui_focus_amounts.size():
		_ui_focus_amounts[index] = move_toward(_ui_focus_amounts[index],1.0 if index == _ui_focus else 0.0,real_delta*9.0)
	if not _ui_pending.is_empty():
		_ui_pending.age += real_delta
		if float(_ui_pending.age) >= MENU_ACTION_DELAY:
			var request: Dictionary = _ui_pending.duplicate()
			_ui_pending.clear()
			_dispatch_ui_action(StringName(request.action),request.get("value"))
	_update_store_preview(real_delta)
	queue_redraw()


func set_snapshot(data: Dictionary) -> void:
	var state := str(data.get("state","menu"))
	var previous_state := str(_snapshot.get("state","menu"))
	if state != previous_state:
		_ui_page = "home"
		_ui_focus = 0
		cancel_menu_gesture()
	if state == "playing" and previous_state == "playing":
		if int(data.get("cut_feedback_serial",0)) > int(_snapshot.get("cut_feedback_serial",0)):
			var force := clampf(float(data.get("cut_feedback_force",0.0)),0.0,1.0)
			var light := str(data.get("cut_feedback_kind","light")) == "light"
			_cut_shake_force = lerpf(0.28,1.0,force) if light else 0.64
			_cut_shake_age = 0.0
		if int(data.get("reflected_kills",0)) > int(_snapshot.get("reflected_kills",0)):
			_reflect_kick_age = 0.0
	else:
		_cut_shake_age = CUT_SHAKE_LIFETIME
		_reflect_kick_age = REFLECT_KICK_LIFETIME
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
	RenderingServer.canvas_item_clear(_popup_canvas.get_canvas_item())
	if _font == null or size.x < 1.0 or size.y < 1.0:
		return
	var scale_factor := size / REFERENCE_SIZE
	draw_set_transform(Vector2.ZERO, 0.0, scale_factor)
	_number_transform = Transform2D(0.0,scale_factor,0.0,Vector2.ZERO)
	var state := str(_snapshot.get("state", "menu"))
	var flash := clampf(float(_snapshot.get("flash", 0.0)), 0.0, 1.0)
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, REFERENCE_SIZE), Color(1.0, 0.14, 0.08, flash * 0.22))
	if state == "playing":
		_draw_kinetics()
	_draw_letterbox()
	if state == "playing":
		_draw_telemetry()
		_draw_speed_bar()
		_draw_targets(scale_factor)
		_draw_heavy_preview(scale_factor)
		_draw_aim(scale_factor)
		_draw_contact(scale_factor)
		_draw_combat_messages()
		_draw_cut_counter(scale_factor)
		_draw_held_cut_popups(scale_factor)
		_draw_tutorial(scale_factor)
		_draw_weapon_trial()
	else:
		_draw_menu()
	draw_set_transform(Vector2.ZERO)


func _draw_heavy_preview(scale_factor: Vector2) -> void:
	var path: PackedVector2Array = _snapshot.get("heavy_preview",PackedVector2Array())
	if path.size() < 2: return
	var projected := PackedVector2Array()
	for point in path:
		if not point.is_finite(): return
		projected.append(point/scale_factor)
	var charge := clampf(float(_snapshot.get("weapon_charge",0.0)),0.0,1.0)
	var full := charge >= 0.999
	var edge := Color("ffce87") if full else Color("dceaf4")
	draw_polyline(projected,Color(INK,0.62),4.0 if full else 3.0,true)
	draw_polyline(projected,Color(edge,0.90 if full else 0.59),1.8 if full else 1.15,true)
	for point in [projected[0],projected[-1]]:
		draw_circle(point,2.4 if full else 1.6,edge,true,-1.0,true)


func _draw_letterbox() -> void:
	var height := LETTERBOX_HEIGHT*smoothstep(0.0,1.0,_letterbox)
	if height > 0.0:
		draw_rect(Rect2(0.0,0.0,REFERENCE_SIZE.x,height),Color.BLACK)
		draw_rect(Rect2(0.0,REFERENCE_SIZE.y-height,REFERENCE_SIZE.x,height),Color.BLACK)


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
	var tutorial: Dictionary = _snapshot.get("tutorial",{})
	var in_tutorial := bool(tutorial.get("active",false))
	var in_trial := bool(_snapshot.get("weapon_trial",false))
	for index in range(5):
		var bar := Rect2(36+float(index)*28,34,20,6)
		draw_rect(bar,Color(PAPER,0.13))
		if index < health: draw_rect(bar,VERMILION if health <= 2 else PAPER)
	_text(Vector2(36,59),"生命",10,ASH)
	if bool(_snapshot.get("invincible",false)):
		_text(Vector2(36,81),"无敌 · F6 关闭",12,AMBER)
	elif bool(_snapshot.get("training",false)) and not in_tutorial and not in_trial:
		_text(Vector2(36,81),"切割实验场",12,CYAN)
	elif bool(_snapshot.get("practice",false)):
		_text(Vector2(36,81),"练习模式",12,AMBER)
	var elapsed := float(_snapshot.get("time",0.0))
	var duration := maxf(1.0,float(_snapshot.get("duration",180.0)))
	var chapter := clampi(int(_snapshot.get("route_section",0)),0,3)
	var label: String = ["装配区","炉区","高架桥","核心长廊"][chapter]
	if bool(_snapshot.get("boss",false)): label = "核心守卫"
	if bool(_snapshot.get("campaign_active",false)):
		label = "%d / 4 · %s" % [int(_snapshot.get("campaign_level",1)),Locale.text(str(_snapshot.get("series_label","第一系列")))]
		if str(_snapshot.get("campaign_phase","")) == "boss": label += Locale.text(" · 守关战")
		elif str(_snapshot.get("campaign_phase","")) == "transition": label += Locale.text(" · 区域过渡")
	if bool(_snapshot.get("training",false)): label = "自由切割"
	if in_tutorial: label = "教程"
	if in_trial: label = "武器试用"
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
	elif float(_snapshot.get("parry",0.0)) > 0.0:
		draw_arc(center,37.0,-PI*0.9,-PI*0.1,32,Color(AMBER,0.55),1.0,true)
	else:
		for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(center + direction * 5.0, center + direction * 12.0, Color(WHITE, 0.7), 1.0, true)
		draw_circle(center, 1.5, CYAN)
	var charge := clampf(float(_snapshot.get("weapon_charge",0.0)),0.0,1.0)
	if charge > 0.0:
		var gauge := Rect2(center+Vector2(-26,23),Vector2(52,4))
		draw_rect(gauge,Color(INK,0.85))
		draw_rect(Rect2(gauge.position,Vector2(gauge.size.x*charge,gauge.size.y)),AMBER.lerp(WHITE,smoothstep(0.90,1.0,charge)))
	for trail in _trails:
		var blade_alpha := pow(clampf(1.0 - float(trail.age) / 0.075, 0.0, 1.0), 1.5)
		var blade_path: PackedVector2Array = trail.path
		var render_path := PackedVector2Array()
		for point in blade_path:
			render_path.append(point / scale_factor)
		draw_polyline(render_path, Color(0.76, 0.95, 0.95, blade_alpha * 0.62), 1.1, true)


func _draw_targets(scale_factor: Vector2) -> void:
	if float(_snapshot.get("parry",0.0)) > 0.0:
		var guard_targets: Array = _snapshot.get("guard_targets",[])
		for target: Dictionary in guard_targets:
			var screen := Vector2(target.get("screen",Vector2(-1000,-1000)))/scale_factor
			if not Rect2(25,110,1230,470).has_point(screen): continue
			var progress := clampf(float(target.get("progress",0.0)),0.0,1.0)
			var accent := CYAN if bool(target.get("can_cut",false)) else MUTED
			if progress >= 0.84:
				accent = RED if int(_animation_time*12.0)%2 == 0 else AMBER
			var radius := 38.0 if str(target.get("kind","")) == "boss" else 29.0
			draw_arc(screen,radius,-PI*0.5,PI*1.5,40,Color(INK,0.65),4.0,true)
			draw_arc(screen,radius,-PI*0.5,-PI*0.5+TAU*maxf(progress,0.005),40,Color(accent,0.85),2.5,true)
		return
	var tutorial: Dictionary = _snapshot.get("tutorial",{})
	if bool(tutorial.get("active",false)): return
	var targets: Array = _snapshot.get("targets", [])
	for target: Dictionary in targets:
		var screen := Vector2(target.get("screen", Vector2(-1000, -1000))) / scale_factor
		if screen.x < 25.0 or screen.x > 1255.0 or screen.y < 110.0 or screen.y > 580.0:
			continue
		var progress := clampf(float(target.get("progress", 0.0)), 0.0, 1.0)
		var time_left := float(target.get("time_left", 99.0))
		if bool(_snapshot.get("training", false)):
			for direction in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var corner: Vector2 = screen + direction * 12.0
				draw_line(corner, corner - Vector2(direction.x * 4.0, 0.0), Color(CYAN, 0.35), 1.0, true)
		elif progress > 0.80 and time_left >= 0.0:
			var accent := AMBER if progress < 0.95 else RED
			var tip := screen - Vector2(0, 33)
			draw_line(tip + Vector2(-6, -7), tip, Color(accent, 0.86), 2.0, true)
			draw_line(tip + Vector2(6, -7), tip, Color(accent, 0.86), 2.0, true)


func _draw_cut_counter(scale_factor: Vector2) -> void:
	var total := int(_snapshot.get("cut_total",0))
	var value := str(total)
	var shake := _cut_shake_force*pow(1.0-_cut_shake_age/CUT_SHAKE_LIFETIME,1.45)
	var kick := pow(1.0-_reflect_kick_age/REFLECT_KICK_LIFETIME,2.6)
	var shake_phase := _cut_shake_age*TAU*24.0
	var offset := Vector2(-cos(shake_phase)*22.0,sin(shake_phase*0.71)*14.0)*shake
	var angle := sin(shake_phase*0.83)*0.105*shake
	var right := Vector2(1244.0,53.0+55.0*kick)+offset
	right.x = minf(right.x,1255.0)
	right.y = maxf(right.y,40.0)
	var font_size := roundi(lerpf(33.0,122.0,kick)+8.0*shake)
	var tint := PAPER.lerp(Color.WHITE,maxf(kick,shake*0.65))
	var reflected_without_cuts := total == 0 and kick > 0.1
	if reflected_without_cuts:
		_draw_number(Vector2(1244,53),value,33,PAPER,true,2)
		right = Vector2(1199,53.0+55.0*kick)
		value = str(int(_snapshot.get("kills",0)))
	var base_transform := _number_transform
	_number_transform = Transform2D(Vector2.RIGHT.rotated(angle)*scale_factor,Vector2.DOWN.rotated(angle)*scale_factor,right*scale_factor)
	_draw_number(Vector2.ZERO,value,font_size,Color.WHITE if kick > 0.1 else tint,true,3 if kick > 0.1 else 2)
	_number_transform = base_transform
	draw_set_transform_matrix(base_transform)
	_text_right(Vector2(1243,71),Locale.text("%02d 斩断")%int(_snapshot.get("kills",0)),11,Color(ASH,1.0-smoothstep(0.0,0.35,kick)))

func _draw_held_cut_popups(scale_factor: Vector2) -> void:
	if not bool(_setting("cut_popups",true)): return
	var popups: Array = _snapshot.get("cut_popups",[])
	if popups.is_empty(): return
	var geometry: Dictionary = {}
	for popup: Dictionary in popups:
		var progress := clampf(float(popup.age)/CUT_POPUP_LIFETIME,0.0,1.0)
		var alpha := 1.0-smoothstep(0.57,1.0,progress)
		if alpha <= 0.0: continue
		var slot := clampi(int(popup.slot),0,5)
		var row := slot/2
		var near: Vector2 = POPUP_NEAR[row]
		var vanish: Vector2 = POPUP_VANISH[row]
		var side := 1.0 if slot%2 == 0 else -1.0
		if side < 0.0:
			near.x = REFERENCE_SIZE.x-near.x
			vanish.x = REFERENCE_SIZE.x-vanish.x
		var value := str(int(popup.cells))
		var digits: Array[Dictionary] = []
		var width := 0.0
		for index in value.length():
			var glyph := _popup_glyphs[value.unicode_at(index)-48]
			digits.append(glyph)
			width += float(glyph.advance)
		var separation: float = POPUP_SPACING[row]
		var height: float = POPUP_HEIGHT[row]
		var depth_span := minf(separation*0.81,lerpf(0.22,0.32,smoothstep(1.0,4.0,digits.size())))
		var snap := lerpf(1.13,1.0,smoothstep(0.0,0.13,progress))+0.12*smoothstep(0.56,1.0,progress)
		for echo in range(POPUP_ECHOES-1,-1,-1):
			var depth := snap+float(echo)*separation
			var opacity := alpha*lerpf(1.0,0.66,float(echo)/float(POPUP_ECHOES-1))
			var front_glyph := 1.0 if echo == 0 else 0.0
			var pen := 0.0
			for glyph in digits:
				var texture: RID = glyph.texture
				if not geometry.has(texture):
					geometry[texture] = {"points":PackedVector2Array(),"uvs":PackedVector2Array(),"colors":PackedColorArray(),"indices":PackedInt32Array()}
				var batch: Dictionary = geometry[texture]
				var base: int = batch.points.size()
				var uv: Rect2 = glyph.uv
				for corner: Vector2 in POPUP_QUAD:
					var cell: Vector2 = glyph.offset+glyph.size*corner
					var glyph_x := (pen+cell.x)/width-0.5
					var glyph_y := (cell.y+37.0)/78.0
					var inv_z := 1.0/(depth+side*glyph_x*depth_span)
					var point := vanish+(near-vanish+Vector2(glyph_x*10.0,glyph_y*height))*inv_z
					batch.points.append(point*scale_factor)
					# Multiplying UV by reciprocal Z before interpolation keeps the
					# glyph on its actual projective plane across both triangles.
					batch.uvs.append((uv.position+uv.size*corner)*inv_z)
					batch.colors.append(Color(inv_z,front_glyph,0.0,opacity))
				batch.indices.append_array(PackedInt32Array([base,base+1,base+2,base,base+2,base+3]))
				pen += float(glyph.advance)
	for texture: RID in geometry:
		var batch: Dictionary = geometry[texture]
		RenderingServer.canvas_item_add_triangle_array(_popup_canvas.get_canvas_item(),batch.indices,batch.points,batch.colors,batch.uvs,PackedInt32Array(),PackedFloat32Array(),texture)


func _draw_combat_messages() -> void:
	var message := Locale.text(str(_snapshot.get("message", "")))
	var guided := bool(_snapshot.get("training", false)) or float(_snapshot.get("time", 0.0)) < 3.0
	var tutorial: Dictionary = _snapshot.get("tutorial",{})
	if bool(tutorial.get("active",false)): guided = false
	if guided and not message.is_empty():
		var width := minf(_font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 30.0, 800.0)
		var top := 225.0 if bool(_snapshot.get("weapon_trial",false)) else 163.0
		_panel(Rect2(640 - width * 0.5, top, width, 31), 0.8)
		_text_center(Vector2(640, top+21.0), message, 16, WHITE)
	if not _snapshot.get("tutorial",{}).is_empty(): return
	var combo := int(_snapshot.get("combo", 0))
	if combo > 1:
		_text(Vector2(32, 176), "%02d" % combo, 38, CYAN)
		_text(Vector2(35, 195), "CHAIN / 连斩", 11, MUTED)


func _draw_tutorial(scale_factor: Vector2) -> void:
	var lesson: Dictionary = _snapshot.get("tutorial",{})
	if not bool(lesson.get("active",false)): return
	var target := Vector2(lesson.get("target",Vector2.INF))/scale_factor
	if target.is_finite() and Rect2(22,105,1236,500).has_point(target):
		for direction in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
			var corner: Vector2 = target+direction*22.0
			draw_line(corner,corner-Vector2(direction.x*7.0,0),Color(UI_PAPER,0.75),1.5,true)
			draw_line(corner,corner-Vector2(0,direction.y*7.0),Color(UI_PAPER,0.75),1.5,true)
	var panel := Rect2(35,102,446,151)
	var alpha := lerpf(1.0,0.20,_hilt_clearance(panel))
	draw_rect(panel,Color(UI_INK,0.88*alpha))
	draw_line(panel.position,panel.position+Vector2(52,0),Color(MENU_RED,alpha),3.0)
	var title := str(lesson.get("title",""))
	_title_text(Vector2(52,139),title,25,Color(UI_PAPER,alpha))
	_text_right(Vector2(464,137),"%d / %d"%[int(lesson.get("step",1)),int(lesson.get("total",1))],13,Color(MENU_MUTED,alpha))
	var prompt := Locale.text(str(lesson.get("prompt","")))
	draw_multiline_string(_font,Vector2(52,173),prompt,HORIZONTAL_ALIGNMENT_LEFT,414,17,2,Color(UI_PAPER,alpha))
	var detail := Locale.text(str(lesson.get("detail","")))
	draw_multiline_string(_font,Vector2(52,211),detail,HORIZONTAL_ALIGNMENT_LEFT,414,14,3,Color(MENU_MUTED,alpha))


func _draw_weapon_trial() -> void:
	if not bool(_snapshot.get("weapon_trial",false)): return
	var finish: Dictionary = _snapshot.get("weapon_trial_finish",{})
	if finish.is_empty(): return
	var panel := Rect2(35,102,446,118)
	var alpha := lerpf(1.0,0.20,_hilt_clearance(panel))
	draw_rect(panel,Color(UI_INK,0.88*alpha))
	draw_line(panel.position,panel.position+Vector2(52,0),Color(finish.color,alpha),3.0)
	_title_text(Vector2(52,138),str(finish.name),24,Color(UI_PAPER,alpha),285)
	_text_right(Vector2(464,136),"武器试用",14,Color(MENU_MUTED,alpha))
	var controls: Array = finish.get("touch_controls" if bool(_snapshot.get("touch_mode",false)) else "controls",[])
	for index in controls.size():
		_text(Vector2(52,167+float(index)*23.0),str(controls[index]),16,Color(UI_PAPER,alpha),411)


func _draw_menu() -> void:
	var state := str(_snapshot.get("state", "menu"))
	var home := _ui_page == "home"
	if state == "menu" and home and not _title_entered:
		_draw_title_gate()
		return
	_draw_menu_backdrop(state == "menu",home)
	if state == "menu" and home:
		_draw_title_page()
		return
	_text(Vector2(88, 88), "SLAY THE HIGHWAY", 14, MENU_MUTED)
	match _ui_page:
		"settings":
			_text(Vector2(85, 173), "设置", 60, UI_PAPER)
			_draw_settings_page()
		"controls":
			_text(Vector2(85, 173), "操作指南", 60, UI_PAPER)
			_draw_controls_page()
		"store":
			_text(Vector2(85, 173), "商店", 60, UI_PAPER)
			_draw_store_page()
		"quit_confirm":
			_text(Vector2(85, 173), "退出游戏？", 60, UI_PAPER)
		_:
			var title := "暂停" if state == "paused" else ("行程结束" if state == "dead" else "突破完成")
			_text(Vector2(84, 215), title, 80, UI_PAPER)
			_draw_result_stats()
	_draw_ui_buttons()
	draw_line(Vector2(88, 650), Vector2(1192, 650), Color(UI_PAPER, 0.22))
	var hint := _navigation_hint()
	if _ui_page == "settings":
		hint = "触碰切换 · 拖动滑块调音量" if bool(_snapshot.get("touch_mode",false)) else "拖动滑块或按 ← → 调音量    ·    ↑ ↓  选择"
	_text(Vector2(88, 680), hint, 15, MENU_MUTED)
	if not bool(_snapshot.get("touch_mode",false)):
		_text_right(Vector2(1192,680),"Esc  继续" if home and state == "paused" else "Esc  返回",15,UI_PAPER)


func _draw_menu_backdrop(title_screen: bool, home: bool) -> void:
	var title_home := title_screen and home
	var left := Color("0a0c0f")
	var right := Color(left,0.03 if title_home else 0.65)
	var middle := Color(left,0.82 if title_home else 0.94)
	var stops := [0.0,370.0 if title_home else 710.0,800.0 if title_home else 1192.0,REFERENCE_SIZE.x]
	var colors := [Color(left,0.92),middle,right,right]
	for index in range(stops.size() - 1):
		var x0: float = stops[index]
		var x1: float = stops[index + 1]
		draw_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, 720), Vector2(x0, 720)]),
			PackedColorArray([colors[index], colors[index + 1], colors[index + 1], colors[index]]))
	if not title_home:
		draw_rect(Rect2(0,650,1280,70),Color(UI_INK,0.77))


func _draw_title_page() -> void:
	draw_rect(Rect2(0,0,1280,40),Color("090b0d"))
	draw_rect(Rect2(0,664,1280,56),Color("090b0d"))
	draw_line(Vector2(88,664),Vector2(1192,664),Color(UI_PAPER,0.19))
	if Locale.current == "zh_CN":
		_title_text(Vector2(79,225),"杀路",138,UI_PAPER)
		_title_text(Vector2(89,264),"SLAY THE HIGHWAY",20,UI_PAPER)
	else:
		_title_text(Vector2(86,171),"SLAY THE",70,UI_PAPER,410)
		_title_text(Vector2(86,249),"HIGHWAY",80,UI_PAPER,410)
	draw_line(Vector2(89,286),Vector2(430,286),Color(UI_PAPER,0.19))
	draw_line(Vector2(89,286),Vector2(141,286),MENU_RED,2.0)
	_draw_title_rows()
	_text(Vector2(90,697),_navigation_hint(),14,MENU_MUTED)


func _draw_title_rows() -> void:
	var buttons := _ui_buttons()
	for index in buttons.size():
		var button: Dictionary = buttons[index]
		var reveal := _title_row_reveal(index)
		var rect := _title_row_rect(button,index)
		var focus := _ui_focus_amounts[index]
		var pressing := not _ui_pending.is_empty() and str(_ui_pending.action) == str(button.action)
		var highlight := maxf(focus,1.0 if pressing else 0.0)
		var plate := _menu_card_points(rect)
		draw_colored_polygon(plate,Color(MENU_RED,highlight*reveal*(0.90 if pressing else 0.65)))
		draw_rect(Rect2(rect.position,Vector2(2,rect.size.y)),Color(MENU_RED,reveal*highlight))
		draw_line(rect.position+Vector2(0,rect.size.y),rect.end,Color(UI_PAPER,0.14*reveal))
		var inset := 19.0+13.0*highlight
		var text_tint := Color(MENU_MUTED.lerp(UI_PAPER,0.45+0.55*highlight),reveal)
		_title_text(rect.position+Vector2(inset,29),str(button.label),25,text_tint)
		if highlight > 0.0:
			var tip := rect.get_center()+Vector2(rect.size.x*0.5-22.0,0)
			draw_polyline(PackedVector2Array([tip-Vector2(8,6),tip,tip-Vector2(8,-6)]),Color(UI_PAPER,reveal*highlight),1.6,true)


func _title_row_reveal(index: int) -> float:
	return 1.0-pow(1.0-clampf((_title_age-float(index)*0.055)/0.34,0.0,1.0),4.0)


func _title_row_rect(button: Dictionary, index: int) -> Rect2:
	var rect: Rect2 = button.rect
	rect.position.x -= 140.0*(1.0-_title_row_reveal(index))
	return rect


func _navigation_hint() -> String:
	return "轻触选择" if bool(_snapshot.get("touch_mode",false)) else "↑ ↓  选择    Enter  确认"


func _draw_title_gate() -> void:
	if bool(_snapshot.get("menu_ready",false)):
		_text_center(Vector2(640,581),"点击任意区域开始游戏",27,Color.WHITE)
		return
	var completed := int(_snapshot.get("warm_completed", 0))
	var total := int(_snapshot.get("warm_total", 0))
	var fraction := clampf(float(completed) / float(maxi(total, 1)), 0.0, 1.0)
	draw_rect(TITLE_GATE_TRACK,Color("353638"))
	draw_rect(Rect2(TITLE_GATE_TRACK.position,Vector2(TITLE_GATE_TRACK.size.x*fraction,TITLE_GATE_TRACK.size.y)),MENU_RED)
	_title_text(Vector2(TITLE_GATE_TRACK.position.x,558),"正在准备行程",26,UI_PAPER)
	_text_right(Vector2(TITLE_GATE_TRACK.end.x,558),"%d%%"%mini(99,roundi(fraction*100.0)),21,MENU_MUTED)


func _draw_result_stats() -> void:
	var panel := Rect2(722, 261, 470, 284)
	draw_colored_polygon(_menu_card_points(panel), Color(UI_INK, 0.88))
	draw_line(panel.position, panel.position + Vector2(44, 0), UI_ACCENT, 3.0)
	_text(Vector2(750, 310), "本次得分", 17, MENU_MUTED)
	_text(Vector2(746, 381), "%06d" % int(_snapshot.get("score", 0)), 60, UI_PAPER)
	draw_line(Vector2(750, 412), Vector2(1164, 412), Color(UI_PAPER, 0.20))
	_text(Vector2(750, 450), "目标斩断", 16, MENU_MUTED)
	_text(Vector2(968, 450), "行程时间", 16, MENU_MUTED)
	_text(Vector2(750, 503), "%02d" % int(_snapshot.get("kills", 0)), 36, UI_PAPER)
	var time := int(_snapshot.get("run_time", _snapshot.get("time", 0)))
	_text(Vector2(968, 503), "%02d:%02d" % [time / 60, time % 60], 36, UI_PAPER)
	var earned := int(_snapshot.get("run_currency",0))
	if earned > 0:
		_text_right(Vector2(1164,310),Locale.text("+%d 资金")%earned,17,UI_PAPER)


func _draw_controls_page() -> void:
	var rows := [
		["移动鼠标", "转头，长斩时控制刀路"],
		["轻点左键", "轻击，连续点击可衔接十二式"],
		["按住左键拖动", "进入慢动作长斩，持续消耗速度"],
		["右键", "轻按精准振刀可提速，长按架刀可挡一击"],
		["按住 Shift", "提速并切换档位"],
		["Esc", "暂停或继续"],
		["F6", "局内切换无敌"],
	]
	for index in range(rows.size()):
		var y := 216.0 + float(index) * 43.0
		draw_rect(Rect2(88, y, 154, 32), Color(UI_PAPER, 0.09))
		_text(Vector2(102, y + 22), rows[index][0], 16, UI_PAPER,129)
		_text(Vector2(264, y + 22), rows[index][1], 18, MENU_MUTED)
		if index < rows.size() - 1:
			draw_line(Vector2(264, y + 36), Vector2(752, y + 36), Color(UI_PAPER, 0.11))
	_text(Vector2(88, 551), "自动前进，无法换道。漏过地面敌人会受伤，天空敌机持续射击。", 16, UI_PAPER)
	_text(Vector2(88, 578), "斩断关键连接即可击毁目标，残骸仍可再切。", 16, MENU_MUTED)


func _setting(key: String, fallback: Variant) -> Variant:
	var settings: Dictionary = _snapshot.get("ui_settings",{})
	return settings.get(key,fallback)


func _draw_settings_page() -> void:
	var volume := _ui_volume_preview if _ui_slider_drag else clampf(float(_setting("volume", 1.0)), 0.0, 1.0)
	var focused := _ui_focus == 0
	var card := Rect2(88, 204, 588, 100)
	draw_colored_polygon(_menu_card_points(card), Color(UI_PAPER, 0.11 if focused else 0.06))
	if focused:
		draw_rect(Rect2(card.position, Vector2(3, card.size.y)), UI_ACCENT)
	_text(Vector2(108, 242), "主音量", 21, UI_PAPER)
	_text_right(Vector2(656, 242), "%d%%" % roundi(volume * 100.0), 21, UI_PAPER)
	var track := Rect2(MENU_VOLUME_RECT.position.x, MENU_VOLUME_RECT.get_center().y - 2, MENU_VOLUME_RECT.size.x, 4)
	draw_rect(track, Color(UI_PAPER, 0.22))
	draw_rect(Rect2(track.position, Vector2(track.size.x * volume, track.size.y)), UI_ACCENT)
	draw_circle(track.position + Vector2(track.size.x * volume, 2), 7.0, UI_PAPER, true, -1.0, true)
	_text(Vector2(88, 351), "画面", 17, MENU_MUTED)
	_text(Vector2(728, 351), "语言", 17, MENU_MUTED)


func _store_weapon() -> Dictionary:
	var weapons: Array = _snapshot.get("shop_weapons",[])
	for weapon in weapons:
		if str(weapon.id) == _store_family: return weapon
	return weapons[0] if not weapons.is_empty() else {}


func _store_finish(weapon: Dictionary) -> Dictionary:
	for skin in weapon.get("skins",[]):
		if str(skin.id) == _store_skin: return skin
	return weapon.get("skins",[weapon])[0]


func _draw_store_page() -> void:
	var weapon := _store_weapon()
	var funds := int(_snapshot.get("currency",0))
	_text(Vector2(90,224),"选择武器",15,MENU_MUTED)
	_text_right(Vector2(1192,167),Locale.text("资金  %d") % funds,23,UI_PAPER)
	if weapon.is_empty(): return
	var finish := _store_finish(weapon)
	_text(Vector2(90,474),"外观",15,MENU_MUTED)
	var panel := Rect2(542,218,650,303)
	var accent: Color = finish.get("color",MENU_RED)
	draw_rect(panel,Color(UI_INK,0.92))
	draw_line(panel.position,panel.position+Vector2(63,0),accent,3.0)
	_title_text(Vector2(565,257),str(finish.name),30,UI_PAPER,606)
	_text(Vector2(567,285),str(finish.description),16,MENU_MUTED,598)
	var controls: Array = weapon.get("touch_controls" if bool(_snapshot.get("touch_mode",false)) else "controls",[])
	for index in controls.size():
		_text(Vector2(568,472+float(index)*23.0),str(controls[index]),16,UI_PAPER,599)
	_draw_store_preview(accent,str(finish.skin_id))
	var message := str(_snapshot.get("shop_message","")) if _ui_last_action in ["shop_weapon","shop_skin"] else ""
	if message.is_empty() and str(finish.id) != str(weapon.id) and not bool(weapon.owned):
		message = "购买武器后可装备此外观"
	if not message.is_empty():
		_text(Vector2(545,618),message,16,UI_PAPER)


func _draw_store_preview(accent: Color, skin: String) -> void:
	var slot := Rect2(568,296,594,145)
	draw_line(Vector2(slot.position.x+12,slot.end.y),Vector2(slot.end.x-12,slot.end.y),Color(accent,0.16))
	if is_instance_valid(_store_preview) and _store_preview.selected_skin == skin:
		draw_texture_rect(_store_preview.get_texture(),slot,false)


func _update_store_preview(delta: float) -> void:
	if DisplayServer.get_name() == "headless": return
	var finish: Dictionary = {}
	if _ui_page == "store" and str(_snapshot.get("state","menu")) == "menu":
		var weapon := _store_weapon()
		if not weapon.is_empty(): finish = _store_finish(weapon)
	if not is_instance_valid(_store_preview):
		if finish.is_empty(): return
		_store_preview = StorePreview.new()
		_store_preview.name = "WeaponStorePreview"
		add_child(_store_preview)
	_store_preview.advance(finish,delta)


func _ui_button(action: StringName, label: String, subtitle: String, rect: Rect2, value: Variant = null, kind: String = "button") -> Dictionary:
	return {"id":str(action),"action":str(action),"label":Locale.text(label),"subtitle":Locale.text(subtitle),"rect":rect,"value":value,"kind":kind,"enabled":true}


func _ui_buttons() -> Array[Dictionary]:
	var buttons: Array[Dictionary] = []
	var state := str(_snapshot.get("state","menu"))
	if state == "playing": return buttons
	if _ui_page == "controls":
		buttons.append(_ui_button(&"back", "返回", "", Rect2(968, 579, 224, 54)))
	elif _ui_page == "settings":
		buttons.append(_ui_button(&"volume", "主音量", "", MENU_VOLUME_RECT, float(_setting("volume", 1.0)), "slider"))
		for index in range(4):
			var action: StringName = [&"fullscreen", &"vsync", &"msaa", &"cut_popups"][index]
			var enabled := bool(_setting(str(action), true))
			var label: String = ["全屏", "垂直同步", "4× 抗锯齿", "长斩透视跳字"][index]
			buttons.append(_ui_button(action, label, "开启" if enabled else "关闭", Rect2(88, 369 + float(index) * 64.0, 588, 54), not enabled, "toggle"))
		var language := str(_setting("language",Locale.DEFAULT))
		for index in Locale.LANGUAGES.size():
			var code: String = Locale.LANGUAGES[index]
			var position := Vector2(728.0+float(index%2)*235.0,369.0+floorf(float(index)/2.0)*64.0)
			var option := _ui_button(&"language",Locale.NAMES[index],"",Rect2(position,Vector2(224,54)),code,"language")
			option.id = "language_"+code
			option.current = language == code
			buttons.append(option)
		buttons.append(_ui_button(&"back", "返回", "", Rect2(968, 579, 224, 54)))
	elif _ui_page == "quit_confirm":
		buttons.append(_ui_button(&"quit", "确认退出", "", Rect2(88, 292, 414, 58)))
		buttons.append(_ui_button(&"back", "取消", "", Rect2(88, 364, 414, 52)))
	elif _ui_page == "store":
		var weapons: Array = _snapshot.get("shop_weapons",[])
		for index in weapons.size():
			var weapon: Dictionary = weapons[index]
			var tag := "已装备" if bool(weapon.equipped) else ("已拥有" if bool(weapon.owned) else str(int(weapon.price)))
			buttons.append(_ui_button(&"shop_select_weapon",str(weapon.name),tag,Rect2(89,238+float(index)*53.0,421,45),str(weapon.id),"weapon"))
		var weapon := _store_weapon()
		if not weapon.is_empty():
			var skins: Array = weapon.get("skins",[])
			for index in skins.size():
				var skin: Dictionary = skins[index]
				var tag := "" if index == 0 else ("已拥有" if bool(skin.owned) else str(int(skin.price)))
				buttons.append(_ui_button(&"shop_select_skin",str(skin.short_name),tag,Rect2(89+float(index)*106.0,490,100,56),str(skin.id),"shop_skin"))
			var finish := _store_finish(weapon)
			var unlocked := bool(weapon.owned)
			var selected := bool(finish.get("equipped",false))
			var action := &"shop_skin" if unlocked else &"shop_weapon"
			var purchase_id := str(finish.id) if unlocked else str(weapon.id)
			var label := "装备" if bool(finish.owned) else Locale.text("购买  %d") % int(finish.price)
			if not unlocked: label = Locale.text("购买武器  %d") % int(weapon.price)
			if selected: label = "已装备"
			buttons.append(_ui_button(action,label,"",Rect2(542,540,318,48),purchase_id,"primary"))
			buttons.append(_ui_button(&"shop_trial","试用","",Rect2(872,540,320,48),str(finish.id)))
		buttons.append(_ui_button(&"back","返回","",Rect2(968,600,224,40)))
	elif state == "menu":
		if not _title_entered or not bool(_snapshot.get("menu_ready",false)): return buttons
		var actions := [&"start",&"tutorial",&"store",&"settings",&"controls",&"quit_confirm"]
		var labels := ["开始游戏","教程","商店","设置","操作指南","退出"]
		for index in actions.size():
			var rect := MENU_NAV_RECT
			rect.position.y += float(index)*MENU_NAV_STEP
			buttons.append(_ui_button(actions[index],labels[index],"",rect))
	else:
		var actions := [&"resume", &"restart", &"settings", &"controls", &"menu"] if state == "paused" else [&"restart", &"settings", &"controls", &"menu"]
		var labels := {&"resume": "继续游戏", &"restart": "重新开始", &"settings": "设置", &"controls": "操作指南", &"menu": "返回商店" if bool(_snapshot.get("weapon_trial",false)) else "返回标题"}
		for index in range(actions.size()):
			var action: StringName = actions[index]
			var kind := "primary" if index == 0 else "button"
			buttons.append(_ui_button(action, labels[action], "", Rect2(88, 261 + float(index) * 64, 414, 54), null, kind))
	return buttons


func _menu_card_points(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position, Vector2(rect.end.x - 13, rect.position.y), Vector2(rect.end.x, rect.position.y + 13),
		rect.end, Vector2(rect.position.x, rect.end.y),
	])


func _draw_ui_buttons() -> void:
	var buttons := _ui_buttons()
	for index in range(buttons.size()):
		var button: Dictionary = buttons[index]
		var kind := str(button.kind)
		if kind == "slider":
			continue
		var rect: Rect2 = button.rect
		var selected := index == _ui_focus
		var previewed := (kind == "weapon" and str(button.value) == _store_family) or (kind == "shop_skin" and str(button.value) == _store_skin)
		var pressing: bool = not _ui_pending.is_empty() and str(_ui_pending.action) == str(button.action) and _ui_pending.get("value") == button.get("value")
		var primary := kind == "primary"
		var filled := primary and selected
		var label_color := UI_INK if filled else UI_PAPER
		var fill := Color(UI_PAPER, 0.15 if selected else 0.065)
		if previewed: fill = Color(MENU_RED,0.25 if selected else 0.17)
		if primary:
			fill = UI_ACCENT if filled else Color(UI_ACCENT, 0.22)
		if pressing:
			fill = Color(MENU_RED,0.76)
		draw_colored_polygon(_menu_card_points(rect), fill)
		if selected and not filled:
			draw_rect(Rect2(rect.position, Vector2(3, rect.size.y)), UI_ACCENT)
		if not filled:
			var border := Color(UI_ACCENT, 0.68) if primary else Color(UI_PAPER, 0.15)
			draw_line(Vector2(rect.position.x, rect.end.y), rect.end, border)
		if kind == "shop_skin":
			_text_center(rect.get_center()+Vector2(0,-3 if not str(button.subtitle).is_empty() else 6),str(button.label),17,label_color,88)
			if not str(button.subtitle).is_empty():
				_text_center(rect.get_center()+Vector2(0,17),str(button.subtitle),12,MENU_MUTED)
			continue
		_text(rect.position + Vector2(20, rect.size.y * 0.5 + 8), str(button.label), 24 if primary else 20, label_color,rect.size.x-(150.0 if kind in ["weapon","toggle"] else 62.0))
		if kind == "toggle":
			_draw_menu_toggle(rect, not bool(button.value), str(button.subtitle))
		elif kind == "weapon":
			_text_right(Vector2(rect.end.x-20.0,rect.get_center().y+6.0),str(button.subtitle),17,UI_PAPER if selected else MENU_MUTED)
		elif kind == "language":
			var marker := Vector2(rect.end.x-27.0,rect.get_center().y)
			draw_circle(marker,5.0,UI_ACCENT if bool(button.current) else Color(MENU_MUTED,0.35))
		else:
			var arrow := rect.get_center() + Vector2(rect.size.x * 0.5 - 30, 0)
			var direction := -1.0 if str(button.action) == "back" else 1.0
			var arrow_color := label_color if filled else (UI_ACCENT if selected else MENU_MUTED)
			draw_polyline(PackedVector2Array([arrow + Vector2(-4 * direction, -6), arrow + Vector2(3 * direction, 0), arrow + Vector2(-4 * direction, 6)]), arrow_color, 2.0, true)


func _draw_menu_toggle(rect: Rect2, enabled: bool, label: String) -> void:
	var center := Vector2(rect.end.x - 42, rect.get_center().y)
	var rail := Rect2(center - Vector2(20, 9), Vector2(40, 18))
	draw_rect(rail, Color(UI_ACCENT, 0.30) if enabled else Color(UI_PAPER, 0.13))
	var thumb_x := rail.end.x - 15 if enabled else rail.position.x + 3
	draw_rect(Rect2(thumb_x, rail.position.y + 3, 12, 12), UI_ACCENT if enabled else MENU_MUTED)
	_text_right(Vector2(rail.position.x - 12, center.y + 6), label, 16, UI_PAPER if enabled else MENU_MUTED)


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


func _text(at: Vector2, value: String, font_size: int, color: Color, max_width: float = 0.0) -> void:
	var label := Locale.text(value)
	draw_string(_font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _fit_font(_font,label,font_size,max_width), color)


func _title_text(at: Vector2, value: String, font_size: int, color: Color, max_width: float = 0.0) -> void:
	var label := Locale.text(value)
	draw_string(_title_font,at,label,HORIZONTAL_ALIGNMENT_LEFT,-1.0,_fit_font(_title_font,label,font_size,max_width),color)


func _text_center(at: Vector2, value: String, font_size: int, color: Color, max_width: float = 0.0) -> void:
	var label := Locale.text(value)
	font_size = _fit_font(_font,label,font_size,max_width)
	var width := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	draw_string(_font,at-Vector2(width*0.5,0),label,HORIZONTAL_ALIGNMENT_LEFT,-1.0,font_size,color)


func _text_right(at: Vector2, value: String, font_size: int, color: Color) -> void:
	var label := Locale.text(value)
	var width := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	draw_string(_font,at-Vector2(width,0),label,HORIZONTAL_ALIGNMENT_LEFT,-1.0,font_size,color)


func _fit_font(font: Font, label: String, size_hint: int, max_width: float) -> int:
	if max_width <= 0.0: return size_hint
	var width := font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1.0,size_hint).x
	return maxi(10,floori(float(size_hint)*minf(1.0,max_width/maxf(1.0,width))))


func _draw_number(at: Vector2, value: String, font_size: int, tint: Color, right_aligned: bool, outline: int) -> void:
	# Scale one cached glyph size so a fast number burst never needs a new font atlas.
	var scale := float(font_size)/NUMBER_GLYPH_SIZE
	var width := _number_font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1.0,NUMBER_GLYPH_SIZE).x
	var origin := Vector2(-width if right_aligned else -width*0.5,0)
	draw_set_transform_matrix(_number_transform*Transform2D(0.0,Vector2.ONE*scale,0.0,at))
	if outline > 0:
		var stroke := 8 if font_size <= 34 else (4 if font_size <= 80 else 3)
		draw_string_outline(_number_font,origin,value,HORIZONTAL_ALIGNMENT_LEFT,-1,NUMBER_GLYPH_SIZE,stroke,Color(INK,tint.a*0.95))
	draw_string(_number_font,origin,value,HORIZONTAL_ALIGNMENT_LEFT,-1,NUMBER_GLYPH_SIZE,tint)
	draw_set_transform_matrix(_number_transform)


func cancel_menu_gesture() -> void:
	_ui_press_button = -1
	_ui_touch_index = -1
	_ui_slider_drag = false
	_ui_pending.clear()


func menu_pointer_down() -> bool:
	return _ui_press_button >= 0 or _ui_touch_index >= 0


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:
		cancel_menu_gesture()


func _ui_point(point: Vector2) -> Vector2:
	var local := get_global_transform_with_canvas().affine_inverse()*point
	return local*REFERENCE_SIZE/size.max(Vector2.ONE)


func _is_title_home() -> bool:
	return str(_snapshot.get("state","menu")) == "menu" and _ui_page == "home"


func _button_at(point: Vector2, buttons: Array[Dictionary]) -> int:
	var title_home := _is_title_home()
	for index in buttons.size():
		var button := buttons[index]
		if not bool(button.enabled): continue
		if title_home and _title_row_reveal(index) < 0.70: continue
		var rect := _title_row_rect(button,index) if title_home else Rect2(button.rect)
		if rect.has_point(point): return index
	return -1


func _set_menu_volume(point: Vector2) -> void:
	_ui_volume_preview = clampf((point.x-MENU_VOLUME_RECT.position.x)/MENU_VOLUME_RECT.size.x,0.0,1.0)
	ui_action.emit(&"volume",_ui_volume_preview)


func handle_menu_input(event: InputEvent) -> bool:
	var state := str(_snapshot.get("state","menu"))
	if state == "playing": return false
	if _is_title_home() and not _title_entered:
		_handle_title_gate(event)
		return true
	if bool(_snapshot.get("touch_mode",false)) and event is InputEventMouse and event.device == -1:
		return true
	var buttons := _ui_buttons()
	if event is InputEventKey:
		_handle_menu_key(event,state,buttons)
	elif event is InputEventMouseMotion:
		_move_menu_pointer(_ui_point(event.position),buttons,_ui_touch_index < 0)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and _ui_touch_index < 0:
		var point := _ui_point(event.position)
		if event.pressed: _press_menu_pointer(point,buttons)
		else: _release_menu_pointer(point,buttons,"click")
	elif event is InputEventScreenTouch:
		if event.canceled:
			if event.index == _ui_touch_index: cancel_menu_gesture()
		elif event.pressed and _ui_touch_index < 0:
			_ui_touch_index = event.index
			_press_menu_pointer(_ui_point(event.position),buttons)
		elif not event.pressed and event.index == _ui_touch_index:
			_ui_touch_index = -1
			_release_menu_pointer(_ui_point(event.position),buttons,"touch")
	elif event is InputEventScreenDrag and event.index == _ui_touch_index:
		_move_menu_pointer(_ui_point(event.position),buttons,false)
	return true


func _handle_title_gate(event: InputEvent) -> void:
	if not bool(_snapshot.get("menu_ready",false)): return
	var accepted := false
	if event is InputEventKey:
		accepted = event.pressed and not event.echo
	elif event is InputEventMouseButton:
		accepted = event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	elif event is InputEventScreenTouch:
		accepted = event.pressed and not event.canceled
	if not accepted: return
	_title_entered = true
	_title_age = 0.0
	_ui_focus = 0
	_ui_focus_amounts.fill(0.0)
	ui_action.emit(&"title_enter",null)
	ui_feedback.emit(&"enter")


func _handle_menu_key(event: InputEventKey, state: String, buttons: Array[Dictionary]) -> void:
	if not event.pressed: return
	var key := event.keycode
	if key == KEY_ESCAPE:
		if event.echo: return
		cancel_menu_gesture()
		if _ui_page != "home": _open_ui_page("home")
		elif state == "paused": ui_action.emit(&"resume",null)
		elif state in ["dead","won"]: ui_action.emit(&"menu",null)
		ui_feedback.emit(&"back")
		return
	if buttons.is_empty() or not _ui_pending.is_empty(): return
	if key in [KEY_TAB,KEY_UP,KEY_DOWN,KEY_W,KEY_S]:
		var step := -1 if key in [KEY_UP,KEY_W] or (key == KEY_TAB and event.shift_pressed) else 1
		_focus_menu_button(posmod(_ui_focus+step,buttons.size()))
		return
	var button: Dictionary = buttons[clampi(_ui_focus,0,buttons.size()-1)]
	if key in [KEY_LEFT,KEY_RIGHT] and str(button.kind) == "slider":
		var value := clampf(float(_setting("volume",1.0))+(0.05 if key == KEY_RIGHT else -0.05),0,1)
		ui_action.emit(&"volume",value)
	elif not event.echo and key in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE] and str(button.kind) != "slider":
		if not _is_title_home() or _title_row_reveal(_ui_focus) >= 0.70:
			_queue_ui_action(button,"key")


func _focus_menu_button(index: int) -> void:
	if _ui_focus == index: return
	_ui_focus = index
	ui_feedback.emit(&"focus")


func _move_menu_pointer(point: Vector2, buttons: Array[Dictionary], hover: bool) -> void:
	_ui_pointer = point
	if _ui_slider_drag:
		_set_menu_volume(point)
	elif hover and _ui_press_button < 0 and _ui_pending.is_empty():
		var index := _button_at(point,buttons)
		if index >= 0: _focus_menu_button(index)


func _press_menu_pointer(point: Vector2, buttons: Array[Dictionary]) -> void:
	_ui_pointer = point
	if _ui_press_button >= 0 or not _ui_pending.is_empty(): return
	_ui_press_button = _button_at(point,buttons)
	if _ui_press_button < 0: return
	_focus_menu_button(_ui_press_button)
	if str(buttons[_ui_press_button].kind) == "slider":
		_ui_slider_drag = true
		_set_menu_volume(point)


func _release_menu_pointer(point: Vector2, buttons: Array[Dictionary], activation_kind: String) -> void:
	_ui_pointer = point
	var pressed := _ui_press_button
	_ui_press_button = -1
	if _ui_slider_drag:
		_ui_slider_drag = false
		_set_menu_volume(point)
	elif pressed >= 0 and pressed == _button_at(point,buttons):
		_queue_ui_action(buttons[pressed],activation_kind)


func _queue_ui_action(button: Dictionary, activation_kind: String) -> void:
	if not _ui_pending.is_empty(): return
	var action := str(button.action)
	_ui_action_count += 1
	_ui_last_action = action
	_ui_last_activation_kind = activation_kind
	_ui_pending = {"action":action,"value":button.get("value"),"age":0.0}
	ui_feedback.emit(&"back" if action == "back" else &"click")


func _open_ui_page(page: String) -> void:
	cancel_menu_gesture()
	_ui_page = page
	_ui_focus = 0
	_ui_focus_amounts.fill(0.0)


func open_weapon_store(id: String = "") -> void:
	_open_ui_page("store")
	var weapons: Array = _snapshot.get("shop_weapons",[])
	if weapons.is_empty(): return
	for index in weapons.size():
		var weapon: Dictionary = weapons[index]
		if id.is_empty() and bool(weapon.equipped):
			_select_store_finish(str(weapon.id),str(weapon.selected_skin))
			_ui_focus = index
			return
		for finish in weapon.get("skins",[]):
			if str(finish.id) != id: continue
			_select_store_finish(str(weapon.id),id)
			_ui_focus = index
			return
	_select_store_finish(str(weapons[0].id),str(weapons[0].id))


func _select_store_finish(family: String, skin: String) -> void:
	_store_family = family
	_store_skin = skin


func _dispatch_ui_action(action: StringName, value: Variant) -> void:
	match action:
		&"settings",&"controls",&"quit_confirm": _open_ui_page(str(action))
		&"store": open_weapon_store()
		&"shop_select_weapon":
			for weapon in _snapshot.get("shop_weapons",[]):
				if str(weapon.id) == str(value):
					_select_store_finish(str(weapon.id),str(weapon.selected_skin))
					break
		&"shop_select_skin": _select_store_finish(_store_family,str(value))
		&"back": _open_ui_page("home")
		_: ui_action.emit(action,value)


func get_ui_debug_state() -> Dictionary:
	return {"page":_ui_page,"state":str(_snapshot.get("state","menu")),"reference_size":REFERENCE_SIZE,"buttons":_ui_buttons(),"pointer_down":menu_pointer_down(),"action_count":_ui_action_count,"last_action":_ui_last_action,"last_activation_kind":_ui_last_activation_kind,"pending_action":_ui_pending.get("action",""),"pending_age":_ui_pending.get("age",-1.0),"activation_delay":MENU_ACTION_DELAY,"focus":_ui_focus,"pointer":_ui_pointer,"volume_slider_rect":MENU_VOLUME_RECT,"slider_dragging":_ui_slider_drag,"menu_ready":bool(_snapshot.get("menu_ready",false)),"title_entered":_title_entered,"title_age":_title_age}
