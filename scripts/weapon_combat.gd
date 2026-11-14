extends RefCounted
## Input for paired blades and heavy charging. Damage and guard use the run's rules.

const CHORD_WINDOW := 0.05
const HAND_RECOVERY := 0.14
const HEAVY_CHARGE_SECONDS := 0.38
const HEAVY_BUFFER_SECONDS := 0.13


var family := "factory"
var hand := 1
var charge := 0.0
var _game: Node
var _buttons := Vector2i.ZERO
var _chord := false
var _pending_hand := 0
var _pending_age := 0.0
var _held_hand := 0
var _left_recovery := 0.0
var _right_recovery := 0.0
var _charging := false
var _heavy_buffer := 0.0
var _heavy_contact_time := -1.0
var _heavy_contact_charge := 0.0
var _heavy_aim := Vector2(0.46,-0.89).normalized()
var _heavy_drag := Vector2.ZERO


func configure(game: Node, finish: Dictionary) -> void:
	_game = game
	family = str(finish.get("family","factory"))
	_game.sword.set_weapon_finish(finish)
	reset()


func reset() -> void:
	_buttons = Vector2i.ZERO
	_chord = false
	_pending_hand = 0
	_pending_age = 0.0
	_held_hand = 0
	_left_recovery = 0.0
	_right_recovery = 0.0
	_cancel_charge()
	_heavy_contact_time = -1.0
	hand = 1
	if _game != null and family == "dual":
		_game.sword.select_weapon_hand(hand)


func button(side: int, pressed: bool) -> void:
	var axis := 0 if side == -1 else 1
	if bool(_buttons[axis]) == pressed:
		return
	_buttons[axis] = int(pressed)
	match family:
		"dual": _dual_input(side,pressed)
		"heavy": _heavy_input(side,pressed)


func cancel_button(side: int) -> void:
	_buttons[0 if side == -1 else 1] = 0
	if side == _pending_hand: _pending_hand = 0
	if side == _held_hand:
		_held_hand = 0
		_game._release_blade_input()
	if _chord or (side == 1 and family == "heavy"):
		_game._release_guard(false)
	if _buttons == Vector2i.ZERO: _chord = false
	if family == "heavy" and side == -1: _cancel_charge()


func steer(movement: Vector2) -> bool:
	if not _charging and _heavy_buffer <= 0.0:
		return false
	_heavy_drag = (_heavy_drag*0.75+movement).limit_length(110.0)
	if _heavy_drag.length_squared() >= 25.0:
		_heavy_aim = _heavy_drag.normalized()
	return true


func heavy_preview(viewport_size: Vector2) -> PackedVector2Array:
	if not _charging:
		return PackedVector2Array()
	return _game.sword.get_heavy_preview_path(_heavy_aim,viewport_size)


func update(real_delta: float) -> void:
	_left_recovery = maxf(0.0,_left_recovery-real_delta)
	_right_recovery = maxf(0.0,_right_recovery-real_delta)
	if _pending_hand != 0:
		_pending_age += real_delta
		if _pending_age >= CHORD_WINDOW:
			_commit_dual_press(true)
	if _charging:
		charge = minf(1.0,charge+real_delta/HEAVY_CHARGE_SECONDS)
		_game.sword.set_weapon_charge(charge,_heavy_aim)
	elif _heavy_buffer > 0.0:
		_heavy_buffer = maxf(0.0,_heavy_buffer-real_delta)
		if _game.sword_time <= 0.0 and _buttons.y == 0:
			var held := _buttons.x != 0
			_heavy_buffer = 0.0
			if held: _start_heavy_charge()
			else: _release_heavy(0.0)


func resolve_heavy_contact(real_delta: float) -> void:
	if _heavy_contact_time < 0.0:
		return
	_heavy_contact_time -= real_delta
	if _heavy_contact_time > 0.0:
		return
	_heavy_contact_time = -1.0
	_game.sword.snap_heavy_contact()
	_game._heavy_slash(_heavy_aim,_heavy_contact_charge)


func touch_guard(pressed: bool, allow_tap: bool = true) -> void:
	if not pressed:
		_game._release_guard(allow_tap)
		return
	_pending_hand = 0
	_held_hand = 0
	_cancel_charge()
	_heavy_contact_time = -1.0
	_game._begin_guard()


func _dual_input(side: int, pressed: bool) -> void:
	if _chord:
		if not pressed:
			_game._release_guard()
			if _buttons == Vector2i.ZERO:
				_chord = false
		return
	if pressed and _buttons == Vector2i.ONE:
		_chord = true
		_pending_hand = 0
		_held_hand = 0
		_game._begin_guard()
		return
	if pressed:
		_pending_hand = side
		_pending_age = 0.0
	elif side == _pending_hand:
		_commit_dual_press(false)
	elif side == _held_hand:
		_held_hand = 0
		_game._release_blade_input()


func _commit_dual_press(held: bool) -> void:
	var side := _pending_hand
	_pending_hand = 0
	if (side == -1 and _left_recovery > 0.0) or (side == 1 and _right_recovery > 0.0):
		return
	if side == -1:
		_left_recovery = HAND_RECOVERY
	else:
		_right_recovery = HAND_RECOVERY
	hand = side
	_game.sword.select_weapon_hand(hand)
	if held:
		_held_hand = side
		_game.left_down = true
		_game.left_time = _pending_age
		_game.press_drag = Vector2.ZERO
	_game._short_slash()


func _heavy_input(side: int, pressed: bool) -> void:
	if side == 1:
		if pressed:
			_cancel_charge()
			_heavy_contact_time = -1.0
			_game._begin_guard()
		else:
			_game._release_guard()
	elif pressed:
		if _buttons.y != 0 or _game.sword_time > HEAVY_BUFFER_SECONDS:
			return
		_heavy_drag = Vector2.ZERO
		_heavy_aim = Vector2(0.46,-0.89).normalized()
		if _game.sword_time <= 0.0:
			_start_heavy_charge()
		else:
			_heavy_buffer = HEAVY_BUFFER_SECONDS
	elif _charging:
		var swing_power := charge
		_cancel_charge()
		_release_heavy(swing_power)


func _start_heavy_charge() -> void:
	_game._release_guard(false)
	_charging = true
	_game.sword.set_weapon_charge(0.01,_heavy_aim)


func _release_heavy(strength: float) -> void:
	_game._release_guard(false)
	_heavy_contact_charge = strength
	_heavy_contact_time = lerpf(0.055,0.095,strength)
	_game.sword_time = lerpf(0.25,0.35,strength)
	_game.sword.play_heavy_slash(_heavy_aim,strength)


func _cancel_charge() -> void:
	_charging = false
	_heavy_buffer = 0.0
	charge = 0.0
	if _game != null and family == "heavy":
		_game.sword.set_weapon_charge(0.0,_heavy_aim)
