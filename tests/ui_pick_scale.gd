extends SceneTree
## Per-soldier pick screens must keep one zoom from pick to pick. Their content sits in a
## W.FitBox, which only ever shrinks for a given box size, so a content swap that briefly
## measures too big (old cards still queued for deletion next to the new ones) left every later
## soldier's choice zoomed out. tests/run.sh runs this after the overflow sweep.
##   godot --headless -s tests/ui_pick_scale.gd

const UiScreens := preload("res://tools/ui_screens.gd")
const W := preload("res://ui/widgets.gd")

## name -> [window size, Interface scale, Text size]: default and the biggest the player can set.
const CONFIGS := {
	"1080p": [Vector2i(1920, 1080), 1.0, 1.0],
	"1080p_ui125": [Vector2i(1920, 1080), 1.25, 1.0],
	"worst": [Vector2i(1280, 720), 1.25, 1.5],
}


func _init() -> void:
	GameSettings.file = "user://ui_pick_scale_settings.cfg"
	Profile.path = "user://ui_pick_scale_profile.cfg"
	DirAccess.remove_absolute(Profile.path)
	await process_frame
	var failed := 0
	for cfg in CONFIGS:
		var c: Array = CONFIGS[cfg]
		root.size = c[0]
		GameSettings.set_value("accessibility", "ui_scale", c[1], false)
		GameSettings.set_value("accessibility", "text_scale", c[2], false)
		for screen in ["kit", "reward", "loadout"]:
			var bad := await _check(screen)
			if bad != "":
				failed += 1
				print("  FAIL  %s @ %s: %s" % [screen, cfg, bad])
			else:
				print("  ok    %s @ %s" % [screen, cfg])
	print("\npick scale: %d failed" % failed)
	DirAccess.remove_absolute(Profile.path)
	quit(1 if failed > 0 else 0)


## Builds the screen, moves to the next soldier the way a player does, then compares that zoom
## with a fresh fit of the same content (the zoom the second soldier should get).
func _check(screen: String) -> String:
	await UiScreens.build(self, screen, 2)
	await _settle()
	var scr := _screen()
	var before := _zoom()
	if screen == "loadout":
		var sq: Array = scr.run.squad()
		scr._sid = sq[1].id
		scr._refresh()
	else:
		scr._select(0)
		scr.session.submit_run(scr._action(0))
	await _settle()
	var after := _zoom()
	_fit().refit()
	await _settle()
	var fresh := _zoom()
	UiScreens.clear(self)
	await process_frame
	if before <= 0.0 or after <= 0.0:
		return "no FitBox found"
	if absf(after - fresh) > 0.03:   # wrapped text settles a step or two off a fresh fit
		return "next soldier shown at %.3f zoom, its content fits at %.3f (first soldier %.3f)" % [after, fresh, before]
	return ""


func _settle() -> void:
	for i in 12:
		await process_frame


func _screen() -> Control:
	for c in root.get_children():
		if c is Control and c.has_method("setup") and "run" in c:
			return c
	return null


func _fit() -> Container:
	var s := _screen()
	if s == null:
		return null
	for n in s.find_children("*", "Container", true, false):
		if n is W.FitBox and n.get_child_count() > 0:
			return n
	return null


func _zoom() -> float:
	var f := _fit()
	return (f.get_child(0) as Control).scale.x if f != null else -1.0
