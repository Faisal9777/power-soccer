extends Node

const LOADING_OVERLAY_SCENE := preload("res://UI/loading/LoadingOverlay.tscn")

var _overlay: CanvasLayer = null

func _ready() -> void:
	# Create once and keep it alive globally
	_overlay = LOADING_OVERLAY_SCENE.instantiate()
	get_tree().root.add_child.call_deferred(_overlay)

func _get_overlay():
	if _overlay == null:
		return null
	return _overlay

func show_loading(title_text: String = "Loading...") -> void:
	var ov = _get_overlay()
	if ov == null:
		return
	ov.show()

func set_progress_percent(percent: float) -> void:
	var ov = _get_overlay()
	if ov == null:
		return
	ov.set_progress_percent(percent)

func set_status(text: String) -> void:
	var ov = _get_overlay()
	if ov == null:
		return
	ov.set_status(text)

func hide_loading() -> void:
	var ov = _get_overlay()
	if ov == null:
		return
	ov.hide()
