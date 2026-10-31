extends TestCase
## Milestone 5 arsenal checks in the running game: the ammo statuses (Incendiary burns without
## stacking, Cryo slows then shatters, Shock arcs and stuns), Stillwater's slow, the Charge
## receiver, the Launcher's grenades, the Shield emitter, the Scanner's markers, and the Signal
## Tower's floor rules on the gun (no reloads, crits only).

const CHASER := "res://data/enemies/chaser.tres"
const CHASER_SCENE := "res://scenes/enemies/chaser.tscn"
const TURRET := "res://data/enemies/turret.tres"
const TURRET_SCENE := "res://scenes/enemies/turret.tscn"


func run_scene(game: Node) -> void:
	game.open_bench()
	await physics_frames(2)
	Progression.reset()
	for wave in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]:
		Progression.record_wave_cleared(wave, 0, 1.0)
	await start_quiet_wave(game)
	await _test_burn(game)
	await _test_cryo(game)
	await _test_shock(game)
	await _test_stillwater(game)
	await _test_tower_rules(game)
	await _test_charge(game)
	await _test_launcher(game)
	await _test_shield_emitter(game)
	await _test_scanner(game)
	game.open_bench()
	await physics_frames(2)
	Progression.reset()
	await start_quiet_wave(game)


func _stats(items: Dictionary) -> WeaponStats:
	return WeaponStats.build(Progression.PISTOL_BASE, {}, items)


func _shot(game: Node) -> ShotPipeline.ShotState:
	var shot := ShotPipeline.ShotState.new()
	shot.rng = rng(7)
	shot.scene = game.player.pistol
	return shot


func _hit(game: Node, enemy: Enemy, stats: WeaponStats) -> ShotPipeline.HitResult:
	var context := WeaponStats.ShotContext.new()
	return ShotPipeline.apply_hit(enemy, enemy.center(), Vector3.FORWARD, stats, context, _shot(game))


func _frozen(game: Node, distance: float, side := 0.0, definition := CHASER, scene := CHASER_SCENE) -> Enemy:
	var enemy := spawn_in_front(game, distance, definition, scene, side)
	await physics_frames(1)
	enemy.is_spawning = false
	enemy.set_physics_process(false)
	return enemy


func _cleanup(game: Node) -> void:
	for enemy in game.wave_runner.living_enemies():
		enemy.set_physics_process(true)
	game.wave_runner.clear_enemies()
	game.projectiles.clear_all()
	await physics_frames(2)


func _equip(game: Node, base_id: StringName, rarity := Items.Rarity.RARE) -> Dictionary:
	var item := Items.make(base_id, rarity)
	Progression.add_item(item, "test")
	Progression.equip(int(item["uid"]))
	game.player.pistol.apply_build(Progression.build_stats(), Progression.equipped())
	return item


func _unequip_all(game: Node) -> void:
	for slot in Items.SLOT_IDS:
		if Progression.equipped_in(slot) != null:
			Progression.unequip(slot)
	game.player.pistol.apply_build(Progression.build_stats(), Progression.equipped())


func _test_burn(game: Node) -> void:
	var stats := _stats({"ammo": Items.make(&"incendiary", Items.Rarity.RARE)})
	var enemy := await _frozen(game, 8.0)
	enemy.health = 1000.0
	_hit(game, enemy, stats)
	var after_hit := enemy.health
	check(enemy.burn_left > 0.0 and enemy.burn_dps > 0.0, "an Incendiary hit sets the robot burning (%.1f a second)" % enemy.burn_dps)
	var rate := enemy.burn_dps
	_hit(game, enemy, stats)
	check(is_equal_approx(enemy.burn_dps, rate) and enemy.burn_left <= StatusEffects.BURN_DURATION * stats.status_duration_scale() + 0.01,
		"a second burn refreshes the first and never stacks")
	# Statuses tick in the enemy's physics step.
	enemy.set_physics_process(true)
	await seconds(1.1)
	check(enemy.health < after_hit - rate * 0.5, "the burn deals its damage over time (%.0f → %.0f)" % [after_hit, enemy.health])
	await _cleanup(game)


func _test_cryo(game: Node) -> void:
	var stats := _stats({"ammo": Items.make(&"cryo", Items.Rarity.RARE)})
	var enemy := await _frozen(game, 8.0)
	var neighbour := await _frozen(game, 8.0, 1.2)
	enemy.health = 1000.0
	neighbour.health = 1000.0
	_hit(game, enemy, stats)
	check(enemy.is_slowed() and enemy._speed_scale() < 0.7, "a Cryo hit slows the robot (speed x%.2f)" % enemy._speed_scale())
	check(not enemy.can_shatter(), "a fresh slow does not shatter yet")
	enemy.slow_age = StatusEffects.SHATTER_AFTER + 0.1
	var before := neighbour.health
	_hit(game, enemy, stats)
	check(not enemy.is_slowed() and neighbour.health < before, "a Cryo hit on an old slow shatters it and the frost hurts robots nearby")
	await _cleanup(game)


func _test_shock(game: Node) -> void:
	var stats := _stats({"ammo": Items.make(&"shock", Items.Rarity.RARE)})
	var enemy := await _frozen(game, 8.0)
	var neighbour := await _frozen(game, 8.0, 2.0)
	enemy.health = 1000.0
	neighbour.health = 1000.0
	_hit(game, enemy, stats)
	check(neighbour.health < 1000.0 and neighbour.stun_left > 0.0 and neighbour._speed_scale() == 0.0,
		"a Shock hit arcs to a robot nearby and stuns it")
	await _cleanup(game)


