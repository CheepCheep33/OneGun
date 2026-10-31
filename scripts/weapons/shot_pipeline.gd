class_name ShotPipeline
extends RefCounted
## Hit resolution shared by hitscan rays and simulated projectiles (plan: interaction rules).
## Receiver decides shots per pull and muzzle decides rays per shot (the pistol); each ray then
## resolves here on its own: pierce through enemies, stop at the world (projectiles may bounce),
## damage from WeaponStats.resolve_shot with the pierce and bounce indices, then affix procs.
## Only direct hits proc. Ammo refund fires at most once per shot; a chain has depth 1 and an
## enemy is the target of one chain per shot at most. Weak points (the heavy's core) multiply
## after crits and ignore armour. Shields (group "shields") stop every round and every ray, with
## no bounce; an explosive round still bursts there, so its blast reaches around the shield.
## Ammo statuses (StatusEffects) land on direct hits: Incendiary burns, Cryo slows and then
## shatters, Shock arcs once and stuns. Area damage (blasts, shatters, grenades) goes through
## area_damage: never a crit, a weak point or a proc.

## A Ricochet plus Penetrator round can pass two enemies, bounce, and pass two more, within this cap.
const MAX_ENEMY_HITS_PER_RAY := 6
const CHAIN_RANGE := 6.0
const CHAIN_DAMAGE_SHARE := 0.5
## How far from a blast's centre an enemy's own centre may be and still be caught: the blast
## radius plus about a robot's half-width.
const BLAST_BODY_ALLOWANCE := 0.5
const SHIELD_GROUP := "shields"
## Non-enemy targets a blast still reaches: the Firing Range's dummies.
const BLAST_TARGET_GROUP := "blast_targets"

## State shared by every ray of one trigger pull.
class ShotState:
	extends RefCounted
	var rng: RandomNumberGenerator
	## A node in the scene tree, for effects and the enemies group.
	var scene: Node
	var ammo_refund_chance := 0.0
	var chain_chance := 0.0
	## 0 to 1 for a Charge receiver's round.
	var charge := 0.0
	var player_health_fraction := 1.0
	var overclock_active := false
	## Every hit of this shot is a critical hit (Triplet: a burst's last round).
	var force_crit := false
	var refund_fired := false
	## Rounds to give back to the magazine after the shot.
	var refunds := 0
	## Instance ids of enemies already chained into this shot.
	var chained: Array[int] = []
	var hits := 0
	var kills := 0
	var crits := 0


## One enemy damaged by a ray.
class HitResult:
	extends RefCounted
	var target: Node
	var position: Vector3
	var damage := 0.0
	var is_crit := false
	var killed := false
	var pierce_index := 0
	var weak_point := false


## Where a hitscan ray ended and what it hit on the way.
class RayResult:
	extends RefCounted
	var end_point: Vector3
	var hits: Array[HitResult] = []
	var hit_world := false
	## The ray stopped on a shield (hit_world is set too: it stops the same way).
	var hit_shield := false
	var world_normal := Vector3.UP


## Casts one hitscan ray: pierces through enemies while pierce remains, stops at the world.
static func fire_hitscan(space: PhysicsDirectSpaceState3D, origin: Vector3, direction: Vector3,
		stats: WeaponStats, shot: ShotState, mask: int, exclude: Array[RID]) -> RayResult:
	var result := RayResult.new()
	var far := origin + direction * stats.max_range
	result.end_point = far
	var excluded: Array[RID] = exclude.duplicate()
	var pierce_left := stats.pierce()
	var enemy_hits := 0
	var from := origin
	for guard in MAX_ENEMY_HITS_PER_RAY + 2:
		var query := PhysicsRayQueryParameters3D.create(from, far, mask, excluded)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		result.end_point = hit.position
		var collider: Object = hit.collider
		if collider is Node and collider.has_method("take_hit"):
			var context := context_for(shot)
			context.distance = origin.distance_to(hit.position)
			context.pierce_index = enemy_hits
			result.hits.append(apply_hit(collider, hit.position, direction, stats, context, shot))
			enemy_hits += 1
			if pierce_left > 0 and enemy_hits < MAX_ENEMY_HITS_PER_RAY:
				pierce_left -= 1
				excluded.append(hit.rid)
				from = hit.position
				continue
			break
		result.hit_world = true
		result.hit_shield = is_shield(collider)
		result.world_normal = hit.normal
		break
	return result


