class_name Gameplay
extends Control

const SONG_SELECTION_SCENE_PATH := "res://scenes/song_selection.tscn"
const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
const GRID_SIZE := BeatmapData.GRID_SIZE
const APPROACH_TIME_MS := 1200.0
const NOTE_FADE_IN_MS := 220.0
const NOTE_FADE_OUT_MS := 180.0
const APPROACH_FADE_OUT_MS := 60.0
const NOTE_CONNECTION_LEAD_MS := 800.0
const NOTE_CONNECTION_MAX_GAP_MS := 1500.0
const HIT_WINDOW_MS := 180.0
const MAX_CONSECUTIVE_MISSES := 5
const NOTE_STATE_PENDING := 0
const NOTE_STATE_HIT := 1
const NOTE_STATE_MISSED := 2
const POINTS_PER_HIT := 1000
const PLAYFIELD_WIDTH_RATIO := 0.5
const PLAYFIELD_HEIGHT_RATIO := 0.74
const PLAYFIELD_TOP_RATIO := 0.15
const CELL_GAP_RATIO := 0.022
const CELL_FILL_COLOUR := Color(0.05, 0.1, 0.18, 0.62)
const CELL_BORDER_COLOUR := Color(0.35, 0.78, 0.92, 0.22)
const NOTE_COLOUR := Color("55e6ff")
const NOTE_ACCENT_COLOUR := Color("a777ff")
const APPROACH_COLOUR := Color(0.52, 0.93, 1.0, 0.9)
const CURSOR_RING_COLOUR := Color(0.86, 0.98, 1.0, 1.0)
const CURSOR_FILL_COLOUR := Color(0.015, 0.055, 0.085, 0.86)
const CURSOR_CENTRE_COLOUR := Color(0.48, 0.86, 1.0, 1.0)
const CURSOR_ACCENT_COLOUR := Color(0.56, 0.36, 0.88, 1.0)
const CURSOR_TRAIL_COLOUR := Color(0.3, 0.82, 0.96, 0.48)
const CURSOR_RADIUS := 9.0
const CURSOR_TRAIL_LIFETIME := 0.16
const CURSOR_TRAIL_SPACING := 3.0
const CURSOR_TRAIL_MAX_POINTS := 18
const MISS_COLOUR := Color(0.79, 0.38, 0.68, 1.0)

enum GameplayState {
	UNINITIALISED,
	PLAYING,
	PAUSED,
	FINISHED,
}

enum ConfirmationAction {
	NONE,
	RESTART,
	MAIN_MENU,
}

var _song: SongData
var _difficulty: SongDifficultyData
var _beatmap: BeatmapData
var _state := GameplayState.UNINITIALISED
var _confirmation_action := ConfirmationAction.NONE
var _note_states := PackedByteArray()
var _note_judgement_times_ms := PackedFloat64Array()
var _cursor_position := Vector2.ZERO
var _cursor_trail_positions: Array[Vector2] = []
var _cursor_trail_ages: Array[float] = []
var _current_song_time_ms := 0.0
var _visual_time_ms := 0.0
var _audio_output_latency := 0.0
var _miss_check_index := 0
var _hit_count := 0
var _miss_count := 0
var _consecutive_misses := 0
var _combo := 0
var _maximum_combo := 0
var _score := 0
var _feedback_tween: Tween
var _previous_accumulated_input := Input.use_accumulated_input

