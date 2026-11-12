class_name CampaignDirector
extends RefCounted
## Pure, seeded preparation. No actors, meshes, SceneTree or global RNG calls.
## A prepared tree is read-only; the consumer owns activation queues and time.

const Encounters = preload("res://scripts/encounter_director.gd")
const SCHEMA_VERSION := 1
const DEFAULT_DURATIONS := [75.0,90.0,90.0,100.0]
var _prepared: Dictionary = {}


static func build_run(run_seed: int, options: Dictionary = {}) -> Dictionary:
	var route_rng := RandomNumberGenerator.new()
	route_rng.seed = Encounters.stream_seed(run_seed,101)
	var middle := [2,3,4]
	Encounters.shuffle_with_rng(middle,route_rng)
	var route: Array[int] = [1,int(middle[0]),int(middle[1]),5]
	var durations: Array = options.get("durations",DEFAULT_DURATIONS)
	var levels: Array[Dictionary] = []
	var catalog: Array[String] = []
	for level_index in range(route.size()):
		var duration := float(DEFAULT_DURATIONS[level_index])
		if level_index < durations.size(): duration = clampf(float(durations[level_index]),45.0,180.0)
		var level_options := {"duration":duration,"planned_speed":float(options.get("planned_speed",18.0)),"level_index":level_index}
		var level_seed := Encounters.stream_seed(run_seed,1000+level_index*97+route[level_index]*17)
		var level: Dictionary = Encounters.build_level(route[level_index],level_index+1,level_seed,level_options)
		levels.append(level)
		for kind: String in level.catalog:
			if not catalog.has(kind): catalog.append(kind)
	var result := {
		"schema_version":SCHEMA_VERSION,"seed":run_seed,"route":route,"levels":levels,"catalog":catalog,
		"activation_contract":{
			"max_actors_per_frame":1,"warm_before_play":true,"count_queued_reservations":true,
			"projectile_cap":24,"explosion_visual_cap":12,"boss_groups_are_sequential":true,
			"damage_is_immediate":true,"cut_geometry_is_authoritative":true,
		},
	}
	Encounters.freeze_tree(result)
	return result


func prepare_run(run_seed: int, options: Dictionary = {}) -> Dictionary:
	_prepared = build_run(run_seed,options)
	return _prepared


func get_route() -> Array:
	return _prepared.get("route",[])


func get_level_plan(level_index: int) -> Dictionary:
	var levels: Array = _prepared.get("levels",[])
	return levels[level_index] if level_index >= 0 and level_index < levels.size() else {}


func get_level_plans() -> Array:
	return _prepared.get("levels",[])


func get_catalog() -> Array:
	return _prepared.get("catalog",[])


static func get_series_definition(series_id: int) -> Dictionary:
	return Encounters.get_series_definition(series_id)
