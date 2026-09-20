class_name BeatmapData
extends Resource

const GRID_SIZE := 3

var song_id: StringName = &""
var difficulty_id: StringName = &""
var audio_offset_ms := 0.0
var notes: Array[Dictionary] = []


static func load_from_file(file_path: String) -> BeatmapData:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("Cannot open beatmap: %s" % file_path)
		return null

	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		push_error(
			"Beatmap JSON error on line %d: %s"
			% [parser.get_error_line(), parser.get_error_message()]
		)
		return null
	if not parser.data is Dictionary:
		push_error("Expected a beatmap JSON object: %s" % file_path)
		return null

	var data: Dictionary = parser.data
	if not data.get("song_id") is String or not data.get("difficulty_id") is String:
		push_error("Beatmap is missing its song or difficulty ID")
		return null
	var offset: Variant = data.get("audio_offset_ms", 0.0)
	if not _is_number(offset):
		push_error("Beatmap audio_offset_ms must be a number")
		return null

	var beatmap := BeatmapData.new()
	beatmap.song_id = StringName(data["song_id"])
	beatmap.difficulty_id = StringName(data["difficulty_id"])
	beatmap.audio_offset_ms = float(offset)
	if not beatmap._read_notes(data):
		return null
	return beatmap


func get_last_note_time_ms() -> float:
	return float(notes.back()["time_ms"])


func _read_notes(data: Dictionary) -> bool:
	var raw_notes: Variant = data.get("notes")
	if not raw_notes is Array or raw_notes.is_empty():
		push_error("Beatmap notes must be a non-empty array")
		return false
	var previous_time_ms := -1.0
	for note_index in range(raw_notes.size()):
		var raw_note: Variant = raw_notes[note_index]
		if not raw_note is Dictionary:
			push_error("Note %d must be an object" % note_index)
			return false
		var note: Dictionary = raw_note
		var time_value: Variant = note.get("time_ms")
		var column_value: Variant = note.get("column")
		var row_value: Variant = note.get("row")
		if (
			not _is_number(time_value)
			or not _is_integer_number(column_value)
			or not _is_integer_number(row_value)
		):
			push_error("Note %d requires numeric time_ms, column and row" % note_index)
			return false
		var time_ms := float(time_value)
		var column := int(column_value)
		var row := int(row_value)
		if time_ms < 0.0 or time_ms <= previous_time_ms:
			push_error("Notes must use strictly increasing non-negative timestamps")
			return false
		if column < 0 or column >= GRID_SIZE or row < 0 or row >= GRID_SIZE:
			push_error("Note %d must be inside the %dx%d grid" % [
				note_index,
				GRID_SIZE,
				GRID_SIZE,
			])
			return false
		notes.append({"time_ms": time_ms, "column": column, "row": row})
		previous_time_ms = time_ms
	return true


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _is_integer_number(value: Variant) -> bool:
	return _is_number(value) and is_equal_approx(float(value), roundf(float(value)))
