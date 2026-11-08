class_name VoxelEnemy
extends Node3D

signal severed(enemy: Node3D, world_point: Vector3, removed_count: int)
signal damaged(enemy: Node3D, world_point: Vector3, removed_count: int)

const DebrisScript = preload("res://scripts/voxel_debris.gd")
const MotionScript = preload("res://scripts/enemy_motion.gd")
const ArchetypesScript = preload("res://scripts/enemy_archetypes.gd")
const PART_COUNT := 10
const FULL_MESH_MASK := (1 << PART_COUNT)-1
const HEAD_TAG := 1
const CORE_TAG := 2
const ANCHOR_TAG := 4
const BOSS_LEFT_REACTOR_TAG := 8
const BOSS_RIGHT_REACTOR_TAG := 16
const BOSS_REACTOR_POINTS: Array[Vector3] = [Vector3(-1.08,3.04,-0.65),Vector3(1.08,3.04,-0.65)]
const DIRECTIONS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const PALETTE: Array[Color] = [
	Color.TRANSPARENT, Color("c5bcaa"), Color("27313a"),
	Color("b56d42"), Color("58bfc6"), Color("62696b"),
	Color("ebe4d1"), Color("11181c"), Color("a96a29"), Color("8a8880"), Color("ffb53a"),
]
static var _body_templates: Dictionary = {}
static var _shared_body_shader: Shader

var enemy_kind := "normal"
var resolved := false
var dead := false
var attack_done := 0
var fire_timer := 0.0
var age := 0.0
var lane_index := 0
var construct_variant := 0
var last_cut_usec := 0
var last_removed_count := 0
var cut_count := 0

var _dimensions := Vector3i(15, 27, 8)
var _cell := 0.1
var _voxels := PackedByteArray()
var _tags := PackedByteArray()
var _live_indices := PackedInt32Array()
var _part_ids := PackedByteArray()
var _cell_points := PackedVector3Array()
var _fine_neighbors := PackedInt32Array()
var _initial_meshes: Array = []
var _mesh_cell_counts := PackedInt32Array()
var _mesh_slice_indices: Array[Dictionary] = []
var _mesh_slice_arrays: Array[Dictionary] = []
var _mesh_dirty_slices: Array[Dictionary] = []
var _mesh_slice_ready := false
var _mesh_full_dirty_mask := 0
var _last_rebuilt_slices := 0
var _last_reused_slices := 0
var _next_mesh_mask := FULL_MESH_MASK
var _body: MeshInstance3D
var _reactor: MeshInstance3D
var _reactor_material: StandardMaterial3D
var _material: Material
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
var _expansion_glows: Array[MeshInstance3D] = []
var _depth_columns: Dictionary = {}
var _walk_distance := 0.0
var _walk_last_age := 0.0
var _walk_weight := 1.0
var _hand_cache: Dictionary = {}
var _emitter_cache: Dictionary = {}
var _ranged_hold_initialized := false
var _ranged_seen_front_target := false
var _ranged_last_pose_age := 0.0
var _ranged_aim_direction := Vector3.BACK
var _ranged_left_hold := Vector3.ZERO
var _ranged_right_hold := Vector3.ZERO
var _boss_reactor_connected: Array[bool] = [true,true]
var _boss_sensor_connected := true


static func prewarm_normal_model() -> void:
	prewarm_models(["normal"])


static func prewarm_models(kinds: Array) -> void:
	# One data-only holder, never inserted into the scene tree: no arm, weapon
	# or debris nodes are constructed, and the holder is freed immediately.
	for kind in kinds:
		for variant in range(3 if kind in ["barrier","beam"] else 1):
			var template_key := _model_template_key(kind,variant)
			if _body_templates.has(template_key):
				continue
			var baker = load("res://scripts/voxel_enemy.gd").new()
			baker.enemy_kind = kind
			baker.construct_variant = variant
			baker._set_model_dimensions(kind)
			baker._build_voxel_data()
			var grouped: Array = []
			for part in range(PART_COUNT): grouped.append(PackedInt32Array())
			for index in baker._live_indices:
				grouped[baker._part_ids[index]].append(index)
			var meshes: Array = []
			for indices: PackedInt32Array in grouped:
				var membership: Dictionary = {}
				for index in indices:
					membership[index] = true
				meshes.append(baker._build_mesh(indices, Vector3.ZERO, membership))
			baker._create_materials()
			_body_templates[template_key] = baker._make_template(meshes)
			baker.free()


static func _model_template_key(kind: String, variant: int) -> String:
	return "%s:%d" % [kind,posmod(variant,3)] if kind in ["barrier","beam"] else kind


func configure(kind: String, lane: int = 0, variant: int = -1) -> void:
	_hand_cache.clear()
	_emitter_cache.clear()
	_ranged_hold_initialized = false
	_ranged_seen_front_target = false
	_ranged_last_pose_age = 0.0
	_ranged_aim_direction = Vector3.BACK
	for child in get_children():
		if child.get_meta("voxel_piece", false) or child.get_meta("cut_chip", false) or child.get_meta("cut_particle_batch", false):
			child.queue_free()
	enemy_kind = kind
	lane_index = lane
	# Variants do not draw from the encounter RNG. Normal two-argument spawns
	# select all three silhouettes through their lane; explicit previews can
	# request one without changing the lane or collision/critical-point rules.
	construct_variant = posmod(variant if variant >= 0 else lane-1,3) if _is_construct() else 0
	dead = false
	_boss_reactor_connected = [true,true]
	_boss_sensor_connected = true
	resolved = false
	attack_done = 0
	fire_timer = 0.0
	age = 0.0
	_walk_distance = 0.0
	_walk_last_age = 0.0
	_walk_weight = 1.0
	_rng.randomize()
	_set_model_dimensions(kind)
	var template_key := _model_template_key(kind,construct_variant)
	var cached := _body_templates.has(template_key)
	_initial_meshes.clear()
	_next_mesh_mask = FULL_MESH_MASK
	_mesh_slice_indices = []
	_mesh_slice_arrays = []
	_mesh_dirty_slices = []
	_mesh_slice_ready = false
	_mesh_full_dirty_mask = 0
	if cached:
		var template: Dictionary = _body_templates[template_key]
		# Packed occupancy and tags remain private to each actor. Initial meshes
		# are immutable resources; a real cut replaces only that actor's mesh.
		_voxels = template.voxels.duplicate()
		_tags = template.tags.duplicate()
		_live_indices = template.live.duplicate()
		_part_ids = template.parts.duplicate()
		_cell_points = template.points.duplicate()
		_fine_neighbors = template.neighbors.duplicate()
		_depth_columns = template.get("columns",{}).duplicate()
		_core_point = template.core
		_initial_meshes = template.meshes.duplicate()
		if template.has("slice_indices"):
			_mesh_slice_indices = _copy_slice_dictionaries(template.slice_indices)
			_mesh_slice_arrays = _copy_slice_dictionaries(template.slice_arrays)
			for part in range(PART_COUNT): _mesh_dirty_slices.append({})
			_mesh_slice_ready = true
	else:
		_build_voxel_data()
	_create_materials()
	_build_action_rig()
	_rebuild_body()
	if not cached:
		var meshes: Array = []
		for part in _part_meshes:
			meshes.append(part.mesh)
		_body_templates[template_key] = _make_template(meshes)
	_build_reactor_marker()
	_configured = true
	set_action("run", 0.0)


func _set_model_dimensions(kind: String) -> void:
	if ArchetypesScript.supports(kind):
		var layout: Dictionary = ArchetypesScript.dimensions(kind)
		_dimensions = layout.dimensions
		_cell = float(layout.cell)
		return
	match kind:
		"normal":
			_dimensions = Vector3i(34, 56, 22)
			_cell = 0.05
		"tank":
			_dimensions = Vector3i(48, 44, 22)
			_cell = 0.075
		"boss":
			_dimensions = Vector3i(92, 60, 40)
			_cell = 0.075
		"ranged":
			_dimensions = Vector3i(34, 62, 24)
			_cell = 0.05
		"drone":
			_dimensions = Vector3i(36, 34, 20)
			_cell = 0.08
		"missile_drone":
			_dimensions = Vector3i(48, 38, 26)
			_cell = 0.08
		"barrier":
			_dimensions = Vector3i(56, 34, 10)
			_cell = 0.08
		"beam":
			_dimensions = Vector3i(72, 38, 12)
			_cell = 0.08
		_:
			_dimensions = Vector3i(15, 27, 8)
			_cell = 0.1


func _build_voxel_data() -> void:
	_voxels.resize(_dimensions.x * _dimensions.y * _dimensions.z)
	_voxels.fill(0)
	_tags.resize(_voxels.size())
	_tags.fill(0)
	_build_robot()
	_live_indices.clear()
	_fine_neighbors.clear()
	_depth_columns.clear()
	_part_ids.resize(_voxels.size())
	_cell_points.resize(_voxels.size())
	for index in range(_voxels.size()):
		if _uses_fine_grid() and _voxels[index] == 0:
			continue
		_part_ids[index] = _classify_part_index(index)
		var coordinate := _coords(index)
		_cell_points[index] = _point(coordinate.x, coordinate.y, coordinate.z)
		if _voxels[index] != 0:
			_live_indices.append(index)
			if enemy_kind in ["tank","boss","shield_drone"]:
				var key := coordinate.x+coordinate.y*_dimensions.x
				if not _depth_columns.has(key): _depth_columns[key] = PackedInt32Array()
				_depth_columns[key].append(index)
	if _uses_fine_grid():
		_cache_fine_neighbors()


func _uses_fine_grid() -> bool:
	return ArchetypesScript.supports(enemy_kind) or enemy_kind in ["normal", "tank", "ranged", "boss", "drone", "missile_drone", "barrier", "beam"]


func _is_flying() -> bool:
	return ArchetypesScript.supports(enemy_kind) or enemy_kind in ["drone", "missile_drone"]


func _is_construct() -> bool:
	return enemy_kind in ["barrier", "beam"]


func _make_template(meshes: Array) -> Dictionary:
	if not _mesh_slice_ready and _uses_fine_grid(): _seed_mesh_slices(meshes)
	var result := {"voxels":_voxels.duplicate(), "tags":_tags.duplicate(), "live":_live_indices.duplicate(), "parts":_part_ids.duplicate(), "points":_cell_points.duplicate(), "neighbors":_fine_neighbors.duplicate(), "columns":_depth_columns.duplicate(), "core":_core_point, "meshes":meshes}
	if _mesh_slice_ready:
		result["slice_indices"] = _copy_slice_dictionaries(_mesh_slice_indices)
		result["slice_arrays"] = _copy_slice_dictionaries(_mesh_slice_arrays)
	return result


func get_aim_point() -> Vector3:
	if enemy_kind == "boss" and not dead:
		var active := 0 if _boss_reactor_connected[0] else 1
		var point := BOSS_REACTOR_POINTS[active]
		# The visible inset port identifies an intact cassette, rather than the
		# decorative central vent or a reactor that was already cut away.
		point.z = 0.84
		return _rig.to_global(point) if is_instance_valid(_rig) else to_global(point)
	return _rig.to_global(_core_point) if is_instance_valid(_rig) else to_global(_core_point)


func get_boss_reactor_state() -> Dictionary:
	# Cached from the same components that commit actual cuts. Reading this
	# for encounter pacing/HUD never runs a per-frame connectivity scan.
	var connected := 0
	var positions: Array[Vector3] = []
	for index in range(BOSS_REACTOR_POINTS.size()):
		if _boss_reactor_connected[index] and not dead: connected += 1
		positions.append(to_global(_part_pose(0)*BOSS_REACTOR_POINTS[index]))
	return {"total":2,"connected":connected,"active":_boss_reactor_connected.duplicate(),"world_positions":positions,"sensor_connected":_boss_sensor_connected}


func _refresh_boss_reactors(groups: Array[Dictionary]) -> void:
	_boss_reactor_connected = [false,false]
	_boss_sensor_connected = false
	for group: Dictionary in groups:
		var flags: int = group.flags
		if flags & ANCHOR_TAG:
			if flags & BOSS_LEFT_REACTOR_TAG: _boss_reactor_connected[0] = true
			if flags & BOSS_RIGHT_REACTOR_TAG: _boss_reactor_connected[1] = true
			if flags & HEAD_TAG: _boss_sensor_connected = true
	if _material is ShaderMaterial:
		_material.set_shader_parameter("boss_reactor_power",Vector2(1.0 if _boss_reactor_connected[0] else 0.0,1.0 if _boss_reactor_connected[1] else 0.0))


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
	if _material is ShaderMaterial:
		_material.set_shader_parameter("warning", _warning)
	if is_instance_valid(_reactor_material):
		_reactor_material.albedo_color = Color("72fce1").lerp(Color("ff3a29"), _warning)
		_reactor_material.emission = _reactor_material.albedo_color
		_reactor_material.emission_energy_multiplier = 1.8 + _warning * 2.5


func set_action_variant(index: int) -> void:
	action_variant = index


func get_muzzle_point() -> Vector3:
	if ArchetypesScript.supports(enemy_kind):
		var emitters: Array[Dictionary] = ArchetypesScript.emitters(enemy_kind)
		var emitter: Dictionary = emitters[0]
		return to_global(_part_pose(int(emitter.part))*Vector3(emitter.point))
	if _is_flying():
		var local := Vector3(0, 1.98, 0.36) if enemy_kind == "drone" else Vector3(1.08, 2.12, 0.52)
		return to_global(_part_pose(0 if enemy_kind == "drone" else 2) * local)
	if not _weapons.is_empty():
		return _weapons[0].to_global(_weapons[0].get_meta("muzzle_local",Vector3(0.0,0.0,0.86)))
	return get_aim_point()


func get_ranged_origins() -> Array[Vector3]:
	var origins: Array[Vector3] = []
	if dead or not _configured:
		return origins
	if ArchetypesScript.supports(enemy_kind):
		for emitter: Dictionary in ArchetypesScript.emitters(enemy_kind):
			if _emitter_intact(int(emitter.part)):
				origins.append(to_global(_part_pose(int(emitter.part))*Vector3(emitter.point)))
	elif enemy_kind == "drone":
		if _emitter_intact(0):
			origins.append(get_muzzle_point())
	elif enemy_kind == "missile_drone":
		for part in [2, 1]:
			if _emitter_intact(part):
				origins.append(to_global(_part_pose(part) * Vector3(1.08 if part == 2 else -1.08, 2.12, 0.52)))
	elif enemy_kind == "boss":
		for index in range(_weapons.size()):
			if _hand_intact(2 if index == 0 else 1):
				origins.append(_weapons[index].to_global(_weapons[index].get_meta("muzzle_local",Vector3.ZERO)))
	elif enemy_kind == "ranged" and has_attack_limb():
		origins.append(get_muzzle_point())
	return origins


