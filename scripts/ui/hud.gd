class_name Hud
extends CanvasLayer
## In-combat HUD: crosshair and hit markers, health, ammo, reload progress, kills, credits, wave
## progress, the boss bar, loot pickup notes, the wave-cleared banner and the death screen.

## The death screen's button: go back to the bench.
signal bench_requested

const LOW_AMMO_FRACTION := 0.3
const PICKUP_NOTE_TIME := 3.2
const MAX_PICKUP_NOTES := 4

const FPS_WINDOW := 0.5

var _vignette_alpha := 0.0
var _fps_frames := 0
var _fps_elapsed := 0.0
var _fps_worst := 0.0
var _reload_total := 0.0
var _reload_elapsed := 0.0
var _credit_pop: Tween
var _banner_tween: Tween

@onready var _vignette: ColorRect = $DamageVignette
@onready var _crosshair: Control = $Crosshair
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _health_label: Label = %HealthLabel
@onready var _ammo_label: Label = %AmmoLabel
@onready var _reload_bar: ProgressBar = %ReloadBar
@onready var _kills_label: Label = %KillsLabel
@onready var _credits_label: Label = %CreditsLabel
@onready var _credit_gain_label: Label = %CreditGainLabel
@onready var _wave_label: Label = %WaveLabel
@onready var _wave_progress_label: Label = %WaveProgressLabel
@onready var _boss_box: Control = %BossBox
@onready var _boss_name: Label = %BossName
@onready var _boss_bar: ProgressBar = %BossBar
@onready var _pickup_notes: VBoxContainer = %PickupNotes
@onready var _banner: Control = %ClearedBanner
@onready var _banner_title: Label = %ClearedTitle
@onready var _banner_detail: Label = %ClearedDetail
@onready var _combat_group: Control = $Combat
@onready var _capture_prompt: Label = %CapturePrompt
@onready var _fps_label: Label = %FpsLabel
@onready var _controls_hint: Label = $Combat/ControlsHint
@onready var _death_panel: Control = $DeathPanel
@onready var _death_summary: Label = %DeathSummary
@onready var _hit_sound: AudioStreamPlayer = $HitSound
@onready var _kill_sound: AudioStreamPlayer = $KillSound
@onready var _pickup_sound: AudioStreamPlayer = $PickupSound


func _ready() -> void:
	_death_panel.visible = false
	_reload_bar.visible = false
	_banner.visible = false
	_boss_box.visible = false
	_credit_gain_label.modulate.a = 0.0
	_fps_label.visible = false
	%BenchButton.pressed.connect(func() -> void: bench_requested.emit())


func _process(delta: float) -> void:
	if _fps_label.visible:
		_fps_frames += 1
		_fps_elapsed += delta
		_fps_worst = maxf(_fps_worst, delta)
		if _fps_elapsed >= FPS_WINDOW:
			_fps_label.text = "%d fps  ·  worst frame %d ms" % [roundi(_fps_frames / _fps_elapsed), roundi(_fps_worst * 1000.0)]
			_fps_frames = 0
			_fps_elapsed = 0.0
			_fps_worst = 0.0
	if _vignette_alpha > 0.0:
		_vignette_alpha = maxf(_vignette_alpha - delta * 1.2, 0.0)
		_vignette.color.a = _vignette_alpha
	if _reload_bar.visible:
		_reload_elapsed += delta
		_reload_bar.value = clampf(_reload_elapsed / _reload_total, 0.0, 1.0)


## The frame-rate readout (pause menu: Show FPS). Shows the average and the worst frame of each
## half second, so a stutter reads as a spike even when the average looks fine.
func set_fps_visible(value: bool) -> void:
	_fps_label.visible = value
	_fps_frames = 0
	_fps_elapsed = 0.0
	_fps_worst = 0.0
	if value:
		_fps_label.text = "measuring..."


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


func set_credits(credits: int) -> void:
	_credits_label.text = "CREDITS  %d" % credits


