class_name SaveFile
extends RefCounted
## Reads and writes the one save file: user://save.json, plain JSON with a version number.
## Loading an older version migrates it step by step; an unknown version keeps a backup copy and
## starts fresh. Unknown item ids are dropped with a warning instead of crashing. Only the bench saves.

const PATH := "user://save.json"
const BACKUP_PATH := "user://save.backup.json"
const VERSION := 2


## The empty version-2 save a new player starts from.
static func fresh() -> Dictionary:
	return {
		"version": VERSION,
		"credits": 0,
		"core_levels": {},
		"waves": {"highest_cleared": 0, "first_clears": []},
		"inventory": [],
		"equipped": {},
		"skills": {},
		"story_flags": [],
		"tier": 0,
		"seed": randi(),
		"records": {"kills": 0, "credits_earned": 0, "deaths": 0, "waves_cleared": 0},
	}


## Returns the loaded, migrated and validated save, or a fresh one when there is none.
static func load_or_fresh() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return fresh()
	var text := FileAccess.get_file_as_string(PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("Save file is not valid JSON; starting fresh and keeping a backup.")
		_backup(text)
		return fresh()
	return migrate(parsed)


## Brings any supported save up to VERSION and fills in missing fields. Public for tests.
static func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 0))
	if version > VERSION or version < 1:
		push_warning("Save version %d is unknown; starting fresh and keeping a backup." % version)
		_backup(JSON.stringify(data))
		return fresh()
	if version == 1:
		data = _migrate_1_to_2(data)
	return sanitize(data)


## Version 1 was the original Milestone 2 spec: credits, upgrade levels and the highest wave.
static func _migrate_1_to_2(old: Dictionary) -> Dictionary:
	var data := fresh()
	data["credits"] = int(old.get("credits", 0))
	var upgrades: Variant = old.get("upgrades", {})
	if upgrades is Dictionary:
		for key in upgrades:
			data["core_levels"][String(key)] = int(upgrades[key])
	var highest := int(old.get("highest_wave", 0))
	data["waves"]["highest_cleared"] = highest
	for wave in range(1, highest + 1):
		data["waves"]["first_clears"].append(wave)
	return data


## Coerces every field to its expected type and drops items that no longer resolve.
static func sanitize(data: Dictionary) -> Dictionary:
	var clean := fresh()
	clean["seed"] = int(data.get("seed", clean["seed"]))
	clean["credits"] = maxi(int(data.get("credits", 0)), 0)
	clean["tier"] = maxi(int(data.get("tier", 0)), 0)
	var levels: Variant = data.get("core_levels", {})
	if levels is Dictionary:
		for key in levels:
			if CoreTuning.get_definition(StringName(String(key))) != null:
				clean["core_levels"][String(key)] = maxi(int(levels[key]), 0)
			else:
				push_warning("Dropping unknown core tuning '%s' from the save." % str(key))
	var waves: Variant = data.get("waves", {})
	if waves is Dictionary:
		clean["waves"]["highest_cleared"] = maxi(int(waves.get("highest_cleared", 0)), 0)
		for wave in waves.get("first_clears", []):
			if (wave is int or wave is float) and int(wave) > 0 and not clean["waves"]["first_clears"].has(int(wave)):
				clean["waves"]["first_clears"].append(int(wave))
	for item in data.get("inventory", []):
		if Items.is_valid(item):
			clean["inventory"].append(Items.normalize(item))
	var equipped: Variant = data.get("equipped", {})
	if equipped is Dictionary:
		for slot in equipped:
			var item: Variant = equipped[slot]
			if Items.SLOT_IDS.has(StringName(String(slot))) and Items.is_valid(item):
				clean["equipped"][String(slot)] = Items.normalize(item)
	var skills: Variant = data.get("skills", {})
	if skills is Dictionary:
		for key in skills:
			clean["skills"][String(key)] = int(skills[key])
	for flag in data.get("story_flags", []):
		if flag is String:
			clean["story_flags"].append(flag)
	var records: Variant = data.get("records", {})
	if records is Dictionary:
		for key in clean["records"]:
			clean["records"][key] = maxi(int(records.get(key, 0)), 0)
	return clean


static func save(data: Dictionary) -> bool:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write the save file (error %d)." % FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	return true


static func delete() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


static func _backup(text: String) -> void:
	var file := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
	if file:
		file.store_string(text)
		file.close()
