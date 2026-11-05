class_name KatanaView
extends Node3D

signal animation_event(event: StringName, intensity: float)

const GRIP_POINT := Vector3(0.0, -0.11, 0.0)
const EDGE_BASE := Vector3(0.0, 0.025, 0.0)
const EDGE_TIP := Vector3(0.0, 0.86, 0.0)
const ACTIVE_CUT_POINT := Vector3(0.0, 0.52, 0.0)
const HELD_DEPTH := 1.22
const DEFAULT_BLADE_AXIS := Vector2(0.38, -0.925)
const AXIS_RESPONSE_DISTANCE := 52.0
const SLASH_RECOVERY_TIME := 0.23
const SHEATHE_TIME := 0.44
const SHEATHE_INSERT_TIME := 0.27
const FOREARM := Vector3(0.025, 0.105, -0.285)
const LIGHT_SLASHES: Array[Dictionary] = [
	{
		"id": 0, "name": "右落袈裟", "swing": Vector2(205, 156), "duration": 0.28,
		"lean": Vector2(0.20, -0.18), "depth": 1.00, "times": Vector3(0.026, 0.068, 0.155),
		"arcs": [Vector3(0.15, -0.10, -0.07), Vector3(0.38, -0.23, 0.02), Vector3(0.30, -0.25, 0.03)],
		"wrists": [Vector3(-0.12, 0.12, -0.38), Vector3(-0.28, 0.34, -0.94), Vector3(-0.10, 0.20, -0.70)],
		"ready": Vector3(0.30, -0.34, -1.06), "ready_angles": Vector3(0.12, -0.14, -1.16), "elbow": Vector3(0.12, 0.18, -0.32),
	},
	{
		"id": 1, "name": "左逆上挑", "swing": Vector2(-208, -164), "duration": 0.30,
		"lean": Vector2(-0.18, 0.24), "depth": 1.04, "times": Vector3(0.028, 0.074, 0.170),
		"arcs": [Vector3(-0.14, 0.14, -0.09), Vector3(-0.36, 0.32, -0.02), Vector3(-0.20, 0.27, 0.03)],
		"wrists": [Vector3(0.18, -0.14, 0.46), Vector3(0.36, -0.40, 1.10), Vector3(0.16, -0.20, 0.84)],
		"ready": Vector3(-0.28, -0.24, -1.02), "ready_angles": Vector3(-0.14, 0.18, 0.84), "elbow": Vector3(-0.18, -0.22, 0.26),
	},
	{
		"id": 2, "name": "右横一文字", "swing": Vector2(256, 0), "duration": 0.26,
		"lean": Vector2(0.08, -0.26), "depth": 0.96, "times": Vector3(0.024, 0.060, 0.145),
		"arcs": [Vector3(0.20, 0.015, -0.04), Vector3(0.51, 0.025, 0.02), Vector3(0.37, -0.08, 0.03)],
		"wrists": [Vector3(0.02, 0.26, -0.22), Vector3(-0.10, 0.56, -0.58), Vector3(-0.05, 0.30, -0.38)],
		"ready": Vector3(0.29, -0.31, -1.08), "ready_angles": Vector3(0.02, -0.14, -1.47), "elbow": Vector3(0.02, 0.30, -0.45),
	},
	{
		"id": 3, "name": "正面纵劈", "swing": Vector2(0, 256), "duration": 0.32,
		"lean": Vector2(0.28, 0.04), "depth": 1.03, "times": Vector3(0.030, 0.076, 0.185),
		"arcs": [Vector3(0.025, -0.20, -0.10), Vector3(0.055, -0.49, 0.025), Vector3(0.11, -0.36, 0.05)],
		"wrists": [Vector3(-0.28, 0.02, 0.05), Vector3(-0.66, 0.08, 0.13), Vector3(-0.30, 0.06, 0.33)],
		"ready": Vector3(0.17, -0.37, -1.12), "ready_angles": Vector3(-0.22, 0.08, 2.12), "elbow": Vector3(0.32, 0.04, 0.0),
	},
	{
		"id": 4, "name": "低位右挑", "swing": Vector2(146, -226), "duration": 0.30,
		"lean": Vector2(-0.26, -0.20), "depth": 1.06, "times": Vector3(0.029, 0.074, 0.178),
		"arcs": [Vector3(0.10, 0.16, -0.12), Vector3(0.29, 0.37, -0.04), Vector3(0.34, 0.18, 0.03)],
		"wrists": [Vector3(0.28, 0.06, -0.34), Vector3(0.50, 0.26, -0.84), Vector3(0.22, 0.14, -1.18)],
		"ready": Vector3(0.30, -0.20, -1.02), "ready_angles": Vector3(0.22, -0.20, -0.65), "elbow": Vector3(-0.28, 0.10, -0.18),
	},
	{
		"id": 5, "name": "左横回切", "swing": Vector2(-256, 0), "duration": 0.27,
		"lean": Vector2(-0.08, 0.32), "depth": 0.98, "times": Vector3(0.025, 0.064, 0.153),
		"arcs": [Vector3(-0.19, -0.045, -0.10), Vector3(-0.48, -0.065, -0.03), Vector3(-0.32, -0.15, 0.05)],
		"wrists": [Vector3(0.12, -0.32, 0.18), Vector3(0.23, -0.66, 0.52), Vector3(0.10, -0.28, 0.80)],
		"ready": Vector3(-0.29, -0.28, -1.10), "ready_angles": Vector3(-0.10, 0.18, 1.31), "elbow": Vector3(-0.04, -0.40, 0.32),
	},
	{
		"id": 6, "name": "左落斜斩", "swing": Vector2(-178, 210), "duration": 0.295,
		"lean": Vector2(0.32, 0.16), "depth": 1.07, "times": Vector3(0.027, 0.070, 0.169),
		"arcs": [Vector3(-0.14, -0.16, -0.05), Vector3(-0.36, -0.35, 0.04), Vector3(-0.23, -0.30, 0.07)],
		"wrists": [Vector3(-0.22, -0.10, 0.36), Vector3(-0.47, -0.27, 0.91), Vector3(-0.14, -0.24, 1.20)],
		"ready": Vector3(-0.30, -0.36, -1.13), "ready_angles": Vector3(0.18, 0.12, 1.78), "elbow": Vector3(0.26, -0.18, 0.40),
	},
	{
		"id": 7, "name": "逆风纵挑", "swing": Vector2(0, -256), "duration": 0.32,
		"lean": Vector2(-0.30, -0.05), "depth": 1.08, "times": Vector3(0.030, 0.078, 0.192),
		"arcs": [Vector3(-0.02, 0.18, -0.14), Vector3(-0.06, 0.43, -0.07), Vector3(-0.14, 0.28, 0.02)],
		"wrists": [Vector3(0.26, -0.04, -0.08), Vector3(0.64, -0.13, -0.24), Vector3(0.25, -0.08, -0.52)],
		"ready": Vector3(-0.16, -0.21, -1.05), "ready_angles": Vector3(-0.20, -0.12, 0.30), "elbow": Vector3(-0.32, -0.04, 0.08),
	},
	{
		"id": 8, "name": "浅角掠切", "swing": Vector2(246, -74), "duration": 0.25,
		"lean": Vector2(0.05, -0.38), "depth": 0.93, "times": Vector3(0.024, 0.062, 0.140),
		"arcs": [Vector3(0.22, 0.08, -0.12), Vector3(0.47, 0.16, -0.10), Vector3(0.25, 0.12, 0.04)],
		"wrists": [Vector3(0.10, 0.28, -0.28), Vector3(0.28, 0.62, -0.68), Vector3(0.08, 0.26, -0.92)],
		"ready": Vector3(0.28, -0.23, -0.98), "ready_angles": Vector3(0.06, -0.32, -0.96), "elbow": Vector3(-0.06, 0.38, -0.30),
	},
	{
		"id": 9, "name": "低位扫切", "swing": Vector2(-244, 82), "duration": 0.285,
		"lean": Vector2(0.18, 0.30), "depth": 1.05, "times": Vector3(0.027, 0.068, 0.164),
		"arcs": [Vector3(-0.18, -0.07, 0.02), Vector3(-0.43, -0.22, 0.12), Vector3(-0.25, -0.23, 0.08)],
		"wrists": [Vector3(-0.12, -0.28, 0.34), Vector3(-0.30, -0.54, 0.88), Vector3(-0.18, -0.18, 1.32)],
		"ready": Vector3(-0.24, -0.37, -1.05), "ready_angles": Vector3(0.15, 0.28, 1.62), "elbow": Vector3(0.16, -0.32, 0.34),
	},
	{
		"id": 10, "name": "折腕陡落", "swing": Vector2(82, 244), "duration": 0.31,
		"lean": Vector2(0.38, -0.24), "depth": 1.10, "times": Vector3(0.030, 0.076, 0.181),
		"arcs": [Vector3(0.09, -0.20, -0.12), Vector3(0.13, -0.46, 0.01), Vector3(-0.03, -0.30, 0.06)],
		"wrists": [Vector3(-0.32, 0.18, -0.18), Vector3(-0.78, 0.38, -0.70), Vector3(-0.30, 0.14, -1.32)],
		"ready": Vector3(-0.14, -0.34, -1.14), "ready_angles": Vector3(0.18, -0.24, -2.00), "elbow": Vector3(0.40, 0.12, -0.14),
	},
	{
		"id": 11, "name": "绕腕弧回", "swing": Vector2(192, -168), "duration": 0.32,
		"lean": Vector2(-0.16, 0.28), "depth": 0.99, "times": Vector3(0.030, 0.078, 0.190),
		"arcs": [Vector3(0.15, 0.12, -0.11), Vector3(0.31, 0.27, 0.01), Vector3(-0.10, 0.08, 0.10)],
		"wrists": [Vector3(0.18, -0.22, -0.58), Vector3(0.44, -0.42, -1.48), Vector3(-0.16, 0.22, -2.42)],
		"ready": Vector3(-0.26, -0.31, -1.08), "ready_angles": Vector3(-0.18, 0.26, 1.16), "elbow": Vector3(-0.14, -0.24, -0.28),
	},
]

