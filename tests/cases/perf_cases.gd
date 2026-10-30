extends TestCase
## The performance gate behind the standing rule (30 Oct 2026): every milestone keeps stutter and
## lag in check. Headless, so it cannot see the GPU; it guards the CPU side that showed up as
## hitches in the browser, where every allocation, mesh upload and first-use shader compile lands
## on the one main thread.
## 1. A busy combat round (automatic fire into a crowd, enemy bolts, drones, sixteen deaths)
##    leaves no node, orphan node or resource behind once its effects have aged out, and at most
##    OBJECT_SLACK plain objects (the engine keeps a few lazily: audio playbacks, caches). A
##    per-shot, per-bolt, per-hit or per-death allocation that lives on shows up here as a count
##    that grows by tens or hundreds.
## 2. Game logic with a full arena costs under CPU_BUDGET_MS a frame: one frame's process
##    callbacks plus one physics step, measured with FrameCost below. The browser build runs this
##    code several times slower than native and still has to render, so the budget is tight on
##    purpose.
## 3. The shader warm-up covers every enemy scene the wave data uses and ran with the muzzle light
##    on (a material the light touches for the first time compiles a second, lit shader), the
##    enemy reserve holds as many of each as the waves can have alive at once, so a spawn mid-wave
##    reuses a node (the round's spawns must all come from the reserve; their cost is printed), and
##    drops come from a reserve too. Damage numbers are 2D labels: a Label3D rebuilds its mesh and
##    material on every change, each frame of its fade included.
## What the GPU does (shader compiles, buffer uploads) needs a renderer: tests/gpu_probe.tscn and
## tests/gpu_gate.sh cover that side.

const CHASERS := 10
const SHOOTERS := 2
const DRONES := 4
const FIRE_SECONDS := 3.0
const BOLT_INTERVAL := 0.1
const BOLTS_PER_VOLLEY := 3
const SETTLE_SECONDS := 1.6
## Plain (non-node, non-resource) objects a round may leave: a handful is engine housekeeping, a
## leak per event in a round of a dozen shots, ninety bolts and sixteen kills is far more.
const OBJECT_SLACK := 8
## Game-logic milliseconds a frame (process callbacks plus one physics step) allowed with the arena
## above, on the reference machine. Measured there at 1.4 ms; a 60 Hz frame is 16.7 ms and the
## browser build runs this code about three times slower and still has to render, so 4 ms native
## is as much as twice the wave cap may ever cost. The budget scales with the test machine's speed
## (CALIBRATION_LOOPS of float math took REFERENCE_CALIBRATION_MS on the reference machine), never
## below the nominal figure and never more than three times it. GAME_PLAN.md, "Performance budget".
const CPU_BUDGET_MS := 4.0
const REFERENCE_CALIBRATION_MS := 110.0
const CALIBRATION_LOOPS := 2000000

const CHASER := "res://data/enemies/chaser.tres"
const CHASER_SCENE := "res://scenes/enemies/chaser.tscn"
const SHOOTER := "res://data/enemies/shooter.tres"
const SHOOTER_SCENE := "res://scenes/enemies/shooter.tscn"
const DRONE := "res://data/enemies/swarm_drone.tres"
const DRONE_SCENE := "res://scenes/enemies/swarm_drone.tscn"
const WARDEN := "res://data/enemies/warden.tres"
const WARDEN_SCENE := "res://scenes/enemies/warden.tscn"

## Definitions with the drop chance zeroed, so a lucky Common does not land on the floor and read
## as a leak. Made once: the second round must not create anything new.
var _definitions: Dictionary = {}
var _automatic: Dictionary = {}


