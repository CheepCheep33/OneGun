class_name Story
extends RefCounted
## Looks up the authored story (data/story/story.tres). Progression owns which triggers have
## fired (save: story_flags) and which lines wait to be read at the bench (story_queue); this
## class only answers what a trigger says. A trigger fires once per save.

const DATA: StoryData = preload("res://data/story/story.tres")
## The bench's Story tab lists logs (trigger ids that start with this) as recovered files.
const LOG_PREFIX := "log_"


static func has(trigger: String) -> bool:
	return DATA.lines.has(trigger)


## [[speaker, text], ...] for a trigger, empty when it has none.
static func lines_for(trigger: String) -> Array:
	return DATA.lines.get(trigger, [])


static func is_log(trigger: String) -> bool:
	return trigger.begins_with(LOG_PREFIX)


## Every trigger id, in authored order.
static func triggers() -> Array:
	return DATA.lines.keys()


## "Speaker: text" lines joined for a card or the bench.
static func describe(trigger: String) -> String:
	var parts := PackedStringArray()
	for line in lines_for(trigger):
		parts.append("%s: %s" % [line[0], line[1]])
	return "\n".join(parts)
