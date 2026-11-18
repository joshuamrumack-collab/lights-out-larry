extends Control
## Chart editor: place tap notes, hold notes and twist events on a timeline.
##
##   Click empty lane        add a note (drag right to make it a hold)
##   Drag a note             move it          Shift+drag: change hold length
##   Right click             delete note / event
##   N (while playing)       place a note at the playhead, on the beat
##   Space                   play / pause      Left/Right: step     Wheel: scroll   Ctrl+wheel: zoom
##   Delete                  delete selected   H: toggle hold        Ctrl+Z: undo     Ctrl+S: save

var song: Dictionary
var diff: String
var notes: Array = []    # [time, duration]
var events: Array = []   # {"t", "type", "v"}
var undo_stack: Array = []
var dirty := false

var bpm := 120.0
var beat := 0.5
var offset := 0.0
var length := 60.0
var grid: Array = []

var cur := 0.0           # playhead time
var pps := 220.0         # pixels per second
var divs := 4            # snap divisions per beat
var playing := false
var sel_note := -1
var sel_event := -1
var drag_mode := ""      # "new", "move", "hold"
var drag_origin := 0.0
var last_play_t := 0.0

var player: AudioStreamPlayer
var tick: AudioStreamPlayer
var timeline: Control
var status: Label
var props: HBoxContainer
var play_btn: Button
var snap_opt: OptionButton
var hit_sounds: CheckBox
var font: Font


func _ready() -> void:
	UI.setup_root(self)
	font = ThemeDB.fallback_font
	song = Library.current
	diff = Library.difficulty
	bpm = float(song.get("bpm", 120.0))
	beat = 60.0 / bpm
	offset = float(song.get("offset", 0.0))
	grid = song.get("grid", [])
	var stream := Library.load_stream(song)
	length = stream.get_length() if stream else float(song.get("length", 60.0))
	player = AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "Music"
	add_child(player)
	tick = AudioStreamPlayer.new()
	tick.stream = Sfx.hit("soft")
	tick.bus = "SFX"
	tick.max_polyphony = 6
	add_child(tick)
	_load_chart(Library.get_chart(song, diff, length))
	cur = Library.get_meta("editor_cursor", 0.0) if Library.has_meta("editor_cursor") else 0.0
	_build_ui()
	_refresh_props()


func _load_chart(c: Dictionary) -> void:
	notes.clear()
	var t: PackedFloat64Array = c.t
	var d: PackedFloat64Array = c.d
	for i in t.size():
		notes.append([t[i], d[i]])
	events = c.get("ev", []).duplicate(true)


func _build_ui() -> void:
	var root := UI.vbox(10)
	UI.margin(self, 20).add_child(root)

	var top := UI.hbox(8)
	root.add_child(top)
	top.add_child(UI.button("‹ Back", _back))
	top.add_child(UI.label("%s · %s" % [song.get("title", ""), UI.DIFF_NAMES.get(diff, diff)], 24))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	play_btn = UI.button("▶ Play", _toggle_play, 110)
	top.add_child(play_btn)
	snap_opt = OptionButton.new()
	for s in ["Snap: 1 beat", "Snap: 1/2", "Snap: 1/4", "Snap: off"]:
		snap_opt.add_item(s)
	snap_opt.selected = 2
	snap_opt.item_selected.connect(func(i): divs = [1, 2, 4, 0][i])
	top.add_child(snap_opt)
	var ev_opt := OptionButton.new()
	ev_opt.add_item("+ Twist event")
	for e in ["Text", "Speed", "Mirror", "Fade"]:
		ev_opt.add_item(e)
	ev_opt.item_selected.connect(func(i):
		if i > 0:
			_add_event(ChartGen.EVENT_TYPES[i - 1])
		ev_opt.selected = 0)
	top.add_child(ev_opt)
	hit_sounds = CheckBox.new()
	hit_sounds.text = "Hit sounds"
	hit_sounds.button_pressed = true
	top.add_child(hit_sounds)
	top.add_child(UI.button("Undo", _undo))
	top.add_child(UI.button("Start over", _regenerate))
	top.add_child(UI.button("Test here", _test))
	var save := UI.button("Save", _save)
	save.add_theme_color_override("font_color", UI.ACCENT3)
	top.add_child(save)

	props = UI.hbox(10)
	props.custom_minimum_size.y = 44
	root.add_child(props)

	timeline = Control.new()
	timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	timeline.focus_mode = Control.FOCUS_ALL
	timeline.mouse_filter = Control.MOUSE_FILTER_STOP
	timeline.draw.connect(_draw_timeline)
	timeline.gui_input.connect(_timeline_input)
	root.add_child(timeline)

	status = UI.label("", 16, UI.MUTED)
	root.add_child(status)
	root.add_child(UI.label("Click: add note · drag right: hold · drag note: move · Shift+drag: hold length · right click: delete · N while playing: tap in notes · Space: play · wheel: scroll · Ctrl+wheel: zoom · Ctrl+Z: undo · Ctrl+S: save", 15, Color(UI.MUTED, 0.7)))
	timeline.grab_focus.call_deferred()


