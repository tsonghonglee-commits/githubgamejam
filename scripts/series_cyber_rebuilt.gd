extends RefCounted
## Independently sculpted pursuit force. Every trim, pouch, barrel and rotor
## is cuttable occupied material, with real joints between separated masses.
const Sculpt = preload("res://scripts/series_ink_rebuilt.gd")
const OFFICERS := ["cyber_captain","cyber_flanker","cyber_suppressor","cyber_spotter"]

static func dimensions(kind: String) -> Dictionary:
	if kind=="cyber_tank": return {"dimensions":Vector3i(70,37,76),"cell":0.10}
	if kind=="cyber_helicopter": return {"dimensions":Vector3i(104,50,110),"cell":0.09}
	if kind=="cyber_gunship": return {"dimensions":Vector3i(104,36,48),"cell":0.09}
	if kind=="cyber_drone": return {"dimensions":Vector3i(68,50,40),"cell":0.05}
	if kind=="cyber_captain": return {"dimensions":Vector3i(48,80,84),"cell":0.05}
	if kind=="cyber_flanker": return {"dimensions":Vector3i(48,72,100),"cell":0.05}
	if kind=="cyber_suppressor": return {"dimensions":Vector3i(58,72,88),"cell":0.05}
	if kind=="cyber_spotter": return {"dimensions":Vector3i(44,78,122),"cell":0.05}
	if kind=="cyber_sniper": return {"dimensions":Vector3i(36,58,110),"cell":0.05}
	if kind=="cyber_riot": return {"dimensions":Vector3i(68,58,66),"cell":0.05}
	return {"dimensions":Vector3i(40,58,72),"cell":0.05}

static func _em(part: int,p: Vector3,radius: float = 0.19) -> Dictionary: return {"part":part,"point":p,"radius":radius}
static func _seg(part: int,a: Vector3,b: Vector3,r: float) -> Dictionary: return {"part":part,"a":a,"b":b,"radius":r}
static func _sp(part: int,p: Vector3,box: AABB) -> Dictionary: return {"part":part,"point":p,"load_bounds":box}

static func boss_modules(kind: String) -> Array:
	match kind:
		"cyber_tank":
			return [
				{"core":Vector3(-0.93,1.40,1.24),"mount":Vector3(-0.88,1.06,-0.32),"tag_size":0.25},
				{"core":Vector3(0.76,2.20,0.39),"mount":Vector3(0.72,1.44,-0.86),"tag_size":0.25},
			]
		"cyber_helicopter":
			return [
				{"core":Vector3(-0.65,1.80,1.05),"mount":Vector3(-0.59,1.79,-0.47),"tag_size":0.24},
				{"core":Vector3(0.65,2.51,-0.65),"mount":Vector3(0.60,2.20,-0.83),"tag_size":0.24},
			]
		"cyber_gunship":
			return [
				{"core":Vector3(-0.85,1.78,1.36),"mount":Vector3(-0.75,1.83,-0.48),"tag_size":0.24},
				{"core":Vector3(0.79,2.46,-0.68),"mount":Vector3(0.77,2.30,-0.91),"tag_size":0.24},
			]
	var index := OFFICERS.find(kind)
	if kind == "cyber_spotter":
		return [
			{"core":Vector3(-0.47,1.91,0.50),"mount":Vector3(-0.35,1.58,-0.24),"tag_size":0.19},
			{"core":Vector3(0.48,1.80,-0.57),"mount":Vector3(0.35,2.06,-0.29),"tag_size":0.19},
		]
	var stagger := 1.0 if index % 2 == 0 else -1.0
	return [
		{"core":Vector3(-0.46,2.06-0.26*stagger,0.27),"mount":Vector3(-0.35,1.58,-0.24),"tag_size":0.19},
		{"core":Vector3(0.48,2.06+0.26*stagger,-0.57),"mount":Vector3(0.35,2.06,-0.29),"tag_size":0.19},
	]

