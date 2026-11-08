class_name EnemyArchetypes
extends RefCounted
## Space-shooter silhouettes made from the same cuttable material as the old
## enemies. These helpers author cells and move existing parts; no hull prop
## can hide a missing cell or keep a severed launch mouth firing.

const MotionScript = preload("res://scripts/enemy_motion.gd")
const KINDS := ["shield_drone", "interceptor", "mine_layer"]


static func supports(kind: String) -> bool:
	return kind in KINDS


static func dimensions(kind: String) -> Dictionary:
	match kind:
		"shield_drone": return {"dimensions":Vector3i(42,44,32),"cell":0.075}
		"interceptor": return {"dimensions":Vector3i(42,44,32),"cell":0.07}
		"mine_layer": return {"dimensions":Vector3i(52,42,34),"cell":0.075}
	return {}


static func build(enemy) -> void:
	match str(enemy.enemy_kind):
		"shield_drone": _build_shield(enemy)
		"interceptor": _build_interceptor(enemy)
		"mine_layer": _build_mine_layer(enemy)


static func classify_part(kind: String, point: Vector3) -> int:
	if kind == "mine_layer" and absf(point.x) < 0.40 and point.y < 1.88 and point.z > 0.15:
		return 3
	var hinge := 0.30 if kind == "shield_drone" else (0.28 if kind == "interceptor" else 0.40)
	return (1 if point.x < 0.0 else 2) if absf(point.x) > hinge else 0


static func emitters(kind: String) -> Array[Dictionary]:
	match kind:
		"shield_drone":
			return [{"part":0,"point":Vector3(0,1.82,0.76),"half":Vector3(0.10,0.10,0.12)}]
		"interceptor":
			return [{"part":1,"point":Vector3(-0.97,2.10,0.78),"half":Vector3(0.14,0.10,0.12)}, {"part":2,"point":Vector3(0.97,2.10,0.78),"half":Vector3(0.14,0.10,0.12)}]
		"mine_layer":
			return [{"part":1,"point":Vector3(-1.14,2.00,0.72),"half":Vector3(0.20,0.14,0.12)}, {"part":2,"point":Vector3(1.14,2.00,0.72),"half":Vector3(0.20,0.14,0.12)}, {"part":3,"point":Vector3(0,1.72,0.75),"half":Vector3(0.18,0.12,0.12)}]
	return []


static func emitter_intact(enemy, part: int) -> bool:
	for emitter: Dictionary in emitters(str(enemy.enemy_kind)):
		if int(emitter.part) != part: continue
		for index in enemy._live_indices:
			if enemy._voxels[index] == 0 or enemy._part_ids[index] != part: continue
			var delta: Vector3 = (enemy._cell_points[index]-Vector3(emitter.point)).abs()
			var half: Vector3 = emitter.half
			if delta.x <= half.x and delta.y <= half.y and delta.z <= half.z:
				return true
	return false


static func apply_pose(enemy, action: String, phase: float) -> void:
	var pose := MotionScript.sample_space_flyer(str(enemy.enemy_kind),float(enemy.age),int(enemy.lane_index),action,phase)
	enemy.action_name = action
	enemy.action_phase = clampf(phase,0.0,1.0)
	enemy._rig.transform = pose.rig
	for part in range(1,enemy.PART_COUNT):
		enemy._parts[part].transform = pose.parts.get(part,Transform3D.IDENTITY)
	var charge: float = pose.charge
	var kick: float = pose.kick
	for glow: MeshInstance3D in enemy._expansion_glows:
		var part := int(glow.get_meta("emitter_part"))
		glow.visible = (charge > 0.03 or kick > 0.05) and enemy._emitter_intact(part)
		glow.scale = Vector3.ONE*(0.4+charge*0.7+kick*0.75)
	enemy._weapon_edge_material.albedo_color = Color("ff9b36").lerp(Color("fff1b8"),charge)
	enemy._weapon_edge_material.emission_energy_multiplier = 0.8+charge*2.0
	enemy._trail.visible = false


static func _box(enemy, center: Vector3, size: Vector3, material: int) -> void:
	enemy._slasher_box(center,size,material)


static func _rod(enemy, from: Vector3, to: Vector3, radius: float, material: int) -> void:
	enemy._slasher_rod(from,to,radius,material)


static func _tags(enemy, anchor: Vector3, core: Vector3, head: Vector3) -> void:
	enemy._slasher_tags(anchor,Vector3(0.20,0.17,0.23),enemy.ANCHOR_TAG)
	enemy._slasher_tags(core,Vector3(0.20,0.20,0.24),enemy.CORE_TAG)
	enemy._slasher_tags(head,Vector3(0.20,0.15,0.23),enemy.HEAD_TAG)


