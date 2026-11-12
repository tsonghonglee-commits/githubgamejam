class_name CarrierArchetype
extends RefCounted
## A cuttable lifting ship, not a decorative hull around the Boss. Every
## visible rib, nozzle lip and suspension lug below is occupied voxel matter.
## Local +Z is the bow; the caller owns the ship's world height and motion.

const CELL_SIZE := 0.16
const GRID_SIZE := Vector3i(112,34,76)
const HANGER_POINTS: Array[Vector3] = [Vector3(-2.3,0.8,0),Vector3(2.3,0.8,0)]
const HANGER_PIVOTS: Array[Vector3] = [Vector3(-2.3,3.15,0),Vector3(2.3,3.15,0)]
const HANGER_TAGS := [8,16]
const CORE_POINT := Vector3(0,3.6,-1.9)
const ANCHOR_POINT := Vector3(0,3.2,-3.8)
const HEAD_POINT := Vector3(0,4.35,4.7)


static func dimensions() -> Dictionary:
	# 289,408 storage slots. The open bay, short plates and hollow nozzles
	# leave most of this box empty instead of authoring a solid 18m brick.
	return {"dimensions":GRID_SIZE,"cell":CELL_SIZE}


static func classify_part(point: Vector3) -> int:
	# Two actual suspension ends can detach independently. Their thin upper
	# necks stay connected to the side frame until the player cuts them.
	if point.y < 3.28 and absf(point.x) > 1.90 and absf(point.x) < 2.78 and absf(point.z) < 0.58:
		return 8 if point.x < 0.0 else 9
	# The four outer wing / engine quarters share no cosmetic shell parts.
	if absf(point.x) > 5.42:
		return (4 if point.x < 0.0 else 5) if point.z >= 0.0 else (6 if point.x < 0.0 else 7)
	if point.z > 3.30 and absf(point.x) < 2.82:
		return 3
	if absf(point.x) > 2.78:
		return 1 if point.x < 0.0 else 2
	return 0


static func build(enemy) -> void:
	_build_frame(enemy)
	_build_bridge(enemy)
	for side in [-1.0,1.0]:
		_build_wing(enemy,side)
		for depth in [-3.12,3.12]:
			_build_lift_nozzle(enemy,Vector3(side*6.55,0,depth))
		_build_tail_nozzle(enemy,side)
		_build_hanger(enemy,side)
	_build_detail_cells(enemy)
	# These regions are all inside the connected spine / bridge / rear beam.
	# Hanger flags alone never supply a core, head, or indestructible anchor.
	enemy._slasher_tags(ANCHOR_POINT,Vector3(0.80,0.48,0.72),enemy.ANCHOR_TAG)
	enemy._slasher_tags(CORE_POINT,Vector3(0.56,0.56,0.64),enemy.CORE_TAG)
	enemy._slasher_tags(HEAD_POINT,Vector3(0.56,0.48,0.56),enemy.HEAD_TAG)
	for index in range(HANGER_POINTS.size()):
		enemy._slasher_tags(HANGER_POINTS[index],Vector3(0.56,0.48,0.56),int(HANGER_TAGS[index]))
	# An actual forward bridge plate remains a readable screen aim point.
	enemy._core_point = Vector3(0,3.80,5.12)


static func _box(enemy, point: Vector3, size: Vector3, material: int) -> void:
	enemy._slasher_box(point,size,material)


static func _rod(enemy, from: Vector3, to: Vector3, radius: float, material: int) -> void:
	enemy._slasher_rod(from,to,radius,material)


static func _build_frame(enemy) -> void:
	# The ceiling sits above the loading void. No belly plate fills the
	# |x|<2.8m, |z|<3.2m space below y=2.8m; only the two real lugs enter it.
	_box(enemy,Vector3(0,3.36,-0.20),Vector3(6.32,0.32,7.80),2)
	_box(enemy,Vector3(0,3.56,-0.48),Vector3(1.28,0.80,8.52),5)
	_box(enemy,Vector3(0,3.20,-4.18),Vector3(7.48,0.80,1.10),2)
	_box(enemy,Vector3(0,3.20,-3.80),Vector3(1.12,0.56,0.80),3)
	_box(enemy,CORE_POINT,Vector3(0.72,0.64,0.88),3)
	_box(enemy,CORE_POINT+Vector3(0,0.08,0.24),Vector3(0.40,0.32,0.40),10)
	for side in [-1.0,1.0]:
		enemy._slasher_taper(2.20,3.56,Vector2(side*3.60,-0.50),Vector2(side*3.55,-0.65),1.10,1.30,9.20,10.00,2)
		_box(enemy,Vector3(side*3.55,3.54,-0.62),Vector3(1.42,0.32,9.64),1)
		# Copper load paths touch the spine, the outer side frames and the
		# aft cross-beam; short armour plates leave these members exposed.
		_rod(enemy,Vector3(side*0.48,3.68,-3.70),Vector3(side*3.55,3.15,-3.70),0.24,3)
		_rod(enemy,Vector3(side*0.48,3.68,2.80),Vector3(side*3.55,3.15,2.80),0.24,3)
		_box(enemy,Vector3(side*2.98,2.72,-0.40),Vector3(0.24,0.26,7.84),3)
		for depth in [-3.35,-1.15,1.05,3.20]:
			_box(enemy,Vector3(side*3.55,3.76,depth),Vector3(1.52,0.40,1.32),1)
			_box(enemy,Vector3(side*3.55,3.99,depth),Vector3(0.64,0.18,0.72),5)
			# Lower clamps are substantial steel cells rather than light props.
			_box(enemy,Vector3(side*3.12,2.30,depth),Vector3(0.44,0.40,0.64),5)