# ---------------------------------------------------------------- helpers

func _ph_x() -> float:
	return timeline.size.x * 0.25


func _lane_y() -> float:
	return timeline.size.y * 0.55


func _x_of(t: float) -> float:
	return _ph_x() + (t - cur) * pps


func _t_of(x: float) -> float:
	return cur + (x - _ph_x()) / pps


func _snap(t: float) -> float:
	if divs == 0:
		return t
	var slot := beat / divs
	return offset + roundf((t - offset) / slot) * slot


func _push_undo() -> void:
	undo_stack.append([notes.duplicate(true), events.duplicate(true)])
	if undo_stack.size() > 100:
		undo_stack.pop_front()
	dirty = true


func _undo() -> void:
	if undo_stack.is_empty():
		return
	var st: Array = undo_stack.pop_back()
	notes = st[0]
	events = st[1]
	sel_note = -1
	sel_event = -1
	_refresh_props()
	timeline.queue_redraw()


func _sort_notes() -> void:
	var keep = notes[sel_note] if sel_note >= 0 and sel_note < notes.size() else null
	notes.sort_custom(func(a, b): return a[0] < b[0])
	sel_note = notes.find(keep) if keep != null else -1


func _note_at(pos: Vector2) -> int:
	var ly := _lane_y()
	if absf(pos.y - ly) > 34.0:
		return -1
	for i in notes.size():
		var x0 := _x_of(notes[i][0])
		var x1 := _x_of(notes[i][0] + notes[i][1])
		if pos.x > x0 - 16.0 and pos.x < maxf(x0 + 16.0, x1 + 10.0):
			return i
	return -1


func _event_at(pos: Vector2) -> int:
	var y := _lane_y() - 110.0
	if pos.y < y - 24.0 or pos.y > y + 24.0:
		return -1
	for i in events.size():
		if absf(pos.x - _x_of(float(events[i].t))) < 12.0:
			return i
	return -1


# ---------------------------------------------------------------- input