## Game-logic cost per frame, measured while the loop runs uncapped and without the sleep headless
## Godot adds to every frame (OS.low_processor_usage_mode_sleep_usec, set to 0 around the
## measurement). The gap between two process_frame signals is one frame's process callbacks when
## no physics step ran in between, and those callbacks plus the physics steps when steps did; the
## two kinds of gap give the cost of each. The Performance monitors cannot be used for this: they
## hold the worst frame of the last second.
class FrameCost:
	var process_total := 0.0
	var process_count := 0
	var mixed_total := 0.0
	var mixed_count := 0
	var mixed_steps := 0
	var worst_process := 0.0
	var worst_mixed := 0.0
	var _last_tick := 0
	var _last_physics := 0

	func start() -> void:
		_last_tick = Time.get_ticks_usec()
		_last_physics = Engine.get_physics_frames()

	## Call right after `await process_frame`.
	func sample() -> void:
		var now := Time.get_ticks_usec()
		var physics_frames := Engine.get_physics_frames()
		var gap := (now - _last_tick) / 1000.0
		if physics_frames == _last_physics:
			process_total += gap
			process_count += 1
			worst_process = maxf(worst_process, gap)
		else:
			mixed_total += gap
			mixed_count += 1
			mixed_steps += physics_frames - _last_physics
			worst_mixed = maxf(worst_mixed, gap)
		_last_tick = now
		_last_physics = physics_frames

	## Milliseconds: process callbacks a frame, one physics step, their sum (one 60 Hz frame), and
	## the worst of each seen.
	func result() -> Dictionary:
		var process := process_total / maxi(process_count, 1)
		var physics := 0.0
		if mixed_steps > 0:
			physics = maxf((mixed_total - mixed_count * process) / mixed_steps, 0.0)
		return {
			"process": process, "physics": physics, "frame": process + physics,
			"worst_process": worst_process, "worst_physics": maxf(worst_mixed - process, 0.0),
			"frames": process_count + mixed_count, "steps": mixed_steps,
		}


func run_scene(game: Node) -> void:
	game.open_bench()
	await physics_frames(2)
	Progression.reset()
	game.start_wave(1)
	await physics_frames(3)
	game.wave_runner.stop()
	game.wave_runner.clear_enemies()
	game.projectiles.clear_all()
	await physics_frames(2)
	var previous_sleep := OS.low_processor_usage_mode_sleep_usec
	OS.low_processor_usage_mode_sleep_usec = 0 # headless Godot sleeps this long every frame
	_test_warm_up_coverage(game)
	await _test_drops_from_reserve(game)
	await _print_spawn_costs(game)
	# Round one brings every pool to its working size; round two must add nothing.
	var first := await _combat_round(game, false)
	var before := _snapshot()
	var second := await _combat_round(game, true)
	var after := _snapshot()
	var total := CHASERS + SHOOTERS + DRONES
	check(first["shots"] >= 8 and second["shots"] >= 8 and second["kills"] == total,
		"the round is busy: %d shots, %d bolts, %d kills" % [second["shots"], second["bolts"], second["kills"]])
	check(second["misses"] == 0, "every spawn of the second round came from the enemy reserve (%d built new)" % second["misses"])
	check(after["nodes"] == before["nodes"],
		"a second combat round adds no nodes (%d -> %d)" % [before["nodes"], after["nodes"]])
	check(after["orphans"] == before["orphans"],
		"a second combat round leaves no orphan nodes beyond the enemy reserve (%d -> %d)" % [before["orphans"], after["orphans"]])
	check(after["resources"] <= before["resources"],
		"a second combat round creates no lasting resources, meshes, materials or shapes (%d -> %d)" % [before["resources"], after["resources"]])
	check(after["objects"] <= before["objects"] + OBJECT_SLACK,
		"a second combat round leaves at most %d plain objects behind (%d -> %d)" % [OBJECT_SLACK, before["objects"], after["objects"]])
	var cost: Dictionary = second["cost"]
	var speed := _machine_speed()
	var budget := CPU_BUDGET_MS * speed
	check(cost["frame"] <= budget,
		"game logic with %d enemies, bolts and automatic fire costs %.2f ms a frame: %.2f process + %.2f physics (budget %.1f ms at %.2fx the reference machine's time; worst step %.1f ms; %d frames, %d steps)" % [total, cost["frame"], cost["process"], cost["physics"], budget, speed, cost["worst_physics"], cost["frames"], cost["steps"]])
	print("PERF  frame %.2f ms (%.2f process + %.2f physics), worst physics step %.1f ms, budget %.1f ms; %d nodes, %d resources, %d objects after the round" % [cost["frame"], cost["process"], cost["physics"], cost["worst_physics"], budget, after["nodes"], after["resources"], after["objects"]])
	OS.low_processor_usage_mode_sleep_usec = previous_sleep
	game.player.pistol.apply_build(Progression.build_stats(), Progression.equipped())
	game.open_bench()
	await physics_frames(2)
	Progression.reset()


