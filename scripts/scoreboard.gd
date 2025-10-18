extends Control

@export var left_team_name: String = "Blue"
@export var right_team_name: String = "Purple"
@export var left_score: int = 0
@export var right_score: int = 0

@onready var _label: Label = $Text

func _ready() -> void:
	_refresh()

func set_scores(left: int, right: int) -> void:
	left_score = max(left, 0)
	right_score = max(right, 0)
	_refresh()

func add_left(delta: int = 1) -> void:
	left_score = max(left_score + delta, 0)
	_refresh()

func add_right(delta: int = 1) -> void:
	right_score = max(right_score + delta, 0)
	_refresh()

func set_team_names(left_name: String, right_name: String) -> void:
	left_team_name = left_name
	right_team_name = right_name
	_refresh()

func _refresh() -> void:
	_label.text = "%s %d - %d %s" % [left_team_name, left_score, right_score, right_team_name]
