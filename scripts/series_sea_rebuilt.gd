extends RefCounted
## Authored occupied-cell aquatic machines. No inherited humanoid hull.

static func dimensions(kind: String) -> Dictionary:
	match kind:
		"sea_leviathan": return {"dimensions":Vector3i(82,48,66),"cell":0.10}
		"sea_crab": return {"dimensions":Vector3i(78,35,58),"cell":0.06}
		"sea_skimmer": return {"dimensions":Vector3i(56,42,68),"cell":0.05}
		"sea_eel": return {"dimensions":Vector3i(40,48,80),"cell":0.05}
	return {"dimensions":Vector3i(100,48,70),"cell":0.05}

static func layout(kind: String) -> Dictionary:
	match kind:
		"sea_leviathan":
			var supports: Array = []
			for i in range(4):
				var side := -1.0 if i%2 == 0 else 1.0
				var z := -1.65 if i<2 else 1.65
				supports.append({"part":3+i,"point":Vector3(side*2.60,1.45,z),"load_bounds":AABB(Vector3(-4.1 if side<0 else 3.0,0,z-0.55),Vector3(1.1,0.9,1.1))})
			return {"name":"四足外露承力杆","supports":supports,"emitters":[_em(1,Vector3(-1.65,4.1,2.2)),_em(2,Vector3(1.65,4.1,2.2))]}
		"sea_crab": return {"emitters":[_em(1,Vector3(-1.65,1.62,1.25)),_em(2,Vector3(1.65,1.62,1.25))],"melee_segments":[_seg(1,Vector3(-1.65,1.62,0.8),Vector3(-1.4,1.62,1.45),0.13),_seg(2,Vector3(1.65,1.62,0.8),Vector3(1.4,1.62,1.45),0.13)]}
		"sea_skimmer": return {"emitters":[_em(2,Vector3(1.12,1.12,1.1))],"melee_segments":[_seg(1,Vector3(-0.55,1.12,0.3),Vector3(-1.17,1.12,1.2),0.10),_seg(2,Vector3(0.55,1.12,0.3),Vector3(1.17,1.12,1.2),0.10)]}
		"sea_eel": return {"emitters":[_em(9,Vector3(-0.65,1.62,-1.65))]}
	return {"emitters":[_em(1,Vector3(-0.48,0.85,0.91)),_em(2,Vector3(0.48,0.85,0.91))]}

static func _em(part: int, point: Vector3) -> Dictionary: return {"part":part,"point":point,"radius":0.24}
static func _seg(part: int,a: Vector3,b: Vector3,r: float) -> Dictionary: return {"part":part,"a":a,"b":b,"radius":r}

static func boss_modules(_kind: String) -> Array:
	return [
		{"core":Vector3(-0.63,2.06,0.95),"mount":Vector3(-0.63,2.60,-0.45),"tag_size":0.26},
		{"core":Vector3(0.64,2.64,1.48),"mount":Vector3(0.72,2.88,-0.90),"tag_size":0.26},
	]

static func build(e,b: Script) -> void:
	match str(e.enemy_kind):
		"sea_leviathan": _leviathan(e,b)
		"sea_crab": _crab(e,b)
		"sea_skimmer": _skimmer(e,b)
		"sea_eel": _eel(e,b)
		_: _ray(e,b)

static func _hinge(at: Vector3, angles: Vector3, offset: Vector3 = Vector3.ZERO) -> Transform3D:
	var basis := Basis.from_euler(angles)
	return Transform3D(basis,at-basis*at+offset)