var _scabbard: Node3D
var _handle: Node3D
var _drawn: Node3D
var _mode := "sheathed"
var _progress := 0.0
var _stroke := Vector2.ZERO
var _action_time := 0.0
var _elapsed := 0.0
var _swing_direction := Vector2(1.0, -0.45)
var _motion_direction := Vector2.RIGHT
var _motion_energy := 0.0
var _motion_offset := Vector2.ZERO
var _has_cut_direction := false
var _snap_held_pose := false
var _recoil := Vector3.ZERO
var _recoil_velocity := Vector3.ZERO
var _recoil_angle := Vector3.ZERO
var _recoil_angular_velocity := Vector3.ZERO
var _contact_energy := 0.0
var _contact_parried := false
var _trail: MeshInstance3D
var _trail_material: StandardMaterial3D
var _trail_samples: Array[Dictionary] = []
var _contact_flash: MeshInstance3D
var _flash_material: StandardMaterial3D
var _camera: Camera3D
var _grip_axis := DEFAULT_BLADE_AXIS.normalized()
var _energy_arc: MeshInstance3D
var _energy_material: StandardMaterial3D
var _edge_material: StandardMaterial3D
var _blade_face_material: StandardMaterial3D
var _action_from := Transform3D.IDENTITY
var _slash_keys: Array[Dictionary] = []
var _guard_keys: Array[Dictionary] = []
var _sheathing := false
var _sheathe_time := 0.0
var _sheathe_from := Transform3D.IDENTITY
var _parry_reacting := false
var _parry_reaction_time := 0.0
var _parry_contact_from := Transform3D.IDENTITY
var _held_depth := HELD_DEPTH
var _held_tilt := -0.26
var _held_rest_roll := 0.0
var _held_twist := 0.0
var _held_twist_velocity := 0.0
var _adopted_held_pose := false
var _last_grip := Vector2.ZERO
var _animation_phase := "docked"
var _draw_connection: PackedVector3Array = []
var _held_whoosh_distance := 0.0
var _last_held_whoosh := -1.0
var _scabbard_drop := 0.0
var _slash_predecessor := Transform3D.IDENTITY
var _slash_inheritance := 0.0
var _combo_ordinal := 0
var _light_slash_style := -1
var _light_slash_duration := SLASH_RECOVERY_TIME
var _light_slash_times := Vector3(0.032, 0.076, 0.145)
var _slash_contact_hold := 0.0
var _slash_contact_drag_elapsed := 0.0
var _held_turn_sign := 1.0


