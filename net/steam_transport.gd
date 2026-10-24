class_name SteamTransport
extends NetTransport
## Online play through Steam: the host opens a friends-only lobby, friends enter it from an
## invite or the friends list, and the game traffic goes over Steam's relay (no port forwarding,
## no IP addresses). Needs the GodotSteam GDExtension; `steam` is its singleton (or a test fake).

const LOBBY_FRIENDS_ONLY := 1        # Steam.LOBBY_TYPE_FRIENDS_ONLY
const RESULT_OK := 1                 # k_EResultOK from lobby_created
const ENTER_SUCCESS := 1             # Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS
## Tags our lobbies so a stray lobby on the shared Spacewar app id (480) is never joined.
const LOBBY_TAG_KEY := "game"
const LOBBY_TAG := "carriers"

var steam   # the Steam singleton or a fake, untyped so its methods resolve at runtime
var max_members := 4
var lobby_id := 0
## The host's Steam id, known once we've entered its lobby; used to reconnect.
var host_steam_id := 0
## Makes the MultiplayerPeer. Tests swap in a stand-in since the real class lives in GodotSteam.
var make_peer := func() -> MultiplayerPeer:
	return ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer


func _init(p_steam = null, p_lobby_id: int = 0, p_host_steam_id: int = 0) -> void:
	steam = p_steam
	lobby_id = p_lobby_id
	host_steam_id = p_host_steam_id


static func available() -> bool:
	return ClassDB.class_exists("SteamMultiplayerPeer")


func kind() -> String:
	return "steam"


func host() -> String:
	if steam == null:
		return "Steam is not running"
	steam.connect("lobby_created", _on_lobby_created, CONNECT_ONE_SHOT)
	steam.createLobby(LOBBY_FRIENDS_ONLY, max_members)
	return ""


func _on_lobby_created(result: int, id: int) -> void:
	if result != RESULT_OK:
		failed.emit("Steam could not create a lobby (error %d)" % result)
		return
	lobby_id = id
	host_steam_id = steam.getSteamID()
	steam.setLobbyData(id, LOBBY_TAG_KEY, LOBBY_TAG)
	steam.setLobbyData(id, "name", "%s's squad" % steam.getPersonaName())
	steam.setLobbyJoinable(id, true)
	var p = make_peer.call()
	if p == null:
		failed.emit("Steam networking is missing from this build")
		return
	var err: int = p.create_host(0)
	if err != OK:
		failed.emit("Steam could not start hosting (%s)" % error_string(err))
		return
	peer = p
	ready.emit(peer)


func join() -> String:
	if steam == null:
		return "Steam is not running"
	if lobby_id == 0:
		return _connect_to(host_steam_id) if host_steam_id != 0 else "No Steam lobby to join"
	steam.connect("lobby_joined", _on_lobby_joined, CONNECT_ONE_SHOT)
	steam.joinLobby(lobby_id)
	return ""


func _on_lobby_joined(id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != ENTER_SUCCESS:
		# The lobby can be gone while its host is still up (a reconnect after the host's lobby
		# timed out): fall back to connecting to the host directly.
		if host_steam_id != 0:
			var err := _connect_to(host_steam_id)
			if err != "":
				failed.emit(err)
			return
		failed.emit(_enter_reason(response))
		return
	lobby_id = id
	if steam.getLobbyData(id, LOBBY_TAG_KEY) != LOBBY_TAG:
		steam.leaveLobby(id)
		failed.emit("That Steam lobby isn't a Carriers game")
		return
	var owner: int = steam.getLobbyOwner(id)
	if owner == steam.getSteamID():
		failed.emit("That's your own lobby")
		return
	var err := _connect_to(owner)
	if err != "":
		failed.emit(err)


func _connect_to(owner: int) -> String:
	host_steam_id = owner
	var p = make_peer.call()
	if p == null:
		return "Steam networking is missing from this build"
	var err: int = p.create_client(owner, 0)
	if err != OK:
		return "Could not reach the host over Steam (%s)" % error_string(err)
	peer = p
	ready.emit.call_deferred(peer)
	return ""


static func _enter_reason(response: int) -> String:
	match response:
		2: return "That Steam lobby no longer exists"
		4: return "That game is full"
		5: return "Steam had a problem entering the lobby"
		6: return "You're banned from that lobby"
		7, 8: return "You can't join that lobby"
	return "Could not enter the Steam lobby (code %d)" % response


func rejoin_copy() -> NetTransport:
	var t := SteamTransport.new(steam, lobby_id, host_steam_id)
	t.make_peer = make_peer
	return t


func describe() -> String:
	return "the Steam lobby"


func player_id() -> String:
	return "steam:%d" % steam.getSteamID() if steam != null else ""


## Opens the Steam overlay's invite dialog for this lobby.
func invite_friends() -> bool:
	if steam == null or lobby_id == 0:
		return false
	steam.activateGameOverlayInviteDialog(lobby_id)
	return true


func close() -> void:
	super.close()
	if steam != null and lobby_id != 0:
		steam.leaveLobby(lobby_id)
