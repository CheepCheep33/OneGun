extends TestCase
## Milestone 5 skill checks: the three trees (eight nodes and a capstone each), tier and capstone
## gates, points from levels and boss first kills, the experience curve, free respec, skills in
## the shared stats function, the player-side effects in the running game, and the bench's
## skills tab.


func run_unit() -> void:
	Progression.reset()
	_test_trees()
	_test_points_and_gates()
	_test_curve()
	_test_stats()
	Progression.reset()


func run_scene(game: Node) -> void:
	await _test_player_effects(game)
	await _test_skills_tab(game)


func _test_trees() -> void:
	check(Skills.all().size() == 27, "27 skill nodes load (%d)" % Skills.all().size())
	var ok := true
	for tree in Skills.TREES:
		var nodes := Skills.nodes_of(tree)
		var capstones := 0
		var per_tier := {}
		for node in nodes:
			if node.capstone:
				capstones += 1
				ok = ok and node.tier == Skills.CAPSTONE_TIER
			else:
				per_tier[node.tier] = int(per_tier.get(node.tier, 0)) + 1
		ok = ok and nodes.size() == 9 and capstones == 1 and per_tier == {0: 2, 1: 2, 2: 2, 3: 2}
	check(ok, "each tree has eight nodes in four tiers of two and one capstone")
	var described := true
	for node in Skills.all():
		described = described and node.display_name != "" and node.description != "" \
			and (not node.modifiers.is_empty() or not node.player_effects.is_empty())
	check(described, "every node has a name, a description and an effect")


func _test_points_and_gates() -> void:
	Progression.reset()
	check(Progression.player_level() == 1 and Progression.skill_points_available() == 0, "a new save is level 1 with no points")
	check(Progression.skill_block_reason(&"steady_hands") == "No skill points", "without points nothing can be taken")
	Progression.add_xp(Skills.xp_to_next(1))
	check(Progression.player_level() == 2 and Progression.skill_points_available() == 1, "level 2 gives the first point")
	check(Progression.record_boss_kill(&"warden") and not Progression.record_boss_kill(&"warden") and Progression.skill_points_available() == 2,
		"a boss's first kill gives one more point, once")
	check(Progression.skill_block_reason(&"long_shot").begins_with("Needs 2 points"), "a tier 1 node waits for two points in its tree (%s)" % Progression.skill_block_reason(&"long_shot"))
	check(Progression.take_skill(&"steady_hands") and Progression.take_skill(&"deadeye"), "tier 0 nodes take a point each")
	check(not Progression.take_skill(&"steady_hands") and Progression.skill_points_available() == 0, "a node is taken once")
	Progression.data["xp"] = 1000000000000
	check(Progression.player_level() == Skills.MAX_LEVEL, "levels stop at %d" % Skills.MAX_LEVEL)
	check(Progression.take_skill(&"keen_eye") and Progression.take_skill(&"long_shot"), "with two points in the tree, tier 1 opens")
	check(Progression.skill_block_reason(&"bullet_time").begins_with("Needs every other"), "the capstone waits for the tree's other eight nodes")
	for node in Skills.nodes_of(&"marksman"):
		if not node.capstone:
			Progression.take_skill(node.id)
	check(Progression.take_skill(&"bullet_time"), "the capstone opens with the whole tree")
	var spent := Skills.spent(Progression.data["skills"])
	Progression.respec_skills()
	check(spent == 9 and Progression.data["skills"].is_empty() and Progression.skill_points_available() == Progression.skill_points_total(),
		"respec is free and refunds every point")
	Progression.reset()


func _test_curve() -> void:
	# The plan's pace: the first point after about two waves, level 15 or so at the first wave 20.
	var income := 0
	var after_two := 0
	for wave in WaveRunner.all_waves():
		income += roundi(wave.kill_income() * pow(Progression.TIER_STEP, Progression.tier_of_wave(wave.number))) \
			+ wave.completion_bonus * (2 if wave.is_boss_wave else 1)
		if wave.number == 2:
			after_two = income
	check(Skills.level_for_xp(after_two) >= 2, "two waves reach level 2 (%d experience)" % after_two)
	var level := Skills.level_for_xp(income)
	check(level >= 13 and level <= 17, "a first run's experience to wave 20 reaches about level 15 (%d at %d)" % [level, income])
	check(level - 1 + 4 < Skills.all().size(), "a first run cannot take every node (%d points of %d)" % [level + 3, Skills.all().size()])


