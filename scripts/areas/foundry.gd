extends Node3D
## The Foundry side area (plan: Side areas): a heat room. Opens when the Foreman falls (wave 10),
## one attempt per intermission. Heavies and shield bearers in a tight room with four molten
## strips across the floor on a cycle: a strip glows its warning, then burns grounded players
## for a few seconds (a jump or a step off avoids it); only one or two burn at a time. Clearing
## the schedule pays cores, the Burst receiver on the first clear, an Epic on a run without
## damage (Progression.record_foundry_clear) and the Foundry's logs. The spawns run on the game's
## wave runner from data/areas/foundry_spawns.tres; the strips are part of the scene and only
## show, hide and test distances, so the hazard builds nothing and writes no material parameter.

signal status_changed(text: String)
## The schedule is cleared: the run pays. `perfect` is a run in which the player took no damage.
signal cleared(perfect: bool, seconds: float)

const SPAWNS := preload("res://data/areas/foundry_spawns.tres")
const HEAT_CYCLE := 12.0
const HEAT_WARNING := 1.5
const HEAT_BURN := 4.0
## Strip n starts its cycle this many seconds after strip n - 1.
const HEAT_STAGGER := 3.0
const HEAT_DAMAGE_PER_SECOND := 18.0
const HEAT_HALF_WIDTH := 10.0
const HEAT_HALF_DEPTH := 1.5
const HEAT_ESCAPE_HEIGHT := 0.5
## Frames every mesh is drawn before the strips hide, so their materials compile at load.
const SHOW_ALL_FRAMES := 2

var running := false
var elapsed := 0.0
var damaged := false
var finished := false

var _player: Player
var _strips: Array[Node3D] = []
var _show_all_left := SHOW_ALL_FRAMES

@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var _player_start: Marker3D = $PlayerStart


func _ready() -> void:
	_nav_region.bake_navigation_mesh(false)
	for strip in $Hazards.get_children():
		_strips.append(strip)


func setup(player: Player) -> void:
	_player = player
	if not player.damaged.is_connected(_on_player_damaged):
		player.damaged.connect(_on_player_damaged)
	Progression.record_foundry_run()


func get_player_start() -> Transform3D:
	return _player_start.global_transform


func get_spawn_points() -> Array[Marker3D]:
	var points: Array[Marker3D] = []
	for node in $SpawnPoints.get_children():
		if node is Marker3D:
			points.append(node)
	return points


func encounter_wave() -> WaveDefinition:
	return SPAWNS


func start_run() -> void:
	running = true
	elapsed = 0.0
	damaged = false
	status_changed.emit(status_text())


## The game forwards the wave runner's clear: the schedule is done.
func on_encounter_cleared(seconds: float) -> void:
	if finished:
		return
	finished = true
	running = false
	_hide_strips()
	status_changed.emit(status_text())
	cleared.emit(not damaged, seconds)


func status_text() -> String:
	if finished:
		return "Foundry cleared%s" % ("  ·  untouched" if not damaged else "")
	if not running:
		return "Clear the heat room; the floor strips glow before they burn"
	return "Heat room  ·  %s" % ("no damage taken" if not damaged else "damage taken")


## 0 idle, 1 warning, 2 burning, for a strip at the run's clock.
func strip_state(index: int) -> int:
	if not running:
		return 0
	var t := fposmod(elapsed - index * HEAT_STAGGER, HEAT_CYCLE)
	if elapsed < index * HEAT_STAGGER:
		return 0
	if t < HEAT_WARNING:
		return 1
	if t < HEAT_WARNING + HEAT_BURN:
		return 2
	return 0


func _process(_delta: float) -> void:
	if _show_all_left > 0:
		_show_all_left -= 1
		if _show_all_left == 0:
			_hide_strips()


func _physics_process(delta: float) -> void:
	if not running or finished or _player == null or _player.is_dead:
		return
	elapsed += delta
	for i in _strips.size():
		var state := strip_state(i)
		var strip := _strips[i]
		var warning: Node3D = strip.get_node("Warning")
		var molten: Node3D = strip.get_node("Molten")
		if warning.visible != (state == 1):
			warning.visible = state == 1
		if molten.visible != (state == 2):
			molten.visible = state == 2
		if state == 2 and _player_on_strip(strip):
			_player.take_damage(HEAT_DAMAGE_PER_SECOND * delta, Vector3.INF, true)


func _player_on_strip(strip: Node3D) -> bool:
	var offset := _player.global_position - strip.global_position
	return absf(offset.x) <= HEAT_HALF_WIDTH and absf(offset.z) <= HEAT_HALF_DEPTH \
		and _player.is_on_floor() and offset.y < HEAT_ESCAPE_HEIGHT


func _on_player_damaged(_amount: float) -> void:
	if running and not finished and not damaged:
		damaged = true
		status_changed.emit(status_text())


func _hide_strips() -> void:
	for strip in _strips:
		strip.get_node("Warning").visible = false
		strip.get_node("Molten").visible = false


func _exit_tree() -> void:
	if _player != null and is_instance_valid(_player) and _player.damaged.is_connected(_on_player_damaged):
		_player.damaged.disconnect(_on_player_damaged)
