extends RefCounted
## Second authored generation: occupied-cell garments, articulated wrists,
## and open silhouette. No inherited mannequin or decorative render shell.

static func dimensions(kind: String) -> Dictionary:
	if kind == "ink_master": return {"dimensions":Vector3i(78,76,114),"cell":0.06}
	if kind == "ink_crane": return {"dimensions":Vector3i(82,52,50),"cell":0.05}
	if kind == "ink_spear": return {"dimensions":Vector3i(52,64,112),"cell":0.05}
	if kind == "ink_talisman": return {"dimensions":Vector3i(70,66,30),"cell":0.05}
	return {"dimensions":Vector3i(44,64,92),"cell":0.05}

static func layout(kind: String) -> Dictionary:
	match kind:
		"ink_swordsman": return {"emitters":[_em(2,Vector3(0.40,1.17,2.12))],"melee_segments":[_seg(2,Vector3(0.76,1.40,0.58),Vector3(0.40,1.17,2.12),0.085)]}
		"ink_spear": return {"emitters":[_em(2,Vector3(0.76,1.48,2.575))],"melee_segments":[_seg(2,Vector3(0.76,1.48,0.55),Vector3(0.76,1.48,2.575),0.10)]}
		"ink_talisman": return {"emitters":[_em(2,Vector3(0.84,1.54,0.58))]}
		"ink_crane": return {"emitters":[_em(0,Vector3(0,2.16,1.18))]}
		"ink_master": return {"name":"双腕锁剑横梁","supports":[{"part":1,"point":Vector3(-1.32,2.18,0.42),"load_bounds":AABB(Vector3(-1.70,1.70,1.35),Vector3(0.32,1.2,1.2))},{"part":2,"point":Vector3(1.32,2.18,0.42),"load_bounds":AABB(Vector3(1.38,1.70,1.35),Vector3(0.32,1.2,1.2))}],"emitters":[_em(1,Vector3(-1.54,2.16,3.20)),_em(2,Vector3(1.54,2.16,3.20))],"melee_segments":[_seg(1,Vector3(-1.54,2.16,0.82),Vector3(-1.54,2.16,3.20),0.09),_seg(2,Vector3(1.54,2.16,0.82),Vector3(1.54,2.16,3.20),0.09)]}
	return {}

static func _em(part: int, point: Vector3) -> Dictionary: return {"part":part,"point":point,"radius":0.19}
static func _seg(part: int,a: Vector3,b: Vector3,r: float) -> Dictionary: return {"part":part,"a":a,"b":b,"radius":r}

static func boss_modules(_kind: String) -> Array:
	return [
		{"core":Vector3(-0.46,2.30,0.23),"mount":Vector3(-0.34,1.76,-0.24),"tag_size":0.21},
		{"core":Vector3(0.55,2.92,-0.58),"mount":Vector3(0.36,2.46,-0.37),"tag_size":0.21},
	]

