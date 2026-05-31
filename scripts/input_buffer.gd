class_name InputBuffer
extends RefCounted
var current_input : Dictionary = {}
var seq := -1

func get_input() -> Dictionary:
	_generate_input_sequence()
	current_input = _get_input()
	current_input['seq'] = seq
	return current_input

func _generate_input_sequence() -> void:
	seq += 1

func _get_input() -> Dictionary:
	return {}
