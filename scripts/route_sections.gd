class_name RouteSections
extends RefCounted
## Four prebuilt industrial districts. Primary architecture stays outside the
## combat tube; recycling only selects an already-built chapter root.

static var _cold_light: StandardMaterial3D


static func build_assembly(game: Node3D, segment: Node3D, index: int, materials: Dictionary) -> Dictionary:
	var section := Node3D.new()
	section.name = "AssemblyBay"
	section.set_meta("route_chapter",0)
	segment.add_child(section)
	var groups: Dictionary = {}
	_assembly(game,groups,index,materials)
	_finish(game,section,groups)
	return {"root":section,"emitters":[]}


static func build_backdrop(game: Node3D, materials: Dictionary) -> Node3D:
	# These detached industrial districts are static, beyond the shadow range
	# and outside the combat tube. They never take part in road recycling.
	var section := Node3D.new()
	section.name = "IndustrialBackdrop"
	game.add_child(section)
	var groups: Dictionary = {}
	var m := materials
	var ice := _ice(m)
	for side in [-1.0,1.0]:
		var offset := 7.0 if side > 0.0 else 0.0
		# A low plant level makes the open bridge read as an elevated route.
		_piece(game,groups,m.soot,Vector3(22.0,3.0,32.0),Vector3(side*35.0,-10.0,-73.0-offset))
		_piece(game,groups,m.concrete,Vector3(18.0,1.0,28.0),Vector3(side*35.0,-8.0,-73.0-offset))
		for tank in range(3):
			var x: float = side*(28.0+float(tank)*6.0)
			var z := -67.0-float(tank)*6.0-offset
			var height: float = [18.0,25.0,15.0][tank]+(3.0 if side < 0.0 else 0.0)
			_piece(game,groups,m.casing,Vector3(4.7,height,5.1),Vector3(x,-7.0+height*0.5,z))
			_piece(game,groups,m.copper,Vector3(4.9,0.23,5.3),Vector3(x,-7.0+height*0.75,z))
			_piece(game,groups,m.steel,Vector3(5.4,0.85,5.8),Vector3(x,height-6.55,z))
			_piece(game,groups,m.casing,Vector3(3.7,1.20,4.0),Vector3(x,height-5.6,z))
		# Broad stepped equipment towers at a second depth, deliberately unequal
		# on either side. Silhouette and occlusion carry most of the detail.
		var tower_height := 32.0 if side < 0.0 else 39.0
		_piece(game,groups,m.soot,Vector3(21.0,3.0,28.0),Vector3(side*43.0,-10.0,-127.0))
		_piece(game,groups,m.casing,Vector3(10.0,tower_height,12.0),Vector3(side*36.0,-8.0+tower_height*0.5,-123.0-offset))
		_piece(game,groups,m.steel,Vector3(6.7,11.0,8.5),Vector3(side*36.7,tower_height-2.5,-123.8-offset))
		_piece(game,groups,m.casing,Vector3(2.2,8.0,2.6),Vector3(side*36.7,tower_height+7.0,-123.8-offset))
		_piece(game,groups,m.copper,Vector3(10.4,0.45,12.4),Vector3(side*36.0,tower_height-11.0,-123.0-offset))
		_piece(game,groups,m.casing,Vector3(11.0,19.0,11.5),Vector3(side*50.0,1.5,-133.0+offset))
		_piece(game,groups,m.steel,Vector3(7.2,5.0,7.0),Vector3(side*50.0,13.4,-133.0+offset))
		_piece(game,groups,m.copper,Vector3(11.3,0.30,11.8),Vector3(side*50.0,9.3,-133.0+offset))
		_piece(game,groups,ice,Vector3(0.10,0.24,7.2),Vector3(side*30.93,19.0,-123.0-offset))
		# Thin refinery stacks close the skyline at the far plane without a
		# featureless wall. No stack or bridge crosses the vanishing point.
		_piece(game,groups,m.soot,Vector3(23.0,5.0,22.0),Vector3(side*40.0,-8.0,-195.0))
		for stack in range(2):
			var x: float = side*(33.0+float(stack)*11.0)
			var z := -190.0-float(stack)*9.0-offset
			var height := 38.0+float(stack)*9.0+(4.0 if side > 0.0 else 0.0)
			_piece(game,groups,m.casing,Vector3(3.5,height,4.1),Vector3(x,-6.0+height*0.5,z))
			_piece(game,groups,m.steel,Vector3(4.3,1.1,4.9),Vector3(x,height-7.8,z))
			_piece(game,groups,m.copper,Vector3(3.7,0.45,4.3),Vector3(x,height-15.0,z))
		# A side trunk conveyor connects foreground plant and distant towers.
		_piece(game,groups,m.steel,Vector3(2.4,0.65,105.0),Vector3(side*26.8,9.0,-117.5))
		_piece(game,groups,m.casing,Vector3(3.1,0.30,105.0),Vector3(side*26.8,11.4,-117.5))
		for z in [-69.0,-117.5,-166.0]:
			_piece(game,groups,m.casing,Vector3(0.65,19.0,0.75),Vector3(side*27.8,1.5,z))
			_piece(game,groups,m.copper,Vector3(1.5,0.24,1.7),Vector3(side*27.8,11.2,z))
		for z in [-92.0,-140.5]:
			_bar(game,groups,m.steel,Vector3(side*26.8,9.3,z-24.0),Vector3(side*26.8,11.25,z+24.0),0.20)
			_piece(game,groups,ice,Vector3(0.07,0.16,2.0),Vector3(side*25.21,11.31,z))
	_finish(game,section,groups)
	for visual in section.get_children():
		if visual is GeometryInstance3D:
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var stats: Dictionary = section.get_meta("route_geometry").duplicate()
	stats["caster_batches"] = 0
	stats["caster_bounds"] = AABB()
	stats["conservative_shadow_tail"] = 0.0
	stats["static"] = true
	section.remove_meta("route_geometry")
	section.set_meta("backdrop_geometry",stats)
	return section


