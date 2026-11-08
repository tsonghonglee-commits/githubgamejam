class_name EncounterDirector
extends RefCounted
## Deterministic authored groups. The main scene owns movement, attacks and
## the actual active-enemy budget; this file only proposes the next group.

const ROW_ATTACK_DELAYS := [0.0,0.12,0.64,0.76]
const COMPLEX_RANGED := ["ranged","drone","missile_drone","interceptor","mine_layer"]


static func plan(wave_index: int, progress: float, speed: float) -> Dictionary:
	var index := maxi(wave_index,0)
	var fraction := clampf(progress,0.0,1.0)
	var stage := 0 if fraction < 0.30 else (1 if fraction < 0.50 else (2 if fraction < 0.75 else 3))
	var lane: int = [1,2,0,3][index % 4]
	# These first three lessons stay in order even when a review route is
	# shortened. Their two 6s intervals expose the row before a 20s Boss.
	if index == 0:
		return _group("opening_single",0,[_spawn("normal",1)],6.0,2.8,speed)
	if index == 1:
		return _pair(0,index,speed,6.0)
	if index == 2:
		return _row(0,speed)
	var slot := index-3
	match stage:
		0:
			match slot % 4:
				0: return _group("normal_single",stage,[_spawn("normal",lane)],6.2,2.8,speed)
				1: return _pair(stage,index,speed)
				2: return _row(stage,speed)
				_: return _group("normal_single",stage,[_spawn("normal",3-lane)],6.2,2.8,speed)
		1:
			match slot % 6:
				0: return _single_ranged("interceptor_lesson","interceptor",stage,lane,speed)
				1: return _pair(stage,index,speed)
				2: return _row(stage,speed)
				3: return _single_ranged("ranged_lesson","ranged",stage,lane,speed)
				4: return _single_ranged("drone_lesson","drone",stage,lane,speed)
				_: return _group("cut_beam",stage,[_spawn("beam",1)],7.2,2.9,speed)
		2:
			match slot % 6:
				0: return _single_ranged("mine_layer_lesson","mine_layer",stage,lane,speed)
				1: return _pair(stage,index,speed)
				2: return _group("tank_lesson",stage,[_spawn("tank",0 if index % 2 == 0 else 2)],7.8,3.0,speed)
				3: return _row(stage,speed)
				4: return _single_ranged("interceptor_return","interceptor",stage,lane,speed)
				_: return _group("cut_barrier",stage,[_spawn("barrier",1)],7.2,2.9,speed)
		_:
			match slot % 8:
				0: return _row(stage,speed)
				1: return _single_ranged("missile_drone_lesson","missile_drone",stage,lane,speed)
				2: return _ranged_pair("ranged",stage,index,speed)
				3: return _single_ranged("mine_layer_return","mine_layer",stage,lane,speed)
				4: return _group("tank_return",stage,[_spawn("tank",0 if index % 2 == 0 else 2)],7.6,3.0,speed)
				5: return _group("cut_beam",stage,[_spawn("beam",1)],7.2,2.9,speed)
				6: return _ranged_pair("drone",stage,index,speed)
				_: return _single_ranged("interceptor_return","interceptor",stage,lane,speed)
	return _group("normal_single",stage,[_spawn("normal",lane)],6.2,2.8,speed)


static func _spawn(kind: String, lane: int, z_offset: float = 0.0, attack_delay: float = 0.0, fire_delay: float = 0.0, role: String = "lead") -> Dictionary:
	return {"kind":kind,"lane":lane,"z_offset":z_offset,"role":role,"fire_delay":fire_delay,"attack_delay":attack_delay}


static func _group(id: String, stage: int, spawns: Array, interval: float, lead: float, speed: float) -> Dictionary:
	return {
		"id":id,"stage":stage,"spawns":spawns,"interval":interval,
		"lead_seconds":lead,"hold_until_clear":true,"heavy_ranged_cap":1,
		"recovery_seconds":1.2 if spawns.size() == 4 else 1.0,
		"planned_speed":clampf(speed,4.0,60.0),
	}


static func _pair(stage: int, index: int, speed: float, interval: float = 7.2) -> Dictionary:
	var lane := 0 if index % 2 == 0 else 1
	return _group("staggered_pair",stage,[
		_spawn("normal",lane,0.0,0.0,0.0,"lead"),
		_spawn("normal",lane+2,-10.0,0.18,0.0,"follow"),
	],interval,2.8,speed)


static func _row(stage: int, speed: float) -> Dictionary:
	var spawns: Array[Dictionary] = []
	for lane in range(4):
		spawns.append(_spawn("normal",lane,0.0,float(ROW_ATTACK_DELAYS[lane]),0.0,"row"))
	return _group("four_lane_row",stage,spawns,8.2,3.2,speed)


static func _single_ranged(id: String, kind: String, stage: int, lane: int, speed: float) -> Dictionary:
	return _group(id,stage,[_spawn(kind,lane,0.0,0.0,0.65,"ranged_lesson")],7.8,3.0,speed)


static func _ranged_pair(kind: String, stage: int, index: int, speed: float) -> Dictionary:
	var lane := 0 if index % 2 == 0 else 3
	return _group("ranged_with_follow",stage,[
		_spawn(kind,lane,0.0,0.0,0.85,"ranged_lead"),
		_spawn("normal",3-lane,-20.0,0.25,0.0,"follow"),
	],8.4,3.0,speed)
