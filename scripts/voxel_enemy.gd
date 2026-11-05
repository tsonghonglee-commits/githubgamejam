class_name VoxelEnemy
extends Node3D

signal severed(enemy: Node3D, world_point: Vector3, removed_count: int)
signal damaged(enemy: Node3D, world_point: Vector3, removed_count: int)

const DebrisScript = preload("res://scripts/voxel_debris.gd")
const HEAD_TAG := 1
const CORE_TAG := 2
const ANCHOR_TAG := 4
const DIRECTIONS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const PALETTE: Array[Color] = [
	Color.TRANSPARENT, Color("d8e5e2"), Color("263b45"),
	Color("ff823b"), Color("80fff0"), Color("b8a178"),
]

var enemy_kind := "normal"
var resolved := false
var dead := false
var attack_done := 0
var fire_timer := 0.0
var age := 0.0
var lane_index := 0
var last_cut_usec := 0
var last_removed_count := 0
var cut_count := 0

var _dimensions := Vector3i(15, 27, 8)
var _cell := 0.1
var _voxels := PackedByteArray()
var _tags := PackedByteArray()
var _body: MeshInstance3D
var _reactor: MeshInstance3D
var _reactor_material: StandardMaterial3D
var _material: StandardMaterial3D
var _core_point := Vector3.ZERO
var _warning := 0.0
var _rng := RandomNumberGenerator.new()
var _configured := false
var _cut_origin := Vector3.ZERO
var _rig: Node3D
var _parts: Array[Node3D] = []
var _part_meshes: Array[MeshInstance3D] = []
var _weapons: Array[Node3D] = []
var _weapon_edge_material: StandardMaterial3D
var _trail: MeshInstance3D
var _flash: MeshInstance3D
var _charge: MeshInstance3D
var action_name := "run"
var action_phase := 0.0
var action_variant := 0
var _sweep_frames: Array[Dictionary] = []
var _sweep_action := ""
var _previous_weapon_inner := Vector3.ZERO
var _previous_weapon_outer := Vector3.ZERO
var _previous_weapon_valid := false
var _strike_from_side := 1.0


func configure(kind: String, lane: int = 0) -> void:
	for child in get_children():
		if child.get_meta("voxel_piece", false) or child.get_meta("cut_chip", false) or child.get_meta("cut_particle_batch", false):
			child.queue_free()
	enemy_kind = kind
	lane_index = lane
	dead = false
	resolved = false
	attack_done = 0
	fire_timer = 0.0
	age = 0.0
	_rng.randomize()
	match kind:
		"tank":
			_dimensions = Vector3i(27, 27, 8)
			_cell = 0.11
		"boss":
			_dimensions = Vector3i(29, 17, 6)
			_cell = 0.24
		_:
			_dimensions = Vector3i(15, 27, 8)
			_cell = 0.1
	_voxels.resize(_dimensions.x * _dimensions.y * _dimensions.z)
	_voxels.fill(0)
	_tags.resize(_voxels.size())
	_tags.fill(0)
	_build_robot()
	_create_materials()
	_build_action_rig()
	_rebuild_body()
	_build_reactor_marker()
	_configured = true
	set_action("run", 0.0)


func get_aim_point() -> Vector3:
	return _rig.to_global(_core_point) if is_instance_valid(_rig) else to_global(_core_point)


func get_screen_bounds(camera: Camera3D) -> Rect2:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for part in _part_meshes:
		if not part.visible or part.mesh == null:
			continue
		var bounds: AABB = part.get_aabb()
		for corner in range(8):
			var point: Vector3 = part.to_global(bounds.get_endpoint(corner))
			if camera.is_position_behind(point):
				continue
			var screen := camera.unproject_position(point)
			low = low.min(screen)
			high = high.max(screen)
	if low.x == INF:
		return Rect2()
	return Rect2(low, high - low)


func pulse_warning(amount: float) -> void:
	_warning = clampf(amount, 0.0, 1.0)
	if is_instance_valid(_reactor_material):
		_reactor_material.albedo_color = Color("72fce1").lerp(Color("ff3a29"), _warning)
		_reactor_material.emission = _reactor_material.albedo_color
		_reactor_material.emission_energy_multiplier = 1.8 + _warning * 2.5


func set_action_variant(index: int) -> void:
	action_variant = index


func get_muzzle_point() -> Vector3:
	if not _weapons.is_empty():
		return _weapons[0].to_global(Vector3(0.0, 0.0, 0.86))
	return get_aim_point()


func get_ranged_origins() -> Array[Vector3]:
	var origins: Array[Vector3] = []
	if dead or not _configured:
		return origins
	if enemy_kind == "boss":
		for index in range(_weapons.size()):
			if _hand_intact(2 if index == 0 else 1):
				origins.append(_weapons[index].global_position)
	elif enemy_kind == "ranged" and has_attack_limb():
		origins.append(get_muzzle_point())
	return origins


func has_attack_limb(variant: int = -1) -> bool:
	if dead or not _configured:
		return false
	var selected: int = action_variant if variant < 0 else variant
	match enemy_kind:
		"tank":
			return _hand_intact(2 if selected % 2 == 0 else 1)
		"boss":
			return _hand_intact(2) if selected % 2 == 0 else (_hand_intact(1) or _hand_intact(2))
		_:
			return _hand_intact(2)


