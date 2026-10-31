extends TestCase
## Milestone 4 roster and ammo checks in the running game: the heavy's armour and weak point, the
## shield bearer's shield against rays, rounds and blasts, Explosive splash, the Foreman's summons
## and molten pools, and the dangerous combinations the plan names (Splitter plus chain arcs and Shock arcs,
## Ricochet plus Penetrator).

const HEAVY := "res://data/enemies/heavy.tres"
const HEAVY_SCENE := "res://scenes/enemies/heavy.tscn"
const BEARER := "res://data/enemies/shield_bearer.tres"
const BEARER_SCENE := "res://scenes/enemies/shield_bearer.tscn"
const FOREMAN := "res://data/enemies/foreman.tres"
const FOREMAN_SCENE := "res://scenes/enemies/foreman.tscn"
## Player rays: the world, enemies and shields (the pistol's mask).
const RAY_MASK := 1 | 4 | 8


func run_scene(game: Node) -> void:
	game.open_bench()
	await physics_frames(2)
	Progression.reset()
	game.start_wave(1)
	await physics_frames(3)
	game.wave_runner.stop()
	await _test_heavy(game)
	await _test_shield_bearer(game)
	await _test_explosive(game)
	await _test_splitter_chain(game)
	await _test_ricochet_penetrator(game)
	await _test_foreman(game)
	game.open_bench()
	await physics_frames(2)
	Progression.reset()
	# Leave wave 1 running with its spawns stopped, as the case before this one did.
	game.start_wave(1)
	await physics_frames(3)
	game.wave_runner.stop()


# ------------------------------------------------------------------ helpers

## Builds the pistol with these items fitted ({slot: item}).
func _stats(items: Dictionary) -> WeaponStats:
	return WeaponStats.build(Progression.PISTOL_BASE, Progression.core_levels(), items)


func _shot(game: Node) -> ShotPipeline.ShotState:
	var shot := ShotPipeline.ShotState.new()
	shot.rng = rng(41)
	shot.scene = game.player.pistol
	return shot


## Stops an enemy where it stands, turned towards `look_at`, so a test can aim at a known pose.
func _freeze(enemy: Enemy, look_at: Vector3) -> void:
	enemy.set_physics_process(false)
	enemy._face(look_at - enemy.global_position)


## Lets every frozen enemy move again (the reserve reuses the nodes) and clears the arena.
func _cleanup(game: Node) -> void:
	for enemy in game.wave_runner.living_enemies():
		enemy.set_physics_process(true)
	game.wave_runner.clear_enemies()
	game.projectiles.clear_all()
	game.player.revive(game.arena.get_player_start())
	await physics_frames(2)


func _ray(game: Node, origin: Vector3, target: Vector3, stats: WeaponStats, shot: ShotPipeline.ShotState) -> ShotPipeline.RayResult:
	var exclude: Array[RID] = [game.player.get_rid()]
	return ShotPipeline.fire_hitscan(game.player.get_world_3d().direct_space_state, origin, (target - origin).normalized(),
		stats, shot, RAY_MASK, exclude)


## Counts each enemy's hits (every take_hit that lands emits health_changed). Call _stop_counting
## before the enemies go back to the reserve.
func _count_hits(enemies: Array) -> Dictionary:
	var counts := {}
	for enemy in enemies:
		counts[enemy] = 0
		var counter := func(_health: float, _max: float) -> void: counts[enemy] += 1
		enemy.set_meta("test_counter", counter)
		enemy.health_changed.connect(counter)
	return counts


func _stop_counting(counts: Dictionary) -> void:
	for enemy in counts:
		enemy.health_changed.disconnect(enemy.get_meta("test_counter"))
		enemy.remove_meta("test_counter")


func _eye(game: Node) -> Vector3:
	return game.player.global_position + Vector3.UP * 0.9


# ------------------------------------------------------------------ heavy

