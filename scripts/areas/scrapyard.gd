extends Node3D
## The Scrapyard side area (plan: Side areas): a salvage run. Opens when the Warden falls. Robots
## come in rising numbers down three lanes split by rows of wrecks (they line up, so Penetrator
## shines) while the player picks scrap cores off the wrecks. After RUN_SECONDS the south door
## opens; standing on its pad extracts with what the player carries: parts in bulk, a Rare every
## time and a log on the first extraction (Progression.record_scrapyard_extraction). Dying or
## leaving loses the carried cores and the floor loot; kill credits and picked-up drops are kept.
## Loaded in place of the arena by the game; the spawns run on the game's wave runner with the
## schedule in data/areas/scrapyard_spawns.tres, from the reserves the waves already fill.

signal status_changed(text: String)
## Standing on the open door's pad: the run is over and pays.
signal extracted(cores: int, seconds: float)
signal core_collected(carried: int)

const RUN_SECONDS := 90.0
const PICKUP_RADIUS := 1.1
const PAD_RADIUS := 1.6
const SPAWNS := preload("res://data/areas/scrapyard_spawns.tres")
const CORE_SPIN := 1.8
## Frames every mesh in the yard is drawn before the open door hides, so its material compiles at
## load, not when the door opens mid-run.
const SHOW_ALL_FRAMES := 2

var elapsed := 0.0
var carried := 0
var running := false
var door_open := false
var extracted_once := false

var _player: Player
var _cores: Array[MeshInstance3D] = []
var _status_left := 0.0
var _show_all_left := SHOW_ALL_FRAMES

@onready var _nav_region: NavigationRegion3D = $NavigationRegion3D
@onready var _player_start: Marker3D = $PlayerStart
@onready var _pad: Node3D = $Pad
@onready var _door_locked: Node3D = $Door/Locked
@onready var _door_open: Node3D = $Door/Open
@onready var _pad_locked: Node3D = $Pad/Locked
@onready var _pad_open: Node3D = $Pad/Open
@onready var _core_root: Node3D = $Cores
@onready var _core_spots: Node3D = $CoreSpots


func _ready() -> void:
	_nav_region.bake_navigation_mesh(false)
	for spot in _core_spots.get_children():
		var core := MeshInstance3D.new()
		core.mesh = _core_mesh()
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_core_root.add_child(core)
		core.global_position = spot.global_position
		_cores.append(core)
	_set_door(false)
	_door_open.visible = true # drawn for the first frames, see SHOW_ALL_FRAMES
	_pad_open.visible = true


func setup(player: Player) -> void:
	_player = player
	Progression.record_scrapyard_run()


func get_player_start() -> Transform3D:
	return _player_start.global_transform


func get_spawn_points() -> Array[Marker3D]:
	var points: Array[Marker3D] = []
	for node in $SpawnPoints.get_children():
		if node is Marker3D:
			points.append(node)
	return points


## The spawn schedule the game runs on its wave runner once the player has control.
func encounter_wave() -> WaveDefinition:
	return SPAWNS


## Called by the game when the spawns start: the run clock starts with them.
func start_run() -> void:
	running = true
	elapsed = 0.0
	status_changed.emit(status_text())


func cores_left() -> int:
	var count := 0
	for core in _cores:
		if core.visible:
			count += 1
	return count


func status_text() -> String:
	if extracted_once:
		return "Extracted with %d cores" % carried
	if not running:
		return "Grab scrap cores from the wrecks; the south door opens after %d s" % roundi(RUN_SECONDS)
	if door_open:
		return "DOOR OPEN  ·  extract at the south pad with %d cores  ·  %d left on the wrecks" % [carried, cores_left()]
	return "Salvage  %d s to the door  ·  %d cores carried  ·  %d on the wrecks" % [
		ceili(RUN_SECONDS - elapsed), carried, cores_left()]


func _process(delta: float) -> void:
	if _show_all_left > 0:
		_show_all_left -= 1
		if _show_all_left == 0:
			_set_door(door_open)
	for core in _cores:
		if core.visible:
			core.rotate_y(CORE_SPIN * delta)


func _physics_process(delta: float) -> void:
	if not running or extracted_once or _player == null or _player.is_dead:
		return
	elapsed += delta
	if not door_open and elapsed >= RUN_SECONDS:
		_set_door(true)
		status_changed.emit(status_text())
	var at := _player.global_position
	for core in _cores:
		if core.visible and _flat_distance(core.global_position, at) <= PICKUP_RADIUS:
			core.visible = false
			carried += 1
			core_collected.emit(carried)
			status_changed.emit(status_text())
	if door_open and _flat_distance(_pad.global_position, at) <= PAD_RADIUS:
		extracted_once = true
		running = false
		status_changed.emit(status_text())
		extracted.emit(carried, elapsed)
		return
	# The countdown text changes once a second; the label is only written then.
	_status_left -= delta
	if _status_left <= 0.0:
		_status_left = 1.0
		status_changed.emit(status_text())


func _set_door(open: bool) -> void:
	door_open = open
	_door_locked.visible = not open
	_pad_locked.visible = not open
	_door_open.visible = open
	_pad_open.visible = open


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## One shared mesh with the core material for every core, made once per load.
func _core_mesh() -> Mesh:
	if not has_meta("core_mesh"):
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * 0.45
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(1.0, 0.75, 0.25)
		mesh.material = material
		set_meta("core_mesh", mesh)
	return get_meta("core_mesh")
