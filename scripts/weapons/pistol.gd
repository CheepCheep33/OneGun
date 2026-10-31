class_name Pistol
extends Node3D
## The player's one gun. Effective stats always come from WeaponStats.build() and arrive through
## apply_build(); this script never edits them. The receiver decides shots per trigger pull
## (semi, automatic, burst, charge), the muzzle decides rays per shot and spread, and each ray
## resolves through ShotPipeline (hitscan) or the projectile pool (simulated ammo). The underbarrel
## adds the Launcher's grenades (alt fire, charged by kills) or the Shield emitter (a frontal
## shield while reloading); the Overclock capstone and kill effects (Hot Swap, Bottomless) live
## here too. Fitted attachments also change the placeholder model so the player can see what they
## equipped.

signal ammo_changed(in_magazine: int, magazine_size: int)
signal reload_started(duration: float)
signal reload_finished
signal fired(recoil_kick_degrees: float)
## A shot hit something with take_hit(). `killed` is true when that hit destroyed it.
signal hit_landed(killed: bool)
## 0 to 1 while a Charge receiver charges; -1 when the charge ends.
signal charge_changed(fraction: float)
## A short status for the HUD beside the ammo ("OVERCLOCK", "GRENADES 2"); empty clears it.
signal status_changed(text: String)
## The Scanner reads the robot under the crosshair: its name, health and maximum; an empty name
## when there is none.
signal scanned(name: String, health: float, maximum: float)

## A click this many seconds before the gun is ready still fires, so fast clicking never feels eaten.
const FIRE_BUFFER := 0.12
## Seconds between the rounds of one burst. The pause after a burst keeps the sustained rate at fire_rate.
const BURST_INTERVAL := 0.08
const FLASH_TIME := 0.045
## The flash stays up for at least this many rendered frames, so it is never skipped at low frame rates.
const FLASH_MIN_FRAMES := 2
const MODEL_RECOVERY := 14.0
const BASE_MUZZLE_Z := -0.16
## How far the muzzle light reaches while the shader warm-up draws the arena: far enough to touch
## everything in view from the player's start (the arena is 46 m across).
const WARM_UP_LIGHT_RANGE := 60.0
## Colour of a simulated player round when its ammo names none.
const PLAYER_ROUND_COLOR := Color(1.0, 0.9, 0.55)
## Launcher: a grenade charges every GRENADE_KILLS kills, at most GRENADE_MAX held; it deals
## GRENADE_DAMAGE times a shot's damage to every robot within GRENADE_RADIUS.
const GRENADE_KILLS := 4
const GRENADE_MAX := 2
const GRENADE_DAMAGE := 3.0
const GRENADE_RADIUS := 3.5
const GRENADE_COOLDOWN := 0.6
## Overclock (Engineer capstone): hold reload this long with a full magazine for OVERCLOCK_TIME of
## double fire rate, then OVERHEAT_TIME without firing.
const OVERCLOCK_HOLD := 0.5
const OVERCLOCK_TIME := 5.0
const OVERHEAT_TIME := 3.0
## Hot Swap: a kill refills the magazine at most this often.
const HOT_SWAP_COOLDOWN := 4.0
## Shield emitter: damage from the front is cut by this share while reloading.
const RELOAD_SHIELD_REDUCTION := 0.7
## Scanner: metres the crosshair reading reaches.
const SCAN_RANGE := 60.0

