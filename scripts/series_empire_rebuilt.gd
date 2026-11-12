extends RefCounted
## Occupied-cell orbital machines. The hull is an open, load-bearing frame
## under thin stepped armor, rather than a solid box with cosmetic fins.

static func dimensions(kind: String) -> Dictionary:
	match kind:
		"empire_dreadnought": return {"dimensions":Vector3i(132,62,126),"cell":0.14}
		"empire_walker": return {"dimensions":Vector3i(86,58,84),"cell":0.06}
		"empire_fighter": return {"dimensions":Vector3i(92,48,90),"cell":0.06}
		"empire_lancer": return {"dimensions":Vector3i(56,64,106),"cell":0.05}
	return {"dimensions":Vector3i(72,66,88),"cell":0.05}

static func _em(part: int,p: Vector3,r: float = 0.22) -> Dictionary: return {"part":part,"point":p,"radius":r}
static func _seg(part: int,a: Vector3,b: Vector3,r: float) -> Dictionary: return {"part":part,"a":a,"b":b,"radius":r}
static func _sp(part: int,p: Vector3,box: AABB) -> Dictionary: return {"part":part,"point":p,"load_bounds":box}

static func boss_modules(_kind: String) -> Array:
	return [
		{"core":Vector3(-1.25,2.83,3.51),"mount":Vector3(-1.28,2.30,0.42),"tag_size":0.30},
		{"core":Vector3(1.10,3.46,2.61),"mount":Vector3(1.58,3.42,-0.82),"tag_size":0.30},
	]

static func layout(kind: String) -> Dictionary:
	match kind:
		"empire_walker": return {"name":"四足架炮承力杆","supports":[_sp(3,Vector3(-1.26,1.35,-0.9),AABB(Vector3(-2.5,0,-1.7),Vector3(1.2,1.0,1.1))),_sp(4,Vector3(1.26,1.35,-0.9),AABB(Vector3(1.3,0,-1.7),Vector3(1.2,1.0,1.1))),_sp(5,Vector3(-1.26,1.35,0.9),AABB(Vector3(-2.5,0,0.6),Vector3(1.2,1.0,1.1))),_sp(6,Vector3(1.26,1.35,0.9),AABB(Vector3(1.3,0,0.6),Vector3(1.2,1.0,1.1)))],"emitters":[_em(1,Vector3(-0.9,2.56,2.05)),_em(2,Vector3(0.9,2.56,2.05))]}
		"empire_lancer": return {"name":"外露推进架","supports":[_sp(9,Vector3(-0.58,2.18,-0.28),AABB(Vector3(-1.0,1.6,-0.9),Vector3(0.42,1.0,0.5)))],"emitters":[_em(2,Vector3(0.72,1.40,2.48))],"melee_segments":[_seg(2,Vector3(0.72,1.40,0.68),Vector3(0.72,1.40,2.48),0.12)]}
		"empire_sentinel": return {"name":"棱盾承力铰链","supports":[_sp(1,Vector3(-0.71,1.63,0.45),AABB(Vector3(-1.65,0.35,0.65),Vector3(0.8,2.3,0.45)))],"emitters":[_em(2,Vector3(0.70,1.60,1.84))],"melee_segments":[_seg(1,Vector3(-1.25,0.56,0.88),Vector3(-1.25,2.35,0.88),0.19)]}
		"empire_fighter": return {"emitters":[_em(1,Vector3(-1.25,1.28,1.0)),_em(2,Vector3(1.25,1.28,1.0))]}
		"empire_dreadnought": return {"name":"三组悬置电容承力颈","supports":[_sp(3,Vector3(-5.1,4.15,-1.5),AABB(Vector3(-6.3,4.5,-2.1),Vector3(1.2,1.5,1.4))),_sp(4,Vector3(5.1,4.15,-1.5),AABB(Vector3(5.1,4.5,-2.1),Vector3(1.2,1.5,1.4))),_sp(5,Vector3(0,6.45,-4.1),AABB(Vector3(-0.8,7.0,-4.8),Vector3(1.6,1.3,1.5)))],"emitters":[_em(1,Vector3(-4.1,2.6,4.3),0.36),_em(2,Vector3(4.1,2.6,4.3),0.36),_em(0,Vector3(0,1.92,6.5),0.35)]}
	return {}

