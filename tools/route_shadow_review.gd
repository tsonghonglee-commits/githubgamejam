extends SceneTree
## Rendered road-recycling diagnostic. Production road/shader/light updates,
## fixed camera, no enemies. RGB is mixed final colour, not a shadow buffer.

const SOURCE_PATHS := ["res://scenes/main.tscn","res://scripts/main.gd","res://scripts/route_sections.gd"]
const GROUND_X := [-4.50,-3.75,-3.0,-2.25,-1.50,-0.75,0.0,2.25,4.50]
const GROUND_Z := [-2.0,-4.0,-6.0,-8.0,-10.0,-12.0,-16.0,-22.0]
const CHAPTER_TIMES := [0.0,50.0,105.0,155.0]

var game
var label := "route-shadow"
var output_dir := ""
var yaw_option := "all"
var target_layout_option := "all"
var chapter := 0
var start_distance := 5.90
var end_distance := 36.10
var distance_step := 0.05
var speed := 18.0
var before_frames := 3
var after_frames := 4
var diagnostics_enabled := true
var save_all_frames := false
var rendered := false
var sequence := 0
var camera_yaw := 0.0
var camera_position := Vector3.ZERO
var camera_fov := 76.0
var layout_indices: Array[int] = []
var cases: Array = []
var frames: Array = []
var wrap_events: Array = []
var diagnostics: Array = []
var rolling: Array = []
var keep_after := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): output_dir = arg.trim_prefix("--capture-dir=")
		elif arg.begins_with("--label="): label = arg.trim_prefix("--label=").validate_filename()
		elif arg.begins_with("--camera-yaw="): yaw_option = arg.trim_prefix("--camera-yaw=")
		elif arg.begins_with("--target-layout-index="): target_layout_option = arg.trim_prefix("--target-layout-index=")
		elif arg.begins_with("--chapter="): chapter = clampi(int(arg.trim_prefix("--chapter=")),0,3)
		elif arg.begins_with("--start-distance="): start_distance = maxf(0.0,float(arg.trim_prefix("--start-distance=")))
		elif arg.begins_with("--end-distance="): end_distance = maxf(0.0,float(arg.trim_prefix("--end-distance=")))
		elif arg.begins_with("--distance-step="): distance_step = clampf(float(arg.trim_prefix("--distance-step=")),0.001,0.5)
		elif arg.begins_with("--speed="): speed = clampf(float(arg.trim_prefix("--speed=")),4.0,60.0)
		elif arg == "--no-diagnostics": diagnostics_enabled = false
		elif arg == "--save-all-frames": save_all_frames = true
	if output_dir.is_empty(): output_dir = ProjectSettings.globalize_path("res://builds/route-shadow-review").path_join(label)
	end_distance = maxf(end_distance,start_distance)
	call_deferred("_run")


func _v3(value: Vector3) -> Array:
	return [value.x,value.y,value.z]


func _transform(value: Transform3D) -> Array:
	return [_v3(value.basis.x),_v3(value.basis.y),_v3(value.basis.z),_v3(value.origin)]


func _has_property(object: Object, name: String) -> bool:
	for property in object.get_property_list():
		if property.name == name: return true
	return false


func _manifest() -> Dictionary:
	var result := {}
	for path in SOURCE_PATHS:
		var raw := FileAccess.file_exists(path)
		var runtime_path: String = path if raw else ""
		if FileAccess.file_exists(path+".remap"):
			var config := ConfigFile.new()
			if config.load(path+".remap") == OK: runtime_path = str(config.get_value("remap","path",""))
		result[path] = {"source_sha256":FileAccess.get_sha256(path) if raw else "","runtime_path":runtime_path,"runtime_sha256":FileAccess.get_sha256(runtime_path) if not runtime_path.is_empty() and FileAccess.file_exists(runtime_path) else ""}
	return result


func _segment_states() -> Array:
	var result: Array = []
	for index in range(game.road_segments.size()):
		var segment: Node3D = game.road_segments[index]
		var visibility: Array = []
		for section_root in segment.get_meta("section_roots",[]): visibility.append(section_root.visible)
		result.append({"array_index":index,"layout_index":layout_indices[index],"transform":_transform(segment.transform),"global_transform":_transform(segment.global_transform),"section":segment.get_meta("route_section",0),"section_visibility":visibility})
	return result


func _lights() -> Array:
	var result: Array = []
	var nodes: Array[Node] = [game]
	while not nodes.is_empty():
		var node: Node = nodes.pop_back()
		if node is Light3D:
			var entry := {"path":str(game.get_path_to(node)),"type":node.get_class(),"transform":_transform(node.global_transform),"energy":node.light_energy,"shadow_enabled":node.shadow_enabled,"visible":node.is_visible_in_tree(),"cull_mask":node.light_cull_mask}
			if node is DirectionalLight3D: entry["shadow_max_distance"] = node.directional_shadow_max_distance
			result.append(entry)
		nodes.append_array(node.get_children())
	return result


