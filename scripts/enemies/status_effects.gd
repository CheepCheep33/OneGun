class_name StatusEffects
extends RefCounted
## Tuning for the enemy-side status effects (plan: interaction rules, status stacking). Ammo names
## an effect in its `on_hit` behaviour; the enemy owns the timers and the look (Enemy.apply_burn,
## apply_slow, apply_stun). The same status refreshes its duration and never stacks its damage;
## different statuses coexist, and since only three kinds exist (burn, slow, stun) the plan's cap of
## three per enemy holds by construction. Status damage (burn ticks, shatter) never procs and
## ignores armour. Tuning values, not balance.

## Incendiary: a burn deals this share of the hit that lit it every second, for BURN_DURATION.
const BURN_SHARE_PER_SECOND := 0.4
const BURN_DURATION := 3.0
const BURN_TICK := 0.5
## Cryo: slows by SLOW_SHARE for SLOW_DURATION. A Cryo hit on a robot slowed for at least
## SHATTER_AFTER seconds shatters the frost instead: SHATTER_SHARE of the hit to it and to every
## robot within SHATTER_RADIUS, and the slow is gone.
const SLOW_SHARE := 0.4
const SLOW_DURATION := 2.5
const SHATTER_AFTER := 1.0
const SHATTER_SHARE := 0.5
const SHATTER_RADIUS := 2.5
## Shock: every hit arcs once (ShotPipeline's chain rules) for SHOCK_SHARE and stuns the robot it
## lands on for SHOCK_STUN seconds.
const SHOCK_SHARE := 0.5
const SHOCK_STUN := 0.4
## Stillwater (the Long barrel's Legendary): robots it hits are slowed this much.
const PIERCE_SLOW_SHARE := 0.35
const PIERCE_SLOW_DURATION := 2.0
## The glow a robot shows while a status is on it and no telegraph is lit.
const BURN_GLOW := Color(1.0, 0.35, 0.05) * 0.9
const SLOW_GLOW := Color(0.35, 0.7, 1.0) * 0.8
const STUN_GLOW := Color(0.7, 0.75, 1.0) * 1.4
const SHATTER_COLOR := Color(0.55, 0.85, 1.0, 0.3)