static func _plate(e,_b: Script,c: Vector3,s: Vector3,m: int,p: int=0,angles: Vector3=Vector3.ZERO) -> void:
	# Sculpted solid plates with planform bevels and rotated load surfaces;
	# all stairs are occupied voxels, never a smooth non-cuttable overlay.
	var basis := Basis.from_euler(angles)
	var half := s*0.5
	var reach := Vector3(absf(basis.x.x)*half.x+absf(basis.y.x)*half.y+absf(basis.z.x)*half.z,absf(basis.x.y)*half.x+absf(basis.y.y)*half.y+absf(basis.z.y)*half.z,absf(basis.x.z)*half.x+absf(basis.y.z)*half.y+absf(basis.z.z)*half.z)
	var bounds: Array[Vector3i] = e._slasher_grid_bounds(c-reach,c+reach)
	var inverse := basis.transposed()
	var plan_bevel := minf(s.x,s.z)*0.22
	var edge_bevel := minf(s.x,s.y)*0.20
	for z in range(bounds[0].z,bounds[1].z+1):
		for y in range(bounds[0].y,bounds[1].y+1):
			for x in range(bounds[0].x,bounds[1].x+1):
				var q: Vector3 = inverse*(Vector3(e._point(x,y,z))-c)
				if q.abs().x>half.x or q.abs().y>half.y or q.abs().z>half.z: continue
				if maxf(absf(q.x)-half.x+plan_bevel,0.0)+maxf(absf(q.z)-half.z+plan_bevel,0.0)>plan_bevel: continue
				if maxf(absf(q.x)-half.x+edge_bevel,0.0)+maxf(absf(q.y)-half.y+edge_bevel,0.0)>edge_bevel: continue
				var index: int = e._index(x,y,z)
				e._voxels[index] = m
				e._series_authored_parts[index] = p

static func _snout(e,c: Vector3,size: Vector3,mat: int,part: int=0) -> void:
	var limits: Array[Vector3i] = e._slasher_grid_bounds(c-size*0.5,c+size*0.5)
	for z in range(limits[0].z,limits[1].z+1):
		for y in range(limits[0].y,limits[1].y+1):
			for x in range(limits[0].x,limits[1].x+1):
				var point: Vector3 = e._point(x,y,z)
				var t := clampf((point.z-c.z+size.z*0.5)/size.z,0.0,1.0)
				var width := size.x*0.5*(1.0-t*0.87)
				var height := size.y*0.5*(1.0-t*0.65)
				if absf(point.x-c.x)>width or absf(point.y-c.y+t*size.y*0.18)>height: continue
				if absf(point.x-c.x)/maxf(width,0.001)+absf(point.y-c.y+t*size.y*0.18)/maxf(height,0.001)>1.65: continue
				var index: int = e._index(x,y,z)
				e._voxels[index] = mat
				e._series_authored_parts[index] = part

