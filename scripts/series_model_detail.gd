class_name SeriesModelDetail
extends RefCounted
## Physical voxel refinement only. The family builder owns weapons, labels,
## support tags and part IDs; this pass never adds a visual shell or prop.

const CYBER_HUMANOIDS := ["cyber_breacher","cyber_riot","cyber_sniper","cyber_captain","cyber_flanker","cyber_suppressor","cyber_spotter"]
const EMPIRE_INFANTRY := ["empire_walker","empire_lancer","empire_sentinel"]


static func refine(enemy, builder: Script) -> void:
	var kind := str(enemy.enemy_kind)
	if kind not in CYBER_HUMANOIDS and kind not in EMPIRE_INFANTRY: return
	var before: PackedByteArray = enemy._voxels.duplicate()
	var parts: PackedByteArray = enemy._series_authored_parts.duplicate()
	var tags: PackedByteArray = enemy._tags.duplicate()
	var protected := _protected_cells(enemy,builder)
	if kind == "empire_walker":
		_walker(enemy,builder,protected)
		_orbital_walker(enemy,builder,protected)
	else:
		var scale := 1.18 if kind in ["cyber_captain","cyber_flanker","cyber_suppressor","cyber_spotter"] else 1.0
		_humanoid(enemy,builder,protected,scale)
		if kind in CYBER_HUMANOIDS: _cyber_concept(enemy,builder,protected,scale)
		elif kind in ["empire_lancer","empire_sentinel"]: _orbital_infantry(enemy,builder,protected)
	# Existing material never changes articulated ownership. Protected empty
	# cells stay empty too: details cannot bridge around a real tagged hinge.
	for index in range(before.size()):
		if before[index] != 0 and enemy._voxels[index] != 0: enemy._series_authored_parts[index] = parts[index]
	for index: int in protected:
		enemy._voxels[index] = before[index]
		enemy._series_authored_parts[index] = parts[index]
		enemy._tags[index] = tags[index]


static func _protected_cells(e, b: Script) -> Dictionary:
	var result: Dictionary = {}
	var frontier: Array[int] = []
	for index in range(e._tags.size()):
		if e._tags[index] != 0:
			result[index] = true
			frontier.append(index)
	var row: int = e._dimensions.x
	var plane: int = row*e._dimensions.y
	for depth in range(2):
		var next: Array[int] = []
		for index: int in frontier:
			var x := index%row
			var y := (index/row as int)%int(e._dimensions.y)
			var z := index/plane as int
			var adjacent: Array[int] = []
			if x+1<row: adjacent.append(index+1)
			if x>0: adjacent.append(index-1)
			if y+1<e._dimensions.y: adjacent.append(index+row)
			if y>0: adjacent.append(index-row)
			if z+1<e._dimensions.z: adjacent.append(index+plane)
			if z>0: adjacent.append(index-plane)
			for neighbor: int in adjacent:
				if result.has(neighbor): continue
				result[neighbor] = true
				next.append(neighbor)
		frontier = next
	for emitter: Dictionary in b.emitters(str(e.enemy_kind)):
		var center: Vector3 = emitter.point
		var radius := float(emitter.get("radius",0.24))+float(e._cell)*2.0
		var limits: Array[Vector3i] = e._slasher_grid_bounds(center-Vector3.ONE*radius,center+Vector3.ONE*radius)
		for z in range(limits[0].z,limits[1].z+1):
			for y in range(limits[0].y,limits[1].y+1):
				for x in range(limits[0].x,limits[1].x+1):
					if Vector3(e._point(x,y,z)).distance_squared_to(center) <= radius*radius: result[e._index(x,y,z)] = true
	return result


static func _chamfer(e, protected: Dictionary, center: Vector3, size: Vector3, radius: float, part: int) -> void:
	var half := size*0.5
	var limits: Array[Vector3i] = e._slasher_grid_bounds(center-half,center+half)
	for z in range(limits[0].z,limits[1].z+1):
		for y in range(limits[0].y,limits[1].y+1):
			for x in range(limits[0].x,limits[1].x+1):
				var index: int = e._index(x,y,z)
				if protected.has(index) or e._voxels[index] == 0 or int(e._series_authored_parts[index]) != part: continue
				var q: Vector3 = (Vector3(e._point(x,y,z))-center).abs()-half+Vector3.ONE*radius
				if maxf(q.x,0.0)+maxf(q.y,0.0)+maxf(q.z,0.0) > radius+float(e._cell)*0.15: e._voxels[index] = 0


