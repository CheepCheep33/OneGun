extends TestCase
## Milestone 3 combat checks in the running game: fire modes, hitscan pierce, the projectile pool
## (tunnelling, pierce, the cap), the shooter's bolts, swarm drones, the Warden's specials and boss
## bar, loot drops on the floor, and the wave data.

const SHOOTER := "res://data/enemies/shooter.tres"
const SHOOTER_SCENE := "res://scenes/enemies/shooter.tscn"
const DRONE := "res://data/enemies/swarm_drone.tres"
const DRONE_SCENE := "res://scenes/enemies/swarm_drone.tscn"
const WARDEN := "res://data/enemies/warden.tres"
const WARDEN_SCENE := "res://scenes/enemies/warden.tscn"


func run_unit() -> void:
	_test_wave_data()
	_test_shooter_aim()


func run_scene(game: Node) -> void:
	game.open_bench()
	await physics_frames(2)
	Progression.reset()
	game.start_wave(1)
	await physics_frames(3)
	game.wave_runner.stop()
	await _test_fire_modes(game)
	await _test_hitscan_pierce(game)
	await _test_projectile_tunnelling(game)
	await _test_player_projectiles(game)
	await _test_shooter(game)
	await _test_shooter_range(game)
	await _test_swarm_drone(game)
	await _test_warden(game)
	await _test_floor_loot(game)
	game.open_bench()
	await physics_frames(2)
	Progression.reset()


func _test_wave_data() -> void:
	var waves := WaveRunner.all_waves()
	check(waves.size() == 10, "ten authored waves load")
	var boss: WaveDefinition = waves[4]
	var has_warden := false
	for group in boss.groups:
		has_warden = has_warden or (group.definition and group.definition.is_boss)
	check(boss.is_boss_wave and has_warden, "wave 5 is the Warden's boss wave")
	var first_shooter := 0
	var first_drone := 0
	for wave in waves:
		for group in wave.groups:
			if group.definition and group.definition.ranged and first_shooter == 0:
				first_shooter = wave.number
			if group.definition and group.definition.flying and first_drone == 0:
				first_drone = wave.number
	check(first_shooter == 4 and first_drone == 7, "the shooter arrives in wave 4 and swarm drones in wave 7")
	var scenes_match := true
	for wave in waves:
		for group in wave.groups:
			var enemy: Node = group.enemy_scene.instantiate()
			var definition: EnemyDefinition = group.definition
			# Runners share the chaser scene, so match the kind of enemy rather than the id.
			var fits := enemy is Enemy and (enemy is Shooter) == definition.ranged \
				and (enemy is SwarmDrone) == definition.flying and (enemy is Warden) == definition.is_boss
			scenes_match = scenes_match and fits
			enemy.free()
	check(scenes_match, "every spawn group's scene matches the kind of its definition")
	var drone: EnemyDefinition = load(DRONE)
	check(is_equal_approx(drone.counts_as, 0.5) and drone.flying and is_equal_approx(drone.loot_weight, 0.5), "drones count as half, fly and drop half as often")
	var income := 0
	for wave in waves:
		income += roundi(wave.kill_income() * pow(Progression.TIER_STEP, Progression.tier_of_wave(wave.number))) \
			+ wave.completion_bonus * (2 if wave.is_boss_wave else 1)
	check(income > 2000 and income < 3500, "ten waves pay a first-run total in the planned band (%d credits)" % income)


