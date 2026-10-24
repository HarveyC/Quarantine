class_name RunSave
extends RefCounted
## The single run save slot (solo / hot-seat / host). Written after every run action and at the
## start of every team phase in a fight, so a crash loses at most one turn.

const PATH := "user://run_save.txt"


static func exists() -> bool:
	return FileAccess.file_exists(PATH)


static func write(run: RunState) -> void:
	if run.phase == RunState.Phase.ENDED:
		clear()
		return
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(run.save_string())


static func read() -> RunState:
	if not exists():
		return null
	return RunState.from_save_string(FileAccess.get_file_as_string(PATH))


static func clear() -> void:
	if exists():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


## Short description for a "Continue run" button.
static func summary(run: RunState) -> String:
	return "Act %d, row %d · %d player%s · Outbreak %d" % [run.act, run.row, run.players.size(),
		"" if run.players.size() == 1 else "s", run.outbreak]