func set_action(action: String, phase: float) -> void:
	if not _configured:
		return
	if dead:
		_hide_action_props()
		return
	action_name = action
	action_phase = clampf(phase, 0.0, 1.0)
	var p: float = action_phase
	var smooth: float = smoothstep(0.0, 1.0, p)
	var side: float = 1.0 if action_variant % 2 == 0 else -1.0
	var body_angles := Vector3.ZERO
	var body_offset := Vector3.ZERO
	var right_arm := Vector3.ZERO
	var left_arm := Vector3.ZERO
	var heavy: bool = enemy_kind == "tank" or enemy_kind == "boss"
	var active_arm: int = 0 if enemy_kind != "tank" or action_variant % 2 == 0 else 1
	var run_phase: float = age * 10.0 + p * TAU
	var stride: float = sin(run_phase)
	var charge_amount := 0.0
	var flash_amount := 0.0
	var trail_amount := 0.0
	match action:
		"run":
			body_angles = Vector3(0.035, sin(run_phase * 0.5) * 0.045, stride * 0.018)
			body_offset.y = absf(stride) * 0.035
			right_arm = Vector3(stride * 0.20, 0.0, -0.12)
			left_arm = Vector3(-stride * 0.22, 0.0, 0.12)
		"windup", "boss_windup":
			body_angles = Vector3(-0.12 * smooth, -side * 0.34 * smooth, side * 0.06 * smooth)
			body_offset = Vector3(-side * 0.06 * smooth, -0.13 * smooth if heavy else -0.05 * smooth, -0.16 * smooth)
			if heavy:
				right_arm = Vector3(1.95 * smooth, 0.0, -0.22 - 0.40 * smooth)
				left_arm = Vector3(0.40 * smooth, 0.0, 0.18 + 0.26 * smooth)
				if enemy_kind == "tank" and active_arm == 1:
					left_arm = Vector3(1.95 * smooth, 0.0, 0.22 + 0.40 * smooth)
					right_arm = Vector3(0.40 * smooth, 0.0, -0.18 - 0.26 * smooth)
				if enemy_kind == "boss" and action_variant % 2 != 0:
					right_arm = Vector3(-0.45 * smooth, 0.0, 1.85 * smooth)
					left_arm = Vector3(-0.45 * smooth, 0.0, -1.85 * smooth)
					charge_amount = smooth
			else:
				right_arm = Vector3(-0.25 * smooth, -0.10 * smooth, -1.95 * smooth)
				left_arm = Vector3(-0.25 * smooth, 0.0, 0.35 * smooth)
			if enemy_kind != "boss":
				# Establish the silhouette early; the remaining windup loads the body.
				var lift: float = smoothstep(0.0, 0.30, p)
				var coil: float = smoothstep(0.25, 1.0, p)
				body_angles = Vector3(-0.07 * lift - 0.06 * coil, -side * 0.23 * lift, side * 0.07 * coil)
				body_offset = Vector3(-side * 0.04 * lift, -(0.07 * lift + 0.12 * coil) if heavy else -(0.03 * lift + 0.06 * coil), -0.10 * coil)
				if enemy_kind == "tank":
					var lifted_arm := Vector3(2.35, 0.0, 0.65 * side) * lift
					right_arm = lifted_arm if active_arm == 0 else Vector3(0.22 * lift, 0.0, 0.10 * lift)
					left_arm = lifted_arm if active_arm == 1 else Vector3(0.22 * lift, 0.0, -0.10 * lift)
				else:
					right_arm = Vector3(0.20, 0.0, 2.20) * lift
					left_arm = Vector3(-0.30, 0.0, -0.25) * lift
		"strike", "boss_strike":
			var strike: float = smoothstep(0.05, 0.80, p)
			body_angles = Vector3(sin(p * PI) * 0.27, lerpf(-side * 0.34, side * 0.28, strike), -side * 0.10 * sin(p * PI))
			body_offset = Vector3(side * 0.08 * sin(p * PI), -0.16 * sin(p * PI) if heavy else -0.04, 0.18 * sin(p * PI))
			if heavy:
				right_arm = Vector3(lerpf(1.95, -1.12, strike), 0.0, lerpf(-0.62, 0.18, strike))
				left_arm = Vector3(0.34, 0.0, 0.30)
				if enemy_kind == "tank" and active_arm == 1:
					left_arm = Vector3(lerpf(1.95, -1.12, strike), 0.0, lerpf(0.62, -0.18, strike))
					right_arm = Vector3(0.34, 0.0, -0.30)
				if enemy_kind == "boss" and action_variant % 2 != 0:
					right_arm = Vector3(-0.45 - sin(p * PI) * 0.6, 0.0, 1.85 - sin(p * PI) * 0.5)
					left_arm = Vector3(-0.45 - sin(p * PI) * 0.6, 0.0, -1.85 + sin(p * PI) * 0.5)
					flash_amount = sin(p * PI)
			else:
				right_arm = Vector3(lerpf(-0.25, -0.90, strike), 0.0, lerpf(-1.95, 1.05, strike))
				left_arm = Vector3(-0.20, 0.0, 0.35)
			trail_amount = sin(p * PI) if p > 0.08 and p < 0.94 else 0.0
			if enemy_kind != "boss":
				var contact: float = smoothstep(0.05, 0.55, p)
				var through: float = smoothstep(0.55, 1.0, p)
				body_angles = Vector3(lerpf(-0.13, 0.12, contact), lerpf(-side * 0.23, side * 0.12, contact), -side * 0.07 * sin(p * PI))
				body_offset = Vector3(side * 0.04 * sin(p * PI), -0.15 if heavy else -0.06, 0.10 * sin(p * PI))
				var raised_arm := Vector3(2.35, 0.0, 0.65 * side) if heavy else Vector3(0.20, 0.0, 2.20)
				var contact_arm := Vector3(-1.63 if heavy else -1.58, 0.0, 0.06 * side if heavy else 0.12)
				var finish_arm := Vector3(-0.54, 0.0, -0.95 * side if heavy else -1.20)
				var attacking_arm: Vector3 = raised_arm.lerp(contact_arm, contact).lerp(finish_arm, through)
				right_arm = attacking_arm if active_arm == 0 else Vector3(0.18, 0.0, 0.10)
				left_arm = attacking_arm if active_arm == 1 else Vector3(-0.20, 0.0, -0.25)
		"recover":
			var release: float = 1.0 - smooth
			body_angles = Vector3(0.16 * release, side * 0.28 * release, 0.0)
			body_offset.y = -0.12 * release if heavy else -0.04 * release
			right_arm = Vector3(-0.65 * release, 0.0, (0.18 if heavy else 1.05) * release)
			left_arm = Vector3(0.18 * release, 0.0, 0.22 * release)
			if enemy_kind != "boss":
				var finishing_arm := Vector3(-0.54, 0.0, -0.95 * side if heavy else -1.20) * release
				right_arm = finishing_arm if active_arm == 0 else Vector3.ZERO
				left_arm = finishing_arm if active_arm == 1 else Vector3(-0.20, 0.0, -0.25) * release
		"stagger":
			var recoil: float = sin(p * PI)
			body_angles = Vector3(-0.30 * recoil, side * 0.18 * recoil, -side * 0.11 * recoil)
			body_offset = Vector3(side * 0.06 * recoil, -0.06 * recoil, -0.30 * recoil)
			right_arm = Vector3(0.45 * recoil, 0.0, -0.80 * recoil)
			left_arm = Vector3(0.35 * recoil, 0.0, 0.65 * recoil)
		"ranged_charge":
			body_angles = Vector3(-0.05 * smooth, -0.12 * smooth, 0.0)
			right_arm = Vector3(-0.62 * smooth, 0.0, -0.12)
			left_arm = Vector3(-0.35 * smooth, 0.0, -0.45 * smooth)
			charge_amount = smooth
		"ranged_fire":
			var kick: float = sin(minf(p * 2.0, 1.0) * PI) * (1.0 - p)
			body_angles = Vector3(-0.11 * kick, -0.12, 0.0)
			body_offset.z = -0.12 * kick
			right_arm = Vector3(-0.62 + 0.26 * kick, 0.0, -0.12)
			left_arm = Vector3(-0.35 + 0.12 * kick, 0.0, -0.45)
			flash_amount = maxf(0.0, 1.0 - absf(p - 0.25) / 0.24)
	_pose(body_angles, body_offset, left_arm, right_arm)
	if enemy_kind != "boss":
		for weapon in _weapons:
			weapon.rotation = Vector3.ZERO
		if action == "strike":
			if _sweep_action != "strike":
				_strike_from_side = -1.0 if _weapons[active_arm].global_position.x < -0.15 else 1.0
			var connect: float = smoothstep(0.12, 0.40, p) * (1.0 - smoothstep(0.65, 0.95, p))
			_aim_striking_weapon(_weapons[active_arm], connect)
	_refresh_weapon_visibility()
	if not has_attack_limb():
		charge_amount = 0.0
		flash_amount = 0.0
		trail_amount = 0.0
	if enemy_kind == "ranged" and not _weapons.is_empty():
		# Gun muzzle points at the player, including when the body turns to brace.
		var gun: Node3D = _weapons[0]
		if gun.global_position.distance_squared_to(Vector3(0, 1.7, 0)) > 0.01:
			gun.look_at(Vector3(0, 1.7, 0), Vector3.UP, true)
	if _weapon_edge_material != null:
		var raised: float = smooth if action == "windup" or action == "boss_windup" else trail_amount
		_weapon_edge_material.emission_energy_multiplier = 0.8 + raised * 3.0
		_weapon_edge_material.albedo_color = Color("ffb77c").lerp(Color("ff3a16"), raised)
	if _charge != null:
		_charge.visible = charge_amount > 0.01
		_charge.scale = Vector3.ONE * (0.18 + charge_amount * 0.9)
	if _flash != null:
		_flash.visible = flash_amount > 0.01
		_flash.scale = Vector3.ONE * (0.30 + flash_amount * 1.3)
	_update_attack_trail(action, p, trail_amount)