static func build(e,b: Script) -> void:
	match str(e.enemy_kind):
		"empire_walker": _walker(e,b)
		"empire_lancer": _infantry(e,b,false)
		"empire_sentinel": _infantry(e,b,true)
		"empire_fighter": _fighter(e,b)
		"empire_dreadnought": _dreadnought(e,b)

static func _panel(e,center: Vector3,size: Vector3,rotation: Vector3,material: int,part: int = 0) -> void:
	var basis := Basis.from_euler(rotation)
	var half := size*0.5
	var extent := basis.x.abs()*half.x+basis.y.abs()*half.y+basis.z.abs()*half.z
	var limits: Array[Vector3i] = e._slasher_grid_bounds(center-extent,center+extent)
	var horizontal := size.y<=size.z
	var bevel := minf(size.x,size.z if horizontal else size.y)*0.19
	for z in range(limits[0].z,limits[1].z+1):
		for y in range(limits[0].y,limits[1].y+1):
			for x in range(limits[0].x,limits[1].x+1):
				var p: Vector3 = (basis.transposed()*(Vector3(e._point(x,y,z))-center)).abs()
				if p.x>half.x or p.y>half.y or p.z>half.z: continue
				if maxf(p.x-half.x+bevel,0)+maxf((p.z-half.z if horizontal else p.y-half.y)+bevel,0)>bevel: continue
				var index: int = e._index(x,y,z)
				e._voxels[index]=material
				e._series_authored_parts[index]=part

static func _walker(e,b: Script) -> void:
	# Broad low gun carriage over four splayed, jointed legs.
	b._box(e,Vector3(0,2.12,-0.15),Vector3(1.58,0.48,1.80),7)
	b._rod(e,Vector3(0,1.42,-0.15),Vector3(0,2.72,-0.15),0.28,2)
	b._depth_wedge(e,Vector3(0,2.53,0.08),Vector3(1.80,0.77,1.62),0.64,1)
	for leg in range(4):
		var side := -1.0 if leg%2==0 else 1.0
		var depth := -0.92 if leg<2 else 0.92
		var part := 3+leg
		var hip := Vector3(side*0.66,1.91,depth*0.62)
		var knee := Vector3(side*1.65,0.98,depth)
		var ankle := Vector3(side*1.95,0.26,depth*1.29)
		b._ellipsoid(e,hip,Vector3.ONE*0.46,8,part)
		b._rod(e,hip,knee,0.14,7,part)
		b._rod(e,knee,ankle,0.13,5,part)
		b._rod(e,hip+Vector3(0,-0.13,0.12),knee+Vector3(0,-0.12,0.12),0.065,8,part)
		_panel(e,hip.lerp(knee,0.60)+Vector3(0,0.09,0),Vector3(0.37,0.68,0.68),Vector3(0,0,side*0.72),1,part)
		b._ellipsoid(e,knee,Vector3.ONE*0.34,2,part)
		b._box(e,knee+Vector3(0,0,0.19),Vector3(0.26,0.20,0.12),8,part)
		_panel(e,ankle+Vector3(0,0.15,0),Vector3(0.39,0.39,0.48),Vector3(0,0,side*0.20),1,part)
		b._box(e,Vector3(ankle.x,0.12,ankle.z+0.10),Vector3(0.58,0.24,0.70),7,part)
		for toe in [-1.0,1.0]: b._depth_wedge(e,Vector3(ankle.x+toe*0.16,0.10,ankle.z+0.38),Vector3(0.18,0.20,0.38),0.45,1,part)
	for side in [-1.0,1.0]:
		var part := 1 if side<0 else 2
		b._rod(e,Vector3(side*0.52,2.32,-0.48),Vector3(side*0.90,2.56,-0.48),0.22,8,part)
		b._box(e,Vector3(side*0.90,2.56,-0.58),Vector3(0.65,0.68,1.04),2,part)
		b._depth_wedge(e,Vector3(side*0.90,2.56,0.42),Vector3(0.42,0.42,1.65),0.78,2,part)
		for section in range(5):
			var z := -0.12+float(section)*0.32
			_panel(e,Vector3(side*0.90,2.80,z),Vector3(0.57,0.13,0.24),Vector3(0.06,0,0),1,part)
			_panel(e,Vector3(side*1.15,2.56,z),Vector3(0.12,0.42,0.24),Vector3(0,0,-side*0.12),9 if section%2 else 1,part)
		for dy in [-0.16,0.16]: b._rod(e,Vector3(side*0.90,2.56+dy,-0.18),Vector3(side*0.90,2.56+dy,1.88),0.075,8,part)
		# Open barrel mouth with four lips, no flat glowing end-cap.
		for axis in [Vector3(0.18,0,0),Vector3(-0.18,0,0),Vector3(0,0.18,0),Vector3(0,-0.18,0)]:
			b._rod(e,Vector3(side*0.90,2.56,1.10)+axis,Vector3(side*0.90,2.56,1.97)+axis,0.075,7,part)
			b._box(e,Vector3(side*0.90,2.56,1.97)+axis,Vector3(0.13,0.13,0.25),7,part)
		b._box(e,Vector3(side*0.90,2.56,2.05)+Vector3(0,0.17,0),Vector3(0.10,0.06,0.10),4,part)
		for strip in range(4): b._box(e,Vector3(side*1.22,2.50,-0.80+strip*0.21),Vector3(0.08,0.33,0.10),8,part)
	b._box(e,Vector3(0,2.62,0.88),Vector3(0.48,0.12,0.09),4)
	b._finish(e,Vector3(0,2.21,-0.15),Vector3(0,1.78,-0.15),Vector3(0,2.61,0.28))
	var supports: Array = []
	for data: Dictionary in layout("empire_walker").supports: supports.append(data.point)
	b._supports(e,supports,0.14)

