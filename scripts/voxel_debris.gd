class_name VoxelDebris
extends Node3D
## Detached chunks retain their cells and can be sliced again while moving.

const DIRECTIONS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const MAX_VOXEL_PIECES := 24
# A single heat ramp replaces the old rainbow confetti. These are stages of
# the same hot metal cooling, not randomly assigned particle colours.
const CUT_PARTICLE_COLORS: Array[Color] = [
	Color("fff4c7"), Color("ffbd3e"), Color("ff5d0b"), Color("8c1002"),
]
const CUT_PARTICLE_CAPACITY := 576
const CUT_PARTICLE_GLOBAL_CAPACITY := 2304
const CUT_PARTICLE_BURST_MULTIPLIER := 3
const CUT_PARTICLE_IMPULSE_MULTIPLIER := 1.80
const CUT_PARTICLE_LIFETIME_MULTIPLIER := 1.15
const HELD_CUT_BURST_MULTIPLIER := 1.35

static var _cut_particle_cube: BoxMesh
# Legacy resource names remain for review tools; both batches now draw solids.
static var _cut_particle_halo: BoxMesh
static var _cut_particle_cube_material: ShaderMaterial
static var _cut_particle_halo_material: ShaderMaterial

var velocity := Vector3.ZERO
var spin := Vector3.ZERO
var lifetime := 5.0
var elapsed := 0.0
var floor_height := 0.08
var cells: Dictionary = {}
var cell_size := 0.1
var palette: Array[Color] = []
var _origin := Vector3.ZERO
var _material: Material
var _visual: MeshInstance3D
var _bounds := AABB()
var _bulk_vertices := PackedVector3Array()
var _bulk_normals := PackedVector3Array()
var _bulk_colors := PackedColorArray()
var _face_normals: Array[PackedVector3Array] = []
var _face_colors: Array = []


func configure_voxels(source_cells: Dictionary, size: float, colors: Array[Color], material: Material, origin: Vector3, source_mesh: ArrayMesh = null, mesh_translation: Vector3 = Vector3.ZERO) -> void:
	cells = source_cells.duplicate()
	cell_size = size
	palette = colors
	_material = material
	_origin = origin
	set_meta("voxel_piece", true)
	if source_mesh == null:
		_rebuild()
	else:
		_ensure_visual()
		_visual.mesh = source_mesh
		_visual.position = mesh_translation
		var source_bounds := source_mesh.get_aabb()
		_bounds = AABB(source_bounds.position+mesh_translation,source_bounds.size)
		_visual.visible = true
		set_meta("shared_intact_mesh",true)


func get_voxel_count() -> int:
	return cells.size()


func get_aim_point() -> Vector3:
	return to_global(_bounds.get_center())


func get_screen_bounds(camera: Camera3D) -> Rect2:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for x in [0.0, 1.0]:
		for y in [0.0, 1.0]:
			for z in [0.0, 1.0]:
				var world_point := to_global(_bounds.position + _bounds.size * Vector3(x, y, z))
				if camera.is_position_behind(world_point):
					continue
				var projected := camera.unproject_position(world_point)
				low = low.min(projected)
				high = high.max(projected)
	return Rect2() if low.x == INF else Rect2(low, high - low)


func cut_path(camera: Camera3D, points: PackedVector2Array, power: float = 1.0) -> Dictionary:
	return _cut_shape(camera, points, power)


func cut_blade_sweep(camera: Camera3D, frames: Array, power: float = 1.0) -> Dictionary:
	if frames.size() < 2:
		return {"removed": 0, "killed": false}
	return _cut_shape(camera, blade_motion_points(frames), power, frames)


func _cut_shape(camera: Camera3D, points: PackedVector2Array, power: float, blade_frames: Array = []) -> Dictionary:
	if cells.is_empty() or points.size() < 2 or is_queued_for_deletion():
		return {"removed": 0, "killed": false}
	var reference := get_aim_point()
	if camera.is_position_behind(reference):
		return {"removed": 0, "killed": false}
	var band := maxf(2.5, camera.unproject_position(reference + camera.global_basis.x * cell_size).distance_to(camera.unproject_position(reference)) * (0.68 + power * 0.15))
	var screen_bounds := get_screen_bounds(camera).grow(band)
	var segments := PackedInt32Array()
	var regions: Array[Dictionary] = []
	if blade_frames.is_empty():
		for index in range(points.size() - 1):
			if _segment_overlaps_rect(points[index], points[index + 1], screen_bounds):
				segments.append(index)
	else:
		regions = sweep_regions(blade_frames, screen_bounds, band)
	if segments.is_empty() and regions.is_empty():
		return {"removed": 0, "killed": false}
	var removed: Array[Vector3i] = []
	var particle_sources := PackedVector3Array()
	var world := global_transform
	var band_squared := band * band
	for coordinate: Vector3i in cells:
		var world_point := world * _cell_point(coordinate)
		if camera.is_position_behind(world_point):
			continue
		var projected := camera.unproject_position(world_point)
		var intersects: bool = not regions.is_empty() and point_in_sweep(projected, regions, band_squared)
		for segment in segments:
			if Geometry2D.get_closest_point_to_segment(projected, points[segment], points[segment + 1]).distance_squared_to(projected) <= band_squared:
				intersects = true
				break
		if intersects:
			removed.append(coordinate)
			particle_sources.append(world_point)
	if removed.is_empty():
		return {"removed": 0, "killed": false}
	var stroke := _longest_stroke(points)
	var stroke_direction := stroke.normalized()
	emit_cut_particles(get_parent(), camera, particle_sources, stroke, cell_size, "debris")
	for coordinate in removed:
		cells.erase(coordinate)
	if bool(get_parent().get_meta("flythrough_enabled", false)):
		velocity += Vector3(stroke_direction.x * 2.8, -stroke_direction.y * 1.5 + 0.6, 2.5)
		spin += Vector3(0.8, 0.35, -stroke_direction.x * 1.6)
	else:
		velocity += Vector3(stroke_direction.x * 0.9, 0.25, 0.15)
		spin += Vector3(0.3, 0.1, -stroke_direction.x * 0.5)
	elapsed = minf(elapsed, lifetime - 1.3)
	if cells.is_empty():
		visible = false
		queue_free()
	else:
		_split_disconnected(stroke)
		_rebuild()
	return {"removed": removed.size(), "killed": false}