static func layout(kind: String) -> Dictionary:
	match kind:
		"cyber_breacher": return {"emitters":[_em(2,Vector3(0.61,1.54,1.66))],"melee_segments":[_seg(2,Vector3(0.61,1.54,0.60),Vector3(0.61,1.54,1.66),0.16)]}
		"cyber_riot": return {"name":"双片盾铰链","supports":[_sp(1,Vector3(-0.80,1.66,0.44),AABB(Vector3(-1.63,0.4,0.66),Vector3(0.8,2.0,0.35)))],"emitters":[_em(2,Vector3(0.79,1.47,1.40))],"melee_segments":[_seg(1,Vector3(-1.44,0.60,0.81),Vector3(-1.44,2.20,0.81),0.18),_seg(2,Vector3(0.79,1.47,0.57),Vector3(0.79,1.47,1.40),0.10)]}
		"cyber_sniper": return {"emitters":[_em(2,Vector3(0.49,1.91,2.51))]}
		"cyber_drone": return {"emitters":[_em(0,Vector3(0,1.54,0.73))]}
		"cyber_captain": return {"name":"肩部中继颈","supports":[_sp(9,Vector3(-0.57,2.86,-0.22),AABB(Vector3(-1.15,2.95,-0.65),Vector3(0.8,0.90,0.8)))],"emitters":[_em(2,Vector3(0.72,1.96,1.95))],"melee_segments":[_seg(2,Vector3(0.72,1.96,0.65),Vector3(0.72,1.96,1.95),0.16)]}
		"cyber_flanker": return {"name":"背部矢量推进颈","supports":[_sp(9,Vector3(0,2.28,-0.48),AABB(Vector3(-0.8,2.05,-0.95),Vector3(1.6,0.8,0.32)))],"emitters":[_em(1,Vector3(-0.92,1.62,2.34)),_em(2,Vector3(0.92,1.62,2.34))],"melee_segments":[_seg(1,Vector3(-0.92,1.62,0.60),Vector3(-0.92,1.62,2.34),0.08),_seg(2,Vector3(0.92,1.62,0.60),Vector3(0.92,1.62,2.34),0.08)]}
		"cyber_suppressor": return {"name":"背弹仓供弹颈","supports":[_sp(9,Vector3(-0.75,2.86,-0.35),AABB(Vector3(-1.40,3.00,-0.80),Vector3(0.85,0.70,0.8)))],"emitters":[_em(1,Vector3(-1.05,1.94,1.97)),_em(2,Vector3(1.05,1.94,1.97))]}
		"cyber_spotter": return {"name":"高位棱镜颈","supports":[_sp(9,Vector3(0.49,3.10,0.0),AABB(Vector3(0.43,3.20,-0.25),Vector3(0.7,0.6,0.6)))],"emitters":[_em(2,Vector3(0.65,2.13,2.88))]}
		"cyber_tank": return {"name":"裸露双侧悬挂","supports":[_sp(3,Vector3(-2.13,0.98,1.20),AABB(Vector3(-3.4,0.29,-2),Vector3(0.90,1.0,4))),_sp(4,Vector3(2.13,0.98,1.20),AABB(Vector3(2.5,0.29,-2),Vector3(0.90,1.0,4)))],"emitters":[_em(0,Vector3(0,2.42,3.49),0.28)]}
		"cyber_helicopter": return {"name":"外偏尾旋翼承力颈","supports":[_sp(3,Vector3(0.65,2.85,-2.98),AABB(Vector3(0.35,2.8,-4.65),Vector3(1.5,1.6,0.8)))],"emitters":[_em(1,Vector3(-1.24,1.62,1.95),0.23),_em(2,Vector3(1.24,1.62,1.95),0.23)]}
		"cyber_gunship": return {"name":"双升力环承力颈","supports":[_sp(1,Vector3(-2.18,2.20,0),AABB(Vector3(-4.4,1.5,-1.9),Vector3(1.7,1.8,3.7))),_sp(2,Vector3(2.18,2.20,0),AABB(Vector3(2.7,1.5,-1.9),Vector3(1.7,1.8,3.7)))],"emitters":[_em(1,Vector3(-3.44,1.62,1.62),0.24),_em(2,Vector3(3.44,1.62,1.62),0.24)]}
	return {}

static func _plate(e,c: Vector3,size: Vector3,rotation: Vector3,mat: int,part: int = 0) -> void:
	Sculpt._plate(e,c,size,rotation,mat,part)

static func build(e,b: Script) -> void:
	var k := str(e.enemy_kind)
	if k=="cyber_drone":
		_drone(e,b)
		return
	if k in ["cyber_helicopter","cyber_tank","cyber_gunship"]:
		_vehicle(e,b)
		return
	var s := 1.18 if k in OFFICERS else 1.0
	_trooper(e,b,k,s)
	if k=="cyber_breacher":
		_plate(e,Vector3(-0.79,1.57,0.31),Vector3(0.45,0.53,0.29),Vector3(-0.17,0,-0.16),1,1)
		b._box(e,Vector3(-0.79,1.71,0.48),Vector3(0.24,0.055,0.07),3,1)
	elif k in ["cyber_sniper","cyber_spotter"]:
		# The asymmetric armored shooting cloak changes the whole outline.
		b._rod(e,Vector3(-0.43,2.02,-0.12)*s,Vector3(-0.63,0.72,-0.18)*s,0.07*s,7,1)
		for n in range(5):
			_plate(e,Vector3(-0.46-n*0.035,1.90-n*0.245,-0.22)*s,Vector3(0.55,0.30,0.18)*s,Vector3(-.07,0,-.13),2,1)
			b._rod(e,Vector3(-0.71-n*.035,1.84-n*.245,-.10)*s,Vector3(-.25-n*.035,1.84-n*.245,-.10)*s,.026*s,5,1)
	if k in ["cyber_breacher","cyber_captain"]:
		_gun(e,b,Vector3(0.61,1.54,0.60)*s,0.98*s,2,0.31*s,false)
	elif k in ["cyber_sniper","cyber_spotter"]:
		var origin := Vector3(0.49,1.91,0.39) if k=="cyber_sniper" else Vector3(0.55,1.805,0.39)*s
		var length := 2.12 if k=="cyber_sniper" else 2.42
		_gun(e,b,origin,length,2,0.17,true)
		b._rod(e,origin+Vector3(0,0,1.04),origin+Vector3(-0.23,-0.62,1.30),0.045,5,2)
		b._rod(e,origin+Vector3(0,0,1.04),origin+Vector3(0.23,-0.62,1.30),0.045,5,2)
	elif k=="cyber_riot":
		_shield(e,b)
		b._rod(e,Vector3(0.79,1.47,0.25),Vector3(0.79,1.47,1.40),0.095,7,2)
		for n in range(4): b._ring_cells(e,Vector3(0.79,1.47,0.72+n*0.15),0.14,0.06,0.035,4,2,true)
	elif k=="cyber_flanker":
		for side in [-1.0,1.0]:
			var arm := 1 if side<0 else 2
			b._rod(e,Vector3(side*0.87,1.68,0.22),Vector3(side*0.92,1.62,2.34),0.075,6,arm)
			b._rod(e,Vector3(side*0.87,1.68,0.52),Vector3(side*0.92,1.62,2.34),0.032,3,arm)
			_plate(e,Vector3(side*0.89,1.68,0.53),Vector3(0.42,0.12,0.18),Vector3.ZERO,5,arm)
	elif k=="cyber_suppressor":
		for side in [-1.0,1.0]: _gun(e,b,Vector3(side*1.05,1.94,0.70),1.27,1 if side<0 else 2,0.36,false)
	if k in OFFICERS:
		_equipment(e,b,k)
		_finish_armored_boss(e,b,k,Vector3(0,1.78,0)*s,Vector3(0,2.40,0)*s)
		return
	b._finish(e,Vector3(0,1.78,0)*s,Vector3(0,1.13,0)*s,Vector3(0,2.40,0)*s)
	var supports: Array = layout(k).get("supports",[])
	var points: Array = []
	for item: Dictionary in supports: points.append(item.point)
	if not points.is_empty(): b._supports(e,points,0.15)