static func _infantry(e,b: Script,shield: bool) -> void:
	# A narrow digitigrade cavalry chassis; the sentinel adds a wide single
	# shoulder and a separate kite shield, rather than changing its color.
	b._ellipsoid(e,Vector3(0,1.65,-0.04),Vector3(0.67,0.89,0.43),7)
	b._rod(e,Vector3(0,1.08,0),Vector3(0,2.28,0),0.16,5)
	b._depth_wedge(e,Vector3(0,1.81,0.12),Vector3(0.69 if shield else 0.58,0.70,0.30),0.57,2)
	for side in [-1.0,1.0]:
		_panel(e,Vector3(side*0.22,1.78,0.29),Vector3(0.21,0.57,0.11),Vector3(0,-side*0.24,-side*0.20),1)
		_panel(e,Vector3(side*0.18,2.01,0.30),Vector3(0.31,0.23,0.15),Vector3(0,-side*0.20,-side*0.24),9)
		for seam in range(3):
			b._rod(e,Vector3(side*0.08,1.50+seam*0.14,0.30),Vector3(side*0.27,1.57+seam*0.14,0.30),0.028,7)
		b._rod(e,Vector3(side*0.26,1.49,0.27),Vector3(side*0.33,1.96,0.25),0.035,8)
		var arm := 1 if side<0 else 2
		var shoulder := Vector3(side*0.48,2.0,0)
		var elbow := Vector3(side*0.63,1.66,0.08)
		var hand := Vector3(side*0.71,1.40,0.42)
		b._rod(e,Vector3(side*0.26,2.0,0),shoulder,0.12,7,arm)
		b._ellipsoid(e,shoulder,Vector3.ONE*0.31,8,arm)
		b._rod(e,shoulder,elbow,0.10,7,arm)
		b._rod(e,elbow,hand,0.10,5,arm)
		for layer in range(3):
			_panel(e,shoulder+Vector3(side*(0.08+layer*0.05),0.12-layer*0.13,0),Vector3(0.48 if shield and side<0 else 0.38,0.16,0.47),Vector3(0,side*0.1,side*0.30),1 if layer%2==0 else 9,arm)
		for layer in range(3): _panel(e,elbow.lerp(hand,0.15+0.30*layer)+Vector3(0,0,0.07),Vector3(0.30,0.18,0.29),Vector3(-0.40,0,0),1 if layer%2==0 else 2,arm)
		b._box(e,hand,Vector3(0.23,0.22,0.28),7,arm)
		var leg := 3 if side<0 else 4
		var foot := leg+2
		var hip := Vector3(side*0.23,1.12,-0.02)
		var knee := Vector3(side*0.34,0.66,0.13)
		var ankle := Vector3(side*0.29,0.20,-0.14)
		b._rod(e,hip,knee,0.11,7,leg)
		b._rod(e,knee,ankle,0.10,5,leg)
		b._ellipsoid(e,knee,Vector3.ONE*0.24,8,leg)
		_panel(e,hip.lerp(knee,0.55)+Vector3(0,0,0.07),Vector3(0.30,0.42,0.26),Vector3(-0.12,0,-side*0.18),1,leg)
		_panel(e,knee.lerp(ankle,0.52)+Vector3(0,0,0.09),Vector3(0.24,0.39,0.24),Vector3(0.30,0,0),1,leg)
		b._box(e,Vector3(ankle.x,0.11,0.04),Vector3(0.35,0.22,0.60),7,foot)
		b._depth_wedge(e,Vector3(ankle.x,0.13,0.24),Vector3(0.34,0.18,0.31),0.5,1,foot)
		for layer in range(3): _panel(e,Vector3(side*(0.31+layer*0.05),1.14-layer*0.15,0.05),Vector3(0.28,0.19,0.43),Vector3(0,0,-side*0.16),1 if layer==0 else 2,leg)
	b._ellipsoid(e,Vector3(0,2.36,0.02),Vector3(0.43,0.43,0.43),2)
	for side in [-1.0,1.0]:
		_panel(e,Vector3(side*0.12,2.34,0.23),Vector3(0.19,0.31,0.16),Vector3(0,side*0.32,-side*0.15),1)
		b._rod(e,Vector3(side*0.035,2.41,0.32),Vector3(side*0.18,2.45,0.26),0.026,4)
	b._depth_wedge(e,Vector3(0,2.22,0.27),Vector3(0.17,0.19,0.16),0.45,9)
	for side in [-1.0,1.0]: b._rod(e,Vector3(side*0.17,2.43,-0.03),Vector3(side*0.30,2.84,-0.12),0.045,1)
	b._rod(e,Vector3(0,2.47,-0.03),Vector3(0,2.97,-0.12),0.04,8)
	if shield:
		b._rod(e,Vector3(-0.61,1.65,0.16),Vector3(-1.21,1.65,0.86),0.10,8,1)
		for row in range(6):
			var width := 0.67 if row<4 else 0.67-float(row-3)*0.15
			_panel(e,Vector3(-1.21,2.36-row*0.34,0.86),Vector3(width,0.30,0.22),Vector3(0,0,0.05),1 if row%3 else 2,1)
			b._box(e,Vector3(-1.21,2.36-row*0.34,1.00),Vector3(0.045,0.25,0.07),8,1)
		b._rod(e,Vector3(-1.21,0.52,0.87),Vector3(-1.21,2.48,0.87),0.075,7,1)
		b._rod(e,Vector3(0.70,1.60,0.35),Vector3(0.70,1.60,1.84),0.105,2,2)
		for side in [-1.0,1.0]: b._rod(e,Vector3(0.70+side*0.13,1.60,0.64),Vector3(0.70+side*0.13,1.60,1.72),0.045,4,2)
		b._supports(e,[Vector3(-0.71,1.63,0.45)],0.12)
	else:
		b._rod(e,Vector3(0.72,1.40,-0.60),Vector3(0.72,1.40,2.48),0.065,8,2)
		b._depth_wedge(e,Vector3(0.72,1.40,2.22),Vector3(0.29,0.20,0.64),0.025,1,2)
		for side in [-1.0,1.0]: b._rod(e,Vector3(0.72+side*0.12,1.40,1.15),Vector3(0.72+side*0.12,1.40,2.18),0.045,4,2)
		# Only the gold neck joins this exposed booster to the chassis.
		b._rod(e,Vector3(-0.32,2.18,-0.15),Vector3(-0.78,2.18,-0.55),0.08,8,9)
		b._depth_wedge(e,Vector3(-0.78,2.02,-0.65),Vector3(0.38,0.74,0.40),0.72,2,9)
		for vent in range(3): b._box(e,Vector3(-0.78,1.80+vent*0.20,-0.86),Vector3(0.28,0.08,0.08),4,9)
		b._supports(e,[Vector3(-0.58,2.18,-0.28)],0.12)
	b._finish(e,Vector3(0,1.77,0),Vector3(0,1.14,0),Vector3(0,2.36,0.02))