## A context carrying what the shot knows (charge, player health, Overclock, a forced crit); the
## caller adds distance and the pierce and bounce indices.
static func context_for(shot: ShotState) -> WeaponStats.ShotContext:
	var context := WeaponStats.ShotContext.new()
	if shot != null:
		context.charge = shot.charge
		context.player_health_fraction = shot.player_health_fraction
		context.overclock_active = shot.overclock_active
		context.force_crit = shot.force_crit
	return context


static func is_shield(collider: Object) -> bool:
	return collider is Node and (collider as Node).is_in_group(SHIELD_GROUP)


## Damages one enemy with the build's numbers for this hit's context, then runs the procs.
static func apply_hit(target: Node, position: Vector3, direction: Vector3, stats: WeaponStats,
		context: WeaponStats.ShotContext, shot: ShotState) -> HitResult:
	var result := HitResult.new()
	result.target = target
	result.position = position
	result.pierce_index = context.pierce_index
	var enemy := target as Enemy
	if enemy != null:
		context.target_health_fraction = enemy.health_fraction()
		context.target_armored = enemy.is_armored()
	var roll := WeaponStats.resolve_shot(stats, context, shot.rng)
	if not roll.in_range:
		return result
	var damage := roll.damage
	# Weak points multiply after crits (plan: weak points) and ignore armour.
	if target.has_method("is_weak_point") and target.is_weak_point(position, stats.weak_point_scale()):
		result.weak_point = true
		damage *= WeaponStats.WEAK_POINT_MULTIPLIER * stats.weak_point_bonus()
	result.is_crit = roll.is_crit
	result.killed = target.take_hit(damage, position, direction, result.weak_point)
	# Armour may have taken some of it; the number shown is what the enemy lost.
	result.damage = target.last_damage_taken if "last_damage_taken" in target else damage
	shot.hits += 1
	if result.killed:
		shot.kills += 1
	if result.is_crit:
		shot.crits += 1
	# Procs: direct hits only, and ammo refund at most once per shot (plan: Procs).
	if result.killed and not shot.refund_fired and shot.ammo_refund_chance > 0.0 \
			and shot.rng.randf() < shot.ammo_refund_chance:
		shot.refund_fired = true
		shot.refunds = 1
	if result.is_crit and shot.chain_chance > 0.0 and shot.rng.randf() < shot.chain_chance:
		_chain_from(target, roll.damage, shot)
	_apply_on_hit(enemy, result, roll.damage, stats, shot)
	return result


## The ammo's status on a direct hit, and Stillwater's slow (plan: status effects are enemy-side;
## only direct hits apply them). `hit_damage` is the hit before armour.
static func _apply_on_hit(enemy: Enemy, result: HitResult, hit_damage: float, stats: WeaponStats, shot: ShotState) -> void:
	if enemy == null:
		return
	var duration_scale := stats.status_duration_scale()
	match String(stats.behaviours.get("on_hit", "")):
		"burn":
			enemy.apply_burn(hit_damage * StatusEffects.BURN_SHARE_PER_SECOND, StatusEffects.BURN_DURATION * duration_scale)
		"cryo":
			if enemy.can_shatter():
				enemy.consume_slow()
				shatter(enemy.center(), hit_damage * StatusEffects.SHATTER_SHARE, shot)
			elif not result.killed:
				enemy.apply_slow(StatusEffects.SLOW_SHARE, StatusEffects.SLOW_DURATION * duration_scale)
		"shock":
			_chain_from(enemy, hit_damage, shot, StatusEffects.SHOCK_SHARE, StatusEffects.SHOCK_STUN * duration_scale)
	if bool(stats.behaviours.get("slow_on_pierce", false)) and not result.killed:
		enemy.apply_slow(StatusEffects.PIERCE_SLOW_SHARE, StatusEffects.PIERCE_SLOW_DURATION * duration_scale)


## Bursts an explosive round at `center`: every living enemy whose centre is inside the build's
## blast radius (wider for a charged round) takes blast_damage, once, with no crit, no weak point
## and no procs (plan: damage split, procs); Sunburst sets them burning. `distance` is how far
## the round travelled, for falloff. Returns the hits.
static func blast(center: Vector3, distance: float, stats: WeaponStats, shot: ShotState) -> Array[HitResult]:
	var charge := shot.charge if shot != null else 0.0
	var radius := stats.blast_radius_at(charge)
	var damage := WeaponStats.blast_damage(stats, distance, charge)
	if shot == null or shot.scene == null or not shot.scene.is_inside_tree():
		var none: Array[HitResult] = []
		return none
	Fx.blast(shot.scene, center, radius)
	var hits := area_damage(shot.scene, center, radius, damage, shot)
	if bool(stats.behaviours.get("blast_burn", false)):
		for hit in hits:
			if hit.target is Enemy and not hit.killed:
				(hit.target as Enemy).apply_burn(damage * StatusEffects.BURN_SHARE_PER_SECOND,
					StatusEffects.BURN_DURATION * stats.status_duration_scale())
	return hits