static func _trooper(e,b: Script,k: String,s: float) -> void:
	var wide := 1.23 if k=="cyber_suppressor" else (1.13 if k=="cyber_riot" else (0.84 if k in ["cyber_sniper","cyber_flanker","cyber_spotter"] else 1.0))
	var lean := 0.14 if k=="cyber_breacher" else 0.0
	# Actual narrow waist, chamfered ribcage and broken armor masses.
	b._ellipsoid(e,Vector3(0,1.72,lean)*s,Vector3(0.80*wide,0.82,0.48)*s,7)
	b._rod(e,Vector3(0,1.08,0)*s,Vector3(0,2.22,lean)*s,0.20*s,2)
	_plate(e,Vector3(0,1.82,0.24+lean)*s,Vector3(0.77*wide,0.61,0.22)*s,Vector3(-0.10,0,0),6)
	_plate(e,Vector3(0,2.04,0.20+lean)*s,Vector3(0.88*wide,0.18,0.23)*s,Vector3(-0.16,0,0),1)
	for side in [-1.0,1.0]:
		b._rod(e,Vector3(side*0.27*wide,1.60,0.35+lean)*s,Vector3(side*0.31*wide,2.03,0.35+lean)*s,0.048*s,7)
		for n in range(3):
			_plate(e,Vector3(side*(0.15+n*0.12)*wide,1.65,0.41+lean)*s,Vector3(0.09,0.25,0.12)*s,Vector3.ZERO,2)
			b._box(e,Vector3(side*(0.15+n*0.12)*wide,1.76,0.48+lean)*s,Vector3(0.065,0.045,0.05)*s,8)
		var arm := 1 if side<0 else 2
		var shoulder := Vector3(side*0.49*wide,2.0,lean)*s
		var elbow := Vector3(side*0.71*wide,1.63,0.17+lean)*s
		var hand := Vector3(side*0.72*wide,1.48,0.53+lean)*s
		b._rod(e,Vector3(side*0.28*wide,2.0,lean)*s,shoulder,0.145*s,7,arm)
		b._ellipsoid(e,shoulder,Vector3.ONE*0.30*s,2,arm)
		b._rod(e,shoulder,elbow,0.13*s,7,arm)
		b._ellipsoid(e,elbow,Vector3.ONE*0.25*s,9,arm)
		b._rod(e,elbow,hand,0.12*s,7,arm)
		_plate(e,shoulder+Vector3(side*0.10,0.09,0)*s,Vector3(0.46,0.29,0.51)*s,Vector3(0.04,0,side*0.35),1,arm)
		_plate(e,shoulder+Vector3(side*0.11,0.15,0.13)*s,Vector3(0.34,0.10,0.24)*s,Vector3(0.04,0,side*0.35),6,arm)
		b._box(e,shoulder+Vector3(side*0.12,0.14,0.29)*s,Vector3(0.19,0.06,0.06)*s,3,arm)
		_plate(e,elbow+Vector3(side*0.06,0.01,0.08)*s,Vector3(0.27,0.36,0.34)*s,Vector3(-0.30,0,side*0.10),1,arm)
		_plate(e,hand,Vector3(0.28,0.25,0.28)*s,Vector3.ZERO,2,arm)
		var leg := 3 if side<0 else 4
		var boot := 5 if side<0 else 6
		var hip := Vector3(side*0.23,1.10,0)*s
		var knee := Vector3(side*(0.36 if k=="cyber_breacher" else 0.29),0.64,0.11+side*0.055)*s
		var ankle := Vector3(side*(0.45 if k=="cyber_breacher" else 0.34),0.20,-side*0.06)*s
		b._rod(e,hip,knee,0.14*s,7,leg)
		_plate(e,hip.lerp(knee,0.55)+Vector3(0,0,0.10)*s,Vector3(0.32,0.47,0.30)*s,Vector3(0,0,-side*0.10),2,leg)
		b._ellipsoid(e,knee,Vector3(0.28,0.25,0.29)*s,7,leg)
		_plate(e,knee+Vector3(0,0,0.15)*s,Vector3(0.34,0.27,0.18)*s,Vector3(-0.12,0,0),1,leg)
		b._rod(e,knee,ankle,0.11*s,7,leg)
		_plate(e,knee.lerp(ankle,0.55)+Vector3(0,0,0.10)*s,Vector3(0.27,0.35,0.23)*s,Vector3(-0.1,0,0),1,leg)
		b._rod(e,ankle,Vector3(ankle.x,0.12*s,ankle.z+0.20*s),0.125*s,7,boot)
		_plate(e,Vector3(ankle.x,0.13*s,ankle.z+0.16*s),Vector3(0.40,0.24,0.62)*s,Vector3.ZERO,2,boot)
		_plate(e,Vector3(ankle.x,0.22*s,ankle.z+0.31*s),Vector3(0.36,0.11,0.32)*s,Vector3.ZERO,1,boot)
		# Rear thigh armor / pouches differ by combat role.
		if k in ["cyber_sniper","cyber_spotter","cyber_captain"]:
			_plate(e,Vector3(side*0.39,1.00,-0.13)*s,Vector3(0.30,0.54,0.17)*s,Vector3(0,0,-side*0.14),5,leg)
		else:
			_plate(e,Vector3(side*0.44,1.13,0.18)*s,Vector3(0.30,0.33,0.26)*s,Vector3.ZERO,2,leg)
	# Angular helmet with split cheekguards, narrow functional visor and antenna.
	b._ellipsoid(e,Vector3(0,2.40,lean)*s,Vector3(0.48,0.45,0.49)*s,2)
	b._taper(e,Vector3(0,2.50,0.015+lean)*s,Vector3(0.49,0.23,0.43)*s,Vector2(0,lean)*s,0.26*s,5)
	_plate(e,Vector3(0,2.48,0.23+lean)*s,Vector3(0.42,0.17,0.13)*s,Vector3(-0.23,0,0),1)
	_plate(e,Vector3(0,2.41,0.25+lean)*s,Vector3(0.44,0.10,0.12)*s,Vector3.ZERO,7)
	b._box(e,Vector3(0,2.43,0.32+lean)*s,Vector3(0.33,0.045,0.05)*s,10 if k in ["cyber_sniper","cyber_spotter"] else 3)
	for side in [-1.0,1.0]:
		_plate(e,Vector3(side*0.17,2.30,0.20+lean)*s,Vector3(0.14,0.22,0.23)*s,Vector3(0,side*0.2,0),1)
		b._ellipsoid(e,Vector3(side*0.27,2.42,lean)*s,Vector3(0.13,0.23,0.25)*s,7)
		if k in ["cyber_flanker","cyber_spotter"]: b._rod(e,Vector3(side*0.19,2.54,lean)*s,Vector3(side*0.30,2.86,-0.09+lean)*s,0.04*s,5)
	_plate(e,Vector3(0,1.24,0.28)*s,Vector3(0.64,0.14,0.17)*s,Vector3.ZERO,1)
	b._box(e,Vector3(0,1.24,0.39)*s,Vector3(0.18,0.10,0.08)*s,8)

