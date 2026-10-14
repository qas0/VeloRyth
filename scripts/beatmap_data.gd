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
		return null

	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return null
	if not parser.data is Dictionary:
		return null

	var data: Dictionary = parser.data
	if not data.get("song_id") is String or not data.get("difficulty_id") is String:
		return null
	var offset: Variant = data.get("audio_offset_ms", 0.0)
	if not _is_number(offset):
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
		return false
	var previous_time_ms := -1.0
	for raw_note in raw_notes:
		if not raw_note is Dictionary:
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
			return false
		var time_ms := float(time_value)
		var column := int(column_value)
		var row := int(row_value)
		if time_ms < 0.0 or time_ms <= previous_time_ms:
			return false
		if column < 0 or column >= GRID_SIZE or row < 0 or row >= GRID_SIZE:
			return false
		notes.append({"time_ms": time_ms, "column": column, "row": row})
		previous_time_ms = time_ms
	return true


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _is_integer_number(value: Variant) -> bool:
	return _is_number(value) and is_equal_approx(float(value), roundf(float(value)))
