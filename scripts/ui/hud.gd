class_name Hud
extends CanvasLayer
## In-combat HUD: crosshair and hit markers, health, ammo, reload progress, kills, credits, wave
## progress, the boss bar, loot pickup notes, the wave-cleared banner and the death screen. Since
## Milestone 5 also the Charge receiver's meter, the gun's status (Overclock, grenades), the
## Scanner's reading and the story card (VERA's lines and the boss intro cards). Every widget is
## built once; text only changes when what it shows changes.

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
## Story cards: seconds a line stays (plus a little per character), and the fade.
const STORY_CARD_TIME := 4.0
const STORY_CARD_PER_CHAR := 0.03
const STORY_CARD_FADE := 0.6
const MAX_SCAN_MARKERS := 6
const STORY_SPEAKER_COLOR := Color(0.55, 0.9, 1.0)

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
var _charge_bar: ProgressBar
var _status_label: Label
var _scan_label: Label
var _story_card: PanelContainer
var _story_speaker: Label
var _story_text: Label
var _story_left := 0.0
## Lines waiting for the card, [speaker, text] each, shown in order.
var _story_queue: Array = []
## Scanner optic: a diamond over each marked robot (turrets), reused in turn; see set_scan_targets.
var _scan_markers: Array[Control] = []
var _scan_targets: Array[Enemy] = []
var _scan_active := false
var _scan_camera: Camera3D

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
	_build_milestone_5_widgets()


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
	if _story_left > 0.0:
		_story_left -= delta
		if _story_left <= 0.0:
			_story_card.visible = false
			if not _story_queue.is_empty():
				var line: Array = _story_queue.pop_front()
				show_story(String(line[0]), String(line[1]))
		elif _story_left < STORY_CARD_FADE:
			_story_card.modulate.a = _story_left / STORY_CARD_FADE
	if _scan_active:
		_place_scan_markers()
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
		_charge_bar.visible = false
		hide_story()
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
	show_note(text, Items.rarity_color(item))
	_pickup_sound.play()


## A line in the note stack (a pickup, a level, Phoenix): the free label or the oldest one.
func show_note(text: String, color: Color) -> void:
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
	note.add_theme_color_override("font_color", color)
	note.modulate.a = 1.0
	note.visible = true
	_note_ages[index] = 0.0
	_pickup_notes.move_child(note, _pickup_notes.get_child_count() - 1)


func pickup_note_count() -> int:
	var count := 0
	for age in _note_ages:
		if age >= 0.0:
			count += 1
	return count


# ------------------------------------------------------------------ banners

func show_wave_cleared(number: int, bonus: int, first_clear: bool, granted: Dictionary = {}) -> void:
	var detail := "+%d credits%s" % [bonus, "" if first_clear else "  (replay)"]
	if not granted.is_empty():
		detail += "\n+ %s  ·  %s" % [Items.display_name(granted), Items.rarity_name(granted)]
	show_banner("WAVE %d CLEARED" % number, detail)


func banner_detail() -> String:
	return _banner_detail.text


## The centre banner (a wave clear, a Scrapyard extraction), faded in.
func show_banner(title: String, detail: String) -> void:
	_banner_title.text = title
	_banner_detail.text = detail
	_banner.visible = true
	_banner.modulate.a = 0.0
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.25)


## `area` names the side area the player died in, instead of the wave.
func show_death(wave: int, kills: int, credits_kept: int, area := "") -> void:
	_reload_bar.visible = false
	_banner.visible = false
	var where := area if area != "" else "Wave %d" % wave
	_death_summary.text = "%s  ·  %d kills  ·  %d credits kept" % [where, kills, credits_kept]
	_death_panel.visible = true
	%BenchButton.grab_focus()


func hide_death() -> void:
	_death_panel.visible = false


# ------------------------------------------------------------------ Milestone 5

