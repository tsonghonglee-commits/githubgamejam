class_name VoxelBlast
extends Node3D

const MAX_PARTICLES := 96
const MAX_REFLECTED_PARTICLES := 224
const REFLECTED_CORE_PARTICLES := 9
static var _mesh: BoxMesh
static var _material: ShaderMaterial
var _instances: MultiMesh
var _visual: MultiMeshInstance3D
var _velocities := PackedVector3Array()
var _spins := PackedVector3Array()
var _sizes := PackedVector3Array()
var _offsets := PackedVector3Array()
var _layers := PackedByteArray()
var _ages := 0.0
var _life := 0.44
var _runner_speed := 0.0
var _pose_initialized := false
var _reflected_impact := false
var _strength := 1.0


func configure(strength: float, runner_speed: float, reflected_impact: bool = false) -> void:
	_runner_speed = runner_speed
	_strength = maxf(strength,0.01)
	_reflected_impact = reflected_impact
	_life = (0.52 if reflected_impact else 0.34) + strength*0.12
	_ages = 0.0
	_pose_initialized = false
	_velocities.clear()
	_spins.clear()
	_sizes.clear()
	_offsets.clear()
	_layers.clear()
	if is_instance_valid(_visual):
		_visual.free()
	if _mesh == null:
		_mesh = BoxMesh.new()
		_mesh.size = Vector3.ONE
		var shader := Shader.new()
		shader.code = """shader_type spatial;
render_mode unshaded, cull_back;
void fragment() {
	float face = 0.55 + 0.45 * abs(dot(NORMAL, normalize(vec3(0.4,0.8,0.3))));
	ALBEDO = COLOR.rgb * face;
}
"""
		_material = ShaderMaterial.new()
		_material.shader = shader
	_instances = MultiMesh.new()
	_instances.transform_format = MultiMesh.TRANSFORM_3D
	_instances.use_colors = true
	_instances.mesh = _mesh
	_instances.instance_count = mini(MAX_REFLECTED_PARTICLES,int(128+strength*80)) if reflected_impact else mini(MAX_PARTICLES,int(40+strength*32))
	_visual = MultiMeshInstance3D.new()
	_visual.multimesh = _instances
	_visual.material_override = _material
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_visual)
	for index in range(_instances.instance_count):
		if reflected_impact:
			_add_reflected_particle(index)
			continue
		var direction := Vector3(randf_range(-1,1),randf_range(-0.65,1),randf_range(-1,1)).normalized()
		_velocities.append(direction*randf_range(4.0,13.0)*strength)
		_spins.append(Vector3(randf_range(-12,12),randf_range(-12,12),randf_range(-12,12)))
		var size := randf_range(0.035,0.12)*strength
		_sizes.append(Vector3(size,size,size*randf_range(0.65,1.8)))
		_offsets.append(Vector3.ZERO)
		_layers.append(0)
	_instances.visible_instance_count = _instances.instance_count
	advance(0.0)


func _add_reflected_particle(index: int) -> void:
	# The first few solid cubes form a sub-100ms blast core. The remaining
	# layers separate into fast hot chips and slower, larger tumbling pieces.
	# All use this one bounded opaque MultiMesh; no screen flash or halo.
	var layer := 2 if index < REFLECTED_CORE_PARTICLES else (1 if index%7 == 0 else 0)
	var direction := Vector3(randf_range(-1,1),randf_range(-0.4,1),randf_range(-1,1)).normalized()
	var mass_scale := sqrt(_strength)
	var size: float
	var impulse: float
	match layer:
		2:
			size = randf_range(0.28,0.46)*mass_scale
			impulse = randf_range(3.0,8.0)*mass_scale
		1:
			size = randf_range(0.11,0.22)*mass_scale
			impulse = randf_range(7.0,17.0)*mass_scale
		_:
			size = randf_range(0.055,0.12)*mass_scale
			impulse = randf_range(18.0,36.0)*mass_scale
	_velocities.append(direction*impulse)
	_spins.append(Vector3(randf_range(-23,23),randf_range(-23,23),randf_range(-23,23)))
	_sizes.append(Vector3(size,size,size*randf_range(0.7,1.65)))
	_offsets.append(direction*randf_range(0.02,0.18)*mass_scale)
	_layers.append(layer)