func has_attack_limb(variant: int = -1) -> bool:
	if dead or not _configured:
		return false
	if ArchetypesScript.supports(enemy_kind):
		for emitter: Dictionary in ArchetypesScript.emitters(enemy_kind):
			if _emitter_intact(int(emitter.part)): return true
		return false
	var selected: int = action_variant if variant < 0 else variant
	match enemy_kind:
		"barrier", "beam":
			return false
		"drone":
			return _emitter_intact(0)
		"missile_drone":
			return _emitter_intact(1) or _emitter_intact(2)
		"tank":
			return _hand_intact(2 if selected % 2 == 0 else 1)
		"boss":
			return _hand_intact(2) if selected % 2 == 0 else (_hand_intact(1) or _hand_intact(2))
		_:
			return _hand_intact(2)


func _emitter_intact(part: int) -> bool:
	if not _emitter_cache.has(part):
		_emitter_cache[part] = _scan_emitter_intact(part)
	return bool(_emitter_cache[part])


func _scan_emitter_intact(part: int) -> bool:
	if ArchetypesScript.supports(enemy_kind): return ArchetypesScript.emitter_intact(self,part)
	# Only surviving forward launch hardware counts. A rear wing stump must
	# not keep firing after its actual gun / launch mouth has been sliced off.
	for index in _live_indices:
		if _voxels[index] == 0 or _part_ids[index] != part:
			continue
		var point: Vector3 = _cell_points[index]
		if enemy_kind == "drone":
			if absf(point.x) < 0.13 and absf(point.y-1.98) < 0.10 and point.z > 0.26:
				return true
		elif absf(absf(point.x)-1.08) < 0.22 and absf(point.y-2.12) < 0.20 and point.z > 0.37:
			return true
	return false


func set_action(action: String, phase: float) -> void:
	if not _configured:
		return
	if dead:
		_hide_action_props()
		return
	if _is_flying() or _is_construct():
		_set_expansion_action(action, phase)
		return
	var gait: Dictionary = {}
	var ranged_delta := maxf(age-_ranged_last_pose_age,0.0)
	if enemy_kind in ["normal","tank","ranged","boss"]:
		var delta := maxf(age-_walk_last_age,0.0)
		_walk_last_age = age
		if action == "run": _walk_distance += delta*maxf(0.0,float(get_meta("ground_run_speed",2.8)))
		_walk_weight = move_toward(_walk_weight,1.0 if action == "run" else 0.0,delta*7.0)
		var step_length := 0.90 if enemy_kind == "normal" else (1.00 if enemy_kind == "tank" else (0.95 if enemy_kind == "ranged" else 1.10))
		gait = MotionScript.sample_feet(_walk_distance*0.6,step_length,0.15 if enemy_kind == "normal" else 0.12)
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
	if enemy_kind == "normal":
		# The blade fighter carries its weapon across the body rather than
		# hanging a long straight blade through the floor between attacks.
		var ready_weight := 1.0 if action == "run" else (smooth if action == "recover" else 0.0)
		right_arm.z -= ready_weight * 0.68
		left_arm.z += ready_weight * 0.12
	if enemy_kind in ["normal","tank","ranged","boss"]:
		if action == "run": body_offset.y = 0.0
		var crouch := 0.23 if enemy_kind == "normal" else (0.27 if enemy_kind == "tank" else 0.21)
		body_offset.y += (-crouch+float(gait.body_bob))*_walk_weight
		body_angles.z += float(gait.body_roll)*_walk_weight
		left_arm.x += float(gait.left_arm)*_walk_weight
		right_arm.x += float(gait.right_arm)*_walk_weight
	if enemy_kind == "ranged":
		# A rifle is carried by both hands, not counter-swung like a sword.
		# Retain small shoulder compensation, bracing and recoil around its hold.
		var brace := smooth if action == "ranged_charge" else (1.0 if action == "ranged_fire" else (1.0-smooth if action == "recover" else 0.0))
		var kick := sin(minf(p*2.0,1.0)*PI)*(1.0-p) if action == "ranged_fire" else (0.55*sin(p*PI) if action == "stagger" else 0.0)
		var thrust := sin(p*PI) if action == "strike" else -0.35*smooth if action == "windup" else 0.0
		var compensation := float(gait.left_arm)*0.06*_walk_weight
		var right_hold := Vector3(-0.07*brace+0.06*kick+0.10*thrust+compensation,0,-0.025*brace)
		var left_hold := Vector3(-0.05*brace+0.04*kick+0.08*thrust+compensation,0,0.018*brace)
		var blend := 1.0 if not _ranged_hold_initialized else 1.0-exp(-ranged_delta*18.0)
		_ranged_right_hold = _ranged_right_hold.lerp(right_hold,blend)
		_ranged_left_hold = _ranged_left_hold.lerp(left_hold,blend)
		right_arm = _ranged_right_hold
		left_arm = _ranged_left_hold
	_pose(body_angles, body_offset, left_arm, right_arm)
	if enemy_kind in ["normal","tank","ranged","boss"]: _pose_walking_legs(gait)
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
		_update_ranged_hold(ranged_delta)
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


func _update_ranged_hold(sim_delta: float) -> void:
	var gun: Node3D = _weapons[0]
	gun.position = Vector3(0.53,1.84,0.20)
	var target: Vector3 = get_meta("aim_target",Vector3(0,1.7,0))
	var to_target := global_basis.inverse()*(target-gun.global_position)
	var forward := global_basis.z.normalized()
	var desired := forward
	var front_target := to_target.z > 0.10 and str(get_meta("action_state","run")) != "exit"
	if front_target:
		# A first-person rifle can track a lane-wide target without twisting its
		# wrist around the back when it passes the player's plane or exits.
		var yaw := clampf(atan2(to_target.x,to_target.z),-0.80,0.80)
		var pitch := clampf(atan2(to_target.y,Vector2(to_target.x,to_target.z).length()),-0.38,0.38)
		desired = (global_basis*Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))).normalized()
	if not _ranged_hold_initialized or (front_target and not _ranged_seen_front_target):
		_ranged_aim_direction = desired
	else:
		var angle := _ranged_aim_direction.angle_to(desired)
		if angle > 0.00001:
			_ranged_aim_direction = _ranged_aim_direction.slerp(desired,minf(1.0,sim_delta*4.8/angle)).normalized()
	_ranged_seen_front_target = _ranged_seen_front_target or front_target
	var gun_basis := Basis.looking_at(_ranged_aim_direction,global_basis.y.normalized(),true)
	var trigger_palm := to_global(_part_pose(2)*Vector3(0.53,1.84,0.22))
	gun.global_transform = Transform3D(gun_basis,trigger_palm-gun_basis*Vector3(0,0,0.02))
	# The support forearm/palm remains part 1; its upper arm has its own real
	# material group. Rigid two-bone IK fixes shoulder, elbow and foregrip
	# together without translating the shoulder or stretching occupied cubes.
	var shoulder := Vector3(-0.37,2.42,0)
	var elbow := Vector3(-0.55,2.04,0.04)
	var palm := Vector3(0.37,1.83,0.44)
	var desired_palm := _rig.to_local(gun.to_global(Vector3(-0.16,-0.01,0.24))) if _hand_intact(1) else shoulder+Vector3(-0.18,-1.05,0.05)
	var arm: Dictionary = MotionScript.solve_leg(shoulder,elbow,palm,desired_palm,elbow-shoulder)
	_parts[9].transform = arm.upper
	_parts[1].transform = arm.lower
	_ranged_hold_initialized = true
	_ranged_last_pose_age = age


func _set_expansion_action(action: String, phase: float) -> void:
	if ArchetypesScript.supports(enemy_kind):
		ArchetypesScript.apply_pose(self,action,phase)
		return
	action_name = action
	action_phase = clampf(phase, 0.0, 1.0)
	if _is_construct():
		_rig.transform = Transform3D.IDENTITY
		for part in [1, 2]:
			_parts[part].transform = Transform3D.IDENTITY
		return
	var charge := smoothstep(0.0, 1.0, action_phase) if action == "ranged_charge" else 0.0
	var kick := sin(minf(action_phase * 2.0, 1.0) * PI) * (1.0-action_phase) if action == "ranged_fire" else 0.0
	var hover := 0.045 * sin(age * 4.4 + float(lane_index))
	var bank := 0.04 * sin(age * 2.4) * (1.0-charge)
	var pivot := Vector3(0, 2.10, 0)
	var angles := Vector3(-0.11*charge-0.07*kick,0.025*sin(age*1.7),bank)
	var offset := Vector3(0,hover,-0.12*kick)
	var fold := charge * 0.08
	match action:
		"windup":
			var lift := smoothstep(0.0,0.82,action_phase)
			angles.x = -0.27*lift
			offset += Vector3(0,0.12*lift,-0.22*lift)
			fold = -0.16*lift
		"strike":
			var dive := smoothstep(0.05,0.55,action_phase)
			var follow := smoothstep(0.55,1.0,action_phase)
			angles.x = lerpf(-0.27,0.42,dive)-0.22*follow
			offset += Vector3(0,lerpf(0.12,-0.32,dive)+0.12*follow,0.12*sin(action_phase*PI))
			fold = lerpf(-0.16,0.18,dive)
		"recover", "stagger":
			var release := 1.0-smoothstep(0.0,1.0,action_phase)
			angles.x = (0.20 if action == "recover" else -0.23)*release
			offset += Vector3(0,-0.20*release,-0.18*sin(action_phase*PI))
			fold = 0.10*release
	var body_basis := Basis.from_euler(angles)
	_rig.transform = Transform3D(body_basis, pivot-body_basis*pivot+offset)
	for part in [1, 2]:
		var side := -1.0 if part == 1 else 1.0
		var wing_pivot := Vector3(side*(0.38 if enemy_kind == "drone" else 0.60),2.12,0)
		var wing_basis := Basis.from_euler(Vector3(-0.05*charge,0,side*(-fold+0.025*sin(age*3.1))))
		_parts[part].transform = Transform3D(wing_basis,wing_pivot-wing_basis*wing_pivot)
	if enemy_kind == "drone":
		for rotor in range(2):
			var side := -1.0 if rotor == 0 else 1.0
			var centre := Vector3(side*0.94,2.0,0.12)
			var rotor_basis := Basis(Vector3.FORWARD,age*TAU*(7.0+charge*3.0)*side)
			_parts[3+rotor].transform = _parts[1+rotor].transform*Transform3D(rotor_basis,centre-rotor_basis*centre)
	for glow in _expansion_glows:
		var part := int(glow.get_meta("emitter_part"))
		glow.visible = (charge > 0.03 or kick > 0.05) and _emitter_intact(part)
		glow.scale = Vector3.ONE * (0.35+charge*0.80+kick*0.8)
	_weapon_edge_material.albedo_color = Color("ff9b36").lerp(Color("fff1b8"),charge)
	_weapon_edge_material.emission_energy_multiplier = 0.8+charge*2.0
	_trail.visible = false


func _part_for_index(index: int) -> int:
	return int(_part_ids[index])


func _classify_part_index(index: int) -> int:
	var coords: Vector3i = _coords(index)
	var center_x: int = _dimensions.x / 2
	if _is_construct():
		return 0
	if _is_flying():
		var point := _point(coords.x, coords.y, coords.z)
		if ArchetypesScript.supports(enemy_kind): return ArchetypesScript.classify_part(enemy_kind,point)
		if enemy_kind == "drone" and point.z > 0.075:
			for rotor in range(2):
				var centre := Vector2(-0.94 if rotor == 0 else 0.94,2.0)
				if Vector2(point.x,point.y).distance_squared_to(centre) < 0.245*0.245:
					return 3+rotor
		var boundary := 0.38 if enemy_kind == "drone" else 0.60
		return (1 if point.x < 0.0 else 2) if absf(point.x) > boundary else 0
	if enemy_kind in ["normal","tank","ranged","boss"]:
		var point := _point(coords.x,coords.y,coords.z)
		var pelvis := 1.10 if enemy_kind == "normal" else (1.12 if enemy_kind == "tank" else (1.43 if enemy_kind == "ranged" else 1.65))
		var knee := 0.76 if enemy_kind == "normal" else (0.84 if enemy_kind == "tank" else (0.86 if enemy_kind == "ranged" else 1.10))
		var foot := 0.23 if enemy_kind == "normal" else (0.30 if enemy_kind == "tank" else (0.20 if enemy_kind == "ranged" else 0.34))
		if point.y < pelvis:
			var right := 1 if point.x > 0.0 else 0
			if point.y <= foot: return 7+right
			if point.y <= knee: return 5+right
			return 3+right
	if enemy_kind == "normal":
		var point := _point(coords.x, coords.y, coords.z)
		if point.y >= 1.14 and point.y <= 2.31:
			var arm_boundary := 0.49 if point.y < 1.40 else 0.39
			if point.x < -arm_boundary:
				return 1
			if point.x > arm_boundary:
				return 2
	elif enemy_kind in ["tank","boss","ranged"]:
		var point := _point(coords.x, coords.y, coords.z)
		if enemy_kind == "ranged":
			var elbow := Vector3(-0.55,2.04,0.04)
			var palm := Vector3(0.36,1.83,0.43)
			var line := palm-elbow
			var nearest := elbow+line*clampf((point-elbow).dot(line)/line.length_squared(),0.0,1.0)
			if point.y <= 2.04 and point.distance_squared_to(nearest) <= 0.075*0.075+0.000001:
				return 1
		if enemy_kind == "ranged" and point.y > 1.69 and point.y < 1.99 and point.z > 0.30 and point.x < 0.50:
			return 1
		var minimum_y := 1.0 if enemy_kind == "tank" else (1.75 if enemy_kind == "boss" else 1.68)
		var maximum_y := 2.86 if enemy_kind == "tank" else (3.88 if enemy_kind == "boss" else 2.59)
		var boundary := 1.02 if enemy_kind == "tank" else (1.90 if enemy_kind == "boss" else 0.37)
		if point.y >= minimum_y and point.y <= maximum_y and absf(point.x) > boundary:
			if point.x < 0.0: return 9 if enemy_kind == "ranged" and point.y > 2.04 else 1
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
	var pivot := Vector3(0, 2.12 if enemy_kind == "boss" else (1.30 if enemy_kind == "tank" else (1.50 if enemy_kind == "ranged" else 0.95)), 0)
	var body_basis := Basis.from_euler(body_angles)
	_rig.transform = Transform3D(body_basis, pivot - body_basis * pivot + offset)
	var arm_x: float = 1.90 if enemy_kind == "boss" else (1.02 if enemy_kind == "tank" else (0.49 if enemy_kind == "normal" else 0.37))
	var arm_y: float = 3.45 if enemy_kind == "boss" else (2.42 if enemy_kind == "tank" else (2.02 if enemy_kind == "normal" else 2.42))
	for index in [1, 2]:
		var arm_pivot := Vector3(-arm_x if index == 1 else arm_x, arm_y, 0.0)
		var arm_basis := Basis.from_euler(left_angles if index == 1 else right_angles)
		_parts[index].transform = Transform3D(arm_basis, arm_pivot - arm_basis * arm_pivot)


