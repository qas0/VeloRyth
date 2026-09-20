extends Control

const VOLUME_PERCENTAGE_SCALE := 100.0
const SONG_SELECTION_SCENE_PATH := "res://scenes/song_selection.tscn"

var _toast_tween: Tween
var _overlay_tween: Tween
var _intro_tween: Tween
var _settings_snapshot: Dictionary = {}
var _is_updating_numeric_input_text := false
var _scene_transition_in_progress := false
var _menu_rest_position := Vector2.ZERO

@onready var _background: ColorRect = %Background
@onready var _background_material: ShaderMaterial = _background.material as ShaderMaterial
@onready var _menu_content: VBoxContainer = %MenuContent
@onready var _play_button: Button = %PlayButton
@onready var _settings_button: Button = %SettingsButton
@onready var _about_button: Button = %AboutButton
@onready var _settings_overlay: Control = %SettingsOverlay
@onready var _about_overlay: Control = %AboutOverlay
@onready var _volume_slider: HSlider = %VolumeSlider
@onready var _volume_input: LineEdit = %VolumeInput
@onready var _sensitivity_slider: HSlider = %SensitivitySlider
@onready var _sensitivity_input: LineEdit = %SensitivityInput
@onready var _sensitivity_preview: SensitivityPreview = %SensitivityPreview
@onready var _fullscreen_toggle: CheckBox = %FullscreenToggle
@onready var _about_back_button: Button = %AboutBackButton
@onready var _toast: Label = %Toast
@onready var _main_menu_music_player: AudioStreamPlayer = $MainMenuMusic
@onready var _menu_hover_sound_player: AudioStreamPlayer = %MenuButtonHoverSound
@onready var _menu_click_sound_player: AudioStreamPlayer = %MenuButtonClickSound
@onready var _play_click_sound_player: AudioStreamPlayer = %PlayButtonClickSound


func _ready() -> void:
	_settings_overlay.hide()
	_about_overlay.hide()
	_volume_slider.set_value_no_signal(GameSettings.master_volume)
	_sensitivity_slider.set_value_no_signal(GameSettings.mouse_sensitivity)
	_update_volume_input(GameSettings.master_volume)
	_update_sensitivity_input(GameSettings.mouse_sensitivity)
	var actual_fullscreen := GameSettings.synchronise_fullscreen_state()
	_fullscreen_toggle.set_pressed_no_signal(actual_fullscreen)
	_sensitivity_preview.set_sensitivity(_sensitivity_slider.value)
	_menu_rest_position = _menu_content.position
	call_deferred("_animate_intro")
	_play_button.call_deferred("grab_focus")


func _process(_delta: float) -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var normalised_cursor_position := get_viewport().get_mouse_position() / viewport_size
	if _background_material:
		_background_material.set_shader_parameter("cursor_position", normalised_cursor_position)


func _input(event: InputEvent) -> void:
	if _scene_transition_in_progress:
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	if _settings_overlay.visible:
		get_viewport().set_input_as_handled()
		_cancel_settings()
	elif _about_overlay.visible:
		get_viewport().set_input_as_handled()
		_hide_overlay(_about_overlay, _about_button)


func _animate_intro() -> void:
	_menu_content.position = _menu_rest_position + Vector2(-28.0, 0.0)
	_menu_content.modulate.a = 0.0
	_intro_tween = create_tween().set_parallel(true)
	_intro_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_intro_tween.tween_property(_menu_content, "position", _menu_rest_position, 0.85)
	_intro_tween.tween_property(_menu_content, "modulate:a", 1.0, 0.55)


func _on_play_pressed() -> void:
	if _scene_transition_in_progress:
		return
	_scene_transition_in_progress = true
	if _intro_tween and _intro_tween.is_valid():
		_intro_tween.kill()
	var starting_music_volume := _main_menu_music_player.volume_db
	var starting_menu_position := _menu_content.position
	_play_click_sound_player.play()
	var transition_duration := maxf(_play_click_sound_player.stream.get_length(), 0.18)
	var transition_tween := create_tween().set_parallel(true)
	transition_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	transition_tween.tween_property(
		_main_menu_music_player,
		"volume_db",
		-40.0,
		transition_duration
	)
	transition_tween.tween_property(
		_menu_content,
		"position",
		starting_menu_position + Vector2(-20.0, 0.0),
		transition_duration
	)
	transition_tween.tween_property(
		_menu_content,
		"modulate:a",
		0.0,
		transition_duration
	)
	await _play_click_sound_player.finished
	var result := get_tree().change_scene_to_file(SONG_SELECTION_SCENE_PATH)
	if result == OK:
		return
	_scene_transition_in_progress = false
	var recovery_tween := create_tween().set_parallel(true)
	recovery_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	recovery_tween.tween_property(_main_menu_music_player, "volume_db", starting_music_volume, 0.2)
	recovery_tween.tween_property(_menu_content, "position", _menu_rest_position, 0.2)
	recovery_tween.tween_property(_menu_content, "modulate:a", 1.0, 0.2)
	_play_button.grab_focus()
	push_error("Cannot open Song Selection: %s" % error_string(result))


