extends SceneTree
## Renders one UI screen to a PNG at 1920x1080 (dev check for the UI polish pass):
##   godot -s tools/shot_ui.gd -- <screen> out.png [players=2]
## Screens: see UiScreens.SCREENS (tools/ui_screens.gd), e.g. title, map, loadout, hud,
## settings_accessibility, hq_unlocks, training:5.
## Run under xvfb-run with --rendering-driver opengl3 (software GL renders the 3D board dark).
## Hover cards: add `tip=<term key>` to hover the first control tagged with that term (or
## `tip=@x,y` to hover a point), `shift` to hold the detail key, `nest=<term>` to open a
## nested card from it.
## Sizes and scales: `size=1280x800` (window pixels, default 1920x1080), `ui=1.5` (Interface
## scale), `text=1.5` (Text size). `report` prints every piece of cut or spilling text that
## tools/ui_overflow.gd finds.

const UiScreens := preload("res://tools/ui_screens.gd")
const TermTips := preload("res://ui/tips/term_tips.gd")
const UiOverflow := preload("res://tools/ui_overflow.gd")
const Styles := preload("res://ui/styles.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var screen: String = args[0] if args.size() > 0 else "title"
	var out: String = args[1] if args.size() > 1 else "user://ui.png"
	var players := int(args[2]) if args.size() > 2 else 2
	# Let the autoloads load and apply settings first, then override what this shot asks for.
	await process_frame
	var size := Vector2i(1920, 1080)
	for a in args:
		if a.begins_with("size="):
			var wh := a.substr(5).split("x")
			size = Vector2i(int(wh[0]), int(wh[1]))
		elif a.begins_with("ui="):
			GameSettings.set_value("accessibility", "ui_scale", float(a.substr(3)), false)
		elif a.begins_with("text="):
			GameSettings.set_value("accessibility", "text_scale", float(a.substr(5)), false)
	DisplayServer.window_set_size(size)
	root.size = size
	await process_frame
	await UiScreens.build(self, screen, players)
	for i in 30:
		await process_frame
	await _hover_tip(args)
	root.get_texture().get_image().save_png(out)
	print("[shot-ui] saved ", out)
	if args.has("report"):
		var found := UiOverflow.scan(root)
		print("[overflow] %s: %d" % [screen, found.size()])
		for f in found:
			print("[overflow]   ", f)
	quit()


## Hovers a control the way the pointer would, so the TermTips card shows for real.
func _hover_tip(args: PackedStringArray) -> void:
	var want := ""
	var nest := ""
	for a in args:
		if a.begins_with("tip="):
			want = a.substr(4)
		elif a.begins_with("nest="):
			nest = a.substr(5)
	if want == "":
		return
	var tips := root.get_node_or_null("TermTips")
	if tips == null:
		tips = TermTips.new()
		root.add_child(tips)
	var at := Vector2(-1, -1)
	if want.begins_with("@"):
		var xy := want.substr(1).split(",")
		at = Vector2(float(xy[0]), float(xy[1]))
	else:
		for c in root.find_children("*", "Control", true, false):
			var tip: Variant = c.get_meta("tip") if c.has_meta("tip") else null
			if c.is_visible_in_tree() and tip is Dictionary and tip.get("terms", []).has(want) \
					and (c as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
				at = (c as Control).get_global_rect().get_center()
				break
	if at.x < 0:
		push_warning("no control tagged " + want)
		return
	_move_pointer(at)
	if args.has("shift"):
		Input.action_press("tip_more")
	for i in 40:
		await process_frame
	if nest != "" and not tips.cards.is_empty():
		tips.open_nested(0, nest)
		await process_frame
		await process_frame
		# Rest the pointer on the nested card, as a player following the link would.
		_move_pointer(tips.cards[-1].get_global_rect().position + Vector2(30, 30))
		for i in 6:
			await process_frame
		for i in 4:
			await process_frame
			var h := root.gui_get_hovered_control()
			print("[dbg] ", tips.cards.size(), " ", h, " ", h.get_path() if h else "", " ", tips.cards[-1].get_global_rect() if tips.cards.size() else "")
		for i in 10:
			await process_frame


## Moves the pointer to a point in UI coordinates. Input events are read in window pixels, so
## give xvfb a screen big enough for the whole window: xvfb-run -s "-screen 0 1920x1080x24".
func _move_pointer(at: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = mm.position
	Input.parse_input_event(mm)
	root.warp_mouse(at)
