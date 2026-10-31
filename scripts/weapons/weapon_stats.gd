class_name WeaponStats
extends RefCounted
## The shared stats contract. Two functions, and everything (combat, bench preview, inventory
## compare, HUD, tests, the Reforge simulation) calls the same two so no preview ever lies:
##
##   build(base, core_levels, equipped, skills, forge, tier) -> WeaponStats
##     Numeric modifiers from every source sum per stat (flats, then additive percentages),
##     multiply once, then clamp to the base's limits and the absolute caps. Behaviours
##     (fire mode, rays, pierce, projectile, on-hit...) are flags the pistol reads at fire time.
##     The Reforge tier scales core damage per level by REFORGE_STEP (plan: Reforge power budget).
##
##   resolve_shot(build, context, rng) -> Shot
##     Turns build stats plus a per-hit context (distance, charge, player health, Overclock,
##     Bullet Time, pierce index, bounce index) into one hit's final numbers. Rolls the crit.
##     Hitscan rays and simulated projectiles both call it once per enemy they damage.
##
## Effective stats are derived, never mutated: when something is bought or equipped, build again.

## Stats the pistol uses directly. Any other modifier key lands in `extra`.
const STAT_KEYS: Array[StringName] = [
	&"damage", &"fire_rate", &"magazine", &"reload_speed", &"crit_chance", &"crit_damage",
	&"range", &"recoil",
]
## Extra keys that combat reads (see the interaction rules). They stay in `extra` for display;
## extra pierce is also folded into the pierce behaviour.
const EXTRA_PIERCE_KEY := "extra_pierce"
const AMMO_REFUND_KEY := "ammo_refund_on_kill"
const CHAIN_ON_CRIT_KEY := "chain_on_crit"
## Overflow magazine: the chance a shot costs no round.
const FREE_SHOT_KEY := "free_shot_chance"
## Lingering affix and Status Mastery: status effects last this much longer.
const STATUS_DURATION_KEY := "status_duration"
## Skills that read the shot's context: Executioner (more damage to a robot under
## EXECUTE_THRESHOLD of its health) and Adrenaline (more damage while the player is under
## LOW_HEALTH_THRESHOLD).
const EXECUTIONER_KEY := "executioner"
const EXECUTE_THRESHOLD := 0.25
const LOW_HEALTH_KEY := "low_health_damage"
const LOW_HEALTH_THRESHOLD := 0.5
## Hollow point: more against light robots, less against armoured ones (any armour above zero).
const HOLLOW_LIGHT_BONUS := 0.35
const HOLLOW_ARMOURED_PENALTY := 0.4
## Rangefinder: damage grows by its `rangefinder` value per metre past this distance, up to its
## cap (`rangefinder_cap`, RANGEFINDER_CAP by default).
const RANGEFINDER_START := 10.0
const RANGEFINDER_CAP := 0.4
## A full charge (Charge receiver) multiplies the shot by one plus this.
const CHARGE_BONUS := 2.0
## A full charge widens an explosive round's blast by this share.
const CHARGE_BLAST_GROWTH := 1.0

## Hard caps that no combination of sources may exceed (plan: interaction rules, Caps).
const ABSOLUTE_FIRE_RATE_CAP := 15.0
const CRIT_CHANCE_CAP := 0.5
const PIERCE_CAP := 4
const RAY_CAP := 4
const BOUNCE_CAP := 2
const BASE_CRIT_MULTIPLIER := 1.5
## Enemy health, kill credits, completion bonuses and core damage per level all step by this
## much per Reforge tier (plan: Reforge power budget). Unused until Milestone 7 except by the
## Reforge simulation, which proves the budget before content is built on it.
const REFORGE_STEP := 2.5
## Damage split (plan: interaction rules). Each pierced enemy after the first takes this share
## of the previous one's damage; each bounce keeps this share.
const PIERCE_FALLOFF := 0.75
const BOUNCE_FALLOFF := 0.8
## A multi-ray muzzle (Splitter) divides one shot's damage across its rays so all of them together
## deal this share of one shot (plan: damage split).
const SPLIT_TOTAL := 1.25
## Explosive ammo: the round deals this share on a direct hit and the blast this share to every
## enemy inside blast_radius, the direct target included. Blasts never crit, pierce or proc.
const EXPLOSIVE_DIRECT_SHARE := 0.6
## A robot's half-width for the readouts' spread estimate (ray_hit_share).
const READOUT_TARGET_RADIUS := 0.45
const EXPLOSIVE_BLAST_SHARE := 0.6
## A weak-point hit (the heavy's core) multiplies after crits, by this times one plus the build's
## weak-point damage, and ignores armour (plan: weak points).
const WEAK_POINT_MULTIPLIER := 2.0
const WEAK_POINT_KEY := "weak_point_damage"
## Representative distances for previews: the bench shows damage at these ranges so a barrel's
## range change is visible (plan: How stats are computed).
const PREVIEW_DISTANCES: Array[float] = [10.0, 25.0, 40.0]