func _timeline_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			if mb.ctrl_pressed:
				pps = clampf(pps * 1.15, 40.0, 1200.0)
			else:
				_seek(cur - beat)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.ctrl_pressed:
				pps = clampf(pps / 1.15, 40.0, 1200.0)
			else:
				_seek(cur + beat)
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			timeline.grab_focus()
			var ei := _event_at(mb.position)
			if ei >= 0:
				sel_event = ei
				sel_note = -1
				drag_mode = "event"
				_push_undo()
			else:
				var ni := _note_at(mb.position)
				sel_event = -1
				_push_undo()
				if ni >= 0:
					sel_note = ni
					drag_mode = "hold" if mb.shift_pressed else "move"
					drag_origin = _snap(_t_of(mb.position.x)) - notes[ni][0]
				elif absf(mb.position.y - _lane_y()) < 60.0:
					var t := _snap(_t_of(mb.position.x))
					if t >= 0.0 and t <= length:
						notes.append([t, 0.0])
						sel_note = notes.size() - 1
						_sort_notes()
						drag_mode = "new"
						_play_tick()
				else:
					# click on the ruler: move the playhead
					_seek(_snap(_t_of(mb.position.x)))
					drag_mode = "seek"
			_refresh_props()
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			drag_mode = ""
			_sort_notes()
			_refresh_props()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var ei := _event_at(mb.position)
			if ei >= 0:
				_push_undo()
				events.remove_at(ei)
				sel_event = -1
			else:
				var ni := _note_at(mb.position)
				if ni >= 0:
					_push_undo()
					notes.remove_at(ni)
					sel_note = -1
			_refresh_props()
		timeline.queue_redraw()
	elif event is InputEventMouseMotion and drag_mode != "":
		var t := _snap(_t_of(event.position.x))
		match drag_mode:
			"new", "hold":
				if sel_note >= 0:
					var d := t - float(notes[sel_note][0])
					notes[sel_note][1] = d if d >= beat * 0.5 else 0.0
			"move":
				if sel_note >= 0:
					notes[sel_note][0] = clampf(t - drag_origin, 0.0, length)
			"event":
				if sel_event >= 0:
					events[sel_event].t = clampf(t, 0.0, length)
			"seek":
				_seek(t)
		timeline.queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		match k.physical_keycode:
			KEY_SPACE:
				_toggle_play()
			KEY_LEFT:
				_seek(_snap(cur - (beat / maxi(divs, 1))))
			KEY_RIGHT:
				_seek(_snap(cur + (beat / maxi(divs, 1))))
			KEY_N, KEY_ENTER:
				_push_undo()
				var t := _snap(cur)
				var exists := false
				for n in notes:
					if absf(float(n[0]) - t) < 0.02:
						exists = true
				if not exists:
					notes.append([t, 0.0])
					_sort_notes()
					_play_tick()
			KEY_DELETE, KEY_BACKSPACE:
				if sel_note >= 0:
					_push_undo()
					notes.remove_at(sel_note)
					sel_note = -1
				elif sel_event >= 0:
					_push_undo()
					events.remove_at(sel_event)
					sel_event = -1
			KEY_H:
				if sel_note >= 0:
					_push_undo()
					notes[sel_note][1] = 0.0 if float(notes[sel_note][1]) > 0.0 else beat
			KEY_Z:
				if k.ctrl_pressed:
					_undo()
			KEY_S:
				if k.ctrl_pressed:
					_save()
		_refresh_props()
		timeline.queue_redraw()
		timeline.accept_event()


func _seek(t: float) -> void:
	cur = clampf(t, 0.0, length)
	if playing:
		player.seek(cur)
	last_play_t = cur
	timeline.queue_redraw()


func _toggle_play() -> void:
	playing = not playing
	play_btn.text = "❚❚ Pause" if playing else "▶ Play"
	if playing:
		player.play(cur)
		last_play_t = cur
	else:
		player.stop()


func _play_tick() -> void:
	if hit_sounds.button_pressed:
		tick.play()


func _process(_delta: float) -> void:
	if playing:
		if not player.playing:
			_toggle_play()
			return
		var t := player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
		if t > cur:
			# hit sounds for notes the playhead passes
			for n in notes:
				if float(n[0]) > last_play_t and float(n[0]) <= t:
					_play_tick()
					break
			last_play_t = t
			cur = t
		timeline.queue_redraw()
	_update_status()


# ---------------------------------------------------------------- editing

func _add_event(type: String) -> void:
	_push_undo()
	var v: Variant = true
	match type:
		"text":
			v = "Get ready!"
		"speed":
			v = 1.5
	events.append({"t": _snap(cur), "type": type, "v": v})
	events.sort_custom(func(a, b): return float(a.t) < float(b.t))
	for i in events.size():
		if absf(float(events[i].t) - _snap(cur)) < 0.001 and events[i].type == type:
			sel_event = i
	sel_note = -1
	_refresh_props()
	timeline.queue_redraw()


func _refresh_props() -> void:
	for c in props.get_children():
		c.queue_free()
	if sel_event >= 0 and sel_event < events.size():
		var ev: Dictionary = events[sel_event]
		props.add_child(UI.label("Event at %s:" % _fmt_time(float(ev.t)), 18, UI.MUTED))
		match str(ev.type):
			"text":
				var e := LineEdit.new()
				e.text = str(ev.v)
				e.custom_minimum_size.x = 420
				e.text_changed.connect(func(t): ev.v = t; dirty = true; timeline.queue_redraw())
				props.add_child(UI.label("Show text", 18))
				props.add_child(e)
			"speed":
				var sb := SpinBox.new()
				sb.min_value = 0.4
				sb.max_value = 2.5
				sb.step = 0.05
				sb.value = float(ev.v)
				sb.value_changed.connect(func(x): ev.v = x; dirty = true; timeline.queue_redraw())
				props.add_child(UI.label("Note speed ×", 18))
				props.add_child(sb)
			"mirror", "fade":
				var cb := CheckButton.new()
				cb.text = ("Mirrored (ring on the right)" if ev.type == "mirror" else "Notes fade out near the ring")
				cb.button_pressed = bool(ev.v)
				cb.toggled.connect(func(b): ev.v = b; dirty = true; timeline.queue_redraw())
				props.add_child(cb)
		props.add_child(UI.button("Delete event", func():
			_push_undo()
			events.remove_at(sel_event)
			sel_event = -1
			_refresh_props()
			timeline.queue_redraw()))
	elif sel_note >= 0 and sel_note < notes.size():
		var n: Array = notes[sel_note]
		props.add_child(UI.label("Note at %s%s" % [_fmt_time(float(n[0])), ("  ·  hold %.2f beats" % (float(n[1]) / beat)) if float(n[1]) > 0.0 else "  ·  tap"], 18, UI.MUTED))
		props.add_child(UI.button("Make tap" if float(n[1]) > 0.0 else "Make hold (H)", func():
			_push_undo()
			n[1] = 0.0 if float(n[1]) > 0.0 else beat
			_refresh_props()
			timeline.queue_redraw()))
	else:
		props.add_child(UI.label("Nothing selected. Click the lane to add notes, or play the song and press N on the beats.", 18, UI.MUTED))


