class_name AttachmentDefinition
extends Resource
## One base attachment (Long barrel, Extended magazine, ...). Items are instances of a base:
## see Items. Marks I to V scale this base's numeric modifiers; behaviours are flags the pistol
## reads at fire time. Authored in data/attachments/, listed in Items.BASE_IDS.

## Mark V upsides are (1 + mark_scale * 4) times mark I; mark V costs are (1 - mark_scale * 4) times.
const DEFAULT_MARK_SCALE := 0.15

@export var id: StringName = &"standard_barrel"
@export var display_name := "Standard barrel"
## Must match a SlotDefinition id.
@export var slot: StringName = &"barrel"
@export_multiline var description := ""
## Numeric changes at mark I. Marks strengthen the base's upside (positive modifiers grow by
## mark_scale per mark) and soften its cost (negative modifiers shrink by the same share).
@export var modifiers: Array[StatModifier] = []
@export var mark_scale := DEFAULT_MARK_SCALE
## Behaviour flags and parameters, read by the pistol at fire time (fire_mode, burst_size,
## ray_count, spread_degrees, pierce, bounces, projectile, on_hit...). Later slots win.
@export var behaviours: Dictionary = {}
## True for the slot's default (Semi-auto, Standard, Open, Iron sights...), which never drops.
@export var is_default := false
## The wave whose first clear unlocks this base. 0 means it opens with its slot. A locked base
## never drops and shows greyed with its gate text (plan: unlock gates for bases).
@export var unlock_wave := 0
@export var gate_text := ""
## A progression unlock that opens this base as well (Progression.has_unlock): "foundry" (the
## Foundry's first clear opens Burst), "signal_tower" (Charge), "signal_tower_top" (Overflow).
@export var unlock_flag := ""
## How the fitted attachment changes the placeholder pistol model, read by Pistol.apply_build:
## "slide_length", "grip_height", "slide_color", "barrel_extension".
@export var visual: Dictionary = {}

@export_group("Legendary")
## The hand-authored unique a Legendary of this base carries (plan: six Legendaries, one per slot
## but the underbarrel). Empty when the base has none, and then no Legendary of it exists:
## transmute needs an Epic of a base with a unique.
@export var legendary_name := ""
@export_multiline var legendary_description := ""
## Added to the base's own modifiers on a Legendary, scaled by its mark the same way.
@export var legendary_modifiers: Array[StatModifier] = []
## Merged over the base's behaviours on a Legendary (pierce, ray_count, burst_final_crit...).
@export var legendary_behaviours: Dictionary = {}


func has_legendary() -> bool:
	return legendary_name != ""


func modifiers_at_mark(mark: int, legendary := false) -> Array[StatModifier]:
	var steps := clampi(mark - 1, 0, Items.MAX_MARK - 1)
	var upside := 1.0 + mark_scale * steps
	var cost := maxf(1.0 - mark_scale * steps, 0.0)
	var scaled: Array[StatModifier] = []
	var all: Array[StatModifier] = modifiers.duplicate()
	if legendary:
		all.append_array(legendary_modifiers)
	for modifier in all:
		var flat := modifier.flat * (upside if modifier.flat >= 0.0 else cost)
		var percent := modifier.percent * (upside if modifier.percent >= 0.0 else cost)
		scaled.append(StatModifier.make(modifier.stat, flat, percent))
	return scaled


## One line per modifier at a mark, for the bench and the Firing Range's preview wall.
func describe_modifiers(mark := Items.MIN_MARK, legendary := false) -> PackedStringArray:
	var lines := PackedStringArray()
	for modifier in modifiers_at_mark(mark, legendary):
		lines.append(Items.describe_modifier(modifier))
	return lines
