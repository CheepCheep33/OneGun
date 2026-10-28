class_name Pistol
extends Node3D
## The player's one gun: hitscan firing, magazine, reload, and shot feedback.
## Effective stats always come from WeaponStats.compute(); this script never edits them.

signal ammo_changed(in_magazine: int, magazine_size: int)
signal reload_started(duration: float)
signal reload_finished
signal fired(recoil_kick_degrees: float)
## A shot hit something with take_hit(). `killed` is true when that shot destroyed it.
signal hit_landed(killed: bool)

## A click this many seconds before the gun is ready still fires, so fast clicking never feels eaten.
const FIRE_BUFFER := 0.12
const FLASH_TIME := 0.045
## The flash stays up for at least this many rendered frames, so it is never skipped at low frame rates.
const FLASH_MIN_FRAMES := 2
const MODEL_RECOVERY := 14.0

@export var base_stats: WeaponBaseStats
## Physics layers a shot can hit: world (1) and enemies (3).
@export_flags_3d_physics var hit_mask := 1 | 4

var stats: WeaponStats
var ammo := 0
var is_reloading := false
## Cleared while the player is dead so the gun ignores input.
var enabled := true

var _camera: Camera3D
var _shooter_rid: RID
var _cooldown := 0.0
var _buffered_fire := 0.0
var _reload_left := 0.0
var _flash_left := 0.0
var _flash_frames := 0
var _kick := 0.0
var _model_rest: Vector3

@onready var _model: Node3D = $Model
@onready var _muzzle: Node3D = $Model/Muzzle
@onready var _flash: Node3D = $Model/Muzzle/Flash
@onready var _flash_light: Light3D = $Model/Muzzle/FlashLight
@onready var _shot_sound: AudioStreamPlayer = $ShotSound
@onready var _reload_start_sound: AudioStreamPlayer = $ReloadStartSound
@onready var _reload_end_sound: AudioStreamPlayer = $ReloadEndSound


func _ready() -> void:
	stats = WeaponStats.compute(base_stats)
	ammo = stats.magazine_size
	_model_rest = _model.position
	_set_flash_visible(false)


## Called by the player: the camera defines the aim ray and the shooter is excluded from hits.
func setup(camera: Camera3D, shooter_rid: RID) -> void:
	_camera = camera
	_shooter_rid = shooter_rid


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return # The click that recaptures the mouse should not also fire.
	if event.is_action_pressed("fire"):
		request_fire()
	elif event.is_action_pressed("reload"):
		request_reload()


func request_fire() -> void:
	if enabled:
		_buffered_fire = FIRE_BUFFER


func request_reload() -> void:
	if enabled and not is_reloading and ammo < stats.magazine_size:
		_start_reload()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_buffered_fire = maxf(_buffered_fire - delta, 0.0)
	if is_reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()
	if _buffered_fire > 0.0 and _cooldown <= 0.0 and not is_reloading and enabled:
		_fire()


func _process(delta: float) -> void:
	_kick = lerpf(_kick, 0.0, 1.0 - exp(-MODEL_RECOVERY * delta))
	var reload_dip := 0.0
	if is_reloading:
		reload_dip = sin(PI * (1.0 - _reload_left / stats.reload_time))
	_model.position = _model_rest + Vector3(0.0, 0.012 * _kick - 0.1 * reload_dip, 0.05 * _kick)
	_model.rotation = Vector3(0.18 * _kick - 0.5 * reload_dip, 0.0, 0.35 * reload_dip)
	if _flash.visible:
		_flash_left -= delta
		_flash_frames += 1
		if _flash_left <= 0.0 and _flash_frames >= FLASH_MIN_FRAMES:
			_set_flash_visible(false)


func _fire() -> void:
	_buffered_fire = 0.0
	if ammo <= 0:
		_start_reload()
		return
	ammo -= 1
	_cooldown = stats.seconds_between_shots()
	_cast_shot()
	_play_shot_feedback()
	fired.emit(stats.recoil_kick_degrees)
	ammo_changed.emit(ammo, stats.magazine_size)
	if ammo == 0:
		_start_reload()


func _cast_shot() -> void:
	if _camera == null:
		return
	var origin := _camera.global_position
	var direction := -_camera.global_basis.z
	var end_point := origin + direction * stats.max_range
	var query := PhysicsRayQueryParameters3D.create(origin, end_point, hit_mask, [_shooter_rid])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		end_point = hit.position
		var target: Object = hit.collider
		if target.has_method("take_hit"):
			var killed: bool = target.take_hit(stats.damage, hit.position, direction)
			hit_landed.emit(killed)
			if Settings.show_damage_numbers:
				Fx.damage_number(self, hit.position, stats.damage, killed)
		else:
			Fx.impact(self, hit.position, hit.normal)
	Fx.tracer(self, _muzzle.global_position, end_point)


func _play_shot_feedback() -> void:
	_kick = 1.0
	_flash_left = FLASH_TIME
	_flash_frames = 0
	_flash.rotation.z = randf() * TAU
	_flash.scale = Vector3.ONE * randf_range(0.8, 1.25)
	_set_flash_visible(true)
	_shot_sound.pitch_scale = randf_range(0.94, 1.06)
	_shot_sound.play()


func _start_reload() -> void:
	is_reloading = true
	_reload_left = stats.reload_time
	_reload_start_sound.play()
	reload_started.emit(stats.reload_time)


func _finish_reload() -> void:
	is_reloading = false
	ammo = stats.magazine_size
	_reload_end_sound.play()
	reload_finished.emit()
	ammo_changed.emit(ammo, stats.magazine_size)


func _set_flash_visible(value: bool) -> void:
	_flash.visible = value
	_flash_light.visible = value