@export var base_stats: WeaponBaseStats
## Physics layers a shot can hit: world (1), enemies (3) and shields (4).
@export_flags_3d_physics var hit_mask := 1 | 4 | 8

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
## The player's health fraction, kept up by the player, for Adrenaline.
var player_health_fraction := 1.0
## Launcher grenades ready, and kills toward the next.
var grenades := 0
var grenade_kills := 0
## Overclock: seconds of it left, seconds of overheat left.
var overclock_left := 0.0
var overheat_left := 0.0
## Charge receiver: seconds the trigger has been held for the current charge, -1 when not charging.
var charge_held := -1.0

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
## The muzzle light's range and energy from the scene, restored after a warm-up.
var _light_range := 5.0
var _light_energy := 3.0
var _reload_held := 0.0
var _reload_pressed := false
var _hot_swap_left := 0.0
var _grenade_cooldown := 0.0
var _status_text := ""
var _scan_query := PhysicsRayQueryParameters3D.new()
var _scanned_id := 0
var _scanned_health := -1.0
## Attachment meshes for the optic and underbarrel, built once; shown by _apply_visuals.
var _parts: Dictionary = {}
var _shield_pane: MeshInstance3D

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
	_light_range = _flash_light.omni_range
	_light_energy = _flash_light.light_energy
	_build_parts()
	_scan_query.collision_mask = hit_mask
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
	charge_held = -1.0
	overclock_left = 0.0
	overheat_left = 0.0
	_reload_held = 0.0
	_reload_pressed = false
	_hot_swap_left = 0.0
	_grenade_cooldown = 0.0
	grenades = 0
	grenade_kills = 0
	_scanned_id = 0
	_scanned_health = -1.0
	_apply_visuals()
	ammo_changed.emit(ammo, stats.magazine_size)
	reload_finished.emit()
	charge_changed.emit(-1.0)
	scanned.emit("", 0.0, 0.0)
	_refresh_status()


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
	if event.is_action_released("reload"):
		_reload_pressed = false
		return
	if not mouse_input_enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return # The click that recaptures the mouse should not also fire.
	if event.is_action_pressed("fire"):
		request_fire()
	elif event.is_action_pressed("reload"):
		_reload_pressed = true
		_reload_held = 0.0
		request_reload()
	elif event.is_action_pressed("alt_fire"):
		request_alt_fire()


## Pulls the trigger. Semi-auto and burst fire once per pull; automatic keeps firing until release_fire().
func request_fire() -> void:
	if enabled:
		_buffered_fire = FIRE_BUFFER
		_trigger_held = true


func release_fire() -> void:
	_trigger_held = false


## Fires a Launcher grenade when one is ready (plan: alt fire). False when nothing fired.
func request_alt_fire() -> bool:
	if not enabled or String(stats.behaviours.get("alt_fire", "")) != "launcher":
		return false
	if grenades <= 0 or _grenade_cooldown > 0.0 or _camera == null or ProjectilePool.current == null:
		return false
	grenades -= 1
	_grenade_cooldown = GRENADE_COOLDOWN
	var direction := (-_camera.global_basis.z + Vector3.UP * 0.12).normalized()
	ProjectilePool.current.fire_grenade(_shooter_rid, _camera.global_position, direction,
		stats.damage * GRENADE_DAMAGE, GRENADE_RADIUS, self)
	_shot_sound.pitch_scale = 0.6
	_shot_sound.play()
	_kick = 1.4
	_refresh_status()
	return true


## Starts Overclock when the capstone is taken, the gun is not reloading, overheated or already
## overclocked. Holding reload with a full magazine calls this; tests call it directly.
func start_overclock() -> bool:
	if stats.extra_percent("overclock") <= 0.0 or overclock_left > 0.0 or overheat_left > 0.0 or is_reloading:
		return false
	overclock_left = OVERCLOCK_TIME
	_refresh_status()
	return true


## A robot died (the game calls this for every kill while this gun is out): Hot Swap refills the
## magazine, Bottomless (kill_refill) puts rounds back, and the Launcher charges.
func notify_kill() -> void:
	if not enabled:
		return
	var refill := int(stats.behaviours.get("kill_refill", 0))
	if stats.extra_percent("hot_swap") > 0.0 and _hot_swap_left <= 0.0 and ammo < stats.magazine_size:
		_hot_swap_left = HOT_SWAP_COOLDOWN
		refill = stats.magazine_size
	if refill > 0 and ammo < stats.magazine_size:
		ammo = mini(ammo + refill, stats.magazine_size)
		if is_reloading and ammo >= stats.magazine_size:
			is_reloading = false
			reload_finished.emit()
		ammo_changed.emit(ammo, stats.magazine_size)
	if String(stats.behaviours.get("alt_fire", "")) == "launcher" and grenades < GRENADE_MAX:
		grenade_kills += 1
		if grenade_kills >= GRENADE_KILLS:
			grenade_kills = 0
			grenades += 1
			_refresh_status()


## True while the Shield emitter's frontal shield is up (during a reload).
func is_shield_up() -> bool:
	return is_reloading and bool(stats.behaviours.get("reload_shield", false))