static func build(e,b: Script) -> void:
	var k := str(e.enemy_kind)
	if k == "ink_crane":
		_crane(e,b)
		return
	var s := 1.45 if k == "ink_master" else 1.0
	var heavy := k == "ink_spear"
	var caster := k == "ink_talisman"
	_frame(e,b,s,heavy,caster)
	_hat(e,b,s,0.94 if k == "ink_master" else (0.70 if k == "ink_swordsman" else 0.51),caster)
	if k == "ink_swordsman":
		_blade(e,b,Vector3(0.76,1.40,0.58),Vector3(0.40,1.17,2.12),2,0.13)
		b._rod(e,Vector3(0.76,1.40,0.58),Vector3(0.72,1.45,0.12),0.085,7,2)
		b._rod(e,Vector3(0.54,1.40,0.57),Vector3(0.95,1.40,0.57),0.065,3,2)
		b._rod(e,Vector3(-0.71,1.32,0.20),Vector3(-0.40,0.55,-0.78),0.105,7,1)
		for n in range(3): b._rod(e,Vector3(-0.70+n*0.045,1.29-n*0.12,0.15-n*0.16),Vector3(-0.54+n*0.045,1.29-n*0.12,0.15-n*0.16),0.04,3,1)
	elif k == "ink_spear":
		b._rod(e,Vector3(0.76,1.48,-1.20),Vector3(0.76,1.48,2.48),0.07,8,2)
		b._depth_wedge(e,Vector3(0.76,1.48,2.37),Vector3(0.32,0.13,0.62),0.02,6,2)
		b._rod(e,Vector3(0.76,1.48,1.98),Vector3(0.76,1.48,2.22),0.12,3,2)
		for n in range(4):
			_plate(e,Vector3(-0.78,2.17-n*0.14,0.02),Vector3(0.83,0.15,0.62),Vector3(0,0,-0.17),7 if n%2 else 9,1)
			b._rod(e,Vector3(-1.12,2.19-n*0.14,0.33),Vector3(-0.52,2.19-n*0.14,0.33),0.035,1,1)
	elif caster:
		_seal_frame(e,b)
	else:
		_master(e,b)
	if k == "ink_master":
		var modules := boss_modules(k)
		for module: Dictionary in modules:
			var seal: Vector3 = module.core
			var mount: Vector3 = module.mount
			b._rod(e,mount,seal,0.17,7)
			b._rod(e,mount,Vector3(0,mount.y+0.10,-0.04),0.16,2)
			_plate(e,seal,Vector3(0.36,0.43,0.35),Vector3.ZERO,3)
			b._ring_cells(e,seal+Vector3(0,0,0.20),0.15,0.093,0.05,1,0,true)
			b._box(e,seal+Vector3(0,0,0.20),Vector3(0.14,0.19,0.10),4)
		b._finish_boss(e,Vector3(0,1.78,0)*s,Vector3(0,2.40,0)*s,modules)
	else:
		b._finish(e,Vector3(0,1.78,0)*s,Vector3(0,1.13,0)*s,Vector3(0,2.40,0)*s)

static func _plate(e,c: Vector3,size: Vector3,rotation: Vector3,mat: int,part: int = 0) -> void:
	var basis := Basis.from_euler(rotation)
	var reach := Vector3.ONE*size.length()*0.5
	var limits: Array[Vector3i] = e._slasher_grid_bounds(c-reach,c+reach)
	var half := size*0.5
	var bevel := minf(size.x,size.y)*0.21
	for z in range(limits[0].z,limits[1].z+1):
		for y in range(limits[0].y,limits[1].y+1):
			for x in range(limits[0].x,limits[1].x+1):
				var p: Vector3 = (basis.transposed()*(Vector3(e._point(x,y,z))-c)).abs()
				if p.x>half.x or p.y>half.y or p.z>half.z: continue
				if maxf(p.x-half.x+bevel,0)+maxf(p.y-half.y+bevel,0)>bevel: continue
				var i: int = e._index(x,y,z)
				e._voxels[i]=mat
				e._series_authored_parts[i]=part

