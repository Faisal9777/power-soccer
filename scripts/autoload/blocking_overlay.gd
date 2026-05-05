# blocking_overlay.gd
extends CanvasLayer
@onready var label: Label = $ColorRect/CenterContainer/PanelContainer/MarginContainer/VBoxContainer/Label


func _ready() -> void:
	hide()

func show_overlay(message: String) -> void:
	label.text = message
	show()

func hide_overlay() -> void:
	hide()
