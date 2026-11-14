extends RefCounted

const WEAPONS := [
	{"id":"factory","name":"工铸太刀","description":"点按拔刀，长按自由斩切","price":0,"color":Color("91d1dc"),
		"controls":["左键轻击，长按拖动刀刃","右键架刀，精准弹反可提速"],
		"touch_controls":["点按普攻，按住斩击可拖动刀刃","按住振刀挡一击，精准弹反可提速"],
		"face":Color(0.62,0.67,0.70),"bevel":Color(0.84,0.90,0.93),"spine":Color(0.12,0.15,0.17),
		"sheath":Color(0.13,0.024,0.020),"wrap":Color(0.074,0.088,0.091),"fittings":Color(0.48,0.25,0.105),
		"edge":Color(0.35,0.68,0.75)},
	{"id":"dual","name":"双手剑","description":"左右独立出剑，合键交叉架刀","price":160,"color":Color("91c7e6"),
		"controls":["左键出左剑，右键出右剑","单键长按拖切，双键交叉格挡"],
		"touch_controls":["点按左剑或右剑，长按并拖动可斩切","双剑同时按下，或按住格挡"],
		"face":Color("9aa7b4"),"bevel":Color("edf0e8"),"spine":Color("252e36"),"sheath":Color("263139"),
		"wrap":Color("303434"),"fittings":Color("566e80"),"edge":Color("b7e5f5")},
	{"id":"long","name":"长刃太刀","description":"超长刀身，大幅拔刀与自由斩切","price":260,"color":Color("afc9df"),
		"controls":["左键拔刀，长按拖动长刃","右键架刀，精准弹反可提速"],
		"touch_controls":["点按普攻，按住斩击可拖动长刃","按住振刀挡一击，精准弹反可提速"],
		"face":Color("758795"),"bevel":Color("e4edf3"),"spine":Color("26313b"),"sheath":Color("22262e"),
		"wrap":Color("30313d"),"fittings":Color("b1a07a"),"edge":Color("94c7f3")},
	{"id":"heavy","name":"重斩剑","description":"用奔跑速度换厚甲深斩","price":230,"color":Color("f0ac6c"),
		"controls":["左键蓄力，拖鼠标预览刀线，松开重斩","重斩耗速，满蓄释放剑气，右键架挡"],
		"touch_controls":["按住蓄力，拖动预览刀线，松开重斩","重斩耗速，满蓄释放剑气，按住格挡"],
		"face":Color("807c75"),"bevel":Color("d5c6b4"),"spine":Color("514749"),"sheath":Color("392c23"),
		"wrap":Color("382e2b"),"fittings":Color("ad7143"),"edge":Color("f0ac6c")},
]