@onready var _background_material: ShaderMaterial = %Background.material as ShaderMaterial
@onready var _song_audio_player: AudioStreamPlayer = %SongAudio
@onready var _menu_hover_sound_player: AudioStreamPlayer = %MenuButtonHoverSound
@onready var _menu_click_sound_player: AudioStreamPlayer = %MenuButtonClickSound
@onready var _song_title_label: Label = %SongTitleLabel
@onready var _artist_label: Label = %ArtistLabel
@onready var _difficulty_label: Label = %DifficultyLabel
@onready var _score_label: Label = %ScoreLabel
@onready var _accuracy_label: Label = %AccuracyLabel
@onready var _combo_label: Label = %ComboLabel
@onready var _misses_label: Label = %MissesLabel
@onready var _song_progress: ProgressBar = %SongProgress
@onready var _timing_feedback_label: Label = %TimingFeedbackLabel
@onready var _pause_overlay: Control = %PauseOverlay
@onready var _resume_button: Button = %ResumeButton
@onready var _pause_restart_button: Button = %PauseRestartButton
@onready var _pause_main_menu_button: Button = %PauseMainMenuButton
@onready var _confirmation_overlay: Control = %ConfirmationOverlay
@onready var _confirmation_title_label: Label = %ConfirmationTitleLabel
@onready var _confirmation_message_label: Label = %ConfirmationMessageLabel
@onready var _confirm_button: Button = %ConfirmButton
@onready var _cancel_button: Button = %CancelButton
@onready var _results_overlay: Control = %ResultsOverlay
@onready var _result_title_label: Label = %ResultTitleLabel
@onready var _rank_label: Label = %RankLabel
@onready var _result_accuracy_label: Label = %ResultAccuracyLabel
@onready var _result_summary_label: Label = %ResultSummaryLabel
@onready var _retry_button: Button = %RetryButton
@onready var _song_selection_button: Button = %SongSelectionButton
@onready var _results_main_menu_button: Button = %ResultsMainMenuButton


func initialise(
		song: SongData,
		difficulty: SongDifficultyData,
		beatmap: BeatmapData,
) -> void:
	_song = song
	_difficulty = difficulty
	_beatmap = beatmap


func _ready() -> void:
	_connect_interface()
	_pause_overlay.hide()
	_confirmation_overlay.hide()
	_results_overlay.hide()
	_timing_feedback_label.modulate.a = 0.0
	_song_audio_player.finished.connect(_on_song_audio_finished)
	if _song == null or _difficulty == null or _beatmap == null:
		return
	_song_title_label.text = _song.title.strip_edges()
	_artist_label.text = _song.artist.strip_edges()
	_difficulty_label.text = "%s  %.1f★" % [
		_difficulty.display_name.strip_edges().to_upper(),
		_difficulty.rating,
	]
	_song_progress.max_value = maxf(_song.get_duration_seconds(), 1.0)
	_cursor_position = _get_playfield_rect().get_center()
	call_deferred("_start_map")


func _process(delta: float) -> void:
	_update_background_cursor()
	if _state != GameplayState.PLAYING and _state != GameplayState.FINISHED:
		return
	_visual_time_ms += delta * 1000.0
	if _state == GameplayState.PLAYING:
		_update_cursor_trail(delta)
		_current_song_time_ms = maxf(_current_song_time_ms, _get_song_time_ms())
		_song_progress.value = maxf(_current_song_time_ms / 1000.0, 0.0)
		_process_missed_notes()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _confirmation_overlay.visible:
			_cancel_confirmation()
		elif _state == GameplayState.PLAYING:
			_pause_map()
		elif _state == GameplayState.PAUSED:
			_resume_map()
		elif _state == GameplayState.FINISHED:
			_return_to_song_selection()
		return
	if _state != GameplayState.PLAYING:
		return
	if event is InputEventMouseMotion:
		var previous_cursor_position := _cursor_position
		_cursor_position += event.relative * GameSettings.mouse_sensitivity
		var cursor_bounds := _get_playfield_rect().grow(-(CURSOR_RADIUS + 3.0))
		_cursor_position.x = clampf(
			_cursor_position.x,
			cursor_bounds.position.x,
			cursor_bounds.end.x,
		)
		_cursor_position.y = clampf(
			_cursor_position.y,
			cursor_bounds.position.y,
			cursor_bounds.end.y,
		)
		_record_cursor_trail(previous_cursor_position, _cursor_position)
		queue_redraw()
	elif (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	):
		_attempt_hit()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if (
		what == NOTIFICATION_APPLICATION_FOCUS_OUT
		and is_node_ready()
		and _state == GameplayState.PLAYING
	):
		call_deferred("_pause_map")