func request_reload() -> void:
	if enabled and not is_reloading and ammo < stats.magazine_size:
		_burst_left = 0
		_start_reload()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_hot_swap_left = maxf(_hot_swap_left - delta, 0.0)
	_grenade_cooldown = maxf(_grenade_cooldown - delta, 0.0)
	_tick_overclock(delta)
	if bool(stats.behaviours.get("scanner", false)):
		_scan()
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
	if overheat_left > 0.0:
		return
	if stats.fire_mode() == "charge":
		_tick_charge(delta)
		return
	var wants_shot := _buffered_fire > 0.0 or (stats.fire_mode() == "auto" and _trigger_held)
	if wants_shot and _cooldown <= 0.0 and not is_reloading:
		_pull_trigger()


## Charge receiver: holding the trigger charges (from the moment the gun is ready), letting go
## fires one round at the charge reached (plan: Charge, hold to charge one heavy simulated shot).
func _tick_charge(delta: float) -> void:
	if charge_held >= 0.0:
		if is_reloading:
			charge_held = -1.0
			charge_changed.emit(-1.0)
			return
		charge_held += delta
		charge_changed.emit(charge_fraction())
		if not _trigger_held:
			var charge := charge_fraction()
			charge_held = -1.0
			charge_changed.emit(-1.0)
			_buffered_fire = 0.0
			if ammo <= 0:
				_start_reload()
				return
			_fire_round(charge)
			_cooldown = _shot_interval()
		return
	if (_trigger_held or _buffered_fire > 0.0) and _cooldown <= 0.0 and not is_reloading:
		_buffered_fire = 0.0
		if ammo <= 0:
			_start_reload()
			return
		# A tap that was already released fires at no charge on the next tick.
		charge_held = 0.0
		charge_changed.emit(0.0)


func charge_fraction() -> float:
	var time := stats.charge_time()
	return clampf(charge_held / time, 0.0, 1.0) if time > 0.0 and charge_held >= 0.0 else 0.0


## Seconds between rounds now: the build's, halved by Overclock up to the absolute cap.
func _shot_interval() -> float:
	if overclock_left > 0.0:
		return 1.0 / minf(stats.fire_rate * 2.0, WeaponStats.ABSOLUTE_FIRE_RATE_CAP)
	return stats.seconds_between_shots()


func _tick_overclock(delta: float) -> void:
	if overclock_left > 0.0:
		overclock_left -= delta
		if overclock_left <= 0.0:
			overclock_left = 0.0
			overheat_left = OVERHEAT_TIME
			_trigger_held = false
			_burst_left = 0
			_refresh_status()
	elif overheat_left > 0.0:
		overheat_left -= delta
		if overheat_left <= 0.0:
			overheat_left = 0.0
			_refresh_status()
	if _reload_pressed and not is_reloading and ammo >= stats.magazine_size:
		_reload_held += delta
		if _reload_held >= OVERCLOCK_HOLD:
			_reload_pressed = false
			start_overclock()


## The HUD's status beside the ammo: Overclock, overheat, or the grenades held.
func _refresh_status() -> void:
	var text := ""
	if overclock_left > 0.0:
		text = "OVERCLOCK"
	elif overheat_left > 0.0:
		text = "OVERHEATED"
	elif String(stats.behaviours.get("alt_fire", "")) == "launcher":
		text = "GRENADES %d" % grenades
	if text != _status_text:
		_status_text = text
		status_changed.emit(text)


## The Scanner's reading: one ray from the crosshair a tick (one reused query), reported only
## when the robot or its health changes.
func _scan() -> void:
	if _camera == null or not is_inside_tree():
		return
	_scan_query.from = _camera.global_position
	_scan_query.to = _camera.global_position - _camera.global_basis.z * SCAN_RANGE
	_scan_query.exclude = [_shooter_rid]
	var hit := get_world_3d().direct_space_state.intersect_ray(_scan_query)
	var enemy := hit.get("collider") as Enemy if not hit.is_empty() else null
	if enemy == null or not enemy.is_alive:
		if _scanned_id != 0:
			_scanned_id = 0
			_scanned_health = -1.0
			scanned.emit("", 0.0, 0.0)
		return
	if enemy.get_instance_id() != _scanned_id or not is_equal_approx(enemy.health, _scanned_health):
		_scanned_id = enemy.get_instance_id()
		_scanned_health = enemy.health
		scanned.emit(enemy.definition.display_name, maxf(enemy.health, 0.0), enemy.max_health)


