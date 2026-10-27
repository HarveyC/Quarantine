extends SceneTree
## Text overflow sweep: builds every screen (tools/ui_screens.gd) at each size and scale the
## player can pick, plus every glossary card, and fails if any text is cut, off screen or
## spilling out of its panel (tools/ui_overflow.gd). tests/run.sh runs it after the unit tests.
##   godot --headless -s tests/ui_overflow_sweep.gd [-- screens=title,loadout configs=worst]

const UiScreens := preload("res://tools/ui_screens.gd")
const UiOverflow := preload("res://tools/ui_overflow.gd")
const Tips := preload("res://ui/tips/tips.gd")
const W := preload("res://ui/widgets.gd")

## Menus never scroll, so a crowded one zooms out (W.FitBox). At the default text size and
## scale it must not zoom out past this, or it is too small to read: redesign it instead.
const MIN_ZOOM := 0.7
const ZOOM_CONFIGS := ["720p", "900p", "deck"]

## name -> [window size, Interface scale, Text size]. 1920x1080 lays out the same as 1280x720
## (the UI stretches with the window), so 16:9 and the Steam Deck's 16:10 cover the shapes.
const CONFIGS := {
	"720p": [Vector2i(1280, 720), 1.0, 1.0],
	"900p": [Vector2i(1600, 900), 1.0, 1.0],
	"deck": [Vector2i(1280, 800), 1.0, 1.15],
	"text": [Vector2i(1280, 720), 1.0, 1.5],
	"worst": [Vector2i(1280, 720), 1.25, 1.5],
	"deck_worst": [Vector2i(1280, 800), 1.25, 1.5],
}


func _init() -> void:
	var screens: Array[String] = UiScreens.SCREENS.duplicate()
	var configs: Array = CONFIGS.keys()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("screens="):
			screens.assign(a.substr(8).split(","))
		elif a.begins_with("configs="):
			configs = Array(a.substr(8).split(","))
	GameSettings.file = "user://ui_sweep_settings.cfg"
	Profile.path = "user://ui_sweep_profile.cfg"
	DirAccess.remove_absolute(Profile.path)
	await process_frame
	var failed := 0
	var checked := 0
	for cfg in configs:
		var c: Array = CONFIGS[cfg]
		root.size = c[0]
		GameSettings.set_value("accessibility", "ui_scale", c[1], false)
		GameSettings.set_value("accessibility", "text_scale", c[2], false)
		for screen in screens:
			await UiScreens.build(self, screen, 2)
			for i in 12:
				await process_frame
			var found := UiOverflow.scan(root)
			if cfg in ZOOM_CONFIGS:
				found.append_array(_zoomed_out(root))
			checked += 1
			if not found.is_empty():
				failed += 1
				print("  FAIL  %s @ %s" % [screen, cfg])
				for f in found:
					print("        - " + f)
			UiScreens.clear(self)
			await process_frame
		var cards := await _sweep_cards()
		checked += 1
		if not cards.is_empty():
			failed += 1
			print("  FAIL  glossary cards @ %s" % cfg)
			for f in cards:
				print("        - " + f)
	print("\nui overflow: %d screens checked, %d with cut text" % [checked, failed])
	DirAccess.remove_absolute(Profile.path)
	quit(1 if failed > 0 else 0)


## Opens every glossary card, short and detailed, from the bottom-right corner (the tightest
## spot) and checks it.
func _sweep_cards() -> PackedStringArray:
	var out := PackedStringArray()
	var tips: Node = root.get_node("TermTips")
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	var spot := Control.new()
	host.add_child(spot)
	var view := root.get_visible_rect().size
	spot.position = view - Vector2(40, 40)
	spot.size = Vector2(20, 20)
	for key in Glossary.all():
		Tips.term(spot, key)
		for detailed in [false, true]:
			tips.set_expanded(detailed)
			tips.show_for(spot)
			await process_frame
			await process_frame
			for f in UiOverflow.scan(root):
				out.append("%s%s: %s" % [key, " (detail)" if detailed else "", f])
	tips.set_expanded(false)
	tips.close_all()
	host.queue_free()
	return out


## Every FitBox on screen that has zoomed its content out below MIN_ZOOM.
func _zoomed_out(from: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for n in from.find_children("*", "Container", true, false):
		if n is W.FitBox and n.is_visible_in_tree() and n.get_child_count() > 0:
			var z: float = (n.get_child(0) as Control).scale.x
			if z < MIN_ZOOM:
				out.append("%s: content zoomed out to %d%%, below the %d%% floor" % [n.get_path(), z * 100.0, MIN_ZOOM * 100.0])
	return out
