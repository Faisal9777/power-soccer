extends Node

var data: Dictionary = {}

# Call this once at startup
func load_config() -> void:
	var default_config := _load_json("res://config/default_config.json")
	var override_config := _load_json_if_exists("user://config.json")

	data = default_config

	if not override_config.is_empty():
		data.merge(override_config, true)

# Safe getter (does NOT override Node.get)
func get_value(key: String, default_value = null):
	return data.get(key, default_value)

# -------------------------
# Internal helpers
# -------------------------

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Config file not found: " + path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open config file: " + path)
		return {}

	var content := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(content)

	if err != OK:
		push_error("JSON parse error in %s: %s" % [path, json.get_error_message()])
		return {}

	if typeof(json.data) != TYPE_DICTIONARY:
		push_error("Config must be a JSON object: " + path)
		return {}

	return json.data


func _load_json_if_exists(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open override config: " + path)
		return {}

	var content := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(content)

	if err != OK:
		push_error("JSON parse error in %s: %s" % [path, json.get_error_message()])
		return {}

	if typeof(json.data) != TYPE_DICTIONARY:
		push_error("Override config must be a JSON object: " + path)
		return {}

	return json.data
