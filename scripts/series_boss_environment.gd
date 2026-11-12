extends Node3D
## Prebuilt machinery attached to an actual stretch of the moving road.

const EntryMotion = preload("res://scripts/series_entry_motion.gd")
const SeriesScenery = preload("res://scripts/series_scenery.gd")
const OPEN_SECONDS := {2:0.92,3:0.80,4:1.04,5:1.18}
# Plane on each authored route and the beat on which its center crosses.
const ROUTES := {
	"ink_master": Vector4(-34.0,1.895,0.40,0.55),
	"cyber_delivery": Vector4(-32.0,1.005,0.24,0.38),
	"cyber_helicopter": Vector4(-32.0,2.429,0.50,0.76),
	"cyber_tank": Vector4(-32.0,1.897,0.46,0.70),
	"cyber_gunship": Vector4(-32.0,2.471,0.50,0.77),
	"sea_leviathan": Vector4(-31.0,2.478,0.43,0.66),
	"empire_dreadnought": Vector4(-46.0,3.408,0.52,0.79),
}
const CYBER_STAGES := ["cyber_delivery","cyber_helicopter","cyber_tank","cyber_gunship"]
const SLING_MEMBERS := ["cyber_captain","cyber_flanker","cyber_suppressor","cyber_spotter"]

var _game: Node3D
var _architecture_material: ShaderMaterial
var _architecture_shadows := false
var _cube: BoxMesh
var _arenas: Dictionary = {}
var _ink_doors: Array[Node3D] = []
var _cyber_roof: Array[Node3D] = []
var _cyber_guides: Array[Node3D] = []
var _cyber_ramp: Node3D
var _cyber_braces: Array[Node3D] = []
var _sea_gates: Array[Node3D] = []
var _sea_runoff: Array[Node3D] = []
var _orbital_clamps: Array[Node3D] = []
var _cyber_rooms: Dictionary = {}
var _mounts: Dictionary = {}
var _terrain_users: Dictionary = {}
var _series := 0
var _kind := ""
var _age := 0.0
var _contact_age := -1.0
var _open := 0.0
var _entry_plane_z := 0.0
var _entry_plane_distance := 0.0
var _entry_plane_valid := false
var _entry_pace_speed := 0.0
var _entry_release := Vector2.ZERO
var _entry_released := false


func configure(game: Node3D) -> void:
	_game = game
	_cube = BoxMesh.new()
	_cube.size = Vector3.ONE
	_build_ink()
	_build_cyber()
	_build_sea()
	_build_orbital()
	_prepare_cyber_rooms()
	reset()


func warm_for_menu() -> void:
	# Submit the district's ordinary and city materials with the arena's
	# instance and shadow variants behind the menu preparation cover.
	for series in [2,3,4]:
		var room: Node3D = _arenas[series]
		room.position.z = -27.0
		room.show()
		await RenderingServer.frame_post_draw
		room.hide()


func reset() -> void:
	for key: String in _mounts.keys(): _unmount(key)
	for room: Node3D in _arenas.values(): room.visible = false
	_series = 0
	_kind = ""
	_age = 0.0
	_contact_age = -1.0
	_open = 0.0
	_entry_plane_valid = false


func preview(series: int, kind: String, lead_seconds: float) -> void:
	if not _arenas.has(series) or not ROUTES.has(kind) or _mounts.has(kind): return
	var route: Vector4 = ROUTES[kind]
	var travel := maxf(_game.BASE_SPEED,float(_game.speed))*(route.y+lead_seconds)
	var preferred_z := route.x-travel
	if preferred_z < -242.0 and lead_seconds > 0.0: return
	var host: Node3D
	var closest := INF
	var target_z := maxf(preferred_z,-251.0)
	for tile: Node3D in _game.road_segments:
		var clear := true
		for mount: Dictionary in _mounts.values():
			if tile.position.z > float(mount.host.position.z)-30.0:
				clear = false
				break
		if not clear: continue
		var delta := target_z-(tile.position.z-5.0)
		if delta < 0.0: continue
		if delta < closest:
			closest = delta
			host = tile
	if host == null: return
	var room := _room_for(series,kind)
	if room == null: return
	var terrain: Array[Node3D] = []
	for tile: Node3D in _game.road_segments:
		if absf(tile.position.z-host.position.z) > 10.25: continue
		terrain.append(tile)
		var users := int(_terrain_users.get(tile,0))
		if users == 0: _game.series_scenery.set_boss_terrain(tile,series,true)
		_terrain_users[tile] = users+1
	room.reparent(host,false)
	room.position = Vector3(0,0,-5.0)
	_pose_room(series,kind,0.0,0.0,-1.0)
	room.visible = true
	_mounts[kind] = {"room":room,"host":host,"terrain":terrain,"last_host_z":host.position.z,"series":series}
	_game._record_combat("arena_terrain_mount",null,{"series":series,"mechanism":kind,"z":room.global_position.z})


func ready_for_early_entry(kind: String) -> bool:
	if not _mounts.has(kind): return false
	var route: Vector4 = ROUTES[kind]
	var room: Node3D = _mounts[kind].room
	return room.global_position.z >= route.x-maxf(_game.BASE_SPEED,float(_game.speed))*route.y


func begin(series: int, kind: String) -> void:
	if not _arenas.has(series): return
	preview(series,kind,0.0)
	_series = series
	_kind = kind
	_age = 0.0
	_contact_age = -1.0
	_open = 0.0
	_entry_released = false
	_entry_plane_valid = _mounts.has(kind)
	if _entry_plane_valid:
		var room: Node3D = _mounts[kind].room
		_entry_plane_z = room.global_position.z
		_entry_plane_distance = _game.run_distance
		var route: Vector4 = ROUTES[kind]
		var available_speed := (route.x-_entry_plane_z)/route.y
		_entry_pace_speed = clampf(available_speed,_game.BASE_SPEED,maxf(_game.BASE_SPEED,float(_game.speed)))
	_pose_room(_series,_kind,0.0,0.0,-1.0)
	_game._record_combat("arena_mechanism_start",null,{"series":series,"mechanism":kind})


func sync_road() -> void:
	for kind: String in _mounts.keys():
		var mount: Dictionary = _mounts[kind]
		var z: float = mount.host.position.z
		if z < float(mount.last_host_z)-100.0 or z > 30.0:
			_unmount(kind)
		else:
			mount.last_host_z = z
			for tile: Node3D in mount.terrain.duplicate():
				if absf(tile.position.z-z) <= 10.25: continue
				_release_terrain(tile,int(mount.series))
				mount.terrain.erase(tile)