func _pose_walking_legs(gait: Dictionary) -> void:
	var rig_inverse := _rig.transform.affine_inverse()
	for leg in range(2):
		var side := -1.0 if leg == 0 else 1.0
		var hip := Vector3(side*0.22,1.13,-0.08)
		var knee := Vector3(side*0.40,0.75,0.25-side*0.125*0.55)
		var ankle := Vector3(side*0.53,0.23,0.14-side*0.125)
		if enemy_kind == "tank":
			hip = Vector3(side*0.35,1.22,-0.04)
			knee = Vector3(side*0.57,0.82,0.25)
			ankle = Vector3(side*0.69,0.30,0.10-side*0.10)
		elif enemy_kind == "ranged":
			hip = Vector3(side*0.18,1.49,-0.07)
			knee = Vector3(side*0.28,0.85,0.16-side*0.08)
			ankle = Vector3(side*0.34,0.20,0.07-side*0.13)
		elif enemy_kind == "boss":
			hip = Vector3(side*0.58,1.78,-0.10)
			knee = Vector3(side*0.90,1.08,0.28)
			ankle = Vector3(side*1.03,0.34,0.05-side*0.12)
		var step: Vector3 = gait.left if leg == 0 else gait.right
		if enemy_kind == "boss": step = Vector3.ZERO
		step.y *= _walk_weight
		var solved: Dictionary = MotionScript.solve_leg(hip,knee,ankle,rig_inverse*(ankle+step))
		_parts[3+leg].transform = solved.upper
		_parts[5+leg].transform = solved.lower
		var root_ankle: Vector3 = _rig.transform*Vector3(solved.ankle)
		# Feet have a separate posed material group, kept flat on the ground
		# through torso lean and knee flexion. Cutting uses this same transform.
		_parts[7+leg].transform = rig_inverse*Transform3D(Basis.IDENTITY,root_ankle-ankle)


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
	for name_suffix in ["LeftArm","RightArm","LeftThigh","RightThigh","LeftShin","RightShin","LeftFoot","RightFoot","LeftUpperArm"]:
		var part := Node3D.new()
		part.name = name_suffix
		_rig.add_child(part)
		_parts.append(part)
	for index in range(PART_COUNT):
		var mesh := MeshInstance3D.new()
		mesh.name = "TorsoVoxels" if index == 0 else ("ArmVoxels" if index <= 2 else "LegVoxels")
		mesh.material_override = _material
		_parts[index].add_child(mesh)
		_part_meshes.append(mesh)
	_body = _part_meshes[0]
	_weapon_edge_material = _prop_material(Color("ff8844"), true)
	_expansion_glows.clear()
	if ArchetypesScript.supports(enemy_kind):
		for emitter: Dictionary in ArchetypesScript.emitters(enemy_kind):
			var part_index := int(emitter.part)
			var glow := _box_prop(_parts[part_index],Vector3(0.08,0.08,0.035),Vector3(emitter.point),_weapon_edge_material)
			glow.name = "LaunchCharge"
			glow.set_meta("emitter_part",part_index)
			_expansion_glows.append(glow)
	elif _is_flying():
		for part_index in ([0] if enemy_kind == "drone" else [2, 1]):
			var point := Vector3(0, 1.98, 0.37) if enemy_kind == "drone" else Vector3(1.08 if part_index == 2 else -1.08, 2.12, 0.53)
			var glow := _box_prop(_parts[part_index], Vector3(0.08, 0.08, 0.035), point, _weapon_edge_material)
			glow.name = "LaunchCharge"
			glow.set_meta("emitter_part", part_index)
			_expansion_glows.append(glow)
	elif not _is_construct():
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
	if enemy_kind == "ranged" and part == 1:
		return
	var side: float = -1.0 if part == 1 else 1.0
	var arm_x: float = 2.65 if enemy_kind == "boss" else (1.30 if enemy_kind == "tank" else (0.61 if enemy_kind == "normal" else 0.53))
	weapon.position = Vector3(side*arm_x,2.18 if enemy_kind == "boss" else (1.20 if enemy_kind == "tank" else (1.25 if enemy_kind == "normal" else 1.84)),0.20)
	var steel := _prop_material(Color("677d86"))
	var dark := _prop_material(Color("15252d"))
	var gold := _prop_material(Color("aa8560"))
	if enemy_kind == "ranged" and part == 2:
		weapon.set_meta("muzzle_local",Vector3(0,0.04,1.12))
		_box_prop(weapon,Vector3(0.34,0.31,0.73),Vector3(0,0.03,0.30),dark)
		_box_prop(weapon,Vector3(0.37,0.085,0.61),Vector3(0,0.20,0.27),gold)
		_box_prop(weapon,Vector3(0.20,0.20,0.51),Vector3(0,0.04,0.81),steel)
		for edge in [-1.0,1.0]:
			_box_prop(weapon,Vector3(0.25,0.035,0.11),Vector3(0,0.04+edge*0.1075,1.105),dark)
			_box_prop(weapon,Vector3(0.035,0.18,0.11),Vector3(edge*0.1075,0.04,1.105),dark)
		_box_prop(weapon,Vector3(0.13,0.13,0.025),Vector3(0,0.04,1.068),_prop_material(Color("070b0d")))
		_box_prop(weapon,Vector3(0.085,0.07,0.71),Vector3(0,0.275,0.30),steel)
		for fin_z in [0.54,0.70,0.86]:
			_box_prop(weapon,Vector3(0.27,0.075,0.045),Vector3(0,0.17,fin_z),steel)
		_box_prop(weapon,Vector3(0.16,0.21,0.27),Vector3(0,-0.19,0.27),gold)
		for rail in [-1.0,1.0]:
			_box_prop(weapon,Vector3(0.035,0.10,0.47),Vector3(rail*0.19,0.04,0.31),_weapon_edge_material)
		_flash = _box_prop(weapon,Vector3(0.16,0.16,0.18),Vector3(0,0.04,1.15),_prop_material(Color("fff3bd"),true))
		_charge = _box_prop(weapon,Vector3(0.08,0.08,0.04),Vector3(0,0.04,1.13),_weapon_edge_material)
	elif enemy_kind == "tank":
		_box_prop(weapon,Vector3(0.105,0.72,0.105),Vector3(0,-0.32,0),dark)
		_box_prop(weapon,Vector3(0.80,0.46,0.66),Vector3(0,-0.82,0),steel)
		_box_prop(weapon,Vector3(0.82,0.09,0.68),Vector3(0,-1.04,0),gold)
		_box_prop(weapon,Vector3(0.61,0.27,0.035),Vector3(0,-0.79,0.35),dark)
		for vent in [-0.16,0.0,0.16]:
			_box_prop(weapon,Vector3(0.075,0.18,0.05),Vector3(vent,-0.79,0.38),_weapon_edge_material)
	elif enemy_kind == "normal" and part == 2:
		_box_prop(weapon, Vector3(0.105, 0.32, 0.105), Vector3(0, 0.08, 0), dark)
		_box_prop(weapon, Vector3(0.31, 0.065, 0.16), Vector3(0, -0.10, 0), gold)
		_build_slasher_blade(weapon, steel)
	elif enemy_kind == "boss":
		weapon.set_meta("muzzle_local",Vector3(0,0.12,0.92 if part == 2 else 1.20))
		if part == 2:
			_box_prop(weapon,Vector3(0.17,0.46,0.17),Vector3(0,0.08,0),dark)
			_box_prop(weapon,Vector3(0.58,0.14,0.24),Vector3(0,-0.15,0),gold)
			_box_prop(weapon,Vector3(0.40,1.78,0.13),Vector3(0,-1.10,0),steel)
			_box_prop(weapon,Vector3(0.065,1.78,0.16),Vector3(0.22,-1.10,0),_weapon_edge_material)
			_box_prop(weapon,Vector3(0.28,0.25,0.70),Vector3(0,0.12,0.47),dark)
			_box_prop(weapon,Vector3(0.12,0.12,0.08),Vector3(0,0.12,0.87),_weapon_edge_material)
		else:
			_box_prop(weapon,Vector3(0.65,0.56,0.92),Vector3(0,0.10,0.34),dark)
			_box_prop(weapon,Vector3(0.72,0.16,0.74),Vector3(0,0.42,0.29),gold)
			_box_prop(weapon,Vector3(0.46,0.39,0.49),Vector3(0,0.10,0.93),steel)
			_box_prop(weapon,Vector3(0.52,0.45,0.10),Vector3(0,0.10,1.17),dark)
			for vent in [-0.13,0.13]:
				_box_prop(weapon,Vector3(0.07,0.25,0.06),Vector3(vent,0.10,1.23),_weapon_edge_material)
			_charge = _box_prop(weapon,Vector3(0.19,0.19,0.045),Vector3(0,0.10,1.24),_weapon_edge_material)
			_flash = _box_prop(weapon,Vector3(0.25,0.25,0.20),Vector3(0,0.10,1.28),_prop_material(Color("fff3bd"),true))
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
	if not _hand_cache.has(part):
		_hand_cache[part] = _scan_hand_intact(part)
	return bool(_hand_cache[part])


func _scan_hand_intact(part: int) -> bool:
	# Check the hand itself, not a surviving shoulder stub. Otherwise a wrist cut
	# would leave a floating weapon and the attack could still inflict damage.
	if enemy_kind == "normal":
		for index in _live_indices:
			if _voxels[index] != 0 and _part_for_index(index) == part:
				var point: Vector3 = _cell_points[index]
				if point.y >= 1.14 and point.y <= 1.39 and absf(point.x) > 0.49 and point.z > 0.10:
					return true
		return false
	if enemy_kind in ["tank","boss","ranged"]:
		for index in _live_indices:
			if _voxels[index] == 0 or _part_ids[index] != part:
				continue
			var point: Vector3 = _cell_points[index]
			if enemy_kind == "ranged" and part == 1:
				if absf(point.x-0.37) <= 0.11 and absf(point.y-1.83) <= 0.10 and absf(point.z-0.44) <= 0.13: return true
				continue
			var low := 1.02 if enemy_kind == "tank" else (1.92 if enemy_kind == "boss" else 1.70)
			var high := 1.38 if enemy_kind == "tank" else (2.38 if enemy_kind == "boss" else 1.98)
			var reach := 1.12 if enemy_kind == "tank" else (2.25 if enemy_kind == "boss" else 0.40)
			if point.y >= low and point.y <= high and absf(point.x) > reach and point.z > 0.04:
				return true
		return false
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
	for glow in _expansion_glows:
		glow.visible = false
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
		outer_local = Vector3(0, 0.04, 1.12)
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


func blast_at(world_point: Vector3, radius: float) -> Dictionary:
	if dead or not _configured or radius <= 0.0:
		return {"removed": 0, "killed": false}
	var start_time := Time.get_ticks_usec()
	var removed := PackedInt32Array()
	var radius_squared := radius * radius
	var poses: Array[Transform3D] = []
	var relevant: Array[bool] = []
	for part in range(PART_COUNT):
		var pose: Transform3D = global_transform * _part_pose(part)
		poses.append(pose)
		var mesh: ArrayMesh = _part_meshes[part].mesh
		# Only a conservative posed-geometry rejection: the actual sphere / cell
		# distance below still decides every removed voxel, including AoE edges.
		relevant.append(mesh != null and (pose * mesh.get_aabb()).grow(radius).has_point(world_point))
	if not relevant.has(true):
		return {"removed": 0, "killed": false}
	for index in _live_indices:
		if _voxels[index] != 0 and relevant[_part_ids[index]] and (poses[_part_ids[index]] * _cell_points[index]).distance_squared_to(world_point) <= radius_squared:
			removed.append(index)
	if removed.is_empty():
		return {"removed": 0, "killed": false}
	# Explosions alter the same material / connected components as the sword.
	# They do not subtract abstract health or mark the target dead on contact.
	var camera := get_viewport().get_camera_3d()
	# A blast keeps its own feedback even if its caller currently owns a held
	# blade style. Restore the caller's metadata after the synchronous commit.
	var had_held_fx := has_meta("held_cut_fx")
	var previous_held_fx: Variant = get_meta("held_cut_fx",false)
	set_meta("held_cut_fx",false)
	var result: Dictionary = _commit_material_cut(removed, Vector2(1.0,-0.2), camera, start_time)
	if had_held_fx:
		set_meta("held_cut_fx",previous_held_fx)
	else:
		remove_meta("held_cut_fx")
	return result


func trace_projectile(from: Vector3, to: Vector3, radius: float = 0.0) -> Dictionary:
	if dead or not _configured:
		return {"hit": false, "fraction": 1.0}
	var starts := PackedVector3Array()
	var ends := PackedVector3Array()
	var radii: Array[float] = []
	var relevant: Array[bool] = []
	for part in range(PART_COUNT):
		var inverse := (global_transform * _part_pose(part)).affine_inverse()
		var local_from := inverse * from
		var local_to := inverse * to
		var scale := inverse.basis.get_scale().abs()
		var local_radius := maxf(0.0,radius) * maxf(scale.x,maxf(scale.y,scale.z))
		starts.append(local_from)
		ends.append(local_to)
		radii.append(local_radius)
		var mesh: ArrayMesh = _part_meshes[part].mesh
		relevant.append(mesh != null and _segment_box_fraction(local_from,local_to,mesh.get_aabb().grow(local_radius)) < INF)
	if not relevant.has(true):
		return {"hit": false, "fraction": 1.0}
	var earliest := INF
	var hit_index := -1
	for index in _live_indices:
		var part: int = _part_ids[index]
		if _voxels[index] == 0 or not relevant[part]:
			continue
		var half := Vector3.ONE * (_cell * 0.5 + radii[part])
		var fraction := _segment_box_fraction(starts[part], ends[part], AABB(_cell_points[index]-half,half*2.0))
		if fraction < earliest:
			earliest = fraction
			hit_index = index
	if hit_index < 0:
		return {"hit": false, "fraction": 1.0}
	return {"hit": true,"fraction":earliest,"point":from.lerp(to,earliest),"voxel_index":hit_index}


