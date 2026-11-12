class_name SeriesEffects
extends Node3D
## Bounded, preallocated opaque fragments. Only visual particles live here;
## occupied actor material and real recuttable debris remain authoritative.

const POOL_SIZE := 8
const PARTICLES_PER_SLOT := 128
var _slots: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _serial: int = 0
static var _mesh: BoxMesh
static var _material: ShaderMaterial
const TRACE_POOL_SIZE := 96
var _trace_mesh: MultiMesh
var _traces: Array[Dictionary] = []
var _trace_cursor := 0


func configure() -> void:
	_rng.seed = 0x534552494553
	if _mesh == null:
		_mesh = BoxMesh.new()
		_mesh.size = Vector3.ONE
		var shader := Shader.new()
		shader.code = """shader_type spatial;
render_mode unshaded, cull_back;
void fragment() { ALBEDO = COLOR.rgb * (0.57+0.43*abs(dot(NORMAL,normalize(vec3(0.3,0.8,0.5))))); }
"""
		_material = ShaderMaterial.new()
		_material.shader = shader
	for slot_index in range(POOL_SIZE):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _mesh
		mm.instance_count = PARTICLES_PER_SLOT
		mm.visible_instance_count = 0
		var visual := MultiMeshInstance3D.new()
		visual.multimesh = mm
		visual.material_override = _material
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)
		var velocities := PackedVector3Array()
		var offsets := PackedVector3Array()
		var sizes := PackedVector3Array()
		var spins := PackedVector3Array()
		var colors := PackedColorArray()
		velocities.resize(PARTICLES_PER_SLOT)
		offsets.resize(PARTICLES_PER_SLOT)
		sizes.resize(PARTICLES_PER_SLOT)
		spins.resize(PARTICLES_PER_SLOT)
		colors.resize(PARTICLES_PER_SLOT)
		_slots.append({"mesh":mm,"visual":visual,"velocity":velocities,"offset":offsets,"size":sizes,"spin":spins,"color":colors,"age":10.0,"life":0.0,"active":false,"count":0,"serial":0,"gravity":-5.0,"drag":1.6,"flow":0.0})
	_trace_mesh = MultiMesh.new()
	_trace_mesh.transform_format = MultiMesh.TRANSFORM_3D
	_trace_mesh.use_colors = true
	_trace_mesh.mesh = _mesh
	_trace_mesh.instance_count = TRACE_POOL_SIZE
	var ribbons := MultiMeshInstance3D.new()
	ribbons.multimesh = _trace_mesh
	ribbons.material_override = _material
	ribbons.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ribbons)
	for index in range(TRACE_POOL_SIZE):
		_traces.append({"age":1.0,"life":0.0,"transform":Transform3D.IDENTITY,"color":Color.BLACK})
		_trace_mesh.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),Vector3.ZERO))


