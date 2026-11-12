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
const NEW_KINDS := ["sword_wave","ink_spear","seal","buckshot","needle","beacon","electric_wave","torpedo","plasma_lance","cannon_orb"]
const KINDS := ["bolt","shock","missile","mine"]+NEW_KINDS


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
	if kind in NEW_KINDS: return _build_series(kind)
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
	# The signal_tint cap is also a solid, but its colour can change after reflection.
	var cap := AABB(indicator_position-indicator_size*0.5,indicator_size)
	var cap_points := PackedVector3Array()
	for index in range(8): cap_points.append(cap.get_endpoint(index))
	_hulls.append(cap_points)
	var mesh := _surface.commit()
	return {"mesh":mesh,"hulls":_hulls,"bounds":mesh.get_aabb().merge(cap),"indicator_size":indicator_size,"indicator_position":indicator_position,"exhaust_start":exhaust_start,"exhaust_size":exhaust_size,"radius":radius}


func _build_series(kind: String) -> Dictionary:
	var paper := Color("e6e0d2")
	var ink := Color("25222a")
	var cinnabar := Color("b52b35")
	var signal_tint := Color(1.8,0.3,0.25)
	var exhaust := Color(1.7,0.45,0.22)
	var size := Vector3(0.06,0.06,0.04)
	var at := Vector3.ZERO
	var radius := 0.2
	var exhaust_at := -0.4
	var exhaust_size := 0.07
	var exhaust_count := 2
	var roll_speed := 0.0
	match kind:
		"sword_wave":
			# Six separate convex crescent strips preserve the open concavity.
			for arc in range(6):
				_arc_strip(-72.0+arc*24.0,-48.0+arc*24.0,0.65,0.90,Vector2(0,-0.55),-0.065,0.065,paper if arc%2 == 0 else ink)
			_arc_strip(-24,24,0.65,0.72,Vector2(0,-0.55),0.065,0.095,cinnabar)
			at = Vector3(0,0.22,0.105)
			size = Vector3(0.10,0.10,0.04)
			radius = 0.91
			exhaust_count = 0
		"ink_spear":
			_prism(Vector2(0.065,0.065),Vector2(0.065,0.065),-0.86,0.47,ink)
			_prism(Vector2(0.26,0.10),Vector2(0.035,0.035),0.42,1.04,paper)
			_prism(Vector2(0.13,0.13),Vector2(0.11,0.11),0.31,0.47,cinnabar)
			_prism(Vector2(0.10,0.10),Vector2(0.065,0.065),-1.02,-0.86,cinnabar)
			for side in [-1.0,1.0]:
				_prism(Vector2(0.12,0.045),Vector2(0.035,0.045),-0.9,-0.50,paper,Vector3(side*0.08,0,0),Basis.IDENTITY,Vector2(-side*0.045,0))
			at = Vector3(0,0,1.05)
			radius = 0.16
			exhaust_count = 0
		"seal":
			_prism(Vector2(0.42,0.72),Vector2(0.42,0.72),-0.035,0.035,paper)
			for side in [-1.0,1.0]:
				_box(Vector3(0.035,0.59,0.025),Vector3(side*0.155,0,0.045),cinnabar)
				_box(Vector3(0.28,0.035,0.025),Vector3(0,side*0.27,0.045),cinnabar)
			_box(Vector3(0.07,0.34,0.035),Vector3(0,0,0.055),ink)
			for line in [-0.13,0.02,0.15]: _box(Vector3(0.20,0.045,0.035),Vector3(0,line,0.055),cinnabar)
			at = Vector3(0,0.02,0.08)
			radius = 0.42
			exhaust_count = 0
			roll_speed = 1.8
		"buckshot":
			_octahedron(Vector3(0.13,0.13,0.18),STEEL)
			_prism(Vector2(0.16,0.16),Vector2(0.16,0.16),-0.035,0.035,COPPER)
			at = Vector3(0,0,0.18)
			size = Vector3(0.055,0.055,0.035)
			radius = 0.14
			exhaust_at = -0.18
			exhaust_size = 0.035
			exhaust_count = 1
			signal_tint = Color(1.8,1.05,0.36)
		"needle":
			_prism(Vector2(0.045,0.045),Vector2(0.065,0.065),-0.45,0.20,STEEL)
			_prism(Vector2(0.065,0.065),Vector2(0.008,0.008),0.20,0.75,Color("adc5ce"))
			for index in range(3):
				var rotation := Basis(Vector3.BACK,float(index)*TAU/3.0)
				_prism(Vector2(0.10,0.018),Vector2(0.025,0.018),-0.42,-0.20,STEEL,rotation*Vector3(0.05,0,0),rotation,Vector2(-0.025,0))
			at = Vector3(0,0,0.76)
			size = Vector3(0.025,0.025,0.025)
			radius = 0.105
			exhaust_at = -0.46
			exhaust_size = 0.026
			exhaust_count = 1
			signal_tint = Color(0.38,1.5,1.8)
		"beacon":
			_octahedron(Vector3(0.17,0.22,0.17),DARK)
			for index in range(3):
				var angle := float(index)*TAU/3.0
				var rotation := Basis(Vector3.BACK,angle)
				_prism(Vector2(0.16,0.09),Vector2(0.16,0.09),-0.13,0.13,STEEL,rotation*Vector3(0.23,0,0),rotation)
				_prism(Vector2(0.13,0.09),Vector2(0.045,0.06),-0.16,0.23,Color("6bb7c5"),rotation*Vector3(0.33,0,0),rotation,Vector2(-0.035,0))
			at = Vector3(0,0,0.185)
			size = Vector3(0.10,0.10,0.09)
			radius = 0.41
			exhaust_count = 0
			roll_speed = 1.2
			signal_tint = Color(0.38,1.7,1.8)
		_:
			return _build_series_heavy(kind)
	return _finish_series(size,at,radius,exhaust_at,exhaust_size,exhaust_count,signal_tint,exhaust,roll_speed)


