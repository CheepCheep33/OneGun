extends TestCase
## Stats checks: every authored base, mark scaling, the range and recoil stats, pierce and bounce
## falloff, the Splitter's damage split and Explosive rounds' direct and blast shares (Milestone 4),
## tier scaling, and a random sample of full builds that must all stay finite and inside the caps
## (plan: stats sample test).

const SAMPLE_BUILDS := 10000


func run_unit() -> void:
	_test_catalogue()
	_test_mark_scaling()
	_test_range_and_falloff()
	_test_bases_change_the_build()
	_test_pierce_and_bounce_split()
	_test_splitter_and_explosive()
	_test_tier_scaling()
	_test_every_base_every_mark()
	_test_sampled_builds()
	_test_descriptions()


func _test_catalogue() -> void:
	var bases := Items.all_attachments()
	check(bases.size() == Items.BASE_IDS.size() and bases.size() == 33, "thirty-three authored bases load (%d)" % bases.size())
	var expected := {&"receiver": 4, &"barrel": 4, &"muzzle": 4, &"magazine": 5, &"ammo": 7, &"optic": 4, &"underbarrel": 5}
	for slot in expected:
		var default := Items.default_for_slot(slot)
		check(default != null and default.is_default and default.modifiers.is_empty(), "%s has a default base with no modifiers" % slot)
		check(Items.bases_for_slot(slot).size() == int(expected[slot]) and Items.slot_has_bases(slot),
			"%s has %d non-default bases (%d)" % [slot, int(expected[slot]) - 1, Items.bases_for_slot(slot).size() - 1])
	check(not Items.slot_has_bases(&"relic"), "the relic slot has no bases yet (Milestone 8)")
	check(Items.drop_affixes().size() == 11 and Items.all_affixes().size() == 11, "all eleven affixes are in the drop pool (%d / %d)" % [Items.drop_affixes().size(), Items.all_affixes().size()])
	var dropping := []
	for affix in Items.drop_affixes():
		dropping.append(String(affix.id))
	check(dropping.has("lingering") and dropping.has("precise"), "the status affix drops now that statuses exist")
	check(Items.legendary_bases().size() == 6, "six bases carry a Legendary (%d)" % Items.legendary_bases().size())
	var legendary_slots := {}
	for base in Items.legendary_bases():
		legendary_slots[String(base.slot)] = true
	check(legendary_slots.size() == 6 and not legendary_slots.has("relic"), "the six Legendaries sit in six different slots, none the relic (%s)" % str(legendary_slots.keys()))
	check(Items.get_attachment(&"explosive_rounds").behaviours.get("projectile") == "shell" and Items.get_attachment(&"ricochet_rounds").behaviours.get("projectile") == "ricochet",
		"Explosive and Ricochet rounds fire on the shared projectile system")
	check(Items.get_attachment(&"automatic").unlock_wave == 5 and Items.get_attachment(&"burst").unlock_flag == "foundry"
		and Items.get_attachment(&"charge").unlock_flag == "signal_tower" and Items.get_attachment(&"overflow").unlock_flag == "signal_tower_top",
		"gated bases carry their gates: Automatic the Warden, Burst the Foundry, Charge the Signal Tower, Overflow its top")


func _test_mark_scaling() -> void:
	var long_barrel := Items.get_attachment(&"long_barrel")
	var mark_one := _modifier_map(long_barrel.modifiers_at_mark(1))
	var mark_five := _modifier_map(long_barrel.modifiers_at_mark(5))
	check(is_equal_approx(mark_one["damage"], 0.15) and is_equal_approx(mark_one["fire_rate"], -0.15), "mark I uses the authored values")
	check(is_equal_approx(mark_five["damage"], 0.15 * 1.6), "mark V strengthens the upside (%.3f)" % mark_five["damage"])
	check(is_equal_approx(mark_five["fire_rate"], -0.15 * 0.4), "mark V softens the cost (%.3f)" % mark_five["fire_rate"])
	var item_one := Items.make(&"long_barrel", Items.Rarity.COMMON, [], 1)
	var item_five := Items.make(&"long_barrel", Items.Rarity.COMMON, [], 5)
	var base: WeaponBaseStats = Progression.PISTOL_BASE
	var one := WeaponStats.build(base, {}, {"barrel": item_one})
	var five := WeaponStats.build(base, {}, {"barrel": item_five})
	check(five.damage > one.damage and five.fire_rate > one.fire_rate, "a mark V item beats its mark I on both sides of the trade")