static func _gun(e,b: Script,origin: Vector3,length: float,part: int,width: float,sniper: bool) -> void:
	_plate(e,origin+Vector3(0,0,length*0.24),Vector3(width*1.55,width*1.20,length*0.50),Vector3.ZERO,7,part)
	_plate(e,origin+Vector3(0,width*0.28,length*0.22),Vector3(width*1.28,width*0.46,length*0.54),Vector3.ZERO,5,part)
	b._rod(e,origin+Vector3(0,0,length*0.40),origin+Vector3(0,0,length),width*0.24,7,part)
	for n in range(4):
		var at := origin+Vector3(0,0,length*(0.45+n*0.095))
		_plate(e,at,Vector3(width,width*0.82,width*0.18),Vector3.ZERO,1 if n==0 else 5,part)
	b._box(e,origin+Vector3(0,0,length),Vector3(width*0.8,width*0.65,0.08),7,part)
	b._box(e,origin+Vector3(0,0,length+0.035),Vector3(width*0.32,width*0.32,0.06),3 if not sniper else 10,part)
	b._rod(e,origin+Vector3(0,-0.04,0),origin+Vector3(0,-0.30,-0.05),width*0.35,2,part)
	if sniper:
		_plate(e,origin+Vector3(0,0.19,0.42),Vector3(0.20,0.19,0.43),Vector3.ZERO,2,part)
		b._box(e,origin+Vector3(0,0.19,0.67),Vector3(0.12,0.12,0.07),10,part)
	else:
		_plate(e,origin+Vector3(width*0.40,-width*0.37,length*0.24),Vector3(width*0.65,width*1.3,width*0.8),Vector3(0,0,0.14),2,part)

static func _shield(e,b: Script) -> void:
	# The external shield root is a narrow red linkage, never bridged by trim.
	b._rod(e,Vector3(-0.73,1.62,0.30),Vector3(-1.12,1.66,0.81),0.11,8,1)
	for row in range(5):
		_plate(e,Vector3(-1.12,0.61+row*0.37,0.80),Vector3(1.0,0.39,0.23),Vector3(0,0,-0.04),2,1)
		b._box(e,Vector3(-1.12,0.69+row*0.37,0.94),Vector3(0.80,0.055,0.06),5,1)
	for x in [-1.52,-0.72]: b._rod(e,Vector3(x,0.48,0.81),Vector3(x,2.30,0.81),0.065,1,1)
	b._box(e,Vector3(-1.12,1.94,0.91),Vector3(0.58,0.10,0.10),10,1)
	b._supports(e,[Vector3(-0.80,1.66,0.44)],0.14)

static func _equipment(e,b: Script,k: String) -> void:
	var p := Vector3(-0.76,2.82,-0.23)
	if k=="cyber_captain":
		b._rod(e,Vector3(-0.38,2.50,-0.17),Vector3(-0.80,3.30,-0.25),0.10,8,9)
		b._ring_cells(e,Vector3(-0.80,3.23,-0.25),0.32,0.18,0.08,5,9,true)
		b._ellipsoid(e,Vector3(-0.80,3.23,-0.25),Vector3.ONE*0.21,10,9)
		b._rod(e,Vector3(-0.80,3.23,-0.25),Vector3(-0.80,3.77,-0.25),0.04,5,9)
	elif k=="cyber_flanker":
		b._rod(e,Vector3(0,2.28,-0.23),Vector3(0,2.28,-0.76),0.11,8,9)
		for side in [-1.0,1.0]:
			_plate(e,Vector3(side*0.43,2.42,-0.77),Vector3(0.43,0.55,0.25),Vector3(0,0,-side*0.22),5,9)
			b._rod(e,Vector3(0,2.28,-0.76),Vector3(side*0.43,2.42,-0.77),0.11,7,9)
			b._box(e,Vector3(side*0.43,2.25,-0.93),Vector3(0.25,0.15,0.07),3,9)
	elif k=="cyber_suppressor":
		b._rod(e,Vector3(-0.48,2.45,-0.30),Vector3(-0.96,3.20,-0.40),0.10,8,9)
		_plate(e,Vector3(-0.96,3.20,-0.40),Vector3(0.64,0.52,0.51),Vector3.ZERO,2,9)
		for n in range(4): b._box(e,Vector3(-1.18+n*0.145,3.24,-0.10),Vector3(0.08,0.30,0.12),10,9)
		for side in [-1.0,1.0]:
			b._rod(e,Vector3(side*0.68,2.22,-0.24),Vector3(side*1.03,1.95,0.42),0.105,8,1 if side<0 else 2)
			_plate(e,Vector3(side*0.65,2.54,-0.30),Vector3(0.45,0.41,0.45),Vector3.ZERO,5)
	else:
		b._rod(e,Vector3(0.30,2.70,0),Vector3(0.66,3.46,0),0.085,8,9)
		_plate(e,Vector3(0.66,3.45,0.04),Vector3(0.64,0.36,0.39),Vector3.ZERO,5,9)
		for n in range(3): b._ellipsoid(e,Vector3(0.46+n*0.20,3.45,0.27),Vector3(0.13,0.15,0.12),10,9)
	# Solid hinged breast plates, leaving a physical channel when opened.
	for side in [-1.0,1.0]:
		_plate(e,Vector3(side*0.24,2.15,0.44),Vector3(0.45,0.69,0.19),Vector3(0,-side*0.12,-side*0.10),2,7 if side<0 else 8)
		b._rod(e,Vector3(side*0.42,2.42,0.39),Vector3(side*0.42,1.83,0.39),0.055,1,7 if side<0 else 8)

