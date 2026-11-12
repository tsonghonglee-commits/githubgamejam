class_name SeriesEntryMotion
extends RefCounted
const Models = preload("res://scripts/series_archetypes.gd")
const GROUNDED := ["ink_swordsman","ink_spear","ink_talisman","cyber_breacher","cyber_riot","cyber_sniper","sea_skimmer","sea_crab","empire_walker","empire_lancer","empire_sentinel"]
const BOSSES := ["ink_master","cyber_captain","cyber_flanker","cyber_suppressor","cyber_spotter","cyber_helicopter","cyber_tank","cyber_gunship","sea_leviathan","empire_dreadnought"]
const ORDINARY_FLYERS := ["ink_crane","cyber_drone","sea_eel","sea_ray","empire_fighter"]
const INK_MASTER_LANDING_PHASE := 0.56
const INK_MASTER_DRAW_PHASES := [0.67, 0.77]
const INK_MASTER_DRAW_WINDOW := 0.066
const DURATIONS := {
	"ink_swordsman":2.7,"ink_spear":2.9,"ink_talisman":3.0,"ink_crane":2.7,"ink_master":5.2,
	"cyber_breacher":2.55,"cyber_riot":2.85,"cyber_sniper":3.05,"cyber_drone":2.4,
	"cyber_captain":4.6,"cyber_flanker":4.6,"cyber_suppressor":4.6,"cyber_spotter":4.6,
	"cyber_helicopter":5.1,"cyber_tank":4.5,"cyber_gunship":5.4,
	"sea_skimmer":2.65,"sea_crab":3.15,"sea_eel":2.8,"sea_ray":3.35,"sea_leviathan":6.2,
	"empire_walker":3.1,"empire_lancer":2.65,"empire_sentinel":3.0,"empire_fighter":2.45,"empire_dreadnought":7.1,
}


static func sample(kind: String, phase: float, lane: int = 0) -> Dictionary:
	var side := -1.0 if lane%2 == 0 else 1.0
	if kind in BOSSES or not DURATIONS.has(kind):
		var authored := {"offset":Vector3.ZERO,"rotation":Vector3.ZERO,"rig":Transform3D.IDENTITY,"parts":{},"opacity":1.0,"impact_phase":-1.0,"entry_climax_phase":-1.0}
		if kind in BOSSES:
			_guardian(authored,kind,clampf(phase,0.0,1.0),side)
		return authored
	var p := clampf(phase/0.985,0.0,1.0)
	if kind in GROUNDED:
		var impact := 0.36
		match kind:
			"sea_skimmer": impact = 0.42
			"sea_crab": impact = 0.48
			"empire_walker", "empire_lancer", "empire_sentinel": impact = 0.38
		var ground := {"offset":Vector3.ZERO,"rotation":Vector3.ZERO,"rig":Transform3D.IDENTITY,"parts":{},"opacity":1.0,"impact_phase":impact}
		if p < 1.0: _approach(ground,kind,p,side)
		return ground
	var pose: Dictionary = Models.sample_entry(kind,p,lane)
	if p < 1.0: _flight(pose,kind,p,side)
	return pose


static func _beat(p: float, begin: float, peak: float, end: float) -> float:
	return smoothstep(begin,peak,p)*(1.0-smoothstep(peak,end,p))


static func _hinge(pivot: Vector3, angles: Vector3, offset: Vector3 = Vector3.ZERO) -> Transform3D:
	return Models._pivot(pivot,angles,offset)


# Waypoints store (phase, lateral, height, depth) relative to the final lane.
const FLIGHT_ROUTES := {
	"ink_crane":[Vector4(0,2.6,5.4,-36),Vector4(0.24,1.9,4.8,-23),Vector4(0.52,-0.95,-0.55,2.8),Vector4(0.70,-0.65,1.45,2.8),Vector4(0.96,0,0,0)],
	"cyber_drone":[Vector4(0,-2.0,0.45,-27),Vector4(0.31,-1.7,1.05,-9),Vector4(0.53,1.9,2.30,3.1),Vector4(0.70,0.9,0.70,3.1),Vector4(0.82,-0.28,0.25,0.2),Vector4(0.96,0,0,0)],
	"sea_eel":[Vector4(0,2.1,-1.55,-32),Vector4(0.23,0.7,-1.75,-19),Vector4(0.47,-1.7,2.10,-5),Vector4(0.65,-0.2,0.9,4.0),Vector4(0.83,0.55,-0.60,2.1),Vector4(0.97,0,0,0)],
	"sea_ray":[Vector4(0,-2.3,5.35,-40),Vector4(0.38,-0.35,-1.10,-8),Vector4(0.52,1.35,-0.60,0.5),Vector4(0.71,1.15,2.85,3.1),Vector4(0.98,0,0,0)],
	"empire_fighter":[Vector4(0,3.25,5.35,-45),Vector4(0.20,2.60,4.65,-30),Vector4(0.51,-1.7,0.3,4.35),Vector4(0.63,-1.4,0.75,4.35),Vector4(0.79,0.4,1.25,0.0),Vector4(0.98,0,0,0)],
}

