class_name Bench
extends CanvasLayer
## The intermission bench: core tuning purchases, the gunsmith slots, the inventory and overflow
## tray with compare, side-area doors and wave select. Runs while the tree is paused. Reads and
## writes progression only through the Progression autoload, and every number it shows comes from
## the same WeaponStats functions combat uses, so no preview ever lies.

signal start_wave_requested(number: int)
signal area_requested(area_id: String)

const CHASER_DEFINITION := preload("res://data/enemies/chaser.tres")
const LOCKED_COLOR := Color(0.6, 0.6, 0.62)
const DEFAULT_COLOR := Color(0.8, 0.82, 0.86)
const ITEM_BUTTON_SIZE := Vector2(36, 32)
const AREAS := [{"id": "firing_range", "name": "Firing Range", "blurb": "Target dummies with damage readouts and a timed gallery. No enemies."}]

var selected_wave := 1
## uid of the item shown in the detail panel, or -1.
var selected_uid := -1
var _confirm_reset := false
var _core_rows: Dictionary = {} # tuning id -> {level, effect, button}
var _wave_buttons: Array[Button] = []
var _slot_buttons: Dictionary = {} # slot id (String) -> Button
var _area_buttons: Dictionary = {} # area id -> Button
var _item_buttons: Dictionary = {} # uid -> Button
var _rarity_styles: Dictionary = {} # rarity -> {normal, hover, pressed}

@onready var _credits_label: Label = %CreditsLabel
@onready var _parts_label: Label = %PartsLabel
@onready var _core_rows_box: VBoxContainer = %CoreRows
@onready var _stats_summary: Label = %StatsSummary
@onready var _gunsmith_blurb: Label = %GunsmithBlurb
@onready var _slot_grid: GridContainer = %SlotGrid
@onready var _inventory_label: Label = %InventoryLabel
@onready var _dismantle_commons_button: Button = %DismantleCommonsButton
@onready var _inventory_grid: GridContainer = %InventoryGrid
@onready var _tray_box: VBoxContainer = %TrayBox
@onready var _tray_label: Label = %TrayLabel
@onready var _tray_grid: GridContainer = %TrayGrid
@onready var _detail_title: Label = %DetailTitle
@onready var _detail_body: Label = %DetailBody
@onready var _compare_label: Label = %CompareLabel
@onready var _equip_button: Button = %EquipButton
@onready var _lock_button: Button = %LockButton
@onready var _move_button: Button = %MoveButton
@onready var _dismantle_button: Button = %DismantleButton
@onready var _wave_list: VBoxContainer = %WaveList
@onready var _wave_note: Label = %WaveNote
@onready var _area_list: VBoxContainer = %AreaList
@onready var _start_button: Button = %StartButton
@onready var _reset_button: Button = %ResetButton
@onready var _greeting: Label = %Greeting
@onready var _storage_warning: Label = %StorageWarning


func _ready() -> void:
	visible = false
	_build_rarity_styles()
	_build_core_rows()
	_build_slot_grid()
	_build_wave_list()
	_build_area_list()
	_start_button.pressed.connect(_on_start_pressed)
	_reset_button.pressed.connect(_on_reset_pressed)
	_dismantle_commons_button.pressed.connect(_on_dismantle_commons_pressed)
	_equip_button.pressed.connect(_on_equip_pressed)
	_lock_button.pressed.connect(_on_lock_pressed)
	_move_button.pressed.connect(_on_move_pressed)
	_dismantle_button.pressed.connect(_on_dismantle_pressed)
	Progression.credits_changed.connect(func(_credits: int) -> void: if visible: refresh())
	Progression.progress_changed.connect(func() -> void: if visible: refresh())
	Progression.inventory_changed.connect(func() -> void: if visible: refresh())


func open() -> void:
	_confirm_reset = false
	_reset_button.text = "Reset progress"
	selected_wave = clampi(Progression.next_wave(), 1, WaveRunner.WAVE_COUNT)
	var records: Dictionary = Progression.data["records"]
	if Progression.highest_cleared_wave == 0 and int(records["deaths"]) == 0:
		_greeting.text = "Spend credits on your pistol between waves. Kills and wave clears pay; enemies drop attachments for the gunsmith. Start wave 1 when ready."
	else:
		_greeting.text = "Welcome back: %d kills, %d wave clears, %d credits earned, %d drops picked up." % [
			int(records["kills"]), int(records["waves_cleared"]), int(records["credits_earned"]), int(records["pickups"])]
	_storage_warning.visible = SaveFile.in_memory
	_storage_warning.text = SaveFile.storage_warning
	# The bench opens on the tray whenever it holds items (plan: Inventory).
	if Progression.has_overflow():
		selected_uid = int(Progression.overflow()[0].get("uid", -1))
	elif Progression.locate(selected_uid).is_empty():
		selected_uid = -1
	visible = true
	refresh()
	_start_button.grab_focus()