func _build_series_heavy(kind: String) -> Dictionary:
	var navy := Color("203d50")
	var pearl := Color("bddfd2")
	var sea_light := Color("65efd1")
	var imperial := Color("454363")
	var gold := Color("c6a75a")
	var light := Color("c2b8ff")
	if kind == "electric_wave":
		for segment in range(8):
			_arc_strip(segment*45.0,segment*45.0+45.0,0.46,0.62,Vector2.ZERO,-0.055,0.055,sea_light if segment%2 == 0 else navy)
			var rotation := Basis(Vector3.BACK,float(segment)*TAU/8.0)
			_prism(Vector2(0.14,0.055),Vector2(0.055,0.055),-0.04,0.11,pearl,rotation*Vector3(0.60,0,0),rotation,Vector2(0.035,0))
		return _finish_series(Vector3(0.08,0.08,0.055),Vector3(0.55,0,0.10),0.72,-0.06,0.03,0,Color(0.45,1.8,1.4),Color(0.2,1.6,1.3),1.5)
	if kind == "torpedo":
		_prism(Vector2(0.30,0.30),Vector2(0.36,0.36),-0.47,0.18,navy)
		_prism(Vector2(0.36,0.36),Vector2(0.08,0.08),0.18,0.67,pearl)
		_prism(Vector2(0.20,0.20),Vector2(0.30,0.30),-0.65,-0.47,sea_light)
		for side in [-1.0,1.0]:
			_prism(Vector2(0.45,0.055),Vector2(0.12,0.055),-0.40,0.12,pearl,Vector3(side*0.30,0,0),Basis.IDENTITY,Vector2(-side*0.12,0))
			_box(Vector3(0.06,0.06,0.68),Vector3(side*0.10,0.15,-0.05),sea_light)
		_prism(Vector2(0.055,0.30),Vector2(0.055,0.10),-0.46,-0.05,navy,Vector3(0,-0.18,0))
		return _finish_series(Vector3(0.07,0.07,0.045),Vector3(0,0,0.68),0.54,-0.66,0.10,3,Color(0.65,1.8,1.5),Color(0.3,1.5,1.3),0.0)
	if kind == "plasma_lance":
		_prism(Vector2(0.13,0.13),Vector2(0.15,0.15),-0.9,0.35,imperial)
		_prism(Vector2(0.15,0.15),Vector2(0.018,0.018),0.35,1.12,light)
		_prism(Vector2(0.72,0.72),Vector2(0.68,0.68),-0.30,-0.20,gold)
		for index in range(3):
			var rotation := Basis(Vector3.BACK,float(index)*TAU/3.0)
			_prism(Vector2(0.12,0.12),Vector2(0.035,0.035),-0.30,0.72,light,rotation*Vector3(0.30,0,0),rotation,Vector2(-0.06,0))
		return _finish_series(Vector3(0.045,0.045,0.04),Vector3(0,0,1.13),0.43,-0.92,0.09,3,Color(1.3,1.0,1.9),Color(1.1,0.7,1.8),0.6)
	# A faceted pressure orb and eight independent equatorial armor sectors.
	_icosahedron(0.31,light)
	for segment in range(8): _arc_strip(segment*45.0,segment*45.0+45.0,0.27,0.35,Vector2.ZERO,-0.055,0.055,gold if segment%2 == 0 else imperial)
	_prism(Vector2(0.12,0.12),Vector2(0.10,0.10),0.23,0.33,imperial)
	return _finish_series(Vector3(0.08,0.08,0.05),Vector3(0,0,0.345),0.36,-0.32,0.09,2,Color(1.2,1.0,1.8),Color(0.8,0.6,1.6),0.9)


