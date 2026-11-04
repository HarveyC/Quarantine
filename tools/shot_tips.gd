extends SceneTree
## Renders hover cards to a PNG (dev check for the glossary tooltips):
##   godot -s tools/shot_tips.gd -- gallery out.png
## Run under xvfb-run with --rendering-driver opengl3.

const TipCard := preload("res://ui/tips/tip_card.gd")
const TermTips := preload("res://ui/tips/term_tips.gd")
const Styles := preload("res://ui/styles.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "gallery"
	var out: String = args[1] if args.size() > 1 else "user://tips.png"
	root.size = Vector2i(1920, 1080)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.035, 0.035)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.theme = Styles.make_theme()
	root.add_child(holder)
	var sets := {
		"gallery": [["cover", false, {}], ["high_ground", false, {}], ["infection", true, {"value": 62}], ["flank", false, {}],
			["hit_chance", false, {"hit": 58, "graze": 10}], ["overwatch", true, {}], ["lapse", false, {}], ["outbreak", false, {"value": 7}],
			["tag_mark", true, {"count": 2}], ["severity", false, {"value": 3}], ["hazards", false, {}], ["rank", false, {}]],
		"actions": [["", false, {"action": {"key": "reload", "label": "Reload", "cost": 1, "desc": "Refill the magazine (5 of 6 rounds)."}}],
			["", false, {"action": {"key": "ability:lunge", "id": "lunge", "label": "Lunge", "cost": -1, "cooldown": 0, "desc": "Dash up to 4 tiles to a visible enemy and cut it for 4-6, +1 per Infection tier. Only half cover counts. Kills on Infected add 5 Infection.", "reason": "Gun drawn: swap weapon first"}}],
			["", true, {"action": {"key": "ability:lunge", "id": "lunge", "label": "Lunge", "cost": -1, "cooldown": 2, "desc": "Dash up to 4 tiles to a visible enemy and cut it for 4-6, +1 per Infection tier. Only half cover counts. Kills on Infected add 5 Infection."}}],
			["", false, {"action": {"key": "ability:swap_weapon", "id": "swap_weapon", "label": "Draw reaper blade", "cost": 1, "desc": "Holster the gun and draw the reaper blade. Only the drawn weapon can attack."}}],
			["", false, {"action": {"key": "hunker", "label": "Hunker", "cost": -1}}]],
		"gallery2": [["turning", false, {}], ["crit", false, {}], ["healing", false, {}],
			["hunker", false, {}], ["set_bonus", true, {"count": 3}], ["mutation", false, {"value": 30}], ["suppress", true, {}]],
	}
	var x := 20.0
	var y := 20.0
	var col_h := 0.0
	for spec in sets.get(mode, sets.gallery):
		var c := TipCard.new([spec[0]] if spec[0] != "" else [], "", spec[2])
		c.set_expanded(spec[1])
		holder.add_child(c)
		await process_frame
		await process_frame
		if y + c.size.y > 1060:
			y = 20.0
			x += 380.0
		c.position = Vector2(x, y)
		y += c.size.y + 16
	for i in 20:
		await process_frame
	root.get_texture().get_image().save_png(out)
	print("[shot-tips] saved ", out)
	quit()
