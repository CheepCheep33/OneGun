extends Node
## Everything that outlives a wave, autoloaded as `Progression`: credits, core tuning levels,
## wave progress, the inventory and equipped build (empty until Milestone 3), and the save file.
## Rewards commit the moment they are earned; the bench is the only place that writes the save.

signal credits_changed(credits: int)
signal core_level_changed(id: StringName, level: int)
signal progress_changed

const PISTOL_BASE := preload("res://data/weapons/pistol_base.tres")
## Per-kill credits, experience and health step up by this much per wave tier (5 waves each).
const TIER_STEP := 1.6
const WAVES_PER_TIER := 5

var data: Dictionary = SaveFile.fresh()
## True when a save existed when the game started, so the bench can greet a returning player.
var loaded_from_disk := false
var _purchases_this_session := 0


func _ready() -> void:
	load_from_disk()


# ------------------------------------------------------------------ credits

var credits: int:
	get:
		return int(data["credits"])


func add_credits(amount: int, source := "") -> void:
	if amount <= 0:
		return
	data["credits"] = credits + amount
	data["records"]["credits_earned"] = int(data["records"]["credits_earned"]) + amount
	credits_changed.emit(credits)
	if not source.is_empty():
		PlaytestLog.event("credits", {"amount": amount, "source": source, "total": credits})


func can_afford(cost: int) -> bool:
	return credits >= cost


# ------------------------------------------------------------------ core tuning

func core_level(id: StringName) -> int:
	return int(data["core_levels"].get(String(id), 0))


func core_levels() -> Dictionary:
	return data["core_levels"]


func core_cost(id: StringName) -> int:
	var tuning := CoreTuning.get_definition(id)
	return tuning.cost_at(core_level(id)) if tuning else 0


func can_buy_core(id: StringName) -> bool:
	var tuning := CoreTuning.get_definition(id)
	return tuning != null and not tuning.is_maxed(core_level(id)) and can_afford(core_cost(id))


## Spends credits on one level. Returns false (and changes nothing) when it cannot be bought.
func buy_core(id: StringName) -> bool:
	if not can_buy_core(id):
		return false
	var cost := core_cost(id)
	data["credits"] = credits - cost
	data["core_levels"][String(id)] = core_level(id) + 1
	_purchases_this_session += 1
	PlaytestLog.event("purchase", {"stat": id, "level": core_level(id), "cost": cost, "left": credits,
		"first_of_session": _purchases_this_session == 1})
	credits_changed.emit(credits)
	core_level_changed.emit(id, core_level(id))
	return true


# ------------------------------------------------------------------ build

## The current build stats: the single source of truth for combat, the bench and the HUD.
func build_stats() -> WeaponStats:
	return WeaponStats.build(PISTOL_BASE, data["core_levels"], data["equipped"], data["skills"], {})


## Build stats with one more level of a core stat, for the bench preview.
func preview_core(id: StringName) -> WeaponStats:
	var levels: Dictionary = data["core_levels"].duplicate()
	levels[String(id)] = core_level(id) + 1
	return WeaponStats.build(PISTOL_BASE, levels, data["equipped"], data["skills"], {})


# ------------------------------------------------------------------ waves

var highest_cleared_wave: int:
	get:
		return int(data["waves"]["highest_cleared"])


func is_wave_cleared(wave: int) -> bool:
	return data["waves"]["first_clears"].has(wave)


## The wave the player should play next: the first uncleared one.
func next_wave() -> int:
	return highest_cleared_wave + 1


## True when the wave can be started: every wave up to the next uncleared one.
func is_wave_available(wave: int) -> bool:
	return wave >= 1 and wave <= next_wave()


static func tier_of_wave(wave: int) -> int:
	return maxi(wave - 1, 0) / WAVES_PER_TIER


## Multiplier for per-kill credits and enemy health at a wave, from the wave tier and Reforge tier.
func reward_multiplier(wave: int) -> float:
	return pow(TIER_STEP, tier_of_wave(wave)) * pow(2.5, int(data["tier"]))


func record_kill(credits_paid: int) -> void:
	data["records"]["kills"] = int(data["records"]["kills"]) + 1
	add_credits(credits_paid)


## Pays the completion bonus and marks the wave. Pays the same on replay (the plan's replay rule);
## first clears are tracked for loot rules that arrive with Milestone 3. Returns whether it was a first clear.
func record_wave_cleared(wave: int, bonus: int, duration: float) -> bool:
	var first := not is_wave_cleared(wave)
	if first:
		data["waves"]["first_clears"].append(wave)
		data["waves"]["highest_cleared"] = maxi(highest_cleared_wave, wave)
	data["records"]["waves_cleared"] = int(data["records"]["waves_cleared"]) + 1
	add_credits(bonus, "wave_%d_bonus" % wave)
	PlaytestLog.event("wave_cleared", {"wave": wave, "first": first, "seconds": "%.1f" % duration, "bonus": bonus})
	progress_changed.emit()
	return first


func record_death(wave: int, duration: float) -> void:
	data["records"]["deaths"] = int(data["records"]["deaths"]) + 1
	PlaytestLog.event("death", {"wave": wave, "seconds": "%.1f" % duration, "credits_kept": credits})
	progress_changed.emit()


# ------------------------------------------------------------------ save

func save() -> bool:
	return SaveFile.save(data)


func load_from_disk() -> void:
	loaded_from_disk = FileAccess.file_exists(SaveFile.PATH)
	data = SaveFile.load_or_fresh()
	credits_changed.emit(credits)
	progress_changed.emit()


## Wipes everything and deletes the save. Used by the bench's reset button and by tests.
func reset() -> void:
	data = SaveFile.fresh()
	loaded_from_disk = false
	SaveFile.delete()
	credits_changed.emit(credits)
	progress_changed.emit()