const SKINS := [
	{"id":"red_scabbard","family":"factory","name":"赤鞘·高频型","short_name":"赤鞘","description":"机械锁扣弹开，刀刃滑出赤色厚鞘","price":170,"color":Color("fa6253"),
		"face":Color("626371"),"bevel":Color("d9e1e5"),"spine":Color("29262a"),"sheath":Color("8a2425"),
		"wrap":Color("2b292b"),"fittings":Color("7c8186"),"edge":Color("fa6253")},
	{"id":"plasma","family":"dual","name":"双极·等离子刃","short_name":"双极","description":"冰蓝与暖金双刃点亮，交叉格挡","price":190,"color":Color("55cfff"),
		"face":Color("566675"),"bevel":Color("e7f6fb"),"spine":Color("25313f"),"sheath":Color("27323b"),
		"wrap":Color("2e3035"),"fittings":Color("738998"),"edge":Color("55cfff"),"secondary":Color("ffbd63")},
	{"id":"yamato","family":"long","name":"断界·长鞘","short_name":"断界","description":"白柄黑鞘，长银刃出鞘时亮起冷光","price":220,"color":Color("c9edff"),
		"face":Color("939eb1"),"bevel":Color("ecf6ff"),"spine":Color("35426b"),"sheath":Color("141923"),
		"wrap":Color("e8dcbc"),"fittings":Color("b59a62"),"edge":Color("a2d8ff")},
	{"id":"maul","family":"long","name":"赤双曜","short_name":"赤曜","description":"黑钢双向握柄，两端伸出猩红光刃","price":200,"color":Color("ff5550"),
		"face":Color("373e47"),"bevel":Color("ffe0d7"),"spine":Color("181d25"),"sheath":Color("202127"),
		"wrap":Color("272930"),"fittings":Color("89919a"),"edge":Color("ff382f")},
	{"id":"bridge","family":"heavy","name":"桥梁断刃","short_name":"断桥","description":"铆接桥梁钢板，蓄力时逐段压紧","price":175,"color":Color("edac62"),
		"face":Color("7d8889"),"bevel":Color("d9e0d5"),"spine":Color("414b50"),"sheath":Color("42362d"),
		"wrap":Color("3f3430"),"fittings":Color("bc8249"),"edge":Color("edac62")},
	{"id":"vermilion","family":"factory","name":"朱棱","short_name":"朱棱","description":"铜骨铆接护手，赤漆多棱鞘与外露护条","price":120,"color":Color("e76850"),
		"face":Color(0.56,0.22,0.16),"bevel":Color(1.0,0.68,0.44),"spine":Color(0.20,0.045,0.04),
		"sheath":Color(0.25,0.027,0.031),"wrap":Color(0.18,0.036,0.041),"fittings":Color(0.72,0.39,0.13),
		"edge":Color(1.0,0.42,0.20)},
	{"id":"frost","family":"factory","name":"霜脊","short_name":"霜脊","description":"冰白阶梯刃脊，深蓝开窗刀鞘","price":260,"color":Color("79c6fa"),
		"face":Color(0.31,0.54,0.77),"bevel":Color(0.74,0.92,1.0),"spine":Color(0.055,0.10,0.23),
		"sheath":Color(0.038,0.10,0.21),"wrap":Color(0.053,0.12,0.19),"fittings":Color(0.55,0.65,0.76),
		"edge":Color(0.36,0.70,1.0)},
]

const SAVE_PATH := "user://weapon_shop.cfg"
var currency := 0
var equipped := "factory"
var owned: Array[String] = ["factory"]
var owned_skins: Array[String] = []
var equipped_skins: Dictionary = {}
var _path := ""
var _dirty := false
var _catalog_cache: Array[Dictionary] = []


func load_profile(path: String) -> void:
	_path = path
	currency = 0
	equipped = "factory"
	owned.assign(["factory"])
	owned_skins.clear()
	equipped_skins.clear()
	_dirty = false
	_catalog_cache = []
	if _path.is_empty(): return
	var save := ConfigFile.new()
	if save.load(_path) != OK: return
	currency = maxi(0,int(save.get_value("shop","currency",0)))
	var saved: Variant = save.get_value("shop","owned",[])
	var legacy_wheel: bool = saved is Array and "wheel" in saved
	if saved is Array:
		for weapon in WEAPONS:
			if (weapon.id in saved or (weapon.id == "long" and legacy_wheel)) and weapon.id not in owned:
				owned.append(weapon.id)
	var saved_skins: Variant = save.get_value("shop","owned_skins",[])
	var legacy_grid: bool = legacy_wheel and saved_skins is Array and "grid" in saved_skins
	for skin in SKINS:
		if skin.family not in owned: continue
		if (saved_skins is Array and skin.id in saved_skins) or (skin.id == "maul" and legacy_grid):
			owned_skins.append(skin.id)
		elif skin.id in ["vermilion","frost"] and saved is Array and skin.id in saved:
			owned_skins.append(skin.id)
	var preferences: Variant = save.get_value("shop","equipped_skins",{})
	if preferences is Dictionary:
		for skin_id in owned_skins:
			var skin := _find_skin(skin_id)
			if preferences.get(skin.family) == skin_id:
				equipped_skins[skin.family] = skin_id
		if legacy_grid and not equipped_skins.has("long") and preferences.get("wheel") == "grid":
			equipped_skins.long = "maul"
	var selected := str(save.get_value("shop","equipped","factory"))
	if selected == "wheel" and legacy_wheel: selected = "long"
	if selected in owned:
		equipped = selected
	elif selected in ["vermilion","frost"] and selected in owned_skins:
		equipped_skins.factory = selected
	_dirty = legacy_wheel


