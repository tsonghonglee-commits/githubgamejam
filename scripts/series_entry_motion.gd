class_name SeriesEntryMotion
extends RefCounted
const Models = preload("res://scripts/series_archetypes.gd")
const GROUNDED := ["ink_swordsman","ink_spear","ink_talisman","cyber_breacher","cyber_riot","cyber_sniper","sea_skimmer","sea_crab","empire_walker","empire_lancer","empire_sentinel"]
const BOSSES := ["ink_master","cyber_captain","cyber_flanker","cyber_suppressor","cyber_spotter","cyber_helicopter","cyber_tank","cyber_gunship","sea_leviathan","empire_dreadnought"]
const ORDINARY_FLYERS := ["ink_crane","cyber_drone","sea_eel","sea_ray","empire_fighter"]
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
	var pose: Dictionary = Models.sample_entry(kind,p,lane)
	if p >= 1.0: return pose
	if kind in ORDINARY_FLYERS:
		_flight(pose,kind,p,side)
	else:
		_approach(pose,kind,p,side)
	return pose


static func _beat(p: float, begin: float, peak: float, end: float) -> float:
	return smoothstep(begin,peak,p)*(1.0-smoothstep(peak,end,p))


static func _hinge(pivot: Vector3, angles: Vector3, offset: Vector3 = Vector3.ZERO) -> Transform3D:
	return Models._pivot(pivot,angles,offset)


static func _flight(pose: Dictionary, kind: String, p: float, side: float) -> void:
	pose.impact_phase = -1.0
	var approach := 1.0-smoothstep(0.0,0.85,p)
	var bank := _beat(p,0.15,0.40,0.84)
	match kind:
		"ink_crane":
			var flutter := sin(p*TAU*3.0)*_beat(p,0.08,0.46,0.90)
			pose.offset = Vector3(side*2.6*approach,5.6*approach+flutter*0.48,-32.0*approach)
			pose.rotation = Vector3(0.19*bank,-side*0.46*approach,-side*0.49*bank)
			for wing in [1,2]:
				var sign := -1.0 if wing == 1 else 1.0
				pose.parts[wing] = _hinge(Vector3(sign*0.36,1.65,-0.12),Vector3(0,0,sign*(0.65*flutter+0.36*approach)))
		"cyber_drone":
			var brake := _beat(p,0.36,0.54,0.77)
			pose.offset = Vector3(side*2.45*approach,3.5*approach,-19.0*(1.0-smoothstep(0.04,0.56,p)))
			pose.rotation = Vector3(-0.18*approach+0.34*brake,-side*0.40*approach,side*0.25*brake)
			for pod in [1,2]:
				var sign := -1.0 if pod == 1 else 1.0
				pose.parts[pod] = _hinge(Vector3(sign*0.48,1.42,0),Vector3(-0.30*brake,0,sign*0.35*approach))
		"sea_eel":
			var pulse := sin(p*TAU*2.0)*_beat(p,0.0,0.40,0.93)
			pose.offset = Vector3(side*(1.8*approach+pulse),-1.15*approach+1.8*bank,-28.0*approach)
			pose.rotation = Vector3(0.38*approach,-side*(0.44*approach+0.42*pulse),0.32*pulse)
			pose.parts[9] = _hinge(Vector3(0.62,1.62,-0.04),Vector3(0.22*bank,side*(-0.84*pulse+0.40*approach),0))
		"sea_ray":
			var stroke := _beat(p,0.10,0.33,0.55)-0.65*_beat(p,0.52,0.66,0.92)
			pose.offset = Vector3(-side*1.45*approach,3.2*bank-0.55*approach,-37.0*approach)
			pose.rotation = Vector3(0.27*stroke,side*0.32*approach,side*0.52*bank)
			for wing in [1,2]:
				var sign := -1.0 if wing == 1 else 1.0
				pose.parts[wing] = _hinge(Vector3(sign*0.30,1.22,0.20),Vector3(0,0,sign*(0.68*stroke+0.28*approach)))
		"empire_fighter":
			var roll := _beat(p,0.16,0.39,0.88)
			pose.offset = Vector3(side*2.8*approach,4.8*approach+1.1*roll,-42.0*(1.0-smoothstep(0.0,0.52,p))-4.5*roll)
			pose.rotation = Vector3(0.24*roll,-side*0.47*approach,-side*0.88*roll)
			for wing in [1,2]:
				var sign := -1.0 if wing == 1 else 1.0
				pose.parts[wing] = _hinge(Vector3(sign*0.28,1.4,-0.4),Vector3(0,sign*0.24*approach,sign*0.68*approach))