func _ready() -> void:
	_camera = get_parent() as Camera3D
	var steel := _material(Color(0.66, 0.75, 0.79), 0.85, 0.23)
	var dark := _material(Color(0.022, 0.03, 0.039), 0.6, 0.32)
	var sheath_material := _material(Color(0.31, 0.045, 0.035), 0.7, 0.27)
	var glow := _material(Color(0.51, 0.97, 0.94), 0.35, 0.18, true)
	_edge_material = glow
	_scabbard = Node3D.new()
	add_child(_scabbard)
	_scabbard.position = Vector3(0.47, -0.26, -0.76)
	_scabbard.rotation = Vector3(0.03, -0.12, 0.72)
	_box(_scabbard, Vector3(0.075, 0.89, 0.042), Vector3(0, -0.455, 0), sheath_material)
	_box(_scabbard, Vector3(0.081, 0.029, 0.049), Vector3(0, -0.024, 0), steel)
	_box(_scabbard, Vector3(0.078, 0.022, 0.045), Vector3(0, -0.89, 0), steel)
	_box(_scabbard, Vector3(0.013, 0.75, 0.003), Vector3(0.025, -0.445, 0.024), dark)
	for index in range(3):
		_box(_scabbard, Vector3(0.061, 0.014, 0.037), Vector3(0, -0.16 - index * 0.2, 0), dark)
	_handle = Node3D.new()
	_scabbard.add_child(_handle)
	# One physical katana stays visible throughout drawing and sheathing. The
	# empty legacy handle node is retained for scene/tool compatibility only.
	_handle.visible = false
	_drawn = Node3D.new()
	add_child(_drawn)
	_make_grip(_drawn, -1.0, steel, dark, glow)
	var blade := MeshInstance3D.new()
	blade.mesh = _blade_mesh()
	_blade_face_material = _material(Color(0.43, 0.53, 0.58), 0.92, 0.26)
	blade.set_surface_override_material(0, _blade_face_material)
	blade.set_surface_override_material(1, _material(Color(0.78, 0.85, 0.86), 0.86, 0.14))
	blade.set_surface_override_material(2, _material(Color(0.065, 0.10, 0.12), 0.72, 0.40))
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drawn.add_child(blade)
	_edge_material = _material(Color(0.18, 0.57, 0.65), 0.75, 0.19, true)
	var edge := _box(_drawn, Vector3(0.0018, 0.72, 0.002), Vector3(-0.018, 0.36, 0), _edge_material)
	edge.rotation.z = -0.018
	# The short mark identifies the one contact point used by continuous cuts.
	_box(_drawn, Vector3(0.043, 0.009, 0.015), ACTIVE_CUT_POINT, glow)
	_box(_drawn, Vector3(0.012, 0.055, 0.019), Vector3(0, 0.048, 0), dark)
	_drawn.transform = _dock_transform()
	_trail = MeshInstance3D.new()
	_trail.name = "BladeAfterimage"
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_material = StandardMaterial3D.new()
	_trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_material.vertex_color_use_as_albedo = true
	_trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_material.no_depth_test = false
	_trail.material_override = _trail_material
	add_child(_trail)
	_contact_flash = MeshInstance3D.new()
	_contact_flash.name = "BladeContact"
	_contact_flash.mesh = _contact_spark_mesh()
	_flash_material = StandardMaterial3D.new()
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flash_material.no_depth_test = true
	_contact_flash.material_override = _flash_material
	_contact_flash.visible = false
	add_child(_contact_flash)
	_energy_arc = MeshInstance3D.new()
	_energy_arc.name = "BladeIonFilaments"
	_energy_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_energy_material = StandardMaterial3D.new()
	_energy_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_energy_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_energy_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_energy_arc.material_override = _energy_material
	_energy_arc.visible = false
	add_child(_energy_arc)


func set_pose(mode: String, progress: float = 0.0, stroke: Vector2 = Vector2.ZERO) -> void:
	if mode != _mode:
		_slash_contact_hold = 0.0
		var previous_mode := _mode
		var from_scabbard := previous_mode == "sheathed" and (not _sheathing or _sheathe_time >= 0.35)
		_action_from = _drawn.transform
		_action_time = 0.0
		_trail_samples.clear()
		_draw_connection.clear()
		if previous_mode == "parry":
			animation_event.emit(&"guard_release", 0.75)
		match mode:
			"held":
				if not _adopted_held_pose:
					adopt_current_held_pose(get_viewport().get_visible_rect().size)
				_adopted_held_pose = false
				_sheathing = false
				_parry_reacting = false
				_held_twist = 0.0
				_held_twist_velocity = 0.0
			"parry":
				_sheathing = false
				_parry_reacting = false
				_guard_keys = _make_guard_keys(_action_from)
				animation_event.emit(&"guard_raise", 1.0)
				if from_scabbard:
					animation_event.emit(&"unsheathe", 0.75)
			"sheathed":
				_sheathing = true
				_sheathe_time = 0.0
				_sheathe_from = _action_from
				_motion_energy = 0.0
				_has_cut_direction = false
	_mode = mode
	_progress = clampf(progress, 0.0, 1.0)
	_stroke = stroke.limit_length(1.0)


func get_light_slash_count() -> int:
	return LIGHT_SLASHES.size()


func get_light_slash_definition(index: int) -> Dictionary:
	return LIGHT_SLASHES[posmod(index, LIGHT_SLASHES.size())].duplicate(true)


func play_slash(direction: Vector2 = Vector2(1.0, -0.45), style_index: int = -1) -> void:
	# Immediate gameplay contact and the physical metal agree in the input frame.
	# A narrow unsheathe streak connects the prior pose; it never deals damage.
	var previous := _drawn.transform
	var from_scabbard := _mode == "sheathed" and (not _sheathing or _sheathe_time >= 0.35)
	var continuing := _mode == "slash" or (_mode == "sheathed" and _sheathing and _sheathe_time < SHEATHE_INSERT_TIME)
	_slash_predecessor = previous
	_slash_inheritance = 0.18 if continuing else 0.0
	_combo_ordinal = _combo_ordinal + 1 if continuing else 0
	if _mode == "parry":
		animation_event.emit(&"guard_release", 0.75)
	_mode = "slash"
	_progress = 0.0
	_action_time = 0.0
	_slash_contact_hold = 0.0
	_slash_contact_drag_elapsed = 0.0
	_sheathing = false
	_parry_reacting = false
	_adopted_held_pose = false
	_light_slash_style = posmod(style_index if style_index >= 0 else _light_slash_style + 1, LIGHT_SLASHES.size())
	var definition := get_light_slash_definition(_light_slash_style)
	_light_slash_duration = float(definition.duration)
	_light_slash_times = definition.times
	_swing_direction = direction.normalized() if direction.length_squared() > 0.001 else Vector2(definition.swing).normalized()
	_motion_energy = 1.0
	_slash_keys = _make_slash_keys()
	_drawn.transform = _sample_arm_keys(_slash_keys, 0.0)
	_animation_phase = "draw_contact"
	_draw_connection.clear()
	var mouth := _scabbard.transform * Vector3(0.0, -0.015, 0.018)
	var before := mouth if from_scabbard else previous * ACTIVE_CUT_POINT
	var contact := _drawn.transform * ACTIVE_CUT_POINT
	var control := mouth if from_scabbard else before.lerp(contact, 0.4) + Vector3(0.0, -0.03, -0.06)
	for index in range(10):
		var weight := float(index) / 9.0
		_draw_connection.append(before.bezier_interpolate(control, control.lerp(contact, 0.6), contact, weight))
	_trail_samples.clear()
	_trail_samples.append({"point": contact, "age": 0.0})
	if from_scabbard:
		animation_event.emit(&"unsheathe", 1.0)
	animation_event.emit(&"blade_whoosh", 0.90 + float(_light_slash_style % 4) * 0.06)


func get_light_slash_cut_path(viewport_size: Vector2) -> PackedVector2Array:
	# This finite piece of the physical edge is already at the aim point in
	# the input frame. No independent diagonal or projected sweep area deals
	# damage, and every authored contact angle therefore cuts where it shows.
	var canvas_size := get_viewport().get_visible_rect().size.max(Vector2.ONE)
	var path := PackedVector2Array()
	for height in [0.24, 0.37, ACTIVE_CUT_POINT.y, 0.65, 0.78]:
		path.append(_camera.unproject_position(_drawn.to_global(Vector3(0.0, height, 0.0))) * viewport_size / canvas_size)
	return path


func stroke_motion(from: Vector2, to: Vector2, viewport_size: Vector2) -> void:
	var motion := to - from
	if motion.length_squared() < 0.0001:
		return
	_motion_direction = motion.normalized()
	set_grip_motion(to, resolve_blade_axis(_grip_axis, motion), motion.length(), viewport_size)


