class_name SavedInputBuffer
extends InputBuffer

var _queue: Array[Dictionary] = []
var _queued_sequences: Dictionary = {}
var _next_expected_seq: int = -1

# =========================================================
# Server injects input here
# (called when network packet arrives)
# =========================================================
func save_input(cmd: Array) -> void:
	for input in cmd:
		if input is Dictionary:
			push_input(input)

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
	_queue.sort_custom(func(a: Dictionary, b: Dictionary): return int(a["seq"]) < int(b["seq"]))
	return true

# =========================================================
# Controller pulls input in order (FIFO)
# =========================================================
func get_input() -> Dictionary:
	if _queue.is_empty():
		current_input = {}
		return current_input

	# Initialize sequence on first received command
	if _next_expected_seq < 0 or last_processed_seq < 0:
		_next_expected_seq = int(_queue[0]["seq"])

	# Discard any stale inputs already processed
	while not _queue.is_empty() and int(_queue[0]["seq"]) < _next_expected_seq:
		var stale = _queue.pop_front()
		_queued_sequences.erase(int(stale["seq"]))

	if _queue.is_empty():
		current_input = {}
		return current_input

	# If there is a sequence gap: if the queue has buffered commands, advance to prevent deadlocks
	if int(_queue[0]["seq"]) > _next_expected_seq:
		if _queue.size() > 2 or _next_expected_seq <= 0:
			_next_expected_seq = int(_queue[0]["seq"])
		else:
			current_input = {}
			return current_input

	current_input = _queue.pop_front()
	seq = int(current_input["seq"])
	_queued_sequences.erase(seq)
	last_processed_seq = seq
	_next_expected_seq = seq + 1
	return current_input

# =========================================================
# Optional helpers
# =========================================================

func size() -> int:
	return _queue.size()

func clear() -> void:
	_queue.clear()
	_queued_sequences.clear()
	_next_expected_seq = -1