static func _leviathan(e,b: Script) -> void:
	# Long horizontal predator spine, separate animal head and load-bearing limbs.
	b._ellipsoid(e,Vector3(0,2.7,-0.45),Vector3(3.4,2.1,4.0),7)
	b._rod(e,Vector3(0,2.8,-2.2),Vector3(0,2.85,1.8),0.55,5)
	for side in [-1.0,1.0]:
		for row in range(5):
			var z := -1.8+row*0.68
			var arch := sin(float(row)/4.0*PI)*0.32
			_plate(e,b,Vector3(side*0.88,3.35+arch,z),Vector3(1.8,0.30,0.9),2,9,Vector3(-0.18+float(row)*0.07,side*0.10,-side*0.26))
			b._rod(e,Vector3(side*0.6,2.95,z),Vector3(side*0.88,3.35+arch,z),0.12,5,9)
			b._rod(e,Vector3(side*0.25,3.57,z),Vector3(side*1.57,3.48,z+0.15),0.065,1,9)
			b._taper(e,Vector3(side*0.88,3.86,z-0.10),Vector3(0.22,0.80-row*0.07,0.48),Vector2(side*1.05,z-0.30),0.08,2,9)
		# Serrated cheek and jaw masses wrap a genuinely hollow maw.
		_plate(e,b,Vector3(side*0.75,3.0,1.65),Vector3(1.0,1.05,1.75),2,0,Vector3(-0.12,side*0.18,-side*0.18))
		_plate(e,b,Vector3(side*0.56,3.22,2.35),Vector3(0.56,0.27,1.45),1,0,Vector3(-0.18,side*0.28,-side*0.14))
		b._rod(e,Vector3(side*0.42,3.12,2.85),Vector3(side*0.87,3.17,1.6),0.08,4)
		b._rod(e,Vector3(side*0.70,2.29,1.65),Vector3(side*0.42,2.29,2.85),0.17,1)
		for tooth in range(5):
			var z := 1.3+tooth*0.34
			b._rod(e,Vector3(side*0.53,2.92,z),Vector3(side*0.45,2.65,z+0.13),0.09,6)
			b._rod(e,Vector3(side*0.51,2.35,z),Vector3(side*0.44,2.54,z+0.13),0.07,6)
		for gill in range(4):
			_plate(e,b,Vector3(side*1.35,2.78,0.6-gill*0.35),Vector3(0.19,0.68,0.20),1)
		# Shoulder missile stacks, each physically attached by its turret yoke.
		var arm := 1 if side<0 else 2
		b._rod(e,Vector3(side*1.0,3.1,-0.25),Vector3(side*1.65,3.95,0.2),0.22,8,arm)
		_plate(e,b,Vector3(side*1.65,4.10,0.95),Vector3(1.18,1.03,2.5),5,arm)
		for armor in range(4):
			_plate(e,b,Vector3(side*1.65,4.54+armor*0.012,-0.02+armor*0.56),Vector3(1.20,0.20,0.62),2 if armor%2==0 else 1,arm,Vector3(-0.12,0,side*0.07))
			for edge in [-1.0,1.0]:
				_plate(e,b,Vector3(side*1.65+edge*0.53,4.15,-0.02+armor*0.56),Vector3(0.15,0.64,0.41),1,arm,Vector3(-0.12,0,edge*0.25))
		b._box(e,Vector3(side*1.65,4.10,2.21),Vector3(0.92,0.79,0.19),7,arm)
		for row in range(2):
			for col in range(2):
				var p := Vector3(side*1.65+(col-0.5)*0.46,3.88+row*0.43,2.08)
				b._box(e,p,Vector3(0.33,0.32,0.34),7,arm)
				b._rod(e,p-Vector3(0,0,0.17),p+Vector3(0,0,0.16),0.095,3,arm)
		# Belly doors are real plate parts; open only after real limb disconnection.
		var door := 7 if side<0 else 8
		_plate(e,b,Vector3(side*0.48,2.05,1.25),Vector3(0.94,1.15,0.42),1,door)
		b._rod(e,Vector3(side*0.78,2.48,1.43),Vector3(side*0.27,1.59,1.43),0.07,8,door)
	for i in range(4):
		var side := -1.0 if i%2==0 else 1.0
		var z := -1.65 if i<2 else 1.65
		var p := 3+i
		var hip := Vector3(side*1.3,2.7,z*0.7)
		var knee := Vector3(side*2.60,1.45,z)
		var ankle := Vector3(side*3.35,0.34,z+0.12)
		b._ellipsoid(e,hip,Vector3(0.70,0.70,0.70),3,p)
		b._rod(e,hip,knee,0.18,8,p)
		b._rod(e,hip+Vector3(0,0.17,-0.16),knee+Vector3(0,0.17,-0.16),0.10,6,p)
		b._ellipsoid(e,knee,Vector3(0.46,0.46,0.52),3,p)
		_plate(e,b,hip.lerp(knee,0.36),Vector3(0.64,0.94,0.82),1,p,Vector3(0.14 if i<2 else -0.14,0,side*0.74))
		_plate(e,b,hip.lerp(knee,0.19)+Vector3(0,0.10,0.10),Vector3(0.78,0.24,0.88),2,p,Vector3(0,0,side*0.52))
		b._rod(e,hip+Vector3(0,-0.10,0.18),knee+Vector3(0,0.12,0.18),0.09,6,p)
		b._rod(e,knee,ankle,0.21,5,p)
		_plate(e,b,knee.lerp(ankle,0.58)+Vector3(side*0.12,0,0.10),Vector3(0.48,0.85,0.56),1,p,Vector3(0,0,side*0.36))
		_plate(e,b,ankle+Vector3(side*0.10,-0.18,0.20),Vector3(1.04,0.28,1.18),1,p)
		_plate(e,b,ankle+Vector3(side*0.10,0.02,0.09),Vector3(0.79,0.21,0.78),2,p)
		for toe in [-1.0,0.0,1.0]:
			b._rod(e,ankle+Vector3(toe*0.30,-0.14,0.3),ankle+Vector3(toe*0.35,-0.20,0.90),0.10,7,p)
			b._rod(e,ankle+Vector3(toe*0.29,-0.12,0.31),ankle+Vector3(toe*0.33,-0.12,0.65),0.10,6,p)
	# Core sits inside the open throat behind the two retained real doors.
	_snout(e,Vector3(0,3.12,2.0),Vector3(2.25,0.78,1.95),2)
	for row in range(3):
		_snout(e,Vector3(0,3.44-row*0.08,1.39+row*0.42),Vector3(1.90-row*0.35,0.18,0.67),1 if row==2 else 2)
	for side in [-1.0,1.0]:
		b._rod(e,Vector3(side*0.9,3.16,1.0),Vector3(side*1.2,3.67,1.45),0.10,1)
		b._rod(e,Vector3(side*0.78,2.32,1.0),Vector3(side*0.55,2.1,1.85),0.13,1)
		for cheek in range(3): _plate(e,b,Vector3(side*(0.83-cheek*0.14),2.79-cheek*0.19,1.32+cheek*0.22),Vector3(0.36,0.21,0.55),1,0,Vector3(-0.28,side*0.25,-side*0.30))
	# Two recessed pumps have separate feed pipes into the flanks of the spine.
	b._rod(e,Vector3(0,2.15,0.83),Vector3(0,2.65,-0.2),0.23,7)
	var modules := boss_modules("sea_leviathan")
	for module: Dictionary in modules:
		var core: Vector3 = module.core
		var mount: Vector3 = module.mount
		b._rod(e,mount,core,0.23,5)
		b._rod(e,mount,Vector3(0,2.80,mount.z-0.25),0.23,8)
		b._ellipsoid(e,core,Vector3(0.54,0.54,0.77),4)
		for ring in [-0.18,0.18]:
			b._ring_cells(e,core+Vector3(0,0,ring),0.31,0.20,0.08,8,0,true)
		b._rod(e,core+Vector3(0,-0.26,0.14),core+Vector3(0,0.26,0.14),0.075,6)
	b._finish_boss(e,Vector3(0,2.15,0.8),Vector3(0,3.10,1.85),modules)