static func _frame(e,b: Script,s: float,heavy: bool,caster: bool) -> void:
	# Slender black skeleton, pinched waist and independently layered panels.
	b._ellipsoid(e,Vector3(0,1.72,-0.05)*s,Vector3(0.77 if heavy else 0.65,0.88,0.48)*s,7)
	b._rod(e,Vector3(0,1.08,-0.04)*s,Vector3(0,2.22,-0.04)*s,0.19*s,2)
	b._ellipsoid(e,Vector3(0,1.13,-0.03)*s,Vector3(0.62,0.30,0.43)*s,7)
	b._ellipsoid(e,Vector3(0,2.40,0.00)*s,Vector3(0.42,0.42,0.41)*s,7)
	# Split ivory mandibles describe a pointed V; the eye sockets stay black.
	b._taper(e,Vector3(0,2.29,0.29)*s,Vector3(0.075,0.21,0.12)*s,Vector2(0,0.25)*s,0.27*s,1)
	for side in [-1.0,1.0]:
		b._rod(e,Vector3(side*0.17,2.43,0.28)*s,Vector3(side*0.055,2.22,0.32)*s,0.055*s,1)
		b._rod(e,Vector3(side*0.02,2.445,0.34)*s,Vector3(side*0.15,2.475,0.31)*s,0.037*s,4)
		b._rod(e,Vector3(side*0.03,2.51,0.27)*s,Vector3(side*0.22,2.55,0.16)*s,0.045*s,7)
		# Flat narrow crossover lapels sit over broad dark faceted chest leaves.
		_plate(e,Vector3(side*0.18,1.83,0.25)*s,Vector3(0.30,0.66,0.16)*s,Vector3(0,side*0.17,-side*0.16),2)
		_plate(e,Vector3(side*0.065,1.85,0.37)*s,Vector3(0.105,0.67,0.10)*s,Vector3(-0.04,0,-side*0.68),1)
		_plate(e,Vector3(side*0.17,1.82,0.39)*s,Vector3(0.055,0.62,0.065)*s,Vector3(-0.04,0,-side*0.68),9)
		var arm := 1 if side<0 else 2
		var shoulder := Vector3(side*0.49,2.02,0)*s
		var elbow := Vector3(side*(0.70 if not caster else 0.87),1.62,0.04)*s
		var hand := Vector3(side*(0.74 if not caster else 0.84),1.42 if not caster else 1.54,0.32)*s
		b._rod(e,Vector3(side*0.30,2.02,0)*s,shoulder,0.14*s,7,arm)
		b._ellipsoid(e,shoulder,Vector3.ONE*0.28*s,9,arm)
		b._rod(e,shoulder,elbow,0.11*s,7,arm)
		b._rod(e,elbow,hand,0.105*s,7,arm)
		b._ellipsoid(e,elbow,Vector3.ONE*0.23*s,5,arm)
		for n in range(3):
			var sh := shoulder.lerp(elbow,float(n)*0.27)
			_plate(e,sh+Vector3(side*(0.05+n*0.018),0.03,0.01)*s,Vector3(0.48 if heavy else 0.36,0.22,0.43)*s,Vector3(0.14,side*0.07,side*(0.36+n*0.08)),1 if n==0 else 2,arm)
		_plate(e,hand+Vector3(0,0,0.04)*s,Vector3(0.30,0.29,0.32)*s,Vector3(-0.25,0,0),7,arm)
		b._rod(e,hand+Vector3(-0.10,0.08,0.18)*s,hand+Vector3(0.10,0.08,0.18)*s,0.04*s,3,arm)
		var leg := 3 if side<0 else 4
		var boot := 5 if side<0 else 6
		var knee := Vector3(side*0.31,0.66,side*0.08)*s
		var ankle := Vector3(side*0.36,0.20,0.04-side*0.07)*s
		b._rod(e,Vector3(side*0.23,1.10,0)*s,knee,0.115*s,7,leg)
		b._ellipsoid(e,knee,Vector3(0.28,0.27,0.28)*s,9,leg)
		b._rod(e,knee,ankle,0.09*s,7,leg)
		_plate(e,knee+Vector3(0,-0.14,0.12)*s,Vector3(0.25,0.38,0.13)*s,Vector3(-0.15,0,side*0.07),1,leg)
		_plate(e,Vector3(side*0.36,0.135,0.17-side*0.07)*s,Vector3(0.34,0.24,0.59)*s,Vector3.ZERO,7,boot)
		b._rod(e,ankle,Vector3(side*0.36,0.12,0.22-side*0.07)*s,0.12*s,7,boot)
		_plate(e,Vector3(side*0.36,0.20,0.29-side*0.07)*s,Vector3(0.30,0.11,0.31)*s,Vector3.ZERO,9,boot)
		# Long black tassets fan from the belt. Staggered grey edges catch light;
		# separated tails preserve the legs' negative space during the lunge.
		for column in range(3):
			var top := Vector3(side*(0.17+column*0.13),1.17,-0.055)*s
			var bottom := Vector3(side*(0.27+column*0.30),0.31+column*0.085 if caster else 0.41+column*0.08,-0.16-column*0.04)*s
			b._rod(e,top,bottom,0.06*s,7,leg)
			for row in range(5):
				var t := (float(row)+0.5)/5.0
				var at := top.lerp(bottom,t)+Vector3(0,0,0.09*s)
				_plate(e,at,Vector3((0.27+0.09*t)*s,0.205*s,0.14*s),Vector3(-0.08,side*0.08,-side*(0.12+column*.14)),7 if row%2 else 2,leg)
				b._rod(e,at+Vector3(-0.11*s,-0.07*s,0.075*s),at+Vector3(0.11*s,-0.07*s,0.075*s),0.025*s,5,leg)
				if row==0: b._box(e,at+Vector3(0,0.02,0.09*s),Vector3(0.08,0.12,0.05)*s,3,leg)
		# Waist rope, knot and hanging crimson ends remain true cells.
		b._rod(e,Vector3(side*0.29,1.23,-0.14)*s,Vector3(side*0.32,1.23,0.22)*s,0.07*s,3)
	b._box(e,Vector3(0,1.23,0.27)*s,Vector3(0.62,0.10,0.13)*s,3)
	for side in [-1.0,1.0]: b._rod(e,Vector3(side*0.08,1.22,0.30)*s,Vector3(side*0.17,0.77,0.29)*s,0.045*s,3,3 if side<0 else 4)