func _part_for_index(index: int) -> int:
	var coords: Vector3i = _coords(index)
	var center_x: int = _dimensions.x / 2
	if enemy_kind == "boss":
		if coords.y >= 6 and coords.y <= 13:
			if coords.x <= 5:
				return 1
			if coords.x >= 23:
				return 2
	elif coords.y >= 12 and coords.y <= 20:
		var shoulder: int = 8 if enemy_kind == "tank" else 4
		if coords.x < center_x - shoulder:
			return 1
		if coords.x > center_x + shoulder:
			return 2
	return 0


func _part_pose(part: int) -> Transform3D:
	return _rig.transform if part == 0 else _rig.transform * _parts[part].transform


func _posed_world_point(index: int) -> Vector3:
	var coords: Vector3i = _coords(index)
	return to_global(_part_pose(_part_for_index(index)) * _point(coords.x, coords.y, coords.z))


func _pose(body_angles: Vector3, offset: Vector3, left_angles: Vector3, right_angles: Vector3) -> void:
	var pivot := Vector3(0, 1.35 if enemy_kind == "boss" else 0.95, 0)
	var body_basis := Basis.from_euler(body_angles)
	_rig.transform = Transform3D(body_basis, pivot - body_basis * pivot + offset)
	var arm_x: float = 2.65 if enemy_kind == "boss" else (1.045 if enemy_kind == "tank" else 0.55)
	var arm_y: float = 3.0 if enemy_kind == "boss" else 1.95 * (_cell / 0.1)
	for index in [1, 2]:
		var arm_pivot := Vector3(-arm_x if index == 1 else arm_x, arm_y, 0.0)
		var arm_basis := Basis.from_euler(left_angles if index == 1 else right_angles)
		_parts[index].transform = Transform3D(arm_basis, arm_pivot - arm_basis * arm_pivot)


func _build_action_rig() -> void:
	if is_instance_valid(_rig):
		_rig.free()
	if is_instance_valid(_trail):
		_trail.free()
	_parts.clear()
	_part_meshes.clear()
	_weapons.clear()
	_sweep_frames.clear()
	_sweep_action = ""
	_previous_weapon_valid = false
	_flash = null
	_charge = null
	_rig = Node3D.new()
	_rig.name = "ActionRig"
	add_child(_rig)
	_parts.append(_rig)
	for name_suffix in ["LeftArm", "RightArm"]:
		var part := Node3D.new()
		part.name = name_suffix
		_rig.add_child(part)
		_parts.append(part)
	for index in range(3):
		var mesh := MeshInstance3D.new()
		mesh.name = "TorsoVoxels" if index == 0 else "ArmVoxels"
		mesh.material_override = _material
		_parts[index].add_child(mesh)
		_part_meshes.append(mesh)
	_body = _part_meshes[0]
	_weapon_edge_material = _prop_material(Color("ff8844"), true)
	for part_index in [2, 1]:
		var weapon := Node3D.new()
		weapon.name = "WeaponRight" if part_index == 2 else "WeaponLeft"
		_parts[part_index].add_child(weapon)
		_weapons.append(weapon)
		_build_weapon(weapon, part_index)
	_trail = MeshInstance3D.new()
	_trail.name = "AttackSweep"
	var trail_material := _prop_material(Color(1.0, 0.24, 0.06, 0.48 if enemy_kind == "boss" else 0.18), true)
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail.material_override = trail_material
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail)
	_trail.visible = false


