extends Node3D
## Runs the loop: bench (intermission) -> wave -> cleared or dead -> bench. Owns pause and the
## mouse. Progression (autoload) owns everything that outlives a wave; the bench is the only place
## the save is written. Starting a wave resets the encounter in place: enemies cleared, player and
## pistol rebuilt from the current build stats.

enum State { BENCH, COMBAT, CLEARED, DEAD }

## How long the "wave cleared" banner stays before the bench opens.
const CLEARED_BANNER_TIME := 2.2

var state := State.BENCH
var current_wave := 0
## Kills this wave, shown on the HUD and the death screen.
var kills := 0
## Becomes true once the player can control the game: the mouse is captured or touch controls are on.
## Browsers only allow capture after a click, so until then the HUD asks for one instead of
## treating the free mouse as a pause.
var _had_control := false
## Enemies start spawning once the player has control, so nothing attacks while waiting for that click.
var _combat_started := false
var _pending_wave: WaveDefinition

@onready var arena: Node3D = $Arena
@onready var player: Player = $Player
@onready var wave_runner: WaveRunner = $WaveRunner
@onready var hud: Hud = $HUD
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var bench: Bench = $Bench
@onready var touch_controls: TouchControls = $TouchControls


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
	hud.bench_requested.connect(open_bench)
	pause_menu.resume_requested.connect(resume)
	pause_menu.abandon_requested.connect(abandon_wave)
	pause_menu.quit_requested.connect(get_tree().quit)
	bench.start_wave_requested.connect(start_wave)
	touch_controls.setup(player)
	touch_controls.activated.connect(_on_touch_activated)
	touch_controls.pause_requested.connect(pause)
	Progression.credits_changed.connect(hud.set_credits)

	hud.set_health(player.health, player.max_health)
	hud.set_ammo(player.pistol.ammo, player.pistol.stats.magazine_size)
	hud.set_kills(kills)
	hud.set_credits(Progression.credits)
	open_bench()


func _unhandled_input(event: InputEvent) -> void:
	match state:
		State.COMBAT, State.CLEARED:
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
	if state != State.COMBAT and state != State.CLEARED:
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


func _notification(what: int) -> void:
	# Losing window focus releases the mouse; pause so the player doesn't die while tabbed out.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready() and state == State.COMBAT \
			and not get_tree().paused:
		pause()


# ------------------------------------------------------------------ bench

## Stops any combat, saves, and shows the bench. The tree stays paused while it is open.
func open_bench() -> void:
	state = State.BENCH
	_pending_wave = null
	wave_runner.stop()
	wave_runner.clear_enemies()
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
	if touch_controls.active:
		_had_control = true
	else:
		_had_control = false
		_capture_mouse()


## Clears leftovers and rebuilds the player and pistol from the current build (plan: starting any
## encounter resets it).
func _reset_encounter() -> void:
	wave_runner.clear_enemies()
	player.revive(arena.get_player_start())
	player.pistol.apply_stats(Progression.build_stats())
	hud.set_health(player.health, player.max_health)


# ------------------------------------------------------------------ pause

func pause() -> void:
	if state != State.COMBAT and state != State.CLEARED:
		return
	get_tree().paused = true
	touch_controls.release_all()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_menu.open()


func resume() -> void:
	pause_menu.close()
	Settings.save_settings()
	get_tree().paused = false
	if not touch_controls.active:
		_had_control = false # Wait for the capture to take effect before watching for its loss again.
		_capture_mouse()


## Leaves the wave from the pause menu: kill credits are kept, no completion bonus (plan: same as death).
func abandon_wave() -> void:
	Settings.save_settings()
	if state == State.COMBAT:
		PlaytestLog.event("abandon", {"wave": current_wave, "seconds": "%.1f" % wave_runner.elapsed})
	open_bench()


# ------------------------------------------------------------------ combat events

func _on_enemy_killed(_enemy: Chaser, credits: int) -> void:
	kills += 1
	hud.set_kills(kills)
	Progression.record_kill(credits)
	hud.show_credit_gain(credits)


func _on_wave_cleared(wave: WaveDefinition, duration: float) -> void:
	if state != State.COMBAT:
		return
	state = State.CLEARED
	var bonus := wave.completion_bonus * (2 if wave.is_boss_wave else 1)
	var first := Progression.record_wave_cleared(wave.number, bonus, duration)
	hud.show_wave_cleared(wave.number, bonus, first)
	var timer := get_tree().create_timer(CLEARED_BANNER_TIME, false)
	await timer.timeout
	if state == State.CLEARED:
		open_bench()


func _on_player_died() -> void:
	state = State.DEAD
	wave_runner.stop()
	touch_controls.set_enabled(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Progression.record_death(current_wave, wave_runner.elapsed)
	hud.show_death(current_wave, kills, Progression.credits)


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