## The shooter's aim error grows with distance (plan: worse accuracy the further away).
func _test_shooter_aim() -> void:
	var definition: EnemyDefinition = load(SHOOTER)
	check(definition.max_fire_range > definition.preferred_range + Shooter.RANGE_SLACK and definition.spread_far_degrees > definition.spread_near_degrees,
		"the shooter fires from beyond where it holds (%.0f m, holds at %.0f) and aims worse out there (%.1f to %.1f degrees)" % [definition.max_fire_range, definition.preferred_range, definition.spread_near_degrees, definition.spread_far_degrees])
	var near := Shooter.spread_degrees_at(definition, definition.preferred_range)
	var closer := Shooter.spread_degrees_at(definition, 3.0)
	var far := Shooter.spread_degrees_at(definition, definition.max_fire_range)
	var beyond := Shooter.spread_degrees_at(definition, definition.max_fire_range + 10.0)
	var middle := Shooter.spread_degrees_at(definition, (definition.preferred_range + definition.max_fire_range) * 0.5)
	check(is_equal_approx(near, definition.spread_near_degrees) and is_equal_approx(closer, definition.spread_near_degrees)
		and is_equal_approx(far, definition.spread_far_degrees) and is_equal_approx(beyond, definition.spread_far_degrees)
		and is_equal_approx(middle, (definition.spread_near_degrees + definition.spread_far_degrees) * 0.5),
		"aim error is the near value up to the preferred range, the far value at maximum range and linear between (%.1f, %.1f, %.1f)" % [near, middle, far])
	var generator := rng(11)
	var forward := Vector3(0.3, -0.1, -1.0).normalized()
	check(Shooter.scatter(forward, 0.0, generator).is_equal_approx(forward), "zero aim error leaves the direction alone")
	var inside := true
	var mean_near := 0.0
	var mean_far := 0.0
	for i in 300:
		var a := Shooter.scatter(forward, 1.5, generator)
		var b := Shooter.scatter(forward, 8.0, generator)
		inside = inside and rad_to_deg(a.angle_to(forward)) <= 1.5 + 0.01 and rad_to_deg(b.angle_to(forward)) <= 8.0 + 0.01
		inside = inside and is_equal_approx(a.length(), 1.0) and is_equal_approx(b.length(), 1.0)
		mean_near += rad_to_deg(a.angle_to(forward)) / 300.0
		mean_far += rad_to_deg(b.angle_to(forward)) / 300.0
	check(inside and mean_far > mean_near * 3.0 and mean_near > 0.5,
		"scattered bolts stay inside their cone and spread further at long range (mean %.2f at 1.5 degrees, %.2f at 8)" % [mean_near, mean_far])
	var straight_up := Shooter.scatter(Vector3.UP, 5.0, generator)
	check(is_equal_approx(straight_up.length(), 1.0) and rad_to_deg(straight_up.angle_to(Vector3.UP)) <= 5.01, "scatter copes with a vertical aim")


# ------------------------------------------------------------------ fire modes

func _equip_fresh(game: Node, base_id: StringName, rarity := Items.Rarity.COMMON, affixes: Array = []) -> void:
	for slot in Items.SLOT_IDS:
		if Progression.equipped_in(slot) != null:
			Progression.unequip(slot)
	var item := Items.make(base_id, rarity, affixes)
	Progression.add_item(item, "test")
	Progression.equip(int(item["uid"]))
	game.player.pistol.apply_build(Progression.build_stats(), Progression.equipped())


func _clear_build(game: Node) -> void:
	for slot in Items.SLOT_IDS:
		if Progression.equipped_in(slot) != null:
			Progression.unequip(slot)
	Progression.data["inventory"].clear()
	Progression.data["overflow"].clear()
	game.player.pistol.apply_build(Progression.build_stats(), Progression.equipped())