static func _build_shield(enemy) -> void:
	# A narrow hanging engine spine carries two deep, chamfered armour leaves.
	# The copper root is behind the leaves and still genuinely cuttable.
	_box(enemy,Vector3(0,1.53,-0.20),Vector3(0.43,0.30,0.52),2)
	_rod(enemy,Vector3(0,1.59,-0.18),Vector3(0,2.52,-0.14),0.14,3)
	_box(enemy,Vector3(0,2.17,-0.14),Vector3(0.48,0.52,0.48),2)
	_box(enemy,Vector3(0,2.20,0.12),Vector3(0.18,0.20,0.11),4)
	_rod(enemy,Vector3(0,2.43,-0.16),Vector3(0,2.76,-0.16),0.11,5)
	enemy._slasher_taper(2.60,2.91,Vector2(0,-0.15),Vector2(0,-0.22),0.40,0.30,0.41,0.32,1)
	_box(enemy,Vector3(0,2.72,0.08),Vector3(0.22,0.075,0.10),4)
	for side in [-1.0,1.0]:
		_rod(enemy,Vector3(side*0.15,2.24,-0.13),Vector3(side*0.76,2.24,0.28),0.14,3)
		_rod(enemy,Vector3(side*0.75,2.24,0.24),Vector3(side*0.71,2.24,0.61),0.13,5)
		# Staggered upper corners and tapered lower tips keep the silhouette
		# shield-shaped instead of another rectangular missile launcher.
		enemy._slasher_taper(1.34,1.73,Vector2(side*0.47,0.61),Vector2(side*0.64,0.60),0.33,0.89,0.32,0.45,2)
		enemy._slasher_taper(1.73,2.69,Vector2(side*0.64,0.60),Vector2(side*0.64,0.58),0.89,0.94,0.45,0.44,1)
		enemy._slasher_taper(2.69,2.98 if side < 0.0 else 2.89,Vector2(side*0.64,0.58),Vector2(side*0.65,0.54),0.94,0.66,0.44,0.32,2)
		_box(enemy,Vector3(side*0.64,2.25,0.86),Vector3(0.11,1.22,0.10),5)
		_box(enemy,Vector3(side*0.27,2.23,0.84),Vector3(0.11,0.67,0.09),3)
		for y in [1.83,2.21,2.59]:
			_box(enemy,Vector3(side*0.93,y,0.84),Vector3(0.12,0.12,0.10),8)
		_box(enemy,Vector3(side*0.68,1.48,0.72),Vector3(0.25,0.10,0.14),10)
		_box(enemy,Vector3(side*0.13,1.56,-0.48),Vector3(0.13,0.16,0.16),10)
	# This exposed lower gun shares the engine body, not the shield plate.
	_rod(enemy,Vector3(0,1.93,-0.03),Vector3(0,1.82,0.58),0.13,5)
	_box(enemy,Vector3(0,1.82,0.64),Vector3(0.25,0.23,0.35),2)
	_box(enemy,Vector3(0,1.82,0.77),Vector3(0.16,0.14,0.12),10)
	_tags(enemy,Vector3(0,1.52,-0.20),Vector3(0,2.20,-0.10),Vector3(0,2.72,-0.16))
	enemy._core_point = Vector3(0,2.20,0.18)


static func _build_interceptor(enemy) -> void:
	# A long spear nose and swept fork wings read like a fast interceptor,
	# with independent gun tips on the two actual folding wing parts.
	_box(enemy,Vector3(0,1.55,-0.36),Vector3(0.32,0.22,0.38),2)
	enemy._slasher_taper(1.25,1.55,Vector2(0,-0.33),Vector2(0,-0.36),0.08,0.30,0.15,0.32,1)
	_rod(enemy,Vector3(0,1.61,-0.33),Vector3(0,2.42,-0.20),0.105,3)
	enemy._slasher_taper(1.87,2.42,Vector2(0,-0.12),Vector2(0,-0.28),0.32,0.44,0.76,0.71,2)
	_rod(enemy,Vector3(0,2.12,0.17),Vector3(0,2.12,0.85),0.10,1)
	_box(enemy,Vector3(0,2.19,0.29),Vector3(0.16,0.10,0.25),4)
	_rod(enemy,Vector3(0,2.36,-0.24),Vector3(0,2.66,-0.20),0.09,3)
	enemy._slasher_taper(2.53,2.80,Vector2(0,-0.20),Vector2(0,-0.34),0.33,0.13,0.32,0.20,1)
	_box(enemy,Vector3(0,2.64,-0.12),Vector3(0.16,0.10,0.22),2)
	_box(enemy,Vector3(0,2.64,0),Vector3(0.21,0.07,0.10),4)
	for side in [-1.0,1.0]:
		_rod(enemy,Vector3(side*0.14,2.16,-0.13),Vector3(side*0.99,2.10,0.01),0.10,3)
		_rod(enemy,Vector3(side*0.43,2.17,-0.11),Vector3(side*1.25,1.62,-0.56),0.12,1)
		_rod(enemy,Vector3(side*0.76,1.95,-0.29),Vector3(side*1.25,1.62,-0.56),0.09,5)
		_rod(enemy,Vector3(side*0.99,2.10,-0.15),Vector3(side*0.97,2.10,0.68),0.13,2)
		_box(enemy,Vector3(side*0.97,2.10,0.45),Vector3(0.29,0.22,0.47),1)
		_box(enemy,Vector3(side*0.97,2.10,0.75),Vector3(0.23,0.16,0.16),7)
		_box(enemy,Vector3(side*0.97,2.10,0.82),Vector3(0.12,0.095,0.08),10)
		_box(enemy,Vector3(side*0.41,2.04,-0.46),Vector3(0.24,0.25,0.40),2)
		_box(enemy,Vector3(side*0.41,2.04,-0.69),Vector3(0.17,0.14,0.10),10)
		_rod(enemy,Vector3(side*0.36,1.99,-0.33),Vector3(side*0.84,1.75,-0.48),0.08,1)
		_box(enemy,Vector3(side*0.68,2.00,-0.30),Vector3(0.10,0.075,0.20),3)
	_tags(enemy,Vector3(0,1.55,-0.36),Vector3(0,2.17,-0.10),Vector3(0,2.64,-0.20))
	enemy._core_point = Vector3(0,2.17,0.31)