static func _hat(e,b: Script,s: float,radius: float,tall: bool) -> void:
	var low := Vector3(-radius,2.54,-radius*0.76)*s
	var high := Vector3(radius,3.03 if tall else 2.88,radius*0.76)*s
	var limits: Array[Vector3i] = e._slasher_grid_bounds(low,high)
	var height := 0.46 if tall else 0.30
	for z in range(limits[0].z,limits[1].z+1):
		for y in range(limits[0].y,limits[1].y+1):
			for x in range(limits[0].x,limits[1].x+1):
				var p: Vector3 = Vector3(e._point(x,y,z))/s
				var r := Vector2(p.x,p.z/0.76).length()
				var surface := 2.55+height*(1.0-r/radius)
				if r>radius or p.y>surface or p.y<surface-0.075: continue
				var i: int = e._index(x,y,z)
				e._voxels[i]=1 if int(r/(radius/5.0))%2==0 else 9
				e._series_authored_parts[i]=0
	b._rod(e,Vector3(0,2.45,0)*s,Vector3(0,2.87,0)*s,0.11*s,7)
	for n in range(10):
		var angle := TAU*float(n)/10.0
		var rim := Vector3(sin(angle)*radius,2.56,cos(angle)*radius*0.76)*s
		b._rod(e,Vector3(0,2.55+height,0)*s,rim,0.025*s,7)
		if n in [2,3,7,8]:
			var tassel := rim*Vector3(0.88,1,0.88)
			b._rod(e,tassel+Vector3(0,0.065*s,0),tassel-Vector3(0,0.26*s,0),0.035*s,3)
	b._box(e,Vector3(0,2.60+height,0)*s,Vector3(0.15,0.10,0.15)*s,3)

static func _blade(e,b: Script,a: Vector3,tip: Vector3,part: int,width: float) -> void:
	var previous := a
	for n in range(9):
		var t := float(n+1)/9.0
		var at := a.lerp(tip,t)+Vector3(sin(t*PI)*0.10,-sin(t*PI)*0.08,0)
		b._rod(e,previous,at,width*(1.0-t*0.70),6,part)
		b._rod(e,previous-Vector3(width*0.38,0,0),at-Vector3(width*0.38*(1.0-t),0,0),0.028,9,part)
		previous=at

static func _seal_frame(e,b: Script) -> void:
	for side in [-1.0,1.0]:
		var arm := 1 if side<0 else 2
		var previous := Vector3(side*0.43,2.04,-0.15)
		for n in range(4):
			var angle := -0.70+float(n)*0.53
			var at := Vector3(side*(0.83+cos(angle)*0.69),2.35+sin(angle)*0.87,-0.23)
			b._rod(e,previous,at,0.045,7,arm)
			b._ellipsoid(e,at,Vector3.ONE*0.17,9,arm)
			b._box(e,at+Vector3(0,-0.22,0.03),Vector3(0.24,0.46,0.07),1,arm)
			for stroke in range(4):
				b._box(e,at+Vector3(0.035 if stroke%2 else -0.035,-0.09-stroke*0.085,0.09),Vector3(0.12,0.045,0.05),3,arm)
			b._rod(e,at+Vector3(0,-0.08,0.09),at+Vector3(0,-0.36,0.09),0.025,3,arm)
			previous=at
		# Huge falling sleeves rather than the sword user's narrow vambraces.
		for n in range(4): _plate(e,Vector3(side*(0.82+n*0.03),1.55-n*0.13,0.03),Vector3(0.42,0.18,0.33),Vector3(0,0,side*0.18),1 if n%2 else 2,arm)
	b._ellipsoid(e,Vector3(0.84,1.54,0.53),Vector3(0.22,0.22,0.23),3,2)