func _build_weapon(weapon: Node3D, part: int) -> void:
	var side: float = -1.0 if part == 1 else 1.0
	var arm_x: float = 2.65 if enemy_kind == "boss" else (1.045 if enemy_kind == "tank" else 0.55)
	weapon.position = Vector3(side * arm_x, 1.7 if enemy_kind == "boss" else 1.25 * (_cell / 0.1), 0.20)
	var steel := _prop_material(Color("677d86"))
	var dark := _prop_material(Color("15252d"))
	var gold := _prop_material(Color("aa8560"))
	if enemy_kind == "ranged" and part == 2:
		_box_prop(weapon, Vector3(0.26, 0.26, 0.68), Vector3(0, 0.02, 0.28), dark)
		_box_prop(weapon, Vector3(0.13, 0.13, 0.32), Vector3(0, 0.02, 0.68), steel)
		_box_prop(weapon, Vector3(0.04, 0.04, 0.55), Vector3(0, 0.17, 0.3), _weapon_edge_material)
		_flash = _sphere_prop(weapon, 0.26, Vector3(0, 0.02, 0.9), _prop_material(Color("fff3bd"), true))
		_charge = _sphere_prop(weapon, 0.15, Vector3(0, 0.02, 0.9), _weapon_edge_material)
	elif enemy_kind == "tank":
		_box_prop(weapon, Vector3(0.09, 0.7, 0.09), Vector3(0, -0.32, 0), dark)
		_box_prop(weapon, Vector3(0.65, 0.37, 0.45), Vector3(0, -0.82, 0), gold)
		_box_prop(weapon, Vector3(0.67, 0.055, 0.47), Vector3(0, -0.99, 0), _weapon_edge_material)
	elif part == 2:
		var length: float = 2.6 if enemy_kind == "boss" else 1.5
		var width: float = 0.22 if enemy_kind == "boss" else 0.09
		_box_prop(weapon, Vector3(0.11, 0.32, 0.11), Vector3(0, 0.08, 0), dark)
		_box_prop(weapon, Vector3(width * 3.0, 0.06, 0.16), Vector3(0, -0.1, 0), steel)
		_box_prop(weapon, Vector3(width, length, 0.055), Vector3(0, -0.2 - length * 0.5, 0), steel)
		_box_prop(weapon, Vector3(0.025, length, 0.065), Vector3(width * 0.52, -0.2 - length * 0.5, 0), _weapon_edge_material)
		if enemy_kind == "boss":
			_charge = _sphere_prop(_rig, 0.48, _core_point + Vector3(0, 0, 0.22), _weapon_edge_material)
			_flash = _sphere_prop(_rig, 0.7, _core_point + Vector3(0, 0, 0.35), _prop_material(Color("fff3bd"), true))
	else:
		_box_prop(weapon, Vector3(0.22, 0.2, 0.17), Vector3.ZERO, dark)
	if _flash != null:
		_flash.visible = false
	if _charge != null:
		_charge.visible = false


func _refresh_weapon_visibility() -> void:
	for index in range(_weapons.size()):
		var part: int = 2 if index == 0 else 1
		_weapons[index].visible = not dead and _hand_intact(part)


func _hand_intact(part: int) -> bool:
	# Check the hand itself, not a surviving shoulder stub. Otherwise a wrist cut
	# would leave a floating weapon and the attack could still inflict damage.
	var y_start: int = 6 if enemy_kind == "boss" else 12
	var y_end: int = 8 if enemy_kind == "boss" else 14
	for y in range(y_start, y_end + 1):
		for x in range(_dimensions.x):
			for z in range(_dimensions.z):
				var index: int = _index(x, y, z)
				if _voxels[index] != 0 and _part_for_index(index) == part:
					return true
	return false


func _hide_action_props() -> void:
	for weapon in _weapons:
		weapon.visible = false
	if _trail != null:
		_trail.visible = false
	if _flash != null:
		_flash.visible = false
	if _charge != null:
		_charge.visible = false


func _update_attack_trail(action: String, phase: float, amount: float) -> void:
	if enemy_kind != "boss":
		_update_weapon_sweep(action, phase, amount)
		return
	_trail.visible = amount > 0.01
	if not _trail.visible:
		return
	var boss: bool = enemy_kind == "boss"
	var heavy: bool = enemy_kind == "tank" or boss
	var radius: float = 3.2 if boss else (2.0 if heavy else 1.9)
	var side: float = -1.0 if enemy_kind == "tank" and action_variant % 2 != 0 else 1.0
	var sweep: float = lerpf(-2.0, 1.15, smoothstep(0.05, 0.8, phase))
	var center := Vector3(side * 0.22, 2.4 if boss else 1.6, 0.45)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for step in range(12):
		var angle_a: float = sweep - 0.65 + float(step) * 0.65 / 12.0
		var angle_b: float = sweep - 0.65 + float(step + 1) * 0.65 / 12.0
		var a: Vector3
		var b: Vector3
		var c: Vector3
		var d: Vector3
		if heavy and (enemy_kind == "tank" or action_variant % 2 == 0):
			a = center + Vector3(side * 0.55, cos(angle_a) * radius * 0.5, sin(angle_a) * radius * 0.65 + 0.8)
			b = center + Vector3(side * 0.55, cos(angle_b) * radius * 0.5, sin(angle_b) * radius * 0.65 + 0.8)
			c = b + Vector3(0.18, -0.10, -0.08)
			d = a + Vector3(0.18, -0.10, -0.08)
		else:
			a = center + Vector3(sin(angle_a) * radius, cos(angle_a) * 0.45, 0.8)
			b = center + Vector3(sin(angle_b) * radius, cos(angle_b) * 0.45, 0.8)
			c = b + Vector3(0.0, -0.14, 0.03)
			d = a + Vector3(0.0, -0.14, 0.03)
		for vertex in [a, b, c, a, c, d]:
			surface.add_vertex(vertex)
	_trail.mesh = surface.commit()


func _aim_striking_weapon(weapon: Node3D, weight: float) -> void:
	if weight <= 0.0:
		return
	# Sweep obliquely across the player's space. Pointing the whole blade straight
	# through the camera would turn its emissive edge into a near-plane polygon.
	var direction := Vector3(-_strike_from_side * 0.92, -0.10, 0.36).normalized()
	var aimed: Basis
	if enemy_kind == "ranged":
		aimed = Basis.looking_at(direction, Vector3.UP, true)
	else:
		var axis_y: Vector3 = -direction
		var axis_z: Vector3 = Vector3(0, 0, 1).slide(direction).normalized()
		aimed = Basis(axis_y.cross(axis_z).normalized(), axis_y, axis_z)
	weapon.global_basis = weapon.global_basis.orthonormalized().slerp(aimed, weight)