func catalog() -> Array[Dictionary]:
	if not _catalog_cache.is_empty(): return _catalog_cache
	for weapon in WEAPONS:
		var family: String = weapon.id
		var selected := str(equipped_skins.get(family,family))
		var row := _finish(weapon,family)
		row.merge({"owned":family in owned,"equipped":family == equipped,"selected_skin":selected})
		var base_skin := _finish(weapon,family)
		base_skin.merge({"short_name":"原装","owned":family in owned,"equipped":family == equipped and selected == family})
		var skins: Array[Dictionary] = [base_skin]
		for skin in SKINS:
			if skin.family != family: continue
			var entry := _finish(skin,family)
			entry.merge({"owned":skin.id in owned_skins,"equipped":family == equipped and selected == skin.id})
			skins.append(entry)
		row.skins = skins
		_catalog_cache.append(row)
	return _catalog_cache


func current_weapon() -> Dictionary:
	return preview_weapon(str(equipped_skins.get(equipped,equipped)))


func preview_weapon(id: String) -> Dictionary:
	var skin := _find_skin(id)
	if not skin.is_empty(): return _finish(skin,str(skin.family))
	var weapon := _find_weapon(id)
	return _finish(weapon,id) if not weapon.is_empty() else {}


func _finish(row: Dictionary, family: String) -> Dictionary:
	var finish := row.duplicate()
	finish.family = family
	finish.skin_id = row.id
	if not finish.has("controls"):
		var weapon := _find_weapon(family)
		finish.controls = weapon.controls
		finish.touch_controls = weapon.touch_controls
	return finish


func _find_weapon(id: String) -> Dictionary:
	for weapon in WEAPONS:
		if weapon.id == id: return weapon
	return {}


func _find_skin(id: String) -> Dictionary:
	for skin in SKINS:
		if skin.id == id: return skin
	return {}


func buy_or_equip(id: String) -> Error:
	var weapon := _find_weapon(id)
	if weapon.is_empty(): return ERR_INVALID_PARAMETER
	if id == equipped: return OK
	var price := int(weapon.price) if id not in owned else 0
	if price > currency: return ERR_UNAVAILABLE
	var next_owned := owned.duplicate()
	if id not in owned: next_owned.append(id)
	return _apply_purchase(price,next_owned,id,owned_skins,equipped_skins)


func buy_or_equip_skin(id: String) -> Error:
	var finish := preview_weapon(id)
	if finish.is_empty(): return ERR_INVALID_PARAMETER
	var family: String = finish.family
	if family not in owned: return ERR_LOCKED
	if family == equipped and id == equipped_skins.get(family,family): return OK
	var is_base := id == family
	var price := int(finish.price) if not is_base and id not in owned_skins else 0
	if price > currency: return ERR_UNAVAILABLE
	var next_skins := owned_skins.duplicate()
	if not is_base and id not in owned_skins: next_skins.append(id)
	var next_selection := equipped_skins.duplicate()
	if is_base:
		next_selection.erase(family)
	else:
		next_selection[family] = id
	return _apply_purchase(price,owned,family,next_skins,next_selection)


func _apply_purchase(price: int, next_owned: Array[String], family: String, next_skins: Array[String], selection: Dictionary) -> Error:
	var error := _save(currency-price,next_owned,family,next_skins,selection)
	if error != OK: return error
	currency -= price
	equipped = family
	owned = next_owned
	owned_skins = next_skins
	equipped_skins = selection
	_catalog_cache = []
	_dirty = false
	return OK


func earn(amount: int) -> void:
	if amount <= 0: return
	currency += amount
	_dirty = true


func flush() -> Error:
	if not _dirty: return OK
	var error := _save(currency,owned,equipped,owned_skins,equipped_skins)
	if error == OK: _dirty = false
	return error


func _save(balance: int, unlocked: Array[String], weapon: String, skins: Array[String], selection: Dictionary) -> Error:
	if _path.is_empty(): return OK
	var save := ConfigFile.new()
	save.set_value("shop","currency",balance)
	save.set_value("shop","owned",unlocked)
	save.set_value("shop","equipped",weapon)
	save.set_value("shop","owned_skins",skins)
	save.set_value("shop","equipped_skins",selection)
	var temporary := _path+".tmp"
	var error := save.save(temporary)
	if error != OK: return error
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(_path))
