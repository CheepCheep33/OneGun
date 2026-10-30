class_name ProjectilePool
extends Node3D
## The minimum shared projectile system (plan: Bullet simulation). Projectiles are pooled movers,
## not rigid bodies: each physics tick one moves along its velocity and raycasts the segment it
## crossed, so fast rounds never tunnel through thin walls. Enemy bolts and player ammo types
## share it; a player round carries the build stats and resolves hits through ShotPipeline exactly
## like a hitscan ray. Hard cap of MAX_LIVE live projectiles, oldest enemy shots expiring first.

const MAX_LIVE := 200
## Projectile profiles by id. Player ammo names one in its `projectile` behaviour (Milestone 4+).
const PROFILES := {
	"bolt": {"speed": 16.0, "gravity": 0.0, "radius": 0.18, "lifetime": 4.0, "bounces": 0},
	"shell": {"speed": 28.0, "gravity": 1.0, "radius": 0.12, "lifetime": 4.0, "bounces": 0},
	"ricochet": {"speed": 60.0, "gravity": 0.0, "radius": 0.06, "lifetime": 3.0, "bounces": 2},
	"charge": {"speed": 90.0, "gravity": 0.0, "radius": 0.1, "lifetime": 3.0, "bounces": 0},
}
const WORLD_LAYER := 1
const PLAYER_LAYER := 2
const ENEMY_LAYER := 4
## Hits and bounces one round may resolve in a single tick before it is stopped.
const MAX_EVENTS_PER_TICK := 8

enum Team { PLAYER, ENEMY }

## The pool of the running main scene, for enemies and the pistol to fire from.
static var current: ProjectilePool

var _free: Array[Projectile] = []
var _live: Array[Projectile] = []
## Capsule meshes by radius, so launching a round never builds a mesh (a stall on the web build).
var _capsules: Dictionary = {}
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


## One pooled round. Plain Node3D with a mesh child; movement and hits are done by the pool.
class Projectile:
	extends Node3D
	var active := false
	var team := Team.ENEMY
	var velocity := Vector3.ZERO
	var gravity_scale := 0.0
	var lifetime := 4.0
	var age := 0.0
	var mask := 0
	var exclude: Array[RID] = []
	## Enemy bolts carry flat damage; player rounds carry the build and resolve through the pipeline.
	var damage := 0.0
	var stats: WeaponStats
	var shot: ShotPipeline.ShotState
	var pierce_left := 0
	var bounces_left := 0
	var enemy_hits := 0
	var bounce_count := 0
	var travelled := 0.0
	var mesh: MeshInstance3D
	var material: StandardMaterial3D


func _ready() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


func live_count() -> int:
	return _live.size()


## Fires one enemy bolt that damages the player on contact and stops at the world.
func fire_enemy_bolt(shooter: Node3D, origin: Vector3, velocity: Vector3, damage: float, color: Color,
		lifetime := 4.0, radius := 0.18) -> Projectile:
	var projectile := _acquire()
	projectile.team = Team.ENEMY
	projectile.mask = WORLD_LAYER | PLAYER_LAYER
	var excluded: Array[RID] = []
	if shooter is CollisionObject3D:
		excluded.append(shooter.get_rid())
	projectile.exclude = excluded
	projectile.damage = damage
	projectile.stats = null
	projectile.shot = null
	projectile.pierce_left = 0
	projectile.bounces_left = 0
	projectile.gravity_scale = 0.0
	_launch(projectile, origin, velocity, lifetime, radius, color)
	return projectile


## Fires one player round with the build stats. Pierce, bounces and procs follow the same rules as
## a hitscan ray; the profile sets speed, gravity, radius and the bounces the round may make.
func fire_player_round(shooter_rid: RID, origin: Vector3, direction: Vector3, stats: WeaponStats,
		shot: ShotPipeline.ShotState, profile: Dictionary, color := Color(1.0, 0.9, 0.55)) -> Projectile:
	var projectile := _acquire()
	projectile.team = Team.PLAYER
	projectile.mask = WORLD_LAYER | ENEMY_LAYER
	var excluded: Array[RID] = [shooter_rid]
	projectile.exclude = excluded
	projectile.damage = 0.0
	projectile.stats = stats
	projectile.shot = shot
	projectile.pierce_left = stats.pierce()
	var bounces: int = int(stats.behaviours.get("bounces", 0))
	if bounces <= 0:
		bounces = int(profile.get("bounces", 0))
	projectile.bounces_left = clampi(bounces, 0, WeaponStats.BOUNCE_CAP)
	projectile.gravity_scale = float(profile.get("gravity", 0.0))
	_launch(projectile, origin, direction.normalized() * float(profile.get("speed", 30.0)),
		float(profile.get("lifetime", 4.0)), float(profile.get("radius", 0.1)), color)
	return projectile


## Retires every live projectile (plan: starting any encounter resets it).
func clear_all() -> void:
	for projectile in _live.duplicate():
		_retire(projectile)


func _physics_process(delta: float) -> void:
	for projectile in _live.duplicate():
		if projectile.active:
			_step(projectile, delta)


