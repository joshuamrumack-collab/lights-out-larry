extends Control


func _ready() -> void:
	UI.setup_root(self)
	var root := UI.vbox(12)
	UI.margin(self, 36).add_child(root)
	var top := UI.hbox()
	root.add_child(top)
	var back := UI.button("‹ Back", func():
		Settings.save_settings()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	top.add_child(back)
	top.add_child(UI.label("Settings", 36))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var cols := UI.hbox(30)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cols)
	var left := UI.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var right := UI.vbox(12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)

	_header(left, "Sound & game")
	_slider(left, "Music volume", Settings.music_volume, 0.0, 1.0, 0.05, func(x): Settings.music_volume = x, "%d%%", 100.0)
	_slider(left, "Hit sound volume", Settings.sfx_volume, 0.0, 1.0, 0.05, func(x): Settings.sfx_volume = x, "%d%%", 100.0)
	_hit_sound_row(left)
	_slider(left, "Note speed", Settings.scroll_speed, 0.5, 2.0, 0.05, func(x): Settings.scroll_speed = x, "%.2fx", 1.0)
	_slider(left, "Timing offset", Settings.offset_ms, -200.0, 200.0, 1.0, func(x): Settings.offset_ms = x, "%+d ms", 1.0)
	_check(left, "No Fail (can't run out of health)", Settings.no_fail, func(b): Settings.no_fail = b)
	_check(left, "Screen shake & flashes", Settings.effects, func(b): Settings.effects = b)
	_check(left, "Background: little brother & the light switch", Settings.background == "room", func(b): Settings.background = "room" if b else "plain")
	var rh := UI.hbox()
	left.add_child(rh)
	var rl := UI.label("Room", 20)
	rl.custom_minimum_size.x = 200
	rh.add_child(rl)
	var ro := OptionButton.new()
	var ids := ["auto"] + PixelRoom.THEMES
	for id in ids:
		ro.add_item("Different room per song" if id == "auto" else PixelRoom.THEME_NAMES[id])
	ro.selected = maxi(0, ids.find(Settings.room_theme))
	ro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ro.item_selected.connect(func(i): Settings.room_theme = ids[i])
	rh.add_child(ro)
	_choice(left, "Picture style", ["Smooth", "Sharp pixels"], ["smooth", "sharp"], Settings.art_style, func(v): Settings.art_style = v)
	if OS.get_name() != "Web":
		_choice(left, "Display", ["Window", "Fullscreen", "Borderless fullscreen"], ["windowed", "fullscreen", "borderless"],
			Settings.window_mode, func(v):
				Settings.window_mode = v
				Settings.apply())
		var sizes := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
		var names: Array = sizes.map(func(z): return "%d × %d" % [z.x, z.y])
		_choice(left, "Window size", names, sizes, Settings.window_size, func(v):
			Settings.window_size = v
			Settings.apply())

	_header(left, "Player & class leaderboard")
	_text(left, "Your name", Settings.player_name, "Name shown on the leaderboard", func(t): Settings.player_name = t.left(20))
	_text(left, "Leaderboard URL", Settings.leaderboard_url, "https://script.google.com/macros/s/…/exec (from your teacher)", func(t): Settings.leaderboard_url = t)
	_text(left, "Class code", Settings.class_code, "optional", func(t): Settings.class_code = t)

	_header(right, "Assist")
	right.add_child(UI.label("Makes the game easier to play. Scores are marked as assist.", 16, UI.MUTED))
	_check(right, "Wider timing windows", Settings.assist_timing, func(b): Settings.assist_timing = b)
	_check(right, "Hold notes only need a press", Settings.holds_as_taps, func(b): Settings.holds_as_taps = b)
	_check(right, "Bigger notes", Settings.big_notes, func(b): Settings.big_notes = b)
	_check(right, "Any key or button counts (switches, big buttons)", Settings.any_key, func(b): Settings.any_key = b)

	_header(right, "Eye tracker mode")
	right.add_child(UI.label("Fewer notes, and each note waits at the ring so there's time to hit it.\nWorks with eye trackers that move the mouse pointer (or click with dwell/blink).", 16, UI.MUTED))
	_check(right, "Eye tracker mode", Settings.eye_mode, func(b): Settings.eye_mode = b)
	_slider(right, "Note waits at ring", Settings.eye_wait, 0.5, 5.0, 0.25, func(x): Settings.eye_wait = x, "%.2f s", 1.0)
	_slider(right, "Time between notes", Settings.eye_gap, 1.5, 6.0, 0.25, func(x): Settings.eye_gap = x, "%.2f s", 1.0)
	_check(right, "Look at the ring to hit (no click needed)", Settings.eye_hover, func(b): Settings.eye_hover = b)
	_slider(right, "Look time to hit", Settings.eye_dwell, 0.1, 1.5, 0.05, func(x): Settings.eye_dwell = x, "%.2f s", 1.0)
	back.grab_focus()


func _header(v: VBoxContainer, text: String) -> void:
	var l := UI.label(text, 26, UI.ACCENT)
	v.add_child(l)


func _text(v: VBoxContainer, text: String, value: String, placeholder: String, setter: Callable) -> void:
	var h := UI.hbox()
	v.add_child(h)
	var l := UI.label(text, 20)
	l.custom_minimum_size.x = 200
	h.add_child(l)
	var e := LineEdit.new()
	e.text = value
	e.placeholder_text = placeholder
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.text_changed.connect(func(t: String): setter.call(t.strip_edges()))
	h.add_child(e)


func _choice(v: VBoxContainer, title: String, labels: Array, values: Array, current: Variant, on_pick: Callable) -> void:
	var h := UI.hbox()
	v.add_child(h)
	var l := UI.label(title, 20)
	l.custom_minimum_size.x = 200
	h.add_child(l)
	var ob := OptionButton.new()
	for t in labels:
		ob.add_item(str(t))
	ob.selected = maxi(0, values.find(current))
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.item_selected.connect(func(i): on_pick.call(values[i]))
	h.add_child(ob)


func _hit_sound_row(v: VBoxContainer) -> void:
	var h := UI.hbox()
	v.add_child(h)
	var l := UI.label("Hit sound", 20)
	l.custom_minimum_size.x = 200
	h.add_child(l)
	var ob := OptionButton.new()
	for i in Sfx.HIT_STYLES.size():
		ob.add_item(Sfx.HIT_NAMES[Sfx.HIT_STYLES[i]], i)
	ob.selected = maxi(0, Sfx.HIT_STYLES.find(Settings.hit_sound))
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ob)
	var p := AudioStreamPlayer.new()
	p.bus = "SFX"
	add_child(p)
	ob.item_selected.connect(func(i: int):
		Settings.hit_sound = Sfx.HIT_STYLES[i]
		var w := Sfx.hit(Settings.hit_sound, 3)
		if w:
			p.stream = w
			p.play())


func _slider(v: VBoxContainer, text: String, value: float, lo: float, hi: float, step: float, setter: Callable, fmt: String, mult: float) -> void:
	var h := UI.hbox()
	v.add_child(h)
	var l := UI.label(text, 20)
	l.custom_minimum_size.x = 200
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(s)
	var val := UI.label(fmt % (value * mult), 20, UI.MUTED)
	val.custom_minimum_size.x = 90
	h.add_child(val)
	s.value_changed.connect(func(x: float):
		setter.call(x)
		val.text = fmt % (x * mult)
		Settings.apply())


func _check(v: VBoxContainer, text: String, value: bool, setter: Callable) -> void:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = value
	c.toggled.connect(func(b: bool):
		setter.call(b)
		Settings.apply())
	v.add_child(c)