func _test_fire_modes(game: Node) -> void:
	var pistol: Pistol = game.player.pistol
	# Burst: one pull fires three rounds a few frames apart, then pauses to hold the sustained rate.
	Progression.record_wave_cleared(10, 0, 1.0) # Burst's gate (temporary stand-in for the Foundry).
	_equip_fresh(game, &"burst")
	check(pistol.stats.fire_mode() == "burst" and pistol.ammo == pistol.stats.magazine_size, "burst receiver is fitted")
	pistol.request_fire()
	await physics_frames(2)
	check(pistol.ammo == pistol.stats.magazine_size - 1, "the first round of a burst leaves immediately")
	await seconds(Pistol.BURST_INTERVAL * 2 + 0.05)
	check(pistol.ammo == pistol.stats.magazine_size - 3, "a burst fires three rounds (%d left)" % pistol.ammo)
	pistol.request_fire()
	await physics_frames(2)
	check(pistol.ammo == pistol.stats.magazine_size - 3, "a second pull during the pause after a burst waits")
	await seconds(3.0 / pistol.stats.fire_rate)
	check(pistol.ammo == pistol.stats.magazine_size - 6, "the buffered pull fires the next burst once the pause ends (%d left)" % pistol.ammo)
	pistol.release_fire()
	# Automatic: holding the trigger keeps firing at the build's rate; releasing stops it.
	Progression.record_wave_cleared(5, 0, 1.0)
	_equip_fresh(game, &"automatic")
	check(pistol.stats.fire_mode() == "auto", "automatic receiver is fitted")
	var before := pistol.ammo
	pistol.request_fire()
	await seconds(1.0)
	var fired := before - pistol.ammo
	check(fired >= floori(pistol.stats.fire_rate) and fired <= ceili(pistol.stats.fire_rate) + 1, "holding the trigger fires at the build's rate (%d rounds in 1 s at %.2f/s)" % [fired, pistol.stats.fire_rate])
	pistol.release_fire()
	await seconds(0.5)
	check(before - pistol.ammo == fired, "releasing the trigger stops automatic fire")
	await seconds(pistol.stats.reload_time + 0.1)
	# Semi-auto: holding does nothing beyond the one buffered shot.
	_clear_build(game)
	before = pistol.ammo
	pistol.request_fire()
	await seconds(1.0)
	check(before - pistol.ammo == 1, "semi-auto fires once per pull however long the trigger is held")
	pistol.release_fire()
	Progression.data["waves"]["first_clears"].clear()
	Progression.data["waves"]["highest_cleared"] = 0


# ------------------------------------------------------------------ hitscan pierce

func _test_hitscan_pierce(game: Node) -> void:
	var pistol: Pistol = game.player.pistol
	_equip_fresh(game, &"penetrator_barrel")
	check(pistol.stats.pierce() == 2, "penetrator barrel pierces two")
	var line: Array[Enemy] = []
	for distance in [4.0, 6.5, 9.0, 11.5]:
		line.append(spawn_in_front(game, distance))
	await seconds(Enemy.SPAWN_TIME + 0.1)
	var hits := [0, 0]
	var connection := func(killed: bool) -> void: hits[1 if killed else 0] += 1
	pistol.hit_landed.connect(connection)
	pistol.request_fire()
	await physics_frames(2)
	pistol.hit_landed.disconnect(connection)
	var damage := pistol.stats.damage
	var full := line[0].definition.max_health
	check(is_equal_approx(line[0].health, full - damage), "the first enemy takes full damage")
	check(is_equal_approx(line[1].health, full - damage * 0.75), "the first pierced enemy takes 25 percent less (%.1f)" % (full - line[1].health))
	check(is_equal_approx(line[2].health, full - damage * 0.75 * 0.75), "the second pierced enemy takes 25 percent less again")
	check(is_equal_approx(line[3].health, full), "pierce 2 stops at the third enemy")
	check(hits[0] == 3, "one shot reports three hits (%d)" % hits[0])
	game.wave_runner.clear_enemies()
	await physics_frames(2)
	# The world stops rays whatever the pierce.
	var player: Player = game.player
	var forward := -player.global_basis.z
	forward.y = 0.0
	var cover: Node3D = game.arena.get_node("NavigationRegion3D/CrateA")
	player.global_position = cover.global_position + Vector3(0.0, -1.0, 4.0)
	player.look_at(Vector3(cover.global_position.x, player.global_position.y, cover.global_position.z), Vector3.UP)
	var behind: Enemy = game.wave_runner.spawn_at(cover.global_position + Vector3(0.0, -1.0, -3.0), load("res://data/enemies/chaser.tres"), load("res://scenes/enemies/chaser.tscn"))
	await seconds(Enemy.SPAWN_TIME + 0.1)
	pistol.request_fire()
	await physics_frames(2)
	check(is_equal_approx(behind.health, behind.max_health), "a crate stops a piercing round")
	game.wave_runner.clear_enemies()
	game.player.revive(game.arena.get_player_start())
	_clear_build(game)
	await physics_frames(2)