func _test_range_and_falloff() -> void:
	var base: WeaponBaseStats = Progression.PISTOL_BASE
	var plain := WeaponStats.build(base)
	check(is_equal_approx(WeaponStats.falloff_multiplier(plain, 10.0), 1.0), "damage is full inside falloff start")
	check(is_equal_approx(WeaponStats.falloff_multiplier(plain, 32.5), 0.8), "damage falls linearly between start and end (%.2f)" % WeaponStats.falloff_multiplier(plain, 32.5))
	check(is_equal_approx(WeaponStats.falloff_multiplier(plain, 60.0), 0.6), "damage floors at the falloff floor")
	check(is_equal_approx(WeaponStats.expected_damage_at(plain, 45.0), 6.0), "expected damage applies falloff (%.1f at 45 m)" % WeaponStats.expected_damage_at(plain, 45.0))
	var long_item := Items.make(&"long_barrel")
	var long := WeaponStats.build(base, {}, {"barrel": long_item})
	check(is_equal_approx(long.falloff_start, 27.0) and is_equal_approx(long.falloff_end, 60.75), "range stat pushes falloff out (%.1f to %.1f m)" % [long.falloff_start, long.falloff_end])
	check(WeaponStats.expected_damage_at(long, 40.0) > WeaponStats.expected_damage_at(plain, 40.0) * 1.3, "long barrel hits much harder at 40 m")
	check(is_equal_approx(long.fire_rate, 4.0 * 0.85), "long barrel's fire rate cost applies")


func _test_bases_change_the_build() -> void:
	var base: WeaponBaseStats = Progression.PISTOL_BASE
	var auto := WeaponStats.build(base, {}, {"receiver": Items.make(&"automatic")})
	check(auto.fire_mode() == "auto" and is_equal_approx(auto.recoil_kick_degrees, 1.5) and is_equal_approx(auto.damage, 9.2), "automatic: hold to fire, more recoil, softer rounds")
	var burst := WeaponStats.build(base, {}, {"receiver": Items.make(&"burst")})
	check(burst.fire_mode() == "burst" and int(burst.behaviours["burst_size"]) == 3 and is_equal_approx(burst.damage, 11.5), "burst: three rounds that hit harder")
	var penetrator := WeaponStats.build(base, {}, {"barrel": Items.make(&"penetrator_barrel")})
	check(penetrator.pierce() == 2 and is_equal_approx(penetrator.damage, 9.0), "penetrator: pierces two, softer rounds")
	var pierce_affix := Items.make(&"penetrator_barrel", Items.Rarity.RARE, [{"id": "piercing", "roll": 1.0}])
	check(WeaponStats.build(base, {}, {"barrel": pierce_affix}).pierce() == 3, "Piercing affix adds to the barrel's pierce")
	var pierce_cap := Items.make(&"penetrator_barrel", Items.Rarity.LEGENDARY, [{"id": "piercing", "roll": 1.0}], 5)
	var skills := {"modifiers": [StatModifier.make(&"extra_pierce", 3.0)]}
	check(WeaponStats.build(base, {}, {"barrel": pierce_cap}, skills).pierce() == WeaponStats.PIERCE_CAP, "pierce never exceeds the cap")
	var extended := WeaponStats.build(base, {}, {"magazine": Items.make(&"extended_magazine")})
	check(extended.magazine_size == 15 and is_equal_approx(extended.reload_time, 1.4 / 0.8), "extended magazine: more rounds, slower change (%d, %.2f s)" % [extended.magazine_size, extended.reload_time])
	var fast := WeaponStats.build(base, {}, {"magazine": Items.make(&"fast_magazine")})
	check(fast.magazine_size == 8 and is_equal_approx(fast.reload_time, 1.4 / 1.3), "fast-mag: fewer rounds, faster change (%d, %.2f s)" % [fast.magazine_size, fast.reload_time])
	var defaults := WeaponStats.build(base, {}, {"receiver": Items.make(&"semi_auto"), "barrel": Items.make(&"standard_barrel"), "magazine": Items.make(&"standard_magazine")})
	check(is_equal_approx(defaults.damage, 10.0) and defaults.fire_mode() == "semi" and defaults.pierce() == 0, "default bases equal an empty gunsmith")
	var ordered := WeaponStats.build(base, {}, {"magazine": Items.make(&"extended_magazine"), "receiver": Items.make(&"burst")})
	var reversed := WeaponStats.build(base, {}, {"receiver": Items.make(&"burst"), "magazine": Items.make(&"extended_magazine")})
	check(ordered.fire_mode() == reversed.fire_mode() and ordered.magazine_size == reversed.magazine_size, "behaviours merge in slot order whatever the save's dictionary order")
	var summary := "  ".join(burst.describe_behaviours())
	check("3-round burst" in summary, "behaviour summary names the burst (%s)" % summary)


