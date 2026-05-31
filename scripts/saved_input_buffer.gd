class_name SavedInputBuffer
extends InputBuffer

var _queue: Array[Dictionary] = []
var pending_input := {} 
# =========================================================
# Optional: last returned input (for debugging/replay)
# =========================================================

# =========================================================
# Server injects input here
# (called when network packet arrives)
# =========================================================
func save_input(cmd: Array) -> void:
	_queue += cmd

func push_back(input: Dictionary) -> void:
	_queue.append(input)

func push_input(input: Dictionary) -> void:
	pending_input = input

# =========================================================
# Controller pulls input in order (FIFO)
# =========================================================
func _get_input() -> Dictionary:
	return pending_input

func _generate_sequence() -> void:
	seq = pending_input["seq"]

# =========================================================
# Optional helpers
# =========================================================

func size() -> int:
	return _queue.size()


func clear() -> void:
	_queue.clear()
