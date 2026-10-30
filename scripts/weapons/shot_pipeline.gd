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
			var context := WeaponStats.ShotContext.new()
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


static func is_shield(collider: Object) -> bool:
	return collider is Node and (collider as Node).is_in_group(SHIELD_GROUP)


## Damages one enemy with the build's numbers for this hit's context, then runs the procs.
static func apply_hit(target: Node, position: Vector3, direction: Vector3, stats: WeaponStats,
		context: WeaponStats.ShotContext, shot: ShotState) -> HitResult:
	var result := HitResult.new()
	result.target = target
	result.position = position
	result.pierce_index = context.pierce_index
	var roll := WeaponStats.resolve_shot(stats, context, shot.rng)
	if not roll.in_range:
		return result
	var damage := roll.damage
	# Weak points multiply after crits (plan: weak points) and ignore armour.
	if target.has_method("is_weak_point") and target.is_weak_point(position):
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
	return result


## Bursts an explosive round at `center`: every living enemy whose centre is inside the build's
## blast radius takes blast_damage, once, with no crit, no weak point and no procs (plan: damage
## split, procs). `distance` is how far the round travelled, for falloff. Returns the hits.
static func blast(center: Vector3, distance: float, stats: WeaponStats, shot: ShotState) -> Array[HitResult]:
	var hits: Array[HitResult] = []
	var radius := stats.blast_radius()
	var damage := WeaponStats.blast_damage(stats, distance)
	if shot == null or shot.scene == null or not shot.scene.is_inside_tree():
		return hits
	Fx.blast(shot.scene, center, radius)
	if damage <= 0.0:
		return hits
	var reach := radius + BLAST_BODY_ALLOWANCE
	var tree := shot.scene.get_tree()
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
		hit.killed = node.take_hit(damage, at, (at - center).normalized())
		hit.damage = node.last_damage_taken if "last_damage_taken" in node else damage
		shot.hits += 1
		if hit.killed:
			shot.kills += 1
		hits.append(hit)
	return hits


## Arcs half the hit's damage to the nearest other living enemy within CHAIN_RANGE that this shot
## has not chained to yet. A chained hit never chains again and never procs (plan: Chains).
static func _chain_from(source: Node, damage: float, shot: ShotState) -> void:
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
	var chained_damage := damage * CHAIN_DAMAGE_SHARE
	var killed: bool = best.take_hit(chained_damage, to, (to - from).normalized())
	if "last_damage_taken" in best:
		chained_damage = best.last_damage_taken
	Fx.tracer(shot.scene, from, to, Color(0.5, 0.8, 1.0, 0.9))
	if Settings.show_damage_numbers:
		Fx.damage_number(shot.scene, to, chained_damage, killed)
