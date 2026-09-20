extends Node

const SAVE_PATH := "user://local_scores.json"
const FORMAT_VERSION := 1
const VALID_GRADES := ["S", "A", "B", "C", "D", "F"]

var _scores: Dictionary = {}


func _ready() -> void:
	_load_scores()


func record_attempt(
		song_id: StringName,
		difficulty_id: StringName,
		grade: String,
		misses: int,
) -> Error:
	var song_key := String(song_id)
	var difficulty_key := String(difficulty_id)
	var normalised_grade := grade.to_upper()
	if (
			song_key.is_empty()
			or difficulty_key.is_empty()
			or normalised_grade not in VALID_GRADES
			or misses < 0
	):
		return ERR_INVALID_PARAMETER

	var song_scores: Dictionary = _scores.get(song_key, {})
	var attempts: Array = song_scores.get(difficulty_key, [])
	attempts.append({
		"grade": normalised_grade,
		"misses": misses,
	})
	song_scores[difficulty_key] = attempts
	_scores[song_key] = song_scores
	return _save_scores()


func get_ranked_attempts(
		song_id: StringName,
		difficulty_id: StringName,
) -> Array[Dictionary]:
	var song_scores: Dictionary = _scores.get(String(song_id), {})
	var stored_attempts: Array = song_scores.get(String(difficulty_id), [])
	var ranked_attempts: Array[Dictionary] = []
	for attempt in stored_attempts:
		if attempt is Dictionary:
			ranked_attempts.append(attempt.duplicate(true))
	ranked_attempts.sort_custom(_is_attempt_better)
	return ranked_attempts


func _is_attempt_better(first_attempt: Dictionary, second_attempt: Dictionary) -> bool:
	var first_grade_index := VALID_GRADES.find(String(first_attempt.get("grade", "F")))
	var second_grade_index := VALID_GRADES.find(String(second_attempt.get("grade", "F")))
	if first_grade_index != second_grade_index:
		return first_grade_index < second_grade_index
	return int(first_attempt.get("misses", 0)) < int(second_attempt.get("misses", 0))


func _load_scores() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var save_file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if save_file == null:
		push_warning("Local scores could not be opened: %s" % error_string(FileAccess.get_open_error()))
		return

	var parsed_data: Variant = JSON.parse_string(save_file.get_as_text())
	if not parsed_data is Dictionary:
		push_warning("Local scores contain invalid JSON and were ignored")
		return
	if int(parsed_data.get("format_version", 0)) != FORMAT_VERSION:
		push_warning("Local scores use an unsupported format version and were ignored")
		return

	var stored_scores: Variant = parsed_data.get("scores", {})
	if not stored_scores is Dictionary:
		push_warning("Local scores contain invalid score data and were ignored")
		return
	_scores = _sanitise_scores(stored_scores)


func _sanitise_scores(stored_scores: Dictionary) -> Dictionary:
	var sanitised_scores: Dictionary = {}
	for song_key_value in stored_scores:
		var song_key := String(song_key_value)
		var stored_song_scores: Variant = stored_scores[song_key_value]
		if song_key.is_empty() or not stored_song_scores is Dictionary:
			continue

		var sanitised_song_scores: Dictionary = {}
		for difficulty_key_value in stored_song_scores:
			var difficulty_key := String(difficulty_key_value)
			var stored_attempts: Variant = stored_song_scores[difficulty_key_value]
			if difficulty_key.is_empty() or not stored_attempts is Array:
				continue

			var sanitised_attempts: Array = []
			for stored_attempt in stored_attempts:
				if not stored_attempt is Dictionary:
					continue
				var grade := String(stored_attempt.get("grade", "")).to_upper()
				var misses := int(stored_attempt.get("misses", -1))
				if grade not in VALID_GRADES or misses < 0:
					continue
				sanitised_attempts.append({
					"grade": grade,
					"misses": misses,
				})
			if not sanitised_attempts.is_empty():
				sanitised_song_scores[difficulty_key] = sanitised_attempts

		if not sanitised_song_scores.is_empty():
			sanitised_scores[song_key] = sanitised_song_scores
	return sanitised_scores


func _save_scores() -> Error:
	var save_file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if save_file == null:
		return FileAccess.get_open_error()
	var save_data := {
		"format_version": FORMAT_VERSION,
		"scores": _scores,
	}
	save_file.store_string(JSON.stringify(save_data, "\t"))
	var write_error := save_file.get_error()
	save_file.close()
	return write_error
