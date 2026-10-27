extends TestCase
## Generated icon art: every gear item, Prototype, consumable and deployment order has a
## texture under assets/icons/items (run tools/gen_icon_set.py for new ones), and the UI
## vocabulary the map and action wheel draw has art too. Files are checked on disk, so the
## test doesn't depend on the editor having imported them.

const IconArt := preload("res://ui/icon_art.gd")


func _has(path: String) -> bool:
	return FileAccess.file_exists(path)


func test_every_item_has_art() -> void:
	var ids: Array = []
	ids.append_array(GearData.ITEMS.keys())
	ids.append_array(GearData.PROTOTYPES.keys())
	ids.append_array(GearData.CONSUMABLES.keys())
	ids.append_array(DeployOrders.ORDERS.keys())
	ids.append_array(Weapons.TABLE.keys())
	for id in ids:
		assert_true(_has("res://assets/icons/items/%s.png" % id), "%s has item art" % id)


func test_node_and_action_art() -> void:
	for id in ["skirmish", "ambush", "nest", "event", "depot", "hospital", "survivors", "boss", "unknown",
			"shoot", "overwatch", "reload", "hunker", "tag", "suppress", "grenade", "smoke", "flash"]:
		assert_true(_has("res://assets/icons/%s.png" % id), "%s has art" % id)


func test_missing_art_falls_back() -> void:
	assert_eq(IconArt.vocab("no_such_icon_id"), null, "a missing id has no texture")
