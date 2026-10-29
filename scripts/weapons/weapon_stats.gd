class_name WeaponStats
extends RefCounted
## The shared stats contract. Two functions, and everything (combat, bench preview, HUD, tests)
## calls the same two so no preview ever lies:
##
##   build(base, core_levels, equipped, skills, forge) -> WeaponStats
##     Numeric modifiers from every source sum per stat (flats, then additive percentages),
##     multiply once, then clamp to the base's limits and the absolute caps. Behaviours
##     (fire mode, rays, pierce, projectile, on-hit...) are flags the pistol reads at fire time.
##
##   resolve_shot(build, context, rng) -> Shot
##     Turns build stats plus a per-shot context (distance, charge, player health, Overclock,
##     Bullet Time) into one shot's final numbers. Rolls the crit.
##
## Effective stats are derived, never mutated: when something is bought, build again.

## Stats the pistol uses directly. Any other modifier key lands in `extra`.
const STAT_KEYS: Array[StringName] = [
	&"damage", &"fire_rate", &"magazine", &"reload_speed", &"crit_chance", &"crit_damage",
]
## Hard caps that no combination of sources may exceed (see the plan's interaction rules).
const ABSOLUTE_FIRE_RATE_CAP := 15.0
const CRIT_CHANCE_CAP := 0.5
const PIERCE_CAP := 4
const RAY_CAP := 4
const BOUNCE_CAP := 2
const BASE_CRIT_MULTIPLIER := 1.5

const DEFAULT_BEHAVIOURS := {
	"fire_mode": "semi", # semi, auto, burst, charge
	"burst_size": 1,
	"ray_count": 1,
	"spread_degrees": 0.0,
	"pierce": 0,
	"bounces": 0,
	"projectile": "hitscan", # hitscan or a projectile profile id
	"on_hit": "", # status effect id applied by the ammo
}

var damage: float
var fire_rate: float
var magazine_size: int
var reload_time: float
var crit_chance: float
var crit_multiplier: float
var max_range: float
var recoil_kick_degrees: float
## Behaviour flags and parameters, keys as in DEFAULT_BEHAVIOURS.
var behaviours: Dictionary = DEFAULT_BEHAVIOURS.duplicate()
## Summed modifiers for stat keys the pistol does not use yet: {key: {"flat": x, "percent": y}}.
var extra: Dictionary = {}


## Per-shot inputs. Everything defaults to a plain standing shot.
class ShotContext:
	extends RefCounted
	var distance := 10.0
	## 0 to 1 for a Charge receiver, 0 otherwise.
	var charge := 0.0
	var player_health_fraction := 1.0
	var overclock_active := false
	var bullet_time_active := false


## One shot's final numbers.
class Shot:
	extends RefCounted
	var damage := 0.0
	var is_crit := false
	## False when the target is beyond the gun's range: the shot lands nothing.
	var in_range := true


static func build(base: WeaponBaseStats, core_levels: Dictionary = {}, equipped: Dictionary = {},
		skills: Dictionary = {}, forge: Dictionary = {}) -> WeaponStats:
	var flats := {}
	var percents := {}
	var behaviours := DEFAULT_BEHAVIOURS.duplicate()
	for modifier in collect_modifiers(core_levels, equipped, skills, forge):
		var key := String(modifier.stat)
		flats[key] = flats.get(key, 0.0) + modifier.flat
		percents[key] = percents.get(key, 0.0) + modifier.percent
	for slot_id in equipped:
		var item: Variant = equipped[slot_id]
		if item is Dictionary:
			var definition := Items.get_attachment(item.get("base", ""))
			if definition:
				behaviours.merge(definition.behaviours, true)

	var stats := WeaponStats.new()
	stats.damage = maxf(_apply(base.damage, flats, percents, "damage"), 0.0)
	var fire_rate_cap := minf(base.max_fire_rate, ABSOLUTE_FIRE_RATE_CAP)
	stats.fire_rate = clampf(_apply(base.fire_rate, flats, percents, "fire_rate"), 0.1, fire_rate_cap)
	stats.magazine_size = maxi(roundi(_apply(float(base.magazine_size), flats, percents, "magazine")), 1)
	# Reload is bought as speed, so percentages divide the time instead of multiplying it.
	var reload_speed: float = 1.0 + percents.get("reload_speed", 0.0)
	var reload_time: float = (base.reload_time + flats.get("reload_speed", 0.0)) / maxf(reload_speed, 0.01)
	stats.reload_time = maxf(reload_time, base.min_reload_time)
	# Crit chance is itself a fraction, so both flat and "percent" modifiers add percentage points.
	var crit_chance: float = base.crit_chance + flats.get("crit_chance", 0.0) + percents.get("crit_chance", 0.0)
	stats.crit_chance = clampf(crit_chance, 0.0, CRIT_CHANCE_CAP)
	stats.crit_multiplier = maxf(_apply(BASE_CRIT_MULTIPLIER, flats, percents, "crit_damage"), 1.0)
	stats.max_range = base.max_range
	stats.recoil_kick_degrees = base.recoil_kick_degrees

	behaviours["pierce"] = clampi(int(behaviours.get("pierce", 0)), 0, PIERCE_CAP)
	behaviours["ray_count"] = clampi(int(behaviours.get("ray_count", 1)), 1, RAY_CAP)
	behaviours["bounces"] = clampi(int(behaviours.get("bounces", 0)), 0, BOUNCE_CAP)
	behaviours["burst_size"] = maxi(int(behaviours.get("burst_size", 1)), 1)
	stats.behaviours = behaviours

	for key in flats.keys() + percents.keys():
		if not STAT_KEYS.has(StringName(key)) and not stats.extra.has(key):
			stats.extra[key] = {"flat": flats.get(key, 0.0), "percent": percents.get(key, 0.0)}
	return stats


