class_name Bench
extends CanvasLayer
## The intermission bench: core tuning purchases, the (locked) gunsmith slots, and wave select.
## Runs while the tree is paused. Reads and writes progression only through the Progression autoload,
## and every number it shows comes from the same WeaponStats functions combat uses.

signal start_wave_requested(number: int)

const CHASER_DEFINITION := preload("res://data/enemies/chaser.tres")
const LOCKED_COLOR := Color(0.6, 0.6, 0.62)

var selected_wave := 1
var _confirm_reset := false
var _core_rows: Dictionary = {} # tuning id -> {level, effect, button}
var _wave_buttons: Array[Button] = []

@onready var _credits_label: Label = %CreditsLabel
@onready var _core_rows_box: VBoxContainer = %CoreRows
@onready var _stats_summary: Label = %StatsSummary
@onready var _slot_grid: GridContainer = %SlotGrid
@onready var _wave_list: VBoxContainer = %WaveList
@onready var _wave_note: Label = %WaveNote
@onready var _start_button: Button = %StartButton
@onready var _reset_button: Button = %ResetButton
@onready var _greeting: Label = %Greeting


func _ready() -> void:
	visible = false
	_build_core_rows()
	_build_slot_grid()
	_build_wave_list()
	_start_button.pressed.connect(_on_start_pressed)
	_reset_button.pressed.connect(_on_reset_pressed)
	Progression.credits_changed.connect(func(_credits: int) -> void: if visible: refresh())
	Progression.progress_changed.connect(func() -> void: if visible: refresh())


func open() -> void:
	_confirm_reset = false
	_reset_button.text = "Reset progress"
	selected_wave = clampi(Progression.next_wave(), 1, WaveRunner.WAVE_COUNT)
	var records: Dictionary = Progression.data["records"]
	if Progression.highest_cleared_wave == 0 and int(records["deaths"]) == 0:
		_greeting.text = "Spend credits on your pistol between waves. Kills and wave clears pay. Start wave 1 when ready."
	else:
		_greeting.text = "Welcome back: %d kills, %d wave clears, %d credits earned so far." % [
			int(records["kills"]), int(records["waves_cleared"]), int(records["credits_earned"])]
	visible = true
	refresh()
	_start_button.grab_focus()


func close() -> void:
	visible = false


## Redraws every number from Progression. Cheap enough to call after each purchase.
func refresh() -> void:
	_credits_label.text = "CREDITS  %d" % Progression.credits
	var stats := Progression.build_stats()
	for id in _core_rows:
		var tuning := CoreTuning.get_definition(id)
		var row: Dictionary = _core_rows[id]
		var level := Progression.core_level(id)
		row["level"].text = "%s  Lv %d" % [tuning.display_name, level]
		if tuning.is_maxed(level):
			row["effect"].text = _describe_stat(tuning, stats)
			row["button"].text = "MAX"
			row["button"].disabled = true
		else:
			var preview := Progression.preview_core(id)
			row["effect"].text = "%s  →  %s" % [_describe_stat(tuning, stats), _describe_stat(tuning, preview)]
			row["button"].text = "Buy  %d c" % Progression.core_cost(id)
			row["button"].disabled = not Progression.can_buy_core(id)
	_stats_summary.text = _summary(stats)
	_refresh_waves()


func _build_core_rows() -> void:
	for tuning in CoreTuning.all():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var level := Label.new()
		level.custom_minimum_size = Vector2(140, 0)
		level.tooltip_text = tuning.description
		var effect := Label.new()
		effect.custom_minimum_size = Vector2(140, 0)
		effect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		effect.modulate = Color(1, 1, 1, 0.85)
		var button := Button.new()
		button.custom_minimum_size = Vector2(100, 36)
		button.pressed.connect(_on_buy_pressed.bind(tuning.id))
		row.add_child(level)
		row.add_child(effect)
		row.add_child(button)
		_core_rows_box.add_child(row)
		_core_rows[tuning.id] = {"level": level, "effect": effect, "button": button}


