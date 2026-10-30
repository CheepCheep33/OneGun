extends TestCase
## Browser-performance guards: pooled effects never grow past their caps, the warm-up ran, the
## projectile pool reuses meshes, and the video settings reach the viewport, light, environment
## and HUD.


func run_scene(game: Node) -> void:
	await _test_effect_pool(game)
	await _test_video_settings(game)


func _test_effect_pool(game: Node) -> void:
	var pool: FxPool = game.get_node_or_null("FxPool")
	var cap := FxPool.MAX_TRACERS + FxPool.MAX_IMPACTS + FxPool.MAX_NUMBERS + FxPool.MAX_LABELS + FxPool.MAX_BURSTS + FxPool.MAX_SOUNDS + FxPool.MAX_RINGS
	check(pool != null and pool.warmed_up, "the effect pool exists and warmed its shaders up at the first bench")
	check(pool.warmed_muzzle_light, "the warm-up drew the arena and its samples with the muzzle light on (lit shader variants)")
	await seconds(1.0)
	check(pool.active_count() == 0 and pool.pooled_count() == cap and pool.get_child_count() == cap - FxPool.MAX_NUMBERS - FxPool.MAX_LABELS + 1,
		"warm-up built every pool to its cap, released its samples and freed the enemy and drop samples (%d nodes)" % pool.pooled_count())
	check(pool._numbers[0].node is Label and pool._labels[0].node is Label and pool.label_parent() == game.hud and pool._label_root.get_index() == 0,
		"damage numbers and drop names are 2D labels drawn first inside the HUD's layer (a Label3D rebuilds its mesh every frame it fades)")
	check(LootDrop._materials.size() == Items.RARITY_COLORS.size(), "every rarity's drop materials exist after the warm-up (%d)" % LootDrop._materials.size())
	var origin: Vector3 = game.player.global_position + Vector3.UP
	for i in 60:
		Fx.tracer(game, origin, origin + Vector3(0.0, 0.0, -5.0 - i * 0.1))
		Fx.impact(game, origin + Vector3(i * 0.1, 0.0, -5.0), Vector3.UP)
		Fx.damage_number(game, origin + Vector3(i * 0.1, 0.0, -5.0), 10.0 + i, i % 7 == 0)
		Fx.burst(game, origin + Vector3(i * 0.1, 0.0, -5.0), Color.RED)
	var children := pool.pooled_count()
	check(children == cap, "sixty of every effect at once stay inside the pool caps (%d nodes)" % children)
	check(pool.active_count() == FxPool.MAX_TRACERS + FxPool.MAX_IMPACTS + FxPool.MAX_NUMBERS + FxPool.MAX_BURSTS,
		"when a pool is full the oldest effect is recycled")
	await seconds(1.2)
	check(pool.active_count() == 0 and pool.pooled_count() == children, "effects age out and their nodes stay for reuse")
	Fx.tracer(game, origin, origin + Vector3(0.0, 0.0, -3.0))
	check(pool.pooled_count() == children, "a new tracer reuses a pooled node")
	var sample: Enemy = load("res://scenes/enemies/chaser.tscn").instantiate()
	var stream: AudioStream = sample.death_sound
	sample.free()
	for i in 20:
		Fx.sound_at(game, stream, origin + Vector3(i * 0.2, 0.0, -4.0))
		Fx.ring(game, origin + Vector3(i * 0.2, -0.9, -4.0), 2.0, Color.RED, 0.3)
	check(stream != null and pool._sounds.size() == FxPool.MAX_SOUNDS and pool._rings.size() == FxPool.MAX_RINGS and pool.pooled_count() == children,
		"death sounds and slam rings are pooled too (%d players, %d rings for twenty of each)" % [pool._sounds.size(), pool._rings.size()])
	await seconds(0.5)
	var projectiles: ProjectilePool = game.projectiles
	check(projectiles._free.size() + projectiles._live.size() >= ProjectilePool.WARM_UP_COUNT and projectiles._capsules.size() >= ProjectilePool.PROFILES.size(),
		"the projectile pool built %d rounds and every profile's capsule at warm-up" % (projectiles._free.size() + projectiles._live.size()))
	var meshes := projectiles._capsules.size()
	projectiles.fire_enemy_bolt(null, origin + Vector3(0.0, 30.0, 0.0), Vector3.UP, 1.0, Color.RED, 0.2, 0.33)
	projectiles.fire_enemy_bolt(null, origin + Vector3(1.0, 30.0, 0.0), Vector3.UP, 1.0, Color.RED, 0.2, 0.33)
	check(projectiles._capsules.size() == meshes + 1, "rounds of the same radius share one capsule mesh")
	await seconds(0.4)
	projectiles.clear_all()


func _test_video_settings(game: Node) -> void:
	var viewport := game.get_viewport()
	var before := {
		"render_scale": Settings.render_scale, "shadows": Settings.shadows, "glow": Settings.glow, "show_fps": Settings.show_fps,
	}
	Settings.set_value(&"render_scale", 0.6)
	check(is_equal_approx(viewport.scaling_3d_scale, 0.6) and viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR,
		"render scale reaches the viewport")
	Settings.set_value(&"render_scale", 0.1)
	check(is_equal_approx(viewport.scaling_3d_scale, Settings.RENDER_SCALE_RANGE.x), "render scale is clamped to its floor")
	Settings.set_value(&"shadows", false)
	Settings.set_value(&"glow", false)
	check(not game.sun.shadow_enabled and not game.world_environment.environment.glow_enabled, "shadows and glow switch off")
	Settings.set_value(&"show_fps", true)
	check(game.hud._fps_label.visible, "the FPS readout shows when asked")
	await seconds(0.7)
	check(" fps " in game.hud._fps_label.text and "worst frame" in game.hud._fps_label.text, "the readout reports the average and the worst frame (%s)" % game.hud._fps_label.text)
	for key in before:
		Settings.set_value(StringName(key), before[key])
	check(is_equal_approx(viewport.scaling_3d_scale, float(before["render_scale"])) and game.sun.shadow_enabled == bool(before["shadows"]) and not game.hud._fps_label.visible,
		"settings restore")