func _update_weapon_sweep(action: String, phase: float, amount: float) -> void:
	var weapon_index: int = 1 if enemy_kind == "tank" and action_variant % 2 != 0 else 0
	var weapon: Node3D = _weapons[weapon_index]
	var inner_local := Vector3(0, -0.88 if enemy_kind == "tank" else -1.53, 0)
	var outer_local := Vector3(0, -1.02 if enemy_kind == "tank" else -1.70, 0)
	if enemy_kind == "ranged":
		inner_local = Vector3(0, 0, 0.4)
		outer_local = Vector3(0, 0, 0.9)
	var inner: Vector3 = to_local(weapon.to_global(inner_local))
	var outer: Vector3 = to_local(weapon.to_global(outer_local))
	if action != "strike":
		_sweep_frames.clear()
		_trail.visible = false
	else:
		if _sweep_action != "strike" or (not _sweep_frames.is_empty() and phase < float(_sweep_frames.back().phase)):
			_sweep_frames.clear()
			if _previous_weapon_valid:
				_sweep_frames.append({"phase": 0.0, "inner": _previous_weapon_inner, "outer": _previous_weapon_outer})
		if _sweep_frames.is_empty() or phase > float(_sweep_frames.back().phase) + 0.00001:
			_sweep_frames.append({"phase": phase, "inner": inner, "outer": outer})
		else:
			_sweep_frames.back()["inner"] = inner
			_sweep_frames.back()["outer"] = outer
		while _sweep_frames.size() > 2 and float(_sweep_frames[0].phase) < phase - 0.22:
			_sweep_frames.pop_front()
		_trail.visible = amount > 0.01 and _sweep_frames.size() >= 2
		if _trail.visible:
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			for index in range(_sweep_frames.size() - 1):
				var a: Dictionary = _sweep_frames[index]
				var b: Dictionary = _sweep_frames[index + 1]
				for point in [a.inner, a.outer, b.outer, a.inner, b.outer, b.inner]:
					surface.add_vertex(point)
			_trail.mesh = surface.commit()
	_sweep_action = action
	_previous_weapon_inner = inner
	_previous_weapon_outer = outer
	_previous_weapon_valid = true


