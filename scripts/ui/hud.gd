class_name Hud
extends CanvasLayer
## In-combat HUD: crosshair and hit markers, health, ammo, reload progress, kills, and the death screen.

signal restart_requested

const LOW_AMMO_FRACTION := 0.3

var _vignette_alpha := 0.0
var _reload_total := 0.0
var _reload_elapsed := 0.0

@onready var _vignette: ColorRect = $DamageVignette
@onready var _crosshair: Control = $Crosshair
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_label: Label = %HealthLabel
@onready var _ammo_label: Label = %AmmoLabel
@onready var _reload_bar: ProgressBar = %ReloadBar
@onready var _kills_label: Label = %KillsLabel
@onready var _capture_prompt: Label = %CapturePrompt
@onready var _death_panel: Control = $DeathPanel
@onready var _death_summary: Label = %DeathSummary
@onready var _hit_sound: AudioStreamPlayer = $HitSound
@onready var _kill_sound: AudioStreamPlayer = $KillSound


func _ready() -> void:
	_death_panel.visible = false
	_reload_bar.visible = false
	%RestartButton.pressed.connect(func() -> void: restart_requested.emit())


func _process(delta: float) -> void:
	if _vignette_alpha > 0.0:
		_vignette_alpha = maxf(_vignette_alpha - delta * 1.2, 0.0)
		_vignette.color.a = _vignette_alpha
	if _reload_bar.visible:
		_reload_elapsed += delta
		_reload_bar.value = clampf(_reload_elapsed / _reload_total, 0.0, 1.0)


func set_health(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_label.text = "HEALTH  %d" % ceili(current)


func flash_damage(_amount: float) -> void:
	_vignette_alpha = 0.45


func set_ammo(in_magazine: int, magazine_size: int) -> void:
	_ammo_label.text = "%d / %d" % [in_magazine, magazine_size]
	if in_magazine == 0:
		_ammo_label.modulate = Color(1.0, 0.3, 0.25)
	elif in_magazine <= ceili(magazine_size * LOW_AMMO_FRACTION):
		_ammo_label.modulate = Color(1.0, 0.75, 0.3)
	else:
		_ammo_label.modulate = Color.WHITE


func show_reload(duration: float) -> void:
	_reload_total = maxf(duration, 0.01)
	_reload_elapsed = 0.0
	_reload_bar.value = 0.0
	_reload_bar.visible = true


func hide_reload() -> void:
	_reload_bar.visible = false


func show_hit_marker(killed: bool) -> void:
	_crosshair.show_hit(killed)
	if killed:
		_kill_sound.play()
	else:
		_hit_sound.play()


func set_kills(kills: int) -> void:
	_kills_label.text = "KILLS  %d" % kills


func show_death(kills: int) -> void:
	_reload_bar.visible = false
	_death_summary.text = "Chasers destroyed: %d" % kills
	_death_panel.visible = true
	%RestartButton.grab_focus()


func set_capture_prompt_visible(value: bool) -> void:
	_capture_prompt.visible = value


func is_death_screen_visible() -> bool:
	return _death_panel.visible