func _geometry_inventory(root_node: Node3D) -> Array:
	var result: Array = []
	var nodes: Array[Node] = [root_node]
	while not nodes.is_empty():
		var node: Node = nodes.pop_back()
		if node is GeometryInstance3D:
			var bounds: AABB = node.get_aabb()
			var entry := {"relative_path":str(root_node.get_path_to(node)),"type":node.get_class(),"transform_in_segment":_transform(root_node.global_transform.affine_inverse()*node.global_transform),"bounds_position":_v3(bounds.position),"bounds_size":_v3(bounds.size),"cast_shadow":node.cast_shadow,"layers":node.layers,"visible":node.is_visible_in_tree(),"section_root":-1}
			var roots: Array = root_node.get_meta("section_roots",[])
			for section in range(roots.size()):
				if roots[section] == node or roots[section].is_ancestor_of(node): entry["section_root"] = section
			if node is MultiMeshInstance3D and node.multimesh != null:
				var instances: Array = []
				for index in range(node.multimesh.instance_count): instances.append(_transform(node.multimesh.get_instance_transform(index)))
				entry["instance_transforms"] = instances
				entry["instance_count"] = node.multimesh.instance_count
				if node.multimesh.mesh != null:
					entry["instance_mesh_bounds_position"] = _v3(node.multimesh.mesh.get_aabb().position)
					entry["instance_mesh_bounds_size"] = _v3(node.multimesh.mesh.get_aabb().size)
			result.append(entry)
		nodes.append_array(node.get_children())
	return result


func _sample(picture: Image, world: Vector3) -> Dictionary:
	var logical: Vector2 = game.camera.unproject_position(world)
	var result := {"world":_v3(world),"logical_pixel":[logical.x,logical.y],"valid":false}
	if picture == null or game.camera.is_position_behind(world) or not game.get_viewport().get_visible_rect().has_point(logical): return result
	var pixel := Vector2i(logical*Vector2(picture.get_size())/game.get_viewport().get_visible_rect().size)
	var total := Vector3.ZERO
	var count := 0
	for y in range(maxi(0,pixel.y-1),mini(picture.get_height(),pixel.y+2)):
		for x in range(maxi(0,pixel.x-1),mini(picture.get_width(),pixel.x+2)):
			var color := picture.get_pixel(x,y)
			total += Vector3(color.r,color.g,color.b)
			count += 1
	result["valid"] = count > 0
	result["native_pixel"] = [pixel.x,pixel.y]
	result["rgb"] = _v3(total/maxf(float(count),1.0))
	return result


func _ground_pairs(before: Image, after: Image, route_travel: float) -> Dictionary:
	var samples: Array = []
	var maximum := 0.0
	var total := 0.0
	var valid := 0
	for z in GROUND_Z:
		for x in GROUND_X:
			var world := Vector3(x,-0.054,z)
			var old := _sample(before,world-Vector3(0,0,route_travel))
			var current := _sample(after,world)
			var entry := {"before":old,"after":current}
			if old.valid and current.valid:
				var delta := Vector3(current.rgb[0]-old.rgb[0],current.rgb[1]-old.rgb[1],current.rgb[2]-old.rgb[2])
				var error := maxf(absf(delta.x),maxf(absf(delta.y),absf(delta.z)))
				entry["rgb_delta"] = _v3(delta)
				maximum = maxf(maximum,error)
				total += error
				valid += 1
			samples.append(entry)
	return {"samples":samples,"valid_count":valid,"max_channel_delta":maximum,"mean_max_channel_delta":total/maxf(float(valid),1.0),"matched_route_travel":route_travel}


func _fix_camera() -> void:
	game.camera.position = camera_position
	game.camera.rotation = Vector3(0,camera_yaw,0)
	game.camera.fov = camera_fov


func _render_only() -> Image:
	_fix_camera()
	await process_frame
	if not rendered: return null
	await RenderingServer.frame_post_draw
	return game.get_viewport().get_texture().get_image()


func _save_frame(frame: Dictionary, view_name: String) -> void:
	if frame.image == null or frame.record.has("png"): return
	var name := "%s-%s-motion-%05d-%.3fm.png" % [label,view_name,int(frame.record.serial),float(frame.record.run_distance)]
	frame.image.save_png(output_dir.path_join(name))
	frame.record["png"] = name


