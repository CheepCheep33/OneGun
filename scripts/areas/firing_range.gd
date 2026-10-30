extends Node3D
## The Firing Range side area (plan: Side areas): no enemies. Target dummies with live damage
## readouts at marked distances, a timed gallery whose first run under par grants a guaranteed
## Uncommon of a chosen slot, and a loot preview wall listing every base and its gate. Loaded in
## place of the arena by the game; leaving returns to the bench with nothing lost.

signal status_changed(text: String)

const PAR_TIME := 14.0
const TARGET_COUNT := 8
const DUMMY_DISTANCES := [8.0, 12.0, 16.0, 20.0, 28.0]
## Pedestal positions for pop-up targets, relative to the gallery's back line.
const PEDESTALS := [
	Vector3(-9.0, 0.0, -2.0), Vector3(-6.0, 0.0, -6.0), Vector3(-3.0, 0.0, -1.0), Vector3(0.0, 0.0, -8.0),
	Vector3(3.0, 0.0, -3.0), Vector3(6.0, 0.0, -7.0), Vector3(9.0, 0.0, -1.5), Vector3(-7.5, 0.0, -10.0),
	Vector3(1.5, 0.0, -12.0), Vector3(7.5, 0.0, -11.0),
]
const GALLERY_ORIGIN := Vector3(0.0, 0.0, -2.0)
const CHOICE_SLOTS: Array[StringName] = [&"receiver", &"barrel", &"magazine"]

var gallery_running := false
var gallery_time := 0.0
var targets_hit := 0
var last_result := ""

var _player: Player
var _rng := RandomNumberGenerator.new()
var _current_target: TargetDummy
var _choice_plates: Dictionary = {}
var _board: Label3D

@onready var _player_start: Marker3D = $PlayerStart
@onready var _targets: Node3D = $Targets


func _ready() -> void:
	_rng.randomize()
	_build_dummies()
	_build_gallery()
	_build_preview_wall()
	_refresh_board()


func setup(player: Player) -> void:
	_player = player


func get_player_start() -> Transform3D:
	return _player_start.global_transform


func get_spawn_points() -> Array[Marker3D]:
	return []


func _process(delta: float) -> void:
	if gallery_running:
		gallery_time += delta
		status_changed.emit(status_text())


func status_text() -> String:
	if gallery_running:
		return "Gallery  %.1f s  ·  %d / %d targets" % [gallery_time, targets_hit, TARGET_COUNT]
	if last_result != "":
		return last_result
	return "Shoot the green plate to start the gallery (par %.0f s)" % PAR_TIME


# ------------------------------------------------------------------ building

func _build_dummies() -> void:
	var start_z := _player_start.position.z
	for i in DUMMY_DISTANCES.size():
		var distance: float = DUMMY_DISTANCES[i]
		var dummy := TargetDummy.new()
		dummy.role = "dummy"
		dummy.label_text = "%d m" % roundi(distance)
		dummy.position = Vector3(-8.0 + 4.0 * i, 0.0, start_z - distance)
		_targets.add_child(dummy)


func _build_gallery() -> void:
	var start := TargetDummy.new()
	start.role = "start"
	start.label_text = "START GALLERY"
	start.color = Color(0.35, 0.85, 0.45)
	start.size = Vector3(1.2, 1.2, 0.3)
	start.position = Vector3(-14.0, 0.0, _player_start.position.z - 6.0)
	start.struck.connect(_on_start_struck)
	_targets.add_child(start)
	var chosen := StringName(String(Progression.range_state().get("chosen_slot", "barrel")))
	for i in CHOICE_SLOTS.size():
		var slot: StringName = CHOICE_SLOTS[i]
		var plate := TargetDummy.new()
		plate.role = "choose"
		plate.slot_choice = slot
		plate.label_text = "REWARD: %s" % String(slot).to_upper()
		plate.color = Color(0.5, 0.65, 0.95)
		plate.size = Vector3(1.0, 1.0, 0.3)
		plate.position = Vector3(-14.0 + 2.0 * (i + 1), 0.0, _player_start.position.z - 9.0 - 1.5 * i)
		plate.struck.connect(_on_choice_struck)
		_targets.add_child(plate)
		_choice_plates[slot] = plate
		plate.set_highlight(slot == chosen)
	_board = Label3D.new()
	_board.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_board.fixed_size = true
	_board.pixel_size = 0.0005
	_board.font_size = 40
	_board.outline_size = 12
	_board.position = Vector3(-12.0, 3.2, _player_start.position.z - 8.0)
	add_child(_board)


