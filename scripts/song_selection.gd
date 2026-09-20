extends Control

const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
const GAMEPLAY_SCENE_PATH := "res://scenes/gameplay.tscn"
const SONG_ROW_HEIGHT := 74.0
const SONG_PREVIEW_DURATION := 15.0
const SONG_PREVIEW_FADE_IN_DURATION := 0.3
const SONG_PREVIEW_FADE_OUT_DURATION := 0.8
const SONG_PREVIEW_VOLUME_DB := -8.0
const SONG_PREVIEW_SILENT_VOLUME_DB := -40.0
const SCORE_ROW_HEIGHT := 54.0

var _intro_tween: Tween
var _preview_tween: Tween
var _song_button_group := ButtonGroup.new()
var _difficulty_button_group := ButtonGroup.new()
var _song_buttons: Array[Button] = []
var _difficulty_buttons: Array[Button] = []
var _current_difficulties: Array[SongDifficultyData] = []
var _remembered_difficulty_ids: Dictionary = {}
var _selected_song_index := -1
var _selected_difficulty_index := -1
var _transition_in_progress := false
var _has_pending_selection := false
var _pending_song_id: StringName = &""
var _pending_difficulty_id: StringName = &""
var _safe_area_rest_position := Vector2.ZERO
var _score_row_style: StyleBoxFlat

@export var songs: Array[SongData] = []

@onready var _background: ColorRect = %Background
@onready var _background_material: ShaderMaterial = _background.material as ShaderMaterial
@onready var _safe_area: MarginContainer = $SafeArea
@onready var _main_menu_button: Button = %MainMenuButton
@onready var _song_count_label: Label = %SongCountLabel
@onready var _song_scroll: ScrollContainer = %SongScroll
@onready var _song_list: VBoxContainer = %SongList
@onready var _song_details: VBoxContainer = %SongDetails
@onready var _song_title_label: Label = %SongTitleLabel
@onready var _artist_label: Label = %ArtistLabel
@onready var _bpm_label: Label = %BpmLabel
@onready var _length_label: Label = %LengthLabel
@onready var _try_count_label: Label = %TryCountLabel
@onready var _score_list: VBoxContainer = %ScoreList
@onready var _difficulty_list: HBoxContainer = %DifficultyList
@onready var _play_button: Button = %PlayButton
@onready var _menu_hover_sound_player: AudioStreamPlayer = %MenuButtonHoverSound
@onready var _menu_click_sound_player: AudioStreamPlayer = %MenuButtonClickSound
@onready var _play_click_sound_player: AudioStreamPlayer = %PlayButtonClickSound
@onready var _song_preview_player: AudioStreamPlayer = %SongPreview


func _ready() -> void:
	_song_button_group.allow_unpress = false
	_difficulty_button_group.allow_unpress = false
	_main_menu_button.pressed.connect(_on_main_menu_pressed)
	_main_menu_button.mouse_entered.connect(
		_on_interactive_control_mouse_entered.bind(_main_menu_button)
	)
	_play_button.pressed.connect(_on_play_pressed)
	_play_button.mouse_entered.connect(
		_on_interactive_control_mouse_entered.bind(_play_button)
	)
	_rebuild_catalogue()
	_apply_pending_selection()
	_safe_area_rest_position = _safe_area.position
	call_deferred("_animate_intro")
	call_deferred("_focus_initial_control")
	call_deferred("_play_initial_song_preview")


func _process(_delta: float) -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var normalised_cursor_position := get_viewport().get_mouse_position() / viewport_size
	if _background_material:
		_background_material.set_shader_parameter("cursor_position", normalised_cursor_position)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _transition_in_progress:
		get_viewport().set_input_as_handled()
		_return_to_main_menu()


func get_selected_song() -> SongData:
	if _selected_song_index < 0 or _selected_song_index >= songs.size():
		return null
	return songs[_selected_song_index]


func get_selected_difficulty() -> SongDifficultyData:
	if (
		_selected_difficulty_index < 0
		or _selected_difficulty_index >= _current_difficulties.size()
	):
		return null
	return _current_difficulties[_selected_difficulty_index]