func _on_settings_pressed() -> void:
	if _scene_transition_in_progress:
		return
	_menu_click_sound_player.play()
	_capture_settings_snapshot()
	_show_overlay(_settings_overlay)


func _on_about_pressed() -> void:
	if _scene_transition_in_progress:
		return
	_menu_click_sound_player.play()
	_show_overlay(_about_overlay, _about_back_button)


func _on_quit_pressed() -> void:
	if _scene_transition_in_progress:
		return
	_menu_click_sound_player.play()
	await _menu_click_sound_player.finished
	get_tree().quit()


func _on_settings_done_pressed() -> void:
	_menu_click_sound_player.play()
	_commit_volume_input()
	_commit_sensitivity_input()
	if GameSettings.save_settings() != OK:
		_show_toast("Settings could not be saved")
		return
	_settings_snapshot.clear()
	_hide_overlay(_settings_overlay, _settings_button)


func _on_about_back_pressed() -> void:
	_menu_click_sound_player.play()
	_hide_overlay(_about_overlay, _about_button)


func _on_menu_control_mouse_entered() -> void:
	if _scene_transition_in_progress:
		return
	_menu_hover_sound_player.play()


func _on_volume_slider_changed(value: float) -> void:
	GameSettings.set_master_volume(value)
	_update_volume_input(value)


func _on_volume_input_focus_entered() -> void:
	_set_numeric_input_text(
		_volume_input,
		str(roundi(GameSettings.master_volume * VOLUME_PERCENTAGE_SCALE))
	)
	_volume_input.caret_column = _volume_input.text.length()


func _on_volume_input_text_changed(new_text: String) -> void:
	if _is_updating_numeric_input_text:
		return
	var filtered_text := _filter_whole_number_input(new_text)
	if filtered_text == new_text:
		return
	var filtered_caret_text := _filter_whole_number_input(
		new_text.left(_volume_input.caret_column)
	)
	_set_numeric_input_text(_volume_input, filtered_text)
	_volume_input.caret_column = filtered_caret_text.length()


func _on_volume_input_focus_exited() -> void:
	_commit_volume_input()


func _on_volume_input_submitted(_new_text: String) -> void:
	_volume_input.release_focus()


func _commit_volume_input() -> void:
	var entered_value := _volume_input.text.strip_edges().trim_suffix("%").strip_edges()
	if not entered_value.is_valid_float():
		_update_volume_input(GameSettings.master_volume)
		return
	var percentage := clampi(
		roundi(entered_value.to_float()),
		roundi(GameSettings.MIN_MASTER_VOLUME * VOLUME_PERCENTAGE_SCALE),
		roundi(GameSettings.MAX_MASTER_VOLUME * VOLUME_PERCENTAGE_SCALE)
	)
	var normalised_volume := float(percentage) / VOLUME_PERCENTAGE_SCALE
	_volume_slider.set_value_no_signal(normalised_volume)
	GameSettings.set_master_volume(normalised_volume)
	_update_volume_input(normalised_volume)


func _on_sensitivity_slider_changed(value: float) -> void:
	GameSettings.set_mouse_sensitivity(value)
	_update_sensitivity_input(value)
	_sensitivity_preview.set_sensitivity(value)


func _on_sensitivity_input_focus_entered() -> void:
	_set_numeric_input_text(_sensitivity_input, "%.2f" % GameSettings.mouse_sensitivity)
	_sensitivity_input.caret_column = _sensitivity_input.text.length()


func _on_sensitivity_input_text_changed(new_text: String) -> void:
	if _is_updating_numeric_input_text:
		return
	var filtered_text := _filter_decimal_input(new_text)
	if filtered_text == new_text:
		return
	var filtered_caret_text := _filter_decimal_input(
		new_text.left(_sensitivity_input.caret_column)
	)
	_set_numeric_input_text(_sensitivity_input, filtered_text)
	_sensitivity_input.caret_column = filtered_caret_text.length()


func _on_sensitivity_input_focus_exited() -> void:
	_commit_sensitivity_input()


func _on_sensitivity_input_submitted(_new_text: String) -> void:
	_sensitivity_input.release_focus()


func _commit_sensitivity_input() -> void:
	var entered_value := _sensitivity_input.text.strip_edges().trim_suffix("×").strip_edges()
	if not entered_value.is_valid_float():
		_update_sensitivity_input(GameSettings.mouse_sensitivity)
		return
	var sensitivity := clampf(
		entered_value.to_float(),
		GameSettings.MIN_MOUSE_SENSITIVITY,
		GameSettings.MAX_MOUSE_SENSITIVITY
	)
	sensitivity = snappedf(sensitivity, _sensitivity_slider.step)
	_sensitivity_slider.set_value_no_signal(sensitivity)
	GameSettings.set_mouse_sensitivity(sensitivity)
	_sensitivity_preview.set_sensitivity(sensitivity)
	_update_sensitivity_input(sensitivity)