static func _humanoid(e, b: Script, protected: Dictionary, s: float) -> void:
	var cyber := str(e.enemy_kind) in CYBER_HUMANOIDS
	var dark := 2
	var steel := 5 if cyber else 8
	_chamfer(e,protected,Vector3(0,2.40,0.03)*s,Vector3(0.48,0.47,0.45)*s,0.115*s,0)
	_chamfer(e,protected,Vector3(0,1.65,0)*s,Vector3(0.94,1.05,0.50)*s,0.15*s,0)
	b._taper(e,Vector3(0,1.64,-0.015)*s,Vector3(0.66,1.04,0.47)*s,Vector2(0,-0.015)*s,0.97*s,dark)
	# Helmet dome, brow and sloping cheek pieces replace the rectangular head.
	b._ellipsoid(e,Vector3(0,2.48,0.01)*s,Vector3(0.57,0.50,0.56)*s,dark)
	b._rod(e,Vector3(-0.24,2.51,0.20)*s,Vector3(0.24,2.51,0.20)*s,0.055*s,7)
	for side in [-1.0,1.0]:
		var arm := 1 if side < 0 else 2
		var leg := 3 if side < 0 else 4
		var foot := 5 if side < 0 else 6
		b._taper(e,Vector3(side*0.205,2.31,0.23)*s,Vector3(0.16,0.25,0.18)*s,Vector2(side*0.16,0.26)*s,0.10*s,steel)
		b._rod(e,Vector3(side*0.05,2.47,0.285)*s,Vector3(side*0.21,2.50,0.22)*s,0.036*s,4)
		# Two overlapping shoulder laminates, both attached to the real arm.
		b._taper(e,Vector3(side*0.61,2.10,-0.025)*s,Vector3(0.64,0.25,0.64)*s,Vector2(side*0.56,-0.025)*s,0.43*s,dark,arm)
		b._taper(e,Vector3(side*0.60,2.23,-0.025)*s,Vector3(0.54,0.16,0.57)*s,Vector2(side*0.56,-0.025)*s,0.34*s,steel,arm)
		b._paint(e,Vector3(side*0.62,2.18,0.265)*s,Vector3(0.26,0.055,0.10)*s,6)
		# Separated chest lobes make a descending V above the narrow belt.
		b._taper(e,Vector3(side*0.25,1.90,0.255)*s,Vector3(0.45,0.54,0.22)*s,Vector2(side*0.22,0.27)*s,0.28*s,dark)
		b._rod(e,Vector3(side*0.39,2.09,0.25)*s,Vector3(side*0.13,1.61,0.27)*s,0.045*s,steel)
		b._box(e,Vector3(side*0.37,1.15,0.28)*s,Vector3(0.23,0.28,0.24)*s,7)
		b._box(e,Vector3(side*0.37,1.19,0.415)*s,Vector3(0.16,0.07,0.075)*s,dark)
		b._rod(e,Vector3(side*0.40,1.28,0.19)*s,Vector3(side*0.38,1.21,0.32)*s,0.055*s,7)
		_chamfer(e,protected,Vector3(side*0.55,1.94,0)*s,Vector3(0.36,0.56,0.46)*s,0.085*s,arm)
		_chamfer(e,protected,Vector3(side*0.23,0.66,0)*s,Vector3(0.30,1.0,0.38)*s,0.075*s,leg)
		_chamfer(e,protected,Vector3(side*0.27,0.16,0.12)*s,Vector3(0.40,0.28,0.68)*s,0.105*s,foot)
		b._taper(e,Vector3(side*0.25,0.48,0.09)*s,Vector3(0.26,0.58,0.34)*s,Vector2(side*0.23,0.02)*s,0.35*s,dark,leg)
		b._taper(e,Vector3(side*0.25,0.72,0.23)*s,Vector3(0.40,0.30,0.22)*s,Vector2(side*0.25,0.19)*s,0.23*s,steel,leg)
		b._rod(e,Vector3(side*0.25,0.39,0.26)*s,Vector3(side*0.25,0.59,0.28)*s,0.035*s,6,leg)
		b._ellipsoid(e,Vector3(side*0.26,0.28,0.08)*s,Vector3(0.34,0.25,0.39)*s,7,leg)
	if str(e.enemy_kind) == "cyber_captain":
		_chamfer(e,protected,Vector3(0,2.0,0.52),Vector3(0.80,0.75,0.28),0.14,7)
		b._paint(e,Vector3(0,2.23,0.66),Vector3(0.52,0.08,0.12),6)