func restore_selection(song_id: StringName, difficulty_id: StringName = &"") -> void:
	if not is_node_ready():
		_has_pending_selection = true
		_pending_song_id = song_id
		_pending_difficulty_id = difficulty_id
		return
	_restore_selection(song_id, difficulty_id)


func _restore_selection(song_id: StringName, difficulty_id: StringName) -> void:
	for song_index in range(songs.size()):
		if songs[song_index].song_id == song_id:
			_select_song(song_index, difficulty_id)
			_song_buttons[song_index].call_deferred("grab_focus")
			return
	if not songs.is_empty():
		var initial_song_index := _find_initial_song_index()
		_select_song(initial_song_index)
		_song_buttons[initial_song_index].call_deferred("grab_focus")


func _apply_pending_selection() -> void:
	if not _has_pending_selection:
		return
	_has_pending_selection = false
	_restore_selection(_pending_song_id, _pending_difficulty_id)
	_pending_song_id = &""
	_pending_difficulty_id = &""


func _animate_intro() -> void:
	_safe_area.position = _safe_area_rest_position + Vector2(-24.0, 0.0)
	_safe_area.modulate.a = 0.0
	_intro_tween = create_tween().set_parallel(true)
	_intro_tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_intro_tween.tween_property(_safe_area, "position", _safe_area_rest_position, 0.72)
	_intro_tween.tween_property(_safe_area, "modulate:a", 1.0, 0.48)


func _focus_initial_control() -> void:
	if _song_buttons.is_empty():
		_main_menu_button.grab_focus()
		return
	var initial_song_index := _selected_song_index
	if initial_song_index < 0 or initial_song_index >= _song_buttons.size():
		initial_song_index = _find_initial_song_index()
		_select_song(initial_song_index)
	_song_buttons[initial_song_index].grab_focus()


func _play_initial_song_preview() -> void:
	if _transition_in_progress or _song_preview_player.playing:
		return
	_play_song_preview(get_selected_song())


func _rebuild_catalogue() -> void:
	_clear_song_buttons()
	_song_count_label.text = _format_song_count(songs.size())
	_song_details.visible = not songs.is_empty()

	if songs.is_empty():
		_selected_song_index = -1
		_selected_difficulty_index = -1
		_current_difficulties.clear()
		_play_button.disabled = true
		_main_menu_button.focus_neighbor_bottom = NodePath()
		return

	for song_index in range(songs.size()):
		var song := songs[song_index]
		var song_button := Button.new()
		song_button.name = "SongButton%d" % (song_index + 1)
		song_button.custom_minimum_size = Vector2(0.0, SONG_ROW_HEIGHT)
		song_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		song_button.focus_mode = Control.FOCUS_ALL
		song_button.toggle_mode = true
		song_button.button_group = _song_button_group
		song_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		song_button.clip_text = true
		song_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		song_button.text = _format_song_row(song)
		song_button.tooltip_text = "%s — %s" % [
			song.title.strip_edges(),
			song.artist.strip_edges(),
		]
		song_button.focus_entered.connect(_on_song_button_focused.bind(song_index))
		song_button.pressed.connect(_on_song_button_pressed.bind(song_index))
		song_button.mouse_entered.connect(
			_on_interactive_control_mouse_entered.bind(song_button)
		)
		_song_list.add_child(song_button)
		_song_buttons.append(song_button)

	_configure_song_focus_neighbours()
	_select_song(_find_initial_song_index())


func _clear_song_buttons() -> void:
	for song_button in _song_buttons:
		if is_instance_valid(song_button):
			_song_list.remove_child(song_button)
			song_button.queue_free()
	_song_buttons.clear()
	_song_button_group = ButtonGroup.new()
	_song_button_group.allow_unpress = false


func _configure_song_focus_neighbours() -> void:
	if _song_buttons.is_empty():
		return
	var last_index := _song_buttons.size() - 1
	for song_index in range(_song_buttons.size()):
		var song_button := _song_buttons[song_index]
		var previous_button := _song_buttons[posmod(song_index - 1, _song_buttons.size())]
		var next_button := _song_buttons[posmod(song_index + 1, _song_buttons.size())]
		song_button.focus_neighbor_top = song_button.get_path_to(previous_button)
		song_button.focus_neighbor_bottom = song_button.get_path_to(next_button)
		song_button.focus_previous = song_button.get_path_to(
			_main_menu_button if song_index == 0 else previous_button
		)
		if song_index < last_index:
			song_button.focus_next = song_button.get_path_to(next_button)
	_main_menu_button.focus_neighbor_bottom = _main_menu_button.get_path_to(_song_buttons[0])
	_main_menu_button.focus_next = _main_menu_button.get_path_to(_song_buttons[0])