static func _entry_route(p: float, side: float, route: Array) -> Vector3:
	for index in range(1,route.size()):
		var to: Vector4 = route[index]
		if p > to.x: continue
		var from: Vector4 = route[index-1]
		var key := from.lerp(to,smoothstep(from.x,to.x,p))
		return Vector3(side*key.y,key.z,key.w)
	return Vector3.ZERO


static func _flight(pose: Dictionary, kind: String, p: float, side: float) -> void:
	pose.impact_phase = -1.0
	pose.offset = _entry_route(p,side,FLIGHT_ROUTES[kind])
	pose.opacity = smoothstep(0.0,0.14,p)
	match kind:
		"ink_crane":
			var fold := _beat(p,0.24,0.46,0.59)
			var lift := _beat(p,0.48,0.61,0.78)
			var brake := _beat(p,0.64,0.77,0.95)
			pose.rotation = Vector3(0.52*fold-0.63*lift,side*(0.55*fold-0.36*brake),side*(-0.68*fold+0.26*brake))
			for wing in [1,2]:
				var sign := -1.0 if wing == 1 else 1.0
				var downstroke := _beat(p,0.50+wing*0.018,0.63+wing*0.018,0.84)
				pose.parts[wing] = _hinge(Vector3(sign*0.36,1.65,-0.12),Vector3(0,sign*0.54*fold,sign*(0.94*fold-1.05*downstroke+0.24*brake)))
		"cyber_drone":
			var cut_across := _beat(p,0.29,0.48,0.57)
			var reverse := _beat(p,0.50,0.65,0.80)
			var level := _beat(p,0.70,0.80,0.97)
			pose.rotation = Vector3(-0.44*cut_across+0.58*reverse,side*(0.95*cut_across-0.86*reverse),side*(0.72*cut_across-0.46*reverse+0.21*level))
			for pod in [1,2]:
				var sign := -1.0 if pod == 1 else 1.0
				var thrust := _beat(p,0.40+pod*0.065,0.52+pod*0.065,0.73+pod*0.06)
				pose.parts[pod] = _hinge(Vector3(sign*0.48,1.42,0),Vector3(0.46*cut_across-0.82*thrust,sign*0.36*reverse,sign*0.60*thrust))
		"sea_eel":
			var rise := _beat(p,0.22,0.39,0.53)
			var redirect := _beat(p,0.45,0.60,0.73)
			var tail_follow := _beat(p,0.52,0.68,0.88)
			var settle := _beat(p,0.67,0.81,0.97)
			pose.rotation = Vector3(-0.85*rise+0.63*redirect,side*(-0.96*rise+0.88*redirect-0.37*settle),side*(0.40*rise-0.44*redirect))
			pose.parts[9] = _hinge(Vector3(0.62,1.62,-0.04),Vector3(0.36*rise-0.43*tail_follow,side*(0.57*rise-1.28*tail_follow+0.54*settle),side*0.22*tail_follow))
		"sea_ray":
			var dive := _beat(p,0.04,0.25,0.48)
			var pull := _beat(p,0.39,0.60,0.77)
			var level := _beat(p,0.62,0.77,0.98)
			pose.rotation = Vector3(0.66*dive-0.74*pull+0.27*level,side*(0.41*dive-0.68*pull),side*(0.86*pull-0.32*level))
			for wing in [1,2]:
				var sign := -1.0 if wing == 1 else 1.0
				var stroke := _beat(p,0.43+wing*0.045,0.54+wing*0.045,0.80+wing*0.06)
				pose.parts[wing] = _hinge(Vector3(sign*0.30,1.22,0.20),Vector3(0,sign*0.56*dive,sign*(0.96*dive-1.09*stroke+0.32*level)))
		"empire_fighter":
			var roll := _beat(p,0.18,0.43,0.60)
			var brake := _beat(p,0.47,0.57,0.72)
			var counter_roll := _beat(p,0.56,0.70,0.86)
			pose.rotation = Vector3(0.58*roll-0.73*brake,side*(0.62*roll-0.62*counter_roll),side*(-1.38*roll+0.81*counter_roll))
			for wing in [1,2]:
				var sign := -1.0 if wing == 1 else 1.0
				var unfold := _beat(p,0.48+wing*0.035,0.63+wing*0.035,0.86)
				pose.parts[wing] = _hinge(Vector3(sign*0.28,1.4,-0.4),Vector3(0,sign*(0.73*roll-0.33*unfold),sign*(0.69*roll-0.58*unfold)))