static func _drone(e,b: Script) -> void:
	b._depth_wedge(e,Vector3(0,1.64,0),Vector3(0.68,0.42,1.12),0.50,2)
	_plate(e,Vector3(0,1.85,-0.08),Vector3(0.56,0.16,0.72),Vector3(-0.12,0,0),1)
	b._rod(e,Vector3(0,1.64,0),Vector3(0,1.36,0.55),0.12,7)
	b._ellipsoid(e,Vector3(0,1.54,0.66),Vector3(0.30,0.30,0.20),10)
	for side in [-1.0,1.0]:
		var arm := 1 if side<0 else 2
		for front in [-1.0,1.0]:
			var knee := Vector3(side*0.67,2.19,front*0.38)
			var tip := Vector3(side*1.49,1.73,front*0.77)
			b._rod(e,Vector3(side*0.18,1.75,front*0.20),knee,0.075,7,arm)
			b._ellipsoid(e,knee,Vector3.ONE*0.21,8,arm)
			b._rod(e,knee,tip,0.08,5,arm)
			_plate(e,knee.lerp(tip,0.62),Vector3(0.76,0.14,0.37),Vector3(0,side*front*0.28,side*0.46),2,arm)
			b._box(e,tip,Vector3(0.23,0.09,0.18),3,arm)
	b._finish(e,Vector3(0,1.64,0),Vector3(0,1.58,-0.20),Vector3(0,1.75,0.31))

