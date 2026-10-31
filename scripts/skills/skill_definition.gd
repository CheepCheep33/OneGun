class_name SkillDefinition
extends Resource
## One skill tree node (plan: Skill trees). Numeric effects are StatModifiers that feed
## WeaponStats.build like attachments do, so previews stay truthful; player-side effects (health,
## speed, plating, dash...) are read by Progression.player_effects(). Capstones are the only nodes
## with behaviour of their own (Bullet Time, Overclock, Phoenix), read by the pistol and the player
## from the same keys. Authored in data/skills/skill_trees.tres.

@export var id: StringName = &""
## "marksman", "engineer" or "survivor".
@export var tree: StringName = &"marksman"
@export var display_name := ""
@export_multiline var description := ""
## 0 to 3 for the eight nodes (two per tier), 4 for the capstone. A node of tier n needs
## Skills.POINTS_PER_TIER * n points spent in its tree; the capstone needs every other node of it.
@export var tier := 0
@export var capstone := false
@export var modifiers: Array[StatModifier] = []
## Player-side effects summed over taken nodes: max_health, move_speed (fraction), plating (flat
## per hit), heal_per_kill, pickup_scale (fraction), dash, loot_luck (fraction), craft_discount,
## phoenix.
@export var player_effects: Dictionary = {}