## Every numeric modifier from every source, in resolution order. Skills and Forge nodes are
## passed as {id: level}; their definitions arrive in later milestones, so for now they contribute
## only when given as inline StatModifier arrays under the key "modifiers".
static func collect_modifiers(core_levels: Dictionary, equipped: Dictionary, skills: Dictionary,
		forge: Dictionary) -> Array[StatModifier]:
	var result: Array[StatModifier] = []
	for tuning in CoreTuning.all():
		var level := int(core_levels.get(String(tuning.id), 0))
		if level > 0:
			result.append(tuning.modifier_for(level))
	for slot_id in equipped:
		var item: Variant = equipped[slot_id]
		if item is Dictionary:
			result.append_array(Items.modifiers_of(item))
	for source in [skills, forge]:
		for modifier in source.get("modifiers", []):
			if modifier is StatModifier:
				result.append(modifier)
	return result


static func resolve_shot(stats: WeaponStats, context: ShotContext, rng: RandomNumberGenerator) -> Shot:
	var shot := Shot.new()
	shot.in_range = context.distance <= stats.max_range
	if not shot.in_range:
		return shot
	var damage := stats.damage
	if stats.behaviours.get("fire_mode", "semi") == "charge":
		damage *= 1.0 + 2.0 * clampf(context.charge, 0.0, 1.0)
	if context.overclock_active:
		# Overclock's fire-rate surplus above the cap becomes damage at the same ratio (plan: Caps).
		var wanted := stats.fire_rate * 2.0
		var cap := minf(stats.fire_rate * 2.0, ABSOLUTE_FIRE_RATE_CAP)
		damage *= wanted / maxf(cap, 0.1)
	shot.is_crit = stats.crit_chance > 0.0 and rng.randf() < stats.crit_chance
	if shot.is_crit:
		damage *= stats.crit_multiplier
	shot.damage = maxf(damage, 0.0)
	return shot


## Average damage per shot over crit rolls, for previews that must not depend on a random roll.
static func expected_damage(stats: WeaponStats, context: ShotContext) -> float:
	var rng := RandomNumberGenerator.new()
	var no_crit := WeaponStats.new()
	no_crit.damage = stats.damage
	no_crit.fire_rate = stats.fire_rate
	no_crit.max_range = stats.max_range
	no_crit.behaviours = stats.behaviours
	no_crit.crit_chance = 0.0
	var shot := resolve_shot(no_crit, context, rng)
	return shot.damage * (1.0 + stats.crit_chance * (stats.crit_multiplier - 1.0))


func seconds_between_shots() -> float:
	return 1.0 / fire_rate


## Sustained damage per second including reloads, for the bench summary.
func sustained_dps() -> float:
	var magazine_time := magazine_size * seconds_between_shots()
	return damage * magazine_size / (magazine_time + reload_time)


func shots_to_kill(health: float) -> int:
	return maxi(ceili(health / maxf(damage, 0.001)), 1)


static func _apply(base_value: float, flats: Dictionary, percents: Dictionary, key: String) -> float:
	return (base_value + flats.get(key, 0.0)) * (1.0 + percents.get(key, 0.0))