## Moves one round for a tick: sweep the segment it would cross, resolve what it meets, and keep
## going with the time that is left after each hit or bounce.
func _step(p: Projectile, delta: float) -> void:
	p.age += delta
	if p.age > p.lifetime:
		_retire(p)
		return
	if p.gravity_scale > 0.0:
		p.velocity.y -= _gravity * p.gravity_scale * delta
	var space := get_world_3d().direct_space_state
	var from := p.global_position
	var remaining := delta
	for event in MAX_EVENTS_PER_TICK:
		var to := from + p.velocity * remaining
		var query := PhysicsRayQueryParameters3D.create(from, to, p.mask, p.exclude)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			from = to
			break
		var segment := from.distance_to(to)
		var used := from.distance_to(hit.position) / segment if segment > 0.0001 else 1.0
		remaining *= 1.0 - clampf(used, 0.0, 1.0)
		p.travelled += from.distance_to(hit.position)
		var collider: Object = hit.collider
		if p.team == Team.ENEMY and collider is Player:
			collider.take_damage(p.damage)
			Fx.impact(self, hit.position, hit.normal)
			_retire(p)
			return
		if p.team == Team.PLAYER and collider is Node and collider.has_method("take_hit"):
			var context := WeaponStats.ShotContext.new()
			context.distance = p.travelled
			context.pierce_index = p.enemy_hits
			context.bounce_index = p.bounce_count
			var result := ShotPipeline.apply_hit(collider, hit.position, p.velocity.normalized(), p.stats, context, p.shot)
			_report_player_hit(p, result)
			p.enemy_hits += 1
			if p.pierce_left > 0 and p.enemy_hits < ShotPipeline.MAX_ENEMY_HITS_PER_RAY:
				p.pierce_left -= 1
				p.exclude.append(hit.rid)
				from = hit.position
				continue
			_retire(p)
			return
		# World geometry (or something a bolt cannot damage): bounce if any remain, else stop.
		if p.bounces_left <= 0:
			Fx.impact(self, hit.position, hit.normal)
			_retire(p)
			return
		_bounce(p, hit)
		from = p.global_position
	p.global_position = from
	_orient(p)


## Reflects the round off world geometry (plan: pierce, bounce, stop; damage split).
func _bounce(p: Projectile, hit: Dictionary) -> void:
	p.bounces_left -= 1
	p.bounce_count += 1
	var normal: Vector3 = hit.normal
	p.velocity = p.velocity.bounce(normal)
	p.damage *= WeaponStats.BOUNCE_FALLOFF
	p.global_position = hit.position + normal * 0.02
	# A bounce forgets pierced enemies so a Ricochet plus Penetrator round can pass new ones.
	if p.team == Team.PLAYER and p.exclude.size() > 1:
		var kept: Array[RID] = [p.exclude[0]]
		p.exclude = kept
	Fx.impact(self, hit.position, normal)


func _report_player_hit(p: Projectile, result: ShotPipeline.HitResult) -> void:
	if p.shot != null and p.shot.scene != null and p.shot.scene.has_signal("hit_landed"):
		p.shot.scene.hit_landed.emit(result.killed)
	if Settings.show_damage_numbers and result.damage > 0.0:
		Fx.damage_number(self, result.position, result.damage, result.killed)


func _acquire() -> Projectile:
	if _live.size() >= MAX_LIVE:
		# Over budget: the oldest enemy projectile expires first, then the oldest of any kind.
		var victim: Projectile = null
		for projectile in _live:
			if projectile.team == Team.ENEMY:
				victim = projectile
				break
		_retire(victim if victim else _live[0])
	var projectile: Projectile
	if _free.is_empty():
		projectile = Projectile.new()
		projectile.mesh = MeshInstance3D.new()
		projectile.mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# A capsule points along Y; turn it to point along -Z, the direction look_at faces.
		projectile.mesh.rotation.x = PI / 2.0
		projectile.material = StandardMaterial3D.new()
		projectile.material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		projectile.mesh.material_override = projectile.material
		projectile.add_child(projectile.mesh)
		add_child(projectile)
	else:
		projectile = _free.pop_back()
	projectile.active = true
	projectile.visible = true
	projectile.age = 0.0
	projectile.enemy_hits = 0
	projectile.bounce_count = 0
	projectile.travelled = 0.0
	_live.append(projectile)
	return projectile


func _launch(p: Projectile, origin: Vector3, velocity: Vector3, lifetime: float, radius: float, color: Color) -> void:
	p.velocity = velocity
	p.lifetime = lifetime
	p.mesh.mesh = _capsule_for(radius)
	p.material.albedo_color = color
	p.global_position = origin
	_orient(p)


func _capsule_for(radius: float) -> CapsuleMesh:
	var key := snappedf(radius, 0.001)
	if not _capsules.has(key):
		var capsule := CapsuleMesh.new()
		capsule.radius = radius
		capsule.height = radius * 6.0
		capsule.radial_segments = 8
		capsule.rings = 2
		_capsules[key] = capsule
	return _capsules[key]


func _orient(p: Projectile) -> void:
	if p.velocity.length_squared() > 0.0001:
		var up := Vector3.UP if absf(p.velocity.normalized().dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
		p.look_at(p.global_position + p.velocity, up)


func _retire(p: Projectile) -> void:
	if p == null or not p.active:
		return
	p.active = false
	p.visible = false
	p.stats = null
	p.shot = null
	var none: Array[RID] = []
	p.exclude = none
	_live.erase(p)
	_free.append(p)