static func _master(e,b: Script) -> void:
	for side in [-1.0,1.0]:
		var arm := 1 if side<0 else 2
		var plate := 7 if side<0 else 8
		# Distinct external red coupling and floating casket beyond a narrow neck.
		b._rod(e,Vector3(side*1.04,2.18,0.42),Vector3(side*1.54,2.18,0.42),0.11,3,arm)
		_plate(e,Vector3(side*1.54,2.25,0.80),Vector3(0.30,0.52,0.72),Vector3(0,0,side*0.08),7,arm)
		for rib in range(4): b._box(e,Vector3(side*1.54,2.07+rib*0.12,1.12),Vector3(0.32,0.06,0.13),1,arm)
		_blade(e,b,Vector3(side*1.54,2.16,0.82),Vector3(side*1.54,2.16,3.20),arm,0.115)
		# Hinged breast leaves are true individually owned occupied material.
		_plate(e,Vector3(side*0.26,2.63,0.45),Vector3(0.46,0.90,0.18),Vector3(0,-side*0.15,-side*0.40),7,plate)
		b._rod(e,Vector3(side*0.64,3.08,0.42),Vector3(side*0.07,2.25,0.59),0.085,1,plate)
		b._rod(e,Vector3(side*0.16,2.28,0.31),Vector3(side*0.54,3.02,0.32),0.055,9,plate)
		b._box(e,Vector3(side*0.10,2.51,0.63),Vector3(0.15,0.18,0.10),3,plate)
		# Shoulder-tier silhouette flares well beyond the thin torso.
		for n in range(3):
			var broad := 1.14 if side<0 else 0.93
			_plate(e,Vector3(side*(0.83+n*0.13),3.04-n*0.16,0.025+n*0.04),Vector3(0.64*broad,0.31,0.64),Vector3(0.12,side*.11,side*(0.42+n*.12)),1 if n==0 else (9 if n==1 else 2),arm)
			b._rod(e,Vector3(side*(0.60+n*.11),3.08-n*.16,.36),Vector3(side*(1.10+n*.11),2.87-n*.16,.36),.06,7,arm)

static func _crane(e,b: Script) -> void:
	b._depth_wedge(e,Vector3(0,1.58,-0.02),Vector3(0.52,0.44,0.94),0.35,1)
	b._rod(e,Vector3(0,1.68,0.23),Vector3(0,2.21,0.80),0.075,7)
	b._depth_wedge(e,Vector3(0,2.16,1.00),Vector3(0.22,0.22,0.43),0.05,3)
	for side in [-1.0,1.0]:
		var arm := 1 if side<0 else 2
		b._rod(e,Vector3(side*0.13,1.65,0),Vector3(side*1.73,2.27,-0.42),0.075,7,arm)
		for n in range(7):
			var at := Vector3(side*(0.30+n*0.22),1.73+n*0.081,-0.14-n*0.035)
			_plate(e,at+Vector3(side*0.07,-0.08,-0.22),Vector3(0.38,0.13,0.70-n*0.035),Vector3(0.15,side*0.28,-side*0.35),1 if n%3 else 9,arm)
			b._rod(e,at,at+Vector3(side*0.12,-0.13,-0.52),0.025,3,arm)
		b._rod(e,Vector3(side*0.12,1.40,-0.27),Vector3(side*0.28,0.96,-0.78),0.045,7,3 if side<0 else 4)
		b._depth_wedge(e,Vector3(side*0.14,1.50,-0.70),Vector3(0.19,0.13,0.76),0.12,1)
		b._rod(e,Vector3(0,1.56,-0.20),Vector3(side*0.14,1.50,-0.76),0.06,7)
	b._finish(e,Vector3(0,1.58,0),Vector3(0,1.48,-0.18),Vector3(0,2.14,0.85))

static func _hinge(at: Vector3,angles: Vector3,offset: Vector3 = Vector3.ZERO) -> Transform3D:
	var basis := Basis.from_euler(angles)
	return Transform3D(basis,at-basis*at+offset)

