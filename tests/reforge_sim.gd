extends Node
## The Reforge simulation: the plan's prototype gate for the prestige loop.
##
## Headless. Runs a first run to wave 20 and then three consecutive Reforges (tiers 1 to 3) with
## the real stats function (WeaponStats.build through the Progression autoload), the real core
## tuning cost curves, the real loot tables and inventory rules, and a scripted buyer. It reports,
## per tier: shots to kill a chaser at wave 1 (plan target 5 to 7 at tier 1, 3 by wave 5),
## minutes to recover the previous tier's sustained damage per second (target under 10), and
## minutes to the next Reforge (target 60 to 90, drifting down with Forge nodes). The run exits
## non-zero when a target is missed, so CI holds the gate: no content past Milestone 3 until it
## passes (GAME_PLAN.md records the numbers and the tuning values they rest on).
##
## What is real and what is modelled is marked below. Everything modelled is a named constant.
##
##   godot --headless --path . res://tests/reforge_sim.tscn

# ------------------------------------------------------------------ plan targets

const TIERS_TO_SIMULATE := 3
const RUN_WAVES := 20
const TARGET_START_STK_MIN := 5
const TARGET_START_STK_MAX := 7
## Later tiers start with Forge nodes, so the plan only pins wave 1 of tier 1; the floor keeps
## later tiers from opening as a one-shot stroll.
const LATER_TIER_START_STK_MIN := 3
const TARGET_WAVE5_STK_MAX := 3
const TARGET_RECOVERY_MINUTES := 10.0
const TARGET_REFORGE_MIN := 60.0
const TARGET_REFORGE_MAX := 90.0
## The first run is the calibration: the plan says 100 to 120 minutes to the first Reforge.
const FIRST_RUN_MIN := 95.0
const FIRST_RUN_MAX := 125.0

# ------------------------------------------------------------------ player model (assumptions)

## Share of shots that land on an average player's aim.
const HIT_RATE := 0.8
## Seconds spent finding, approaching or waiting for each enemy on top of the shooting itself.
const ENGAGE_SECONDS := 1.2
## Extra seconds a boss costs in telegraphs and phases where it cannot be shot.
const BOSS_OVERHEAD_SECONDS := 15.0
## Real combat runs slower than the kill arithmetic: moving, dodging bolts, reloading at the wrong
## moment, walking to drops, resting the trigger hand. This multiplies combat time and is the
## one knob anchored to the plan's first-run estimate (100 to 120 minutes); refit it from the
## wave_cleared seconds in the playtest log once real runs exist.
const COMBAT_PACE := 3.0
## Bench time between waves: buying, equipping, reading.
const BENCH_SECONDS := 30.0
const CLEARED_SECONDS := 3.0
const SHOOT_DISTANCE := 10.0
## Side content every tier has: side-area runs and the crafting table (Milestones 4 to 6). Time
## only; their income and parts are not modelled, which is the conservative side.
const SIDE_CONTENT_MINUTES_PER_TIER := 20.0
## Deaths. The chance of dying in a wave attempt rises with how many shots a chaser of that wave
## takes: a gun that kills in two shots rarely loses, one that needs seven often does. A boss
## wave doubles it. A death loses the rest of the wave and its bonus; kills already made still
## pay, and getting back to the wave costs a few seconds at the bench.
const DEATH_RATE_PER_SHOT := 0.05
const DEATH_RATE_MIN := 0.02
const DEATH_RATE_MAX := 0.5
const BOSS_DEATH_FACTOR := 2.0
const DEATH_WAVE_FRACTION := 0.6
const DEATH_OVERHEAD_SECONDS := 15.0
## Farming. The player replays the highest cleared wave instead of pushing on while a chaser of
## the next wave would take more than this many shots (and buys between replays), up to a cap.
## Replays pay the same bonus and cap drops at Uncommon, as in the game.
const FARM_STK_THRESHOLD := 5
const MAX_FARMS_PER_WAVE := 8
## First-run learning: reading the bench, story cards at each boss, and first visits to the side
## areas (Firing Range at wave 2, Scrapyard at wave 5). Later tiers skip all of it.
const FIRST_RUN_BENCH_EXTRA_SECONDS := 30.0
const FIRST_RUN_BOSS_STORY_SECONDS := 90.0
const FIRST_RUN_SIDE_AREA_SECONDS := {2: 240.0, 5: 300.0}