func close() -> void:
	visible = false


func select_item(uid: int) -> void:
	selected_uid = uid
	refresh()


## Redraws every number from Progression. Cheap enough to call after each purchase or swap.
func refresh() -> void:
	_credits_label.text = "CREDITS  %d" % Progression.credits
	var parts: Dictionary = Progression.parts()
	_parts_label.text = "SCRAP %d   ·   ALLOY %d   ·   CIRCUITS %d" % [
		int(parts.get("scrap", 0)), int(parts.get("alloy", 0)), int(parts.get("circuits", 0))]
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
	_refresh_slots()
	_refresh_inventory()
	_refresh_detail()
	_refresh_waves()
	_refresh_areas()


# ------------------------------------------------------------------ building

func _build_rarity_styles() -> void:
	for rarity in Items.RARITY_COLORS.size():
		var color: Color = Items.RARITY_COLORS[rarity]
		_rarity_styles[rarity] = {
			"normal": _item_style(color.darkened(0.6), color.darkened(0.15), 1),
			"hover": _item_style(color.darkened(0.45), color, 1),
			"pressed": _item_style(color.darkened(0.3), Color.WHITE, 2),
		}


func _item_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(4)
	return style


func _build_core_rows() -> void:
	for tuning in CoreTuning.all():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var level := Label.new()
		level.custom_minimum_size = Vector2(118, 0)
		level.tooltip_text = tuning.description
		level.add_theme_font_size_override("font_size", 14)
		var effect := Label.new()
		effect.custom_minimum_size = Vector2(120, 0)
		effect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		effect.modulate = Color(1, 1, 1, 0.85)
		effect.add_theme_font_size_override("font_size", 14)
		var button := Button.new()
		button.custom_minimum_size = Vector2(92, 32)
		button.pressed.connect(_on_buy_pressed.bind(tuning.id))
		row.add_child(level)
		row.add_child(effect)
		row.add_child(button)
		_core_rows_box.add_child(row)
		_core_rows[tuning.id] = {"level": level, "effect": effect, "button": button}


func _build_slot_grid() -> void:
	for slot in Items.get_slots():
		var button := Button.new()
		button.custom_minimum_size = Vector2(120, 66)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_on_slot_pressed.bind(String(slot.id)))
		_slot_grid.add_child(button)
		_slot_buttons[String(slot.id)] = button


func _build_wave_list() -> void:
	for wave in WaveRunner.all_waves():
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 30)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.clip_text = true
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(_on_wave_pressed.bind(wave.number))
		_wave_list.add_child(button)
		_wave_buttons.append(button)


func _build_area_list() -> void:
	for area in AREAS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 34)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.add_theme_font_size_override("font_size", 13)
		button.tooltip_text = area["blurb"]
		button.pressed.connect(_on_area_pressed.bind(area["id"]))
		_area_list.add_child(button)
		_area_buttons[area["id"]] = button


# ------------------------------------------------------------------ refreshing

func _refresh_slots() -> void:
	var open_count := 0
	for slot in Items.get_slots():
		var button: Button = _slot_buttons[String(slot.id)]
		var equipped: Variant = Progression.equipped_in(slot.id)
		button.remove_theme_color_override("font_color")
		if not Progression.is_slot_open(slot.id):
			button.text = "%s\nLOCKED\nopens after wave %d" % [slot.display_name.to_upper(), slot.unlock_wave]
			button.add_theme_color_override("font_color", LOCKED_COLOR)
			button.tooltip_text = slot.summary + "\n" + slot.gate_text
		elif not Items.slot_has_bases(slot.id):
			button.text = "%s\nno bases yet\n(a later milestone)" % slot.display_name.to_upper()
			button.add_theme_color_override("font_color", LOCKED_COLOR)
			button.tooltip_text = slot.summary
		elif equipped is Dictionary:
			open_count += 1
			button.text = "%s\n%s\n%s" % [slot.display_name.to_upper(), Items.display_name(equipped), Items.rarity_name(equipped)]
			button.add_theme_color_override("font_color", Items.rarity_color(equipped))
			button.tooltip_text = "\n".join(_item_lines(equipped))
		else:
			open_count += 1
			var default := Items.default_for_slot(slot.id)
			button.text = "%s\n%s\n(default)" % [slot.display_name.to_upper(), default.display_name if default else "Empty"]
			button.add_theme_color_override("font_color", DEFAULT_COLOR)
			button.tooltip_text = slot.summary + ("\n" + default.description if default else "")
	_gunsmith_blurb.text = "%d of 7 slots open. Drops: about 1 in 12 kills (Common), 1 in 50 (Uncommon), one Uncommon per first clear." % open_count