func update(sim_dt: float) -> void:
	if _series == 0 or _kind.is_empty() or sim_dt <= 0.0: return
	if _open >= 1.0 and _series != 3 and (_contact_age < 0.0 or _contact_age > 1.25): return
	_age += entry_delta(_kind,sim_dt)
	if _contact_age >= 0.0: _contact_age += sim_dt
	var progress := smoothstep(0.0,float(OPEN_SECONDS[_series]),_age)
	if progress >= 1.0 and _open < 1.0:
		_game._record_combat("arena_mechanism_open",null,{"series":_series,"mechanism":_kind})
	_open = progress
	_pose_room(_series,_kind,progress,_age,_contact_age)


func observe_pass(enemy: Node3D) -> void:
	var aircraft := str(enemy.enemy_kind) == "cyber_helicopter"
	if _contact_age >= 0.0 or _open < 1.0 or not _mounts.has(_kind): return
	if str(enemy.enemy_kind) != _kind and not (_kind == "cyber_delivery" and aircraft): return
	var room: Node3D = _mounts[_kind].room
	if enemy.global_position.z < room.global_position.z: return
	_contact_age = 0.0
	_game._record_combat("arena_mechanism_contact",enemy,{"series":_series,"mechanism":_kind,"z":room.global_position.z})


func entry_delta(kind: String, sim_dt: float) -> float:
	if not _entry_plane_valid: return sim_dt
	if kind != _kind and not (_kind == "cyber_delivery" and kind in SLING_MEMBERS): return sim_dt
	return sim_dt*_entry_pace()


func _entry_pace() -> float:
	# At a higher gear the same physical stretch approaches faster. Use its
	# distance to keep the opening and approach on time together.
	return maxf(1.0,float(_game.speed)/_entry_pace_speed)


func approach_offset(kind: String, phase: float) -> float:
	if kind != _kind or not _entry_plane_valid: return 0.0
	var route: Vector4 = ROUTES[kind]
	if phase >= route.w: return 0.0
	var advance := float(_game.run_distance)-_entry_plane_distance
	var offset := _entry_plane_z+advance-route.x
	if phase <= route.z:
		return 8.0*tanh(offset/8.0) if offset > 0.0 else offset
	# The opening and actor move together through the crossing. At release,
	# inherit the road's velocity once, then ease to the authored combat
	# route with a continuous tangent, independently of the tile's recycle.
	if not _entry_released:
		var duration: float = EntryMotion.DURATIONS["cyber_captain" if kind == "cyber_delivery" else kind]
		var velocity := float(_game.speed)/_entry_pace()
		var at_release := offset-velocity*(phase-route.z)*duration
		if at_release > 0.0:
			var saturation := tanh(at_release/8.0)
			at_release = 8.0*saturation
			velocity *= 1.0-saturation*saturation
		_entry_release = Vector2(at_release,velocity*(route.w-route.z)*duration)
		_entry_released = true
	var progress := (phase-route.z)/(route.w-route.z)
	var left := 1.0-progress
	return left*left*((1.0+2.0*progress)*_entry_release.x+progress*_entry_release.y)


func _unmount(kind: String) -> void:
	var mount: Dictionary = _mounts[kind]
	var room: Node3D = mount.room
	room.hide()
	room.reparent(self,false)
	for tile: Node3D in mount.terrain: _release_terrain(tile,int(mount.series))
	_mounts.erase(kind)


func _release_terrain(tile: Node3D, series: int) -> void:
	var users := int(_terrain_users[tile])-1
	if users > 0:
		_terrain_users[tile] = users
	else:
		_terrain_users.erase(tile)
		_game.series_scenery.set_boss_terrain(tile,series,false)


func get_debug_state() -> Dictionary:
	var mount: Dictionary = _mounts.get(_kind,{})
	var room: Node3D = mount.get("room")
	var tile: Node3D = mount.get("host")
	return {"series":_series,"mechanism":_kind,"open":_open,"age":_age,"contact_age":_contact_age,
		"position_z":room.global_position.z if room != null else 0.0,"visible":room != null and room.visible,
		"tile_z":tile.global_position.z if tile != null else 0.0,"tile_id":tile.get_instance_id() if tile != null else 0,
		"mount_count":_mounts.size()}


func _room_for(series: int, kind: String) -> Node3D:
	if series == 3:
		var hardware: Dictionary = _cyber_rooms[kind]
		return hardware.room
	return _arenas[series]


func _prepare_cyber_rooms() -> void:
	var original: Node3D = _arenas[3]
	for kind: String in CYBER_STAGES:
		var room := original
		if kind != CYBER_STAGES[0]:
			room = original.duplicate() as Node3D
			room.name = "HoistHall_"+kind
			add_child(room)
		_cyber_rooms[kind] = {"room":room,"roof":_copy_joints(room,_cyber_roof),
			"guides":_copy_joints(room,_cyber_guides),"braces":_copy_joints(room,_cyber_braces),
			"ramp":room.get_child(_cyber_ramp.get_index())}
		room.hide()


func _copy_joints(room: Node3D, joints: Array[Node3D]) -> Array[Node3D]:
	var mapped: Array[Node3D] = []
	for joint: Node3D in joints: mapped.append(room.get_child(joint.get_index()))
	return mapped


func _pose_room(series: int, kind: String, open: float, age: float, contact_age: float) -> void:
	var rebound := sin(contact_age*15.0)*exp(-contact_age*5.8) if contact_age >= 0.0 else 0.0
	match series:
		2:
			for index in _ink_doors.size():
				var side := -1.0 if index == 0 else 1.0
				_ink_doors[index].rotation.y = -side*(1.66*open+0.055*rebound)
		3:
			var hardware: Dictionary = _cyber_rooms[kind]
			var roof: Array[Node3D] = hardware.roof
			var guides: Array[Node3D] = hardware.guides
			var braces: Array[Node3D] = hardware.braces
			var ramp: Node3D = hardware.ramp
			var returning := kind == "cyber_helicopter"
			var roof_open := 1.0 if kind != "cyber_delivery" else open
			for index in roof.size():
				var side := -1.0 if index == 0 else 1.0
				roof[index].position.x = side*(2.75+5.5*roof_open)
				roof[index].rotation.z = side*(0.055*roof_open+0.015*rebound)
			var guide_count := guides.size()
			var wave := mini(guide_count-1,int(age*8.0))
			for index in guide_count:
				var lamp := guides[index]
				var order := guide_count-1-index if returning else index
				lamp.visible = order <= wave
			var ramp_deploy := smoothstep(0.0,0.45,open)
			ramp.visible = kind == "cyber_tank"
			ramp.position.y = lerpf(-4.6,-0.14,ramp_deploy)
			ramp.rotation.x = 0.63*ramp_deploy*(1.0-open)
			for index in braces.size():
				var side := -1.0 if index == 0 else 1.0
				braces[index].visible = kind == "cyber_gunship"
				braces[index].rotation.y = side*(1.60-0.96*sin(open*PI)+0.08*rebound)
		4:
			for index in _sea_gates.size():
				var side := -1.0 if index == 0 else 1.0
				_sea_gates[index].position.x = side*(5.6+2.85*open)
				_sea_gates[index].position.y = 1.0+2.6*open
				_sea_runoff[index].position.y = -0.10+1.48*(1.0-open)+0.20*rebound
				_sea_runoff[index].position.z = 1.8+1.75*open
		5:
			for index in _orbital_clamps.size():
				var side := -1.0 if index%2 == 0 else 1.0
				var stroke := smoothstep(0.08*float(index),1.0,open)
				_orbital_clamps[index].rotation.y = side*(1.55*stroke+0.05*rebound)
				_orbital_clamps[index].position.y = 6.2+float(index >> 1)*5.3+0.70*stroke