static func pose(kind: String,action: String,phase: float,age: float,lane: int,integrity: Dictionary) -> Dictionary:
	var p := clampf(phase,0,1)
	var s := 1.45 if kind=="ink_master" else 1.0
	var parts: Dictionary = {}
	var rig := Transform3D.IDENTITY
	var side := -1.0 if lane%2==0 else 1.0
	if kind=="ink_crane":
		for arm in [1,2]: parts[arm]=_hinge(Vector3((-0.15 if arm==1 else 0.15),1.65,0),Vector3(0,0,(-1.0 if arm==1 else 1.0)*(sin(age*6.0)*0.26+0.13)))
		rig.origin.y=sin(age*3.2)*0.08
		if action=="charge": rig=_hinge(Vector3(0,1.6,0),Vector3(-0.26*sin(p*PI),0,side*0.16))
	else:
		var gait := sin(age*8.2)*(0.25 if action=="run" else 0.0)
		for arm in [1,2]:
			var sign := -1.0 if arm==1 else 1.0
			var angles := Vector3(0,0,sign*0.10)
			if kind=="ink_swordsman":
				if action in ["windup","charge"]: angles=Vector3(-0.32,sign*0.95*smoothstep(0,0.7,p),sign*0.22)
				elif action=="strike": angles=Vector3(0.08,-sign*lerpf(-0.95,0.66,smoothstep(0.12,0.76,p)),sign*0.10)
				elif action=="recover": angles=Vector3(0.08*(1-p),-sign*0.66*(1-p),sign*0.10)
			elif kind=="ink_spear":
				if arm==2:
					angles=Vector3(0,0.25,0)
					if action in ["windup","charge"]: angles=Vector3(-0.12,0.55,0)
					elif action=="strike": angles=Vector3(0.015,lerpf(0.55,-0.34,smoothstep(0.12,0.48,p)),0)
					elif action=="fire": angles=Vector3(0,lerpf(0.55,-0.34,smoothstep(0.12,0.48,p)),0)
			elif kind=="ink_talisman":
				angles=Vector3(-0.08+sin(age*2+sign)*0.04,0,sign*0.12)
				if action=="charge": angles=Vector3(-0.25,sign*0.45*sin(p*PI*0.5),sign*0.32)
				elif action=="fire": angles=Vector3(0.15,-sign*0.20,sign*0.10)
			else:
				var alternate := -1.0 if int(integrity.get("series_attack_variant",0))%2 else 1.0
				angles=Vector3(-0.10,sign*0.58,sign*0.12)
				if action in ["windup","charge"]: angles=Vector3(-0.22,sign*0.80,sign*0.25)
				elif action=="strike":
					var reverse := alternate<0
					angles=Vector3(0.15 if reverse else 0.34,sign*lerpf(0.80,-0.75,smoothstep(0.08 if reverse else 0.04,0.74 if reverse else 0.65,p))*alternate,sign*0.12)
				elif action=="fire": angles=Vector3(-0.05,sign*0.12,sign*0.12)
			parts[arm]=_hinge(Vector3(sign*0.48,2.0,0)*s,angles)
		for leg in [3,4]:
			var sign := -1.0 if leg==3 else 1.0
			parts[leg]=_hinge(Vector3(sign*0.23,1.1,0)*s,Vector3(gait*sign,0,0))
			parts[leg+2]=parts[leg]
		if action=="strike":
			var drive := sin(p*PI)
			rig=_hinge(Vector3(0,1.1,0)*s,Vector3(0.06*drive,side*0.08*drive,0),Vector3(0,0,0.45*drive))
		elif kind=="ink_master" and action!="entry":
			# The default guard has a twisted waist and loaded back leg, not a T-pose.
			rig=_hinge(Vector3(0,1.1,0)*s,Vector3(0.18,-side*0.22,0),Vector3(0,0,0))
			parts[3]=_hinge(Vector3(-0.23,1.1,0)*s,Vector3(-0.27,0,-0.10))
			parts[5]=parts[3]
			parts[4]=_hinge(Vector3(0.23,1.1,0)*s,Vector3(0.16,0,0.08))
			parts[6]=parts[4]
		if action=="entry" and bool(integrity.get("series_entry_authored",false)):
			parts={}
			rig=Transform3D.IDENTITY
		var active: Array = integrity.get("support_active",[])
		if kind=="ink_master":
			for n in range(mini(2,active.size())):
				if not bool(active[n]): parts[7+n]=_hinge(Vector3(-0.68 if n==0 else 0.68,2.9,0.36),Vector3(0,-1.2 if n==0 else 1.2,0))
	if action=="death":
		var fall := smoothstep(0.25,0.86,p)
		rig=_hinge(Vector3(0,1.1,0)*s,Vector3(fall*0.70,fall*side*0.12,0),Vector3(0,-0.38*fall*s,0))
		if kind=="ink_master":
			# Formal kneeling blade salute before the red seal discharge.
			for arm in [1,2]: parts[arm]=_hinge(Vector3((-0.48 if arm==1 else 0.48),2,0)*s,Vector3(-0.18,-0.6 if arm==1 else 0.6,0))
	var result := {"rig":rig,"parts":parts}
	if kind!="ink_crane" and action not in ["death","entry"]: _seat_boots(result,s)
	return result

