extends Node3D
## The title uses an independent portrait camera so gameplay projection is untouched.

const Enemy = preload("res://scripts/voxel_enemy.gd")
const TITLE_LAYER := 1 << 7
const PORTRAIT_LAYER := 1 << 8
const STAGE_SCALE := 0.12
const SHOWCASE_SPEED := 1.0 / 3.0
const SHOT_SECONDS := 4.20
const SHOT_COVER := 0.34
const PORTRAIT_ANCHOR := Vector2(0.745,0.48)
const IRON := Color("1b2026")
const PORTRAITS := [
	{"kind":"normal","pose":"recover","phase":0.58,"yaw":-0.34,"elevation":0.12,"detail":Vector3(0.10,0.31,0.12)},
	{"kind":"interceptor","pose":"run","phase":0.28,"yaw":0.49,"elevation":0.24,"detail":Vector3(0.06,0.01,0.22)},
	{"kind":"ink_swordsman","pose":"recover","phase":0.74,"yaw":0.32,"elevation":0.04,"detail":Vector3(0.0,0.32,0.10)},
	{"kind":"cyber_riot","pose":"recover","phase":0.72,"yaw":-0.44,"elevation":0.09,"detail":Vector3(0.16,0.12,0.25)},
	{"kind":"sea_crab","pose":"run","phase":0.16,"yaw":0.44,"elevation":0.24,"detail":Vector3(0.0,0.13,0.22)},
	{"kind":"empire_dreadnought","pose":"run","phase":0.20,"yaw":-0.50,"elevation":0.21,"detail":Vector3(0.06,0.10,0.29)},
]

var _clock := 0.0
var _motion: Node3D
var _actors: Array[Node3D] = []
var _portrait_bounds: Array[AABB] = []
var _portrait_camera: Camera3D
var _portrait_view: SubViewport
var _portrait_image: TextureRect
var _backdrop_material: ShaderMaterial
var _configured := false
var intro_started := false
var _showcase_age := 0.0
var _shot_index := -1


func configure() -> void:
	if _configured: return
	_configured = true
	_build_stage()
	_build_portrait_camera()
	# Near-camera scale occludes the warmup and highway while preserving perspective.
	scale = Vector3.ONE*STAGE_SCALE


func set_active(active: bool) -> void:
	visible = active
	set_process(active and _configured)
	if _portrait_image != null:
		_portrait_image.visible = active and intro_started and not _actors.is_empty()
		_portrait_view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if _portrait_image.visible else SubViewport.UPDATE_DISABLED


func _process(delta: float) -> void:
	_clock += delta
	_backdrop_material.set_shader_parameter("time",_clock)
	if not intro_started: return
	_showcase_age = fposmod(_showcase_age+delta*SHOWCASE_SPEED,SHOT_SECONDS*PORTRAITS.size())
	_pose(_showcase_age)


func begin_intro() -> void:
	if intro_started: return
	intro_started = true
	_portrait_image.show()
	_portrait_view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_motion.show()
	_pose(0.0)


func prepare_roster() -> void:
	for shot in PORTRAITS:
		var actor = Enemy.new()
		_motion.add_child(actor)
		actor.configure(shot.kind,1)
		actor.set_process(false)
		actor.set_meta("simulation_scale",0.0)
		actor.set_meta("flythrough_enabled",false)
		actor.set_action(shot.pose,shot.phase)
		_set_layer(actor,PORTRAIT_LAYER)
		_portrait_bounds.append(_model_bounds(actor))
		actor.hide()
		_actors.append(actor)
		await get_tree().process_frame
	_motion.hide()


func _build_stage() -> void:
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
uniform float time = 0.0;
uniform float pulse = 0.0;
void fragment() {
	vec2 p = UV;
	float sweep = p.x + p.y * 0.43;
	vec2 center = p - vec2(0.61,0.47);
	float vignette = exp(-dot(center * vec2(1.35,1.0),center * vec2(1.35,1.0))*21.0);
	float panel = smoothstep(0.008,0.012,abs(fract(sweep*7.0)-0.5));
	float seam = 1.0-smoothstep(0.0,0.004,abs(fract((p.x-p.y*0.16)*18.0)-0.5));
	float scan = exp(-abs(p.y - fract(time*0.10+0.19))*76.0);
	vec3 graphite = vec3(0.012,0.020,0.030)+vignette*vec3(0.027,0.040,0.052);
	vec3 oxide = vec3(0.48,0.028,0.052);
	float flare = exp(-dot((p-vec2(0.60,0.50))*vec2(1.7,0.8),(p-vec2(0.60,0.50))*vec2(1.7,0.8))*52.0);
	float texture_noise = fract(sin(dot(floor(p*vec2(1800.0,1000.0)),vec2(127.1,311.7)))*43758.5453);
	ALBEDO = graphite*(0.92+0.08*panel)+seam*vignette*0.018+vignette*scan*0.012+oxide*flare*(0.16+0.37*pulse);
	ALBEDO *= 0.95+0.085*texture_noise;
}
"""
	material.shader = shader
	_backdrop_material = material
	var plate := QuadMesh.new()
	plate.size = Vector2(38,22)
	_mesh(plate,material,self,Vector3(0,0,-12.0))

	# The deck plates and the copper/blue line work are built in the same
	# industrial family as the highway. The left side stays dark for controls.
	var floor_shader := Shader.new()
	floor_shader.code = """shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled;