func _room(series: int, label: String) -> Node3D:
	_architecture_material = _game.series_scenery.architecture_material(series)
	_architecture_shadows = series in [2,3]
	var room := Node3D.new()
	room.name = label
	add_child(room)
	_arenas[series] = room
	return room


func _pivot(parent: Node3D, label: String, at: Vector3) -> Node3D:
	var joint := Node3D.new()
	joint.name = label
	parent.add_child(joint)
	joint.position = at
	return joint


func _boxes(parent: Node3D, label: String, entries: Array, luminous: bool = false) -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = _cube
	multi.instance_count = entries.size()
	for index in entries.size():
		var item: Array = entries[index]
		var rotation: Basis = item[3] if item.size() > 3 else Basis.IDENTITY
		multi.set_instance_transform(index,Transform3D(rotation.scaled_local(item[0]),item[1]))
		var tint: Color = item[2]
		if luminous and is_equal_approx(tint.a,1.0): tint.a = 0.77
		multi.set_instance_color(index,tint.srgb_to_linear())
	var mesh := MultiMeshInstance3D.new()
	mesh.name = label
	mesh.multimesh = multi
	mesh.material_override = _architecture_material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _architecture_shadows and not luminous else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)


func _strut(entries: Array, first: Vector3, last: Vector3, width: float, depth: float, color: Color) -> void:
	var axis := last-first
	var rotation := Basis(Quaternion(Vector3.UP,axis.normalized()))
	entries.append([Vector3(width,axis.length(),depth),(first+last)*0.5,color,rotation])


func _build_ink() -> void:
	var room := _room(2,"RidgeGate")
	var slate := Color("242424")
	var granite := Color("8c8c8c")
	var pale := Color("c4c4c4")
	var cliff := Color("656565")
	var red := Color("8d2622")
	var frame: Array = []
	var lanterns: Array = []
	for side: float in [-1.0,1.0]:
		# Split bedrock ties the gate into the gorge, with the dressed stone
		# courses above it continuing the material of the existing road rail.
		for tier in range(6):
			var level := float(tier)
			frame.append([Vector3(5.0+level*0.56,3.52,10.0+level*0.83),
				Vector3(side*(10.85-level*0.19),-19.72+level*3.5,0.4),
				cliff.lightened(level*0.014)])
		frame.append([Vector3(6.2,0.60,15.3),Vector3(side*8.68,-0.37,0.15),granite])
		for tier in range(3):
			var width := 3.23-float(tier)*0.47
			frame.append([Vector3(width,0.28,4.38-float(tier)*0.49),Vector3(side*6.92,0.10+float(tier)*0.28,0),granite.darkened(0.048*float(tier))])
		for z: float in [-1.15,1.15]:
			var column := Vector3(side*6.53,0,z)
			frame.append([Vector3(1.18,0.33,1.22),column+Vector3(0,0.95,0),pale.darkened(0.18)])
			frame.append([Vector3(0.79,9.28,0.85),column+Vector3(0,5.74,0),slate])
			frame.append([Vector3(0.52,7.87,0.053),column+Vector3(0,5.63,0.438),slate.lightened(0.12)])
			frame.append([Vector3(0.98,0.28,1.03),column+Vector3(0,9.57,0),slate])
			for course in range(3):
				var arm := 1.34+0.34*float(course)
				var y := 9.88+0.30*float(course)
				frame.append([Vector3(arm,0.20,0.36),column+Vector3(-side*0.12*float(course),y,0),slate if course != 1 else granite.darkened(0.25)])
				frame.append([Vector3(0.33,0.18,arm),column+Vector3(0,y+0.13,0),slate])
		for y: float in [1.22,3.42,5.66]:
			frame.append([Vector3(1.18,0.25,0.47),Vector3(side*5.82,y,0),slate])
			frame.append([Vector3(0.25,0.33,0.40),Vector3(side*5.31,y,0),granite.darkened(0.40)])
		for z: float in [-5.35,4.9]:
			var foot := Vector3(side*9.20,0.36,z)
			frame.append([Vector3(1.8,0.35,1.86),foot,granite])
			frame.append([Vector3(0.55,2.9,0.61),foot+Vector3(0,1.52,0),slate])
			frame.append([Vector3(1.12,0.24,1.18),foot+Vector3(0,2.86,0),slate])
			frame.append([Vector3(0.72,0.53,0.76),foot+Vector3(0,2.49,0),slate])
			lanterns.append([Vector3(0.43,0.32,0.047),foot+Vector3(0,2.51,0.40),Color(red,0.87)])
		# Through-lattice panels are built as stiles, rails and a low planked
		# kick plate. The lock side reveals the valley before the gates move.
		var leaf := _pivot(room,"TimberGateLeaf",Vector3(side*5.25,0,0))
		var leaf_frame: Array = [
			[Vector3(5.02,0.43,0.39),Vector3(-side*2.51,0.46,0),slate],
			[Vector3(5.02,0.39,0.41),Vector3(-side*2.51,5.94,0),slate],
			[Vector3(0.27,5.67,0.38),Vector3(-side*0.15,3.19,0),slate],
			[Vector3(0.32,5.67,0.39),Vector3(-side*4.85,3.19,0),slate],
		]
		for slat in range(9):
			var x := -side*(0.44+float(slat)*0.518)
			leaf_frame.append([Vector3(0.479,1.86,0.17),Vector3(x,1.50,0),slate.lightened(0.071+0.023*float(slat%3))])
			leaf_frame.append([Vector3(0.14,3.55,0.16),Vector3(x,4.07,0),slate])
		for y: float in [2.49,3.57,4.66,5.43]:
			leaf_frame.append([Vector3(4.57,0.135,0.24),Vector3(-side*2.49,y,0),slate])
		for z: float in [-0.205,0.205]:
			leaf_frame.append([Vector3(0.64,0.77,0.06),Vector3(-side*4.56,2.52,z),red.darkened(0.24)])
			leaf_frame.append([Vector3(0.22,0.38,0.11),Vector3(-side*4.56,2.52,z+signf(z)*0.034),granite.darkened(0.39)])
		_boxes(leaf,"DoorLatticeAndFittings",leaf_frame)
		_ink_doors.append(leaf)
	for z: float in [-1.15,1.15]:
		frame.append([Vector3(14.7,0.49,0.52),Vector3(0,10.89,z),slate])
		frame.append([Vector3(13.0,0.12,0.16),Vector3(0,10.78,z+signf(z)*0.31),red.darkened(0.16)])
		for i in range(15):
			var x := -6.30+float(i)*0.90
			frame.append([Vector3(0.12,0.16,0.14),Vector3(x,11.12,z+signf(z)*0.30),granite.darkened(0.22)])
	# Short stepped tiles over a double-sided pitch. The rolled ends are
	# carried by visible purlins and each outer rafter reaches the fascia.
	for side: float in [-1.0,1.0]:
		for course in range(6):
			var fraction := float(course)/5.0
			var at := Vector3(0,12.52-pow(fraction,0.76)*1.03,side*(0.33+float(course)*0.45))
			frame.append([Vector3(15.82+fraction*0.82,0.29,0.59),at,slate])
			frame.append([Vector3(16.0+fraction*0.94,0.10,0.075),at+Vector3(0,0.086,side*0.294),slate.lightened(0.16)])
		for i in range(29):
			var x := -8.12+float(i)*0.58
			var lift := pow(absf(x)/8.12,7.0)*0.38
			_strut(frame,Vector3(x,11.42+lift,side*2.38),Vector3(x,12.53,side*0.19),0.128,0.19,slate.lightened(0.11))
		frame.append([Vector3(17.23,0.15,0.15),Vector3(0,11.34,side*2.67),slate])
	frame.append([Vector3(16.6,0.31,0.34),Vector3(0,12.81,0),slate.lightened(0.10)])
	frame.append([Vector3(1.58,0.76,0.12),Vector3(0,11.44,1.55),slate])
	for x: float in [-0.37,0.0,0.37]:
		frame.append([Vector3(0.061,0.35,0.034),Vector3(x,11.45,1.62),pale.darkened(0.35)])
	_boxes(room,"CliffFootingsAndTimberRoof",frame)
	_boxes(room,"RecessedVermilionLanterns",lanterns,true)


