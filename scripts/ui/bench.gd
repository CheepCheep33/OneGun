class_name Bench
extends CanvasLayer
## The intermission bench: core tuning purchases and the crafting table (two tabs on the left), the
## gunsmith slots, the inventory and overflow tray with compare, side-area doors and wave select. Runs while the tree is paused. Reads and
## writes progression only through the Progression autoload, and every number it shows comes from
## the same WeaponStats functions combat uses, so no preview ever lies.

signal start_wave_requested(number: int)
signal area_requested(area_id: String)

const CHASER_DEFINITION := preload("res://data/enemies/chaser.tres")
const LOCKED_COLOR := Color(0.6, 0.6, 0.62)
const DEFAULT_COLOR := Color(0.8, 0.82, 0.86)
const ITEM_BUTTON_SIZE := Vector2(36, 32)
const AREAS := [
	{"id": "firing_range", "name": "Firing Range", "blurb": "Target dummies with damage readouts and a timed gallery. No enemies."},
	{"id": "scrapyard", "name": "Scrapyard", "blurb": "A salvage run: grab scrap cores off the wrecks under rising spawns, then extract at the south door when it opens after 90 s. Parts in bulk and a Rare every extraction. Dying or leaving loses the cores you carry."},
]
## Rarities the crafting table makes; Legendaries come from a Legendary core (Milestone 5).
const CRAFT_RARITIES := [Items.Rarity.COMMON, Items.Rarity.UNCOMMON, Items.Rarity.RARE, Items.Rarity.EPIC]

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
## The crafting table's choices and widgets (built in code under %CraftView).
var craft_slot: StringName = &"barrel"
var craft_base: StringName = &""
var craft_rarity := Items.Rarity.COMMON
var craft_message := ""
var _craft_slot_buttons: Dictionary = {} # slot id (String) -> Button
var _craft_base_row: HBoxContainer
var _craft_rarity_buttons: Dictionary = {} # rarity -> Button
var _craft_cost_label: Label
var _craft_button: Button
var _reroll_title: Label
var _reroll_buttons: Array[Button] = []
var _craft_message_label: Label

@onready var _credits_label: Label = %CreditsLabel
@onready var _parts_label: Label = %PartsLabel
@onready var _core_rows_box: VBoxContainer = %CoreRows
@onready var _stats_summary: Label = %StatsSummary
@onready var _core_tab_button: Button = %CoreTabButton
@onready var _craft_tab_button: Button = %CraftTabButton
@onready var _core_view: VBoxContainer = %CoreView
@onready var _craft_view: VBoxContainer = %CraftView
@onready var _wave_scroll: ScrollContainer = %WaveScroll
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
	_build_craft_view()
	_core_tab_button.pressed.connect(show_tab.bind("core"))
	_craft_tab_button.pressed.connect(show_tab.bind("craft"))
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
	_scroll_to_selected_wave.call_deferred()


func close() -> void:
	visible = false


## Shows the left panel's "core" (core tuning and the pistol summary) or "craft" tab.
func show_tab(tab: String) -> void:
	var crafting := tab == "craft"
	_core_view.visible = not crafting
	_craft_view.visible = crafting
	_core_tab_button.button_pressed = not crafting
	_craft_tab_button.button_pressed = crafting
	if crafting:
		_refresh_craft()


func is_craft_tab_open() -> bool:
	return _craft_view.visible


func select_item(uid: int) -> void:
	selected_uid = uid
	refresh()


## Redraws every number from Progression. Cheap enough to call after each purchase or swap.
func refresh() -> void:
	_credits_label.text = "CREDITS  %d" % Progression.credits
	var parts: Dictionary = Progression.parts()
	var part_texts := PackedStringArray()
	for part in Items.PART_IDS:
		if part != "legendary_cores" or int(parts.get(part, 0)) > 0:
			part_texts.append("%s %d" % [String(Items.PART_NAMES[part]).to_upper(), int(parts.get(part, 0))])
	_parts_label.text = "   ·   ".join(part_texts)
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
	_refresh_craft()


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