func resolve_blade_axis(previous_axis: Vector2, motion: Vector2) -> Vector2:
	var axis := previous_axis.normalized() if previous_axis.length_squared() > 0.0001 else DEFAULT_BLADE_AXIS.normalized()
	var travel := motion.length()
	if travel < 0.000001:
		return axis
	# The cursor holds the hilt, which leads into the gesture; the blade tip
	# trails behind it. This is a directed heading, not an unoriented cutting
	# line: reversing the hand must turn the actual katana through 180 degrees.
	var desired := -motion / travel
	var response := 1.0 - exp(-travel / AXIS_RESPONSE_DISTANCE)
	var angle := wrapf(desired.angle() - axis.angle(), -PI, PI)
	if absf(absf(angle) - PI) < 0.00001:
		angle = PI * _held_turn_sign
	return axis.rotated(angle * response).normalized()


func adopt_current_held_pose(viewport_size: Vector2) -> Dictionary:
	# Keep the live wrist, screen axis and 3D lean on mode entry. Never stand the
	# blade upright or move its grip back to a guessed screen-centre position.
	var grip_camera := _drawn.transform * GRIP_POINT
	_held_depth = clampf(-grip_camera.z, 0.68, 2.5)
	_held_tilt = clampf(_drawn.basis.y.z, -0.80, 0.80)
	var canvas_size := get_viewport().get_visible_rect().size.max(Vector2.ONE)
	var scale_to_view := viewport_size / canvas_size
	var grip := _camera.unproject_position(_drawn.to_global(GRIP_POINT)) * scale_to_view
	var tip := _camera.unproject_position(_drawn.to_global(EDGE_TIP)) * scale_to_view
	_grip_axis = (tip - grip).normalized()
	_held_rest_roll = 0.0
	var base := transform_for_grip(grip, _grip_axis, viewport_size).basis
	_held_rest_roll = atan2(-base.z.dot(_drawn.basis.x), base.x.dot(_drawn.basis.x)) - (_recoil_angle.z + _recoil_angle.x) * 1.35
	_last_grip = grip
	_adopted_held_pose = true
	return {"grip": grip, "axis": _grip_axis, "contact": _camera.unproject_position(_drawn.to_global(ACTIVE_CUT_POINT)) * scale_to_view}


func set_grip_motion(grip: Vector2, direction: Vector2, travel_pixels: float, viewport_size: Vector2) -> void:
	var previous_axis := _grip_axis
	if direction.length_squared() > 0.0001:
		_grip_axis = direction.normalized()
	var motion := grip - _last_grip
	if motion.length_squared() > 0.0001:
		_motion_direction = motion.normalized()
	_last_grip = grip
	_has_cut_direction = true
	_motion_energy = maxf(_motion_energy, clampf(travel_pixels / maxf(viewport_size.y * 0.04, 1.0), 0.0, 1.0))
	_stroke = grip / viewport_size.max(Vector2.ONE) - Vector2(0.5, 0.5)
	var turn := wrapf(_grip_axis.angle() - previous_axis.angle(), -PI, PI)
	if absf(turn) > 0.00001:
		_held_turn_sign = signf(turn)
	_held_twist_velocity += clampf(turn * 5.0 + motion.x / maxf(viewport_size.x, 1.0) * 1.4, -1.1, 1.1)
	_held_whoosh_distance += travel_pixels
	if travel_pixels > 0.0 and _held_whoosh_distance > viewport_size.y * 0.105 and _elapsed - _last_held_whoosh > 0.095:
		animation_event.emit(&"blade_whoosh", clampf(_held_whoosh_distance / maxf(viewport_size.y * 0.24, 1.0), 0.3, 1.0))
		_held_whoosh_distance = 0.0
		_last_held_whoosh = _elapsed
	if _mode == "held" and is_instance_valid(_drawn):
		_apply_held_pose(viewport_size)


func transform_for_grip(grip: Vector2, direction: Vector2, viewport_size: Vector2) -> Transform3D:
	var axis := direction.normalized() if direction.length_squared() > 0.0001 else DEFAULT_BLADE_AXIS.normalized()
	var canvas_size := get_viewport().get_visible_rect().size.max(Vector2.ONE)
	var scale_to_canvas := canvas_size / viewport_size.max(Vector2.ONE)
	var ray := _camera.project_local_ray_normal(grip * scale_to_canvas)
	var anchor := ray * (_held_depth / maxf(-ray.z, 0.001))
	var next_ray := _camera.project_local_ray_normal((grip + axis * 64.0) * scale_to_canvas)
	var next_anchor := next_ray * (_held_depth / maxf(-next_ray.z, 0.001))
	var plane_axis := (next_anchor - anchor).normalized()
	# Compensate perspective so a real forward-leaning 3D blade still projects
	# onto the exact requested screen axis, including far from screen centre.
	var perspective := Vector3(-anchor.x * _held_tilt / _held_depth, -anchor.y * _held_tilt / _held_depth, _held_tilt)
	var projection := plane_axis.dot(perspective)
	var length_scale := -projection + sqrt(maxf(0.001, projection * projection + 1.0 - perspective.length_squared()))
	var blade_axis := (plane_axis * length_scale + perspective).normalized()
	var side := blade_axis.cross(Vector3.BACK).normalized()
	var normal := side.cross(blade_axis).normalized()
	var basis := Basis(side, blade_axis, normal) * Basis(Vector3.UP, _held_rest_roll)
	return Transform3D(basis, anchor - basis * GRIP_POINT)


func blade_segment_for_grip(grip: Vector2, direction: Vector2, viewport_size: Vector2) -> PackedVector2Array:
	var pose := transform_for_grip(grip, direction, viewport_size)
	var canvas_size := get_viewport().get_visible_rect().size.max(Vector2.ONE)
	var scale_to_view := viewport_size / canvas_size
	return PackedVector2Array([
		_camera.unproject_position(_camera.to_global(pose * EDGE_BASE)) * scale_to_view,
		_camera.unproject_position(_camera.to_global(pose * EDGE_TIP)) * scale_to_view,
	])


func active_cut_point_for_grip(grip: Vector2, direction: Vector2, viewport_size: Vector2) -> Vector2:
	var pose := transform_for_grip(grip, direction, viewport_size)
	var canvas_size := get_viewport().get_visible_rect().size.max(Vector2.ONE)
	return _camera.unproject_position(_camera.to_global(pose * ACTIVE_CUT_POINT)) * viewport_size / canvas_size


func grip_for_active_cut_point(point: Vector2, direction: Vector2, viewport_size: Vector2) -> Vector2:
	# Perspective is not a planar UI offset. Invert the shared physical pose.
	var grip := point - (active_cut_point_for_grip(point, direction, viewport_size) - point)
	for iteration in range(7):
		var current := active_cut_point_for_grip(grip, direction, viewport_size)
		var error := current - point
		if error.length_squared() < 0.000001:
			break
		var x_step := active_cut_point_for_grip(grip + Vector2.RIGHT, direction, viewport_size) - current
		var y_step := active_cut_point_for_grip(grip + Vector2.DOWN, direction, viewport_size) - current
		var determinant := x_step.cross(y_step)
		if absf(determinant) < 0.00001:
			break
		grip -= Vector2(error.cross(y_step), x_step.cross(error)) / determinant
	return grip


func get_grip_screen_position() -> Vector2:
	return _camera.unproject_position(_drawn.to_global(GRIP_POINT))