static func _walker(e, b: Script, protected: Dictionary) -> void:
	_chamfer(e,protected,Vector3(0,1.7,0),Vector3(1.45,1.2,1.1),0.22,0)
	_chamfer(e,protected,Vector3(0,2.25,0),Vector3(1.7,0.45,0.9),0.18,0)
	b._taper(e,Vector3(0,2.25,-0.02),Vector3(1.74,0.36,1.0),Vector2(0,-0.08),1.20,2)
	for side in [-1.0,1.0]:
		b._taper(e,Vector3(side*0.48,1.75,0.48),Vector3(0.45,0.74,0.30),Vector2(side*0.40,0.38),0.29,2)
		b._rod(e,Vector3(side*0.55,2.20,0.40),Vector3(side*0.24,1.44,0.52),0.055,8)
		b._paint(e,Vector3(side*0.55,2.31,0.48),Vector3(0.36,0.06,0.12),6)
		for row in range(2):
			var z := -0.45 if row == 0 else 0.45
			var part := 3+row*2+(0 if side < 0 else 1)
			_chamfer(e,protected,Vector3(side*0.95,0.40,z),Vector3(0.40,0.70,0.55),0.12,part)
			b._taper(e,Vector3(side*1.0,0.16,z+0.12),Vector3(0.60,0.26,0.82),Vector2(side*0.95,z+0.05),0.41,2,part)
			b._box(e,Vector3(side*1.0,0.23,z+0.41),Vector3(0.27,0.075,0.10),8,part)


static func _clear_part(e, protected: Dictionary, center: Vector3, size: Vector3, part: int) -> void:
	var limits: Array[Vector3i] = e._slasher_grid_bounds(center-size*0.5,center+size*0.5)
	for z in range(limits[0].z,limits[1].z+1):
		for y in range(limits[0].y,limits[1].y+1):
			for x in range(limits[0].x,limits[1].x+1):
				var index: int = e._index(x,y,z)
				if not protected.has(index) and int(e._series_authored_parts[index]) == part: e._voxels[index] = 0