func _process(delta: float) -> void:
	_kick = lerpf(_kick, 0.0, 1.0 - exp(-MODEL_RECOVERY * delta))
	if _flash_left != INF:
		_process_shield()
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
		_burst_left = size - 1
		_fire_round()
		_burst_timer = BURST_INTERVAL
		if _burst_left == 0:
			_cooldown = _burst_cooldown(size)
	else:
		_fire_round()
		_cooldown = _shot_interval()


## The pause after a burst, so bursts of `size` rounds sustain the build's fire rate.
func _burst_cooldown(size: int) -> float:
	return maxf(size * _shot_interval() - (size - 1) * BURST_INTERVAL, 0.05)


## Fires one round: every ray of the shot through the pipeline, then feedback and the auto reload.
## `charge` is a Charge receiver's charge, 0 to 1.
func _fire_round(charge := 0.0) -> void:
	# Overflow: some shots cost no round.
	var free_chance := stats.extra_percent(WeaponStats.FREE_SHOT_KEY)
	if free_chance <= 0.0 or _rng.randf() >= free_chance:
		ammo -= 1
	shots_fired += 1
	var shot := ShotPipeline.ShotState.new()
	shot.rng = _rng
	shot.scene = self
	shot.charge = charge
	shot.player_health_fraction = player_health_fraction
	shot.overclock_active = overclock_left > 0.0
	# Triplet: the last round of a burst always crits (_burst_left is already counted down).
	shot.force_crit = bool(stats.behaviours.get("burst_final_crit", false)) and stats.fire_mode() == "burst" and _burst_left == 0
	shot.ammo_refund_chance = float(stats.extra.get(WeaponStats.AMMO_REFUND_KEY, {}).get("percent", 0.0))
	shot.chain_chance = float(stats.extra.get(WeaponStats.CHAIN_ON_CRIT_KEY, {}).get("percent", 0.0))
	if _camera != null:
		var ray_count := int(stats.behaviours.get("ray_count", 1))
		var profile_id := String(stats.behaviours.get("projectile", "hitscan"))
		for ray in ray_count:
			var direction := _ray_direction(ray, ray_count)
			if profile_id != "hitscan" and ProjectilePool.current != null and ProjectilePool.PROFILES.has(profile_id):
				ProjectilePool.current.fire_player_round(_shooter_rid, _camera.global_position, direction, stats, shot,
					ProjectilePool.PROFILES[profile_id], stats.behaviours.get("projectile_color", PLAYER_ROUND_COLOR))
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
			Fx.damage_number(self, hit.position, hit.damage, hit.killed, hit.weak_point)
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
	_shot_sound.pitch_scale = randf_range(0.94, 1.06) * (1.12 if stats.fire_mode() == "burst" else 1.0) \
		* (0.75 if stats.fire_mode() == "charge" else 1.0)
	_shot_sound.play()


func _start_reload() -> void:
	if overclock_left > 0.0 and ammo > 0:
		return # Overclock runs on what is loaded; the reload waits for an empty magazine.
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


func _process_shield() -> void:
	var up := is_shield_up()
	if _shield_pane.visible != up:
		_shield_pane.visible = up


## Shows the muzzle flash and its light for the shader warm-up (FxPool.warm_up) until called with
## false, with the light reaching the whole arena at no brightness. The Compatibility renderer
## compiles a lit variant of a material's shader the first time a point light touches it; without
## this, every material the muzzle light reaches for the first time compiled mid-shot, which is a
## frozen frame in the browser (nearly a second for the first hit on an enemy under llvmpipe).
func set_warm_up_flash(active: bool) -> void:
	if active:
		_flash_light.omni_range = WARM_UP_LIGHT_RANGE
		_flash_light.light_energy = 0.0
		_flash_left = INF
		_flash_frames = 0
		_set_flash_visible(true)
	else:
		_flash_light.omni_range = _light_range
		_flash_light.light_energy = _light_energy
		_flash_left = 0.0
		_set_flash_visible(false)
	# Every attachment mesh and the reload shield are drawn too, so fitting one compiles nothing.
	for part in _parts.values():
		(part as Node3D).visible = active or part.get_meta("fitted", false)
	_shield_pane.visible = active