static func build_variants(game: Node3D, segment: Node3D, index: int, materials: Dictionary) -> Dictionary:
	var roots: Array[Node3D] = []
	var emitters: Array[Dictionary] = []
	for chapter in range(3):
		var section := Node3D.new()
		section.name = ["FurnaceSection","SkybridgeSection","CoreSection"][chapter]
		section.visible = false
		section.set_meta("route_chapter",chapter+1)
		segment.add_child(section)
		roots.append(section)
		var groups: Dictionary = {}
		match chapter:
			0:
				var mouth := _furnace(game,groups,index,materials)
				emitters.append({"segment":segment,"side":mouth.side,"local":mouth.point,"visual_root":section})
			1:
				_bridge(game,groups,index,materials)
			2:
				_core(game,groups,index,materials)
		_finish(game,section,groups)
	return {"roots":roots,"emitters":emitters}


static func _piece(game: Node3D, groups: Dictionary, material: Material, size: Vector3, at: Vector3, angle: Vector3 = Vector3.ZERO) -> void:
	game._forge_piece(groups,material,size,at,angle)


static func _bar(_game: Node3D, groups: Dictionary, material: Material, from: Vector3, to: Vector3, width: float, depth: float = -1.0) -> void:
	var delta := to-from
	var orientation := Basis(Quaternion(Vector3.UP,delta.normalized()))
	# Scale the authored axes before the rotation. The common forge helper
	# scales global rows; that would squash a diagonal long beam into the road.
	var shaped := Basis(orientation.x*width,orientation.y*delta.length(),orientation.z*(width if depth < 0.0 else depth))
	if not groups.has(material):
		groups[material] = []
	groups[material].append(Transform3D(shaped,(from+to)*0.5))


static func _ice(m: Dictionary) -> StandardMaterial3D:
	if _cold_light == null:
		_cold_light = m.work_light.duplicate()
		_cold_light.albedo_color = Color(0.66,0.88,1.0)
		_cold_light.emission = Color(0.66,0.88,1.0)
		_cold_light.set_meta("no_shadow",true)
	return _cold_light