static func _approach(pose: Dictionary, kind: String, p: float, side: float) -> void:
	var plant := float(pose.impact_phase)
	var u := clampf(p/plant,0.0,1.0)
	var advance := smoothstep(0.0,1.0,u)
	var bracing := _beat(p,plant*0.65,plant+0.06,0.73)
	pose.offset.z = -34.0*(1.0-advance)
	pose.opacity = smoothstep(0.0,0.18,p)
	match kind:
		"ink_swordsman", "cyber_breacher", "cyber_sniper", "empire_lancer":
			# A leading foot takes the slide, while the trailing leg trails the hips.
			var stride := 0.38 if kind == "cyber_sniper" else 0.54
			for leg in [3,4]:
				var sign := -1.0 if leg == 3 else 1.0
				var foot := Vector3(sign*0.27,1.15,0)
				var step := _hinge(foot,Vector3(sign*side*stride*bracing,0,0))
				pose.parts[leg] = step
				pose.parts[leg+2] = step
		"ink_talisman":
			pose.rig.origin.y += 0.40*_beat(p,0.05,0.24,plant)
			pose.parts[1] = _hinge(Vector3(-0.48,2,0),Vector3(-0.95*_beat(p,0.20,0.43,0.79),-0.35*bracing,0))
			pose.parts[2] = _hinge(Vector3(0.48,2,0),Vector3(-0.78*_beat(p,0.38,0.62,0.90),0.28*bracing,0))
		"sea_skimmer":
			pose.offset.y = 2.1*_beat(p,0.0,0.21,plant)
			pose.rotation = Vector3(-0.29*_beat(p,0.04,0.19,plant),-side*0.36*(1.0-advance),side*0.23*bracing)
		"sea_crab":
			pose.offset = Vector3(side*1.3*(1.0-advance),0.75*_beat(p,0.02,0.22,plant),pose.offset.z)
			pose.rotation = Vector3(0,-side*0.52*(1.0-advance),side*0.19*bracing)
			for leg in range(6):
				var reach := _beat(p,0.05+leg*0.038,0.23+leg*0.046,0.49+leg*0.04)
				pose.parts[3+leg] = Transform3D(Basis.IDENTITY,Vector3(side*0.17*reach,0.37*reach,0.49*reach))
		"empire_walker":
			pose.offset.y = 3.5*(1.0-smoothstep(0.06,plant,p))
			for leg in range(4):
				var sign := -1.0 if leg%2 == 0 else 1.0
				var extend := _beat(p,0.04+leg*0.025,0.20+leg*0.032,0.64+leg*0.024)
				pose.parts[3+leg] = _hinge(Vector3(sign*0.66,1.91,-0.57 if leg<2 else 0.57),Vector3(0.19*extend,0,-sign*0.36*extend))
			pose.rig.origin.y -= 0.20*bracing


