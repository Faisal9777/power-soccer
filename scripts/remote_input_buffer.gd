class_name RemoteInputBuffer
extends InputBuffer


# =========================================================
# Internal queue of inputs
# =========================================================
var _queue: Array[Dictionary] = []


# =========================================================
# Optional: last returned input (for debugging/replay)
# =========================================================
var last_input: Dictionary = {
	"mvx": 0.0,
	"mvz": 0.0,
	"sprint": false,
	"move_magnitude": 0.0,
	"yaw": 0.0,
	"pitch": 0.0,
	"seq": -1
}


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

	if not _queue.is_empty():
		var cmd: Dictionary = _queue.pop_front()
		last_input = cmd
		return cmd

	# No new packet this tick.
	# Continue using the most recent input instead of
	# creating an artificial neutral frame.
	return last_input.duplicate(true)


# =========================================================
# Optional helpers
# =========================================================

func size() -> int:
	return _queue.size()


func clear() -> void:
	_queue.clear()
