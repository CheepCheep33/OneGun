extends TestCase
## Browser-performance guards: pooled effects never grow past their caps, the warm-up ran, the
## projectile pool reuses meshes, and the video settings reach the viewport, light, environment
## and HUD.


func run_scene(game: Node) -> void:
	await _test_effect_pool(game)
	await _test_video_settings(game)


func _test_effect_pool(game: Node) -> void:
	var pool: FxPool = game.get_node_or_null("FxPool")
	check(pool != null and pool.warmed_up, "the effect pool exists and warmed its shaders up at the first bench")
	await seconds(1.0)
	check(pool.active_count() == 0 and pool.get_child_count() <= FxPool.MAX_TRACERS + FxPool.MAX_IMPACTS + FxPool.MAX_NUMBERS + FxPool.MAX_BURSTS,
		"warm-up samples are released and the enemy and drop samples are freed (%d children)" % pool.get_child_count())
	var origin: Vector3 = game.player.global_position + Vector3.UP
	for i in 60:
		Fx.tracer(game, origin, origin + Vector3(0.0, 0.0, -5.0 - i * 0.1))
		Fx.impact(game, origin + Vector3(i * 0.1, 0.0, -5.0), Vector3.UP)
		Fx.damage_number(game, origin + Vector3(i * 0.1, 0.0, -5.0), 10.0 + i, i % 7 == 0)
		Fx.burst(game, origin + Vector3(i * 0.1, 0.0, -5.0), Color.RED)
	var children := pool.get_child_count()
	check(children <= FxPool.MAX_TRACERS + FxPool.MAX_IMPACTS + FxPool.MAX_NUMBERS + FxPool.MAX_BURSTS,
		"sixty of every effect at once stay inside the pool caps (%d nodes)" % children)
	check(pool.active_count() == FxPool.MAX_TRACERS + FxPool.MAX_IMPACTS + FxPool.MAX_NUMBERS + FxPool.MAX_BURSTS,
		"when a pool is full the oldest effect is recycled")
	await seconds(1.2)
	check(pool.active_count() == 0 and pool.get_child_count() == children, "effects age out and their nodes stay for reuse")
	Fx.tracer(game, origin, origin + Vector3(0.0, 0.0, -3.0))
	check(pool.get_child_count() == children, "a new tracer reuses a pooled node")
	var projectiles: ProjectilePool = game.projectiles
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
