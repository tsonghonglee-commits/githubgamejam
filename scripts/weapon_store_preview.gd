extends SubViewport
## The shop lights a copy of the equipment built by the first-person view.

const ViewModel = preload("res://scripts/katana_view.gd")
const PREVIEW_SIZE := Vector2i(960,236)

var selected_skin := ""
var _camera: Camera3D
var _model: Node3D
var _turntable: Node3D
var _equipment: Node3D
var _age := 0.0


func _ready() -> void:
	size = PREVIEW_SIZE
	own_world_3d = true
	transparent_bg = true
	msaa_3d = Viewport.MSAA_4X
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.position.z = 5.0
	_camera.near = 0.03
	_camera.far = 16.0
	add_child(_camera)
	_camera.make_current()
	var lighting := Environment.new()
	var reflections := Sky.new()
	var studio := ProceduralSkyMaterial.new()
	studio.sky_top_color = Color("74889e")
	studio.sky_horizon_color = Color("b6c5d8")
	studio.ground_horizon_color = Color("665844")
	studio.ground_bottom_color = Color("252331")
	reflections.sky_material = studio
	lighting.sky = reflections
	lighting.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	lighting.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	lighting.ambient_light_color = Color("cad4e3")
	lighting.ambient_light_energy = 1.15
	_camera.environment = lighting
	_add_light(Vector3(-28,-31,0),Color("e8f4ff"),1.75)
	_add_light(Vector3(24,32,30),Color("ffd5b2"),0.85)
	_add_light(Vector3(-13,155,-12),Color("92bdff"),1.30)
	_turntable = Node3D.new()
	add_child(_turntable)
	_model = ViewModel.new()
	_camera.add_child(_model)
	_model.hide()
	_model.set_process(false)


func _add_light(angles: Vector3, tint: Color, energy: float) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = angles
	light.light_color = tint
	light.light_energy = energy
	add_child(light)


func advance(finish: Dictionary, delta: float) -> void:
	if finish.is_empty():
		render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if selected_skin != str(finish.skin_id):
		_replace_equipment(finish)
	_age += delta
	_turntable.rotation = Vector3(0.24+0.10*sin(_age*1.1),0.30*sin(_age*0.83),-0.08)
	render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE


func _replace_equipment(finish: Dictionary) -> void:
	selected_skin = str(finish.skin_id)
	if is_instance_valid(_equipment): _equipment.free()
	_equipment = Node3D.new()
	_turntable.add_child(_equipment)
	_model.set_weapon_finish(finish)
	_model.populate_shop_preview(_equipment)
	_age = 0.0

	var bounds := AABB()
	var empty := true
	var inverse := _equipment.global_transform.affine_inverse()
	for node in _equipment.find_children("*","MeshInstance3D",true,false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
		var sample := inverse*mesh.global_transform*mesh.get_aabb()
		bounds = sample if empty else bounds.merge(sample)
		empty = false
	if empty: return
	_equipment.position = -bounds.get_center()
	var aspect := float(PREVIEW_SIZE.x)/float(PREVIEW_SIZE.y)
	var visible_height := bounds.size.x*0.092+bounds.size.y+bounds.size.z*0.26
	_camera.size = maxf(0.36,maxf(visible_height,bounds.size.x/aspect)*1.12)
