class_name PlaytestLog
extends RefCounted
## Appends one line per notable event to user://playtest_log.txt so balance can use real numbers:
## time to first purchase, wave durations, deaths per wave. Never read by the game itself.

const PATH := "user://playtest_log.txt"

static var _session_start_msec := -1


static func event(name: String, fields: Dictionary = {}) -> void:
	if _session_start_msec < 0:
		_session_start_msec = Time.get_ticks_msec()
	var parts := PackedStringArray()
	for key in fields:
		parts.append("%s=%s" % [key, str(fields[key])])
	var line := "%s t=%.1f %s %s\n" % [
		Time.get_datetime_string_from_system(true), session_seconds(), name, " ".join(parts)]
	var file := FileAccess.open(PATH, FileAccess.READ_WRITE if FileAccess.file_exists(PATH) else FileAccess.WRITE)
	if file:
		file.seek_end()
		file.store_string(line)
		file.close()


static func session_seconds() -> float:
	if _session_start_msec < 0:
		_session_start_msec = Time.get_ticks_msec()
	return (Time.get_ticks_msec() - _session_start_msec) / 1000.0