static func _cyber_concept(e, b: Script, protected: Dictionary, s: float) -> void:
	var kind := str(e.enemy_kind)
	var heavy := kind in ["cyber_riot","cyber_suppressor","cyber_captain"]
	# The concept's body is a narrow waist between angular chest lobes and
	# separate hip/thigh/knee/shin/ankle masses, not a bevel on a solid pillar.
	b._paint(e,Vector3(0,1.75,0.22)*s,Vector3(0.96,1.12,0.75)*s,2)
	b._taper(e,Vector3(0,1.88,0.26)*s,Vector3(0.68,0.48,0.24)*s,Vector2(0,0.27)*s,0.92*s,5)
	for side in [-1.0,1.0]:
		var leg := 3 if side < 0 else 4
		var arm := 1 if side < 0 else 2
		_clear_part(e,protected,Vector3(side*0.27,0.62,0.08)*s,Vector3(0.58,0.95,0.70)*s,leg)
		var hip := Vector3(side*0.23,1.08,-0.025)*s
		var knee := Vector3(side*0.29,0.66,0.13+side*0.035)*s
		var ankle := Vector3(side*0.31,0.22,0.035-side*0.02)*s
		b._rod(e,hip,knee,0.115*s,7,leg)
		b._rod(e,knee,ankle,0.095*s,7,leg)
		b._taper(e,Vector3(side*0.26,0.91,0.035)*s,Vector3(0.32,0.38,0.34)*s,Vector2(side*0.23,-0.025)*s,0.37*s,2,leg)
		b._ellipsoid(e,knee,Vector3(0.35,0.28,0.30)*s,5,leg)
		b._taper(e,knee+Vector3(0,0,0.15)*s,Vector3(0.29,0.22,0.16)*s,Vector2(knee.x,knee.z+0.11*s),0.22*s,2,leg)
		b._taper(e,(knee+ankle)*0.5,Vector3(0.24,0.47,0.28)*s,Vector2(knee.x,knee.z),0.32*s,2,leg)
		b._ellipsoid(e,ankle,Vector3(0.28,0.22,0.30)*s,7,leg)
		for rib in range(2): b._box(e,Vector3(side*0.31,0.39+rib*0.12,0.22)*s,Vector3(0.20,0.055,0.09)*s,5,leg)
		# Arm joints remain visible between layered shoulder and forearm armor.
		_clear_part(e,protected,Vector3(side*0.60,1.92,0.01)*s,Vector3(0.70,1.00,0.74)*s,arm)
		var shoulder := Vector3(side*0.48,2.05,0)*s
		var elbow := Vector3(side*0.66,1.68,0.07)*s
		var hand := Vector3(side*0.73,1.30,0.13)*s
		b._rod(e,shoulder,elbow,0.135*s,7,arm)
		b._ellipsoid(e,elbow,Vector3(0.29,0.27,0.30)*s,5,arm)
		b._rod(e,elbow,hand,0.105*s,7,arm)
		b._taper(e,Vector3(side*0.70,1.49,0.11)*s,Vector3(0.31,0.37,0.33)*s,Vector2(side*0.66,0.07)*s,0.35*s,2,arm)
		var broad := 0.77 if heavy else (0.52 if kind == "cyber_flanker" else 0.61)
		b._taper(e,Vector3(side*0.62,2.12,-0.035)*s,Vector3(broad,0.29,0.65)*s,Vector2(side*0.53,-0.07)*s,broad*0.59*s,2,arm)
		b._taper(e,Vector3(side*0.61,2.28,-0.035)*s,Vector3(broad*0.82,0.15,0.58)*s,Vector2(side*0.54,-0.06)*s,broad*0.46*s,5,arm)
		b._box(e,Vector3(side*0.64,2.22,0.245)*s,Vector3(0.40,0.08,0.17)*s,2,arm)
		b._box(e,Vector3(side*0.64,2.22,0.29)*s,Vector3(0.24,0.055,0.10)*s,3,arm)
		# Buckles, pouches and separated front tassets break the waist silhouette.
		b._box(e,Vector3(side*0.37,1.23,0.30)*s,Vector3(0.25,0.23,0.23)*s,8)
		b._box(e,Vector3(side*0.37,1.23,0.435)*s,Vector3(0.09,0.10,0.06)*s,5)
		if kind in ["cyber_captain","cyber_sniper","cyber_spotter"]:
			b._taper(e,Vector3(side*0.37,0.96,-0.18)*s,Vector3(0.36,0.72,0.18)*s,Vector2(side*0.28,-0.08)*s,0.24*s,2,leg)
			b._rod(e,Vector3(side*0.52,0.67,-0.08)*s,Vector3(side*0.37,1.25,-0.08)*s,0.032*s,3,leg)
	_cyber_helmet(e,b,protected,s)
	_cyber_loadout(e,b,protected,s)