func _test_warm_up_coverage(game: Node) -> void:
	var pool: FxPool = game.get_node_or_null("FxPool")
	var expected: Array[String] = []
	for wave in WaveRunner.all_waves():
		for group in wave.groups:
			if group.enemy_scene != null and not expected.has(group.enemy_scene.resource_path):
				expected.append(group.enemy_scene.resource_path)
	var missing: Array[String] = []
	for path in expected:
		if pool == null or not pool.warmed_scenes.has(path):
			missing.append(path)
	check(pool != null and pool.warmed_up and expected.size() >= 4 and missing.is_empty(),
		"the shader warm-up drew every enemy scene the waves use (%d scenes%s)" % [expected.size(), "" if missing.is_empty() else ", missing " + ", ".join(missing)])
	var runner: WaveRunner = game.wave_runner
	var targets := WaveRunner.reserve_targets()
	var short: Array[String] = []
	for path in targets:
		if runner.reserved_count(path) < int(targets[path]):
			short.append("%s %d/%d" % [String(path).get_file().get_basename(), runner.reserved_count(path), targets[path]])
	check(targets.size() == expected.size() and short.is_empty() and runner.reserved_count() >= 16,
		"the enemy reserve holds what the waves can have alive at once (%d nodes%s)" % [runner.reserved_count(), "" if short.is_empty() else ", short: " + ", ".join(short)])
	check(pool != null and pool.warmed_muzzle_light,
		"the warm-up drew the arena and every sample with the muzzle light on, so no lit shader variant compiles at the first shots")
	check(pool != null and not pool._numbers.is_empty() and pool._numbers[0].node is Label,
		"damage numbers are 2D labels on the canvas, not Label3D meshes rebuilt every frame they fade")
	check(game.drop_reserve_count() == game.DROP_RESERVE,
		"the drop reserve is full at the bench (%d of %d)" % [game.drop_reserve_count(), game.DROP_RESERVE])


## Drops land from the reserve: a second batch after the first is cleared builds no node and no
## material (one Label3D text per drop is the only thing it writes).
func _test_drops_from_reserve(game: Node) -> void:
	var before := _snapshot()
	var misses_before: int = game.drop_reserve_misses
	var materials: int = LootDrop._materials.size()
	var at: Vector3 = game.player.global_position
	for round in 2:
		for i in 8:
			game._spawn_drop(Items.make(&"long_barrel", i % Items.RARITY_COLORS.size()), at + Vector3(i * 1.5 - 5.0, 0.0, -4.0 - round))
		await physics_frames(2)
		game._clear_drops()
		await physics_frames(2)
	var after := _snapshot()
	check(game.drop_reserve_misses == misses_before and after["nodes"] == before["nodes"] and after["resources"] <= before["resources"]
		and LootDrop._materials.size() == materials,
		"sixteen drops over two batches come from the drop reserve and build no node, mesh or material (%d -> %d nodes, %d built new)" % [before["nodes"], after["nodes"], game.drop_reserve_misses - misses_before])


## What one spawn from the reserve costs, for the plan's budget table (printed, not gated: the
## node-count checks below prove the reuse).
func _print_spawn_costs(game: Node) -> void:
	var report := PackedStringArray()
	for pair in [[CHASER, CHASER_SCENE], [SHOOTER, SHOOTER_SCENE], [DRONE, DRONE_SCENE], [WARDEN, WARDEN_SCENE]]:
		var definition: EnemyDefinition = load(pair[0])
		var scene: PackedScene = load(pair[1])
		var started := Time.get_ticks_usec()
		game.wave_runner.spawn_at(Vector3(0.0, 1.0, 0.0), definition, scene)
		report.append("%s %.2f ms" % [String(pair[1]).get_file().get_basename(), (Time.get_ticks_usec() - started) / 1000.0])
	game.wave_runner.clear_enemies()
	await physics_frames(2)
	print("PERF  spawn from the reserve: " + ", ".join(report))


