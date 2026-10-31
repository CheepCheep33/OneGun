extends Node3D
## Runs the loop: bench (intermission) -> wave or side area -> cleared or dead -> bench. Owns pause
## and the mouse. Progression (autoload) owns everything that outlives a wave; the bench is the
## only place the save is written. Starting any encounter resets it in place: enemies, projectiles
## and floor loot cleared, player and pistol rebuilt from the current build.

enum State { BENCH, COMBAT, CLEARED, DEAD, AREA }

## How long the "wave cleared" banner stays before the bench opens.
const CLEARED_BANNER_TIME := 2.6
const MAIN_ARENA := preload("res://scenes/arena/arena.tscn")
const AREA_SCENES := {
	"firing_range": "res://scenes/areas/firing_range.tscn",
	"scrapyard": "res://scenes/areas/scrapyard.tscn",
	"foundry": "res://scenes/areas/foundry.tscn",
	"signal_tower": "res://scenes/areas/signal_tower.tscn",
}
const AREA_NAMES := {"firing_range": "Firing Range", "scrapyard": "Scrapyard", "foundry": "Foundry", "signal_tower": "Signal Tower"}
## First wave clears that also find an arena log (the story's found files).
const ARENA_LOG_WAVES := [12, 18]
const NOTE_COLOR := Color(0.6, 0.9, 1.0)
## Drop nodes kept ready outside the tree, so a drop landing mid-wave builds nothing.
const DROP_RESERVE := 12

var state := State.BENCH
var current_wave := 0
## "" while the main arena is loaded, otherwise the side area's id.
var current_area := ""
## Kills this wave, shown on the HUD and the death screen.
var kills := 0
## Becomes true once the player can control the game: the mouse is captured or touch controls are on.
## Browsers only allow capture after a click, so until then the HUD asks for one instead of
## treating the free mouse as a pause.
var _had_control := false
## Enemies start spawning once the player has control, so nothing attacks while waiting for that click.
var _combat_started := false
var _pending_wave: WaveDefinition
## Health and credit multiplier for the pending encounter: the wave's, or a side area's.
var _pending_scale := 1.0
var _pending_income := 1.0
var _boss: Enemy
var _drop_reserve: Array[LootDrop] = []
## Drops built by _spawn_drop because the reserve was empty (the performance gate expects zero).
var drop_reserve_misses := 0
## Story triggers fired before the current banner, so it can show the logs that just turned up.
var _story_mark := 0

@onready var arena: Node3D = $Arena
@onready var player: Player = $Player
@onready var wave_runner: WaveRunner = $WaveRunner
@onready var projectiles: ProjectilePool = $Projectiles
@onready var drops: Node3D = $Drops
@onready var hud: Hud = $HUD
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var bench: Bench = $Bench
@onready var touch_controls: TouchControls = $TouchControls
@onready var sun: DirectionalLight3D = $Sun
@onready var world_environment: WorldEnvironment = $WorldEnvironment