func _test_pierce_and_bounce_split() -> void:
	var stats := WeaponStats.build(Progression.PISTOL_BASE, {"damage": 5})
	var generator := TestCase.rng(1)
	var context := WeaponStats.ShotContext.new()
	context.pierce_index = 1
	check(is_equal_approx(WeaponStats.resolve_shot(stats, context, generator).damage, 15.0), "the first pierced enemy takes a quarter less")
	context.pierce_index = 2
	check(is_equal_approx(WeaponStats.resolve_shot(stats, context, generator).damage, 20.0 * 0.75 * 0.75), "each further pierced enemy takes a quarter less again")
	context.pierce_index = 0
	context.bounce_index = 1
	check(is_equal_approx(WeaponStats.resolve_shot(stats, context, generator).damage, 16.0), "a bounce keeps 80 percent")


## Plan: Splitter divides one shot across its rays for 125% in total; Explosive deals 60% on the hit
## and 60% in the blast, which never crits.
func _test_splitter_and_explosive() -> void:
	var base: WeaponBaseStats = Progression.PISTOL_BASE
	var plain := WeaponStats.build(base)
	var splitter := WeaponStats.build(base, {}, {"muzzle": Items.make(&"splitter")})
	check(int(splitter.behaviours["ray_count"]) == 3 and is_equal_approx(WeaponStats.ray_share(splitter), 1.25 / 3.0), "the Splitter fires three rays of 125/3 percent each")
	var context := WeaponStats.ShotContext.new()
	var one_ray := WeaponStats.resolve_shot(splitter, context, TestCase.rng(1))
	check(is_equal_approx(one_ray.damage, splitter.damage * 1.25 / 3.0), "one Splitter ray deals its share (%.2f)" % one_ray.damage)
	check(is_equal_approx(WeaponStats.expected_damage_at(splitter, 5.0), WeaponStats.expected_damage_at(plain, 5.0) * 1.25),
		"up close the bench's per-pull damage shows all three rays together: 125 percent of one shot (%.2f)" % WeaponStats.expected_damage_at(splitter, 5.0))
	var share := WeaponStats.ray_hit_share(splitter, 10.0)
	check(share < 0.5 and is_equal_approx(WeaponStats.expected_damage_at(splitter, 10.0), WeaponStats.expected_damage_at(plain, 10.0) * 1.25 * share),
		"at 10 m the spread costs the Splitter rays, so the readout drops below a plain shot (%.0f%% of rays land)" % (share * 100.0))
	var explosive := WeaponStats.build(base, {}, {"ammo": Items.make(&"explosive_rounds")})
	var direct := WeaponStats.resolve_shot(explosive, context, TestCase.rng(1))
	check(is_equal_approx(explosive.blast_radius(), 2.5) and is_equal_approx(direct.damage, explosive.damage * 0.6), "an explosive round's direct hit deals 60 percent (%.2f)" % direct.damage)
	check(is_equal_approx(WeaponStats.blast_damage(explosive, 10.0), explosive.damage * 0.6), "its blast deals 60 percent to everything in the radius")
	check(is_equal_approx(WeaponStats.expected_damage_at(explosive, 10.0), explosive.damage * 1.2), "the direct target takes the hit and the blast: 120 percent")
	var keen := WeaponStats.build(base, {}, {"ammo": Items.make(&"explosive_rounds", Items.Rarity.EPIC, [{"id": "keen", "roll": 1.0}, {"id": "brutal", "roll": 1.0}])})
	check(keen.crit_chance > 0.0 and is_equal_approx(WeaponStats.blast_damage(keen, 10.0), keen.damage * 0.6), "a blast never crits, whatever the build's crit")
	check(is_zero_approx(WeaponStats.blast_damage(plain, 10.0)), "rounds without blast radius make no blast")
	var both := WeaponStats.build(base, {}, {"muzzle": Items.make(&"splitter"), "ammo": Items.make(&"explosive_rounds")})
	check(is_equal_approx(WeaponStats.blast_damage(both, 5.0), both.damage * 0.6 * 1.25 / 3.0), "a Splitter's explosive rays each blast for their share")
	var weak := WeaponStats.build(base, {}, {"barrel": Items.make(&"long_barrel", Items.Rarity.UNCOMMON, [{"id": "precise", "roll": 1.0}])})
	check(is_equal_approx(weak.weak_point_bonus(), 1.2), "the Precise affix raises weak-point damage (x%.2f)" % weak.weak_point_bonus())