func _find_initial_song_index() -> int:
	for song_index in range(songs.size()):
		var song := songs[song_index]
		if song.audio_stream != null and not song.difficulties.is_empty():
			return song_index
	return 0


func _select_song(song_index: int, preferred_difficulty_id: StringName = &"") -> void:
	if song_index < 0 or song_index >= songs.size():
		return
	_selected_song_index = song_index
	for button_index in range(_song_buttons.size()):
		_song_buttons[button_index].set_pressed_no_signal(button_index == song_index)
	_refresh_song_details(preferred_difficulty_id)
	_song_scroll.call_deferred("ensure_control_visible", _song_buttons[song_index])


func _refresh_song_details(preferred_difficulty_id: StringName = &"") -> void:
	var song := get_selected_song()
	if song == null:
		return

	_song_title_label.text = song.title.strip_edges()
	_artist_label.text = song.artist.strip_edges()
	_bpm_label.visible = song.bpm > 0.0
	if _bpm_label.visible:
		_bpm_label.text = "BPM  %s" % _format_bpm(song.bpm)
	_length_label.text = "LENGTH  %s" % _format_duration(song.get_duration_seconds())
	_rebuild_difficulties(song, preferred_difficulty_id)


func _rebuild_difficulties(song: SongData, preferred_difficulty_id: StringName) -> void:
	_clear_difficulty_buttons()
	_current_difficulties = song.difficulties.duplicate()
	_difficulty_list.visible = not _current_difficulties.is_empty()

	if _current_difficulties.is_empty():
		_selected_difficulty_index = -1
		_configure_focus_without_difficulties()
		_update_difficulty_details()
		return

	if preferred_difficulty_id.is_empty() and _remembered_difficulty_ids.has(song.song_id):
		preferred_difficulty_id = StringName(_remembered_difficulty_ids[song.song_id])

	_selected_difficulty_index = _find_difficulty_index(preferred_difficulty_id)
	if _selected_difficulty_index < 0:
		_selected_difficulty_index = 0

	for difficulty_index in range(_current_difficulties.size()):
		var difficulty := _current_difficulties[difficulty_index]
		var difficulty_button := Button.new()
		difficulty_button.name = "DifficultyButton%d" % (difficulty_index + 1)
		difficulty_button.custom_minimum_size = Vector2(118.0, 46.0)
		difficulty_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		difficulty_button.focus_mode = Control.FOCUS_ALL
		difficulty_button.toggle_mode = true
		difficulty_button.button_group = _difficulty_button_group
		difficulty_button.text = _format_difficulty(difficulty)
		difficulty_button.clip_text = true
		difficulty_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		difficulty_button.focus_entered.connect(
			_on_difficulty_button_focused.bind(difficulty_index)
		)
		difficulty_button.pressed.connect(
			_on_difficulty_button_pressed.bind(difficulty_index)
		)
		difficulty_button.mouse_entered.connect(
			_on_interactive_control_mouse_entered.bind(difficulty_button)
		)
		_difficulty_list.add_child(difficulty_button)
		_difficulty_buttons.append(difficulty_button)

	_configure_difficulty_focus_neighbours()
	_select_difficulty(_selected_difficulty_index)


func _clear_difficulty_buttons() -> void:
	for difficulty_button in _difficulty_buttons:
		if is_instance_valid(difficulty_button):
			_difficulty_list.remove_child(difficulty_button)
			difficulty_button.queue_free()
	_difficulty_buttons.clear()
	_current_difficulties.clear()
	_difficulty_button_group = ButtonGroup.new()
	_difficulty_button_group.allow_unpress = false


