extends MultiplayerPeerExtension
## Stand-in for GodotSteam's SteamMultiplayerPeer: records how it was opened.

var hosting := false
var target := 0


func create_host(_virtual_port: int = 0) -> int:
	hosting = true
	return OK


func create_client(steam_id: int, _virtual_port: int = 0) -> int:
	target = steam_id
	return OK


func _close() -> void:
	pass