func _test_stats() -> void:
	var base := Progression.PISTOL_BASE
	var plain := WeaponStats.build(base, {}, {})
	var marksman := WeaponStats.build(base, {}, {}, {"deadeye": 1, "steady_hands": 1})
	check(marksman.crit_chance > plain.crit_chance, "Deadeye raises crit chance through the shared stats function (%.2f → %.2f)" % [plain.crit_chance, marksman.crit_chance])
	check(marksman.recoil_kick_degrees < plain.recoil_kick_degrees, "Steady hands lowers recoil")
	var effects := Skills.player_effects({"toughness": 1, "bulwark": 1, "magnet": 1})
	check(is_equal_approx(float(effects.get("max_health", 0.0)), 50.0) and float(effects.get("pickup_scale", 0.0)) > 0.0,
		"Survivor's player effects add up (%s)" % str(effects))


func _test_player_effects(game: Node) -> void:
	game.open_bench()
	await physics_frames(2)
	Progression.reset()
	Progression.data["xp"] = 1000000
	for id in ["toughness", "fleet_foot", "second_wind", "plating"]:
		Progression.take_skill(StringName(id))
	await start_quiet_wave(game)
	var player: Player = game.player
	check(is_equal_approx(player.max_health, player.base_max_health + 25.0) and is_equal_approx(player.health, player.max_health),
		"Toughness raises max health for the encounter (%.0f)" % player.max_health)
	player.take_damage(10.0)
	check(is_equal_approx(player.health, player.max_health - 7.0), "Plating takes 3 off a hit (%.1f left)" % player.health)
	var chaser := spawn_in_front(game, 6.0)
	await physics_frames(2)
	var before := player.health
	chaser.take_hit(10000.0, chaser.center(), Vector3.FORWARD)
	await physics_frames(2)
	check(player.health > before, "Second Wind heals on a kill (%.1f → %.1f)" % [before, player.health])
	game.wave_runner.clear_enemies()
	# Phoenix: one lethal hit per encounter leaves the player standing.
	game.open_bench()
	await physics_frames(2)
	Progression.respec_skills()
	for pass_number in 2: # the capstone opens once the other eight are in
		for node in Skills.nodes_of(&"survivor"):
			Progression.take_skill(node.id)
	await start_quiet_wave(game)
	player.take_damage(100000.0)
	check(not player.is_dead and is_equal_approx(player.health, 1.0) and player.is_invulnerable(), "Phoenix turns the first lethal hit into 1 health")
	player._invulnerable_left = 0.0
	player.take_damage(100000.0)
	await physics_frames(2)
	check(player.is_dead, "Phoenix works once per encounter")
	game.open_bench()
	await physics_frames(2)
	Progression.reset()
	check(Engine.time_scale == 1.0, "the bench leaves the game at normal speed")


func _test_skills_tab(game: Node) -> void:
	var bench: Bench = game.bench
	Progression.reset()
	Progression.add_xp(Skills.xp_to_next(1))
	bench.open()
	bench.show_tab("skills")
	check(bench.current_tab() == "skills" and bench._tab_views["skills"].visible, "the bench has a skills tab")
	var button: Button = bench._skill_buttons["steady_hands"]
	check(not button.disabled and bench._skill_buttons["long_shot"].disabled, "an open node is offered, a gated one greyed")
	button.pressed.emit()
	check(Progression.has_skill(&"steady_hands") and bench._skill_buttons["steady_hands"].button_pressed, "clicking a node takes it")
	check(not bench._respec_button.disabled, "respec is offered once a node is taken")
	bench._respec_button.pressed.emit()
	check(not Progression.has_skill(&"steady_hands") and Progression.skill_points_available() == 1, "respec on the bench refunds the point")
	bench.show_tab("core")
	Progression.reset()
	bench.refresh()