const DEFAULT_BEHAVIOURS := {
	"fire_mode": "semi", # semi, auto, burst, charge
	"burst_size": 1,
	"ray_count": 1,
	"spread_degrees": 0.0,
	"pierce": 0,
	"bounces": 0,
	"projectile": "hitscan", # hitscan or a projectile profile id (see ProjectilePool.PROFILES)
	"blast_radius": 0.0, # metres; above zero the round bursts where it stops (Explosive rounds)
	"on_hit": "", # status effect applied by the ammo: burn, cryo or shock (see StatusEffects)
	"charge_time": 0.0, # seconds to a full charge (Charge receiver)
}

var damage: float
var fire_rate: float
var magazine_size: int
var reload_time: float
var crit_chance: float
var crit_multiplier: float
var max_range: float
## Damage is full up to falloff_start, then drops linearly to falloff_floor at falloff_end.
var falloff_start: float
var falloff_end: float
var falloff_floor: float
var recoil_kick_degrees: float
## The Reforge tier this build was made for.
var tier := 0
## Behaviour flags and parameters, keys as in DEFAULT_BEHAVIOURS.
var behaviours: Dictionary = DEFAULT_BEHAVIOURS.duplicate()
## Summed modifiers for stat keys the pistol does not use directly: {key: {"flat": x, "percent": y}}.
var extra: Dictionary = {}


## Per-hit inputs. Everything defaults to a plain standing shot on the first enemy a ray meets.
class ShotContext:
	extends RefCounted
	var distance := 10.0
	## 0 to 1 for a Charge receiver, 0 otherwise.
	var charge := 0.0
	var player_health_fraction := 1.0
	var overclock_active := false
	var bullet_time_active := false
	## The enemy's health before this hit, as a fraction (Executioner).
	var target_health_fraction := 1.0
	## True when the enemy has armour (Hollow point).
	var target_armored := false
	## The hit is a critical hit whatever the roll (Triplet: a burst's last round).
	var force_crit := false
	## 0 for the first enemy a ray hits, 1 for the first pierced enemy, and so on.
	var pierce_index := 0
	## How many times the round bounced off world geometry before this hit.
	var bounce_index := 0


## One hit's final numbers.
class Shot:
	extends RefCounted
	var damage := 0.0
	var is_crit := false
	## False when the target is beyond the gun's range: the shot lands nothing.
	var in_range := true


