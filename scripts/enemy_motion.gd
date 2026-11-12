class_name EnemyMotion
extends RefCounted

const STANCE_FRACTION := 0.6
const SWING_FRACTION := 1.0 - STANCE_FRACTION
const LENGTH_EPSILON := 0.000001
const FLYBY_ENTRY_TIME_SCALE := 2.0/3.0
const GROUND_ENTRY_EXTRA_DEPTH := 30.0
const GROUND_ENTRY_FADE_END_PHASE := 0.42
# Authored blade-tip / hammer-base vertices, rotated about their real shoulder
# pivots, sit 1mm above the bind sole plane during the held contact poses.
const ENTRY_SLASHER_DRAG_PITCH := 1.0293675
const ENTRY_TANK_PLANT_PITCH := 0.8153234


# Ground samples are root-relative. The owner supplies the aircraft world
# fly-by and transport drop while sharing these durations and part phases.
static func entry_duration(kind: String) -> float:
	match kind:
		"normal": return 2.20
		"tank": return 2.50
		"ranged": return 2.30
		"drone": return 3.20*FLYBY_ENTRY_TIME_SCALE
		"missile_drone": return 3.60*FLYBY_ENTRY_TIME_SCALE
		"shield_drone": return 3.60*FLYBY_ENTRY_TIME_SCALE
		"interceptor": return 2.80*FLYBY_ENTRY_TIME_SCALE
		"mine_layer": return 3.80*FLYBY_ENTRY_TIME_SCALE
		"boss": return 6.00
	return 0.0


static func sample_entry(kind: String, _lane: int, phase: float) -> Dictionary:
	var p: float = clampf(phase,0.0,1.0)
	if p >= 1.0 or entry_duration(kind) <= 0.0:
		return {"offset":Vector3.ZERO,"rotation":Vector3.ZERO}
	var offset: Vector3 = Vector3.ZERO
	var angles: Vector3 = Vector3.ZERO
	match kind:
		"normal":
			var slide: float = smoothstep(0.0,0.34,p)
			var launch: float = smoothstep(0.52,0.82,p)
			var guard: float = smoothstep(0.82,1.0,p)
			offset = Vector3(lerpf(1.6,0.10,slide)*(1.0-launch),0,lerpf(-5.5,-0.8,slide)*(1.0-launch))
			angles.y = lerpf(0.85,-0.65,launch)*(1.0-guard)
		"tank":
			var leap: float = smoothstep(0.02,0.20,p)
			var land: float = smoothstep(0.25,0.38,p)
			var extract: float = smoothstep(0.58,0.84,p)
			offset = Vector3(0.25*(1.0-land),1.60*leap*(1.0-land),-4.6*(1.0-smoothstep(0.0,0.38,p)))
			angles.y = 0.18*(1.0-extract)
		"ranged":
			var brake: float = smoothstep(0.0,0.30,p)
			var lock: float = smoothstep(0.70,1.0,p)
			offset = Vector3(1.8*(1.0-brake),0,lerpf(-5.0,-0.45,brake)*(1.0-lock))
			angles.y = lerpf(0.95,0.32,brake)*(1.0-lock)
		_:
			# The owner supplies the complete behind-camera fly-by and turn,
			# or the transport ship's suspended Boss drop. Never stack a second
			# descent/turn here. Part poses still use the same phase below.
			pass
	if kind in ["normal","tank","ranged"]:
		# Reach the original contact position before the brace/scan holds:
		# the extra distant approach must not slide planted hammers forward.
		var stop: float = 0.38 if kind == "tank" else (0.30 if kind == "ranged" else 0.34)
		offset.z -= GROUND_ENTRY_EXTRA_DEPTH*(1.0-smoothstep(0.0,stop,p))
	return {"offset":offset,"rotation":angles}


static func entry_visibility(kind: String, phase: float) -> float:
	if kind not in ["normal","tank","ranged"]: return 1.0
	return smoothstep(0.0,GROUND_ENTRY_FADE_END_PHASE,clampf(phase,0.0,1.0))


