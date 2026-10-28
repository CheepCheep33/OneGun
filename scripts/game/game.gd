extends Node3D
## Wires the player, spawner, HUD, and pause menu together, and owns pause, death, and restart.
## Restart reloads the whole scene, so no enemy, effect, or weapon state can survive into the next attempt.

var kills := 0

@onready var arena: Node3D = $Arena
@onready var player: Player = $Player
@onready var spawner: EnemySpawner = $EnemySpawner
@onready var hud: Hud = $HUD
@onready var pause_menu: PauseMenu = $PauseMenu


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
	spawner.enemy_killed.connect(_on_enemy_killed)
	hud.restart_requested.connect(restart)
	pause_menu.resume_requested.connect(resume)
	pause_menu.restart_requested.connect(restart)
	pause_menu.quit_requested.connect(get_tree().quit)

	hud.set_health(player.health, player.max_health)
	hud.set_ammo(player.pistol.ammo, player.pistol.stats.magazine_size)
	hud.set_kills(kills)
	_capture_mouse()
	spawner.start(player, arena)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not player.is_dead:
		pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reload") and player.is_dead:
		restart()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not player.is_dead \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_capture_mouse()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# Losing window focus releases the mouse; pause so the player doesn't die while tabbed out.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready() and not player.is_dead \
			and not get_tree().paused:
		pause()


func pause() -> void:
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_menu.open()


func resume() -> void:
	pause_menu.close()
	Settings.save_settings()
	get_tree().paused = false
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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_death(kills)


func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
