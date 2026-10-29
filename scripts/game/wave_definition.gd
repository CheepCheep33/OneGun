class_name WaveDefinition
extends Resource
## One authored wave (data/waves/). The wave runner spawns its groups, holds the alive cap,
## and pays the completion bonus once the last enemy falls. Tuning values, not final balance.

@export var number := 1
@export var display_name := ""
@export var groups: Array[SpawnGroup] = []
## Never more than this many enemies alive at once; spawning waits for a kill.
@export var max_alive := 4
## Credits paid when the wave is cleared, first clear and replays alike.
@export var completion_bonus := 30
## Boss waves pay double bonus and drop better loot (loot arrives in Milestone 3).
@export var is_boss_wave := false


func total_enemies() -> int:
	var total := 0
	for group in groups:
		total += group.count
	return total


## Kill income if every enemy pays its listed reward, before tier scaling.
func kill_income() -> int:
	var total := 0
	for group in groups:
		if group.definition:
			total += group.count * group.definition.credit_reward
	return total