# Deliberate held poses, not a continuous idle sway. All coordinates remain
# offsets of the original rigid parts; the existing leg solver preserves the
# actual hip/knee/ankle connections and never scales occupied material.
static func sample_entry_body(kind: String, lane: int, phase: float, run_phase: float, boss_side: float = 1.0) -> Dictionary:
	var p: float = clampf(phase,0.0,1.0)
	var side: float = -1.0 if posmod(lane,2)==0 else 1.0
	var stride: float = sin(run_phase)
	var run_angles: Vector3 = Vector3(0.035,sin(run_phase*0.5)*0.045,stride*0.018)
	var run_right: Vector3 = Vector3(stride*0.20,0,-0.12)
	var run_left: Vector3 = Vector3(-stride*0.22,0,0.12)
	var angles: Vector3 = run_angles
	var offset: Vector3 = Vector3.ZERO
	var right: Vector3 = run_right
	var left: Vector3 = run_left
	var left_foot: Vector3 = Vector3.ZERO
	var right_foot: Vector3 = Vector3.ZERO
	var feet_blend: float = 0.0
	match kind:
		"normal":
			var rise: float = smoothstep(0.52,0.84,p)
			var ready: float = smoothstep(0.84,1.0,p)
			var drag: float = 1.0-rise
			var draw: float = rise*(1.0-ready)
			angles = Vector3(0,side*0.10,0)*drag+Vector3(0.10,-side*0.75,0)*draw+run_angles*ready
			offset.y = -0.55*drag-0.08*draw
			var draw_arm: Vector3 = Vector3(ENTRY_SLASHER_DRAG_PITCH,-0.12,-0.10).lerp(Vector3(-0.35,0.12,-0.90),rise)
			# Lift/turn the blade clear before lowering the shoulder pitch. A
			# direct angle blend would briefly drive the long tip through deck.
			draw_arm.x = lerpf(ENTRY_SLASHER_DRAG_PITCH,-0.35,smoothstep(0.45,1.0,rise))
			right = draw_arm.lerp(run_right,ready)
			left = Vector3(-0.65,0.10,0.70)*drag+Vector3(-0.35,0,-0.40)*draw+run_left*ready
			left_foot = Vector3(-0.10,0,0.22)*drag+Vector3(0.05,0.08,-0.18)*draw
			right_foot = Vector3(0.04,0.02,-0.38)*drag+Vector3(0.04,0,0.28)*draw
			feet_blend = 1.0-ready
		"tank":
			var land: float = smoothstep(0.25,0.38,p)
			var extract: float = smoothstep(0.58,0.82,p)
			var ready: float = smoothstep(0.82,1.0,p)
			var air: float = 1.0-land
			angles = Vector3(0.06*air,0,0).lerp(run_angles,ready)
			offset.y = (-0.22*air-0.42*land*(1.0-extract)-0.12*extract)*(1.0-ready)
			right = Vector3(1.65,0,-0.25).lerp(Vector3(ENTRY_TANK_PLANT_PITCH,0,-0.06),land).lerp(Vector3(1.15,0,-0.50),extract).lerp(run_right,ready)
			left = Vector3(1.65,0,0.25).lerp(Vector3(ENTRY_TANK_PLANT_PITCH,0,0.06),land).lerp(Vector3(1.15,0,0.50),extract).lerp(run_left,ready)
			left_foot = Vector3(-0.18,0.25*air,0.05)
			right_foot = Vector3(0.18,0.25*air,-0.05)
			feet_blend = 1.0-ready
		"ranged":
			var ready: float = smoothstep(0.70,1.0,p)
			angles = Vector3(0,side*0.30,0).lerp(run_angles,ready)
			offset.y = -0.24*(1.0-ready)
			right = Vector3(0.28,0,-0.12).lerp(run_right,ready)
			left = Vector3(0.22,0,0.15).lerp(run_left,ready)
			left_foot = Vector3(-0.10,0,0.25)
			right_foot = Vector3(0.10,0,-0.25)
			feet_blend = 1.0-ready
		"boss":
			var suspended: float = 1.0-smoothstep(0.56,0.72,p)
			var impact: float = smoothstep(0.72,0.755,p)
			var rise: float = smoothstep(0.88,1.0,p)
			var load: float = impact*(1.0-rise)
			var display: float = smoothstep(0.88,0.94,p)*(1.0-smoothstep(0.96,1.0,p))
			angles = Vector3(0.08,0,0)*suspended+Vector3(0.22,0,0)*load+Vector3(0.16,boss_side*0.28,0)*rise
			offset.y = -0.62*load-0.12*rise
			right = Vector3(0.80,0,-0.65)*suspended+Vector3(0.75,0,-0.30)*load+Vector3(-0.65,0,0.18)*rise+Vector3(0,0,-0.65)*display
			left = Vector3(0.80,0,0.65)*suspended+Vector3(0.75,0,0.30)*load+Vector3(0.18,0,0.22)*rise+Vector3(0,0,0.65)*display
			left_foot = Vector3(-0.15,0.80,-0.45)*suspended+Vector3(-0.18,0,0.14)*load
			right_foot = Vector3(0.15,0.80,-0.45)*suspended+Vector3(0.18,0,0.14)*load
			feet_blend = 1.0
	return {"angles":angles,"offset":offset,"left_arm":left,"right_arm":right,"left_foot":left_foot,"right_foot":right_foot,"feet_blend":feet_blend}