## One busy round: the crowd spawns, the pistol fires on automatic for FIRE_SECONDS while bolts
## rain down near the player, then everything dies and the effects age out. Returns what happened
## and, when `measure` is set, the game-logic cost per frame over the firing phase.
func _combat_round(game: Node, measure: bool) -> Dictionary:
	var player: Player = game.player
	var pistol: Pistol = game.player.pistol
	var pool: ProjectilePool = game.projectiles
	player.revive(game.arena.get_player_start())
	player.health = 1.0e9 # the crowd must not kill the player mid-round
	game.state = game.State.COMBAT
	if _automatic.is_empty():
		_automatic = Items.make(&"automatic")
	var build := {"receiver": _automatic}
	pistol.apply_build(WeaponStats.build(Progression.PISTOL_BASE, Progression.core_levels(), build), build)
	var misses_before: int = game.wave_runner.reserve_misses
	var enemies: Array[Enemy] = []
	for i in CHASERS:
		enemies.append(_spawn(game, CHASER, CHASER_SCENE, 4.5 + 1.6 * (i % 5), -2.5 + 5.0 * (i / 5)))
	for i in SHOOTERS:
		enemies.append(_spawn(game, SHOOTER, SHOOTER_SCENE, 10.0, -4.0 + 8.0 * i))
	for i in DRONES:
		enemies.append(_spawn(game, DRONE, DRONE_SCENE, 7.0 + i, -1.5 + i))
	for enemy in enemies:
		enemy.health = 1.0e9 # the crowd survives the firing phase so every shot lands on something
	await seconds(Enemy.SPAWN_TIME + 0.1)
	var result := {"shots": 0, "bolts": 0, "kills": 0, "cost": {}, "misses": game.wave_runner.reserve_misses - misses_before}
	var shots_before: int = pistol.shots_fired
	var elapsed := 0.0
	var volley_timer := 0.0
	var cost := FrameCost.new()
	pistol.request_fire()
	cost.start()
	while elapsed < FIRE_SECONDS:
		await tree().process_frame
		if measure:
			cost.sample()
		var delta := game.get_process_delta_time()
		elapsed += delta
		volley_timer -= delta
		if volley_timer <= 0.0:
			volley_timer = BOLT_INTERVAL
			for i in BOLTS_PER_VOLLEY:
				var origin := player.global_position + Vector3(randf_range(-3.0, 3.0), 5.0, randf_range(-3.0, 3.0))
				pool.fire_enemy_bolt(null, origin, Vector3.DOWN * 20.0, 1.0, Color.RED, 1.0)
				result["bolts"] += 1
	pistol.release_fire()
	result["shots"] = pistol.shots_fired - shots_before
	result["cost"] = cost.result()
	# Everything dies, a few a frame, the way a strong build clears a crowd.
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.is_alive:
			enemy.take_hit(1.0e12, enemy.global_position, Vector3.FORWARD)
			result["kills"] += 1
			if result["kills"] % 4 == 0:
				await physics_frames(1)
	await seconds(SETTLE_SECONDS)
	pool.clear_all()
	await physics_frames(2)
	return result


func _spawn(game: Node, definition_path: String, scene_path: String, distance: float, side: float) -> Enemy:
	if not _definitions.has(definition_path):
		var definition: EnemyDefinition = load(definition_path).duplicate()
		definition.loot_weight = 0.0
		_definitions[definition_path] = definition
	var player: Player = game.player
	var forward := -player.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	return game.wave_runner.spawn_at(player.global_position + forward * distance + right * side,
		_definitions[definition_path], load(scene_path))


## How much slower this machine is than the reference one, from a fixed loop of float math: 1.0 on
## a machine as fast or faster, up to 3.0 on a slow runner.
func _machine_speed() -> float:
	var started := Time.get_ticks_usec()
	var sink := 0.0
	for i in CALIBRATION_LOOPS:
		sink += sqrt(float(i)) * 0.5
	var took := (Time.get_ticks_usec() - started) / 1000.0
	print("PERF  calibration loop %.1f ms (reference %.1f ms, sink %.0f)" % [took, REFERENCE_CALIBRATION_MS, sink])
	return clampf(took / REFERENCE_CALIBRATION_MS, 1.0, 3.0)


func _snapshot() -> Dictionary:
	return {
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
	}