static func _vehicle(e,b: Script) -> void:
	var k := str(e.enemy_kind)
	if k=="cyber_tank":
		b._depth_wedge(e,Vector3(0,1.21,-0.22),Vector3(3.62,0.91,3.71),0.63,2)
		_plate(e,Vector3(0,1.58,-0.33),Vector3(3.0,0.22,2.64),Vector3.ZERO,5)
		b._ring_cells(e,Vector3(0,1.72,-0.44),1.02,0.71,0.16,7,0)
		b._depth_wedge(e,Vector3(0,2.14,-0.35),Vector3(2.42,0.72,2.24),0.55,5)
		_plate(e,Vector3(0,2.53,-0.63),Vector3(1.66,0.18,1.27),Vector3.ZERO,2)
		b._rod(e,Vector3(0,2.42,0.18),Vector3(0,2.42,3.49),0.14,7)
		for n in range(4): _plate(e,Vector3(0,2.42,0.71+n*0.69),Vector3(0.43 if n<3 else 0.51,0.36,0.25),Vector3.ZERO,1)
		_plate(e,Vector3(0,2.42,3.40),Vector3(0.50,0.38,0.28),Vector3.ZERO,1)
		b._box(e,Vector3(0.18,2.42,3.49),Vector3(0.08,0.17,0.11),10)
		b._box(e,Vector3(0,2.42,3.54),Vector3(0.18,0.18,0.10),0)
		for side in [-1.0,1.0]:
			var part := 3 if side<0 else 4
			# One real exposed suspension links an otherwise separated tread bank.
			b._rod(e,Vector3(side*1.04,1.10,1.20),Vector3(side*2.75,0.87,1.20),0.145,8,part)
			for n in range(7):
				var z := -1.65+float(n)*0.54
				b._ellipsoid(e,Vector3(side*2.87,0.77,z),Vector3(0.62,0.73,0.69),7,part)
				b._ellipsoid(e,Vector3(side*3.18,0.77,z),Vector3(0.17,0.43,0.43),5,part)
				b._rod(e,Vector3(side*3.20,0.77,z),Vector3(side*3.22,0.77,z),0.10,8,part)
			for n in range(16):
				var z := -1.94+n*0.255
				_plate(e,Vector3(side*2.87,0.39,z),Vector3(0.89,0.18,0.19),Vector3.ZERO,5,part)
				_plate(e,Vector3(side*2.87,1.10,z),Vector3(0.89,0.18,0.19),Vector3.ZERO,2,part)
			b._rod(e,Vector3(side*2.87,0.76,-1.97),Vector3(side*2.87,0.76,1.98),0.11,7,part)
			var plate := 7 if side<0 else 8
			b._depth_wedge(e,Vector3(side*0.77,1.42,1.62),Vector3(1.46,0.81,0.37),0.72,5,plate)
			for rib in range(4): b._rod(e,Vector3(side*(0.28+rib*0.27),1.12,1.84),Vector3(side*(0.34+rib*0.27),1.73,1.84),0.045,1,plate)
			b._box(e,Vector3(side*1.31,1.43,1.89),Vector3(0.22,0.11,0.10),10,plate)
			for n in range(4): _plate(e,Vector3(side*0.66,2.51,-1.04+n*0.32),Vector3(0.23,0.08,0.18),Vector3.ZERO,7)
		b._rod(e,Vector3(0.73,2.44,-0.96),Vector3(0.73,3.37,-0.96),0.04,5)
		_finish_armored_boss(e,b,k,Vector3(0,1.5,0),Vector3(0,2.2,0))
	else:
		var heli := k=="cyber_helicopter"
		b._depth_wedge(e,Vector3(0,2.05,0),Vector3(2.05 if heli else 2.53,1.24,3.37),0.57,2)
		b._depth_wedge(e,Vector3(0,2.16,1.09),Vector3(1.55,0.70,1.14),0.44,5)
		for side in [-1.0,1.0]:
			_plate(e,Vector3(side*0.34,2.38,1.43),Vector3(0.56,0.42,0.16),Vector3(-0.31,side*0.20,0),10)
			b._rod(e,Vector3(side*0.62,2.17,1.49),Vector3(side*0.08,2.59,1.46),0.055,7)
			_plate(e,Vector3(side*0.52,2.74,-0.42),Vector3(0.75,0.43,1.65),Vector3(0,0,-side*0.11),5)
			for n in range(5): _plate(e,Vector3(side*0.52,2.98,-0.91+n*0.24),Vector3(0.49,0.06,0.11),Vector3.ZERO,7)
			_plate(e,Vector3(side*0.87,2.11,-0.07),Vector3(0.29,0.54,1.17),Vector3(0,0,-side*0.15),1)
		if heli:
			# Swept, offset tail leaves the bearing readable from the player camera.
			b._rod(e,Vector3(0,2.20,-1.17),Vector3(1.05,3.26,-4.10),0.14,5,3)
			b._ring_cells(e,Vector3(1.05,3.42,-4.15),0.64,0.42,0.10,5,3,true)
			b._ellipsoid(e,Vector3(1.05,3.42,-4.15),Vector3.ONE*0.25,8,3)
			for n in range(5):
				var angle := n*TAU/5.0
				b._rod(e,Vector3(1.05,3.42,-4.15),Vector3(1.05+sin(angle)*0.54,3.42+cos(angle)*0.54,-4.15),0.055,7,3)
			_plate(e,Vector3(0.82,3.61,-3.73),Vector3(0.18,1.11,0.86),Vector3(-0.34,0,0),2,3)
			b._rod(e,Vector3(0,2.54,-0.30),Vector3(0,3.39,-0.30),0.14,8,9)
			b._ellipsoid(e,Vector3(0,3.39,-0.30),Vector3(0.54,0.29,0.54),5,9)
			for n in range(4):
				var angle := n*TAU/4.0
				var end := Vector3(sin(angle)*4.44,3.42,-0.30+cos(angle)*4.44)
				b._rod(e,Vector3(0,3.40,-0.30),end,0.09,7,9)
				_plate(e,end*Vector3(0.82,0,0.82)+Vector3(0,3.42,-0.054),Vector3(0.25,0.09,1.58),Vector3(0,angle,0),2,9)
				b._ellipsoid(e,end,Vector3(0.26,0.12,0.26),10,9)
			for side in [-1.0,1.0]:
				var arm := 1 if side<0 else 2
				b._rod(e,Vector3(side*0.69,1.88,0.15),Vector3(side*1.24,1.62,0.72),0.14,5,arm)
				_gun(e,b,Vector3(side*1.24,1.62,0.72),1.23,arm,0.40,false)
				var skid := 4 if side<0 else 5
				for z in [-0.73,0.77]: b._rod(e,Vector3(side*0.60,1.65,z),Vector3(side*0.96,0.91,z+0.13),0.08,5,skid)
				b._rod(e,Vector3(side*0.96,0.90,-1.46),Vector3(side*0.96,0.90,1.44),0.105,7,skid)
		else:
			for side in [-1.0,1.0]:
				var arm := 1 if side<0 else 2
				b._rod(e,Vector3(side*0.96,2.20,0),Vector3(side*3.44,2.20,0),0.16,8,arm)
				b._depth_wedge(e,Vector3(side*3.44,2.17,-0.07),Vector3(1.43,0.75,3.08),0.72,5,arm)
				b._ring_cells(e,Vector3(side*3.44,2.63,-0.32),0.93,0.66,0.16,2,arm)
				b._ring_cells(e,Vector3(side*3.44,2.57,-0.32),0.81,0.70,0.08,10,arm)
				b._rod(e,Vector3(side*3.44,2.16,-0.32),Vector3(side*3.44,2.65,-0.32),0.13,8,arm)
				for n in range(6):
					var angle := n*TAU/6.0
					b._rod(e,Vector3(side*3.44,2.65,-0.32),Vector3(side*3.44+sin(angle)*0.78,2.65,-0.32+cos(angle)*0.78),0.06,7,arm)
				_gun(e,b,Vector3(side*3.44,1.62,0.57),1.05,arm,0.40,false)
		for side in [-1.0,1.0]:
			var plate := 7 if side<0 else 8
			b._depth_wedge(e,Vector3(side*0.42,1.75,1.56),Vector3(0.95,0.75,0.39),0.60,1,plate)
			for n in range(3): b._box(e,Vector3(side*0.54,1.54+n*0.18,1.82),Vector3(0.41,0.07,0.10),7,plate)
		_finish_armored_boss(e,b,k,Vector3(0,2,0),Vector3(0,2.2,1.0))

