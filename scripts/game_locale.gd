extends RefCounted

const Interface = preload("res://scripts/game_locale_ui.gd")
const Content = preload("res://scripts/game_locale_content.gd")

const DEFAULT := "en"
const LANGUAGES := ["en","zh_CN","fr","ru"]
const NAMES := ["English","简体中文","Français","Русский"]
const TRANSLATION_COLUMNS := {"en":0,"fr":1,"ru":2}

static var current := DEFAULT


static func set_language(language: String) -> void:
	current = language if language in LANGUAGES else DEFAULT


static func text(source: String) -> String:
	if current == "zh_CN" or source.is_empty():
		return source
	var column := int(TRANSLATION_COLUMNS[current])
	if Interface.STRINGS.has(source):
		return Interface.STRINGS[source][column]
	if Content.STRINGS.has(source):
		return Content.STRINGS[source][column]
	return source