func _find_difficulty_index(difficulty_id: StringName) -> int:
	for difficulty_index in range(_current_difficulties.size()):
		if _current_difficulties[difficulty_index].difficulty_id == difficulty_id:
			return difficulty_index
	return -1


func _select_difficulty(difficulty_index: int) -> void:
	if difficulty_index < 0 or difficulty_index >= _current_difficulties.size():
		_selected_difficulty_index = -1
		_update_difficulty_details()
		return
	_selected_difficulty_index = difficulty_index
	for button_index in range(_difficulty_buttons.size()):
		_difficulty_buttons[button_index].set_pressed_no_signal(
			button_index == difficulty_index
		)
	var song := get_selected_song()
	var difficulty := get_selected_difficulty()
	if song != null and difficulty != null:
		_remembered_difficulty_ids[song.song_id] = difficulty.difficulty_id
	_update_selected_difficulty_focus_neighbours()
	_update_difficulty_details()


func _configure_difficulty_focus_neighbours() -> void:
	if _difficulty_buttons.is_empty():
		return
	var song_button := _song_buttons[_selected_song_index]
	for difficulty_index in range(_difficulty_buttons.size()):
		var difficulty_button := _difficulty_buttons[difficulty_index]
		var previous_button := _difficulty_buttons[
			posmod(difficulty_index - 1, _difficulty_buttons.size())
		]
		var next_button := _difficulty_buttons[
			posmod(difficulty_index + 1, _difficulty_buttons.size())
		]
		difficulty_button.focus_neighbor_left = difficulty_button.get_path_to(previous_button)
		difficulty_button.focus_neighbor_right = difficulty_button.get_path_to(next_button)
		difficulty_button.focus_neighbor_top = difficulty_button.get_path_to(song_button)
		difficulty_button.focus_neighbor_bottom = difficulty_button.get_path_to(_play_button)
		difficulty_button.focus_previous = difficulty_button.get_path_to(
			song_button if difficulty_index == 0 else previous_button
		)
		difficulty_button.focus_next = difficulty_button.get_path_to(
			_play_button
			if difficulty_index == _difficulty_buttons.size() - 1
			else next_button
		)

	_song_buttons[_song_buttons.size() - 1].focus_next = (
		_song_buttons[_song_buttons.size() - 1].get_path_to(
			_difficulty_buttons[_selected_difficulty_index]
		)
	)
	_play_button.focus_neighbor_left = _play_button.get_path_to(song_button)
	_play_button.focus_previous = _play_button.get_path_to(
		_difficulty_buttons[_difficulty_buttons.size() - 1]
	)
	_play_button.focus_next = _play_button.get_path_to(_main_menu_button)
	_main_menu_button.focus_previous = _main_menu_button.get_path_to(_play_button)
	_update_selected_difficulty_focus_neighbours()


func _update_selected_difficulty_focus_neighbours() -> void:
	if _difficulty_buttons.is_empty() or _selected_song_index < 0:
		return
	var song_button := _song_buttons[_selected_song_index]
	var difficulty_button := _difficulty_buttons[_selected_difficulty_index]
	song_button.focus_neighbor_right = song_button.get_path_to(difficulty_button)
	_play_button.focus_neighbor_top = _play_button.get_path_to(difficulty_button)


func _update_difficulty_details() -> void:
	_refresh_local_scores()
	_play_button.disabled = not _can_play_selected_song() or _transition_in_progress
	_update_action_focus_neighbours()


func _refresh_local_scores() -> void:
	_clear_score_rows()
	var song := get_selected_song()
	var difficulty := get_selected_difficulty()
	if song == null or difficulty == null:
		_try_count_label.text = "0 TRIES"
		return

	var local_scores := get_node_or_null("/root/LocalScores")
	if local_scores == null:
		_try_count_label.text = "0 TRIES"
		return
	var attempts_value: Variant = local_scores.call(
		"get_ranked_attempts",
		song.song_id,
		difficulty.difficulty_id,
	)
	if not attempts_value is Array:
		_try_count_label.text = "0 TRIES"
		return

	var attempts: Array = attempts_value
	_try_count_label.text = "%d %s" % [
		attempts.size(),
		"TRY" if attempts.size() == 1 else "TRIES",
	]
	for attempt_index in range(attempts.size()):
		var attempt: Variant = attempts[attempt_index]
		if attempt is Dictionary:
			_score_list.add_child(_create_score_row(attempt_index + 1, attempt))