func _test_stillwater(game: Node) -> void:
	var plain := _stats({"barrel": Items.make(&"long_barrel", Items.Rarity.EPIC)})
	var legendary := _stats({"barrel": Items.make(&"long_barrel", Items.Rarity.LEGENDARY)})
	var enemy := await _frozen(game, 8.0)
	enemy.health = 1000.0
	_hit(game, enemy, plain)
	check(not enemy.is_slowed(), "an Epic Long barrel does not slow")
	_hit(game, enemy, legendary)
	check(enemy.is_slowed(), "Stillwater, its Legendary, slows the robots it hits")
	await _cleanup(game)


func _test_tower_rules(game: Node) -> void:
	var pistol: Pistol = game.player.pistol
	var stats := _stats({})
	var enemy := await _frozen(game, 8.0)
	enemy.health = 1000.0
	ShotPipeline.crits_only = true
	var context := WeaponStats.ShotContext.new()
	var miss := ShotPipeline.apply_hit(enemy, enemy.center(), Vector3.FORWARD, stats, context, _shot(game))
	context.force_crit = true
	var crit := ShotPipeline.apply_hit(enemy, enemy.center(), Vector3.FORWARD, stats, context, _shot(game))
	ShotPipeline.crits_only = false
	check(miss.damage == 0.0 and crit.damage > 0.0, "on an Only crits floor a plain hit does nothing and a crit lands")
	await _cleanup(game)
	pistol.no_reloads = true
	pistol.ammo = 1
	pistol.request_reload()
	check(not pistol.is_reloading, "on a No reloads floor the gun does not reload")
	pistol.notify_kill()
	check(pistol.ammo == pistol.stats.magazine_size, "and a kill fills the magazine")
	pistol.apply_build(Progression.build_stats(), Progression.equipped())
	check(not pistol.no_reloads, "a rebuild clears the floor rule")


func _test_charge(game: Node) -> void:
	Progression.add_unlock("signal_tower")
	var pistol: Pistol = game.player.pistol
	_equip(game, &"charge")
	check(pistol.stats.fire_mode() == "charge" and pistol.stats.charge_time() > 0.0, "the Charge receiver is fitted")
	var full := pistol.ammo
	var fractions: Array[float] = []
	var record := func(fraction: float) -> void: fractions.append(fraction)
	pistol.charge_changed.connect(record)
	pistol.request_fire()
	await seconds(pistol.stats.charge_time() + 0.2)
	check(pistol.ammo == full and pistol.charge_fraction() >= 0.99, "holding the trigger charges without firing")
	pistol.release_fire()
	await physics_frames(3)
	pistol.charge_changed.disconnect(record)
	check(pistol.ammo == full - 1 and fractions.has(-1.0) and fractions.max() >= 0.99, "releasing fires one charged round and hides the meter")
	var charged := WeaponStats.ShotContext.new()
	charged.charge = 1.0
	var flat := WeaponStats.ShotContext.new()
	check(WeaponStats.resolve_shot(pistol.stats, charged, rng(1)).damage > WeaponStats.resolve_shot(pistol.stats, flat, rng(1)).damage,
		"a full charge hits harder than a tap")
	_unequip_all(game)


func _test_launcher(game: Node) -> void:
	var pistol: Pistol = game.player.pistol
	_equip(game, &"launcher")
	check(not pistol.request_alt_fire() and game.hud.gun_status() == "GRENADES 0", "the Launcher starts empty and the HUD says so")
	for i in Pistol.GRENADE_KILLS:
		pistol.notify_kill()
	check(pistol.grenades == 1 and game.hud.gun_status() == "GRENADES 1", "%d kills load a grenade" % Pistol.GRENADE_KILLS)
	var enemy := await _frozen(game, 6.0)
	enemy.health = 1.0
	check(pistol.request_alt_fire() and pistol.grenades == 0, "alt fire throws it")
	await seconds(1.2)
	check(not enemy.is_alive, "the grenade's blast kills a weak robot in front")
	await _cleanup(game)
	_unequip_all(game)


func _test_shield_emitter(game: Node) -> void:
	var pistol: Pistol = game.player.pistol
	var player: Player = game.player
	_equip(game, &"shield_emitter")
	player.revive(game.arena.get_player_start())
	pistol.ammo = 1
	pistol.request_reload()
	check(pistol.is_shield_up(), "the Shield emitter raises a shield while reloading")
	var front := player.global_position - player.global_basis.z * 5.0
	var before := player.health
	player.take_damage(10.0, front)
	check(is_equal_approx(before - player.health, 10.0 * (1.0 - Pistol.RELOAD_SHIELD_REDUCTION)), "it blocks most of a hit from the front (%.1f)" % (before - player.health))
	before = player.health
	player.take_damage(10.0, player.global_position + player.global_basis.z * 5.0)
	check(is_equal_approx(before - player.health, 10.0), "but not from behind")
	player.revive(game.arena.get_player_start())
	_unequip_all(game)


func _test_scanner(game: Node) -> void:
	_equip(game, &"scanner")
	var turret := await _frozen(game, 14.0, 0.0, TURRET, TURRET_SCENE)
	await physics_frames(2)
	check(game.hud.visible_scan_markers() >= 1, "the Scanner marks a turret on the HUD")
	turret.take_hit(100000.0, turret.center(), Vector3.FORWARD, true)
	await physics_frames(2)
	check(game.hud.visible_scan_markers() == 0, "the marker goes with the turret")
	await _cleanup(game)
	_unequip_all(game)