# ------------------------------------------------------------------ projectiles

func _test_projectile_tunnelling(game: Node) -> void:
	var pool: ProjectilePool = game.projectiles
	var player: Player = game.player
	player.revive(game.arena.get_player_start())
	await physics_frames(2)
	var health := player.health
	# A very fast bolt crosses more than a wall's thickness per tick; the swept ray must still stop it.
	var cover: Node3D = game.arena.get_node("NavigationRegion3D/CoverNorth") # 1 m thick, 1.5 m tall at z = -12
	var origin := cover.global_position + Vector3(0.0, -0.1, -4.0)
	var target := player.global_position + Vector3.UP * 0.5
	var direction := (target - origin).normalized()
	pool.fire_enemy_bolt(null, origin, direction * 600.0, 25.0, Color.RED, 2.0)
	check(pool.live_count() == 1, "a bolt is live after firing")
	await physics_frames(3)
	check(pool.live_count() == 0 and is_equal_approx(player.health, health), "a 600 m/s bolt stops at a 1 m wall instead of tunnelling (health %.0f)" % player.health)
	# The same bolt with a clear line hits the player.
	var clear_origin := player.global_position + Vector3(0.0, 1.0, -6.0) + (-player.global_basis.z) * 0.0
	pool.fire_enemy_bolt(null, clear_origin, (player.global_position + Vector3.UP * 1.0 - clear_origin).normalized() * 600.0, 25.0, Color.RED, 2.0)
	await physics_frames(3)
	check(is_equal_approx(player.health, health - 25.0), "a bolt with a clear line damages the player (%.0f)" % player.health)
	# The cap: the oldest enemy bolts expire first.
	for i in 250:
		pool.fire_enemy_bolt(null, Vector3(0.0, 40.0 + i * 0.01, 0.0), Vector3(0.0, 1.0, 0.0), 1.0, Color.RED, 30.0)
	check(pool.live_count() == ProjectilePool.MAX_LIVE, "the pool never exceeds %d live projectiles (%d)" % [ProjectilePool.MAX_LIVE, pool.live_count()])
	pool.clear_all()
	check(pool.live_count() == 0, "clear_all retires everything")
	player.revive(game.arena.get_player_start())
	await physics_frames(2)


