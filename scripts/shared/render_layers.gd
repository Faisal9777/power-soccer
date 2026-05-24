class_name RenderLayers

const WORLD := 1
const PLAYER_BODY := 19
const PLAYER_UI := 20

const WORLD_MASK := 1 << (WORLD - 1)
const PLAYER_BODY_MASK := 1 << (PLAYER_BODY - 1)
const PLAYER_UI_MASK := 1 << (PLAYER_UI - 1)