static func _crab(e,b: Script) -> void:
	# Low broad carapace, six separate scuttling legs and two independent pincers.
	b._ellipsoid(e,Vector3(0,1.08,-0.1),Vector3(2.05,0.92,1.85),7)
	for row in range(4):
		for side in [-1.0,1.0]:
			_plate(e,b,Vector3(side*0.48,1.48+sin(row*0.8)*0.10,-0.83+row*0.45),Vector3(1.12-row*0.06,0.23,0.66),2,0,Vector3(-0.12,side*0.10,-side*0.26))
		for side in [-1.0,1.0]:
			_plate(e,b,Vector3(side*0.85,1.22,-0.77+row*0.43),Vector3(0.48,0.39,0.43),1)
			b._rod(e,Vector3(side*0.9,1.24,-0.77+row*0.43),Vector3(side*1.13,1.39,-0.87+row*0.43),0.06,3)
	for side in [-1.0,1.0]:
		var arm := 1 if side<0 else 2
		b._rod(e,Vector3(side*0.68,1.15,0.42),Vector3(side*1.48,1.58,0.62),0.13,8,arm)
		b._ellipsoid(e,Vector3(side*1.47,1.58,0.62),Vector3(0.50,0.42,0.55),3,arm)
		_plate(e,b,Vector3(side*1.65,1.62,0.92),Vector3(0.58,0.52,0.69),2,arm)
		for jaw in [-1.0,1.0]:
			b._rod(e,Vector3(side*1.65,1.62+jaw*0.18,0.9),Vector3(side*1.40,1.62+jaw*0.27,1.45),0.105,1,arm)
			b._rod(e,Vector3(side*1.4,1.62+jaw*0.27,1.45),Vector3(side*1.23,1.62+jaw*0.12,1.52),0.08,6,arm)
		b._rod(e,Vector3(side*0.38,1.45,0.55),Vector3(side*0.44,1.86,0.67),0.065,8)
		b._ellipsoid(e,Vector3(side*0.44,1.86,0.70),Vector3(0.25,0.17,0.25),4)
		for leg in range(3):
			var part := 3+leg*2+(0 if side<0 else 1)
			var z := -0.75+leg*0.64
			var hip := Vector3(side*0.72,0.96,z)
			var knee := Vector3(side*1.45,0.72,z-0.22)
			var foot := Vector3(side*2.05,0.11,z+0.14)
			b._rod(e,hip,knee,0.095,8,part)
			b._ellipsoid(e,knee,Vector3(0.29,0.29,0.32),3,part)
			b._rod(e,knee,foot,0.095,5,part)
			b._rod(e,foot,foot+Vector3(side*0.11,0,0.25),0.09,1,part)
	b._box(e,Vector3(0,1.10,0.72),Vector3(0.48,0.40,0.27),4)
	b._finish(e,Vector3(0,1.1,0.2),Vector3(0,1.02,-0.55),Vector3(0,1.5,0.6))
