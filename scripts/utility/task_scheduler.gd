extends Node
# =========================================================
# Task definition
# =========================================================
class Task:

	var id: int
	var interval: float
	var elapsed := 0.0

	var callback: Callable
	var repeating := true

	var cancelled := false


# =========================================================
# Scheduler state
# =========================================================
var _tasks := {}        # id -> Task
var _next_id := 1


# =========================================================
# Schedule a repeating or one-shot task
#
# Example:
# var id = TaskScheduler.schedule(20.0, func(): print("tick"))
# =========================================================
func schedule(rate_hz: float, callback: Callable, repeating := true) -> int:

	var task := Task.new()

	task.id = _next_id
	_next_id += 1

	task.interval = 1.0 / max(rate_hz, 0.0001)
	task.callback = callback
	task.repeating = repeating

	_tasks[task.id] = task

	return task.id


# =========================================================
# Remove task manually (your design requirement)
# =========================================================
func remove(task_id: int) -> void:
	_tasks.erase(task_id)


# =========================================================
# Optional: mark task as cancelled (lazy removal)
# =========================================================
func cancel(task_id: int) -> void:
	if _tasks.has(task_id):
		_tasks[task_id].cancelled = true


# =========================================================
# Main update loop
# =========================================================
func _process(delta: float) -> void:

	# iterate over a copy to avoid mutation issues
	for id in _tasks.keys().duplicate():

		var task: Task = _tasks[id]

		# hard removal
		if task.cancelled:
			_tasks.erase(id)
			continue

		task.elapsed += delta

		if task.elapsed >= task.interval:

			task.elapsed -= task.interval

			if task.callback.is_valid():
				task.callback.call()

			# auto-remove one-shot tasks
			if not task.repeating:
				_tasks.erase(id)
