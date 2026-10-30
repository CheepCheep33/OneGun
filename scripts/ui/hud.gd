class_name Hud
extends CanvasLayer
## In-combat HUD: crosshair and hit markers, health, ammo, reload progress, kills, credits, wave
## progress, the boss bar, loot pickup notes, the wave-cleared banner and the death screen.

## The death screen's button: go back to the bench.
signal bench_requested

const LOW_AMMO_FRACTION := 0.3
const PICKUP_NOTE_TIME := 3.2
const PICKUP_NOTE_FADE := 0.5
const MAX_PICKUP_NOTES := 4
## Font and outline sizes of every text that changes during play, for warm_up_text: the first glyph
## at a new size allocates a font atlas page and each new glyph re-uploads it, which the browser
## would otherwise do at the first pickup, boss, banner or death.
const WARM_UP_TEXT_STYLES := [[15, 4], [16, 5], [17, 0], [18, 6], [20, 0], [20, 6], [22, 0], [22, 6], [28, 8], [30, 8], [44, 8], [54, 10], [64, 10]]
const WARM_UP_TEXT := "THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG the quick brown fox jumps over the lazy dog 0123456789 / + - · → ( ) % , . : ! ' ms fps left"

const FPS_WINDOW := 0.5

var _vignette_alpha := 0.0
var _fps_frames := 0
var _fps_elapsed := 0.0
var _fps_worst := 0.0
var _reload_total := 0.0
var _reload_elapsed := 0.0
var _credit_pop: Tween
var _banner_tween: Tween
## The pickup notes, built once (MAX_PICKUP_NOTES) and reused; a note's age is -1 while hidden.
var _notes: Array[Label] = []
var _note_ages: Array[float] = []

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
	for i in MAX_PICKUP_NOTES:
		var note := Label.new()
		note.add_theme_font_size_override("font_size", 18)
		note.add_theme_color_override("font_outline_color", Color.BLACK)
		note.add_theme_constant_override("outline_size", 6)
		note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		note.visible = false
		_pickup_notes.add_child(note)
		_notes.append(note)
		_note_ages.append(-1.0)


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
	for i in _notes.size():
		if _note_ages[i] < 0.0:
			continue
		_note_ages[i] += delta
		if _note_ages[i] >= PICKUP_NOTE_TIME + PICKUP_NOTE_FADE:
			_note_ages[i] = -1.0
			_notes[i].visible = false
		elif _note_ages[i] > PICKUP_NOTE_TIME:
			_notes[i].modulate.a = 1.0 - (_note_ages[i] - PICKUP_NOTE_TIME) / PICKUP_NOTE_FADE


## Draws every size of text the HUD shows during play once, invisibly, so the font atlas pages
## exist and hold the glyphs before the first wave (GAME_PLAN.md, "Performance budget").
func warm_up_text() -> void:
	var labels: Array[Label] = []
	for style in WARM_UP_TEXT_STYLES:
		var label := Label.new()
		label.text = WARM_UP_TEXT
		label.add_theme_font_size_override("font_size", int(style[0]))
		label.add_theme_constant_override("outline_size", int(style[1]))
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.modulate = Color(1.0, 1.0, 1.0, 0.0)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		labels.append(label)
	for i in 3:
		await get_tree().process_frame
	for label in labels:
		label.queue_free()


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
		for i in _notes.size():
			_note_ages[i] = -1.0
			_notes[i].visible = false


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

## One line per item that arrived, coloured by rarity, fading after a few seconds. Notes are a
## fixed set of labels reused in turn (nothing is built or freed mid-wave); the newest sits lowest.
func show_pickup(item: Dictionary, destination: String) -> void:
	var text := "%s  ·  %s" % [Items.display_name(item), Items.rarity_name(item)]
	match destination:
		"overflow":
			text += "  →  overflow tray"
		"dismantled":
			text += "  →  inventory full, turned to parts"
		"bumped":
			text += "  →  tray (a lesser item became parts)"
	var index := -1
	var oldest := 0
	for i in _notes.size():
		if _note_ages[i] < 0.0:
			index = i
			break
		if _note_ages[i] > _note_ages[oldest]:
			oldest = i
	if index == -1:
		index = oldest
	var note := _notes[index]
	note.text = text
	note.add_theme_color_override("font_color", Items.rarity_color(item))
	note.modulate.a = 1.0
	note.visible = true
	_note_ages[index] = 0.0
	_pickup_notes.move_child(note, _pickup_notes.get_child_count() - 1)
	_pickup_sound.play()


func pickup_note_count() -> int:
	var count := 0
	for age in _note_ages:
		if age >= 0.0:
			count += 1
	return count


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
