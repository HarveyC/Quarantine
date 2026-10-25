extends SceneTree
## Writes tools/voice_manifest.json: every voice clip the story needs (see story/voice_lines.gd).
## Run after changing a voiced line, then tools/gen_voices.py records and processes what's new:
##   godot --headless -s tools/voice_manifest.gd


func _init() -> void:
	var list := VoiceLines.manifest()
	var f := FileAccess.open("res://tools/voice_manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(list, "\t") + "\n")
	f.close()
	print("voice manifest: %d clips" % list.size())
	quit()