func _segment_box_fraction(from: Vector3, to: Vector3, bounds: AABB) -> float:
	var delta := to-from
	var enter := 0.0
	var leave := 1.0
	for axis in range(3):
		if absf(delta[axis]) < 0.000001:
			if from[axis] < bounds.position[axis] or from[axis] > bounds.end[axis]:
				return INF
		else:
			var a := (bounds.position[axis]-from[axis])/delta[axis]
			var b := (bounds.end[axis]-from[axis])/delta[axis]
			enter = maxf(enter,minf(a,b))
			leave = minf(leave,maxf(a,b))
			if enter > leave:
				return INF
	return enter


func _cut_body(camera: Camera3D, points: PackedVector2Array, power: float, blade_frames: Array = []) -> Dictionary:
	if points.size() < 2:
		return {"removed": 0, "killed": false}
	var start_time: int = Time.get_ticks_usec()
	var aim_point := get_aim_point()
	# Both samples must use the same aim origin. Boss ports can switch after
	# a reactor is lost; comparing a central sample with an offset port would
	# accidentally turn their metre-wide separation into the blade's width.
	var cell_screen: Vector2 = camera.unproject_position(aim_point+_rig.global_basis.x*_cell)
	var core_screen: Vector2 = camera.unproject_position(aim_point)
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
	var depth_budget: int = _dimensions.z
	if enemy_kind in ["tank","shield_drone"]:
		depth_budget = clampi(int(floor(power * 1.40)), 1, _dimensions.z)
	elif enemy_kind == "boss":
		depth_budget = clampi(int(floor(power * 1.25)), 1, _dimensions.z)
	var armored := enemy_kind in ["tank", "boss", "shield_drone"]
	var part_poses: Array[Transform3D] = []
	if armored or _uses_fine_grid():
		for part in range(PART_COUNT):
			part_poses.append(global_transform * _part_pose(part))
	# Depth is counted from the camera-facing surviving layer, so repeat cuts
	# genuinely carve farther into the same material instead of subtracting HP.
	# Heavy armor takes a shallow material bite, not most of a joint at once.
	if _uses_fine_grid() and not armored:
		# The finer slasher grid is mostly air. Project occupied cells only, using
		# the same three posed body parts as the mesh and retained fragments.
		for index in _live_indices:
			if _voxels[index] == 0:
				continue
			var world_point: Vector3 = part_poses[_part_ids[index]] * _cell_points[index]
			if camera.is_position_behind(world_point):
				continue
			var screen := camera.unproject_position(world_point)
			var intersects_path: bool = not regions.is_empty() and DebrisScript.point_in_sweep(screen, regions, band * band)
			for segment in relevant_segments:
				if Geometry2D.get_closest_point_to_segment(screen, points[segment], points[segment+1]).distance_squared_to(screen) <= band*band:
					intersects_path = true
					break
			if intersects_path:
				cut_indices.append(index)
	else:
		cut_indices = _select_coarse_cut(camera, points, relevant_segments, regions, band, depth_budget, armored, part_poses)
	if cut_indices.is_empty():
		last_cut_usec = Time.get_ticks_usec() - start_time
		return {"removed": 0, "killed": false}
	return _commit_material_cut(cut_indices, stroke, camera, start_time)


func _commit_material_cut(cut_indices: PackedInt32Array, stroke: Vector2, camera: Camera3D, start_time: int) -> Dictionary:
	# Integrity depends on occupied material only. Poses leave this cache valid;
	# every real material removal / detached group goes through this commit.
	_hand_cache.clear()
	_emitter_cache.clear()
	var center := Vector3.ZERO
	var spark_sources := PackedVector3Array()
	var poses: Array[Transform3D] = []
	for part in range(PART_COUNT):
		poses.append(_part_pose(part))
	for index in cut_indices:
		var point := to_global(poses[_part_ids[index]] * _cell_points[index])
		center += to_local(point)
		spark_sources.append(point)
	center /= float(cut_indices.size())
	_cut_origin = center
	# Keep the exact posed cut cells before removing material. The visual
	# burst is chosen after connectivity decides whether this is a real sever.
	var dirty_mesh_mask := 0
	var cache_cut := _mesh_slice_ready and cut_indices.size() <= 1024
	var removed_set: Dictionary = {}
	for index in cut_indices:
		dirty_mesh_mask |= 1 << _part_ids[index]
		if cache_cut: removed_set[index] = true
		_voxels[index] = 0
	if cache_cut:
		for index in cut_indices: _mark_removed_mesh_slices(index,removed_set)
	else:
		_mesh_full_dirty_mask |= dirty_mesh_mask
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
	if enemy_kind == "boss":
		_refresh_boss_reactors(groups)
		# The head is a removable sensor. Each real reactor and its own retained
		# base connection can power the remaining machine independently.
		dead = was_dead or not _boss_reactor_connected.has(true)
	else:
		dead = was_dead or not core_survives or not core_connected_to_base or not head_connected_to_base
	if is_instance_valid(camera):
		DebrisScript.emit_cut_particles(self, camera, spark_sources, stroke, _cell, "sever" if dead and not was_dead else "body")
	for group_index in range(groups.size()):
		if not dead:
			var flags: int = groups[group_index].flags
			if enemy_kind == "boss":
				if flags & ANCHOR_TAG and flags & (BOSS_LEFT_REACTOR_TAG|BOSS_RIGHT_REACTOR_TAG): continue
			elif group_index == primary:
				continue
		var indices: PackedInt32Array = groups[group_index]["indices"]
		if _spawn_fragment(indices, stroke, dead):
			for index in indices:
				dirty_mesh_mask |= 1 << _part_ids[index]
				_mesh_full_dirty_mask |= 1 << _part_ids[index]
				_voxels[index] = 0
	_next_mesh_mask = dirty_mesh_mask
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


func _select_coarse_cut(camera: Camera3D, points: PackedVector2Array, relevant_segments: PackedInt32Array, regions: Array[Dictionary], band: float, depth_budget: int, armored: bool, part_poses: Array[Transform3D]) -> PackedInt32Array:
	var cut_indices := PackedInt32Array()
	# Columns contain authored occupied cells only, ordered by their real Z.
	# Removed cells are skipped, while the first *surviving* facing layer still
	# blocks later layers when the narrow blade missed it. Fine grids need not
	# walk their much larger empty bounding volume to preserve this rule.
	for column: PackedInt32Array in _depth_columns.values():
		var pose: Transform3D = part_poses[_part_ids[column[0]]]
		var ascending := pose.basis.z.dot(camera.global_position-pose*_cell_points[column[column.size()/2]]) < 0.0
		var removed_in_column := 0
		for offset in range(column.size()):
			var index: int = column[offset if ascending else column.size()-1-offset]
			if _voxels[index] == 0:
				continue
			var world_point := pose*_cell_points[index]
			if camera.is_position_behind(world_point):
				continue
			var screen := camera.unproject_position(world_point)
			var intersects_path: bool = not regions.is_empty() and DebrisScript.point_in_sweep(screen,regions,band*band)
			for segment in relevant_segments:
				if Geometry2D.get_closest_point_to_segment(screen,points[segment],points[segment+1]).distance_squared_to(screen) <= band*band:
					intersects_path = true
					break
			if not intersects_path:
				break
			if removed_in_column >= depth_budget:
				break
			removed_in_column += 1
			cut_indices.append(index)
	return cut_indices


func _build_robot() -> void:
	if ArchetypesScript.supports(enemy_kind):
		ArchetypesScript.build(self)
		return
	if _is_flying():
		_build_flyer()
		_finish_machine_details()
		return
	if _is_construct():
		_build_construct()
		_finish_machine_details()
		return
	if enemy_kind == "boss":
		_build_boss()
		return
	if enemy_kind == "tank":
		_build_brute()
		return
	if enemy_kind == "ranged":
		_build_gunner()
		return
	if enemy_kind == "normal":
		_build_slasher()
		_finish_machine_details()
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


func _finish_machine_details() -> void:
	if enemy_kind == "drone":
		for side in [-1.0,1.0]:
			_build_duct(Vector3(side*0.94,2.00,-0.19),0.405,0.30)
			_slasher_box(Vector3(side*0.94,1.66,-0.10),Vector3(0.28,0.10,0.26),5)
			_slasher_box(Vector3(side*0.94,2.0,0.04),Vector3(0.17,0.17,0.25),3)
			for blade_side in [-1.0,1.0]:
				_slasher_rod(Vector3(side*0.94,2.0,0.12),Vector3(side*0.94+blade_side*0.20,2.0+blade_side*0.10,0.12),0.05,5)
		_slasher_box(Vector3(-0.17,2.18,-0.15),Vector3(0.13,0.17,0.24),1)
	elif enemy_kind == "missile_drone":
		for side in [-1.0,1.0]:
			_slasher_box(Vector3(side*1.08,2.12,-0.47),Vector3(0.53,0.30,0.12),3)
			_slasher_box(Vector3(side*1.08,2.12,-0.54),Vector3(0.32,0.17,0.10),7)
			_slasher_box(Vector3(side*1.08,2.12,-0.60),Vector3(0.16,0.12,0.08),10)
			_slasher_box(Vector3(side*0.72,2.36,0.20),Vector3(0.13,0.20,0.39),5)
		_slasher_box(Vector3(-0.22,2.81,-0.06),Vector3(0.13,0.23,0.19),5)
	elif enemy_kind == "normal":
		# Small inset seams are paint on existing occupied armour, not a new
		# outer shell or random noisy voxels across the entire character.
		for side in [-1.0,1.0]:
			_paint_detail(Vector3(side*0.40,0.75,0.43-side*0.125*0.55),Vector3(0.10,0.07,0.12),5)
			_paint_detail(Vector3(side*0.61,1.42,0.31),Vector3(0.09,0.08,0.12),5)
		_paint_detail(Vector3(-0.65,2.16,0.29),Vector3(0.17,0.06,0.12),5)


func _paint_detail(center: Vector3, size: Vector3, material: int) -> void:
	var bounds := _slasher_grid_bounds(center-size*0.5,center+size*0.5)
	for z in range(bounds[0].z,bounds[1].z+1):
		for y in range(bounds[0].y,bounds[1].y+1):
			for x in range(bounds[0].x,bounds[1].x+1):
				var index := _index(x,y,z)
				if _voxels[index] != 0: _voxels[index] = material


func _build_flyer() -> void:
	var missile := enemy_kind == "missile_drone"
	# A suspended keel, exposed copper neck and chamfered sensor head give the
	# machine a real cuttable load path instead of an invulnerable hull shell.
	_slasher_taper(1.43,1.72,Vector2(0,-0.05),Vector2(0,0.02),0.26,0.47,0.36,0.46,2)
	_slasher_rod(Vector3(0,1.67,0),Vector3(0,2.17,0),0.11 if missile else 0.095,3)
	_slasher_taper(1.94,2.34,Vector2(0,0.02),Vector2(0,-0.03),0.46 if missile else 0.34,0.62 if missile else 0.42,0.48,0.48,2)
	_slasher_box(Vector3(0,2.10,0.25),Vector3(0.22,0.16,0.09),4)
	_slasher_rod(Vector3(0,2.25,-0.02),Vector3(0,2.55 if missile else 2.40,0.06),0.10,3)
	_slasher_taper(2.48 if missile else 2.30,2.76 if missile else 2.54,Vector2(0,0.07),Vector2(0,-0.02),0.54 if missile else 0.39,0.36,0.53,0.35,1)
	_slasher_box(Vector3(0,2.60 if missile else 2.40,0.31),Vector3(0.30,0.08,0.12),7)
	_slasher_box(Vector3(0,2.60 if missile else 2.40,0.38),Vector3(0.20,0.045,0.06),4)
	for side in [-1.0,1.0]:
		# The open duct / square launcher silhouettes stay distinct at range.
		_slasher_rod(Vector3(side*0.18,2.14,-0.02),Vector3(side*(1.04 if missile else 0.92),2.14,-0.02),0.105,3)
		_slasher_taper(2.19,2.42,Vector2(side*0.50,-0.06),Vector2(side*0.57,-0.11),0.66 if missile else 0.62,0.48,0.40,0.31,1)
		if missile:
			_slasher_taper(1.88,2.42,Vector2(side*1.08,0),Vector2(side*1.08,-0.03),0.66,0.74,0.90,0.95,2)
			_slasher_box(Vector3(side*1.08,2.44,-0.02),Vector3(0.72,0.16,0.91),1)
			_slasher_box(Vector3(side*1.08,2.12,0.42),Vector3(0.57,0.38,0.18),7)
			for chamber in [-1.0,1.0]:
				_slasher_box(Vector3(side*1.08+chamber*0.15,2.12,0.51),Vector3(0.16,0.17,0.09),10)
			_slasher_box(Vector3(side*1.08,1.82,-0.21),Vector3(0.40,0.13,0.37),3)
			_slasher_box(Vector3(side*1.08,1.73,-0.21),Vector3(0.26,0.08,0.23),10)
			_slasher_taper(2.18,2.67,Vector2(side*1.49,-0.16),Vector2(side*1.64,-0.22),0.18,0.12,0.51,0.35,1)
		else:
			_build_duct(Vector3(side*0.94,2.00,-0.02),0.39,0.25)
			_slasher_rod(Vector3(side*0.94,1.67,-0.02),Vector3(side*0.94,2.34,-0.02),0.055,5)
			_slasher_rod(Vector3(side*0.64,2.00,-0.02),Vector3(side*1.23,2.00,-0.02),0.055,5)
			_slasher_box(Vector3(side*0.94,2.00,0),Vector3(0.18,0.18,0.29),3)
			_slasher_box(Vector3(side*0.94,1.62,-0.02),Vector3(0.18,0.08,0.21),10)
			_slasher_taper(2.24,2.58,Vector2(side*0.85,-0.12),Vector2(side*1.16,-0.18),0.21,0.10,0.22,0.17,1)
	if not missile:
		_slasher_box(Vector3(0,1.98,0.22),Vector3(0.21,0.17,0.28),5)
		_slasher_box(Vector3(0,1.98,0.35),Vector3(0.14,0.12,0.12),7)
	_surface_hazard_stripes()
	_slasher_tags(Vector3(0,1.54,-0.03),Vector3(0.20,0.16,0.24),ANCHOR_TAG)
	_slasher_tags(Vector3(0,2.12,0),Vector3(0.20,0.18,0.24),CORE_TAG)
	_slasher_tags(Vector3(0,2.60 if missile else 2.40,0.04),Vector3(0.22,0.12,0.22),HEAD_TAG)
	_core_point = Vector3(0,2.10,0.30)