func _finish_series(size: Vector3, at: Vector3, radius: float, exhaust_start: float, exhaust_size: float, exhaust_count: int, signal_tint: Color, exhaust: Color, roll_speed: float) -> Dictionary:
	var cap := AABB(at-size*0.5,size)
	var vertices := PackedVector3Array()
	for index in range(8): vertices.append(cap.get_endpoint(index))
	_hulls.append(vertices)
	var mesh := _surface.commit()
	return {"mesh":mesh,"hulls":_hulls,"bounds":mesh.get_aabb().merge(cap),"indicator_size":size,"indicator_position":at,"radius":radius,"exhaust_start":exhaust_start,"exhaust_size":exhaust_size,"exhaust_count":exhaust_count,"signal_tint":signal_tint,"exhaust_tint":exhaust,"roll_speed":roll_speed}


func _arc_strip(start_degrees: float, end_degrees: float, inner: float, outer: float, center: Vector2, z0: float, z1: float, tint: Color) -> void:
	var a := deg_to_rad(start_degrees)
	var b := deg_to_rad(end_degrees)
	var va := Vector2(sin(a),cos(a))
	var vb := Vector2(sin(b),cos(b))
	_extrude([center+va*inner,center+va*outer,center+vb*outer,center+vb*inner],z0,z1,tint)


func _extrude(polygon: Array[Vector2], z0: float, z1: float, tint: Color) -> void:
	var vertices := PackedVector3Array()
	var faces: Array = []
	var n := polygon.size()
	for point in polygon: vertices.append(Vector3(point.x,point.y,z0))
	for point in polygon: vertices.append(Vector3(point.x,point.y,z1))
	for index in range(1,n-1):
		faces.append([0,index+1,index])
		faces.append([n,n+index,n+index+1])
	for index in range(n):
		var next := (index+1)%n
		faces.append([index,next,n+next])
		faces.append([index,n+next,n+index])
	_polyhedron(vertices,faces,tint)


func _octahedron(size: Vector3, tint: Color) -> void:
	var vertices := PackedVector3Array([Vector3(size.x,0,0),Vector3(0,size.y,0),Vector3(-size.x,0,0),Vector3(0,-size.y,0),Vector3(0,0,size.z),Vector3(0,0,-size.z)])
	_polyhedron(vertices,[[0,1,4],[1,2,4],[2,3,4],[3,0,4],[1,0,5],[2,1,5],[3,2,5],[0,3,5]],tint)


func _icosahedron(radius: float, tint: Color) -> void:
	var t := (1.0+sqrt(5.0))*0.5
	var vertices := PackedVector3Array([Vector3(-1,t,0),Vector3(1,t,0),Vector3(-1,-t,0),Vector3(1,-t,0),Vector3(0,-1,t),Vector3(0,1,t),Vector3(0,-1,-t),Vector3(0,1,-t),Vector3(t,0,-1),Vector3(t,0,1),Vector3(-t,0,-1),Vector3(-t,0,1)])
	for index in range(vertices.size()): vertices[index] = vertices[index].normalized()*radius
	_polyhedron(vertices,[[0,11,5],[0,5,1],[0,1,7],[0,7,10],[0,10,11],[1,5,9],[5,11,4],[11,10,2],[10,7,6],[7,1,8],[3,9,4],[3,4,2],[3,2,6],[3,6,8],[3,8,9],[4,9,5],[2,4,11],[6,2,10],[8,6,7],[9,8,1]],tint)


func _polyhedron(vertices: PackedVector3Array, faces: Array, tint: Color) -> void:
	_hulls.append(vertices)
	var center := Vector3.ZERO
	for vertex in vertices: center += vertex
	center /= vertices.size()
	for face: Array in faces:
		var a: Vector3 = vertices[face[0]]
		var b: Vector3 = vertices[face[1]]
		var c: Vector3 = vertices[face[2]]
		if (b-a).cross(c-a).dot((a+b+c)/3.0-center) < 0.0: _triangle(a,c,b,tint)
		else: _triangle(a,b,c,tint)


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