## Small "+N" pop beside the credits counter when a kill pays out.
func show_credit_gain(amount: int) -> void:
	_credit_gain_label.text = "+%d" % amount
	if _credit_pop:
		_credit_pop.kill()
	_credit_gain_label.modulate.a = 1.0
	_credit_pop = create_tween()
	_credit_pop.tween_property(_credit_gain_label, "modulate:a", 0.0, 0.6).set_delay(0.35)


func set_wave(number: int, display_name: String) -> void:
	_wave_label.text = "WAVE %d  ·  %s" % [number, display_name.to_upper()]


## Free-form title and progress line, for side areas.
func set_wave_text(title: String, progress: String) -> void:
	_wave_label.text = title
	_wave_progress_label.text = progress


func set_wave_progress(remaining: int, total: int) -> void:
	_wave_progress_label.text = "%d / %d left" % [remaining, total]


func set_wave_progress_text(text: String) -> void:
	_wave_progress_label.text = text


## Hides the combat readouts while the bench is open so it is not drawn under the panels.
func set_combat_visible(value: bool) -> void:
	_combat_group.visible = value
	_crosshair.visible = value
	if not value:
		_banner.visible = false
		_reload_bar.visible = false
		for note in _pickup_notes.get_children():
			note.queue_free()


# ------------------------------------------------------------------ boss bar

func show_boss(name: String, current: float, maximum: float) -> void:
	_boss_name.text = name.to_upper()
	_boss_box.visible = true
	set_boss_health(current, maximum)


func set_boss_health(current: float, maximum: float) -> void:
	_boss_bar.max_value = maxf(maximum, 1.0)
	_boss_bar.value = clampf(current, 0.0, maximum)


func hide_boss() -> void:
	_boss_box.visible = false


func is_boss_bar_visible() -> bool:
	return _boss_box.visible


# ------------------------------------------------------------------ loot notes

## One line per item that arrived, coloured by rarity, fading after a few seconds.
func show_pickup(item: Dictionary, destination: String) -> void:
	var text := "%s  ·  %s" % [Items.display_name(item), Items.rarity_name(item)]
	match destination:
		"overflow":
			text += "  →  overflow tray"
		"dismantled":
			text += "  →  inventory full, turned to parts"
		"bumped":
			text += "  →  tray (a lesser item became parts)"
	var note := Label.new()
	note.text = text
	note.add_theme_font_size_override("font_size", 18)
	note.add_theme_color_override("font_outline_color", Color.BLACK)
	note.add_theme_constant_override("outline_size", 6)
	note.add_theme_color_override("font_color", Items.rarity_color(item))
	_pickup_notes.add_child(note)
	while _pickup_notes.get_child_count() > MAX_PICKUP_NOTES:
		var oldest := _pickup_notes.get_child(0)
		_pickup_notes.remove_child(oldest)
		oldest.queue_free()
	_pickup_sound.play()
	var tween := note.create_tween()
	tween.tween_property(note, "modulate:a", 0.0, 0.5).set_delay(PICKUP_NOTE_TIME)
	tween.tween_callback(note.queue_free)


func pickup_note_count() -> int:
	return _pickup_notes.get_child_count()


# ------------------------------------------------------------------ banners

func show_wave_cleared(number: int, bonus: int, first_clear: bool, granted: Dictionary = {}) -> void:
	_banner_title.text = "WAVE %d CLEARED" % number
	var detail := "+%d credits%s" % [bonus, "" if first_clear else "  (replay)"]
	if not granted.is_empty():
		detail += "\n+ %s  ·  %s" % [Items.display_name(granted), Items.rarity_name(granted)]
	_banner_detail.text = detail
	_banner.visible = true
	_banner.modulate.a = 0.0
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.25)


func show_death(wave: int, kills: int, credits_kept: int) -> void:
	_reload_bar.visible = false
	_banner.visible = false
	_death_summary.text = "Wave %d  ·  %d kills  ·  %d credits kept" % [wave, kills, credits_kept]
	_death_panel.visible = true
	%BenchButton.grab_focus()


func hide_death() -> void:
	_death_panel.visible = false


func set_capture_prompt_visible(value: bool) -> void:
	_capture_prompt.visible = value


func set_controls_hint(text: String) -> void:
	_controls_hint.text = text


func is_death_screen_visible() -> bool:
	return _death_panel.visible