static func _ground_entry_steps(pose: Dictionary, side: float, angles: Vector2, lifts: Vector2, spread: float, scale: float = 1.0) -> void:
	for part in [3,4]:
		var sign := -1.0 if part == 3 else 1.0
		var leading := sign == side
		var pitch := angles.x if leading else angles.y
		var height := lifts.x if leading else lifts.y
		var hip := Vector3(sign*0.23,1.10,0)*scale
		var ankle := Vector3(sign*0.36,0.20,0.04-sign*0.07)*scale
		var leg := _hinge(hip,Vector3(pitch,0,sign*spread),Vector3(0,height,0))
		pose.parts[part] = leg
		pose.parts[part+2] = leg*_hinge(ankle,Vector3(-pitch*0.78,0,-sign*spread))


static func _approach(pose: Dictionary, kind: String, p: float, side: float) -> void:
	var plant := float(pose.impact_phase)
	var u := clampf(p/plant,0.0,1.0)
	var advance := smoothstep(0.0,1.0,u)
	var remaining := 1.0-advance
	var load := _beat(p,plant*0.66,plant+0.04,plant+0.28)
	var present := _beat(p,plant+0.075,plant+0.24,0.97)
	var stride := sin(u*TAU*2.0)*sin(u*PI)
	pose.offset = Vector3(0,0,-34.0*remaining)
	pose.opacity = smoothstep(0.0,0.18,p)
	match kind:
		"ink_swordsman":
			var cross := _beat(u,0.16,0.68,1.0)
			pose.offset.x = side*(3.0*remaining-2.2*cross)
			pose.offset.z = -38.0*(1.0-smoothstep(0.12,0.99,u))
			pose.rotation = Vector3(0.44*remaining+0.52*load,-side*(0.63*remaining-0.71*cross+0.27*present),side*(0.26*cross-0.19*load))
			pose.rig.origin.y = -0.48*load-0.17*remaining
			pose.parts[1] = _hinge(Vector3(-0.48,2.0,0),Vector3(-0.53*load,-0.38*present,-0.28*cross))
			pose.parts[2] = _hinge(Vector3(0.48,2.0,0),Vector3(0.45*remaining+0.58*load-1.22*present,0.95*remaining-0.56*present,0.27*present))
			_ground_entry_steps(pose,side,Vector2(-0.73*load+0.43*stride,0.68*load-0.43*stride),Vector2.ZERO,0.18*load)
		"ink_spear":
			var cross := _beat(u,0.14,0.63,1.0)
			pose.offset = Vector3(side*(3.1*remaining+0.63*cross),0.85*cross,-38.0*(1.0-smoothstep(0.01,1.0,u)))
			pose.rotation = Vector3(0.21*cross+0.44*load,side*(0.89*remaining-0.31*present),-side*0.23*cross)
			pose.rig.origin.y = -0.33*load
			pose.parts[1] = _hinge(Vector3(-0.48,2.0,0),Vector3(-0.45*load,-0.36*remaining,0))
			pose.parts[2] = _hinge(Vector3(0.48,2.0,0),Vector3(-0.24*remaining+0.62*load-0.68*present,1.10*remaining-0.41*present,0.19*remaining))
			_ground_entry_steps(pose,side,Vector2(-0.62*load-0.27*cross,0.48*load+0.44*cross),Vector2.ZERO,0.14*load)
		"ink_talisman":
			var seal := _beat(p,plant*0.55,plant+0.08,plant+0.27)
			var open := _beat(p,plant+0.14,plant+0.32,0.98)
			pose.offset.x = side*(2.7*remaining-1.8*_beat(u,0.08,0.72,1.0))
			pose.offset.z = -35.0*(1.0-smoothstep(0.0,0.94,u))
			pose.rotation = Vector3(0.24*seal-0.25*open,-side*(1.03*remaining+0.36*open),side*0.23*remaining)
			pose.rig.origin.y = -0.30*seal+0.18*open
			for arm in [1,2]:
				var sign := -1.0 if arm == 1 else 1.0
				pose.parts[arm] = _hinge(Vector3(sign*0.48,2.0,0),Vector3(-0.61*seal-1.03*open,sign*(-0.95*seal+1.03*open),sign*(0.38*remaining+0.24*open)))
			_ground_entry_steps(pose,side,Vector2(-0.52*seal+0.38*stride,0.38*seal-0.38*stride),Vector2.ZERO,0.09*seal)
		"cyber_breacher":
			var sprint := _beat(u,0.06,0.73,1.0)
			pose.offset.x = side*(3.2*remaining-1.36*sprint)
			pose.offset.z = -40.0*(1.0-smoothstep(0.07,0.97,u))
			pose.rotation = Vector3(0.56*sprint+0.33*load,-side*(0.67*remaining+0.44*load),side*0.34*sprint)
			pose.rig.origin.y = -0.42*load-0.27*sprint
			pose.parts[1] = _hinge(Vector3(-0.52,2.0,0),Vector3(-0.78*sprint,0.28*load,-0.31*load))
			pose.parts[2] = _hinge(Vector3(0.48,2.0,0),Vector3(0.45*sprint-1.03*present,0.64*remaining-0.31*present,0.10*load))
			_ground_entry_steps(pose,side,Vector2(-0.68*load+0.63*stride,0.70*load-0.63*stride),Vector2(0.15*maxf(stride,0.0),0.15*maxf(-stride,0.0)),0.24*load)
		"cyber_riot":
			var turn := _beat(p,plant*0.53,plant+0.06,plant+0.29)
			pose.offset.x = side*4.1*remaining
			pose.offset.z = -35.0*(1.0-smoothstep(0.0,0.91,u))
			pose.rotation = Vector3(0.30*load,side*(1.05*remaining-0.48*turn),-side*0.23*turn)
			pose.rig.origin.y = -0.38*load
			pose.parts[1] = _hinge(Vector3(-0.48,2.0,0),Vector3(-0.28*turn,1.18*remaining-0.89*turn,0.28*remaining-0.27*turn))
			pose.parts[2] = _hinge(Vector3(0.48,2.0,0),Vector3(-0.44*present,0.38*turn,0.11*turn))
			_ground_entry_steps(pose,side,Vector2(-0.76*load+0.31*stride,0.34*load-0.31*stride),Vector2.ZERO,0.28*load)
		"cyber_sniper":
			var scope := _beat(p,plant+0.04,plant+0.28,0.98)
			var sweep := _beat(p,plant*0.67,plant+0.03,plant+0.24)
			pose.offset.x = side*(4.2*remaining-0.9*_beat(u,0.13,0.78,1.0))
			pose.offset.z = -34.0*(1.0-smoothstep(0.13,0.93,u))
			pose.rotation = Vector3(0.21*load,side*(1.04*remaining-0.46*sweep+0.32*scope),side*0.19*sweep)
			pose.rig.origin.y = -0.52*load-0.17*scope
			pose.parts[1] = _hinge(Vector3(-0.48,2.0,0),Vector3(-0.47*scope,-0.28*sweep,0))
			pose.parts[2] = _hinge(Vector3(0.48,2.0,0),Vector3(-0.82*sweep-0.14*scope,side*(1.08*remaining-0.62*sweep),0.20*sweep))
			_ground_entry_steps(pose,side,Vector2(-0.67*load+0.29*stride,0.83*load-0.29*stride),Vector2.ZERO,0.22*load)
		"sea_skimmer":
			var launch := _beat(u,0.19,0.66,1.0)
			var low := 1.0-smoothstep(0.16,0.42,u)
			pose.offset = Vector3(side*(3.8*remaining-2.2*launch),2.45*launch,-37.0*(1.0-smoothstep(0.07,0.96,u)))
			pose.rotation = Vector3(0.23*low-0.63*launch+0.33*load,side*(0.63*remaining-0.56*launch),side*(0.55*launch-0.36*load))
			pose.rig.origin.y = -0.24*low-0.25*load
			for part in [1,2]:
				var sign := -1.0 if part == 1 else 1.0
				pose.parts[part] = _hinge(Vector3(sign*0.30,1.09,0.10),Vector3(-0.26*launch,sign*(-0.74*low+0.89*present),sign*0.41*launch))
		"sea_crab":
			pose.offset.x = side*4.5*remaining
			pose.offset.z = -35.0*(1.0-smoothstep(0.02,0.96,u))
			pose.rotation = Vector3(0.18*load,side*(0.98*remaining-0.28*present),side*0.32*load)
			pose.rig.origin.y = -0.46*load
			for index in range(6):
				var order := index if side < 0.0 else 5-index
				var reach := _beat(p,0.09+order*0.039,0.25+order*0.040,plant+0.04+order*0.036)
				pose.parts[3+index] = Transform3D(Basis.IDENTITY,Vector3(side*0.27*reach,0.49*reach,0.43*reach))
			for arm in [1,2]:
				var sign := -1.0 if arm == 1 else 1.0
				var open := _beat(p,plant+0.09+(arm-1)*0.10,plant+0.23+(arm-1)*0.10,0.97)
				pose.parts[arm] = _hinge(Vector3(sign*0.68,1.15,0.42),Vector3(-0.55*open+0.17*load,sign*(-0.62*load+0.94*open),0))
		"empire_walker":
			var fall := 1.0-smoothstep(0.20,1.0,u)
			pose.offset = Vector3(side*1.70*remaining,3.7*fall,-35.0*remaining)
			pose.rotation = Vector3(-0.18*fall+0.31*load,side*0.38*remaining,side*0.17*load)
			pose.rig.origin.y = -0.55*load
			for leg in range(4):
				var sign := -1.0 if leg%2 == 0 else 1.0
				var rear := leg < 2
				var contact := _beat(p,plant-(0.13 if rear else 0.23),plant+(0.08 if rear else 0.0),plant+0.29)
				pose.parts[3+leg] = _hinge(Vector3(sign*0.66,1.91,-0.57 if rear else 0.57),Vector3((0.34 if rear else -0.46)*contact,0,-sign*(0.42*fall+0.22*contact)))
			for arm in [1,2]:
				var sign := -1.0 if arm == 1 else 1.0
				pose.parts[arm] = _hinge(Vector3(sign*0.90,2.56,0.6),Vector3(-0.63*fall+0.26*present,sign*0.33*present,0))
		"empire_lancer":
			var drive := _beat(u,0.10,0.70,1.0)
			pose.offset = Vector3(side*(3.1*remaining-1.35*drive),1.05*drive,-42.0*(1.0-smoothstep(0.21,0.97,u)))
			pose.rotation = Vector3(0.51*drive+0.36*load,-side*(0.91*remaining-0.50*drive),side*0.28*drive)
			pose.rig.origin.y = -0.34*load
			pose.parts[2] = _hinge(Vector3(0.48,2.0,0),Vector3(-0.47*remaining+0.34*load-0.36*present,1.08*remaining-0.45*present,0.21*load),Vector3(0,0,0.12*present))
			pose.parts[9] = _hinge(Vector3(-0.58,2.18,-0.28),Vector3(0.82*drive,0,side*0.23*drive))
			_ground_entry_steps(pose,side,Vector2(-0.79*load+0.28*drive,0.77*load+0.72*drive),Vector2.ZERO,0.13*load)
		"empire_sentinel":
			var kneel := _beat(p,plant*0.84,plant+0.10,plant+0.37)
			var emerge := _beat(p,plant+0.19,plant+0.37,0.98)
			pose.offset.x = side*1.35*remaining
			pose.offset.z = -35.0*(1.0-smoothstep(0.04,1.0,u))
			pose.rotation = Vector3(0.29*kneel,side*(0.37*remaining-0.56*kneel+0.22*emerge),side*0.17*kneel)
			pose.rig.origin.y = -0.57*kneel
			pose.parts[1] = _hinge(Vector3(-0.71,1.63,0.45),Vector3(-0.39*kneel,0.96*remaining-0.92*kneel,-0.15*kneel))
			pose.parts[2] = _hinge(Vector3(0.48,2.0,0),Vector3(-0.57*emerge,0.91*kneel-0.83*emerge,0.20*emerge))
			_ground_entry_steps(pose,side,Vector2(-0.79*kneel+0.28*stride,0.90*kneel-0.28*stride),Vector2.ZERO,0.26*kneel)


