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
}