# distance is a travelled-distance phase, not time. One complete cycle spans
# stride metres. Passing ground_distance * STANCE_FRACTION makes the planted
# foot move backwards by exactly ground_distance while its y stays at zero.
# Returned foot positions are offsets from the caller's original ankle points.
static func sample_feet(distance: float, stride: float = 0.72, lift: float = 0.16) -> Dictionary:
	var step_length := absf(stride)
	if step_length <= LENGTH_EPSILON:
		return {
			"left": Vector3.ZERO,
			"right": Vector3.ZERO,
			"body_bob": 0.0,
			"body_roll": 0.0,
			"left_arm": 0.0,
			"right_arm": 0.0,
			"left_stance": true,
			"right_stance": true,
		}
	var phase := fposmod(distance / step_length, 1.0)
	var left := _sample_foot(phase, step_length, maxf(0.0, lift))
	var right := _sample_foot(fposmod(phase + 0.5, 1.0), step_length, maxf(0.0, lift))
	var left_offset: Vector3 = left["offset"]
	var right_offset: Vector3 = right["offset"]
	var left_lift: float = left["lift_weight"]
	var right_lift: float = right["lift_weight"]
	return {
		"left": left_offset,
		"right": right_offset,
		"body_bob": 0.018 * (left_lift + right_lift),
		"body_roll": 0.018 * (right_lift - left_lift),
		# Positive foot z is forward; the same-side arm counters that motion.
		"left_arm": clampf(-left_offset.z / (step_length * 0.5) * 0.18, -0.2, 0.2),
		"right_arm": clampf(-right_offset.z / (step_length * 0.5) * 0.18, -0.2, 0.2),
		"left_stance": left["stance"],
		"right_stance": right["stance"],
	}


static func _sample_foot(phase: float, stride: float, lift: float) -> Dictionary:
	if phase < STANCE_FRACTION:
		return {
			"offset": Vector3(0.0, 0.0, stride * (0.5 - phase / STANCE_FRACTION)),
			"lift_weight": 0.0,
			"stance": true,
		}
	var swing := (phase - STANCE_FRACTION) / SWING_FRACTION
	# The Hermite tangents match the stance velocity at both ends. The small
	# natural overshoot at toe-off/landing lets the foot reverse without a snap.
	var tangent := -stride * SWING_FRACTION / STANCE_FRACTION
	var swing_squared := swing * swing
	var swing_cubed := swing_squared * swing
	var z := (2.0 * swing_cubed - 3.0 * swing_squared + 1.0) * -stride * 0.5
	z += (swing_cubed - 2.0 * swing_squared + swing) * tangent
	z += (-2.0 * swing_cubed + 3.0 * swing_squared) * stride * 0.5
	z += (swing_cubed - swing_squared) * tangent
	# Squared sine keeps lift nonnegative and matches zero vertical velocity
	# at the two contacts; it cannot push a foot beneath its bind floor.
	var lift_weight := pow(sin(PI * swing), 2.0)
	return {
		"offset": Vector3(0.0, lift * lift_weight, z),
		"lift_weight": lift_weight,
		"stance": false,
	}