func _build_milestone_5_widgets() -> void:
	_charge_bar = _reload_bar.duplicate() as ProgressBar
	_charge_bar.name = "ChargeBar"
	_charge_bar.offset_top = 40.0
	_charge_bar.offset_bottom = 48.0
	_charge_bar.modulate = Color(0.6, 0.9, 1.0)
	_charge_bar.visible = false
	_combat_group.add_child(_charge_bar)
	_status_label = _outlined_label(20, 6, Color(0.55, 0.9, 1.0))
	_status_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_status_label.offset_left = -300.0
	_status_label.offset_top = -126.0
	_status_label.offset_right = -28.0
	_status_label.offset_bottom = -96.0
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combat_group.add_child(_status_label)
	_scan_label = _outlined_label(16, 5, Color(0.7, 1.0, 0.75))
	_scan_label.set_anchors_preset(Control.PRESET_CENTER)
	_scan_label.offset_left = -200.0
	_scan_label.offset_right = 200.0
	_scan_label.offset_top = 54.0
	_scan_label.offset_bottom = 78.0
	_scan_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combat_group.add_child(_scan_label)
	_story_card = PanelContainer.new()
	_story_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.1, 0.78)
	style.border_color = Color(0.3, 0.6, 0.75, 0.8)
	style.border_width_left = 3
	style.set_content_margin_all(10)
	_story_card.add_theme_stylebox_override("panel", style)
	_story_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_story_card.offset_left = -330.0
	_story_card.offset_right = 330.0
	_story_card.offset_top = 150.0
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_story_speaker = _outlined_label(16, 5, STORY_SPEAKER_COLOR)
	_story_text = _outlined_label(18, 6, Color(0.92, 0.95, 1.0))
	_story_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_story_text.custom_minimum_size = Vector2(620, 0)
	box.add_child(_story_speaker)
	box.add_child(_story_text)
	_story_card.add_child(box)
	_story_card.visible = false
	add_child(_story_card)
	for i in MAX_SCAN_MARKERS:
		var marker := ColorRect.new()
		marker.color = Color(0.7, 1.0, 0.75, 0.85)
		marker.size = Vector2(14, 14)
		marker.pivot_offset = Vector2(7, 7)
		marker.rotation = PI / 4.0
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.visible = false
		_combat_group.add_child(marker)
		_scan_markers.append(marker)
		_scan_targets.append(null)


func _outlined_label(size: int, outline: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_constant_override("outline_size", outline)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## The Charge receiver's meter under the crosshair; a negative fraction hides it.
func set_charge(fraction: float) -> void:
	if fraction < 0.0:
		_charge_bar.visible = false
		return
	_charge_bar.visible = true
	_charge_bar.value = fraction


func set_gun_status(text: String) -> void:
	_status_label.text = text


func gun_status() -> String:
	return _status_label.text


## The Scanner's reading of the robot under the crosshair; an empty name clears it.
func set_scan(name: String, health: float, maximum: float) -> void:
	_scan_label.text = "" if name == "" else "%s  %d / %d" % [name.to_upper(), mini(ceili(health - 0.001), roundi(maximum)), roundi(maximum)]


func scan_text() -> String:
	return _scan_label.text


## A story card at the top of the view: who speaks and the line. Never blocks play; it fades on
## its own (plan: every line is skippable, nothing in the story gates progression).
func show_story(speaker: String, text: String) -> void:
	_story_speaker.text = speaker.to_upper()
	_story_text.text = text
	_story_card.visible = true
	_story_card.modulate.a = 1.0
	_story_left = STORY_CARD_TIME + text.length() * STORY_CARD_PER_CHAR


func hide_story() -> void:
	_story_left = 0.0
	_story_queue.clear()
	_story_card.visible = false


## Shows a trigger's lines one after another ([[speaker, text], ...]); appends when a card is up.
func queue_story(lines: Array) -> void:
	for line in lines:
		_story_queue.append(line)
	if not _story_card.visible and not _story_queue.is_empty():
		var first: Array = _story_queue.pop_front()
		show_story(String(first[0]), String(first[1]))


func story_queue_size() -> int:
	return _story_queue.size()


## The Scanner marks a robot through walls (EnemyDefinition.scanner_marked) while it is fitted:
## a diamond over it each frame until it dies. The markers and their slots are a fixed set built
## with the HUD, so marking builds nothing mid-wave; a full set reuses a dead robot's slot.
func add_scan_target(camera: Camera3D, enemy: Enemy) -> void:
	_scan_camera = camera
	for i in _scan_targets.size():
		var held := _scan_targets[i]
		if held == null or not is_instance_valid(held) or not held.is_alive:
			_scan_targets[i] = enemy
			_scan_active = true
			return


func clear_scan_targets() -> void:
	for i in _scan_targets.size():
		_scan_targets[i] = null
	for marker in _scan_markers:
		marker.visible = false
	_scan_active = false


func visible_scan_markers() -> int:
	var count := 0
	for marker in _scan_markers:
		if marker.visible:
			count += 1
	return count


func _place_scan_markers() -> void:
	var shown := 0
	if _scan_camera != null and is_instance_valid(_scan_camera) and _combat_group.visible:
		for enemy in _scan_targets:
			if enemy == null or not is_instance_valid(enemy) or not enemy.is_alive or not enemy.is_inside_tree():
				continue
			var at := enemy.center() + Vector3.UP * 1.4
			if _scan_camera.is_position_behind(at):
				continue
			var marker := _scan_markers[shown]
			marker.position = _scan_camera.unproject_position(at) - marker.size * 0.5
			marker.visible = true
			shown += 1
	for i in range(shown, _scan_markers.size()):
		_scan_markers[i].visible = false


func is_story_visible() -> bool:
	return _story_card.visible


func story_text() -> String:
	return _story_text.text


func set_capture_prompt_visible(value: bool) -> void:
	_capture_prompt.visible = value


func set_controls_hint(text: String) -> void:
	_controls_hint.text = text


func is_death_screen_visible() -> bool:
	return _death_panel.visible