func _clear_score_rows() -> void:
	for score_row in _score_list.get_children():
		_score_list.remove_child(score_row)
		score_row.queue_free()


func _create_score_row(placing: int, attempt: Dictionary) -> PanelContainer:
	var score_row := PanelContainer.new()
	score_row.name = "ScoreRow%d" % placing
	score_row.custom_minimum_size = Vector2(0.0, SCORE_ROW_HEIGHT)
	score_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_row.add_theme_stylebox_override("panel", _get_score_row_style())

	var row_content := HBoxContainer.new()
	row_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_content.add_theme_constant_override("separation", 12)
	score_row.add_child(row_content)

	var placing_label := Label.new()
	placing_label.custom_minimum_size.x = 38.0
	placing_label.text = "#%d" % placing
	placing_label.add_theme_color_override("font_color", Color(0.34, 0.9, 1, 0.78))
	placing_label.add_theme_font_size_override("font_size", 14)
	row_content.add_child(placing_label)

	var misses := int(attempt.get("misses", 0))
	var misses_label := Label.new()
	misses_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	misses_label.text = "%d %s" % [misses, "MISS" if misses == 1 else "MISSES"]
	misses_label.add_theme_color_override("font_color", Color(0.62, 0.76, 0.83, 0.92))
	misses_label.add_theme_font_size_override("font_size", 14)
	row_content.add_child(misses_label)

	var grade := String(attempt.get("grade", "F"))
	var grade_label := Label.new()
	grade_label.custom_minimum_size.x = 44.0
	grade_label.text = grade
	grade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grade_label.add_theme_color_override("font_color", _get_grade_colour(grade))
	grade_label.add_theme_font_size_override("font_size", 26)
	row_content.add_child(grade_label)
	return score_row


func _get_score_row_style() -> StyleBoxFlat:
	if _score_row_style != null:
		return _score_row_style
	_score_row_style = StyleBoxFlat.new()
	_score_row_style.bg_color = Color(0.015, 0.06, 0.085, 0.82)
	_score_row_style.border_color = Color(0.23, 0.74, 0.84, 0.28)
	_score_row_style.border_width_left = 2
	_score_row_style.corner_radius_top_left = 5
	_score_row_style.corner_radius_top_right = 5
	_score_row_style.corner_radius_bottom_right = 5
	_score_row_style.corner_radius_bottom_left = 5
	_score_row_style.content_margin_left = 14.0
	_score_row_style.content_margin_top = 8.0
	_score_row_style.content_margin_right = 14.0
	_score_row_style.content_margin_bottom = 8.0
	return _score_row_style


func _get_grade_colour(grade: String) -> Color:
	match grade:
		"S":
			return Color(0.89, 0.97, 1.0)
		"A":
			return Color(0.34, 0.9, 1.0)
		"B":
			return Color(0.36, 0.66, 1.0)
		"C":
			return Color(0.65, 0.43, 1.0)
		"D":
			return Color(0.62, 0.52, 0.76)
		_:
			return Color(1.0, 0.38, 0.58)


func _configure_focus_without_difficulties() -> void:
	if _song_buttons.is_empty() or _selected_song_index < 0:
		return
	var selected_song_button := _song_buttons[_selected_song_index]
	var last_song_button := _song_buttons[_song_buttons.size() - 1]
	selected_song_button.focus_neighbor_right = NodePath()
	last_song_button.focus_next = last_song_button.get_path_to(_main_menu_button)
	_main_menu_button.focus_previous = _main_menu_button.get_path_to(last_song_button)
	_play_button.focus_neighbor_top = NodePath()
	_play_button.focus_previous = NodePath()


func _update_action_focus_neighbours() -> void:
	if _difficulty_buttons.is_empty():
		return
	var last_difficulty_button := _difficulty_buttons[_difficulty_buttons.size() - 1]
	var next_control: Control = _main_menu_button if _play_button.disabled else _play_button
	for difficulty_button in _difficulty_buttons:
		difficulty_button.focus_neighbor_bottom = difficulty_button.get_path_to(next_control)
	last_difficulty_button.focus_next = last_difficulty_button.get_path_to(next_control)
	_main_menu_button.focus_previous = _main_menu_button.get_path_to(
		last_difficulty_button if _play_button.disabled else _play_button
	)