const BOSS_FLIGHT_ROUTES := {
	"cyber_tank":[Vector4(0,2.65,0,-47),Vector4(0.31,1.65,0,-28),Vector4(0.55,-1.30,0,3.3),Vector4(0.69,-1.15,0,2.75),Vector4(0.98,0,0,0)],
	"cyber_gunship":[Vector4(0,4.1,4.6,-66),Vector4(0.26,3.20,3.3,-38),Vector4(0.56,-2.35,0.95,3.1),Vector4(0.67,-2.35,1.8,4.3),Vector4(0.79,0.8,0.5,3.0),Vector4(0.98,0,0,0)],
	"sea_leviathan":[Vector4(0,2.40,0,-47),Vector4(0.26,2.0,0,-34),Vector4(0.47,-1.35,4.9,-7.2),Vector4(0.66,-0.7,0,3.8),Vector4(0.78,-0.3,0,3.2),Vector4(0.98,0,0,0)],
	"empire_dreadnought":[Vector4(0,2.55,8.4,-96),Vector4(0.23,2.4,6.85,-71),Vector4(0.48,-1.35,4.9,-18),Vector4(0.68,-1.8,2.4,5.3),Vector4(0.83,0.6,1.2,5.3),Vector4(0.98,0,0,0)],
}

static func _guardian(pose: Dictionary, kind: String, p: float, side: float) -> void:
	pose.opacity = smoothstep(0.0,0.08,p)
	match kind:
		"ink_master":
			_ink_master_entry(pose,p,side)
		"cyber_captain", "cyber_flanker", "cyber_suppressor", "cyber_spotter":
			_tactical_entry(pose,kind,p,side)
		"cyber_helicopter":
			# One continuous approach with a shallow overshoot and return.
			# The later lateral drift settles independently of forward speed.
			var advance := smoothstep(0.0,0.68,p)
			var ease_back := smoothstep(0.50,0.98,p)
			var lateral := lerpf(-2.35,1.6,smoothstep(0.12,0.66,p))*(1.0-smoothstep(0.64,0.98,p))
			var altitude := 3.65*(1.0-smoothstep(0.07,0.75,p))+0.28*_beat(p,0.64,0.77,0.98)
			pose.offset = Vector3(side*lateral,altitude,(-61.0+65.0*advance)-4.0*ease_back)
			var crab := _beat(p,0.04,0.39,0.59)
			var brake := _beat(p,0.46,0.64,0.86)
			var tail := _beat(p,0.64,0.78,0.97)
			pose.rotation = Vector3(0.20*crab-0.29*brake+0.11*tail,side*(0.79*crab-0.41*brake+0.15*tail),side*(0.29*crab-0.33*brake+0.12*tail))
			for arm in [1,2]:
				var sign := -1.0 if arm == 1 else 1.0
				pose.parts[arm] = _hinge(Vector3(sign*1.24,1.62,0.68),Vector3(-0.62*brake+0.18*tail,sign*0.31*crab,sign*0.39*brake))
			pose.entry_climax_phase = 0.64
		"cyber_tank":
			pose.offset = _entry_route(p,side,BOSS_FLIGHT_ROUTES[kind])
			var approach := 1.0-smoothstep(0.19,0.53,p)
			var yaw_stop := _beat(p,0.42,0.56,0.70)
			var compress := _beat(p,0.48,0.60,0.72)
			var recoil := _beat(p,0.62,0.73,0.89)
			pose.rotation = Vector3(0.43*compress-0.16*recoil,side*(0.83*approach-0.35*yaw_stop),side*(0.15*approach+0.20*compress-0.13*recoil))
			pose.rig.origin.y = -0.42*compress+0.12*recoil
			pose.parts[1] = _hinge(Vector3(0,1.35,0.35),Vector3(-0.28*recoil,side*(-0.68*approach+0.47*yaw_stop),0))
			for tread in [3,4]:
				var sign := -1.0 if tread == 3 else 1.0
				var load := _beat(p,0.47+tread*0.018,0.51+tread*0.025,0.80)
				pose.parts[tread] = _hinge(Vector3(sign*2.87,0.98,0),Vector3(-0.34*load,0,0),Vector3(0,0.18*load,0.08*load))
			pose.impact_phase = 0.55
		"cyber_gunship":
			pose.offset = _entry_route(p,side,BOSS_FLIGHT_ROUTES[kind])
			var bank := _beat(p,0.11,0.38,0.57)
			var counter := _beat(p,0.44,0.64,0.80)
			var hull_settle := _beat(p,0.60,0.77,0.97)
			pose.rotation = Vector3(0.44*bank-0.62*counter+0.20*hull_settle,side*(-0.81*bank+0.54*counter),side*(-0.72*bank+0.47*hull_settle))
			for pod in [1,2]:
				var sign := -1.0 if pod == 1 else 1.0
				var thrust := _beat(p,0.38+pod*0.072,0.47+pod*0.084,0.83+pod*0.045)
				pose.parts[pod] = _hinge(Vector3(sign*2.18,2.20,0),Vector3(-0.98*thrust+0.27*bank,sign*0.50*counter,sign*(0.54*thrust-0.32*bank)))
			pose.entry_climax_phase = 0.64
		"sea_leviathan":
			pose.offset = _entry_route(p,side,BOSS_FLIGHT_ROUTES[kind])
			var crouch := _beat(p,0.01,0.22,0.38)
			var crest := _beat(p,0.25,0.44,0.59)
			var front_plant := _beat(p,0.52,0.65,0.75)
			var rear_load := _beat(p,0.61,0.72,0.85)
			var head_lift := _beat(p,0.72,0.85,0.98)
			pose.rotation = Vector3(0.19*crouch-0.46*crest+0.34*front_plant-0.21*head_lift,side*(-0.40*crest+0.20*rear_load),side*0.18*(crest-front_plant))
			pose.rig.origin.y = -0.42*crouch-0.46*front_plant-0.29*rear_load
			for leg in range(4):
				var sign := -1.0 if leg%2 == 0 else 1.0
				var front := leg >= 2
				var contact := front_plant if front else rear_load
				var stride := (-0.95 if front else 0.71)*crest+(0.78 if front else -0.55)*contact
				pose.parts[3+leg] = _hinge(Vector3(sign*2.05,2.53,-1.65 if leg<2 else 1.65),Vector3(stride,0,sign*(0.32*crest-0.22*contact)))
			for arm in [1,2]:
				var sign := -1.0 if arm == 1 else 1.0
				pose.parts[arm] = _hinge(Vector3(sign*1.0,3.1,-0.25),Vector3(-0.64*crest+0.52*front_plant-0.81*head_lift,sign*(0.48*head_lift-0.27*crest),sign*0.31*front_plant))
			pose.parts[9] = _hinge(Vector3(0,3.1,-0.30),Vector3(0.45*crest+0.40*front_plant-0.90*head_lift,0,0))
			pose.opacity = smoothstep(0.03,0.15,p)
			pose.impact_phase = 0.66
		"empire_dreadnought":
			pose.offset = _entry_route(p,side,BOSS_FLIGHT_ROUTES[kind])
			var broadside := 1.0-smoothstep(0.29,0.67,p)
			var reverse := _beat(p,0.49,0.68,0.84)
			var heavy_settle := _beat(p,0.64,0.83,0.98)
			pose.rotation = Vector3(-0.18*broadside+0.27*reverse-0.11*heavy_settle,side*(1.02*broadside-0.36*reverse),side*(-0.17*broadside+0.16*heavy_settle))
			for pod in [1,2]:
				var sign := -1.0 if pod == 1 else 1.0
				var thrust := _beat(p,0.42+pod*0.07,0.54+pod*0.08,0.87+pod*0.035)
				pose.parts[pod] = _hinge(Vector3(sign*4.1,2.6,1.0),Vector3(-0.67*thrust+0.19*broadside,sign*0.28*thrust,sign*(0.20*broadside-0.37*thrust)))
			pose.entry_climax_phase = 0.75


