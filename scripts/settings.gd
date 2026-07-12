# Settings.gd (Autoload)
extends Node

const CFG_PATH := "user://settingss.cfg"

var player_name := ""   # shown in lobbies

var fullscreen := false
var vsync := true
var quality := 1          # 0=Low, 1=Med, 2=High (MSAA)
var tex_quality := 2      # 0=Low, 1=Med, 2=High (Textures)
var net_indicators := true

# NEW: 3D render scale (Project Settings -> Rendering -> Scaling 3D -> Scale)
var scale_3d: float = 1.0

func _enter_tree() -> void:
	_load()
	_apply()

# UPDATED: add new_scale_3d
func set_and_save(new_fullscreen: bool, new_vsync: bool, new_quality: int, new_tex_quality: int, new_scale_3d: float, new_net_indicators: bool) -> void:
	fullscreen = new_fullscreen
	vsync = new_vsync
	quality = new_quality
	tex_quality = new_tex_quality
	scale_3d = new_scale_3d
	net_indicators = new_net_indicators
	_apply()
	_save()

func _apply() -> void:
	# Window mode + VSync
	if !OS.has_feature("mobile"):
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		)
	ProjectSettings.set_setting("display/window/vsync/vsync_mode", 1 if vsync else 0)

	# MSAA (3D)
	match quality:
		0: get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		1: get_viewport().msaa_3d = Viewport.MSAA_2X
		2: get_viewport().msaa_3d = Viewport.MSAA_4X

	# Texture "quality"
	match tex_quality:
		0:
			get_viewport().texture_mipmap_bias = 2.0
			get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		1:
			get_viewport().texture_mipmap_bias = 1.0
			get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
		2:
			get_viewport().texture_mipmap_bias = 0.0
			get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	# NEW: 3D scaling (apply to the root viewport so it matches Project Settings behavior)
	var vp := get_tree().root
	vp.scaling_3d_scale = clampf(scale_3d, 0.25, 2.0)

	# Optional: also keep ProjectSettings in sync (not strictly required for runtime)
	ProjectSettings.set_setting("rendering/scaling_3d/scale", vp.scaling_3d_scale)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		fullscreen  = cfg.get_value("video", "fullscreen", fullscreen)
		vsync       = cfg.get_value("video", "vsync", vsync)
		quality     = cfg.get_value("video", "quality", quality)
		tex_quality = cfg.get_value("video", "texture_quality", tex_quality)
		net_indicators = bool(cfg.get_value("video", "net_indicators", net_indicators))

		# NEW:
		scale_3d    = float(cfg.get_value("video", "scale_3d", scale_3d))

		# profile
		player_name = cfg.get_value("profile", "name", player_name)

func _save() -> void:
	var cfg := ConfigFile.new()

	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "quality", quality)
	cfg.set_value("video", "texture_quality", tex_quality)
	cfg.set_value("video", "net_indicators", net_indicators)

	# NEW:
	cfg.set_value("video", "scale_3d", scale_3d)

	cfg.set_value("profile", "name", player_name)

	cfg.save(CFG_PATH)

func ensure_player_name() -> void:
	if player_name.strip_edges() == "":
		player_name = "Player_%d" % randi()
		_save()

func set_player_name_and_save(name: String) -> void:
	player_name = name.strip_edges()
	if player_name == "":
		player_name = "Player_%d" % randi()
	_save()
