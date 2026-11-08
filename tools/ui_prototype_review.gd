extends "ui_prototype_verify.gd"
## Native UI gallery driven by real parsed menu input. Ending pages use
## explicitly injected production damage/material fixtures, not fake scores.

var capture_dir := ""
var captures: Array = []


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
		elif argument == "--require-packed": require_packed = true
	if capture_dir.is_empty(): capture_dir = ProjectSettings.globalize_path("res://builds/ui-review-v096/gallery")
	output_path = capture_dir.path_join("ui-gallery-checks.json")
	call_deferred("_run")


func _capture(stage: String, fixture: Dictionary = {}) -> void:
	game._update_hud()
	await process_frame
	await RenderingServer.frame_post_draw
	var path := capture_dir.path_join(stage+".png")
	root.get_texture().get_image().save_png(path)
	captures.append({"stage":stage,"path":path,"window_size":str(DisplayServer.window_get_size()),"hud_canvas_size":str(game.hud.size),"state":game.state,"health":game.health,"score":game.score,"kills":game.kills,"ui":_plain(_debug()),"fixture":fixture})


func _held_key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("UI gallery requires the native renderer; use ui_prototype_verify for headless contracts.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(capture_dir)
	if not await _setup():
		await _finish()
		return
	observations["manifest_before"] = _manifest()
	if require_packed:
		for path in RUNTIME_PATHS:
			var row: Dictionary = observations.manifest_before[path]
			expect(not row.raw_exists and not str(row.sha256).is_empty() and row.runtime_path!=path,"native standalone compiled UI resource: "+path,row)
	await _capture("00-title")
	var rect := _rect("start")
	var a := Vector2(rect.position.x-25,rect.get_center().y+12)
	var b := Vector2(rect.end.x+25,rect.get_center().y-12)
	_motion(a)
	_mouse(true,a)
	_motion(b)
	_step(0.07)
	await _capture("01-title-slice-mid",{"method":"actual parsed press and one crossing pointer segment","pending_age":_debug().pending_age})
	_mouse(false,b)
	_step(0.15)
	expect(game.state=="playing" and int(game.combat_stats.get("light_slashes",0))==0,"rendered menu slice starts a run without a free attack")
	game.spawn_timer = 999.0
	await _capture("02-gameplay-hud")
	_key(KEY_ESCAPE)
	_step(0.2)
	await _capture("03-paused")
	_click("settings")
	await _capture("04-settings")
	_click("back")
	_click("controls")
	await _capture("05-controls")
	_click("back")
	_click("resume")
	game.spawn_timer = 999.0
	_held_key(KEY_SHIFT,true)
	for tick in range(900):
		_step(1.0/60.0)
		if game.speed>=game.MAX_SPEED: break
	_held_key(KEY_SHIFT,false)
	await _capture("06-gear-four-hud",{"method":"actual parsed held Shift with explicit manual simulation ticks","scope":"HUD layout, not real-time speed/performance evidence."})
	_mouse(true,Vector2(640,360))
	_step(0.16)
	_motion(pointer+Vector2(50,-20))
	_step(0.02)
	await _capture("07-held-hud",{"method":"actual parsed hold/drag","slashing":game.slashing})
	_mouse(false,pointer)
	_step(0.02)
	var dead: Dictionary = await _prepare_ending_fixture(false)
	expect(game.state=="dead","review real finite damage reaches death layout",dead)
	await _capture("08-dead-layout-fixture",dead)
	var won: Dictionary = await _prepare_ending_fixture(true)
	expect(game.state=="won" and game.kills==1,"review actual material sever reaches victory layout",won)
	await _capture("09-won-material-layout-fixture",won)
	_click("menu")
	_click("quit_confirm")
	await _capture("10-quit-confirm")
	observations["captures"] = captures
	var file := FileAccess.open(capture_dir.path_join("ui-prototype-review.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":ProjectSettings.get_setting("application/config/version"),"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"rendered":true,"captures":captures,"checks":checks,"failures":failures,"tool_sha256":FileAccess.get_sha256(get_script().resource_path),"base_tool_sha256":FileAccess.get_sha256(get_script().resource_path.get_base_dir().path_join("ui_prototype_verify.gd")),"runtime_manifest":_manifest(),"scope":"Native actual UI gallery, parsed pointer/key controls and explicitly manual simulation. Damage/large-radius Boss material ending fixtures are labelled per image; scores are actual fixture results, not assigned or normal-combat evidence. No GPU performance, normal-run or subjective visual approval."},"\t"))
	file.close()
	print("UI PROTOTYPE REVIEW: ",captures.size()," native captures")
	await _finish()
