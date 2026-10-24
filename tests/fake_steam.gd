extends RefCounted
## Stand-in for the GodotSteam singleton: just the calls Carriers makes, answering synchronously.

signal lobby_created(result: int, lobby_id: int)
signal lobby_joined(lobby_id: int, permissions: int, locked: bool, response: int)
signal join_requested(lobby_id: int, friend_id: int)
signal join_game_requested(friend_id: int, connect: String)

var init_status := 0
var my_id := 1001
var lobby_result := 1
var join_response := 1
var lobby_owner := 2002
var lobby_data := {}
var presence := {}
var achievements := {}
var stats := {}
var stored := 0
var invited := 0
var left := []
var cloud := {}          # name -> {"data": PackedByteArray, "time": int}
var cloud_on := true
var callbacks := 0


func steamInitEx(_app_id: int, _embed: bool) -> Dictionary:
	return {"status": init_status, "verbal": "fake status %d" % init_status}


func run_callbacks() -> void:
	callbacks += 1


func getSteamID() -> int:
	return my_id


func getPersonaName() -> String:
	return "Harvey"


func createLobby(_type: int, _max: int) -> void:
	lobby_created.emit(lobby_result, 99 if lobby_result == 1 else 0)


func joinLobby(id: int) -> void:
	lobby_data.get_or_add(id, {"game": "carriers"})
	lobby_joined.emit(id, 0, false, join_response)


func leaveLobby(id: int) -> void:
	left.append(id)


func setLobbyData(id: int, key: String, value: String) -> bool:
	lobby_data.get_or_add(id, {})[key] = value
	return true


func getLobbyData(id: int, key: String) -> String:
	return lobby_data.get(id, {}).get(key, "")


func setLobbyJoinable(_id: int, _on: bool) -> bool:
	return true


func getLobbyOwner(_id: int) -> int:
	return lobby_owner


func activateGameOverlayInviteDialog(_id: int) -> void:
	invited += 1


func clearRichPresence() -> void:
	presence = {}


func setRichPresence(key: String, value: String) -> bool:
	presence[key] = value
	return true


func setAchievement(name: String) -> bool:
	achievements[name] = true
	return true


func setStatInt(name: String, value: int) -> bool:
	stats[name] = value
	return true


func storeStats() -> bool:
	stored += 1
	return true


func isCloudEnabledForAccount() -> bool:
	return cloud_on


func isCloudEnabledForApp() -> bool:
	return cloud_on


func fileExists(name: String) -> bool:
	return cloud.has(name)


func getFileTimestamp(name: String) -> int:
	return cloud[name].time


func getFileSize(name: String) -> int:
	return cloud[name].data.size()


func fileRead(name: String, _size: int) -> Dictionary:
	return {"ret": true, "buf": cloud[name].data}


func fileWrite(name: String, data: PackedByteArray, _size: int = 0) -> bool:
	cloud[name] = {"data": data, "time": int(Time.get_unix_time_from_system())}
	return true


func fileDelete(name: String) -> bool:
	return cloud.erase(name)