func _prop_material(color: Color, glowing: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.65
	material.roughness = 0.35
	if glowing:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.5
	return material


func _box_prop(parent: Node3D, dimensions: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	parent.add_child(instance)
	return instance


func _sphere_prop(parent: Node3D, radius: float, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


func cut_screen(camera: Camera3D, from: Vector2, to: Vector2, power: float = 1.0) -> Dictionary:
	return cut_path(camera, PackedVector2Array([from, to]), power)


func cut_path(camera: Camera3D, points: PackedVector2Array, power: float = 1.0) -> Dictionary:
	return _cut_shape(camera, points, power)


func cut_blade_sweep(camera: Camera3D, frames: Array, power: float = 1.0) -> Dictionary:
	if frames.size() < 2:
		return {"removed": 0, "killed": false}
	return _cut_shape(camera, DebrisScript.blade_motion_points(frames), power, frames)


func _cut_shape(camera: Camera3D, points: PackedVector2Array, power: float, blade_frames: Array = []) -> Dictionary:
	if not _configured or points.size() < 2:
		return {"removed": 0, "killed": false}
	var start_time := Time.get_ticks_usec()
	var fragment_removed := 0
	# Capture the list before this cut: freshly separated pieces must not be cut twice.
	for child in get_children():
		if child.get_meta("voxel_piece", false) and not child.is_queued_for_deletion():
			var result: Dictionary = child.cut_path(camera, points, power) if blade_frames.is_empty() else child.cut_blade_sweep(camera, blade_frames, power)
			fragment_removed += int(result.get("removed", 0))
	var body_result := _cut_body(camera, points, power, blade_frames)
	var total_removed: int = int(body_result.get("removed", 0)) + fragment_removed
	if fragment_removed > 0 and int(body_result.get("removed", 0)) == 0:
		cut_count += 1
		damaged.emit(self, get_aim_point(), fragment_removed)
	last_removed_count = total_removed
	last_cut_usec = Time.get_ticks_usec() - start_time
	return {"removed": total_removed, "killed": bool(body_result.get("killed", false))}


func get_remaining_voxel_count(include_fragments: bool = true) -> int:
	var count := 0
	for voxel in _voxels:
		if voxel != 0:
			count += 1
	if include_fragments:
		for child in get_children():
			if child.get_meta("voxel_piece", false) and not child.is_queued_for_deletion():
				count += child.get_voxel_count()
	return count


func _cut_body(camera: Camera3D, points: PackedVector2Array, power: float, blade_frames: Array = []) -> Dictionary:
	if points.size() < 2:
		return {"removed": 0, "killed": false}
	var start_time: int = Time.get_ticks_usec()
	var cell_screen: Vector2 = camera.unproject_position(_rig.to_global(_core_point + Vector3(_cell, 0.0, 0.0)))
	var core_screen: Vector2 = camera.unproject_position(get_aim_point())
	var band: float = maxf(3.5, cell_screen.distance_to(core_screen) * (0.75 + power * 0.18))
	var bounds: Rect2 = get_screen_bounds(camera).grow(band * 1.5)
	var relevant_segments := PackedInt32Array()
	var regions: Array[Dictionary] = []
	if blade_frames.is_empty():
		for segment in range(points.size() - 1):
			if _segment_overlaps_rect(points[segment], points[segment + 1], bounds):
				relevant_segments.append(segment)
	else:
		regions = DebrisScript.sweep_regions(blade_frames, bounds, band)
	if relevant_segments.is_empty() and regions.is_empty():
		last_cut_usec = Time.get_ticks_usec() - start_time
		return {"removed": 0, "killed": false}
	var stroke := Vector2.ZERO
	for segment in range(points.size() - 1):
		var direction := points[segment + 1] - points[segment]
		if direction.length_squared() > stroke.length_squared():
			stroke = direction
	var cut_indices := PackedInt32Array()
	var center := Vector3.ZERO
	var depth_budget: int = _dimensions.z
	if enemy_kind == "tank":
		depth_budget = clampi(int(floor(power * 1.40)), 1, _dimensions.z)
	elif enemy_kind == "boss":
		depth_budget = clampi(int(floor(power * 1.25)), 1, _dimensions.z)
	var armored := enemy_kind in ["tank", "boss"]
	var part_poses: Array[Transform3D] = []
	if armored:
		for part in range(3):
			part_poses.append(global_transform * _part_pose(part))
	# Depth is counted from the camera-facing surviving layer, so repeat cuts
	# genuinely carve farther into the same material instead of subtracting HP.
	# Heavy armor takes a shallow material bite, not most of a joint at once.
	for y in range(_dimensions.y):
		for x in range(_dimensions.x):
			var removed_in_column := 0
			var start_z: int = _dimensions.z - 1
			var end_z := -1
			var depth_step := -1
			if armored:
				# A raised arm can turn its authored back toward the camera.
				# Start at the near Z end of that currently posed material column.
				var pose: Transform3D = part_poses[_part_for_index(_index(x, y, 0))]
				var toward_camera: Vector3 = camera.global_position - pose * _point(x, y, _dimensions.z / 2)
				if pose.basis.z.dot(toward_camera) < 0.0:
					start_z = 0
					end_z = _dimensions.z
					depth_step = 1
			for z in range(start_z, end_z, depth_step):
				var index: int = _index(x, y, z)
				if _voxels[index] == 0:
					continue
				var local_point: Vector3 = _point(x, y, z)
				var world_point: Vector3 = _posed_world_point(index)
				if camera.is_position_behind(world_point):
					continue
				var screen: Vector2 = camera.unproject_position(world_point)
				var intersects_path: bool = not regions.is_empty() and DebrisScript.point_in_sweep(screen, regions, band * band)
				for segment in relevant_segments:
					var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(screen, points[segment], points[segment + 1])
					if nearest.distance_squared_to(screen) <= band * band:
						intersects_path = true
						break
				if not intersects_path:
					# Do not skip an intact surface whose projected centre missed
					# the narrow blade line and tunnel into its exposed-looking core.
					# A later stroke can enter the next layer after real material loss.
					if armored:
						break
					continue
				if removed_in_column >= depth_budget:
					break
				removed_in_column += 1
				cut_indices.append(index)
				center += to_local(world_point)
	if cut_indices.is_empty():
		last_cut_usec = Time.get_ticks_usec() - start_time
		return {"removed": 0, "killed": false}
	center /= float(cut_indices.size())
	_cut_origin = center
	# Keep the exact posed cut cells before removing material. The visual
	# burst is chosen after connectivity decides whether this is a real sever.
	var spark_sources := PackedVector3Array()
	for index in cut_indices:
		spark_sources.append(_posed_world_point(index))
		_voxels[index] = 0
	var groups: Array[Dictionary] = _connected_components()
	var core_survives := false
	var core_connected_to_base := false
	var head_connected_to_base := false
	var primary := -1
	var largest := 0
	for group_index in range(groups.size()):
		var flags: int = groups[group_index]["flags"]
		var indices: PackedInt32Array = groups[group_index]["indices"]
		if flags & CORE_TAG:
			core_survives = true
			if flags & ANCHOR_TAG:
				core_connected_to_base = true
		if flags & HEAD_TAG and flags & ANCHOR_TAG:
			head_connected_to_base = true
			primary = group_index
		if primary < 0 and indices.size() > largest:
			largest = indices.size()
			primary = group_index
	var was_dead := dead
	dead = was_dead or not core_survives or not core_connected_to_base or not head_connected_to_base
	DebrisScript.emit_cut_particles(self, camera, spark_sources, stroke, _cell, "sever" if dead and not was_dead else "body")
	for group_index in range(groups.size()):
		if not dead and group_index == primary:
			continue
		var indices: PackedInt32Array = groups[group_index]["indices"]
		if _spawn_fragment(indices, stroke, dead):
			for index in indices:
				_voxels[index] = 0
	_rebuild_body()
	if is_instance_valid(_reactor):
		_reactor.visible = not dead and core_survives
	if dead:
		_hide_action_props()
	last_removed_count = cut_indices.size()
	cut_count += 1
	last_cut_usec = Time.get_ticks_usec() - start_time
	var point: Vector3 = to_global(center)
	if dead and not was_dead:
		severed.emit(self, point, cut_indices.size())
	else:
		damaged.emit(self, point, cut_indices.size())
	return {"removed": cut_indices.size(), "killed": dead and not was_dead}


func _build_robot() -> void:
	if enemy_kind == "boss":
		_build_boss()
		return
	var cx: int = _dimensions.x / 2
	var cz: int = _dimensions.z / 2
	var thick := 1 if enemy_kind != "tank" else 3
	# Deliberately narrow joints make the physical cut legible at runner speed.
	_fill_box(cx - 4 - thick, 0, 1, cx - 1, 2, _dimensions.z - 2, 2)
	_fill_box(cx + 1, 0, 1, cx + 4 + thick, 2, _dimensions.z - 2, 2)
	_fill_box(cx - 4, 3, cz - thick, cx - 2, 9, cz + thick, 1)
	_fill_box(cx + 2, 3, cz - thick, cx + 4, 9, cz + thick, 1)
	_fill_box(cx - 4, 9, 2, cx + 4, 11, _dimensions.z - 3, 2)
	_fill_box(cx - thick, 12, cz - thick, cx + thick, 13, cz + thick, 4)
	var shoulder := 4 if enemy_kind != "tank" else 8
	_fill_box(cx - shoulder, 14, 1, cx + shoulder, 20, _dimensions.z - 2, 1 if enemy_kind != "tank" else 5)
	# The tank's visible neck shares five real depth layers with head/chest.
	# Its former three-layer joint was thinner than one high-gear armor bite.
	var neck_depth := 2 if enemy_kind == "tank" else 1
	_fill_box(cx - 1, 21, cz - neck_depth, cx + 1, 22, cz + neck_depth, 2)
	_fill_box(cx - 3, 23, 1, cx + 3, 26, _dimensions.z - 2, 1)
	_fill_box(cx - shoulder - 2, 17, 2, cx - shoulder - 1, 20, _dimensions.z - 3, 2)
	_fill_box(cx + shoulder + 1, 17, 2, cx + shoulder + 2, 20, _dimensions.z - 3, 2)
	_fill_box(cx - shoulder - 2, 12, 2, cx - shoulder - 1, 16, _dimensions.z - 3, 1)
	_fill_box(cx + shoulder + 1, 12, 2, cx + shoulder + 2, 16, _dimensions.z - 3, 1)
	_fill_box(cx - 2, 24, _dimensions.z - 2, cx + 2, 24, _dimensions.z - 2, 4)
	if enemy_kind == "ranged":
		_fill_box(cx + 4, 14, _dimensions.z - 1, cx + 6, 16, _dimensions.z - 1, 3)
	_fill_box(cx - 1, 16, cz - 1, cx + 1, 18, cz, 3)
	_tag_box(cx - 1, 24, cz - 1, cx + 1, 25, cz, HEAD_TAG)
	_tag_box(cx - 1, 16, cz - 1, cx + 1, 18, cz, CORE_TAG)
	_tag_box(cx - 3, 9, 2, cx + 3, 10, _dimensions.z - 3, ANCHOR_TAG)
	_core_point = _point(cx, 17, _dimensions.z - 1)


func _build_boss() -> void:
	# Boss authoring coordinates are halved into a coarser runtime grid.
	# A larger silhouette should not require eight times the carving work.
	var cx := 28
	var cz := 6
	_fill_box(cx - 12, 0, 2, cx - 5, 3, 10, 2)
	_fill_box(cx + 5, 0, 2, cx + 12, 3, 10, 2)
	_fill_box(cx - 10, 4, 3, cx - 6, 12, 8, 1)
	_fill_box(cx + 6, 4, 3, cx + 10, 12, 8, 1)
	_fill_box(cx - 8, 12, 2, cx + 8, 15, 9, 2)
	_fill_box(cx - 3, 16, 3, cx + 3, 17, 8, 4)
	_fill_box(cx - 16, 18, 1, cx + 16, 27, 10, 1)
	_fill_box(cx - 25, 21, 2, cx - 17, 27, 9, 5)
	_fill_box(cx + 17, 21, 2, cx + 25, 27, 9, 5)
	_fill_box(cx - 27, 13, 3, cx - 23, 20, 8, 2)
	_fill_box(cx + 23, 13, 3, cx + 27, 20, 8, 2)
	_fill_box(cx - 2, 28, 3, cx + 2, 29, 8, 2)
	_fill_box(cx - 6, 30, 2, cx + 6, 33, 9, 1)
	_fill_box(cx - 4, 31, 10, cx + 4, 31, 10, 4)
	_fill_box(cx - 3, 21, cz - 1, cx + 3, 24, cz + 1, 3)
	_tag_box(cx - 2, 31, cz - 1, cx + 2, 32, cz + 1, HEAD_TAG)
	_tag_box(cx - 3, 21, cz - 1, cx + 3, 24, cz + 1, CORE_TAG)
	_tag_box(cx - 6, 12, 3, cx + 6, 14, 8, ANCHOR_TAG)
	_core_point = _point(14, 11, _dimensions.z - 1)


func _fill_box(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, color_index: int) -> void:
	if enemy_kind == "boss":
		x0 = int(floor(float(x0) * 0.5))
		y0 = int(floor(float(y0) * 0.5))
		z0 = int(floor(float(z0) * 0.5))
		x1 = int(floor(float(x1) * 0.5))
		y1 = int(floor(float(y1) * 0.5))
		z1 = int(floor(float(z1) * 0.5))
	for z in range(maxi(z0, 0), mini(z1 + 1, _dimensions.z)):
		for y in range(maxi(y0, 0), mini(y1 + 1, _dimensions.y)):
			for x in range(maxi(x0, 0), mini(x1 + 1, _dimensions.x)):
				_voxels[_index(x, y, z)] = color_index


func _tag_box(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, tag: int) -> void:
	if enemy_kind == "boss":
		x0 = int(floor(float(x0) * 0.5))
		y0 = int(floor(float(y0) * 0.5))
		z0 = int(floor(float(z0) * 0.5))
		x1 = int(floor(float(x1) * 0.5))
		y1 = int(floor(float(y1) * 0.5))
		z1 = int(floor(float(z1) * 0.5))
	for z in range(maxi(z0, 0), mini(z1 + 1, _dimensions.z)):
		for y in range(maxi(y0, 0), mini(y1 + 1, _dimensions.y)):
			for x in range(maxi(x0, 0), mini(x1 + 1, _dimensions.x)):
				_tags[_index(x, y, z)] |= tag


func _create_materials() -> void:
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.72
	_material.metallic = 0.18
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.emission_enabled = true
	_material.emission = Color(0.025, 0.05, 0.055)
	_material.emission_energy_multiplier = 0.5
	_reactor_material = StandardMaterial3D.new()
	_reactor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_reactor_material.albedo_color = Color("ff944b")
	_reactor_material.emission_enabled = true
	_reactor_material.emission = Color("ff944b")
	_reactor_material.emission_energy_multiplier = 2.0


func _build_reactor_marker() -> void:
	if is_instance_valid(_reactor):
		_reactor.queue_free()
	_reactor = MeshInstance3D.new()
	_reactor.name = "ReactorTarget"
	var marker := BoxMesh.new()
	marker.size = Vector3(0.32, 0.25, 0.035) if enemy_kind != "boss" else Vector3(0.8, 0.45, 0.045)
	_reactor.mesh = marker
	_reactor.material_override = _reactor_material
	_reactor.position = _core_point
	_rig.add_child(_reactor)


func _connected_components() -> Array[Dictionary]:
	var visited := PackedByteArray()
	visited.resize(_voxels.size())
	visited.fill(0)
	var result: Array[Dictionary] = []
	for seed in range(_voxels.size()):
		if _voxels[seed] == 0 or visited[seed] != 0:
			continue
		var queue := PackedInt32Array([seed])
		var group := PackedInt32Array()
		var flags := 0
		var head := 0
		visited[seed] = 1
		while head < queue.size():
			var current: int = queue[head]
			head += 1
			group.append(current)
			flags |= _tags[current]
			var coords: Vector3i = _coords(current)
			for direction in DIRECTIONS:
				var neighbor: Vector3i = coords + direction
				if not _inside(neighbor):
					continue
				var next: int = _index(neighbor.x, neighbor.y, neighbor.z)
				if _voxels[next] != 0 and visited[next] == 0:
					visited[next] = 1
					queue.append(next)
		result.append({"indices": group, "flags": flags})
	return result


func _rebuild_body() -> void:
	var groups: Array[PackedInt32Array] = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	for index in range(_voxels.size()):
		if _voxels[index] != 0:
			groups[_part_for_index(index)].append(index)
	for part_index in range(3):
		var indices: PackedInt32Array = groups[part_index]
		var membership: Dictionary = {}
		for index in indices:
			membership[index] = true
		_part_meshes[part_index].mesh = _build_mesh(indices, Vector3.ZERO, membership)
		_part_meshes[part_index].visible = not indices.is_empty()
	_refresh_weapon_visibility()


func _build_mesh(indices: PackedInt32Array, origin: Vector3, membership: Dictionary = {}) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var face_count := 0
	for index in indices:
		var coords: Vector3i = _coords(index)
		var point: Vector3 = _point(coords.x, coords.y, coords.z) - origin
		var color: Color = PALETTE[_voxels[index]]
		for side in range(6):
			var neighbor: Vector3i = coords + DIRECTIONS[side]
			var neighbor_index: int = _index(neighbor.x, neighbor.y, neighbor.z) if _inside(neighbor) else -1
			if neighbor_index >= 0 and _voxels[neighbor_index] != 0 and (membership.is_empty() or membership.has(neighbor_index)):
				continue
			_add_face(surface, point, side, color)
			face_count += 1
	if face_count == 0:
		return null
	return surface.commit()


func _add_face(surface: SurfaceTool, center: Vector3, side: int, color: Color) -> void:
	var normal := Vector3(DIRECTIONS[side])
	var tangent: Vector3 = Vector3.UP if side < 2 else Vector3.RIGHT
	var bitangent: Vector3 = normal.cross(tangent)
	var half := _cell * 0.5
	var face_center := center + normal * half
	var a := face_center + (tangent + bitangent) * half
	var b := face_center + (tangent - bitangent) * half
	var c := face_center + (-tangent - bitangent) * half
	var d := face_center + (-tangent + bitangent) * half
	var shade: float = 0.84 + maxf(normal.y, 0.0) * 0.16
	var shaded := Color(color.r * shade, color.g * shade, color.b * shade, 1.0)
	for vertex in [a, b, c, a, c, d]:
		surface.set_normal(normal)
		surface.set_color(shaded)
		surface.add_vertex(vertex)


func _spawn_fragment(indices: PackedInt32Array, stroke: Vector2, lethal: bool) -> bool:
	if indices.is_empty():
		return false
	var groups: Dictionary = {}
	for index in indices:
		var part: int = _part_for_index(index)
		if not groups.has(part):
			groups[part] = PackedInt32Array()
		groups[part].append(index)
	var piece_count := 0
	for child in get_children():
		if child.get_meta("voxel_piece", false) and not child.is_queued_for_deletion():
			piece_count += 1
	if piece_count + groups.size() > DebrisScript.MAX_VOXEL_PIECES:
		# Budget limits motion, never the amount of remaining visible material.
		return false
	for part in groups:
		_spawn_posed_fragment(groups[part], int(part), stroke, lethal)
	return true


func _spawn_posed_fragment(indices: PackedInt32Array, part: int, stroke: Vector2, lethal: bool) -> void:
	var center := Vector3.ZERO
	var lowest_y := INF
	var cells: Dictionary = {}
	var pose: Transform3D = _part_pose(part)
	for index in indices:
		var coords: Vector3i = _coords(index)
		var voxel_point: Vector3 = _point(coords.x, coords.y, coords.z)
		center += voxel_point
		lowest_y = minf(lowest_y, (pose * voxel_point).y)
		cells[coords] = int(_voxels[index])
	center /= float(indices.size())
	var fragment = DebrisScript.new()
	fragment.name = "SeveredVoxelChunk"
	fragment.transform = pose * Transform3D(Basis.IDENTITY, center)
	fragment.floor_height = maxf(0.08, fragment.position.y - lowest_y + _cell * 0.5)
	var side: float = signf(center.x)
	if is_zero_approx(side):
		side = _rng.randf_range(-1.0, 1.0)
	var direction := stroke.normalized()
	if bool(get_meta("flythrough_enabled", false)):
		var cut_normal := Vector3(-direction.y, -direction.x, 0.0)
		var separation_side: float = signf(((pose * center) - _cut_origin).dot(cut_normal))
		var separation: Vector3 = cut_normal * separation_side * (4.5 if lethal else 2.5)
		fragment.velocity = Vector3(side * 2.0 + direction.x * 4.6, 2.4 - direction.y * 2.3, _rng.randf_range(11.0, 18.0) if lethal else _rng.randf_range(8.0, 13.0)) + separation
		fragment.spin = Vector3(_rng.randf_range(-3.8, 3.8), _rng.randf_range(-2.4, 2.4), -direction.x * 4.5)
	else:
		fragment.velocity = Vector3(side * 1.5 + direction.x * 1.7, 1.6 - direction.y, 2.2 if lethal else 1.1)
		fragment.spin = Vector3(_rng.randf_range(-1.4, 1.4), _rng.randf_range(-1.1, 1.1), -direction.x * 1.5)
	add_child(fragment)
	fragment.configure_voxels(cells, _cell, PALETTE, _material, _point(0, 0, 0) - center)


func get_cut_particle_debug_state() -> Dictionary:
	var batch := get_node_or_null("CutVoxelBurst")
	return batch.get_debug_state() if is_instance_valid(batch) else {"active_count": 0, "emitted_total": 0, "emitted_body": 0, "emitted_debris": 0}


func _index(x: int, y: int, z: int) -> int:
	return x + _dimensions.x * (y + _dimensions.y * z)


func _coords(index: int) -> Vector3i:
	var x: int = index % _dimensions.x
	var y: int = (index / _dimensions.x) % _dimensions.y
	var z: int = index / (_dimensions.x * _dimensions.y)
	return Vector3i(x, y, z)


func _point(x: int, y: int, z: int) -> Vector3:
	return Vector3((float(x) - float(_dimensions.x - 1) * 0.5) * _cell, (float(y) + 0.5) * _cell, (float(z) - float(_dimensions.z - 1) * 0.5) * _cell)


func _inside(point: Vector3i) -> bool:
	return point.x >= 0 and point.y >= 0 and point.z >= 0 and point.x < _dimensions.x and point.y < _dimensions.y and point.z < _dimensions.z


func _segment_overlaps_rect(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	if rect.has_point(from) or rect.has_point(to):
		return true
	var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for side in range(4):
		if Geometry2D.segment_intersects_segment(from, to, corners[side], corners[(side + 1) % 4]) != null:
			return true
	return false
