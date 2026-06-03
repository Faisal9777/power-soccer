extends Control

signal next_pressed
signal exit_pressed

@export var _next: Button                    # assign NextButton
@export var _countdown_label: Label          # assign the label beside Next
@export var auto_advance_seconds: int = 10
@export var next_scene_path: String = "res://scenes/ScoreboardScene.tscn"     # optional: path for next scene

var _remaining: float = 0.0
var _last_shown_secs: int = -1
var _fired: bool = false

func _ready() -> void:
	print("Win Scene loaded")
	# Ensure it runs even when the game world is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	mouse_filter = Control.MOUSE_FILTER_STOP

	if _next:
		_next.pressed.connect(_on_next_pressed)
		_next.text = "Next"
	

	_remaining = float(max(1, auto_advance_seconds))
	_update_countdown_label(int(_remaining))
	

func _process(delta: float) -> void:
	if _fired:
		return

	_remaining -= delta
	var secs: int = max(0, ceili(_remaining))

	if secs != _last_shown_secs:
		_last_shown_secs = secs
		_update_countdown_label(secs)

	if _remaining <= 0.0:
		_fired = true
		_on_next_pressed()

func _update_countdown_label(secs: int) -> void:
	if _countdown_label:
		_countdown_label.text = "%ds" % secs

func _on_next_pressed() -> void:
	
	next_pressed.emit()
	if next_scene_path != "":
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		get_tree().paused = false
		SessionManager.session_node.change_state("Scoreboard")

func _on_exit_pressed() -> void:
	exit_pressed.emit()
