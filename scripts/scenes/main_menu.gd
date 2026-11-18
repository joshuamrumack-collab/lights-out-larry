extends Control

var _t := 0.0
var music: AudioStreamPlayer
var m_bpm := 100.0
var m_offset := 0.0
var house := HouseBg.new()
var _last_beat := -1
var _house_layer: Control
const PANEL_W := 420.0
const MENU_SONG := "Larry at the Switch (take 2)"


func _ready() -> void:
	UI.setup_root(self)
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.show_behind_parent = true
	layer.texture_filter = Settings.art_filter()
	layer.draw.connect(func(): house.draw(layer, Rect2(Vector2(PANEL_W * 0.5, 0), layer.size)))
	add_child(layer)
	_house_layer = layer
	Library.reset_session()
	# menu on the left, the house on the right
	var side := MarginContainer.new()
	side.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	side.offset_right = PANEL_W
	for m in ["margin_left", "margin_right"]:
		side.add_theme_constant_override(m, 36)
	add_child(side)
	var mid := CenterContainer.new()
	side.add_child(mid)
	var v := UI.vbox(7)
	mid.add_child(v)
	v.add_child(UI.label("LIGHTS OUT,\nLARRY!", 50, Color(1.0, 0.86, 0.5), HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.label("one button  ·  every beat", 18, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.label("★ %d stars" % Progress.total_stars(), 20, UI.ACCENT3, HORIZONTAL_ALIGNMENT_CENTER))
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 4
	v.add_child(spacer)
	var play := UI.button("Play", _go.bind("res://scenes/song_select.tscn"), PANEL_W - 72)
	var learn := UI.button("Learn to play", func():
		Library.start_tutorial()
		get_tree().change_scene_to_file("res://scenes/gameplay.tscn"))
	if Library.songs.is_empty():
		v.add_child(learn)
		learn.add_theme_color_override("font_color", UI.ACCENT3)
	v.add_child(play)
	if not Library.songs.is_empty():
		v.add_child(learn)
	_daily_button(v)
	if OS.get_name() != "Web":
		v.add_child(UI.button("Import Suno song", _import))
	v.add_child(UI.button("Customize", _go.bind("res://scenes/customize.tscn")))
	v.add_child(UI.button("Calibrate timing", _go.bind("res://scenes/calibration.tscn")))
	v.add_child(UI.button("Settings", _go.bind("res://scenes/settings_menu.tscn")))
	if OS.get_name() != "Web":
		v.add_child(UI.button("Quit", func(): get_tree().quit()))
	for b in v.get_children():
		if b is Button:
			_light_switch_style(b)
	if Library.songs.is_empty():
		learn.grab_focus()
	else:
		play.grab_focus()
	_start_music()


## Buttons look like dark windows that switch on (with a little bulb flicker) when hovered.
func _light_switch_style(b: Button) -> void:
	var off := StyleBoxFlat.new()
	off.bg_color = Color(0.07, 0.07, 0.14, 0.82)
	off.border_color = Color(0.22, 0.2, 0.32)
	off.set_border_width_all(3)
	off.set_corner_radius_all(4)
	off.content_margin_left = 16
	off.content_margin_right = 16
	off.content_margin_top = 5
	off.content_margin_bottom = 5
	var on := off.duplicate() as StyleBoxFlat
	on.bg_color = Color(1.0, 0.86, 0.5)
	on.border_color = Color(0.45, 0.25, 0.12)
	on.shadow_color = Color(1.0, 0.75, 0.3, 0.55)
	on.shadow_size = 14
	b.add_theme_stylebox_override("normal", off)
	b.add_theme_stylebox_override("hover", on)
	b.add_theme_stylebox_override("focus", on)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_color_override("font_color", Color(0.62, 0.62, 0.75))
	b.add_theme_color_override("font_hover_color", Color(0.2, 0.1, 0.05))
	b.add_theme_color_override("font_focus_color", Color(0.2, 0.1, 0.05))
	b.add_theme_color_override("font_pressed_color", Color(0.2, 0.1, 0.05))
	b.add_theme_color_override("font_hover_pressed_color", Color(0.2, 0.1, 0.05))
	b.add_theme_font_size_override("font_size", 19 if b.text.find("\n") < 0 else 16)
	b.mouse_entered.connect(_flicker.bind(b))
	b.focus_entered.connect(_flicker.bind(b))


func _flicker(b: Button) -> void:
	if b.disabled:
		return
	var tw := b.create_tween()
	for a in [0.45, 1.0, 0.6, 1.0]:
		tw.tween_property(b, "modulate", Color(a, a, a), 0.035)


## Menu music: the chorus of a random song from your library (or the tutorial beat), pulsing to its tempo.
func _start_music() -> void:
	var s: Dictionary = {}
	for song in Library.songs:
		if str(song.get("title", "")) == MENU_SONG:
			s = song
	if s.is_empty():
		s = Library.songs.pick_random() if not Library.songs.is_empty() else Library.tutorial_song()
	if s.is_empty():
		return
	var stream := Library.load_stream(s)
	if stream == null:
		return
	m_bpm = float(s.get("bpm", 100.0))
	m_offset = float(s.get("offset", 0.0))
	music = AudioStreamPlayer.new()
	music.stream = stream
	music.bus = "Music"
	music.volume_db = -40.0
	add_child(music)
	music.finished.connect(func(): music.play())   # loop it
	music.play(0.0 if str(s.get("title", "")) == MENU_SONG else (Library.preview_start(s) if not Library.songs.is_empty() else 4.8))
	create_tween().tween_property(music, "volume_db", -9.0, 2.0)


func _daily_button(v: VBoxContainer) -> void:
	var d := Progress.daily()
	var b := Button.new()
	b.add_theme_font_size_override("font_size", 19)
	if d.is_empty():
		b.text = "Daily challenge (import a song first)"
		b.disabled = true
	else:
		var s := Library.find(d.song_id)
		var mod: Dictionary = Progress.MODS[d.mod]
		var streak := Progress.streak()
		b.text = "Daily challenge%s\n%s · %s · %s%s" % [
			"  ✓ done" if d.done else "", s.get("title", "?"), UI.DIFF_NAMES[d.diff], mod.name,
			"   🔥 %d day streak" % streak if streak > 0 else ""]
		b.text = b.text.replace("🔥 ", "")
		b.tooltip_text = mod.desc
		b.pressed.connect(func():
			Library.current = s
			Library.difficulty = d.diff
			Library.mode = "play"
			Library.practice = {}
			Library.modifier = d.mod
			Library.is_daily = true
			get_tree().change_scene_to_file("res://scenes/gameplay.tscn"))
	v.add_child(b)


func _import() -> void:
	Library.editing = {}
	get_tree().change_scene_to_file("res://scenes/import_song.tscn")


func _go(path: String) -> void:
	get_tree().change_scene_to_file(path)


func _process(delta: float) -> void:
	_t += delta
	var beat := 60.0 / m_bpm
	var bt := _t
	if music and music.playing:
		bt = music.get_playback_position() + AudioServer.get_time_since_last_mix() - m_offset
	var n := int(floor(bt / beat))
	if n != _last_beat:
		_last_beat = n
		house.beat()
	house.update(delta)
	queue_redraw()


func _draw() -> void:
	var th := Progress.theme()
	var beat := 60.0 / m_bpm
	var ph := fposmod(_t / 0.6, 1.0)
	if music and music.playing:
		var mt := music.get_playback_position() + AudioServer.get_time_since_last_mix()
		ph = fposmod((mt - m_offset) / beat, 1.0)
	var pulse := pow(1.0 - ph, 3.0)
	_house_layer.queue_redraw()
	# soft dark panel behind the menu, fading into the night
	var steps := 24
	for i in steps:
		var x0 := PANEL_W * float(i) / steps
		var a := 0.62 * clampf(1.15 - float(i) / steps, 0.0, 1.0)
		draw_rect(Rect2(x0, 0, PANEL_W / steps + 1, size.y), Color(0.03, 0.03, 0.08, a))
	draw_rect(Rect2(PANEL_W, 0, 60, size.y), Color(0.03, 0.03, 0.08, 0.0))
	draw_rect(Rect2(Vector2.ZERO, size), Color(th.hot, pulse * 0.04))
	if size.y > size.x * 1.05:
		var f := ThemeDB.fallback_font
		draw_string(f, Vector2(0, 40), "Turn your device sideways for the best view", HORIZONTAL_ALIGNMENT_CENTER, size.x, 26, Color(1.0, 0.86, 0.5))