func _test_tier_scaling() -> void:
	var base: WeaponBaseStats = Progression.PISTOL_BASE
	var tier_zero := WeaponStats.build(base, {"damage": 3, "fire_rate": 2})
	var tier_one := WeaponStats.build(base, {"damage": 3, "fire_rate": 2}, {}, {}, {}, 1)
	check(is_equal_approx(tier_zero.damage, 16.0) and is_equal_approx(tier_one.damage, 10.0 + 3.0 * 2.0 * WeaponStats.REFORGE_STEP), "core damage per level scales with the Reforge tier (%.1f)" % tier_one.damage)
	check(is_equal_approx(tier_one.fire_rate, tier_zero.fire_rate), "percentage stats do not scale with the tier")
	check(tier_one.tier == 1, "the build remembers its tier")


## The boundary sweep (plan: Milestone 5 verification): every base at every mark, as an Epic and,
## where it has one, as its Legendary, with every affix at its lowest and highest roll, against no
## core levels and maxed ones, no skills and every skill, at Reforge tiers 0 and 3; each build is
## then fired in the extreme shot contexts (point blank and far past falloff, full and empty
## charge, full and nearly dead player, armoured target at 1% health, forced crit).
func _test_every_base_every_mark() -> void:
	var base: WeaponBaseStats = Progression.PISTOL_BASE
	var ok := true
	var count := 0
	var all_skills := {}
	for node in Skills.all():
		all_skills[String(node.id)] = 1
	var maxed := {}
	for tuning in CoreTuning.all():
		maxed[String(tuning.id)] = 60
	var affix_sets := []
	for roll in [0.0, 1.0]:
		var rolled := []
		for affix in Items.drop_affixes():
			rolled.append({"id": String(affix.id), "roll": roll})
		affix_sets.append(rolled)
	var contexts := _extreme_contexts()
	var generator := TestCase.rng(15)
	for definition in Items.all_attachments():
		for mark in range(Items.MIN_MARK, Items.MAX_MARK + 1):
			for rarity in ([Items.Rarity.EPIC, Items.Rarity.LEGENDARY] if definition.has_legendary() else [Items.Rarity.EPIC]):
				for rolled in affix_sets:
					for levels in [{}, maxed]:
						for skills in [{}, all_skills]:
							for tier in [0, 3]:
								var item := Items.make(definition.id, rarity, rolled.slice(0, 3), mark)
								var stats := WeaponStats.build(base, levels, {String(definition.slot): item}, skills, {}, tier)
								ok = ok and _within_limits(stats, base)
								for context in contexts:
									var shot := WeaponStats.resolve_shot(stats, context, generator)
									ok = ok and is_finite(shot.damage) and shot.damage >= 0.0
								ok = ok and is_finite(stats.sustained_dps()) and stats.sustained_dps() >= 0.0
								ok = ok and is_finite(WeaponStats.blast_damage(stats, 30.0, 1.0)) and stats.rounds_per_magazine() >= 1.0
								count += 1
	check(ok and count > Items.BASE_IDS.size() * 5 * 16, "boundary sweep: every base, mark, rarity, affix extreme, core, skill and tier corner stays finite and inside the caps (%d builds)" % count)


