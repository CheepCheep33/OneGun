extends Node
## Player-facing options, autoloaded as `Settings`.
## Saved to user://settings.cfg. Missing, unreadable, or wrongly typed values fall back to defaults.

signal changed

const SAVE_PATH := "user://settings.cfg"
const MOUSE_SENSITIVITY_RANGE := Vector2(0.1, 5.0)
const FIELD_OF_VIEW_RANGE := Vector2(60.0, 110.0)
const CAMERA_RECOIL_RANGE := Vector2(0.0, 2.0)

var mouse_sensitivity := 1.0
var field_of_view := 80.0
## Scales how far each shot kicks the camera. 0 disables camera recoil entirely.
var camera_recoil := 1.0
var show_damage_numbers := true
var master_volume := 0.8


func _ready() -> void:
	load_settings()


## Changes one option and applies it immediately. Call save_settings() when the player is done editing.
func set_value(key: StringName, value: Variant) -> void:
	set(key, value)
	_clamp_all()
	_apply_audio()
	changed.emit()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		mouse_sensitivity = _read(cfg, "input", "mouse_sensitivity", mouse_sensitivity)
		field_of_view = _read(cfg, "video", "field_of_view", field_of_view)
		camera_recoil = _read(cfg, "feedback", "camera_recoil", camera_recoil)
		show_damage_numbers = _read(cfg, "feedback", "show_damage_numbers", show_damage_numbers)
		master_volume = _read(cfg, "audio", "master_volume", master_volume)
	_clamp_all()
	_apply_audio()
	changed.emit()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("video", "field_of_view", field_of_view)
	cfg.set_value("feedback", "camera_recoil", camera_recoil)
	cfg.set_value("feedback", "show_damage_numbers", show_damage_numbers)
	cfg.set_value("audio", "master_volume", master_volume)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("Could not save settings (error %d)." % err)


func _read(cfg: ConfigFile, section: String, key: String, default_value: Variant) -> Variant:
	var value: Variant = cfg.get_value(section, key, default_value)
	if typeof(default_value) == TYPE_FLOAT and typeof(value) == TYPE_INT:
		return float(value)
	return value if typeof(value) == typeof(default_value) else default_value


func _clamp_all() -> void:
	mouse_sensitivity = clampf(mouse_sensitivity, MOUSE_SENSITIVITY_RANGE.x, MOUSE_SENSITIVITY_RANGE.y)
	field_of_view = clampf(field_of_view, FIELD_OF_VIEW_RANGE.x, FIELD_OF_VIEW_RANGE.y)
	camera_recoil = clampf(camera_recoil, CAMERA_RECOIL_RANGE.x, CAMERA_RECOIL_RANGE.y)
	master_volume = clampf(master_volume, 0.0, 1.0)


func _apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
