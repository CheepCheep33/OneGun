class_name Pistol
extends Node3D
## The player's one gun. Effective stats always come from WeaponStats.build() and arrive through
## apply_build(); this script never edits them. The receiver decides shots per trigger pull
## (semi, automatic, burst), the muzzle decides rays per shot and spread, and each ray resolves
## through ShotPipeline (hitscan) or the projectile pool (simulated ammo). Fitted attachments also
## change the placeholder model so the player can see what they equipped.

signal ammo_changed(in_magazine: int, magazine_size: int)
signal reload_started(duration: float)
signal reload_finished
signal fired(recoil_kick_degrees: float)
## A shot hit something with take_hit(). `killed` is true when that hit destroyed it.
signal hit_landed(killed: bool)

## A click this many seconds before the gun is ready still fires, so fast clicking never feels eaten.
const FIRE_BUFFER := 0.12
## Seconds between the rounds of one burst. The pause after a burst keeps the sustained rate at fire_rate.
const BURST_INTERVAL := 0.08
const FLASH_TIME := 0.045
## The flash stays up for at least this many rendered frames, so it is never skipped at low frame rates.
const FLASH_MIN_FRAMES := 2
const MODEL_RECOVERY := 14.0
const BASE_MUZZLE_Z := -0.16

@export var base_stats: WeaponBaseStats
## Physics layers a shot can hit: world (1) and enemies (3).
@export_flags_3d_physics var hit_mask := 1 | 4

var stats: WeaponStats
## The equipped items the current stats were built from, for the model.
var equipped: Dictionary = {}
var ammo := 0
var is_reloading := false
## Cleared while the player is dead so the gun ignores input.
var enabled := true
## Cleared in touch mode: browsers also report each tap as a mouse click, which must not fire.
var mouse_input_enabled := true
## Rounds fired since the stats were applied, for the playtest log and tests.
var shots_fired := 0

var _camera: Camera3D
var _shooter_rid: RID
var _rng := RandomNumberGenerator.new()
var _cooldown := 0.0
var _buffered_fire := 0.0
var _trigger_held := false
var _burst_left := 0
var _burst_timer := 0.0
var _reload_left := 0.0
var _flash_left := 0.0
var _flash_frames := 0
var _kick := 0.0
var _model_rest: Vector3
var _slide_rest_scale: Vector3
var _grip_rest_scale: Vector3

@onready var _model: Node3D = $Model
@onready var _slide: MeshInstance3D = $Model/Slide
@onready var _grip: MeshInstance3D = $Model/Grip
@onready var _barrel_extension: MeshInstance3D = $Model/BarrelExtension
@onready var _muzzle: Node3D = $Model/Muzzle
@onready var _flash: Node3D = $Model/Muzzle/Flash
@onready var _flash_light: Light3D = $Model/Muzzle/FlashLight
@onready var _shot_sound: AudioStreamPlayer = $ShotSound
@onready var _reload_start_sound: AudioStreamPlayer = $ReloadStartSound
@onready var _reload_end_sound: AudioStreamPlayer = $ReloadEndSound


func _ready() -> void:
	_model_rest = _model.position
	_slide_rest_scale = _slide.scale
	_grip_rest_scale = _grip.scale
	if stats == null:
		apply_build(WeaponStats.build(base_stats))
	_set_flash_visible(false)


## Takes a freshly built stats object (at the bench, never mid-wave), refits the model to the
## equipped attachments and refills the magazine.
func apply_build(new_stats: WeaponStats, equipped_items: Dictionary = {}) -> void:
	stats = new_stats
	equipped = equipped_items
	ammo = stats.magazine_size
	is_reloading = false
	shots_fired = 0
	_reload_left = 0.0
	_cooldown = 0.0
	_buffered_fire = 0.0
	_burst_left = 0
	_trigger_held = false
	_apply_visuals()
	ammo_changed.emit(ammo, stats.magazine_size)
	reload_finished.emit()