func _build_craft_view() -> void:
	# The table's rules live on the tab's tooltip: the panel has no height to spare.
	_craft_tab_button.tooltip_text = "Turn spare parts into the attachment you want: every recipe is known and nothing fails. Dismantle loot for parts; the Scrapyard pays them in bulk."
	_craft_view.add_child(_heading("CRAFT"))
	# Three to a row: five slot names side by side do not fit the panel.
	var slot_row := GridContainer.new()
	slot_row.columns = 3
	slot_row.add_theme_constant_override("h_separation", 4)
	slot_row.add_theme_constant_override("v_separation", 4)
	for slot in Items.get_slots():
		if not Items.slot_has_bases(slot.id):
			continue
		var button := _choice_button(slot.display_name)
		button.pressed.connect(_on_craft_slot_pressed.bind(slot.id))
		slot_row.add_child(button)
		_craft_slot_buttons[String(slot.id)] = button
	_craft_view.add_child(slot_row)
	_craft_base_row = HBoxContainer.new()
	_craft_base_row.add_theme_constant_override("separation", 4)
	_craft_view.add_child(_craft_base_row)
	var rarity_row := HBoxContainer.new()
	rarity_row.add_theme_constant_override("separation", 4)
	for rarity in CRAFT_RARITIES:
		var button := _choice_button(Items.RARITY_NAMES[rarity])
		button.add_theme_font_size_override("font_size", 11)
		var styles: Dictionary = _rarity_styles[rarity]
		button.add_theme_stylebox_override("normal", styles["normal"])
		button.add_theme_stylebox_override("hover", styles["hover"])
		button.add_theme_stylebox_override("pressed", styles["pressed"])
		button.pressed.connect(_on_craft_rarity_pressed.bind(rarity))
		rarity_row.add_child(button)
		_craft_rarity_buttons[rarity] = button
	_craft_view.add_child(rarity_row)
	_craft_cost_label = _small_label("", 13)
	_craft_view.add_child(_craft_cost_label)
	_craft_button = Button.new()
	_craft_button.custom_minimum_size = Vector2(0, 34)
	_craft_button.add_theme_font_size_override("font_size", 14)
	_craft_button.pressed.connect(_on_craft_pressed)
	_craft_view.add_child(_craft_button)
	_craft_view.add_child(HSeparator.new())
	_craft_view.add_child(_heading("REROLL ONE AFFIX"))
	_reroll_title = _small_label("", 13)
	_craft_view.add_child(_reroll_title)
	for i in Items.AFFIX_COUNT.max():
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 30)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_on_reroll_pressed.bind(i))
		_craft_view.add_child(button)
		_reroll_buttons.append(button)
	_craft_message_label = _small_label("", 13)
	_craft_message_label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.75))
	_craft_view.add_child(_craft_message_label)
	craft_slot = &"barrel"


func _small_label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	return label


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	return label


func _choice_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(0, 30)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_text = true
	button.add_theme_font_size_override("font_size", 12)
	return button


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
	_gunsmith_blurb.text = "%d of 7 slots open. Drops: 1 in 12 kills Common, 1 in 50 Uncommon, an Uncommon per first clear; heavies and shield bearers drop Rares, bosses an Epic." % open_count


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
		_wave_note.text = "All %d waves cleared. Replay any wave for the same bonus (replays drop Common and Uncommon only); more waves come with the next milestone." % WaveRunner.WAVE_COUNT
	else:
		_wave_note.text = "Clear a wave to unlock the next. Replaying a cleared wave pays the same bonus but drops Common and Uncommon loot only."


func _refresh_areas() -> void:
	for area in AREAS:
		var button: Button = _area_buttons[area["id"]]
		var gate := int(Progression.AREA_GATES.get(area["id"], 0))
		if Progression.is_area_open(area["id"]):
			button.text = "%s  ·  open" % area["name"]
			if area["id"] == "scrapyard":
				var yard := Progression.scrapyard_state()
				if int(yard["extractions"]) > 0:
					button.text = "%s  ·  %d extracted, best %d cores" % [area["name"], int(yard["extractions"]), int(yard["best_cores"])]
				else:
					button.text = "%s  ·  open  ·  a Rare per extraction" % area["name"]
			button.disabled = false
		else:
			button.text = "%s  ·  locked until wave %d" % [area["name"], gate]
			button.disabled = true


## Keeps the selected wave in view in the scrolling list.
func _scroll_to_selected_wave() -> void:
	var index := selected_wave - 1
	if index >= 0 and index < _wave_buttons.size():
		_wave_scroll.ensure_control_visible(_wave_buttons[index])