static func _guardian(pose: Dictionary, kind: String, p: float, side: float) -> void:
	pose.opacity = smoothstep(0.0,0.08,p)
	match kind:
		"ink_master":
			var leap := _beat(p,0.06,0.32,0.60)
			var approach := 1.0-smoothstep(0.08,0.60,p)
			var brace := _beat(p,0.51,0.62,0.78)
			var draw := _beat(p,0.62,0.77,0.98)
			var turn := _beat(p,0.13,0.39,0.62)
			pose.offset = Vector3(side*(1.75*approach-1.25*turn),4.3*leap,-43.0*approach)
			pose.rotation = Vector3(-0.21*leap+0.37*brace,-side*(0.36*approach+0.58*turn-0.22*draw),side*0.13*turn)
			pose.rig.origin.y = -0.30*brace
			for arm in [1,2]:
				var sign := -1.0 if arm == 1 else 1.0
				var flourish := draw if arm == 2 else _beat(p,0.66,0.81,0.99)
				pose.parts[arm] = _hinge(Vector3(sign*0.48,2,0)*1.45,Vector3(-0.80*leap-0.68*flourish,sign*(0.88*leap-0.37*brace+0.92*flourish),sign*0.18*leap))
				var leg := _hinge(Vector3(sign*0.23,1.1,0)*1.45,Vector3((0.55 if arm == 1 else -0.66)*leap+(0.37 if arm == 1 else -0.27)*brace,0,sign*0.11*brace))
				pose.parts[arm+2] = leg
				pose.parts[arm+4] = leg
			pose.impact_phase = 0.60
		"cyber_captain", "cyber_flanker", "cyber_suppressor", "cyber_spotter":
			_tactical_entry(pose,kind,p,side)
		"cyber_helicopter":
			var approach := 1.0-smoothstep(0.02,0.66,p)
			var bank := _beat(p,0.08,0.30,0.61)
			var brake := _beat(p,0.42,0.64,0.89)
			pose.offset = Vector3(side*(1.1*approach+1.15*bank),3.5*approach+0.90*brake,-61.0*approach)
			pose.rotation = Vector3(0.27*approach-0.30*brake,-side*(0.27*approach+0.43*bank),side*(0.31*bank-0.17*brake))
			for arm in [1,2]:
				var sign := -1.0 if arm == 1 else 1.0
				pose.parts[arm] = _hinge(Vector3(sign*1.24,1.62,0.68),Vector3(0.29*bank-0.16*brake,sign*0.20*brake,0))
			pose.entry_climax_phase = 0.64
		"cyber_tank":
			var approach := 1.0-smoothstep(0.0,0.55,p)
			var steer := _beat(p,0.08,0.29,0.53)
			var brake := _beat(p,0.41,0.55,0.81)
			pose.offset = Vector3(side*1.22*approach,0.0,-47.0*approach)
			pose.rotation = Vector3(0.23*brake,-side*(0.25*approach+0.34*steer),side*0.09*steer)
			pose.rig.origin.y = -0.21*brake
			for tread in [3,4]:
				var sign := -1.0 if tread == 3 else 1.0
				pose.parts[tread] = _hinge(Vector3(sign*2.87,0.98,0),Vector3(-0.20*brake,0,0),Vector3(0,0.10*brake,0))
			pose.impact_phase = 0.55
		"cyber_gunship":
			var approach := 1.0-smoothstep(0.02,0.69,p)
			var vectoring := _beat(p,0.14,0.40,0.71)
			var brake := _beat(p,0.46,0.67,0.92)
			pose.offset = Vector3(side*1.25*vectoring,4.0*approach+1.2*brake,-69.0*approach)
			pose.rotation = Vector3(0.30*approach-0.25*brake,-side*0.40*vectoring,side*(0.22*vectoring-0.15*brake))
			for pod in [1,2]:
				var sign := -1.0 if pod == 1 else 1.0
				var swivel := _beat(p,0.34+float(pod)*0.035,0.62+float(pod)*0.035,0.88+float(pod)*0.035)
				pose.parts[pod] = _hinge(Vector3(sign*2.18,2.20,0),Vector3(-0.47*swivel,0,sign*0.19*vectoring))
			pose.entry_climax_phase = 0.67
		"sea_leviathan":
			var crest := _beat(p,0.04,0.35,0.66)
			var approach := 1.0-smoothstep(0.05,0.66,p)
			var drop := _beat(p,0.55,0.67,0.88)
			var roar := _beat(p,0.68,0.79,0.98)
			pose.offset = Vector3(side*2.65*approach,4.3*crest,-54.0*approach)
			pose.rotation = Vector3(-0.45*crest+0.22*drop-0.10*roar,-side*0.40*approach,side*0.16*crest)
			pose.rig.origin.y = -0.44*drop
			for leg in range(4):
				var sign := -1.0 if leg%2 == 0 else 1.0
				var tuck := _beat(p,0.10+leg*0.016,0.35+leg*0.018,0.58+leg*0.018)
				pose.parts[3+leg] = _hinge(Vector3(sign*2.05,2.53,-1.65 if leg<2 else 1.65),Vector3(-0.49*tuck+0.19*drop,0,sign*(0.26*tuck-0.10*drop)))
			for arm in [1,2]:
				var sign := -1.0 if arm == 1 else 1.0
				pose.parts[arm] = _hinge(Vector3(sign*1.0,3.1,-0.25),Vector3(-0.47*crest+0.25*drop-0.32*roar,sign*0.22*roar,sign*0.14*crest))
			pose.parts[9] = _hinge(Vector3(0,3.1,-0.30),Vector3(0.26*crest-0.26*drop-0.20*roar,0,0))
			pose.opacity = smoothstep(0.03,0.15,p)
			pose.impact_phase = 0.66
		"empire_dreadnought":
			var glide := 1.0-smoothstep(0.04,0.86,p)
			var turn := _beat(p,0.12,0.40,0.84)
			var brake := _beat(p,0.57,0.80,0.98)
			var settle := 1.0-smoothstep(0.20,0.99,p)
			pose.offset = Vector3(side*(1.2*glide-1.1*turn),8.4*settle+0.85*brake,-104.0*glide)
			pose.rotation = Vector3(-0.20*glide+0.15*brake,side*(0.26*glide+0.55*turn),-side*(0.09*turn-0.06*brake))
			for pod in [1,2]:
				var sign := -1.0 if pod == 1 else 1.0
				var thrust := _beat(p,0.39+float(pod)*0.055,0.61+float(pod)*0.055,0.88+float(pod)*0.055)
				pose.parts[pod] = _hinge(Vector3(sign*4.1,2.6,1.0),Vector3(-0.30*thrust,0,sign*0.07*turn))
			pose.entry_climax_phase = 0.80