func _test_heavy(game: Node) -> void:
	var heavy := spawn_in_front(game, 8.0, HEAVY, HEAVY_SCENE)
	await seconds(Enemy.SPAWN_TIME + 0.1)
	_freeze(heavy, game.player.global_position)
	await physics_frames(1)
	var stats := _stats({})
	var raw := stats.damage * WeaponStats.falloff_multiplier(stats, 3.0)
	var front := heavy.global_position - heavy.global_basis.z * 3.0
	var back := heavy.global_position + heavy.global_basis.z * 3.0
	var health := heavy.health
	var hit := _ray(game, front + Vector3.UP * 1.0, heavy.global_position + Vector3.UP * 1.0, stats, _shot(game))
	var armoured := maxf(raw - heavy.definition.armor * heavy.health_scale, raw * (1.0 - Enemy.ARMOR_MAX_SHARE))
	check(hit.hits.size() == 1 and not hit.hits[0].weak_point and is_equal_approx(health - heavy.health, armoured),
		"armour takes a flat share of a front hit (%.1f of %.1f landed)" % [health - heavy.health, raw])
	health = heavy.health
	var core_height := Vector3.UP * heavy.definition.weak_point_offset.y
	hit = _ray(game, back + core_height, heavy.global_position + core_height, stats, _shot(game))
	check(hit.hits.size() == 1 and hit.hits[0].weak_point and is_equal_approx(health - heavy.health, raw * WeaponStats.WEAK_POINT_MULTIPLIER),
		"a hit on the core from behind doubles and ignores armour (%.1f)" % (health - heavy.health))
	var precise := Items.make(&"long_barrel", Items.Rarity.UNCOMMON, [{"id": "precise", "roll": 1.0}])
	var precise_stats := _stats({"barrel": precise})
	check(precise_stats.weak_point_bonus() > 1.0, "the Precise affix raises weak-point damage (x%.2f)" % precise_stats.weak_point_bonus())
	# A tiny hit still lands a quarter through the armour.
	health = heavy.health
	heavy.take_hit(2.0, heavy.global_position, Vector3.FORWARD)
	check(is_equal_approx(health - heavy.health, 0.5), "armour never stops more than three quarters of a hit")
	await _cleanup(game)


# ------------------------------------------------------------------ shield bearer

func _test_shield_bearer(game: Node) -> void:
	var bearer: ShieldBearer = spawn_in_front(game, 7.0, BEARER, BEARER_SCENE)
	await seconds(Enemy.SPAWN_TIME + 0.1)
	_freeze(bearer, game.player.global_position)
	await physics_frames(2)
	check(bearer.shield_up, "the shield is up while the bearer walks in")
	var stats := _stats({})
	var health := bearer.health
	var result := _ray(game, _eye(game), bearer.center(), stats, _shot(game))
	check(result.hits.is_empty() and result.hit_shield and is_equal_approx(bearer.health, health), "a hitscan ray from the front stops on the shield")
	# A piercing ray stops there too, and so does an enemy standing behind the bearer.
	var behind := spawn_in_front(game, 9.0)
	await seconds(Enemy.SPAWN_TIME + 0.1)
	_freeze(behind, game.player.global_position)
	var penetrator := _stats({"barrel": Items.make(&"penetrator_barrel")})
	result = _ray(game, _eye(game), bearer.center(), penetrator, _shot(game))
	check(result.hits.is_empty() and is_equal_approx(behind.health, behind.max_health), "pierce does not pass the shield or reach the enemy it covers")
	# Ricochet rounds stop on the shield with no bounce.
	var ricochet_stats := _stats({"ammo": Items.make(&"ricochet_rounds")})
	var fired: ProjectilePool.Projectile = game.projectiles.fire_player_round(game.player.get_rid(), _eye(game), (bearer.center() - _eye(game)).normalized(),
		ricochet_stats, _shot(game), ProjectilePool.PROFILES["ricochet"])
	await physics_frames(10)
	check(not fired.active and fired.bounce_count == 0 and is_equal_approx(bearer.health, health), "a Ricochet round stops on the shield without bouncing")
	# An explosive shell bursts on the shield and its blast reaches the bearer behind it.
	var explosive_stats := _stats({"ammo": Items.make(&"explosive_rounds")})
	game.projectiles.fire_player_round(game.player.get_rid(), _eye(game), (bearer.center() - _eye(game)).normalized(),
		explosive_stats, _shot(game), ProjectilePool.PROFILES["shell"])
	await physics_frames(20)
	var splash := WeaponStats.blast_damage(explosive_stats, 6.0)
	check(bearer.health < health and absf((health - bearer.health) - splash) < splash * 0.05,
		"an explosive shell's blast reaches around the shield (%.1f, blast %.1f)" % [health - bearer.health, splash])
	# Flanking: a ray from the side hits the bearer.
	health = bearer.health
	var side := bearer.global_position + bearer.global_basis.x * 4.0 + Vector3.UP * 0.9
	result = _ray(game, side, bearer.center(), stats, _shot(game))
	check(result.hits.size() == 1 and bearer.health < health, "a shot from the side hits the bearer")
	# The shield drops to attack: walk up to the player and the window opens during the swing.
	behind.set_physics_process(true)
	behind.dismiss()
	bearer.set_physics_process(true)
	bearer.global_position = game.player.global_position - game.player.global_basis.z * 1.5
	var lowered := false
	var elapsed := 0.0
	while elapsed < 2.0 and not lowered:
		await physics_frames(1)
		elapsed += 1.0 / Engine.physics_ticks_per_second
		lowered = bearer.phase == ShieldBearer.Phase.WINDUP and not bearer.shield_up
	check(lowered, "the shield is down while the bearer winds up a swing")
	health = bearer.health
	result = _ray(game, _eye(game), bearer.center(), stats, _shot(game))
	check(result.hits.size() == 1 and bearer.health < health, "a shot from the front lands while the shield is down")
	elapsed = 0.0
	while elapsed < 4.0 and not bearer.shield_up:
		await physics_frames(1)
		elapsed += 1.0 / Engine.physics_ticks_per_second
	check(bearer.shield_up, "the shield comes back up after the swing")
	bearer.dismiss()
	check(bearer.get_node("Shield").collision_layer == 0, "a dead bearer's shield stops blocking")
	await _cleanup(game)