# ------------------------------------------------------------------ systems not built yet (plan budget)

## Skill trees arrive in Milestone 4. The plan budgets about 1.3x effective damage by the end of
## a first run; later runs fill the third tree with diminishing returns.
const SKILL_DAMAGE_BY_RUNS: Array[float] = [0.0, 0.30, 0.40, 0.45, 0.45]
## The crafting table (Milestone 4) refines kept gear one mark per run; the credits it costs are
## not modelled, which flatters the gear side slightly.
const MARKS_PER_RUN := 1
## Forge tree (Milestone 7): nodes bought with Reforge tokens, in this order while tokens last.
## "Head start" grants starting damage levels that grow with the tier: none at tier 1, one per
## rank at tier 2, two per rank at tier 3. The plan's flat "10 free damage levels" was simulated
## first and one-shots wave 1 from tier 2 on (a level is worth 2.5x more each tier), so the node
## scales with the tier instead; GAME_PLAN.md records the change.
const FORGE_NODES := [
	{"name": "Head start I", "cost": 1, "head_start_per_tier": 1},
	{"name": "Income I", "cost": 1, "income": 0.10},
	{"name": "Income II", "cost": 2, "income": 0.10},
	{"name": "Income III", "cost": 2, "income": 0.10},
	{"name": "Head start II", "cost": 3, "head_start_per_tier": 1},
]
## Tokens per Reforge: one for the clear, one for the tier's first boss kill (no endless waves).
const TOKENS_PER_REFORGE := 2

## Waves 11 to 20 are not authored until Milestone 4. They are extrapolated from waves 6 to 10:
## the same groups with more enemies and the next wave tier's bonus, bosses at 15 and 20.
const EXTRAPOLATED_COUNT_SCALE := 1.3
const EXTRAPOLATED_BONUS_SCALE := 1.6
const SENTINEL_HEALTH_SCALE := 1.6
const GUARDIAN_HEALTH_SCALE := 2.5

const CHASER: EnemyDefinition = preload("res://data/enemies/chaser.tres")
const WARDEN: EnemyDefinition = preload("res://data/enemies/warden.tres")


class SimGroup:
	var definition: EnemyDefinition
	var count: int
	var start_delay: float
	var interval: float


class SimWave:
	var number: int
	var groups: Array[SimGroup] = []
	var completion_bonus: int
	var is_boss_wave: bool

	func spawn_schedule_seconds() -> float:
		var longest := 0.0
		for group in groups:
			longest = maxf(longest, group.start_delay + (group.count - 1) * group.interval)
		return longest


class TierReport:
	var tier := 0
	var start_stk := 0
	var wave5_stk := 0
	var start_dps := 0.0
	var end_dps := 0.0
	var recovery_minutes := INF
	var reforge_minutes := 0.0
	var income := 0
	var damage_levels := 0
	var total_levels := 0
	var drops := 0
	var gear_damage_percent := 0.0
	var gear_fire_rate_percent := 0.0
	var expected_deaths := 0.0
	var farms := 0
	var farm_minutes := 0.0


var _waves: Array[SimWave] = []
var _runs_completed := 0
var _tokens := 0
var _forge_bought: Array[String] = []
var _forge_income := 0.0
## Starting damage levels per Reforge tier beyond the first, from Head start nodes.
var _forge_head_start := 0
var _failures: PackedStringArray = []