static func _ink_master_entry(pose: Dictionary, p: float, side: float) -> void:
	pose.impact_phase = INK_MASTER_LANDING_PHASE
	if p >= 0.985: return
	# Build the silhouette on the distant road, then cover the distance in one
	# leap. The advancing descent continues right into the planted landing.
	var windup := _beat(p,0.0,0.125,0.235)
	var leap := clampf((p-0.125)/(INK_MASTER_LANDING_PHASE-0.125),0.0,1.0)
	var cross := smoothstep(0.175,0.475,p)
	var approach := smoothstep(0.0,1.0,leap)
	var height := 4.75*4.0*leap*(1.0-leap)
	var step_out := smoothstep(0.835,0.985,p)
	var x := lerpf(2.45,-1.10,cross)
	pose.offset = Vector3(side*x*(1.0-step_out),height,lerpf(-48.0,4.15,approach)*(1.0-step_out))
	# Stay in a three-quarter guard for the two sword beats, with the body
	# carrying the first draw and counter-turning under the second.
	var crouch := _beat(p,0.52,0.585,0.69)
	var guard := smoothstep(0.45,0.575,p)*(1.0-step_out)
	var lead := _beat(p,0.67,0.736,0.785)
	var trail := _beat(p,0.77,0.836,0.90)
	pose.rotation = Vector3(
		0.28*windup-0.30*_beat(p,0.24,0.39,0.465)+0.27*crouch-0.10*lead+0.13*trail,
		side*(0.69*windup-0.62*_beat(p,0.23,0.39,0.54)-0.57*guard+0.37*lead-0.34*trail),
		side*(-0.14*windup+0.30*_beat(p,0.22,0.39,0.55)-0.12*crouch+0.12*lead-0.15*trail))
	pose.rig.origin.y = -0.31*windup-0.62*crouch
	var tuck := _beat(p,0.145,0.33,0.51)
	var reach := _beat(p,0.39,0.548,0.62)
	for arm in [1,2]:
		var sign := -1.0 if arm == 1 else 1.0
		var leading := sign == side
		var draw_start: float = INK_MASTER_DRAW_PHASES[0 if leading else 1]
		var draw_end := draw_start+INK_MASTER_DRAW_WINDOW
		var draw := smoothstep(draw_start,draw_end,p)*(1.0-smoothstep(0.85 if leading else 0.9,0.985,p))
		# Blade tips cross in projection at different heights before either opens.
		var load := smoothstep(0.455,0.575,p)*(1.0-smoothstep(draw_start,draw_end,p))
		var pitch := (-0.48 if leading else 0.32)*load+(-1.22 if leading else 0.13)*draw
		pitch += (-0.37 if leading else 0.18)*windup+(-0.48 if leading else 0.34)*tuck
		var yaw := sign*(-0.89*load+(0.74 if leading else 1.30)*draw+0.35*windup+0.42*tuck)
		pose.parts[arm] = _hinge(Vector3(sign*0.48,2.0,0)*1.45,Vector3(pitch,yaw,sign*(0.12*windup+0.20*draw)))
		# Separate the planted boots and let each rearward step lift in turn.
		var rear_step := _beat(p,0.835,0.875,0.918) if leading else _beat(p,0.908,0.945,0.984)
		var stride := (-0.38 if leading else 0.34)*guard
		stride += (-0.67 if leading else 0.79)*tuck+(-0.55 if leading else 0.18)*reach
		stride += (-0.28 if leading else 0.32)*windup+(-0.30 if leading else 0.32)*crouch
		stride += 0.58*rear_step
		var hip := Vector3(sign*0.23,1.10,0)*1.45
		var ankle := Vector3(sign*0.36,0.20,0.04-sign*0.07)*1.45
		var leg := _hinge(hip,Vector3(stride,0,sign*0.16*guard),Vector3(0,0.24*rear_step,0))
		pose.parts[arm+2] = leg
		pose.parts[arm+4] = leg*_hinge(ankle,Vector3(-stride*0.78,0,-sign*0.16*guard))