func _build_cyber() -> void:
	var room := _room(3,"CyberHoistHall")
	# The same steel, hull, asphalt, paint and signal glass as _night_pursuit.
	var steel := Color("3c4a59")
	var hull := Color("25303d")
	var dark := Color("131c26")
	var frame := Color("657382")
	var rail := Color("b88646")
	var amber := Color(1.0,0.64,0.27,0.58)
	var glass := Color(0.28,0.68,0.82,0.76)
	var structure: Array = []
	var signals: Array = []
	for side: float in [-1.0,1.0]:
		# A recessed maintenance trench separates the crash rail from the hall
		# wall. The lower carriage rail and the yard foundations share its curb.
		structure.append([Vector3(10.32,0.50,19.4),Vector3(side*10.45,-0.31,0),steel])
		structure.append([Vector3(3.30,5.4,19.35),Vector3(side*11.25,-2.98,0),dark])
		structure.append([Vector3(1.55,0.09,18.6),Vector3(side*6.75,-0.008,0),hull])
		for x: float in [6.12,7.38]:
			structure.append([Vector3(0.095,0.075,18.82),Vector3(side*x,0.074,0),rail])
		for rib in range(12):
			structure.append([Vector3(0.82,0.028,0.075),Vector3(side*6.75,0.052,-8.7+1.57*rib),frame.darkened(0.17)])

		# Two raked column pairs hold the overhead lattice. The shoulders
		# are plated in bays rather than formed from a solid slab of metal.
		for z: float in [-6.65,6.65]:
			var shoe := Vector3(side*11.12,0.25,z)
			var head := Vector3(side*9.12,14.54,z)
			structure.append([Vector3(3.08,0.46,2.65),shoe,hull])
			structure.append([Vector3(2.15,0.16,1.86),shoe+Vector3(-side*0.12,0.31,0),frame.darkened(0.17)])
			_strut(structure,shoe+Vector3(0,0.33,0),head,1.35,1.10,hull)
			_strut(structure,shoe+Vector3(-side*0.48,0.33,0.38),head+Vector3(-side*0.48,0,0.38),0.28,0.40,steel)
			_strut(structure,Vector3(side*7.84,0.12,z),Vector3(side*10.22,4.65,z),0.71,0.81,steel)
			_strut(structure,Vector3(side*10.20,7.05,z),Vector3(side*7.12,8.89,z),0.54,0.58,steel)
			structure.append([Vector3(2.92,0.65,1.76),head,steel])
			for bolt in range(3):
				structure.append([Vector3(0.16,0.14,0.21),shoe+Vector3(side*(0.57-0.42*bolt),0.39,0.69),frame])
			structure.append([Vector3(0.58,1.46,0.12),Vector3(side*10.08,5.11,z+0.63),dark])
			for strip in range(3):
				signals.append([Vector3(0.32,0.115,0.09),Vector3(side*10.08,4.69+0.36*strip,z+0.71),amber])
		# A long gallery hides the actuator runs. Its interior face uses the
		# same recessed split windows and ochre catwalk rail as the district.
		structure.append([Vector3(3.72,0.46,14.8),Vector3(side*10.35,4.72,0),steel])
		structure.append([Vector3(2.83,2.38,13.0),Vector3(side*12.18,6.13,0),hull])
		structure.append([Vector3(3.62,0.26,13.8),Vector3(side*11.91,7.38,0),steel])
		structure.append([Vector3(0.12,0.12,14.4),Vector3(side*8.55,5.56,0),rail])
		for bay in range(7):
			var z := -6.30+2.10*bay
			structure.append([Vector3(0.12,0.83,0.14),Vector3(side*8.55,5.14,z),rail])
			structure.append([Vector3(0.14,1.28,1.72),Vector3(side*10.73,6.09,z),frame.darkened(0.19)])
			structure.append([Vector3(0.10,1.05,1.48),Vector3(side*10.63,6.09,z),dark])
			for band in range(2):
				var pane := Vector3(side*10.56,5.92+band*0.32,z)
				if (bay+band+(0 if side < 0.0 else 1))%4 != 0:
					signals.append([Vector3(0.045,0.20,1.29),pane,glass])
				else:
					structure.append([Vector3(0.045,0.20,1.29),pane,steel])

		# Long side receivers and the short transverse rack are visible when
		# the shutter rolls under the overhang. All receivers are outside the
		# moving air lane, leaving the high lattice as the only fixed span.
		for x: float in [6.12,10.63]:
			structure.append([Vector3(0.42,0.42,14.42),Vector3(side*x,8.51,0),hull])
			structure.append([Vector3(0.21,0.115,14.40),Vector3(side*x,8.74,0),steel])
		structure.append([Vector3(4.14,0.38,11.30),Vector3(side*9.47,10.11,0),hull])
		structure.append([Vector3(0.22,0.29,10.8),Vector3(side*7.48,9.88,0),rail])
		for z: float in [-3.84,3.84]:
			structure.append([Vector3(5.24,0.32,0.45),Vector3(side*8.44,8.48,z),steel])
			for tooth in range(6):
				structure.append([Vector3(0.17,0.096,0.29),Vector3(side*(6.27+0.65*tooth),8.67,z),frame.darkened(0.14)])
		for z: float in [-5.70,-3.80,-1.90,0.0,1.90,3.80,5.70]:
			structure.append([Vector3(0.21,0.39,0.46),Vector3(side*7.58,9.71,z),steel])
			signals.append([Vector3(0.055,0.125,0.28),Vector3(side*7.454,9.68,z),amber])
		for z: float in [-8.6,8.6]:
			_strut(structure,Vector3(side*11.18,10.22,z),Vector3(side*9.31,13.66,z*0.77),0.49,0.61,steel)

		# Outboard plinth, spindle collar and visible return springs.
		structure.append([Vector3(1.54,1.33,2.14),Vector3(side*7.81,4.57,-1.50),hull])
		structure.append([Vector3(0.46,1.13,1.40),Vector3(side*7.22,4.55,-1.50),steel])
		_strut(structure,Vector3(side*9.62,1.2,-1.50),Vector3(side*7.94,4.26,-1.50),0.62,0.73,steel)

		var shutter := _pivot(room,"HoistRoofLeaf",Vector3(side*2.75,8.90,0))
		var panels: Array = []
		var marks: Array = []
		for rail_x: float in [-2.46,2.46]:
			panels.append([Vector3(0.30,0.34,8.28),Vector3(rail_x,0.025,-0.05),steel])
		for index in range(6):
			var z := -3.47+1.39*index
			panels.append([Vector3(4.66,0.24,1.24),Vector3(0,0.061,z),hull if index%2==0 else steel])
			panels.append([Vector3(4.82,0.21,0.13),Vector3(0,-0.124,z+0.57),hull])
			panels.append([Vector3(0.25,0.17,1.15),Vector3(-side*2.42,-0.06,z),hull])
			marks.append([Vector3(0.075,0.036,0.72),Vector3(-side*2.38,-0.163,z),amber])
		for z: float in [-3.82,3.82]:
			panels.append([Vector3(5.22,0.39,0.36),Vector3(0,-0.04,z),hull])
			for x: float in [-2.02,2.02]:
				panels.append([Vector3(0.68,0.38,0.78),Vector3(x,-0.195,z),steel])
				panels.append([Vector3(0.48,0.32,0.54),Vector3(x,-0.244,z),dark])
		_boxes(shutter,"SegmentedRoofAndCarriage",panels)
		_boxes(shutter,"ShutterSeamMarkers",marks,true)
		_cyber_roof.append(shutter)

		var brace := _pivot(room,"InspectionArm",Vector3(side*7.25,4.55,-1.5))
		var arm: Array = []
		for z: float in [-0.27,0.27]:
			arm.append([Vector3(3.71,0.31,0.22),Vector3(-side*1.86,0.19,z),steel])
			arm.append([Vector3(2.77,0.22,0.17),Vector3(-side*1.65,-0.22,z),frame.darkened(0.22)])
		arm.append([Vector3(0.77,0.76,0.78),Vector3(-side*0.31,0.0,0),hull])
		arm.append([Vector3(0.73,0.64,0.66),Vector3(-side*3.69,0.05,0),hull])
		for jaw in [-1.0,1.0]:
			arm.append([Vector3(0.65,0.21,0.27),Vector3(-side*4.11,jaw*0.34,0),steel])
			arm.append([Vector3(0.22,0.25,0.26),Vector3(-side*4.38,jaw*0.24,0),rail])
		_boxes(brace,"ActuatorAndGripper",arm)
		_boxes(brace,"GripperState",[[Vector3(0.24,0.15,0.065),Vector3(-side*3.62,0.14,0.37),glass]],true)
		_cyber_braces.append(brace)

	# Upper box trusses remain above the highest actor pose. Between them,
	# a raised inspection pod hangs off one end rather than mirroring the hall.
	for z: float in [-6.65,6.65]:
		structure.append([Vector3(18.82,0.34,0.64),Vector3(0,13.45,z),steel])
		structure.append([Vector3(18.82,0.42,0.72),Vector3(0,15.38,z),hull])
		for bay in range(8):
			var x := -9.10+2.275*bay
			var slope := -1.0 if bay%2==0 else 1.0
			_strut(structure,Vector3(x,14.42+slope*0.78,z),Vector3(x+2.275,14.42-slope*0.78,z),0.19,0.34,steel)
		for x: float in [-5.65,-2.8,2.8,5.65]:
			structure.append([Vector3(0.61,0.22,0.42),Vector3(x,13.19,z),dark])
			signals.append([Vector3(0.42,0.045,0.29),Vector3(x,13.06,z),amber])
	for x: float in [-9.0,-3.42,3.42,9.0]:
		structure.append([Vector3(0.31,0.33,13.55),Vector3(x,15.32,0),hull])
	structure.append([Vector3(2.43,2.36,3.58),Vector3(-10.76,12.74,5.01),hull])
	structure.append([Vector3(2.61,0.24,4.14),Vector3(-10.81,14.03,5.05),steel])
	structure.append([Vector3(1.91,0.52,0.15),Vector3(-10.76,12.97,6.86),dark])
	for pane in range(3):
		signals.append([Vector3(0.47,0.23,0.038),Vector3(-11.30+pane*0.55,12.94,6.96),glass])
	_boxes(room,"SwitchyardAndLattice",structure)
	_boxes(room,"InspectionWindowAndLamps",signals,true)

	for index in range(8):
		var guide := _pivot(room,"GuidePair",Vector3(0,8.29,-6.40+index*1.83))
		_boxes(guide,"Guidance",[[Vector3(0.075,0.12,0.81),Vector3(-5.88,0,0),glass],
			[Vector3(0.075,0.12,0.81),Vector3(5.88,0,0),glass]],true)
		_cyber_guides.append(guide)

	_cyber_ramp = _pivot(room,"ServiceRamp",Vector3(0,-0.14,6.1))
	var plates: Array = []
	var marks: Array = []
	for x: float in [-3.80,3.80]:
		plates.append([Vector3(0.35,0.22,6.47),Vector3(x,-0.078,-3.24),steel])
	for index in range(7):
		var z := -0.44-0.92*index
		plates.append([Vector3(7.95,0.178,0.88),Vector3(0,0,z),hull if index%2==0 else steel])
		for x: float in [-3.48,3.48]:
			plates.append([Vector3(0.34,0.022,0.46),Vector3(x,0.099,z),dark])
			marks.append([Vector3(0.15,0.021,0.26),Vector3(x,0.114,z+0.055),amber])
	_boxes(_cyber_ramp,"ReinforcedTreadPlates",plates)
	_boxes(_cyber_ramp,"RampInsetLights",marks,true)


