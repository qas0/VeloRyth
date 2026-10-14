class_name DrawingHelpers
extends RefCounted


static func draw_glow_square(
		canvas: CanvasItem,
		centre: Vector2,
		half_size: float,
		glow_colour: Color,
		glow_strength: float,
) -> void:
	for layer in range(5, 0, -1):
		var expansion := float(layer) * half_size * 0.48
		var glow_rect := Rect2(
			centre - Vector2.ONE * (half_size + expansion),
			Vector2.ONE * (half_size + expansion) * 2.0,
		)
		canvas.draw_rect(
			glow_rect,
			Color(glow_colour, glow_strength * 0.035 * float(6 - layer)),
			true,
		)