func _exit_tree() -> void:
	_restore_system_cursor()


func _draw() -> void:
	var playfield := _get_playfield_rect()
	var cell_gap := playfield.size.x * CELL_GAP_RATIO
	var cell_size := (playfield.size.x - cell_gap * (GRID_SIZE - 1)) / GRID_SIZE
	_draw_playfield(playfield, cell_size, cell_gap)
	if _beatmap != null:
		_draw_notes(playfield, cell_size, cell_gap)
	if _state == GameplayState.PLAYING:
		_draw_cursor_trail()
		_draw_gameplay_cursor()


func _draw_playfield(playfield: Rect2, cell_size: float, cell_gap: float) -> void:
	for frame_index in range(3, 0, -1):
		var frame_expansion := float(frame_index) * 9.0
		draw_rect(
			playfield.grow(frame_expansion),
			Color(0.22, 0.76, 0.95, 0.018 * float(4 - frame_index)),
			false,
			1.0,
			true,
		)
	for row in range(GRID_SIZE):
		for column in range(GRID_SIZE):
			var cell_position := playfield.position + Vector2(column, row) * (
				cell_size + cell_gap
			)
			var cell_rect := Rect2(cell_position, Vector2.ONE * cell_size)
			var cell_index := row * GRID_SIZE + column
			var glow_alpha := 0.018 + 0.01 * sin(
				_current_song_time_ms * 0.0014 + float(cell_index) * 0.8
			)
			draw_rect(cell_rect.grow(6.0), Color(NOTE_COLOUR, glow_alpha), true)
			draw_rect(cell_rect, CELL_FILL_COLOUR, true)
			draw_rect(cell_rect, CELL_BORDER_COLOUR, false, 1.25, true)


func _draw_notes(playfield: Rect2, cell_size: float, cell_gap: float) -> void:
	if _note_states.size() != _beatmap.notes.size():
		return
	_draw_note_connections(playfield, cell_size, cell_gap)
	for note_index in range(_beatmap.notes.size()):
		var note := _beatmap.notes[note_index]
		var time_until_note := float(note["time_ms"]) - _current_song_time_ms
		if time_until_note > APPROACH_TIME_MS:
			break
		if _note_states[note_index] == NOTE_STATE_PENDING:
			if time_until_note < -HIT_WINDOW_MS or _state == GameplayState.FINISHED:
				continue
		elif _get_note_fade_progress(note_index) >= 1.0:
			continue
		var note_colour := NOTE_COLOUR if note_index % 2 == 0 else NOTE_ACCENT_COLOUR
		var visibility := _get_note_visibility(note_index)
		var note_centre := _get_note_centre(
			note,
			playfield,
			cell_size,
			cell_gap,
		)
		var note_half_size := cell_size * 0.105
		if _note_states[note_index] == NOTE_STATE_HIT:
			var expansion := 1.0 - pow(1.0 - _get_note_fade_progress(note_index), 2.0)
			note_half_size *= lerpf(1.0, 1.3, expansion)
		elif _note_states[note_index] == NOTE_STATE_MISSED:
			note_colour = note_colour.lerp(MISS_COLOUR, 0.65)
		DrawingHelpers.draw_glow_square(
			self,
			note_centre,
			note_half_size,
			note_colour,
			0.2 * visibility,
		)
		if _note_states[note_index] == NOTE_STATE_PENDING:
			var approach_progress := clampf(1.0 - time_until_note / APPROACH_TIME_MS, 0.0, 1.0)
			var approach_half_size := note_half_size * lerpf(4.0, 1.0, approach_progress)
			var approach_visibility := visibility * (
				1.0 - smoothstep(0.0, APPROACH_FADE_OUT_MS, -time_until_note)
			)
			draw_rect(
				Rect2(
					note_centre - Vector2.ONE * approach_half_size,
					Vector2.ONE * approach_half_size * 2.0,
				),
				Color(note_colour, 0.82 * approach_visibility),
				false,
				2.4,
				true,
			)
		var note_rect := Rect2(
			note_centre - Vector2.ONE * note_half_size,
			Vector2.ONE * note_half_size * 2.0,
		)
		draw_rect(note_rect, Color(note_colour, 0.94 * visibility), true)
		draw_rect(
			note_rect,
			Color(0.87, 0.98, 1.0, 0.92 * visibility),
			false,
			2.0,
			true,
		)
		var core_half_size := note_half_size * 0.32
		draw_rect(
			Rect2(
				note_centre - Vector2.ONE * core_half_size,
				Vector2.ONE * core_half_size * 2.0,
			),
			Color(0.94, 0.99, 1.0, 0.95 * visibility),
			true,
		)