static func emit_cut_particles(source_owner: Node3D, camera: Camera3D, source_points: PackedVector3Array, stroke: Vector2, source_cell: float, source_kind: String = "body") -> void:
	if source_points.is_empty() or not is_instance_valid(source_owner):
		return
	var batch = source_owner.get_node_or_null("CutVoxelBurst")
	if is_instance_valid(batch) and batch.is_queued_for_deletion():
		source_owner.remove_child(batch)
		batch = null
	if batch == null:
		_prepare_cut_particle_resources()
		batch = CutVoxelBurst.new()
		batch.name = "CutVoxelBurst"
		batch.source_owner = source_owner
		batch.camera = camera
		source_owner.add_child(batch)
		# World-space particles inherit no enemy root displacement. Their runner
		# flow is applied once below, even while the severed parent accelerates.
		batch.top_level = true
		batch.global_transform = Transform3D(Basis.IDENTITY, source_points[0])
	batch.emit_from_cut(source_points, stroke, source_cell, source_kind, _held_cut_feedback(source_owner))


static func _held_cut_feedback(source_owner: Node) -> bool:
	# Recut fragments emit through their parent enemy. The ancestor fallback
	# also supports a directly owned fragment without copying a stale mode.
	var ancestor := source_owner
	while is_instance_valid(ancestor):
		if ancestor.has_meta("held_cut_fx"):
			return bool(ancestor.get_meta("held_cut_fx"))
		ancestor = ancestor.get_parent()
	return false


static func _prepare_cut_particle_resources() -> void:
	if _cut_particle_cube != null:
		return
	_cut_particle_cube = BoxMesh.new()
	_cut_particle_cube.size = Vector3.ONE
	_cut_particle_halo = BoxMesh.new()
	_cut_particle_halo.size = Vector3.ONE
	var cube_shader := Shader.new()
	cube_shader.code = """shader_type spatial;
render_mode unshaded, cull_back;
void fragment() {
	// Hard cube normals and a broad face contrast keep volume visible even
	// at the hot peak. Saturating every face to white made flakes look flat.
	float facet = max(dot(normalize(NORMAL), normalize(vec3(-0.45, 0.75, 0.60))), 0.0);
	// Compatibility's unshaded pass outputs ALBEDO only; EMISSION is ignored.
	vec3 side_heat = COLOR.rgb * vec3(1.0, 0.62, 0.28);
	ALBEDO = mix(side_heat, COLOR.rgb, facet) * (0.42 + facet * 0.88);
}
"""
	_cut_particle_cube_material = ShaderMaterial.new()
	_cut_particle_cube_material.shader = cube_shader
	_cut_particle_halo_material = ShaderMaterial.new()
	_cut_particle_halo_material.shader = cube_shader


static func spark_heat_color(age_fraction: float) -> Color:
	var cooling := clampf(age_fraction, 0.0, 1.0)
	if cooling < 0.18:
		return CUT_PARTICLE_COLORS[0].lerp(CUT_PARTICLE_COLORS[1], cooling / 0.18)
	if cooling < 0.64:
		return CUT_PARTICLE_COLORS[1].lerp(CUT_PARTICLE_COLORS[2], (cooling - 0.18) / 0.46)
	return CUT_PARTICLE_COLORS[2].lerp(CUT_PARTICLE_COLORS[3], (cooling - 0.64) / 0.36)


