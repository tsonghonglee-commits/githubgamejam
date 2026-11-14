class_name TouchControls
extends Control
## Every finger keeps its original role until release, even outside its button.

const REFERENCE_SIZE := Vector2(1280, 720)
const Locale = preload("res://scripts/game_locale.gd")
const CYAN := Color(0.32, 0.96, 0.86)
const AMBER := Color(1.0, 0.61, 0.27)

var game: Node
var enabled := false
var touches: Dictionary = {}
var _font: Font


func configure(owner_game: Node, active: bool) -> void:
	game = owner_game
	enabled = active
	visible = enabled
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	if enabled:
		queue_redraw()


func _safe_reference_rect() -> Rect2:
	var safe := Rect2(Vector2(24, 18), REFERENCE_SIZE - Vector2(48, 36))
	if OS.has_feature("android") or OS.has_feature("ios"):
		var native_safe := DisplayServer.get_display_safe_area()
		if native_safe.size.x > 0 and native_safe.size.y > 0:
			var inverse: Transform2D = get_viewport().get_final_transform().affine_inverse()
			var view_size := get_viewport_rect().size.max(Vector2.ONE)
			var low: Vector2 = (inverse * Vector2(native_safe.position)) * REFERENCE_SIZE / view_size
			var high: Vector2 = (inverse * Vector2(native_safe.end)) * REFERENCE_SIZE / view_size
			safe = safe.intersection(Rect2(low, high - low))
	return safe


func _reference_button_rect(action: String) -> Rect2:
	var safe := _safe_reference_rect()
	match action:
		"boost": return Rect2(safe.position.x + 12, safe.end.y - 130, 140, 112)
		"parry": return Rect2(safe.position.x + 176, safe.end.y - 132, 120, 112)
		"attack": return Rect2(safe.position.x + 318, safe.end.y - 123, 108, 104)
		"blade": return Rect2(safe.end.x - 170, safe.end.y - 135, 154, 118)
		"pause": return Rect2(safe.end.x - 92, safe.position.y + 112, 76, 76)
	return Rect2()


func get_button_rect(action: String) -> Rect2:
	var rectangle := _reference_button_rect(action)
	var factor := get_viewport_rect().size / REFERENCE_SIZE
	return Rect2(rectangle.position * factor, rectangle.size * factor)


func get_action_at(point: Vector2) -> String:
	for action in ["pause", "boost", "parry", "attack", "blade"]:
		if get_button_rect(action).has_point(point):
			return action
	if point.x > get_viewport_rect().size.x * 0.42:
		return "look"
	return "ignored"


func handle_event(event: InputEvent) -> bool:
	if not enabled:
		return false
	if event is InputEventScreenTouch:
		if event.canceled or not event.pressed:
			_release(event.index,not event.canceled)
		else:
			_press(event.index, event.position)
		return true
	if event is InputEventScreenDrag:
		var action: String = str(touches.get(event.index, "ignored"))
		if game.state != "playing":
			return true
		var family: String = game.weapon_combat.family
		if family == "heavy" and action == "blade" and game.weapon_combat.steer(event.relative):
			return true
		if (action == "blade" or (family == "dual" and action == "attack")) and game.slashing and game.left_down:
			game.mobile_drag_blade(event.relative)
		elif action == "look" and not game.slashing:
			game.mobile_look_drag(event.relative)
		return true
	return false


func _press(index: int, point: Vector2) -> void:
	if touches.has(index):
		_release(index,false)
	if game.state != "playing":
		touches[index] = "menu"
		if game.state == "paused":
			game._resume_game()
		else:
			game.training = false
			game.practice = false
			game.start_game()
		return
	var action := get_action_at(point)
	var family: String = game.weapon_combat.family
	var katana := family in ["factory", "long"]
	if (action in ["blade", "look", "parry"] or (not katana and action == "attack")) and touches.values().has(action):
		action = "ignored"
	if family == "heavy" and action == "attack": action = "ignored"
	touches[index] = action
	match action:
		"boost": game.shift_down = true
		"attack":
			if katana: game._short_slash()
			else: game.weapon_combat.button(-1,true)
		"parry":
			if katana: game._begin_guard()
			else: game.weapon_combat.touch_guard(true)
		"blade":
			if katana: game.mobile_begin_blade()
			else: game.weapon_combat.button(-1 if family == "heavy" else 1,true)
		"pause": game._pause_game()


