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
## How the fitted attachment changes the placeholder pistol model, read by Pistol.apply_build:
## "slide_length", "grip_height", "slide_color", "barrel_extension".
@export var visual: Dictionary = {}


func modifiers_at_mark(mark: int) -> Array[StatModifier]:
	var steps := clampi(mark - 1, 0, Items.MAX_MARK - 1)
	var upside := 1.0 + mark_scale * steps
	var cost := maxf(1.0 - mark_scale * steps, 0.0)
	var scaled: Array[StatModifier] = []
	for modifier in modifiers:
		var flat := modifier.flat * (upside if modifier.flat >= 0.0 else cost)
		var percent := modifier.percent * (upside if modifier.percent >= 0.0 else cost)
		scaled.append(StatModifier.make(modifier.stat, flat, percent))
	return scaled


## One line per modifier at a mark, for the bench and the Firing Range's preview wall.
func describe_modifiers(mark := Items.MIN_MARK) -> PackedStringArray:
	var lines := PackedStringArray()
	for modifier in modifiers_at_mark(mark):
		lines.append(Items.describe_modifier(modifier))
	return lines