static func _finish(game: Node3D, section: Node3D, groups: Dictionary) -> void:
	var boxes := 0
	var bounds := AABB()
	var caster_bounds := AABB()
	var has_bounds := false
	var has_casters := false
	for material: Material in groups:
		var casts: bool = not material.get_meta("no_shadow",false)
		if material is BaseMaterial3D and material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			casts = false
		for transform: Transform3D in groups[material]:
			boxes += 1
			for x in [-0.5,0.5]:
				for y in [-0.5,0.5]:
					for z in [-0.5,0.5]:
						var corner := transform*Vector3(x,y,z)
						bounds = bounds.expand(corner) if has_bounds else AABB(corner,Vector3.ZERO)
						has_bounds = true
						if casts:
							caster_bounds = caster_bounds.expand(corner) if has_casters else AABB(corner,Vector3.ZERO)
							has_casters = true
	game._forge_batch(section,groups)
	var batches := 0
	var caster_batches := 0
	for child in section.get_children():
		if child is MultiMeshInstance3D:
			batches += 1
			if child.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				caster_batches += 1
	section.set_meta("box_count",boxes)
	section.set_meta("route_geometry",{"boxes":boxes,"batches":batches,"caster_batches":caster_batches,"bounds":bounds,"caster_bounds":caster_bounds,"conservative_shadow_tail":maxf(0.0,caster_bounds.end.y)*0.82-caster_bounds.position.z,"triangles":boxes*12})


static func _railing(game: Node3D, groups: Dictionary, m: Dictionary, side: float, x: float, y: float, z: float, length: float) -> void:
	for level in [0.45,1.02]:
		_piece(game,groups,m.yellow,Vector3(0.075,0.075,length),Vector3(side*x,y+level,z))
	for offset in [-length*0.43,length*0.43]:
		_piece(game,groups,m.steel,Vector3(0.11,1.15,0.11),Vector3(side*x,y+0.5,z+offset))


