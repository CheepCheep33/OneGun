extends TestCase
## Milestone 5 roster checks in the running game: the turret (stationary, a locked aim line, one
## heavy bolt, a weak core), the Sentinel (shield arcs stop rays, the low sweep hits a grounded
## player and misses a jumping one), the Core Guardian (four phases by health, a vent between
## phases with the core open only then, its first kill drops a Legendary) and the story cards on a
## boss's first appearance.

const TURRET := "res://data/enemies/turret.tres"
const TURRET_SCENE := "res://scenes/enemies/turret.tscn"
const SENTINEL := "res://data/enemies/sentinel.tres"
const SENTINEL_SCENE := "res://scenes/enemies/sentinel.tscn"
const GUARDIAN := "res://data/enemies/core_guardian.tres"
const GUARDIAN_SCENE := "res://scenes/enemies/core_guardian.tscn"
const RAY_MASK := 1 | 4 | 8


func run_scene(game: Node) -> void:
	game.open_bench()
	await physics_frames(2)
	Progression.reset()
	await start_quiet_wave(game)
	await _test_turret(game)
	await _test_sentinel(game)
	await _test_guardian(game)
	game.open_bench()
	await physics_frames(2)
	Progression.reset()
	await start_quiet_wave(game)


func _cleanup(game: Node) -> void:
	for enemy in game.wave_runner.living_enemies():
		enemy.set_physics_process(true)
	game.wave_runner.clear_enemies()
	game.projectiles.clear_all()
	game.player.revive(game.arena.get_player_start())
	await physics_frames(2)


func _test_turret(game: Node) -> void:
	var player: Player = game.player
	# 8 m keeps the arena's centre block out of the way.
	var turret: Turret = spawn_in_front(game, 8.0, TURRET, TURRET_SCENE)
	turret._cooldown_left = 0.0
	var start := turret.global_position
	await seconds(Enemy.SPAWN_TIME + 0.1)
	check(turret.phase == Turret.Phase.AIM and turret._aim_pivot.visible, "a turret with line of sight starts aiming and shows its aim line")
	await seconds(turret.definition.attack_windup - Turret.LOCK_TIME + 0.05)
	var locked := turret._aim_point
	player.global_position += player.global_basis.x * 3.0
	await physics_frames(3)
	check(turret._aim_point == locked, "the aim line locks before the shot, so a step aside dodges it")
	var bolts: int = game.projectiles.live_count()
	await seconds(Turret.LOCK_TIME + 0.05)
	check(game.projectiles.live_count() == bolts + 1 and not turret._aim_pivot.visible, "after the wind-up it fires one bolt and hides the line")
	check(Vector2(turret.global_position.x - start.x, turret.global_position.z - start.z).length() < 0.2, "the turret never moves")
	check(turret.is_weak_point(turret.to_global(turret.definition.weak_point_offset)) and turret.is_armored(),
		"its core is a weak point and its body is armoured")
	check(turret.definition.scanner_marked and turret.definition.rare_chance > 0.0, "the Scanner marks it and it drops Rares")
	await _cleanup(game)