static func build(base: WeaponBaseStats, core_levels: Dictionary = {}, equipped: Dictionary = {},
		skills: Dictionary = {}, forge: Dictionary = {}, reforge_tier := 0) -> WeaponStats:
	var flats := {}
	var percents := {}
	var behaviours := DEFAULT_BEHAVIOURS.duplicate()
	for modifier in collect_modifiers(core_levels, equipped, skills, forge, reforge_tier):
		var key := String(modifier.stat)
		flats[key] = flats.get(key, 0.0) + modifier.flat
		percents[key] = percents.get(key, 0.0) + modifier.percent
	# Behaviours merge in slot order (receiver, barrel, muzzle, ...) so "later entries win" is
	# deterministic whatever order the equipped dictionary was saved in.
	# Spread composes across slots: the muzzle's cone (spread_degrees), plus each base's
	# added_spread (Short barrel), times each base's spread_scale (Compensator).
	var added_spread := 0.0
	var spread_scale := 1.0
	for slot_id in Items.SLOT_IDS:
		var item: Variant = equipped.get(String(slot_id))
		if item is Dictionary:
			var definition := Items.get_attachment(item.get("base", ""))
			if definition:
				behaviours.merge(definition.behaviours, true)
				if Items.is_legendary(item):
					behaviours.merge(definition.legendary_behaviours, true)
				added_spread += float(definition.behaviours.get("added_spread", 0.0))
				spread_scale *= float(definition.behaviours.get("spread_scale", 1.0))
	behaviours.erase("added_spread")
	behaviours.erase("spread_scale")
	behaviours["spread_degrees"] = (float(behaviours.get("spread_degrees", 0.0)) + added_spread) * spread_scale
	# Charge plus a projectile ammo makes one round on the Charge profile with the ammo's on-hit
	# and blast (plan: hitscan or projectile); the Charge receiver's own shot is simulated too.
	if behaviours.get("fire_mode", "semi") == "charge":
		behaviours["projectile"] = "charge"

	var stats := WeaponStats.new()
	stats.tier = reforge_tier
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
	# Range scales the falloff distances and the hard limit together.
	var range_scale: float = maxf(1.0 + percents.get("range", 0.0), 0.1)
	var range_flat: float = flats.get("range", 0.0)
	stats.falloff_start = maxf((base.falloff_start + range_flat) * range_scale, 1.0)
	stats.falloff_end = maxf((base.falloff_end + range_flat) * range_scale, stats.falloff_start + 1.0)
	stats.falloff_floor = clampf(base.falloff_floor, 0.0, 1.0)
	stats.max_range = maxf((base.max_range + range_flat) * range_scale, stats.falloff_end)
	stats.recoil_kick_degrees = maxf(_apply(base.recoil_kick_degrees, flats, percents, "recoil"), 0.0)

	var pierce := int(behaviours.get("pierce", 0)) + roundi(flats.get(EXTRA_PIERCE_KEY, 0.0))
	behaviours["pierce"] = clampi(pierce, 0, PIERCE_CAP)
	behaviours["ray_count"] = clampi(int(behaviours.get("ray_count", 1)), 1, RAY_CAP)
	behaviours["bounces"] = clampi(int(behaviours.get("bounces", 0)), 0, BOUNCE_CAP)
	behaviours["burst_size"] = maxi(int(behaviours.get("burst_size", 1)), 1)
	behaviours["spread_degrees"] = maxf(float(behaviours.get("spread_degrees", 0.0)), 0.0)
	behaviours["blast_radius"] = maxf(float(behaviours.get("blast_radius", 0.0)), 0.0)
	stats.behaviours = behaviours

	for key in flats.keys() + percents.keys():
		if not STAT_KEYS.has(StringName(key)) and not stats.extra.has(key):
			stats.extra[key] = {"flat": flats.get(key, 0.0), "percent": percents.get(key, 0.0)}
	return stats


## Every numeric modifier from every source, in resolution order. Skills are passed as {id: rank}
## and resolve through Skills (data/skills/); Forge nodes arrive with Milestone 7. Either may also
## carry inline StatModifier arrays under the key "modifiers" (tests and the Reforge simulation).
static func collect_modifiers(core_levels: Dictionary, equipped: Dictionary, skills: Dictionary,
		forge: Dictionary, reforge_tier := 0) -> Array[StatModifier]:
	var result: Array[StatModifier] = []
	var tier_scale := pow(REFORGE_STEP, maxi(reforge_tier, 0))
	for tuning in CoreTuning.all():
		var level := int(core_levels.get(String(tuning.id), 0))
		if level > 0:
			result.append(tuning.modifier_for(level, tier_scale))
	for slot_id in Items.SLOT_IDS:
		var item: Variant = equipped.get(String(slot_id))
		if item is Dictionary:
			result.append_array(Items.modifiers_of(item))
	for source in [skills, forge]:
		for modifier in source.get("modifiers", []):
			if modifier is StatModifier:
				result.append(modifier)
	for id in skills:
		if String(id) != "modifiers" and int(skills[id]) > 0:
			var skill := Skills.get_definition(StringName(String(id)))
			if skill:
				result.append_array(skill.modifiers)
	return result