func _on_fullscreen_toggled(enabled: bool) -> void:
	_menu_click_sound_player.play()
	GameSettings.set_fullscreen(enabled)
	await get_tree().process_frame
	var actual_fullscreen := GameSettings.synchronise_fullscreen_state()
	_fullscreen_toggle.set_pressed_no_signal(actual_fullscreen)
	if actual_fullscreen != enabled:
		_show_toast("Fullscreen is unavailable in this window")


func _capture_settings_snapshot() -> void:
	_settings_snapshot = {
		"master_volume": GameSettings.master_volume,
		"mouse_sensitivity": GameSettings.mouse_sensitivity,
		"fullscreen": GameSettings.is_fullscreen_active(),
	}


func _cancel_settings() -> void:
	if _settings_snapshot.is_empty():
		_hide_overlay(_settings_overlay, _settings_button)
		return

	var snapshot: Dictionary = _settings_snapshot.duplicate()
	_settings_snapshot.clear()
	var previous_master_volume := float(snapshot["master_volume"])
	var previous_mouse_sensitivity := float(snapshot["mouse_sensitivity"])
	var previous_fullscreen := bool(snapshot["fullscreen"])

	GameSettings.set_master_volume(previous_master_volume)
	GameSettings.set_mouse_sensitivity(previous_mouse_sensitivity)
	GameSettings.set_fullscreen(previous_fullscreen)

	_volume_slider.set_value_no_signal(previous_master_volume)
	_sensitivity_slider.set_value_no_signal(previous_mouse_sensitivity)
	_update_volume_input(previous_master_volume)
	_update_sensitivity_input(previous_mouse_sensitivity)
	_sensitivity_preview.set_sensitivity(previous_mouse_sensitivity)

	await get_tree().process_frame
	var actual_fullscreen := GameSettings.synchronise_fullscreen_state()
	_fullscreen_toggle.set_pressed_no_signal(actual_fullscreen)
	_hide_overlay(_settings_overlay, _settings_button)


func _update_volume_input(value: float) -> void:
	_set_numeric_input_text(
		_volume_input,
		"%d%%" % roundi(value * VOLUME_PERCENTAGE_SCALE)
	)


func _update_sensitivity_input(value: float) -> void:
	_set_numeric_input_text(_sensitivity_input, "%.2f×" % value)


func _set_numeric_input_text(input_field: LineEdit, new_text: String) -> void:
	_is_updating_numeric_input_text = true
	input_field.text = new_text
	_is_updating_numeric_input_text = false


func _filter_whole_number_input(input_text: String) -> String:
	var filtered_text := ""
	for character_index in range(input_text.length()):
		var character := input_text.substr(character_index, 1)
		if character.is_valid_int():
			filtered_text += character
	return filtered_text


func _filter_decimal_input(input_text: String) -> String:
	var filtered_text := ""
	var decimal_point_found := false
	for character_index in range(input_text.length()):
		var character := input_text.substr(character_index, 1)
		if character.is_valid_int():
			filtered_text += character
		elif character == "." and not decimal_point_found:
			filtered_text += character
			decimal_point_found = true
	return filtered_text


func _show_overlay(overlay: Control, initial_focus: Control = null) -> void:
	if _overlay_tween and _overlay_tween.is_valid():
		_overlay_tween.kill()
	overlay.show()
	overlay.modulate.a = 0.0
	if initial_focus:
		initial_focus.grab_focus()
	else:
		get_viewport().gui_release_focus()
	var overlay_panel := overlay.get_node("Centre/Panel") as Control
	overlay_panel.scale = Vector2(0.96, 0.96)
	overlay_panel.pivot_offset = overlay_panel.size * 0.5
	_overlay_tween = create_tween().set_parallel(true)
	_overlay_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_overlay_tween.tween_property(overlay, "modulate:a", 1.0, 0.2)
	_overlay_tween.tween_property(overlay_panel, "scale", Vector2.ONE, 0.28)


func _hide_overlay(overlay: Control, return_focus: Control) -> void:
	if overlay == _settings_overlay:
		_sensitivity_preview.restore_system_cursor()
	if _overlay_tween and _overlay_tween.is_valid():
		_overlay_tween.kill()
	_overlay_tween = create_tween()
	_overlay_tween.tween_property(overlay, "modulate:a", 0.0, 0.16)
	_overlay_tween.tween_callback(overlay.hide)
	_overlay_tween.tween_callback(return_focus.grab_focus)


func _show_toast(message: String) -> void:
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.text = message
	_toast.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.2)
	_toast_tween.tween_interval(2.1)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.3)