func _build_slot_grid() -> void:
	for slot in Items.get_slots():
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(140, 78)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.modulate = LOCKED_COLOR
		var margin := MarginContainer.new()
		for side in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 8)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		var name := Label.new()
		name.text = slot.display_name.to_upper()
		name.add_theme_font_size_override("font_size", 15)
		var summary := Label.new()
		summary.text = slot.summary
		summary.add_theme_font_size_override("font_size", 12)
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var gate := Label.new()
		gate.text = "LOCKED  ·  " + slot.gate_text
		gate.add_theme_font_size_override("font_size", 12)
		gate.modulate = Color(1, 0.8, 0.5)
		box.add_child(name)
		box.add_child(summary)
		box.add_child(gate)
		margin.add_child(box)
		card.add_child(margin)
		_slot_grid.add_child(card)


func _build_wave_list() -> void:
	for wave in WaveRunner.all_waves():
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 36)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.clip_text = true
		button.pressed.connect(_on_wave_pressed.bind(wave.number))
		_wave_list.add_child(button)
		_wave_buttons.append(button)


func _refresh_waves() -> void:
	var waves := WaveRunner.all_waves()
	for i in _wave_buttons.size():
		var wave := waves[i]
		var button := _wave_buttons[i]
		var available := Progression.is_wave_available(wave.number)
		var status := ""
		if Progression.is_wave_cleared(wave.number):
			status = "cleared"
		elif available:
			status = "next"
		else:
			status = "locked"
		button.text = "Wave %d   %s   ·   %s" % [wave.number, wave.display_name, status]
		button.disabled = not available
		button.button_pressed = wave.number == selected_wave
		button.tooltip_text = "%d enemies, up to %d at once. Clear bonus %d credits%s." % [
			wave.total_enemies(), wave.max_alive, wave.completion_bonus,
			", paid again on replay" if Progression.is_wave_cleared(wave.number) else ""]
	_start_button.text = "START WAVE %d" % selected_wave
	if Progression.highest_cleared_wave >= WaveRunner.WAVE_COUNT:
		_wave_note.text = "All five waves cleared. Replay any wave for the same bonus; more waves come with the next milestone."
	else:
		_wave_note.text = "Clear a wave to unlock the next. Replaying a cleared wave pays the same bonus."


func _describe_stat(tuning: CoreTuningDefinition, stats: WeaponStats) -> String:
	match tuning.stat:
		&"damage":
			return "%d dmg" % roundi(stats.damage)
		&"fire_rate":
			return "%.2f /s" % stats.fire_rate
		&"magazine":
			return "%d rounds" % stats.magazine_size
		&"reload_speed":
			return "%.2f s" % stats.reload_time
	return str(stats.extra.get(String(tuning.stat), ""))


func _summary(stats: WeaponStats) -> String:
	var context := WeaponStats.ShotContext.new()
	var per_shot := WeaponStats.expected_damage(stats, context)
	return "\n".join([
		"Damage per shot   %d" % roundi(per_shot),
		"Fire rate         %.2f shots/s" % stats.fire_rate,
		"Magazine          %d rounds" % stats.magazine_size,
		"Reload            %.2f s" % stats.reload_time,
		"Sustained damage  %d /s" % roundi(stats.sustained_dps()),
		"Chaser (%d hp)     %d shots" % [roundi(CHASER_DEFINITION.max_health), stats.shots_to_kill(CHASER_DEFINITION.max_health)],
	])


func _on_buy_pressed(id: StringName) -> void:
	if Progression.buy_core(id):
		Progression.save()
		refresh()


func _on_wave_pressed(number: int) -> void:
	selected_wave = number
	_refresh_waves()


func _on_start_pressed() -> void:
	start_wave_requested.emit(selected_wave)


func _on_reset_pressed() -> void:
	if not _confirm_reset:
		_confirm_reset = true
		_reset_button.text = "Click again to wipe the save"
		return
	_confirm_reset = false
	_reset_button.text = "Reset progress"
	Progression.reset()
	Progression.save()
	selected_wave = 1
	refresh()