func get_blade_screen_direction() -> Vector2:
	var tip := _camera.unproject_position(_drawn.to_global(EDGE_TIP))
	return (tip - get_grip_screen_position()).normalized()


func get_contact_world_position() -> Vector3:
	return _drawn.to_global(ACTIVE_CUT_POINT)


func get_animation_debug_state() -> Dictionary:
	var style_name := String(LIGHT_SLASHES[_light_slash_style].name) if _light_slash_style >= 0 else ""
	var screen := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var tip := _camera.unproject_position(_drawn.to_global(EDGE_TIP))
	var grip := get_grip_screen_position()
	return {"phase": _animation_phase, "mode": _mode, "action_time": _action_time, "sheathing": _sheathing, "sheathe_time": _sheathe_time, "parry_reaction": _parry_reacting, "held_depth": _held_depth, "held_tilt": _held_tilt, "twist": _held_twist, "light_slash_style": _light_slash_style, "light_slash_name": style_name, "light_slash_duration": _light_slash_duration, "held_turn_sign": _held_turn_sign, "blade_tip_offscreen": not screen.has_point(tip), "hilt_onscreen": screen.has_point(grip), "ordinary_contact_hold": _slash_contact_hold, "ordinary_contact_drag_elapsed": _slash_contact_drag_elapsed}


func impact(strength: float, parried: bool = false) -> void:
	var force := clampf(strength, 0.1, 1.6)
	var direction := _motion_direction if _mode == "held" else _swing_direction
	var recoil_scale := 0.32 if parried else 1.0
	_recoil_velocity += Vector3(-direction.x * 0.42, direction.y * 0.24, 0.48) * force * recoil_scale
	_recoil_angular_velocity += Vector3(-0.45, direction.x * 0.22, -direction.x * 0.65) * force * recoil_scale
	_contact_energy = maxf(_contact_energy, force)
	_contact_parried = parried
	if _mode == "slash" and not parried:
		# A real contact briefly loads the ordinary swing before it tears free.
		# Held precision input never waits for this visual contact resistance.
		_slash_contact_hold = maxf(_slash_contact_hold, clampf(0.018 + force * 0.008, 0.020, 0.030))
	if parried and _mode == "parry":
		_parry_reacting = true
		_parry_reaction_time = 0.0
		_parry_contact_from = _drawn.transform
		_animation_phase = "parry_contact"


func _process(delta: float) -> void:
	if _drawn == null:
		return
	var real_delta := minf(delta / maxf(Engine.time_scale, 0.001), 0.1)
	var action_delta := real_delta
	if _mode == "slash" and _slash_contact_hold > 0.0:
		var resisted := minf(real_delta, _slash_contact_hold)
		_slash_contact_hold -= resisted
		_slash_contact_drag_elapsed += resisted
		action_delta -= resisted * 0.86
	_action_time += action_delta
	_elapsed += real_delta
	_motion_energy = move_toward(_motion_energy, 0.0, real_delta * 4.0)
	# This decay affects sound only. Slow continuous precision cuts keep every
	# input point without accumulating an implausible delayed air whoosh.
	_held_whoosh_distance *= exp(-real_delta * 8.0)
	_recoil_velocity += -_recoil * (490.0 * real_delta)
	_recoil_velocity *= exp(-real_delta * 23.0)
	_recoil += _recoil_velocity * real_delta
	_recoil = _recoil.limit_length(0.065)
	_recoil_angular_velocity += -_recoil_angle * (420.0 * real_delta)
	_recoil_angular_velocity *= exp(-real_delta * 19.0)
	_recoil_angle += _recoil_angular_velocity * real_delta
	_recoil_angle = _recoil_angle.limit_length(0.13)
	_held_twist_velocity += -_held_twist * 150.0 * real_delta
	_held_twist_velocity *= exp(-real_delta * 18.0)
	_held_twist += _held_twist_velocity * real_delta
	_held_twist = clampf(_held_twist, -0.22, 0.22)
	_contact_energy = move_toward(_contact_energy, 0.0, real_delta * 14.0)
	var sway := sin(_elapsed * 5.5) * 0.004
	# The off-hand sheath lowers clear of the cutting arc. It returns before
	# the tip alignment, independently of the cursor-owned physical wrist.
	var drop_target := 0.0 if _mode == "sheathed" else 1.0
	_scabbard_drop = lerpf(_scabbard_drop, drop_target, 1.0 - exp(-real_delta * 28.0))
	_scabbard.position = Vector3(0.47 + sway + _scabbard_drop * 0.10, -0.26 + sway * 0.5 - _scabbard_drop * 0.36, -0.76)
	var pose := _drawn.transform
	match _mode:
		"slash":
			pose = _sample_arm_keys(_slash_keys, _action_time)
			_animation_phase = "draw_contact" if _action_time < _light_slash_times.x else ("follow_through" if _action_time < _light_slash_times.y else ("wrist_recovery" if _action_time < _light_slash_times.z else "ready"))
			if _slash_contact_hold > 0.0:
				_animation_phase = "contact_resistance"
		"held":
			_apply_held_pose(get_viewport().get_visible_rect().size)
			_animation_phase = "free_cut"
		"parry":
			pose = _sample_arm_keys(_guard_keys, _action_time)
			_animation_phase = "guard_intercept" if _action_time < 0.080 else ("guard_settle" if _action_time < 0.12 else "guard_ready")
			if _parry_reacting:
				_parry_reaction_time += real_delta
				pose = _parry_reaction_pose(pose, _parry_reaction_time)
				_animation_phase = "parry_compress" if _parry_reaction_time < 0.03 else ("parry_rebound" if _parry_reaction_time < 0.095 else "parry_recover")
				if _parry_reaction_time >= 0.18:
					_parry_reacting = false
		"sheathed":
			if _sheathing:
				_sheathe_time += real_delta
				pose = _sheathe_pose(_sheathe_time)
				_animation_phase = "sheathe_align" if _sheathe_time < SHEATHE_INSERT_TIME else "sheathe_insert"
				if _sheathe_time >= SHEATHE_TIME:
					_sheathing = false
					animation_event.emit(&"sheathe", 1.0)
			else:
				pose = _dock_transform()
				_animation_phase = "docked"
	if _mode != "held":
		var grip := pose * GRIP_POINT
		pose.basis = pose.basis * Basis(Quaternion.from_euler(_recoil_angle))
		pose.origin = grip + _recoil - pose.basis * GRIP_POINT
		if _mode == "slash":
			pose = _keep_hilt_adoptable(pose)
			pose = _present_slash_face(pose)
		_drawn.transform = pose
	# The broad steel face must remain readable during the very fast ordinary
	# drive. Precision-mode lighting and its exact pose are left unchanged.
	_blade_face_material.albedo_color = Color(0.64, 0.73, 0.77) if _mode == "slash" else Color(0.43, 0.53, 0.58)
	_blade_face_material.metallic = 0.68 if _mode == "slash" else 0.92
	_update_blade_trail(real_delta, _mode == "sheathed")
	_update_energy_arc(_mode == "sheathed")
	_edge_material.emission_energy_multiplier = 0.38 + _motion_energy * 0.16 + _contact_energy * 0.35
	_contact_flash.visible = _contact_energy > 0.2 and _mode != "sheathed"
	if _contact_flash.visible:
		_contact_flash.position = _drawn.transform * (ACTIVE_CUT_POINT + Vector3(0, 0, 0.012))
		_contact_flash.rotation.z += real_delta * 17.0
		_contact_flash.scale = Vector3.ONE * clampf(_contact_energy * 0.6, 0.2, 0.9)
		_flash_material.albedo_color = Color(1.0, 0.78 if _contact_parried else 0.98, 0.42 if _contact_parried else 0.95, _contact_energy * 0.32)