## Kept for callers that only have stats (tests, the Firing Range preview).
func apply_stats(new_stats: WeaponStats) -> void:
	apply_build(new_stats, equipped)


## Called by the player: the camera defines the aim ray and the shooter is excluded from hits.
func setup(camera: Camera3D, shooter_rid: RID) -> void:
	_camera = camera
	_shooter_rid = shooter_rid


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_released("fire"):
		release_fire()
		return
	if not mouse_input_enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return # The click that recaptures the mouse should not also fire.
	if event.is_action_pressed("fire"):
		request_fire()
	elif event.is_action_pressed("reload"):
		request_reload()


## Pulls the trigger. Semi-auto and burst fire once per pull; automatic keeps firing until release_fire().
func request_fire() -> void:
	if enabled:
		_buffered_fire = FIRE_BUFFER
		_trigger_held = true


func release_fire() -> void:
	_trigger_held = false


func request_reload() -> void:
	if enabled and not is_reloading and ammo < stats.magazine_size:
		_burst_left = 0
		_start_reload()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _cooldown <= 0.0 and _burst_left == 0:
		# A pull during a burst or the pause after one is kept until the gun can fire again.
		_buffered_fire = maxf(_buffered_fire - delta, 0.0)
	if is_reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()
	if not enabled:
		return
	if _burst_left > 0:
		_burst_timer -= delta
		if _burst_timer <= 0.0 and not is_reloading:
			_burst_left -= 1
			_fire_round()
			_burst_timer = BURST_INTERVAL
			if _burst_left == 0:
				_cooldown = _burst_cooldown(int(stats.behaviours.get("burst_size", 3)))
		return
	var wants_shot := _buffered_fire > 0.0 or (stats.fire_mode() == "auto" and _trigger_held)
	if wants_shot and _cooldown <= 0.0 and not is_reloading:
		_pull_trigger()


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


## One trigger pull: a single round, or the first round of a burst.
func _pull_trigger() -> void:
	_buffered_fire = 0.0
	if ammo <= 0:
		_start_reload()
		return
	if stats.fire_mode() == "burst":
		var size := mini(int(stats.behaviours.get("burst_size", 3)), ammo)
		_fire_round()
		_burst_left = size - 1
		_burst_timer = BURST_INTERVAL
		if _burst_left == 0:
			_cooldown = _burst_cooldown(size)
	else:
		_fire_round()
		_cooldown = stats.seconds_between_shots()


## The pause after a burst, so bursts of `size` rounds sustain the build's fire rate.
func _burst_cooldown(size: int) -> float:
	return maxf(size * stats.seconds_between_shots() - (size - 1) * BURST_INTERVAL, 0.05)


## Fires one round: every ray of the shot through the pipeline, then feedback and the auto reload.
func _fire_round() -> void:
	ammo -= 1
	shots_fired += 1
	var shot := ShotPipeline.ShotState.new()
	shot.rng = _rng
	shot.scene = self
	shot.ammo_refund_chance = float(stats.extra.get(WeaponStats.AMMO_REFUND_KEY, {}).get("percent", 0.0))
	shot.chain_chance = float(stats.extra.get(WeaponStats.CHAIN_ON_CRIT_KEY, {}).get("percent", 0.0))
	if _camera != null:
		var ray_count := int(stats.behaviours.get("ray_count", 1))
		var profile_id := String(stats.behaviours.get("projectile", "hitscan"))
		for ray in ray_count:
			var direction := _ray_direction(ray, ray_count)
			if profile_id != "hitscan" and ProjectilePool.current != null and ProjectilePool.PROFILES.has(profile_id):
				ProjectilePool.current.fire_player_round(_shooter_rid, _camera.global_position, direction, stats, shot,
					ProjectilePool.PROFILES[profile_id])
				Fx.tracer(self, _muzzle.global_position, _camera.global_position + direction * 1.5)
			else:
				_cast_ray(direction, shot)
	if shot.refunds > 0:
		ammo = mini(ammo + shot.refunds, stats.magazine_size)
	_play_shot_feedback()
	fired.emit(stats.recoil_kick_degrees)
	ammo_changed.emit(ammo, stats.magazine_size)
	if ammo == 0:
		_burst_left = 0
		_start_reload()