static func _cyber_helmet(e, b: Script, protected: Dictionary, s: float) -> void:
	# Faceted forehead/crown, inset visor and overlapping jaw plates.
	b._paint(e,Vector3(0,2.42,0.22)*s,Vector3(0.50,0.39,0.30)*s,7)
	b._taper(e,Vector3(0,2.64,-0.015)*s,Vector3(0.48,0.24,0.47)*s,Vector2(0,-0.04)*s,0.25*s,2)
	b._rod(e,Vector3(-0.21,2.49,0.27)*s,Vector3(0.21,2.49,0.27)*s,0.039*s,5)
	for side in [-1.0,1.0]:
		b._rod(e,Vector3(side*0.025,2.44,0.29)*s,Vector3(side*0.17,2.47,0.27)*s,0.028*s,10)
		b._taper(e,Vector3(side*0.19,2.30,0.24)*s,Vector3(0.17,0.23,0.16)*s,Vector2(side*0.12,0.29)*s,0.075*s,5)
		b._ellipsoid(e,Vector3(side*0.275,2.44,-0.015)*s,Vector3(0.12,0.21,0.22)*s,7)
		b._box(e,Vector3(side*0.29,2.46,0.11)*s,Vector3(0.075,0.075,0.065)*s,5)
	if str(e.enemy_kind) == "cyber_flanker":
		for side in [-1.0,1.0]:
			b._taper(e,Vector3(side*0.15,2.74,-0.02)*s,Vector3(0.12,0.28,0.18)*s,Vector2(side*0.22,-0.06)*s,maxf(0.035*s,float(e._cell)*2.1),2)
			b._rod(e,Vector3(side*0.15,2.65,-0.02)*s,Vector3(side*0.22,2.86,-0.06)*s,0.045*s,2)
	elif str(e.enemy_kind) == "cyber_sniper":
		b._box(e,Vector3(-0.24,2.45,0.32)*s,Vector3(0.22,0.20,0.24)*s,7)
		b._ellipsoid(e,Vector3(-0.24,2.45,0.46)*s,Vector3(0.13,0.13,0.08)*s,10)
	elif str(e.enemy_kind) == "cyber_spotter":
		_clear_part(e,protected,Vector3(0,3.13,0),Vector3(1.90,1.18,0.85),9)
		b._box(e,Vector3(0,2.55,0.32)*s,Vector3(0.67,0.18,0.24)*s,7,9)
		for lens in range(5):
			b._ellipsoid(e,Vector3(-0.25+float(lens)*0.125,2.55,0.46)*s,Vector3(0.09,0.10,0.075)*s,10 if lens%2 == 0 else 5,9)