static func _assembly(game: Node3D, groups: Dictionary, index: int, m: Dictionary) -> void:
	var bay := posmod(index,6)
	var busy_side := -1.0 if posmod(index*7,5) < 2 else 1.0
	for side in [-1.0,1.0]:
		# One machine side faces a quieter loading side. Upper gaps expose
		# distant masses instead of another continuous ten-metre wall.
		_piece(game,groups,m.concrete,Vector3(4.9,0.60,9.2),Vector3(side*9.15,0.15,-4.8))
		_piece(game,groups,m.steel,Vector3(0.62,7.7,0.64),Vector3(side*6.35,3.75,-0.8))
		_piece(game,groups,m.casing,Vector3(0.92,0.72,1.05),Vector3(side*6.35,0.32,-0.8))
		_piece(game,groups,m.casing,Vector3(3.8,0.22,8.7),Vector3(side*8.75,5.00,-4.8))
		_railing(game,groups,m,side,6.87,5.12,-4.8,8.7)
		_piece(game,groups,m.copper,Vector3(0.25,0.25,9.0),Vector3(side*7.00,6.40,-4.8))
		for z in [-2.0,-7.6]:
			_piece(game,groups,m.steel,Vector3(0.26,0.46,0.70),Vector3(side*7.00,6.12,z))
		_piece(game,groups,m.work_light,Vector3(0.09,0.13,1.25),Vector3(side*6.74,4.80,-2.0 if side == busy_side else -7.2))
		_piece(game,groups,m.casing,Vector3(0.24,1.17,0.25),Vector3(side*5.62,0.55,-4.8))
		_piece(game,groups,m.work_light,Vector3(0.055,0.18,0.29),Vector3(side*5.47,1.01,-4.8))
		if side == busy_side:
			# Press columns, lowered ram, cavity and anvil are separate volumes.
			_piece(game,groups,m.soot,Vector3(2.40,4.10,3.9),Vector3(side*8.10,2.50,-5.7))
			for offset in [-1.95,1.95]:
				_piece(game,groups,m.casing,Vector3(1.30,6.60,0.72),Vector3(side*8.00,3.60,-5.7+offset))
			_piece(game,groups,m.steel,Vector3(3.25,1.15,4.65),Vector3(side*8.30,6.60,-5.7))
			_piece(game,groups,m.copper,Vector3(0.64,1.25,1.75),Vector3(side*7.46,5.37,-5.7))
			_piece(game,groups,m.casing,Vector3(2.30,0.70,2.65),Vector3(side*7.60,4.62,-5.7))
			_piece(game,groups,m.yellow,Vector3(0.12,0.18,2.20),Vector3(side*6.38,4.56,-5.7))
			_piece(game,groups,m.steel,Vector3(2.40,0.62,3.05),Vector3(side*7.60,1.02,-5.7))
			_piece(game,groups,m.copper,Vector3(0.24,4.4,0.27),Vector3(side*9.23,3.05,-3.3))
			_piece(game,groups,m.work_light,Vector3(0.055,0.12,1.65),Vector3(side*6.88,4.15,-5.7))
		else:
			# Conveyor rollers and an articulated manipulator replace cabinet rows.
			_piece(game,groups,m.steel,Vector3(2.50,0.45,7.8),Vector3(side*8.65,1.0,-5.2))
			for offset in [-2.7,-0.9,0.9,2.7]:
				_piece(game,groups,m.casing,Vector3(2.40,0.16,0.28),Vector3(side*8.65,1.32,-5.2+offset))
			for offset in [-1.8,1.2]:
				_piece(game,groups,m.casing,Vector3(1.50,1.15,1.40),Vector3(side*8.65,1.94,-5.2+offset))
				_piece(game,groups,m.yellow,Vector3(0.07,0.22,1.12),Vector3(side*7.86,2.16,-5.2+offset))
			_piece(game,groups,m.casing,Vector3(1.25,0.60,1.15),Vector3(side*8.20,0.85,-1.3))
			_bar(game,groups,m.yellow,Vector3(side*8.20,1.0,-1.3),Vector3(side*7.05,3.55,-1.0),0.54,0.64)
			_bar(game,groups,m.casing,Vector3(side*7.05,3.55,-1.0),Vector3(side*6.12,2.62,-2.15),0.37,0.48)
			_piece(game,groups,m.steel,Vector3(0.70,0.80,0.70),Vector3(side*7.05,3.55,-1.0))
			_piece(game,groups,m.copper,Vector3(0.42,0.26,0.80),Vector3(side*6.02,2.54,-2.15))
		if posmod(index+(1 if side > 0 else 3),3) == 0:
			var height := 11.8+float(posmod(index*5,4))*1.7
			_piece(game,groups,m.casing,Vector3(4.8,height,5.6),Vector3(side*14.2,height*0.5,-4.2))
			_piece(game,groups,m.soot,Vector3(0.14,height*0.68,2.6),Vector3(side*11.72,height*0.50,-4.2))
			_piece(game,groups,m.copper,Vector3(0.25,0.25,5.4),Vector3(side*14.2,height+0.20,-4.2))
	if bay in [0,3]:
		# Sparse carrier frames alternate compressed landmarks and open runs.
		_piece(game,groups,m.steel,Vector3(15.2,0.78,1.15),Vector3(0,8.15,-1.15))
		_piece(game,groups,m.casing,Vector3(10.7,0.38,1.75),Vector3(-0.8,8.74,-1.15))
		var carrier_x := 1.15 if bay == 0 else -2.0
		_piece(game,groups,m.copper,Vector3(1.10,1.20,1.30),Vector3(carrier_x,7.20,-1.15))
		_piece(game,groups,m.work_light,Vector3(1.25,0.08,0.70),Vector3(carrier_x,6.55,-1.15))
		for side in [-1.0,1.0]:
			_bar(game,groups,m.casing,Vector3(side*6.35,5.8,-1.15),Vector3(side*4.65,7.88,-1.15),0.35,0.85)