static func resolve_shot(stats: WeaponStats, context: ShotContext, rng: RandomNumberGenerator) -> Shot:
	var shot := Shot.new()
	shot.in_range = context.distance <= stats.max_range
	if not shot.in_range:
		return shot
	var damage := stats.damage * falloff_multiplier(stats, context.distance) * ray_share(stats)
	if stats.blast_radius() > 0.0:
		damage *= EXPLOSIVE_DIRECT_SHARE
	if stats.behaviours.get("fire_mode", "semi") == "charge":
		damage *= 1.0 + CHARGE_BONUS * clampf(context.charge, 0.0, 1.0)
	damage *= context_multiplier(stats, context)
	if context.overclock_active:
		# Overclock's fire-rate surplus above the cap becomes damage at the same ratio (plan: Caps).
		var wanted := stats.fire_rate * 2.0
		var cap := minf(stats.fire_rate * 2.0, ABSOLUTE_FIRE_RATE_CAP)
		damage *= wanted / maxf(cap, 0.1)
	damage *= pow(PIERCE_FALLOFF, maxi(context.pierce_index, 0))
	damage *= pow(BOUNCE_FALLOFF, maxi(context.bounce_index, 0))
	shot.is_crit = context.force_crit or (stats.crit_chance > 0.0 and rng.randf() < stats.crit_chance)
	if shot.is_crit:
		damage *= stats.crit_multiplier
	shot.damage = maxf(damage, 0.0)
	return shot


## Everything the shot's context adds on top of the build's numbers, before crits: the
## Rangefinder's distance bonus, Hollow point against light or armoured robots, Executioner on a
## robot near death and Adrenaline while the player is hurt. Previews call it with their own
## context, so the bench shows the Rangefinder at 10, 25 and 40 m.
static func context_multiplier(stats: WeaponStats, context: ShotContext) -> float:
	var multiplier := 1.0
	var per_metre := float(stats.behaviours.get("rangefinder", 0.0))
	if per_metre > 0.0:
		var cap := float(stats.behaviours.get("rangefinder_cap", RANGEFINDER_CAP))
		multiplier *= 1.0 + minf(maxf(context.distance - RANGEFINDER_START, 0.0) * per_metre, cap)
	if bool(stats.behaviours.get("hollow_point", false)):
		multiplier *= (1.0 - HOLLOW_ARMOURED_PENALTY) if context.target_armored else (1.0 + HOLLOW_LIGHT_BONUS)
	if context.target_health_fraction <= EXECUTE_THRESHOLD:
		multiplier *= 1.0 + stats.extra_percent(EXECUTIONER_KEY)
	if context.player_health_fraction <= LOW_HEALTH_THRESHOLD:
		multiplier *= 1.0 + stats.extra_percent(LOW_HEALTH_KEY)
	return multiplier


## The share of one shot's damage each ray deals: 1 for a single ray, SPLIT_TOTAL / rays for a
## Splitter, so every ray together deals SPLIT_TOTAL.
static func ray_share(stats: WeaponStats) -> float:
	var rays := int(stats.behaviours.get("ray_count", 1))
	return SPLIT_TOTAL / rays if rays > 1 else 1.0


## What one ray's blast deals to each enemy inside its radius, at the distance the round travelled:
## never a crit, so it is the same for every enemy it reaches. Zero without explosive ammo.
static func blast_damage(stats: WeaponStats, distance: float, charge := 0.0) -> float:
	if stats.blast_radius() <= 0.0 or distance > stats.max_range:
		return 0.0
	var damage := stats.damage * falloff_multiplier(stats, distance) * ray_share(stats) * EXPLOSIVE_BLAST_SHARE
	if stats.fire_mode() == "charge":
		damage *= 1.0 + CHARGE_BONUS * clampf(charge, 0.0, 1.0)
	return damage


