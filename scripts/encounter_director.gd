class_name EncounterDirector
extends RefCounted
## Preserve the v0.9.5 stream's order, lane cycle and timed cadence. The main
## scene owns admission limits and the one exceptional row's clear window.

const ROW_ATTACK_DELAYS := [0.0,0.12,0.64,0.76]
const COMPLEX_RANGED := ["ranged","drone","missile_drone","interceptor","mine_layer"]
const BASELINE_SEQUENCE := ["normal","ranged","drone","normal","barrier","tank","missile_drone","ranged","beam","drone","normal","tank"]
const BASELINE_LANES := [1,2,0,3,2,1,0,2]
const ROW_WAVE_INDEX := 22


static func plan(wave_index: int, progress: float, speed: float, route_seconds: float = 180.0) -> Dictionary:
	var index := maxi(wave_index,0)
	var elapsed := clampf(progress,0.0,1.0)*maxf(route_seconds,1.0)
	var original: String = BASELINE_SEQUENCE[index % BASELINE_SEQUENCE.size()]
	var lane: int = BASELINE_LANES[index % BASELINE_LANES.size()]
	if original == "tank": lane = 0 if index % 2 == 0 else 2
	# A single ordinary slot becomes the optional broad-cut moment. It does
	# not cycle, and shortened routes cannot pull it into their opening.
	if index == ROW_WAVE_INDEX and elapsed >= 75.0:
		return _row(index,elapsed,speed)
	var kind := original
	var advanced := false
	if (index == 13 and elapsed >= 50.0) or (index == 37 and elapsed >= 130.0):
		kind = "interceptor"
		advanced = true
	elif index == 25 and elapsed >= 90.0:
		kind = "mine_layer"
		advanced = true
	var first_delay := 0.65 if kind == "interceptor" else (0.85 if kind == "mine_layer" else (0.25 if kind in COMPLEX_RANGED else 0.0))
	var spawns: Array[Dictionary] = [_spawn(kind,lane,0.0,0.0,first_delay,"advanced_intro" if advanced else "baseline")]
	# Match the old post-increment test: current zero-based slots3,7,11...
	# may add one ordinary follower after75s, fourteen metres behind.
	if not advanced and elapsed > 75.0 and (index+1) % 4 == 0 and kind not in ["barrier","beam"]:
		spawns.append(_spawn("normal",(lane+2)%4,-14.0,0.0,0.0,"baseline_follow"))
	var result := _group("advanced_"+kind if advanced else "baseline_"+kind,index,elapsed,spawns,4.3 if elapsed < 40.0 else 3.5,2.0,speed)
	result["baseline_kind"] = original
	result["advanced_intro"] = advanced
	return result


static func _spawn(kind: String, lane: int, z_offset: float = 0.0, attack_delay: float = 0.0, fire_delay: float = 0.0, role: String = "lead") -> Dictionary:
	return {"kind":kind,"lane":lane,"z_offset":z_offset,"role":role,"fire_delay":fire_delay,"attack_delay":attack_delay}


static func _group(id: String, index: int, elapsed: float, spawns: Array, interval: float, lead: float, speed: float) -> Dictionary:
	return {
		"id":id,"stage":0 if elapsed < 40.0 else (1 if elapsed < 75.0 else (2 if elapsed < 130.0 else 3)),
		"spawns":spawns,"interval":interval,"lead_seconds":lead,
		"approach_seconds":lead,"minimum_distance":40.0,"approach_speed_offset":0.0,"distance_bias":12.0,
		"hold_until_clear":false,"heavy_ranged_cap":2,"recovery_seconds":0.0,
		"baseline_index":index,"route_elapsed":elapsed,"advanced_intro":false,
		"planned_speed":clampf(speed,4.0,60.0),
	}


static func _row(index: int, elapsed: float, speed: float) -> Dictionary:
	var spawns: Array[Dictionary] = []
	for lane in range(4):
		spawns.append(_spawn("normal",lane,0.0,float(ROW_ATTACK_DELAYS[lane]),0.0,"row"))
	var result := _group("four_lane_row",index,elapsed,spawns,4.8,2.4,speed)
	result["baseline_kind"] = "normal"
	result["hold_until_clear"] = true
	result["recovery_seconds"] = 1.2
	return result