static func _furnace(game: Node3D, groups: Dictionary, index: int, m: Dictionary) -> Dictionary:
	var hot_side := -1.0 if posmod(index*5+1,4) < 2 else 1.0
	var bay := posmod(index,5)
	var mouth_z := -3.5 if bay in [0,3] else -6.1
	for side in [-1.0,1.0]:
		_piece(game,groups,m.concrete,Vector3(4.4,0.65,9.15),Vector3(side*8.9,0.20,-4.8))
		_piece(game,groups,m.steel,Vector3(0.60,8.4,0.70),Vector3(side*6.82,4.1,-0.9))
		_piece(game,groups,m.casing,Vector3(3.40,0.30,9.0),Vector3(side*8.48,5.50,-4.8))
		_railing(game,groups,m,side,6.86,5.65,-4.8,8.7)
		_piece(game,groups,m.copper,Vector3(0.42,5.1,0.46),Vector3(side*7.38,2.95,-1.5))
		_piece(game,groups,m.copper,Vector3(0.42,0.42,7.5),Vector3(side*7.38,5.65,-5.0))
		_piece(game,groups,m.work_light,Vector3(0.09,0.17,0.90),Vector3(side*6.58,5.16,-7.5))
		if side == hot_side:
			# A deep refractory throat sits behind independent grates and jambs.
			_piece(game,groups,m.casing,Vector3(3.05,5.1,4.8),Vector3(side*8.24,3.04,mouth_z))
			_piece(game,groups,m.soot,Vector3(0.12,3.6,3.90),Vector3(side*6.66,3.17,mouth_z))
			_piece(game,groups,m.furnace,Vector3(0.08,2.75,3.10),Vector3(side*6.54,3.16,mouth_z))
			for end in [-1.89,1.89]:
				_piece(game,groups,m.concrete,Vector3(0.68,3.25,0.65),Vector3(side*6.28,2.75,mouth_z+end))
				_piece(game,groups,m.steel,Vector3(0.20,2.05,0.33),Vector3(side*5.82,2.65,mouth_z+end))
			_piece(game,groups,m.concrete,Vector3(0.76,0.80,4.4),Vector3(side*6.24,4.68,mouth_z))
			_piece(game,groups,m.steel,Vector3(0.25,0.25,3.85),Vector3(side*5.75,4.14,mouth_z))
			_piece(game,groups,m.copper,Vector3(0.23,0.34,3.6),Vector3(side*5.78,1.54,mouth_z))
			for grate in [-1.10,0.0,1.10]:
				_piece(game,groups,m.steel,Vector3(0.18,2.75,0.14),Vector3(side*6.31,3.18,mouth_z+grate))
			_bar(game,groups,m.casing,Vector3(side*7.8,6.35,mouth_z),Vector3(side*9.15,9.10,mouth_z),1.6,2.9)
			_piece(game,groups,m.steel,Vector3(1.65,4.7,2.0),Vector3(side*9.40,11.2,mouth_z))
			_piece(game,groups,m.copper,Vector3(2.05,0.38,2.50),Vector3(side*9.4,12.20,mouth_z))
		else:
			for offset in [-2.3,1.9]:
				_piece(game,groups,m.soot,Vector3(2.65,4.0,2.7),Vector3(side*8.5,2.6,-4.7+offset))
				_piece(game,groups,m.casing,Vector3(0.25,3.8,2.30),Vector3(side*7.04,2.8,-4.7+offset))
				for vent in [1.75,2.65,3.55]:
					_piece(game,groups,m.steel,Vector3(0.15,0.17,1.93),Vector3(side*6.84,vent,-4.7+offset))
				_piece(game,groups,m.copper,Vector3(0.48,4.6,0.48),Vector3(side*8.28,3.0,-3.05+offset))
			if bay in [1,4]:
				_piece(game,groups,m.casing,Vector3(4.0,13.8,4.4),Vector3(side*14.2,6.9,-4.7))
				_piece(game,groups,m.copper,Vector3(1.55,2.25,1.80),Vector3(side*14.2,14.3,-4.7))
	if bay in [0,2]:
		_piece(game,groups,m.steel,Vector3(14.5,0.75,1.10),Vector3(0,8.8,-7.9))
		_piece(game,groups,m.casing,Vector3(2.25,0.85,1.7),Vector3(-1.4,7.75,-7.9))
		_piece(game,groups,m.work_light,Vector3(1.8,0.075,1.25),Vector3(-1.4,7.24,-7.9))
	return {"side":hot_side,"point":Vector3(hot_side*6.21,3.24,mouth_z)}