func _ready() -> void:
	get_tree().paused = false
	player.global_transform = arena.get_player_start()

	player.health_changed.connect(hud.set_health)
	player.damaged.connect(hud.flash_damage)
	player.died.connect(_on_player_died)
	player.pistol.ammo_changed.connect(hud.set_ammo)
	player.pistol.reload_started.connect(hud.show_reload)
	player.pistol.reload_finished.connect(hud.hide_reload)
	player.pistol.hit_landed.connect(hud.show_hit_marker)
	player.pistol.charge_changed.connect(hud.set_charge)
	player.pistol.status_changed.connect(hud.set_gun_status)
	player.pistol.scanned.connect(hud.set_scan)
	player.phoenix_triggered.connect(_on_phoenix)
	player.bullet_time_changed.connect(_on_bullet_time)
	Progression.level_up.connect(_on_level_up)
	wave_runner.enemy_spawned.connect(_on_enemy_spawned)
	wave_runner.setup(player, arena)
	wave_runner.enemy_killed.connect(_on_enemy_killed)
	wave_runner.remaining_changed.connect(_on_remaining_changed)
	wave_runner.wave_cleared.connect(_on_wave_cleared)
	wave_runner.boss_spawned.connect(_on_boss_spawned)
	hud.bench_requested.connect(open_bench)
	pause_menu.resume_requested.connect(resume)
	pause_menu.abandon_requested.connect(abandon_wave)
	pause_menu.quit_requested.connect(get_tree().quit)
	bench.start_wave_requested.connect(start_wave)
	bench.area_requested.connect(enter_area)
	bench.climb_requested.connect(climb)
	touch_controls.setup(player)
	touch_controls.activated.connect(_on_touch_activated)
	touch_controls.pause_requested.connect(pause)
	Progression.credits_changed.connect(hud.set_credits)
	Progression.item_received.connect(_on_item_received)
	Settings.changed.connect(_apply_video_settings)
	_apply_video_settings()
	# Compile the effect, enemy and drop shaders (lit by the muzzle light and unlit) and build the
	# enemy and drop reserves behind the first bench, not in the first wave (GAME_PLAN.md,
	# "Performance budget").
	Fx.warm_up(self, player.camera, player.pistol, hud)
	hud.warm_up_text()
	wave_runner.warm_up()
	_fill_drop_reserve()

	hud.set_health(player.health, player.max_health)
	hud.set_ammo(player.pistol.ammo, player.pistol.stats.magazine_size)
	hud.set_kills(kills)
	hud.set_credits(Progression.credits)
	open_bench()


func _unhandled_input(event: InputEvent) -> void:
	match state:
		State.COMBAT, State.CLEARED, State.AREA:
			if event.is_action_pressed("pause"):
				pause()
				get_viewport().set_input_as_handled()
			elif event is InputEventMouseButton and event.pressed and not touch_controls.active \
					and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				_capture_mouse()
				get_viewport().set_input_as_handled()
		State.DEAD:
			if event.is_action_pressed("reload"):
				open_bench()
				get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if state != State.COMBAT and state != State.CLEARED and state != State.AREA:
		return
	var has_control := _has_control()
	_had_control = _had_control or has_control
	if has_control and not _combat_started and _pending_wave:
		_combat_started = true
		# The Signal Tower starts its floors itself (floor_started), with their modifiers.
		if not arena.has_signal("floor_started"):
			wave_runner.start(_pending_wave, _pending_scale, _pending_income)
		if state == State.AREA and arena.has_method("start_run"):
			arena.start_run()
	hud.set_capture_prompt_visible(not has_control and not _had_control)
	# Browsers release the mouse on Esc without sending the key to the game; treat any lost capture as a pause.
	if _had_control and not has_control:
		pause()


## Render scale, shadows, glow and the FPS readout, from Settings (pause menu).
func _apply_video_settings() -> void:
	var viewport := get_viewport()
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = Settings.render_scale
	sun.shadow_enabled = Settings.shadows
	world_environment.environment.glow_enabled = Settings.glow
	hud.set_fps_visible(Settings.show_fps)


func _notification(what: int) -> void:
	# Losing window focus releases the mouse; pause so the player doesn't die while tabbed out.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready() \
			and (state == State.COMBAT or state == State.AREA) and not get_tree().paused:
		pause()


# ------------------------------------------------------------------ bench

