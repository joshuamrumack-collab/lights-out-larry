extends Control
## Pick your theme, note shape and hit effect. Locked items show how many stars they need.

var grid_box: VBoxContainer
var preview: Control
var stars_label: Label
var _t := 0.0


func _ready() -> void:
	UI.setup_root(self)
	var root := UI.vbox(16)
	UI.margin(self, 36).add_child(root)
	var top := UI.hbox()
	root.add_child(top)
	top.add_child(UI.button("‹ Back", func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn")))
	var title := UI.label("Customize", 36)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	stars_label = UI.label("", 26, UI.ACCENT3)
	top.add_child(stars_label)

	var body := UI.hbox(24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	grid_box = UI.vbox(10)
	grid_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_box)

	var pv := PanelContainer.new()
	pv.custom_minimum_size = Vector2(380, 0)
	body.add_child(pv)
	preview = Control.new()
	preview.draw.connect(_draw_preview)
	pv.add_child(preview)
	_build()


func _build() -> void:
	for c in grid_box.get_children():
		c.queue_free()
	var stars := Progress.total_stars()
	stars_label.text = "★ %d" % stars
	var nxt := Progress.next_unlock()
	if not nxt.is_empty():
		grid_box.add_child(UI.label("Next unlock: %s at ★ %d. Earn stars with better grades (C=1 … S=4, +1 for a full combo)." % [nxt.name, nxt.stars], 18, UI.MUTED))
	_section("Theme", "theme", Cosmetics.THEME_ORDER, Cosmetics.THEMES, Progress.theme_id, stars)
	_section("Note shape", "shape", Cosmetics.SHAPE_ORDER, Cosmetics.SHAPES, Progress.shape_id, stars)
	_section("Hit effect", "effect", Cosmetics.EFFECT_ORDER, Cosmetics.EFFECTS, Progress.effect_id, stars)


func _section(title: String, kind: String, order: Array, defs: Dictionary, current: String, stars: int) -> void:
	grid_box.add_child(UI.label(title, 26))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	grid_box.add_child(flow)
	for id in order:
		var d: Dictionary = defs[id]
		var locked := stars < int(d.stars)
		var b := Button.new()
		b.custom_minimum_size = Vector2(170, 56)
		b.text = str(d.name) + ("   ★%d to unlock" % d.stars if locked else "") + ("  ✓" if id == current else "")
		b.disabled = locked
		b.pressed.connect(_pick.bind(kind, id))
		flow.add_child(b)


func _pick(kind: String, id: String) -> void:
	match kind:
		"theme":
			Progress.theme_id = id
		"shape":
			Progress.shape_id = id
		"effect":
			Progress.effect_id = id
	Progress.save()
	_build()


func _process(delta: float) -> void:
	_t += delta
	preview.queue_redraw()


func _draw_preview() -> void:
	var th := Progress.theme()
	var sz := preview.size
	preview.draw_rect(Rect2(Vector2.ZERO, sz), th.bg)
	var y := sz.y * 0.5
	preview.draw_rect(Rect2(0, y - 34, sz.x, 68), th.lane)
	var target := Vector2(70, y)
	var pulse := pow(1.0 - fposmod(_t / 0.5, 1.0), 3.0)
	preview.draw_arc(target, 40.0 + pulse * 5.0, 0, TAU, 48, th.ring, 4.0, true)
	var cols := [th.a, th.b, th.c]
	for i in 4:
		var x := target.x + fposmod(i * 90.0 - _t * 180.0, 360.0)
		var col: Color = cols[i % 3]
		Cosmetics.draw_shape(preview, Progress.shape_id, Vector2(x, y), 26.0, col)
		Cosmetics.draw_shape(preview, Progress.shape_id, Vector2(x, y), 11.0, Color(1, 1, 1, 0.85))
	# effect sample
	var k := fposmod(_t, 1.0)
	for j in 10:
		var a := j * TAU / 10.0
		var p := target + Vector2(cos(a), sin(a)) * (20.0 + k * 90.0)
		var c := Color(cols[j % 3], 1.0 - k)
		match Progress.effect_id:
			"confetti":
				preview.draw_rect(Rect2(p, Vector2(8, 4)), c)
			"stars":
				Cosmetics.draw_shape(preview, "star", p, 5.0, c)
			"fireworks":
				preview.draw_line(p, p - Vector2(cos(a), sin(a)) * 14.0, c, 2.0)
			_:
				preview.draw_circle(p, 4.0, c)
	preview.draw_string(ThemeDB.fallback_font, Vector2(20, 40), "Preview", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UI.MUTED)
