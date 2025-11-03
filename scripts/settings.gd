# Settings.gd (Autoload)
extends Node

const CFG_PATH := "user://settings.cfg"

var fullscreen := false
var vsync := true
var quality := 1          # 0=Low, 1=Med, 2=High (MSAA)
var tex_quality := 2      # 0=Low, 1=Med, 2=High (Textures)

func _enter_tree() -> void:
	_load()
	_apply()

func set_and_save(new_fullscreen: bool, new_vsync: bool, new_quality: int, new_tex_quality: int) -> void:
	fullscreen = new_fullscreen
	vsync = new_vsync
	quality = new_quality
	tex_quality = new_tex_quality
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
	# - Uses mipmap bias globally (2D & 3D)
	# - Also adjusts default 2D filter (Controls/Node2D); 3D filtering is per-material
	match tex_quality:
		0:
			get_viewport().texture_mipmap_bias = 2.0           # more blurry / cheaper
			get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		1:
			get_viewport().texture_mipmap_bias = 1.0
			get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
		2:
			get_viewport().texture_mipmap_bias = 0.0           # crispest
			get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		fullscreen  = cfg.get_value("video", "fullscreen", fullscreen)
		vsync       = cfg.get_value("video", "vsync", vsync)
		quality     = cfg.get_value("video", "quality", quality)
		tex_quality = cfg.get_value("video", "texture_quality", tex_quality)

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "quality", quality)
	cfg.set_value("video", "texture_quality", tex_quality)
	cfg.save(CFG_PATH)