## Refits the placeholder model from the equipped bases' `visual` hints: a longer slide for long
## barrels, a taller or shorter grip for magazines, a tinted slide for receivers, a muzzle extension.
func _apply_visuals() -> void:
	var slide_length := 1.0
	var grip_height := 1.0
	var slide_color: Variant = null
	var extension := false
	var muzzle_scale := 1.0
	var shown := {}
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
		for key in ["optic", "underbarrel"]:
			if definition.visual.has(key):
				shown[String(definition.visual[key])] = true
		muzzle_scale = maxf(muzzle_scale, float(definition.visual.get("muzzle_scale", 1.0)))
	_slide.scale = Vector3(_slide_rest_scale.x, _slide_rest_scale.y, _slide_rest_scale.z * slide_length)
	# Grow the slide forward: its mesh is centred, so shift it by half the added length.
	_slide.position.z = -0.13 * (slide_length - 1.0)
	_grip.scale = Vector3(_grip_rest_scale.x, _grip_rest_scale.y * grip_height, _grip_rest_scale.z)
	_grip.position.y = -0.085 - 0.06 * (grip_height - 1.0)
	_muzzle.position.z = BASE_MUZZLE_Z - 0.26 * (slide_length - 1.0) - (0.06 if extension else 0.0)
	_barrel_extension.visible = extension
	_barrel_extension.scale = Vector3(muzzle_scale, 1.0, muzzle_scale) # the cylinder runs along its local Y
	_barrel_extension.position.z = BASE_MUZZLE_Z - 0.26 * (slide_length - 1.0) - 0.03
	for id in _parts:
		var part: Node3D = _parts[id]
		part.set_meta("fitted", shown.has(id))
		part.visible = shown.has(id)
	if slide_color is Color:
		var material := StandardMaterial3D.new()
		material.albedo_color = slide_color
		material.metallic = 0.6
		material.roughness = 0.4
		_slide.material_override = material
	else:
		_slide.material_override = null


## The optic and underbarrel placeholders, built once from the gun's own materials (their shaders
## already compile for the slide), and the Shield emitter's pane.
func _build_parts() -> void:
	var metal: Material = _slide.mesh.surface_get_material(0) if _slide.mesh else null
	var sight: MeshInstance3D = $Model/FrontSight
	var accent: Material = sight.mesh.surface_get_material(0) if sight.mesh else null
	_add_part("reflex", _box(Vector3(0.04, 0.035, 0.012), accent), Vector3(0.0, 0.065, -0.02))
	_add_part("scanner", _box(Vector3(0.035, 0.03, 0.07), metal), Vector3(0.0, 0.06, 0.02))
	_add_part("rangefinder", _box(Vector3(0.02, 0.02, 0.09), accent), Vector3(0.035, 0.03, -0.05))
	_add_part("grip", _box(Vector3(0.025, 0.06, 0.025), metal), Vector3(0.0, -0.06, -0.08))
	_add_part("laser", _box(Vector3(0.02, 0.02, 0.06), accent), Vector3(0.0, -0.035, -0.09))
	_add_part("launcher", _box(Vector3(0.04, 0.04, 0.16), metal), Vector3(0.0, -0.05, -0.1))
	_add_part("shield", _box(Vector3(0.05, 0.025, 0.05), accent), Vector3(0.0, -0.04, -0.06))
	_shield_pane = MeshInstance3D.new()
	var pane := QuadMesh.new()
	pane.size = Vector2(0.9, 0.5)
	var glass := StandardMaterial3D.new()
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.4, 0.75, 1.0, 0.18)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	pane.material = glass
	_shield_pane.mesh = pane
	_shield_pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shield_pane.position = Vector3(-0.2, 0.1, -0.7)
	_shield_pane.visible = false
	add_child(_shield_pane)


func _add_part(id: String, mesh: Mesh, at: Vector3) -> void:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	_model.add_child(node)
	_parts[id] = node


func _box(size: Vector3, material: Material) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	return box
