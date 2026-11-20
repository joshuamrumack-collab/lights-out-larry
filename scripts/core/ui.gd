class_name UI
extends RefCounted
## Small helpers for building the menus in code, plus the shared colour palette.

const BG := Color(0.05, 0.04, 0.09)
const PANEL := Color(0.10, 0.08, 0.17)
const ACCENT := Color(0.38, 0.85, 1.0)      # cyan
const ACCENT2 := Color(1.0, 0.35, 0.75)     # pink
const ACCENT3 := Color(1.0, 0.85, 0.3)      # yellow
const TEXT := Color(0.93, 0.92, 1.0)
const MUTED := Color(0.6, 0.57, 0.75)
const BAD := Color(1.0, 0.3, 0.35)

const DIFF_NAMES := {"easy": "Easy", "normal": "Normal", "hard": "Hard", "expert": "Expert", "twist": "Chaos"}
const DIFF_COLORS := {
	"easy": Color(0.45, 1.0, 0.55),
	"normal": Color(0.38, 0.85, 1.0),
	"hard": Color(1.0, 0.6, 0.25),
	"expert": Color(1.0, 0.3, 0.6),
	"twist": Color(0.75, 0.5, 1.0),
}

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 22

	var normal := _box(PANEL.lightened(0.08), ACCENT.darkened(0.5))
	var hover := _box(PANEL.lightened(0.18), ACCENT)
	var pressed := _box(ACCENT.darkened(0.45), ACCENT)
	var focus := _box(Color(0, 0, 0, 0), ACCENT2, 3)
	focus.draw_center = false
	var disabled := _box(PANEL, PANEL.lightened(0.1))
	for type in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("focus", type, focus)
		t.set_stylebox("disabled", type, disabled)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, MUTED.darkened(0.3))

	var line := _box(BG.lightened(0.04), MUTED.darkened(0.3))
	var line_focus := _box(BG.lightened(0.06), ACCENT)
	for type in ["LineEdit", "SpinBox"]:
		t.set_stylebox("normal", type, line)
		t.set_stylebox("focus", type, line_focus)
		t.set_color("font_color", type, TEXT)

	var panel := _box(PANEL, ACCENT.darkened(0.6), 2, 14)
	panel.set_content_margin_all(22)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	t.set_color("font_color", "Label", TEXT)

	var bar_bg := _box(BG.lightened(0.05), Color(0, 0, 0, 0), 0, 6)
	var bar_fill := _box(ACCENT, Color(0, 0, 0, 0), 0, 6)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)

	var slider_area := _box(ACCENT, Color(0, 0, 0, 0), 0, 4)
	slider_area.content_margin_top = 4
	slider_area.content_margin_bottom = 4
	var slider_bg := _box(BG.lightened(0.1), Color(0, 0, 0, 0), 0, 4)
	slider_bg.content_margin_top = 4
	slider_bg.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", slider_bg)
	t.set_stylebox("grabber_area", "HSlider", slider_area)
	t.set_stylebox("grabber_area_highlight", "HSlider", slider_area)
	_theme = t
	return t


static func _box(bg: Color, border: Color, border_w: int = 2, radius: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


## Prepares a full-screen root Control: applies the theme and returns it for chaining.
static func setup_root(root: Control) -> void:
	root.theme = get_theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)


static func button(text: String, on_press: Callable, min_width: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	if min_width > 0.0:
		b.custom_minimum_size.x = min_width
	b.pressed.connect(on_press)
	return b


static func label(text: String, size: int = 22, color: Color = TEXT, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l


static func vbox(sep: int = 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


## A full-rect MarginContainer to put screen content in.
static func margin(root: Control, m: int = 40) -> MarginContainer:
	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, m)
	root.add_child(mc)
	return mc


static func format_score(v: int) -> String:
	var s := str(v)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out
	return out


static func grade_for(acc: float, failed: bool) -> String:
	if failed:
		return "F"
	if acc >= 0.95:
		return "S"
	if acc >= 0.90:
		return "A"
	if acc >= 0.80:
		return "B"
	if acc >= 0.70:
		return "C"
	return "D"