static func _skimmer(e,b: Script) -> void:
	# Slim forward hunter; no torso/head/arm reuse from the biped families.
	b._ellipsoid(e,Vector3(0,1.03,-0.13),Vector3(0.94,0.64,1.95),7)
	for row in range(4):
		for side in [-1.0,1.0]:
			_plate(e,b,Vector3(side*0.22,1.28,-0.80+row*0.48),Vector3(0.52-row*0.04,0.16,0.65),2,0,Vector3(-0.10,0,-side*0.32))
	_snout(e,Vector3(0,1.08,0.93),Vector3(0.78,0.46,1.12),1)
	b._box(e,Vector3(0,0.98,1.25),Vector3(0.36,0.09,0.25),7)
	for side in [-1.0,1.0]:
		var arm := 1 if side<0 else 2
		b._rod(e,Vector3(side*0.30,1.09,0.10),Vector3(side*0.67,1.12,0.48),0.105,8,arm)
		# A long horizontal scythe, initially folded outwards. Its swept volume
		# is supplied in layout; attack pose brings the actual blade inward.
		b._rod(e,Vector3(side*0.53,1.12,0.28),Vector3(side*1.17,1.12,1.20),0.095,6,arm)
		b._rod(e,Vector3(side*0.58,1.14,0.30),Vector3(side*1.14,1.14,0.98),0.05,3,arm)
		b._box(e,Vector3(side*0.24,1.2,0.70),Vector3(0.10,0.09,0.22),4)
		for tooth in range(4): b._rod(e,Vector3(side*(0.24-tooth*0.035),0.99,0.81+tooth*0.14),Vector3(side*(0.24-tooth*0.035),0.91,0.85+tooth*0.14),0.035,6)
		b._taper(e,Vector3(side*0.42,1.62,-0.5),Vector3(0.14,0.58,0.60),Vector2(side*0.64,-0.70),0.05,2,9)
		b._rod(e,Vector3(side*0.30,1.26,-0.58),Vector3(side*0.62,1.87,-0.73),0.065,2,9)
		for leg in range(2):
			var part := 3+leg*2+(0 if side<0 else 1)
			var z := -0.65 if leg==0 else 0.28
			b._rod(e,Vector3(side*0.30,0.92,z),Vector3(side*0.55,0.50,z-0.16),0.095,8,part)
			b._rod(e,Vector3(side*0.55,0.50,z-0.16),Vector3(side*0.63,0.13,z+0.03),0.085,5,part)
			_plate(e,b,Vector3(side*0.63,0.085,z+0.20),Vector3(0.25,0.14,0.70),1,part)
	b._taper(e,Vector3(0,1.62,-0.50),Vector3(0.19,0.76,0.58),Vector2(0,-0.79),0.07,2,9)
	b._rod(e,Vector3(0,1.03,-0.75),Vector3(0,1.13,-1.48),0.10,2,9)
	b._finish(e,Vector3(0,1.04,0.15),Vector3(0,0.99,-0.55),Vector3(0,1.1,0.96))
static func _eel(e,b: Script) -> void:
	var previous := Vector3(0,1.62,1.20)
	for segment in range(11):
		var t := float(segment)/10.0
		var point := Vector3(sin(t*PI*1.5)*0.65,1.62+sin(t*TAU)*0.20,1.2-t*2.85)
		var part := 0 if segment<5 else 9
		var radius := lerpf(0.22,0.11,t)
		b._rod(e,previous,point,radius,7,part)
		b._ellipsoid(e,point,Vector3(radius*2.8,radius*2.5,0.35),2 if segment%2==0 else 1,part)
		b._rod(e,point+Vector3(0,radius,0),point+Vector3(0,radius+0.18,0.06),0.05,3,part)
		if segment>6:
			b._ring_cells(e,point,0.24,0.13,0.07,8,part,true)
			b._box(e,point+Vector3(0,0.17,0.16),Vector3(0.13,0.12,0.13),4,part)
		previous = point
	_snout(e,Vector3(0,1.67,1.21),Vector3(0.78,0.51,0.96),1)
	for side in [-1.0,1.0]:
		_plate(e,b,Vector3(side*0.26,1.77,0.98),Vector3(0.25,0.16,0.55),2,0,Vector3(-0.1,side*0.2,-side*0.2))
	b._box(e,Vector3(0,1.54,1.54),Vector3(0.44,0.09,0.28),7)
	for side in [-1.0,1.0]:
		b._box(e,Vector3(side*0.22,1.78,0.98),Vector3(0.10,0.09,0.20),4)
		b._rod(e,Vector3(side*0.18,1.49,1.55),Vector3(side*0.18,1.55,1.69),0.04,6)
		b._rod(e,Vector3(side*0.22,1.66,0.9),Vector3(side*0.83,1.55,0.4),0.065,2,1 if side<0 else 2)
	# Exact tail emitter on the last physical capacitor, not a floating oracle.
	b._ellipsoid(e,previous,Vector3(0.28,0.30,0.31),4,9)
	for ring in [-1.0,1.0]: b._ring_cells(e,previous+Vector3(0,0,ring*0.12),0.24,0.12,0.045,8,9,true)
	b._finish(e,Vector3(0,1.63,1.10),Vector3(0.44,1.79,0.43),Vector3(0,1.67,1.43))