class CutVoxelBurst extends Node3D:
	## Legacy node name retained for review tools; these are tumbling hot voxels.
	## One fixed pool per enemy, not a physics/node allocation per spark.
	static var global_active_count := 0
	var source_owner: Node3D
	var camera: Camera3D
	var cores: MultiMesh
	var halos: MultiMesh
	var slots: Array[Dictionary] = []
	var next_slot := 0
	var active_count := 0
	var emitted_total := 0
	var emitted_body := 0
	var emitted_debris := 0
	var emitted_sever := 0
	var emitted_held := 0
	var emitted_standard := 0
	var last_burst_count := 0
	var last_tier_counts: Dictionary = {}
	var last_feedback_mode := "standard"
	var last_layer_counts: Dictionary = {}
	var last_base_burst_count := 0
	var last_requested_burst_count := 0
	var last_held_pool_available := 0
	var size_min := INF
	var size_max := 0.0
	var source_cell_min := INF
	var source_cell_max := 0.0
	var last_origins := PackedVector3Array()
	var last_sources := PackedVector3Array()
	var last_velocities := PackedVector3Array()
	var last_cut_tangent := Vector3.RIGHT
	var last_cut_normal := Vector3.UP
	var last_source_kind := ""
	var random := RandomNumberGenerator.new()
	var held_random := RandomNumberGenerator.new()
	var max_lifetime := 0.0
	var min_lifetime := INF
	var length_min := INF
	var length_max := 0.0
	var last_widths := PackedFloat32Array()
	var last_lengths := PackedFloat32Array()
	var last_dimensions := PackedVector3Array()
	var last_spins := PackedVector3Array()
	var _draw_world := Transform3D.IDENTITY
	var _draw_camera_inverse := Transform3D.IDENTITY
	var _draw_tan_half_fov := 0.0
	var _draw_view_height := 1.0
	var _tail_orientation := Basis.from_euler(Vector3(0.35, 0.60, 0.20))
	var _hidden_pose := Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO)

	func _ready() -> void:
		random.randomize()
		held_random.randomize()
		set_meta("cut_particle_batch", true)
		cores = _make_instances(VoxelDebris._cut_particle_cube, VoxelDebris._cut_particle_cube_material)
		halos = _make_instances(VoxelDebris._cut_particle_halo, VoxelDebris._cut_particle_halo_material)
		slots.resize(VoxelDebris.CUT_PARTICLE_CAPACITY)
		for index in range(slots.size()):
			slots[index] = {}
			_hide_slot(index)
		set_process(false)

	func _make_instances(mesh: Mesh, material: Material) -> MultiMesh:
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.use_colors = true
		instances.mesh = mesh
		instances.instance_count = VoxelDebris.CUT_PARTICLE_CAPACITY
		var visual := MultiMeshInstance3D.new()
		visual.multimesh = instances
		visual.material_override = material
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)
		return instances

	func emit_from_cut(points: PackedVector3Array, stroke: Vector2, source_cell: float, kind: String, held_cut: bool = false) -> void:
		if points.is_empty():
			return
		_refresh_draw_projection()
		var camera_basis := camera.global_basis
		var world_inverse := _draw_world.affine_inverse()
		last_source_kind = kind
		last_cut_tangent = (camera_basis * Vector3(stroke.x, -stroke.y, 0.0)).normalized()
		if last_cut_tangent.length_squared() < 0.001:
			last_cut_tangent = camera_basis.x
		last_cut_normal = last_cut_tangent.cross(camera_basis.z).normalized()
		var flythrough := bool(source_owner.get_meta("flythrough_enabled", false))
		var sever := kind == "sever"
		var material_span := sqrt(float(points.size()))
		var count := clampi(8 + int(material_span * 4.8), 18, 62)
		if sever:
			count = clampi(32 + int(material_span * 8.0), 72, 120)
		elif kind == "debris":
			count = clampi(12 + int(material_span * 5.3), 24, 70)
		count *= VoxelDebris.CUT_PARTICLE_BURST_MULTIPLIER
		var base_count := count
		if held_cut:
			count = mini(VoxelDebris.CUT_PARTICLE_CAPACITY, ceili(float(count) * VoxelDebris.HELD_CUT_BURST_MULTIPLIER))
		last_base_burst_count = base_count
		last_requested_burst_count = count
		last_held_pool_available = 0
		last_feedback_mode = "held" if held_cut else "standard"
		last_burst_count = 0
		last_tier_counts = {"pin": 0, "jet": 0, "lance": 0}
		last_layer_counts = {"standard":0,"hot_jet":0,"hot_plate":0,"cut_flash":0}
		# Most visible sparks belong to the actual cut's front-facing cells.
		# Sampling every depth layer made the first hot frame disappear inside
		# the upper/lower fragments, especially while hit-stop froze motion.
		var front_cells: Dictionary = {}
		var front_depths: Dictionary = {}
		for point in points:
			var view_point := _draw_camera_inverse * point
			var column := Vector2i(roundi(view_point.x / source_cell), roundi(view_point.y / source_cell))
			if not front_cells.has(column) or view_point.z > float(front_depths[column]):
				front_cells[column] = point
				front_depths[column] = view_point.z
		var surface_points: Array = front_cells.values()
		last_origins.clear()
		last_sources.clear()
		last_velocities.clear()
		last_widths.clear()
		last_lengths.clear()
		last_dimensions.clear()
		last_spins.clear()
		var held_slots := PackedInt32Array()
		if held_cut:
			# Reserve at most the free global budget, then reuse this owner's
			# cooling slots only. Scan once per burst, never once per new spark.
			var cooling_slots := PackedInt32Array()
			var free_budget := maxi(0,VoxelDebris.CUT_PARTICLE_GLOBAL_CAPACITY-global_active_count)
			for offset in range(slots.size()):
				var candidate := (next_slot+offset)%slots.size()
				if slots[candidate].is_empty():
					if free_budget > 0:
						held_slots.append(candidate)
						free_budget -= 1
				elif float(slots[candidate].age)/float(slots[candidate].life) >= 0.25:
					cooling_slots.append(candidate)
			held_slots.append_array(cooling_slots)
			last_held_pool_available = held_slots.size()
		for number in range(count):
			# The original base particles consume the original private stream in
			# its previous order. Extra held layers never touch it or main's RNG.
			var rng := held_random if number >= base_count else random
			var index := next_slot
			if held_cut:
				if number >= held_slots.size():
					break
				index = held_slots[number]
			# Recycle this pool's oldest slot; never overflow the global budget.
			if not held_cut and slots[index].is_empty() and global_active_count >= VoxelDebris.CUT_PARTICLE_GLOBAL_CAPACITY:
				# A fresh sever may replace this owner's cooling spark, even if
				# the next ring slot is empty. Never steal another owner's slots.
				var oldest := -1
				var oldest_fraction := -1.0
				for candidate in range(slots.size()):
					if not slots[candidate].is_empty():
						var fraction: float = float(slots[candidate].age) / float(slots[candidate].life)
						if fraction > oldest_fraction:
							oldest = candidate
							oldest_fraction = fraction
				if oldest < 0:
					break
				index = oldest
			next_slot = ((index if held_cut else next_slot)+1)%slots.size()
			if slots[index].is_empty():
				active_count += 1
				global_active_count += 1
			var source: Vector3 = points[mini(points.size() - 1, int(float(number) / float(count) * points.size()))]
			if number % 4 != 3:
				source = surface_points[mini(surface_points.size() - 1, int(float(number) / float(count) * surface_points.size()))]
			# Start at the sampled cell's camera-facing surface with only a 2%
			# cell separation. The real removed cell remains the recorded source;
			# neither x-ray rendering nor an unrelated screen-space flash is used.
			var spawn := source + camera_basis.z * source_cell * 0.52 + last_cut_normal * rng.randf_range(-0.05, 0.05) * source_cell
			# Two opposing fans carry the cut, with a smaller wild scatter. The
			# result is a broken spray rather than a uniform circular firework.
			var side := -1.0 if number % 2 == 0 else 1.0
			var spread := rng.randf_range(-0.85, 0.85)
			var heading := last_cut_normal * side * cos(spread) + last_cut_tangent * sin(spread)
			if number % 5 == 1:
				heading = last_cut_tangent * side + last_cut_normal * rng.randf_range(-0.85, 0.85)
			elif number % 7 == 0:
				var angle := rng.randf_range(-PI, PI)
				heading = last_cut_normal * cos(angle) + last_cut_tangent * sin(angle)
			var depth_impulse := rng.randf_range(0.32, 0.82)
			if number % 5 == 0:
				depth_impulse = rng.randf_range(-0.20, 0.55)
			heading += camera_basis.z * depth_impulse
			# Keep the established impulse tiers, but make their main geometry
			# compact solid cubes/cuboids. None is a velocity-aligned laser strip.
			var tier := "pin"
			var impulse := rng.randf_range(42.0, 76.0)
			var lifetime := rng.randf_range(0.065, 0.13)
			var size := clampf(source_cell * rng.randf_range(0.25, 0.44), 0.025, 0.055)
			var head_pixels := rng.randf_range(2.0, 2.6)
			var drag := 6.5
			if number % 10 == 0:
				tier = "lance"
				impulse = rng.randf_range(72.0, 110.0)
				lifetime = rng.randf_range(0.12, 0.22)
				size = clampf(source_cell * rng.randf_range(0.50, 0.75), 0.05, 0.09)
				head_pixels = rng.randf_range(2.8, 3.3)
				drag = 2.6
			elif number % 10 <= 3:
				tier = "jet"
				impulse = rng.randf_range(48.0, 90.0)
				lifetime = rng.randf_range(0.10, 0.20)
				size = clampf(source_cell * rng.randf_range(0.36, 0.60), 0.035, 0.075)
				head_pixels = rng.randf_range(2.3, 2.9)
				drag = 4.0
			if sever:
				impulse *= 1.15
			if not flythrough:
				impulse *= 0.70
			impulse *= VoxelDebris.CUT_PARTICLE_IMPULSE_MULTIPLIER
			lifetime *= VoxelDebris.CUT_PARTICLE_LIFETIME_MULTIPLIER
			drag *= 0.85
			var velocity := heading.normalized() * impulse
			var cuboid := number % 5 == 0 or number % 5 == 3
			var proportions := Vector3.ONE
			if cuboid:
				proportions = Vector3(rng.randf_range(1.35, 1.85), rng.randf_range(0.85, 1.05), rng.randf_range(0.85, 1.05))
			var dimensions := proportions * size
			var orientation := Basis.from_euler(Vector3(rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(-PI, PI)))
			var angular_velocity := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized() * rng.randf_range(12.0, 34.0)
			var block_length := maxf(dimensions.x, maxf(dimensions.y, dimensions.z))
			var tail_point := number % 4 == 0
			var tail_phase := rng.randf_range(0.0, 0.024)
			var layer := "standard"
			var heat_gain := 1.0
			if held_cut:
				# A small cut-surface flash, fast fine jets, and slower broad blocks
				# have distinct scale/time ranges; all originate at real cut cells.
				var phase := number % 12
				layer = "cut_flash" if phase in [0,5] else ("hot_plate" if phase in [2,7,10] else "hot_jet")
				if layer == "cut_flash":
					tier = "pin"
					impulse = held_random.randf_range(18.0,28.0)
					lifetime = held_random.randf_range(0.055,0.085)
					size = clampf(source_cell*held_random.randf_range(0.55,0.85),0.045,0.085)
					head_pixels = 2.5
					drag = 6.2
					cuboid = false
					proportions = Vector3.ONE
					tail_point = false
					heat_gain = 1.55
					angular_velocity *= 0.40
				elif layer == "hot_plate":
					tier = "lance"
					impulse = held_random.randf_range(37.0,66.0)
					lifetime = held_random.randf_range(0.13,0.235)
					size = clampf(source_cell*held_random.randf_range(0.60,0.95),0.055,0.10)
					head_pixels = 3.0
					drag = 2.2
					cuboid = true
					proportions = Vector3(held_random.randf_range(1.2,1.65),held_random.randf_range(0.85,1.05),held_random.randf_range(0.85,1.05))
					tail_point = number % 2 == 1
					heat_gain = 1.12
					angular_velocity *= 0.65
				else:
					tier = "jet"
					impulse = held_random.randf_range(62.0,112.0)
					lifetime = held_random.randf_range(0.07,0.135)
					size = clampf(source_cell*held_random.randf_range(0.20,0.38),0.020,0.050)
					head_pixels = held_random.randf_range(2.0,2.8)
					drag = 4.8
					cuboid = number % 5 == 0
					proportions = Vector3(1.45,1.0,1.0) if cuboid else Vector3.ONE
					tail_point = number % 3 == 1
					heat_gain = 1.25
					angular_velocity *= 1.20
				if sever: impulse *= 1.15
				if not flythrough: impulse *= 0.70
				impulse *= VoxelDebris.CUT_PARTICLE_IMPULSE_MULTIPLIER
				lifetime *= VoxelDebris.CUT_PARTICLE_LIFETIME_MULTIPLIER
				drag *= 0.85
				velocity = heading.normalized()*impulse
				dimensions = proportions*size
				block_length = maxf(dimensions.x,maxf(dimensions.y,dimensions.z))
				tail_phase = fposmod(tail_phase,0.018)
			slots[index] = {"position": world_inverse * spawn, "velocity": velocity, "age": 0.0, "life": lifetime, "size": size, "length": block_length, "shutter": 0.0, "head_pixels": head_pixels, "tail_pixels": head_pixels * 0.45, "long_ray": false, "tier": tier, "drag": drag, "dimensions": dimensions, "orientation": orientation, "angular_velocity": angular_velocity, "cuboid": cuboid, "source_cell": source_cell, "tail_point": tail_point, "tail_phase": tail_phase, "held_cut":held_cut,"layer":layer,"heat_gain":heat_gain}
			last_sources.append(source)
			last_origins.append(spawn)
			last_velocities.append(velocity)
			last_widths.append(size)
			last_lengths.append(block_length)
			last_dimensions.append(dimensions)
			last_spins.append(angular_velocity)
			size_min = minf(size_min, size)
			size_max = maxf(size_max, size)
			source_cell_min = minf(source_cell_min, source_cell)
			source_cell_max = maxf(source_cell_max, source_cell)
			max_lifetime = maxf(max_lifetime, lifetime)
			min_lifetime = minf(min_lifetime, lifetime)
			length_min = minf(length_min, block_length)
			length_max = maxf(length_max, block_length)
			emitted_total += 1
			if held_cut: emitted_held += 1
			else: emitted_standard += 1
			last_burst_count += 1
			last_tier_counts[tier] = int(last_tier_counts[tier]) + 1
			last_layer_counts[layer] = int(last_layer_counts[layer]) + 1
			if sever:
				emitted_sever += 1
			if kind == "debris":
				emitted_debris += 1
			else:
				emitted_body += 1
			_draw_slot(index)
		set_process(active_count > 0)

	func _process(delta: float) -> void:
		var step := delta * float(source_owner.get_meta("simulation_scale", 1.0))
		if step <= 0.0:
			return
		_refresh_draw_projection()
		var flow := Vector3.ZERO
		if bool(source_owner.get_meta("flythrough_enabled", false)) and not bool(source_owner.get_meta("boss_death_stationary",false)):
			flow.z = maxf(48.0, float(source_owner.get_meta("runner_speed", 0.0)) * 1.35)
		for index in range(slots.size()):
			var slot: Dictionary = slots[index]
			if slot.is_empty():
				continue
			slot.age += step
			slot.velocity.y -= step * 10.0
			slot.velocity *= exp(-step * float(slot.drag))
			slot.position += (slot.velocity + flow) * step
			var angular_velocity: Vector3 = slot.angular_velocity
			if angular_velocity.length_squared() > 0.0001:
				slot.orientation = (Basis(angular_velocity.normalized(), angular_velocity.length() * step) * Basis(slot.orientation)).orthonormalized()
			if slot.age >= slot.life or (flow.z > 0.0 and (_draw_world * Vector3(slot.position)).z > 3.0):
				slots[index] = {}
				active_count -= 1
				global_active_count -= 1
				_hide_slot(index)
			else:
				_draw_slot(index)
		if active_count == 0:
			set_process(false)

	func _refresh_draw_projection() -> void:
		# Every slot in one emission / simulation step sees the same view and
		# pool transform. Keep the original transform order and pixel formula.
		_draw_world = global_transform
		_draw_camera_inverse = camera.global_transform.affine_inverse()
		_draw_tan_half_fov = tan(deg_to_rad(camera.fov) * 0.5)
		_draw_view_height = maxf(camera.get_viewport().get_visible_rect().size.y, 1.0)

	func _draw_slot(index: int) -> void:
		var slot: Dictionary = slots[index]
		var age_fraction := clampf(float(slot.age) / float(slot.life), 0.0, 1.0)
		var remaining := 1.0 - age_fraction
		var fade := pow(remaining, 0.65)
		var color := VoxelDebris.spark_heat_color(age_fraction)
		color *= (0.30 + fade * 0.70)
		color *= float(slot.get("heat_gain",1.0))
		color.a = 1.0
		# Preserve all three dimensions and the random world-space orientation.
		# The modest pixel floor grows the whole solid uniformly, never stretches
		# it along velocity or flattens it into a camera-facing rectangle.
		var depth: float = maxf(0.1, -(_draw_camera_inverse * (_draw_world * Vector3(slot.position))).z)
		var pixel_width := 2.0 * depth * _draw_tan_half_fov / _draw_view_height
		var dimensions: Vector3 = slot.dimensions
		var shortest := minf(dimensions.x, minf(dimensions.y, dimensions.z))
		var longest := maxf(dimensions.x, maxf(dimensions.y, dimensions.z))
		var pixel_floor: float = minf(pixel_width * slot.head_pixels, float(slot.source_cell) * 0.85)
		var display_scale := minf(maxf(1.0, pixel_floor / shortest), maxf(1.0, float(slot.source_cell) * 1.20 / longest))
		dimensions *= display_scale * (0.62 + fade * 0.38)
		var orientation: Basis = slot.orientation
		var block_basis := Basis(orientation.x * dimensions.x, orientation.y * dimensions.y, orientation.z * dimensions.z)
		var block_pose := Transform3D(block_basis, slot.position)
		slot.render_dimensions = dimensions
		slot.render_transform = block_pose
		cores.set_instance_transform(index, block_pose)
		cores.set_instance_color(index, color)
		# Only a minority have an auxiliary detached cube. Its short gap and
		# simulation-time cadence produce broken hot flecks, not a laser trail.
		var held_cut := bool(slot.get("held_cut",false))
		var tail_period := 0.018 if held_cut else 0.024
		var tail_duty := 0.010 if held_cut else 0.014
		slot.tail_visible = bool(slot.tail_point) and age_fraction < 0.66 and fposmod(float(slot.age) + float(slot.tail_phase), tail_period) < tail_duty
		if slot.tail_visible:
			var tail_orientation := orientation * _tail_orientation
			var tail_dimensions := dimensions * 0.36
			var tail_basis := Basis(tail_orientation.x * tail_dimensions.x, tail_orientation.y * tail_dimensions.y, tail_orientation.z * tail_dimensions.z)
			var gap := minf(0.14, 0.05 + float(slot.size) * 0.85)
			var tail_position: Vector3 = slot.position - Vector3(slot.velocity).normalized() * gap
			halos.set_instance_transform(index, Transform3D(tail_basis, tail_position))
			var tail_color := VoxelDebris.spark_heat_color(minf(1.0, age_fraction + 0.25)) * (0.40 + fade * 0.35)
			tail_color.a = 1.0
			halos.set_instance_color(index, tail_color)
		else:
			halos.set_instance_transform(index, _hidden_pose)

	func _hide_slot(index: int) -> void:
		cores.set_instance_transform(index, _hidden_pose)
		halos.set_instance_transform(index, _hidden_pose)

	func get_debug_state() -> Dictionary:
		var heat_samples: Array[Dictionary] = []
		var shape_samples: Array[Dictionary] = []
		var cube_count := 0
		var cuboid_count := 0
		var tail_point_count := 0
		var held_active_count := 0
		var active_layers := {"standard":0,"hot_jet":0,"hot_plate":0,"cut_flash":0}
		var maximum_aspect := 0.0
		for slot in slots:
			if not slot.is_empty():
				if bool(slot.get("held_cut",false)):
					held_active_count += 1
				var layer: String = slot.get("layer","standard")
				active_layers[layer] = int(active_layers[layer])+1
				var dimensions: Vector3 = slot.dimensions
				maximum_aspect = maxf(maximum_aspect, maxf(dimensions.x, maxf(dimensions.y, dimensions.z)) / minf(dimensions.x, minf(dimensions.y, dimensions.z)))
				if slot.cuboid:
					cuboid_count += 1
				else:
					cube_count += 1
				if slot.tail_visible:
					tail_point_count += 1
				var heat_fraction := clampf(float(slot.age) / float(slot.life), 0.0, 1.0)
				if heat_samples.size() < 3:
					heat_samples.append({"age_fraction": heat_fraction, "color": VoxelDebris.spark_heat_color(heat_fraction), "width": slot.size, "length": slot.length, "head_width_pixels": slot.head_pixels, "tail_ribbon_pixels": slot.tail_pixels, "long_ray": false})
					var orientation: Basis = slot.orientation
					shape_samples.append({"geometry": "short_cuboid" if slot.cuboid else "cube", "dimensions": dimensions, "render_dimensions": slot.render_dimensions, "orientation_axes": [orientation.x, orientation.y, orientation.z], "angular_velocity": slot.angular_velocity, "tail_point_visible": slot.tail_visible,"held_cut":bool(slot.get("held_cut",false)),"layer":layer,"heat_gain":float(slot.get("heat_gain",1.0))})
		# Keep all previous debug fields available to combat capture tools.
		return {
			"style": "metal_spark", "shape": "tumbling_voxel_blocks", "primary_mesh": cores.mesh.get_class(), "secondary_mesh": halos.mesh.get_class(),
			"tail_shape": "sparse_detached_box_points", "length_semantics": "longest_primary_edge_m", "shape_samples": shape_samples,
			"cube_count": cube_count, "cuboid_count": cuboid_count, "tail_point_count": tail_point_count, "primary_aspect_max": maximum_aspect,
			"active_count": active_count, "capacity": VoxelDebris.CUT_PARTICLE_CAPACITY, "global_active_count": global_active_count, "global_capacity": VoxelDebris.CUT_PARTICLE_GLOBAL_CAPACITY,
			"burst_multiplier": VoxelDebris.CUT_PARTICLE_BURST_MULTIPLIER, "impulse_multiplier": VoxelDebris.CUT_PARTICLE_IMPULSE_MULTIPLIER, "lifetime_multiplier": VoxelDebris.CUT_PARTICLE_LIFETIME_MULTIPLIER,
			"emitted_total": emitted_total, "emitted_body": emitted_body, "emitted_debris": emitted_debris, "emitted_sever": emitted_sever,
			"last_burst_count": last_burst_count, "last_tier_counts": last_tier_counts.duplicate(),
			"held_emitted_total":emitted_held,"standard_emitted_total":emitted_standard,"held_active_count":held_active_count,"held_burst_multiplier":VoxelDebris.HELD_CUT_BURST_MULTIPLIER,
			"last_feedback_mode":last_feedback_mode,"last_base_burst_count":last_base_burst_count,"last_requested_burst_count":last_requested_burst_count,"last_held_pool_available":last_held_pool_available,"last_layer_counts":last_layer_counts.duplicate(),"active_layer_counts":active_layers,"held_recycle_min_age_fraction":0.25,
			"size_min": 0.0 if size_min == INF else size_min, "size_max": size_max, "width_min": 0.0 if size_min == INF else size_min, "width_max": size_max,
			"length_min": 0.0 if length_min == INF else length_min, "length_max": length_max, "source_cell_min": 0.0 if source_cell_min == INF else source_cell_min, "source_cell_max": source_cell_max,
			"palette": VoxelDebris.CUT_PARTICLE_COLORS, "emission": 0.0, "brightness_output": "unshaded_albedo", "tail_albedo_gain": 0.75,
			"min_lifetime": 0.0 if min_lifetime == INF else min_lifetime, "max_lifetime": max_lifetime, "heat_samples": heat_samples,
			"last_widths": last_widths.duplicate(), "last_lengths": last_lengths.duplicate(), "last_dimensions": last_dimensions.duplicate(), "last_spins": last_spins.duplicate(),
			"last_source_kind": last_source_kind, "last_origins": last_origins.duplicate(), "last_source_points": last_sources.duplicate(), "last_velocities": last_velocities.duplicate(),
			"cut_tangent": last_cut_tangent, "cut_normal": last_cut_normal, "simulation_scale": float(source_owner.get_meta("simulation_scale", 1.0)), "world_space": top_level,
		}

	func _exit_tree() -> void:
		global_active_count -= active_count
		active_count = 0