## Stops any combat, returns to the main arena, saves, and shows the bench. The tree stays paused
## while it is open.
func open_bench() -> void:
	state = State.BENCH
	_pending_wave = null
	Engine.time_scale = 1.0
	_set_encounter_modifiers({})
	wave_runner.stop()
	wave_runner.clear_enemies()
	wave_runner.warm_up() # top the enemy reserve up while nothing is happening
	projectiles.clear_all()
	_clear_drops()
	_fill_drop_reserve()
	_clear_boss()
	if current_area != "":
		_swap_arena(MAIN_ARENA, "")
	pause_menu.close()
	get_tree().paused = true
	touch_controls.set_enabled(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.hide_death()
	hud.set_combat_visible(false)
	Progression.save()
	bench.open()


## Closes the bench and starts a wave. Called from the bench's button, which in a browser is the
## click that lets the game capture the mouse.
func start_wave(number: int) -> void:
	var wave := WaveRunner.load_wave(number)
	if wave == null or not Progression.is_wave_available(number):
		push_warning("Wave %d is not available." % number)
		return
	bench.close()
	if current_area != "":
		_swap_arena(MAIN_ARENA, "")
	current_wave = number
	kills = 0
	Progression.refresh_intermission()
	_pending_wave = wave
	_pending_scale = Progression.reward_multiplier(number)
	_pending_income = Progression.income_multiplier(number)
	_combat_started = false
	_reset_encounter()
	state = State.COMBAT
	get_tree().paused = false
	hud.set_kills(kills)
	hud.set_wave(number, wave.display_name)
	hud.set_wave_progress(wave.total_enemies(), wave.total_enemies())
	hud.set_combat_visible(true)
	touch_controls.set_enabled(true)
	PlaytestLog.event("wave_started", {"wave": number, "credits": Progression.credits})
	_take_control()


## Closes the bench and loads a side area in place of the arena (plan: scene swap for side areas).
func enter_area(area_id: String) -> void:
	if not AREA_SCENES.has(area_id) or Progression.area_block_reason(area_id) != "":
		push_warning("Area '%s' is not open." % area_id)
		return
	bench.close()
	_pending_wave = null
	_combat_started = false
	_swap_arena(load(AREA_SCENES[area_id]), area_id)
	_reset_encounter()
	state = State.AREA
	get_tree().paused = false
	if arena.has_method("setup"):
		arena.setup(player)
	if arena.has_signal("status_changed"):
		arena.status_changed.connect(hud.set_wave_progress_text)
	if arena.has_signal("extracted"):
		arena.extracted.connect(_on_area_extracted)
	if arena.has_signal("cleared"):
		arena.cleared.connect(_on_area_cleared)
	if arena.has_signal("floor_started"):
		arena.floor_started.connect(_on_floor_started)
	if arena.has_signal("pad_reached"):
		arena.pad_reached.connect(_on_pad_reached)
	# An area with a spawn schedule (the Scrapyard) runs it on the wave runner once the player has
	# control, scaled like the next wave the player would fight.
	if arena.has_method("encounter_wave"):
		current_wave = 0
		kills = 0
		hud.set_kills(kills)
		_pending_wave = arena.encounter_wave()
		var level := clampi(Progression.next_wave(), 1, WaveRunner.WAVE_COUNT)
		_pending_scale = Progression.reward_multiplier(level)
		_pending_income = Progression.income_multiplier(level)
	hud.set_wave_text(String(AREA_NAMES.get(area_id, area_id)).to_upper(), "Esc, then Leave, returns to the bench")
	hud.set_wave_progress_text(arena.status_text() if arena.has_method("status_text") else "")
	hud.set_combat_visible(true)
	touch_controls.set_enabled(true)
	PlaytestLog.event("area_entered", {"area": area_id})
	_take_control()
	Fx.warm_up_lighting(self, player.pistol) # the area's materials have not met the muzzle light


## Replaces the arena node (the main arena or a side area) and points everything at the new one.
func _swap_arena(scene: PackedScene, area_id: String) -> void:
	var old := arena
	var index := old.get_index()
	remove_child(old)
	old.queue_free()
	arena = scene.instantiate()
	arena.name = "Arena"
	add_child(arena)
	move_child(arena, index)
	current_area = area_id
	wave_runner.setup(player, arena)
	player.global_transform = arena.get_player_start()


## Clears leftovers and rebuilds the player and pistol from the current build (plan: starting any
## encounter resets it).
func _reset_encounter() -> void:
	wave_runner.clear_enemies()
	projectiles.clear_all()
	_clear_drops()
	_clear_boss()
	Engine.time_scale = 1.0
	_set_encounter_modifiers({})
	var effects := Progression.player_effects()
	player.apply_skills(effects)
	LootDrop.pickup_scale = 1.0 + float(effects.get("pickup_scale", 0.0))
	player.revive(arena.get_player_start())
	player.pistol.apply_build(Progression.build_stats(), Progression.equipped())
	hud.clear_scan_targets()
	hud.set_health(player.health, player.max_health)


## The Signal Tower's floor rules, or none ({}): robot speed and armour, no reloads, crits only.
func _set_encounter_modifiers(modifiers: Dictionary) -> void:
	wave_runner.set_modifiers(float(modifiers.get("speed", 1.0)), float(modifiers.get("armor", 0.0)))
	player.pistol.no_reloads = bool(modifiers.get("no_reloads", false))
	ShotPipeline.crits_only = bool(modifiers.get("crits_only", false))


func _take_control() -> void:
	if touch_controls.active:
		_had_control = true
	else:
		_had_control = false
		_capture_mouse()


# ------------------------------------------------------------------ pause

func pause() -> void:
	if state != State.COMBAT and state != State.CLEARED and state != State.AREA:
		return
	get_tree().paused = true
	touch_controls.release_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_menu.open("Leave the range" if state == State.AREA else "Abandon wave")


func resume() -> void:
	pause_menu.close()
	Settings.save_settings()
	get_tree().paused = false
	if not touch_controls.active:
		_had_control = false # Wait for the capture to take effect before watching for its loss again.
		_capture_mouse()


## Leaves the wave or area from the pause menu: kill credits and collected loot are kept, floor
## loot and the completion bonus are not (plan: same as death).
func abandon_wave() -> void:
	Settings.save_settings()
	if state == State.COMBAT:
		PlaytestLog.event("abandon", {"wave": current_wave, "seconds": "%.1f" % wave_runner.elapsed})
	elif state == State.AREA:
		PlaytestLog.event("area_left", {"area": current_area})
	open_bench()


# ------------------------------------------------------------------ combat events

func _on_enemy_killed(enemy: Enemy, credits: int) -> void:
	kills += 1
	hud.set_kills(kills)
	Progression.record_kill(credits)
	hud.show_credit_gain(credits)
	player.pistol.notify_kill()
	player.notify_kill()
	if enemy.definition.is_boss and Progression.record_boss_kill(enemy.definition.id):
		hud.show_note("Boss down: +1 skill point", NOTE_COLOR)
	# A boss's adds pay credits but drop nothing, so a boss fight cannot be farmed for loot.
	if enemy.summoned:
		return
	var in_salvage := state == State.AREA and _pending_wave != null
	if state != State.COMBAT and not in_salvage:
		return
	# Drops commit the moment the enemy dies (plan: rewards paid once per source). A side area's
	# kills drop like a replay (Common and Uncommon); its own reward is the Rare on extraction.
	var replay := in_salvage or Progression.is_wave_cleared(current_wave)
	var item := Progression.roll_kill_drop(enemy.definition, replay)
	if item.is_empty():
		return
	if enemy.definition.is_boss:
		# A boss killed just before the player dies still pays: its drop goes straight to the bench.
		Progression.add_item(item, "boss_%s" % enemy.definition.id)
	else:
		_spawn_drop(item, enemy.global_position)


func _spawn_drop(item: Dictionary, position: Vector3) -> void:
	var drop := _take_drop()
	drops.add_child(drop)
	drop.reset(item)
	drop.global_position = Vector3(position.x, maxf(position.y, 0.0), position.z)
	PlaytestLog.event("drop", {"base": item.get("base", ""), "rarity": item.get("rarity", 0), "wave": current_wave})


## A ready drop node from the reserve, or a new one when it is empty (counted as a miss).
func _take_drop() -> LootDrop:
	while not _drop_reserve.is_empty():
		var drop: LootDrop = _drop_reserve.pop_back()
		if is_instance_valid(drop):
			return drop
	drop_reserve_misses += 1
	return _make_drop()


func _make_drop() -> LootDrop:
	var drop := LootDrop.new()
	drop.picked_up.connect(_on_drop_picked_up)
	drop.retired.connect(_on_drop_retired)
	return drop


## Builds drop nodes up to DROP_RESERVE at the bench (each enters the tree once to pay its _ready),
## so no drop is built mid-wave.
func _fill_drop_reserve() -> void:
	while _drop_reserve.size() < DROP_RESERVE:
		var drop := _make_drop()
		drops.add_child(drop)
		drops.remove_child(drop)
		_drop_reserve.append(drop)


func drop_reserve_count() -> int:
	var count := 0
	for drop in _drop_reserve:
		if is_instance_valid(drop):
			count += 1
	return count


## A collected drop leaves the floor at the end of the frame (it is inside its own area signal).
func _on_drop_retired(drop: LootDrop) -> void:
	_recycle_drop.call_deferred(drop)


func _recycle_drop(drop: LootDrop) -> void:
	if not is_instance_valid(drop):
		return
	if drop.get_parent() != null:
		drop.get_parent().remove_child(drop)
	if _drop_reserve.size() >= DROP_RESERVE or _drop_reserve.has(drop):
		if not _drop_reserve.has(drop):
			drop.queue_free()
		return
	_drop_reserve.append(drop)


func _on_drop_picked_up(drop: LootDrop) -> void:
	Progression.add_item(drop.item, "pickup")


func _on_item_received(item: Dictionary, destination: String) -> void:
	hud.show_pickup(item, destination)


func _clear_drops() -> void:
	for drop in drops.get_children():
		if drop is LootDrop:
			_recycle_drop(drop)
		else:
			drops.remove_child(drop)
			drop.queue_free()


func _exit_tree() -> void:
	for drop in _drop_reserve:
		if is_instance_valid(drop):
			drop.free()
	_drop_reserve.clear()


## A side area's spawn schedule is not a wave to clear: its status line stays the area's own.
func _on_remaining_changed(remaining: int, total: int) -> void:
	if state != State.AREA:
		hud.set_wave_progress(remaining, total)


func _on_wave_cleared(wave: WaveDefinition, duration: float) -> void:
	if state == State.AREA:
		# A side area's schedule ran out of robots: the Foundry pays, the tower lights its pad.
		if arena.has_method("on_encounter_cleared"):
			var mark: int = Progression.data["story_flags"].size()
			arena.on_encounter_cleared(duration)
			var flags: Array = Progression.data["story_flags"]
			for i in range(mark, flags.size()):
				hud.queue_story(Story.lines_for(String(flags[i])))
		return
	if state != State.COMBAT:
		return
	state = State.CLEARED
	_story_mark = Progression.data["story_flags"].size()
	var bonus := roundi(wave.completion_bonus * (2 if wave.is_boss_wave else 1) * Progression.bonus_multiplier())
	var first := Progression.record_wave_cleared(wave.number, bonus, duration)
	# Success auto-collects whatever is still on the floor (plan: outcomes are explicit).
	for drop in drops.get_children():
		if drop is LootDrop:
			drop.collect()
	var granted := {}
	if first:
		granted = Progression.grant_item(Loot.FIRST_CLEAR_RARITY, &"", "first_clear_%d" % wave.number)
	hud.show_wave_cleared(wave.number, bonus, first, granted)
	# VERA's line for a first clear waits for the bench (its greeting); a log shows on the banner.
	var story_time := 0.0
	if first:
		Progression.fire_story("wave_%d" % wave.number)
		if wave.number in ARENA_LOG_WAVES:
			Progression.fire_story("log_arena_%d" % wave.number)
		var logs := _new_log_lines()
		if logs != "":
			hud.show_banner("WAVE %d CLEARED" % wave.number, hud.banner_detail() + "\n" + logs)
			story_time = 2.0
	var timer := get_tree().create_timer(CLEARED_BANNER_TIME + story_time, false)
	await timer.timeout
	if state == State.CLEARED:
		open_bench()


## The Scrapyard's door pad: the run pays its parts and Rare, the floor loot is collected and the
## bench opens after the banner (plan: side areas, outcomes are explicit).
func _on_area_extracted(cores: int, seconds: float) -> void:
	if state != State.AREA:
		return
	state = State.CLEARED
	wave_runner.stop()
	wave_runner.clear_enemies()
	projectiles.clear_all()
	for drop in drops.get_children():
		if drop is LootDrop:
			drop.collect()
	_story_mark = Progression.data["story_flags"].size()
	var result := Progression.record_scrapyard_extraction(cores, seconds)
	var lines := PackedStringArray(["%d scrap cores" % cores])
	var parts: Dictionary = result["parts"]
	if not parts.is_empty():
		lines[0] += "  ·  +" + Crafting.describe_cost(parts)
	var reward: Dictionary = result["reward"]
	if not reward.is_empty():
		lines.append("+ %s  ·  %s" % [Items.display_name(reward), Items.rarity_name(reward)])
	var logs := _new_log_lines()
	if logs != "":
		lines.append(logs)
	hud.show_banner("EXTRACTED", "\n".join(lines))
	var timer := get_tree().create_timer(CLEARED_BANNER_TIME + (2.0 if logs != "" else 0.0), false)
	await timer.timeout
	if state == State.CLEARED:
		open_bench()


func _on_player_died() -> void:
	state = State.DEAD
	wave_runner.stop()
	projectiles.clear_all()
	_clear_drops() # Floor loot is lost on death; everything picked up is kept.
	touch_controls.set_enabled(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Progression.record_death(current_wave, wave_runner.elapsed)
	Engine.time_scale = 1.0
	Progression.fire_story("first_death") # read at the bench
	if current_area != "":
		hud.show_death(current_wave, kills, Progression.credits, String(AREA_NAMES.get(current_area, current_area)))
	else:
		hud.show_death(current_wave, kills, Progression.credits)


func _on_boss_spawned(enemy: Enemy) -> void:
	_boss = enemy
	hud.show_boss(enemy.definition.display_name, enemy.health, enemy.max_health)
	# The intro card shows on the boss's first appearance only.
	hud.queue_story(Progression.fire_story("boss_%s" % enemy.definition.id))
	if enemy.has_signal("phase_changed") and not enemy.phase_changed.is_connected(_on_boss_phase_changed):
		enemy.phase_changed.connect(_on_boss_phase_changed)
	if not enemy.health_changed.is_connected(hud.set_boss_health):
		enemy.health_changed.connect(hud.set_boss_health)
	if not enemy.tree_exited.is_connected(_clear_boss):
		enemy.tree_exited.connect(_clear_boss, CONNECT_ONE_SHOT)


## Runs when the boss dies or the encounter resets (its node leaves the arena for the reserve).
func _clear_boss() -> void:
	if is_instance_valid(_boss) and _boss.health_changed.is_connected(hud.set_boss_health):
		_boss.health_changed.disconnect(hud.set_boss_health)
	_boss = null
	hud.hide_boss()


func _on_touch_activated() -> void:
	# Touch screens have no mouse to capture; taps also arrive as emulated clicks, which must not fire.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.set_mouse_input_enabled(false)
	hud.set_controls_hint("Left thumb: move (push to edge to sprint)   Drag right side: look")


func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## The player can play: touch controls are on or the mouse is captured. The headless server used by
## the smoke test has no mouse to capture, so it always counts as in control.
func _has_control() -> bool:
	return touch_controls.active or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
		or DisplayServer.get_name() == "headless"


# ------------------------------------------------------------------ Milestone 5 events

## Lines of the logs fired since _story_mark, for an area or wave banner ("" when none).
func _new_log_lines() -> String:
	var flags: Array = Progression.data["story_flags"]
	var texts := PackedStringArray()
	for i in range(_story_mark, flags.size()):
		if Story.is_log(String(flags[i])):
			texts.append(Story.describe(String(flags[i])))
	_story_mark = flags.size()
	return "\n".join(texts)


func _on_boss_phase_changed(index: int) -> void:
	hud.queue_story(Progression.fire_story("guardian_phase_%d" % (index + 1)))


func _on_enemy_spawned(enemy: Enemy) -> void:
	if enemy.definition.scanner_marked and bool(player.pistol.stats.behaviours.get("scanner", false)):
		hud.add_scan_target(player.camera, enemy)


func _on_level_up(level: int) -> void:
	if state != State.BENCH:
		hud.show_note("Level %d: +1 skill point" % level, NOTE_COLOR)


func _on_phoenix() -> void:
	hud.show_note("PHOENIX: back on your feet", Color(1.0, 0.6, 0.25))


func _on_bullet_time(active: bool) -> void:
	if active:
		hud.show_note("BULLET TIME", Color(0.7, 0.85, 1.0))


## A Signal Tower floor starts: its schedule on the wave runner with the floor's rules.
func _on_floor_started(wave: WaveDefinition, modifiers: Dictionary) -> void:
	if state != State.AREA:
		return
	_pending_wave = wave
	_set_encounter_modifiers(modifiers)
	wave_runner.start(wave, _pending_scale, _pending_income)


## Standing on a lit loadout pad opens the gunsmith in pad mode; the game waits there.
func _on_pad_reached(floor_number: int) -> void:
	if state != State.AREA:
		return
	get_tree().paused = true
	touch_controls.set_enabled(false)
	touch_controls.release_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.set_combat_visible(false)
	var next := floor_number + 1
	bench.open_pad(floor_number, "%s, %s" % [arena.floor_name(next), arena.floor_modifier_text(next)])


## Pad mode's Climb: the swapped build goes on the gun, and the next floor starts.
func climb() -> void:
	if state != State.AREA or not arena.has_method("start_floor"):
		return
	bench.close()
	Progression.save()
	player.pistol.apply_build(Progression.build_stats(), Progression.equipped())
	hud.clear_scan_targets()
	hud.set_combat_visible(true)
	touch_controls.set_enabled(true)
	get_tree().paused = false
	_take_control()
	arena.start_floor(arena.floor_number + 1)


## The Foundry's clear or the Signal Tower's top: the run pays, the floor loot is collected and
## the bench opens after the banner.
func _on_area_cleared(perfect: bool, seconds: float) -> void:
	if state != State.AREA:
		return
	state = State.CLEARED
	wave_runner.stop()
	wave_runner.clear_enemies()
	projectiles.clear_all()
	for drop in drops.get_children():
		if drop is LootDrop:
			drop.collect()
	_story_mark = Progression.data["story_flags"].size()
	var result: Dictionary
	var title := "CLEARED"
	if current_area == "foundry":
		result = Progression.record_foundry_clear(perfect, seconds)
		title = "FOUNDRY CLEARED" + ("  ·  UNTOUCHED" if perfect else "")
	else:
		result = Progression.record_tower_top(seconds)
		title = "TOP OF THE TOWER"
	var lines := PackedStringArray(["+" + Crafting.describe_cost(result["parts"])])
	for item in result["rewards"]:
		lines.append("+ %s  ·  %s" % [Items.display_name(item), Items.rarity_name(item)])
	var logs := _new_log_lines()
	if logs != "":
		lines.append(logs)
	hud.show_banner(title, "\n".join(lines))
	var timer := get_tree().create_timer(CLEARED_BANNER_TIME + (2.0 if logs != "" else 0.0), false)
	await timer.timeout
	if state == State.CLEARED:
		open_bench()
