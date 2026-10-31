class_name Loot
extends RefCounted
## Drop tables and item rolling (plan: Loot rarity, Rules that keep the loop clean). Pure
## functions over a RandomNumberGenerator so drop rates are testable and reproducible from the
## save's seeded loot stream. Tuning values, not balance.

## Per-kill chances for light enemies ("about 1 in 12 kills" Common, "about 1 in 50" Uncommon).
const COMMON_CHANCE := 1.0 / 12.0
const UNCOMMON_CHANCE := 1.0 / 50.0
## One guaranteed Uncommon per first wave clear.
const FIRST_CLEAR_RARITY := Items.Rarity.UNCOMMON
## Bosses drop an Epic on first clear and a Rare on replay (plan: the replay rule beats the boss Epic).
const BOSS_FIRST_CLEAR_RARITY := Items.Rarity.EPIC
const BOSS_REPLAY_RARITY := Items.Rarity.RARE
## Replays of any wave drop Common and Uncommon loot only.
const REPLAY_MAX_RARITY := Items.Rarity.UNCOMMON


## Rolls one kill's drop. Empty when nothing drops. `bases` are the bases that may drop right now
## (non-default, slot open, gate passed); `loot_weight` scales the chance for fragile enemies.
static func roll_kill_drop(definition: EnemyDefinition, bases: Array[AttachmentDefinition],
		rng: RandomNumberGenerator, is_replay := false) -> Dictionary:
	if definition == null or bases.is_empty():
		return {}
	var rarity: int
	if definition.is_boss:
		rarity = BOSS_REPLAY_RARITY if is_replay else BOSS_FIRST_CLEAR_RARITY
	elif definition.rare_chance > 0.0 and rng.randf() < definition.rare_chance:
		# Armoured enemies roll their Rare first (plan: loot roles follow the roster).
		rarity = Items.Rarity.RARE
	else:
		var roll := rng.randf()
		var uncommon := UNCOMMON_CHANCE * definition.loot_weight
		var common := COMMON_CHANCE * definition.loot_weight
		if roll < uncommon:
			rarity = Items.Rarity.UNCOMMON
		elif roll < uncommon + common:
			rarity = Items.Rarity.COMMON
		else:
			return {}
	if is_replay and not definition.is_boss:
		rarity = mini(rarity, REPLAY_MAX_RARITY)
	return make_item(pick_base(bases, rng), rarity, rng)


## Rolls a fresh mark I item of a base at a rarity: AFFIX_COUNT distinct affixes from the drop
## pool, each with a roll in [0, 1].
static func make_item(base: AttachmentDefinition, rarity: int, rng: RandomNumberGenerator) -> Dictionary:
	var pool := Items.drop_affixes().duplicate()
	var affixes: Array = []
	var count: int = Items.AFFIX_COUNT[clampi(rarity, Items.Rarity.COMMON, Items.Rarity.LEGENDARY)]
	for i in count:
		if pool.is_empty():
			break
		var index := rng.randi_range(0, pool.size() - 1)
		affixes.append({"id": String(pool[index].id), "roll": rng.randf()})
		pool.remove_at(index)
	return Items.make(base.id, rarity, affixes, Items.MIN_MARK)


static func pick_base(bases: Array[AttachmentDefinition], rng: RandomNumberGenerator) -> AttachmentDefinition:
	return bases[rng.randi_range(0, bases.size() - 1)]


## Chance that one kill of a light enemy drops at least something, for the bench's loot text.
static func any_drop_chance(loot_weight := 1.0) -> float:
	return clampf((COMMON_CHANCE + UNCOMMON_CHANCE) * loot_weight, 0.0, 1.0)
