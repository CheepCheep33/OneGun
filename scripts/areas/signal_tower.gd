extends Node3D
## The Signal Tower side area (plan: Side areas): a challenge ladder. Opens when the Sentinel falls
## (wave 15). Ten short floors, one modifier each (FLOORS), joined by a loadout pad: when a floor
## is cleared the pad lights, and standing on it opens the gunsmith for swaps only (no crafting or
## respec); Climb starts the next floor. The game runs each floor's schedule on its wave runner and
## applies the modifier (robot speed and armour, no reloads, crits only). Floor 5 cleared the
## first time opens the Charge receiver; the top pays an Epic, the Overflow magazine the first
## time and a Legendary core once per Reforge tier (Progression.record_tower_floor). One room
## stands in for every floor; the floors' schedules are built at load, never mid-run.

signal status_changed(text: String)
## A floor's schedule should start, with its modifiers (see FLOORS).
signal floor_started(wave: WaveDefinition, modifiers: Dictionary)
## The player stands on the lit pad after clearing `floor_number`.
signal pad_reached(floor_number: int)
## The top floor is cleared.
signal cleared(perfect: bool, seconds: float)

const FLOOR_COUNT := 10
const PAD_RADIUS := 1.6
const SHOW_ALL_FRAMES := 2
const SCENES := {
	"chaser": "res://scenes/enemies/chaser.tscn", "runner": "res://scenes/enemies/chaser.tscn",
	"shooter": "res://scenes/enemies/shooter.tscn", "heavy": "res://scenes/enemies/heavy.tscn",
	"shield_bearer": "res://scenes/enemies/shield_bearer.tscn", "swarm_drone": "res://scenes/enemies/swarm_drone.tscn",
	"turret": "res://scenes/enemies/turret.tscn",
}
## name, modifier text, modifiers {speed, armor, no_reloads, crits_only}, groups [id, count, interval, delay].
const FLOORS := [
	["Relay deck", "No modifier", {}, [["chaser", 6, 1.2, 1.0], ["shooter", 2, 3.0, 3.0]]],
	["Overdrive", "Robots move twice as fast", {"speed": 2.0}, [["chaser", 8, 1.0, 1.0]]],
	["Dry magazine", "No reloads: every kill fills the magazine", {"no_reloads": true}, [["chaser", 6, 1.0, 1.0], ["runner", 4, 1.0, 4.0]]],
	["Precision", "Only critical hits count", {"crits_only": true}, [["chaser", 5, 1.5, 1.0], ["shooter", 2, 3.0, 2.0]]],
	["Plated", "Robots carry extra armour", {"armor": 3.0}, [["heavy", 2, 4.0, 1.0], ["shield_bearer", 2, 3.0, 2.0], ["chaser", 4, 1.0, 4.0]]],
	["Turret nest", "Turrets cover the room", {}, [["turret", 3, 2.0, 1.0], ["chaser", 6, 1.2, 4.0]]],
	["Shield line", "Robots move twice as fast", {"speed": 2.0}, [["shield_bearer", 4, 2.0, 1.0], ["shooter", 3, 2.5, 3.0]]],
	["Swarm", "Drones in numbers", {}, [["swarm_drone", 16, 0.4, 1.0], ["runner", 4, 1.2, 6.0]]],
	["Long shift", "No reloads, extra armour", {"no_reloads": true, "armor": 2.0}, [["heavy", 2, 4.0, 1.0], ["chaser", 6, 1.0, 2.0], ["shooter", 2, 3.0, 5.0]]],
	["The mast", "Extra armour, turrets and heavies", {"armor": 3.0}, [["turret", 2, 3.0, 1.0], ["heavy", 3, 4.0, 2.0], ["shield_bearer", 2, 3.0, 4.0], ["runner", 6, 1.0, 6.0]]],
]

## 0 before the first floor starts; the floor being fought or just cleared.
var floor_number := 0
var floor_running := false
var pad_open := false
var finished := false
var elapsed := 0.0

var _player: Player
var _waves: Array[WaveDefinition] = []
var _show_all_left := SHOW_ALL_FRAMES
var _on_pad := false

@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var _player_start: Marker3D = $PlayerStart
@onready var _pad: Node3D = $Pad
@onready var _pad_closed: Node3D = $Pad/Closed
@onready var _pad_open: Node3D = $Pad/Open


