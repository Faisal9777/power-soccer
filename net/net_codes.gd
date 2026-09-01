extends RefCounted
class_name NetCodes

# Bump this if you change ids in a breaking way
const PROTOCOL_VERSION := 1

enum session_message {
	REGISTER_PEER = 7,
	REGISTRATION_COMPLETE = 8,
	SESSION_DATA = 12,
	SCENE_ACTION = 13,
	REJECT = 14,
}

enum Msg {
	INIT_BEGIN = 1,
	INIT_DONE  = 2,
	GAME_ROSTER = 3,
	SET_PLAYERS   = 4,
	GAME_BEGIN       = 5,
	GAME_END       = 6,
	SNAPSHOTS = 9,
	ROUND_START = 10,
	INPUTS = 11,
	DISCRETE_INPUTS = 15
}

enum Lobby_action {
	READY = 1
}

const backend = {
	PLAYER_JOINED = "/player-joined",
	PLAYER_DISCONNECTED = "/player-disconnected"
}

enum MatchAction {
	END = 1
}

enum States {
	STATE = -1,
	TITLE = 0,
	LOBBY = 1,
	WORLD = 2,
	SCOREBOARD = 3
}

enum message {
	SESSION = -1,
	STATE = 0
}

enum state_message {
	PLAYER_RECONNECT = 17,
	CHANGE_STATE = 0,
	STATE = 1,
	PLAYER_CONNECT = 18
}

enum ResponseType{
	NEW_SERVER = 0,
	REJOIN = 1,
	REJECTED = 2
}

class Rpc:
	const INPUT_STREAM := "receive_network_input_dictionary"
	const INPUT_BY_ID := "receive_network_input_by_id"