static func _build_bridge(enemy) -> void:
	# A broad stern-to-bow spine carries a forward V-faced command bridge.
	_box(enemy,Vector3(0,3.80,4.18),Vector3(3.92,0.90,2.12),2)
	enemy._slasher_taper(4.12,5.04,Vector2(0,4.34),Vector2(0,4.68),4.40,2.56,1.92,1.50,1)
	_box(enemy,Vector3(0,4.20,4.78),Vector3(0.88,0.64,0.72),2)
	for side in [-1.0,1.0]:
		_rod(enemy,Vector3(side*0.12,4.08,5.26),Vector3(side*1.44,4.68,5.18),0.17,7)
		_rod(enemy,Vector3(side*0.14,4.13,5.39),Vector3(side*1.34,4.66,5.30),0.12,4)
		_box(enemy,Vector3(side*1.62,4.20,4.88),Vector3(0.48,0.40,0.36),5)
		_rod(enemy,Vector3(side*1.58,3.74,3.54),Vector3(side*3.42,3.44,3.56),0.24,3)
	# A copper forehead cap sits on the bridge's real upper material.
	_box(enemy,Vector3(0,4.91,4.48),Vector3(1.04,0.24,0.72),3)


static func _build_wing(enemy, side: float) -> void:
	# Wide, shallow swept plates bridge the open side frame to two lift pods.
	# Their leading edge is stepped; this is not another rectangular gun box.
	enemy._slasher_taper(3.22,3.62,Vector2(side*5.80,-0.80),Vector2(side*6.00,-1.00),4.80,4.92,7.80,7.40,2)
	_box(enemy,Vector3(side*5.64,3.77,-1.24),Vector3(2.16,0.40,3.12),1)
	_box(enemy,Vector3(side*7.67,3.56,-1.40),Vector3(1.10,0.42,3.68),1)
	_rod(enemy,Vector3(side*3.54,3.32,2.68),Vector3(side*7.90,3.34,1.94),0.24,3)
	_rod(enemy,Vector3(side*3.54,3.32,-3.66),Vector3(side*7.90,3.34,-4.22),0.24,3)
	# Short stepped tips keep the 17m silhouette broad without filling the
	# entire storage box, or lowering the side wings into the loading bay.
	_box(enemy,Vector3(side*8.12,3.48,-2.46),Vector3(0.84,0.40,2.24),2)
	_box(enemy,Vector3(side*8.25,3.60,-2.46),Vector3(0.48,0.24,1.44),1)
	for depth in [-1.92,-0.48]:
		_box(enemy,Vector3(side*5.68,4.02,depth),Vector3(0.80,0.18,0.56),8)
		_box(enemy,Vector3(side*5.68,4.04,depth+0.18),Vector3(0.80,0.18,0.18),7)


static func _build_lift_nozzle(enemy, center: Vector3) -> void:
	# A voxel octagonal bell has an open lower throat and an occupied upper
	# chamber. The hole is material absence, shared by mesh and all cuts.
	var limits: Array[Vector3i] = enemy._slasher_grid_bounds(center+Vector3(-1.22,1.16,-1.22),center+Vector3(1.22,4.48,1.22))
	for y in range(limits[0].y,limits[1].y+1):
		var height: float = (float(y)+0.5)*CELL_SIZE
		var shoulder: float = smoothstep(1.28,2.20,height)
		var outer: float = lerpf(1.18,0.83,shoulder)
		if height > 3.72: outer = lerpf(0.83,1.06,clampf((height-3.72)/0.64,0.0,1.0))
		var inner: float = lerpf(0.62,0.34,clampf((height-1.20)/1.14,0.0,1.0))
		for z in range(limits[0].z,limits[1].z+1):
			for x in range(limits[0].x,limits[1].x+1):
				var point: Vector3 = enemy._point(x,y,z)-center
				var flat := Vector2(absf(point.x),absf(point.z))
				if maxf(flat.x,flat.y)>outer or flat.x+flat.y>outer*1.60: continue
				var hole: bool = height < 2.34 and maxf(flat.x,flat.y)<inner and flat.x+flat.y<inner*1.60
				var index: int = enemy._index(x,y,z)
				if hole:
					enemy._voxels[index] = 0
					continue
				var material: int = 1 if height > 2.82 else 2
				if height < 1.60 or (height > 3.54 and height < 3.88): material = 5
				if height > 1.60 and height < 2.34 and maxf(flat.x,flat.y) < inner+0.25: material = 10
				if height >= 2.34 and height < 2.54 and maxf(flat.x,flat.y) < 0.50: material = 10
				if height > 2.66 and height < 2.86: material = 3
				enemy._voxels[index] = material
	# The upper body intersects the wing plate. These heavy copper ribs are
	# actual overlapping cells, so no engine hangs from an invisible joint.
	for depth in [-0.72,0.72]:
		_rod(enemy,center+Vector3(-0.72,3.42,depth),center+Vector3(0.72,3.42,depth),0.18,3)
	_box(enemy,center+Vector3(0,4.36,0),Vector3(1.60,0.24,1.64),2)