func _can_play_selected_song() -> bool:
	var song := get_selected_song()
	return song != null and song.audio_stream != null and get_selected_difficulty() != null


func _format_song_row(song: SongData) -> String:
	return "%s\n%s  ·  %s" % [
		song.title.strip_edges(),
		song.artist.strip_edges(),
		_format_duration(song.get_duration_seconds()),
	]


func _format_song_count(song_count: int) -> String:
	return "%d %s" % [song_count, "SONG" if song_count == 1 else "SONGS"]


func _format_duration(duration_seconds: float) -> String:
	var total_seconds := maxi(roundi(duration_seconds), 0)
	var total_minutes := floori(total_seconds / 60.0)
	return "%d:%02d" % [total_minutes, total_seconds % 60]


func _format_bpm(bpm: float) -> String:
	if is_equal_approx(bpm, roundf(bpm)):
		return str(roundi(bpm))
	return "%.1f" % bpm


func _format_difficulty(difficulty: SongDifficultyData) -> String:
	if difficulty.rating <= 0.0:
		return difficulty.display_name.strip_edges().to_upper()
	var rating_text := (
		str(roundi(difficulty.rating))
		if is_equal_approx(difficulty.rating, roundf(difficulty.rating))
		else "%.1f" % difficulty.rating
	)
	return "%s  %s" % [difficulty.display_name.strip_edges().to_upper(), rating_text]


func _on_song_button_focused(song_index: int) -> void:
	if _transition_in_progress:
		return
	if song_index != _selected_song_index:
		_select_song(song_index)
	else:
		_song_scroll.call_deferred("ensure_control_visible", _song_buttons[song_index])


func _on_song_button_pressed(song_index: int) -> void:
	if _transition_in_progress:
		_synchronise_button_states()
		return
	_menu_click_sound_player.play()
	if song_index != _selected_song_index:
		_select_song(song_index)
	_play_song_preview(get_selected_song())
	if not _difficulty_buttons.is_empty():
		_difficulty_buttons[_selected_difficulty_index].grab_focus()


func _on_difficulty_button_focused(difficulty_index: int) -> void:
	if _transition_in_progress:
		return
	if difficulty_index != _selected_difficulty_index:
		_select_difficulty(difficulty_index)


func _on_difficulty_button_pressed(difficulty_index: int) -> void:
	if _transition_in_progress:
		_synchronise_button_states()
		return
	_menu_click_sound_player.play()
	if difficulty_index != _selected_difficulty_index:
		_select_difficulty(difficulty_index)


func _synchronise_button_states() -> void:
	for song_index in range(_song_buttons.size()):
		_song_buttons[song_index].set_pressed_no_signal(
			song_index == _selected_song_index
		)
	for difficulty_index in range(_difficulty_buttons.size()):
		_difficulty_buttons[difficulty_index].set_pressed_no_signal(
			difficulty_index == _selected_difficulty_index
		)


func _on_interactive_control_mouse_entered(control: BaseButton) -> void:
	if not _transition_in_progress and not control.disabled:
		_menu_hover_sound_player.play()


func _on_play_pressed() -> void:
	if _transition_in_progress or _play_button.disabled:
		return
	_open_gameplay(get_selected_song(), get_selected_difficulty())


func _open_gameplay(song: SongData, difficulty: SongDifficultyData) -> void:
	var beatmap := BeatmapData.load_from_file(difficulty.beatmap_path)
	if beatmap == null:
		return
	if beatmap.song_id != song.song_id or beatmap.difficulty_id != difficulty.difficulty_id:
		push_error("Beatmap identity does not match the selected song and difficulty")
		return
	if beatmap.get_last_note_time_ms() > song.get_duration_seconds() * 1000.0:
		push_error("Beatmap contains notes beyond the end of its audio")
		return
	var packed_scene := load(GAMEPLAY_SCENE_PATH) as PackedScene
	var gameplay := packed_scene.instantiate() as Gameplay
	gameplay.initialise(song, difficulty, beatmap)

	_transition_in_progress = true
	_play_button.disabled = true
	_stop_song_preview(SONG_PREVIEW_FADE_IN_DURATION)
	_play_click_sound_player.play()
	await _play_click_sound_player.finished

	var tree := get_tree()
	tree.root.add_child(gameplay)
	tree.current_scene = gameplay
	queue_free()


