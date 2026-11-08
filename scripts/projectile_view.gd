class_name ProjectileView
extends Node3D

const GeometryScript = preload("res://scripts/projectile_geometry.gd")

var projectile_kind := "bolt"
var collision_radius := 0.12
var reflected := false
var age := 0.0
var _solids: Array[PackedVector3Array] = []
var _signal: MeshInstance3D
var _exhaust: MultiMesh
var _exhaust_start := -0.4
var _exhaust_size := 0.08
var _solid_bounds := AABB()
static var _materials: Dictionary = {}
static var _shell_material: ShaderMaterial


static func prewarm() -> void:
	for kind in ["bolt","missile","shock","mine"]:
		GeometryScript.get_template(kind)
	_get_shell_material()


func configure(kind: String) -> void:
	projectile_kind = kind
	var template: Dictionary = GeometryScript.get_template(kind)
	collision_radius = template.radius
	_solid_bounds = template.bounds
	_solids.assign(template.hulls)
	var shell := MeshInstance3D.new()
	shell.mesh = template.mesh
	shell.material_override = _get_shell_material()
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shell)
	var hot := _material("hot", Color(1.8, 0.74, 0.18), 0.0, 0.6, true)
	_signal = _box(template.indicator_size,template.indicator_position,hot)
	_exhaust_start = template.exhaust_start
	_exhaust_size = template.exhaust_size
	_exhaust = MultiMesh.new()
	_exhaust.transform_format = MultiMesh.TRANSFORM_3D
	_exhaust.use_colors = true
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	_exhaust.mesh = cube
	_exhaust.instance_count = 0 if kind == "mine" else (4 if kind == "missile" else 2)
	var jets := MultiMeshInstance3D.new()
	jets.multimesh = _exhaust
	jets.material_override = _material("exhaust",Color.WHITE,0.0,0.6,true)
	jets.material_override.vertex_color_use_as_albedo = true
	jets.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(jets)


func set_reflected() -> void:
	reflected = true
	if is_instance_valid(_signal):
		_signal.material_override = _material("reflected", Color(0.48,1.8,1.5),0.0,0.6,true)


func advance(sim_dt: float, velocity: Vector3) -> void:
	if sim_dt <= 0.0:
		return
	age += sim_dt
	if velocity.length_squared() > 0.0001:
		var direction := velocity.normalized()
		var up := Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP
		basis = Basis.looking_at(direction, up, true)
	for index in range(_exhaust.instance_count):
		var size := _exhaust_size*(1.0-float(index)*0.19)*(0.88+sin(age*47.0+index*1.7)*0.12)
		var transform := Transform3D(Basis.IDENTITY.scaled(Vector3(size,size,size*0.85)),Vector3(0,0,_exhaust_start-float(index)*_exhaust_size*1.1))
		_exhaust.set_instance_transform(index,transform)
		_exhaust.set_instance_color(index,Color(2.0,1.24,0.48).lerp(Color(0.65,0.18,0.025),float(index)*0.24))


func intersects_path(camera: Camera3D, points: PackedVector2Array) -> bool:
	if points.size() < 2:
		return false
	var coarse := Rect2()
	var has_corner := false
	for corner in range(8):
		var world := to_global(_solid_bounds.get_endpoint(corner))
		if camera.is_position_behind(world):
			continue
		var screen := camera.unproject_position(world)
		coarse = coarse.expand(screen) if has_corner else Rect2(screen,Vector2.ZERO)
		has_corner = true
	var path_bounds := Rect2(points[0],Vector2.ZERO)
	for point in points: path_bounds = path_bounds.expand(point)
	if not has_corner or not coarse.intersects(path_bounds.grow(0.5)):
		return false
	# Project the actual convex shell pieces; holes between fins stay empty,
	# and the small exhaust never enlarges the blade's contact area.
	for solid in _solids:
		var corners := PackedVector2Array()
		for vertex in solid:
			var point := to_global(vertex)
			if camera.is_position_behind(point):
				continue
			corners.append(camera.unproject_position(point))
		if corners.size() < 3:
			continue
		var polygon := Geometry2D.convex_hull(corners)
		for index in range(points.size()-1):
			if Geometry2D.is_point_in_polygon(points[index],polygon) or Geometry2D.is_point_in_polygon(points[index+1],polygon):
				return true
			for edge in range(polygon.size()-1):
				if Geometry2D.segment_intersects_segment(points[index],points[index+1],polygon[edge],polygon[edge+1]) != null:
					return true
	return false


func _box(size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.position = at
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	return visual


static func _get_shell_material() -> ShaderMaterial:
	if _shell_material != null:
		return _shell_material
	var shader := Shader.new()
	shader.code = """shader_type spatial;
void fragment() {
	vec3 base = COLOR.rgb;
	float copper = step(base.g*1.30,base.r);
	float paint = step(0.5,base.r)*(1.0-copper);
	float rubber = 1.0-smoothstep(0.05,0.11,max(base.r,max(base.g,base.b)));
	ALBEDO = base;
	METALLIC = mix(mix(0.82,0.28,paint),0.78,copper)*(1.0-rubber);
	ROUGHNESS = mix(mix(0.32,0.57,paint),0.36,copper);
	ROUGHNESS = mix(ROUGHNESS,0.85,rubber);
}
"""
	_shell_material = ShaderMaterial.new()
	_shell_material.shader = shader
	return _shell_material


static func _material(key: String, tint: Color, metal: float, roughness: float, unshaded: bool = false) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.metallic = metal
	material.roughness = roughness
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_materials[key] = material
	return material