func _draw_note_connections(
		playfield: Rect2,
		cell_size: float,
		cell_gap: float,
) -> void:
	if _state == GameplayState.FINISHED:
		return
	for first_note_index in range(maxi(_miss_check_index - 1, 0), _beatmap.notes.size() - 1):
		var second_note_index := first_note_index + 1
		var first_note := _beatmap.notes[first_note_index]
		var second_note := _beatmap.notes[second_note_index]
		var first_time_ms := float(first_note["time_ms"])
		var second_time_ms := float(second_note["time_ms"])
		if first_time_ms > _current_song_time_ms + NOTE_CONNECTION_LEAD_MS:
			break
		if second_time_ms < _current_song_time_ms - NOTE_FADE_OUT_MS:
			continue
		var note_gap_ms := second_time_ms - first_time_ms
		if note_gap_ms > NOTE_CONNECTION_MAX_GAP_MS:
			continue
		var first_centre := _get_note_centre(
			first_note,
			playfield,
			cell_size,
			cell_gap,
		)
		var second_centre := _get_note_centre(
			second_note,
			playfield,
			cell_size,
			cell_gap,
		)
		var distance := first_centre.distance_to(second_centre)
		if distance <= cell_size * 0.3:
			continue
		var direction := first_centre.direction_to(second_centre)
		var margin := cell_size * 0.15
		var segment_count := maxi(floori((distance - margin * 2.0) / (cell_size * 0.16)), 1)
		for segment_index in range(segment_count):
			var progress := float(segment_index + 1) / float(segment_count + 1)
			var segment_time_ms := lerpf(first_time_ms, second_time_ms, progress)
			var time_until_segment := segment_time_ms - _current_song_time_ms
			var reveal := smoothstep(
				0.0, NOTE_FADE_IN_MS, NOTE_CONNECTION_LEAD_MS - time_until_segment
			)
			var visibility := reveal * (
				1.0 - smoothstep(0.0, NOTE_FADE_OUT_MS, -time_until_segment)
			)
			if visibility <= 0.0:
				continue
			var centre := (first_centre + direction * margin).lerp(
				second_centre - direction * margin, progress
			)
			centre -= direction * cell_size * 0.05 * (1.0 - reveal)
			var half_segment := direction * cell_size * 0.025
			draw_line(
				centre - half_segment, centre + half_segment,
				Color(0.43, 0.88, 1.0, 0.08 * visibility), 8.0, true,
			)
			draw_line(
				centre - half_segment, centre + half_segment,
				Color(0.52, 0.92, 1.0, 0.3 * visibility), 1.4, true,
			)


func _get_note_visibility(note_index: int) -> float:
	if _note_states[note_index] != NOTE_STATE_PENDING:
		return 1.0 - smoothstep(0.0, 1.0, _get_note_fade_progress(note_index))
	var time_until_note := float(_beatmap.notes[note_index]["time_ms"]) - _current_song_time_ms
	return smoothstep(0.0, NOTE_FADE_IN_MS, APPROACH_TIME_MS - time_until_note)


func _get_note_fade_progress(note_index: int) -> float:
	return clampf(
		(_visual_time_ms - _note_judgement_times_ms[note_index]) / NOTE_FADE_OUT_MS, 0.0, 1.0
	)