# All points share the caller's bind/root coordinate space. upper and lower
# map any bind-space point directly to its posed position (including the pivot
# translation); they are not local rotations to concatenate with a bind pose.
# ankle is the reachable target after clamping and should also place the foot.
static func solve_leg(hip: Vector3, knee: Vector3, ankle: Vector3, target_ankle: Vector3, forward: Vector3 = Vector3(0.0, 0.0, 1.0)) -> Dictionary:
	var upper_length := hip.distance_to(knee)
	var lower_length := knee.distance_to(ankle)
	if upper_length <= LENGTH_EPSILON or lower_length <= LENGTH_EPSILON:
		return {
			"upper": Transform3D.IDENTITY,
			"lower": Transform3D.IDENTITY,
			"knee": knee,
			"ankle": ankle,
		}
	var target_delta := target_ankle - hip
	var requested_distance := target_delta.length()
	var direction: Vector3
	if requested_distance > LENGTH_EPSILON:
		direction = target_delta / requested_distance
	else:
		direction = (ankle - hip).normalized()
		if direction.length_squared() < 0.5:
			direction = Vector3.DOWN
	# Stay just inside the reach limits to retain a defined forward knee bend
	# rather than numerically crossing the straight-leg/hyperextension boundary.
	var reach_margin := minf(upper_length, lower_length) * 0.00001
	var minimum_reach := absf(upper_length - lower_length) + reach_margin
	var maximum_reach := upper_length + lower_length - reach_margin
	var reach := clampf(requested_distance, minimum_reach, maximum_reach)
	var solved_ankle := hip + direction * reach
	var bend_direction := forward - direction * forward.dot(direction)
	if bend_direction.length_squared() <= LENGTH_EPSILON * LENGTH_EPSILON:
		bend_direction = knee - hip - direction * (knee - hip).dot(direction)
	if bend_direction.length_squared() <= LENGTH_EPSILON * LENGTH_EPSILON:
		bend_direction = _perpendicular(direction)
	else:
		bend_direction = bend_direction.normalized()
	var along := (upper_length * upper_length - lower_length * lower_length + reach * reach) / (2.0 * reach)
	var height := sqrt(maxf(0.0, upper_length * upper_length - along * along))
	var solved_knee := hip + direction * along + bend_direction * height
	return {
		"upper": _segment_transform(hip, knee, hip, solved_knee),
		"lower": _segment_transform(knee, ankle, solved_knee, solved_ankle),
		"knee": solved_knee,
		"ankle": solved_ankle,
	}


static func _segment_transform(bind_start: Vector3, bind_end: Vector3, posed_start: Vector3, posed_end: Vector3) -> Transform3D:
	var from := (bind_end - bind_start).normalized()
	var to := (posed_end - posed_start).normalized()
	var cross := from.cross(to)
	var cross_length := cross.length()
	var dot := clampf(from.dot(to), -1.0, 1.0)
	var rotation := Basis.IDENTITY
	if cross_length > LENGTH_EPSILON:
		rotation = Basis(cross / cross_length, atan2(cross_length, dot))
	elif dot < 0.0:
		rotation = Basis(_perpendicular(from), PI)
	return Transform3D(rotation, posed_start - rotation * bind_start)


static func _perpendicular(direction: Vector3) -> Vector3:
	var reference := Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT
	return (reference - direction * reference.dot(direction)).normalized()


static func flyer_entry_weights(phase: float) -> Vector2:
	var p: float = clampf(phase,0.0,1.0)
	return Vector2(1.0-smoothstep(0.40,0.52,p),smoothstep(0.48,0.62,p)*(1.0-smoothstep(0.82,1.0,p)))