static func floor_name(number: int) -> String:
	return String(FLOORS[clampi(number, 1, FLOOR_COUNT) - 1][0])


static func floor_modifier_text(number: int) -> String:
	return String(FLOORS[clampi(number, 1, FLOOR_COUNT) - 1][1])


static func floor_modifiers(number: int) -> Dictionary:
	return FLOORS[clampi(number, 1, FLOOR_COUNT) - 1][2]


## Every definition and scene the floors spawn, built into WaveDefinitions once at load.
static func build_floor_wave(number: int) -> WaveDefinition:
	var wave := WaveDefinition.new()
	wave.number = 0
	wave.display_name = "Signal Tower floor %d" % number
	wave.max_alive = 6
	wave.completion_bonus = 0
	var groups: Array[SpawnGroup] = []
	for entry in FLOORS[number - 1][3]:
		var group := SpawnGroup.new()
		group.enemy_scene = load(SCENES[entry[0]])
		group.definition = load("res://data/enemies/%s.tres" % entry[0])
		group.count = int(entry[1])
		group.interval = float(entry[2])
		group.start_delay = float(entry[3])
		groups.append(group)
	wave.groups = groups
	return wave


func _ready() -> void:
	_nav_region.bake_navigation_mesh(false)
	for number in range(1, FLOOR_COUNT + 1):
		_waves.append(build_floor_wave(number))
	_set_pad(false)
	_pad_open.visible = true # drawn for the first frames, see SHOW_ALL_FRAMES


func setup(player: Player) -> void:
	_player = player
	Progression.record_tower_run()


func get_player_start() -> Transform3D:
	return _player_start.global_transform


func get_spawn_points() -> Array[Marker3D]:
	var points: Array[Marker3D] = []
	for node in $SpawnPoints.get_children():
		if node is Marker3D:
			points.append(node)
	return points


## Floor 1's schedule: the game holds it as the pending encounter until the player has control,
## then calls start_run (the tower starts every floor itself, with its rules).
func encounter_wave() -> WaveDefinition:
	return _waves[0]


## The game calls this once the player has control: the first floor starts.
func start_run() -> void:
	elapsed = 0.0
	start_floor(1)


func start_floor(number: int) -> void:
	floor_number = clampi(number, 1, FLOOR_COUNT)
	floor_running = true
	_set_pad(false)
	floor_started.emit(_waves[floor_number - 1], floor_modifiers(floor_number))
	status_changed.emit(status_text())


func floor_wave(number: int) -> WaveDefinition:
	return _waves[number - 1]


## The game forwards the wave runner's clear: the floor is done; the pad lights unless it was the top.
func on_encounter_cleared(_seconds: float) -> void:
	if not floor_running:
		return
	floor_running = false
	Progression.record_tower_floor(floor_number)
	if floor_number >= FLOOR_COUNT:
		finished = true
		status_changed.emit(status_text())
		cleared.emit(true, elapsed)
		return
	_set_pad(true)
	_on_pad = _player != null and _flat_distance(_pad.global_position, _player.global_position) <= PAD_RADIUS
	status_changed.emit(status_text())


func status_text() -> String:
	if finished:
		return "The top of the tower. The mast is still broadcasting."
	if floor_number == 0:
		return "Ten floors, one rule each. Swap gear on the pad between floors."
	var head := "Floor %d / %d  ·  %s  ·  %s" % [floor_number, FLOOR_COUNT, floor_name(floor_number), floor_modifier_text(floor_number)]
	if pad_open:
		return "Floor %d cleared  ·  step on the pad to swap gear and climb to floor %d (%s)" % [
			floor_number, floor_number + 1, floor_modifier_text(floor_number + 1)]
	return head


func _process(_delta: float) -> void:
	if _show_all_left > 0:
		_show_all_left -= 1
		if _show_all_left == 0:
			_set_pad(pad_open)


func _physics_process(delta: float) -> void:
	if finished or _player == null or _player.is_dead or floor_number == 0:
		return
	elapsed += delta
	if not pad_open:
		return
	# The pad fires on stepping onto it, so returning to the room after Climb does not reopen it.
	var on := _flat_distance(_pad.global_position, _player.global_position) <= PAD_RADIUS
	if on and not _on_pad:
		pad_reached.emit(floor_number)
	_on_pad = on


func _set_pad(open: bool) -> void:
	pad_open = open
	_pad_closed.visible = not open
	_pad_open.visible = open


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