func _draw_cursor_trail() -> void:
	var point_count := _cursor_trail_positions.size()
	for trail_index in range(point_count):
		var age_progress := clampf(
			_cursor_trail_ages[trail_index] / CURSOR_TRAIL_LIFETIME,
			0.0,
			1.0,
		)
		var sequence_progress := float(trail_index + 1) / float(point_count)
		var trail_colour := CURSOR_TRAIL_COLOUR
		trail_colour.a *= pow(1.0 - age_progress, 2.0) * sequence_progress
		var trail_radius := lerpf(1.2, 3.6, sequence_progress)
		draw_circle(
			_cursor_trail_positions[trail_index],
			trail_radius,
			trail_colour,
			true,
			-1.0,
			true,
		)


func _draw_gameplay_cursor() -> void:
	var glow_colour := CURSOR_CENTRE_COLOUR
	glow_colour.a = 0.18
	draw_circle(_cursor_position, CURSOR_RADIUS + 3.0, glow_colour, true, -1.0, true)
	draw_circle(_cursor_position, CURSOR_RADIUS, CURSOR_FILL_COLOUR, true, -1.0, true)
	draw_arc(
		_cursor_position,
		CURSOR_RADIUS,
		0.0,
		TAU,
		32,
		CURSOR_RING_COLOUR,
		2.0,
		true,
	)
	draw_circle(_cursor_position, 2.6, CURSOR_CENTRE_COLOUR, true, -1.0, true)
	draw_circle(_cursor_position, 1.2, CURSOR_ACCENT_COLOUR, true, -1.0, true)


func _record_cursor_trail(from_position: Vector2, to_position: Vector2) -> void:
	var distance := from_position.distance_to(to_position)
	if distance < 0.5:
		return
	var sample_count := maxi(ceili(distance / CURSOR_TRAIL_SPACING), 1)
	for sample_index in range(maxi(sample_count - CURSOR_TRAIL_MAX_POINTS, 0), sample_count):
		var sample_progress := float(sample_index) / float(sample_count)
		_cursor_trail_positions.append(
			from_position.lerp(to_position, sample_progress)
		)
		_cursor_trail_ages.append(0.0)
	while _cursor_trail_positions.size() > CURSOR_TRAIL_MAX_POINTS:
		_cursor_trail_positions.remove_at(0)
		_cursor_trail_ages.remove_at(0)


func _update_cursor_trail(delta: float) -> void:
	for trail_index in range(_cursor_trail_ages.size() - 1, -1, -1):
		_cursor_trail_ages[trail_index] += delta
		if _cursor_trail_ages[trail_index] >= CURSOR_TRAIL_LIFETIME:
			_cursor_trail_positions.remove_at(trail_index)
			_cursor_trail_ages.remove_at(trail_index)


func _clear_cursor_trail() -> void:
	_cursor_trail_positions.clear()
	_cursor_trail_ages.clear()


func _connect_interface() -> void:
	_resume_button.pressed.connect(_on_resume_pressed)
	_pause_restart_button.pressed.connect(_on_pause_restart_pressed)
	_pause_main_menu_button.pressed.connect(_on_pause_main_menu_pressed)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	_retry_button.pressed.connect(_on_retry_pressed)
	_song_selection_button.pressed.connect(_on_song_selection_pressed)
	_results_main_menu_button.pressed.connect(_on_results_main_menu_pressed)
	var buttons: Array[Button] = [
		_resume_button,
		_pause_restart_button,
		_pause_main_menu_button,
		_confirm_button,
		_cancel_button,
		_retry_button,
		_song_selection_button,
		_results_main_menu_button,
	]
	for button in buttons:
		button.mouse_entered.connect(_on_button_mouse_entered.bind(button))