func emit_trace(a: Vector3,b: Vector3,width: float,tint: Color,life: float = 0.18,drift: Vector3 = Vector3.ZERO) -> void:
	if _trace_mesh == null or a.distance_squared_to(b) < 0.000001: return
	var direction := b-a
	var up := Vector3.UP if absf(direction.normalized().dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var basis := Basis.looking_at(direction.normalized(),up).scaled(Vector3(width,width,direction.length()))
	var slot: Dictionary = _traces[_trace_cursor]
	slot.age = 0.0
	slot.life = maxf(life,0.01)
	slot.transform = Transform3D(basis,(a+b)*0.5)
	slot.color = tint
	slot.drift = drift
	_trace_mesh.set_instance_transform(_trace_cursor,slot.transform)
	_trace_mesh.set_instance_color(_trace_cursor,tint)
	_trace_cursor = (_trace_cursor+1)%TRACE_POOL_SIZE


func emit_arc(center: Vector3,radius: float,normal: Vector3,tint: Color,start: float = 0.0,span: float = TAU,spread_speed: float = 0.0,life: float = 0.28) -> void:
	var axis := normal.normalized()
	var first := axis.cross(Vector3.UP).normalized() if absf(axis.dot(Vector3.UP)) < 0.96 else Vector3.RIGHT
	var second := axis.cross(first).normalized()
	var count := 12
	for index in range(count):
		var a := start+span*float(index)/float(count)
		var b := start+span*float(index+1)/float(count)
		var start_axis := first*cos(a)+second*sin(a)
		var end_axis := first*cos(b)+second*sin(b)
		emit_trace(center+start_axis*radius,center+end_axis*radius,0.025+radius*0.018,tint,life,(start_axis+end_axis).normalized()*spread_speed)


func emit_burst(point: Vector3, series: int, strength: float = 1.0, stage: int = 0, stationary: bool = true, runner_speed: float = 0.0) -> void:
	if _slots.is_empty(): return
	var selected: int = -1
	var oldest: int = 9223372036854775807
	for index in range(_slots.size()):
		if not bool(_slots[index].active):
			selected = index
			break
		if int(_slots[index].serial) < oldest:
			oldest = int(_slots[index].serial)
			selected = index
	var slot: Dictionary = _slots[selected]
	_serial += 1
	slot.serial = _serial
	slot.active = true
	slot.age = 0.0
	slot.life = 0.72 + minf(strength,2.0)*0.25
	slot.flow = 0.0 if stationary else runner_speed
	slot.count = clampi(int(36.0+strength*36.0),24,PARTICLES_PER_SLOT)
	slot.visual.global_position = point
	slot.gravity = -1.5 if series == 2 else (-3.8 if series == 4 else -6.0)
	slot.drag = 3.2 if series == 2 else (1.2 if series == 4 else 1.8)
	var amplitude := sqrt(maxf(strength,0.05))
	for index in range(int(slot.count)):
		var direction := Vector3(_rng.randf_range(-1,1),_rng.randf_range(-0.25,1.0),_rng.randf_range(-1,1)).normalized()
		var speed := _rng.randf_range(3.0,12.0)*amplitude
		var edge := _rng.randf_range(0.035,0.13)*amplitude
		var tint := Color(2.4,1.1,0.2)
		var particle_size := Vector3(edge,edge,edge*1.35)
		match series:
			2:
				direction.y += 0.4
				particle_size = Vector3(edge*2.8,edge*0.75,edge*0.22)
				tint = Color("b91e31") if index%7 == 0 else (Color("e5e0d6") if index%4 == 0 else Color("151719"))
				if stage >= 2 and index%9 == 0: tint = Color(2.2,0.1,0.16)
			3:
				particle_size.z *= 2.5 if index%5 == 0 else 1.0
				if stage >= 2:
					tint = Color(0.1,2.5,2.4) if index%3 == 0 else (Color(2.3,2.6,2.7) if index%2 == 0 else Color(0.5,0.8,1.6))
				else:
					tint = Color(0.1,2.5,2.4) if index%6 == 0 else (Color(2.8,0.18,0.4) if index%11 == 0 else Color(2.6,1.4,0.55))
			4:
				direction.y = absf(direction.y)+0.5
				particle_size = Vector3(edge*0.8,edge*2.2,edge*0.8)
				tint = Color(1.8,2.2,2.3) if index%3 == 0 else Color(0.35,0.95,1.2)
				if stage >= 2 and index%9 == 0: tint = Color(2.6,1.3,0.25)
			5:
				particle_size.z *= 3.4 if index%4 == 0 else 1.0
				tint = Color(0.25,1.9,2.8) if index%5 == 0 else (Color(3.0,2.8,2.3) if index%3 == 0 else Color(1.2,0.15,0.2))
		slot.velocity[index] = direction*speed
		slot.offset[index] = direction*_rng.randf_range(0.0,0.25)*amplitude
		slot.size[index] = particle_size
		slot.spin[index] = Vector3(_rng.randf_range(-12,12),_rng.randf_range(-12,12),_rng.randf_range(-12,12))
		slot.color[index] = tint
	slot.mesh.visible_instance_count = int(slot.count)
	_draw_slot(slot)


func update(sim_dt: float) -> void:
	if sim_dt <= 0.0: return
	for index in range(_traces.size()):
		var trace: Dictionary = _traces[index]
		if float(trace.age) >= float(trace.life): continue
		trace.age = float(trace.age)+sim_dt
		var t := clampf(float(trace.age)/float(trace.life),0.0,1.0)
		var pose: Transform3D = trace.transform
		pose.origin += Vector3(trace.drift)*float(trace.age)
		pose.basis = pose.basis.scaled(Vector3(1.0-t,1.0-t,1))
		_trace_mesh.set_instance_transform(index,pose)
		_trace_mesh.set_instance_color(index,Color(trace.color).lerp(Color(0.04,0.045,0.05),t*t))
	for slot in _slots:
		if not bool(slot.active): continue
		slot.age = float(slot.age)+sim_dt
		if float(slot.age) >= float(slot.life):
			slot.active = false
			slot.mesh.visible_instance_count = 0
			continue
		_draw_slot(slot)


func _draw_slot(slot: Dictionary) -> void:
	var age: float = slot.age
	var fraction := clampf(age/float(slot.life),0.0,1.0)
	var shrink := pow(1.0-fraction,0.7)
	var flight := (1.0-exp(-age*float(slot.drag)))/float(slot.drag)
	var fall := Vector3(0,float(slot.gravity)*age*age,float(slot.flow)*age)
	for index in range(int(slot.count)):
		var point: Vector3 = slot.offset[index]+slot.velocity[index]*flight+fall
		var basis := Basis.from_euler(slot.spin[index]*age).scaled(slot.size[index]*shrink)
		slot.mesh.set_instance_transform(index,Transform3D(basis,point))
		slot.mesh.set_instance_color(index,Color(slot.color[index]).lerp(Color(0.035,0.043,0.05),fraction*0.82))


func clear() -> void:
	for slot in _slots:
		slot.active = false
		slot.mesh.visible_instance_count = 0
	for index in range(_traces.size()):
		_traces[index].age = _traces[index].life
		_trace_mesh.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),Vector3.ZERO))


func get_debug_state() -> Dictionary:
	var active := 0
	var count := 0
	for slot in _slots:
		if bool(slot.active):
			active += 1
			count += int(slot.count)
	return {"slots":POOL_SIZE,"particles_per_slot":PARTICLES_PER_SLOT,"active_slots":active,"visible_particles":count,"serial":_serial,"shared_mesh":true,"new_lights":0}
