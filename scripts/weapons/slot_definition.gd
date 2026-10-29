class_name SlotDefinition
extends Resource
## One gunsmith attachment slot. Milestone 2 ships every slot locked; the bench shows them greyed
## with their gate text so the player can see what is coming. Unlock rules arrive with Milestone 3.

@export var id: StringName = &"receiver"
@export var display_name := "Receiver"
## What the slot governs, shown under its name.
@export var summary := ""
## Shown on the locked slot, for example "Opens at wave 3".
@export var gate_text := ""
## The wave whose first clear opens this slot. 0 means it never opens by wave (another gate does).
@export var unlock_wave := 0
@export var sort_order := 0