static func _finish_armored_boss(e,b: Script,k: String,aim: Vector3,head: Vector3) -> void:
	var modules := boss_modules(k)
	var infantry := k in OFFICERS
	var scale := 0.68 if infantry else 1.0
	for i in range(modules.size()):
		var core: Vector3 = modules[i].core
		var mount: Vector3 = modules[i].mount
		b._rod(e,mount,core,0.21*scale,7)
		b._rod(e,mount,Vector3(0,mount.y+0.13,mount.z),0.24*scale,5)
		b._box(e,mount,Vector3(0.40,0.36,0.36)*scale,7)
		b._depth_wedge(e,core,Vector3(0.48,0.48,0.54)*scale,0.73,5)
		b._box(e,core,Vector3(0.28,0.31,0.36)*scale,10 if i == 0 else 4)
		for rib in [-0.13,0.13]:
			b._rod(e,core+Vector3(rib,-0.18,0.27)*scale,core+Vector3(rib,0.18,0.21)*scale,0.046,1)
		var flank := signf(core.x)
		for rib in [-0.10,0.10]:
			var vent := core+Vector3(flank*0.24,rib,0.01)*scale
			b._box(e,vent,Vector3(0.12,0.065,0.28)*scale,10 if i == 0 else 4)
	b._finish_boss(e,aim,head,modules)

static func _hinge(at: Vector3,angles: Vector3,offset: Vector3 = Vector3.ZERO) -> Transform3D:
	var basis := Basis.from_euler(angles)
	return Transform3D(basis,at-basis*at+offset)

static func pose(k: String,action: String,phase: float,age: float,lane: int,integrity: Dictionary) -> Dictionary:
	var p := clampf(phase,0,1)
	var side := -1.0 if lane%2==0 else 1.0
	var s := 1.18 if k in OFFICERS else 1.0
	var parts: Dictionary = {}
	var rig := Transform3D.IDENTITY
	var flying := k in ["cyber_drone","cyber_helicopter","cyber_gunship"]
	var vehicle := k in ["cyber_helicopter","cyber_gunship","cyber_tank","cyber_drone"]
	if flying: rig=_hinge(Vector3(0,2,0),Vector3(sin(age*2.1)*0.025,0,sin(age*1.9)*0.04),Vector3(0,sin(age*2.3)*0.075,0))
	if k=="cyber_helicopter": parts[9]=_hinge(Vector3(0,3.39,-0.30),Vector3(0,age*29,0))
	elif k=="cyber_drone":
		for arm in [1,2]: parts[arm]=_hinge(Vector3(-0.2 if arm==1 else 0.2,1.75,0),Vector3(0,0,(-1.0 if arm==1 else 1.0)*(0.09+sin(age*4.5)*0.06)))
	elif not vehicle:
		var gait := sin(age*7.2)*(0.28 if action=="run" else 0.0)
		for leg in [3,4]:
			var sign := -1.0 if leg==3 else 1.0
			parts[leg]=_hinge(Vector3(sign*0.23,1.1,0)*s,Vector3(sign*gait,0,0))
			parts[leg+2]=parts[leg]
		for arm in [1,2]:
			var sign := -1.0 if arm==1 else 1.0
			var angles := Vector3(0,-0.35 if arm==2 else -0.20,sign*0.04)
			if k in ["cyber_sniper","cyber_spotter"]: angles=Vector3(-0.03,-0.57 if arm==2 else 0.0,0)
			elif k=="cyber_flanker": angles=Vector3(0,sign*0.48,sign*0.10)
			if action=="charge": angles=Vector3(-0.06,sign*0.09*sin(p*PI),0)
			elif action=="fire": angles=Vector3(-0.10*sin(p*PI*4.0),0,0)
			elif action=="windup": angles=Vector3(-0.15,sign*0.65,sign*0.20)
			elif action=="strike": angles=Vector3(0,sign*lerpf(0.65,-0.55,smoothstep(0.12,0.68,p)),sign*0.05)
			parts[arm]=_hinge(Vector3(sign*0.48,2.0,0)*s,angles)
		if k=="cyber_riot":
			var opening := maxf(float(integrity.get("series_shield_open",0)),1.0 if bool(integrity.get("vulnerable",false)) else 0.0)
			parts[1]=_hinge(Vector3(-0.48,2,0),Vector3(0,-opening*1.15,0))
		if action=="strike": rig.origin.z=sin(p*PI)*0.52
		elif action=="charge" and k in ["cyber_sniper","cyber_spotter"]: rig=_hinge(Vector3(0,1.1,0)*s,Vector3(0.10*sin(p*PI),side*0.07,0))
		elif action=="run" and k=="cyber_breacher": rig=_hinge(Vector3(0,1.1,0),Vector3(0.22,-side*0.22,0))
		if action=="entry" and bool(integrity.get("series_entry_authored",false)):
			parts={}
			rig=Transform3D.IDENTITY
	if bool(integrity.get("vulnerable",false)):
		var missing := float(int(integrity.get("total_supports",0))-int(integrity.get("active_supports",0)))
		for n in [7,8]: parts[n]=_hinge(Vector3(-0.60 if n==7 else 0.60,2.0,0.38),Vector3(0,(-1.0 if n==7 else 1.0)*1.15,0))
		if k in ["cyber_helicopter","cyber_gunship"]: rig=_hinge(Vector3(0,2,0),Vector3(0.08,0,side*minf(0.22,missing*0.11)))
	if action=="death":
		var collapse := smoothstep(0.20,0.88,p)
		if k=="cyber_helicopter":
			rig=_hinge(Vector3(0,2,0),Vector3(collapse*0.26,collapse*0.18,side*collapse*0.86),Vector3(0,-collapse*0.12,0))
			parts[9]=_hinge(Vector3(0,3.39,-0.30),Vector3(0,age*29*(1.0-collapse),collapse*0.18))
		elif k=="cyber_tank": rig=_hinge(Vector3(0,1.1,0),Vector3(-0.08*sin(p*PI),0,0),Vector3(0,0.18*sin(p*PI),0))
		elif k=="cyber_gunship":
			rig=_hinge(Vector3(0,2,0),Vector3(0.20*collapse,0,side*collapse*0.42))
			for arm in [1,2]: parts[arm]=_hinge(Vector3(-1.3 if arm==1 else 1.3,2.20,0),Vector3(0,0,(-1.0 if arm==1 else 1.0)*collapse*0.38))
		elif k=="cyber_captain":
			rig=_hinge(Vector3(0,1.1,0)*s,Vector3(0.46*collapse,0,0),Vector3(0,-collapse*0.20,0))
			parts[9]=_hinge(Vector3(-0.57,2.86,-0.22),Vector3(0.25*collapse,0,-0.85*collapse))
		elif k=="cyber_flanker":
			rig=_hinge(Vector3(0,1.1,0)*s,Vector3(0.26*collapse,0,side*0.39*collapse))
			for arm in [1,2]: parts[arm]=_hinge(Vector3(-0.48 if arm==1 else 0.48,2,0)*s,Vector3(0.22*collapse,(0.64 if arm==1 else -0.64)*collapse,0))
			parts[9]=_hinge(Vector3(0,2.28,-0.48),Vector3(0.60*collapse,0,0))
		elif k=="cyber_suppressor":
			rig=_hinge(Vector3(0,1.1,0)*s,Vector3(-0.13*sin(p*PI)+0.43*collapse,0,side*0.09*collapse))
			for arm in [1,2]: parts[arm]=_hinge(Vector3(-0.48 if arm==1 else 0.48,2,0)*s,Vector3(0.75*collapse,0,0))
		elif k=="cyber_spotter":
			rig=_hinge(Vector3(0,1.1,0)*s,Vector3(0.31*collapse,0,-side*0.23*collapse))
			parts[9]=_hinge(Vector3(0.49,3.10,0),Vector3(1.14*collapse,0,0))
		else: rig=_hinge(Vector3(0,1.1,0)*s,Vector3(0.35*collapse,0,side*0.27*collapse),Vector3(0,-collapse*0.20,0))
	var result := {"rig":rig,"parts":parts}
	if not vehicle and action not in ["death","entry"]: _seat_feet(result,k)
	return result

