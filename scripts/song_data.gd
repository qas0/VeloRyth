class_name SongData
extends Resource

@export var song_id: StringName = &""
@export var title: String = ""
@export var artist: String = ""
@export var audio_stream: AudioStream
@export var preview_start_seconds := -1.0
@export var bpm: float = 0.0
@export var difficulties: Array[SongDifficultyData] = []


func get_duration_seconds() -> float:
	if audio_stream == null:
		return 0.0
	return audio_stream.get_length()