static func _ray(e,b: Script) -> void:
	# Kite-shaped thin planform, broken pinion silhouette and curled horns.
	_snout(e,Vector3(0,1.28,0.10),Vector3(1.15,0.78,2.1),2)
	for side in [-1.0,1.0]:
		var part := 1 if side<0 else 2
		b._rod(e,Vector3(side*0.30,1.22,0.20),Vector3(side*1.35,1.58,-0.45),0.10,8,part)
		b._rod(e,Vector3(side*1.35,1.58,-0.45),Vector3(side*2.22,1.69,-0.90),0.10,8,part)
		for strip in range(10):
			var x := 0.34+strip*0.20
			var z := -strip*0.09
			var rise := sin(float(strip)/9.0*PI)*0.26+float(strip)*0.038
			_plate(e,b,Vector3(side*x,1.19+rise,z),Vector3(0.29,0.15,1.85-strip*0.11),2 if strip%3 else 1,part,Vector3(-0.06,-side*0.14,side*(0.25-float(strip)*0.045)))
			if strip%2==0: b._rod(e,Vector3(side*x,1.29+rise,z-0.42),Vector3(side*x,1.30+rise,z+0.36),0.035,6,part)
		b._taper(e,Vector3(side*2.17,1.85,-0.84),Vector3(0.22,0.85,0.75),Vector2(side*2.36,-0.96),0.06,1,part)
		# Ventral tube is the vulnerable actual launch assembly.
		_plate(e,b,Vector3(side*0.48,0.85,0.43),Vector3(0.35,0.37,1.2),1,part)
		b._box(e,Vector3(side*0.48,0.85,0.94),Vector3(0.23,0.23,0.24),7,part)
		b._rod(e,Vector3(side*0.20,1.23,0.89),Vector3(side*0.38,1.34,1.30),0.065,1)
		b._box(e,Vector3(side*0.25,1.3,0.80),Vector3(0.13,0.07,0.21),4)
	b._rod(e,Vector3(0,1.13,-0.7),Vector3(0.12,1.12,-1.47),0.09,5,9)
	b._rod(e,Vector3(0.12,1.12,-1.47),Vector3(0.25,1.22,-1.58),0.06,3,9)
	b._finish(e,Vector3(0,1.18,0.18),Vector3(0,1.15,-0.45),Vector3(0,1.25,0.75))