# The three space-shooter archetypes keep their actual launch hardware posed
# with the cell body. Time is the enemy's world age, so pause, hit-stop and
# long-slash slow motion cannot leave the wings or recoil running separately.
static func sample_space_flyer(kind: String, time: float, lane: int, action: String, phase: float) -> Dictionary:
	var p := clampf(phase,0.0,1.0)
	var charge := smoothstep(0.0,0.90,p) if action == "ranged_charge" else 0.0
	var aim := charge
	var kick := 0.0
	if action == "ranged_fire":
		aim = 1.0-smoothstep(0.62,1.0,p)
		if kind == "interceptor":
			for shot in [0.18,0.38,0.58]:
				kick = maxf(kick,_launch_pulse(p,float(shot),0.13))
		else:
			kick = _launch_pulse(p,0.25,0.32)
	var hover_rate := 4.0 if kind == "interceptor" else (2.2 if kind == "mine_layer" else 2.8)
	var hover_height := 0.065 if kind == "interceptor" else 0.035
	var hover := hover_height*sin(time*hover_rate+float(lane)*0.7)
	var bank := (0.075 if kind == "interceptor" else 0.025)*sin(time*1.9+float(lane)*0.4)*(1.0-aim)
	var angles := Vector3(-0.12*aim-0.08*kick,0.025*sin(time*1.5),bank)
	var offset := Vector3(0,hover,-0.14*kick)
	var entry_weights: Vector2 = flyer_entry_weights(p) if action == "entry" else Vector2.ZERO
	var entry_fold: float = entry_weights.x
	var entry_brake: float = entry_weights.y
	if action == "entry":
		var entry_side: float = -1.0 if posmod(lane,2)==0 else 1.0
		angles += Vector3(0.12*entry_fold-0.18*entry_brake,entry_side*0.16*entry_brake,entry_side*(0.18*entry_fold-0.22*entry_brake))
	elif action == "windup":
		var ready := smoothstep(0.0,0.85,p)
		angles.x = -0.28*ready
		offset += Vector3(0,0.11*ready,-0.19*ready)
	elif action == "strike":
		var dive := smoothstep(0.02,0.52,p)
		var follow := smoothstep(0.56,1.0,p)
		angles.x = lerpf(-0.28,0.36,dive)-0.14*follow
		offset += Vector3(0,lerpf(0.11,-0.23,dive)+0.11*follow,0.13*sin(p*PI))
	elif action == "stagger":
		var release := 1.0-smoothstep(0.0,1.0,p)
		angles.x = -0.22*release
		offset += Vector3(0,-0.06*release,-0.18*sin(p*PI))
	var basis := Basis.from_euler(angles)
	var pivot := Vector3(0,2.18,-0.12)
	var parts: Dictionary = {}
	for part in [1,2]:
		var side := -1.0 if part == 1 else 1.0
		var hinge: Vector3
		var wing_angles: Vector3
		match kind:
			"shield_drone":
				hinge = Vector3(side*0.30,2.24,-0.05)
				# Opening the real leaves exposes the central material root. Keep
				# that opening through the shot and most of recovery; the end of
				# recovery closes continuously into the next idle/charge pose.
				var shield_open := smoothstep(0.12,0.82,p) if action == "ranged_charge" else 0.0
				if action == "ranged_fire": shield_open = 1.0
				elif action == "recover": shield_open = 1.0-smoothstep(0.65,1.0,p)
				wing_angles = Vector3(0,side*(0.025+0.525*shield_open),side*0.018*sin(time*2.2))
				# Arrival keeps the actual shield leaves closed; their idle hinge
				# motion returns only as the craft finishes levelling out.
				if action == "entry":
					wing_angles.x += -0.18*entry_fold+0.20*entry_brake
					wing_angles.z = wing_angles.z*(1.0-entry_fold)+side*(-0.20*entry_fold+0.22*entry_brake)
			"interceptor":
				hinge = Vector3(side*0.28,2.16,-0.13)
				wing_angles = Vector3(-0.06*aim,side*0.04*aim,side*(0.11*aim+0.03*sin(time*3.7)))
				wing_angles += Vector3(-0.30,side*0.12,-side*0.58)*entry_fold+Vector3(0.20,side*0.16,side*0.40)*entry_brake
			_:
				hinge = Vector3(side*0.40,2.16,-0.17)
				wing_angles = Vector3(-0.10*aim,0,side*(0.09*aim+0.012*sin(time*2.0)))
				wing_angles += Vector3(-0.25,0,-side*0.40)*entry_fold+Vector3(0.18,side*0.10,side*0.28)*entry_brake
		var wing_basis := Basis.from_euler(wing_angles)
		parts[part] = Transform3D(wing_basis,hinge-wing_basis*hinge)
	if kind == "mine_layer":
		var hinge := Vector3(0,1.86,0.15)
		var hatch_basis := Basis(Vector3.RIGHT,0.18*aim)
		if action == "entry": hatch_basis = Basis(Vector3.RIGHT,0.24*entry_brake)
		parts[3] = Transform3D(hatch_basis,hinge-hatch_basis*hinge)
	return {"rig":Transform3D(basis,pivot-basis*pivot+offset),"parts":parts,"charge":charge,"kick":kick}


static func _launch_pulse(phase: float, start: float, duration: float) -> float:
	var t := (phase-start)/duration
	return sin(PI*t)*(1.0-t) if t >= 0.0 and t <= 1.0 else 0.0
