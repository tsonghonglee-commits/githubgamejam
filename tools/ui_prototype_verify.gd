extends SceneTree
## Real parsed-input UI fixtures. World/ending injections are labelled layout
## checks; this is not normal-combat, performance or subjective UI approval.

const REFERENCE := Vector2(1280,720)
const RUNTIME_PATHS := ["res://scenes/main.tscn","res://scripts/main.gd","res://scripts/prototype_hud.gd"]
var game
var output_path := ""
var require_packed := false
var checks: Array = []
var observations: Dictionary = {}
var failures := 0
var actions: Array = []
var pointer := Vector2(1200,40)
var settings_path := ""
var original_display: Dictionary = {}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output_path = argument.trim_prefix("--output=")
		elif argument == "--require-packed": require_packed = true
	if output_path.is_empty(): output_path = ProjectSettings.globalize_path("res://builds/ui-review-v096/verify.json")
	call_deferred("_run")


func expect(condition: bool, label: String, detail: Dictionary = {}) -> void:
	checks.append({"label":label,"passed":condition,"detail":_plain(detail)})
	if condition: print("PASS: ",label)
	else:
		failures += 1
		push_error("UI FAIL: "+label)


func _plain(value: Variant) -> Variant:
	if value is Vector2: return [value.x,value.y]
	if value is Vector2i: return [value.x,value.y]
	if value is Rect2: return {"position":_plain(value.position),"size":_plain(value.size)}
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[str(key)] = _plain(value[key])
		return result
	if value is Array or value is PackedVector2Array:
		var result: Array = []
		for item in value: result.append(_plain(item))
		return result
	return value


func _manifest() -> Dictionary:
	var result: Dictionary = {}
	for path in RUNTIME_PATHS:
		var runtime: String = path
		var config := ConfigFile.new()
		if FileAccess.file_exists(path+".remap") and config.load(path+".remap")==OK:
			runtime = str(config.get_value("remap","path",path))
		result[path] = {"raw_exists":FileAccess.file_exists(path),"runtime_path":runtime,"sha256":FileAccess.get_sha256(runtime)}
	return result


func _on_action(action: StringName, value: Variant) -> void:
	actions.append({"action":str(action),"value":_plain(value)})


func _debug() -> Dictionary:
	return game.hud.get_ui_debug_state()


func _buttons() -> Array:
	return _debug().get("buttons",[])


func _button(action: String) -> Dictionary:
	for row: Dictionary in _buttons():
		if str(row.get("action",row.get("id",""))) == action or str(row.get("id","")) == action:
			return row
	return {}


func _rect(action: String) -> Rect2:
	var row := _button(action)
	if row.is_empty():
		push_error("UI fixture cannot find button: "+action+" page="+str(_debug().get("page","")))
		return Rect2(-500,-500,1,1)
	return Rect2(row.rect)


func _canvas_point(reference: Vector2) -> Vector2:
	return reference*game.hud.size/REFERENCE


func _window_point(reference: Vector2) -> Vector2:
	return game.get_viewport().get_final_transform()*_canvas_point(reference)