static func entry(k: String,p: float,lane: int) -> Dictionary:
	var data := {"offset":Vector3.ZERO,"rotation":Vector3.ZERO,"opacity":1.0,"rig":Transform3D.IDENTITY,"parts":{},"impact_phase":0.36}
	if p>=1 or k=="cyber_drone": return data
	var side := -1.0 if lane%2==0 else 1.0
	var boss := k in OFFICERS or k in ["cyber_helicopter","cyber_tank","cyber_gunship"]
	var approach := 1.0-smoothstep(0,0.36,p)
	var brace := smoothstep(0.14,0.36,p)*(1.0-smoothstep(0.70,1.0,p))
	var present := smoothstep(0.39,0.64,p)*(1.0-smoothstep(0.74,1.0,p))
	data.opacity=1.0 if boss else smoothstep(0,0.35,p)
	data.offset.z=-35*approach if not boss else -8*approach
	if k=="cyber_helicopter":
		data.offset+=Vector3(side*4*approach,3.6*approach,0)
		data.rotation=Vector3(-0.23*approach,side*0.35*approach,-side*0.35*approach)
	elif k=="cyber_gunship":
		data.offset.y=5.0*approach
		data.rotation.x=-0.18*approach
	elif k=="cyber_tank":
		data.offset.x=side*2.0*approach
		data.rotation.y=-side*0.26*approach
		data.rig=_hinge(Vector3(0,0.30,1.8),Vector3(-0.10*brace,0,0),Vector3(0,0.12*brace,0))
	else:
		var s := 1.18 if k in OFFICERS else 1.0
		data.offset.x=side*(2.4 if k!="cyber_riot" else 1.0)*approach
		if k in OFFICERS: data.offset.y=2.8*approach
		data.rotation.y=-side*0.55*approach
		data.rig=_hinge(Vector3(0,1.1,0)*s,Vector3((0.36 if k=="cyber_breacher" else 0.17)*brace,side*0.16*brace,0),Vector3(0,-0.23*brace,0))
		data.parts[2]=_hinge(Vector3(0.48,2,0)*s,Vector3(-0.65*brace+0.60*present,0.3*brace,0))
		if k=="cyber_riot": data.parts[1]=_hinge(Vector3(-0.48,2,0),Vector3(0,-0.95*(1.0-smoothstep(0.37,0.69,p)),0))
		elif k in ["cyber_sniper","cyber_spotter"]: data.parts[2]=_hinge(Vector3(0.48,2,0)*s,Vector3(-0.70*(1.0-smoothstep(0.38,0.67,p)),0,0))
		elif k=="cyber_flanker":
			for arm in [1,2]: data.parts[arm]=_hinge(Vector3(-0.48 if arm==1 else 0.48,2,0)*s,Vector3(-0.3*brace,(-1.0 if arm==1 else 1.0)*(0.90*brace-0.70*present),0))
	if k not in ["cyber_drone","cyber_helicopter","cyber_gunship"]: _seat_feet(data,k)
	return data

static func _seat_feet(data: Dictionary,k: String) -> void:
	var low := INF
	var s := 1.18 if k in OFFICERS else 1.0
	for side in [-1.0,1.0]:
		var part := (3 if side<0 else 4) if k=="cyber_tank" else (5 if side<0 else 6)
		var transform := Transform3D(data.rig)*Transform3D(data.parts.get(part,Transform3D.IDENTITY))
		if k=="cyber_tank":
			for x in [-0.45,0.45]:
				for z in [-2.08,2.08]: low=minf(low,(transform*Vector3(side*2.87+x,0.30,z)).y-0.30)
		else:
			var spread := 0.45 if k=="cyber_breacher" else 0.34
			for x in [-0.20,0.20]:
				for z in [-0.31,0.31]: low=minf(low,(transform*(Vector3(side*spread+x,0,0.16-side*0.06+z)*s)).y)
	data.rig.origin.y-=low