func _ready() -> void:
	SaveFile.in_memory = true # never touch a developer's real save
	_waves = _load_waves()
	_fresh_progression(0)
	var reports: Array[TierReport] = []
	var previous_end_dps := 0.0
	for tier in TIERS_TO_SIMULATE + 1:
		var report := _run_tier(tier, previous_end_dps)
		reports.append(report)
		previous_end_dps = report.end_dps
		if tier < TIERS_TO_SIMULATE:
			_reforge()
	_print_report(reports)
	_judge(reports)
	if _failures.is_empty():
		print("\nReforge simulation: all targets hit.")
	else:
		print("\nReforge simulation: %d target(s) missed." % _failures.size())
		for failure in _failures:
			print("  MISS  " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


# ------------------------------------------------------------------ one tier

func _run_tier(tier: int, previous_end_dps: float) -> TierReport:
	var report := TierReport.new()
	report.tier = tier
	var minutes := 0.0
	_equip_best_from_inventory()
	var stats := Progression.build_stats()
	report.start_stk = stats.shots_to_kill(_enemy_health(CHASER, 1), SHOOT_DISTANCE)
	report.start_dps = stats.sustained_dps(SHOOT_DISTANCE)
	if previous_end_dps > 0.0 and report.start_dps >= previous_end_dps:
		report.recovery_minutes = 0.0
	var first_run := tier == 0
	for wave in _waves:
		if wave.number == 5:
			report.wave5_stk = Progression.build_stats().shots_to_kill(_enemy_health(CHASER, 5), SHOOT_DISTANCE)
		# Farm the last cleared wave while the next one would be a slog.
		var farms := 0
		while wave.number > 1 and farms < MAX_FARMS_PER_WAVE \
				and Progression.build_stats().shots_to_kill(_enemy_health(CHASER, wave.number), SHOOT_DISTANCE) > FARM_STK_THRESHOLD:
			var farm_seconds := _fight_wave(_waves[wave.number - 2], report) + BENCH_SECONDS
			minutes += farm_seconds / 60.0
			report.farm_minutes += farm_seconds / 60.0
			farms += 1
			_equip_best_from_inventory()
			_buy()
		report.farms += farms
		var seconds := _fight_wave(wave, report)
		minutes += seconds / 60.0
		# Bench: equip anything better, then spend.
		_equip_best_from_inventory()
		_buy()
		minutes += BENCH_SECONDS / 60.0
		if first_run:
			minutes += FIRST_RUN_BENCH_EXTRA_SECONDS / 60.0
			minutes += float(FIRST_RUN_SIDE_AREA_SECONDS.get(wave.number, 0.0)) / 60.0
			if wave.is_boss_wave:
				minutes += FIRST_RUN_BOSS_STORY_SECONDS / 60.0
		var dps := Progression.build_stats().sustained_dps(SHOOT_DISTANCE)
		if previous_end_dps > 0.0 and report.recovery_minutes == INF and dps >= previous_end_dps:
			report.recovery_minutes = minutes
	minutes += SIDE_CONTENT_MINUTES_PER_TIER
	report.reforge_minutes = minutes
	var final := Progression.build_stats()
	report.end_dps = final.sustained_dps(SHOOT_DISTANCE)
	report.damage_levels = Progression.core_level(&"damage")
	for id in CoreTuning.IDS:
		report.total_levels += Progression.core_level(id)
	for slot in Items.SLOT_IDS:
		var item: Variant = Progression.equipped_in(slot)
		if item is Dictionary:
			for modifier in Items.modifiers_of(item):
				if modifier.stat == &"damage":
					report.gear_damage_percent += modifier.percent
				elif modifier.stat == &"fire_rate":
					report.gear_fire_rate_percent += modifier.percent
	return report


## Fights one wave with the current build and pays it like the game does. Returns the seconds.
func _fight_wave(wave: SimWave, report: TierReport) -> float:
	var stats := Progression.build_stats()
	var dps := stats.sustained_dps(SHOOT_DISTANCE) * HIT_RATE
	var kill_seconds := 0.0
	var last_kill := 0.0
	var kill_credits := 0.0
	var replay := Progression.is_wave_cleared(wave.number)
	for group in wave.groups:
		var health := _enemy_health(group.definition, wave.number)
		var seconds_each := health / maxf(dps, 0.01) + ENGAGE_SECONDS
		if group.definition.is_boss:
			seconds_each += BOSS_OVERHEAD_SECONDS
		kill_seconds += seconds_each * group.count
		last_kill = maxf(last_kill, seconds_each)
		var reward := maxi(roundi(group.definition.credit_reward * Progression.reward_multiplier(wave.number)), 1)
		kill_credits += reward * group.count
		for i in group.count:
			# Real loot tables, real inventory rules (drops on the floor are collected on a clear).
			var item := Progression.roll_kill_drop(group.definition, replay)
			if not item.is_empty():
				report.drops += 1
				Progression.add_item(item, "sim")
	var seconds := maxf(kill_seconds, wave.spawn_schedule_seconds() + last_kill) * COMBAT_PACE + CLEARED_SECONDS
	# Deaths: expected failed attempts before the clear, each costing part of the wave and paying
	# for the kills made before dying.
	var chaser_stk := stats.shots_to_kill(_enemy_health(CHASER, wave.number), SHOOT_DISTANCE)
	var death_rate := clampf(DEATH_RATE_PER_SHOT * (chaser_stk - 1), DEATH_RATE_MIN, DEATH_RATE_MAX)
	if wave.is_boss_wave:
		death_rate = clampf(death_rate * BOSS_DEATH_FACTOR, DEATH_RATE_MIN, DEATH_RATE_MAX)
	var failed_attempts := death_rate / (1.0 - death_rate)
	report.expected_deaths += failed_attempts
	seconds += failed_attempts * (seconds * DEATH_WAVE_FRACTION + DEATH_OVERHEAD_SECONDS)
	kill_credits *= 1.0 + failed_attempts * DEATH_WAVE_FRACTION
	var income := roundi(kill_credits * (1.0 + _forge_income))
	Progression.add_credits(income)
	var bonus := roundi(wave.completion_bonus * (2 if wave.is_boss_wave else 1) * Progression.bonus_multiplier())
	bonus = roundi(bonus * (1.0 + _forge_income))
	var first := Progression.record_wave_cleared(wave.number, bonus, seconds)
	income += bonus
	if first:
		var granted := Progression.grant_item(Loot.FIRST_CLEAR_RARITY, &"", "sim_first_clear")
		if not granted.is_empty():
			report.drops += 1
	report.income += income
	return seconds


## Enemy health at a wave of the current tier, exactly as the wave runner scales it.
func _enemy_health(definition: EnemyDefinition, wave: int) -> float:
	return definition.max_health * Progression.reward_multiplier(wave)


# ------------------------------------------------------------------ the scripted buyer

## Greedy: the core level with the most sustained damage per second per credit, until nothing is
## affordable. Uses the real preview and the real prices.
func _buy() -> void:
	var guard := 0
	while guard < 10000:
		guard += 1
		var current := Progression.build_stats().sustained_dps(SHOOT_DISTANCE)
		var best_id: StringName = &""
		var best_value := 0.0
		for id in CoreTuning.IDS:
			if not Progression.can_buy_core(id):
				continue
			var gain := Progression.preview_core(id).sustained_dps(SHOOT_DISTANCE) - current
			var value := gain / float(Progression.core_cost(id))
			if value > best_value:
				best_value = value
				best_id = id
		if best_id == &"" or best_value <= 0.0:
			return
		Progression.buy_core(best_id)


## Equips, per open slot, the inventory item that gives the most sustained damage per second,
## keeping what is fitted when nothing beats it. Dismantles the unlocked Commons it leaves behind.
func _equip_best_from_inventory() -> void:
	for slot in Items.SLOT_IDS:
		if not Progression.is_slot_open(slot):
			continue
		var best_uid := -1
		var best_dps := Progression.build_stats().sustained_dps(SHOOT_DISTANCE)
		for item in Progression.inventory():
			if Items.slot_of(item) != slot:
				continue
			var base := Items.get_attachment(item["base"])
			if base == null or not Progression.is_base_unlocked(base):
				continue
			var dps := Progression.preview_equipped(slot, item).sustained_dps(SHOOT_DISTANCE)
			if dps > best_dps + 0.0001:
				best_dps = dps
				best_uid = int(item["uid"])
		if best_uid >= 0:
			Progression.equip(best_uid)
	Progression.dismantle_unlocked_commons()


# ------------------------------------------------------------------ Reforge

## The reset and keep rules from the plan, plus the kept systems that are not built yet.
func _reforge() -> void:
	_runs_completed += 1
	_tokens += TOKENS_PER_REFORGE
	for node in FORGE_NODES:
		if _forge_bought.has(node["name"]) or _tokens < int(node["cost"]):
			continue
		_forge_bought.append(node["name"])
		_tokens -= int(node["cost"])
		_forge_income += float(node.get("income", 0.0))
		_forge_head_start += int(node.get("head_start_per_tier", 0))
	var kept := Progression.data
	var next_tier := Progression.tier + 1
	_fresh_progression(next_tier)
	# Keep: inventory, equipped build, parts (the real keep list), with the crafting table's marks.
	Progression.data["inventory"] = kept["inventory"]
	Progression.data["overflow"] = kept["overflow"]
	Progression.data["equipped"] = kept["equipped"]
	Progression.data["parts"] = kept["parts"]
	Progression.data["records"] = kept["records"]
	Progression.data["loot_state"] = kept["loot_state"]
	Progression._restore_loot_state()
	for slot in Progression.data["equipped"]:
		var item: Dictionary = Progression.data["equipped"][slot]
		item["mark"] = mini(int(item.get("mark", 1)) + MARKS_PER_RUN, Items.MAX_MARK)


## A fresh tier's progression: wave progress, credits and core tuning reset; Forge grants applied.
func _fresh_progression(tier: int) -> void:
	Progression.data = SaveFile.fresh()
	Progression.data["seed"] = 20261029
	Progression.data["tier"] = tier
	Progression._restore_loot_state()
	var free_levels := _forge_head_start * maxi(tier - 1, 0)
	if free_levels > 0:
		Progression.data["core_levels"]["damage"] = free_levels
	var skill_percent: float = SKILL_DAMAGE_BY_RUNS[mini(_runs_completed, SKILL_DAMAGE_BY_RUNS.size() - 1)]
	if skill_percent > 0.0:
		Progression.data["skills"] = {"modifiers": [StatModifier.make(&"damage", 0.0, skill_percent)]}


# ------------------------------------------------------------------ waves

func _load_waves() -> Array[SimWave]:
	var waves: Array[SimWave] = []
	for definition in WaveRunner.all_waves():
		var wave := SimWave.new()
		wave.number = definition.number
		wave.completion_bonus = definition.completion_bonus
		wave.is_boss_wave = definition.is_boss_wave
		for group in definition.groups:
			var sim_group := SimGroup.new()
			sim_group.definition = group.definition
			sim_group.count = group.count
			sim_group.start_delay = group.start_delay
			sim_group.interval = group.interval
			wave.groups.append(sim_group)
		waves.append(wave)
	assert(waves.size() == 10, "the simulation extrapolates from ten authored waves")
	var sentinel := _boss_stand_in("sentinel", SENTINEL_HEALTH_SCALE)
	var guardian := _boss_stand_in("core_guardian", GUARDIAN_HEALTH_SCALE)
	for number in range(11, RUN_WAVES + 1):
		var template: SimWave = waves[(number - 6) % 5 + 5]
		var wave := SimWave.new()
		wave.number = number
		wave.completion_bonus = roundi(template.completion_bonus * EXTRAPOLATED_BONUS_SCALE)
		wave.is_boss_wave = number % 5 == 0
		for group in template.groups:
			if group.definition.is_boss:
				continue
			var sim_group := SimGroup.new()
			sim_group.definition = group.definition
			sim_group.count = maxi(roundi(group.count * EXTRAPOLATED_COUNT_SCALE), 1)
			sim_group.start_delay = group.start_delay
			sim_group.interval = group.interval
			wave.groups.append(sim_group)
		if wave.is_boss_wave:
			var boss := SimGroup.new()
			boss.definition = sentinel if number == 15 else guardian
			boss.count = 1
			boss.start_delay = 2.0
			boss.interval = 1.0
			wave.groups.append(boss)
		waves.append(wave)
	return waves


func _boss_stand_in(id: String, health_scale: float) -> EnemyDefinition:
	var definition: EnemyDefinition = WARDEN.duplicate()
	definition.id = StringName(id)
	definition.display_name = id.capitalize()
	definition.max_health = WARDEN.max_health * health_scale
	definition.credit_reward = roundi(WARDEN.credit_reward * health_scale)
	return definition


# ------------------------------------------------------------------ report

func _print_report(reports: Array[TierReport]) -> void:
	print("\nReforge simulation: first run plus %d consecutive Reforges" % TIERS_TO_SIMULATE)
	print("Real: stats function, cost curves, loot tables, inventory rules, wave data 1-10, tier steps.")
	print("Modelled: hit rate %.2f, %.1f s per enemy, combat pace x%.1f, %.0f s bench, %.0f min side content per tier, deaths and farming from shots to kill, first-run learning, waves 11-20 extrapolated, skills, marks, Forge." % [HIT_RATE, ENGAGE_SECONDS, COMBAT_PACE, BENCH_SECONDS, SIDE_CONTENT_MINUTES_PER_TIER])
	print("Minutes are anchored to the plan's first-run estimate through COMBAT_PACE; shots to kill and recovery do not depend on it.")
	print("")
	print("%-5s %-7s %-7s %-10s %-10s %-12s %-9s %-7s %-7s %-7s %-7s %-7s %-9s %-9s" % [
		"tier", "stk w1", "stk w5", "dps start", "dps end", "recover min", "to next", "deaths", "farms", "farm m", "income", "dmg lv", "gear dmg", "gear rof"])
	for report in reports:
		var recovery := "-" if report.tier == 0 else ("%.1f" % report.recovery_minutes if report.recovery_minutes != INF else "never")
		print("%-5d %-7d %-7d %-10.1f %-10.1f %-12s %-9.1f %-7.1f %-7d %-7.1f %-7d %-7d %-9s %-9s" % [
			report.tier, report.start_stk, report.wave5_stk, report.start_dps, report.end_dps, recovery,
			report.reforge_minutes, report.expected_deaths, report.farms, report.farm_minutes, report.income, report.damage_levels,
			"%+.0f%%" % (report.gear_damage_percent * 100.0), "%+.0f%%" % (report.gear_fire_rate_percent * 100.0)])
	print("")
	print("Forge nodes owned by the end: %s (tokens left %d)" % [", ".join(_forge_bought) if not _forge_bought.is_empty() else "none", _tokens])
	print("Drops rolled per tier: %s" % ", ".join(reports.map(func(r: TierReport) -> String: return str(r.drops))))


func _judge(reports: Array[TierReport]) -> void:
	var first := reports[0]
	_expect(first.reforge_minutes >= FIRST_RUN_MIN and first.reforge_minutes <= FIRST_RUN_MAX,
		"first run reaches Reforge in %.0f to %.0f minutes (%.1f)" % [FIRST_RUN_MIN, FIRST_RUN_MAX, first.reforge_minutes])
	_expect(first.start_stk == 4, "a fresh wave 1 chaser takes 4 shots (%d)" % first.start_stk)
	for i in range(1, reports.size()):
		var report := reports[i]
		if i == 1:
			_expect(report.start_stk >= TARGET_START_STK_MIN and report.start_stk <= TARGET_START_STK_MAX,
				"tier %d wave 1 chaser takes %d to %d shots (%d)" % [report.tier, TARGET_START_STK_MIN, TARGET_START_STK_MAX, report.start_stk])
		else:
			_expect(report.start_stk >= LATER_TIER_START_STK_MIN and report.start_stk <= TARGET_START_STK_MAX,
				"tier %d wave 1 chaser takes %d to %d shots (%d)" % [report.tier, LATER_TIER_START_STK_MIN, TARGET_START_STK_MAX, report.start_stk])
		_expect(report.wave5_stk <= TARGET_WAVE5_STK_MAX,
			"tier %d wave 5 chaser takes at most %d shots (%d)" % [report.tier, TARGET_WAVE5_STK_MAX, report.wave5_stk])
		_expect(report.recovery_minutes < TARGET_RECOVERY_MINUTES,
			"tier %d recovers the previous tier's damage per second inside %.0f minutes (%s)" % [
				report.tier, TARGET_RECOVERY_MINUTES, "%.1f" % report.recovery_minutes if report.recovery_minutes != INF else "never"])
		_expect(report.reforge_minutes >= TARGET_REFORGE_MIN and report.reforge_minutes <= TARGET_REFORGE_MAX,
			"tier %d reaches the next Reforge in %.0f to %.0f minutes (%.1f)" % [report.tier, TARGET_REFORGE_MIN, TARGET_REFORGE_MAX, report.reforge_minutes])


func _expect(condition: bool, description: String) -> void:
	print("%s  %s" % ["HIT " if condition else "MISS", description])
	if not condition:
		_failures.append(description)
