class_name Skills
extends RefCounted
## The three skill trees (plan: Skill trees): Marksman, Engineer and Survivor, eight nodes and a
## capstone each, drawn by the bench from data/skills/skill_trees.tres. Skill points come from
## player levels (experience from kills and clears, one point a level) and one per first boss
## kill. Respec is free. Skills survive Reforge. Pure functions over the save's {id: rank} map, so
## the bench, Progression, the stats function and the tests share them.

const DATA_PATH := "res://data/skills/skill_trees.tres"
const TREES: Array[StringName] = [&"marksman", &"engineer", &"survivor"]
const TREE_NAMES := {"marksman": "Marksman", "engineer": "Engineer", "survivor": "Survivor"}
const TREE_THEMES := {
	"marksman": "Precision, crits and weak points",
	"engineer": "Gun behaviour, ammo and crafting",
	"survivor": "Movement, health and sustain",
}
## Points a tree needs spent in it before its next tier opens.
const POINTS_PER_TIER := 2
const CAPSTONE_TIER := 4
const MAX_LEVEL := 50
## Experience to reach level n + 1 from level n: XP_BASE * XP_GROWTH^(n - 1). Kills pay their
## definition's credit reward in experience, scaled like credits; a clear pays its bonus. Tuned so
## a first run to wave 20 reaches about level 15 (see GAME_PLAN.md, "Starting tuning values").
const XP_BASE := 40.0
const XP_GROWTH := 1.2

static var _data: SkillTreeData
static var _by_id: Dictionary = {}


static func all() -> Array[SkillDefinition]:
	_load()
	return _data.nodes if _data else ([] as Array[SkillDefinition])


static func get_definition(id: StringName) -> SkillDefinition:
	_load()
	return _by_id.get(String(id))


## The tree's nodes, by tier then file order; the capstone last.
static func nodes_of(tree: StringName) -> Array[SkillDefinition]:
	var result: Array[SkillDefinition] = []
	for node in all():
		if node.tree == tree:
			result.append(node)
	result.sort_custom(func(a: SkillDefinition, b: SkillDefinition) -> bool: return a.tier < b.tier)
	return result


static func points_in(tree: StringName, ranks: Dictionary) -> int:
	var count := 0
	for id in ranks:
		var node := get_definition(StringName(String(id)))
		if node and node.tree == tree and int(ranks[id]) > 0:
			count += 1
	return count


static func spent(ranks: Dictionary) -> int:
	var count := 0
	for id in ranks:
		if get_definition(StringName(String(id))) != null and int(ranks[id]) > 0:
			count += 1
	return count


## Why the node cannot be taken with these ranks and `available` points, or "".
static func block_reason(id: StringName, ranks: Dictionary, available: int) -> String:
	var node := get_definition(id)
	if node == null:
		return "Unknown skill"
	if int(ranks.get(String(id), 0)) > 0:
		return "Taken"
	var in_tree := points_in(node.tree, ranks)
	if node.capstone:
		var others := nodes_of(node.tree).size() - 1
		if in_tree < others:
			return "Needs every other %s node (%d of %d)" % [TREE_NAMES[String(node.tree)], in_tree, others]
	elif in_tree < node.tier * POINTS_PER_TIER:
		return "Needs %d points in %s" % [node.tier * POINTS_PER_TIER, TREE_NAMES[String(node.tree)]]
	if available <= 0:
		return "No skill points"
	return ""


## Player-side effects of every taken node, summed by key.
static func player_effects(ranks: Dictionary) -> Dictionary:
	var effects := {}
	for id in ranks:
		var node := get_definition(StringName(String(id)))
		if node == null or int(ranks[id]) <= 0:
			continue
		for key in node.player_effects:
			effects[key] = float(effects.get(key, 0.0)) + float(node.player_effects[key])
	return effects


## Experience from level `level` to the next.
static func xp_to_next(level: int) -> int:
	return roundi(XP_BASE * pow(XP_GROWTH, maxi(level, 1) - 1))


## The level a total experience reaches, from level 1.
static func level_for_xp(xp: int) -> int:
	var level := 1
	var left := xp
	while level < MAX_LEVEL and left >= xp_to_next(level):
		left -= xp_to_next(level)
		level += 1
	return level


## Experience into the current level and the amount the next one needs.
static func level_progress(xp: int) -> Vector2i:
	var level := 1
	var left := xp
	while level < MAX_LEVEL and left >= xp_to_next(level):
		left -= xp_to_next(level)
		level += 1
	return Vector2i(left, xp_to_next(level))


static func _load() -> void:
	if _data != null:
		return
	_data = load(DATA_PATH) as SkillTreeData
	_by_id.clear()
	if _data:
		for node in _data.nodes:
			_by_id[String(node.id)] = node
