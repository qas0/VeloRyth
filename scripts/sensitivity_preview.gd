class_name SensitivityPreview
extends Control

const BACKGROUND_COLOUR := Color(0.018, 0.055, 0.085, 0.96)
const BORDER_COLOUR := Color(0.23, 0.66, 0.78, 0.6)
const GRID_LINE_COLOUR := Color(0.27, 0.73, 0.84, 0.1)
const CURSOR_COLOUR := Color("5debff")

var _sensitivity_multiplier := GameSettings.DEFAULT_MOUSE_SENSITIVITY
var _preview_cursor_position := Vector2.ZERO
var _cursor_initialised := false
var _is_hovered := false
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(_reset_cursor)
	visibility_changed.connect(_on_visibility_changed)
	_reset_cursor()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mouse_motion := event as InputEventMouseMotion
		if not _cursor_initialised:
			_preview_cursor_position = mouse_motion.position
			_cursor_initialised = true
		else:
			_preview_cursor_position += mouse_motion.relative * _sensitivity_multiplier
		_preview_cursor_position = _preview_cursor_position.clamp(
			Vector2(18.0, 18.0),
			size - Vector2(18.0, 18.0)
		)
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOUR, true)
	draw_rect(Rect2(Vector2.ZERO, size), BORDER_COLOUR, false, 1.5, true)

	for column in range(1, 8):
		var x := size.x * float(column) / 8.0
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), GRID_LINE_COLOUR, 1.0)
	for row in range(1, 3):
		var y := size.y * float(row) / 3.0
		draw_line(Vector2(0.0, y), Vector2(size.x, y), GRID_LINE_COLOUR, 1.0)

	var cursor_alpha := 1.0 if _is_hovered else 0.5
	draw_circle(_preview_cursor_position, 14.0, Color(CURSOR_COLOUR, 0.08 * cursor_alpha))
	draw_arc(
		_preview_cursor_position,
		9.0,
		0.0,
		TAU,
		32,
		Color(CURSOR_COLOUR, cursor_alpha),
		2.0,
		true
	)
	draw_line(
		_preview_cursor_position - Vector2(14.0, 0.0),
		_preview_cursor_position + Vector2(14.0, 0.0),
		Color(CURSOR_COLOUR, 0.55 * cursor_alpha),
		1.0
	)
	draw_line(
		_preview_cursor_position - Vector2(0.0, 14.0),
		_preview_cursor_position + Vector2(0.0, 14.0),
		Color(CURSOR_COLOUR, 0.55 * cursor_alpha),
		1.0
	)
	draw_circle(_preview_cursor_position, 2.5, Color(0.9, 0.99, 1.0, cursor_alpha))


func _exit_tree() -> void:
	restore_system_cursor()


func set_sensitivity(value: float) -> void:
	_sensitivity_multiplier = clampf(
		value,
		GameSettings.MIN_MOUSE_SENSITIVITY,
		GameSettings.MAX_MOUSE_SENSITIVITY
	)


func restore_system_cursor() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = _previous_mouse_mode


func _reset_cursor() -> void:
	_preview_cursor_position = size * 0.5
	_cursor_initialised = false
	queue_redraw()


func _on_mouse_entered() -> void:
	_is_hovered = true
	_cursor_initialised = false
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	queue_redraw()


func _on_mouse_exited() -> void:
	_is_hovered = false
	_cursor_initialised = false
	restore_system_cursor()
	queue_redraw()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		restore_system_cursor()