func _build_duct(center: Vector3, outer: float, inner: float) -> void:
	var limits := _slasher_grid_bounds(center-Vector3(outer,outer,0.16),center+Vector3(outer,outer,0.16))
	for z in range(limits[0].z,limits[1].z+1):
		for y in range(limits[0].y,limits[1].y+1):
			for x in range(limits[0].x,limits[1].x+1):
				var p := _point(x,y,z)-center
				var r2 := p.x*p.x+p.y*p.y
				if r2 >= inner*inner and r2 <= outer*outer:
					_voxels[_index(x,y,z)] = 1 if p.z > 0.04 else 2


func _build_construct() -> void:
	# A machined lock is the only material path through the centre. All skins,
	# ribs, bolts and exposed pipes below are occupied cells in this same grid;
	# no decorative mesh can conceal a cut or create an uncuttable gate shell.
	if enemy_kind == "barrier":
		_build_gate_construct()
	else:
		_build_brace_construct()
	_surface_hazard_stripes()


func _build_gate_construct() -> void:
	var lock_y := 1.60
	for side in [-1.0,1.0]:
		var post: float = side*1.60
		_slasher_box(Vector3(post,0.12,0),Vector3(0.72,0.24,0.64),2)
		_slasher_taper(0.24,2.32,Vector2(post,0),Vector2(post,0),0.28,0.24,0.30,0.30,5)
		_slasher_box(Vector3(post,2.19,0),Vector3(0.54,0.48,0.48),2)
		_slasher_box(Vector3(post,2.40,0),Vector3(0.39,0.16,0.38),1)
		_slasher_box(Vector3(post,0.38,0.02),Vector3(0.42,0.27,0.44),1)
		_slasher_box(Vector3(post,2.19,0.25),Vector3(0.25,0.12,0.08),10)
		_slasher_rod(Vector3(post-side*0.08,0.52,0.13),Vector3(post-side*0.08,1.19,0.13),0.062,3)
		_construct_fasteners(Vector3(post,0.37,0.26),0.21,0.0)
		match construct_variant:
			0:
				# Clamp gate: stepped hanging teeth and a cut-away shoulder.
				_slasher_box(Vector3(side*0.94,lock_y,0),Vector3(1.40,0.30,0.32),1)
				_slasher_taper(1.13,1.65,Vector2(side*0.56,0),Vector2(side*0.70,0),0.19,0.40,0.22,0.30,2)
				_slasher_taper(1.01,1.65,Vector2(side*1.05,0),Vector2(side*1.13,0),0.18,0.26,0.22,0.30,2)
				_slasher_rod(Vector3(post,1.10,-0.04),Vector3(side*0.97,1.57,-0.04),0.085,5)
				_paint_detail(Vector3(side*1.01,1.60,0.15),Vector3(0.64,0.08,0.12),8)
			1:
				# Staggered shutter: opposed, chamfered armour leaves meet at
				# one exposed dog-bone instead of a solid screen-wide slab.
				var leaf_y: float = 1.46 if side < 0 else 1.82
				_slasher_rod(Vector3(post,leaf_y,0),Vector3(side*0.27,lock_y,0),0.15,5)
				_slasher_taper(leaf_y-0.34,leaf_y+0.26,Vector2(side*1.03,0),Vector2(side*0.87,0),0.84,1.07,0.24,0.30,1)
				_slasher_box(Vector3(side*0.95,leaf_y+0.11,0.17),Vector3(0.58,0.09,0.10),5)
				for slit in range(3):
					_paint_detail(Vector3(side*(0.70+float(slit)*0.18),leaf_y-0.07,0.14),Vector3(0.075,0.19,0.10),7)
				_construct_fasteners(Vector3(side*1.31,leaf_y,0.19),0.0,0.28)
			2:
				# Coolant manifold: two real pipes on each side converge into
				# the same vulnerable coupling; neither pipe bypasses it.
				for rise in [-1.0,1.0]:
					_slasher_rod(Vector3(post,lock_y+rise*0.43,0),Vector3(side*0.30,lock_y+rise*0.10,0),0.12,3)
					_slasher_box(Vector3(side*1.15,lock_y+rise*0.31,0),Vector3(0.26,0.33,0.36),5)
				_slasher_box(Vector3(post,1.57,-0.02),Vector3(0.47,0.78,0.44),1)
				for groove in [1.38,1.58,1.78]:
					_paint_detail(Vector3(post,groove,0.21),Vector3(0.31,0.075,0.10),7)
				_slasher_box(Vector3(side*0.66,1.76,0),Vector3(0.22,0.28,0.32),2)
		_construct_lock_collar(Vector3(side*0.30,lock_y,0),side)
	# 0.15m high, four real depth layers: this is structural material rather
	# than HP or a glowing weak-point overlay. All six forms retain this cue.
	_slasher_box(Vector3(0,lock_y,0),Vector3(0.55,0.15,0.26),3)
	_paint_detail(Vector3(0,lock_y,0.10),Vector3(0.20,0.13,0.10),10)
	_slasher_tags(Vector3(-1.60,0.38,0),Vector3(0.25,0.24,0.30),ANCHOR_TAG)
	_slasher_tags(Vector3(0,lock_y,0),Vector3(0.17,0.14,0.23),CORE_TAG)
	_slasher_tags(Vector3(1.60,1.46,0),Vector3(0.22,0.18,0.23),HEAD_TAG)
	_core_point = Vector3(0,lock_y,0.15)


func _build_brace_construct() -> void:
	var reverse := construct_variant == 1
	var a := Vector3(-2.52,2.64 if reverse else 0.36,0)
	var b := Vector3(-0.31,1.64 if reverse else 1.36,0)
	var c := Vector3(0.31,1.36 if reverse else 1.64,0)
	var d := Vector3(2.52,0.36 if reverse else 2.64,0)
	if construct_variant == 2:
		a.y = 0.66
		d.y = 2.34
		b.y = 1.50
		c.y = 1.50
	for end in [a,d]:
		var foot := Vector3(end.x,0.12,0)
		_slasher_box(foot,Vector3(0.60,0.24,0.56),2)
		# A tall, slim end support gives the raised end a credible load path.
		_slasher_rod(foot+Vector3(0,0.10,0),end,0.105,5)
		_slasher_box(end,Vector3(0.45,0.40,0.46),2)
		_construct_fasteners(end+Vector3(0,0,0.25),0.22,0.0)
	if construct_variant == 2:
		# Articulated conveyor truss: flat end spans, triangular open webs.
		var elbow_a := Vector3(-1.36,0.66,0)
		var elbow_d := Vector3(1.36,2.34,0)
		for pair in [[a,elbow_a],[elbow_a,b],[c,elbow_d],[elbow_d,d]]:
			_slasher_rod(pair[0],pair[1],0.15,1)
		_slasher_rod(a,b,0.078,5)
		_slasher_rod(c,d,0.078,5)
		for side in [-1.0,1.0]:
			var level: float = 0.66 if side < 0 else 2.34
			_slasher_box(Vector3(side*1.92,level,0),Vector3(0.75,0.22,0.36),1)
			for tooth in range(3):
				_slasher_box(Vector3(side*(1.64+float(tooth)*0.24),level+0.16,0),Vector3(0.14,0.16,0.30),5)
	else:
		_slasher_rod(a,b,0.15,1)
		_slasher_rod(c,d,0.15,1)
		for side in [-1.0,1.0]:
			for step in [0.80,1.53,2.12]:
				var x: float = side*step
				var y: float = 1.50+x*(-0.45 if reverse else 0.45)
				_slasher_box(Vector3(x,y,0),Vector3(0.38,0.38 if reverse else 0.28,0.40),5 if reverse else 2)
				_slasher_box(Vector3(x,y,0.21),Vector3(0.19,0.09,0.08),3 if reverse else 8)
				if reverse:
					_slasher_box(Vector3(x,y+0.21,0),Vector3(0.13,0.13,0.30),1)
			if not reverse:
				# Exposed telescoping copper ram sits within each half only.
				_slasher_rod(Vector3(side*1.87,1.50+side*0.84,0.11),Vector3(side*0.56,1.50+side*0.25,0.11),0.062,3)
	_slasher_rod(b,c,0.135,3)
	for point in [b,c]:
		_construct_lock_collar(point,signf(point.x))
	_paint_detail(Vector3(0,1.50,0.10),Vector3(0.17,0.13,0.10),10)
	var anchor: Vector3 = d if reverse else a
	var hazard: Vector3 = a if reverse else d
	_slasher_tags(anchor,Vector3(0.26,0.24,0.30),ANCHOR_TAG)
	_slasher_tags(Vector3(0,1.50,0),Vector3(0.17,0.14,0.18),CORE_TAG)
	_slasher_tags(hazard,Vector3(0.26,0.24,0.30),HEAD_TAG)
	_core_point = Vector3(0,1.50,0.15)


func _construct_lock_collar(center: Vector3, side: float) -> void:
	_slasher_box(center,Vector3(0.23,0.41,0.42),5)
	_slasher_box(center+Vector3(side*0.015,0,0.23),Vector3(0.15,0.26,0.08),1)
	_construct_fasteners(center+Vector3(0,0,0.28),0.0,0.17)
	_slasher_box(center+Vector3(side*0.16,0.16,0),Vector3(0.13,0.12,0.29),2)


func _construct_fasteners(center: Vector3, span_x: float, span_y: float) -> void:
	for side in [-1.0,1.0]:
		_slasher_box(center+Vector3(side*span_x*0.5,side*span_y*0.5,0),Vector3(0.083,0.083,0.083),8)


func get_construct_debug_state() -> Dictionary:
	if not _is_construct(): return {}
	var names: Array = ["钳口隔离闸","折板滑闸","冷却阀架"] if enemy_kind == "barrier" else ["伸缩吊臂","反向母线","折线转运桁架"]
	return {"kind":enemy_kind,"variant":construct_variant,"name":names[construct_variant],"template_key":_model_template_key(enemy_kind,construct_variant),"cell_size":_cell,"initial_cells":_live_indices.size(),"aim_point":_core_point}


func _surface_hazard_stripes() -> void:
	# Paint only existing exposed ivory cells; stripes cannot create bridges.
	for z in range(_dimensions.z):
		for y in range(_dimensions.y):
			for x in range(_dimensions.x):
				var index := _index(x,y,z)
				if _voxels[index] == 1 and (z+1 >= _dimensions.z or _voxels[_index(x,y,z+1)] == 0) and posmod(x+y,17) < 2:
					_voxels[index] = 8