func _test_sentinel(game: Node) -> void:
	var player: Player = game.player
	var sentinel: Sentinel = spawn_in_front(game, 8.0, SENTINEL, SENTINEL_SCENE)
	await physics_frames(1)
	sentinel.is_spawning = false
	sentinel.set_physics_process(false)
	check(game.hud.is_story_visible(), "the Sentinel's first appearance shows its intro card (%s)" % game.hud.story_text())
	check(Progression.has_seen_story("boss_sentinel"), "the intro is recorded so it shows once")
	# A ray straight at an arc panel stops on it.
	var panel: StaticBody3D = sentinel.arcs.panels[0]
	var origin := player.camera.global_position
	var shot := ShotPipeline.ShotState.new()
	shot.rng = rng(3)
	shot.scene = player.pistol
	var exclude: Array[RID] = [player.get_rid()]
	var stats := WeaponStats.build(Progression.PISTOL_BASE, {}, {})
	var result := ShotPipeline.fire_hitscan(player.get_world_3d().direct_space_state, origin,
		(panel.global_position - origin).normalized(), stats, shot, RAY_MASK, exclude)
	check(result.hit_shield and result.hits.is_empty(), "a shield arc stops a ray")
	var angle: float = sentinel.arcs.pivot.rotation.y
	sentinel.arcs.tick(1.0)
	check(not is_equal_approx(sentinel.arcs.pivot.rotation.y, angle), "the arcs turn around it")
	# The sweep: a grounded player in the beam's path takes the hit once; a jump clears it.
	sentinel.sweep.start(player.global_position, sentinel.global_position)
	var health := player.health
	var hit_count := 0
	for i in 240:
		if sentinel.sweep.tick(1.0 / 60.0, sentinel, player):
			hit_count += 1
	check(hit_count == 1, "the sweep hits a grounded player once per turn (%d)" % hit_count)
	sentinel.sweep.start(player.global_position, sentinel.global_position)
	player.global_position.y += 1.0
	hit_count = 0
	for i in 240:
		if sentinel.sweep.tick(1.0 / 60.0, sentinel, player):
			hit_count += 1
	player.global_position.y -= 1.0
	check(hit_count == 0 and not sentinel.sweep.active, "a player in the air is over the beam, and the sweep ends after one turn")
	check(player.health == health, "the sweep's damage is the boss's to apply")
	await _cleanup(game)
	game.hud.hide_story()


func _test_guardian(game: Node) -> void:
	var guardian: CoreGuardian = spawn_in_front(game, 12.0, GUARDIAN, GUARDIAN_SCENE)
	var phases := []
	var record := func(index: int) -> void: phases.append(index)
	guardian.phase_changed.connect(record)
	game.player._invulnerable_left = 1000.0 # its swings must not end the test
	await seconds(Enemy.SPAWN_TIME + 0.1)
	check(guardian.fight_phase == 0 and guardian.phase_for_health() == 0, "the Core Guardian opens in its first phase")
	var core := guardian.to_global(guardian.definition.weak_point_offset)
	check(not guardian.is_weak_point(core), "its core is shut while it fights")
	guardian.take_hit(guardian.max_health * 0.3, core, Vector3.FORWARD)
	await physics_frames(2)
	check(guardian.is_venting() and guardian.is_weak_point(core), "crossing a phase line makes it vent with the core open")
	var before := guardian.health
	var damage := 50.0
	guardian.take_hit(damage, core, Vector3.FORWARD, true)
	check(is_equal_approx(before - guardian.health, damage), "a core hit while venting ignores the armour")
	await seconds(CoreGuardian.VENT_TIME + 0.1)
	check(not guardian.is_venting() and guardian.fight_phase == 1 and phases == [1], "after the vent it fights in its second phase")
	check(Progression.has_seen_story("guardian_phase_2"), "the phase change fires its story line")
	guardian.take_hit(guardian.max_health * 0.3, core, Vector3.FORWARD)
	await physics_frames(2)
	await seconds(CoreGuardian.VENT_TIME + 0.1)
	guardian.take_hit(guardian.max_health * 0.25, core, Vector3.FORWARD)
	await physics_frames(2)
	await seconds(CoreGuardian.VENT_TIME + 0.1)
	check(guardian.fight_phase == 3 and phases == [1, 2, 3] and guardian.arcs.raised, "the last phase raises the Sentinel's arcs")
	guardian.phase_changed.disconnect(record)
	# The first kill drops a Legendary straight to the bench.
	var inventory_before := Progression.inventory().size()
	guardian.take_hit(100000.0, core, Vector3.FORWARD, true)
	await physics_frames(2)
	var found := false
	for item in Progression.inventory():
		found = found or int(item.get("rarity", 0)) == Items.Rarity.LEGENDARY
	check(Progression.inventory().size() > inventory_before and found, "its first kill drops a Legendary")
	await _cleanup(game)
	game.hud.hide_story()
