class_name ProjectileGeometry
extends RefCounted
## One cached PBR shell per ammunition type; collision uses the same convex
## solid pieces, rather than filling the gaps between tail fins.

static var _templates: Dictionary = {}
var _surface: SurfaceTool
var _hulls: Array[PackedVector3Array] = []
const PAINT := Color("c4bcaa")
const STEEL := Color("34424c")
const DARK := Color("111a21")
const COPPER := Color("ac6c42")


static func get_template(kind: String) -> Dictionary:
	if _templates.has(kind):
		return _templates[kind]
	var builder = load("res://scripts/projectile_geometry.gd").new()
	var result: Dictionary = builder._build(kind)
	_templates[kind] = result
	return result


func _build(kind: String) -> Dictionary:
	_surface = SurfaceTool.new()
	_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indicator_size := Vector3(0.055,0.055,0.035)
	var indicator_position := Vector3(0,0,0.47)
	var exhaust_start := -0.39
	var exhaust_size := 0.07
	var radius := 0.14
	if kind == "missile":
		radius = 0.32
		exhaust_start = -0.59
		exhaust_size = 0.14
		_prism(Vector2(0.28,0.28),Vector2(0.30,0.30),-0.39,0.20,PAINT)
		_prism(Vector2(0.30,0.30),Vector2(0.21,0.21),0.20,0.40,STEEL)
		_prism(Vector2(0.21,0.21),Vector2(0.065,0.065),0.40,0.65,COPPER)
		_prism(Vector2(0.32,0.32),Vector2(0.32,0.32),-0.47,-0.39,STEEL)
		_prism(Vector2(0.20,0.20),Vector2(0.24,0.24),-0.56,-0.47,DARK)
		_prism(Vector2(0.305,0.305),Vector2(0.305,0.305),-0.10,-0.065,COPPER)
		for side in [-1.0,1.0]:
			_box(Vector3(0.012,0.10,0.20),Vector3(side*0.153,0,0.05),DARK)
			for stud in [-0.24,0.11]:
				_box(Vector3(0.018,0.035,0.035),Vector3(side*0.154,0.065,stud),STEEL)
		for index in range(4):
			var angle := float(index)*PI*0.5
			var rotation := Basis(Vector3.BACK,angle)
			_prism(Vector2(0.20,0.035),Vector2(0.065,0.035),-0.40,-0.03,STEEL,rotation*Vector3(0.23,0,0),rotation,Vector2(-0.065,0))
		indicator_size = Vector3(0.06,0.06,0.045)
		indicator_position = Vector3(0,0,0.66)
	elif kind == "mine":
		radius = 0.34
		exhaust_start = -0.24
		exhaust_size = 0.04
		# A compact cubic charge with four separated armour lugs. The gaps
		# remain real empty space in the same convex solids used for cutting.
		_box(Vector3(0.42,0.42,0.42),Vector3.ZERO,DARK)
		_box(Vector3(0.30,0.30,0.05),Vector3(0,0,0.235),COPPER)
		for side in [-1.0,1.0]:
			_box(Vector3(0.13,0.52,0.30),Vector3(side*0.25,0,0),PAINT)
			_box(Vector3(0.22,0.12,0.30),Vector3(0,side*0.25,0),STEEL)
			_box(Vector3(0.05,0.18,0.045),Vector3(side*0.25,0,0.175),COPPER)
		indicator_size = Vector3(0.13,0.13,0.07)
		indicator_position = Vector3(0,0,0.295)
	elif kind == "shock":
		radius = 0.46
		exhaust_start = -0.26
		exhaust_size = 0.14
		_prism(Vector2(0.77,0.38),Vector2(0.70,0.34),-0.20,0.20,STEEL)
		_prism(Vector2(0.54,0.26),Vector2(0.48,0.22),0.20,0.29,COPPER)
		for side in [-1.0,1.0]:
			_box(Vector3(0.13,0.43,0.24),Vector3(side*0.34,0,-0.015),PAINT)
			for fin in range(3):
				_box(Vector3(0.04,0.30,0.025),Vector3(side*(0.22-float(fin)*0.075),0,0.22),DARK)
		indicator_size = Vector3(0.20,0.16,0.075)
		indicator_position = Vector3(0,0,0.32)
	else:
		_prism(Vector2(0.15,0.15),Vector2(0.16,0.16),-0.24,0.14,STEEL)
		_prism(Vector2(0.16,0.16),Vector2(0.13,0.13),0.14,0.29,PAINT)
		_prism(Vector2(0.13,0.13),Vector2(0.035,0.035),0.29,0.47,STEEL)
		_prism(Vector2(0.18,0.18),Vector2(0.18,0.18),-0.19,-0.135,COPPER)
		_prism(Vector2(0.11,0.11),Vector2(0.11,0.11),-0.33,-0.24,DARK)
		for index in range(4):
			var rotation := Basis(Vector3.BACK,float(index)*PI*0.5)
			_prism(Vector2(0.075,0.022),Vector2(0.035,0.022),-0.29,-0.12,PAINT,rotation*Vector3(0.105,0,0),rotation,Vector2(-0.025,0))
	# The signal cap is also a solid, but its colour can change after reflection.
	var cap := AABB(indicator_position-indicator_size*0.5,indicator_size)
	var cap_points := PackedVector3Array()
	for index in range(8): cap_points.append(cap.get_endpoint(index))
	_hulls.append(cap_points)
	var mesh := _surface.commit()
	return {"mesh":mesh,"hulls":_hulls,"bounds":mesh.get_aabb().merge(cap),"indicator_size":indicator_size,"indicator_position":indicator_position,"exhaust_start":exhaust_start,"exhaust_size":exhaust_size,"radius":radius}