func _apply_held_pose(viewport_size: Vector2) -> void:
	var held := transform_for_grip((_stroke + Vector2(0.5, 0.5)) * viewport_size, _grip_axis, viewport_size)
	# Torsion changes metallic highlights but not grip / blade centreline / contact.
	held.basis = held.basis * Basis(Vector3.UP, _held_twist + (_recoil_angle.z + _recoil_angle.x) * 1.35)
	_drawn.transform = held


func _dock_transform() -> Transform3D:
	return _scabbard.transform * Transform3D(Basis(Vector3.BACK, PI), Vector3.ZERO)


func _arm_key(time: float, pose: Transform3D, elbow_angles: Vector3) -> Dictionary:
	var elbow_rotation := Quaternion.from_euler(elbow_angles)
	return {"time": time, "elbow": pose * GRIP_POINT - Basis(elbow_rotation) * FOREARM, "elbow_rotation": elbow_rotation, "wrist_rotation": elbow_rotation.inverse() * pose.basis.get_rotation_quaternion()}


func _grip_pose(grip: Vector3, rotation_angles: Vector3) -> Transform3D:
	var basis := Basis(Quaternion.from_euler(rotation_angles))
	return Transform3D(basis, grip - basis * GRIP_POINT)


func _sample_arm_keys(keys: Array[Dictionary], time: float) -> Transform3D:
	if keys.is_empty():
		return _drawn.transform
	var index := 0
	while index < keys.size() - 2 and time > float(keys[index + 1].time):
		index += 1
	var first: Dictionary = keys[index]
	var second: Dictionary = keys[mini(index + 1, keys.size() - 1)]
	var duration := maxf(float(second.time) - float(first.time), 0.0001)
	var weight := clampf((time - float(first.time)) / duration, 0.0, 1.0)
	var before: Dictionary = keys[maxi(index - 1, 0)]
	var after: Dictionary = keys[mini(index + 2, keys.size() - 1)]
	# The time-aware tangent is shared by adjacent segments. Keys shape the
	# swing instead of making it stop and re-accelerate at every authored pose.
	var first_velocity: Vector3 = (second.elbow - before.elbow) / maxf(float(second.time) - float(before.time), 0.0001)
	var second_velocity: Vector3 = (after.elbow - first.elbow) / maxf(float(after.time) - float(first.time), 0.0001)
	if index == 0 and _mode != "slash":
		first_velocity = Vector3.ZERO
	if index + 2 >= keys.size():
		second_velocity = Vector3.ZERO
	var square := weight * weight
	var cube := square * weight
	var elbow: Vector3 = first.elbow * (2.0 * cube - 3.0 * square + 1.0) + first_velocity * duration * (cube - 2.0 * square + weight) + second.elbow * (-2.0 * cube + 3.0 * square) + second_velocity * duration * (cube - square)
	var pre_time := float(before.time) - float(first.time) if index > 0 else -duration
	var post_time := float(after.time) - float(first.time) if index + 2 < keys.size() else duration * 2.0
	var upper: Quaternion = first.elbow_rotation.spherical_cubic_interpolate_in_time(second.elbow_rotation, before.elbow_rotation, after.elbow_rotation, weight, duration, pre_time, post_time).normalized()
	var wrist: Quaternion = first.wrist_rotation.spherical_cubic_interpolate_in_time(second.wrist_rotation, before.wrist_rotation, after.wrist_rotation, weight, duration, pre_time, post_time).normalized()
	var basis := Basis(upper * wrist)
	var grip := elbow + Basis(upper) * FOREARM
	return Transform3D(basis, grip - basis * GRIP_POINT)


func _make_slash_keys() -> Array[Dictionary]:
	var definition := get_light_slash_definition(_light_slash_style)
	var angle := atan2(-_swing_direction.x, -_swing_direction.y)
	var lean: Vector2 = definition.lean
	var contact_basis := Basis(Quaternion.from_euler(Vector3(lean.x, lean.y, angle)))
	if _slash_inheritance > 0.0:
		contact_basis = Basis(contact_basis.get_rotation_quaternion().slerp(_slash_predecessor.basis.get_rotation_quaternion(), _slash_inheritance))
	var depth_offset := float((_combo_ordinal % 3) - 1) * 0.024 if _slash_inheritance > 0.0 else 0.0
	var contact := Transform3D(contact_basis, Vector3(0.0, 0.0, -float(definition.depth) + depth_offset) - contact_basis * ACTIVE_CUT_POINT)
	var grip := contact * GRIP_POINT
	var elbow: Vector3 = definition.elbow
	var keys: Array[Dictionary] = [_arm_key(0.0, contact, elbow)]
	var times: Vector3 = definition.times
	var outgoing := Vector3(_swing_direction.x, -_swing_direction.y, 0.0)
	var peak: Vector3 = _wide_hand_arc(definition.arcs[1])
	peak.z = maxf(0.035, peak.z)
	var last_pose := contact
	# The main drive crosses the view in the first few frames. The shoulder
	# then brakes on the far side; it does not flip the sword back into a small
	# central display pose. Only the hilt is kept adoptable, never the blade.
	for index in range(3):
		var travel: Vector3 = _wide_hand_arc(definition.arcs[index])
		# Drive the blade across the near view rather than shrink it away from
		# the lens while the only two readable cutting frames are passing.
		if index == 0:
			travel.z = maxf(0.085, -travel.z * 0.50)
		elif index == 1:
			travel.z = maxf(0.035, travel.z)
		var wrist_delta: Vector3 = definition.wrists[index]
		wrist_delta = Vector3(wrist_delta.x * 1.18, wrist_delta.y * 1.22, clampf(wrist_delta.z * 1.30, -2.70, 2.70))
		if index == 2:
			# Take up the outgoing momentum instead of bouncing back through the
			# target. The flourish retains more of its authored winding return.
			var return_weight := 0.38 if _light_slash_style == 11 else 0.12
			travel = peak.lerp(travel, return_weight) + outgoing * 0.085 + Vector3(0.0, -0.025, 0.035)
			var peak_wrist: Vector3 = definition.wrists[1]
			peak_wrist = Vector3(peak_wrist.x * 1.18, peak_wrist.y * 1.22, peak_wrist.z * 1.30)
			wrist_delta = peak_wrist.lerp(wrist_delta, 0.40 if _light_slash_style == 11 else 0.24)
		var basis := contact_basis * Basis(Quaternion.from_euler(wrist_delta))
		var pose := Transform3D(basis, grip + travel - basis * GRIP_POINT)
		var carry: float = [0.18, 0.72, 0.80][index] if _light_slash_style != 11 else [0.16, 0.58, 0.42][index]
		pose = _carry_cut_outward(pose, outgoing, carry)
		pose = _keep_hilt_adoptable(pose, index == 2)
		pose = _present_slash_face(pose)
		var arm_rotation := elbow + Vector3(-travel.y * 1.05, travel.x * 0.90, wrist_delta.z * 0.22)
		keys.append(_arm_key(times[index], pose, arm_rotation))
		last_pose = pose
	# The wrist settles where the cut finished. A following click can inherit
	# that remote-side tension; no automatic neutral/upright reset is inserted.
	var ready := last_pose
	var side := signf(_swing_direction.x) if absf(_swing_direction.x) > 0.1 else (1.0 if _light_slash_style % 2 == 0 else -1.0)
	ready.basis = ready.basis * Basis(Quaternion.from_euler(Vector3(0.028, -side * 0.045, side * 0.055)))
	ready.origin = last_pose * GRIP_POINT + Vector3(-outgoing.x * 0.025, -0.025, 0.055) - ready.basis * GRIP_POINT
	ready = _present_slash_face(_keep_hilt_adoptable(ready, true))
	keys.append(_arm_key(float(definition.duration), ready, elbow * 0.55 + Vector3(-outgoing.y * 0.20, outgoing.x * 0.28, side * -0.28)))
	return keys