static func _fighter(e,b: Script) -> void:
	b._depth_wedge(e,Vector3(0,1.40,0.12),Vector3(0.83,0.56,3.52),0.08,1)
	b._depth_wedge(e,Vector3(0,1.68,-0.30),Vector3(0.43,0.28,1.28),0.20,7)
	b._box(e,Vector3(0,1.74,-0.11),Vector3(0.29,0.07,0.61),8)
	for side in [-1.0,1.0]:
		var part := 1 if side<0 else 2
		b._rod(e,Vector3(side*0.25,1.39,-0.45),Vector3(side*2.36,1.63,-1.86),0.08,7,part)
		for n in range(7):
			var t := float(n)/6.0
			var at := Vector3(side*(0.48+1.82*t),1.41+0.22*t,-0.38-1.37*t)
			_panel(e,at,Vector3(0.43,0.13,1.28-0.37*t),Vector3(-0.06,side*0.39,side*0.13),1 if n%3 else 2,part)
			b._box(e,at+Vector3(0,0.095,-0.34),Vector3(0.10,0.055,0.34),8,part)
		b._rod(e,Vector3(side*0.76,1.29,-0.83),Vector3(side*1.25,1.28,1.00),0.10,2,part)
		b._box(e,Vector3(side*1.25,1.28,1),Vector3(0.16,0.15,0.15),4,part)
		b._depth_wedge(e,Vector3(side*0.55,1.20,-1.25),Vector3(0.40,0.38,0.66),0.78,2,part)
		b._box(e,Vector3(side*0.55,1.20,-1.60),Vector3(0.28,0.23,0.07),4,part)
		b._rod(e,Vector3(side*0.19,1.61,-1.14),Vector3(side*0.43,2.39,-1.75),0.06,1,9)
	b._finish(e,Vector3(0,1.42,-0.20),Vector3(0,1.39,-0.78),Vector3(0,1.48,1.16))

