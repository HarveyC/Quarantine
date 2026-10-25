class_name VoiceLines
extends RefCounted
## Which story lines are voiced, by whom, and which clips make each one. Pure data and lookups:
## tools/voice_manifest.gd writes every clip it needs to tools/voice_manifest.json for
## tools/gen_voices.py, and view/voice_player.gd asks plan() which clips to play for a caption.
##
## Okafor, the Source, Hale and Halden-Voss speak recorded lines (audio/voice/). Soldiers speak
## in mask babble made at play time (view/babble.gd), so they need no clips.
##
## A line with {name}, {wave} or {last_wave} is cut into pieces around them; each name and
## number is its own clip, so one recording covers every soldier and every wave. A "--" in a line
## is a burst of interference baked into the clip.

const DIR := "res://audio/voice/"
## Caption speaker -> voice. Bark captions are upper case and spelled out.
const VOICES := {"OKAFOR": "okafor", "MAJOR OKAFOR": "okafor", "SOURCE": "source", "HALE": "hale",
	"HALDEN-VOSS": "hv"}
## Voices that come over Okafor's radio: the line gets a key-up click and a release.
const RADIO := ["okafor"]
## Highest wave number with a recorded number.
const MAX_NUMBER := 60
const VARS := ["name", "wave", "last_wave"]

const _ONES: Array[String] = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
	"ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
const _TENS: Array[String] = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

static var _templates: Array = []
static var _patterns := {}


## Every voiced line as [voice, template], templates unfilled.
static func templates() -> Array:
	if not _templates.is_empty():
		return _templates
	var out: Array = []
	var add_scene := func(lines: Array) -> void:
		for l in lines:
			if VOICES.has(l[0]):
				out.append([VOICES[l[0]], l[1]])
	for k in StoryData.INTRO_OPENERS:
		add_scene.call(StoryData.INTRO_OPENERS[k])
	add_scene.call(StoryData.INTRO_ORDERS)
	for k in StoryData.ACT_SCENES:
		add_scene.call(StoryData.ACT_SCENES[k].lines)
	add_scene.call([StoryData.SOURCE_REMEMBERS, StoryData.SOURCE_BURNED])
	for k in StoryData.BOSS_SCENES:
		add_scene.call(StoryData.BOSS_SCENES[k].lines)
	for k in StoryData.ENDINGS:
		add_scene.call(StoryData.ENDINGS[k].lines)
	for k in StoryData.BARKS:
		for t in StoryData.BARKS[k]:
			out.append(["okafor", t])
	for tier in StoryData.WHISPERS:
		for t in StoryData.WHISPERS[tier]:
			out.append(["source", t])
	for phase in StoryData.HALE_BARKS:
		for t in StoryData.HALE_BARKS[phase]:
			out.append(["hale_turned" if phase >= 2 else "hale", t])
	var seen := {}
	for e in out:
		var key := "%s|%s" % e
		if not seen.has(key):
			seen[key] = true
			_templates.append(e)
	return _templates


## The voice for a caption's speaker, "" if it isn't recorded (soldiers, plain captions).
static func voice_of(speaker: String) -> String:
	return VOICES.get(speaker.strip_edges().to_upper(), "")


## A template as pieces: {"text": literal} or {"var": key, "poss": true if followed by 's}.
static func pieces(template: String) -> Array:
	var out: Array = []
	var rx := RegEx.create_from_string("\\{(%s)\\}('s)?" % "|".join(VARS))
	var at := 0
	for m in rx.search_all(template):
		var lit := template.substr(at, m.get_start() - at)
		if _speakable(lit):
			out.append({"text": lit.strip_edges().lstrip(",.;: ")})
		out.append({"var": m.get_string(1), "poss": m.get_string(2) != ""})
		at = m.get_end()
	var tail := template.substr(at)
	if _speakable(tail):
		out.append({"text": tail.strip_edges().lstrip(",.;: ")})
	return out


static func _speakable(s: String) -> bool:
	return RegEx.create_from_string("[A-Za-z0-9]").search(s) != null


## The clip for one piece of text in one voice.
static func clip(voice: String, text: String) -> String:
	return DIR + "%s_%s.ogg" % [voice, text.md5_text().left(10)]


## How a filled value is said: names as they are, numbers in words.
static func say_value(key: String, value: String, poss := false) -> String:
	var s := value
	if key != "name" and value.is_valid_int():
		s = number_words(int(value))
	return s + ("'s" if poss else "")


static func number_words(n: int) -> String:
	if n < 20:
		return _ONES[maxi(n, 0)]
	if n < 100:
		return _TENS[n / 10] + ("" if n % 10 == 0 else "-" + _ONES[n % 10])
	return str(n)


## The clips that speak `text` (already filled) as `speaker`, in order; [] if the line has no
## recording. A name or number with no clip of its own is skipped.
static func plan(speaker: String, text: String) -> Array[String]:
	var out: Array[String] = []
	var voice := voice_of(speaker)
	if voice == "":
		return out
	for t in templates():
		if t[0] != voice:
			continue
		var vals: Variant = match_line(t[1], text)
		if vals == null:
			continue
		for p in pieces(t[1]):
			var path := clip(voice, p.text) if p.has("text") else clip(voice, say_value(p.var, vals.get(p.var, ""), p.poss))
			if ResourceLoader.exists(path):
				out.append(path)
		return out
	return out


## The filled values if `text` is `template` filled in, else null.
static func match_line(template: String, text: String) -> Variant:
	if not template.contains("{"):
		return {} if template == text else null
	if not _patterns.has(template):
		var rx := "^"
		var names: Array = []
		var at := 0
		var ph := RegEx.create_from_string("\\{(%s)\\}" % "|".join(VARS))
		for m in ph.search_all(template):
			rx += _escape(template.substr(at, m.get_start() - at)) + "(.+?)"
			names.append(m.get_string(1))
			at = m.get_end()
		rx += _escape(template.substr(at)) + "$"
		_patterns[template] = [RegEx.create_from_string(rx), names]
	var pat: Array = _patterns[template]
	var m: RegExMatch = pat[0].search(text)
	if m == null:
		return null
	var vals := {}
	for i in pat[1].size():
		vals[pat[1][i]] = m.get_string(i + 1)
	return vals


static func _escape(s: String) -> String:
	var out := ""
	for c in s:
		out += ("\\" + c) if ".^$*+?()[]{}|\\".contains(c) else c
	return out


## Every clip to record: [{file, voice, text}], where text may hold "--" for interference.
static func manifest() -> Array:
	var files := {}
	var add := func(voice: String, text: String) -> void:
		var f := clip(voice, text).get_file()
		if not files.has(f):
			files[f] = {"file": f, "voice": voice, "text": text}
	var vars_used := {}
	for t in templates():
		for p in pieces(t[1]):
			if p.has("text"):
				add.call(t[0], p.text)
			else:
				vars_used["%s|%s|%s" % [t[0], p.var, p.poss]] = true
	for k in vars_used:
		var parts: PackedStringArray = k.split("|")
		var poss := parts[2] == "true"
		if parts[1] == "name":
			for n in RunSoldier.NAMES:
				add.call(parts[0], say_value("name", n, poss))
		else:
			for n in range(1, MAX_NUMBER + 1):
				add.call(parts[0], say_value(parts[1], str(n), poss))
	var keys := files.keys()
	keys.sort()
	return keys.map(func(k: String) -> Dictionary: return files[k])