func _start_map() -> void:
	if _feedback_tween and _feedback_tween.is_valid():
		_feedback_tween.kill()
	_pause_overlay.hide()
	_confirmation_overlay.hide()
	_results_overlay.hide()
	_timing_feedback_label.modulate.a = 0.0
	_note_states.resize(_beatmap.notes.size())
	_note_states.fill(NOTE_STATE_PENDING)
	_note_judgement_times_ms.resize(_beatmap.notes.size())
	_note_judgement_times_ms.fill(0.0)
	_miss_check_index = 0
	_hit_count = 0
	_miss_count = 0
	_consecutive_misses = 0
	_combo = 0
	_maximum_combo = 0
	_score = 0
	_current_song_time_ms = 0.0
	_visual_time_ms = 0.0
	_audio_output_latency = AudioServer.get_output_latency()
	_confirmation_action = ConfirmationAction.NONE
	_cursor_position = _get_playfield_rect().get_center()
	_clear_cursor_trail()
	_song_progress.value = 0.0
	_update_hud()
	_state = GameplayState.PLAYING
	_song_audio_player.stop()
	_song_audio_player.stream = _song.audio_stream
	_song_audio_player.stream_paused = false
	_song_audio_player.play()
	_capture_mouse()
	_show_timing_feedback("GET READY", APPROACH_COLOUR, 1.2)
	queue_redraw()


func _get_song_time_ms() -> float:
	var playback_seconds := _song_audio_player.get_playback_position()
	playback_seconds += AudioServer.get_time_since_last_mix()
	playback_seconds -= _audio_output_latency
	return maxf(playback_seconds * 1000.0 - _beatmap.audio_offset_ms, 0.0)


func _process_missed_notes() -> void:
	while _miss_check_index < _beatmap.notes.size():
		var note_time_ms := float(_beatmap.notes[_miss_check_index]["time_ms"])
		if note_time_ms >= _current_song_time_ms - HIT_WINDOW_MS:
			break
		if _note_states[_miss_check_index] == NOTE_STATE_PENDING:
			_note_states[_miss_check_index] = NOTE_STATE_MISSED
			_note_judgement_times_ms[_miss_check_index] = _visual_time_ms
			_register_miss()
			if _state != GameplayState.PLAYING:
				break
		_miss_check_index += 1


func _attempt_hit() -> void:
	_current_song_time_ms = maxf(_current_song_time_ms, _get_song_time_ms())
	var playfield := _get_playfield_rect()
	var cell_gap := playfield.size.x * CELL_GAP_RATIO
	var cell_size := (playfield.size.x - cell_gap * (GRID_SIZE - 1)) / GRID_SIZE
	var target_size := cell_size * 0.38
	var best_note_index := -1
	var best_timing_error := HIT_WINDOW_MS + 1.0
	for note_index in range(_miss_check_index, _beatmap.notes.size()):
		if _note_states[note_index] != NOTE_STATE_PENDING:
			continue
		var note := _beatmap.notes[note_index]
		var timing_error := absf(float(note["time_ms"]) - _current_song_time_ms)
		if float(note["time_ms"]) > _current_song_time_ms + HIT_WINDOW_MS:
			break
		if timing_error > HIT_WINDOW_MS:
			continue
		var note_centre := _get_note_centre(
			note,
			playfield,
			cell_size,
			cell_gap,
		)
		var hit_rect := Rect2(
			note_centre - Vector2.ONE * target_size * 0.5,
			Vector2.ONE * target_size,
		)
		if hit_rect.has_point(_cursor_position) and timing_error < best_timing_error:
			best_note_index = note_index
			best_timing_error = timing_error
	if best_note_index < 0:
		return
	_note_states[best_note_index] = NOTE_STATE_HIT
	_note_judgement_times_ms[best_note_index] = _visual_time_ms
	_hit_count += 1
	_consecutive_misses = 0
	_combo += 1
	_maximum_combo = maxi(_maximum_combo, _combo)
	_score += POINTS_PER_HIT
	_show_timing_feedback("HIT", NOTE_COLOUR)
	_update_hud()
	queue_redraw()