func _on_main_menu_pressed() -> void:
	_return_to_main_menu()


func _return_to_main_menu() -> void:
	if _transition_in_progress:
		return
	_transition_in_progress = true
	if _intro_tween and _intro_tween.is_valid():
		_intro_tween.kill()
	_play_button.disabled = true
	_stop_song_preview(SONG_PREVIEW_FADE_IN_DURATION)
	_menu_click_sound_player.play()
	var fade_duration := maxf(_menu_click_sound_player.stream.get_length(), 0.18)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_safe_area, "modulate:a", 0.0, fade_duration)
	await _menu_click_sound_player.finished
	var result := get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
	if result != OK:
		_transition_in_progress = false
		_safe_area.position = _safe_area_rest_position
		_safe_area.modulate.a = 1.0
		_synchronise_button_states()
		_update_difficulty_details()
		push_error("Cannot open Main Menu: %s" % error_string(result))


func _play_song_preview(song: SongData) -> void:
	_stop_song_preview()
	if song == null or song.audio_stream == null:
		return
	var song_duration := song.get_duration_seconds()
	if song_duration <= 0.0:
		return
	var preview_duration := minf(SONG_PREVIEW_DURATION, song_duration)
	var maximum_start := maxf(song_duration - preview_duration, 0.0)
	var preview_start := song.preview_start_seconds
	if preview_start < 0.0:
		preview_start = song_duration * 0.25
	preview_start = clampf(preview_start, 0.0, maximum_start)
	_song_preview_player.stream = song.audio_stream
	_start_song_preview_cycle(preview_start, preview_duration)


func _start_song_preview_cycle(preview_start: float, preview_duration: float) -> void:
	if _song_preview_player.stream == null:
		return
	var fade_in_duration := minf(
		SONG_PREVIEW_FADE_IN_DURATION,
		preview_duration,
	)
	var fade_out_duration := minf(
		SONG_PREVIEW_FADE_OUT_DURATION,
		maxf(preview_duration - fade_in_duration, 0.0),
	)
	var hold_duration := maxf(
		preview_duration - fade_in_duration - fade_out_duration,
		0.0,
	)

	_song_preview_player.volume_db = SONG_PREVIEW_SILENT_VOLUME_DB
	_song_preview_player.play(preview_start)
	_preview_tween = create_tween()
	_preview_tween.tween_property(
		_song_preview_player,
		"volume_db",
		SONG_PREVIEW_VOLUME_DB,
		fade_in_duration,
	)
	if hold_duration > 0.0:
		_preview_tween.tween_interval(hold_duration)
	if fade_out_duration > 0.0:
		_preview_tween.tween_property(
			_song_preview_player,
			"volume_db",
			SONG_PREVIEW_SILENT_VOLUME_DB,
			fade_out_duration,
		)
	_preview_tween.tween_callback(
		_start_song_preview_cycle.bind(preview_start, preview_duration)
	)


func _stop_song_preview(fade_duration := 0.0) -> void:
	if _preview_tween and _preview_tween.is_valid():
		_preview_tween.kill()
	_preview_tween = null
	if not _song_preview_player.playing:
		_finish_song_preview()
		return
	if fade_duration <= 0.0:
		_finish_song_preview()
		return
	_preview_tween = create_tween()
	_preview_tween.tween_property(
		_song_preview_player,
		"volume_db",
		SONG_PREVIEW_SILENT_VOLUME_DB,
		fade_duration,
	)
	_preview_tween.tween_callback(_finish_song_preview)


func _finish_song_preview() -> void:
	_song_preview_player.stop()
	_song_preview_player.stream = null
	_song_preview_player.volume_db = SONG_PREVIEW_SILENT_VOLUME_DB
	_preview_tween = null