static func _cyber_loadout(e, b: Script, protected: Dictionary, s: float) -> void:
	var kind := str(e.enemy_kind)
	match kind:
		"cyber_breacher":
			_chamfer(e,protected,Vector3(0.76,1.6,0.45),Vector3(0.42,0.32,0.90),0.10,2)
			b._rod(e,Vector3(0.72,1.61,0.03),Vector3(0.78,1.66,0.84),0.11,7,2)
			b._taper(e,Vector3(0.71,1.57,0.22),Vector3(0.32,0.26,0.48),Vector2(0.70,0.19),0.25,5,2)
			for groove in range(3): b._box(e,Vector3(0.76,1.44,0.40+groove*0.11),Vector3(0.29,0.08,0.06),7,2)
			b._box(e,Vector3(-0.48,1.77,0.34),Vector3(0.23,0.20,0.16),7)
			b._box(e,Vector3(-0.48,1.81,0.43),Vector3(0.13,0.05,0.06),3)
		"cyber_riot":
			_chamfer(e,protected,Vector3(-0.76,1.50,0.42),Vector3(0.88,1.55,0.21),0.17,1)
			b._taper(e,Vector3(-0.76,2.43,0.42),Vector3(0.86,0.44,0.21),Vector2(-0.76,0.42),0.66,2,1)
			b._taper(e,Vector3(-0.76,0.62,0.42),Vector3(0.80,0.42,0.21),Vector2(-0.76,0.42),0.86,2,1)
			for x in [-1.12,-0.40]: b._rod(e,Vector3(x,0.66,0.52),Vector3(x,2.44,0.52),0.045,7,1)
			for y in [0.90,1.32,1.78,2.18]:
				b._box(e,Vector3(-0.76,y,0.53),Vector3(0.72,0.075,0.09),7,1)
				b._box(e,Vector3(-0.76,y+0.045,0.58),Vector3(0.21,0.045,0.05),10,1)
			b._rod(e,Vector3(0.74,1.2,0.2),Vector3(0.85,2.2,0.25),0.12,7,2)
		"cyber_sniper":
			_chamfer(e,protected,Vector3(-0.26,1.7,-0.40),Vector3(0.80,1.25,0.22),0.17,0)
			b._rod(e,Vector3(0.67,1.62,-0.10),Vector3(0.70,1.65,1.12),0.083,7,2)
			b._taper(e,Vector3(0.64,1.63,0.14),Vector3(0.32,0.28,0.56),Vector2(0.60,0.12),0.24,5,2)
			b._paint(e,Vector3(0.70,1.86,0.48),Vector3(0.23,0.20,0.46),7)
			b._ellipsoid(e,Vector3(0.70,1.86,0.73),Vector3(0.14,0.14,0.12),10,2)
			for side in [-1.0,1.0]:
				b._taper(e,Vector3(side*0.33,1.08,-0.40),Vector3(0.36,0.94,0.18),Vector2(side*0.26,-0.34),0.27,2)
				b._rod(e,Vector3(0.70,1.58,0.72),Vector3(0.70+side*0.18,1.18,0.92),0.035,5,2)
		"cyber_captain":
			b._rod(e,Vector3(0.76,1.82,0.05),Vector3(0.88,1.90,0.88),0.11,7,2)
			b._taper(e,Vector3(0.82,1.84,0.20),Vector3(0.28,0.26,0.45),Vector2(0.79,0.20),0.23,5,2)
			b._taper(e,Vector3(-0.68,2.26,-0.02)*s,Vector3(0.85,0.29,0.70)*s,Vector2(-0.59,-0.08)*s,0.52*s,2,1)
			for plate in range(3):
				b._box(e,Vector3(-0.66,2.18+plate*0.10,0.32)*s,Vector3(0.37,0.065,0.10)*s,5 if plate%2 == 0 else 3,1)
			var center := Vector3(-0.62,2.78,-0.26)
			var previous := center+Vector3(-0.34,0,0)
			for segment in range(1,9):
				var angle := PI-float(segment)*PI/8.0
				var point := center+Vector3(cos(angle)*0.34,sin(angle)*0.35,0)
				b._rod(e,previous,point,0.065,5,9)
				previous = point
			b._rod(e,center+Vector3(-0.34,0,0),Vector3(-0.36,2.50,-0.25),0.06,7,9)
			b._rod(e,center+Vector3(0.34,0,0),Vector3(-0.36,2.50,-0.25),0.06,7,9)
			for stripe in range(3): b._box(e,Vector3(-0.75+stripe*0.10,2.98,-0.18),Vector3(0.055,0.12,0.06),10,9)
		"cyber_flanker":
			for side in [-1.0,1.0]:
				var part := 1 if side < 0 else 2
				b._rod(e,Vector3(side*0.73,1.30,0.13)*s,Vector3(side*0.86,1.50,0.15),0.105,7,part)
				b._rod(e,Vector3(side*0.86,1.50,0.15),Vector3(side*1.20,2.55,0.40),0.077,5,part)
				b._rod(e,Vector3(side*0.91,1.64,0.21),Vector3(side*1.18,2.42,0.43),0.047,3,part)
				b._box(e,Vector3(side*0.87,1.52,0.16),Vector3(0.36,0.08,0.20),7,part)
				b._taper(e,Vector3(side*0.63,2.18,-0.12)*s,Vector3(0.48,0.22,0.66)*s,Vector2(side*0.51,-0.20)*s,0.25*s,3,part)
		"cyber_suppressor":
			for side in [-1.0,1.0]:
				var part := 1 if side < 0 else 2
				_clear_part(e,protected,Vector3(side*0.90,1.75,0.53),Vector3(0.45,0.45,1.18),part)
				b._rod(e,Vector3(side*0.74,1.74,0.04),Vector3(side*0.90,1.75,1.02),0.15,7,part)
				b._taper(e,Vector3(side*0.84,1.75,0.23),Vector3(0.36,0.35,0.48),Vector2(side*0.82,0.21),0.29,5,part)
				b._rod(e,Vector3(side*0.86,1.35,0.13),Vector3(side*0.80,1.72,0.09),0.115,5,part)
				b._taper(e,Vector3(side*0.67,2.28,-0.04)*s,Vector3(0.89,0.35,0.80)*s,Vector2(side*0.59,-0.07)*s,0.62*s,2,part)
				for shell in range(3):
					var x: float = side*(0.15+shell*0.13)
					b._box(e,Vector3(x,1.96,0.46)*s,Vector3(0.10,0.19,0.12)*s,8)
					b._box(e,Vector3(x,2.06,0.49)*s,Vector3(0.08,0.05,0.08)*s,10)
		"cyber_spotter":
			b._rod(e,Vector3(0.72,1.93,0.04),Vector3(0.78,2.0,0.91),0.105,7,2)
			b._taper(e,Vector3(0.73,1.96,0.20),Vector3(0.30,0.28,0.48),Vector2(0.72,0.18),0.23,5,2)
			b._rod(e,Vector3(-0.25,2.23,-0.20)*s,Vector3(-0.36,2.92,-0.24)*s,0.035*s,5)
			b._box(e,Vector3(-0.36,2.94,-0.24)*s,Vector3(0.045,0.10,0.045)*s,3)


