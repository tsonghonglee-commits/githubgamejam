class_name SeriesScenery
extends Node3D
## Each district has its own spatial rhythm. All geometry/materials are
## prepared before play. A transition crosses a physical open bridge between
## two visible districts, rather than exchanging nearby tiles under fog.

const TILE_LENGTH := 10.0
const LAYOUT_COUNT := 24
const APPROACH_METERS := 132.0
const TRANSITION_DISTANCE := 224.0
const CROSSING_HALF_SPAN := 32.0
const DISTRICT_EDGE := 29.0
const INDUSTRIAL_EXIT_EDGE := 47.0
const TRANSITION_SECONDS := 0.0 # Compatibility label; transitions use meters.
const THEMES := [2,3,4,5]
const ORBITAL_STEEL := Color("777280")
const ORBITAL_ARMOR := Color("474457")
const ORBITAL_FRAME := Color("2b2939")
const ORBITAL_INSET := Color("1c1b28")
const ORBITAL_BRASS := Color("b68b4a")
const ORBITAL_AMBER := Color(0.97,0.68,0.36,0.76)
const ORBITAL_VIOLET := Color(0.60,0.40,0.85,0.81)
var _game: Node3D
var _tiles: Array[Node3D] = []
var _visuals: Array[MeshInstance3D] = []
var _incoming: Array[MeshInstance3D] = []
var _waters: Array[MeshInstance3D] = []
var _incoming_waters: Array[MeshInstance3D] = []
var _old_tile_visuals: Array[Array] = []
var _old_decks: Array[Material] = []
var _legacy: Array[GeometryInstance3D] = []
var _legacy_visibility: Array[bool] = []
var _legacy_materials: Array[Dictionary] = []
var _legacy_clip_materials: Array[ShaderMaterial] = []
var _clip_cache: Dictionary = {}
var _meshes: Dictionary = {}
var _decks: Dictionary = {}
var _surface: ShaderMaterial
var _city_surface: ShaderMaterial
var _arrival_surface: ShaderMaterial
var _transition_deck: ShaderMaterial
var _industrial_transition_deck: ShaderMaterial
var _landmark_material: ShaderMaterial
var _water_material: ShaderMaterial
var _arrival_water: ShaderMaterial
var _sky_material: ShaderMaterial
var _water_mesh: ArrayMesh
var _environment: Environment
var _original_environment: Dictionary = {}
var _legacy_backdrop: Node3D
var _forge_lamps: Array = []
var _sunlights: Array[DirectionalLight3D] = []
var _sun_colors: Array[Color] = []
var _sun_energy: Array[float] = []
var _corridor: MeshInstance3D
var _standard_crossing: ArrayMesh
var _industrial_exits: Dictionary = {}
var _shore_join: MeshInstance3D
var _landmarks: Dictionary = {}
var _incoming_landmarks: Dictionary = {}
var _horizon: MeshInstance3D
var _current := 1
var _target := 1
var _stage := 0
var _age := 0.0
var _distance := 0.0
var _start_distance := 0.0
var _world_time := 0.0
var _gpu_warmed := false
var _boundary := -10000.0
var _transition_blend := 0.0
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()

func configure(game: Node3D, road_segments: Array) -> void:
	_game = game
	_legacy_backdrop = game.get_node_or_null("IndustrialBackdrop") as Node3D
	_forge_lamps = game.get("forge_lights")
	for child in game.get_children():
		if child is GeometryInstance3D:
			_legacy.append(child)
			_legacy_visibility.append(child.visible)
		if child is WorldEnvironment: _environment = child.environment
		if child is DirectionalLight3D:
			_sunlights.append(child)
			_sun_colors.append(child.light_color)
			_sun_energy.append(child.light_energy)
	if _environment != null:
		_original_environment = {"fog":_environment.fog_light_color,"density":_environment.fog_density,"ambient":_environment.ambient_light_color,"energy":_environment.ambient_light_energy,"sky":_environment.sky.sky_material if _environment.sky else null,"fog_sky":_environment.fog_sky_affect}
	_build_materials()
	for theme: int in THEMES:
		var layouts: Array[ArrayMesh] = []
		for layout in range(LAYOUT_COUNT): layouts.append(_build_theme(theme,layout))
		_meshes[theme] = layouts
	for segment: Node3D in road_segments:
		_tiles.append(segment)
		segment.set_meta("scenery_series_id",1)
		var old: Array[GeometryInstance3D] = []
		for child in segment.get_children():
			if child is GeometryInstance3D and child.name != "DeckReceiver": old.append(child)
		_old_tile_visuals.append(old)
		var deck := segment.get_node_or_null("DeckReceiver") as MeshInstance3D
		_old_decks.append(deck.material_override if deck else null)
		_visuals.append(_instance(segment,"DistrictGeometry",null,_surface))
		_incoming.append(_instance(segment,"NextDistrictGeometry",null,_arrival_surface))
		_waters.append(_instance(segment,"DistrictSea",_water_mesh,_water_material))
		_incoming_waters.append(_instance(segment,"NextDistrictSea",_water_mesh,_arrival_water))
	_build_industrial_transition_deck()
	for item: GeometryInstance3D in _legacy: _prepare_legacy_clips(item)
	if _legacy_backdrop: _prepare_legacy_clips(_legacy_backdrop)
	_build_crossing()
	_build_landmarks()
	force_series(1)

