class_name CrashReporter
extends RefCounted
## Notices when the last session ended without a clean exit (a crash, a freeze the player killed,
## a power cut) and saves a report: the game version, when that session started, and the end of
## its log. The title screen mentions the report. If `carriers/crash_reports/url` is set in the
## project settings, reports are also POSTed there as plain text (e.g. a Discord webhook relay or
## a small form endpoint); it's empty by default, so nothing leaves the player's PC.

const LOCK := "user://running.lock"
const DIR := "user://crash_reports"
const LOGS := "user://logs"
const KEEP := 10
const LOG_LINES := 200

var lock_path := LOCK
var dir := DIR
var logs_dir := LOGS


## Call once at startup. Returns the path of a new crash report, or "" if the last run was clean.
func start() -> String:
	var report := ""
	if FileAccess.file_exists(lock_path):
		report = _write_report(FileAccess.get_file_as_string(lock_path))
	var f := FileAccess.open(lock_path, FileAccess.WRITE)
	if f:
		f.store_string("version=%s\nstarted=%s\nos=%s\nargs=%s\n" % [version(), Time.get_datetime_string_from_system(true),
			OS.get_name(), " ".join(OS.get_cmdline_user_args())])
	return report


## Call on a clean exit.
func stop() -> void:
	if FileAccess.file_exists(lock_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(lock_path))


static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "dev"))


func _write_report(lock_text: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var stamp := Time.get_datetime_string_from_system(true).replace(":", "-")
	var path := "%s/crash-%s.txt" % [dir, stamp]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string("Carriers crash report\nThe previous session did not exit cleanly.\n\n%s\n--- end of that session's log ---\n%s\n" % [
		lock_text.strip_edges(), _previous_log_tail()])
	f.close()
	_prune()
	return path


## Godot rotates the last session's godot.log to godot<timestamp>.log when a new one starts,
## so the newest rotated log is the one that crashed.
func _previous_log_tail() -> String:
	var d := DirAccess.open(logs_dir)
	if d == null:
		return "(no log found)"
	var newest := ""
	var newest_time := 0
	for name in d.get_files():
		if not name.ends_with(".log") or name == "godot.log":
			continue
		var t := FileAccess.get_modified_time(logs_dir + "/" + name)
		if t >= newest_time:
			newest_time = t
			newest = name
	if newest == "":
		return "(no log found)"
	var lines := FileAccess.get_file_as_string(logs_dir + "/" + newest).split("\n")
	return "\n".join(lines.slice(maxi(0, lines.size() - LOG_LINES)))


func _prune() -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	var names := Array(d.get_files()).filter(func(n: String) -> bool: return n.begins_with("crash-"))
	names.sort()
	while names.size() > KEEP:
		d.remove(names.pop_front())


## Where reports go, or "" to keep them local.
static func upload_url() -> String:
	return str(ProjectSettings.get_setting("carriers/crash_reports/url", ""))