static func _orbital_infantry(e, b: Script, protected: Dictionary) -> void:
	# Bone ceramic panels over a purple/graphite frame, following the orbital
	# sheet. Armor remains an occupied part of the same articulated actor.
	b._paint(e,Vector3(0,1.69,0.0),Vector3(1.05,1.17,0.74),2)
	b._taper(e,Vector3(0,2.57,-0.035),Vector3(0.52,0.32,0.52),Vector2(0,-0.10),0.25,1)
	b._taper(e,Vector3(0,2.33,0.30),Vector3(0.24,0.25,0.18),Vector2(0,0.29),0.16,1)
	for side in [-1.0,1.0]:
		var arm := 1 if side < 0 else 2
		var leg := 3 if side < 0 else 4
		var foot := 5 if side < 0 else 6
		b._rod(e,Vector3(side*0.025,2.48,0.30),Vector3(side*0.23,2.55,0.16),0.044,6)
		b._rod(e,Vector3(side*0.045,2.44,0.31),Vector3(side*0.16,2.48,0.27),0.026,3)
		b._taper(e,Vector3(side*0.22,2.79,-0.11),Vector3(0.14,0.44,0.23),Vector2(side*0.30,-0.15),maxf(0.07,float(e._cell)*2.1),1)
		b._rod(e,Vector3(side*0.21,2.60,-0.06),Vector3(side*0.31,2.98,-0.16),0.060,1)
		b._taper(e,Vector3(side*0.27,1.91,0.29),Vector3(0.49,0.60,0.24),Vector2(side*0.23,0.22),0.32,1)
		b._rod(e,Vector3(side*0.44,2.15,0.30),Vector3(side*0.14,1.64,0.36),0.035,8)
		b._paint(e,Vector3(side*0.55,2.22,-0.08),Vector3(0.80,0.88,0.71),2)
		b._taper(e,Vector3(side*0.62,2.17,-0.05),Vector3(0.70,0.39,0.68),Vector2(side*0.52,-0.16),0.40,1,arm)
		b._taper(e,Vector3(side*0.64,2.00,0.04),Vector3(0.65,0.12,0.61),Vector2(side*0.61,0.04),0.52,2,arm)
		b._box(e,Vector3(side*0.66,2.12,0.30),Vector3(0.22,0.065,0.10),8,arm)
		_clear_part(e,protected,Vector3(side*0.28,0.62,0.08),Vector3(0.58,0.95,0.70),leg)
		var hip := Vector3(side*0.23,1.08,-0.02)
		var knee := Vector3(side*0.30,0.65,0.16)
		var ankle := Vector3(side*0.34,0.20,0.02)
		b._rod(e,hip,knee,0.12,7,leg)
		b._rod(e,knee,ankle,0.095,8,leg)
		b._taper(e,Vector3(side*0.27,0.90,0.04),Vector3(0.34,0.40,0.36),Vector2(side*0.23,-0.04),0.40,1,leg)
		b._ellipsoid(e,knee,Vector3(0.38,0.28,0.34),1,leg)
		b._taper(e,knee+Vector3(0,0,0.15),Vector3(0.25,0.17,0.13),Vector2(knee.x,knee.z+0.12),0.17,8,leg)
		b._taper(e,Vector3(side*0.32,0.43,0.07),Vector3(0.25,0.47,0.32),Vector2(knee.x,knee.z),0.34,1,leg)
		b._ellipsoid(e,ankle,Vector3(0.27,0.20,0.28),7,leg)
		b._taper(e,Vector3(side*0.30,0.15,0.28),Vector3(0.36,0.20,0.48),Vector2(side*0.31,0.14),0.28,1,foot)
		b._taper(e,Vector3(side*0.36,1.14,-0.07),Vector3(0.34,0.48,0.22),Vector2(side*0.26,0.02),0.24,1,leg)
	if str(e.enemy_kind) == "empire_lancer": _orbital_boosters(e,b)
	else: _orbital_shield(e,b)