static func _hull_skin(e,part: int,side: float,central: bool) -> void:
	var bounds: Array[Vector3i] = e._slasher_grid_bounds(Vector3(-8.8,0.65,-6.6),Vector3(8.8,5.2,8.5))
	for z in range(bounds[0].z,bounds[1].z+1):
		for y in range(bounds[0].y,bounds[1].y+1):
			for x in range(bounds[0].x,bounds[1].x+1):
				var p: Vector3 = e._point(x,y,z)
				var t := (p.z+6.5)/(15.0 if central else 12.1)
				if t<0 or t>1: continue
				var width := lerpf(1.85,0.38,t) if central else lerpf(4.5,0.52,t)
				var height := lerpf(0.94,0.40,t) if central else lerpf(1.82,0.63,t)
				var cx := 0.0 if central else side*lerpf(3.55,2.0,t)
				var cy := lerpf(1.92,1.72,t) if central else lerpf(3.18,2.98,t)
				var q := absf(p.x-cx)/width+absf(p.y-cy)/height
				var thickness := float(e._cell)*1.65/minf(width,height)
				if q>1 or q<1.0-thickness: continue
				var material := 1 if p.y>cy else 2
				var strip := int(floor((p.z+7)*3.2))
				if strip%6==0: material=5
				elif strip%6==1 and p.y>cy: material=9
				if not central and absf(p.x-cx)>width*0.72: material=5 if strip%2 else 8
				var i: int = e._index(x,y,z)
				e._voxels[i]=material
				e._series_authored_parts[i]=part