## The aim direction for one ray, spread inside the muzzle's cone (rays past the first are offset).
func _ray_direction(index: int, count: int) -> Vector3:
	var direction := -_camera.global_basis.z
	var spread := float(stats.behaviours.get("spread_degrees", 0.0))
	if spread <= 0.0 or (count == 1 and index == 0 and spread <= 0.0):
		return direction
	var angle := deg_to_rad(spread) * sqrt(_rng.randf())
	var around := _rng.randf() * TAU
	var right := direction.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	var up := right.cross(direction).normalized()
	var offset := (right * cos(around) + up * sin(around)) * tan(angle)
	return (direction + offset).normalized()


func _cast_ray(direction: Vector3, shot: ShotPipeline.ShotState) -> void:
	var origin := _camera.global_position
	var result := ShotPipeline.fire_hitscan(get_world_3d().direct_space_state, origin, direction, stats, shot,
		hit_mask, [_shooter_rid])
	for hit in result.hits:
		hit_landed.emit(hit.killed)
		if Settings.show_damage_numbers and hit.damage > 0.0:
			Fx.damage_number(self, hit.position, hit.damage, hit.killed)
	if result.hit_world:
		Fx.impact(self, result.end_point, result.world_normal)
	Fx.tracer(self, _muzzle.global_position, result.end_point)


func _play_shot_feedback() -> void:
	_kick = 1.0
	_flash_left = FLASH_TIME
	_flash_frames = 0
	_flash.rotation.z = randf() * TAU
	_flash.scale = Vector3.ONE * randf_range(0.8, 1.25)
	_set_flash_visible(true)
	_shot_sound.pitch_scale = randf_range(0.94, 1.06) * (1.12 if stats.fire_mode() == "burst" else 1.0)
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


## Refits the placeholder model from the equipped bases' `visual` hints: a longer slide for long
## barrels, a taller or shorter grip for magazines, a tinted slide for receivers, a muzzle extension.
func _apply_visuals() -> void:
	var slide_length := 1.0
	var grip_height := 1.0
	var slide_color: Variant = null
	var extension := false
	for slot_id in Items.SLOT_IDS:
		var item: Variant = equipped.get(String(slot_id))
		if not (item is Dictionary):
			continue
		var definition := Items.get_attachment(item.get("base", ""))
		if definition == null:
			continue
		slide_length *= float(definition.visual.get("slide_length", 1.0))
		grip_height *= float(definition.visual.get("grip_height", 1.0))
		if definition.visual.has("slide_color"):
			slide_color = definition.visual["slide_color"]
		extension = extension or bool(definition.visual.get("barrel_extension", false))
	_slide.scale = Vector3(_slide_rest_scale.x, _slide_rest_scale.y, _slide_rest_scale.z * slide_length)
	# Grow the slide forward: its mesh is centred, so shift it by half the added length.
	_slide.position.z = -0.13 * (slide_length - 1.0)
	_grip.scale = Vector3(_grip_rest_scale.x, _grip_rest_scale.y * grip_height, _grip_rest_scale.z)
	_grip.position.y = -0.085 - 0.06 * (grip_height - 1.0)
	_muzzle.position.z = BASE_MUZZLE_Z - 0.26 * (slide_length - 1.0) - (0.06 if extension else 0.0)
	_barrel_extension.visible = extension
	_barrel_extension.position.z = BASE_MUZZLE_Z - 0.26 * (slide_length - 1.0) - 0.03
	if slide_color is Color:
		var material := StandardMaterial3D.new()
		material.albedo_color = slide_color
		material.metallic = 0.6
		material.roughness = 0.4
		_slide.material_override = material
	else:
		_slide.material_override = null