func _build_slasher() -> void:
	# Author the concept's stance and mechanical anatomy in metres. Every plate,
	# piston, horn and seam is the same fine occupied grid consumed by cuts.
	for side in [-1.0, 1.0]:
		# Knees lead the ankles in a staggered advancing stance. Armour and
		# pistons use these same anchors; the fixed pelvis remains unchanged.
		var stride_z: float = -float(side)*0.125
		var ankle := Vector3(side*0.53, 0.23, 0.14+stride_z)
		var knee := Vector3(side*0.40, 0.75, 0.25+stride_z*0.55)
		var hip := Vector3(side*0.22, 1.13, -0.08)
		_slasher_box(Vector3(side*0.53, 0.10, 0.13+stride_z), Vector3(0.32, 0.20, 0.58), 2)
		_slasher_box(Vector3(side*0.53, 0.18, 0.30+stride_z), Vector3(0.29, 0.10, 0.24), 9)
		_slasher_rod(ankle, knee, 0.085, 7)
		_slasher_rod(knee, hip, 0.105, 2)
		_slasher_rod(ankle+Vector3(side*0.06, 0, -0.03), knee+Vector3(side*0.06, 0, 0), 0.04, 3)
		_slasher_taper(0.25, 0.63, Vector2(side*0.52, ankle.z+0.11), Vector2(side*0.44, knee.z+0.10), 0.25, 0.23, 0.16, 0.18, 1)
		_slasher_box(Vector3(side*0.40, 0.73, knee.z+0.04), Vector3(0.28, 0.21, 0.30), 2)
		_slasher_box(Vector3(side*0.40, 0.75, knee.z+0.15), Vector3(0.22, 0.13, 0.10), 9)
		_slasher_taper(0.86, 1.15, Vector2(side*0.36, knee.z+0.05), Vector2(side*0.25, 0.04), 0.30, 0.28, 0.25, 0.26, 1)
		_slasher_box(Vector3(side*0.43, 0.37, lerpf(ankle.z+0.11, knee.z+0.10, 0.32)+0.08), Vector3(0.07, 0.07, 0.07), 2)
	# Low broad pelvis, split skirt plates, narrow exposed copper spine.
	_slasher_box(Vector3(0, 1.17, -0.04), Vector3(0.62, 0.25, 0.34), 2)
	for side in [-1.0, 1.0]:
		_slasher_taper(0.97, 1.27, Vector2(side*0.34, 0.20), Vector2(side*0.20, 0.15), 0.27, 0.22, 0.12, 0.14, 1)
		_slasher_taper(1.02, 1.26, Vector2(side*0.36, -0.14), Vector2(side*0.27, -0.11), 0.17, 0.16, 0.17, 0.18, 2)
	_slasher_rod(Vector3(0, 1.25, -0.02), Vector3(0, 1.58, 0.08), 0.105, 3)
	for side in [-1.0, 1.0]:
		_slasher_rod(Vector3(side*0.09, 1.28, -0.02), Vector3(side*0.10, 1.57, 0.08), 0.04, 9)
	# Tapered breastplate over a dark cage: broad shoulders, narrow abdomen.
	_slasher_taper(1.54, 2.10, Vector2(0, 0.02), Vector2(0, 0.12), 0.37, 0.76, 0.29, 0.37, 2)
	_slasher_box(Vector3(0, 1.82, 0.16), Vector3(0.20, 0.27, 0.20), 3)
	for side in [-1.0, 1.0]:
		_slasher_taper(1.77, 2.10, Vector2(side*0.15, 0.23), Vector2(side*0.23, 0.29), 0.21, 0.29, 0.13, 0.16, 1)
		_slasher_box(Vector3(side*0.23, 2.02, 0.37), Vector3(0.07, 0.07, 0.07), 9)
		_slasher_box(Vector3(side*0.13, 1.72, 0.19), Vector3(0.12, 0.12, 0.13), 5)
	_slasher_box(Vector3(0, 1.98, 0.30), Vector3(0.14, 0.11, 0.09), 5)
	_slasher_box(Vector3(0, 1.86, 0.29), Vector3(0.10, 0.08, 0.07), 4)
	# Connected shoulder axles and bent mechanical arms, with a much larger
	# left pauldron. The hand region is independently classified and severable.
	for side in [-1.0, 1.0]:
		_slasher_rod(Vector3(side*0.29, 2.02, 0.10), Vector3(side*0.56, 2.02, 0.07), 0.115, 3)
		_slasher_rod(Vector3(side*0.55, 2.00, 0.07), Vector3(side*0.63, 1.68, 0.06), 0.085, 2)
		_slasher_rod(Vector3(side*0.60, 1.69, 0.08), Vector3(side*0.61, 1.25, 0.20), 0.10, 7)
		_slasher_rod(Vector3(side*0.68, 1.90, 0.10), Vector3(side*0.70, 1.67, 0.15), 0.04, 3)
		_slasher_box(Vector3(side*0.63, 1.68, 0.09), Vector3(0.23, 0.17, 0.24), 9)
		_slasher_taper(1.34, 1.59, Vector2(side*0.61, 0.23), Vector2(side*0.63, 0.15), 0.23, 0.27, 0.17, 0.23, 1)
		_slasher_box(Vector3(side*0.61, 1.23, 0.22), Vector3(0.21, 0.20, 0.23), 2)
		_slasher_box(Vector3(side*0.61, 1.28, 0.35), Vector3(0.21, 0.06, 0.06), 7)
	_slasher_taper(1.99, 2.30, Vector2(-0.64, 0.10), Vector2(-0.56, 0.05), 0.46, 0.38, 0.43, 0.37, 1)
	_slasher_box(Vector3(-0.70, 2.12, 0.32), Vector3(0.07, 0.07, 0.06), 9)
	_slasher_taper(1.99, 2.20, Vector2(0.54, 0.09), Vector2(0.49, 0.08), 0.27, 0.26, 0.31, 0.27, 5)
	_slasher_box(Vector3(0.54, 2.13, 0.25), Vector3(0.20, 0.11, 0.07), 1)
	# Forward, pointed mask and two swept rear fins. This replaces the broad
	# rectangular forehead and robot visor rather than decorating that box.
	_slasher_rod(Vector3(0, 2.08, 0.16), Vector3(0, 2.24, 0.24), 0.095, 3)
	_slasher_taper(2.16, 2.48, Vector2(0, 0.23), Vector2(-0.02, 0.16), 0.23, 0.35, 0.32, 0.31, 2)
	_slasher_taper(2.15, 2.49, Vector2(0, 0.40), Vector2(-0.02, 0.32), 0.06, 0.34, 0.12, 0.16, 1)
	_slasher_taper(2.38, 2.63, Vector2(-0.11, 0.19), Vector2(-0.19, 0.02), 0.13, 0.07, 0.20, 0.09, 1)
	_slasher_taper(2.38, 2.57, Vector2(0.14, 0.17), Vector2(0.18, 0.03), 0.12, 0.06, 0.17, 0.08, 5)
	# The mask's two short diagonal sockets converge into a V. No horizontal
	# visor bar or long central nose plate remains from the discarded draft.
	for side in [-1.0, 1.0]:
		_slasher_rod(Vector3(side*0.04, 2.29, 0.44), Vector3(side*0.14, 2.35, 0.40), 0.047, 7)
		_slasher_rod(Vector3(side*0.05, 2.30, 0.48), Vector3(side*0.13, 2.35, 0.44), 0.030, 4)
	for z in range(_dimensions.z):
		for y in range(_dimensions.y):
			for x in range(_dimensions.x):
				var index:=_index(x,y,z)
				if _voxels[index]==0: continue
				var p:=_point(x,y,z)
				# Diagonal upper cut turns the front mask into a sloping wedge.
				if p.y>2.48-maxf(p.x+0.08,0.0)*0.65 and p.z>0.26:
					_voxels[index]=0
				elif p.x< -0.43 and p.x> -0.79 and p.y>2.06 and p.y<2.26 and (z+1>=_dimensions.z or _voxels[_index(x,y,z+1)]==0):
					if posmod(x+y,5)<=1: _voxels[index]=8
	_slasher_tags(Vector3(0, 2.34, 0.24), Vector3(0.15, 0.13, 0.15), HEAD_TAG)
	_slasher_tags(Vector3(0, 1.82, 0.15), Vector3(0.17, 0.19, 0.19), CORE_TAG)
	_slasher_tags(Vector3(0, 1.15, -0.04), Vector3(0.46, 0.15, 0.25), ANCHOR_TAG)
	_core_point = Vector3(0, 1.86, 0.30)


func _slasher_box(center: Vector3, size: Vector3, material_id: int) -> void:
	_slasher_taper(center.y-size.y*0.5, center.y+size.y*0.5, Vector2(center.x, center.z), Vector2(center.x, center.z), size.x, size.x, size.z, size.z, material_id)


func _slasher_grid_bounds(low: Vector3, high: Vector3) -> Array[Vector3i]:
	var offset := Vector3(float(_dimensions.x-1)*0.5, -0.5, float(_dimensions.z-1)*0.5)
	var a := Vector3i((low/_cell+offset).ceil()).clamp(Vector3i.ZERO, _dimensions-Vector3i.ONE)
	var b := Vector3i((high/_cell+offset).floor()).clamp(Vector3i.ZERO, _dimensions-Vector3i.ONE)
	return [a, b]


func _slasher_taper(y0: float, y1: float, bottom: Vector2, top: Vector2, w0: float, w1: float, d0: float, d1: float, material_id: int) -> void:
	var pad := Vector3(maxf(w0, w1)*0.5, 0, maxf(d0, d1)*0.5)
	var low := Vector3(minf(bottom.x, top.x), y0, minf(bottom.y, top.y))-pad
	var high := Vector3(maxf(bottom.x, top.x), y1, maxf(bottom.y, top.y))+pad
	var limits := _slasher_grid_bounds(low, high)
	for y in range(limits[0].y, limits[1].y+1):
		var height := (float(y)+0.5)*_cell
		var t := clampf((height-y0)/maxf(0.001, y1-y0), 0.0, 1.0)
		var center := bottom.lerp(top, t)
		var half := Vector2(lerpf(w0, w1, t), lerpf(d0, d1, t))*0.5
		var chamfer: float = minf(0.055, minf(half.x, half.y)*0.35)
		for z in range(limits[0].z, limits[1].z+1):
			for x in range(limits[0].x, limits[1].x+1):
				var p := _point(x, y, z)
				var delta := (Vector2(p.x, p.z)-center).abs()
				if delta.x > half.x or delta.y > half.y:
					continue
				if maxf(delta.x-half.x+chamfer, 0.0)+maxf(delta.y-half.y+chamfer, 0.0) > chamfer:
					continue
				_voxels[_index(x, y, z)] = material_id


func _slasher_rod(from: Vector3, to: Vector3, radius: float, material_id: int) -> void:
	var limits := _slasher_grid_bounds(from.min(to)-Vector3.ONE*radius, from.max(to)+Vector3.ONE*radius)
	var line := to-from
	for z in range(limits[0].z, limits[1].z+1):
		for y in range(limits[0].y, limits[1].y+1):
			for x in range(limits[0].x, limits[1].x+1):
				var p := _point(x, y, z)
				var t := clampf((p-from).dot(line)/maxf(line.length_squared(), 0.00001), 0.0, 1.0)
				if p.distance_squared_to(from+line*t) <= radius*radius:
					_voxels[_index(x, y, z)] = material_id


func _slasher_tags(center: Vector3, size: Vector3, tag: int) -> void:
	var limits := _slasher_grid_bounds(center-size*0.5, center+size*0.5)
	for z in range(limits[0].z, limits[1].z+1):
		for y in range(limits[0].y, limits[1].y+1):
			for x in range(limits[0].x, limits[1].x+1):
				var index := _index(x, y, z)
				if _voxels[index] != 0:
					_tags[index] |= tag


func _build_slasher_blade(weapon: Node3D, steel: Material) -> void:
	var profile := PackedVector2Array([Vector2(-0.10, -0.20), Vector2(0.13, -0.20), Vector2(0.18, -1.23), Vector2(0.07, -1.57), Vector2(-0.10, -1.70), Vector2(-0.14, -1.20)])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		for index in range(1, profile.size()-1):
			var triangle: Array = [0, index, index+1] if side > 0.0 else [0, index+1, index]
			for point in triangle:
				surface.set_normal(Vector3(0, 0, side))
				surface.add_vertex(Vector3(profile[point].x, profile[point].y, side*0.035))
	for index in range(profile.size()):
		var a := profile[index]
		var b := profile[(index+1)%profile.size()]
		var normal := Vector3(b.y-a.y, a.x-b.x, 0).normalized()
		for point in [Vector3(a.x,a.y,-0.035), Vector3(b.x,b.y,-0.035), Vector3(b.x,b.y,0.035), Vector3(a.x,a.y,-0.035), Vector3(b.x,b.y,0.035), Vector3(a.x,a.y,0.035)]:
			surface.set_normal(normal)
			surface.add_vertex(point)
	var blade := MeshInstance3D.new()
	blade.name = "BroadSlasherBlade"
	blade.mesh = surface.commit()
	blade.material_override = steel
	weapon.add_child(blade)
	_box_prop(weapon, Vector3(0.025, 1.18, 0.08), Vector3(0.155,-0.80,0), _weapon_edge_material)


func _recolor_box(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, color_index: int) -> void:
	# Paint cannot create an invisible bridge or change a material's occupancy.
	for z in range(maxi(z0, 0), mini(z1 + 1, _dimensions.z)):
		for y in range(maxi(y0, 0), mini(y1 + 1, _dimensions.y)):
			for x in range(maxi(x0, 0), mini(x1 + 1, _dimensions.x)):
				var index := _index(x, y, z)
				if _voxels[index] != 0:
					_voxels[index] = color_index


func _build_brute() -> void:
	for side in [-1.0,1.0]:
		var ankle := Vector3(side*0.69,0.30,0.10-side*0.10)
		var knee := Vector3(side*0.57,0.82,0.25)
		var hip := Vector3(side*0.35,1.22,-0.04)
		_slasher_box(Vector3(side*0.69,0.12,ankle.z+0.12),Vector3(0.55,0.24,0.75),2)
		_slasher_rod(ankle,knee,0.13,7)
		_slasher_rod(knee,hip,0.18,3)
		_slasher_taper(0.28,0.72,Vector2(side*0.69,ankle.z+0.14),Vector2(side*0.58,0.32),0.42,0.41,0.34,0.35,1)
		_slasher_box(knee,Vector3(0.45,0.26,0.42),5)
		_slasher_taper(0.89,1.22,Vector2(side*0.51,0.28),Vector2(side*0.35,0.09),0.47,0.48,0.37,0.35,1)
	_slasher_box(Vector3(0,1.24,-0.02),Vector3(1.18,0.30,0.62),2)
	_slasher_rod(Vector3(0,1.36,-0.04),Vector3(0,1.94,0.0),0.235,3)
	for side in [-1.0,1.0]:
		_slasher_rod(Vector3(side*0.27,1.38,-0.08),Vector3(side*0.39,1.87,-0.08),0.08,5)
		_slasher_taper(1.50,1.87,Vector2(side*0.30,0.23),Vector2(side*0.44,0.28),0.28,0.40,0.23,0.29,1)
		_slasher_box(Vector3(side*0.48,1.92,0.32),Vector3(0.39,0.33,0.29),2)
		_slasher_box(Vector3(side*0.48,1.98,0.49),Vector3(0.32,0.13,0.12),1)
		_slasher_taper(1.08,1.42,Vector2(side*0.56,0.25),Vector2(side*0.35,0.25),0.42,0.35,0.18,0.19,1)
	_slasher_taper(1.78,2.51,Vector2(0,-0.02),Vector2(0,-0.06),1.13,1.92,0.68,0.76,2)
	for side in [-1.0,1.0]:
		_slasher_taper(1.96,2.45,Vector2(side*0.32,0.37),Vector2(side*0.47,0.39),0.44,0.53,0.20,0.22,1)
		_slasher_rod(Vector3(side*0.77,2.42,-0.02),Vector3(side*1.25,2.42,-0.02),0.18,3)
		_slasher_rod(Vector3(side*1.26,2.40,-0.02),Vector3(side*1.43,1.89,0.07),0.14,7)
		_slasher_rod(Vector3(side*1.42,1.89,0.07),Vector3(side*1.30,1.20,0.20),0.15,3)
		_slasher_box(Vector3(side*1.43,1.89,0.08),Vector3(0.40,0.30,0.42),5)
		_slasher_taper(1.31,1.76,Vector2(side*1.31,0.28),Vector2(side*1.40,0.17),0.46,0.54,0.48,0.53,1)
		_slasher_box(Vector3(side*1.40,1.60,0.47),Vector3(0.27,0.12,0.12),5)
		_slasher_box(Vector3(side*1.30,1.18,0.22),Vector3(0.32,0.31,0.34),2)
		_slasher_taper(2.36,2.92 if side < 0.0 else 2.82,Vector2(side*1.25,-0.03),Vector2(side*1.12,-0.15),0.86,0.72,0.94,0.77,1)
		_slasher_box(Vector3(side*1.25,2.46,0.44),Vector3(0.56,0.11,0.09),5)
	_slasher_rod(Vector3(0,2.46,-0.02),Vector3(0,2.80,0.01),0.24,3)
	_slasher_taper(2.71,3.12,Vector2(0,0.08),Vector2(0,-0.02),0.47,0.61,0.55,0.50,5)
	_slasher_box(Vector3(0,2.88,0.34),Vector3(0.38,0.29,0.10),7)
	for x in [-0.12,0.0,0.12]:
		_slasher_box(Vector3(x,2.87,0.41),Vector3(0.055,0.22,0.065),10)
	_slasher_box(Vector3(0,2.17,0.30),Vector3(0.28,0.28,0.20),5)
	_slasher_box(Vector3(0,2.17,0.39),Vector3(0.18,0.21,0.08),4)
	_surface_hazard_stripes()
	_slasher_tags(Vector3(0,2.94,0.01),Vector3(0.25,0.18,0.28),HEAD_TAG)
	_slasher_tags(Vector3(0,2.12,0),Vector3(0.30,0.28,0.35),CORE_TAG)
	_slasher_tags(Vector3(0,1.24,-0.02),Vector3(0.82,0.18,0.39),ANCHOR_TAG)
	_core_point = Vector3(0,2.17,0.43)