static func pose(kind: String,action: String,phase: float,age: float,lane: int,integrity: Dictionary) -> Dictionary:
	var p := clampf(phase,0.0,1.0)
	var parts: Dictionary = {}
	var rig := Transform3D.IDENTITY
	var side := -1.0 if lane%2==0 else 1.0
	var load := sin(p*PI*0.5)
	var hit := smoothstep(0.12,0.56,p)*(1.0-smoothstep(0.72,1.0,p))
	var moving := action=="run"
	if kind=="sea_skimmer":
		var creep := sin(age*9.0)
		for i in range(4):
			var sign := -1.0 if i%2==0 else 1.0
			var z := -0.65 if i<2 else 0.28
			var stride := sin(age*9.0+i*PI*0.7)*0.12 if moving else 0.0
			parts[3+i] = Transform3D(Basis.IDENTITY,Vector3(0,maxf(stride,0.0)*0.45,stride))
		var furl := -0.35*load if action=="windup" else (0.9*hit if action=="strike" else 0.0)
		parts[1] = _hinge(Vector3(-0.30,1.09,0.10),Vector3(0,furl,0))
		parts[2] = _hinge(Vector3(0.30,1.09,0.10),Vector3(0,-furl,0))
		parts[9] = _hinge(Vector3(0,1.1,-0.65),Vector3(0,creep*0.05,0))
		if action=="strike": rig.origin = Vector3(0,sin(p*PI)*0.32,0.75*hit)
	elif kind=="sea_crab":
		for i in range(6):
			var stride := sin(age*7.5+i*PI*0.7)*0.13 if moving else 0.0
			parts[3+i] = Transform3D(Basis.IDENTITY,Vector3(stride*0.35,maxf(stride,0.0)*0.5,stride))
		var selected := 1 if int(integrity.get("series_attack_variant",0))%2==0 else 2
		for arm in [1,2]:
			var sign := -1.0 if arm==1 else 1.0
			var cock := (-0.38*load if action=="windup" else (1.17*hit if action=="strike" else 0.0)) if arm==selected else 0.0
			parts[arm] = _hinge(Vector3(sign*0.68,1.15,0.42),Vector3(0,-sign*cock,0),Vector3(0,0,0.65*hit if action=="strike" and arm==selected else 0.0))
		if action=="charge": parts[1] = _hinge(Vector3(-0.68,1.15,0.42),Vector3(0,-0.4*load,-0.4*load))
	elif kind=="sea_eel":
		var coil := sin(age*4.2)*0.22
		if action=="charge": coil = -0.85*load
		elif action=="fire": coil = lerpf(-0.85,0.85,smoothstep(0.05,0.7,p))
		elif action=="recover": coil = 0.85*(1.0-p)
		parts[9] = _hinge(Vector3(0.62,1.62,-0.04),Vector3(0,coil,0))
		parts[1] = _hinge(Vector3(-0.22,1.66,0.9),Vector3(0,0,sin(age*3.8)*0.3))
		parts[2] = _hinge(Vector3(0.22,1.66,0.9),Vector3(0,0,-sin(age*3.8)*0.3))
		rig.origin.y = sin(age*2.3)*0.11
	elif kind=="sea_ray":
		for arm in [1,2]:
			var sign := -1.0 if arm==1 else 1.0
			var bank := sin(age*2.1)*0.10
			if action=="charge": bank += 0.28*load
			elif action=="fire": bank += 0.28*(1.0-p)
			parts[arm] = _hinge(Vector3(sign*0.30,1.22,0.20),Vector3(0,0,sign*bank))
		parts[9] = _hinge(Vector3(0,1.13,-0.7),Vector3(0,sin(age*2.7)*0.17,0))
		rig.origin.y = sin(age*1.8)*0.10
	else:
		for i in range(4):
			var sign := -1.0 if i%2==0 else 1.0
			var z := -1.65 if i<2 else 1.65
			var gait := sin(age*3.5+i*PI*0.68)*0.12 if moving else 0.0
			parts[3+i] = Transform3D(Basis.IDENTITY,Vector3(0,maxf(gait,0.0)*0.7,gait))
		for arm in [1,2]:
			var sign := -1.0 if arm==1 else 1.0
			var recoil := -0.20*sin(p*PI) if action=="fire" else (-0.08*load if action=="charge" else 0.0)
			parts[arm] = _hinge(Vector3(sign*1.0,3.1,-0.25),Vector3(recoil,0,0))
		var missing := int(integrity.get("total_supports",0))-int(integrity.get("active_supports",0))
		var opening := clampf(float(missing)/4.0,0.0,1.0)
		parts[7] = _hinge(Vector3(-0.92,2.1,1.25),Vector3(0,-opening*1.55,0))
		parts[8] = _hinge(Vector3(0.92,2.1,1.25),Vector3(0,opening*1.55,0))
		if opening>0.0: rig = _hinge(Vector3(0,0.9,0),Vector3(0,0,side*opening*0.72),Vector3(0,-opening*0.18,0))
		parts[9] = _hinge(Vector3(0,3.1,-0.3),Vector3(sin(age*2.1)*0.018,0,0))
	if action=="entry" and bool(integrity.get("series_entry_authored",false)):
		return {"rig":Transform3D.IDENTITY,"parts":{}}
	if action=="death":
		var fall := smoothstep(0.17,0.87,p)
		if kind=="sea_leviathan":
			rig = _hinge(Vector3(0,0.85,0),Vector3(0.12*fall,0,side*fall*0.92),Vector3(0,-fall*0.2,0))
			# The corpse's remaining articulated legs stay planted while the
			# torso tears away between them. A real released part is absent from
			# the body mesh, so this never recalls or restores a detached leg.
			for leg in range(3,7): parts[leg] = rig.affine_inverse()
			for arm in [1,2]: parts[arm] = _hinge(Vector3(-1.0 if arm==1 else 1.0,3.1,-0.25),Vector3(-fall*0.45,0,0))
			parts[9] = _hinge(Vector3(0,3.1,-0.3),Vector3(0.2*fall,0,0))
		else: rig = _hinge(Vector3(0,0.7,0),Vector3(fall*0.15,0,side*fall*0.7))
	return {"rig":rig,"parts":parts}