func _fmt_time(t: float) -> String:
	var b := (t - offset) / beat
	return "%d:%05.2f  (bar %d, beat %.2f)" % [int(t) / 60, fmod(t, 60.0), int(floor(b / 4.0)) + 1, fposmod(b, 4.0) + 1.0]


func _update_status() -> void:
	var holds := 0
	for n in notes:
		if float(n[1]) > 0.0:
			holds += 1
	status.text = "%s / %d:%02d   ·   %d notes (%d holds)   ·   %d events   ·   %s" % [
		_fmt_time(cur), int(length) / 60, int(length) % 60, notes.size(), holds, events.size(), "unsaved changes" if dirty else "saved"]


func _chart() -> Dictionary:
	_sort_notes()
	var t := PackedFloat64Array()
	var d := PackedFloat64Array()
	for n in notes:
		t.append(float(n[0]))
		d.append(float(n[1]))
	var ev := events.duplicate(true)
	ev.sort_custom(func(a, b): return float(a.t) < float(b.t))
	return {"t": t, "d": d, "ev": ev}


func _save() -> void:
	var charts: Dictionary = song.get("charts", {})
	charts[diff] = ChartGen.to_json(_chart())
	song["charts"] = charts
	Library.save_song(song)
	var fresh := Library.find(str(song.id))
	if not fresh.is_empty():
		song = fresh
		Library.current = fresh
	dirty = false


func _regenerate() -> void:
	_push_undo()
	var tmp := song.duplicate(true)
	tmp["charts"] = {}
	_load_chart(ChartGen.generate(tmp, diff, length))
	sel_note = -1
	sel_event = -1
	_refresh_props()
	timeline.queue_redraw()


func _test() -> void:
	_save()
	player.stop()
	Library.set_meta("editor_cursor", cur)
	Library.set_meta("return_to_editor", true)
	Library.mode = "play"
	var bar := beat * 4.0
	Library.practice = {"speed": 1.0, "start": maxf(0.0, offset + floorf((cur - offset) / bar) * bar), "loop_bars": 0}
	get_tree().change_scene_to_file("res://scenes/gameplay.tscn")


func _back() -> void:
	if dirty:
		var dlg := ConfirmationDialog.new()
		dlg.dialog_text = "Save your changes first?"
		dlg.ok_button_text = "Save"
		dlg.cancel_button_text = "Discard"
		dlg.confirmed.connect(func():
			_save()
			_leave())
		dlg.canceled.connect(_leave)
		add_child(dlg)
		dlg.popup_centered()
	else:
		_leave()


func _leave() -> void:
	if Library.has_meta("editor_cursor"):
		Library.remove_meta("editor_cursor")
	get_tree().change_scene_to_file("res://scenes/song_select.tscn")


# ---------------------------------------------------------------- drawing

