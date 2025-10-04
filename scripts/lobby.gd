extends Control

@onready var status_label: Label = $PanelContainer/VBoxContainer/StatusLabel
@onready var player_list: ItemList = $PanelContainer/VBoxContainer/PlayerList
@onready var start_btn: Button = $PanelContainer/VBoxContainer/HBoxContainer/StartButton
@onready var leave_btn: Button = $PanelContainer/VBoxContainer/HBoxContainer/LeaveButton

func _ready() -> void:
	# Host creates lobby with his own name already in players.
	if GameState.players.is_empty():
		GameState.players.append(GameState.player_name)
		GameState.is_host = true

	_refresh_ui()

	# In this stub, Start does nothing yet; disable if not host
	start_btn.disabled = !GameState.is_host

	start_btn.pressed.connect(func():
		print("TODO: host starts match")
	)

	leave_btn.pressed.connect(func():
		GameState.reset_lobby()
		get_tree().change_scene_to_file("res://title_screen.tscn")
	)

func _refresh_ui() -> void:
	player_list.clear()
	for name in GameState.players:
		var label := name
		if GameState.is_host and name == GameState.player_name:
			label += " (Host)"
		player_list.add_item(label)
	status_label.text = "Connected: %d" % GameState.players.size()