func _refresh_inventory() -> void:
	for child in _inventory_grid.get_children():
		child.queue_free()
	for child in _tray_grid.get_children():
		child.queue_free()
	_item_buttons.clear()
	var inventory := Items.sort_items(Progression.inventory())
	for item in inventory:
		_inventory_grid.add_child(_make_item_button(item))
	for i in range(inventory.size(), Progression.INVENTORY_SIZE):
		_inventory_grid.add_child(_make_empty_cell())
	_inventory_label.text = "INVENTORY  %d / %d" % [inventory.size(), Progression.INVENTORY_SIZE]
	var commons := 0
	for list in [Progression.inventory(), Progression.overflow()]:
		for item in list:
			if int(item.get("rarity", 0)) == Items.Rarity.COMMON and not bool(item.get("locked", false)):
				commons += 1
	_dismantle_commons_button.text = "Dismantle unlocked Commons (%d)" % commons
	_dismantle_commons_button.disabled = commons == 0
	var tray: Array = Progression.overflow()
	_tray_box.visible = not tray.is_empty()
	if not tray.is_empty():
		_tray_label.text = "OVERFLOW TRAY  %d / %d  ·  move these in or dismantle them; nothing leaves on its own" % [
			tray.size(), Progression.OVERFLOW_SIZE]
		for item in Items.sort_items(tray):
			_tray_grid.add_child(_make_item_button(item))


func _make_item_button(item: Dictionary) -> Button:
	var button := Button.new()
	var uid := int(item.get("uid", -1))
	button.custom_minimum_size = ITEM_BUTTON_SIZE
	button.toggle_mode = true
	button.button_pressed = uid == selected_uid
	button.text = "%s\n%s" % [Items.slot_glyph(Items.slot_of(item)), "LOCK" if bool(item.get("locked", false)) else Items.mark_numeral(int(item.get("mark", 1)))]
	button.add_theme_font_size_override("font_size", 10)
	button.tooltip_text = "\n".join(_item_lines(item)) + "\n\n" + _compare_text(item, "inventory")
	var styles: Dictionary = _rarity_styles[clampi(int(item.get("rarity", 0)), 0, Items.RARITY_COLORS.size() - 1)]
	button.add_theme_stylebox_override("normal", styles["normal"])
	button.add_theme_stylebox_override("hover", styles["hover"])
	button.add_theme_stylebox_override("pressed", styles["pressed"])
	button.add_theme_stylebox_override("focus", styles["pressed"])
	button.pressed.connect(_on_item_pressed.bind(uid))
	_item_buttons[uid] = button
	return button


func _make_empty_cell() -> Control:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = ITEM_BUTTON_SIZE
	cell.add_theme_stylebox_override("panel", _item_style(Color(0.14, 0.15, 0.18), Color(0.22, 0.24, 0.28), 1))
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cell