static func _orbital_boosters(e, b: Script) -> void:
	for side in [-1.0,1.0]:
		b._rod(e,Vector3(side*0.39,1.53,-0.65),Vector3(side*0.44,2.14,-0.65),0.065,8,9)
		b._taper(e,Vector3(side*0.22,1.99,-0.77),Vector3(0.39,0.40,0.22),Vector2(side*0.19,-0.70),0.28,1,9)
		var center := Vector3(side*0.20,1.44,-0.65)
		var previous := center+Vector3(0.20,0,0)
		for segment in range(1,9):
			var a := float(segment)*TAU/8.0
			var point := center+Vector3(cos(a)*0.20,0,sin(a)*0.20)
			b._rod(e,previous,point,0.055,8,9)
			previous = point
		b._ellipsoid(e,center+Vector3(0,0.04,0),Vector3(0.17,0.09,0.17),4,9)
		# Real longitudinal lance guard and back-swept armor seam; its tip stays
		# protected at the original emitter, so collision geometry cannot drift.
		b._rod(e,Vector3(side*0.42,2.18,-0.20),Vector3(side*0.67,2.45,-0.31),0.065,8,1 if side < 0 else 2)


static func _orbital_shield(e, b: Script) -> void:
	for leaf in range(2):
		var part := 1 if leaf == 0 else 9
		var x := -0.96 if leaf == 0 else -0.57
		b._taper(e,Vector3(x,1.55,0.56),Vector3(0.40,2.05,0.17),Vector2(x-0.04 if leaf == 0 else x+0.04,0.51),0.33,1,part)
		for rib in range(4):
			b._box(e,Vector3(x,0.88+rib*0.39,0.66),Vector3(0.34,0.07,0.10),2,part)
			b._box(e,Vector3(x,0.92+rib*0.39,0.69),Vector3(0.12,0.045,0.075),8,part)
		b._rod(e,Vector3(x,0.58,0.60),Vector3(x,2.53,0.60),0.038,8,part)
	b._taper(e,Vector3(0.70,1.84,0.37),Vector3(0.38,0.43,0.65),Vector2(0.70,0.32),0.28,1,2)
	b._rod(e,Vector3(0.70,1.84,0.08),Vector3(0.70,1.84,0.81),0.11,7,2)


static func _orbital_walker(e, b: Script, protected: Dictionary) -> void:
	b._taper(e,Vector3(0,2.27,-0.04),Vector3(1.66,0.32,1.0),Vector2(0,-0.15),1.15,1)
	for side in [-1.0,1.0]:
		var gun := 1 if side < 0 else 2
		b._taper(e,Vector3(side*0.47,1.84,0.47),Vector3(0.51,0.82,0.27),Vector2(side*0.39,0.36),0.30,1)
		b._taper(e,Vector3(side*0.90,2.0,-0.14),Vector3(0.69,0.67,0.81),Vector2(side*0.90,-0.18),0.54,1,gun)
		b._rod(e,Vector3(side*0.90,2.0,-0.61),Vector3(side*0.90,2.0,0.43),0.18,2,gun)
		for slot in range(3): b._box(e,Vector3(side*0.90,2.23,-0.30+slot*0.18),Vector3(0.43,0.065,0.075),8,gun)
		for row in range(2):
			var sign_z := -1.0 if row == 0 else 1.0
			var z := sign_z*0.45
			var part := 3+row*2+(0 if side < 0 else 1)
			_clear_part(e,protected,Vector3(side*1.0,0.25,z+0.08),Vector3(0.72,0.40,0.90),part)
			b._rod(e,Vector3(side*0.95,0.58,z),Vector3(side*1.13,0.22,z+sign_z*0.10),0.115,8,part)
			b._taper(e,Vector3(side*1.01,0.47,z),Vector3(0.35,0.34,0.37),Vector2(side*0.95,z),0.43,1,part)
			b._box(e,Vector3(side*1.13,0.18,z+sign_z*0.10),Vector3(0.35,0.21,0.30),2,part)
			for toe in range(3):
				b._rod(e,Vector3(side*1.13,0.17,z+sign_z*0.13),Vector3(side*(1.13+float(toe-1)*0.16),0.07,z+sign_z*(0.48 if toe == 1 else 0.37)),0.083,1,part)
