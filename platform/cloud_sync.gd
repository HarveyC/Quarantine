class_name CloudSync
extends RefCounted
## Mirrors the save files to Steam Cloud (ISteamRemoteStorage), so a run and the profile follow the
## player to another PC or a Steam Deck. On startup the newer copy of each file wins; while
## playing, changed files go up every few seconds and once more on quit. A file deleted here (a
## finished run's save) is deleted from the cloud too, so it doesn't come back next launch.

const FILES := ["user://profile.cfg", "user://run_save.txt"]

var steam
## The files to sync (tests point this elsewhere).
var files: Array = FILES.duplicate()
## path -> local modified time when we last synced it (0 = the file didn't exist).
var _synced := {}


func _init(p_steam = null) -> void:
	steam = p_steam


func enabled() -> bool:
	if steam == null:
		return false
	if steam.has_method("isCloudEnabledForAccount") and not steam.isCloudEnabledForAccount():
		return false
	if steam.has_method("isCloudEnabledForApp") and not steam.isCloudEnabledForApp():
		return false
	return true


static func cloud_name(path: String) -> String:
	return path.get_file()


static func local_time(path: String) -> int:
	return FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0


## Startup: takes the cloud copy of any file that is newer there (or missing here).
## Returns the files it replaced.
func pull() -> Array[String]:
	var got: Array[String] = []
	if not enabled():
		return got
	for path in files:
		var name := cloud_name(path)
		if steam.fileExists(name):
			var cloud_time: int = steam.getFileTimestamp(name)
			if cloud_time > local_time(path):
				var res: Dictionary = steam.fileRead(name, steam.getFileSize(name))
				var buf: PackedByteArray = res.get("buf", PackedByteArray())
				if res.get("ret", false) and not buf.is_empty():
					var f := FileAccess.open(path, FileAccess.WRITE)
					if f:
						f.store_buffer(buf)
						f.close()
						got.append(path)
		_synced[path] = local_time(path)
	return got


## Uploads files that changed since the last sync and deletes cloud copies of removed ones.
## Returns the files it touched.
func push() -> Array[String]:
	var done: Array[String] = []
	if not enabled():
		return done
	for path in files:
		var now := local_time(path)
		if _synced.has(path) and _synced[path] == now:
			continue
		var name := cloud_name(path)
		if now == 0:
			if steam.fileExists(name):
				steam.fileDelete(name)
				done.append(path)
		else:
			var buf := FileAccess.get_file_as_bytes(path)
			if steam.fileWrite(name, buf, buf.size()):
				done.append(path)
			else:
				continue   # try again next time
		_synced[path] = now
	return done