func _wide_hand_arc(arc: Vector3) -> Vector3:
	return Vector3(arc.x * 2.60, arc.y * 2.60, arc.z * 1.30)


func _carry_cut_outward(pose: Transform3D, outgoing: Vector3, weight: float) -> Transform3D:
	var grip := pose * GRIP_POINT
	var axis := pose.basis.y.normalized()
	var target := Vector3(outgoing.x, outgoing.y, clampf(axis.z, -0.30, 0.30)).normalized()
	var carried := axis.slerp(target, weight).normalized()
	pose.basis = Basis(Quaternion(axis, carried)) * pose.basis
	pose.origin = grip - pose.basis * GRIP_POINT
	return pose


func _keep_hilt_adoptable(pose: Transform3D, settled: bool = false) -> Transform3D:
	var grip := pose * GRIP_POINT
	# Do not turn a screen-filling cut into a lens-pointing stab. Excessive
	# foreshortening both loses the metal silhouette and cannot be adopted by
	# the precision mode's existing lean range without a visible tip jump.
	var axis := pose.basis.y.normalized()
	var visible_tilt := clampf(axis.z, -0.46, 0.68)
	if not is_equal_approx(axis.z, visible_tilt):
		var plane := Vector3(axis.x, axis.y, 0.0).normalized()
		var visible_axis := plane * sqrt(1.0 - visible_tilt * visible_tilt) + Vector3(0, 0, visible_tilt)
		pose.basis = Basis(Quaternion(axis, visible_axis.normalized())) * pose.basis
		pose.origin = grip - pose.basis * GRIP_POINT
	var pixel := _camera.unproject_position(_camera.to_global(grip))
	var view_size := get_viewport().get_visible_rect().size
	# After the offscreen overshoot, let a short section of steel remain in the
	# peripheral recovery. The shoulder stays on the far side of the cut.
	var margin := Vector2(106, 126) if settled else Vector2(24, 24)
	margin = margin.min(view_size * 0.22)
	var safe_pixel := pixel.clamp(margin, view_size - margin)
	if safe_pixel.distance_squared_to(pixel) > 0.0001:
		var ray := _camera.project_local_ray_normal(safe_pixel)
		var anchor := ray * (maxf(0.55, -grip.z) / maxf(-ray.z, 0.001))
		pose.origin = anchor - pose.basis * GRIP_POINT
	return pose


func _present_slash_face(pose: Transform3D) -> Transform3D:
	# Roll around the real longitudinal axis only: hilt, blade centreline and
	# contact geometry do not move when the forged face opens to the camera.
	var grip := pose * GRIP_POINT
	var axis := pose.basis.y.normalized()
	var toward_eye := -(grip + axis * 0.43).normalized()
	var facing := (toward_eye - axis * toward_eye.dot(axis)).normalized()
	var normal := pose.basis.z.normalized()
	if normal.dot(facing) < 0.0:
		facing = -facing
	var turn := normal.signed_angle_to(facing, axis)
	var excess := maxf(0.0, absf(turn) - 0.70)
	if excess > 0.0001:
		pose.basis = Basis(axis, signf(turn) * minf(excess, 0.72)) * pose.basis
		pose.origin = grip - pose.basis * GRIP_POINT
	return pose


func _make_guard_keys(previous: Transform3D) -> Array[Dictionary]:
	var basis := Basis(Quaternion.from_euler(Vector3(0.20, -0.13, -0.82)))
	var guard := Transform3D(basis, Vector3(0.0, -0.045, -0.92) - basis * ACTIVE_CUT_POINT)
	var guard_grip := guard * GRIP_POINT
	var early := previous
	early.basis = Basis(previous.basis.get_rotation_quaternion().slerp(guard.basis.get_rotation_quaternion(), 0.22))
	early.origin = (previous * GRIP_POINT).lerp(guard_grip, 0.22) + Vector3(0.0, -0.025, -0.015) - early.basis * GRIP_POINT
	return [
		_arm_key(0.0, previous, Vector3(0.04, 0.12, -0.15)),
		_arm_key(0.035, early, Vector3(0.12, -0.04, 0.02)),
		_arm_key(0.080, _grip_pose(guard_grip + Vector3(-0.024, 0.028, -0.038), Vector3(0.11, -0.17, -0.91)), Vector3(0.24, -0.30, 0.45)),
		_arm_key(0.12, guard, Vector3(0.20, -0.23, 0.35)),
		_arm_key(0.30, guard, Vector3(0.20, -0.23, 0.35)),
	]


func _parry_reaction_pose(guard: Transform3D, time: float) -> Transform3D:
	var start_grip := _parry_contact_from * GRIP_POINT
	var compressed := _grip_pose(start_grip + Vector3(0.026, -0.018, 0.105), _parry_contact_from.basis.get_euler() + Vector3(-0.25, 0.13, -0.12))
	var rebound := _grip_pose(guard * GRIP_POINT + Vector3(-0.035, 0.035, -0.075), guard.basis.get_euler() + Vector3(0.09, -0.08, 0.15))
	var keys: Array[Dictionary] = [
		_arm_key(0.0, _parry_contact_from, Vector3(0.20, -0.23, 0.35)),
		_arm_key(0.028, compressed, Vector3(-0.02, -0.05, 0.25)),
		_arm_key(0.095, rebound, Vector3(0.30, -0.37, 0.50)),
		_arm_key(0.18, guard, Vector3(0.20, -0.23, 0.35)),
	]
	return _sample_arm_keys(keys, time)