static func _build_mine_layer(enemy) -> void:
	# A flat M-wing gunship with three separate, underslung launch mouths.
	# Chambers and rear engine blocks are true connected cells, not props.
	_box(enemy,Vector3(0,1.48,-0.34),Vector3(0.43,0.26,0.45),2)
	_rod(enemy,Vector3(0,1.57,-0.32),Vector3(0,2.39,-0.17),0.14,3)
	_box(enemy,Vector3(0,2.16,-0.15),Vector3(0.63,0.43,0.72),2)
	_box(enemy,Vector3(0,2.23,0.25),Vector3(0.31,0.12,0.12),4)
	_rod(enemy,Vector3(0,2.33,-0.21),Vector3(0,2.67,-0.25),0.12,5)
	enemy._slasher_taper(2.56,2.81,Vector2(0,-0.25),Vector2(0,-0.35),0.43,0.30,0.44,0.30,1)
	_box(enemy,Vector3(0,2.66,0),Vector3(0.27,0.075,0.10),4)
	for side in [-1.0,1.0]:
		_rod(enemy,Vector3(side*0.22,2.16,-0.17),Vector3(side*1.12,2.00,-0.04),0.16,3)
		_rod(enemy,Vector3(side*0.30,2.31,-0.23),Vector3(side*1.52,2.57,-0.25),0.14,1)
		_rod(enemy,Vector3(side*1.52,2.57,-0.25),Vector3(side*1.66,2.11,-0.18),0.11,2)
		_box(enemy,Vector3(side*1.14,2.00,0.11),Vector3(0.68,0.46,0.90),2)
		_box(enemy,Vector3(side*1.14,2.27,0.06),Vector3(0.70,0.15,0.87),1)
		_box(enemy,Vector3(side*1.14,2.00,0.61),Vector3(0.58,0.33,0.23),5)
		_box(enemy,Vector3(side*1.14,2.00,0.74),Vector3(0.42,0.24,0.10),7)
		for slit in [-1.0,1.0]:
			_box(enemy,Vector3(side*1.14+slit*0.11,2.00,0.80),Vector3(0.09,0.16,0.08),10)
		_box(enemy,Vector3(side*1.14,2.00,-0.43),Vector3(0.42,0.28,0.14),3)
		_box(enemy,Vector3(side*1.14,2.00,-0.53),Vector3(0.25,0.14,0.10),10)
		_box(enemy,Vector3(side*1.51,2.53,-0.15),Vector3(0.17,0.12,0.30),5)
		_box(enemy,Vector3(side*1.14,2.36,0.17),Vector3(0.13,0.10,0.31),8)
	_rod(enemy,Vector3(0,2.04,-0.16),Vector3(0,1.72,0.36),0.15,5)
	_box(enemy,Vector3(0,1.72,0.40),Vector3(0.48,0.29,0.54),2)
	_box(enemy,Vector3(0,1.72,0.70),Vector3(0.37,0.23,0.18),5)
	_box(enemy,Vector3(0,1.72,0.80),Vector3(0.23,0.16,0.09),10)
	_tags(enemy,Vector3(0,1.48,-0.34),Vector3(0,2.16,-0.15),Vector3(0,2.66,-0.25))
	enemy._core_point = Vector3(0,2.20,0.33)