func _build_gunner() -> void:
	for side in [-1.0,1.0]:
		var ankle := Vector3(side*0.34,0.20,0.07-side*0.13)
		var knee := Vector3(side*0.28,0.85,0.16-side*0.08)
		var hip := Vector3(side*0.18,1.49,-0.07)
		_slasher_box(Vector3(side*0.34,0.09,ankle.z+0.10),Vector3(0.25,0.18,0.46),2)
		_slasher_rod(ankle,knee,0.065,7)
		_slasher_rod(knee,hip,0.075,3)
		_slasher_taper(0.27,0.75,Vector2(side*0.34,ankle.z+0.10),Vector2(side*0.29,knee.z+0.09),0.20,0.22,0.15,0.19,1)
		_slasher_box(knee,Vector3(0.24,0.17,0.25),5)
		_slasher_taper(0.97,1.43,Vector2(side*0.26,knee.z+0.06),Vector2(side*0.19,0.02),0.21,0.23,0.16,0.21,1)
	_slasher_box(Vector3(0,1.50,-0.06),Vector3(0.51,0.21,0.31),2)
	_slasher_rod(Vector3(0,1.57,-0.05),Vector3(0,1.98,0.01),0.10,3)
	_slasher_taper(1.91,2.45,Vector2(0,-0.01),Vector2(0,0),0.35,0.58,0.30,0.37,2)
	for side in [-1.0,1.0]:
		_slasher_taper(2.08,2.44,Vector2(side*0.15,0.19),Vector2(side*0.19,0.23),0.16,0.24,0.12,0.16,1)
		_slasher_rod(Vector3(side*0.23,2.41,0),Vector3(side*0.49,2.41,0),0.095,3)
		_slasher_rod(Vector3(side*0.49,2.40,0),Vector3(side*0.55,2.04,0.04),0.072,2)
		_slasher_taper(2.33,2.60 if side < 0 else 2.52,Vector2(side*0.48,0.03),Vector2(side*0.44,-0.02),0.33,0.30,0.39,0.31,1)
	_slasher_rod(Vector3(0.55,2.05,0.04),Vector3(0.53,1.84,0.21),0.09,7)
	_slasher_box(Vector3(0.53,1.84,0.22),Vector3(0.19,0.20,0.23),2)
	_slasher_rod(Vector3(-0.55,2.04,0.04),Vector3(0.36,1.83,0.43),0.075,3)
	_slasher_box(Vector3(0.37,1.83,0.44),Vector3(0.20,0.15,0.24),2)
	# Bevel the four-cell rear corner where the support palm touched the
	# trigger palm. An actual air gap keeps a severed right wrist from being
	# accidentally welded back to the torso through the other hand.
	var clearance := _slasher_grid_bounds(Vector3(0.45,1.75,0.30),Vector3(0.50,1.95,0.35))
	for z in range(clearance[0].z,clearance[1].z+1):
		for y in range(clearance[0].y,clearance[1].y+1):
			for x in range(clearance[0].x,clearance[1].x+1):
				_voxels[_index(x,y,z)] = 0
	_slasher_rod(Vector3(0,2.42,-0.03),Vector3(0,2.73,-0.02),0.085,3)
	_slasher_box(Vector3(0,2.78,0.03),Vector3(0.51,0.22,0.45),2)
	_slasher_box(Vector3(0.02,2.81,0.27),Vector3(0.39,0.13,0.12),1)
	_slasher_box(Vector3(0.07,2.81,0.35),Vector3(0.24,0.075,0.065),4)
	_slasher_box(Vector3(-0.20,2.97,-0.08),Vector3(0.06,0.22,0.07),3)
	_slasher_box(Vector3(-0.20,2.93,0.02),Vector3(0.14,0.06,0.24),5)
	_slasher_box(Vector3(0,2.16,0.22),Vector3(0.10,0.11,0.08),4)
	_surface_hazard_stripes()
	_slasher_tags(Vector3(0,2.78,0.02),Vector3(0.21,0.11,0.21),HEAD_TAG)
	_slasher_tags(Vector3(0,2.15,0),Vector3(0.17,0.21,0.18),CORE_TAG)
	_slasher_tags(Vector3(0,1.5,-0.06),Vector3(0.35,0.14,0.21),ANCHOR_TAG)
	_core_point = Vector3(0,2.16,0.27)


func _build_boss() -> void:
	for side in [-1.0,1.0]:
		var ankle := Vector3(side*1.03,0.34,0.05-side*0.12)
		var knee := Vector3(side*0.90,1.08,0.28)
		var hip := Vector3(side*0.58,1.78,-0.10)
		_slasher_box(Vector3(side*1.03,0.14,ankle.z+0.18),Vector3(0.85,0.28,1.10),2)
		_slasher_rod(ankle,knee,0.17,3)
		_slasher_rod(knee,hip,0.22,2)
		_slasher_taper(0.35,0.94,Vector2(side*1.03,ankle.z+0.21),Vector2(side*0.93,0.36),0.67,0.64,0.44,0.48,1)
		_slasher_box(knee,Vector3(0.73,0.33,0.58),5)
		_slasher_taper(1.24,1.80,Vector2(side*0.83,0.31),Vector2(side*0.59,0.07),0.67,0.70,0.39,0.47,1)
	_slasher_box(Vector3(0,1.81,-0.09),Vector3(1.85,0.36,0.82),2)
	_slasher_rod(Vector3(0,1.93,-0.08),Vector3(0,2.64,-0.04),0.31,3)
	for side in [-1.0,1.0]:
		# Separate deep reactor cassettes, carried by two broad rear spars.
		# These are occupied, cuttable layers all the way from the visible
		# front plate to the inset reactor. They are not cosmetic shield shells.
		_slasher_taper(1.82,3.39,Vector2(side*0.68,-0.72),Vector2(side*1.08,-0.72),0.52,0.56,0.76,0.76,2)
		_slasher_box(Vector3(side*1.08,3.04,-0.25),Vector3(0.96,1.20,1.65),2)
		_slasher_box(Vector3(side*1.08,3.04,-0.65),Vector3(0.45,0.54,0.38),4)
		_slasher_box(Vector3(side*1.08,3.04,0.64),Vector3(0.79,0.97,0.15),1)
		for rail in [-0.33,0.33]:
			_slasher_box(Vector3(side*1.08+rail,3.04,0.75),Vector3(0.10,0.87,0.11),5)
		_slasher_box(Vector3(side*1.08,3.04,0.75),Vector3(0.13,0.64,0.11),10)
		_slasher_box(Vector3(side*1.08,3.04,0.82),Vector3(0.08,0.38,0.05),4)
		_slasher_rod(Vector3(side*0.38,1.96,-0.19),Vector3(side*0.65,2.73,-0.17),0.12,5)
		_slasher_taper(1.50,2.01,Vector2(side*0.76,0.40),Vector2(side*0.46,0.38),0.63,0.57,0.22,0.24,1)
		# The original central furnace cage is now a noncritical vent between
		# the two independent side cassettes, rather than a single fatal core.
		_slasher_rod(Vector3(side*0.54,2.49,-0.10),Vector3(side*0.69,3.57,-0.11),0.16,3)
		_slasher_taper(2.55,3.56,Vector2(side*1.11,0.10),Vector2(side*1.22,0.04),0.88,0.97,0.75,0.82,2)
		_slasher_taper(2.72,3.49,Vector2(side*1.13,0.54),Vector2(side*1.20,0.47),0.70,0.79,0.22,0.24,1)
		for seam_x in [0.81,1.54]:
			_slasher_box(Vector3(side*seam_x,3.12,0.64),Vector3(0.12,0.64,0.16),5)
		for bolt_y in [2.86,3.39]:
			_slasher_box(Vector3(side*1.18,bolt_y,0.64),Vector3(0.12,0.12,0.17),3)
		_slasher_rod(Vector3(side*1.44,3.45,-0.03),Vector3(side*2.31,3.45,-0.03),0.24,3)
		_slasher_rod(Vector3(side*2.31,3.43,-0.03),Vector3(side*2.71,2.76,0.01),0.19,7)
		_slasher_rod(Vector3(side*2.71,2.76,0.01),Vector3(side*2.65,2.18,0.20),0.20,3)
		_slasher_box(Vector3(side*2.71,2.75,0.03),Vector3(0.60,0.43,0.61),5)
		_slasher_taper(2.32,2.64,Vector2(side*2.65,0.26),Vector2(side*2.70,0.17),0.60,0.67,0.49,0.56,1)
		_slasher_box(Vector3(side*2.65,2.15,0.23),Vector3(0.43,0.42,0.49),2)
		_slasher_taper(3.38,3.98 if side < 0 else 3.88,Vector2(side*2.35,-0.05),Vector2(side*2.19,-0.20),1.33,1.12,1.20,0.95,1)
		_slasher_box(Vector3(side*2.35,3.56,0.57),Vector3(0.85,0.15,0.10),5)
		for bolt_x in [2.02,2.66]:
			_slasher_box(Vector3(side*bolt_x,3.72,0.43),Vector3(0.14,0.14,0.23),5)
		_slasher_rod(Vector3(side*1.56,3.52,-0.45),Vector3(side*1.56,4.19,-0.45),0.13,3)
	_slasher_box(Vector3(0,3.02,-0.31),Vector3(1.29,1.10,0.22),7)
	_slasher_box(Vector3(0,2.96,0.01),Vector3(0.54,0.76,0.54),3)
	for bar in [-0.19,0.0,0.19]:
		_slasher_box(Vector3(bar,2.96,0.32),Vector3(0.10,0.64,0.12),10)
	for skirt_x in [-0.46,0.0,0.46]:
		_slasher_taper(1.97,2.32,Vector2(skirt_x,0.40),Vector2(skirt_x*0.86,0.34),0.38,0.35,0.17,0.20,1)
		_slasher_box(Vector3(skirt_x,2.27,0.46),Vector3(0.25,0.075,0.10),5)
	_slasher_box(Vector3(0,2.49,0.26),Vector3(1.20,0.21,0.50),2)
	_slasher_box(Vector3(0,3.52,0.22),Vector3(1.30,0.21,0.60),2)
	_slasher_rod(Vector3(0,3.50,-0.02),Vector3(0,3.98,-0.01),0.29,3)
	_slasher_taper(3.92,4.24,Vector2(0,0.06),Vector2(0,-0.05),0.65,0.75,0.70,0.56,5)
	_slasher_box(Vector3(0,4.05,0.40),Vector3(0.47,0.13,0.12),7)
	_slasher_box(Vector3(0,4.05,0.48),Vector3(0.30,0.07,0.06),4)
	_slasher_box(Vector3(0,4.17,-0.45),Vector3(6.42,0.29,0.39),2)
	for side in [-1.0,1.0]:
		_slasher_box(Vector3(side*3.12,4.20,-0.45),Vector3(0.27,0.56,0.51),5)
		_slasher_box(Vector3(side*3.12,4.20,-0.15),Vector3(0.17,0.36,0.12),10)
	_surface_hazard_stripes()
	_slasher_tags(Vector3(0,4.08,-0.02),Vector3(0.28,0.18,0.31),HEAD_TAG)
	for index in range(BOSS_REACTOR_POINTS.size()):
		_slasher_tags(BOSS_REACTOR_POINTS[index],Vector3(0.45,0.54,0.38),CORE_TAG|(BOSS_LEFT_REACTOR_TAG if index == 0 else BOSS_RIGHT_REACTOR_TAG))
	_slasher_tags(Vector3(0,1.82,-0.09),Vector3(1.25,0.22,0.52),ANCHOR_TAG)
	_core_point = Vector3(0,2.97,0.39)


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
	var body_shader: Shader = _shared_body_shader
	if body_shader == null:
		body_shader = Shader.new()
		body_shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform float warning : hint_range(0.0, 1.0) = 0.0;