static func _bridge(game: Node3D, groups: Dictionary, index: int, m: Dictionary) -> void:
	var phase := posmod(index,6)
	var ice := _ice(m)
	for side in [-1.0,1.0]:
		# Open sky is a rest in density; large A portals occur every sixty m.
		_piece(game,groups,m.steel,Vector3(0.24,0.30,9.4),Vector3(side*5.92,0.20,-4.8))
		_piece(game,groups,m.casing,Vector3(0.12,0.12,9.4),Vector3(side*5.87,1.28,-4.8))
		for z in [-0.8,-5.0,-9.0]:
			_piece(game,groups,m.casing,Vector3(0.18,1.14,0.20),Vector3(side*5.87,0.75,z))
			_piece(game,groups,ice,Vector3(0.055,0.12,0.18),Vector3(side*5.75,1.17,z))
		_piece(game,groups,m.concrete,Vector3(1.0,2.8,1.6),Vector3(side*6.72,-0.95,-4.9))
		_bar(game,groups,m.steel,Vector3(side*6.72,-0.95,-4.9),Vector3(side*9.50,-3.0,-4.9),0.58,0.75)
		if phase == 0:
			_piece(game,groups,m.concrete,Vector3(1.7,1.45,2.15),Vector3(side*7.0,0.70,-4.8))
			_bar(game,groups,m.casing,Vector3(side*7.0,1.05,-4.8),Vector3(side*4.85,15.8,-4.8),0.86,1.05)
			_bar(game,groups,m.steel,Vector3(side*4.85,15.8,-4.8),Vector3(side*1.90,18.20,-4.8),0.68,0.90)
			for end_z in [-0.4,-9.3]:
				_bar(game,groups,m.steel,Vector3(side*6.20,1.3,end_z),Vector3(side*5.7,10.0,-4.8),0.13)
			_piece(game,groups,ice,Vector3(0.14,1.25,0.09),Vector3(side*5.62,10.5,-4.22))
		elif phase == 3:
			_piece(game,groups,m.steel,Vector3(0.42,8.1,0.60),Vector3(side*7.1,4.05,-4.8))
			_bar(game,groups,m.steel,Vector3(side*7.1,7.6,-4.8),Vector3(side*5.96,1.30,-0.6),0.13)
			_bar(game,groups,m.steel,Vector3(side*7.1,7.6,-4.8),Vector3(side*5.96,1.30,-9.0),0.13)
		if posmod(index+(1 if side > 0 else 4),4) == 0:
			# Detached cargo aprons create actual parallax beyond the open edge.
			_piece(game,groups,m.concrete,Vector3(5.4,0.55,7.2),Vector3(side*13.6,-0.75,-5.1))
			_piece(game,groups,m.casing,Vector3(3.9,4.7,5.2),Vector3(side*14.2,1.85,-5.1))
			_piece(game,groups,m.copper,Vector3(4.0,0.20,5.3),Vector3(side*14.2,4.34,-5.1))
			_piece(game,groups,m.soot,Vector3(1.6,2.4,3.0),Vector3(side*14.6,5.60,-5.1))
			_piece(game,groups,ice,Vector3(0.08,0.12,2.70),Vector3(side*12.16,2.80,-5.1))
	if phase == 0:
		_piece(game,groups,m.casing,Vector3(4.4,0.65,1.15),Vector3(0,18.45,-4.8))
		_piece(game,groups,m.steel,Vector3(12.5,0.44,0.75),Vector3(0,10.2,-4.8))
		_piece(game,groups,ice,Vector3(2.15,0.085,0.38),Vector3(0,9.90,-4.8))


