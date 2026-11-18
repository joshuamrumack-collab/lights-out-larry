class_name Cosmetics
extends RefCounted
## Unlockable looks. `stars` = total stars needed. Stars come from best grades:
## C=1, B=2, A=3, S=4, plus 1 for a full combo, per song and difficulty.

const THEMES := {
	"neon":     {"name": "Neon", "stars": 0, "bg": Color(0.05, 0.04, 0.09), "hot": Color(0.18, 0.07, 0.28), "lane": Color(0.12, 0.09, 0.2),
		"a": Color(0.38, 0.85, 1.0), "b": Color(1.0, 0.35, 0.75), "c": Color(1.0, 0.85, 0.3), "ring": Color(0.38, 0.85, 1.0)},
	"contrast": {"name": "High contrast", "stars": 0, "bg": Color(0, 0, 0), "hot": Color(0.08, 0.08, 0.08), "lane": Color(0.15, 0.15, 0.15),
		"a": Color(1, 1, 1), "b": Color(1, 0.9, 0), "c": Color(0, 0.9, 1), "ring": Color(1, 1, 1)},
	"sunset":   {"name": "Sunset", "stars": 3, "bg": Color(0.1, 0.04, 0.06), "hot": Color(0.32, 0.08, 0.1), "lane": Color(0.2, 0.08, 0.1),
		"a": Color(1.0, 0.55, 0.25), "b": Color(1.0, 0.3, 0.45), "c": Color(1.0, 0.85, 0.45), "ring": Color(1.0, 0.6, 0.3)},
	"ocean":    {"name": "Ocean", "stars": 8, "bg": Color(0.02, 0.06, 0.1), "hot": Color(0.03, 0.18, 0.28), "lane": Color(0.05, 0.12, 0.18),
		"a": Color(0.3, 0.9, 0.85), "b": Color(0.4, 0.6, 1.0), "c": Color(0.85, 1.0, 0.9), "ring": Color(0.4, 1.0, 0.9)},
	"candy":    {"name": "Candy", "stars": 15, "bg": Color(0.12, 0.05, 0.12), "hot": Color(0.3, 0.1, 0.3), "lane": Color(0.2, 0.1, 0.2),
		"a": Color(1.0, 0.5, 0.85), "b": Color(0.6, 0.9, 1.0), "c": Color(1.0, 1.0, 0.6), "ring": Color(1.0, 0.6, 0.9)},
	"toxic":    {"name": "Toxic", "stars": 25, "bg": Color(0.02, 0.07, 0.03), "hot": Color(0.06, 0.22, 0.06), "lane": Color(0.05, 0.13, 0.06),
		"a": Color(0.5, 1.0, 0.3), "b": Color(0.9, 1.0, 0.2), "c": Color(0.2, 1.0, 0.7), "ring": Color(0.5, 1.0, 0.3)},
	"gold":     {"name": "Gold", "stars": 40, "bg": Color(0.06, 0.05, 0.02), "hot": Color(0.22, 0.16, 0.04), "lane": Color(0.14, 0.11, 0.04),
		"a": Color(1.0, 0.82, 0.35), "b": Color(1.0, 0.95, 0.7), "c": Color(1.0, 0.6, 0.2), "ring": Color(1.0, 0.85, 0.4)},
}
const THEME_ORDER := ["neon", "contrast", "sunset", "ocean", "candy", "toxic", "gold"]

const SHAPES := {
	"circle":  {"name": "Circle", "stars": 0},
	"diamond": {"name": "Diamond", "stars": 5},
	"star":    {"name": "Star", "stars": 12},
	"heart":   {"name": "Heart", "stars": 20},
	"hexagon": {"name": "Hexagon", "stars": 30},
}
const SHAPE_ORDER := ["circle", "diamond", "star", "heart", "hexagon"]

const EFFECTS := {
	"sparks":    {"name": "Sparks", "stars": 0},
	"confetti":  {"name": "Confetti", "stars": 6},
	"stars":     {"name": "Little stars", "stars": 18},
	"fireworks": {"name": "Fireworks", "stars": 35},
}
const EFFECT_ORDER := ["sparks", "confetti", "stars", "fireworks"]


static func theme(id: String) -> Dictionary:
	return THEMES.get(id, THEMES.neon)


static func all_unlockables() -> Array:
	var out := []
	for id in THEME_ORDER:
		out.append({"kind": "theme", "id": id, "name": THEMES[id].name, "stars": THEMES[id].stars})
	for id in SHAPE_ORDER:
		out.append({"kind": "shape", "id": id, "name": SHAPES[id].name, "stars": SHAPES[id].stars})
	for id in EFFECT_ORDER:
		out.append({"kind": "effect", "id": id, "name": EFFECTS[id].name, "stars": EFFECTS[id].stars})
	return out


## Draws a note head of the given shape. r = radius.
static func draw_shape(ci: CanvasItem, shape: String, pos: Vector2, r: float, col: Color) -> void:
	match shape:
		"diamond":
			ci.draw_colored_polygon(PackedVector2Array([pos + Vector2(0, -r * 1.15), pos + Vector2(r * 1.15, 0), pos + Vector2(0, r * 1.15), pos + Vector2(-r * 1.15, 0)]), col)
		"star":
			var pts := PackedVector2Array()
			for k in 10:
				var rr := r * 1.25 if k % 2 == 0 else r * 0.55
				var a := -PI / 2.0 + k * PI / 5.0
				pts.append(pos + Vector2(cos(a), sin(a)) * rr)
			ci.draw_colored_polygon(pts, col)
		"heart":
			var pts := PackedVector2Array()
			for k in 32:
				var t := TAU * k / 32.0
				var x := 16.0 * pow(sin(t), 3)
				var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
				pts.append(pos + Vector2(x, y + 2.0) * (r / 15.0))
			ci.draw_colored_polygon(pts, col)
		"hexagon":
			var pts := PackedVector2Array()
			for k in 6:
				var a := PI / 6.0 + k * TAU / 6.0
				pts.append(pos + Vector2(cos(a), sin(a)) * r * 1.08)
			ci.draw_colored_polygon(pts, col)
		_:
			ci.draw_circle(pos, r, col)
