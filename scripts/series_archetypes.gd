extends RefCounted
const Ink = preload("res://scripts/series_ink_rebuilt.gd")
const Cyber = preload("res://scripts/series_cyber_rebuilt.gd")
const Sea = preload("res://scripts/series_sea_rebuilt.gd")
const Empire = preload("res://scripts/series_empire_rebuilt.gd")

# All visible structure, weapons, armor and hinges below are occupied cells.
# Special bits identify real connected supports; they never represent health.
const KINDS := ["ink_swordsman","ink_spear","ink_talisman","ink_crane","ink_master","cyber_breacher","cyber_riot","cyber_sniper","cyber_drone","cyber_captain","cyber_flanker","cyber_suppressor","cyber_spotter","cyber_helicopter","cyber_tank","cyber_gunship","sea_skimmer","sea_crab","sea_eel","sea_ray","sea_leviathan","empire_walker","empire_lancer","empire_sentinel","empire_fighter","empire_dreadnought"]
const BOSSES := ["ink_master","cyber_captain","cyber_flanker","cyber_suppressor","cyber_spotter","cyber_helicopter","cyber_tank","cyber_gunship","sea_leviathan","empire_dreadnought"]
const FLYING := ["ink_crane","cyber_drone","cyber_helicopter","cyber_gunship","sea_eel","sea_ray","empire_fighter","empire_dreadnought"]
const HEAVY := ["ink_spear","cyber_riot","sea_crab","empire_walker"]
const RANGED := ["ink_talisman","cyber_sniper","sea_eel","empire_sentinel"]
const SUPPORT := ["ink_crane","cyber_drone","sea_ray","empire_fighter"]
const CORE_TAGS := [8, 16]
const MOUNT_TAGS := [32, 64]
const LABELS := ["墨刃客","折锋长枪","朱符使","纸鹤机关","朱印宗师","破门突击手","折盾镇暴兵","棱镜狙击手","蛛翼侦察机","中继队长","侧击双刃","重火压制手","观测标定手","断尾直升机","裂履主战坦克","双舱炮艇","掠浪鳍刃","礁壳重蟹","电棘海鳗","翼潮鳐机","四足潮汐巨兽","轨道重步机","星矛突骑","棱盾哨卫","折翼战机","王冠无畏舰"]
static var _authored_part_maps: Dictionary = {}
static var _layout_cache: Dictionary = {}
static var _info_cache: Dictionary = {}
static var _boss_modules_cache: Dictionary = {}

static func supports(kind: String) -> bool:
	return kind in KINDS

static func info(kind: String) -> Dictionary:
	if _info_cache.has(kind): return _info_cache[kind]
	var i := KINDS.find(kind)
	if i < 0: return {}
	var series := 2 if kind.begins_with("ink_") else (3 if kind.begins_with("cyber_") else (4 if kind.begins_with("sea_") else 5))
	var role := "heavy" if kind in HEAVY else ("ranged" if kind in RANGED else ("support" if kind in SUPPORT else "melee"))
	if kind in BOSSES: role = "ranged" if kind in ["cyber_suppressor","cyber_spotter","cyber_helicopter","cyber_tank","cyber_gunship","empire_dreadnought"] else "heavy"
	_info_cache[kind] = {"series":series,"role":role,"flying":kind in FLYING,"boss":kind in BOSSES,"armored":kind in BOSSES or kind in HEAVY,"label":LABELS[i],"entry_duration":3.6 if kind in BOSSES else 2.0,"behavior":kind,"approach_speed":0.65 if kind in HEAVY else 1.0,"shot_kind":"missile" if kind in ["cyber_helicopter","cyber_gunship","empire_dreadnought"] else "bolt"}
	return _info_cache[kind]

static func _library(kind: String) -> Script:
	if kind.begins_with("ink_"): return Ink
	if kind.begins_with("cyber_"): return Cyber
	if kind.begins_with("sea_"): return Sea
	return Empire