void fragment() {
	vec2 q = UV;
	float lane = 1.0-smoothstep(0.002,0.005,abs(fract(q.x*10.0)-0.5));
	float gap = 1.0-smoothstep(0.002,0.008,abs(fract(q.y*18.0)-0.5));
	float signal = lane * smoothstep(0.48,0.62,q.x) * (0.44+0.56*step(0.72,fract(q.y*9.0)));
	ALBEDO = vec3(0.028,0.041,0.054)*(0.74+q.y*0.26)-gap*0.013;
	ALBEDO += signal*vec3(0.026,0.23,0.30);
}
"""
	var floor_material := ShaderMaterial.new()
	floor_material.shader = floor_shader
	var deck := PlaneMesh.new()
	deck.size = Vector2(26,10)
	_mesh(deck,floor_material,self,Vector3(0,-1.82,-6.7))
	var rail_material := _material(IRON,0.82)
	var copper := _material(Color("442734"),0.9)
	var cold := _material(Color("487c91"),0.0,0.85)
	var red := _material(Color("a4273e"),0.0,0.9)
	for index in range(6):
		var x := -0.4+float(index)*1.9
		var z := -10.9-float(index%2)*0.26
		var beam := _box(Vector3(0.13,7.0,0.12),rail_material,Vector3(x,0.2,z))
		beam.rotation.z = -0.30
		_box(Vector3(0.24,0.045,0.10),cold,Vector3(x+0.77,1.9,z+0.11))
		_box(Vector3(0.43,0.06,0.12),copper,Vector3(x-0.41,-1.34,z+0.15))
	for index in range(8):
		_box(Vector3(0.34,0.036,0.045),red,Vector3(0.7+float(index)*0.71,2.38,-10.6))
	for index in range(6):
		var z := -4.5-float(index)*0.83
		_box(Vector3(0.56,0.013,0.028),cold,Vector3(5.9,-1.81,z))
	_omni(Vector3(1.9,3.0,-2.8),Color("a9dfff"),3.0,12.0)
	_omni(Vector3(5.1,2.3,-7.0),Color("ff3d57"),4.7,8.0)
	_omni(Vector3(3.0,-1.0,-3.8),Color("6bd0e0"),0.95,7.0)


func _build_portrait_camera() -> void:
	_portrait_view = SubViewport.new()
	_portrait_view.name = "MonsterPortraits"
	_portrait_view.own_world_3d = true
	_portrait_view.transparent_bg = true
	_portrait_view.msaa_3d = Viewport.MSAA_4X
	_portrait_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_portrait_view)
	_motion = Node3D.new()
	_portrait_view.add_child(_motion)
	_portrait_camera = Camera3D.new()
	_portrait_camera.near = 0.025
	_portrait_camera.far = 110.0
	_portrait_camera.cull_mask = PORTRAIT_LAYER
	_portrait_view.add_child(_portrait_camera)
	_portrait_camera.make_current()
	var lighting := Environment.new()
	var studio := ProceduralSkyMaterial.new()
	studio.sky_top_color = Color("405976")
	studio.sky_horizon_color = Color("a0abb9")
	studio.ground_horizon_color = Color("675864")
	studio.ground_bottom_color = Color("292631")
	var reflections := Sky.new()
	reflections.sky_material = studio
	lighting.sky = reflections
	lighting.background_mode = Environment.BG_CLEAR_COLOR
	lighting.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	lighting.ambient_light_color = Color("b2bbcb")
	lighting.ambient_light_energy = 1.20
	lighting.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_portrait_camera.environment = lighting
	_portrait_key(Vector3(-27,-27,0),Color("d9efff"),1.60)
	_portrait_key(Vector3(-8,145,-14),Color("ff7784"),1.45)
	_portrait_key(Vector3(20,41,0),Color("8eaff0"),0.70)
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	_portrait_image = TextureRect.new()
	_portrait_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_image.stretch_mode = TextureRect.STRETCH_SCALE
	_portrait_image.texture = _portrait_view.get_texture()
	layer.add_child(_portrait_image)
	_portrait_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait_image.hide()
	get_viewport().size_changed.connect(_resize_portrait)
	_resize_portrait()


func _resize_portrait() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var render_scale := minf(1.0,1280.0/maxf(1.0,viewport_size.x))
	_portrait_view.size = Vector2i((viewport_size*render_scale).max(Vector2(2.0,2.0)))
	if intro_started: _pose(_showcase_age)


func _portrait_key(angles: Vector3, tint: Color, energy: float) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = angles
	light.light_color = tint
	light.light_energy = energy
	light.light_cull_mask = PORTRAIT_LAYER
	_portrait_view.add_child(light)


func _model_bounds(actor: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	var to_actor := actor.global_transform.affine_inverse()
	for node in actor.find_children("*","MeshInstance3D",true,false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
		var sample := to_actor*mesh.global_transform*mesh.get_aabb()
		bounds = sample if first else bounds.merge(sample)
		first = false
	return bounds if not first else AABB(Vector3(-1.0,0.0,-1.0),Vector3(2.0,2.0,2.0))


func _pose(age: float) -> void:
	if _actors.is_empty(): return
	var time := fposmod(age,SHOT_SECONDS*float(_actors.size()))
	var index := int(time/SHOT_SECONDS)
	var shot_time := fposmod(time,SHOT_SECONDS)
	if index != _shot_index:
		if _shot_index >= 0: _actors[_shot_index].hide()
		_shot_index = index
		_actors[index].show()
	var coverage := smoothstep(0.0,SHOT_COVER,shot_time)*(1.0-smoothstep(SHOT_SECONDS-SHOT_COVER,SHOT_SECONDS,shot_time))
	_portrait_image.modulate.a = coverage
	var shot: Dictionary = PORTRAITS[index]
	var bounds := _portrait_bounds[index]
	var travel := smoothstep(0.08,SHOT_SECONDS-SHOT_COVER,shot_time)
	var approach := smoothstep(0.36,SHOT_SECONDS-0.68,shot_time)
	var yaw := float(shot.yaw)+lerpf(-0.20,0.23,travel)
	var elevation := float(shot.elevation)+lerpf(0.09,-0.045,travel)
	var radius := maxf(0.25,bounds.size.length()*0.5)
	var focus := bounds.get_center()+Vector3(shot.detail)*radius*approach
	_portrait_camera.fov = lerpf(48.0,34.0,approach)
	var half_lens := deg_to_rad(_portrait_camera.fov*0.5)
	var frame_radius := maxf(bounds.size.y*0.50,bounds.size.x*0.31)
	var distance := radius*0.52+frame_radius/tan(deg_to_rad(24.0))*lerpf(1.36,1.05,approach)
	var orbit := Vector3(sin(yaw)*cos(elevation),sin(elevation),cos(yaw)*cos(elevation))
	_portrait_camera.position = focus+orbit*distance
	_portrait_camera.look_at(focus,Vector3.UP)
	# Off-axis framing leaves the left controls clear while the real lens pushes in.
	var half_height := distance*tan(half_lens)
	var aspect := float(_portrait_view.size.x)/maxf(1.0,float(_portrait_view.size.y))
	_portrait_camera.h_offset = (0.5-PORTRAIT_ANCHOR.x)*2.0*half_height*aspect
	_portrait_camera.v_offset = (PORTRAIT_ANCHOR.y-0.5)*2.0*half_height


func _mesh(geometry: Mesh, material: Material, parent: Node3D, point: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = geometry
	node.material_override = material
	node.layers = TITLE_LAYER
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position = point
	parent.add_child(node)
	return node


func _box(size: Vector3, material: Material, point: Vector3) -> MeshInstance3D:
	var geometry := BoxMesh.new()
	geometry.size = size
	return _mesh(geometry,material,self,point)


func _material(tint: Color, metal: float, emission: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.metallic = metal
	material.roughness = 0.57
	material.disable_fog = true
	material.emission_enabled = emission > 0.0
	material.emission = tint
	material.emission_energy_multiplier = emission
	return material


func _omni(point: Vector3, tint: Color, energy: float, radius: float) -> OmniLight3D:
	var node := OmniLight3D.new()
	node.position = point
	node.light_color = tint
	node.light_energy = energy
	node.omni_range = radius*STAGE_SCALE
	node.light_cull_mask = TITLE_LAYER
	add_child(node)
	return node


func _set_layer(node: Node, render_layer: int) -> void:
	if node is GeometryInstance3D:
		node.layers = render_layer
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children(): _set_layer(child,render_layer)