func advance(sim_dt: float) -> bool:
	if sim_dt <= 0.0 and _pose_initialized:
		return true
	_ages += sim_dt
	if _ages >= _life:
		queue_free()
		return false
	if _reflected_impact:
		_advance_reflected()
		_pose_initialized = true
		return true
	var fraction := clampf(_ages/_life,0.0,1.0)
	var scale_factor := pow(1.0-fraction,0.7)
	var cooling := pow(fraction,0.6)
	var cooled := Color(0.19,0.065,0.017)
	var hot_core := Color(2.7,2.3,1.4).lerp(cooled,cooling)
	var hot_edge := Color(1.9,0.88,0.16).lerp(cooled,cooling)
	for index in range(_instances.instance_count):
		var position := _velocities[index]*_ages + Vector3(0,-5.0*_ages*_ages,_runner_speed*_ages)
		var basis := Basis.from_euler(_spins[index]*_ages).scaled(_sizes[index]*scale_factor)
		_instances.set_instance_transform(index,Transform3D(basis,position))
		_instances.set_instance_color(index,hot_core if index%4 == 0 else hot_edge)
	_pose_initialized = true
	return true


func _advance_reflected() -> void:
	# Evaluate each layer's cooling, drag and shrink once for the whole batch.
	var fast_fraction := clampf(_ages/(_life*0.72),0.0,1.0)
	var heavy_fraction := clampf(_ages/_life,0.0,1.0)
	var core_fraction := clampf(_ages/(0.06+sqrt(_strength)*0.02),0.0,1.0)
	var scales := Vector3(pow(1.0-fast_fraction,0.65),pow(1.0-heavy_fraction,0.9),pow(1.0-core_fraction,0.35))
	var flights := Vector3((1.0-exp(-_ages*3.8))/3.8,(1.0-exp(-_ages*1.6))/1.6,_ages)
	var flow := Vector3(0,0,_runner_speed*_ages)
	var gravity := Vector3(0,-7.0*_ages*_ages,0)
	var cold := Color(0.12,0.039,0.009)
	var fast_hot := Color(3.8,2.8,1.3).lerp(cold,pow(fast_fraction,0.52))
	var fast_edge := Color(2.9,1.20,0.18).lerp(cold,pow(fast_fraction,0.58))
	var heavy_hot := Color(2.0,0.83,0.13).lerp(cold,pow(heavy_fraction,0.40))
	var core_hot := Color(4.6,3.8,2.4).lerp(Color(2.2,0.70,0.10),core_fraction)
	for index in range(_instances.instance_count):
		var layer: int = _layers[index]
		var position := _offsets[index]+_velocities[index]*flights[layer]+gravity+flow
		var basis := Basis.from_euler(_spins[index]*_ages).scaled(_sizes[index]*scales[layer])
		_instances.set_instance_transform(index,Transform3D(basis,position))
		var color := core_hot if layer == 2 else (heavy_hot if layer == 1 else (fast_hot if index%5 == 0 else fast_edge))
		_instances.set_instance_color(index,color)


func get_debug_state() -> Dictionary:
	# Explicit diagnostic read of the submitted CPU instance poses; not a GPU
	# visibility or physical-memory readback measurement. Never used per frame.
	var bounds := AABB()
	var visible_count := 0
	var maximum_speed := 0.0
	var maximum_size := 0.0
	var layers := Vector3i.ZERO
	if _instances != null:
		var cube := AABB(Vector3(-0.5,-0.5,-0.5),Vector3.ONE)
		for index in range(_instances.instance_count):
			layers[int(_layers[index])] += 1
			maximum_speed = maxf(maximum_speed,_velocities[index].length())
			maximum_size = maxf(maximum_size,_sizes[index][_sizes[index].max_axis_index()])
			var transform := _instances.get_instance_transform(index)
			if transform.basis.get_scale().length_squared() < 0.000001:
				continue
			var particle_bounds: AABB = transform*cube
			bounds = particle_bounds if visible_count == 0 else bounds.merge(particle_bounds)
			visible_count += 1
	return {"reflected_impact":_reflected_impact,"age":_ages,"life":_life,"runner_speed":_runner_speed,"instance_count":0 if _instances == null else _instances.instance_count,"noncollapsed_instances":visible_count,"layers_fast_heavy_core":str(layers),"maximum_initial_speed":maximum_speed,"maximum_initial_size":maximum_size,"cpu_local_bounds_position":str(bounds.position),"cpu_local_bounds_size":str(bounds.size),"pose_initialized":_pose_initialized}