func _test_player_projectiles(game: Node) -> void:
	# A test ammo base that fires simulated Ricochet rounds through the shared pool.
	var ammo := AttachmentDefinition.new()
	ammo.id = &"test_ricochet_ammo"
	ammo.display_name = "Test ricochet"
	ammo.slot = &"ammo"
	ammo.behaviours = {"projectile": "ricochet", "bounces": 2}
	Items.register_attachment(ammo)
	var pistol: Pistol = game.player.pistol
	var pool: ProjectilePool = game.projectiles
	var penetrator := Items.make(&"penetrator_barrel")
	var ammo_item := Items.make(&"test_ricochet_ammo")
	pistol.apply_build(WeaponStats.build(Progression.PISTOL_BASE, Progression.core_levels(), {"barrel": penetrator, "ammo": ammo_item}), {"barrel": penetrator, "ammo": ammo_item})
	check(pistol.stats.behaviours["projectile"] == "ricochet" and pistol.stats.pierce() == 2, "test ammo makes the pistol fire simulated rounds")
	var line: Array[Enemy] = [spawn_in_front(game, 5.0), spawn_in_front(game, 8.0)]
	await seconds(Enemy.SPAWN_TIME + 0.1)
	var hits := [0]
	var connection := func(_killed: bool) -> void: hits[0] += 1
	pistol.hit_landed.connect(connection)
	await seconds(0.3) # let the previous test's shot cooldown end so the pull fires at once
	pistol.request_fire()
	await physics_frames(2) # the pistol fires in the tick after the first frame signal; 60 m/s is 1 m a tick
	check(pool.live_count() == 1 and is_equal_approx(line[0].health, line[0].max_health), "a simulated round is in flight and has not landed yet")
	await physics_frames(12)
	pistol.hit_landed.disconnect(connection)
	var damage := pistol.stats.damage
	check(is_equal_approx(line[0].health, line[0].max_health - damage), "the simulated round damages the first enemy with the build's numbers")
	check(is_equal_approx(line[1].health, line[1].max_health - damage * 0.75), "the simulated round pierces with the same falloff as hitscan")
	check(hits[0] == 2, "projectile hits report hit markers (%d)" % hits[0])
	game.wave_runner.clear_enemies()
	# Fired at the floor at an angle, a ricochet round bounces instead of stopping.
	var player: Player = game.player
	player.rotation = Vector3.ZERO
	player._pitch = -0.6
	player._apply_pitch()
	pistol.request_fire()
	await physics_frames(1)
	var bounced := false
	for i in 20:
		await physics_frames(1)
		for projectile in pool._live:
			bounced = bounced or projectile.bounce_count > 0
	check(bounced, "a ricochet round bounces off the floor")
	pool.clear_all()
	Items.unregister(&"test_ricochet_ammo")
	player.rotation = Vector3.ZERO
	player.revive(game.arena.get_player_start())
	pistol.apply_build(Progression.build_stats(), Progression.equipped())
	await physics_frames(2)


# ------------------------------------------------------------------ enemies

func _test_shooter(game: Node) -> void:
	var player: Player = game.player
	var pool: ProjectilePool = game.projectiles
	player.revive(game.arena.get_player_start())
	var shooter := spawn_in_front(game, 10.0, SHOOTER, SHOOTER_SCENE)
	check(shooter is Shooter and shooter.definition.ranged, "a shooter spawns from its scene and definition")
	var health := player.health
	var fired_at := -1.0
	var elapsed := 0.0
	while pool.live_count() == 0 and elapsed < 6.0:
		await physics_frames(1)
		elapsed += 1.0 / Engine.physics_ticks_per_second
	check(pool.live_count() > 0, "the shooter fires a bolt within a few seconds (%.1f s)" % elapsed)
	check(is_equal_approx(player.health, health), "the bolt has travel time: no damage the instant it is fired")
	fired_at = elapsed
	while is_equal_approx(player.health, health) and elapsed < fired_at + 3.0:
		await physics_frames(1)
		elapsed += 1.0 / Engine.physics_ticks_per_second
	check(is_equal_approx(player.health, health - shooter.definition.attack_damage), "the bolt reaches the player and deals the shooter's damage (%.1f s of flight)" % (elapsed - fired_at))
	# A shooter keeps its distance instead of walking into melee.
	await seconds(1.5)
	check(shooter.is_alive and shooter.global_position.distance_to(player.global_position) > shooter.definition.retreat_range * 0.8, "the shooter holds range (%.1f m)" % shooter.global_position.distance_to(player.global_position))
	game.wave_runner.clear_enemies()
	pool.clear_all()
	player.revive(game.arena.get_player_start())
	await physics_frames(2)