## The blast radius of a round fired at `charge` (a full Charge shot widens it).
func blast_radius_at(charge: float) -> float:
	var radius := blast_radius()
	if fire_mode() == "charge":
		radius *= 1.0 + CHARGE_BLAST_GROWTH * clampf(charge, 0.0, 1.0)
	return radius


## 1.0 up to falloff_start, falling linearly to falloff_floor at falloff_end and beyond.
static func falloff_multiplier(stats: WeaponStats, distance: float) -> float:
	if distance <= stats.falloff_start:
		return 1.0
	var span := maxf(stats.falloff_end - stats.falloff_start, 0.001)
	var t := clampf((distance - stats.falloff_start) / span, 0.0, 1.0)
	return lerpf(1.0, stats.falloff_floor, t)


## Average damage per hit over crit rolls, for previews that must not depend on a random roll.
static func expected_damage(stats: WeaponStats, context: ShotContext) -> float:
	var rng := RandomNumberGenerator.new()
	var no_crit := WeaponStats.new()
	no_crit.damage = stats.damage
	no_crit.fire_rate = stats.fire_rate
	no_crit.max_range = stats.max_range
	no_crit.falloff_start = stats.falloff_start
	no_crit.falloff_end = stats.falloff_end
	no_crit.falloff_floor = stats.falloff_floor
	no_crit.behaviours = stats.behaviours
	no_crit.extra = stats.extra
	no_crit.crit_chance = 0.0
	var shot := resolve_shot(no_crit, context, rng)
	return shot.damage * (1.0 + stats.crit_chance * (stats.crit_multiplier - 1.0))


## Expected damage of one trigger pull against a single enemy at a distance: every ray of the
## shot lands on it, so a Splitter's total shows rather than one pellet, and an explosive round's
## blast lands on its direct target too.
static func expected_damage_at(stats: WeaponStats, distance: float) -> float:
	var context := ShotContext.new()
	context.distance = distance
	# A Charge receiver's readouts assume a full charge; its sustained rate counts the charge time.
	context.charge = 1.0 if stats.fire_mode() == "charge" else 0.0
	var per_ray := expected_damage(stats, context) + blast_damage(stats, distance, context.charge)
	return per_ray * int(stats.behaviours.get("ray_count", 1)) * ray_hit_share(stats, distance)


## The share of a pull's rays that land on one robot at `distance`: every ray is spread evenly over
## a disc of spread_degrees (Pistol._ray_direction), and a robot is about READOUT_TARGET_RADIUS
## wide. 1 without spread, so a Splitter reads as 125% up close and falls off past a few metres.
static func ray_hit_share(stats: WeaponStats, distance: float) -> float:
	var spread := float(stats.behaviours.get("spread_degrees", 0.0))
	if spread <= 0.0:
		return 1.0
	var disc := distance * tan(deg_to_rad(spread))
	if disc <= READOUT_TARGET_RADIUS:
		return 1.0
	return pow(READOUT_TARGET_RADIUS / disc, 2.0)


func seconds_between_shots() -> float:
	return 1.0 / fire_rate


## Seconds from one round to the next when firing flat out: the cooldown, plus a full charge for
## a Charge receiver.
func seconds_per_round() -> float:
	return seconds_between_shots() + charge_time()


func charge_time() -> float:
	return float(behaviours.get("charge_time", 0.0)) if fire_mode() == "charge" else 0.0


## Rounds fired per magazine: more than it holds when some shots are free (Overflow).
func rounds_per_magazine() -> float:
	return magazine_size / maxf(1.0 - clampf(extra_percent(FREE_SHOT_KEY), 0.0, 0.9), 0.1)