static func _tactical_entry(pose: Dictionary, kind: String, p: float, side: float) -> void:
	const SCALE := 1.18
	var left := Vector3(-0.48,2.0,0)*SCALE
	var right := Vector3(0.48,2.0,0)*SCALE
	# Arrival order remains flanker, spotter, suppressor, captain. Distinct
	# height and deceleration keep the silhouettes legible in one formation.
	match kind:
		"cyber_flanker":
			pose.impact_phase = 0.42
			var approach := 1.0-smoothstep(0.075,0.42,p)
			var sideslip := _beat(p,0.13,0.33,0.43)
			var brake := _beat(p,0.33,0.435,0.66)
			var open_left := _beat(p,0.44,0.56,0.84)
			var open_right := _beat(p,0.50,0.66,0.94)
			pose.offset = Vector3(-side*(1.55*approach+0.7*sideslip),0.45*sideslip,-39.0*approach)
			pose.rotation = Vector3(0.40*sideslip+0.45*brake,side*(0.86*approach-0.49*brake),side*(-0.22*sideslip+0.26*brake))
			pose.rig.origin.y = -0.56*brake-0.18*sideslip
			pose.parts[1] = _hinge(left,Vector3(-0.44*brake-0.78*open_left,0.86*sideslip-1.15*open_left,-0.24*open_left))
			pose.parts[2] = _hinge(right,Vector3(0.41*sideslip-0.48*open_right,-0.62*sideslip+1.15*open_right,0.19*open_right))
			_ground_entry_steps(pose,side,Vector2(-0.87*brake-0.34*sideslip,0.86*brake+0.52*sideslip),Vector2.ZERO,0.19*brake,SCALE)
		"cyber_spotter":
			pose.impact_phase = 0.49
			var approach := 1.0-smoothstep(0.015,0.34,p)
			var fall := 1.0-smoothstep(0.26,0.49,p)
			var seat := _beat(p,0.43,0.53,0.70)
			var scan := _beat(p,0.51,0.64,0.84)
			var mark := _beat(p,0.66,0.82,0.97)
			pose.offset = Vector3(-side*1.34*approach,6.8*fall,-20.0*approach)
			pose.rotation = Vector3(-0.24*fall+0.40*seat,side*(0.89*fall-0.62*scan+0.29*mark),-side*(0.26*fall+0.18*seat))
			pose.rig.origin.y = -0.48*seat-0.17*scan
			pose.parts[1] = _hinge(left,Vector3(-0.48*seat-0.85*mark,-0.31*scan,0.17*seat))
			pose.parts[2] = _hinge(right,Vector3(-0.66*fall+0.26*scan-0.81*mark,side*(0.54*fall-0.95*scan+0.39*mark),0.19*mark))
			_ground_entry_steps(pose,side,Vector2(-0.68*seat-0.35*fall,0.53*seat+0.78*fall),Vector2.ZERO,0.18*seat,SCALE)
		"cyber_suppressor":
			pose.impact_phase = 0.56
			var approach := 1.0-smoothstep(0.04,0.44,p)
			var fall := 1.0-smoothstep(0.37,0.56,p)
			var load := _beat(p,0.51,0.585,0.74)
			var lift := _beat(p,0.62,0.76,0.92)
			var settle := _beat(p,0.75,0.82,0.97)
			pose.offset = Vector3(-side*0.58*approach,4.5*fall,-32.0*approach)
			pose.rotation = Vector3(-0.16*fall+0.49*load-0.31*lift+0.27*settle,-side*0.26*approach,side*0.18*load)
			pose.rig.origin.y = -0.65*load-0.27*settle
			pose.parts[1] = _hinge(left,Vector3(-0.49*load-0.84*lift,0.38*load-0.35*lift,-0.26*lift))
			pose.parts[2] = _hinge(right,Vector3(-0.63*fall+0.32*load-0.96*lift+0.39*settle,0.62*fall-0.46*lift,0.23*lift))
			_ground_entry_steps(pose,side,Vector2(-0.55*load-0.38*settle,0.73*load+0.35*settle),Vector2.ZERO,0.33*load,SCALE)
		"cyber_captain":
			pose.impact_phase = 0.64
			var approach := 1.0-smoothstep(0.11,0.64,p)
			var fall := 1.0-smoothstep(0.33,0.64,p)
			var finish_turn := _beat(p,0.52,0.67,0.81)
			var survey := _beat(p,0.64,0.75,0.87)
			var signal_up := _beat(p,0.72,0.82,0.95)
			var signal_down := _beat(p,0.82,0.90,0.98)
			pose.offset = Vector3(-side*1.2*approach,5.6*fall,-27.0*approach)
			pose.rotation = Vector3(-0.23*fall+0.27*finish_turn-0.16*signal_up,side*(0.74*approach-0.52*finish_turn+0.53*survey),-side*0.19*fall)
			pose.rig.origin.y = -0.43*finish_turn+0.16*signal_up
			pose.parts[1] = _hinge(left,Vector3(-0.63*fall-1.89*signal_up+0.45*signal_down,-0.42*signal_up,-0.48*signal_up))
			pose.parts[2] = _hinge(right,Vector3(-0.42*survey-0.61*signal_down,0.53*fall-0.44*signal_down,0.18*fall))
			_ground_entry_steps(pose,side,Vector2(-0.62*finish_turn-0.31*fall,0.56*finish_turn+0.48*fall),Vector2.ZERO,0.16*finish_turn,SCALE)