## A shooter with line of sight opens fire from beyond its preferred range; without it, it never
## fires. Fixed geometry: the shooter cannot move (speed 0) and stands behind CrateB (9, 5) from
## the player's start (0, 12); the player then steps to (0, 7), where the crate no longer covers.
func _test_shooter_range(game: Node) -> void:
	var player: Player = game.player
	var pool: ProjectilePool = game.projectiles
	player.revive(game.arena.get_player_start())
	var definition: EnemyDefinition = load(SHOOTER).duplicate()
	definition.move_speed = 0.0
	definition.spread_near_degrees = 0.0
	var standing := Vector3(13.95, 0.0, 1.15)
	var shooter: Shooter = game.wave_runner.spawn_at(standing, definition, load(SHOOTER_SCENE))
	shooter._rng.seed = 7
	var blocked_distance := shooter.global_position.distance_to(player.global_position)
	await seconds(Enemy.SPAWN_TIME + definition.attack_cooldown * 0.5 + definition.attack_windup + 0.4)
	check(blocked_distance < definition.max_fire_range and not shooter.has_line_of_sight() and pool.live_count() == 0 and shooter.phase == Shooter.Phase.APPROACH,
		"a shooter in range but without line of sight does not fire (%.1f m, crate between)" % blocked_distance)
	player.global_position = Vector3(0.0, player.global_position.y, 7.0)
	await physics_frames(2)
	var distance := shooter.global_position.distance_to(player.global_position)
	var exact := (player.global_position + Vector3.UP - shooter._eye.global_position).normalized()
	var elapsed := 0.0
	while pool.live_count() == 0 and elapsed < 3.0:
		await physics_frames(1)
		elapsed += 1.0 / Engine.physics_ticks_per_second
	check(shooter.has_line_of_sight() and pool.live_count() == 1 and distance > definition.preferred_range + Shooter.RANGE_SLACK and distance < definition.max_fire_range,
		"once it can see the player it fires from beyond its preferred range without walking in (%.1f m, %.1f s)" % [distance, elapsed])
	if pool.live_count() == 1:
		var bolt: ProjectilePool.Projectile = pool._live[0]
		var error := rad_to_deg(bolt.velocity.normalized().angle_to(exact))
		var allowed := Shooter.spread_degrees_at(definition, distance)
		check(error > 0.0 and error <= allowed + 0.01 and allowed > 3.0,
			"the long shot carries the aim error of its distance (%.2f of up to %.1f degrees)" % [error, allowed])
	game.wave_runner.clear_enemies()
	pool.clear_all()
	player.revive(game.arena.get_player_start())
	await physics_frames(2)


func _test_swarm_drone(game: Node) -> void:
	var player: Player = game.player
	var runner: WaveRunner = game.wave_runner
	var drones: Array[Enemy] = []
	for i in 4:
		drones.append(spawn_in_front(game, 8.0 + i, DRONE, DRONE_SCENE, -1.5 + i))
	check(is_equal_approx(runner.active_weight(), 2.0) and runner.active_count() == 4, "four drones count as two toward the alive cap")
	var health := player.health
	var elapsed := 0.0
	while is_equal_approx(player.health, health) and elapsed < 6.0:
		await physics_frames(1)
		elapsed += 1.0 / Engine.physics_ticks_per_second
	check(player.health < health, "drones close in and zap the player (%.1f s)" % elapsed)
	var hovering := true
	for drone in drones:
		if is_instance_valid(drone) and drone.is_alive:
			hovering = hovering and absf(drone.global_position.y) < 0.5 and drone.get_node("Visual").position.y > 1.4
	check(hovering, "drones hover at head height while pathing along the floor")
	var drone := drones[0]
	check(drone.take_hit(12.0, drone.global_position, Vector3.FORWARD), "a drone dies to a single 12-damage hit")
	await physics_frames(2)
	runner.clear_enemies()
	player.revive(game.arena.get_player_start())
	await physics_frames(2)
	# The alive cap counts weights: eight drones fit under a cap of four.
	var wave := WaveDefinition.new()
	wave.number = 1
	wave.max_alive = 4
	var group := SpawnGroup.new()
	group.enemy_scene = load(DRONE_SCENE)
	group.definition = load(DRONE)
	group.count = 12
	group.interval = 0.02
	wave.groups = [group]
	var occupied := runner.occupied_radius
	runner.occupied_radius = 0.0 # fresh spawns would otherwise block their own point for a while
	runner.start(wave, 1.0)
	await seconds(0.8)
	runner.stop()
	runner.occupied_radius = occupied
	check(runner.active_count() == 8 and is_equal_approx(runner.active_weight(), 4.0), "the alive cap admits twice as many drones (%d alive)" % runner.active_count())
	runner.clear_enemies()
	await physics_frames(2)