## Sustained damage per second including reloads, for the bench summary. A burning round adds its
## burn (one burn per robot, refreshed while the fire keeps up, so about a burn's worth a second).
func sustained_dps(distance := 10.0) -> float:
	var rounds := rounds_per_magazine()
	var magazine_time := rounds * seconds_per_round()
	var per_round := WeaponStats.expected_damage_at(self, distance)
	var dps := per_round * rounds / (magazine_time + reload_time)
	if String(behaviours.get("on_hit", "")) == "burn":
		dps += per_round * StatusEffects.BURN_SHARE_PER_SECOND
	return dps


## A modifier sum from `extra`, percent and flat together (keys like ammo refund or status duration).
func extra_percent(key: String) -> float:
	var entry: Dictionary = extra.get(key, {})
	return float(entry.get("percent", 0.0)) + float(entry.get("flat", 0.0))


func shots_to_kill(health: float, distance := 10.0) -> int:
	return maxi(ceili(health / maxf(WeaponStats.expected_damage_at(self, distance), 0.001)), 1)


func fire_mode() -> String:
	return String(behaviours.get("fire_mode", "semi"))


func pierce() -> int:
	return int(behaviours.get("pierce", 0))


func blast_radius() -> float:
	return float(behaviours.get("blast_radius", 0.0))


## One plus the build's weak-point damage bonus (the Precise affix).
func weak_point_bonus() -> float:
	return 1.0 + float(extra.get(WEAK_POINT_KEY, {}).get("percent", 0.0))


## How much wider weak points count (Reflex sight).
func weak_point_scale() -> float:
	return maxf(float(behaviours.get("weak_point_scale", 1.0)), 1.0)


## Status effects last this many times their base duration (Lingering, Status Mastery).
func status_duration_scale() -> float:
	return maxf(1.0 + extra_percent(STATUS_DURATION_KEY), 0.1)


## Short human-readable list of the behaviours that differ from a plain semi-automatic pistol.
func describe_behaviours() -> PackedStringArray:
	var parts := PackedStringArray()
	match fire_mode():
		"auto":
			parts.append("Automatic")
		"burst":
			parts.append("%d-round burst" % int(behaviours.get("burst_size", 3)))
		"charge":
			parts.append("Charge")
		_:
			parts.append("Semi-auto")
	if pierce() > 0:
		parts.append("pierces %d" % pierce())
	if int(behaviours.get("ray_count", 1)) > 1:
		parts.append("%d rays" % int(behaviours.get("ray_count", 1)))
	if int(behaviours.get("bounces", 0)) > 0:
		parts.append("bounces %d" % int(behaviours.get("bounces", 0)))
	match String(behaviours.get("projectile", "hitscan")):
		"hitscan":
			pass
		"shell":
			parts.append("explosive shells (%.1f m blast)" % blast_radius() if blast_radius() > 0.0 else "shells")
		"charge":
			parts.append("charged rounds" + (" (%.1f to %.1f m blast)" % [blast_radius(), blast_radius_at(1.0)] if blast_radius() > 0.0 else ""))
		var profile:
			parts.append(String(profile).capitalize() + " rounds")
	match String(behaviours.get("on_hit", "")):
		"burn":
			parts.append("burns")
		"cryo":
			parts.append("slows and shatters")
		"shock":
			parts.append("arcs")
	if bool(behaviours.get("hollow_point", false)):
		parts.append("hollow point")
	if float(behaviours.get("rangefinder", 0.0)) > 0.0:
		parts.append("rangefinder")
	if float(behaviours.get("spread_degrees", 0.0)) > 0.0 and int(behaviours.get("ray_count", 1)) == 1:
		parts.append("%.1f° spread" % float(behaviours.get("spread_degrees", 0.0)))
	match String(behaviours.get("alt_fire", "")):
		"launcher":
			parts.append("grenade launcher")
	if bool(behaviours.get("reload_shield", false)):
		parts.append("reload shield")
	if bool(behaviours.get("scanner", false)):
		parts.append("scanner")
	return parts


static func _apply(base_value: float, flats: Dictionary, percents: Dictionary, key: String) -> float:
	return (base_value + flats.get(key, 0.0)) * (1.0 + percents.get(key, 0.0))