static func _core(game: Node3D, groups: Dictionary, index: int, m: Dictionary) -> void:
	var phase := posmod(index,4)
	var ice := _ice(m)
	for side in [-1.0,1.0]:
		# Faceted vault feet, layered outer armour and deep service slots.
		_piece(game,groups,m.concrete,Vector3(2.30,0.80,9.4),Vector3(side*7.40,0.24,-4.8))
		_piece(game,groups,m.soot,Vector3(0.32,6.4,8.45),Vector3(side*8.30,3.5,-4.8))
		for z in [-2.50,-6.70]:
			_piece(game,groups,m.casing,Vector3(0.85,4.55,2.65),Vector3(side*7.68,2.82,z))
			_piece(game,groups,m.steel,Vector3(0.27,0.90,2.12),Vector3(side*7.10,1.35,z))
			_piece(game,groups,m.copper,Vector3(0.24,3.25,0.22),Vector3(side*7.10,3.3,z-0.95))
			_piece(game,groups,ice,Vector3(0.075,2.40,0.12),Vector3(side*7.13,3.30,z+0.82))
		_piece(game,groups,m.steel,Vector3(0.40,0.35,9.4),Vector3(side*6.37,1.50,-4.8))
		_piece(game,groups,m.copper,Vector3(0.20,0.20,9.3),Vector3(side*6.25,4.85,-4.8))
		_piece(game,groups,m.casing,Vector3(1.25,1.05,1.30),Vector3(side*6.20,0.6,-0.9))
		_piece(game,groups,m.steel,Vector3(0.90,4.1,0.80),Vector3(side*6.20,3.0,-0.9))
		_bar(game,groups,m.casing,Vector3(side*6.20,4.90,-0.9),Vector3(side*3.85,7.30,-0.9),0.90,1.05)
		_piece(game,groups,ice,Vector3(0.12,1.0,0.14),Vector3(side*5.72,3.8,-0.41))
		if phase in [0,2]:
			_bar(game,groups,m.steel,Vector3(side*6.20,4.90,-8.9),Vector3(side*3.85,7.30,-8.9),0.62,0.72)
			_piece(game,groups,m.steel,Vector3(0.60,5.0,0.70),Vector3(side*6.20,2.6,-8.9))
		if phase == 1:
			_piece(game,groups,m.casing,Vector3(3.0,10.5,5.3),Vector3(side*12.1,4.8,-4.8))
			_piece(game,groups,m.copper,Vector3(3.35,0.40,1.05),Vector3(side*12.1,8.2,-4.8))
	_piece(game,groups,m.casing,Vector3(8.4,0.80,1.15),Vector3(0,7.65,-0.9))
	_piece(game,groups,m.steel,Vector3(2.60,0.62,9.3),Vector3(0,8.35,-4.8))
	_piece(game,groups,m.copper,Vector3(0.18,0.24,9.2),Vector3(-1.22,7.97,-4.8))
	_piece(game,groups,m.copper,Vector3(0.18,0.24,9.2),Vector3(1.22,7.97,-4.8))
	if phase == 0:
		# Suspended power cradle remains above the Boss silhouette.
		_piece(game,groups,m.casing,Vector3(3.35,1.10,3.30),Vector3(0,7.50,-5.8))
		_piece(game,groups,m.soot,Vector3(2.72,0.24,2.60),Vector3(0,6.80,-5.8))
		_piece(game,groups,ice,Vector3(1.85,0.07,1.70),Vector3(0,6.63,-5.8))
		for x in [-1.15,1.15]:
			_piece(game,groups,m.copper,Vector3(0.18,0.58,2.5),Vector3(x,6.84,-5.8))
	else:
		_piece(game,groups,ice,Vector3(1.10,0.055,1.25),Vector3(0,7.18,-4.9))