static func dimensions(kind: String) -> Dictionary:
	return _library(kind).dimensions(kind)

static func palette(kind: String) -> Array[Color]:
	if kind.begins_with("ink_"):
		return [Color.TRANSPARENT,Color("e7e3d9"),Color("29292b"),Color("ad292b"),Color("f14b43"),Color("686569"),Color("e4dfd6"),Color("111013"),Color("878381"),Color("aaa5a1"),Color("eb5b5a")]
	if kind.begins_with("cyber_"):
		return [Color.TRANSPARENT,Color("687780"),Color("222b35"),Color("a63b42"),Color("69d9e6"),Color("424f5b"),Color("a7bec8"),Color("0d131a"),Color("85714d"),Color("747d85"),Color("ffa43e")]
	if kind.begins_with("sea_"):
		return [Color.TRANSPARENT,Color("bacfca"),Color("38696d"),Color("d47358"),Color("60f1c8"),Color("4d7b88"),Color("d0f2e3"),Color("112d3a"),Color("bb956a"),Color("73a1a4"),Color("ffd98a")]
	return [Color.TRANSPARENT,Color("c9ccd8"),Color("30334e"),Color("8a456f"),Color("b0b0ff"),Color("626481"),Color("f3e5b4"),Color("151529"),Color("bd9754"),Color("8d92af"),Color("ffbe72")]

static func build(enemy) -> void:
	enemy._series_authored_parts.resize(enemy._voxels.size())
	enemy._series_authored_parts.fill(0)
	_library(str(enemy.enemy_kind)).build(enemy,load("res://scripts/series_archetypes.gd"))
	_authored_part_maps[enemy.enemy_kind] = {"parts":enemy._series_authored_parts,"dimensions":enemy._dimensions,"cell":enemy._cell}

static func classify_part(kind: String, point: Vector3) -> int:
	if not _authored_part_maps.has(kind): return 0
	var layout: Dictionary = _authored_part_maps[kind]
	var d: Vector3i = layout.dimensions
	var cell: float = layout.cell
	var p := Vector3i((point/cell+Vector3(float(d.x)*0.5,0,float(d.z)*0.5)).floor())
	if p.x < 0 or p.y < 0 or p.z < 0 or p.x >= d.x or p.y >= d.y or p.z >= d.z: return 0
	return int(layout.parts[p.x+d.x*(p.y+d.y*p.z)])