func _build_sea() -> void:
	var room := _room(4,"StormCaissonLock")
	var hull := Color(Color("303f4d"),0.994)
	var plate := Color(Color("647889"),0.994)
	var galvanised := Color(Color("9aa6a7"),0.994)
	var teal := Color(Color("356a73"),0.994)
	var dark := Color(Color("243442"),0.994)
	var rust := Color("bd6c3f")
	var ochre := Color("a87248")
	var lamp := Color(0.96,0.70,0.37,0.64)
	var wet := Color(0.15,0.55,0.57,0.92)
	var whitewater := Color(0.63,0.84,0.80,0.89)
	var caissons: Array = []
	var signals: Array = []
	for side: float in [-1.0,1.0]:
		var edge := side*5.27
		caissons.append([Vector3(1.90,0.26,18.5),Vector3(edge+side*0.95,-0.20,0),plate])
		caissons.append([Vector3(2.30,1.22,17.35),Vector3(side*6.45,-0.91,0),hull])
		caissons.append([Vector3(6.50,0.42,17.7),Vector3(side*10.88,-0.36,-0.20),dark])
		caissons.append([Vector3(6.29,0.29,16.92),Vector3(side*10.89,-0.04,-0.20),hull])
		for z: float in [-6.5,-1.96,2.22,6.37]:
			var inner := Vector3(side*6.52,-0.72,z)
			var outer := Vector3(side*13.22,-0.82,z)
			_strut(caissons,inner+Vector3(side*0.64,-9.25,0.35),inner,0.89,1.18,hull)
			_strut(caissons,outer+Vector3(side*0.54,-9.1,0.40),outer,1.22,1.42,dark)
			_strut(caissons,outer+Vector3(side*0.44,-5.7,0.30),inner,0.39,0.79,plate)
			caissons.append([Vector3(1.48,0.43,1.41),outer+Vector3(0,-2.37,0.12),teal])
			caissons.append([Vector3(1.51,0.19,1.48),outer+Vector3(0,-2.03,0.12),rust])
			caissons.append([Vector3(0.59,0.30,1.32),Vector3(side*6.18,0.34,z),dark])
			signals.append([Vector3(0.065,0.11,0.49),Vector3(side*5.866,0.40,z),lamp])
		for z: float in [-4.1,4.16]:
			_strut(caissons,Vector3(side*13.22,-0.58,z-1.65),Vector3(side*13.48,-5.94,z+1.5),0.35,0.68,plate)
		for grating in range(13):
			var z := -6.2+float(grating)*0.99
			caissons.append([Vector3(0.73,0.035,0.48),Vector3(side*6.25,-0.031,z),plate if grating%3 == 0 else dark])

		# The leaf climbs a pair of rails on the near face of the open jack.
		# Guide shoes carry the moving leaf into the receiving gantry.
		var rail_foot := Vector3(side*5.52,0.70,-0.92)
		var rail_head := Vector3(side*10.82,5.54,-0.92)
		for shoe_offset: float in [0.0,1.48]:
			var shift := Vector3(side*shoe_offset,0,0)
			_strut(caissons,rail_foot+shift,rail_head+shift,0.19,0.23,galvanised)
			for support in range(5):
				var at := rail_foot.lerp(rail_head,float(support)/4.0)+shift
				caissons.append([Vector3(0.34,0.23,0.24),at+Vector3(0,0,-0.18),hull])
				caissons.append([Vector3(0.13,0.17,0.12),at+Vector3(side*0.15,0.02,0.20),ochre])
		var jack := Vector3(side*12.24,6.83,-0.92)
		for end: float in [-2.63,2.48]:
			var foot := Vector3(side*13.71,0.08,end)
			caissons.append([Vector3(1.81,0.31,1.72),foot,plate])
			_strut(caissons,foot,jack,0.82,1.06,hull)
			_strut(caissons,foot+Vector3(-side*1.36,0,0),jack+Vector3(-side*0.38,-0.38,0),0.46,0.59,teal)
			_strut(caissons,foot+Vector3(0,1.53,0),Vector3(side*13.72,0.61,-end*0.81),0.26,0.37,plate)
		_strut(caissons,Vector3(side*10.2,6.18,-0.78),jack+Vector3(side*0.57,0.13,0),0.62,1.46,plate)
		caissons.append([Vector3(2.58,0.30,1.92),jack+Vector3(0,0.10,0),dark])
		caissons.append([Vector3(1.76,0.79,1.46),jack+Vector3(side*0.22,0.53,-0.11),teal])
		caissons.append([Vector3(2.10,0.19,1.72),jack+Vector3(side*0.22,1.0,-0.11),hull])
		for drum_end: float in [-0.68,0.68]:
			caissons.append([Vector3(0.19,0.57,0.71),jack+Vector3(drum_end,0.55,0.65),galvanised])
		signals.append([Vector3(0.51,0.19,0.085),jack+Vector3(-side*0.41,0.49,0.64),lamp])

		# The spill bed is graded 1.48m per 1.75m, matching the runoff
		# node's rise and travel so the animated crests stay on the apron.
		var lip := Vector3(side*9.22,1.75,1.42)
		var outlet := Vector3(side*9.22,-4.61,8.94)
		_strut(caissons,lip,outlet,3.83,0.36,dark)
		_strut(caissons,lip+Vector3(0,0.04,0),outlet+Vector3(0,0.04,0),2.78,0.31,teal)
		for bank: float in [-1.74,1.74]:
			var wall := Vector3(bank,0.26,0)
			_strut(caissons,lip+wall,outlet+wall,0.29,0.53,plate)
			_strut(caissons,lip+wall+Vector3(0,0.28,0),outlet+wall+Vector3(0,0.28,0),0.10,0.13,ochre)
		for step in range(6):
			var at := lip.lerp(outlet,float(step)/6.0)
			caissons.append([Vector3(3.22,0.16,0.29),at+Vector3(0,0.14,0),hull])
		for column in range(3):
			var x := side*(12.02+float(column)*0.61)
			caissons.append([Vector3(0.38,0.82,1.89),Vector3(x,0.55,5.94),hull])
			caissons.append([Vector3(0.26,0.09,1.72),Vector3(x,1.01,5.94),plate])
		var basin := Vector3(side*9.22,1.34,0.73)
		caissons.append([Vector3(3.78,0.56,1.56),basin,teal])
		caissons.append([Vector3(3.02,0.12,1.47),basin+Vector3(0,0.34,0.03),wet.darkened(0.15)])
		caissons.append([Vector3(3.86,0.14,0.22),basin+Vector3(0,0.41,-0.66),rust])
		_strut(caissons,basin+Vector3(side*1.79,0.02,-0.16),Vector3(side*12.14,0.28,-0.12),0.33,0.34,ochre)

		# Dark panel faces, deep ribs and a short ochre datum mark keep
		# the opening visible against the waves without a bright facade.
		var gate := _pivot(room,"CaissonLiftLeaf",Vector3(side*5.6,1,0))
		var leaf: Array = []
		leaf.append([Vector3(4.16,2.62,0.57),Vector3(side*2.13,1.39,0),hull])
		leaf.append([Vector3(4.19,0.32,0.79),Vector3(side*2.13,0.12,0.08),dark])
		leaf.append([Vector3(4.18,0.23,0.73),Vector3(side*2.13,2.73,0.04),plate])
		for bay in range(4):
			var x := side*(0.65+float(bay)*0.98)
			leaf.append([Vector3(0.83,2.13,0.12),Vector3(x,1.45,0.31),teal if bay%2 == 0 else hull])
			leaf.append([Vector3(0.16,2.38,0.19),Vector3(x-side*0.43,1.40,0.35),plate])
			leaf.append([Vector3(0.11,0.16,0.11),Vector3(x-side*0.31,2.45,0.39),galvanised])
			leaf.append([Vector3(0.57,0.12,0.10),Vector3(x,0.67,0.39),rust])
		for shoe: float in [0.45,1.93]:
			leaf.append([Vector3(0.52,0.32,0.73),Vector3(side*shoe,0.18,-0.50),dark])
			leaf.append([Vector3(0.36,0.20,0.24),Vector3(side*shoe,0.18,-0.92),galvanised])
		_boxes(gate,"RibbedLockLeaves",leaf)
		_sea_gates.append(gate)

		var runoff := _pivot(room,"SpillwayCrests",Vector3(side*6.7,0.65,1.8))
		var streaks: Array = []
		for crest in range(8):
			var z := 0.22+float(crest)*0.60
			var at := Vector3(side*2.52,0.24-z*0.8457,z)
			var shift := float((crest*7)%5-2)*0.16
			streaks.append([Vector3(1.8+float(crest%3)*0.21,0.082,0.24),at+Vector3(shift,0,0),wet])
			streaks.append([Vector3(0.69+float(crest%4)*0.29,0.042,0.12),at+Vector3(-shift,0.07,0.06),whitewater])
			streaks.append([Vector3(0.23,0.062,0.20),at+Vector3(-0.98-shift,-0.07,0.18),wet])
		_boxes(runoff,"BrokenWaterAndFoam",streaks)
		_sea_runoff.append(runoff)

	# Different equipment on the two working decks leaves an asymmetric
	# horizon. One side has a glazed operator booth, the other a vent rack.
	var booth := Vector3(13.36,0.48,-4.62)
	caissons.append([Vector3(3.92,0.21,3.88),booth+Vector3(0,-0.37,0),plate])
	caissons.append([Vector3(3.48,2.24,3.41),booth+Vector3(0,0.89,0),hull])
	caissons.append([Vector3(3.79,0.22,3.73),booth+Vector3(0,2.07,0),plate])
	caissons.append([Vector3(3.29,0.13,3.34),booth+Vector3(0,2.23,0),dark])
	for mullion in range(4):
		var x := -1.20+float(mullion)*0.79
		signals.append([Vector3(0.63,0.55,0.08),booth+Vector3(x,1.27,1.74),Color(0.74,0.59,0.34,0.77)])
	for window in range(3):
		signals.append([Vector3(0.085,0.55,0.59),booth+Vector3(-1.77,1.27,-0.97+float(window)*0.83),Color(0.74,0.59,0.34,0.77)])
	for stack in range(3):
		var at := Vector3(-13.50+float(stack)*0.91,0.24,-4.79-float(stack%2)*0.48)
		var height := 2.42+float(stack)*0.38
		caissons.append([Vector3(0.69,height,0.73),at+Vector3(0,height*0.5,0),hull])
		caissons.append([Vector3(0.79,0.24,0.81),at+Vector3(0,height,0),rust])
		_strut(caissons,at+Vector3(0,height*0.77,0),at+Vector3(0.57,height*0.60,0.76),0.21,0.29,plate)
	_boxes(room,"CaissonsAndOpenLiftJacks",caissons)
	_boxes(room,"SodiumServiceLights",signals,true)