## Cryo's shatter: `damage` to every living robot within SHATTER_RADIUS of `center`, as status
## damage (no armour, no procs).
static func shatter(center: Vector3, damage: float, shot: ShotState) -> Array[HitResult]:
	if shot == null or shot.scene == null or not shot.scene.is_inside_tree():
		var none: Array[HitResult] = []
		return none
	Fx.shatter(shot.scene, center, StatusEffects.SHATTER_RADIUS)
	var hits := area_damage(shot.scene, center, StatusEffects.SHATTER_RADIUS, damage, shot, true)
	for hit in hits:
		if Settings.show_damage_numbers and hit.damage > 0.0:
			Fx.damage_number(shot.scene, hit.position, hit.damage, hit.killed)
	return hits


## `damage` once to every living enemy (and Firing Range dummy) whose centre is within `radius`
## plus a robot's half-width of `center`: blasts, shatters and grenades. Never a crit, a weak point
## or a proc. `as_status` skips armour (a shatter). Counts hits and kills on `shot` when given.
static func area_damage(scene: Node, center: Vector3, radius: float, damage: float, shot: ShotState = null,
		as_status := false) -> Array[HitResult]:
	var hits: Array[HitResult] = []
	if damage <= 0.0 or scene == null or not scene.is_inside_tree():
		return hits
	var reach := radius + BLAST_BODY_ALLOWANCE
	var tree := scene.get_tree()
	for node in tree.get_nodes_in_group("enemies") + tree.get_nodes_in_group(BLAST_TARGET_GROUP):
		if not (node is Node3D) or not node.has_method("take_hit"):
			continue
		if "is_alive" in node and not node.is_alive:
			continue
		var at: Vector3 = node.center() if node.has_method("center") else node.global_position + Vector3.UP * 0.9
		if at.distance_to(center) > reach:
			continue
		var hit := HitResult.new()
		hit.target = node
		hit.position = at
		if as_status and node.has_method("take_status_damage"):
			hit.killed = node.take_status_damage(damage)
		else:
			hit.killed = node.take_hit(damage, at, (at - center).normalized())
		hit.damage = node.last_damage_taken if "last_damage_taken" in node else damage
		if shot != null:
			shot.hits += 1
			if hit.killed:
				shot.kills += 1
		hits.append(hit)
	return hits


## Arcs `share` of the hit's damage to the nearest other living enemy within CHAIN_RANGE that this
## shot has not chained to yet, stunning it for `stun` seconds (Shock). A chained hit never chains
## again and never procs (plan: Chains): Shock rounds and the Arcing affix share the one-chain-per-
## robot rule.
static func _chain_from(source: Node, damage: float, shot: ShotState, share := CHAIN_DAMAGE_SHARE, stun := 0.0) -> void:
	if shot.scene == null or not shot.scene.is_inside_tree() or not (source is Node3D):
		return
	var best: Node3D = null
	var best_distance := CHAIN_RANGE
	for node in shot.scene.get_tree().get_nodes_in_group("enemies"):
		if node == source or not (node is Node3D) or not node.has_method("take_hit"):
			continue
		if "is_alive" in node and not node.is_alive:
			continue
		if shot.chained.has(node.get_instance_id()):
			continue
		var distance: float = node.global_position.distance_to(source.global_position)
		if distance <= best_distance:
			best_distance = distance
			best = node
	if best == null:
		return
	shot.chained.append(best.get_instance_id())
	var from: Vector3 = source.global_position + Vector3.UP * 0.9
	var to: Vector3 = best.global_position + Vector3.UP * 0.9
	var chained_damage := damage * share
	var killed: bool = best.take_hit(chained_damage, to, (to - from).normalized())
	if stun > 0.0 and not killed and best is Enemy:
		(best as Enemy).apply_stun(stun)
	if "last_damage_taken" in best:
		chained_damage = best.last_damage_taken
	Fx.tracer(shot.scene, from, to, Color(0.5, 0.8, 1.0, 0.9))
	if Settings.show_damage_numbers:
		Fx.damage_number(shot.scene, to, chained_damage, killed)