## Name, rarity, slot, the base's effect at this mark and every affix, one per line.
func _item_lines(item: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var base := Items.get_attachment(item.get("base", ""))
	lines.append("%s  ·  %s" % [Items.display_name(item), Items.rarity_name(item)])
	if base:
		var slot := Items.get_slot(base.slot)
		lines.append("%s slot  ·  %s" % [slot.display_name if slot else String(base.slot), base.description])
		var effects := base.describe_modifiers(int(item.get("mark", 1)))
		var behaviours := PackedStringArray()
		for key in base.behaviours:
			match key:
				"fire_mode":
					behaviours.append(String(base.behaviours[key]).capitalize() + " fire")
				"pierce":
					behaviours.append("pierces %d" % int(base.behaviours[key]))
				"burst_size":
					behaviours.append("%d-round bursts" % int(base.behaviours[key]))
		if not effects.is_empty() or not behaviours.is_empty():
			lines.append("Base: " + ", ".join(effects + behaviours))
	for affix_line in Items.affix_lines(item):
		lines.append(affix_line)
	if item.get("affixes", []).is_empty():
		lines.append("No affixes")
	if bool(item.get("locked", false)):
		lines.append("Locked: will not be dismantled")
	return lines


## "If equipped:" (or unequipped) with the stats that change, through the shared stats function.
func _compare_text(item: Dictionary, where: String) -> String:
	var slot := Items.slot_of(item)
	if slot == &"":
		return ""
	var current := Progression.build_stats()
	var candidate: WeaponStats
	var header: String
	if where == "equipped":
		candidate = Progression.preview_equipped(slot, null)
		header = "If unequipped:"
	else:
		candidate = Progression.preview_equipped(slot, item)
		var replaced: Variant = Progression.equipped_in(slot)
		header = "If equipped (replaces %s):" % Items.display_name(replaced) if replaced is Dictionary else "If equipped:"
	var lines := PackedStringArray([header])
	lines.append_array(_diff_lines(current, candidate))
	if lines.size() == 1:
		lines.append("No change to the pistol's numbers")
	return "\n".join(lines)


func _diff_lines(current: WeaponStats, candidate: WeaponStats) -> PackedStringArray:
	var lines := PackedStringArray()
	var rows := [
		["Damage per shot", WeaponStats.expected_damage_at(current, 10.0), WeaponStats.expected_damage_at(candidate, 10.0), "%.0f"],
		["Damage at 40 m", WeaponStats.expected_damage_at(current, 40.0), WeaponStats.expected_damage_at(candidate, 40.0), "%.0f"],
		["Fire rate", current.fire_rate, candidate.fire_rate, "%.2f /s"],
		["Magazine", float(current.magazine_size), float(candidate.magazine_size), "%.0f rounds"],
		["Reload", current.reload_time, candidate.reload_time, "%.2f s"],
		["Crit chance", current.crit_chance * 100.0, candidate.crit_chance * 100.0, "%.0f%%"],
		["Sustained damage", current.sustained_dps(), candidate.sustained_dps(), "%.0f /s"],
		["Recoil", current.recoil_kick_degrees, candidate.recoil_kick_degrees, "%.2f°"],
	]
	for row in rows:
		var before: float = row[1]
		var after: float = row[2]
		if absf(before - after) > 0.004:
			lines.append("%s  %s  →  %s" % [row[0], row[3] % before, row[3] % after])
	var before_behaviour := "  ·  ".join(current.describe_behaviours())
	var after_behaviour := "  ·  ".join(candidate.describe_behaviours())
	if before_behaviour != after_behaviour:
		lines.append("Behaviour  %s  →  %s" % [before_behaviour, after_behaviour])
	return lines


func _refresh_detail() -> void:
	var found := Progression.locate(selected_uid)
	_equip_button.visible = true
	_move_button.visible = false
	if found.is_empty():
		selected_uid = -1
		_detail_title.text = "No item selected"
		_detail_title.remove_theme_color_override("font_color")
		_detail_body.text = "Click an item in the inventory to compare it with what is fitted. Hover for a quick look. Every first wave clear pays one Uncommon; enemies drop more."
		_compare_label.text = ""
		for button in [_equip_button, _lock_button, _dismantle_button]:
			button.disabled = true
		_equip_button.text = "Equip"
		_lock_button.text = "Lock"
		_dismantle_button.text = "Dismantle"
		return
	var item: Dictionary = found["item"]
	var where: String = found["where"]
	var base := Items.get_attachment(item.get("base", ""))
	var lines := _item_lines(item)
	_detail_title.text = lines[0]
	_detail_title.add_theme_color_override("font_color", Items.rarity_color(item))
	_detail_body.text = "\n".join(lines.slice(1))
	_compare_label.text = _compare_text(item, where)
	var locked := bool(item.get("locked", false))
	_lock_button.disabled = false
	_lock_button.text = "Unlock" if locked else "Lock"
	if where == "equipped":
		_equip_button.text = "Unequip"
		_equip_button.disabled = false
		_dismantle_button.text = "Dismantle (unequip first)"
		_dismantle_button.disabled = true
	else:
		_equip_button.disabled = base == null or not Progression.is_base_unlocked(base)
		if base == null:
			_equip_button.text = "Equip"
		elif not Progression.is_slot_open(base.slot):
			var slot := Items.get_slot(base.slot)
			_equip_button.text = "Equip  ·  %s" % (slot.gate_text if slot else "slot locked")
		elif not Progression.is_base_unlocked(base):
			_equip_button.text = "Equip  ·  %s" % base.gate_text
		else:
			_equip_button.text = "Equip"
		var parts := Items.parts_for_rarity(int(item.get("rarity", 0)))
		var part_names := PackedStringArray()
		for part in parts:
			part_names.append("+%d %s" % [int(parts[part]), Items.PART_NAMES[part]])
		_dismantle_button.text = "Dismantle (%s)" % ", ".join(part_names)
		_dismantle_button.disabled = locked
		if where == "overflow":
			_move_button.visible = true
			_move_button.disabled = Progression.inventory().size() >= Progression.INVENTORY_SIZE
			_move_button.text = "Move to inventory" if not _move_button.disabled else "Inventory full"


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
		button.text = "%d  %s%s  ·  %s" % [wave.number, wave.display_name, " (boss)" if wave.is_boss_wave else "", status]
		button.disabled = not available
		button.button_pressed = wave.number == selected_wave
		button.tooltip_text = "%d enemies, up to %d at once. Clear bonus %d credits%s." % [
			wave.total_enemies(), wave.max_alive, wave.completion_bonus * (2 if wave.is_boss_wave else 1),
			", paid again on replay" if Progression.is_wave_cleared(wave.number) else ""]
	_start_button.text = "START WAVE %d" % selected_wave
	if Progression.highest_cleared_wave >= WaveRunner.WAVE_COUNT:
		_wave_note.text = "All ten waves cleared. Replay any wave for the same bonus (replays drop Common and Uncommon only); more waves come with the next milestone."
	else:
		_wave_note.text = "Clear a wave to unlock the next. Replaying a cleared wave pays the same bonus but drops Common and Uncommon loot only."


func _refresh_areas() -> void:
	for area in AREAS:
		var button: Button = _area_buttons[area["id"]]
		var gate := int(Progression.AREA_GATES.get(area["id"], 0))
		if Progression.is_area_open(area["id"]):
			button.text = "%s  ·  open" % area["name"]
			button.disabled = false
		else:
			button.text = "%s  ·  locked until wave %d" % [area["name"], gate]
			button.disabled = true


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
	var per_shot := WeaponStats.expected_damage_at(stats, 10.0)
	var lines := PackedStringArray([
		"Damage per shot   %d   (25 m: %d, 40 m: %d)" % [roundi(per_shot),
			roundi(WeaponStats.expected_damage_at(stats, 25.0)), roundi(WeaponStats.expected_damage_at(stats, 40.0))],
		"Fire rate         %.2f shots/s" % stats.fire_rate,
		"Magazine          %d rounds" % stats.magazine_size,
		"Reload            %.2f s" % stats.reload_time,
		"Sustained damage  %d /s" % roundi(stats.sustained_dps()),
		"Behaviour         %s" % "  ·  ".join(stats.describe_behaviours()),
		"Chaser (%d hp)     %d shots" % [roundi(CHASER_DEFINITION.max_health), stats.shots_to_kill(CHASER_DEFINITION.max_health)],
	])
	if stats.crit_chance > 0.0:
		lines.insert(1, "Crit              %d%% for x%.2f" % [roundi(stats.crit_chance * 100.0), stats.crit_multiplier])
	return "\n".join(lines)


# ------------------------------------------------------------------ handlers

func _on_buy_pressed(id: StringName) -> void:
	if Progression.buy_core(id):
		Progression.save()
		refresh()


func _on_wave_pressed(number: int) -> void:
	selected_wave = number
	_refresh_waves()


func _on_start_pressed() -> void:
	start_wave_requested.emit(selected_wave)


func _on_area_pressed(area_id: String) -> void:
	if Progression.is_area_open(area_id):
		area_requested.emit(area_id)


func _on_slot_pressed(slot_id: String) -> void:
	var equipped: Variant = Progression.equipped_in(StringName(slot_id))
	selected_uid = int(equipped.get("uid", -1)) if equipped is Dictionary else -1
	refresh()


func _on_item_pressed(uid: int) -> void:
	selected_uid = uid
	refresh()


func _on_equip_pressed() -> void:
	var found := Progression.locate(selected_uid)
	if found.is_empty():
		return
	var changed := false
	if found["where"] == "equipped":
		changed = Progression.unequip(StringName(String(found["slot"])))
	else:
		changed = Progression.equip(selected_uid)
	if changed:
		Progression.save()
	refresh()


func _on_lock_pressed() -> void:
	var found := Progression.locate(selected_uid)
	if found.is_empty():
		return
	Progression.set_locked(selected_uid, not bool(found["item"].get("locked", false)))
	Progression.save()
	refresh()


func _on_move_pressed() -> void:
	if Progression.move_to_inventory(selected_uid):
		Progression.save()
	refresh()


func _on_dismantle_pressed() -> void:
	if Progression.dismantle(selected_uid):
		selected_uid = -1
		Progression.save()
	refresh()


func _on_dismantle_commons_pressed() -> void:
	if Progression.dismantle_unlocked_commons() > 0:
		if Progression.locate(selected_uid).is_empty():
			selected_uid = -1
		Progression.save()
	refresh()


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
	selected_uid = -1
	refresh()