static func entry(kind: String,phase: float,lane: int) -> Dictionary:
	var p := clampf(phase,0.0,1.0)
	var side := -1.0 if lane%2==0 else 1.0
	var data := {"offset":Vector3.ZERO,"rotation":Vector3.ZERO,"opacity":1.0,"rig":Transform3D.IDENTITY,"parts":{},"impact_phase":0.46}
	if p>=1.0: return data
	if kind in ["sea_eel","sea_ray"]: return data
	if kind=="sea_leviathan":
		var emerge := smoothstep(0.0,0.52,p)
		data.offset = Vector3(side*6.0*(1.0-emerge),3.3*sin(emerge*PI),-18.0*(1.0-emerge))
		data.rotation = Vector3(-0.20*sin(emerge*PI),-side*0.7*(1.0-emerge),side*0.18*sin(emerge*PI))
		var compression := smoothstep(0.40,0.54,p)*(1.0-smoothstep(0.63,0.94,p))
		data.rig.origin.y = -0.27*compression
		for i in range(4):
			var step := smoothstep(0.31+i*0.035,0.46+i*0.035,p)*(1.0-smoothstep(0.64,0.94,p))
			data.parts[3+i] = Transform3D(Basis.IDENTITY,Vector3(0,0.27*compression,(-0.18 if i<2 else 0.18)*step))
		for arm in [1,2]: data.parts[arm] = _hinge(Vector3(-1.0 if arm==1 else 1.0,3.1,-0.25),Vector3(-0.3*(1.0-smoothstep(0.55,0.9,p)),0,0))
		data.opacity = smoothstep(0.0,0.20,p)
		data.impact_phase = 0.52
	elif kind=="sea_crab":
		var climb := smoothstep(0.0,0.48,p)
		data.offset = Vector3(side*5.5*(1.0-climb),-1.3*(1.0-climb)+0.6*sin(climb*PI),-35.0*(1.0-climb))
		data.rotation = Vector3(0,-side*0.7*(1.0-climb),-side*0.35*(1.0-climb))
		for i in range(6):
			var step := sin(clampf((p-float(i)*0.035)/0.45,0.0,1.0)*PI)
			data.parts[3+i] = Transform3D(Basis.IDENTITY,Vector3(0,step*0.32,-step*0.26))
		for arm in [1,2]: data.parts[arm] = _hinge(Vector3(-0.68 if arm==1 else 0.68,1.15,0.42),Vector3(-0.5*(1.0-smoothstep(0.4,0.85,p)),0,0))
		data.opacity = smoothstep(0.0,0.25,p)
		data.impact_phase = 0.48
	else:
		var leap := smoothstep(0.0,0.42,p)
		data.offset = Vector3(side*4.7*(1.0-leap),-0.8*(1.0-leap)+1.6*sin(leap*PI),-35.0*(1.0-leap))
		data.rotation = Vector3(-0.18*sin(leap*PI),-side*0.65*(1.0-leap),side*0.20*sin(leap*PI))
		var unfold := 1.0-smoothstep(0.33,0.8,p)
		data.parts[1] = _hinge(Vector3(-0.3,1.09,0.1),Vector3(0,-0.6*unfold,0))
		data.parts[2] = _hinge(Vector3(0.3,1.09,0.1),Vector3(0,0.6*unfold,0))
		data.opacity = smoothstep(0.0,0.25,p)
		data.impact_phase = 0.42
	return data