func _test_warden(game: Node) -> void:
	var player: Player = game.player
	var hud: Hud = game.hud
	player.revive(game.arena.get_player_start())
	game.state = game.State.COMBAT
	game.current_wave = 5
	var warden := spawn_in_front(game, 11.0, WARDEN, WARDEN_SCENE)
	check(warden is Warden and warden.definition.is_boss and is_equal_approx(warden.max_health, 450.0), "the Warden spawns as a boss with 450 health")
	check(hud.is_boss_bar_visible(), "spawning a boss shows the boss bar")
	await seconds(Enemy.SPAWN_TIME + 0.1)
	# The charge: telegraph, then a rush that reaches and hits the player.
	warden._charge_cooldown = 0.0
	warden._slam_cooldown = 99.0
	var health := player.health
	var saw_telegraph := false
	var saw_charge := false
	var elapsed := 0.0
	while is_equal_approx(player.health, health) and elapsed < 8.0:
		await physics_frames(1)
		elapsed += 1.0 / Engine.physics_ticks_per_second
		saw_telegraph = saw_telegraph or warden.phase == Warden.Phase.CHARGE_TELEGRAPH
		saw_charge = saw_charge or warden.phase == Warden.Phase.CHARGING
	check(saw_telegraph and saw_charge, "the Warden telegraphs and then charges")
	check(is_equal_approx(player.health, health - Warden.CHARGE_DAMAGE), "the charge hits for its own damage (%.0f)" % (health - player.health))
	# The slam: ring telegraph, damage to a grounded player, none to one in the air.
	warden._enter(Warden.Phase.CHASE)
	warden._charge_cooldown = 99.0
	warden._slam_cooldown = 0.0
	warden.global_position = player.global_position + Vector3(3.0, 0.0, 0.0)
	health = player.health
	var saw_ring := false
	elapsed = 0.0
	while is_equal_approx(player.health, health) and elapsed < 6.0:
		await physics_frames(1)
		elapsed += 1.0 / Engine.physics_ticks_per_second
		saw_ring = saw_ring or (warden.phase == Warden.Phase.SLAM_TELEGRAPH and warden.get_node("Ring").visible)
	check(saw_ring, "the slam shows its ring while winding up")
	check(is_equal_approx(player.health, health - Warden.SLAM_DAMAGE), "the slam hits a grounded player for its damage (%.0f)" % (health - player.health))
	health = player.health
	player.global_position.y = 3.0
	player.velocity = Vector3.ZERO
	warden._slam()
	check(is_equal_approx(player.health, health), "a player in the air is not hit by the slam")
	player.revive(game.arena.get_player_start())
	# Killing the boss pays its credits and drops a Rare straight into the inventory.
	var credits := Progression.credits
	var inventory_before := Progression.inventory().size()
	var records: Dictionary = Progression.data["records"].duplicate(true)
	var warden_reward: int = warden.definition.credit_reward
	warden.take_hit(100000.0, warden.global_position, Vector3.FORWARD)
	await physics_frames(3)
	check(Progression.credits == credits + warden_reward, "the Warden pays its credits")
	check(Progression.inventory().size() == inventory_before + 1 and int(Progression.inventory().back()["rarity"]) == Items.Rarity.RARE, "the Warden's drop goes straight into the inventory as a Rare")
	check(not hud.is_boss_bar_visible(), "the boss bar hides when the boss dies")
	check(hud.pickup_note_count() >= 1, "the HUD notes the pickup")
	Progression.data["records"] = records
	Progression.data["inventory"].clear()
	await physics_frames(2)