func _advance(travel: float) -> Array:
	var before: Array = []
	for segment in game.road_segments:
		before.append({"transform":segment.transform,"section":segment.get_meta("route_section",0)})
	game.run_distance += travel
	game.elapsed += travel/speed
	game.game_clock += travel/speed
	game._update_road(travel/speed)
	_fix_camera()
	var wraps: Array = []
	for index in range(game.road_segments.size()):
		var segment: Node3D = game.road_segments[index]
		var expected: Transform3D = before[index].transform
		expected.origin.z += travel
		if absf(segment.position.z-expected.origin.z) > 0.1:
			var record := {"serial":sequence,"run_distance":game.run_distance,"array_index":index,"layout_index":layout_indices[index],"before_transform":_transform(before[index].transform),"expected_unwrapped_transform":_transform(expected),"after_transform":_transform(segment.transform),"before_section":before[index].section,"after_section":segment.get_meta("route_section",0),"recycle_displacement":segment.position.z-expected.origin.z}
			wrap_events.append(record)
			wraps.append({"node":segment,"expected":expected,"before_section":before[index].section,"record":record})
	return wraps


func _diagnose(wrap: Dictionary, view_name: String) -> void:
	var segment: Node3D = wrap.node
	var actual: Transform3D = segment.transform
	var actual_section: int = int(segment.get_meta("route_section",0))
	var held_distance: float = game.run_distance
	var lights_before := _lights()
	var stable_post: Image = await _render_only()
	stable_post = await _render_only()
	segment.transform = wrap.expected
	game._set_route_section(segment,int(wrap.before_section))
	var unwrapped: Image = await _render_only()
	unwrapped = await _render_only()
	segment.transform = actual
	game._set_route_section(segment,actual_section)
	var restored: Image = await _render_only()
	restored = await _render_only()
	var prefix := "%s-%s-frozen-%05d-layout%d" % [label,view_name,sequence,int(wrap.record.layout_index)]
	if rendered:
		stable_post.save_png(output_dir.path_join(prefix+"-actual-post.png"))
		unwrapped.save_png(output_dir.path_join(prefix+"-counterfactual-unwrapped.png"))
		restored.save_png(output_dir.path_join(prefix+"-restored-post.png"))
	diagnostics.append({"wrap":wrap.record,"run_distance":held_distance,"operation":"At fixed run_distance and clocks, restore ONLY the target tile to its expected unwrapped transform and pre-wrap section, then restore its actual post-wrap state. No road/light update is called during this counterfactual; lamps and shadow flags are not modified.","distance_unchanged":is_equal_approx(game.run_distance,held_distance),"lights_unchanged":lights_before == _lights(),"target_restored":segment.transform == actual and int(segment.get_meta("route_section",0)) == actual_section,"images_prefix":prefix,"target_contribution_at_frozen_ground":_ground_pairs(stable_post,unwrapped,0.0),"restoration_control":_ground_pairs(stable_post,restored,0.0)})