func _process(delta: float) -> void:
	var owner_node: Node3D = get_parent()
	if bool(owner_node.get_meta("boss_death_hold",false)):
		return
	var simulation_scale: float = float(owner_node.get_meta("simulation_scale", 1.0))
	var step: float = delta * simulation_scale
	elapsed += step
	velocity.y -= 12.0 * step
	position += velocity * step
	if bool(owner_node.get_meta("flythrough_enabled", false)) and not bool(owner_node.get_meta("boss_death_stationary",false)):
		# Parent motion is already applied by the runner. Replace it, rather than
		# adding another full running speed to fragments attached to a live enemy.
		var parent_motion: Vector3 = owner_node.get_meta("root_motion_velocity", Vector3(0, 0, float(owner_node.get_meta("root_forward_speed", 0.0))))
		var runner_speed: float = maxf(0.0, float(owner_node.get_meta("runner_speed", 0.0)))
		position += (Vector3(0, 0, maxf(48.0, runner_speed * 1.35)) - parent_motion) * step
	rotation += spin * step
	if has_meta("world_floor_height"):
		floor_height = float(get_meta("world_floor_height"))-owner_node.global_position.y
	if position.y < floor_height:
		position.y = floor_height
		velocity.y = absf(velocity.y) * 0.20
		velocity.x *= maxf(0.0, 1.0 - step * 2.0)
		# Friction damps the cut impulse only. Runner flow above remains intact.
		velocity.z *= maxf(0.0, 1.0 - step * 0.6)
	if elapsed > lifetime - 0.45:
		var fraction: float = clampf((lifetime - elapsed) / 0.45, 0.001, 1.0)
		scale = Vector3.ONE * fraction
	if elapsed >= lifetime:
		queue_free()
	elif bool(owner_node.get_meta("flythrough_enabled", false)) and global_position.z > 4.0:
		queue_free()