func _build_preview_wall() -> void:
	var wall := Label3D.new()
	wall.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	wall.font_size = 30
	wall.outline_size = 8
	wall.pixel_size = 0.012
	wall.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	wall.position = Vector3(14.5, 3.0, _player_start.position.z - 12.0)
	wall.rotation.y = -PI / 2.0
	var lines := PackedStringArray(["LOOT PREVIEW  ·  what can drop", ""])
	for slot in Items.get_slots():
		if not Items.slot_has_bases(slot.id):
			continue
		lines.append(slot.display_name.to_upper())
		for base in Items.bases_for_slot(slot.id):
			if base.is_default:
				continue
			var state := "drops now" if Progression.is_base_unlocked(base) else "locked · " + base.gate_text
			lines.append("  %s  ·  %s" % [base.display_name, state])
			lines.append("      " + "  ".join(base.describe_modifiers()))
		lines.append("")
	wall.text = "\n".join(lines)
	add_child(wall)


# ------------------------------------------------------------------ gallery

func _on_start_struck(_dummy: TargetDummy, _damage: float) -> void:
	if gallery_running:
		return
	gallery_running = true
	gallery_time = 0.0
	targets_hit = 0
	last_result = ""
	_refresh_board()
	_pop_next_target()
	status_changed.emit(status_text())


func _on_choice_struck(plate: TargetDummy, _damage: float) -> void:
	Progression.set_range_slot(plate.slot_choice)
	for slot in _choice_plates:
		_choice_plates[slot].set_highlight(slot == plate.slot_choice)
	_refresh_board()


func _pop_next_target() -> void:
	var pedestal: Vector3 = PEDESTALS[_rng.randi_range(0, PEDESTALS.size() - 1)]
	var target := TargetDummy.new()
	target.role = "gallery"
	target.label_text = ""
	target.color = Color(0.95, 0.75, 0.25)
	target.size = Vector3(0.8, 1.4, 0.3)
	target.position = GALLERY_ORIGIN + pedestal + Vector3(0.0, 0.0, _player_start.position.z - 8.0)
	target.struck.connect(_on_gallery_target_struck)
	_targets.add_child(target)
	_current_target = target


func _on_gallery_target_struck(target: TargetDummy, _damage: float) -> void:
	if not gallery_running or target != _current_target:
		return
	targets_hit += 1
	target.queue_free()
	_current_target = null
	if targets_hit >= TARGET_COUNT:
		_finish_gallery()
	else:
		_pop_next_target()


func _finish_gallery() -> void:
	gallery_running = false
	var result := Progression.record_range_time(gallery_time, PAR_TIME)
	var reward: Dictionary = result["reward"]
	last_result = "Gallery  %.1f s" % gallery_time
	if gallery_time <= PAR_TIME:
		last_result += "  ·  under par"
	if result["best"]:
		last_result += "  ·  new best"
	if not reward.is_empty():
		last_result += "  ·  reward: %s" % Items.display_name(reward)
	_refresh_board()
	status_changed.emit(status_text())


func _refresh_board() -> void:
	var state := Progression.range_state()
	var best := float(state.get("best_time", 0.0))
	var lines := PackedStringArray()
	lines.append("GALLERY  ·  %d targets  ·  par %.0f s" % [TARGET_COUNT, PAR_TIME])
	lines.append("Best  %s" % ("%.1f s" % best if best > 0.0 else "none yet"))
	lines.append("Reward slot  %s%s" % [String(state.get("chosen_slot", "barrel")).capitalize(),
		"  (claimed)" if bool(state.get("par_rewarded", false)) else "  ·  first run under par pays an Uncommon"])
	if last_result != "":
		lines.append(last_result)
	_board.text = "\n".join(lines)
