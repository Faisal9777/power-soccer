class_name SavedInputBuffer
extends InputBuffer

var _queue: Array[Dictionary] = []
var _queued_sequences: Dictionary = {}
var _next_expected_seq: int = -1
var _last_input: Dictionary = {}
var _ticks_since_input: int = 0
const HOLD_TICKS := 3   # ~50ms at 60Hz before decaying to neutral

func save_input(cmd: Array) -> void:
	var added := false
	for input in cmd:
		if input is Dictionary and push_input(input):
			added = true
	if added:
		_queue.sort_custom(func(a: Dictionary, b: Dictionary): return int(a["seq"]) < int(b["seq"]))

func push_back(input: Dictionary) -> void:
	push_input(input)

func push_input(input: Dictionary) -> bool:
	if not input.has("seq"):
		return false
	var input_seq := int(input["seq"])
	if last_processed_seq >= 0 and input_seq <= last_processed_seq:
		return false
	if _queued_sequences.has(input_seq):
		return false
	_queue.append(input.duplicate(true))
	_queued_sequences[input_seq] = true
#	_queue.sort_custom(func(a: Dictionary, b: Dictionary): return int(a["seq"]) < int(b["seq"]))
	return true

func _held_or_empty() -> Dictionary:
	_ticks_since_input += 1
	if not _last_input.is_empty() and _ticks_since_input <= HOLD_TICKS:
		current_input = _last_input
	else:
		current_input = {}
	return current_input

func get_input() -> Dictionary:
	if _queue.is_empty():
		return _held_or_empty()

	if _next_expected_seq < 0 or last_processed_seq < 0:
		_next_expected_seq = int(_queue[0]["seq"])

	while not _queue.is_empty() and int(_queue[0]["seq"]) < _next_expected_seq:
		var stale = _queue.pop_front()
		_queued_sequences.erase(int(stale["seq"]))

	if _queue.is_empty():
		return _held_or_empty()

	if int(_queue[0]["seq"]) > _next_expected_seq:
		if _queue.size() > 2 or _next_expected_seq <= 0:
			_next_expected_seq = int(_queue[0]["seq"])
		else:
			return _held_or_empty()

	current_input = _queue.pop_front()
	seq = int(current_input["seq"])
	_queued_sequences.erase(seq)
	last_processed_seq = seq
	_next_expected_seq = seq + 1
	_last_input = current_input
	_ticks_since_input = 0
	return current_input

func size() -> int:
	return _queue.size()

func clear() -> void:
	_queue.clear()
	_queued_sequences.clear()
	_next_expected_seq = -1
	_last_input = {}
	_ticks_since_input = 0