# ------------------------------------------------------------------ explosive

func _test_explosive(game: Node) -> void:
	var player: Player = game.player
	var right := (-player.global_basis.z).cross(Vector3.UP).normalized()
	var target := spawn_in_front(game, 8.0)
	var beside := spawn_in_front(game, 8.0, "res://data/enemies/chaser.tres", "res://scenes/enemies/chaser.tscn", 1.6)
	var far := spawn_in_front(game, 8.0, "res://data/enemies/chaser.tres", "res://scenes/enemies/chaser.tscn", -6.0)
	await seconds(Enemy.SPAWN_TIME + 0.1)
	for enemy in [target, beside, far]:
		_freeze(enemy, player.global_position)
		enemy.health = 1000.0
	var stats := _stats({"ammo": Items.make(&"explosive_rounds")})
	check(right.length() > 0.5 and stats.blast_radius() > 2.0, "explosive rounds carry a blast radius (%.1f m)" % stats.blast_radius())
	var shot := _shot(game)
	game.projectiles.fire_player_round(player.get_rid(), _eye(game), (target.center() - _eye(game)).normalized(),
		stats, shot, ProjectilePool.PROFILES["shell"])
	await physics_frames(25)
	var splash := WeaponStats.blast_damage(stats, 7.6)
	var direct := stats.damage * WeaponStats.EXPLOSIVE_DIRECT_SHARE
	check(absf((1000.0 - target.health) - (direct + splash)) < (direct + splash) * 0.05,
		"the struck enemy takes the direct share and the blast (%.1f of %.1f)" % [1000.0 - target.health, direct + splash])
	check(absf((1000.0 - beside.health) - splash) < splash * 0.05, "an enemy beside it takes the blast (%.1f)" % (1000.0 - beside.health))
	check(is_equal_approx(far.health, 1000.0), "an enemy outside the radius is untouched")
	check(shot.hits == 3 and shot.crits == 0, "the blast counts its hits and never crits (%d hits)" % shot.hits)
	check(game.get_node("FxPool")._blasts.size() <= FxPool.MAX_BLASTS, "the blast effect comes from its pool")
	await _cleanup(game)


# ------------------------------------------------------------------ dangerous combinations