static func _dreadnought(e,b: Script) -> void:
	# Deep faceted hulls, recessed machinery and a narrow long ventral prow.
	# All three volumes are thin physical skins around a real connected frame.
	_hull_skin(e,0,0,true)
	for side in [-1.0,1.0]: _hull_skin(e,1 if side<0 else 2,side,false)
	b._rod(e,Vector3(0,2.85,-5.9),Vector3(0,2.96,3.0),0.34,2)
	for side in [-1.0,1.0]:
		var wing := 1 if side<0 else 2
		for z in [-4.8,-2.4,0.0,2.4]:
			b._rod(e,Vector3(side*0.2,2.85,z),Vector3(side*5.7,3.0,z),0.17,5,wing)
			b._rod(e,Vector3(side*1.1,2.0,z),Vector3(side*3.7,4.2,z),0.12,8,wing)
		for rib in range(8):
			var z := -5.0+float(rib)*1.14
			var width := 3.2-float(rib)*0.27
			var at := Vector3(side*(3.55-float(rib)*0.14),4.34-float(rib)*0.08,z)
			_panel(e,at,Vector3(width,0.19,0.88),Vector3(0.08,side*0.12,-side*0.17),1 if rib%3 else 9,wing)
			b._rod(e,at-Vector3(0,0.32,0),at,0.10,2,wing)
			if rib%2==0:
				b._box(e,Vector3(side*(5.4-float(rib)*0.2),2.85,z),Vector3(0.44,0.35,0.67),7,wing)
				b._box(e,Vector3(side*(5.4-float(rib)*0.2+0.23),2.85,z),Vector3(0.09,0.13,0.36),4,wing)
		b._rod(e,Vector3(side*3.3,2.6,1.4),Vector3(side*4.1,2.6,2.7),0.21,5,wing)
		b._box(e,Vector3(side*4.1,2.6,2.55),Vector3(0.58,0.58,1.2),2,wing)
		for axis in [Vector3(0.24,0,0),Vector3(-0.24,0,0),Vector3(0,0.24,0),Vector3(0,-0.24,0)]:
			b._rod(e,Vector3(side*4.1,2.6,2.55)+axis,Vector3(side*4.1,2.6,4.30)+axis,0.12,7,wing)
		b._box(e,Vector3(side*4.1,2.84,4.3),Vector3(0.16,0.10,0.18),4,wing)
		for engine in range(3):
			var at := Vector3(side*(1.8+float(engine)*1.65),2.60,-5.9)
			b._depth_wedge(e,at,Vector3(0.87,0.81,1.1),0.8,2,wing)
			b._rod(e,at+Vector3(0,0,0.4),Vector3(at.x,2.85,-4.8),0.15,5,wing)
			b._box(e,at+Vector3(0,0,-0.57),Vector3(0.55,0.49,0.14),4,wing)
		var support := 3 if side<0 else 4
		b._rod(e,Vector3(side*4.7,3.7,-1.5),Vector3(side*5.1,4.15,-1.5),0.16,8,support)
		b._rod(e,Vector3(side*5.1,4.15,-1.5),Vector3(side*5.65,4.75,-1.5),0.16,8,support)
		_capacitor(e,b,Vector3(side*5.65,5.05,-1.5),support,1.0)
	# Separate armored feed racks flank the central throat. The shutters expose
	# both modules while their offset bulkheads preserve two power paths.
	var modules := boss_modules("empire_dreadnought")
	for module: Dictionary in modules:
		var core: Vector3 = module.core
		var mount: Vector3 = module.mount
		var side := signf(core.x)
		b._rod(e,mount,core,0.24,5)
		b._rod(e,mount,Vector3(0,2.85,mount.z),0.25,2)
		b._rod(e,mount,Vector3(side*2.25,3.1,mount.z-0.75),0.22,8)
		b._depth_wedge(e,core-Vector3(0,0,0.35),Vector3(1.10,1.13,1.55),0.69,2)
		b._ellipsoid(e,core,Vector3(0.67,0.67,0.91),4)
		for rib in [-0.26,0.26]:
			b._rod(e,core+Vector3(rib,-0.38,0.29),core+Vector3(rib,0.38,0.35),0.095,8)
		b._ring_cells(e,core+Vector3(0,0,0.34),0.39,0.25,0.09,1,0,true)
	for side in [-1.0,1.0]:
		b._rod(e,Vector3(side*0.50,2.96,1.0),Vector3(side*0.50,2.96,5.15),0.12,8)
		var leaf := 7 if side<0 else 8
		var center := Vector3(side*0.64,2.96,5.18)
		var angles := Vector3(-0.58,side*0.27,side*0.20)
		_panel(e,center,Vector3(1.13,1.50,0.28),angles,1,leaf)
		var face := Basis.from_euler(angles)
		for seam in range(3):
			var y := -0.43+float(seam)*0.39
			b._rod(e,center+face*Vector3(-0.40,y,0.16),center+face*Vector3(0.40,y,0.16),0.075,9,leaf)
		b._rod(e,Vector3(side*0.64,2.96,5.18),Vector3(side*1.28,2.96,4.4),0.12,2,7 if side<0 else 8)
	b._box(e,Vector3(0,1.92,5.5),Vector3(0.54,0.54,1.88),2)
	b._box(e,Vector3(0,2.15,6.50),Vector3(0.24,0.10,0.15),4)
	# Offset command decks, tall buttresses and separate illuminated windows.
	b._box(e,Vector3(0,4.04,-3.65),Vector3(1.2,2.5,1.3),2)
	for level in range(3):
		var width := 3.7-float(level)*0.75
		var y := 4.85+float(level)*0.48
		var z := -3.25-float(level)*0.34
		b._depth_wedge(e,Vector3(0,y,z),Vector3(width,0.36,2.1-float(level)*0.32),0.75,2)
		_panel(e,Vector3(0,y+0.22,z),Vector3(width+0.15,0.14,2.25-float(level)*0.32),Vector3.ZERO,1)
		for window in range(7-level*2):
			b._box(e,Vector3((float(window)-float(6-level*2)*0.5)*0.38,y+0.035,z+0.93-float(level)*0.16),Vector3(0.23,0.10,0.13),8)
	for side in [-1.0,1.0]:
		b._rod(e,Vector3(side*2.2,3.5,-3.4),Vector3(side*1.0,5.7,-3.4),0.13,5)
		b._rod(e,Vector3(side*0.8,6.1,-3.7),Vector3(side*1.0,7.0,-3.7),0.105,1)
	b._rod(e,Vector3(0,5.95,-4.1),Vector3(0,7.0,-4.1),0.17,8,5)
	_capacitor(e,b,Vector3(0,7.45,-4.1),5,1.12)
	b._finish_boss(e,Vector3(0,2.96,3.02),Vector3(0,5.9,-3.7),modules)