# ------------------------------------------------------------------ floor loot

func _test_floor_loot(game: Node) -> void:
	var player: Player = game.player
	player.revive(game.arena.get_player_start())
	game.state = game.State.COMBAT
	var forward := -player.global_basis.z
	forward.y = 0.0
	var item := Items.make(&"long_barrel", Items.Rarity.UNCOMMON, [{"id": "sharp", "roll": 0.5}])
	game._spawn_drop(item, player.global_position + forward.normalized() * 4.0)
	await physics_frames(2)
	check(game.drops.get_child_count() == 1 and game.drops.get_child(0) is LootDrop, "a drop appears on the floor")
	var before := Progression.inventory().size()
	Input.action_press("move_forward")
	var elapsed := 0.0
	while game.drops.get_child_count() > 0 and elapsed < 4.0:
		await physics_frames(1)
		elapsed += 1.0 / Engine.physics_ticks_per_second
	Input.action_release("move_forward")
	await physics_frames(2)
	check(game.drops.get_child_count() == 0 and Progression.inventory().size() == before + 1, "walking over a drop picks it up (%.1f s)" % elapsed)
	check(int(Progression.inventory().back()["uid"]) == int(item["uid"]), "the picked-up item is the one that dropped")
	# A cleared wave auto-collects what is left on the floor.
	var far_item := Items.make(&"fast_magazine")
	game._spawn_drop(far_item, player.global_position + forward.normalized() * 15.0)
	var wave := WaveRunner.load_wave(1)
	game.current_wave = 1
	game.wave_runner.start(wave, 1.0)
	game.wave_runner._killed = wave.total_enemies() - 1
	var victim := spawn_in_front(game, 6.0)
	await seconds(Enemy.SPAWN_TIME + 0.1)
	var credits := Progression.credits
	var victim_reward: int = victim.definition.credit_reward
	victim.take_hit(10000.0, victim.global_position, Vector3.FORWARD)
	await physics_frames(3)
	check(game.state == game.State.CLEARED, "killing the last enemy clears the wave")
	check(game.drops.get_child_count() == 0 and Items.find_by_uid(Progression.inventory(), int(far_item["uid"])) >= 0, "a cleared wave collects the loot left on the floor")
	var granted: Dictionary = Progression.inventory().back()
	# At least the two floor items and the grant; the kill itself may roll a drop on top.
	check(Progression.inventory().size() >= before + 3 and int(granted["rarity"]) == Items.Rarity.UNCOMMON and granted["affixes"].size() == 1, "a first clear pays one Uncommon with an affix")
	check(Progression.credits == credits + victim_reward + wave.completion_bonus, "the clear pays kill credits and the bonus")
	check(Items.display_name(granted) in game.hud._banner_detail.text, "the cleared banner names the granted item (%s)" % game.hud._banner_detail.text.replace("\n", " / "))
	await seconds(game.CLEARED_BANNER_TIME + 0.3)
	check(game.state == game.State.BENCH, "the bench opens after the banner")
	# Death loses floor loot but keeps everything collected.
	game.start_wave(1)
	await physics_frames(3)
	game.wave_runner.stop()
	game._spawn_drop(Items.make(&"long_barrel"), player.global_position + forward.normalized() * 10.0)
	var kept := Progression.inventory().size()
	player.take_damage(10000.0)
	await physics_frames(2)
	check(game.state == game.State.DEAD and game.drops.get_child_count() == 0 and Progression.inventory().size() == kept, "death discards floor loot and keeps the inventory")
	game.open_bench()
	await physics_frames(2)
	Progression.reset()
