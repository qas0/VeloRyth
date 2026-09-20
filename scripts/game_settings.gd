extends Node

const SETTINGS_PATH := "user://settings.cfg"
const MIN_WINDOW_SIZE := Vector2i(1280, 720)
const MIN_MASTER_VOLUME := 0.0
const MAX_MASTER_VOLUME := 1.0
const DEFAULT_MASTER_VOLUME := 1.0
const MIN_MOUSE_SENSITIVITY := 0.25
const MAX_MOUSE_SENSITIVITY := 3.0
const DEFAULT_MOUSE_SENSITIVITY := 1.0
const DEFAULT_FULLSCREEN := false

var master_volume := DEFAULT_MASTER_VOLUME
var mouse_sensitivity := DEFAULT_MOUSE_SENSITIVITY
var fullscreen := DEFAULT_FULLSCREEN


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		get_window().min_size = MIN_WINDOW_SIZE
	load_settings()
	_apply_audio()
	_apply_display()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, MIN_MASTER_VOLUME, MAX_MASTER_VOLUME)
	_apply_audio()


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, MIN_MOUSE_SENSITIVITY, MAX_MOUSE_SENSITIVITY)


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	_apply_display()


func is_fullscreen_active() -> bool:
	var mode := DisplayServer.window_get_mode()
	return (
		mode == DisplayServer.WINDOW_MODE_FULLSCREEN
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	)


func synchronise_fullscreen_state() -> bool:
	fullscreen = is_fullscreen_active()
	return fullscreen


func load_settings() -> void:
	var config := ConfigFile.new()
	var load_error := config.load(SETTINGS_PATH)
	if load_error == ERR_FILE_NOT_FOUND:
		return
	if load_error != OK:
		push_warning("Could not load settings: %s" % error_string(load_error))
		return
	master_volume = clampf(
		float(config.get_value("audio", "master_volume", DEFAULT_MASTER_VOLUME)),
		MIN_MASTER_VOLUME,
		MAX_MASTER_VOLUME
	)
	mouse_sensitivity = clampf(
		float(config.get_value("controls", "mouse_sensitivity", DEFAULT_MOUSE_SENSITIVITY)),
		MIN_MOUSE_SENSITIVITY,
		MAX_MOUSE_SENSITIVITY
	)
	fullscreen = bool(config.get_value("display", "fullscreen", DEFAULT_FULLSCREEN))


func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("display", "fullscreen", fullscreen)
	var save_error := config.save(SETTINGS_PATH)
	if save_error != OK:
		push_error("Could not save settings: %s" % error_string(save_error))
	return save_error


func _apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.001)))
	AudioServer.set_bus_mute(0, master_volume <= 0.001)


func _apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