func _build_orbital() -> void:
	var room := _room(5,"OrbitalDryDock")
	var frame := SeriesScenery.ORBITAL_FRAME
	var armor := SeriesScenery.ORBITAL_ARMOR
	var steel := SeriesScenery.ORBITAL_STEEL
	var recess := SeriesScenery.ORBITAL_INSET
	var brass := SeriesScenery.ORBITAL_BRASS
	var amber := SeriesScenery.ORBITAL_AMBER
	var violet := SeriesScenery.ORBITAL_VIOLET
	var steelwork: Array = []
	var markers: Array = []
	for side: float in [-1.0,1.0]:
		var deck := Vector3(side*10.45,-0.44,0)
		steelwork.append([Vector3(8.90,0.64,18.60),deck,armor])
		steelwork.append([Vector3(6.40,1.38,17.80),deck+Vector3(side*1.12,-0.96,0),frame])
		steelwork.append([Vector3(3.26,4.74,13.22),Vector3(side*12.81,-3.48,-0.66),recess])
		for z: float in [-7.6,-3.1,2.5,7.6]:
			_strut(steelwork,Vector3(side*6.40,-1.68,z),Vector3(side*13.24,-5.37,z),0.61,0.84,steel)
			steelwork.append([Vector3(1.53,0.21,0.26),Vector3(side*7.72,-0.21,z),steel])
			steelwork.append([Vector3(3.53,0.06,0.51),Vector3(side*10.34,-0.087,z),frame])
			steelwork.append([Vector3(1.17,0.065,0.32),Vector3(side*8.75,-0.055,z+0.17),brass])
		steelwork.append([Vector3(0.39,0.48,17.87),Vector3(side*14.67,0.07,0),frame])
		steelwork.append([Vector3(0.49,0.12,17.91),Vector3(side*14.67,0.37,0),brass])
		markers.append([Vector3(0.09,0.16,4.72),Vector3(side*8.02,-0.31,3.62),violet])
		# Two longitudinal tower legs leave a service opening. The inner
		# assembly carries the clamp axles into the deep dock floor.
		var head_y := 18.10 if side < 0.0 else 15.70
		steelwork.append([Vector3(4.92,0.86,7.46),Vector3(side*12.91,0.26,-2.25),recess])
		for z: float in [-5.05,1.36]:
			steelwork.append([Vector3(2.34,0.85,2.44),Vector3(side*13.16,0.82,z),steel])
			_strut(steelwork,Vector3(side*13.26,1.0,z),Vector3(side*11.96,head_y,z),1.72,2.09,frame)
			_strut(steelwork,Vector3(side*13.81,1.4,z),Vector3(side*12.65,head_y-0.26,z),0.40,1.85,armor)
			for height: float in [2.64,6.36,10.10,13.82]:
				var x := side*lerpf(13.26,11.96,(height-1.0)/(head_y-1.0))
				steelwork.append([Vector3(1.92,0.29,2.22),Vector3(x,height,z),steel])
		for height: float in [3.2,9.30,head_y-0.63]:
			steelwork.append([Vector3(1.44,0.61,6.62),Vector3(side*12.73,height,-1.84),armor])
		_strut(steelwork,Vector3(side*13.12,3.10,-4.94),Vector3(side*12.66,9.34,1.40),0.67,0.84,armor)
		_strut(steelwork,Vector3(side*12.66,9.36,1.41),Vector3(side*12.06,head_y-0.78,-4.98),0.75,0.79,armor)
		steelwork.append([Vector3(3.92,0.62,7.74),Vector3(side*12.06,head_y,-1.87),armor])
		steelwork.append([Vector3(3.53,0.22,7.90),Vector3(side*12.06,head_y+0.33,-1.87),steel])
		steelwork.append([Vector3(0.72,0.48,6.41),Vector3(side*10.39,head_y-0.42,-1.87),frame])
		for z: float in [-4.19,-2.07,0.05,1.70]:
			markers.append([Vector3(0.12,0.17,0.86),Vector3(side*10.00,head_y-0.38,z),amber])
		# The angled maintenance platforms carry cable reels and terminate
		# in faced stops at the road-facing end of the cradle.
		steelwork.append([Vector3(3.35,0.47,7.65),Vector3(side*10.18,3.04,3.76),armor])
		steelwork.append([Vector3(0.49,0.71,7.81),Vector3(side*8.56,3.08,3.76),frame])
		for z: float in [0.25,3.67,7.31]:
			_strut(steelwork,Vector3(side*12.11,-0.28,z),Vector3(side*8.68,2.78,z),0.64,0.80,frame)
			steelwork.append([Vector3(0.54,0.91,0.47),Vector3(side*8.68,3.48,z),steel])
			markers.append([Vector3(0.16,0.19,0.63),Vector3(side*8.30,2.96,z),amber])
		steelwork.append([Vector3(2.42,0.66,0.42),Vector3(side*10.08,3.48,7.48),recess])
		for lug in range(4):
			steelwork.append([Vector3(0.25,0.18,0.07),Vector3(side*(9.30+float(lug)*0.43),3.53,7.72),brass])
		var mast_x := 13.70 if side < 0.0 else 13.0
		var mast_h := 2.16 if side < 0.0 else 3.62
		steelwork.append([Vector3(0.30,mast_h,0.30),Vector3(side*mast_x,head_y+0.30+mast_h*0.5,-4.81),steel])
		markers.append([Vector3(0.39,0.24,0.39),Vector3(side*mast_x,head_y+0.33+mast_h,-4.81),amber])
		for height: float in [6.2,11.5]:
			steelwork.append([Vector3(2.85,0.98,1.41),Vector3(side*11.67,height+0.30,-2.66),armor])
			steelwork.append([Vector3(1.38,2.37,0.76),Vector3(side*10.58,height+0.35,-2.11),frame])
			steelwork.append([Vector3(0.27,2.0,0.86),Vector3(side*10.05,height+0.35,-2.11),brass])
			steelwork.append([Vector3(1.17,0.16,0.79),Vector3(side*10.61,height+1.29,-2.11),steel])
			markers.append([Vector3(0.34,0.17,0.09),Vector3(side*10.63,height+1.33,-1.65),amber])
	for index in range(4):
		var side := -1.0 if index%2 == 0 else 1.0
		var height := 6.2+float(index >> 1)*5.3
		var clamp_arm := _pivot(room,"BerthClamp",Vector3(side*10.4,height,-1.5))
		var arm: Array = [
			[Vector3(1.28,1.22,1.13),Vector3(-side*0.29,0,0),frame],
			[Vector3(1.07,0.84,1.28),Vector3(-side*0.54,0.05,0),steel],
			[Vector3(3.49,0.59,0.88),Vector3(-side*2.31,0.05,0),armor],
			[Vector3(2.54,0.20,0.98),Vector3(-side*2.37,-0.27,0),recess],
			[Vector3(0.64,1.20,1.02),Vector3(-side*4.18,0.08,0),frame],
			[Vector3(0.23,0.87,1.12),Vector3(-side*4.40,0.13,0),brass],
			[Vector3(0.54,0.22,1.04),Vector3(-side*3.93,0.70,0),steel]
		]
		for joint in range(3):
			arm.append([Vector3(0.16,0.69,0.89),Vector3(-side*(1.46+float(joint)*0.79),0.02,0),steel])
		_boxes(clamp_arm,"ArmHousingAndGrip",arm)
		_boxes(clamp_arm,"ArmGuidance",[[Vector3(1.65,0.11,0.10),Vector3(-side*2.08,0.08,0.47),violet],
			[Vector3(0.27,0.17,0.09),Vector3(-side*4.22,0.36,0.55),amber]],true)
		_orbital_clamps.append(clamp_arm)
	_boxes(room,"DryDockSteelwork",steelwork)
	_boxes(room,"DryDockServiceMarkers",markers,true)