## Splitter plus Arcing: every ray crits and may chain, but an enemy is chained to once per shot.
func _test_splitter_chain(game: Node) -> void:
	var splitter := Items.make(&"splitter", Items.Rarity.UNCOMMON, [{"id": "arcing", "roll": 1.0}])
	var stats := _stats({"muzzle": splitter})
	stats.crit_chance = 1.0
	var rays := int(stats.behaviours["ray_count"])
	var target := spawn_in_front(game, 6.0)
	var left := spawn_in_front(game, 6.0, "res://data/enemies/chaser.tres", "res://scenes/enemies/chaser.tscn", 2.0)
	var right := spawn_in_front(game, 6.0, "res://data/enemies/chaser.tres", "res://scenes/enemies/chaser.tscn", -2.0)
	await seconds(Enemy.SPAWN_TIME + 0.1)
	for enemy in [target, left, right]:
		_freeze(enemy, game.player.global_position)
		enemy.health = 1000.0
	var counts := _count_hits([target, left, right])
	var shot := _shot(game)
	shot.chain_chance = float(stats.extra.get(WeaponStats.CHAIN_ON_CRIT_KEY, {}).get("percent", 0.0))
	check(rays == 3 and shot.chain_chance > 0.0, "the Splitter with Arcing fires %d rays that can chain" % rays)
	shot.chain_chance = 1.0
	for i in rays:
		_ray(game, _eye(game), target.center(), stats, shot)
	check(counts[target] == rays and counts[left] == 1 and counts[right] == 1 and shot.chained.size() == 2,
		"three crits on one enemy chain once to each neighbour and never twice (%d, %d, %d)" % [counts[target], counts[left], counts[right]])
	check(shot.hits == rays, "chained hits are not direct hits and do not proc")
	# The plan names Splitter plus Shock ammo: Shock's arcs share the shot's once-per-robot list.
	for enemy in counts:
		counts[enemy] = 0
	var shock := _stats({"muzzle": Items.make(&"splitter"), "ammo": Items.make(&"shock")})
	var shock_shot := _shot(game)
	for i in rays:
		_ray(game, _eye(game), target.center(), shock, shock_shot)
	check(counts[target] == rays and counts[left] <= 1 and counts[right] <= 1 and counts[left] + counts[right] >= 1,
		"three Shock rays on one enemy arc at most once into each neighbour (%d, %d, %d)" % [counts[target], counts[left], counts[right]])
	_stop_counting(counts)
	await _cleanup(game)


## Ricochet plus Penetrator: a round that bounces forgets whom it pierced, so it can strike the same
## enemies on the way back, but its pierce is spent per enemy and the pipeline caps the total.
func _test_ricochet_penetrator(game: Node) -> void:
	var cover: Node3D = game.arena.get_node("NavigationRegion3D/CoverNorth")
	var floor_point := Vector3(cover.global_position.x, game.player.global_position.y, cover.global_position.z)
	var line: Array[Enemy] = []
	for gap in [3.0, 5.0]:
		line.append(game.wave_runner.spawn_at(floor_point + Vector3(0.0, 0.0, gap), load("res://data/enemies/chaser.tres"), load("res://scenes/enemies/chaser.tscn")))
	await seconds(Enemy.SPAWN_TIME + 0.1)
	for enemy in line:
		_freeze(enemy, floor_point + Vector3(0.0, 0.0, 20.0))
		enemy.health = 1000.0
	var barrel := Items.make(&"penetrator_barrel", Items.Rarity.UNCOMMON, [{"id": "piercing", "roll": 1.0}])
	var stats := _stats({"barrel": barrel, "ammo": Items.make(&"ricochet_rounds")})
	stats.behaviours["pierce"] = WeaponStats.PIERCE_CAP
	var shot := _shot(game)
	var origin := floor_point + Vector3(0.0, cover.global_position.y - floor_point.y, 8.0)
	var counts := _count_hits(line)
	var fired: ProjectilePool.Projectile = game.projectiles.fire_player_round(game.player.get_rid(), origin, Vector3.FORWARD,
		stats, shot, ProjectilePool.PROFILES["ricochet"])
	var bounced := false
	for i in 200:
		await physics_frames(1)
		bounced = bounced or fired.bounce_count > 0
		if not fired.active:
			break
	_stop_counting(counts)
	check(bounced and counts[line[0]] >= 2 and counts[line[1]] >= 2, "a Ricochet plus Penetrator round strikes the line again after bouncing off the cover")
	check(shot.hits <= stats.pierce() + 1 and shot.hits <= ShotPipeline.MAX_ENEMY_HITS_PER_RAY,
		"one round lands at most pierce plus one hits, inside the pipeline cap of %d (%d hits)" % [ShotPipeline.MAX_ENEMY_HITS_PER_RAY, shot.hits])
	await _cleanup(game)