func _sheathe_pose(time: float) -> Transform3D:
	var dock := _dock_transform()
	var before_insert := dock
	before_insert.origin -= dock.basis.y * 0.875
	if time >= SHEATHE_INSERT_TIME:
		# Once the tip enters, the real blade slides down the sheath's axis;
		# independent elbow / wrist curves must not bend it through the sheath.
		var inserted := clampf((time - SHEATHE_INSERT_TIME) / (SHEATHE_TIME - SHEATHE_INSERT_TIME), 0.0, 1.0)
		inserted = inserted * inserted * (3.0 - 2.0 * inserted)
		dock.origin -= dock.basis.y * (0.875 * (1.0 - inserted))
		return dock
	var clear := _sheathe_from
	var clear_grip := clear * GRIP_POINT + Vector3(0.075, -0.095, -0.10)
	clear.basis = Basis(clear.basis.get_rotation_quaternion().slerp(dock.basis.get_rotation_quaternion(), 0.48))
	clear.origin = clear_grip - clear.basis * GRIP_POINT
	var keys: Array[Dictionary] = [
		_arm_key(0.0, _sheathe_from, Vector3(0.05, 0.10, 0.0)),
		_arm_key(0.11, clear, Vector3(0.18, 0.32, -0.28)),
		_arm_key(SHEATHE_INSERT_TIME, before_insert, Vector3(0.28, 0.14, -0.65)),
	]
	return _sample_arm_keys(keys, time)

func _update_energy_arc(_resting: bool) -> void:
	# One physical cutting edge and one contact trail. Parallel ion filaments
	# previously read as extra swords, so even short actions do not draw them.
	_energy_arc.visible = false


func _append_streak(surface: SurfaceTool, from: Vector3, to: Vector3, width: float, tint: Color) -> void:
	var tangent := to - from
	if tangent.length_squared() < 0.000001:
		return
	var side := tangent.cross(Vector3.BACK).normalized() * width
	for vertex in [from - side, from + side, to + side, from - side, to + side, to - side]:
		surface.set_color(tint)
		surface.add_vertex(vertex)


func _update_blade_trail(real_delta: float, resting: bool) -> void:
	if _mode == "held":
		_trail_samples.clear()
		_trail.visible = false
		return
	for index in range(_trail_samples.size() - 1, -1, -1):
		_trail_samples[index].age += real_delta
		if float(_trail_samples[index].age) > 0.060:
			_trail_samples.remove_at(index)
	if not resting:
		var contact: Vector3 = _drawn.transform * ACTIVE_CUT_POINT
		if _trail_samples.is_empty() or contact.distance_to(_trail_samples[-1].point) > 0.008:
			_trail_samples.append({"point": contact, "age": 0.0})
	var draw_window := 0.042
	var show_draw := _mode == "slash" and _action_time < draw_window and _draw_connection.size() > 1
	if _trail_samples.size() < 2 and not show_draw:
		_trail.visible = false
		return
	_trail.visible = true
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	if show_draw:
		var draw_opacity := clampf(1.0 - _action_time / draw_window, 0.0, 1.0)
		for index in range(_draw_connection.size() - 1):
			_append_streak(surface, _draw_connection[index], _draw_connection[index + 1], 0.0028, Color(0.82, 0.96, 1.0, draw_opacity * 0.62))
	for index in range(_trail_samples.size() - 1):
		var first: Dictionary = _trail_samples[index]
		var second: Dictionary = _trail_samples[index + 1]
		var opacity := clampf(1.0 - float(first.age) / 0.060, 0.0, 1.0)
		var tint := Color(1.0, 0.77, 0.38, opacity * 0.18) if _mode == "parry" else Color(0.66, 0.96, 1.0, opacity * 0.16)
		_append_streak(surface, first.point, second.point, 0.0032 if _mode == "slash" else 0.0018, tint)
	_trail.mesh = surface.commit()

func _make_grip(parent: Node3D, direction: float, steel: StandardMaterial3D, dark: StandardMaterial3D, glow: StandardMaterial3D) -> void:
	_box(parent, Vector3(0.098, 0.015, 0.05), Vector3.ZERO, steel)
	_box(parent, Vector3(0.037, 0.19, 0.028), Vector3(0, direction * 0.111, 0), dark)
	for index in range(6):
		var band := _box(parent, Vector3(0.043, 0.009, 0.032), Vector3(0, direction * (0.04 + index * 0.027), 0), steel)
		band.rotation.z = 0.22
	_box(parent, Vector3(0.046, 0.02, 0.036), Vector3(0, direction * 0.213, 0), steel)
	_box(parent, Vector3(0.018, 0.027, 0.004), Vector3(0, direction * 0.025, 0.028), glow)


func _contact_spark_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(8):
		var direction := Vector2.from_angle(float(index) * TAU / 8.0)
		var side := Vector2(-direction.y, direction.x) * 0.008
		var length := 0.075 if index % 2 == 0 else 0.044
		for point in [side, direction * length, -side]:
			surface.add_vertex(Vector3(point.x, point.y, 0.0))
	return surface.commit()


func _box(parent: Node3D, dimensions: Vector3, at: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


func _material(color: Color, metallic: float, roughness: float, luminous: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if luminous:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.5
	return material


func _blade_mesh() -> ArrayMesh:
	# A broad forged face, a narrow sharpened bevel and a dark spine have
	# different normals. Wrist torsion now moves highlights across real volume.
	var face := SurfaceTool.new()
	var bevel := SurfaceTool.new()
	var spine := SurfaceTool.new()
	for surface in [face, bevel, spine]:
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sections := [
		Vector3(-0.019, 0.020, 0.025),
		Vector3(-0.018, 0.021, 0.20),
		Vector3(-0.014, 0.027, 0.47),
		Vector3(-0.012, 0.033, 0.65),
		Vector3(-0.006, 0.018, 0.76),
		Vector3(0.0, 0.0004, 0.86),
	]
	for index in range(sections.size() - 1):
		var first: Vector3 = sections[index]
		var second: Vector3 = sections[index + 1]
		for side in [-1.0, 1.0]:
			var width_a := minf(0.010, (first.y - first.x) * 0.35)
			var width_b := minf(0.010, (second.y - second.x) * 0.35)
			var depth_a := 0.006 if index < sections.size() - 2 else 0.004
			var depth_b := 0.006 if index < sections.size() - 2 else 0.0003
			var cut_a := Vector3(first.x, first.z, 0.0)
			var cut_b := Vector3(second.x, second.z, 0.0)
			var bevel_a := Vector3(first.x + width_a, first.z, depth_a * side)
			var bevel_b := Vector3(second.x + width_b, second.z, depth_b * side)
			var back_a := Vector3(first.y - width_a * 0.35, first.z, depth_a * side)
			var back_b := Vector3(second.y - width_b * 0.35, second.z, depth_b * side)
			_blade_quad(face, bevel_a, back_a, back_b, bevel_b, side < 0.0)
			_blade_quad(bevel, cut_a, bevel_a, bevel_b, cut_b, side < 0.0)
			_blade_quad(spine, back_a, Vector3(first.y, first.z, 0.0), Vector3(second.y, second.z, 0.0), back_b, side < 0.0)
	var mesh := ArrayMesh.new()
	face.commit(mesh)
	bevel.commit(mesh)
	spine.commit(mesh)
	return mesh


func _blade_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, reverse: bool) -> void:
	var vertices := [a, d, c, b] if reverse else [a, b, c, d]
	var normal: Vector3 = (vertices[1] - vertices[0]).cross(vertices[2] - vertices[0]).normalized()
	# Godot fronts are clockwise; keep the outward shading normal above.
	for index in [0, 2, 1, 0, 3, 2]:
		surface.set_normal(normal)
		surface.add_vertex(vertices[index])
