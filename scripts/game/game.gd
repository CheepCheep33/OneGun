extends Node3D
## Wires the player, spawner, HUD, and pause menu together, and owns pause, death, and restart.
## Restart reloads the whole scene, so no enemy, effect, or weapon state can survive into the next attempt.

var kills := 0
## Becomes true once the player can control the game: the mouse is captured or touch controls are on.
## Browsers only allow capture after a click, so until then the HUD asks for one instead of
## treating the free mouse as a pause.
var _had_control := false
## Enemies start spawning once the player has control, so nothing attacks while waiting for that click.
var _combat_started := false

@onready var arena: Node3D = $Arena
@onready var player: Player = $Player
@onready var spawner: EnemySpawner = $EnemySpawner
@onready var hud: Hud = $HUD
@onready var pause_menu: PauseMenu = $PauseMenu
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
	spawner.setup(player, arena)
	spawner.enemy_killed.connect(_on_enemy_killed)
	hud.restart_requested.connect(restart)
	pause_menu.resume_requested.connect(resume)
	pause_menu.restart_requested.connect(restart)
	pause_menu.quit_requested.connect(get_tree().quit)
	touch_controls.setup(player)
	touch_controls.activated.connect(_on_touch_activated)
	touch_controls.pause_requested.connect(pause)

	hud.set_health(player.health, player.max_health)
	hud.set_ammo(player.pistol.ammo, player.pistol.stats.magazine_size)
	hud.set_kills(kills)
	_capture_mouse()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not player.is_dead:
		pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reload") and player.is_dead:
		restart()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not player.is_dead \
			and not touch_controls.active and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_capture_mouse()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var has_control := touch_controls.active or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_had_control = _had_control or has_control
	if has_control and not _combat_started:
		_combat_started = true
		spawner.start()
	hud.set_capture_prompt_visible(not has_control and not _had_control and not player.is_dead)
	# Browsers release the mouse on Esc without sending the key to the game; treat any lost capture as a pause.
	if _had_control and not has_control and not player.is_dead:
		pause()


func _notification(what: int) -> void:
	# Losing window focus releases the mouse; pause so the player doesn't die while tabbed out.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready() and not player.is_dead \
			and not get_tree().paused:
		pause()


func pause() -> void:
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


func restart() -> void:
	Settings.save_settings()
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_enemy_killed(_enemy: Chaser) -> void:
	kills += 1
	hud.set_kills(kills)


func _on_player_died() -> void:
	spawner.stop()
	touch_controls.set_enabled(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_death(kills)


func _on_touch_activated() -> void:
	# Touch screens have no mouse to capture; taps also arrive as emulated clicks, which must not fire.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.set_mouse_input_enabled(false)
	hud.set_controls_hint("Left thumb: move (push to edge to sprint)   Drag right side: look")


func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