func _refresh_craft() -> void:
	if _craft_button == null or not _craft_view.visible:
		return
	for slot_id in _craft_slot_buttons:
		var slot_button: Button = _craft_slot_buttons[slot_id]
		slot_button.button_pressed = StringName(slot_id) == craft_slot
		slot_button.disabled = not Progression.is_slot_open(StringName(slot_id))
		var slot := Items.get_slot(StringName(slot_id))
		slot_button.tooltip_text = slot.gate_text if slot and slot_button.disabled else ""
	# The base row: every non-default base of the slot, greyed with its gate when locked.
	var bases: Array[AttachmentDefinition] = []
	for base in Items.bases_for_slot(craft_slot):
		if not base.is_default:
			bases.append(base)
	var valid := false
	for base in bases:
		valid = valid or base.id == craft_base
	if not valid:
		craft_base = bases[0].id if not bases.is_empty() else &""
		for base in bases:
			if Progression.is_base_unlocked(base):
				craft_base = base.id
				break
	for child in _craft_base_row.get_children():
		child.queue_free()
	for base in bases:
		var button := _choice_button(base.display_name)
		button.button_pressed = base.id == craft_base
		button.tooltip_text = base.description if Progression.is_base_unlocked(base) else base.gate_text
		if not Progression.is_base_unlocked(base):
			button.add_theme_color_override("font_color", LOCKED_COLOR)
		button.pressed.connect(_on_craft_base_pressed.bind(base.id))
		_craft_base_row.add_child(button)
	for rarity in _craft_rarity_buttons:
		_craft_rarity_buttons[rarity].button_pressed = rarity == craft_rarity
	var cost := Crafting.craft_cost(craft_rarity)
	var have := PackedStringArray()
	for part in cost:
		have.append("%d %s" % [int(Progression.parts().get(part, 0)), Items.PART_NAMES[part]])
	_craft_cost_label.text = "Costs %s  ·  you have %s" % [Crafting.describe_cost(cost), ", ".join(have)]
	var reason := Progression.craft_block_reason(craft_base, craft_rarity)
	var base_definition := Items.get_attachment(craft_base)
	var label := "%s %s" % [Items.RARITY_NAMES[craft_rarity], base_definition.display_name if base_definition else "attachment"]
	_craft_button.text = "Craft %s" % label if reason == "" else "Craft %s  ·  %s" % [label, reason]
	_craft_button.disabled = reason != ""
	# Reroll works on the item selected in the inventory, tray or a slot.
	var found := Progression.locate(selected_uid)
	for button in _reroll_buttons:
		button.visible = false
	if found.is_empty():
		_reroll_title.text = "Select an item in the inventory, the tray or a fitted slot to reroll one of its affixes; the others stay."
	else:
		var item: Dictionary = found["item"]
		var affixes: Array = item.get("affixes", [])
		if affixes.is_empty():
			_reroll_title.text = "%s (%s) has no affixes to reroll." % [Items.display_name(item), Items.rarity_name(item)]
		else:
			var cost_text := Crafting.describe_cost(Crafting.reroll_cost(item))
			_reroll_title.text = "%s (%s)  ·  each reroll costs %s, rising with every reroll of this item" % [
				Items.display_name(item), Items.rarity_name(item), cost_text]
			var lines := Items.affix_lines(item)
			for i in affixes.size():
				var button := _reroll_buttons[i]
				var blocked := Progression.reroll_block_reason(selected_uid, i)
				button.visible = true
				button.text = "Reroll  %s" % lines[i] if i < lines.size() else "Reroll"
				button.disabled = blocked != ""
				var line: String = lines[i] if i < lines.size() else ""
				button.tooltip_text = "%s\n%s" % [line, blocked if blocked != "" else "Replaces this affix with a fresh one; the others stay."]
	_craft_message_label.text = craft_message


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


func _on_craft_slot_pressed(slot_id: StringName) -> void:
	craft_slot = slot_id
	craft_base = &""
	_refresh_craft()


func _on_craft_base_pressed(base_id: StringName) -> void:
	craft_base = base_id
	_refresh_craft()


func _on_craft_rarity_pressed(rarity: int) -> void:
	craft_rarity = rarity
	_refresh_craft()


func _on_craft_pressed() -> void:
	var item := Progression.craft(craft_base, craft_rarity)
	if item.is_empty():
		_refresh_craft()
		return
	craft_message = "Crafted %s  ·  %s" % [Items.display_name(item), Items.rarity_name(item)]
	selected_uid = int(item.get("uid", -1))
	Progression.save()
	refresh()


func _on_reroll_pressed(index: int) -> void:
	var found := Progression.locate(selected_uid)
	if found.is_empty():
		return
	var before := Items.affix_lines(found["item"])
	if Progression.reroll_affix(selected_uid, index):
		var after := Items.affix_lines(found["item"])
		craft_message = "%s  →  %s" % [before[index], after[index]]
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
