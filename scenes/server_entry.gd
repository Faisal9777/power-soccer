extends PanelContainer
@onready var name_label = $MarginContainer/HBoxContainer/NameLabel
@onready var players_label = $MarginContainer/HBoxContainer/PlayersLabel
@onready var ping_label = $MarginContainer/HBoxContainer/PingLabel
@onready var join_button = $MarginContainer/HBoxContainer/JoinButton

var server_data

func setup(data):
	print("data in tthe entry; ", data)
	server_data = data
	if not name_label:
		print("name label is null")
	name_label.text = data.get("name", "Unknown Server")
	players_label.text = "%d/%d" % [data.get("players", 0), data.get("lobby_size", 0)]
	ping_label.text = "%d ms" % data.get("ping", 0)

func update_status(data):
	setup(data)