static func entry(kind: String,p: float,lane: int) -> Dictionary:
	var side := -1.0 if lane%2==0 else 1.0
	var s := 1.45 if kind=="ink_master" else 1.0
	var data := {"offset":Vector3.ZERO,"rotation":Vector3.ZERO,"opacity":1.0,"rig":Transform3D.IDENTITY,"parts":{},"impact_phase":0.36}
	if p>=1 or kind=="ink_crane": return data
	var boss := kind=="ink_master"
	var enter := 1.0-smoothstep(0,0.36,p)
	var hold := smoothstep(0.12,0.36,p)*(1.0-smoothstep(0.72,1.0,p))
	var draw := smoothstep(0.39,0.66,p)*(1.0-smoothstep(0.76,1.0,p))
	data.opacity=1.0 if boss else smoothstep(0,0.32,p)
	data.offset=Vector3(side*2.2*enter,0 if kind!="ink_spear" else sin(clampf(p/0.36,0,1)*PI)*1.9,-35*enter if not boss else -7*enter)
	data.rotation.y=-side*0.65*enter
	if kind=="ink_swordsman":
		data.rig=_hinge(Vector3(0,1.1,0),Vector3(0.25*hold,-side*0.35*hold,0),Vector3(0,-0.25*hold,0))
		data.parts[1]=_hinge(Vector3(-0.48,2,0),Vector3(0,-0.45*hold,-0.25*hold))
		data.parts[2]=_hinge(Vector3(0.48,2,0),Vector3(-0.2*hold,1.1*hold-1.7*draw,0.15*hold))
	elif kind=="ink_spear":
		data.parts[2]=_hinge(Vector3(0.48,2,0),Vector3(-1.25*enter,0.4*hold,0))
		data.rig=_hinge(Vector3(0,1.1,0),Vector3(0.18*hold,0,0),Vector3(0,0,0))
	elif kind=="ink_talisman":
		for arm in [1,2]: data.parts[arm]=_hinge(Vector3(-0.48 if arm==1 else 0.48,2,0),Vector3(0,(-1.0 if arm==1 else 1.0)*1.2*(1.0-smoothstep(0.30,0.72,p)),0))
	else:
		data.offset.y=1.65*enter
		data.rig=_hinge(Vector3(0,1.1,0)*s,Vector3(0.16*hold,0,0),Vector3(0,-0.22*hold,0))
		for arm in [1,2]: data.parts[arm]=_hinge(Vector3(-0.48 if arm==1 else 0.48,2,0)*s,Vector3(-0.35*hold,(-1.0 if arm==1 else 1.0)*(.82*hold-.65*draw),0))
	_seat_boots(data,s)
	return data

static func _seat_boots(data: Dictionary,s: float) -> void:
	var low := INF
	for side in [-1.0,1.0]:
		var transform := Transform3D(data.rig)*Transform3D(data.parts.get(5 if side<0 else 6,Transform3D.IDENTITY))
		for x in [-0.17,0.17]:
			for z in [-0.295,0.295]: low=minf(low,(transform*(Vector3(side*0.36+x,0,0.17-side*0.07+z)*s)).y)
	data.rig.origin.y-=low