func _draw_timeline() -> void:
	var sz := timeline.size
	var th := Progress.theme()
	var ly := _lane_y()
	timeline.draw_rect(Rect2(Vector2.ZERO, sz), th.bg)

	# music strength (where the song has hits) along the bottom
	var slot := beat / 4.0
	if not grid.is_empty():
		var g0 := maxi(0, int((_t_of(0) - offset) / slot))
		var g1 := mini(grid.size(), int((_t_of(sz.x) - offset) / slot) + 1)
		for g in range(g0, g1):
			var x := _x_of(offset + g * slot)
			var h := float(grid[g]) * 60.0
			timeline.draw_rect(Rect2(x, sz.y - 10 - h, maxf(1.0, slot * pps - 1.0), h), Color(th.a, 0.25))
		timeline.draw_string(font, Vector2(8, sz.y - 76), "music hits", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(UI.MUTED, 0.6))

	# grid lines
	var sub := maxi(divs, 1)
	var step := beat / sub
	var k0 := int(floor((_t_of(0) - offset) / step))
	var k1 := int(ceil((_t_of(sz.x) - offset) / step))
	if (k1 - k0) < 2000:
		for k in range(k0, k1 + 1):
			var t := offset + k * step
			if t < 0.0 or t > length:
				continue
			var x := _x_of(t)
			var is_beat := posmod(k, sub) == 0
			var is_bar := is_beat and posmod(k / sub, 4) == 0
			var a := 0.35 if is_bar else (0.14 if is_beat else 0.05)
			timeline.draw_line(Vector2(x, 30), Vector2(x, sz.y - 80), Color(1, 1, 1, a), 2.0 if is_bar else 1.0)
			if is_bar:
				timeline.draw_string(font, Vector2(x + 3, 22), str(int(floor((t - offset) / (beat * 4.0))) + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.MUTED)

	# song bounds + lane
	timeline.draw_rect(Rect2(_x_of(0.0), ly - 34, length * pps, 68), Color(th.lane, 0.9))
	timeline.draw_string(font, Vector2(8, ly - 110 + 5), "twists", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(UI.MUTED, 0.6))
	timeline.draw_line(Vector2(0, ly - 110), Vector2(sz.x, ly - 110), Color(1, 1, 1, 0.06), 1.0)

	# notes
	for i in notes.size():
		var t := float(notes[i][0])
		var d := float(notes[i][1])
		var x := _x_of(t)
		if x + d * pps < -40 or x > sz.x + 40:
			continue
		var b := (t - offset) / beat
		var subp := posmod(roundi(b * 4.0), 4)
		var col: Color = th.a if subp == 0 else (th.b if subp == 2 else th.c)
		if d > 0.0:
			timeline.draw_rect(Rect2(x, ly - 14, d * pps, 28), Color(col, 0.55))
			timeline.draw_circle(Vector2(x + d * pps, ly), 12.0, Color(col, 0.7))
		Cosmetics.draw_shape(timeline, Progress.shape_id, Vector2(x, ly), 22.0, col)
		Cosmetics.draw_shape(timeline, Progress.shape_id, Vector2(x, ly), 9.0, Color(1, 1, 1, 0.85))
		if i == sel_note:
			timeline.draw_arc(Vector2(x, ly), 30.0, 0, TAU, 32, Color.WHITE, 3.0, true)

	# events
	for i in events.size():
		var ev: Dictionary = events[i]
		var x := _x_of(float(ev.t))
		if x < -200 or x > sz.x + 20:
			continue
		var y := ly - 110.0
		var col: Color = {"text": UI.TEXT, "speed": UI.ACCENT3, "mirror": UI.ACCENT2, "fade": UI.ACCENT}.get(str(ev.type), UI.TEXT)
		timeline.draw_line(Vector2(x, y), Vector2(x, ly + 34), Color(col, 0.35), 2.0)
		timeline.draw_colored_polygon(PackedVector2Array([Vector2(x - 9, y - 9), Vector2(x + 9, y - 9), Vector2(x + 9, y + 9), Vector2(x - 9, y + 9)]), col if i != sel_event else Color.WHITE)
		var label := ""
		match str(ev.type):
			"text":
				label = '"%s"' % str(ev.v)
			"speed":
				label = "speed ×%.2f" % float(ev.v)
			"mirror":
				label = "mirror on" if bool(ev.v) else "mirror off"
			"fade":
				label = "fade on" if bool(ev.v) else "fade off"
		timeline.draw_string(font, Vector2(x + 13, y - 14), label, HORIZONTAL_ALIGNMENT_LEFT, 260, 15, col)

	# playhead
	var px := _ph_x()
	timeline.draw_line(Vector2(px, 0), Vector2(px, sz.y), Color(UI.ACCENT3, 0.9), 2.0)
	timeline.draw_arc(Vector2(px, ly), 40.0, 0, TAU, 40, Color(th.ring, 0.6), 3.0, true)
