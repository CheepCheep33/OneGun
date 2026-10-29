class_name SlotDefinition
extends Resource
## One gunsmith attachment slot. A slot opens when the wave in unlock_wave has been cleared once
## (0 means it is open from the first intermission). A slot whose bases have not shipped yet
## shows "coming later" even when its gate has passed (Items.slot_has_bases).

@export var id: StringName = &"receiver"
@export var display_name := "Receiver"
## What the slot governs, shown under its name.
@export var summary := ""
## Shown on the locked slot, for example "Opens when the Warden falls".
@export var gate_text := ""
## The wave whose first clear opens this slot. 0 means open from the start.
@export var unlock_wave := 0
@export var sort_order := 0