func _split_disconnected(stroke: Vector2) -> void:
	var piece_count := 0
	for sibling in get_parent().get_children():
		if sibling.get_meta("voxel_piece", false) and not sibling.is_queued_for_deletion():
			piece_count += 1
	# The full pool retains every extra island in this same sliceable chunk.
	# No connectivity result is consumed in that branch, so skip its scan.
	if piece_count >= MAX_VOXEL_PIECES:
		return
	var groups: Array = _connected_groups()
	if groups.size() <= 1:
		return
	groups.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size())
	var stroke_direction := stroke.normalized()
	for group_index in range(1, groups.size()):
		if piece_count >= MAX_VOXEL_PIECES:
			# Keep additional islands visible and sliceable in this chunk instead of deleting material.
			break
		var group: Array = groups[group_index]
		var center := Vector3.ZERO
		var group_cells: Dictionary = {}
		for coordinate: Vector3i in group:
			center += _cell_point(coordinate)
			group_cells[coordinate] = cells[coordinate]
		center /= float(group.size())
		var fragment = get_script().new()
		get_parent().add_child(fragment)
		fragment.transform = transform * Transform3D(Basis.IDENTITY, center)
		if bool(get_parent().get_meta("flythrough_enabled", false)):
			fragment.velocity = velocity + Vector3(signf(center.x) * 1.8 + stroke_direction.x * 1.6, 0.8 - stroke_direction.y, 1.2)
			fragment.spin = spin + Vector3(0.8, -0.5, 1.1)
		else:
			fragment.velocity = velocity + Vector3(signf(center.x) * 0.7 + stroke_direction.x * 0.6, 0.6, 0.3)
			fragment.spin = spin + Vector3(0.3, -0.2, 0.4)
		fragment.lifetime = maxf(1.8, lifetime - elapsed)
		fragment.floor_height = maxf(0.04, floor_height + center.y)
		if has_meta("world_floor_height"):
			fragment.set_meta("world_floor_height",float(get_meta("world_floor_height"))+fragment.position.y-position.y)
			fragment.floor_height = float(fragment.get_meta("world_floor_height"))-get_parent().global_position.y
		if get_parent().has_meta("sky_lane"):
			fragment.floor_height = floor_height + center.y
		fragment.configure_voxels(group_cells, cell_size, palette, _material, _origin - center)
		for coordinate: Vector3i in group:
			cells.erase(coordinate)
		piece_count += 1