func _extreme_contexts() -> Array[WeaponStats.ShotContext]:
	var contexts: Array[WeaponStats.ShotContext] = []
	for distance in [0.0, 400.0]:
		for charge in [0.0, 1.0]:
			for health in [1.0, 0.01]:
				var context := WeaponStats.ShotContext.new()
				context.distance = distance
				context.charge = charge
				context.player_health_fraction = health
				context.target_health_fraction = 0.01
				context.target_armored = true
				context.force_crit = health < 0.5
				context.overclock_active = charge > 0.5
				context.pierce_index = 5
				context.bounce_index = 3
				contexts.append(context)
	return contexts


## 10,000 sampled builds (plan: Milestone 5 verification): random core levels, a random base in
## every slot at a random rarity, mark and affix rolls, a random set of real skill nodes and a
## Reforge tier, each fired once in a random context.
func _test_sampled_builds() -> void:
	var base: WeaponBaseStats = Progression.PISTOL_BASE
	var generator := TestCase.rng(2026)
	var affixes := Items.drop_affixes()
	var skill_ids := []
	for node in Skills.all():
		skill_ids.append(String(node.id))
	var ok := true
	var worst_fire_rate := 0.0
	for i in SAMPLE_BUILDS:
		var levels := {}
		for tuning in CoreTuning.all():
			levels[String(tuning.id)] = generator.randi_range(0, 60)
		var equipped := {}
		for slot in [&"receiver", &"barrel", &"muzzle", &"magazine", &"ammo", &"optic", &"underbarrel"]:
			if generator.randf() < 0.8:
				var choices := Items.bases_for_slot(slot)
				var definition: AttachmentDefinition = choices[generator.randi_range(0, choices.size() - 1)]
				var rarity := generator.randi_range(0, Items.Rarity.LEGENDARY)
				var rolled: Array = []
				var pool := affixes.duplicate()
				for n in Items.AFFIX_COUNT[rarity]:
					var index := generator.randi_range(0, pool.size() - 1)
					rolled.append({"id": String(pool[index].id), "roll": generator.randf()})
					pool.remove_at(index)
				equipped[String(slot)] = Items.make(definition.id, rarity, rolled, generator.randi_range(1, 5))
		var skills := {}
		for id in skill_ids:
			if generator.randf() < 0.4:
				skills[id] = 1
		var stats := WeaponStats.build(base, levels, equipped, skills, {}, generator.randi_range(0, 3))
		ok = ok and _within_limits(stats, base)
		worst_fire_rate = maxf(worst_fire_rate, stats.fire_rate)
		var context := WeaponStats.ShotContext.new()
		context.distance = generator.randf() * 120.0
		context.charge = generator.randf()
		context.player_health_fraction = generator.randf()
		context.target_health_fraction = generator.randf()
		context.target_armored = generator.randf() < 0.5
		var shot := WeaponStats.resolve_shot(stats, context, generator)
		ok = ok and is_finite(shot.damage) and shot.damage >= 0.0 and is_finite(stats.sustained_dps())
	check(ok, "%d random full builds (seven slots, skills, tiers) stay finite and inside the caps" % SAMPLE_BUILDS)
	check(worst_fire_rate <= WeaponStats.ABSOLUTE_FIRE_RATE_CAP, "no sampled build beats the fire-rate cap (%.2f)" % worst_fire_rate)