func _instance(parent: Node3D, title: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = title
	visual.mesh = mesh
	visual.material_override = material
	visual.visible = false
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if mesh == _water_mesh and mesh != null:
		visual.custom_aabb = AABB(Vector3(-322,-12,-12),Vector3(644,21,14))
	parent.add_child(visual)
	return visual

func begin_transition(series_id: int) -> void:
	if series_id < 1 or series_id > 5 or series_id == _current or _stage != 0: return
	_target = series_id
	_stage = 1
	_age = 0.0
	_start_distance = _distance
	_boundary = -APPROACH_METERS
	_transition_blend = 0.0
	_corridor.mesh = _industrial_exits.get(_target,_standard_crossing) if _current == 1 else _standard_crossing
	_corridor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _current == 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_corridor.position.z = _boundary
	_corridor.visible = true
	_shore_join.visible = _current == 4 or _target == 4
	_shore_join.rotation.y = PI if _current == 4 else 0.0
	_transition_deck.set_shader_parameter("district_theme",_current)
	_transition_deck.set_shader_parameter("destination_theme",_target)
	_industrial_transition_deck.set_shader_parameter("district_theme",1)
	_industrial_transition_deck.set_shader_parameter("destination_theme",_target)
	for index in range(_tiles.size()): _set_arrival(index,_target)
	if _current == 1:
		for item: Dictionary in _legacy_materials: item.node.material_override = item.clipped
	_update_clip_planes()
	_update_district_edges()
	_set_landmarks()
	_set_atmosphere(0.0)

func force_series(series_id: int) -> void:
	if series_id < 1 or series_id > 5: return
	_current = series_id
	_target = series_id
	_stage = 0
	_age = 0.0
	_boundary = -10000.0
	_transition_blend = 0.0
	for item: Dictionary in _legacy_materials: item.node.material_override = item.original
	for index in range(_tiles.size()):
		_assign_tile(index,series_id)
		_incoming[index].visible = false
		_incoming_waters[index].visible = false
	if _corridor: _corridor.visible = false
	if _shore_join: _shore_join.visible = false
	_set_legacy(series_id == 1)
	_update_clip_planes()
	_set_landmarks()
	_set_atmosphere(0.0)

func update(sim_dt: float, run_distance: float) -> void:
	if sim_dt <= 0.0: return
	_distance = run_distance
	_world_time += sim_dt
	_water_material.set_shader_parameter("route_time",_world_time)
	_arrival_water.set_shader_parameter("route_time",_world_time)
	_sky_material.set_shader_parameter("world_time",_world_time)
	_water_material.set_shader_parameter("run_distance",run_distance)
	_arrival_water.set_shader_parameter("run_distance",run_distance)
	for material: ShaderMaterial in _decks.values(): material.set_shader_parameter("run_distance",run_distance)
	_transition_deck.set_shader_parameter("run_distance",run_distance)
	_industrial_transition_deck.set_shader_parameter("run_distance",run_distance)
	_city_surface.set_shader_parameter("run_distance",run_distance)
	_set_legacy(_current == 1)
	if _stage == 0: return
	_age += sim_dt
	var meters := maxf(0.0,run_distance-_start_distance)
	_boundary = -APPROACH_METERS+meters
	_corridor.position.z = _boundary
	_update_clip_planes()
	_update_district_edges()
	_transition_blend = smoothstep(APPROACH_METERS-63.0,APPROACH_METERS+48.0,meters)
	_set_atmosphere(_transition_blend)
	for theme: int in _landmarks:
		# The offshore rigs are already beyond the edge of the causeway.
		# Carry them past the flank before the dry district fills the view.
		var shoreline_parallax := 1.56 if theme==4 else 1.0
		_landmarks[theme].position.z = meters*shoreline_parallax*smoothstep(0.0,38.0,meters)
		if theme == 3 and _target == 4:
			_landmarks[theme].position.z += 92.0*smoothstep(14.0,110.0,meters)
		_incoming_landmarks[theme].position.z = -134.0*(1.0-smoothstep(0.0,TRANSITION_DISTANCE-18.0,meters))
	if meters >= TRANSITION_DISTANCE: force_series(_target)

func is_transitioning() -> bool: return _stage != 0
func transition_ready() -> bool: return _stage == 0
func get_current_series() -> int: return _current

func warm_for_menu() -> void:
	if _gpu_warmed or DisplayServer.get_name()=="headless" or _tiles.is_empty(): return
	# Main owns the opaque loading cover. Submit each prepared layout and
	# water/sky/clip variant here, before the first playable frame.
	var index := 0
	var nearest := INF
	for candidate in range(_tiles.size()):
		var distance := absf(_tiles[candidate].position.z+18.0)
		if distance<nearest: nearest=distance;index=candidate
	for theme: int in THEMES:
		force_series(theme)
		for layout in range(LAYOUT_COUNT):
			_visuals[index].mesh = _meshes[theme][layout]
			await RenderingServer.frame_post_draw
	for destination in [2,3,4]:
		force_series(1)
		begin_transition(destination)
		await RenderingServer.frame_post_draw
	force_series(1)
	_gpu_warmed=true

func _assign_tile(index: int, theme: int) -> void:
	var tile := _tiles[index]
	tile.set_meta("scenery_series_id",theme)
	for old: GeometryInstance3D in _old_tile_visuals[index]: old.visible = theme == 1
	for old: Node3D in tile.get_meta("section_roots",[]): old.visible = theme == 1 and int(old.get_meta("route_chapter",0)) == int(tile.get_meta("route_section",0))
	_visuals[index].visible = theme != 1
	_visuals[index].material_override = _city_surface if theme == 3 else _surface
	_visuals[index].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if theme in [2,3] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_waters[index].visible = theme == 4
	if theme != 1: _visuals[index].mesh = _meshes[theme][posmod(int(tile.get_meta("layout_index",index)),LAYOUT_COUNT)]
	var deck := tile.get_node_or_null("DeckReceiver") as MeshInstance3D
	if deck: deck.material_override = _old_decks[index] if theme == 1 else _decks[theme]

func _set_arrival(index: int, theme: int) -> void:
	if theme == 1: return
	_incoming[index].mesh = _meshes[theme][posmod(int(_tiles[index].get_meta("layout_index",index)),LAYOUT_COUNT)]
	_incoming[index].material_override = _city_surface if theme == 3 else _arrival_surface
	_incoming[index].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if theme in [2,3] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_incoming_waters[index].visible = theme == 4
	var deck := _tiles[index].get_node_or_null("DeckReceiver") as MeshInstance3D
	if deck: deck.material_override = _industrial_transition_deck if _current == 1 else _transition_deck

func _update_district_edges() -> void:
	# These bounds move with the course. An assembled structure keeps the same
	# side of the crossing until its tile wraps behind the player's view.
	for index in range(_tiles.size()):
		var z := _tiles[index].position.z-5.0
		_visuals[index].visible = _current != 1 and z >= _boundary+DISTRICT_EDGE
		_incoming[index].visible = z <= _boundary-DISTRICT_EDGE
		if _current == 1:
			var keep := z >= _boundary+INDUSTRIAL_EXIT_EDGE
			for old: GeometryInstance3D in _old_tile_visuals[index]: old.visible = keep
			for old: Node3D in _tiles[index].get_meta("section_roots",[]):
				old.visible = keep and int(old.get_meta("route_chapter",0)) == int(_tiles[index].get_meta("route_section",0))

func _set_legacy(enabled: bool) -> void:
	for index in range(_legacy.size()): _legacy[index].visible = enabled and _legacy_visibility[index]
	if _legacy_backdrop: _legacy_backdrop.visible = enabled
	if not enabled:
		for light in _forge_lamps: light.visible = false

func _prepare_legacy_clips(root_node: Node) -> void:
	if root_node is GeometryInstance3D:
		var original: Material = root_node.material_override
		var source: Material = original
		if source == null:
			if root_node is MeshInstance3D and root_node.mesh != null: source = root_node.mesh.surface_get_material(0)
			elif root_node is MultiMeshInstance3D and root_node.multimesh != null and root_node.multimesh.mesh != null: source = root_node.multimesh.mesh.surface_get_material(0)
		var id: int = source.get_instance_id() if source else 0
		if not _clip_cache.has(id):
			var clipped := ShaderMaterial.new()
			var shader := Shader.new()
			if source is ShaderMaterial:
				clipped = source.duplicate()
				var code: String = source.shader.code
				code = code.replace("shader_type spatial;","shader_type spatial;\nuniform float series_boundary = -10000.0;\nvarying float series_world_z;\n")
				if code.contains("void vertex() {"): code = code.replace("void vertex() {","void vertex() {\nseries_world_z = (MODEL_MATRIX*vec4(VERTEX,1.0)).z;\n")
				else: code += "\nvoid vertex() { series_world_z=(MODEL_MATRIX*vec4(VERTEX,1.0)).z; }\n"
				code = code.replace("void fragment() {","void fragment() {\nif (series_world_z < series_boundary+46.0) discard;\n")
				shader.code = code
			else:
				var unshaded: bool = source is BaseMaterial3D and source.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
				var render_mode := "render_mode unshaded;" if unshaded else ""
				shader.code = "shader_type spatial; "+render_mode+" uniform float series_boundary=-10000.0; uniform vec4 tint:source_color=vec4(1.0); uniform float roughness_value=0.75; uniform float metal_value=0.25; uniform float specular_value=0.5; uniform bool vertex_tint=false; varying float z; void vertex(){z=(MODEL_MATRIX*vec4(VERTEX,1.0)).z;} void fragment(){if(z<series_boundary+46.0)discard; ALBEDO=tint.rgb*(vertex_tint ? COLOR.rgb : vec3(1.0)); ROUGHNESS=roughness_value; METALLIC=metal_value; SPECULAR=specular_value;}"
				clipped.shader = shader
				if source is BaseMaterial3D:
					clipped.set_shader_parameter("tint",source.albedo_color)
					clipped.set_shader_parameter("roughness_value",source.roughness)
					clipped.set_shader_parameter("metal_value",source.metallic)
					clipped.set_shader_parameter("specular_value",source.metallic_specular)
					clipped.set_shader_parameter("vertex_tint",source.vertex_color_use_as_albedo)
			clipped.shader = shader
			_clip_cache[id] = clipped
			_legacy_clip_materials.append(clipped)
		_legacy_materials.append({"node":root_node,"original":original,"clipped":_clip_cache[id]})
	for child in root_node.get_children(): _prepare_legacy_clips(child)

func _update_clip_planes() -> void:
	var active := _stage != 0
	_surface.set_shader_parameter("clip_mode",0)
	_surface.set_shader_parameter("boundary_z",_boundary)
	_arrival_surface.set_shader_parameter("boundary_z",_boundary)
	_water_material.set_shader_parameter("clip_mode",1 if active else 0)
	_water_material.set_shader_parameter("boundary_z",_boundary)
	_arrival_water.set_shader_parameter("boundary_z",_boundary)
	_transition_deck.set_shader_parameter("boundary_z",_boundary)
	_industrial_transition_deck.set_shader_parameter("boundary_z",_boundary)
	for material: ShaderMaterial in _legacy_clip_materials: material.set_shader_parameter("series_boundary",_boundary)

func _set_landmarks() -> void:
	for theme: int in _landmarks:
		_landmarks[theme].visible = theme == _current
		_landmarks[theme].position.z = 0.0
		_incoming_landmarks[theme].visible = _stage != 0 and theme == _target
		_incoming_landmarks[theme].position.z = -134.0

func _tone(theme: int) -> Dictionary:
	match theme:
		2: return {"fog":Color("aaaaaa"),"top":Color("828282"),"horizon":Color("dddddd"),"ambient":Color("bebebe"),"density":0.0027,"energy":0.55,"sun":Color("efefef"),"sun_energy":1.22}
		3: return {"fog":Color("293e52"),"top":Color("071322"),"horizon":Color("415e78"),"ambient":Color("a3b8ce"),"density":0.0026,"energy":0.62,"sun":Color("b5d4f2"),"sun_energy":1.14}
		4: return {"fog":Color("657c92"),"top":Color("355575"),"horizon":Color("a8bac8"),"ambient":Color("b7ccdc"),"density":0.0021,"energy":0.79,"sun":Color("e7e8df"),"sun_energy":1.07}
		5: return {"fog":Color("111321"),"top":Color("020410"),"horizon":Color("151b2c"),"ambient":Color("b1a7c4"),"density":0.0010,"energy":0.62,"sun":Color("e2d8f4"),"sun_energy":0.85}
	return {"fog":_original_environment.get("fog",Color("263b50")),"top":Color("101d35"),"horizon":Color("334c69"),"ambient":_original_environment.get("ambient",Color("9eabbc")),"density":_original_environment.get("density",0.0035),"energy":_original_environment.get("energy",0.4),"sun":Color.WHITE,"sun_energy":1.0}

func _set_atmosphere(blend: float) -> void:
	if _environment == null: return
	if (_current == 1 and blend <= 0.0) or (_target == 1 and blend >= 1.0):
		_environment.fog_light_color = _original_environment.fog
		_environment.fog_density = _original_environment.density
		_environment.ambient_light_color = _original_environment.ambient
		_environment.ambient_light_energy = _original_environment.energy
		_environment.fog_sky_affect = _original_environment.fog_sky
		if _environment.sky: _environment.sky.sky_material = _original_environment.sky
		for index in range(_sunlights.size()):
			_sunlights[index].light_color = _sun_colors[index]
			_sunlights[index].light_energy = _sun_energy[index]
		return
	var from := _tone(_current)
	var to := _tone(_target)
	_environment.fog_light_color = Color(from.fog).lerp(to.fog,blend)
	_environment.fog_density = lerpf(from.density,to.density,blend)
	_environment.ambient_light_color = Color(from.ambient).lerp(to.ambient,blend)
	_environment.ambient_light_energy = lerpf(from.energy,to.energy,blend)
	var original_sky_fog: float = _original_environment.fog_sky
	_environment.fog_sky_affect = lerpf(original_sky_fog if _current == 1 else 0.08,original_sky_fog if _target == 1 else 0.08,blend)
	for index in range(_sunlights.size()):
		var from_color: Color = _sun_colors[index] if _current == 1 else from.sun
		var to_color: Color = _sun_colors[index] if _target == 1 else to.sun
		var from_energy: float = _sun_energy[index] if _current == 1 else float(from.sun_energy)*(1.0 if index == 0 else 0.16)
		var to_energy: float = _sun_energy[index] if _target == 1 else float(to.sun_energy)*(1.0 if index == 0 else 0.16)
		_sunlights[index].light_color = from_color.lerp(to_color,blend)
		_sunlights[index].light_energy = lerpf(from_energy,to_energy,blend)
	if _environment.sky: _environment.sky.sky_material = _sky_material
	# Mix the two complete skies. The foundry's horizon and sky response use
	# the original material at the endpoint and its gradient inside the mix.
	var from_sky := _target if _current == 1 else _current
	var to_sky := _current if _target == 1 else _target
	var from_palette: Dictionary = to if _current == 1 else from
	var to_palette: Dictionary = from if _target == 1 else to
	_sky_material.set_shader_parameter("foundry_sky",1.0-blend if _current == 1 else (blend if _target == 1 else 0.0))
	_sky_material.set_shader_parameter("top_color",Color(from_palette.top).lerp(to_palette.top,blend))
	_sky_material.set_shader_parameter("horizon_color",Color(from_palette.horizon).lerp(to_palette.horizon,blend))
	_sky_material.set_shader_parameter("stars",lerpf(1.0 if from_sky == 5 else 0.0,1.0 if to_sky == 5 else 0.0,blend))
	_sky_material.set_shader_parameter("storm",lerpf(1.0 if from_sky == 4 else 0.0,1.0 if to_sky == 4 else 0.0,blend))
	_sky_material.set_shader_parameter("ink_clouds",lerpf(1.0 if from_sky == 2 else 0.0,1.0 if to_sky == 2 else 0.0,blend))
	_sky_material.set_shader_parameter("city_clouds",lerpf(1.0 if from_sky == 3 else 0.0,1.0 if to_sky == 3 else 0.0,blend))

func _build_materials() -> void:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode diffuse_burley;
uniform int clip_mode=0;
uniform float boundary_z=-10000.0;
uniform float run_distance=0.0;
uniform bool city_material=false;
varying vec3 world;
varying vec3 local_surface;
float detail_hash(vec2 p){return fract(sin(dot(p,vec2(73.3,129.7)))*3719.83);}
float detail_noise(vec2 p){
 vec2 i=floor(p);
 vec2 f=fract(p);
 f=f*f*(3.0-2.0*f);
 return mix(mix(detail_hash(i),detail_hash(i+vec2(1.0,0.0)),f.x),mix(detail_hash(i+vec2(0.0,1.0)),detail_hash(i+vec2(1.0,1.0)),f.x),f.y);
}
void vertex(){
 local_surface=VERTEX;
 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment(){
 if(clip_mode==1 && world.z<boundary_z+22.0)discard;
 if(clip_mode==-1 && world.z>boundary_z-22.0)discard;
 float grain=fract(sin(dot(floor(world.xz*45.0+world.y*17.0),vec2(73.3,129.7)))*3719.83);
 ALBEDO=COLOR.rgb*(0.965+grain*0.055);
 ROUGHNESS=0.77; METALLIC=0.22;
 EMISSION=COLOR.rgb*(0.045+max(0.0,1.0-COLOR.a)*5.2);
 if(COLOR.a>0.991 && COLOR.a<0.998){
  float top=abs((INV_VIEW_MATRIX*vec4(NORMAL,0.0)).y);
  vec2 steel=mix(vec2(local_surface.x+local_surface.z*0.79,local_surface.y+local_surface.z*0.22),local_surface.xz*0.62,smoothstep(0.65,0.9,top));
  float fine=1.0-smoothstep(0.019,0.074,length(fwidth(steel)));
  float patina=detail_noise(steel*vec2(2.4,0.46))*0.69+mix(0.5,detail_noise(steel*vec2(17.1,3.2)),fine)*0.31;
  float oxide=smoothstep(0.65,0.82,patina);
  float scrapes=smoothstep(0.90,0.96,detail_noise(steel*vec2(85.0,0.90)))*0.23*fine;
  ALBEDO=mix(COLOR.rgb*(0.85+patina*0.27+mix(0.5,grain,fine)*0.09),vec3(0.19,0.090,0.055),oxide*0.47);
  ALBEDO+=vec3(0.085,0.090,0.093)*scrapes;
  ROUGHNESS=0.58+oxide*0.30;
  METALLIC=0.30;
  EMISSION=COLOR.rgb*0.018;
 }
 if(city_material){
  vec3 street=world-vec3(0.0,0.0,run_distance);
  float lane_x=abs(street.x);
  float lamp_z=abs(mod(street.z-0.45,2.0)-1.0);
  vec3 rail_light=vec3((lane_x-5.35)*0.82,(street.y-0.07)*1.24,lamp_z*1.85);
  vec3 gallery_light=vec3((lane_x-9.4)*0.37,(street.y-1.3)*0.28,(mod(street.z+1.0,4.0)-2.0)*0.82);
  float grime=detail_noise(vec2(local_surface.x+local_surface.y*0.41,local_surface.z)*vec2(0.81,1.75));
  ALBEDO*=0.93+grime*0.13;
  ROUGHNESS=0.66+grime*0.13;
  EMISSION+=ALBEDO*(vec3(0.87,0.37,0.09)*exp(-dot(rail_light,rail_light))*0.64+vec3(0.72,0.39,0.16)*exp(-dot(gallery_light,gallery_light))*0.52);
 }
}
"""
	_surface = ShaderMaterial.new()
	_surface.shader = shader
	_city_surface = _surface.duplicate()
	_city_surface.set_shader_parameter("city_material",true)
	_arrival_surface = _surface.duplicate()
	_landmark_material = _surface.duplicate()
	_landmark_material.set_shader_parameter("clip_mode",0)
	var sky_shader := Shader.new()
	sky_shader.code = """shader_type sky;
render_mode use_debanding;
uniform vec4 top_color:source_color=vec4(0.03,0.05,0.08,1.0);
uniform vec4 horizon_color:source_color=vec4(0.15,0.2,0.25,1.0);
uniform vec4 foundry_top:source_color=vec4(0.063,0.114,0.208,1.0);
uniform vec4 foundry_horizon:source_color=vec4(0.20,0.298,0.412,1.0);
uniform vec4 foundry_ground:source_color=vec4(0.063,0.082,0.110,1.0);
uniform vec4 foundry_ground_horizon:source_color=vec4(0.149,0.224,0.282,1.0);
uniform float foundry_sky=0.0;
uniform float foundry_sky_power=2.608696;
uniform float foundry_ground_power=30.0;
uniform float foundry_exposure=1.0;
uniform float stars=0.0;
uniform float storm=0.0;
uniform float ink_clouds=0.0;
uniform float city_clouds=0.0;
uniform float world_time=0.0;
float h(vec2 v){return fract(sin(dot(v,vec2(127.1,311.7)))*43758.5453);}
float n(vec2 v){vec2 i=floor(v);vec2 f=fract(v);f=f*f*(3.0-2.0*f);return mix(mix(h(i),h(i+vec2(1,0)),f.x),mix(h(i+vec2(0,1)),h(i+vec2(1,1)),f.x),f.y);}
float storm_billow(vec2 p){
 vec2 q=p+vec2(n(p*0.66+1.7),n(p*0.62+6.1))*1.25;
 return n(q)*0.51+n(q*2.05)*0.26+n(q*4.1)*0.13+n(q*8.21)*0.07+n(q*16.47)*0.03;
}
vec4 marine_hash(vec4 v){
 vec4 r=fract(v*0.1031);
 r*=r+33.33;
 r*=r+r;
 return fract(r);
}
float marine_noise(vec3 v){
 vec3 i=floor(v);
 vec3 f=fract(v);
 f=f*f*(3.0-2.0*f);
 float cell=dot(i,vec3(1.0,57.0,113.0));
 vec4 h0=marine_hash(cell+vec4(0.0,1.0,57.0,58.0));
 vec4 h1=marine_hash(cell+vec4(113.0,114.0,170.0,171.0));
 vec2 x0=mix(h0.xz,h0.yw,f.x);
 vec2 x1=mix(h1.xz,h1.yw,f.x);
 vec2 y=mix(x0,x1,f.z);
 return mix(y.x,y.y,f.y);
}
float marine_cloud(vec3 p){
 float body=marine_noise(p)*0.62+marine_noise(p*2.03+1.93)*0.25+marine_noise(p*4.17)*0.09+marine_noise(p*8.11)*0.04;
 return body;
}
vec3 marine_weather(vec3 clear,vec3 ray,float height){
 vec3 sun=normalize(vec3(-0.34,0.64,-0.68));
 float glow=pow(max(0.0,dot(sun,ray)),12.0);
 vec3 ambient=clear*0.82+glow*vec3(0.25,0.24,0.20);
 vec3 front=vec3(0.0);
 float transmission=1.0;
 float inclination=max(0.13,ray.y+0.047);
 for(int layer=0;layer<6;layer++){
  float stratum=(float(layer)+0.5)/6.0;
  float depth=(1.22+stratum*0.8)/inclination;
  vec3 p=vec3(ray.x*depth,3.8+stratum*1.54,ray.z*depth)+vec3(4.2+world_time*0.011,0.0,1.3+world_time*0.005);
  float body=marine_cloud(p);
  float volume=pow(sin(stratum*3.14159),0.74);
  float density=smoothstep(0.44,0.73,body)*volume;
  if(density>0.01){
   vec3 light_point=p+sun*0.38;
   float sunward=marine_noise(light_point)*0.64+marine_noise(light_point*2.03+1.93)*0.27+0.045;
   float light=clamp(0.27+(body-sunward)*3.7+glow*0.37,0.0,1.0);
   vec3 dark=vec3(0.043,0.077,0.132)+vec3(0.12,0.15,0.18)*(1.0-volume);
   vec3 bright=vec3(0.54,0.66,0.77)+glow*vec3(0.29,0.25,0.20);
   float cover=1.0-exp(-density*1.1/inclination);
   front+=transmission*cover*mix(dark,bright,light);
   transmission*=1.0-cover;
   if(transmission<0.04) break;
  }
 }
 vec3 storm_color=front+ambient*transmission;
 return mix(clear,storm_color,smoothstep(0.02,0.19,height));
}
void sky(){
 float height=clamp(EYEDIR.y,0.0,1.0);
 vec3 sky=mix(horizon_color.rgb,top_color.rgb,pow(height,0.48));
 vec2 cloud_uv=EYEDIR.xz/max(0.12,EYEDIR.y+0.16)*2.0+vec2(world_time*0.006,0.0);
 if(city_clouds>0.001){
  vec2 cloud_scale=vec2(cloud_uv.x*0.8+cloud_uv.y*0.36,cloud_uv.y*1.45);
  float low=n(cloud_scale)*0.60+n(cloud_scale*2.51)*0.26+n(cloud_scale*5.47)*0.14;
  sky=mix(sky,sky*0.53+vec3(0.015,0.028,0.043),city_clouds*smoothstep(0.35,0.75,low)*smoothstep(0.02,0.17,height)*0.64);
 }
 if(ink_clouds>0.001){
  vec2 wash=vec2(cloud_uv.x*0.40+cloud_uv.y*0.25,cloud_uv.y*2.3);
  float band=n(wash)*0.68+n(wash*3.4)*0.32;
  sky=mix(sky,vec3(0.72),ink_clouds*smoothstep(0.39,0.74,band)*smoothstep(0.01,0.12,height)*0.54);
 }
 if(storm>0.001) sky=mix(sky,marine_weather(sky,EYEDIR,height),storm);
 if(stars>0.001){
  vec2 suv=SKY_COORDS*vec2(1220,610);
  vec2 cell=floor(suv);
  float seed=h(cell);
  vec2 spot=fract(suv)-mix(vec2(0.14),vec2(0.86),vec2(h(cell+2.7),h(cell+6.4)));
  float star=(1.0-smoothstep(0.035,0.12+0.07*h(cell-2.9),length(spot)))*step(0.986,seed);
  sky+=mix(vec3(0.38,0.54,0.91),vec3(0.9,0.75,0.55),h(cell+14.5))*star*stars*(0.23+0.54*h(cell-1.8));
  // Ray intersection with a lit sphere gives a curved horizon and a
  // thin atmosphere independent of the camera's position on the runway.
  vec3 center=normalize(vec3(-0.54,-0.58,-0.61))*2.0;
  vec3 star_sun=normalize(vec3(-0.30,0.85,-0.44));
  float d=dot(EYEDIR,center);
  float q=dot(center,center)-d*d;
  float radius=1.17;
  if(d>0.0 && q<1.42){
   float air=exp(-max(0.0,sqrt(max(0.0,q))-radius)*130.0);
   sky+=vec3(0.067,0.18,0.33)*air*stars;
   if(q<radius*radius){
    vec3 normal=(EYEDIR*(d-sqrt(radius*radius-q))-center)/radius;
    float lit=smoothstep(-0.16,0.74,dot(normal,star_sun));
    vec2 surface=vec2(atan(normal.x,normal.z),asin(clamp(normal.y,-1.0,1.0)));
    vec2 weather=vec2(surface.x+surface.y*1.4,surface.y)*vec2(8.2,13.5);
    float fronts=storm_billow(weather+vec2(1.6,4.3));
    float cloud=smoothstep(0.40,0.69,fronts);
    float continent=smoothstep(0.51,0.66,n(surface*7.9+vec2(8.2,5.2))*0.67+n(surface*22.0)*0.33);
    vec3 water=mix(vec3(0.030,0.090,0.16),vec3(0.063,0.128,0.16),continent);
    vec3 face=mix(water,vec3(0.42,0.55,0.65),cloud*0.82)*lit;
    float limb=pow(1.0-max(0.0,dot(normal,-EYEDIR)),4.2);
    face+=vec3(0.095,0.24,0.48)*limb*(0.35+lit*0.65);
    sky=mix(sky,face,stars);
   }
  }
 }
 if(foundry_sky>0.0){
  float elevation=clamp(EYEDIR.y,-1.0,1.0);
  float edge_weight=pow(1.0-abs(elevation),elevation>=0.0?foundry_sky_power:foundry_ground_power);
  vec3 forge=elevation>=0.0?mix(foundry_top.rgb,foundry_horizon.rgb,edge_weight):mix(foundry_ground.rgb,foundry_ground_horizon.rgb,edge_weight);
  sky=mix(sky,forge*foundry_exposure,foundry_sky);
 }
 COLOR=sky;
}
"""
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = sky_shader
	var original_sky := _original_environment.get("sky") as ProceduralSkyMaterial
	if original_sky:
		_sky_material.set_shader_parameter("foundry_top",original_sky.sky_top_color*original_sky.sky_energy_multiplier)
		_sky_material.set_shader_parameter("foundry_horizon",original_sky.sky_horizon_color*original_sky.sky_energy_multiplier)
		_sky_material.set_shader_parameter("foundry_ground",original_sky.ground_bottom_color*original_sky.ground_energy_multiplier)
		_sky_material.set_shader_parameter("foundry_ground_horizon",original_sky.ground_horizon_color*original_sky.ground_energy_multiplier)
		# Godot 4.7.2 converts both curve controls to cosine-space exponents.
		_sky_material.set_shader_parameter("foundry_sky_power",0.6/maxf(0.001,original_sky.sky_curve))
		_sky_material.set_shader_parameter("foundry_ground_power",0.6/maxf(0.001,original_sky.ground_curve))
		_sky_material.set_shader_parameter("foundry_exposure",original_sky.energy_multiplier)
	var deck_shader := Shader.new()
	deck_shader.code = """shader_type spatial;
uniform int district_theme=2;
uniform int destination_theme=0;
uniform int clip_mode=0;
uniform float boundary_z=-10000.0;
uniform float run_distance=0.0;
varying vec3 world;
float h(vec2 v){return fract(sin(dot(v,vec2(127.1,311.7)))*43758.5453);}
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
vec3 deck(int theme, out vec3 emission){
 emission=vec3(0.0);
 float z=world.z-run_distance;
 float aa=max(fwidth(z),0.008);
 float period=theme==2?2.15:4.0;
 float row=floor(z/period);
 float local_z=mod(z,period);
 float offset=theme==2?mod(row,2.0)*1.15:0.0;
 float local_x=mod(world.x+offset,theme==2?2.3:1.25);
 float seam=1.0-smoothstep(0.012,0.02+aa,min(local_z,period-local_z));
 float cross_seam=1.0-smoothstep(0.01,0.018+max(fwidth(world.x),0.004),min(local_x,(theme==2?2.3:1.25)-local_x));
 vec2 cell=vec2(floor((world.x+offset)/(theme==2?2.3:1.25)),row);
 float panel=h(cell);
 float grain=h(floor(vec2(world.x,z)*60.0));
 vec3 base=theme==1?vec3(0.103,0.112,0.118):(theme==2?vec3(0.21):(theme==3?vec3(0.060,0.072,0.083):(theme==4?vec3(0.065,0.088,0.095):vec3(0.095,0.09,0.13))));
 base*=0.90+panel*0.18+grain*0.035;
 base*=1.0-max(seam,cross_seam)*0.56;
 float lane=1.0-smoothstep(0.014,0.025,abs(mod(world.x+1.0,2.0)-1.0));
 float edge=1.0-smoothstep(0.018,0.04,abs(abs(world.x)-4.75));
 vec3 paint=theme==2?vec3(0.24,0.028,0.022):(theme==5?vec3(0.38,0.28,0.12):vec3(0.08,0.27,0.31));
 float dash=theme==2?1.0:step(2.0,mod(z,8.0))*step(mod(z,8.0),6.5);
 base=mix(base,paint,max(edge,lane*dash)*0.72);
 // Rivets sit on panel corners; breaks in plates never become broad bands.
 vec2 bolt=vec2(local_x-0.09,local_z-0.13);
 float rivet=1.0-smoothstep(0.014,0.026,length(bolt));
 if(theme!=2)base=mix(base,vec3(0.18,0.20,0.21),rivet*0.6);
 if(theme==4){
  float shoulder=smoothstep(4.55,4.62,abs(world.x));
  float track=sin(world.x*8.5+sin(z*0.77)*0.33)*0.5+0.5;
  float wet=smoothstep(0.46,0.91,h(vec2(floor(z*0.51),floor(world.x*1.81)))*0.55+track*0.45);
  float grooves=(1.0-smoothstep(0.012,0.02+aa,abs(mod(z+0.07,0.48)-0.24)));
  vec3 grip=vec3(0.13,0.080,0.050)*(0.84+grain*0.16)*(1.0-grooves*0.55);
  base=mix(base*(1.0-wet*0.15),grip,shoulder*(1.0-edge));
  float marker=1.0-smoothstep(0.13,0.22,abs(mod(z+1.5,8.0)-4.0));
  float studs=1.0-smoothstep(0.18,0.24,abs(mod(world.x+1.0,2.0)-1.0));
  base=mix(base,vec3(0.15,0.40,0.50),marker*studs*0.82);
  // Even parapet bays put the lens at route Z = 4.75 modulo 5m.
  float lamp=pow(max(0.0,1.0-abs(mod(z-2.25,5.0)-2.5)*0.65),2.5)*smoothstep(3.80,4.92,abs(world.x));
  emission=vec3(0.145,0.079,0.027)*lamp+vec3(0.02,0.09,0.11)*(edge+marker*studs)*0.35;
 }
 if(theme==3){
  float shoulder=smoothstep(4.16,4.30,abs(world.x));
  float groove=(1.0-smoothstep(0.016,0.029+aa,abs(mod(z,0.29)-0.145)))*shoulder;
  float patch=h(floor(vec2(world.x*0.9,z*0.43)));
  base*=0.88+patch*0.17+grain*0.055;
  base=mix(base,vec3(0.038,0.047,0.055),groove*0.56);
  float tick=(1.0-smoothstep(0.08,0.15+aa,abs(mod(z+2.0,10.0)-5.0)));
  float lanes=(1.0-smoothstep(0.19,0.24,abs(mod(world.x+1.0,2.0)-1.0)));
  float running_line=max(edge*0.72,lane*0.76)*max(dash,edge);
  float lamp_x=max(0.0,5.17-abs(world.x));
  float lamp_z=abs(mod(z-0.45,2.0)-1.0);
  float pool=exp(-lamp_x*lamp_x*1.24-lamp_z*lamp_z*3.7)*0.36;
  emission=vec3(0.031,0.16,0.21)*(running_line+tick*lanes*0.78)+vec3(0.45,0.18,0.053)*pool;
 }
 return base;
}
float roughness_for(int district){return district==4?0.44:(district==2?0.92:0.69);}
float metal_for(int district){return district==2?0.02:0.37;}
void fragment(){
 vec3 glow;
 ALBEDO=deck(district_theme,glow);
 EMISSION=glow;
 ROUGHNESS=roughness_for(district_theme);
 METALLIC=metal_for(district_theme);
 if(destination_theme!=0){
  float blend=1.0-smoothstep(-27.0,22.0,world.z-boundary_z);
  vec3 arrival_glow;
  ALBEDO=mix(ALBEDO,deck(destination_theme,arrival_glow),blend);
  EMISSION=mix(EMISSION,arrival_glow,blend);
  ROUGHNESS=mix(ROUGHNESS,roughness_for(destination_theme),blend);
  METALLIC=mix(METALLIC,metal_for(destination_theme),blend);
 }
}
"""
	_transition_deck = ShaderMaterial.new()
	_transition_deck.shader = deck_shader
	for theme: int in THEMES:
		var material := ShaderMaterial.new()
		material.shader = deck_shader
		material.set_shader_parameter("district_theme",theme)
		_decks[theme] = material
	var water_shader := Shader.new()
	water_shader.code = """shader_type spatial;
render_mode unshaded,cull_disabled;
uniform float route_time=0.0;
uniform float run_distance=0.0;
uniform int clip_mode=0;
uniform float boundary_z=-10000.0;
varying vec3 world;
varying vec2 sea_coord;
varying vec2 slope;
varying float crest;
varying float chop;
varying float spray;
varying float shore_distance;
float sea_hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
void vertex(){
 vec2 origin=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz;
 sea_coord=origin-vec2(0.0,run_distance);
 vec2 p=vec2(abs(sea_coord.x),sea_coord.y);
 float side=sign(sea_coord.x);
 float shoal=smoothstep(8.3,23.0,p.x);
 float shoal_gradient=6.0*clamp((p.x-8.3)/14.7,0.0,1.0)*(1.0-clamp((p.x-8.3)/14.7,0.0,1.0))/14.7;
 shore_distance=clip_mode==0?32.0:(origin.y-boundary_z)*float(clip_mode);
 float shore_fade=clamp((shore_distance-1.1)/12.1,0.0,1.0);
 float breakwater=shore_fade*shore_fade*(3.0-2.0*shore_fade);
 float shore_gradient=6.0*shore_fade*(1.0-shore_fade)*float(clip_mode)/12.1;
 float warp=sin(p.y*0.051+side*1.8);
 float group_angle=p.y*0.058-p.x*0.029+side*1.5-route_time*0.18;
 float swell_limit=1.0-smoothstep(47.0,112.0,p.x);
 float group=2.42+(1.03+1.15*swell_limit)*sin(group_angle)+1.38*swell_limit;
 float wave_angle=p.x*0.241+p.y*0.091+warp*0.52+route_time*0.88+side*1.35;
 float wave_sine=sin(wave_angle);
 float ridge=pow(0.5+wave_sine*0.5,6.0);
 vec2 ridge_gradient=3.0*pow(0.5+wave_sine*0.5,5.0)*cos(wave_angle)*vec2(0.241,0.091+0.02652*cos(p.y*0.051+side*1.8));
 float across=p.x*0.104-p.y*0.171+route_time*0.65+side*2.14;
 float diagonal=p.x*0.47+p.y*0.35-route_time*1.21;
 float wind=p.x*0.92-p.y*0.73+route_time*2.0;
 float far_detail=1.0-smoothstep(42.0,100.0,p.x);
 float wave=group*(ridge-0.13)+sin(across)*0.97+sin(diagonal)*0.34*far_detail;
 float tide=0.21*sin(p.y*0.17+route_time*0.63);
 VERTEX.x+=side*shoal*breakwater*0.84*cos(wave_angle)*ridge;
 VERTEX.y+=tide+shoal*breakwater*wave+sin(wind)*0.075*far_detail;
 slope=shoal*breakwater*(group*ridge_gradient+(ridge-0.13)*(1.03+1.15*swell_limit)*cos(group_angle)*vec2(-0.029,0.058)+cos(across)*0.97*vec2(0.104,-0.171)+cos(diagonal)*0.34*far_detail*vec2(0.47,0.35));
 slope.x=side*(slope.x+wave*shoal_gradient*breakwater);
 slope.y+=0.0357*cos(p.y*0.17+route_time*0.63)+wave*shoal*shore_gradient;
 crest=ridge*shoal*breakwater;
 chop=group;
 spray=-1.0;
 if(UV2.x>0.0){
  float age=fract(route_time*(1.25+UV2.x*0.12)+UV2.x*11.83);
  float life=sin(age*3.14159);
  spray=smoothstep(0.61,0.94,crest)*smoothstep(3.5,5.0,chop)*life;
  float span=(0.047+UV2.y*0.15)*sqrt(spray);
  VERTEX.x-=side*(0.1+age*0.46);
  VERTEX.y+=0.075+life*(0.16+UV2.y*0.88);
  VERTEX.xyz+=(INV_VIEW_MATRIX[0].xyz*UV.x+INV_VIEW_MATRIX[1].xyz*UV.y)*span;
 }
 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment(){
 if(clip_mode==1 && world.z<boundary_z)discard;
 if(clip_mode==-1 && world.z>=boundary_z)discard;
 if(spray>=0.0){
  if(spray<0.04 || abs(UV.x)+abs(UV.y)>1.32) discard;
  ALBEDO=mix(vec3(0.36,0.55,0.65),vec3(0.87,0.94,0.98),spray);
 } else {
 vec2 p=sea_coord;
 float pixel_size=max(length(dFdx(p)),length(dFdy(p)));
 float detail=1.0-smoothstep(0.12,0.65,pixel_size);
 float wind=dot(p,vec2(1.34,-2.68))+route_time*2.8;
 float ripple=dot(p,vec2(3.72,1.57))-route_time*3.7;
 vec2 micro=(vec2(0.07,-0.15)*cos(wind)+vec2(0.11,0.047)*cos(ripple))*detail;
 vec3 normal=normalize(vec3(-slope.x-micro.x,1.0,-slope.y-micro.y));
 vec3 view=normalize(INV_VIEW_MATRIX[3].xyz-world);
 vec3 reflected=reflect(-view,normal);
 float fresnel=pow(1.0-max(0.0,dot(normal,view)),4.0);
 float sky_angle=smoothstep(-0.18,0.75,reflected.y);
 float cloud=sin(reflected.z*5.1+reflected.x*4.7)+0.3*sin(reflected.x*13.7-reflected.z*9.3);
 vec3 sky=mix(vec3(0.26,0.38,0.51),vec3(0.045,0.089,0.15),sky_angle);
 sky*=0.75+0.30*smoothstep(-0.48,0.82,cloud);
 vec3 light=normalize(vec3(-0.34,0.64,-0.68));
 float lit=max(0.0,dot(light,normal));
 float face=0.14+lit*0.60+crest*0.27;
 vec3 sea=mix(vec3(0.006,0.041,0.070),vec3(0.015,0.19,0.26),face);
 sea=mix(sea,sky,fresnel*0.69);
 sea+=vec3(0.11,0.16,0.19)*pow(max(0.0,dot(light,reflected)),36.0);
 // Crest sheets and their torn edges move with the same wave that lifts them.
 vec2 grain=floor((p+vec2(route_time*0.35,0.0))*4.75);
 float pore=mix(0.51,sea_hash(grain),detail);
 float streak=0.5+0.5*sin(dot(p,vec2(0.59,0.94))+sin(p.y*0.73)*1.8+route_time*0.8);
 float lace=smoothstep(0.23,0.78,pore*0.61+streak*0.64);
 float white=smoothstep(0.70,0.94,crest+(chop-3.8)*0.104+(streak-0.5)*0.22);
 float trails=smoothstep(0.29,0.73,crest)*smoothstep(0.74,0.95,pore*0.37+streak*0.67)*0.29;
 vec2 piling=vec2(abs(p.x)-6.28,mod(p.y+9.0,20.0)-10.0);
 float pile_foam=(1.0-smoothstep(0.69,2.24,length(piling*vec2(0.84,1.0))))*smoothstep(0.44,0.86,pore*0.44+streak*0.61);
 float wash=(1.0-smoothstep(5.9,8.8,abs(p.x)))*smoothstep(0.67,0.98,streak)*0.27+pile_foam*0.38;
 float tidal_wash=(1.0-smoothstep(0.56,3.8,shore_distance))*smoothstep(0.23,0.83,pore*0.49+streak*0.64)*0.43;
 float foam=clamp(white*(0.36+lace*0.64)+trails+wash+tidal_wash,0.0,1.0);
 vec3 surf=mix(vec3(0.31,0.49,0.56),vec3(0.82,0.89,0.92),lace);
 ALBEDO=mix(sea,surf,foam);
 }
}
"""
	_water_material = ShaderMaterial.new()
	_water_material.shader = water_shader
	_arrival_water = _water_material.duplicate()
	_arrival_water.set_shader_parameter("clip_mode",-1)
	_build_tidal_water()

func _build_industrial_transition_deck() -> void:
	_industrial_transition_deck = _transition_deck.duplicate()
	var source := _old_decks[0] as ShaderMaterial if not _old_decks.is_empty() else null
	if source == null: return
	# Reuse the original road fragment and surface properties at the start.
	var original: String = source.shader.code
	var helper_start := original.find("float route_hash(")
	var vertex_start := original.find("void vertex()")
	var fragment_start := original.find("void fragment() {")
	if helper_start < 0 or vertex_start < helper_start or fragment_start < vertex_start: return
	var functions := original.substr(helper_start,vertex_start-helper_start)
	var fragment := original.substr(fragment_start+"void fragment() {".length()).strip_edges().trim_suffix("}")
	fragment = fragment.replace("world_position","world").replace("ALBEDO =","vec3 result =").replace("ROUGHNESS =","rough =").replace("METALLIC =","metal =").replace("SPECULAR =","specular =")
	var shader := Shader.new()
	var code: String = _transition_deck.shader.code
	code = code.replace("void fragment(){",functions+"\nvec3 industrial_road(out float rough,out float metal,out float specular){\n"+fragment+"\nreturn result;\n}\nvoid fragment(){")
	code = code.replace("if(destination_theme!=0){","float rough; float metal; float specular; ALBEDO=industrial_road(rough,metal,specular); ROUGHNESS=rough; METALLIC=metal; SPECULAR=specular;\n if(destination_theme!=0){")
	code = code.replace("smoothstep(-27.0,22.0,world.z-boundary_z)","smoothstep(-45.0,58.0,world.z-boundary_z)")
	code = code.replace("EMISSION=mix(EMISSION,arrival_glow,blend);","EMISSION=mix(EMISSION,arrival_glow,blend); SPECULAR=mix(SPECULAR,0.5,blend);")
	shader.code = code
	_industrial_transition_deck.shader = shader

func _build_tidal_water() -> void:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var spray_corners := PackedVector2Array()
	var spray_seeds := PackedVector2Array()
	var across := PackedFloat32Array()
	# Lateral resolution falls away from the bridge. The strip edges use
	# identical X samples and world phases so recycling does not split a crest.
	for band in [Vector3(0.0,46.25,0.625),Vector3(46.25,91.25,1.25),Vector3(91.25,171.25,2.5),Vector3(171.25,321.25,5.0)]:
		for step in range(roundi((band.y-band.x)/band.z)):
			across.append(band.x+float(step)*band.z)
	across.append(321.25)
	var row_width := across.size()
	for side in [-1.0,1.0]:
		var first := vertices.size()
		for z in range(17):
			for x in across:
				vertices.append(Vector3(side*x,-3.15,-TILE_LENGTH+float(z)*TILE_LENGTH/16.0))
		for z in range(16):
			for x in range(row_width-1):
				var a := first+z*row_width+x
				var b := a+row_width
				if side > 0.0:
					indices.append_array(PackedInt32Array([a,b+1,b,a,a+1,b+1]))
				else:
					indices.append_array(PackedInt32Array([a,b,b+1,a,b+1,a+1]))
	# The spray is evaluated on the same wave field as the water below it.
	# These prebuilt quads never allocate particles or bodies during the run.
	spray_corners.resize(vertices.size())
	spray_seeds.resize(vertices.size())
	var random := RandomNumberGenerator.new()
	random.seed = 4441
	for side in [-1.0,1.0]:
		for fleck in range(112):
			var at := Vector3(side*random.randf_range(13.0,64.0),-3.15,random.randf_range(-TILE_LENGTH,0.0))
			var seed := Vector2(random.randf_range(0.1,1.0),random.randf())
			var first := vertices.size()
			for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
				vertices.append(at)
				spray_corners.append(corner)
				spray_seeds.append(seed)
			indices.append_array(PackedInt32Array([first,first+1,first+2,first,first+2,first+3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = spray_corners
	arrays[Mesh.ARRAY_TEX_UV2] = spray_seeds
	arrays[Mesh.ARRAY_INDEX] = indices
	_water_mesh = ArrayMesh.new()
	_water_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)

func _build_theme(theme: int, layout: int) -> ArrayMesh:
	_clear_geometry()
	match theme:
		2: _ink_pass(layout)
		3: _night_pursuit(layout)
		4: _tidal_front(layout)
		5: _orbital_berth(layout)
	_district_craft(theme,layout)
	return _commit_geometry()

func _district_craft(theme: int, layout: int) -> void:
	if theme != 2: return
	var stone := Color("939393")
	for side: float in [-1.0,1.0]:
		for z: float in [-1.2,-8.6]:
			for course in range(3):
				_box(Vector3(0.54-float(course)*0.07,0.11,0.60-float(course)*0.07),Vector3(side*5.5,0.83+float(course)*0.11,z),stone)
			for slot in range(3):
				_box(Vector3(0.075,0.25,0.10),Vector3(side*5.20,0.30,z-0.16+float(slot)*0.16),Color("383838"))
		for brick in range(12):
			var z := -0.43-float(brick)*0.82
			_box(Vector3(0.42,0.20,0.78),Vector3(side*5.5,0.0,z),stone.darkened(float(brick%3)*0.045))
	if layout in [1,7,14,21]:
		var side := -1.0 if layout in [1,14] else 1.0
		var at := Vector3(side*13.8,-0.5,-5)
		_stone_foundation(at+Vector3(0,-10.25,0),Vector3(13,20.5,14),Color("777777"),layout)
		_box(Vector3(3.4,0.5,12.4),Vector3(side*7.2,-0.25,-5),Color("858585"))
		for z in [-9.0,-1.0]:
			_beam(Vector3(side*8.8,-4.0,z),Vector3(side*6.2,-0.4,z),0.45,Color("666666"),0.55)
		for z in [-10.7,0.7]:
			for panel in range(7):
				var x := side*13.8-4.7+float(panel)*1.55
				_box(Vector3(1.45,0.37,0.20),Vector3(x,0.1,z),Color("9a9a9a"))
				_box(Vector3(1.40,0.32,0.18),Vector3(x+0.2,0.49,z+0.03),Color("858585"))
		_stone_lantern(Vector3(side*7.2,0,-8.4),Color("818181"),Color("303030"))


func _stone_foundation(at: Vector3, size: Vector3, stone: Color, seed: int) -> void:
	# A complete occupied base reaches below the visible valley floor. Layered
	# masonry ledges and buttresses carry the pavilion rather than floating.
	for level in range(7):
		var p := float(level)/7.0
		var width := size.x*(1.0-p*0.16)
		var depth := size.z*(1.0-p*0.14)
		_box(Vector3(width,size.y/7.0+0.03,depth),at+Vector3(sin(float(level+seed))*0.2,size.y*(p-0.5)+size.y/14.0,0),stone.darkened(float(level%3)*0.035))
		for pillar in [-1.0,1.0]:
			_box(Vector3(0.7,size.y/7.0,depth+0.45),at+Vector3(pillar*width*0.4,size.y*(p-0.5)+size.y/14.0,0),stone.lightened(0.04))

func _stone_lantern(at: Vector3, stone: Color, ink: Color) -> void:
	for level in range(3): _box(Vector3(0.9-float(level)*0.18,0.14,0.9-float(level)*0.18),at+Vector3(0,0.07+float(level)*0.14,0),stone)
	_box(Vector3(0.24,1.0,0.24),at+Vector3(0,0.92,0),ink)
	_box(Vector3(0.60,0.10,0.60),at+Vector3(0,1.42,0),stone)
	for x in [-0.24,0.24]:
		for z in [-0.24,0.24]: _box(Vector3(0.10,0.55,0.10),at+Vector3(x,1.73,z),ink)
	_box(Vector3(0.40,0.38,0.40),at+Vector3(0,1.7,0),Color("a54032"))
	for level in range(4): _box(Vector3(0.90-float(level)*0.18,0.11,0.90-float(level)*0.18),at+Vector3(0,2.06+float(level)*0.11,0),stone)

func _equipment_cabinet(at: Vector3, size: Vector3, base: Color, trim: Color, glow_color: Color) -> void:
	for side in [-1.0,1.0]:
		_box(Vector3(0.20,0.28,size.z*0.76),at+Vector3(side*size.x*0.33,0.12,0),trim)
	_beveled_box(size-Vector3(0,0.25,0),at+Vector3(0,size.y*0.5+0.135,0),0.12,base)
	for front in [-1.0,1.0]:
		var z: float = front*(size.z*0.5+0.025)
		_box(Vector3(size.x*0.83,size.y*0.74,0.07),at+Vector3(0,size.y*0.51,z),base.darkened(0.38))
		_box(Vector3(size.x*0.70,size.y*0.59,0.08),at+Vector3(-0.02,size.y*0.49,z+front*0.045),base.lightened(0.08))
		for hinge in [-1.0,1.0]: _box(Vector3(0.12,0.28,0.09),at+Vector3(-size.x*0.31,size.y*(0.5+hinge*0.20),z+front*0.08),trim)
		_box(Vector3(0.10,0.32,0.10),at+Vector3(size.x*0.23,size.y*0.50,z+front*0.10),trim)
		for slit in range(5): _box(Vector3(size.x*0.40,0.06,0.06),at+Vector3(-size.x*0.07,size.y*0.30+float(slit)*0.14,z+front*0.095),base.darkened(0.6))
		_box(Vector3(size.x*0.4,0.11,0.07),at+Vector3(0,size.y*0.82,z+front*0.09),glow_color)
	for rib in range(6): _box(Vector3(size.x*0.9,0.10,0.13),at+Vector3(0,size.y+0.055,-size.z*0.38+float(rib)*size.z*0.15),trim)

func _pipe_run(points: Array, width: float, tint: Color) -> void:
	for index in range(points.size()-1):
		_beam(points[index],points[index+1],width,tint)
	for point: Vector3 in points: _box(Vector3.ONE*(width*1.45),point,tint.lightened(0.14))

func _guard_rail(a: Vector3, b: Vector3, height: float, tint: Color) -> void:
	_beam(a+Vector3(0,height,0),b+Vector3(0,height,0),0.08,tint)
	_beam(a+Vector3(0,height*0.48,0),b+Vector3(0,height*0.48,0),0.06,tint)
	var count := maxi(1,ceili(a.distance_to(b)/1.4))
	for index in range(count+1):
		var at := a.lerp(b,float(index)/float(count))
		_box(Vector3(0.11,height,0.11),at+Vector3(0,height*0.5,0),tint)
		_box(Vector3(0.20,0.12,0.20),at+Vector3(0,0.04,0),tint.darkened(0.15))

func _voxel_drum(at: Vector3, radius: float, height: float, body: Color, rim: Color) -> void:
	var unit := 0.18
	var extent := ceili(radius/unit)
	for row in range(-extent,extent+1):
		var z := float(row)*unit
		var width := sqrt(maxf(0.0,radius*radius-z*z))
		if width < 0.04: continue
		_box(Vector3(width*2.0,height,unit),at+Vector3(0,height*0.5,z),body)
		for y in [0.08,height-0.08]: _box(Vector3(width*2.0+0.05,0.13,unit),at+Vector3(0,y,z),rim)
	_box(Vector3(radius*0.7,0.13,radius*0.7),at+Vector3(0,height+0.04,0),rim)

func _ink_pass(layout: int) -> void:
	var ink := Color("242424")
	var stone := Color("8c8c8c")
	var pale := Color("c4c4c4")
	var red := Color("8d2622")
	# The mist has an actual valley under it. Adjacent courses overlap in z
	# and remain attached to the district when the crossing clips it.
	_box(Vector3(264,2.8,10.06),Vector3(0,-21.4,-5),Color("797979"))
	for side in [-1.0,1.0]:
		var shelf := 7.0+float(posmod(layout*5+int(side),4))*1.5
		_box(Vector3(26,6,10.05),Vector3(side*29,-17.2,-5),Color("717171"))
		_box(Vector3(18,shelf,9.8),Vector3(side*40,-14.25+shelf*0.5-0.1,-5),Color("727272"))
	for side in [-1.0,1.0]:
		_box(Vector3(0.44,0.18,10),Vector3(side*5.50,0.67,-5),stone)
		_box(Vector3(0.5,0.2,10),Vector3(side*5.50,-0.10,-5),stone)
		for z in [-1.2,-8.6]:
			_box(Vector3(0.5,0.9,0.52),Vector3(side*5.50,0.25,z),stone)
			_box(Vector3(0.68,0.14,0.67),Vector3(side*5.50,0.76,z),pale)
			_box(Vector3(0.07,0.15,0.22),Vector3(side*5.22,0.32,z),red)
	# Only one side is built up. The opposite side opens across the mountain
	# valley, so the route does not become another identical column tunnel.
	if layout in [1,7,14,21]:
		var side := -1.0 if layout in [1,14] else 1.0
		var at := Vector3(side*13.8,-0.5,-5)
		for tier in range(4):
			_box(Vector3(11.0-float(tier)*0.8,0.75,13.0-float(tier)),at+Vector3(0,float(tier)*0.75,0),stone.darkened(float(tier)*0.025))
		for step in range(12):
			_box(Vector3(0.38,0.22,4.3),Vector3(side*(6.6+float(step)*0.37),float(step)*0.22-0.15,-3.5),pale)
		_pavilion(at+Vector3(0,2.5,0),1.0,ink,stone,red)
		_banner(at+Vector3(-side*3.1,5.1,3.1),2.5,red,pale)
	elif layout in [4,12,18]:
		var side := 1.0 if layout != 12 else -1.0
		_karst(Vector3(side*17,-8,-5),Vector3(8,17,12),Color("626262"),layout)
		_stone_foundation(Vector3(side*14,-9,-4),Vector3(7,30,8),Color("656565"),layout+17)
		_pine(Vector3(side*14,6.0,-4),side,ink)
	# Bamboo is a set of irregular small groves, with long breathing spaces.
	if layout in [0,2,9,10,16,22]:
		var side := -1.0 if layout%2 == 0 else 1.0
		_stone_foundation(Vector3(side*9.2,-11.98,-5),Vector3(6,24,10.2),Color("737373"),layout+31)
		for stem in range(4):
			var at := Vector3(side*(7.8+float(stem%3)*0.8),0,-1.3-float(stem)*2.1)
			var height := 4.3+float(posmod(layout+stem,5))*0.7
			_beam(at,at+Vector3(side*0.30,height,0.2),0.115,ink)
			for node in range(2,6):
				var base := at+Vector3(side*0.05*float(node),height*float(node)/6.5,0)
				_box(Vector3(0.16,0.055,0.15),base,stone)
				var tip := base+Vector3(-side*(0.6+float(node%2)*0.45),0.25,0.55)
				_beam(base,tip,0.035,ink)
				for leaf in range(3):
					var origin := base.lerp(tip,0.35+float(leaf)*0.25)
					_leaf(origin,origin+Vector3(side*0.45,-0.23,0.35+float(leaf)*0.16),ink)
		for stem in range(5):
			var at := Vector3(side*(7.6+float(stem%3)*0.58),0.04,-1.1-float(stem)*1.63)
			var crown := at+Vector3(side*(0.42+0.12*stem),5.8+0.27*stem,0.21)
			_beam(at,crown,0.105,ink)
			for branch in range(3):
				var start := at.lerp(crown,0.55+branch*0.17)
				var tip := start+Vector3(-side*(0.90+branch*0.31),0.54,0.37*float(branch-1))
				_beam(start,tip,0.044,ink)
				for leaf in range(4):
					var root := start.lerp(tip,0.4+0.18*leaf)
					_leaf(root,root+Vector3(-side*(0.36+0.14*leaf),-0.27,0.42*(-1 if leaf%2 == 0 else 1)),ink)
	if layout == 5: _mountain_gate(Vector3(0,0,-5),ink,stone,red)
	if layout in [3,17]:
		var side := -1.0 if layout == 3 else 1.0
		for panel in range(5):
			var z := -1.0-float(panel)*1.7
			_box(Vector3(0.5,3.8,1.5),Vector3(side*9,1.5,z),stone)
			_box(Vector3(0.36,1.1,0.32),Vector3(side*9,3.88,z),ink)
			for slope in [-1.0,1.0]: _beam(Vector3(side*9,4.25,z),Vector3(side*9+slope*2.0,3.6,z),0.15,ink,0.16)
		_roof(Vector3(side*9,3.5,-5),Vector2(2.4,5.5),0.8,ink,pale)
		# A carved screen sits in the walkway rather than appearing on the rail.
		_stone_foundation(Vector3(side*9,-8.0,-5),Vector3(4.6,16,10),stone.darkened(0.20),layout)
		for cell in range(14):
			var z := -8.6+0.48*cell
			var crest := sin(0.7*cell)*0.45+sin(1.8*cell)*0.22
			_box(Vector3(0.07,0.53+crest*0.45,0.41),Vector3(side*8.71,1.38+crest,z),Color("414141"))
		for z in [-2.0,-7.8]: _stone_lantern(Vector3(side*6.6,-0.05,z),stone,ink)

func _pavilion(at: Vector3, scale: float, ink: Color, stone: Color, red: Color) -> void:
	_box(Vector3(7.5,0.35,8.0)*scale,at,stone)
	for x in [-2.8,2.8]:
		for z in [-2.9,2.9]:
			_box(Vector3(0.34,4.6,0.34)*scale,at+Vector3(x,2.3,z)*scale,ink)
			_box(Vector3(0.55,0.24,0.55)*scale,at+Vector3(x,0.18,z)*scale,stone)
			for height in [3.7,4.2]: _box(Vector3(0.70,0.18,0.62)*scale,at+Vector3(x,height,z)*scale,red)
			# Stacked bracket arms carry the eaves into the column head.
			for bracket in range(3):
				_box(Vector3(0.96-float(bracket)*0.20,0.13,0.18)*scale,at+Vector3(x,4.32+float(bracket)*0.14,z)*scale,stone if bracket==1 else ink)
				_box(Vector3(0.18,0.13,0.96-float(bracket)*0.20)*scale,at+Vector3(x,4.32+float(bracket)*0.14,z)*scale,red if bracket==1 else ink)
			_beam(at+Vector3(x,4.32,z)*scale,at+Vector3(0,5.72,z)*scale,0.13*scale,ink)
	_box(Vector3(6.2,0.24,6.4)*scale,at+Vector3(0,4.3,0)*scale,ink)
	for z in [-2.9,2.9]: _box(Vector3(6.8,0.42,0.28)*scale,at+Vector3(0,4.84,z)*scale,ink)
	_roof(at+Vector3(0,4.5,0)*scale,Vector2(4.5,4.7)*scale,1.4*scale,ink,stone)
	for z in [-2.9,2.9]:
		_box(Vector3(5.8,0.1,0.12)*scale,at+Vector3(0,1.2,z)*scale,red)
		for x in [-2.0,-0.8,0.8,2.0]: _box(Vector3(0.12,1.05,0.12)*scale,at+Vector3(x,0.65,z)*scale,ink)

func _roof(at: Vector3, size: Vector2, height: float, ink: Color, rim: Color) -> void:
	# Individual stepped roof courses form the roof surface. Upturned ends
	# have actual volume and rafters; two crossing beams cannot stand in for it.
	for side in [-1.0,1.0]:
		for strip in range(10):
			var t := (float(strip)+0.5)/10.0
			var x: float = side*t*size.x
			var y := height*pow(1.0-t,1.45)+pow(t,7.0)*height*0.32
			_box(Vector3(size.x/10.0+0.025,0.15,size.y*2.0+pow(t,3.0)*0.40),at+Vector3(x,y,0),ink)
			if strip < 9:
				var next_t := t+0.1
				var next_y := height*pow(1.0-next_t,1.45)+pow(next_t,7.0)*height*0.32
				_box(Vector3(0.06,absf(next_y-y)+0.16,size.y*2.0),at+Vector3(side*(t+0.05)*size.x,(y+next_y)*0.5,0),ink)
			for tile in range(int(ceil(size.y/0.28))):
				var z := -size.y+0.28+float(tile)*0.56
				_box(Vector3(size.x/10.0*0.73,0.085,0.50),at+Vector3(x,y+0.11,z),ink.lightened(0.025 if tile%3 else 0.07))
			for z in [-size.y,size.y]: _box(Vector3(size.x/10.0+0.03,0.08,0.14),at+Vector3(x,y+0.10,z),rim)
		for rib in range(13):
			var z := -size.y+float(rib)*size.y/6.0
			_beam(at+Vector3(0,height-0.15,z),at+Vector3(side*size.x*0.83,0.08,z),0.07,rim,0.07)
	_box(Vector3(size.x*0.10+0.06,0.24,size.y*2.0),at+Vector3(0,height-0.04,0),ink)
	_box(Vector3(0.22,0.23,size.y*2.0+0.4),at+Vector3(0,height+0.12,0),rim)

func _mountain_gate(at: Vector3, ink: Color, stone: Color, red: Color) -> void:
	for side in [-1.0,1.0]:
		_box(Vector3(1.5,0.65,2.4),at+Vector3(side*7.0,0.15,0),stone)
		_box(Vector3(0.75,11.3,0.9),at+Vector3(side*7.0,5.75,0),ink)
		for height in [9.8,10.5,11.2]: _box(Vector3(1.8,0.22,1.4),at+Vector3(side*7.0,height,0),stone)
		_box(Vector3(0.48,0.42,4.4),at+Vector3(side*7.0,11.82,0),ink)
		_beam(at+Vector3(side*7,10.6,0),at+Vector3(side*5.35,11.4,0),0.27,ink,0.45)
		_banner(at+Vector3(side*6.0,10.9,0.78),2.7,red.lightened(0.10),stone)
	_box(Vector3(16.5,0.55,1.2),at+Vector3(0,11.4,0),ink)
	_box(Vector3(0.10,0.50,0.10),at+Vector3(0,10.98,0),ink)
	_box(Vector3(0.62,0.41,0.62),at+Vector3(0,10.56,0),red)
	for height in [10.31,10.81]: _box(Vector3(0.79,0.11,0.75),at+Vector3(0,height,0),ink)
	_roof(at+Vector3(0,11.7,0),Vector2(9.2,2.1),1.1,ink,stone)

func _karst(at: Vector3, size: Vector3, tint: Color, seed: int) -> void:
	# Unequal broad cliff masses and narrow split fingers, staggered in depth.
	# Their shared footprint has6m ledges and1m fissures, not equal city towers.
	var widths := [0.35,0.15,0.27,0.12,0.21]
	var cursor := -size.x*0.55
	for mass in range(widths.size()):
		var noise := sin(float(seed*17+mass*31))*0.5+0.5
		var width: float = size.x*widths[posmod(mass+seed,widths.size())]
		var depth := size.z*(0.43+noise*0.33)
		var z := sin(float(seed+mass)*2.1)*size.z*0.25
		var height := size.y*(0.48+noise*0.53)
		var x := cursor+width*0.5
		for tier in range(12):
			var h := height/12.0
			var p := float(tier)/12.0
			var taper: float = maxf(0.12,pow(1.0-p,0.72))
			var jag := sin(float(tier*3+mass+seed))*width*0.07
			_box(Vector3(width*taper,h+0.02,depth*(1.0-p*0.23)),at+Vector3(x+jag,h*(float(tier)+0.5),z+p*depth*0.14),tint.lightened(p*0.06+noise*0.025))
			if tier < 8:
				var shoulder := width*taper*(0.35+0.20*sin(float(tier*2+mass+seed)))
				var ledge := depth*(0.14+0.06*cos(float(tier+seed)))
				var front := at+Vector3(x+jag+width*0.14*sin(float(mass+seed)),h*(float(tier)+0.5),z+depth*0.46)
				_box(Vector3(shoulder,h*0.99,ledge*2.0),front,tint.darkened(0.12+0.04*noise))
			if tier in [2,5,9]:
				_box(Vector3(width*taper*0.62,h*0.055,depth*0.25),at+Vector3(x+jag,h*float(tier),z+depth*0.44),tint.darkened(0.12))
		cursor += width*0.84

func _pine(at: Vector3, side: float, ink: Color) -> void:
	_beam(at,at+Vector3(side*0.7,3.7,0),0.25,ink)
	for arm in range(4):
		var root := at+Vector3(side*0.2,1.4+float(arm)*0.6,0)
		var tip := root+Vector3(side*(1.4+float(arm%2)*1.1),0.45,float(arm%3)-1.0)
		_beam(root,tip,0.12,ink)
		_taper(tip-Vector3(0,0.05,0),0.38,Vector2(1.4,1.1),Vector2(0.4,0.3),ink,7)

func _night_pursuit(layout: int) -> void:
	var frame := Color("657382")
	var steel := Color("3c4a59")
	var hull := Color("25303d")
	var dark := Color("131c26")
	var lamp := Color(1.0,0.64,0.27,0.58)
	var glass := Color(0.28,0.68,0.82,0.76)
	var rail := Color("b88646")
	_box(Vector3(264,2.2,10.04),Vector3(0,-16.3,-5),dark)
	for side: float in [-1.0,1.0]:
		var band := posmod(layout+(0 if side < 0 else 5),12)
		_pursuit_roadside(side,steel,hull,frame,lamp,glass)
		_pursuit_service_yard(side,band,steel,hull,frame,lamp,glass,rail)
		if band not in [4,9,11]:
			_pursuit_service_gallery(side,band,steel,hull,dark,frame,lamp,glass,rail)
		_pursuit_tower(side,layout,band,steel,hull,dark,glass)
		_box(Vector3(6.4,0.25,10.02),Vector3(side*33.0,-14.99,-5),steel.darkened(0.35))
		_box(Vector3(0.08,0.04,10),Vector3(side*33.0,-14.85,-5),rail)
		for z: float in [-2.0,-8.0]:
			_box(Vector3(0.14,4.7,0.15),Vector3(side*36.4,-12.59,z),frame)
			_box(Vector3(1.0,0.12,0.15),Vector3(side*36.0,-10.30,z),steel)
			_box(Vector3(0.53,0.07,0.14),Vector3(side*35.73,-10.39,z),lamp)
	if layout in [1,8,15,22]: _pursuit_checkpoint(-5.0,layout%2==0,steel,frame,lamp)
	if layout in [6,18]: _pursuit_overpass(layout,steel,hull,frame,lamp)


func _pursuit_roadside(side: float, steel: Color, hull: Color, frame: Color, lamp: Color, glass: Color) -> void:
	_box(Vector3(1.82,0.44,10),Vector3(side*5.95,-0.30,-5),hull)
	_box(Vector3(0.40,0.47,10),Vector3(side*5.45,0.11,-5),steel)
	_box(Vector3(0.16,0.11,10),Vector3(side*5.49,0.39,-5),frame)
	for panel in range(5):
		var z := -1.0-2.0*panel
		_box(Vector3(0.35,0.41,1.88),Vector3(side*5.38,0.13,z),hull.lightened(0.04*float(panel%2)))
		_box(Vector3(0.40,0.46,0.14),Vector3(side*5.39,0.21,z-0.94),frame)
		_box(Vector3(0.11,0.14,0.73),Vector3(side*5.20,0.04,z+0.45),Color("151f29"))
		_box(Vector3(0.06,0.065,0.60),Vector3(side*5.13,0.04,z+0.45),lamp)
		_box(Vector3(0.038,0.080,0.19),Vector3(side*5.201,0.298,z-0.71),glass)
	for drain in range(15):
		_box(Vector3(0.20,0.018,0.25),Vector3(side*5.11,-0.051,-0.38-0.66*drain),steel)


func _pursuit_service_yard(side: float, band: int, steel: Color, hull: Color, frame: Color, lamp: Color, glass: Color, rail: Color) -> void:
	_box(Vector3(10.3,0.51,9.95),Vector3(side*10.35,-0.31,-5),steel)
	for z: float in [-1.0,-8.7]:
		_beam(Vector3(side*6.50,-0.44,z),Vector3(side*13.0,-5.9,z),0.49,frame,0.68)
		_box(Vector3(1.95,15.3,1.93),Vector3(side*13.0,-7.9,z),hull)
	if band in [4,9,11]:
		_guard_rail(Vector3(side*15.40,-0.055,-9.9),Vector3(side*15.40,-0.055,-0.1),0.93,rail)
		for module in range(3):
			var x := side*(9.0+float(module%2)*2.80)
			var z := -1.45-float(module)*2.8
			_equipment_cabinet(Vector3(x,-0.055,z),Vector3(1.82,2.66 if module == 1 else 1.77,1.47),hull,frame,glass)
		var mast := Vector3(side*7.7,-0.055,-5.35)
		_box(Vector3(0.29,4.55,0.30),mast+Vector3(0,2.275,0),steel)
		_box(Vector3(1.6,0.20,0.36),mast+Vector3(side*0.62,4.43,0),frame)
		_box(Vector3(0.85,0.065,0.27),mast+Vector3(side*0.79,4.31,0),lamp)


func _pursuit_service_gallery(side: float, band: int, steel: Color, hull: Color, dark: Color, frame: Color, lamp: Color, glass: Color, rail: Color) -> void:
	var setback := 10.65 if band in [2,3,7,8] else 11.9
	var mezzanine := 4.75 if band%3==0 else 5.30
	var roof := mezzanine+4.15
	var z := -5.0
	var x := side*setback
	_box(Vector3(8.5,15.7,9.92),Vector3(side*(setback+2.55),-7.88,z),dark)
	_box(Vector3(5.4,mezzanine+0.14,9.72),Vector3(side*(setback+2.1),mezzanine*0.5-0.05,z),hull)
	_box(Vector3(6.9,0.48,9.78),Vector3(x,mezzanine,z),steel)
	_box(Vector3(0.37,0.62,9.74),Vector3(side*(setback-3.33),mezzanine-0.02,z),hull)
	_guard_rail(Vector3(side*(setback-3.28),mezzanine+0.26,-9.9),Vector3(side*(setback-3.28),mezzanine+0.26,-0.1),0.91,rail)
	_box(Vector3(4.8,4.25,9.49),Vector3(side*(setback+2.42),(roof+mezzanine)*0.5,z),hull.darkened(0.16))
	_box(Vector3(5.7,0.39,9.72),Vector3(side*(setback+2.1),roof,z),steel)
	for column in range(6):
		var pane_z := -0.93-1.63*column
		_box(Vector3(0.34,2.40,1.48),Vector3(x,mezzanine+1.71,pane_z),frame.darkened(0.19))
		_box(Vector3(0.085,1.84,1.16),Vector3(side*(setback-0.18),mezzanine+1.73,pane_z),dark)
		for bar in range(2):
			var lit := posmod(column+band+bar,5) != 0
			_box(Vector3(0.035,0.37,0.98),Vector3(side*(setback-0.23),mezzanine+1.37+bar*0.52,pane_z),glass if lit else steel)
		_box(Vector3(0.085,1.82,0.047),Vector3(side*(setback-0.26),mezzanine+1.72,pane_z),frame)
	for post_z: float in [-1.05,-8.9]:
		var shoe := Vector3(side*(setback-3.66),0.21,post_z)
		var elbow := Vector3(side*(setback-1.94),mezzanine*0.56,post_z)
		var head := Vector3(side*(setback-0.31),mezzanine-0.21,post_z)
		_beveled_box(Vector3(1.47,0.54,1.48),shoe,0.16,frame)
		_beam(shoe+Vector3(0,0.23,0),elbow,0.85,frame,1.06)
		_beam(elbow,head,0.83,steel,1.06)
		_box(Vector3(1.04,0.40,1.13),elbow,frame)
		_box(Vector3(0.12,0.15,0.88),elbow-Vector3(side*0.54,0.02,0),lamp)
	for lamp_z: float in [-3.0,-7.0]:
		var at := Vector3(side*(setback-2.78),mezzanine-0.30,lamp_z)
		_box(Vector3(0.73,0.16,1.46),at,hull)
		_box(Vector3(0.55,0.045,1.12),at-Vector3(0,0.10,0),lamp)
	var door := Vector3(side*(setback-0.69),0.04,-5.1)
	_box(Vector3(0.76,3.74,3.67),door+Vector3(0,1.85,0),frame)
	_box(Vector3(0.18,3.12,2.98),door+Vector3(-side*0.40,1.54,0),dark)
	for panel: float in [-0.71,0.71]:
		_box(Vector3(0.07,2.82,1.22),door+Vector3(-side*0.52,1.42,panel),steel)
	_box(Vector3(0.039,0.18,2.12),door+Vector3(-side*0.57,2.37,0),glass)
	_box(Vector3(0.18,0.13,2.82),door+Vector3(-side*0.46,3.32,0),Color(0.88,0.24,0.13,0.67))
	var stairs := band in ([2,7,8] if side < 0 else [1,5,8,10])
	if stairs:
		_pursuit_stairs(side,side*(setback-2.28),mezzanine+0.24,steel,frame,rail)
	else:
		_equipment_cabinet(Vector3(side*(setback-2.34),-0.055,-6.9),Vector3(1.32,1.83,1.14),hull,frame,glass)
		for crate in range(2):
			_beveled_box(Vector3(0.80,0.75,1.08),Vector3(side*(setback-2.05-crate*0.92),0.321,-3.29),0.10,steel)
	_pipe_run([Vector3(x,0,-2.28),Vector3(x,3.47,-2.28),Vector3(side*(setback-0.62),3.47,-2.28),Vector3(side*(setback-0.62),3.47,-7.57)],0.15,rail.darkened(0.41))


func _pursuit_stairs(side: float, x: float, height: float, steel: Color, frame: Color, rail: Color) -> void:
	for step in range(18):
		var z := -8.77+0.42*step
		var y := height*float(step+1)/18.0
		_box(Vector3(1.56,0.18,0.44),Vector3(x,y-0.09,z),steel)
		_box(Vector3(1.59,0.049,0.10),Vector3(x,y-0.026,z-0.16),frame)
		if step%3 == 0: _box(Vector3(0.085,0.92,0.085),Vector3(x-side*0.78,y+0.46,z),frame)
	for beam_x: float in [-0.59,0.59]:
		_beam(Vector3(x+beam_x,-0.06,-9.07),Vector3(x+beam_x,height-0.23,-1.54),0.20,frame,0.27)
	_beam(Vector3(x-side*0.78,0.96,-8.86),Vector3(x-side*0.78,height+0.87,-1.56),0.088,rail,0.12)
	_box(Vector3(3.42,0.27,1.62),Vector3(x+side*0.79,height-0.13,-0.81),steel)


func _pursuit_tower(side: float, layout: int, band: int, steel: Color, hull: Color, dark: Color, glass: Color) -> void:
	var x := side*(21.2+float(band%3)*3.6)
	var z := -5.0
	var height := 17.5+float(posmod(layout*7+band,7))*2.7
	_beveled_box(Vector3(9.0,height+8.0,8.67),Vector3(x,height*0.5-11.0,z),0.61,hull)
	_box(Vector3(8.7,0.47,8.95),Vector3(x,height-7.0,z),steel)
	_box(Vector3(5.9,4.0,6.65),Vector3(x+side*0.78,height-4.85,z-0.53),dark)
	_box(Vector3(6.8,0.44,7.3),Vector3(x+side*0.78,height-2.67,z-0.53),steel)
	for floor_index in range(6):
		var y := -6.1+height*float(floor_index+1)/7.4
		var edge := x-side*4.52
		_box(Vector3(0.38,0.23,8.78),Vector3(edge,y,z),steel)
		for bay in range(4):
			var pane_z := z-3.0+2.0*bay
			_box(Vector3(0.21,0.83,1.50),Vector3(edge,y+0.59,pane_z),dark)
			if posmod(floor_index*5+bay+layout,7) < 4:
				_box(Vector3(0.049,0.45,1.24),Vector3(edge-side*0.13,y+0.66,pane_z),glass)
	for rib: float in [-3.85,-1.90,2.05,3.90]:
		_box(Vector3(0.36,height*0.78,0.12),Vector3(x-side*4.60,height*0.40-6.1,z+rib),steel.darkened(0.12))
	var mast := Vector3(x+side*0.68,height-2.43,z-0.52)
	_box(Vector3(0.13,3.3,0.15),mast+Vector3(0,1.65,0),steel)
	_box(Vector3(0.23,0.24,0.24),mast+Vector3(0,3.30,0),Color(0.9,0.18,0.09,0.60))


func _pursuit_overpass(layout: int, steel: Color, hull: Color, frame: Color, lamp: Color) -> void:
	var at := Vector3(3.0,18.0,-5.0)
	var angle := 0.14 if layout == 6 else -0.19
	var turn := Basis(Vector3.UP,angle)
	var rotation := Vector3(0,angle,0)
	_box(Vector3(68,1.36,8.2),at,hull,rotation)
	for z: float in [-3.71,3.71]:
		_box(Vector3(68.0,0.52,0.42),at+turn*Vector3(0,0.74,z),frame,rotation)
		_box(Vector3(67.9,0.36,0.27),at+turn*Vector3(0,-0.69,z),steel,rotation)
	for x: float in [-31.8,-22.0,20.0,31.8]:
		var deck := at+turn*Vector3(x,-0.69,0)
		_box(Vector3(2.1,32.62,2.9),deck-Vector3(0,16.31,0),hull,rotation)
		_box(Vector3(3.2,0.75,7.8),deck-Vector3(0,0.39,0),frame,rotation)
		for side: float in [-1.0,1.0]:
			_beam(deck+Vector3(0,-3.4,0),deck+turn*Vector3(0,-0.42,side*3.5),0.54,steel,0.80)
	for bay in range(12):
		var x := -32.0+5.8*bay
		_box(Vector3(2.90,0.12,0.38),at+turn*Vector3(x,-0.76,2.45),frame,rotation)
		_box(Vector3(2.48,0.049,0.25),at+turn*Vector3(x,-0.84,2.45),lamp,rotation)


func _pursuit_checkpoint(z: float, left_first: bool, steel: Color, frame: Color, amber: Color) -> void:
	var dark := Color("222b35")
	for side in [-1.0,1.0]:
		var foot := Vector3(side*7.35,-0.32,z)
		var knee := Vector3(side*8.2,4.45,z)
		var elbow := Vector3(side*6.25,12.9,z)
		_box(Vector3(2.45,15.0,2.5),foot-Vector3(0,7.4,0),dark)
		_beveled_box(Vector3(2.5,0.62,2.8),foot+Vector3(0,0.31,0),0.18,frame)
		_beam(foot+Vector3(0,0.52,0),knee,1.03,steel,1.28)
		_beam(knee,elbow,1.03,steel,1.28)
		_box(Vector3(1.45,1.04,1.55),knee,frame)
		_box(Vector3(0.10,0.22,1.00),knee-Vector3(side*0.77,0.22,0),amber)
		var sign := -1.0 if left_first else 1.0
		if side == sign:
			_equipment_cabinet(foot+Vector3(side*0.32,0.61,1.95),Vector3(1.42,1.56,1.1),steel,frame,Color(0.22,0.68,0.78,0.63))
			_box(Vector3(1.9,0.22,2.5),foot+Vector3(side*0.25,0.50,1.57),frame)
	_box(Vector3(13.2,0.73,1.55),Vector3(0,13.23,z),steel)
	_box(Vector3(12.2,0.23,0.37),Vector3(0,12.80,z+0.36),dark)
	for x in [-4.25,0.0,4.25]:
		_box(Vector3(1.1,0.28,0.62),Vector3(x,12.72,z),frame)
		_box(Vector3(0.84,0.07,0.44),Vector3(x,12.55,z),amber)

func _tidal_front(layout: int) -> void:
	var hull := Color(Color("303f4d"),0.994)
	var plate := Color(Color("647889"),0.994)
	var galvanised := Color(Color("9aa6a7"),0.994)
	var teal := Color(Color("356a73"),0.994)
	var rust := Color("bd6c3f")
	var lamp := Color(0.96,0.70,0.37,0.64)
	for side in [-1.0,1.0]:
		# The rail, shoulder and longitudinal stringer form one visible edge.
		_box(Vector3(1.25,0.30,10),Vector3(side*5.63,-0.18,-5),plate)
		_box(Vector3(1.32,0.72,10),Vector3(side*5.47,-0.69,-5),hull)
		_box(Vector3(0.24,0.17,10),Vector3(side*5.56,0.66,-5),galvanised)
		for bay in range(4):
			var z := -1.25-float(bay)*2.5
			_beveled_box(Vector3(0.70,0.64,0.95),Vector3(side*5.61,0.29,z),0.12,plate)
			_box(Vector3(0.54,0.13,0.83),Vector3(side*5.57,0.65,z),hull)
			_box(Vector3(0.10,0.22,0.59),Vector3(side*5.23,0.23,z),hull)
			if bay%2 == 0:
				_box(Vector3(0.053,0.116,0.46),Vector3(side*5.17,0.24,z),lamp)
			else:
				for stripe in range(3):
					_box(Vector3(0.05,0.20,0.095),Vector3(side*5.245,0.39,z+float(stripe-1)*0.16),rust,Vector3(0.35,0,0))
			for bolt in [-0.29,0.29]:
				_box(Vector3(0.092,0.08,0.095),Vector3(side*5.25,0.11,z+bolt),galvanised)
			_box(Vector3(0.40,0.03,1.44),Vector3(side*5.25,-0.025,z+0.94),Color("514940"))
			for grate in range(4):
				_box(Vector3(0.35,0.020,0.028),Vector3(side*5.25,-0.016,z+0.44+float(grate)*0.32),hull)
		if layout%2 == 0:
			var foot := Vector3(side*7.35,-10.0,-5)
			var head := Vector3(side*5.73,-0.54,-5)
			_beam(foot,head,1.45,hull,2.50)
			_beveled_box(Vector3(2.8,0.96,3.4),Vector3(side*5.82,-0.92,-5),0.31,plate)
			_box(Vector3(2.05,0.52,2.7),Vector3(side*6.31,-3.88,-5),rust)
			_beam(Vector3(side*6.46,-4.6,-5),Vector3(side*5.5,-0.65,-0.45),0.47,plate,0.56)
			_beam(Vector3(side*6.46,-4.6,-5),Vector3(side*5.5,-0.65,-9.55),0.47,plate,0.56)
		if layout%2 == 0 and (layout%4 == 0) == (side < 0.0):
			var post := Vector3(side*6.03,0,-7.52)
			_beveled_box(Vector3(0.51,0.45,0.62),post+Vector3(0,0.19,0),0.08,hull)
			_box(Vector3(0.23,3.55,0.27),post+Vector3(0,1.96,0),plate)
			_beam(post+Vector3(0,3.7,0),post+Vector3(side*0.81,3.7,0),0.23,hull,0.32)
			_box(Vector3(0.58,0.19,0.45),post+Vector3(side*0.85,3.66,0),hull)
			_box(Vector3(0.43,0.07,0.32),post+Vector3(side*0.85,3.55,0),lamp)
	if layout in [3,17]:
		var side := -1.0 if layout == 3 else 1.0
		var at := Vector3(side*15.5,0,-5)
		_tidal_pump_house(at,side)
		for rail_side: float in [-1.0,1.0]:
			var z := -5.0+rail_side*1.21
			_beam(Vector3(side*5.70,-0.34,z),Vector3(side*9.13,1.25,z),0.25,hull,0.35)
			_beam(Vector3(side*5.9,0.94,z),Vector3(side*9.0,2.44,z),0.08,rust)
			for step in range(5):
				var t := float(step)/4.0
				_box(Vector3(0.12,1.21,0.13),Vector3(side*lerpf(5.88,9.13,t),lerpf(0.42,1.91,t),z),plate)
		for step in range(9):
			_box(Vector3(0.40,0.21,2.30),Vector3(side*(5.90+float(step)*0.38),float(step)*0.177,-5),galvanised)
	if layout in [1,13,22]:
		var side := -1.0 if layout == 13 else 1.0
		var at := Vector3(side*(22.0+float(layout%3)*6.3),-1.05,-5)
		_tidal_radar_pier(at,hull,plate,teal,rust,lamp)
	if layout in [8,20]:
		var at := Vector3(0,0,-5)
		for side in [-1.0,1.0]:
			var foot := at+Vector3(side*6.81,0,0)
			_beveled_box(Vector3(2.27,0.60,2.82),foot+Vector3(0,0.20,0),0.22,plate)
			_beveled_box(Vector3(1.26,15.4,1.68),foot+Vector3(0,6.95,0),0.19,hull)
			_box(Vector3(1.42,0.62,1.85),foot+Vector3(0,3.13,0),rust)
			_beam(foot+Vector3(0,9.73,0),at+Vector3(side*5.34,13.36,0),0.52,plate,1.10)
			_beveled_box(Vector3(1.91,2.16,2.37),foot+Vector3(0,13.50,0),0.25,teal)
			_box(Vector3(0.63,0.35,0.1),foot+Vector3(0,13.75,1.19),lamp)
			for z in [-0.62,0.62]:
				_box(Vector3(1.55,0.15,0.32),foot+Vector3(0,3.79,z),galvanised)
		_beveled_box(Vector3(14.8,1.34,1.95),at+Vector3(0,13.70,0),0.21,plate)
		_box(Vector3(10.81,0.34,1.23),at+Vector3(0,14.52,0),hull)
		for x in [-3.7,1.95]:
			_box(Vector3(2.65,0.11,0.45),at+Vector3(x,12.99,0.32),lamp)
		_pipe_run([at+Vector3(6.40,13.35,1.09),at+Vector3(5.45,13.35,1.09),at+Vector3(5.11,13.99,1.09),at+Vector3(3.91,13.99,1.09)],0.18,rust)
		_guard_rail(at+Vector3(-4.8,14.68,-0.61),at+Vector3(5.16,14.68,-0.61),0.87,rust)
		_tidal_beacon(at+Vector3(6.8,14.58,0),2.12)

func _tidal_pump_house(at: Vector3, side: float) -> void:
	var foundation := Color(Color("303e4b"),0.994)
	var steel := Color(Color("667786"),0.994)
	var teal := Color(Color("3f7380"),0.994)
	var trim := Color(Color("8f9e9d"),0.994)
	var copper := Color("ae683f")
	var gold := Color("c59953")
	var windows := Color(0.74,0.59,0.34,0.77)
	_beveled_box(Vector3(13.9,1.15,13.7),at+Vector3(0,0.83,0),0.57,steel)
	for x in [-5.3,5.3]:
		for z in [-4.85,4.85]:
			var pile := at+Vector3(x,0,z)
			_beam(pile+Vector3(x*0.27,-14.0,z*0.22),pile+Vector3(0,0.65,0),2.05,foundation,2.25)
			_box(Vector3(2.44,0.62,2.53),pile+Vector3(x*0.078,-3.67,z*0.074),teal)
			_box(Vector3(2.35,0.19,2.52),pile+Vector3(x*0.067,-3.23,z*0.061),copper)
		_beam(at+Vector3(x,-5.3,-4.6),at+Vector3(x,-0.01,4.6),0.62,steel,0.78)
	for z in [-4.85,4.85]:
		_beam(at+Vector3(-5.7,-5.21,z),at+Vector3(5.2,0.20,z),0.70,steel,0.90)
		_beam(at+Vector3(5.7,-5.21,z),at+Vector3(-5.2,0.20,z),0.70,steel,0.90)
		_box(Vector3(13.2,0.23,0.62),at+Vector3(0,1.29,z*1.27),foundation)
	for index in range(7):
		var x := float(index-3)*1.83
		_box(Vector3(1.61,0.13,0.11),at+Vector3(x,1.08,6.88),gold if index%3==0 else teal)
		_box(Vector3(0.63,0.14,0.12),at+Vector3(x,0.64,6.89),windows if index%2==0 else foundation)
	_guard_rail(at+Vector3(-6.3,1.41,6.28),at+Vector3(6.3,1.41,6.28),1.08,gold)
	_guard_rail(at+Vector3(side*6.44,1.41,-6.0),at+Vector3(side*6.44,1.41,6.28),1.08,gold)
	var core := at+Vector3(side*1.45,1.4,-1.25)
	_beveled_box(Vector3(7.5,4.9,8.3),core+Vector3(0,2.42,0),0.42,teal)
	_beveled_box(Vector3(8.9,0.55,9.3),core+Vector3(0,4.89,0),0.34,trim)
	_box(Vector3(6.9,0.32,7.3),core+Vector3(0,5.26,0),foundation)
	for bay in [-2.31,0.0,2.31]:
		var panel := core+Vector3(bay,2.25,4.20)
		_beveled_box(Vector3(2.10,3.82,0.15),panel,0.07,steel.darkened(0.20))
		_box(Vector3(1.99,0.10,0.14),panel+Vector3(0,1.55,0.08),teal.lightened(0.13))
		for fastener in [-0.83,0.83]:
			_box(Vector3(0.12,0.19,0.08),panel+Vector3(fastener,1.32,0.10),trim)
			_box(Vector3(0.12,0.19,0.08),panel+Vector3(fastener,-1.63,0.10),trim)
		_box(Vector3(0.81,0.53,0.10),panel+Vector3(0.36,-1.08,0.06),foundation)
		for stripe in range(3):
			_box(Vector3(0.113,0.28,0.04),panel+Vector3(0.13+float(stripe)*0.22,-1.07,0.127),copper,Vector3(0,0,0.46))
		_box(Vector3(0.12,0.51,0.16),panel+Vector3(-0.58,0.12,0.08),foundation)
	for vent_bay in range(3):
		var at_vent := core+Vector3(-side*3.79,2.47,float(vent_bay-1)*2.23)
		_box(Vector3(0.10,2.68,1.80),at_vent,foundation)
		for slat in range(6):
			_box(Vector3(0.18,0.12,1.53),at_vent+Vector3(-side*0.063,-0.97+float(slat)*0.38,0),steel,Vector3(0,0,side*0.15))
		_box(Vector3(0.19,0.11,1.93),at_vent+Vector3(-side*0.03,1.4,0),trim)
	for z in [-3.51,3.56]:
		_pipe_run([core+Vector3(-side*3.99,0.08,z),core+Vector3(-side*3.99,4.24,z),core+Vector3(-side*4.27,4.64,z),core+Vector3(-side*4.27,5.1,z)],0.24,copper)
		for y in [0.42,2.27,4.21]:
			_box(Vector3(0.48,0.13,0.48),core+Vector3(-side*3.94,y,z),trim)
	for module in [-1.0,1.0]:
		_equipment_cabinet(at+Vector3(side*2.73*module,1.45,4.5),Vector3(1.88,1.56,1.64),steel,trim,Color(0.25,0.55,0.56,0.82))
	var cabin := core+Vector3(-side*1.20,5.85,-0.21)
	_box(Vector3(2.71,1.1,2.62),cabin-Vector3(0,0.60,0),foundation)
	_beveled_box(Vector3(5.53,1.73,4.15),cabin+Vector3(0,0.71,0),0.38,foundation)
	_beveled_box(Vector3(6.01,0.25,4.59),cabin+Vector3(0,1.66,0),0.39,trim)
	_box(Vector3(0.075,0.69,3.32),cabin+Vector3(-side*2.79,0.96,0),windows)
	_box(Vector3(4.70,0.69,0.075),cabin+Vector3(0,0.96,2.10),windows)
	for bay in range(5):
		_box(Vector3(0.13,0.95,0.09),cabin+Vector3(-side*2.825,0.96,float(bay-2)*0.78),steel)
		_box(Vector3(0.09,0.95,0.13),cabin+Vector3(float(bay-2)*1.05,0.96,2.135),steel)
	_guard_rail(core+Vector3(-side*3.64,5.2,-4.15),core+Vector3(-side*3.64,5.2,4.16),0.81,gold)
	_tidal_beacon(cabin+Vector3(side*1.56,1.78,-1.34),2.25)
	for z in [-6.37,6.37]:
		_box(Vector3(3.4,0.16,0.42),at+Vector3(0,1.19,z),teal)

func _tidal_beacon(at: Vector3, height: float) -> void:
	var iron := Color("313c47")
	_box(Vector3(0.5,0.18,0.51),at+Vector3(0,0.09,0),iron)
	_box(Vector3(0.16,height,0.18),at+Vector3(0,height*0.5,0),iron)
	_box(Vector3(0.48,0.10,0.43),at+Vector3(0,height-0.09,0),iron)
	_box(Vector3(0.32,0.25,0.34),at+Vector3(0,height+0.075,0),Color(0.91,0.29,0.12,0.59))
	_box(Vector3(0.41,0.08,0.39),at+Vector3(0,height+0.21,0),iron)

func _tidal_radar_pier(at: Vector3, hull: Color, plate: Color, teal: Color, rust: Color, lamp: Color) -> void:
	_beveled_box(Vector3(9.8,0.78,7.2),at,0.45,plate)
	for x in [-3.63,3.63]:
		for z in [-2.61,2.61]:
			_beam(at+Vector3(x*1.22,-12,z*1.12),at+Vector3(x,0,z),1.25,hull,1.52)
		_beam(at+Vector3(x,-4.5,-2.6),at+Vector3(x,-0.15,2.6),0.46,plate)
	_guard_rail(at+Vector3(-4.4,0.40,3.17),at+Vector3(4.4,0.40,3.17),0.93,rust)
	_beveled_box(Vector3(4.2,2.45,3.8),at+Vector3(0,1.58,-0.72),0.25,teal)
	_box(Vector3(4.48,0.27,4.14),at+Vector3(0,2.91,-0.72),plate)
	_box(Vector3(2.7,0.42,0.08),at+Vector3(0,2.1,1.23),lamp)
	for bay in [-0.81,0.0,0.81]: _box(Vector3(0.09,0.65,0.11),at+Vector3(bay,2.1,1.27),hull)
	_tidal_beacon(at+Vector3(1.31,3.04,-1.93),3.14)

func _orbital_berth(layout: int) -> void:
	# The runway, two continuous service walkways, and the lower station
	# spine share overlapping cross-sections at every tile boundary.
	_box(Vector3(13.0,1.85,10),Vector3(0,-1.08,-5),ORBITAL_FRAME)
	_box(Vector3(10.9,2.25,10),Vector3(0,-3.05,-5),ORBITAL_INSET)
	for side: float in [-1.0,1.0]:
		_box(Vector3(2.85,0.62,10),Vector3(side*6.52,-0.39,-5),ORBITAL_ARMOR)
		_box(Vector3(0.60,0.50,10),Vector3(side*5.43,0.15,-5),ORBITAL_FRAME)
		_box(Vector3(0.66,0.14,10),Vector3(side*5.43,0.40,-5),ORBITAL_STEEL)
		_box(Vector3(0.16,0.075,10),Vector3(side*5.24,0.49,-5),ORBITAL_BRASS)
		_box(Vector3(0.17,0.12,10),Vector3(side*7.87,-0.04,-5),ORBITAL_STEEL)
		_box(Vector3(0.12,0.11,10),Vector3(side*7.72,0.51,-5),ORBITAL_ARMOR)
		_box(Vector3(0.075,0.07,10),Vector3(side*7.72,0.25,-5),ORBITAL_STEEL)
		for z: float in [-1.1,-5.0,-8.9]:
			_box(Vector3(0.67,0.79,0.46),Vector3(side*5.43,0.25,z),ORBITAL_STEEL)
			_box(Vector3(0.10,0.21,0.27),Vector3(side*5.08,0.46,z),ORBITAL_BRASS)
			_box(Vector3(0.31,0.65,0.33),Vector3(side*7.72,0.22,z),ORBITAL_ARMOR)
			_beam(Vector3(side*5.5,-3.08,z),Vector3(side*7.68,-0.42,z),0.40,ORBITAL_STEEL,0.48)
		for z: float in [-3.1,-6.9]:
			_box(Vector3(0.10,0.27,1.62),Vector3(side*5.12,0.10,z),ORBITAL_INSET)
			_box(Vector3(0.04,0.105,1.37),Vector3(side*5.055,0.12,z),ORBITAL_AMBER)
			_box(Vector3(1.32,0.025,2.6),Vector3(side*6.64,-0.067,z),ORBITAL_FRAME)
			for lug in range(4):
				_box(Vector3(1.2,0.031,0.085),Vector3(side*6.64,-0.051,z-0.91+float(lug)*0.60),ORBITAL_STEEL)
	if layout in [1,2,3,9,10,14,16,17,22]:
		_orbital_hangar(-1.0 if layout in [1,2,9,14,16] else 1.0,layout)
	if layout in [5,12,19]:
		_orbital_control_tower(-1.0 if layout == 12 else 1.0)
	if layout in [4,13,21]:
		_orbital_dock_ring(layout)
	if layout in [6,7,8,15,18,20,23]:
		_orbital_transfer_deck(-1.0 if layout in [8,15,20] else 1.0,layout)

func _orbital_transfer_deck(side: float, layout: int) -> void:
	# The lower freight line is visible between hangars and remains
	# connected under the catwalk even where there is no full upper bay.
	_box(Vector3(14.9,0.78,9.7),Vector3(side*12.62,-0.42,-5),ORBITAL_ARMOR)
	_box(Vector3(11.6,0.51,9.5),Vector3(side*13.7,-3.90,-5),ORBITAL_FRAME)
	for z: float in [-1.0,-9.0]:
		_beam(Vector3(side*5.3,-3.35,z),Vector3(side*9.0,-3.85,z),0.49,ORBITAL_STEEL,0.72)
		_beam(Vector3(side*8.5,-0.59,z),Vector3(side*18.7,-3.90,z),0.54,ORBITAL_ARMOR,0.78)
		_beam(Vector3(side*8.9,-3.84,z),Vector3(side*18.8,-0.55,z),0.52,ORBITAL_STEEL,0.66)
	_guard_rail(Vector3(side*19.84,-0.03,-9.55),Vector3(side*19.84,-0.03,-0.45),0.94,ORBITAL_BRASS)
	for z: float in [-1.85,-5.3,-7.9]:
		var w := 2.65 if layout%3 == 1 else 1.94
		var h := 1.30+float(posmod(layout+roundi(z),3))*0.29
		var at := Vector3(side*17.60,h*0.5-0.045,z)
		_beveled_box(Vector3(w,h,1.55),at,0.17,ORBITAL_FRAME)
		for edge: float in [-0.65,0.65]:
			_box(Vector3(w+0.16,h+0.10,0.20),at+Vector3(0,0,edge),ORBITAL_STEEL)
			_box(Vector3(0.12,0.13,0.24),at+Vector3(-side*(w*0.5+0.04),-0.23,edge),ORBITAL_BRASS)
		_box(Vector3(0.10,0.17,0.49),at+Vector3(-side*w*0.5,0.13,-0.08),ORBITAL_VIOLET)

func _orbital_hangar(side: float, layout: int) -> void:
	# Full cross-bracing carries the hangar apron back to the runway spine.
	_box(Vector3(12,0.83,9.82),Vector3(side*12.85,-0.67,-5),ORBITAL_ARMOR)
	_box(Vector3(12,1.05,9.7),Vector3(side*11.9,-6.0,-5),ORBITAL_FRAME)
	for z: float in [-1.22,-8.78]:
		_box(Vector3(1.85,6.1,1.62),Vector3(side*17.5,-3.30,z),ORBITAL_ARMOR)
		_beam(Vector3(side*5.2,-3.3,z),Vector3(side*7.0,-5.95,z),0.63,ORBITAL_STEEL,0.68)
		_beam(Vector3(side*6.4,-5.85,z),Vector3(side*17.6,-0.63,z),0.82,ORBITAL_STEEL,0.90)
		_beam(Vector3(side*6.4,-0.64,z),Vector3(side*17.6,-5.77,z),0.52,ORBITAL_FRAME,0.70)
		_beveled_box(Vector3(2.3,7.2,1.64),Vector3(side*13.6,3.1,z),0.21,ORBITAL_STEEL)
		_beam(Vector3(side*11.1,-0.2,z),Vector3(side*13.5,5.55,z),0.76,ORBITAL_ARMOR,0.96)
		_box(Vector3(0.15,1.02,1.20),Vector3(side*12.36,1.62,z),ORBITAL_BRASS)
	_box(Vector3(6.15,0.95,9.22),Vector3(side*15.7,6.56,-5),ORBITAL_ARMOR)
	_box(Vector3(6.6,0.33,9.38),Vector3(side*15.7,7.07,-5),ORBITAL_STEEL)
	_box(Vector3(0.48,6.53,7.78),Vector3(side*18.59,2.99,-5),ORBITAL_FRAME)
	_box(Vector3(0.19,0.22,5.7),Vector3(side*12.55,6.30,-5),ORBITAL_AMBER)
	_box(Vector3(0.23,0.20,5.40),Vector3(side*18.28,5.45,-5),ORBITAL_VIOLET)
	for joint in range(5):
		var z := -2.14-float(joint)*1.42
		_box(Vector3(0.19,0.46,0.12),Vector3(side*12.59,6.52,z),ORBITAL_STEEL)
		_box(Vector3(0.18,3.45,0.26),Vector3(side*18.27,2.86,z),ORBITAL_ARMOR)
		_box(Vector3(0.14,0.25,0.91),Vector3(side*18.32,1.02,z),ORBITAL_STEEL)
	for height: float in [0.57,3.57]:
		_box(Vector3(0.32,0.15,7.33),Vector3(side*18.36,height,-5),ORBITAL_ARMOR)
	for z: float in [-3.13,-6.84]:
		_equipment_cabinet(Vector3(side*16.65,-0.25,z),Vector3(1.62,2.25,1.50),ORBITAL_ARMOR,ORBITAL_STEEL,ORBITAL_VIOLET)
	if layout%3 == 1:
		_guard_rail(Vector3(side*13.1,7.23,-8.8),Vector3(side*13.1,7.23,-1.2),0.90,ORBITAL_BRASS)
		for z: float in [-2.6,-5.8,-7.4]:
			_box(Vector3(1.42,0.90,1.32),Vector3(side*15.4,7.62,z),ORBITAL_FRAME)
			_box(Vector3(1.53,0.19,1.42),Vector3(side*15.4,8.07,z),ORBITAL_STEEL)

func _orbital_control_tower(side: float) -> void:
	_box(Vector3(14.0,1.05,9.85),Vector3(side*12.12,-0.73,-5),ORBITAL_FRAME)
	_box(Vector3(11.6,1.2,9.52),Vector3(side*11.78,-7.8,-5),ORBITAL_ARMOR)
	_beveled_box(Vector3(4.65,17.9,6.9),Vector3(side*14.4,1.65,-5),0.46,ORBITAL_ARMOR)
	_box(Vector3(1.15,16.6,7.52),Vector3(side*16.15,2.22,-5),ORBITAL_STEEL)
	for z: float in [-2.35,-7.65]:
		_beam(Vector3(side*5.2,-3.3,z),Vector3(side*8.1,-7.68,z),0.82,ORBITAL_STEEL,0.96)
		_beam(Vector3(side*8.0,-7.72,z),Vector3(side*13.4,8.65,z),0.93,ORBITAL_FRAME,1.24)
		_beam(Vector3(side*11.18,-0.60,z),Vector3(side*13.40,10.2,z),0.48,ORBITAL_STEEL,0.54)
		_box(Vector3(0.17,0.35,0.63),Vector3(side*12.04,6.55,z),Color(0.82,0.18,0.22,0.68))
		for collar: float in [1.10,3.80,8.20]:
			_box(Vector3(0.17,0.38,1.03),Vector3(side*12.07,collar,z),ORBITAL_STEEL)
	_box(Vector3(0.21,5.65,2.04),Vector3(side*12.04,3.55,-5),ORBITAL_FRAME)
	for slot in range(7):
		_box(Vector3(0.12,0.13,1.63),Vector3(side*11.93,1.35+float(slot)*0.56,-5),ORBITAL_STEEL)
	_box(Vector3(0.10,0.15,0.53),Vector3(side*11.91,5.63,-4.62),ORBITAL_VIOLET)
	_beveled_box(Vector3(8.15,0.93,7.9),Vector3(side*13.08,10.60,-5),0.34,ORBITAL_STEEL)
	_beveled_box(Vector3(7.16,2.22,6.81),Vector3(side*13.22,11.90,-5),0.48,ORBITAL_FRAME)
	_beveled_box(Vector3(8.22,0.46,7.7),Vector3(side*13.08,13.22,-5),0.41,ORBITAL_STEEL)
	_box(Vector3(0.16,1.05,5.45),Vector3(side*9.60,11.96,-5),ORBITAL_AMBER)
	_box(Vector3(6.04,0.92,0.17),Vector3(side*13.2,11.97,-1.57),ORBITAL_AMBER)
	for bar in range(6):
		_box(Vector3(0.22,1.35,0.13),Vector3(side*9.47,11.94,-7.6+float(bar)*1.04),ORBITAL_STEEL)
		_box(Vector3(0.13,1.32,0.24),Vector3(side*(10.7+float(bar)),11.94,-1.47),ORBITAL_ARMOR)
	_guard_rail(Vector3(side*10.1,10.92,-8.83),Vector3(side*16.18,10.92,-8.83),0.65,ORBITAL_BRASS)
	for mast: Vector2 in [Vector2(12.0,-4.7),Vector2(15.5,-5.9)]:
		var height := 3.4 if mast.x < 13.0 else 5.8
		_box(Vector3(0.32,height,0.32),Vector3(side*mast.x,13.4+height*0.5,mast.y),ORBITAL_STEEL)
		_box(Vector3(0.43,0.27,0.43),Vector3(side*mast.x,13.4+height,mast.y),Color(0.92,0.19,0.24,0.68))

func _orbital_dock_ring(layout: int) -> void:
	var outer := 34.0 if layout != 13 else 31.4
	var inner := outer-2.80
	var base_y := 2.65
	_box(Vector3(outer*2.0+2.0,2.1,8.4),Vector3(0,-9.75,-5),ORBITAL_FRAME)
	_box(Vector3(12.6,7.2,8.2),Vector3(0,-5.68,-5),ORBITAL_ARMOR)
	for side: float in [-1.0,1.0]:
		var foot := side*(inner+outer)*0.5
		_beveled_box(Vector3(3.62,14.25,5.9),Vector3(foot,-4.37,-5),0.35,ORBITAL_ARMOR)
		_box(Vector3(4.03,1.10,6.2),Vector3(foot,-8.61,-5),ORBITAL_STEEL)
		_box(Vector3(4.21,0.42,6.25),Vector3(foot,1.52,-5),ORBITAL_BRASS)
		_beam(Vector3(side*14.8,-9.38,-5),Vector3(foot,-3.1,-5),0.9,ORBITAL_STEEL,3.0)
		for section in range(14):
			var a := float(section)*0.102
			var b := float(section+1)*0.102
			_orbital_arc_panel(side,a,b,inner,outer,base_y,-7.0,-3.0,ORBITAL_ARMOR.lightened(float(section%3)*0.045))
			_orbital_arc_panel(side,a+0.008,b-0.008,inner+0.48,outer-0.31,base_y,-3.04,-2.64,ORBITAL_STEEL)
			if section%3 != 2:
				_orbital_arc_panel(side,a+0.014,b-0.015,inner+0.18,inner+0.46,base_y,-3.02,-2.84,ORBITAL_AMBER)
		_orbital_arc_panel(side,1.421,1.454,inner-0.11,outer+0.16,base_y,-7.28,-2.34,ORBITAL_FRAME)
		_orbital_arc_panel(side,1.443,1.458,inner+0.34,outer-0.28,base_y,-6.76,-2.52,ORBITAL_VIOLET)

func _orbital_arc_panel(side: float, a: float, b: float, inner: float, outer: float, height: float, z_back: float, z_front: float, tint: Color) -> void:
	var p := PackedVector3Array()
	for z in [z_back,z_front]:
		p.append(Vector3(side*cos(a)*inner,height+sin(a)*inner,z))
		p.append(Vector3(side*cos(a)*outer,height+sin(a)*outer,z))
		p.append(Vector3(side*cos(b)*outer,height+sin(b)*outer,z))
		p.append(Vector3(side*cos(b)*inner,height+sin(b)*inner,z))
	for indices in [[0,1,2,3],[4,7,6,5],[0,4,5,1],[3,2,6,7],[0,3,7,4],[1,5,6,2]]:
		var i := indices as Array
		if side > 0.0: _orbital_facet(p[i[0]],p[i[3]],p[i[2]],p[i[1]],tint)
		else: _orbital_facet(p[i[0]],p[i[1]],p[i[2]],p[i[3]],tint)

func _orbital_facet(a: Vector3, b: Vector3, c: Vector3, d: Vector3, tint: Color) -> void:
	_face(a,b,c,d,(b-a).cross(c-a).normalized(),tint)

func _panel(at: Vector3, size: Vector3, color: Color, lip: float) -> void:
	_box(size,at,color)
	for side in [-1.0,1.0]:
		_box(Vector3(size.x+lip,0.06,size.z+lip),at+Vector3(0,side*size.y*0.44,0),color.lightened(0.10))

func _beveled_box(size: Vector3, at: Vector3, bevel: float, color: Color) -> void:
	# A single closed stepped perimeter avoids overlapping coplanar box faces.
	var b := minf(bevel,minf(size.x,size.z)*0.40)
	var x := size.x*0.5
	var z := size.z*0.5
	var ring: Array[Vector2] = [Vector2(-x+b,-z),Vector2(x-b,-z),Vector2(x-b,-z+b),Vector2(x,-z+b),Vector2(x,z-b),Vector2(x-b,z-b),Vector2(x-b,z),Vector2(-x+b,z),Vector2(-x+b,z-b),Vector2(-x,z-b),Vector2(-x,-z+b),Vector2(-x+b,-z+b)]
	for index in range(ring.size()):
		var a := at+Vector3(ring[index].x,-size.y*0.5,ring[index].y)
		var c := at+Vector3(ring[(index+1)%ring.size()].x,-size.y*0.5,ring[(index+1)%ring.size()].y)
		var normal := Vector3(c.z-a.z,0,a.x-c.x).normalized()
		_face(a,c,c+Vector3(0,size.y,0),a+Vector3(0,size.y,0),normal,color)
		_triangle(at+Vector3(0,size.y*0.5,0),a+Vector3(0,size.y,0),c+Vector3(0,size.y,0),Vector3.UP,color)
		_triangle(at-Vector3(0,size.y*0.5,0),c,a,Vector3.DOWN,color)

func _build_crossing() -> void:
	_clear_geometry()
	var steel := Color("6e747b")
	var dark := Color("353d45")
	var edge := Color("a0a8a6")
	var lamp := Color(0.88,0.61,0.32,0.56)
	var length := CROSSING_HALF_SPAN*2.0
	# The normal DeckReceiver is the walking surface for the entire crossing.
	# The causeway carries it from below and joins the district rails at both ends.
	_box(Vector3(10.50,0.51,length),Vector3(0,-0.55,0),dark)
	for side in [-1.0,1.0]:
		_box(Vector3(0.56,0.42,length),Vector3(side*5.48,-0.19,0),dark)
		_box(Vector3(0.13,0.12,length),Vector3(side*5.55,0.68,0),edge)
		_box(Vector3(0.48,0.38,length),Vector3(side*5.45,-3.24,0),steel)
		for bay in range(10):
			var z := -30.0+6.0*bay
			var top := Vector3(side*5.50,-0.35,z)
			_beam(top,Vector3(side*5.50,-3.22,z+3.0),0.29,steel,0.32)
			_beam(Vector3(side*5.50,-3.22,z+3.0),top+Vector3(0,0,6),0.29,steel,0.32)
			_box(Vector3(0.31,0.75,0.26),Vector3(side*5.55,0.32,z),steel)
			_box(Vector3(0.10,0.16,0.20),Vector3(side*5.38,0.48,z),lamp)
		for z in [-25.5,0.0,25.5]:
			_beveled_box(Vector3(2.25,2.0,2.8),Vector3(side*6.42,-2.32,z),0.19,dark)
			_beam(Vector3(side*6.52,-3.2,z),Vector3(side*8.7,-14.0,z),0.65,steel,0.9)
			_box(Vector3(2.0,0.24,2.6),Vector3(side*6.55,-1.24,z),edge)
		for z in [-25.5,25.5]:
			_box(Vector3(1.48,0.39,2.6),Vector3(side*6.18,0.06,z),dark)
			var mast := Vector3(side*6.64,0.23,z)
			_beveled_box(Vector3(0.7,4.1,0.78),mast+Vector3(0,2.0,0),0.13,steel)
			_box(Vector3(1.0,0.18,0.82),mast+Vector3(-side*0.33,4.0,0),edge)
			_box(Vector3(0.71,0.08,0.54),mast+Vector3(-side*0.44,3.87,0),lamp)
	var bridge_material: ShaderMaterial = _surface.duplicate()
	bridge_material.set_shader_parameter("clip_mode",0)
	_standard_crossing = _commit_geometry()
	_corridor = _instance(self,"WorldRelayOpenCauseway",_standard_crossing,bridge_material)
	for target in [2,3,4]:
		_build_industrial_exit(target)
		_industrial_exits[target] = _commit_geometry()
	_build_shore_join(bridge_material)

func _build_industrial_exit(target: int) -> void:
	_clear_geometry()
	var steel := Color("596470")
	var frame := Color("38444d")
	var brass := Color("9b7950")
	var light := Color(0.79,0.62,0.37,0.63)
	var destination := {2:Color("878787"),3:Color("43596b"),4:Color("4c6871")}
	var end_trim: Color = destination[target]
	# One deck structure below the running surface. The south and north
	# abutments reach the whole first and last tile instead of ending in air.
	_box(Vector3(10.5,0.48,88),Vector3(0,-0.50,11.0),frame)
	for side: float in [-1.0,1.0]:
		_box(Vector3(0.69,0.46,87.5),Vector3(side*5.63,-0.17,11.25),frame)
		_box(Vector3(0.22,0.16,39.8),Vector3(side*5.68,0.60,33.9),steel)
		_box(Vector3(0.22,0.16,47.2),Vector3(side*5.68,0.60,-9.55),end_trim)
		for bay in range(18):
			var z := 52.0-4.9*bay
			var blend := 1.0-smoothstep(-26.0,44.0,z)
			var trim := steel.lerp(end_trim,blend)
			_box(Vector3(0.44,0.70,0.39),Vector3(side*5.67,0.27,z),trim)
			_box(Vector3(0.08,0.12,0.28),Vector3(side*5.41,0.31,z),light)
			if bay%2 == 0:
				_box(Vector3(0.39,0.45,7.0),Vector3(side*5.64,-2.62,z-3.5),frame)
				_beam(Vector3(side*5.64,-0.36,z),Vector3(side*5.64,-2.58,z-3.5),0.26,trim,0.32)
				_beam(Vector3(side*5.64,-2.58,z-3.5),Vector3(side*5.64,-0.36,z-7.0),0.26,trim,0.32)
		for z: float in [43,14,-15,-29]:
			_box(Vector3(1.70,15.8,2.75),Vector3(side*7.16,-8.2,z),frame)
			_beam(Vector3(side*5.63,-1.08,z),Vector3(side*7.15,-5.9,z),0.51,steel,0.81)
		# The first service bay keeps the industrial conduit and dark steel.
		# It shares a foundation with the new district's furniture behind it.
		_box(Vector3(5.4,0.40,23),Vector3(side*8.58,-0.29,33.7),frame)
		for z: float in [24,42]:
			_box(Vector3(3.2,0.32,3.6),Vector3(side*8.2,-0.12,z),steel)
			_equipment_cabinet(Vector3(side*8.17,0.04,z),Vector3(1.48,2.18,1.50),frame,steel,light)
		_pipe_run([Vector3(side*9.42,0.1,44),Vector3(side*9.42,2.45,44),Vector3(side*9.42,2.45,22.2),Vector3(side*9.42,0.1,22.2)],0.24,brass)
		if target == 2:
			_exit_to_ink(side,end_trim,frame)
		elif target == 3:
			_exit_to_city(side,end_trim,frame,light,brass)
		else:
			_exit_to_sea(side,end_trim,frame,light)
	if target == 2:
		_mountain_gate(Vector3(0,0,-19),Color("303030"),end_trim,Color("a32924"))
	elif target == 3:
		_pursuit_checkpoint(-18.0,true,end_trim,steel,light)
	else:
		_build_port_gantry(-19.0,end_trim,frame,light)

func _exit_to_ink(side: float, stone: Color, steel: Color) -> void:
	var ink := Color("313131")
	var red := Color("a32924")
	_box(Vector3(6.4,0.46,40),Vector3(side*8.97,-0.31,-5),stone.darkened(0.13))
	_box(Vector3(19.0,3.5,81.0),Vector3(side*19.5,-13.6,8.5),stone.darkened(0.27))
	for ridge in range(3):
		var z := 22.5-20.0*ridge+(4.7 if side > 0 else -2.5)
		_karst(Vector3(side*(20.2+ridge*1.8),-12.0,z),Vector3(12.1+ridge*1.75,14.9+ridge*2.8,17.7),stone.darkened(0.22-0.05*ridge),61+ridge+int(side))
	for z: float in [12,2,-11,-23]:
		_box(Vector3(3.55,13.9,3.80),Vector3(side*8.1,-7.22,z),stone.darkened(0.26))
		_box(Vector3(0.8,0.24,0.80),Vector3(side*7.5,0.02,z),steel)
		_stone_lantern(Vector3(side*7.5,0.13,z),stone,ink)
	for z: float in [6,-8,-19]:
		var foot := Vector3(side*10.1,-0.08,z)
		for stem in range(3):
			var at := foot+Vector3(side*0.34*stem,0,0.5*stem)
			var tip := at+Vector3(side*0.28,3.9+0.77*stem,0.24)
			_beam(at,tip,0.13,ink)
			for branch in range(2):
				var joint := at.lerp(tip,0.57+0.22*branch)
				var leaf := joint+Vector3(-side*(1.25+0.4*branch),0.48,0.58)
				_beam(joint,leaf,0.045,ink)
				_leaf(leaf,leaf+Vector3(side*0.58,-0.32,0.2),ink)
	_box(Vector3(1.52,0.68,10.9),Vector3(side*10.56,0.18,3.0),stone)
	for z: float in [-1.7,7.7]:
		_box(Vector3(0.43,3.05,0.46),Vector3(side*10.56,1.7,z),ink)
	_box(Vector3(1.85,0.35,10.5),Vector3(side*10.56,3.21,3.0),ink)
	_roof(Vector3(side*10.56,3.37,3.0),Vector2(1.75,5.3),0.71,ink,stone)
	_banner(Vector3(side*9.64,2.92,7.45),1.82,red,stone)

func _exit_to_city(side: float, steel: Color, frame: Color, light: Color, rail: Color) -> void:
	_box(Vector3(7.5,0.48,38.0),Vector3(side*9.25,-0.29,-6.0),steel)
	_box(Vector3(4.7,16.0,33.0),Vector3(side*11.5,-8.2,-6.5),frame)
	_box(Vector3(12.0,0.7,45),Vector3(side*16.4,-14.85,2.5),frame)
	for index in range(3):
		var z := 11.8-float(index)*11.8+side*2.1
		var h := 8.2+float(index)*3.7
		var at := Vector3(side*(16.8+float(index%2)*2.0),-14.45,z)
		_beveled_box(Vector3(6.8,h,8.2),at+Vector3(0,h*0.5,0),0.52,frame)
		_box(Vector3(7.25,0.44,8.48),at+Vector3(0,h,0),steel)
		for bay in range(3):
			_box(Vector3(0.16,0.35,1.5),at+Vector3(-side*3.44,h-1.38,-2.15+bay*2.13),Color(0.23,0.44,0.56,0.76))
	for z: float in [12,1,-10,-21]:
		var at := Vector3(side*7.05,-0.06,z)
		var head := at+Vector3(side*3.2,4.18,0)
		_box(Vector3(1.2,0.25,1.2),at+Vector3(0,0.12,0),frame)
		_beam(at+Vector3(0,0.24,0),head,0.65,steel,0.86)
		_box(Vector3(0.20,0.14,0.64),at+Vector3(side*1.4,1.96,0.43),light)
	_box(Vector3(6.35,0.49,33),Vector3(side*10.23,4.17,-5.2),frame)
	_guard_rail(Vector3(side*7.2,4.44,-21.5),Vector3(side*7.2,4.44,11.1),0.88,rail)
	for z: float in [7,-3,-12,-20]:
		_equipment_cabinet(Vector3(side*10.4,-0.05,z),Vector3(1.6,2.25,1.50),frame,steel,Color(0.24,0.57,0.66,0.78))
		_box(Vector3(0.64,0.11,1.35),Vector3(side*7.9,3.89,z),light)

func _exit_to_sea(side: float, steel: Color, frame: Color, light: Color) -> void:
	_box(Vector3(5.8,0.46,29.0),Vector3(side*8.55,-0.30,1.0),steel)
	for z: float in [12,2,-8,-22]:
		_box(Vector3(1.56,13.2,1.65),Vector3(side*9.33,-6.90,z),frame)
		_beam(Vector3(side*9.33,-4.5,z),Vector3(side*6.2,-0.4,z),0.41,steel,0.65)
		var post := Vector3(side*7.4,-0.07,z)
		_box(Vector3(0.23,3.2,0.28),post+Vector3(0,1.6,0),frame)
		_box(Vector3(0.78,0.16,0.36),post+Vector3(-side*0.24,3.15,0),steel)
		_box(Vector3(0.54,0.06,0.24),post+Vector3(-side*0.31,3.06,0),light)
	for z: float in [7,-8]:
		_equipment_cabinet(Vector3(side*9.62,-0.07,z),Vector3(1.90,2.5,2.2),frame,steel,light)

func _build_port_gantry(z: float, steel: Color, frame: Color, light: Color) -> void:
	for side: float in [-1.0,1.0]:
		var base := Vector3(side*7.16,-0.32,z)
		_box(Vector3(2.6,1.1,2.4),base+Vector3(0,0.37,0),steel)
		_box(Vector3(1.24,12.64,1.46),base+Vector3(0,6.62,0),frame)
		_beam(base+Vector3(0,9.36,0),Vector3(side*4.8,12.2,z),0.56,steel,0.78)
	_box(Vector3(15.65,0.64,1.55),Vector3(0,12.58,z),steel)
	for x: float in [-4.0,0.0,4.0]:
		_box(Vector3(1.42,0.17,0.56),Vector3(x,12.24,z),frame)
		_box(Vector3(1.12,0.066,0.42),Vector3(x,12.14,z),light)

func _build_shore_join(material: Material) -> void:
	_clear_geometry()
	var concrete := Color(Color("586777"),0.994)
	var base := Color(Color("394755"),0.994)
	var trim := Color(Color("86969d"),0.994)
	var paint := Color("ad6d43")
	var light := Color(0.91,0.69,0.40,0.72)
	# Positive local Z is the dry district. The seaward toe reaches under
	# the crest-suppressed strip, while the recessed apron supports fittings.
	for side: float in [-1.0,1.0]:
		_box(Vector3(65.0,12.0,39.0),Vector3(side*37.75,-6.38,19.35),base)
		_box(Vector3(252.0,11.0,28.0),Vector3(side*196.10,-6.75,13.78),concrete.darkened(0.19))
		_box(Vector3(252.0,0.32,5.5),Vector3(side*196.10,-0.96,2.36),trim.darkened(0.19))
		for pier in range(14):
			var x := side*(7.60+4.53*float(pier))
			var top := 0.53-float(pier%4)*0.11
			var shade := concrete.darkened(float(pier%3)*0.045)
			_box(Vector3(4.5,8.7,1.38),Vector3(x,top-4.35,-0.42),shade)
			_box(Vector3(4.51,0.17,1.67),Vector3(x,top+0.07,-0.44),trim)
			_box(Vector3(4.5,0.62,0.73),Vector3(x,-2.71,-1.15),shade.darkened(0.18))
			_beam(Vector3(x,-5.66,-2.28),Vector3(x,top-0.55,-0.89),0.67,base,1.10)
			_box(Vector3(0.30,1.44,0.16),Vector3(x+side*1.64,-0.83,-1.12),base)
			if pier < 5:
				_box(Vector3(0.77,0.13,0.12),Vector3(x,top-0.29,-1.16),light)
				for stripe in range(3):
					_box(Vector3(0.11,0.22,0.04),Vector3(x+side*(0.77+float(stripe)*0.21),top-0.38,-1.125),paint,Vector3(0,0,side*0.34))
		_box(Vector3(24.4,0.29,16.6),Vector3(side*17.52,-0.37,8.34),concrete)
		for panel in range(7):
			var x := side*(8.6+float(panel)*2.97)
			_box(Vector3(2.91,0.06,10.8),Vector3(x,-0.214,8.12),base.lightened(float(panel%3)*0.055))
			_box(Vector3(0.19,0.025,10.2),Vector3(x+side*0.95,-0.17,8.08),trim)
			_box(Vector3(0.78,0.032,0.23),Vector3(x,-0.168,12.11),paint)
		_guard_rail(Vector3(side*6.91,-0.20,1.45),Vector3(side*6.91,-0.20,12.7),0.84,trim)
		_guard_rail(Vector3(side*8.4,-0.20,2.24),Vector3(side*28.8,-0.20,2.24),0.88,paint)
		for x in [10.8,17.6,24.4]:
			var at := Vector3(side*x,-0.19,4.85)
			_equipment_cabinet(at,Vector3(1.2,1.22,1.18),base,trim,light)
		for x in [12.6,22.9]:
			var at := Vector3(side*x,-0.19,7.75)
			_box(Vector3(2.30,0.15,2.2),at+Vector3(0,0.07,0),base)
			_voxel_drum(at+Vector3(-0.52,0.14,0),0.34,0.95,base,trim)
			_voxel_drum(at+Vector3(0.52,0.14,0),0.34,0.95,base,trim)
			_pipe_run([at+Vector3(-0.52,0.87,0),at+Vector3(-0.52,1.27,0),at+Vector3(0.52,1.27,0),at+Vector3(0.52,0.87,0)],0.13,paint)
		for x in [9.54,20.4,27.33]:
			var at := Vector3(side*x,-0.19,10.43)
			_box(Vector3(0.67,0.15,0.59),at+Vector3(0,0.05,0),base)
			_box(Vector3(0.13,0.46,0.13),at+Vector3(0,0.3,0),trim)
			_box(Vector3(0.38,0.12,0.39),at+Vector3(0,0.54,0),paint)
		var post := Vector3(side*8.26,-0.19,4.9)
		_box(Vector3(0.46,0.27,0.58),post+Vector3(0,0.10,0),base)
		_box(Vector3(0.18,4.05,0.23),post+Vector3(0,2.08,0),trim)
		_box(Vector3(1.73,0.19,0.43),post+Vector3(side*0.74,4.07,0),concrete)
		_box(Vector3(1.26,0.06,0.34),post+Vector3(side*0.87,3.95,0),light)
	_shore_join = _instance(_corridor,"TidalBarrierAndServiceApron",_commit_geometry(),material)

func _build_landmarks() -> void:
	for theme: int in THEMES:
		_clear_geometry()
		match theme:
			2: _ink_horizon()
			3: _city_horizon()
			4: _sea_horizon()
			5: _ship_horizon()
		var mesh := _commit_geometry()
		var visual := _instance(self,"District%dHorizon" % theme,mesh,_landmark_material)
		var arrival := _instance(self,"Arrival%dHorizon" % theme,mesh,_landmark_material)
		_landmarks[theme] = visual
		_incoming_landmarks[theme] = arrival
	_horizon = _landmarks[5]

func _append_voxel_cells(cells: Dictionary, unit: float, offset: Vector3) -> void:
	var h := unit*0.5
	var directions: Array[Vector3i] = [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.DOWN,Vector3i.UP,Vector3i.FORWARD,Vector3i.BACK]
	var corners: Array[Array] = [
		[Vector3(-h,-h,-h),Vector3(-h,-h,h),Vector3(-h,h,h),Vector3(-h,h,-h)],
		[Vector3(h,-h,h),Vector3(h,-h,-h),Vector3(h,h,-h),Vector3(h,h,h)],
		[Vector3(-h,-h,h),Vector3(-h,-h,-h),Vector3(h,-h,-h),Vector3(h,-h,h)],
		[Vector3(-h,h,-h),Vector3(-h,h,h),Vector3(h,h,h),Vector3(h,h,-h)],
		[Vector3(h,-h,-h),Vector3(-h,-h,-h),Vector3(-h,h,-h),Vector3(h,h,-h)],
		[Vector3(-h,-h,h),Vector3(h,-h,h),Vector3(h,h,h),Vector3(-h,h,h)],
	]
	for coord: Vector3i in cells:
		var at := offset+Vector3(coord)*unit
		for face in range(6):
			if cells.has(coord+directions[face]): continue
			var c: Array = corners[face]
			_face(at+c[0],at+c[1],at+c[2],at+c[3],Vector3(directions[face]),cells[coord])

func _ink_horizon() -> void:
	var ink := Color("393939")
	var stone := Color("8d8d8d")
	var red := Color("8e3028")
	# The moving distant landmark keeps its own base as the tile floor is
	# clipped away. The slight height offset avoids a shared surface.
	_box(Vector3(264,2.6,138),Vector3(0,-21.35,-157),Color("797979"))
	for peak in range(9):
		var side := -1.0 if peak%2 == 0 else 1.0
		var x := side*(29.0+float(peak%5)*16)
		var z := -105.0-float(peak)*11.0
		var height := 42.0+float(posmod(peak*13,8))*6
		_karst(Vector3(x,-21,z),Vector3(26,height,33),Color("777777").lightened(float(peak)*0.024),peak+3)
	# The monastery is a destination on a high right-hand escarpment, not a
	# gate pasted into the central road's vanishing point.
	var at := Vector3(44,33,-147)
	# Skyline peaks are deliberately irregular. Give each occupied terrace
	# its own continuous mountain down to the valley instead of hoping a
	# separate distant peak happens to sit beneath it at every view angle.
	_stone_foundation(Vector3(44,4,-147),Vector3(35,58,30),Color("777777"),43)
	for step in range(4): _box(Vector3(30-float(step)*3,2.2,24-float(step)*2),at+Vector3(0,float(step)*2.2,0),stone)
	# A gateway crowns the terrace. The opening is bounded by real masonry
	# shoulders and a stepped lintel, with a second roof above the gallery.
	for side in [-1.0,1.0]:
		_box(Vector3(5.4,9.0,8.2),at+Vector3(side*6.0,11.7,0),stone.darkened(0.12))
		for course in range(4):
			_box(Vector3(5.4+course*0.58,0.65,8.5),at+Vector3(side*(6.0-0.19*course),16.3+0.60*course,0),stone)
		_banner(at+Vector3(side*6.0,16.3,4.13),6.2,red.lightened(0.16),stone.lightened(0.22))
	_box(Vector3(18,1.8,8.4),at+Vector3(0,19.0,0),stone)
	_roof(at+Vector3(0,19.9,0),Vector2(10.9,6.3),2.4,ink,stone)
	_pavilion(at+Vector3(0,22.0,0),1.26,ink,stone,red)
	_stone_foundation(Vector3(26,-1,-120),Vector3(12,50,14),Color("707070"),26)
	_pavilion(Vector3(26,24,-120),1.1,ink,stone,red)
	for z in [-115.0,-125.0,-135.0]:
		_box(Vector3(4.2,0.65,10.2),Vector3(29,23,z),stone)
		_box(Vector3(0.5,22,0.6),Vector3(28,12,z),ink)
	_stone_foundation(Vector3(-30,-4,-124),Vector3(12,46,16),Color("6c6c6c"),17)
	_pine(Vector3(-30,19,-124),-1,ink)
	_stone_foundation(Vector3(37,-1,-124),Vector3(9,50,10),Color("737373"),39)
	_pine(Vector3(37,24,-124),1,ink)

func _city_horizon() -> void:
	var black := Color("1d252d")
	var steel := Color("35404b")
	var cyan := Color(0.12,0.37,0.43,0.85)
	var amber := Color(0.59,0.41,0.20,0.80)
	_box(Vector3(264,2.3,126),Vector3(0,-16.4,-155),Color("222c35"))
	for index in range(15):
		var side := -1.0 if index%2 == 0 else 1.0
		var x := side*(26.0+float(posmod(index*13,7))*12.0)
		var z := -108.0-float(index%7)*14.0
		var height := 32.0+float(posmod(index*17,9))*8.0
		_box(Vector3(12+float(index%3)*3,height,14),Vector3(x,height*0.5-16,z),black)
		_box(Vector3(10,height*0.27,12),Vector3(x,height*0.82-16,z),steel)
		for service in range(3):
			var y := height*(0.43+0.16*service)-16.0
			var depth := 7.35+float(service%2)*0.28
			_box(Vector3(8.4,0.35,0.69),Vector3(x,y,z+depth),steel)
			for pane in range(6):
				var glass := cyan if posmod(index+pane+service,4) == 0 else steel.darkened(0.25)
				_box(Vector3(0.87,1.2,0.16),Vector3(x-3.5+float(pane)*1.4,y+0.78,z+depth-0.19),glass)
		for floor_index in range(4):
			_box(Vector3(8,0.25,0.10),Vector3(x,height*0.35+float(floor_index)*4.6,z+7.03),cyan if index%3 == 0 else steel)
		var mast_height := 5.0+float(index%2)*6.0
		_box(Vector3(0.3,mast_height,0.3),Vector3(x,height-15,z),steel)
		_box(Vector3(0.32,0.3,0.32),Vector3(x,height-15+mast_height*0.5+0.12,z),Color(0.65,0.06,0.035,0.75))
	_box(Vector3(145,1.7,11),Vector3(-9,22,-155),steel,Vector3(0,-0.16,0.015))
	_box(Vector3(145,0.13,0.15),Vector3(-9,23,-149.5),amber,Vector3(0,-0.16,0.015))
	for x in [-53.0,-26.0,24.0,57.0]:
		_box(Vector3(2.3,43,3.0),Vector3(x,0,-155-x*0.16),black)
		_beam(Vector3(x,13,-155-x*0.16),Vector3(x+5,21,-155-x*0.16),1.4,steel,2)

func _sea_horizon() -> void:
	_tidal_offshore_rig(Vector3(67,0,-153),1.0,0.12,false)
	_tidal_offshore_rig(Vector3(-67,0,-182),0.77,-0.32,true)
	_tidal_offshore_rig(Vector3(134,-0.3,-165),0.66,0.38,true)

func _tidal_offshore_rig(at: Vector3, size: float, yaw: float, relay: bool) -> void:
	var first := _vertices.size()
	var hull := Color("344756")
	var steel := Color("607282")
	var teal := Color("446975")
	var upper := Color("8c9ca0")
	var ochre := Color("b37d4f")
	var lit := Color(0.70,0.61,0.39,0.79)
	# A deck flange over a four-leg jacket, with the visible bracing
	# attached to both pile collars at the height of each actual member.
	for x in [-17.2,17.2]:
		for z in [-11.2,11.2]:
			var pile := Vector3(x,0,z)
			_beam(pile*Vector3(1.27,1,1.25)+Vector3(0,-19,0),pile+Vector3(0,14.5,0),3.05,hull,3.40)
			_box(Vector3(4.0,1.36,4.22),pile+Vector3(0,13.2,0),upper)
			_box(Vector3(4.05,0.82,4.10),pile*Vector3(1.15,1,1.13)+Vector3(0,-2,0),ochre)
		_beam(Vector3(x*1.12,-1.0,-12.3),Vector3(x,12.9,11.2),1.10,steel,1.46)
		_beam(Vector3(x*1.12,-1.0,12.3),Vector3(x,12.9,-11.2),1.10,steel,1.46)
	for z in [-11.2,11.2]:
		_beam(Vector3(-19.4,-0.85,z*1.10),Vector3(17.5,12.9,z),1.12,steel,1.42)
		_beam(Vector3(19.4,-0.85,z*1.10),Vector3(-17.5,12.9,z),1.12,steel,1.42)
		_box(Vector3(44.8,1.22,0.83),Vector3(0,13.3,z),hull)
	_beveled_box(Vector3(49,2.7,33),Vector3(0,15.0,0),2.1,steel)
	_beveled_box(Vector3(48,0.59,32.5),Vector3(0,16.56,0),1.84,hull)
	for bay in range(10):
		var x := float(bay-5)*4.42+2.15
		_box(Vector3(3.7,0.55,0.10),Vector3(x,15.82,16.52),teal if bay%3!=0 else ochre)
		_box(Vector3(0.30,1.67,0.30),Vector3(x-1.97,15.13,16.57),upper)
		_box(Vector3(1.08,0.33,0.11),Vector3(x,14.72,16.58),lit if bay%2==0 else hull)
	_guard_rail(Vector3(-22.3,16.85,15.4),Vector3(22.3,16.85,15.4),1.25,ochre)
	_guard_rail(Vector3(-22.3,16.85,-15.4),Vector3(-22.3,16.85,15.4),1.25,ochre)
	var control := Vector3(-7.6,0,-2.2) if not relay else Vector3(4.7,0,-2.8)
	var tier_count := 2 if relay and at.x > 0.0 else 3
	for tier in range(tier_count):
		var y := 19.15+float(tier)*4.34
		var width := 16.5-float(tier)*2.26
		var depth := 17.2-float(tier)*2.31
		var center := control+Vector3(float(tier)*0.75,y,0)
		_beveled_box(Vector3(width,4.38,depth),center,0.85,teal if tier%2==0 else hull)
		_beveled_box(Vector3(width+1.55,0.40,depth+1.3),center+Vector3(0,2.19,0),0.74,upper)
		for pane in range(6-tier):
			var x := -width*0.36+float(pane)*width*0.15
			_box(Vector3(width*0.11,0.74,0.09),center+Vector3(x,0.65,depth*0.5+0.055),lit)
		for pane in range(4):
			var z := -depth*0.33+float(pane)*depth*0.21
			_box(Vector3(0.095,0.69,depth*0.142),center+Vector3(-width*0.5-0.059,0.65,z),lit)
		_guard_rail(center+Vector3(-width*0.41,2.37,depth*0.5+0.32),center+Vector3(width*0.40,2.37,depth*0.5+0.32),0.94,ochre)
	var roof := 21.40+float(tier_count-1)*4.34
	_tidal_beacon(control+Vector3(-1.5,roof,0),7.5 if not relay else 5.75)
	_tidal_beacon(control+Vector3(4.4,roof,-2.8),3.2)
	for x in [-1.8,1.8]: _voxel_drum(Vector3(x+10.7,16.91,9.6),1.2,3.22,teal,upper)
	if relay:
		var base := Vector3(-12,16.8,0.0)
		_box(Vector3(3.85,6.0,3.85),base+Vector3(0,2.97,0),hull)
		_beam(base+Vector3(-1.55,3.1,0),base+Vector3(0.0,17.45,0),0.61,steel)
		_beam(base+Vector3(1.55,3.1,0),base+Vector3(0.0,17.45,0),0.61,steel)
		_box(Vector3(8.0,0.84,0.96),base+Vector3(0,16.75,0),upper,Vector3(0,0.24,0.14))
		_tidal_beacon(base+Vector3(0,17.11,0),1.48)
	else:
		var foot := Vector3(14.5,17.1,-0.9)
		_beveled_box(Vector3(7.2,1.8,7.3),foot+Vector3(0,0.7,0),0.62,hull)
		var heel := foot+Vector3(0,17.35,0)
		var head := foot+Vector3(0,27.2,0)
		var tip := foot+Vector3(37,32.3,-13)
		_box(Vector3(2.85,17.0,2.85),foot+Vector3(0,9.3,0),teal)
		_beveled_box(Vector3(5.65,3.0,3.6),heel+Vector3(-1.1,0,0),0.28,hull)
		_box(Vector3(0.09,0.88,2.52),heel+Vector3(-3.96,0.42,0),lit)
		_beam(heel,head,1.20,steel,1.24)
		_beam(heel,tip,1.02,ochre,1.20)
		_beam(heel+Vector3(0,2.35,0),tip+Vector3(0,0.22,0),0.76,steel,0.89)
		for panel in range(8):
			var a := float(panel)/8.0
			var b := float(panel+1)/8.0
			_beam(heel.lerp(tip,a),heel.lerp(tip,b)+Vector3(0,lerpf(2.35,0.22,b),0),0.33,ochre,0.42)
		_beam(head,tip,0.14,hull)
		_beam(tip,tip-Vector3(0,16.6,0),0.11,hull)
		_box(Vector3(0.63,1.03,0.67),tip-Vector3(0,16.68,0),ochre)
	var orientation := Basis(Vector3.UP,yaw).scaled(Vector3.ONE*size)
	_transform_from(first,Transform3D(orientation,at))

func _ship_horizon() -> void:
	var first := _vertices.size()
	_orbital_capital_ship()
	# The mooring clamps, lower gallery, and ship are built in one frame.
	_box(Vector3(23.0,1.65,62.0),Vector3(0,-13.3,-0.5),ORBITAL_FRAME)
	_box(Vector3(19.0,1.2,55.0),Vector3(0,-14.5,-0.5),ORBITAL_INSET)
	for z: float in [-16.0,1.0,18.0]:
		_box(Vector3(15.4,1.12,3.8),Vector3(0,-4.63,z),ORBITAL_ARMOR)
		_box(Vector3(9.4,0.64,3.3),Vector3(0,-4.05,z),ORBITAL_BRASS)
		for side: float in [-1.0,1.0]:
			_box(Vector3(1.65,9.1,2.52),Vector3(side*6.7,-8.89,z),ORBITAL_STEEL)
			_beam(Vector3(side*10.7,-13.2,z),Vector3(side*5.2,-4.58,z),1.23,ORBITAL_ARMOR,1.9)
			_box(Vector3(1.84,1.56,3.10),Vector3(side*4.0,-3.67,z),ORBITAL_STEEL)
			_box(Vector3(0.18,0.19,1.45),Vector3(side*7.55,-4.64,z),ORBITAL_AMBER)
	var berth := Transform3D(Basis(Vector3.UP,-0.15).scaled(Vector3(2.35,1.95,2.35)),Vector3(-74,17,-119))
	_transform_from(first,berth)
	for z: float in [-16.0,18.0]:
		var mooring := berth*Vector3(9.7,-13.1,z)
		var runway := Vector3(-5.1,-7.3,mooring.z)
		_beam(mooring,runway,1.65,ORBITAL_FRAME,4.1)
		_beam(mooring+Vector3(0,-2.1,0),runway+Vector3(0,2.1,0),0.70,ORBITAL_STEEL,1.10)
		_box(Vector3(3.6,6.1,4.6),runway+Vector3(0,0.7,0),ORBITAL_ARMOR)
	_orbital_outboard_terminal()

func _orbital_outboard_terminal() -> void:
	# Freight transfers on an outboard deck under the flight paths. Its two
	# access bridges share a foundation with the underside of the runway.
	var at := Vector3(66,-4.2,-150)
	_box(Vector3(43,2.9,49),at+Vector3(0,-1.4,0),ORBITAL_ARMOR)
	_box(Vector3(38,1.4,45),at+Vector3(1.0,-3.48,0),ORBITAL_FRAME)
	_box(Vector3(32,1.6,39),at+Vector3(2.7,-4.76,0),ORBITAL_INSET)
	for z: float in [-15.0,15.0]:
		var road_end := Vector3(5.25,-7.85,at.z+z)
		var dock_end := at+Vector3(-19.8,-2.1,z)
		_beam(road_end,dock_end,1.47,ORBITAL_FRAME,4.6)
		_beam(road_end+Vector3(0,-1.65,0),dock_end+Vector3(0,-1.5,0),0.64,ORBITAL_STEEL,2.5)
		_box(Vector3(3.75,6.65,4.9),road_end+Vector3(0,0.6,0),ORBITAL_ARMOR)
		for bay in range(4):
			var offset := float(bay)/4.0
			var a := road_end.lerp(dock_end,offset)
			var b := road_end.lerp(dock_end,offset+0.25)
			_beam(a,b-Vector3(0,1.42,0),0.29,ORBITAL_ARMOR,1.2)
			_beam(a-Vector3(0,1.46,0),b,0.25,ORBITAL_STEEL,1.0)
	for z: float in [-16.5,17.5]:
		var tower := at+Vector3(6.4,0,z)
		var height := 12.8 if z < 0.0 else 19.6
		_beveled_box(Vector3(7.0,height,7.6),tower+Vector3(0,height*0.5-0.35,0),0.67,ORBITAL_ARMOR)
		_box(Vector3(1.18,height*0.90,8.1),tower+Vector3(2.25,height*0.44,0),ORBITAL_STEEL)
		_beam(tower+Vector3(-7.1,0,0),tower+Vector3(-2.7,height-1.85,0),0.93,ORBITAL_STEEL,1.38)
		_beveled_box(Vector3(13.4,1.15,9.6),tower+Vector3(-1.63,height-0.55,0),0.63,ORBITAL_STEEL)
		_beveled_box(Vector3(11.3,2.56,8.2),tower+Vector3(-1.2,height+0.99,0),0.47,ORBITAL_FRAME)
		_beveled_box(Vector3(12.1,0.42,9.03),tower+Vector3(-1.3,height+2.42,0),0.43,ORBITAL_STEEL)
		_box(Vector3(0.14,1.14,6.31),tower+Vector3(-6.86,height+1.10,0),ORBITAL_AMBER)
		_box(Vector3(9.35,1.04,0.16),tower+Vector3(-1.28,height+1.10,4.14),ORBITAL_AMBER)
		for bar in range(5):
			_box(Vector3(0.18,1.44,0.18),tower+Vector3(-6.93,height+1.10,-2.59+float(bar)*1.29),ORBITAL_STEEL)
			_box(Vector3(0.16,1.42,0.20),tower+Vector3(-5.21+float(bar)*1.93,height+1.10,4.23),ORBITAL_STEEL)
		_box(Vector3(0.24,5.8,0.27),tower+Vector3(2.4,height+5.45,-1.3),ORBITAL_STEEL)
		_box(Vector3(0.36,0.34,0.36),tower+Vector3(2.4,height+8.32,-1.3),ORBITAL_VIOLET)
	_box(Vector3(3.0,1.2,35.1),at+Vector3(2.0,8.5,0),ORBITAL_ARMOR)
	_guard_rail(at+Vector3(0.56,9.1,-16.75),at+Vector3(0.56,9.1,17.54),0.88,ORBITAL_BRASS)
	for z: float in [-17.5,-9.1,-0.7,7.7,16.1]:
		var bay := at+Vector3(-13.4,0,z)
		_beveled_box(Vector3(5.9,2.0,5.1),bay+Vector3(0,0.95,0),0.32,ORBITAL_FRAME)
		_box(Vector3(0.17,0.22,2.3),bay+Vector3(-2.95,1.02,0),ORBITAL_VIOLET)
		for rim: float in [-1.86,1.86]:
			_box(Vector3(6.13,2.16,0.41),bay+Vector3(0,0.98,rim),ORBITAL_STEEL)

func _orbital_capital_ship() -> void:
	# Joined longitudinal sections define a thick armored wedge and a blunt
	# drive bay. The yoke clamps and every smaller plate meet this volume.
	var sections: Array[Vector4] = [
		Vector4(-34.0,0.52,0.42,0.55),Vector4(-27.0,3.8,1.24,1.36),
		Vector4(-16.0,6.75,2.30,3.54),Vector4(-6.0,8.9,3.0,4.12),
		Vector4(6.0,9.36,3.22,4.22),Vector4(18.0,9.0,3.1,4.15),
		Vector4(27.0,7.6,2.7,3.72),Vector4(34.0,6.48,2.1,3.36),
	]
	var rings: Array[PackedVector3Array] = []
	for profile in sections:
		var z := profile.x
		var w := profile.y
		var t := profile.z
		var b := profile.w
		rings.append(PackedVector3Array([
			Vector3(-w*0.64,t,z),Vector3(w*0.64,t,z),Vector3(w,t*0.46,z),Vector3(w*0.96,-b*0.43,z),
			Vector3(w*0.48,-b,z),Vector3(-w*0.48,-b,z),Vector3(-w*0.96,-b*0.43,z),Vector3(-w,t*0.46,z),
		]))
	var plating: Array[Color] = [ORBITAL_STEEL,ORBITAL_STEEL.lightened(0.19),ORBITAL_ARMOR,ORBITAL_FRAME,ORBITAL_INSET,ORBITAL_FRAME,ORBITAL_ARMOR,ORBITAL_STEEL.lightened(0.19)]
	for index in range(rings.size()-1):
		var rear := rings[index]
		var fore := rings[index+1]
		for plate in range(8):
			var next := (plate+1)%8
			var color := plating[plate].lightened(0.065) if index%2 == 1 else plating[plate]
			_orbital_facet(rear[plate],fore[plate],fore[next],rear[next],color)
			if index > 0 and plate in [1,2,3,5,6,7]:
				_orbital_hull_plating(rear[plate],fore[plate],fore[next],rear[next],index,plate)
	for index in range(8):
		var next := (index+1)%8
		_triangle(Vector3(0,0,sections[0].x),rings[0][index],rings[0][next],Vector3.FORWARD,ORBITAL_STEEL)
		_triangle(Vector3(0,0,sections[-1].x),rings[-1][next],rings[-1][index],Vector3.BACK,ORBITAL_FRAME)
	_beveled_box(Vector3(9.7,1.55,31.0),Vector3(0,3.58,7.5),0.74,ORBITAL_ARMOR)
	_beveled_box(Vector3(7.12,1.2,24.4),Vector3(0,4.76,9.7),0.53,ORBITAL_STEEL)
	_beveled_box(Vector3(5.9,2.54,12.2),Vector3(0,6.0,13.8),0.56,ORBITAL_FRAME)
	_beveled_box(Vector3(6.42,0.39,12.78),Vector3(0,7.40,13.8),0.56,ORBITAL_STEEL)
	_box(Vector3(4.74,0.49,0.12),Vector3(0,6.67,19.92),ORBITAL_AMBER)
	for bar in range(7):
		_box(Vector3(0.14,0.58,0.19),Vector3(-2.13+float(bar)*0.71,6.65,19.98),ORBITAL_STEEL)
	for side: float in [-1.0,1.0]:
		_box(Vector3(0.24,3.65,0.30),Vector3(side*1.92,9.17,12.68),ORBITAL_STEEL)
		_box(Vector3(0.29,0.31,0.37),Vector3(side*1.92,10.99,12.68),ORBITAL_VIOLET)
		_beveled_box(Vector3(3.36,1.31,15.2),Vector3(side*4.1,3.1,13.5),0.43,ORBITAL_STEEL.lightened(0.12))
		for plate in range(5):
			var z := -9.0+float(plate)*6.4
			_beveled_box(Vector3(1.1,0.65,5.84),Vector3(side*8.15,0.87,z),0.18,ORBITAL_BRASS if plate == 2 else ORBITAL_STEEL)
			_box(Vector3(0.14,0.20,2.90),Vector3(side*8.68,0.91,z-0.64),ORBITAL_AMBER)
			_box(Vector3(1.75,0.65,5.71),Vector3(side*3.51,-3.88,z),ORBITAL_ARMOR)
			_box(Vector3(0.52,0.13,3.1),Vector3(side*3.62,-4.24,z),ORBITAL_VIOLET)
		_beveled_box(Vector3(5.19,4.83,6.65),Vector3(side*3.9,-0.14,30.67),0.42,ORBITAL_ARMOR)
		_orbital_engine_bell(Vector3(side*3.9,-0.12,34.6))

func _orbital_hull_plating(a: Vector3, b: Vector3, c: Vector3, d: Vector3, section: int, panel: int) -> void:
	var n := (b-a).cross(c-a).normalized()
	for plate in range(3):
		var start := 0.035+float(plate)*0.32
		var end := start+0.288
		var p := a.lerp(b,start)
		var q := a.lerp(b,end)
		var r := d.lerp(c,end)
		var s := d.lerp(c,start)
		var cap := PackedVector3Array([p.lerp(s,0.15),q.lerp(r,0.15),q.lerp(r,0.88),p.lerp(s,0.88)])
		var tint := ORBITAL_STEEL.lightened(0.19) if panel in [1,7] else ORBITAL_ARMOR.lightened(0.13)
		tint = tint.darkened(float(posmod(plate+section+panel,3))*0.09)
		tint.a = 0.956 if panel in [3,5] else 0.964
		var lift := n*(0.085+float(posmod(plate+section,3))*0.034)
		_orbital_facet(cap[0]+lift,cap[1]+lift,cap[2]+lift,cap[3]+lift,tint)
		for edge in range(4):
			var next := (edge+1)%4
			_orbital_facet(cap[edge]-n*0.20,cap[next]-n*0.20,cap[next]+lift,cap[edge]+lift,ORBITAL_ARMOR)
		if posmod(plate+section+panel,4) == 1:
			var recess := lift+n*0.006
			var near_bottom := cap[0].lerp(cap[1],0.24)+recess
			var near_top := cap[3].lerp(cap[2],0.24)+recess
			var far_bottom := cap[0].lerp(cap[1],0.77)+recess
			var far_top := cap[3].lerp(cap[2],0.77)+recess
			_orbital_facet(near_bottom.lerp(near_top,0.38),far_bottom.lerp(far_top,0.38),far_bottom.lerp(far_top,0.51),near_bottom.lerp(near_top,0.51),ORBITAL_AMBER if panel == 2 else ORBITAL_VIOLET)

func _orbital_engine_bell(at: Vector3) -> void:
	var segments := 14
	for index in range(segments):
		var a := TAU*float(index)/float(segments)
		var b := TAU*float(index+1)/float(segments)
		var pa := Vector3(cos(a),sin(a),0)
		var pb := Vector3(cos(b),sin(b),0)
		var rim := ORBITAL_STEEL if index%3 == 0 else ORBITAL_FRAME
		var rear := at-Vector3(0,0,0.70)
		var front := at+Vector3(0,0,1.28)
		_orbital_facet(rear+pa*2.20,rear+pb*2.20,front+pb*1.86,front+pa*1.86,rim)
		_orbital_facet(front+pa*1.56,front+pa*1.86,front+pb*1.86,front+pb*1.56,ORBITAL_BRASS)
		_orbital_facet(front+pa*1.56,front+pb*1.56,at+pb*1.44,at+pa*1.44,ORBITAL_ARMOR)
		if index%3 != 2:
			var lamp := front+Vector3(0,0,0.007)
			_orbital_facet(lamp+pa*1.56,lamp+pa*1.68,lamp+pb*1.68,lamp+pb*1.56,ORBITAL_AMBER)
		_orbital_facet(at+pa*1.05,at+pa*1.44,at+pb*1.44,at+pb*1.05,ORBITAL_AMBER if index%4 != 0 else ORBITAL_INSET)
		_triangle(at-Vector3(0,0,0.018),at+pa*1.06,at+pb*1.06,Vector3.BACK,ORBITAL_INSET)

func _transform_from(first: int, transform: Transform3D) -> void:
	var normal_basis := transform.basis.inverse().transposed()
	for index in range(first,_vertices.size()):
		_vertices[index] = transform*_vertices[index]
		_normals[index] = (normal_basis*_normals[index]).normalized()

func _clear_geometry() -> void:
	_vertices = PackedVector3Array()
	_normals = PackedVector3Array()
	_colors = PackedColorArray()

func _commit_geometry() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func _triangle(a: Vector3,b: Vector3,c: Vector3,n: Vector3,color: Color) -> void:
	# Godot's front faces use clockwise vertex order.
	for point in [a,c,b]:
		_vertices.append(point)
		_normals.append(n)
		_colors.append(color.srgb_to_linear())

func _face(a: Vector3,b: Vector3,c: Vector3,d: Vector3,n: Vector3,color: Color) -> void:
	_triangle(a,b,c,n,color)
	_triangle(a,c,d,n,color)

func _box(size: Vector3,at: Vector3,color: Color,rotation: Vector3 = Vector3.ZERO) -> void:
	var b := Basis.from_euler(rotation)
	var p: Array[Vector3] = []
	for v in [Vector3(-1,-1,-1),Vector3(1,-1,-1),Vector3(1,1,-1),Vector3(-1,1,-1),Vector3(-1,-1,1),Vector3(1,-1,1),Vector3(1,1,1),Vector3(-1,1,1)]: p.append(at+b*(v*size*0.5))
	for face in [[0,3,2,1,Vector3.BACK*-1.0],[4,5,6,7,Vector3.BACK],[0,4,7,3,Vector3.LEFT],[1,2,6,5,Vector3.RIGHT],[3,7,6,2,Vector3.UP],[0,1,5,4,Vector3.DOWN]]:
		_face(p[face[0]],p[face[1]],p[face[2]],p[face[3]],b*Vector3(face[4]),color)

func _beam(a: Vector3,b: Vector3,width: float,color: Color,depth: float = -1.0) -> void:
	var direction := b-a
	var rotation := Basis(Quaternion(Vector3.UP,direction.normalized())).get_euler()
	_box(Vector3(width,direction.length(),width if depth < 0.0 else depth),(a+b)*0.5,color,rotation)

func _taper(at: Vector3,height: float,radius: Vector2,tip: Vector2,color: Color,sides: int = 6,lean: Vector3 = Vector3.ZERO) -> void:
	for side in range(sides):
		var a := TAU*float(side)/float(sides)
		var b := TAU*float(side+1)/float(sides)
		var p0 := at+Vector3(cos(a)*radius.x,0,sin(a)*radius.y)
		var p1 := at+Vector3(cos(b)*radius.x,0,sin(b)*radius.y)
		var p2 := at+Vector3(cos(b)*tip.x,height,sin(b)*tip.y)+lean
		var p3 := at+Vector3(cos(a)*tip.x,height,sin(a)*tip.y)+lean
		var normal := (p3-p0).cross(p1-p0).normalized()
		_face(p0,p3,p2,p1,normal,color)
		_triangle(at+Vector3(0,height,0)+lean,p2,p3,Vector3.UP,color)
		_triangle(at,p0,p1,Vector3.DOWN,color)

func _banner(at: Vector3,height: float,red: Color,border: Color) -> void:
	_box(Vector3(0.60,height,0.08),at,red)
	_box(Vector3(0.065,height*0.86,0.012),at+Vector3(-0.21,0,0.047),border)
	_box(Vector3(0.065,height*0.86,0.012),at+Vector3(0.21,0,0.047),border)
	for y in [-0.43,0.43]: _box(Vector3(0.47,0.055,0.012),at+Vector3(0,y*height,0.048),border)

func _leaf(base: Vector3,tip: Vector3,tint: Color) -> void:
	var center := base.lerp(tip,0.34)
	var width := Vector3(0.24,0.12,-0.10)
	var ridge := center+Vector3(0,0.035,0)
	for face in [[base,center+width,ridge],[center+width,tip,ridge],[tip,center-width,ridge],[center-width,base,ridge]]:
		var n: Vector3 = (face[1]-face[0]).cross(face[2]-face[0]).normalized()
		_triangle(face[0],face[1],face[2],n,tint)
		_triangle(face[2],face[1],face[0],-n,tint)