static func emitters(kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Dictionary in _layout(kind).get("emitters",[]): result.append(item)
	return result

static func emitter_intact(enemy, part: int) -> bool:
	for item: Dictionary in emitters(enemy.enemy_kind):
		if int(item.part) != part: continue
		var target: Vector3 = item.point
		var radius: float = float(item.get("radius",0.18))
		for index: int in enemy._live_indices:
			if enemy._voxels[index] > 0 and enemy._part_ids[index] == part and enemy._cell_points[index].distance_squared_to(target) < radius*radius: return true
	return false

static func sample_entry(kind: String, p: float, lane: int = 0) -> Dictionary:
	return _library(kind).entry(kind,clampf(p,0,1),lane)

static func sample_pose(kind: String, action: String, phase: float, age: float, lane: int, integrity: Dictionary) -> Dictionary:
	return _library(kind).pose(kind,action,phase,age,lane,integrity)

static func _layout(kind: String) -> Dictionary:
	if not _layout_cache.has(kind): _layout_cache[kind] = _library(kind).layout(kind)
	return _layout_cache[kind]

static func integrity_layout(kind: String) -> Dictionary:
	return _layout(kind)

static func boss_modules(kind: String) -> Array:
	if kind not in BOSSES: return []
	if not _boss_modules_cache.has(kind): _boss_modules_cache[kind] = _library(kind).boss_modules(kind)
	return _boss_modules_cache[kind]

static func powered_boss_modules(flags: int) -> int:
	var powered := 0
	for index in range(CORE_TAGS.size()):
		var pair: int = CORE_TAGS[index] | MOUNT_TAGS[index]
		if flags & pair == pair: powered |= 1 << index
	return powered

static func _pivot(at: Vector3, angles: Vector3, offset: Vector3 = Vector3.ZERO) -> Transform3D:
	var basis := Basis.from_euler(angles)
	return Transform3D(basis,at-basis*at+offset)

static func _box(e, center: Vector3, size: Vector3, material: int, part: int = 0) -> void:
	_primitive(e,center-size*0.5,center+size*0.5,material,part,0,center,size)

static func _depth_wedge(e, center: Vector3, size: Vector3, front_scale: float, material: int, part: int = 0) -> void:
	_primitive(e,center-size*0.5,center+size*0.5,material,part,4,center,size,front_scale)

static func _ellipsoid(e, center: Vector3, size: Vector3, material: int, part: int = 0) -> void:
	_primitive(e,center-size*0.5,center+size*0.5,material,part,1,center,size)

static func _ring_cells(e, center: Vector3, outer: float, inner: float, half_height: float, material: int, part: int, vertical: bool = false) -> void:
	var span := Vector3(outer,outer,half_height) if vertical else Vector3(outer,half_height,outer)
	var limits: Array[Vector3i] = e._slasher_grid_bounds(center-span,center+span)
	for z in range(limits[0].z,limits[1].z+1):
		for y in range(limits[0].y,limits[1].y+1):
			for x in range(limits[0].x,limits[1].x+1):
				var d: Vector3 = e._point(x,y,z)-center
				var radial := Vector2(d.x,d.y).length_squared() if vertical else Vector2(d.x,d.z).length_squared()
				if radial < inner*inner or radial > outer*outer: continue
				var index: int = e._index(x,y,z)
				e._voxels[index] = material
				e._series_authored_parts[index] = part

static func _capacitor(e, center: Vector3, part: int, s: float) -> void:
	_ellipsoid(e,center,Vector3(0.46,0.62,0.46)*s,4,part)
	for ring in [-1.0,1.0]: _ring_cells(e,center+Vector3(0,ring*0.24,0)*s,0.43*s,0.19*s,0.075*s,8,part)
	for rail in range(4):
		var angle := float(rail)*TAU/4.0
		var offset := Vector3(sin(angle)*0.28,0,cos(angle)*0.28)*s
		_rod(e,center+offset-Vector3(0,0.29*s,0),center+offset+Vector3(0,0.29*s,0),0.10*s,8,part)

static func _rod(e, a: Vector3, b: Vector3, radius: float, material: int, part: int = 0) -> void:
	_primitive(e,a.min(b)-Vector3.ONE*radius,a.max(b)+Vector3.ONE*radius,material,part,2,a,b,radius)

static func _taper(e, center: Vector3, size: Vector3, top: Vector2, top_width: float, material: int, part: int = 0) -> void:
	var low := center-size*0.5
	var high := center+size*0.5
	low.x = minf(low.x,top.x-top_width*0.5)
	high.x = maxf(high.x,top.x+top_width*0.5)
	low.z = minf(low.z,top.y-size.z*0.5)
	high.z = maxf(high.z,top.y+size.z*0.5)
	_primitive(e,low,high,material,part,3,center,size,top_width,top)

static func _primitive(e, low: Vector3, high: Vector3, material: int, part: int, mode: int, a: Vector3, b: Vector3, radius: float = 0.0, top: Vector2 = Vector2.ZERO) -> void:
	var bounds: Array[Vector3i] = e._slasher_grid_bounds(low,high)
	for z in range(bounds[0].z,bounds[1].z+1):
		for y in range(bounds[0].y,bounds[1].y+1):
			for x in range(bounds[0].x,bounds[1].x+1):
				var point: Vector3 = e._point(x,y,z)
				if mode == 1 and ((point-a)/(b*0.5)).length_squared() > 1.0: continue
				if mode == 2:
					var line := b-a
					var t := clampf((point-a).dot(line)/maxf(line.length_squared(),0.00001),0.0,1.0)
					if point.distance_squared_to(a+line*t) > radius*radius: continue
				if mode == 3:
					var t := clampf((point.y-low.y)/maxf(high.y-low.y,0.001),0.0,1.0)
					var middle := Vector2(a.x,a.z).lerp(top,t)
					if absf(point.x-middle.x) > lerpf(b.x,radius,t)*0.5 or absf(point.z-middle.y) > b.z*0.5: continue
				if mode == 4:
					var t := clampf((point.z-low.z)/maxf(high.z-low.z,0.001),0.0,1.0)
					var width := lerpf(1.0,radius,t)
					var delta := (point-a).abs()
					var half := b*Vector3(width,width,1.0)*0.5
					if delta.x > half.x or delta.y > half.y: continue
					var bevel := minf(b.x,b.y)*0.13
					if maxf(delta.x-half.x+bevel,0.0)+maxf(delta.y-half.y+bevel,0.0) > bevel: continue
				var index: int = e._index(x,y,z)
				e._voxels[index] = material
				e._series_authored_parts[index] = part

static func _humanoid(e, scale: float, armor: int, joints: int) -> void:
	_box(e,Vector3(0,1.65,0)*scale,Vector3(0.94,1.05,0.50)*scale,armor)
	_box(e,Vector3(0,1.12,-0.02)*scale,Vector3(0.65,0.37,0.45)*scale,joints)
	_box(e,Vector3(0,2.13,0)*scale,Vector3(0.28,0.25,0.29)*scale,joints)
	_box(e,Vector3(0,2.40,0.03)*scale,Vector3(0.48,0.47,0.45)*scale,armor)
	_box(e,Vector3(0,2.41,0.26)*scale,Vector3(0.35,0.09,0.08)*scale,4)
	for side in [-1.0,1.0]:
		var part := 1 if side < 0 else 2
		_box(e,Vector3(side*0.55,1.94,0)*scale,Vector3(0.36,0.56,0.46)*scale,armor,part)
		_rod(e,Vector3(side*0.59,1.80,0)*scale,Vector3(side*0.73,1.27,0.13)*scale,0.135*scale,joints,part)
		_box(e,Vector3(side*0.73,1.30,0.13)*scale,Vector3(0.30,0.37,0.33)*scale,armor,part)
		_box(e,Vector3(side*0.23,0.66,0)*scale,Vector3(0.30,1.0,0.38)*scale,armor,3 if side < 0 else 4)
		_box(e,Vector3(side*0.27,0.16,0.12)*scale,Vector3(0.40,0.28,0.68)*scale,joints,5 if side < 0 else 6)

static func _finish(e, core: Vector3, anchor: Vector3, head: Vector3) -> void:
	e._core_point = core
	# Tag only existing material; these calls never manufacture a hidden bridge.
	var tag_cell: float = 0.11 if e.enemy_kind in ["cyber_helicopter","cyber_gunship"] else e._cell
	e._slasher_tags(core,Vector3.ONE*maxf(tag_cell*2.5,0.20),2)
	e._slasher_tags(anchor,Vector3.ONE*maxf(tag_cell*3.0,0.23),4)
	e._slasher_tags(head,Vector3.ONE*maxf(tag_cell*2.5,0.20),1)

static func _finish_boss(e, aim: Vector3, head: Vector3, modules: Array) -> void:
	e._core_point = aim
	e._slasher_tags(head, Vector3.ONE * maxf(e._cell * 2.5, 0.20), 1)
	for i in range(modules.size()):
		var module: Dictionary = modules[i]
		var tag_size: float = module.tag_size
		e._slasher_tags(module.core, Vector3.ONE * tag_size, 2 | CORE_TAGS[i])
		e._slasher_tags(module.mount, Vector3.ONE * tag_size, 4 | MOUNT_TAGS[i])

static func _supports(e, points: Array, radius: float) -> void:
	for i in range(points.size()):
		e._slasher_tags(points[i],Vector3.ONE*radius*2.0,8<<i)