static func _capacitor(e,b: Script,at: Vector3,part: int,s: float) -> void:
	b._ellipsoid(e,at,Vector3(0.68,1.04,0.68)*s,4,part)
	for end in [-1.0,1.0]: b._box(e,at+Vector3(0,end*0.52*s,0),Vector3(0.9,0.16,0.9)*s,8,part)
	for side in [-1.0,1.0]:
		for depth in [-1.0,1.0]: b._rod(e,at+Vector3(side*0.36,-0.52,depth*0.36)*s,at+Vector3(side*0.36,0.52,depth*0.36)*s,0.07*s,2,part)

static func _hinge(at: Vector3,angles: Vector3,offset: Vector3 = Vector3.ZERO) -> Transform3D:
	var basis := Basis.from_euler(angles)
	return Transform3D(basis,at-basis*at+offset)

static func pose(kind: String,action: String,phase: float,age: float,lane: int,integrity: Dictionary) -> Dictionary:
	var p := clampf(phase,0,1)
	var parts: Dictionary = {}
	var rig := Transform3D.IDENTITY
	var side := -1.0 if lane%2==0 else 1.0
	var active: Array = integrity.get("support_active",[])
	if kind=="empire_walker":
		for leg in range(4):
			var sign := -1.0 if leg%2==0 else 1.0
			var stride := sin(age*4.6+float(leg)*PI*0.6)*0.12 if action=="run" else 0.0
			var brace := sin(p*PI*0.5)*0.14 if action=="charge" else (0.14 if action=="fire" else 0.0)
			parts[3+leg]=_hinge(Vector3(sign*0.66,1.91,-0.57 if leg<2 else 0.57),Vector3(stride,0,sign*brace))
		if action=="fire":
			for arm in [1,2]:
				var kick := maxf(0,1.0-absf(p-(0.24 if arm==1 else 0.72))*12.0)
				parts[arm]=Transform3D(Basis.IDENTITY,Vector3(0,0,-0.22*kick))
	elif kind in ["empire_lancer","empire_sentinel"]:
		var gait := sin(age*7.2)*0.22 if action=="run" else 0.0
		for leg in [3,4]:
			var sign := -1.0 if leg==3 else 1.0
			parts[leg]=_hinge(Vector3(sign*0.23,1.12,0),Vector3(sign*gait,0,0))
			parts[leg+2]=parts[leg]
		if kind=="empire_lancer":
			var angle := 0.1
			if action=="windup": angle=lerpf(0.12,0.65,smoothstep(0,0.7,p))
			elif action=="strike": angle=lerpf(0.65,-0.31,smoothstep(0.05,0.50,p))
			elif action=="recover": angle=-0.31*(1.0-p)
			parts[2]=_hinge(Vector3(0.48,2,0),Vector3(0.02,angle,0))
			if action=="strike": rig.origin.z=sin(p*PI)*0.42
		else:
			var opened := clampf(float(integrity.get("series_shield_open",0)),0,1)
			parts[1]=_hinge(Vector3(-0.71,1.63,0.45),Vector3(0,-opened*1.12,0))
			if action=="fire": parts[2]=Transform3D(Basis.IDENTITY,Vector3(0,0,-0.14*sin(p*PI)))
			elif action=="windup":
				parts[1]=_hinge(Vector3(-0.71,1.63,0.45),Vector3(0,-0.25*sin(p*PI),0))
				rig.origin.z=-sin(p*PI)*0.25
			elif action=="strike":
				parts[1]=_hinge(Vector3(-0.71,1.63,0.45),Vector3(0,2.10*smoothstep(0.08,0.62,p),0))
				rig.origin.z=sin(p*PI)*1.18
	elif kind=="empire_fighter":
		rig.origin.y=sin(age*2.8)*0.09
		for arm in [1,2]: parts[arm]=_hinge(Vector3(-0.28 if arm==1 else 0.28,1.4,-0.4),Vector3(0,0,(-1.0 if arm==1 else 1.0)*(0.10+sin(age*2)*0.045)))
	else:
		rig.origin.y=sin(age*0.9)*0.075
		var lost := 3-int(integrity.get("active_supports",3))
		var opening := clampf(float(lost)/3.0,0,1)
		parts[7]=_hinge(Vector3(-1.22,2.96,4.5),Vector3(0,-1.22*opening,0),Vector3(-0.25*opening,0,0))
		parts[8]=_hinge(Vector3(1.22,2.96,4.5),Vector3(0,1.22*opening,0),Vector3(0.25*opening,0,0))
	if action=="entry" and bool(integrity.get("series_entry_authored",false)):
		rig=Transform3D.IDENTITY
		parts={}
	if action=="death":
		if kind=="empire_dreadnought":
			var fall := smoothstep(0.34,0.92,p)
			rig=_hinge(Vector3(0,2.8,-1),Vector3(fall*0.16,0,side*fall*0.12),Vector3(0,-0.7*fall,0))
			for arm in [1,2]: parts[arm]=_hinge(Vector3(-0.5 if arm==1 else 0.5,2.9,-3),Vector3(0,0,(-1.0 if arm==1 else 1.0)*fall*0.35))
		else: rig=_hinge(Vector3(0,0.7,0),Vector3(smoothstep(0.2,0.9,p)*0.6,0,side*smoothstep(0.2,0.9,p)*0.3))
	return {"rig":rig,"parts":parts}