func _register_miss() -> void:
	_miss_count += 1
	_consecutive_misses += 1
	_combo = 0
	_show_timing_feedback(
		"MISS  %d/%d" % [_consecutive_misses, MAX_CONSECUTIVE_MISSES],
		MISS_COLOUR,
	)
	_update_hud()
	if _consecutive_misses >= MAX_CONSECUTIVE_MISSES:
		_finish_map(false)


func _get_note_centre(
		note: Dictionary,
		playfield: Rect2,
		cell_size: float,
		cell_gap: float,
) -> Vector2:
	return playfield.position + Vector2(
		float(note["column"]),
		float(note["row"]),
	) * (cell_size + cell_gap) + Vector2.ONE * cell_size * 0.5


func _get_playfield_rect() -> Rect2:
	var viewport_size := size
	var side_length := minf(
		viewport_size.x * PLAYFIELD_WIDTH_RATIO,
		viewport_size.y * PLAYFIELD_HEIGHT_RATIO,
	)
	var playfield_position := Vector2(
		(viewport_size.x - side_length) * 0.5,
		viewport_size.y * PLAYFIELD_TOP_RATIO,
	)
	return Rect2(playfield_position, Vector2.ONE * side_length)


func _update_hud() -> void:
	_score_label.text = "SCORE  %07d" % _score
	_accuracy_label.text = "ACCURACY  %.1f%%" % _get_live_accuracy()
	_combo_label.text = "COMBO  %d" % _combo
	_misses_label.text = "MISSES  %d" % _miss_count


func _get_live_accuracy() -> float:
	var judged_notes := _hit_count + _miss_count
	if judged_notes <= 0:
		return 100.0
	return float(_hit_count) / judged_notes * 100.0


func _get_rank(completed: bool, accuracy: float) -> String:
	if not completed:
		return "F"
	if accuracy >= 99.999:
		return "S"
	if accuracy >= 90.0:
		return "A"
	if accuracy >= 80.0:
		return "B"
	if accuracy >= 70.0:
		return "C"
	return "D"


func _show_timing_feedback(
		message: String,
		colour: Color,
		display_duration := 0.38,
) -> void:
	if _feedback_tween and _feedback_tween.is_valid():
		_feedback_tween.kill()
	_timing_feedback_label.text = message
	_timing_feedback_label.add_theme_color_override("font_color", colour)
	_timing_feedback_label.modulate.a = 1.0
	_feedback_tween = create_tween()
	_feedback_tween.tween_interval(display_duration)
	_feedback_tween.tween_property(_timing_feedback_label, "modulate:a", 0.0, 0.2)


func _pause_map() -> void:
	if _state != GameplayState.PLAYING:
		return
	_current_song_time_ms = maxf(_current_song_time_ms, _get_song_time_ms())
	_state = GameplayState.PAUSED
	_song_audio_player.stream_paused = true
	_clear_cursor_trail()
	_restore_system_cursor()
	_pause_overlay.show()
	_resume_button.grab_focus()
	queue_redraw()


func _resume_map() -> void:
	if _state != GameplayState.PAUSED or _confirmation_overlay.visible:
		return
	_pause_overlay.hide()
	_audio_output_latency = AudioServer.get_output_latency()
	_state = GameplayState.PLAYING
	_song_audio_player.stream_paused = false
	_clear_cursor_trail()
	_capture_mouse()
	queue_redraw()


func _show_confirmation(action: ConfirmationAction) -> void:
	if _state != GameplayState.PAUSED:
		return
	_confirmation_action = action
	_pause_overlay.hide()
	_confirmation_overlay.show()
	if action == ConfirmationAction.RESTART:
		_confirmation_title_label.text = "RESTART MAP?"
		_confirmation_message_label.text = "Your current progress will be lost."
		_confirm_button.text = "RESTART"
	else:
		_confirmation_title_label.text = "RETURN TO MAIN MENU?"
		_confirmation_message_label.text = "Your current progress will be lost."
		_confirm_button.text = "MAIN MENU"
	_cancel_button.grab_focus()


