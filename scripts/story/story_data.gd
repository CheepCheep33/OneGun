class_name StoryData
extends Resource
## The authored story (plan: chapters 1 to 4). `lines` maps a trigger id to a list of
## [speaker, text] pairs: wave_N fires on the first clear of wave N, boss_<id> on a boss's first
## spawn, log_<area>_<n> when an area run reaches that point, and the rest name their moment.
## Generated from the story script; edit the text here, the ids are referenced by code.

@export var lines: Dictionary = {}