static func entry(kind: String,p: float,lane: int) -> Dictionary:
	var data := {"offset":Vector3.ZERO,"rotation":Vector3.ZERO,"opacity":1.0,"rig":Transform3D.IDENTITY,"parts":{},"impact_phase":0.38}
	if p>=1.0 or kind=="empire_fighter": return data
	var side := -1.0 if lane%2==0 else 1.0
	var approach := 1.0-smoothstep(0,0.38,p)
	var hold := smoothstep(0.15,0.40,p)*(1.0-smoothstep(0.72,1,p))
	if kind=="empire_dreadnought":
		var descend := 1.0-smoothstep(0.0,0.88,p)
		data.offset=Vector3(0,7.0*descend,-45.0*descend)
		data.rotation=Vector3(-0.12*sin(p*PI),0,side*0.055*descend)
		data.impact_phase=-1.0
		for leaf in [7,8]: data.parts[leaf]=_hinge(Vector3(-1.22 if leaf==7 else 1.22,2.96,4.5),Vector3(0,(-1.0 if leaf==7 else 1.0)*0.32*sin(p*PI),0))
	else:
		data.offset=Vector3(side*1.8*approach,0,-35*approach)
		data.opacity=smoothstep(0,0.32,p)
		if kind=="empire_walker":
			data.offset.y=2.4*approach
			data.rotation.y=-side*0.35*approach
			for leg in range(4):
				var sign := -1.0 if leg%2==0 else 1.0
				var spread := sin(p*PI)*0.24
				data.parts[3+leg]=_hinge(Vector3(sign*0.66,1.91,-0.57 if leg<2 else 0.57),Vector3(0,0,-sign*spread))
		elif kind=="empire_lancer":
			data.offset.y=sin(clampf(p/0.38,0,1)*PI)*2.4
			data.rotation.y=side*0.7*approach
			data.parts[2]=_hinge(Vector3(0.48,2,0),Vector3(-0.5*approach,0.65*hold,0))
		else:
			data.parts[1]=_hinge(Vector3(-0.71,1.63,0.45),Vector3(0,-0.85*(1.0-smoothstep(0.28,0.68,p)),0))
			data.rig=_hinge(Vector3(0,1.1,0),Vector3(0.10*hold,0,0))
	return data