func _release(index: int, allow_tap: bool = true) -> void:
	var action: String = str(touches.get(index, "ignored"))
	touches.erase(index)
	var family: String = game.weapon_combat.family
	var katana := family in ["factory", "long"]
	match action:
		"boost": game.shift_down = touches.values().has("boost")
		"attack":
			if not katana: _release_weapon_button(-1,allow_tap)
		"blade":
			if katana: game.mobile_end_blade()
			else: _release_weapon_button(-1 if family == "heavy" else 1,allow_tap)
		"parry":
			if katana: game._release_guard(allow_tap)
			else: game.weapon_combat.touch_guard(false,allow_tap)


func _release_weapon_button(side: int, allow_tap: bool) -> void:
	if allow_tap: game.weapon_combat.button(side,false)
	else: game.weapon_combat.cancel_button(side)


func release_all() -> void:
	touches.clear()
	if is_instance_valid(game):
		game.shift_down = false


func _draw() -> void:
	if not enabled or _font == null or game.state != "playing":
		return
	draw_set_transform(Vector2.ZERO, 0.0, size / REFERENCE_SIZE)
	var family: String = game.weapon_combat.family
	var labels := {"boost": "提速", "attack": "普攻", "parry": "振刀", "blade": "按住斩击", "pause": "暂停"}
	var actions := ["boost", "parry", "attack", "blade", "pause"]
	var blade_hint := "拖动操刀"
	var hint := "右侧空白拖动转头 · 按住斩击后拖动操刀"
	if family in ["dual", "heavy"]: labels.parry = "格挡"
	match family:
		"dual":
			labels.attack = "左剑"
			labels.blade = "右剑"
			blade_hint = "长按可拖切"
			hint = "双剑同时按下可交叉格挡"
		"heavy":
			labels.blade = "蓄力"
			actions.erase("attack")
			blade_hint = "拖动预览刀线"
			hint = "拖动预览刀线 · 满蓄释放剑气"
	for action in actions:
		var rectangle := _reference_button_rect(action)
		var pressed := touches.values().has(action)
		var accent: Color = AMBER if action == "parry" else CYAN
		draw_style_box(_button_style(accent, pressed), rectangle)
		var label: String = Locale.text(labels[action])
		var font_size: int = 23 if action != "pause" else 19
		var label_width := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if label_width > rectangle.size.x - 18.0:
			font_size = maxi(11, floori(font_size * (rectangle.size.x - 18.0) / label_width))
			label_width = _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(_font, rectangle.get_center() + Vector2(-label_width * 0.5, 8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.94, 1, 1))
		var button_hint := blade_hint if action == "blade" else ("持续按住" if action == "boost" else "")
		if not button_hint.is_empty():
			var localized_hint := Locale.text(button_hint)
			var hint_width := minf(rectangle.size.x - 16.0, _font.get_string_size(localized_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x)
			draw_string(_font, rectangle.get_center() + Vector2(-hint_width * 0.5, 32), localized_hint, HORIZONTAL_ALIGNMENT_LEFT, hint_width, 13, Color(accent, 0.85))
	var safe := _safe_reference_rect()
	draw_string(_font, Vector2(500, safe.end.y - 20), Locale.text(hint), HORIZONTAL_ALIGNMENT_LEFT, safe.end.x - 685.0, 14, Color(CYAN, 0.7))
	draw_set_transform(Vector2.ZERO)


func _button_style(accent: Color, pressed: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent, 0.24) if pressed else Color(0.02, 0.05, 0.065, 0.72)
	style.border_color = Color(accent, 1.0 if pressed else 0.55)
	style.set_border_width_all(2 if pressed else 1)
	style.set_corner_radius_all(17)
	return style