static func _tactical_entry(pose: Dictionary, kind: String, p: float, side: float) -> void:
	# The flanker takes the low route, then the spotter and gunner arrive.
	# The captain lands last and signals once all four have their sightlines.
	var plant: float = {"cyber_flanker":0.42,"cyber_spotter":0.49,"cyber_suppressor":0.56,"cyber_captain":0.64}[kind]
	var drop_height: float = {"cyber_flanker":1.0,"cyber_spotter":6.6,"cyber_suppressor":3.1,"cyber_captain":5.6}[kind]
	var distance: float = {"cyber_flanker":39.0,"cyber_spotter":21.0,"cyber_suppressor":32.0,"cyber_captain":27.0}[kind]
	var approach := 1.0-smoothstep(0.04,plant,p)
	var fall := 1.0-smoothstep(plant*0.32,plant,p)
	var brace := _beat(p,plant*0.76,plant+0.035,plant+0.23)
	var set_weapon := _beat(p,plant,plant+0.14,0.99)
	var turn := _beat(p,plant*0.15,plant*0.63,plant+0.08)
	pose.offset = Vector3(-side*(0.62*approach+0.50*turn),drop_height*fall,-distance*approach)
	pose.rotation = Vector3(0.29*brace,-side*(0.42*approach+0.42*turn),side*(0.20*turn-0.10*brace))
	pose.rig.origin.y = -(0.34 if kind == "cyber_flanker" else 0.24)*brace
	pose.impact_phase = plant
	for arm in [1,2]:
		var sign := -1.0 if arm == 1 else 1.0
		var angles := Vector3(-0.32*fall+0.25*brace,-sign*0.32*fall,sign*0.10*turn)
		match kind:
			"cyber_flanker": angles += Vector3(-0.24*set_weapon,sign*(0.77*turn-0.42*set_weapon),sign*0.16*brace)
			"cyber_spotter": angles += Vector3(-0.28*set_weapon,-0.52*set_weapon if arm == 2 else 0.18*set_weapon,0.0)
			"cyber_suppressor": angles += Vector3(-0.32*set_weapon,sign*0.13*set_weapon,sign*0.21*brace)
			"cyber_captain": angles += Vector3((-1.30 if arm == 1 else -0.29)*set_weapon,sign*0.22*set_weapon,sign*0.11*set_weapon)
		pose.parts[arm] = _hinge(Vector3(sign*0.48,2.0,0)*1.18,angles)
		var stride := (0.61 if kind == "cyber_flanker" else 0.34)*turn
		var leg := _hinge(Vector3(sign*0.23,1.1,0)*1.18,Vector3(sign*stride-sign*0.31*brace,0,sign*0.11*brace))
		pose.parts[arm+2] = leg
		pose.parts[arm+4] = leg
