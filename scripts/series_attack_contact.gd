extends RefCounted
## Weapon contacts use surviving occupied cells in the authored weapon volume.
## The previous and current true part transforms form a swept material test.
static var _candidates: Dictionary = {}
const BODY_LOW := Vector3(0,0.90,-0.55)
const BODY_HIGH := Vector3(0,1.65,-0.55)

static func prepare(enemy, layout: Dictionary) -> void:
	var kind: String = enemy.enemy_kind
	if _candidates.has(kind): return
	# A first actor may already be damaged when it begins its attack. Always
	# derive the shared candidate list from the complete immutable template.
	var template: Dictionary = enemy._body_templates[enemy._model_template_key(kind,int(enemy.construct_variant))]
	var live: PackedInt32Array = template.live
	var parts: PackedByteArray = template.parts
	var points: PackedVector3Array = template.points
	var candidates: Array[Dictionary] = []
	for weapon: Dictionary in layout.get("melee_segments",[]):
		var indices := PackedInt32Array()
		var bounds := AABB()
		var a: Vector3 = weapon.a
		var b: Vector3 = weapon.b
		var axis := b-a
		var radius: float = float(weapon.get("radius",0.12))+float(enemy._cell)*0.87
		for index: int in live:
			if int(parts[index]) != int(weapon.part): continue
			var point: Vector3 = points[index]
			var t := clampf((point-a).dot(axis)/maxf(axis.length_squared(),0.00001),0.0,1.0)
			if point.distance_squared_to(a+axis*t) <= radius*radius:
				bounds = AABB(point,Vector3.ZERO) if indices.is_empty() else bounds.expand(point)
				indices.append(index)
		candidates.append({"part":int(weapon.part),"indices":indices,"tip":b,"bounds":bounds})
	_candidates[kind] = candidates

static func surviving_tip(enemy, layout: Dictionary, part: int) -> Dictionary:
	prepare(enemy,layout)
	for weapon: Dictionary in _candidates.get(str(enemy.enemy_kind),[]):
		if int(weapon.part) != part: continue
		var best := -1
		var distance := INF
		for index: int in weapon.indices:
			if enemy._voxels[index] == 0: continue
			var point: Vector3 = enemy._cell_points[index]
			var candidate := point.distance_squared_to(weapon.tip)
			if candidate < distance:
				best = index
				distance = candidate
		if best >= 0:
			var pose: Transform3D = enemy.global_transform*enemy._part_pose(part)
			return {"cell":best,"point":pose*enemy._cell_points[best]}
	return {}

static func reset(enemy) -> void:
	enemy.set_meta("series_weapon_previous",{})

static func weapon_candidates(enemy, layout: Dictionary) -> Array[Dictionary]:
	prepare(enemy,layout)
	var candidates: Array[Dictionary] = _candidates[str(enemy.enemy_kind)]
	if str(enemy.enemy_kind) != "sea_crab": return candidates
	var active_part := 1 if int(enemy.get_meta("series_attack_variant",0))%2 == 0 else 2
	var active: Array[Dictionary] = []
	for weapon: Dictionary in candidates:
		if int(weapon.part) == active_part: active.append(weapon)
	return active

static func check(enemy, layout: Dictionary) -> Dictionary:
	var previous: Dictionary = enemy.get_meta("series_weapon_previous",{})
	var current: Dictionary = {}
	var result: Dictionary = {}
	for weapon: Dictionary in weapon_candidates(enemy,layout):
		var part := int(weapon.part)
		var now: Transform3D = enemy.global_transform*enemy._part_pose(part)
		var before: Transform3D = previous.get(part,now)
		current[part] = now
		var index := swept_cell(enemy,weapon,before,now)
		if index >= 0:
			result = {"hit":true,"part":part,"cell":index,"point":now*enemy._cell_points[index]}
			break
	enemy.set_meta("series_weapon_previous",current)
	return result

static func swept_cell(enemy, weapon: Dictionary, before: Transform3D, now: Transform3D) -> int:
	var radius: float = 0.31+float(enemy._cell)*0.87
	var bounds: AABB = weapon.bounds
	# Every swept centre stays inside the union bounds of the two endpoint poses.
	var capsule := AABB(BODY_LOW,BODY_HIGH-BODY_LOW).grow(radius+0.00001)
	if not capsule.intersects((before*bounds).merge(now*bounds)): return -1
	var reach := radius*radius
	var voxels: PackedByteArray = enemy._voxels
	var points: PackedVector3Array = enemy._cell_points
	for index: int in weapon.indices:
		if voxels[index] == 0: continue
		var point := points[index]
		# The cube circumradius conservatively includes its face.
		if _segment_distance_squared(before*point,now*point,BODY_LOW,BODY_HIGH) <= reach: return index
	return -1

static func _segment_distance_squared(a: Vector3,b: Vector3,c: Vector3,d: Vector3) -> float:
	var u := b-a
	var v := d-c
	var w := a-c
	var aa := u.dot(u)
	var bb := u.dot(v)
	var cc := v.dot(v)
	var dd := u.dot(w)
	var ee := v.dot(w)
	if aa < 0.00000001:
		return a.distance_squared_to(c+v*clampf(ee/maxf(cc,0.00000001),0.0,1.0))
	var denominator := aa*cc-bb*bb
	var s := clampf((bb*ee-cc*dd)/denominator,0.0,1.0) if denominator > 0.00000001 else 0.0
	var t := (bb*s+ee)/maxf(cc,0.00000001)
	if t < 0.0:
		t = 0.0
		s = clampf(-dd/aa,0.0,1.0)
	elif t > 1.0:
		t = 1.0
		s = clampf((bb-dd)/aa,0.0,1.0)
	return (a+u*s).distance_squared_to(c+v*t)
