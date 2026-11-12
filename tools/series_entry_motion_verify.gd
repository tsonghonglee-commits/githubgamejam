extends SceneTree
## Pure normalized pose math: no enemy scene, mesh, combat, AI or wave update.
const Motion = preload("res://scripts/series_entry_motion.gd")
const GROUND := ["ink_swordsman","ink_spear","ink_talisman","cyber_breacher","cyber_riot","cyber_sniper","sea_skimmer","sea_crab","empire_walker","empire_lancer","empire_sentinel"]
const BOSS := ["ink_master","cyber_captain","cyber_flanker","cyber_suppressor","cyber_spotter","cyber_helicopter","cyber_tank","cyber_gunship","sea_leviathan","empire_dreadnought"]
const FLY := ["ink_crane","cyber_drone","sea_eel","sea_ray","empire_fighter"]
var checks := 0
var failures: Array[String] = []
var records: Array[Dictionary] = []
var output_path := "res://.local/series-entry-motion-final.json"


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--entry-output="): output_path = argument.trim_prefix("--entry-output=")
	call_deferred("_run")


func _expect(okay: bool, label: String) -> void:
	checks += 1
	if not okay:
		failures.append(label)
		push_error(label)


func _valid_transform(value: Transform3D) -> bool:
	return value.origin.is_finite() and value.basis.x.is_finite() and value.basis.y.is_finite() and value.basis.z.is_finite() and absf(value.basis.determinant()-1.0) < 0.0001 and value.basis.is_equal_approx(value.basis.orthonormalized())


func _neutral(data: Dictionary) -> bool:
	if not Vector3(data.offset).is_zero_approx() or not Vector3(data.rotation).is_zero_approx(): return false
	if not Transform3D(data.rig).is_equal_approx(Transform3D.IDENTITY): return false
	for transform: Transform3D in data.parts.values():
		if not transform.is_equal_approx(Transform3D.IDENTITY): return false
	return is_equal_approx(float(data.opacity),1.0)


func _signature(kind: String) -> String:
	var values: Array = []
	for p in [0.15,0.35,0.55,0.80]:
		var data: Dictionary = Motion.sample(kind,p,0)
		values.append([str(data.offset),str(data.rotation),str(data.rig),str(data.parts)])
	return JSON.stringify(values).sha256_text()


func _verify_kind(kind: String) -> void:
	var finite := true
	var monotone := true
	var keys_valid := true
	var behind := true
	var roots_stopped := true
	var flight_animated := false
	var previous_opacity := -1.0
	var max_z := -INF
	for lane in range(7):
		previous_opacity = -1.0
		for tick in range(101):
			var p := tick/100.0
			var data: Dictionary = Motion.sample(kind,p,lane)
			finite = finite and Vector3(data.offset).is_finite() and Vector3(data.rotation).is_finite() and _valid_transform(data.rig)
			monotone = monotone and float(data.opacity) >= -0.00001 and float(data.opacity) <= 1.00001 and float(data.opacity)+0.00001 >= previous_opacity
			previous_opacity = float(data.opacity)
			for part: int in data.parts:
				keys_valid = keys_valid and part > 0 and part < 10 and _valid_transform(data.parts[part])
			if kind in GROUND:
				behind = behind and Vector3(data.offset).z <= 0.00001
				if p >= float(data.impact_phase)+0.00001: roots_stopped = roots_stopped and Vector3(data.offset).is_zero_approx()
				max_z = maxf(max_z,-40.0+Vector3(data.offset).z)
			if kind in FLY: flight_animated = flight_animated or (Vector3(data.offset).length() > 10.0 and not data.parts.is_empty())
	_expect(finite,kind+": finite rigid transforms")
	_expect(monotone,kind+": fade monotone in [0,1]")
	_expect(keys_valid,kind+": real part IDs1..9 only")
	_expect(_neutral(Motion.sample(kind,1.0,0)) and _neutral(Motion.sample(kind,4.0,6)),kind+": neutral terminal and clamped phase")
	var end_near: Dictionary = Motion.sample(kind,0.999,0)
	_expect(_neutral(end_near),kind+": continuous settled terminal")
	if kind in GROUND:
		_expect(behind and roots_stopped and max_z <= -40.0,kind+": root approach stops before planted phase; stays40m away")
		_expect(Vector3(Motion.sample(kind,0.0,0).offset).z <= -30.0,kind+": begins at least30m behind entry destination")
	if kind in FLY: _expect(flight_animated,kind+": owns travel and articulated flight pose")
	records.append({"kind":kind,"signature":_signature(kind),"maximum_ground_root_z":max_z if kind in GROUND else null})


func _run() -> void:
	_expect(Motion.GROUNDED == GROUND and Motion.BOSSES == BOSS and Motion.ORDINARY_FLYERS == FLY,"literal26kind catalog")
	for kind: String in GROUND+BOSS+FLY: _verify_kind(kind)
	for group in [GROUND,BOSS,FLY]:
		var signatures := {}
		for kind: String in group: signatures[_signature(kind)] = kind
		_expect(signatures.size() == group.size(),"distinct sampled geometry pose signatures: "+str(group.size()))
	_expect(_neutral(Motion.sample("unknown",0.45,0)),"unknown kind is neutral")
	_expect(Vector3(Motion.sample("ink_master",0.23,0).offset).x*Vector3(Motion.sample("ink_master",0.45,0).offset).x < 0.0,"master crosses the center between the two approach beats")
	var hashes := {}
	for path in ["res://scripts/series_entry_motion.gd","res://scripts/series_combat.gd","res://tools/series_entry_motion_verify.gd"]: hashes[path] = FileAccess.get_sha256(path)
	var report := {"scope":"normalized pose mathematics only; no actors/material/mesh/GPU/AI/waves/completion; root-distance check is not actual mesh clearance", "checks":checks,"failures":failures,"records":records,"source_sha256":hashes}
	var output := FileAccess.open(output_path,FileAccess.WRITE)
	if output == null:
		push_error("Cannot write pose report")
		quit(1)
		return
	output.store_string(JSON.stringify(report,"\t"))
	output.close()
	print("ENTRY_POSE_VERIFY ",checks," checks / ",failures.size()," failures; ",output_path)
	quit(0 if failures.is_empty() else 1)