uniform float paint_value = 1.0;
uniform float heat_value = 0.0;
uniform float boss_ports = 0.0;
uniform vec2 boss_reactor_power = vec2(1.0);
varying vec3 authored_position;
void vertex() {
	authored_position = VERTEX;
}
void fragment() {
	vec3 base = COLOR.rgb;
	// Only the surviving real inset port faces change colour when their
	// cassette loses actual power connectivity. Missing cells stay missing.
	float port_yz = step(abs(authored_position.y-3.04),0.23) * step(0.77,authored_position.z);
	float left_port = step(abs(authored_position.x+1.08),0.08) * port_yz;
	float right_port = step(abs(authored_position.x-1.08),0.08) * port_yz;
	float unpowered = boss_ports * (left_port*(1.0-boss_reactor_power.x)+right_port*(1.0-boss_reactor_power.y));
	base = mix(base,vec3(0.065,0.08,0.085),unpowered);
	// The solid palette travels with each cut cell and its detached fragments.
	// Family tests use colour ratios so the existing per-face shading survives.
	float sensor = step(base.r * 1.35, base.b) * step(0.3, base.g);
	float copper = step(base.g * 1.38, base.r) * step(base.b * 1.4, base.r);
	float paint = step(0.55, base.r) * step(0.55, base.g) * (1.0 - copper);
	float rubber = 1.0 - smoothstep(0.07, 0.15, max(base.r, max(base.g, base.b)));
	ALBEDO = mix(base, vec3(1.0, 0.12, 0.035), sensor * warning * 0.8);
	ALBEDO *= mix(1.0, paint_value, paint);
	METALLIC = mix(mix(0.72, 0.12, paint), 0.86, copper) * (1.0 - rubber);
	ROUGHNESS = mix(mix(0.43, 0.68, paint), 0.34, copper);
	ROUGHNESS = mix(ROUGHNESS, 0.86, rubber);
	EMISSION = mix(base, vec3(1.0, 0.12, 0.035), warning) * sensor * (0.20 + warning * 0.65);
	float heat = step(0.78,base.r) * step(base.b * 2.2, base.g) * heat_value;
	EMISSION += base * heat * 0.85;
}
"""
		_shared_body_shader = body_shader
	var body_material := ShaderMaterial.new()
	body_material.shader = body_shader
	body_material.set_shader_parameter("paint_value", 0.74 if enemy_kind == "normal" else 0.82)
	body_material.set_shader_parameter("heat_value", 1.0 if _is_flying() or enemy_kind in ["tank","boss"] else 0.0)
	body_material.set_shader_parameter("boss_ports",1.0 if enemy_kind == "boss" else 0.0)
	body_material.set_shader_parameter("boss_reactor_power",Vector2.ONE)
	_material = body_material
	_reactor_material = StandardMaterial3D.new()
	_reactor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_reactor_material.albedo_color = Color("ff944b")
	_reactor_material.emission_enabled = true
	_reactor_material.emission = Color("ff944b")
	_reactor_material.emission_energy_multiplier = 2.0


func _build_reactor_marker() -> void:
	if is_instance_valid(_reactor):
		_reactor.queue_free()
	if _uses_fine_grid():
		# The slasher's small inset indicator is real front-layer voxel material.
		# A separate floating rectangle would cover the panel seams after cuts.
		_reactor = null
		return
	_reactor = MeshInstance3D.new()
	_reactor.name = "ReactorTarget"
	var marker := BoxMesh.new()
	marker.size = Vector3(0.32, 0.25, 0.035) if enemy_kind != "boss" else Vector3(0.8, 0.45, 0.045)
	_reactor.mesh = marker
	_reactor.material_override = _reactor_material
	_reactor.position = _core_point
	_rig.add_child(_reactor)


func _connected_components() -> Array[Dictionary]:
	if _uses_fine_grid():
		return _fine_components()
	var visited := PackedByteArray()
	visited.resize(_voxels.size())
	visited.fill(0)
	var result: Array[Dictionary] = []
	for seed in _live_indices:
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
	_last_rebuilt_slices = 0
	_last_reused_slices = 0
	if _mesh_cell_counts.size() != PART_COUNT:
		_mesh_cell_counts.resize(PART_COUNT)
	if not _initial_meshes.is_empty():
		_mesh_cell_counts.fill(0)
		for index in _live_indices:
			_mesh_cell_counts[_part_ids[index]] += 1
		for part_index in range(PART_COUNT):
			_part_meshes[part_index].mesh = _initial_meshes[part_index]
			_part_meshes[part_index].visible = _initial_meshes[part_index] != null
		_initial_meshes.clear()
		_next_mesh_mask = FULL_MESH_MASK
		if not _mesh_slice_ready:
			var meshes: Array = []
			for visual in _part_meshes: meshes.append(visual.mesh)
			_seed_mesh_slices(meshes)
		_refresh_weapon_visibility()
		return
	var groups: Array[PackedInt32Array] = []
	for part in range(PART_COUNT): groups.append(PackedInt32Array())
	var retained := PackedInt32Array()
	for index in _live_indices:
		if _voxels[index] != 0:
			groups[_part_for_index(index)].append(index)
			retained.append(index)
	_live_indices = retained
	for part_index in range(PART_COUNT):
		if (_next_mesh_mask & (1 << part_index)) == 0:
			continue
		var indices: PackedInt32Array = groups[part_index]
		_mesh_cell_counts[part_index] = indices.size()
		if indices.is_empty():
			_part_meshes[part_index].mesh = null
			if _mesh_slice_ready:
				_mesh_slice_arrays[part_index].clear()
				_mesh_dirty_slices[part_index].clear()
		elif _mesh_slice_ready and (_mesh_full_dirty_mask & (1 << part_index)) == 0 and not _mesh_dirty_slices[part_index].is_empty():
			var slices: Dictionary = _mesh_slice_arrays[part_index]
			for key: Vector2i in _mesh_dirty_slices[part_index]:
				var patch := _build_mesh_slice(part_index,key)
				if patch.is_empty(): slices.erase(key)
				else: slices[key] = patch
				_last_rebuilt_slices += 1
			_last_reused_slices += maxi(0,slices.size()-_mesh_dirty_slices[part_index].size())
			_part_meshes[part_index].mesh = _assemble_mesh_slices(slices)
			_mesh_dirty_slices[part_index].clear()
		else:
			# Non-standard callers and large detachments keep the full original
			# mesher. Only the standard recorded cut path uses incremental planes.
			var membership: Dictionary = {}
			for index in indices: membership[index] = true
			_part_meshes[part_index].mesh = _build_mesh(indices, Vector3.ZERO, membership)
			if _mesh_slice_ready:
				_mesh_slice_arrays[part_index] = _capture_mesh_slices(_part_meshes[part_index].mesh)
				_mesh_dirty_slices[part_index].clear()
		_part_meshes[part_index].visible = not indices.is_empty()
	_next_mesh_mask = FULL_MESH_MASK
	_mesh_full_dirty_mask = 0
	_refresh_weapon_visibility()


func _copy_slice_dictionaries(source: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	# Entries hold immutable packed arrays. Each actor owns the dictionaries
	# that replace entries; assembly never writes into the shared arrays.
	for part: Dictionary in source: result.append(part.duplicate())
	return result


func _seed_mesh_slices(meshes: Array) -> void:
	_mesh_slice_indices = []
	_mesh_slice_arrays = []
	_mesh_dirty_slices = []
	for part in range(PART_COUNT):
		_mesh_slice_indices.append({})
		_mesh_slice_arrays.append(_capture_mesh_slices(meshes[part]))
		_mesh_dirty_slices.append({})
	for index in _live_indices:
		var coordinate := _coords(index)
		var slices: Dictionary = _mesh_slice_indices[_part_ids[index]]
		for axis in range(3):
			var key := Vector2i(axis,coordinate[axis])
			if not slices.has(key): slices[key] = PackedInt32Array()
			slices[key].append(index)
	_mesh_slice_ready = _uses_fine_grid()


func _capture_mesh_slices(mesh: ArrayMesh) -> Dictionary:
	var result: Dictionary = {}
	if mesh == null: return result
	var origin := _point(0,0,0)
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for offset in range(0,vertices.size(),6):
			var normal := normals[offset]
			var axis := 0 if absf(normal.x)>0.5 else (1 if absf(normal.y)>0.5 else 2)
			var side := axis*2+(0 if normal[axis]>0.0 else 1)
			var layer := roundi((vertices[offset][axis]-origin[axis])/_cell-normal[axis]*0.5)
			var key := Vector2i(side,layer)
			if not result.has(key): result[key] = {"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"colors":PackedColorArray()}
			var slice: Dictionary = result[key]
			slice.vertices.append_array(vertices.slice(offset,offset+6))
			slice.normals.append_array(normals.slice(offset,offset+6))
			slice.colors.append_array(colors.slice(offset,offset+6))
	return result


func _mark_removed_mesh_slices(index: int, removed: Dictionary) -> void:
	var part: int = _part_ids[index]
	var coordinate := _coords(index)
	var dirty: Dictionary = _mesh_dirty_slices[part]
	for side in range(6):
		var axis: int = side/2
		var adjacent: int = _fine_neighbors[index*6+side]
		var same_part := adjacent>=0 and _part_ids[adjacent]==part
		var survives := same_part and _voxels[adjacent]!=0
		# A face that was visible disappears with this cell. Internal faces
		# between cells removed by this same stroke never existed and stay out.
		if not same_part or (not survives and not removed.has(adjacent)):
			dirty[Vector2i(side,coordinate[axis])] = true
		if survives:
			# The opposite face of the surviving neighbour becomes visible now.
			dirty[Vector2i(side^1,coordinate[axis]+DIRECTIONS[side][axis])] = true


func _build_mesh_slice(part: int, key: Vector2i) -> Dictionary:
	var side := key.x
	var axis: int = side/2
	var u := 1 if axis==0 else 0
	var v := 2 if axis<2 else 1
	var row := _dimensions[u]
	var layers: Dictionary = {}
	var authored: PackedInt32Array = _mesh_slice_indices[part].get(Vector2i(axis,key.y),PackedInt32Array())
	for index in authored:
		if _voxels[index]==0: continue
		var adjacent: int = _fine_neighbors[index*6+side]
		if adjacent>=0 and _voxels[adjacent]!=0 and _part_ids[adjacent]==part: continue
		var coordinate := _coords(index)
		var material := int(_voxels[index])
		if not layers.has(material): layers[material] = {}
		layers[material][coordinate[u]+coordinate[v]*row] = true
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var face_count := 0
	var normal := Vector3(DIRECTIONS[side])
	var tangent := Vector3.UP if axis==0 else Vector3.RIGHT
	var bitangent := normal.cross(tangent)
	var shade := 0.84+maxf(normal.y,0.0)*0.16
	for material: int in layers:
		var mask: Dictionary = layers[material]
		var color: Color = PALETTE[material]
		var tint := Color(color.r*shade,color.g*shade,color.b*shade,1.0)
		surface.set_normal(normal)
		surface.set_color(tint)
		for seed: int in mask.keys():
			if not mask.has(seed): continue
			var x: int = seed%row
			var y: int = seed/row
			var width := 1
			while x+width<row and mask.has(seed+width): width += 1
			var height := 1
			while y+height<_dimensions[v]:
				var complete := true
				for step in range(width):
					if not mask.has(seed+height*row+step):
						complete = false
						break
				if not complete: break
				height += 1
			for yy in range(height):
				for xx in range(width): mask.erase(seed+xx+yy*row)
			var coordinate := Vector3i.ZERO
			coordinate[axis] = key.y
			coordinate[u] = x
			coordinate[v] = y
			var center := _point(coordinate.x,coordinate.y,coordinate.z)+normal*_cell*0.5
			center[u] += float(width-1)*_cell*0.5
			center[v] += float(height-1)*_cell*0.5
			var a := tangent*float(width)*_cell*0.5
			var b := bitangent*float(height)*_cell*0.5
			for vertex in [center+a+b,center+a-b,center-a-b,center+a+b,center-a-b,center-a+b]: surface.add_vertex(vertex)
			face_count += 1
	if face_count==0: return {}
	var arrays := surface.commit_to_arrays()
	return {"vertices":arrays[Mesh.ARRAY_VERTEX],"normals":arrays[Mesh.ARRAY_NORMAL],"colors":arrays[Mesh.ARRAY_COLOR]}


func _assemble_mesh_slices(slices: Dictionary) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for slice: Dictionary in slices.values():
		vertices.append_array(slice.vertices)
		normals.append_array(slice.normals)
		colors.append_array(slice.colors)
	if vertices.is_empty(): return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh


func get_mesh_rebuild_debug_state() -> Dictionary:
	return {"slice_cache_ready":_mesh_slice_ready,"last_rebuilt_planes":_last_rebuilt_slices,"last_reused_planes":_last_reused_slices,"part_count":_part_meshes.size()}


func _build_mesh(indices: PackedInt32Array, origin: Vector3, membership: Dictionary = {}) -> ArrayMesh:
	if _uses_fine_grid():
		return _build_fine_mesh(indices, origin, membership)
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
	# A detached group is a subset of its pre-cut part. Equal cell counts
	# therefore prove it contains that entire unchanged mesh, not a damaged
	# lookalike. Share the immutable surface; cells remain private and any
	# subsequent cut rebuilds that fragment's own mesh as before.
	var source_mesh: ArrayMesh = null
	if _mesh_cell_counts.size() == PART_COUNT and indices.size() == _mesh_cell_counts[part]:
		source_mesh = _part_meshes[part].mesh as ArrayMesh
	fragment.configure_voxels(cells, _cell, PALETTE, _material, _point(0, 0, 0) - center, source_mesh, -center)


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
func _cache_fine_neighbors() -> void:
	_fine_neighbors.resize(_voxels.size()*6)
	_fine_neighbors.fill(-1)
	var row := _dimensions.x
	var plane := row*_dimensions.y
	for index in _live_indices:
		var p := _coords(index)
		var base := index*6
		if p.x+1<_dimensions.x: _fine_neighbors[base]=index+1
		if p.x>0: _fine_neighbors[base+1]=index-1
		if p.y+1<_dimensions.y: _fine_neighbors[base+2]=index+row
		if p.y>0: _fine_neighbors[base+3]=index-row
		if p.z+1<_dimensions.z: _fine_neighbors[base+4]=index+plane
		if p.z>0: _fine_neighbors[base+5]=index-plane


func _fine_components() -> Array[Dictionary]:
	var visited:=PackedByteArray()
	visited.resize(_voxels.size())
	var result:Array[Dictionary]=[]
	for seed in _live_indices:
		if _voxels[seed]==0 or visited[seed]!=0:
			continue
		# The BFS queue is already the final visitation order; keep one
		# packed list instead of appending every cell a second time.
		var queue:=PackedInt32Array([seed])
		var head:=0
		var flags:=0
		visited[seed]=1
		while head<queue.size():
			var current:int=queue[head]
			head+=1
			flags|=_tags[current]
			var base:=current*6
			for side in range(6):
				var adjacent:int=_fine_neighbors[base+side]
				if adjacent>=0 and _voxels[adjacent]!=0 and visited[adjacent]==0:
					visited[adjacent]=1
					queue.append(adjacent)
		result.append({"indices":queue,"flags":flags})
	return result


func _build_fine_mesh(indices: PackedInt32Array, origin: Vector3, membership: Dictionary) -> ArrayMesh:
	# Merge only adjacent coplanar faces with the same material and body part.
	# Occupancy, visible stair steps and every actual cut face remain identical.
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var face_count:=0
	for side in range(6):
		var axis:int=side/2
		var u:int=1 if axis==0 else 0
		var v:int=2 if axis<2 else 1
		var row:int=_dimensions[u]
		var layers:Dictionary={}
		for index in indices:
			var adjacent:int=_fine_neighbors[index*6+side]
			if adjacent>=0 and _voxels[adjacent]!=0 and (membership.is_empty() or membership.has(adjacent)):
				continue
			var p:=_coords(index)
			var key:int=p[axis]*PALETTE.size()+int(_voxels[index])
			if not layers.has(key): layers[key]={}
			layers[key][p[u]+p[v]*row]=true
		for code:int in layers:
			var mask:Dictionary=layers[code]
			var layer:int=code/PALETTE.size()
			var color:Color=PALETTE[code%PALETTE.size()]
			for key:int in mask.keys():
				if not mask.has(key): continue
				var x:int=key%row
				var y:int=key/row
				var width:=1
				while x+width<row and mask.has(key+width): width+=1
				var height:=1
				while y+height<_dimensions[v]:
					var complete:=true
					for step in range(width):
						if not mask.has(key+height*row+step):
							complete=false
							break
					if not complete: break
					height+=1
				for yy in range(height):
					for xx in range(width): mask.erase(key+xx+yy*row)
				var p:=Vector3i.ZERO
				p[axis]=layer
				p[u]=x
				p[v]=y
				var normal:=Vector3(DIRECTIONS[side])
				var tangent:=Vector3.UP if axis==0 else Vector3.RIGHT
				var bitangent:=normal.cross(tangent)
				var centre:=_point(p.x,p.y,p.z)-origin+normal*_cell*0.5
				centre[u]+=float(width-1)*_cell*0.5
				centre[v]+=float(height-1)*_cell*0.5
				var a:=tangent*float(width)*_cell*0.5
				var b:=bitangent*float(height)*_cell*0.5
				var shade:float=0.84+maxf(normal.y,0.0)*0.16
				var tint:=Color(color.r*shade,color.g*shade,color.b*shade,1.0)
				for vertex in [centre+a+b,centre+a-b,centre-a-b,centre+a+b,centre-a-b,centre-a+b]:
					surface.set_normal(normal)
					surface.set_color(tint)
					surface.add_vertex(vertex)
				face_count+=1
	if face_count==0: return null
	return surface.commit()