# ------------------------------------------------------------------ the Foreman

func _test_foreman(game: Node) -> void:
	var player: Player = game.player
	var runner: WaveRunner = game.wave_runner
	game.state = game.State.COMBAT
	game.current_wave = 10
	var foreman: Foreman = spawn_in_front(game, 12.0, FOREMAN, FOREMAN_SCENE)
	check(foreman.definition.is_boss and game.hud.is_boss_bar_visible(), "the Foreman spawns as a boss with its bar")
	await seconds(Enemy.SPAWN_TIME + 0.1)
	foreman._volley_cooldown = 99.0
	foreman._pool_cooldown = 99.0
	foreman._summon_cooldown = 0.0
	var saw_telegraph := false
	var elapsed := 0.0
	while runner.summon_count() == 0 and elapsed < 4.0:
		await physics_frames(1)
		elapsed += 1.0 / Engine.physics_ticks_per_second
		saw_telegraph = saw_telegraph or foreman.phase == Foreman.Phase.SUMMON
	check(saw_telegraph and runner.summon_count() == Foreman.SUMMON_COUNT, "the Foreman telegraphs, then calls in %d drones" % runner.summon_count())
	check(is_equal_approx(runner.active_weight(), foreman.definition.counts_as), "summoned drones sit outside the wave's alive cap")
	foreman._summon_cooldown = 0.0
	foreman._volley_cooldown = 99.0
	elapsed = 0.0
	while runner.summon_count() < foreman.definition.max_summons and elapsed < 4.0:
		await physics_frames(1)
		elapsed += 1.0 / Engine.physics_ticks_per_second
	foreman._summon_cooldown = 0.0
	await seconds(Foreman.SUMMON_TELEGRAPH + Foreman.RECOVER_TIME + 0.4)
	check(runner.summon_count() == foreman.definition.max_summons, "a third summon stays at the cap of %d" % foreman.definition.max_summons)
	foreman._summon_cooldown = 99.0
	foreman._volley_cooldown = 99.0
	for enemy in runner.living_enemies():
		if enemy.summoned:
			enemy.set_physics_process(false) # drones would otherwise sting the player during the pool checks
	# A molten pool warns, then burns a grounded player and spares one in the air.
	player.revive(game.arena.get_player_start())
	await physics_frames(2)
	var health := player.health
	foreman.lay_pool(player.global_position)
	await seconds(Foreman.POOL_WARNING * 0.5)
	check(is_equal_approx(player.health, health), "the warning ring does no damage")
	await seconds(Foreman.POOL_WARNING * 0.5 + 0.5)
	var burned := health - player.health
	check(burned > 0.0 and burned <= Foreman.POOL_DAMAGE_PER_SECOND * 0.75, "the molten pool burns a grounded player (%.1f in about half a second)" % burned)
	health = player.health
	player.global_position.y += 3.0
	player.velocity = Vector3.ZERO
	await physics_frames(4)
	check(is_equal_approx(player.health, health), "a player in the air over the pool is not burned")
	for enemy in runner.living_enemies():
		enemy.set_physics_process(true)
	# Killing the Foreman pays its credits, drops an Epic on the first clear and dismisses the adds.
	var credits := Progression.credits
	var inventory_before := Progression.inventory().size()
	var reward := maxi(roundi(foreman.definition.credit_reward * runner.scale), 1)
	foreman.take_hit(100000.0, foreman.global_position, Vector3.FORWARD)
	await physics_frames(3)
	check(Progression.credits == credits + reward, "the Foreman pays its credits and its dismissed adds pay nothing")
	check(runner.summon_count() == 0, "the adds fall with the Foreman")
	check(Progression.inventory().size() == inventory_before + 1 and int(Progression.inventory().back()["rarity"]) == Items.Rarity.EPIC,
		"the Foreman's first-clear drop is an Epic")
	var pools_hidden := true
	for pool in foreman.pools:
		pools_hidden = pools_hidden and not pool.node.visible
	check(pools_hidden, "its pools go out with it")
	Progression.data["inventory"].clear()
	await _cleanup(game)
