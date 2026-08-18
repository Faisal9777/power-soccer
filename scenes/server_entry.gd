extends PanelContainer

@onready var lock_icon = $MarginContainer/HBoxContainer/LeftGroup/LockIcon
@onready var name_label = $MarginContainer/HBoxContainer/LeftGroup/NameLabel
@onready var network_label = $MarginContainer/HBoxContainer/RightGroup/NetworkLabel
@onready var players_label = $MarginContainer/HBoxContainer/RightGroup/PlayersLabel
@onready var ping_label = $MarginContainer/HBoxContainer/RightGroup/PingLabel
@onready var join_button = $MarginContainer/HBoxContainer/RightGroup/JoinButton

const LOCKED_ICON = preload("res://Texture/lock.png")

var server_data

func setup(data):
	print("data in the entry: ", data)


	server_data = data
	
	name_label.text = data.get("name", "Unknown Server")
	players_label.text = "%d/%d" % [
		data.get("players_connected", 0),
		data.get("lobby_size", 0)
	]
	ping_label.text = "%d ms" % data.get("ping", 0)

	# Public / Private
	var is_public = data.get("is_public", true)
	if is_public:
		lock_icon.texture = null
	else:
		lock_icon.texture = LOCKED_ICON

	# LAN / Cloud
	var is_lan = data.get("is_lan", true)
	network_label.text = "LAN" if is_lan else "Cloud"

func update_status(data):
	setup(data)
