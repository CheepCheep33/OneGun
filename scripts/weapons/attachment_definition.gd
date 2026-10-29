class_name AttachmentDefinition
extends Resource
## One base attachment (Long barrel, Extended magazine, ...). Items are instances of a base:
## see Items. Marks I to V scale this base's numeric modifiers; behaviours are flags the pistol
## reads at fire time. Milestone 2 ships the data model only; bases arrive with Milestone 3.

## Mark V modifiers are (1 + mark_scale * 4) times mark I modifiers.
const DEFAULT_MARK_SCALE := 0.15

@export var id: StringName = &"standard_barrel"
@export var display_name := "Standard barrel"
## Must match a SlotDefinition id.
@export var slot: StringName = &"barrel"
@export_multiline var description := ""
## Numeric changes at mark I. Scaled by mark: flat and percent both grow by mark_scale per mark.
@export var modifiers: Array[StatModifier] = []
@export var mark_scale := DEFAULT_MARK_SCALE
## Behaviour flags and parameters, read by the pistol at fire time (fire_mode, burst_size,
## ray_count, spread_degrees, pierce, bounces, projectile, on_hit...). Later entries win.
@export var behaviours: Dictionary = {}
## True for the slot's default (Semi-auto, Standard, Open, Iron sights...), which never drops.
@export var is_default := false


func modifiers_at_mark(mark: int) -> Array[StatModifier]:
	var scale := 1.0 + mark_scale * clampi(mark - 1, 0, Items.MAX_MARK - 1)
	var scaled: Array[StatModifier] = []
	for modifier in modifiers:
		scaled.append(StatModifier.make(modifier.stat, modifier.flat * scale, modifier.percent * scale))
	return scaled