func _box(size: Vector3, at: Vector3, tint: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index in indices:
		_surface.set_color(tint)
		_surface.set_normal(normals[index])
		_surface.add_vertex(vertices[index]+at)
	var bounds := AABB(at-size*0.5,size)
	var hull := PackedVector3Array()
	for index in range(8): hull.append(bounds.get_endpoint(index))
	_hulls.append(hull)


func _ring(size: Vector2) -> Array[Vector2]:
	var h := size*0.5
	var c := minf(h.x,h.y)*0.42
	return [Vector2(-h.x+c,-h.y),Vector2(h.x-c,-h.y),Vector2(h.x,-h.y+c),Vector2(h.x,h.y-c),Vector2(h.x-c,h.y),Vector2(-h.x+c,h.y),Vector2(-h.x,h.y-c),Vector2(-h.x,-h.y+c)]


func _prism(back: Vector2, front: Vector2, z0: float, z1: float, tint: Color, at: Vector3 = Vector3.ZERO, rotation: Basis = Basis.IDENTITY, front_shift: Vector2 = Vector2.ZERO) -> void:
	var a := _ring(back)
	var b := _ring(front)
	var hull := PackedVector3Array()
	for index in range(8):
		hull.append(at+rotation*Vector3(a[index].x,a[index].y,z0))
	for index in range(8):
		hull.append(at+rotation*Vector3(b[index].x+front_shift.x,b[index].y+front_shift.y,z1))
	_hulls.append(hull)
	var back_center := at+rotation*Vector3(0,0,z0)
	var front_center := at+rotation*Vector3(front_shift.x,front_shift.y,z1)
	for index in range(8):
		var next := (index+1)%8
		_triangle(back_center,hull[next],hull[index],tint)
		_triangle(front_center,hull[8+index],hull[8+next],tint)
		_triangle(hull[index],hull[next],hull[8+next],tint)
		_triangle(hull[index],hull[8+next],hull[8+index],tint)


func _triangle(a: Vector3, b: Vector3, c: Vector3, tint: Color) -> void:
	var normal := (b-a).cross(c-a).normalized()
	for vertex in [a,c,b]:
		_surface.set_color(tint)
		_surface.set_normal(normal)
		_surface.add_vertex(vertex)
