extends Node
const C = preload("res://scripts/shared/scene.gd")
var current_scene := -1
var current_state : Node
var state_init_data

func register_state(state):
	current_state = state
	if state_init_data:
		current_state.sync_init(state_init_data)
		state_init_data = null

func change_state(state, state_data=null):
	state_init_data = state_data
	_change_state(state)

func handle_data(data):
	if current_state:
		current_state.handle_data(data)

func send_data_id(target_id, value):
	SessionManager.send_data_id(target_id, value)

func send_data(value):
	SessionManager.send_data(value)

func _ready() -> void:
	LevelContainer.world_ready.connect(_on_world_node_ready)

func _physics_process(delta: float) -> void:
	if Input.is_action_pressed("debug"):
		print("the user id of the current game is: ", GameState.user_id)

func _change_state(state_info: int):
	var scene_to_load = ""
	current_state = null
	current_scene = state_info
	if state_info == NetCodes.States.LOBBY:
		scene_to_load = C.LOBBY
	if state_info == NetCodes.States.WORLD:
		scene_to_load = C.WORLD
	elif state_info == NetCodes.States.SCOREBOARD:
		scene_to_load = C.SCORE
	elif state_info == NetCodes.States.TITLE:
		scene_to_load = C.TITLE
		SessionManager.session_node.disconnect_connection()
		SessionManager.session_node.queue_free()
	get_tree().change_scene_to_file(scene_to_load)

func on_connected_to_server(server_info):
	_change_state(server_info.get("current_state"))

func _on_world_node_ready(node):
	var old_scene = get_tree().current_scene
	get_tree().current_scene = node   # World stays nested under LevelContainer — no reparenting
	if old_scene:
		old_scene.queue_free()