func _connected_groups() -> Array:
	var unvisited: Dictionary = cells.duplicate()
	var groups: Array = []
	# Dictionary iteration preserves the same first-remaining seed order, but
	# does not allocate all remaining keys again for every disconnected island.
	for first: Vector3i in cells:
		if not unvisited.has(first):
			continue
		var queue: Array[Vector3i] = [first]
		var head := 0
		unvisited.erase(first)
		while head < queue.size():
			var coordinate: Vector3i = queue[head]
			head += 1
			for direction in DIRECTIONS:
				var adjacent: Vector3i = coordinate + direction
				if unvisited.has(adjacent):
					queue.append(adjacent)
					unvisited.erase(adjacent)
		groups.append(queue)
	return groups


func _ensure_visual() -> void:
	if _visual == null:
		_visual = MeshInstance3D.new()
		_visual.name = "SliceableVoxelSurface"
		_visual.material_override = _material
		add_child(_visual)


func _rebuild() -> void:
	_ensure_visual()
	# Shared intact surfaces use a local translation. Recut meshes already
	# include the authored origin, so they must return to the identity pose.
	_visual.transform = Transform3D.IDENTITY
	set_meta("shared_intact_mesh",false)
	if cells.is_empty():
		_visual.visible = false
		return
	_bulk_vertices = PackedVector3Array()
	_bulk_normals = PackedVector3Array()
	_bulk_colors = PackedColorArray()
	_face_normals = []
	_face_colors = []
	var bulk := cells.size() >= 128
	var surface: SurfaceTool
	if bulk:
		for side in range(6):
			var normal := Vector3(DIRECTIONS[side])
			_face_normals.append(PackedVector3Array([normal,normal,normal,normal,normal,normal]))
			var shades: Array[PackedColorArray] = []
			for color: Color in palette:
				var shade := 0.84+maxf(normal.y,0.0)*0.16
				var tint := Color(color.r*shade,color.g*shade,color.b*shade,1.0)
				shades.append(PackedColorArray([tint,tint,tint,tint,tint,tint]))
			_face_colors.append(shades)
	else:
		surface = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var coordinates := cells.keys()
	var materials := cells.values()
	var grid_low: Vector3i = coordinates[0]
	var grid_high := grid_low
	for coordinate: Vector3i in coordinates:
		grid_low = grid_low.min(coordinate)
		grid_high = grid_high.max(coordinate)
	var span := grid_high-grid_low+Vector3i(3,3,3)
	var plane := span.x*span.y
	# Disconnected/sparse recut islands may span a huge integer box. Keep
	# those on the original dictionary lookup path instead of allocating it.
	var dense := span.x>0 and span.y>0 and span.z>0 and span.x<=2000000 and span.y<=2000000 and span.z<=2000000 and plane*span.z<=2000000
	var occupied := PackedByteArray()
	var indices := PackedInt32Array()
	if dense:
		occupied.resize(plane*span.z)
		for coordinate: Vector3i in coordinates:
			var p := coordinate-grid_low+Vector3i.ONE
			var index := p.x+p.y*span.x+p.z*plane
			occupied[index] = 1
			indices.append(index)
	var strides := [1,-1,span.x,-span.x,plane,-plane]
	var low := _cell_point(grid_low) - Vector3.ONE * cell_size * 0.5
	var high := _cell_point(grid_high) + Vector3.ONE * cell_size * 0.5
	# Keep every real cell for cuts and connectivity. Only coplanar exposed
	# faces of the same palette entry share a rectangle in the visual mesh.
	for side in range(6):
		var axis: int = side / 2
		var u := 1 if axis == 0 else 0
		var v := 2 if axis < 2 else 1
		var row := grid_high[u] - grid_low[u] + 1
		var rows := grid_high[v] - grid_low[v] + 1
		var layers: Dictionary = {}
		for item in range(coordinates.size()):
			var coordinate: Vector3i = coordinates[item]
			if (occupied[indices[item]+int(strides[side])] != 0 if dense else cells.has(coordinate+DIRECTIONS[side])):
				continue
			var layer := Vector2i(coordinate[axis], int(materials[item]))
			if not layers.has(layer):
				layers[layer] = {}
			layers[layer][coordinate[u] - grid_low[u] + (coordinate[v] - grid_low[v]) * row] = true
		for layer: Vector2i in layers:
			var mask: Dictionary = layers[layer]
			for key: int in mask.keys():
				if not mask.has(key):
					continue
				var x: int = key % row
				var y: int = key / row
				var width := 1
				while x + width < row and mask.has(key + width):
					width += 1
				var height := 1
				while y + height < rows:
					var complete := true
					for step in range(width):
						if not mask.has(key + height * row + step):
							complete = false
							break
					if not complete:
						break
					height += 1
				for yy in range(height):
					for xx in range(width):
						mask.erase(key + xx + yy * row)
				var coordinate := Vector3i.ZERO
				coordinate[axis] = layer.x
				coordinate[u] = x + grid_low[u]
				coordinate[v] = y + grid_low[v]
				var center := _cell_point(coordinate)
				center[u] += float(width - 1) * cell_size * 0.5
				center[v] += float(height - 1) * cell_size * 0.5
				if bulk: _append_bulk_face(center, side, layer.y, width, height)
				else: _add_face(surface,center,side,palette[layer.y],width,height)
	_bounds = AABB(low, high - low)
	if bulk:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _bulk_vertices
		arrays[Mesh.ARRAY_NORMAL] = _bulk_normals
		arrays[Mesh.ARRAY_COLOR] = _bulk_colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		_visual.mesh = mesh
	else: _visual.mesh = surface.commit()
	_bulk_vertices = PackedVector3Array()
	_bulk_normals = PackedVector3Array()
	_bulk_colors = PackedColorArray()
	_face_normals.clear()
	_face_colors.clear()
	_visual.visible = true



