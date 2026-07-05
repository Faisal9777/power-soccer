# task_scheduler.gd
class_name JobScheduler
extends Node

func schedule(callable: Callable, delay: float) -> Timer:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = delay
	timer.timeout.connect(func():
		callable.call()
		timer.queue_free()
	)
	add_child(timer)
	timer.start()
	return timer

func schedule_repeating(callable: Callable, interval: float) -> Timer:
	var timer := Timer.new()
	timer.one_shot = false
	timer.wait_time = interval
	timer.timeout.connect(callable)
	add_child(timer)
	timer.start()
	return timer

func cancel(timer: Timer) -> void:
	if is_instance_valid(timer):
		timer.queue_free()
