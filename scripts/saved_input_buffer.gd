class_name SavedInputBuffer
extends InputBuffer

var _queue: Array[Dictionary] = []


# =========================================================
# Optional: last returned input (for debugging/replay)
# =========================================================
var last_input: Dictionary = {}


# =========================================================
# Server injects input here
# (called when network packet arrives)
# =========================================================
func save_input(cmd: Dictionary) -> void:
	_queue.append(cmd)


# =========================================================
# Controller pulls input in order (FIFO)
# =========================================================
func get_input() -> Dictionary:

	if _queue.is_empty():
		return {}

	var cmd: Dictionary = _queue.pop_front()

	last_input = cmd
	return cmd


# =========================================================
# Optional helpers
# =========================================================

func size() -> int:
	return _queue.size()


func clear() -> void:
	_queue.clear()