func _append_bulk_face(center: Vector3, side: int, material: int, width: int = 1, height: int = 1) -> void:
	var normal := Vector3(DIRECTIONS[side])
	var tangent: Vector3 = Vector3.UP if side < 2 else Vector3.RIGHT
	var bitangent: Vector3 = normal.cross(tangent)
	var half := cell_size * 0.5
	var face_center := center + normal * half
	var along := tangent * half * width
	var across := bitangent * half * height
	var a := face_center + along + across
	var b := face_center + along - across
	var c := face_center - along - across
	var d := face_center - along + across
	_bulk_vertices.append_array(PackedVector3Array([a,b,c,a,c,d]))
	_bulk_normals.append_array(_face_normals[side])
	_bulk_colors.append_array(_face_colors[side][material])


func _add_face(surface: SurfaceTool, center: Vector3, side: int, color: Color, width: int = 1, height: int = 1) -> void:
	var normal := Vector3(DIRECTIONS[side])
	var tangent: Vector3 = Vector3.UP if side < 2 else Vector3.RIGHT
	var bitangent: Vector3 = normal.cross(tangent)
	var half := cell_size * 0.5
	var face_center := center + normal * half
	var along := tangent * half * width
	var across := bitangent * half * height
	var a := face_center + along + across
	var b := face_center + along - across
	var c := face_center - along - across
	var d := face_center - along + across
	var shade := 0.84 + maxf(normal.y, 0.0) * 0.16
	surface.set_normal(normal)
	surface.set_color(Color(color.r * shade, color.g * shade, color.b * shade, 1.0))
	for vertex in [a, b, c, a, c, d]:
		surface.add_vertex(vertex)