func _within_limits(stats: WeaponStats, base: WeaponBaseStats) -> bool:
	return is_finite(stats.damage) and stats.damage >= 0.0 \
		and stats.fire_rate <= WeaponStats.ABSOLUTE_FIRE_RATE_CAP + 0.0001 and stats.fire_rate >= 0.1 \
		and stats.magazine_size >= 1 and stats.reload_time >= base.min_reload_time - 0.0001 \
		and stats.crit_chance <= WeaponStats.CRIT_CHANCE_CAP + 0.0001 and stats.crit_multiplier >= 1.0 \
		and stats.pierce() <= WeaponStats.PIERCE_CAP and int(stats.behaviours["ray_count"]) <= WeaponStats.RAY_CAP \
		and int(stats.behaviours["bounces"]) <= WeaponStats.BOUNCE_CAP and stats.recoil_kick_degrees >= 0.0 \
		and stats.falloff_end > stats.falloff_start and stats.max_range >= stats.falloff_end


func _test_descriptions() -> void:
	check(Items.describe_modifier(StatModifier.make(&"damage", 0.0, 0.15)) == "+15% damage", "percent modifiers describe themselves")
	check(Items.describe_modifier(StatModifier.make(&"magazine", 2.0)) == "+2 rounds", "flat modifiers describe themselves")
	check(Items.describe_modifier(StatModifier.make(&"extra_pierce", 1.0)) == "+1 pierce", "extra keys describe themselves")
	var item := Items.make(&"long_barrel", Items.Rarity.RARE, [{"id": "sharp", "roll": 1.0}, {"id": "thrifty", "roll": 0.0}])
	var lines := Items.affix_lines(item)
	check(lines.size() == 2 and lines[0] == "Sharp: +12% damage" and "refunds" in lines[1], "affix lines name the affix and its rolled value (%s)" % ", ".join(lines))
	var items := [Items.make(&"extended_magazine", Items.Rarity.COMMON), Items.make(&"long_barrel", Items.Rarity.COMMON),
		Items.make(&"long_barrel", Items.Rarity.RARE), Items.make(&"automatic", Items.Rarity.UNCOMMON)]
	var sorted := Items.sort_items(items)
	check(sorted[0]["base"] == "automatic" and sorted[1]["rarity"] == Items.Rarity.RARE and sorted[3]["base"] == "extended_magazine", "items sort by slot, then rarity high to low")
	var parts := Items.parts_for_rarity(Items.Rarity.RARE)
	check(parts.get("circuits", 0) == 1 and parts.get("alloy", 0) == 1 and not parts.has("scrap"), "a Rare dismantles into Circuits and Alloy")
	check(Items.parts_for_rarity(Items.Rarity.COMMON) == {"scrap": 1}, "a Common dismantles into Scrap")


static func _modifier_map(modifiers: Array[StatModifier]) -> Dictionary:
	var result := {}
	for modifier in modifiers:
		result[String(modifier.stat)] = modifier.percent if modifier.percent != 0.0 else modifier.flat
	return result
