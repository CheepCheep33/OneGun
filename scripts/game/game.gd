extends Node3D
## Runs the loop: bench (intermission) -> wave or side area -> cleared or dead -> bench. Owns pause
## and the mouse. Progression (autoload) owns everything that outlives a wave; the bench is the
## only place the save is written. Starting any encounter resets it in place: enemies, projectiles
## and floor loot cleared, player and pistol rebuilt from the current build.

enum State { BENCH, COMBAT, CLEARED, DEAD, AREA }

## How long the "wave cleared" banner stays before the bench opens.
const CLEARED_BANNER_TIME := 2.6
const MAIN_ARENA := preload("res://scenes/arena/arena.tscn")
const AREA_SCENES := {"firing_range": "res://scenes/areas/firing_range.tscn"}
const AREA_NAMES := {"firing_range": "Firing Range"}

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
var _boss: Enemy

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
	wave_runner.setup(player, arena)
	wave_runner.enemy_killed.connect(_on_enemy_killed)
	wave_runner.remaining_changed.connect(hud.set_wave_progress)
	wave_runner.wave_cleared.connect(_on_wave_cleared)
	wave_runner.boss_spawned.connect(_on_boss_spawned)
	hud.bench_requested.connect(open_bench)
	pause_menu.resume_requested.connect(resume)
	pause_menu.abandon_requested.connect(abandon_wave)
	pause_menu.quit_requested.connect(get_tree().quit)
	bench.start_wave_requested.connect(start_wave)
	bench.area_requested.connect(enter_area)
	touch_controls.setup(player)
	touch_controls.activated.connect(_on_touch_activated)
	touch_controls.pause_requested.connect(pause)
	Progression.credits_changed.connect(hud.set_credits)
	Progression.item_received.connect(_on_item_received)
	Settings.changed.connect(_apply_video_settings)
	_apply_video_settings()
	# Compile the effect, enemy and drop shaders behind the first bench, not in the first wave.
	Fx.warm_up(self, player.camera)

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
		wave_runner.start(_pending_wave, Progression.reward_multiplier(current_wave))
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
	wave_runner.stop()
	wave_runner.clear_enemies()
	projectiles.clear_all()
	_clear_drops()
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
	_pending_wave = wave
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
	if not AREA_SCENES.has(area_id) or not Progression.is_area_open(area_id):
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
	hud.set_wave_text(String(AREA_NAMES.get(area_id, area_id)).to_upper(), "Esc, then Leave, returns to the bench")
	hud.set_wave_progress_text(arena.status_text() if arena.has_method("status_text") else "")
	hud.set_combat_visible(true)
	touch_controls.set_enabled(true)
	PlaytestLog.event("area_entered", {"area": area_id})
	_take_control()


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
	player.revive(arena.get_player_start())
	player.pistol.apply_build(Progression.build_stats(), Progression.equipped())
	hud.set_health(player.health, player.max_health)


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
	if state != State.COMBAT:
		return
	# Drops commit the moment the enemy dies (plan: rewards paid once per source).
	var replay := Progression.is_wave_cleared(current_wave)
	var item := Progression.roll_kill_drop(enemy.definition, replay)
	if item.is_empty():
		return
	if enemy.definition.is_boss:
		# A boss killed just before the player dies still pays: its drop goes straight to the bench.
		Progression.add_item(item, "boss_%s" % enemy.definition.id)
	else:
		_spawn_drop(item, enemy.global_position)


func _spawn_drop(item: Dictionary, position: Vector3) -> void:
	var drop := LootDrop.create(item)
	drops.add_child(drop)
	drop.global_position = Vector3(position.x, maxf(position.y, 0.0), position.z)
	drop.picked_up.connect(_on_drop_picked_up)
	PlaytestLog.event("drop", {"base": item.get("base", ""), "rarity": item.get("rarity", 0), "wave": current_wave})


func _on_drop_picked_up(drop: LootDrop) -> void:
	Progression.add_item(drop.item, "pickup")


func _on_item_received(item: Dictionary, destination: String) -> void:
	hud.show_pickup(item, destination)


func _clear_drops() -> void:
	for drop in drops.get_children():
		drops.remove_child(drop)
		drop.queue_free()


func _on_wave_cleared(wave: WaveDefinition, duration: float) -> void:
	if state != State.COMBAT:
		return
	state = State.CLEARED
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
	var timer := get_tree().create_timer(CLEARED_BANNER_TIME, false)
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
	hud.show_death(current_wave, kills, Progression.credits)


func _on_boss_spawned(enemy: Enemy) -> void:
	_boss = enemy
	hud.show_boss(enemy.definition.display_name, enemy.health, enemy.max_health)
	enemy.health_changed.connect(hud.set_boss_health)
	enemy.tree_exited.connect(_clear_boss, CONNECT_ONE_SHOT)


func _clear_boss() -> void:
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