func _cell_point(coordinate: Vector3i) -> Vector3:
	return _origin + Vector3(coordinate) * cell_size


func _longest_stroke(points: PackedVector2Array) -> Vector2:
	var result := Vector2.ZERO
	for index in range(points.size() - 1):
		var stroke := points[index + 1] - points[index]
		if stroke.length_squared() > result.length_squared():
			result = stroke
	return result


func _segment_overlaps_rect(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	if rect.has_point(from) or rect.has_point(to):
		return true
	var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for side in range(4):
		if Geometry2D.segment_intersects_segment(from, to, corners[side], corners[(side + 1) % 4]) != null:
			return true
	return false


static func blade_motion_points(frames: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for frame in frames:
		if frame.size() >= 2:
			points.append((Vector2(frame[0]) + Vector2(frame[1])) * 0.5)
	return points


static func sweep_regions(frames: Array, target_bounds: Rect2, band: float) -> Array[Dictionary]:
	var regions: Array[Dictionary] = []
	if frames.size() < 2:
		return regions
	var run_start: PackedVector2Array = frames[0]
	var run_end: PackedVector2Array = frames[1]
	for index in range(2, frames.size()):
		var next: PackedVector2Array = frames[index]
		if _same_translation_run(run_start, run_end, next):
			run_end = next
			continue
		_append_sweep_region(regions, run_start, run_end, target_bounds, band)
		run_start = run_end
		run_end = next
	_append_sweep_region(regions, run_start, run_end, target_bounds, band)
	return regions


static func _same_translation_run(start: PackedVector2Array, end: PackedVector2Array, next: PackedVector2Array) -> bool:
	if start.size() < 2 or end.size() < 2 or next.size() < 2:
		return false
	# Only parallel, equal-length edges undergoing the same forward translation
	# form one identical swept quad. Never bridge a reversal, bend, or blade turn.
	var edge: Vector2 = start[1] - start[0]
	if edge.distance_squared_to(end[1] - end[0]) > 0.000001 or edge.distance_squared_to(next[1] - next[0]) > 0.000001:
		return false
	var before: Vector2 = end[0] - start[0]
	var after: Vector2 = next[0] - end[0]
	if before.length_squared() < 0.000001 or after.length_squared() < 0.000001:
		return before.length_squared() < 0.000001 or next[0].distance_squared_to(end[0]) < 0.000001
	if before.dot(after) <= 0.0:
		return false
	# Packed screen vectors have subpixel rounding after projection. This is a
	# 0.001-pixel line tolerance, far below a voxel's existing cut band.
	return absf(before.cross(next[0] - start[0])) <= before.length() * 0.001


static func _append_sweep_region(regions: Array[Dictionary], from: PackedVector2Array, to: PackedVector2Array, target_bounds: Rect2, band: float) -> void:
	if from.size() < 2 or to.size() < 2:
		return
	var quad := PackedVector2Array([from[0], from[1], to[1], to[0]])
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point in quad:
		low = low.min(point)
		high = high.max(point)
	var bounds := Rect2(low, high - low).grow(band)
	if bounds.intersects(target_bounds):
		var first := PackedVector2Array()
		var second := PackedVector2Array()
		if absf((quad[1] - quad[0]).cross(quad[2] - quad[0])) >= 0.0001:
			first = PackedVector2Array([quad[0], quad[1], quad[2]])
		if absf((quad[2] - quad[0]).cross(quad[3] - quad[0])) >= 0.0001:
			second = PackedVector2Array([quad[0], quad[2], quad[3]])
		regions.append({"quad": quad, "bounds": bounds, "first": first, "second": second})


static func point_in_sweep(point: Vector2, regions: Array[Dictionary], band_squared: float) -> bool:
	for region in regions:
		if not Rect2(region.bounds).has_point(point):
			continue
		var quad: PackedVector2Array = region.quad
		# Keep the exact two-triangle union, even for crossed frames. Native
		# triangle tests avoid interpreting the same scalar math for every voxel.
		if (not region.first.is_empty() and Geometry2D.is_point_in_polygon(point, region.first)) or (not region.second.is_empty() and Geometry2D.is_point_in_polygon(point, region.second)):
			return true
		for edge in range(4):
			if Geometry2D.get_closest_point_to_segment(point, quad[edge], quad[(edge + 1) % 4]).distance_squared_to(point) <= band_squared:
				return true
	return false


static func _inside_triangle(point: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var area: float = (b - a).cross(c - a)
	if absf(area) < 0.0001:
		return false
	var first: float = (b - a).cross(point - a)
	var second: float = (c - b).cross(point - b)
	var third: float = (a - c).cross(point - c)
	return (first >= 0.0 and second >= 0.0 and third >= 0.0) or (first <= 0.0 and second <= 0.0 and third <= 0.0)