func _motion(to: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = _window_point(to)
	event.global_position = event.position
	event.relative = _window_point(to)-_window_point(pointer)
	event.screen_relative = event.relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	pointer = to


func _mouse(pressed: bool, at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = _window_point(at)
	event.global_position = event.position
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	pointer = at


func _key(code: Key, pressed: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	if pressed and not echo: _key(code,false)


func _step(delta: float = 1.0/60.0) -> void:
	game._process(delta)
	game.sword._process(delta)
	game.hud._process(delta)
	game._update_hud()


func _click(action: String) -> void:
	var point := _rect(action).get_center()
	_mouse(true,point)
	_step(0.035)
	_mouse(false,point)
	_step(0.20)


func _slice(action: String, hz: float = 60.0, duration: float = 0.35, reverse: bool = false, release: bool = true) -> void:
	var rect := _rect(action)
	var a := Vector2(rect.position.x-20,rect.get_center().y)
	var b := Vector2(rect.end.x+20,rect.get_center().y)
	if reverse:
		var old := a
		a = b
		b = old
	_motion(a)
	_mouse(true,a)
	var count := maxi(1,ceili(duration*hz))
	for index in range(1,count+1):
		_motion(a.lerp(b,float(index)/count))
		_step(1.0/hz)
	if release:
		_mouse(false,b)
		_step(0.20)


func _home() -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): _mouse(false,pointer)
	game.hud.cancel_menu_gesture()
	if game.state == "playing":
		_key(KEY_ESCAPE)
		_step(0.2)
	if str(_debug().get("page","home")) != "home":
		_key(KEY_ESCAPE)
		_step(0.2)
	if game.state != "menu":
		_click("menu")
		_step(0.2)
	for frame in range(90):
		if game.menu_prepared: break
		await process_frame
		if DisplayServer.get_name()!="headless": await RenderingServer.frame_post_draw
	game._update_hud()


func _setup() -> bool:
	original_display = {"mode":DisplayServer.window_get_mode(),"size":DisplayServer.window_get_size(),"vsync":DisplayServer.window_get_vsync_mode(),"msaa":root.msaa_3d,"volume_db":AudioServer.get_bus_volume_db(0),"muted":AudioServer.is_bus_mute(0)}
	settings_path = "user://qa_ui_prototype_%d.cfg"%Time.get_ticks_msec()
	game = load("res://scenes/main.tscn").instantiate()
	game.ui_settings_path = settings_path
	root.add_child(game)
	game.test_mode = true
	game.set_process(false)
	game.sword.set_process(false)
	game.hud.set_process(false)
	for frame in range(2): await process_frame
	for frame in range(90):
		if game.menu_prepared: break
		await process_frame
		if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	game.spawn_timer = 999.0
	game._update_hud()
	expect(game.menu_prepared,"actual menu preparation completes before UI fixtures")
	expect(game.hud.has_method("get_ui_debug_state") and game.hud.has_method("handle_menu_input"),"production HUD exposes observation / input interface")
	if failures>0: return false
	game.hud.ui_action.connect(_on_action)
	return true


func _verify_menu_inputs() -> void:
	var before := actions.size()
	_motion(Vector2(1240,35))
	_mouse(true,pointer)
	_mouse(false,pointer)
	_step(0.4)
	expect(game.state=="menu" and actions.size()==before,"empty-space click never starts a run")
	var controls := _rect("controls")
	_motion(controls.position-Vector2(20,0)+Vector2(0,controls.size.y*0.5))
	_motion(controls.end+Vector2(20,-controls.size.y*0.5))
	_step(0.4)
	expect(str(_debug().page)=="home" and actions.size()==before,"passive hover across an option never activates it")
	var edge := Vector2(controls.position.x+2,controls.get_center().y)
	_mouse(true,edge)
	_motion(edge-Vector2(8,0))
	_mouse(false,edge-Vector2(8,0))
	_step(0.4)
	expect(str(_debug().page)=="home","short drag outside cancels without click or valid slice")
	for hz in [32.0,60.0,240.0]:
		_slice("controls",hz)
		expect(str(_debug().page)=="controls" and game.state=="menu","slice controls works at %d Hz input cadence"%int(hz),{"ui":_debug()})
		_click("back")
		_step(0.2)
	var rect := _rect("controls")
	var a := Vector2(rect.position.x-35,rect.get_center().y)
	var b := Vector2(rect.end.x+35,rect.get_center().y)
	_motion(a)
	_mouse(true,a)
	_motion(b)
	_mouse(false,b)
	_step(0.2)
	expect(str(_debug().page)=="controls","single coalesced long motion segment crosses a real option")
	_click("back")
	_slice("controls",60,1.6,true)
	expect(str(_debug().page)=="controls","slow reverse-direction slicing remains usable")
	_click("back")
	rect = _rect("controls")
	a = Vector2(rect.position.x-25,rect.get_center().y-15)
	b = Vector2(rect.end.x+25,rect.get_center().y+15)
	_motion(a)
	_mouse(true,a)
	for index in range(1,20):
		var t := float(index)/19.0
		_motion(a.lerp(b,t)+Vector2(0,sin(t*TAU)*9.0))
		_step(1.0/60.0)
	_mouse(false,b)
	_step(0.2)
	expect(str(_debug().page)=="controls","curved pointer route activates the crossed option")
	_click("back")
	rect = _rect("controls")
	a = Vector2(rect.position.x-30,rect.get_center().y)
	b = Vector2(rect.end.x+30,rect.get_center().y)
	_motion(a)
	_mouse(true,a)
	_motion(Vector2(rect.position.x-2,a.y))
	_step(0.02)
	_mouse(false,b)
	_step(0.2)
	expect(str(_debug().page)=="controls","release event consumes its final pointer segment before clearing the stroke")
	_click("back")
	rect = _rect("settings")
	a = Vector2(rect.position.x-30,rect.get_center().y)
	b = Vector2(rect.end.x+30,rect.get_center().y)
	_motion(a)
	_mouse(true,a)
	_motion(b)
	_step(0.2)
	var settings_before: Variant = _plain(_debug())
	var action_count := int(_debug().get("action_count",-1))
	if str(_debug().page)=="settings":
		var toggle := _rect("vsync").get_center()
		_motion(toggle-Vector2(100,0))
		_motion(toggle+Vector2(100,0))
		_step(0.4)
	expect(str(_debug().page)=="settings" and int(_debug().get("action_count",-2))==action_count,"one held press cannot slice a second option after the page changes",{"before":settings_before,"after":_debug()})
	_mouse(false,pointer)
	_step(0.2)
	_click("back")
	var top := _rect("start")
	var bottom := _rect("quit_confirm")
	var vertical_low := Vector2(top.get_center().x,bottom.end.y+25)
	var vertical_high := Vector2(top.get_center().x,top.position.y-25)
	_motion(vertical_low)
	_mouse(true,vertical_low)
	_motion(vertical_high)
	_step(0.2)
	expect(str(_debug().page)=="quit_confirm" and str(_debug().last_action)=="quit_confirm" and game.state=="menu","single upward segment crossing four options activates the first physical entry, not array-order Start")
	_mouse(false,vertical_high)
	_key(KEY_ESCAPE)
	_step(0.2)
	_motion(vertical_high)
	_mouse(true,vertical_high)
	_motion(vertical_low)
	_step(0.2)
	expect(game.state=="playing" and int(game.combat_stats.get("light_slashes",0))==0,"reversed downward segment crosses Start first and starts exactly one clean run")
	_mouse(false,vertical_low)
	await _home()
	_key(KEY_TAB)
	var focus: int = int(_debug().focus)
	var selected_action: String = str(_buttons()[focus].action)
	var count_before_echo := int(_debug().action_count)
	_key(KEY_ENTER,true,true)
	_key(KEY_ENTER,false)
	_step(0.2)
	expect(int(_debug().action_count)==count_before_echo and str(_debug().page)=="home","echo Enter cannot activate the focused menu option")
	_key(KEY_ENTER)
	_step(0.25)
	expect(selected_action=="settings" and str(_debug().page)=="settings","Tab focuses settings and Enter activates that focused option")
	await _home()


func _verify_cancel_and_gameplay() -> void:
	var rect := _rect("settings")
	var a := Vector2(rect.position.x-25,rect.get_center().y)
	var b := Vector2(rect.end.x+25,rect.get_center().y)
	_motion(a)
	_mouse(true,a)
	_motion(b)
	_step(0.05)
	game._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_mouse(false,b)
	_step(0.4)
	expect(str(_debug().page)=="home" and str(_debug().get("pending_action",""))=="","focus loss cancels a queued split action before dispatch")
	game._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_slice("start",60,0.35,false,false)
	_step(0.2)
	var lights := int(game.combat_stats.get("light_slashes",0))
	var aim_before: Vector2 = game.aim_angles
	_motion(pointer+Vector2(120,60))
	_step(0.05)
	expect(game.state=="playing" and lights==0 and not game.left_down and not game.slashing,"menu start slice enters combat without an accidental light attack or held mode")
	expect(game.aim_angles==aim_before,"the remainder of a menu slice cannot whip the gameplay camera")
	_mouse(false,pointer)
	_step(0.05)
	_mouse(true,Vector2(640,360))
	_step(0.02)
	expect(int(game.combat_stats.get("light_slashes",0))==lights+1,"first independent gameplay click still attacks immediately")
	_mouse(false,pointer)
	_step(0.05)
	_key(KEY_ESCAPE)
	_step(0.2)
	var elapsed_before: float = game.elapsed
	_mouse(true,Vector2(1230,30))
	_mouse(false,pointer)
	_step(0.5)
	expect(game.state=="paused" and is_equal_approx(game.elapsed,elapsed_before),"pause freezes the world and a blank click cannot resume it")
	_slice("resume",60,0.35,false,false)
	_step(0.2)
	expect(game.state=="playing" and int(game.combat_stats.get("light_slashes",0))==lights+1 and not game.left_down,"resume slice does not leak into gameplay damage")
	_mouse(false,pointer)
	_step(0.1)
	_key(KEY_ESCAPE)
	_step(0.2)
	_click("menu")
	expect(game.state=="menu" and not game.left_down and not game.slashing,"pause return-to-menu is a real clean state transition")


func _verify_settings() -> void:
	_click("settings")
	expect(str(_debug().page)=="settings","settings page opens through a real button click")
	var slider: Rect2 = _debug().volume_slider_rect
	var volume_point := Vector2(slider.position.x+slider.size.x*0.25,slider.get_center().y)
	_mouse(true,volume_point)
	_mouse(false,volume_point)
	_step(0.5)
	expect(absf(float(game.ui_settings.volume)-0.25)<0.03,"volume slider changes the actual master setting")
	for action in ["vsync","msaa","fullscreen"]:
		if _button(action).is_empty():
			expect(false,"configured settings control exists: "+action)
			continue
		var value_before: bool = bool(game.ui_settings[action])
		_click(action)
		_step(0.1)
		await process_frame
		game._update_hud()
		expect(str(_debug().page)=="settings" and bool(game.ui_settings[action])!=value_before,"settings toggle changes the real preference and stays on its page: "+action)
		if action=="msaa": expect(root.msaa_3d==(Viewport.MSAA_4X if bool(game.ui_settings.msaa) else Viewport.MSAA_DISABLED),"anti-aliasing control applies the real viewport MSAA mode")
		elif DisplayServer.get_name()!="headless" and action=="vsync": expect(DisplayServer.window_get_vsync_mode()==(DisplayServer.VSYNC_ENABLED if bool(game.ui_settings.vsync) else DisplayServer.VSYNC_DISABLED),"VSync control applies the native display mode")
		elif DisplayServer.get_name()!="headless" and action=="fullscreen": expect(DisplayServer.window_get_mode()==(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(game.ui_settings.fullscreen) else DisplayServer.WINDOW_MODE_WINDOWED),"fullscreen control applies the native display mode")
	_step(0.5)
	expect(FileAccess.file_exists(settings_path),"real preference writes use the isolated QA file",{"path":settings_path})
	var saved := FileAccess.get_file_as_bytes(settings_path)
	var db_before := AudioServer.get_bus_volume_db(0)
	volume_point = Vector2(slider.position.x+slider.size.x*0.75,slider.get_center().y)
	_mouse(true,volume_point)
	_mouse(false,volume_point)
	_step(0.5)
	expect(absf(float(game.ui_settings.volume)-0.75)<0.03 and not is_equal_approx(AudioServer.get_bus_volume_db(0),db_before),"second volume gesture changes audio before persistence reload")
	var file := FileAccess.open(settings_path,FileAccess.WRITE)
	file.store_buffer(saved)
	file.close()
	game._load_ui_settings()
	game._update_hud()
	expect(is_equal_approx(AudioServer.get_bus_volume_db(0),db_before),"saved preferences load through production boot/settings implementation")
	_click("back")
	_click("quit_confirm")
	expect(str(_debug().page)=="quit_confirm" and not game.ui_quit_requested,"quit needs a separate confirmation page")
	_key(KEY_ESCAPE)
	_step(0.2)
	expect(str(_debug().page)=="home" and not game.ui_quit_requested,"Escape cancels quitting")
	_click("quit_confirm")
	_click("quit")
	expect(game.ui_quit_requested and int(game.ui_quit_count)==1,"confirmed quit reaches production exit request exactly once in test mode")
	_key(KEY_ESCAPE)
	_step(0.2)


func _prepare_ending_fixture(won: bool) -> Dictionary:
	await _home()
	_click("start")
	_step(0.05)
	game.spawn_timer = 999.0
	if not won:
		var amount: int = game.health
		game._hurt(amount,"ui_layout_fixture")
		_step(0.1)
		return {"method":"actual production _hurt(current health)","injected_damage":amount,"state":game.state,"health":game.health,"score":game.score,"kills":game.kills,"scope":"Injected death-layout fixture, not normal defeat or difficulty."}
	game._spawn_boss()
	var boss = game.boss_enemy
	var result: Dictionary = boss.blast_at(boss.get_aim_point(),12.0)
	for tick in range(240):
		_step(1.0/60.0)
		if game.state=="won": break
	return {"method":"actual Boss material deletion via production blast_at, actual sever signal and victory timer","material_result":result,"boss_dead":boss.dead,"state":game.state,"health":game.health,"score":game.score,"kills":game.kills,"scope":"Injected large-radius real-material layout fixture, not a normal Boss win or balance/score approval."}


func _verify_endings() -> void:
	var dead: Dictionary = await _prepare_ending_fixture(false)
	expect(game.state=="dead" and game.health==0 and not _button("restart").is_empty(),"real finite damage reaches the death UI and exposes restart",dead)
	_click("restart")
	_step(0.02)
	expect(game.state=="playing" and game.health==5 and game.score==0 and game.kills==0 and game.elapsed<0.5,"death UI restart creates a fresh run without carrying scores")
	var won: Dictionary = await _prepare_ending_fixture(true)
	expect(game.state=="won" and game.kills==1 and game.score>0 and bool(won.get("boss_dead",false)),"actual material Boss sever and timer reach the victory UI",won)
	_click("menu")
	expect(game.state=="menu" and not game.left_down and not game.slashing,"victory UI returns to the title through its real button")
	observations["ending_layout_fixtures"] = {"dead":dead,"won":won}


func _finish() -> void:
	var current := _manifest()
	if observations.has("manifest_before"):
		expect(observations.manifest_before==current,"runtime UI resources stay unchanged during the fixture")
	observations["manifest_after"] = current
	observations["actions"] = actions
	observations["final_ui"] = _plain(_debug()) if is_instance_valid(game) and game.hud.has_method("get_ui_debug_state") else {}
	if is_instance_valid(game):
		game._pause_game()
		await create_timer(1.2).timeout
		game.free()
		await process_frame
	if FileAccess.file_exists(settings_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	if not original_display.is_empty():
		DisplayServer.window_set_mode(original_display.mode)
		DisplayServer.window_set_size(original_display.size)
		DisplayServer.window_set_vsync_mode(original_display.vsync)
		root.msaa_3d = original_display.msaa
		AudioServer.set_bus_volume_db(0,original_display.volume_db)
		AudioServer.set_bus_mute(0,original_display.muted)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var file := FileAccess.open(output_path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":ProjectSettings.get_setting("application/config/version"),"engine":Engine.get_version_info().string,"checks":checks,"failures":failures,"observations":observations,"tool_sha256":FileAccess.get_sha256(get_script().resource_path),"scope":"Parsed-input UI contract fixtures with explicit manual simulation steps and isolated preferences. No normal-combat, performance or subjective feel/visual acceptance."},"\t"))
	file.close()
	print("UI PROTOTYPE VERIFY: ",checks.size()," checks / ",failures," failures")
	quit(0 if failures==0 else 1)


func _run() -> void:
	if not await _setup():
		await _finish()
		return
	observations["manifest_before"] = _manifest()
	if require_packed:
		for path in RUNTIME_PATHS:
			var row: Dictionary = observations.manifest_before[path]
			expect(not row.raw_exists and not str(row.sha256).is_empty() and row.runtime_path!=path,"standalone compiled resource without raw-source fallback: "+path,row)
	await _verify_menu_inputs()
	_verify_cancel_and_gameplay()
	await _verify_settings()
	await _verify_endings()
	await _finish()
