extends RefCounted
class_name NetCodes

# Bump this if you change ids in a breaking way
const PROTOCOL_VERSION := 1

enum Msg {
	INIT_BEGIN = 1,
	INIT_DONE  = 2,
	GAME_ROSTER = 3,
	SET_PLAYERS   = 4,
	GAME_BEGIN       = 5,
	GAME_END       = 6,
	REGISTER_PEER = 7,
	ROSTER_DATA = 8,
	SNAPSHOTS = 9
}


class Rpc:
	const INPUT_STREAM := "receive_network_input_dictionary"
	const INPUT_BY_ID := "receive_network_input_by_id"