static func _build_tail_nozzle(enemy, side: float) -> void:
	# Two short aft exhausts sit inside the rear side hull. Only their real
	# chamber mouths are hollowed; the forward hot end stays joined to it.
	var center := Vector3(side*3.58,2.84,-5.12)
	var limits: Array[Vector3i] = enemy._slasher_grid_bounds(center-Vector3(0.76,0.76,0.66),center+Vector3(0.76,0.76,0.66))
	for z in range(limits[0].z,limits[1].z+1):
		for y in range(limits[0].y,limits[1].y+1):
			for x in range(limits[0].x,limits[1].x+1):
				var point: Vector3 = enemy._point(x,y,z)-center
				var flat := Vector2(absf(point.x),absf(point.y))
				if maxf(flat.x,flat.y)>0.70 or flat.x+flat.y>1.08: continue
				var index: int = enemy._index(x,y,z)
				if point.z < 0.20 and maxf(flat.x,flat.y)<0.34 and flat.x+flat.y<0.52:
					enemy._voxels[index] = 0
				else:
					var material: int = 5 if point.z < -0.28 else 2
					if point.z >= 0.20 and maxf(flat.x,flat.y)<0.48: material = 10
					enemy._voxels[index] = material


static func _build_hanger(enemy, side: float) -> void:
	# The ivory upper joint occupies the requested y=3.15 hinge. Its narrow
	# copper stem carries the separately tagged ivory lower clamp.
	_rod(enemy,Vector3(side*3.55,3.15,0),Vector3(side*2.30,3.15,0),0.28,6)
	_box(enemy,Vector3(side*2.30,1.92,0),Vector3(0.48,2.56,0.56),3)
	_box(enemy,Vector3(side*2.30,0.80,0),Vector3(0.72,0.48,0.72),6)
	_box(enemy,Vector3(side*2.30,0.80,0.30),Vector3(0.40,0.32,0.24),10)
	# A short solid pin is part of the lug, not a rope extending to the Boss.
	_box(enemy,Vector3(side*2.30,0.80,-0.30),Vector3(0.40,0.32,0.24),6)
	_paint_hanger_cells(enemy,side)


static func _paint_hanger_cells(enemy, side: float) -> void:
	# Paint only cells the unchanged solid stem already authored. The ivory
	# collar and small forward warm stripe identify its actual cuttable path
	# against the dark loading bay without adding a shell, light, or cell.
	var limits: Array[Vector3i] = enemy._slasher_grid_bounds(Vector3(side*2.30-0.24,1.12,-0.28),Vector3(side*2.30+0.24,2.06,0.28))
	for y in range(limits[0].y,limits[1].y+1):
		for z in range(limits[0].z,limits[1].z+1):
			for x in range(limits[0].x,limits[1].x+1):
				var index: int = enemy._index(x,y,z)
				if enemy._voxels[index] == 0: continue
				var point: Vector3 = enemy._point(x,y,z)
				if point.y >= 1.74:
					enemy._voxels[index] = 6
				elif point.y <= 1.52 and point.z > 0.16 and absf(point.x-side*2.30) <= 0.12:
					enemy._voxels[index] = 10


static func _build_detail_cells(enemy) -> void:
	# Every accent is thick enough to occupy this grid and intersects a beam
	# or armour plate. None is a floating light or an uncuttably rendered prop.
	for side in [-1.0,1.0]:
		for depth in [-2.72,-1.76,-0.80,0.16,1.12,2.08]:
			_rod(enemy,Vector3(side*2.94,2.14,depth-0.16),Vector3(side*2.94,2.64,depth+0.16),0.13,8)
			_box(enemy,Vector3(side*3.60,3.78,depth),Vector3(0.32,0.32,0.32),3)
		for depth in [-3.84,2.72]:
			_box(enemy,Vector3(side*4.48,3.80,depth),Vector3(0.56,0.32,0.80),5)
	for depth in [-3.02,-2.06,-1.10,-0.14,0.82,1.78,2.74]:
		_box(enemy,Vector3(0,4.02,depth),Vector3(0.80,0.24,0.40),3)
		_box(enemy,Vector3(0,4.16,depth),Vector3(0.48,0.16,0.24),10)
