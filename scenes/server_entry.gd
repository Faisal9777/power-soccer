extends PanelContainer
@onready var name_label = $MarginContainer/HBoxContainer/NameLabel
@onready var players_label = $MarginContainer/HBoxContainer/PlayersLabel
@onready var ping_label = $MarginContainer/HBoxContainer/PingLabel
@onready var join_button = $MarginContainer/HBoxContainer/JoinButton

var server_data

func setup(data):
	server_data = data
	if not name_label:
		print("name label is null")
	name_label.text = data.name
	players_label.text = "%d/%d" % [data.players, data.max]
	ping_label.text = "%d ms" % data.ping

func _ready():
	join_button.pressed.connect(_on_join_pressed)

func _on_join_pressed():
	print("Joining:", server_data.name)
	# Later: emit signal instead of print
