extends Control

const CYAN := Color("55e6ff")
const VIOLET := Color("a777ff")
const CELL_FILL := Color(0.05, 0.10, 0.18, 0.62)
const CELL_BORDER := Color(0.35, 0.78, 0.92, 0.18)
const NOTE_CELL_SEQUENCE: Array[int] = [6, 4, 2, 5]

var _elapsed_time := 0.0


func _process(delta: float) -> void:
	_elapsed_time += delta
	queue_redraw()


func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return

	var board_size := minf(size.x * 0.76, size.y * 0.62)
	var cell_gap := board_size * 0.035
	var cell_size := (board_size - cell_gap * 2.0) / 3.0
	var board_origin := Vector2(size.x * 0.53 - board_size * 0.5, size.y * 0.49 - board_size * 0.5)
	var float_offset := sin(_elapsed_time * 0.8) * 7.0

	draw_set_transform(Vector2(size.x * 0.53, size.y * 0.49 + float_offset), -0.055, Vector2.ONE)
	var local_origin := board_origin - Vector2(size.x * 0.53, size.y * 0.49)

	# soft frames behind the board
	for frame_index in range(3, 0, -1):
		var frame_expansion := float(frame_index) * 13.0
		var frame_rect := Rect2(
			local_origin - Vector2.ONE * frame_expansion,
			Vector2.ONE * (board_size + frame_expansion * 2.0)
		)
		draw_rect(frame_rect, Color(0.22, 0.76, 0.95, 0.016 * float(4 - frame_index)), false, 1.0, true)

	var cell_centres: Array[Vector2] = []
	for row in range(3):
		for column in range(3):
			var cell_position := local_origin + Vector2(column, row) * (cell_size + cell_gap)
			var cell_rect := Rect2(cell_position, Vector2.ONE * cell_size)
			var cell_index := row * 3 + column
			var cell_glow_alpha := 0.025 + 0.018 * sin(
				_elapsed_time * 1.4 + float(cell_index) * 0.8
			)
			draw_rect(cell_rect.grow(7.0), Color(CYAN, cell_glow_alpha), true)
			draw_rect(cell_rect, CELL_FILL, true)
			draw_rect(cell_rect, CELL_BORDER, false, 1.25, true)
			cell_centres.append(cell_rect.get_center())

	# aim trail
	for trail_index in range(NOTE_CELL_SEQUENCE.size() - 1):
		var trail_start := cell_centres[NOTE_CELL_SEQUENCE[trail_index]]
		var trail_end := cell_centres[NOTE_CELL_SEQUENCE[trail_index + 1]]
		draw_line(trail_start, trail_end, Color(0.43, 0.88, 1.0, 0.08), 8.0, true)
		draw_line(trail_start, trail_end, Color(0.52, 0.92, 1.0, 0.25), 1.2, true)

	for note_index in range(NOTE_CELL_SEQUENCE.size()):
		var note_centre := cell_centres[NOTE_CELL_SEQUENCE[note_index]]
		var approach_phase: float = fposmod(
			_elapsed_time * 0.52 + float(note_index) * 0.235,
			1.0
		)
		var approach_intensity: float = 1.0 - absf(approach_phase - 0.82) / 0.82
		approach_intensity = clampf(approach_intensity, 0.0, 1.0)
		var approach_half_size := lerpf(cell_size * 0.64, cell_size * 0.14, approach_phase)
		var note_half_size := cell_size * 0.105
		var note_colour := CYAN.lerp(
			VIOLET,
			float(note_index) / float(NOTE_CELL_SEQUENCE.size() - 1)
		)
		_draw_glow_square(note_centre, note_half_size, note_colour, 0.2 + approach_intensity * 0.18)
		var approach_rect := Rect2(
			note_centre - Vector2.ONE * approach_half_size,
			Vector2.ONE * approach_half_size * 2.0
		)
		draw_rect(
			approach_rect,
			Color(note_colour, 0.16 + approach_intensity * 0.66),
			false,
			2.4,
			true
		)
		var note_rect := Rect2(
			note_centre - Vector2.ONE * note_half_size,
			Vector2.ONE * note_half_size * 2.0
		)
		draw_rect(note_rect, Color(note_colour, 0.94), true)
		draw_rect(note_rect, Color(0.87, 0.98, 1.0, 0.92), false, 2.0, true)
		var core_half_size := note_half_size * 0.32
		draw_rect(
			Rect2(
				note_centre - Vector2.ONE * core_half_size,
				Vector2.ONE * core_half_size * 2.0
			),
			Color(0.94, 0.99, 1.0, 0.95),
			true
		)

	# cursor marker
	var cursor_centre := cell_centres[4] + Vector2(
		sin(_elapsed_time * 0.9),
		cos(_elapsed_time * 0.73)
	) * cell_size * 0.42
	_draw_glow_circle(cursor_centre, 7.0, Color.WHITE, 0.22)
	draw_arc(cursor_centre, 10.0, 0.0, TAU, 32, Color(0.88, 0.98, 1.0, 0.9), 1.5, true)
	draw_circle(cursor_centre, 2.0, Color.WHITE)

	draw_set_transform(Vector2.ZERO)


func _draw_glow_circle(
		centre: Vector2,
		radius: float,
		glow_colour: Color,
		glow_strength: float
) -> void:
	for layer in range(5, 0, -1):
		var glow_scale := 1.0 + float(layer) * 0.42
		draw_circle(
			centre,
			radius * glow_scale,
			Color(glow_colour, glow_strength * 0.045 * float(6 - layer))
		)


func _draw_glow_square(
		centre: Vector2,
		half_size: float,
		glow_colour: Color,
		glow_strength: float
) -> void:
	for layer in range(5, 0, -1):
		var expansion := float(layer) * half_size * 0.48
		var glow_rect := Rect2(
			centre - Vector2.ONE * (half_size + expansion),
			Vector2.ONE * (half_size + expansion) * 2.0
		)
		draw_rect(
			glow_rect,
			Color(glow_colour, glow_strength * 0.035 * float(6 - layer)),
			true
		)