func _cancel_confirmation() -> void:
	if not _confirmation_overlay.visible:
		return
	var previous_action := _confirmation_action
	_confirmation_action = ConfirmationAction.NONE
	_confirmation_overlay.hide()
	_pause_overlay.show()
	if previous_action == ConfirmationAction.RESTART:
		_pause_restart_button.grab_focus()
	else:
		_pause_main_menu_button.grab_focus()


func _finish_map(completed: bool) -> void:
	if _state == GameplayState.FINISHED:
		return
	_state = GameplayState.FINISHED
	_song_audio_player.stop()
	_clear_cursor_trail()
	_restore_system_cursor()
	_pause_overlay.hide()
	_confirmation_overlay.hide()
	var accuracy := float(_hit_count) / _beatmap.notes.size() * 100.0
	var rank := _get_rank(completed, accuracy)
	_record_local_score(rank)
	_result_title_label.text = "MAP COMPLETE" if completed else "MAP FAILED"
	_rank_label.text = rank
	_rank_label.add_theme_color_override(
		"font_color",
		NOTE_COLOUR if completed else MISS_COLOUR,
	)
	_result_accuracy_label.text = "ACCURACY  %.1f%%" % accuracy
	_result_summary_label.text = (
		"%d HITS  ·  %d MISSES  ·  %d MAX COMBO\nSCORE  %07d"
		% [_hit_count, _miss_count, _maximum_combo, _score]
	)
	_results_overlay.show()
	_retry_button.grab_focus()
	queue_redraw()


func _record_local_score(rank: String) -> void:
	LocalScores.record_attempt(
		_song.song_id,
		_difficulty.difficulty_id,
		rank,
		_miss_count,
	)


func _update_background_cursor() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var cursor_shader_position := _cursor_position
	if _state != GameplayState.PLAYING:
		cursor_shader_position = get_viewport().get_mouse_position()
	_background_material.set_shader_parameter(
		"cursor_position",
		cursor_shader_position / size,
	)


func _capture_mouse() -> void:
	Input.use_accumulated_input = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _restore_system_cursor() -> void:
	Input.use_accumulated_input = _previous_accumulated_input
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_button_mouse_entered(button: Button) -> void:
	if button.visible and not button.disabled:
		_menu_hover_sound_player.play()


func _on_resume_pressed() -> void:
	_menu_click_sound_player.play()
	_resume_map()


func _on_pause_restart_pressed() -> void:
	_menu_click_sound_player.play()
	_show_confirmation(ConfirmationAction.RESTART)


func _on_pause_main_menu_pressed() -> void:
	_menu_click_sound_player.play()
	_show_confirmation(ConfirmationAction.MAIN_MENU)


func _on_cancel_pressed() -> void:
	_menu_click_sound_player.play()
	_cancel_confirmation()


func _on_confirm_pressed() -> void:
	var action := _confirmation_action
	if action == ConfirmationAction.NONE:
		return
	_menu_click_sound_player.play()
	await _menu_click_sound_player.finished
	if action == ConfirmationAction.RESTART:
		_start_map()
	else:
		_open_main_menu()


func _on_retry_pressed() -> void:
	_menu_click_sound_player.play()
	_start_map()


func _on_song_selection_pressed() -> void:
	_menu_click_sound_player.play()
	await _menu_click_sound_player.finished
	_return_to_song_selection()


func _on_results_main_menu_pressed() -> void:
	_menu_click_sound_player.play()
	await _menu_click_sound_player.finished
	_open_main_menu()


func _on_song_audio_finished() -> void:
	if _state == GameplayState.PLAYING:
		_finish_map(true)


func _return_to_song_selection() -> void:
	_restore_system_cursor()
	var packed_scene := load(SONG_SELECTION_SCENE_PATH) as PackedScene
	if packed_scene == null:
		return
	var song_selection := packed_scene.instantiate()
	song_selection.restore_selection(_song.song_id, _difficulty.difficulty_id)
	var tree := get_tree()
	tree.root.add_child(song_selection)
	tree.current_scene = song_selection
	queue_free()


func _open_main_menu() -> void:
	_restore_system_cursor()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