func _run_case(view_name: String, requested_yaw: Variant) -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	if rendered: await RenderingServer.frame_post_draw
	game.test_mode = true
	game.set_process(false)
	game.sword.set_process(false)
	game.start_game()
	await process_frame
	game.practice = false
	game.training = false
	game.spawn_timer = 999.0
	game.hud.visible = false
	game.speed = speed
	game.gear = game.gear_for_speed(speed)
	game.elapsed = CHAPTER_TIMES[chapter]
	for segment in game.road_segments: game._set_route_section(segment,chapter)
	game._update_road(0.0)
	# Query the production normal-look clamp through its actual input handler.
	game.aim_angles = Vector2.ZERO
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(-1000000,0)
	game._input(motion)
	var left_limit: float = game.aim_angles.x
	motion.relative = Vector2(1000000,0)
	game._input(motion)
	var right_limit: float = game.aim_angles.x
	game.aim_angles = Vector2.ZERO
	camera_yaw = left_limit if str(requested_yaw) == "left" else clampf(float(requested_yaw),right_limit,left_limit)
	camera_position = game.camera.position
	camera_fov = game.camera.fov
	layout_indices.clear()
	var inventory: Array = []
	for index in range(game.road_segments.size()):
		var segment: Node3D = game.road_segments[index]
		var layout := roundi((6.0-segment.position.z)/10.0)
		layout_indices.append(layout)
		inventory.append({"array_index":index,"layout_index":layout,"initial_transform":_transform(segment.transform),"geometry":_geometry_inventory(segment)})
	frames = []
	wrap_events = []
	diagnostics = []
	rolling = []
	keep_after = 0
	sequence = 0
	_fix_camera()
	while float(game.run_distance) < start_distance-0.000001:
		_advance(minf(0.5,start_distance-float(game.run_distance)))
		await process_frame
	var previous: Dictionary = {}
	while true:
		var wraps: Array = []
		if sequence > 0: wraps = _advance(minf(distance_step,end_distance-float(game.run_distance)))
		var picture: Image = await _render_only()
		var record := {"serial":sequence,"run_distance":game.run_distance,"elapsed":game.elapsed,"world_time":game.game_clock,"render_frame":Engine.get_frames_drawn(),"camera_transform":_transform(game.camera.global_transform),"fov":game.camera.fov,"visible_section":game.get("route_section") if _has_property(game,"route_section") else chapter,"segments":_segment_states(),"lights":_lights()}
		if not previous.is_empty():
			record["fixed_world_ground_delta"] = _ground_pairs(previous.image,picture,0.0)
			record["matched_route_ground_delta"] = _ground_pairs(previous.image,picture,float(game.run_distance)-float(previous.record.run_distance))
		frames.append(record)
		var frame := {"record":record,"image":picture}
		rolling.append(frame)
		while rolling.size() > before_frames+1:
			var expired: Dictionary = rolling.pop_front()
			if not expired.record.has("png"):
				if expired.record.has("fixed_world_ground_delta"): expired.record.fixed_world_ground_delta.erase("samples")
				if expired.record.has("matched_route_ground_delta"): expired.record.matched_route_ground_delta.erase("samples")
		var selected: Array = []
		for wrap in wraps:
			if target_layout_option == "all" or int(wrap.record.layout_index) == int(target_layout_option): selected.append(wrap)
		if not selected.is_empty():
			for held in rolling: _save_frame(held,view_name)
			keep_after = after_frames
		elif keep_after > 0:
			_save_frame(frame,view_name)
			keep_after -= 1
		# A narrow before/after window is useful even when a fix deliberately
		# keeps the selected tile alive and therefore produces no selected wrap.
		if save_all_frames or end_distance-start_distance <= 0.5 or sequence == 0 or float(game.run_distance) >= end_distance-0.000001:
			_save_frame(frame,view_name)
		if diagnostics_enabled:
			for wrap in selected: await _diagnose(wrap,view_name)
		previous = frame
		sequence += 1
		if float(game.run_distance) >= end_distance-0.000001: break
	cases.append({"view":view_name,"requested_yaw":requested_yaw,"effective_yaw":camera_yaw,"production_look_limits":{"left":left_limit,"right":right_limit,"source":"Production _input with large opposite normal mouse deltas"},"chapter_initial":chapter,"initial_tile_geometry":inventory,"frames":frames,"wrap_events":wrap_events,"frozen_counterfactuals":diagnostics})
	rolling.clear()
	game._pause_game()
	game.audio.set_runner_motion(0.0,0.0,false,0.0)
	game.free()
	await process_frame


func _run() -> void:
	rendered = DisplayServer.get_name() != "headless"
	if rendered:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280,720)
	Engine.max_fps = 60
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DirAccess.make_dir_recursive_absolute(output_dir)
	var before := _manifest()
	if yaw_option == "all":
		await _run_case("front",0.0)
		await _run_case("left","left")
	else:
		await _run_case("left" if yaw_option == "left" else "yaw",yaw_option)
	var after := _manifest()
	var report := {"label":label,"version":ProjectSettings.get_setting("application/config/version"),"rendered":rendered,"gpu":RenderingServer.get_video_adapter_name(),"chapter":chapter,"start_distance":start_distance,"end_distance":end_distance,"distance_step":distance_step,"speed":speed,"target_layout_index":target_layout_option,"before_frames":before_frames,"after_frames":after_frames,"cases":cases,"source_manifest_before":before,"source_manifest_after":after,"sources_unchanged":before == after,"tool_sha256":FileAccess.get_sha256(get_script().resource_path),"scope":"Rendered scenery diagnostic, fixed camera / FOV, no combat. Advances actual production _update_road with matching run_distance/elapsed/world clock; road shaders and forge lamps update through production helpers. Chapter initialisation uses production _set_route_section. Layout index is inferred from initial (6-z)/10 to align old 23-tile and padded layouts. Normal frame comparisons include real world motion, view-dependent shading and mixed final colour. Matched-route probes compensate travel but still do not separate lighting. Only frozen target-tile counterfactuals isolate a tile's visible contribution; no shadow / light settings are changed. No automatic visual pass/fail, performance measurement or human quality approval."}
	var file := FileAccess.open(output_dir.path_join(label+"-route-shadow.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("ROUTE SHADOW REVIEW ",label," cases=",cases.size()," rendered=",rendered," sources_unchanged=",before == after)
	quit(0 if before == after else 1)
