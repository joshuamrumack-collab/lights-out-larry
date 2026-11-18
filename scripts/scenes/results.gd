extends Control

var r: Dictionary
var song: Dictionary


func _ready() -> void:
	UI.setup_root(self)
	r = Library.last_result
	song = Library.current
	_gameover_music()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 640
	center.add_child(panel)
	var v := UI.vbox(14)
	panel.add_child(v)
	var diff_name: String = UI.DIFF_NAMES.get(Library.difficulty, Library.difficulty)
	v.add_child(UI.label("%s  ·  %s" % [song.get("title", ""), diff_name], 24, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	if r.get("record", false):
		_build_record(v)
	else:
		_build_score(v)


func _build_score(v: VBoxContainer) -> void:
	var practice: bool = r.get("practice", false)
	var autoplay: bool = r.get("autoplay", false)
	var tutorial: bool = r.get("tutorial", false)
	var watching: bool = r.get("watching", false)
	var counts_for_progress: bool = not practice and not autoplay and not r.failed and not tutorial and not watching
	var stars_before := Progress.total_stars()
	var new_best := false
	if counts_for_progress:
		new_best = Library.submit_score(song.id, Library.difficulty, r)
		if new_best:
			Library.save_replay(str(song.id), Library.difficulty, r.replay)
	var stars_after := Progress.total_stars()

	if tutorial:
		v.add_child(UI.label("Tutorial complete!" if not r.failed else "Nice try! Give it another go.", 34, UI.ACCENT3, HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(UI.label("Next: make a song on Suno, download the MP3 and import it.", 20, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	if watching:
		v.add_child(UI.label("REPLAY", 30, UI.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	if practice:
		v.add_child(UI.label("PRACTICE", 30, UI.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	if autoplay:
		v.add_child(UI.label("AUTOPLAY: score not saved", 22, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var grade_col := UI.BAD if r.failed else (UI.ACCENT3 if r.grade == "S" else UI.ACCENT)
	v.add_child(UI.label(r.grade, 110, grade_col, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.label(UI.format_score(r.score), 48, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	if r.get("all_perfect", false):
		v.add_child(UI.label("★ ALL PERFECT ★", 30, UI.ACCENT3, HORIZONTAL_ALIGNMENT_CENTER))
	elif r.get("full_combo", false):
		v.add_child(UI.label("FULL COMBO", 30, UI.ACCENT2, HORIZONTAL_ALIGNMENT_CENTER))
	if new_best:
		v.add_child(UI.label("NEW BEST!", 26, UI.ACCENT2, HORIZONTAL_ALIGNMENT_CENTER))
	if stars_after > stars_before:
		v.add_child(UI.label("+%d ★   (total ★ %d)" % [stars_after - stars_before, stars_after], 24, UI.ACCENT3, HORIZONTAL_ALIGNMENT_CENTER))
		for u in Progress.unlocked_between(stars_before, stars_after):
			v.add_child(UI.label("Unlocked: %s %s! (Customize)" % [u.name, {"theme": "theme", "shape": "note shape", "effect": "hit effect"}[u.kind]], 22, UI.ACCENT2, HORIZONTAL_ALIGNMENT_CENTER))
	if r.get("daily", false) and counts_for_progress:
		Progress.mark_daily_done()
		v.add_child(UI.label("Daily challenge complete!  %d day streak" % Progress.streak(), 24, UI.ACCENT3, HORIZONTAL_ALIGNMENT_CENTER))
	if r.failed:
		var why := "One miss in Sudden death." if r.get("mod", "") == "sudden" else "Out of health. Try again, or turn on No Fail in Settings."
		v.add_child(UI.label(why, 20, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.label("Accuracy %.2f%%     Max combo %d" % [r.accuracy * 100.0, r.max_combo], 24, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var c: Dictionary = r.counts
	v.add_child(UI.label("Perfect %d   ·   Great %d   ·   Good %d   ·   Miss %d   ·   Misclicks %d" % [c.perfect, c.great, c.good, c.miss, int(r.get("misclicks", 0))], 22, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var el: Dictionary = r.early_late
	if el.early + el.late >= 6:
		var hint := "Mostly early" if el.early > el.late * 2 else ("Mostly late" if el.late > el.early * 2 else "Nicely balanced timing")
		v.add_child(UI.label("%s (%d early / %d late)" % [hint, el.early, el.late], 18, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))

	# Class leaderboard
	if counts_for_progress and Leaderboard.enabled():
		var lb := UI.label("", 18, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(lb)
		if Settings.player_name.strip_edges() == "":
			lb.text = "Add your name in Settings to join the class leaderboard."
		else:
			lb.text = "Sending score to the class leaderboard…"
			Leaderboard.submitted.connect(func(ok: bool):
				if is_instance_valid(lb):
					lb.text = "Score posted to the class leaderboard!" if ok else "Couldn't reach the class leaderboard.", CONNECT_ONE_SHOT)
			Leaderboard.submit(song, Library.difficulty, r)

	var h := UI.hbox()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	var retry := UI.button("Retry  (R)", _retry, 200)
	h.add_child(retry)
	if Library.has_meta("return_to_editor"):
		h.add_child(UI.button("Back to editor", func():
			Library.reset_session()
			get_tree().change_scene_to_file("res://scenes/chart_editor.tscn")))
	h.add_child(UI.button("Songs", _songs, 200))
	if tutorial and OS.get_name() != "Web":
		h.add_child(UI.button("Import a song", func():
			Library.editing = {}
			get_tree().change_scene_to_file("res://scenes/import_song.tscn")))
	if counts_for_progress or watching:
		var card_btn := UI.button("Save score card", _save_card.bind(new_best))
		h.add_child(card_btn)
	if Leaderboard.enabled() and not tutorial:
		h.add_child(UI.button("Leaderboard", func(): get_tree().change_scene_to_file("res://scenes/leaderboard_screen.tscn"), 200))
	retry.grab_focus()


func _build_record(v: VBoxContainer) -> void:
	var rec: Dictionary = r.recorded
	var holds := 0
	for d in rec.d:
		if d > 0.0:
			holds += 1
	v.add_child(UI.label("Recorded %d notes (%d holds)" % [rec.t.size(), holds], 40, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.label("Save as the %s chart? Snapping lines your taps up with the beat grid." % UI.DIFF_NAMES.get(Library.difficulty, ""), 20, UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var h := UI.hbox()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	var snap := UI.button("Save (snap to beat)", _save_chart.bind(true))
	h.add_child(snap)
	h.add_child(UI.button("Save (exact taps)", _save_chart.bind(false)))
	h.add_child(UI.button("Discard", _songs))
	snap.disabled = rec.t.size() < 4
	snap.grab_focus()


func _save_chart(quantize: bool) -> void:
	var chart: Dictionary = r.recorded
	if quantize:
		chart = ChartGen.quantize_chart(chart, float(song.bpm), float(song.offset))
	var charts: Dictionary = song.get("charts", {})
	charts[Library.difficulty] = ChartGen.to_json(chart)
	song["charts"] = charts
	Library.save_song(song)
	_songs()


func _retry() -> void:
	if not r.get("tutorial", false):
		Library.current = Library.find(song.id) if not Library.find(song.id).is_empty() else song
	Library.replay = {}
	get_tree().change_scene_to_file("res://scenes/gameplay.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		_retry()


## Renders a shareable 1200x630 picture of this result and saves it as PNG.
func _save_card(new_best: bool) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1200, 630)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var card := Control.new()
	card.size = Vector2(1200, 630)
	card.draw.connect(_draw_card.bind(card, new_best))
	vp.add_child(card)
	add_child(vp)
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null:
		return
	var fname := "%s_%s_%d.png" % [str(song.id), Library.difficulty, int(Time.get_unix_time_from_system())]
	var dlg := AcceptDialog.new()
	if OS.get_name() == "Web":
		JavaScriptBridge.download_buffer(img.save_png_to_buffer(), fname, "image/png")
		dlg.dialog_text = "Score card downloaded!"
	else:
		DirAccess.make_dir_recursive_absolute("user://scorecards")
		var path := "user://scorecards/" + fname
		img.save_png(path)
		dlg.dialog_text = "Score card saved! Opening the folder…"
		OS.shell_open(ProjectSettings.globalize_path("user://scorecards"))
	add_child(dlg)
	dlg.popup_centered()


func _draw_card(c: Control, new_best: bool) -> void:
	var th := Progress.theme()
	var f := ThemeDB.fallback_font
	var w := 1200.0
	c.draw_rect(Rect2(0, 0, w, 630), th.bg)
	for i in 6:
		c.draw_arc(Vector2(980, 315), 80.0 + i * 70.0, 0, TAU, 96, Color(th.ring, 0.18 - i * 0.025), 6.0, true)
	c.draw_rect(Rect2(0, 0, 14, 630), th.a)
	c.draw_string(f, Vector2(60, 90), "LIGHTS OUT, LARRY!", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(th.a))
	c.draw_string(f, Vector2(60, 170), str(song.get("title", "")), HORIZONTAL_ALIGNMENT_LEFT, 760, 56, UI.TEXT)
	c.draw_string(f, Vector2(60, 220), "%s  ·  %s" % [song.get("artist", ""), UI.DIFF_NAMES.get(Library.difficulty, "")], HORIZONTAL_ALIGNMENT_LEFT, 760, 28, UI.MUTED)
	c.draw_string(f, Vector2(60, 340), UI.format_score(int(r.score)), HORIZONTAL_ALIGNMENT_LEFT, -1, 96, UI.TEXT)
	c.draw_string(f, Vector2(60, 410), "Accuracy %.2f%%   ·   Max combo %d" % [float(r.accuracy) * 100.0, int(r.max_combo)], HORIZONTAL_ALIGNMENT_LEFT, -1, 32, UI.MUTED)
	var badge := ""
	if r.get("all_perfect", false):
		badge = "ALL PERFECT"
	elif r.get("full_combo", false):
		badge = "FULL COMBO"
	if new_best:
		badge += ("   ·   " if badge != "" else "") + "NEW BEST"
	if badge != "":
		c.draw_string(f, Vector2(60, 470), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, th.b)
	if Settings.player_name != "":
		c.draw_string(f, Vector2(60, 560), "played by " + Settings.player_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UI.MUTED)
	if str(song.get("suno_url", "")) != "":
		c.draw_string(f, Vector2(60, 596), "song: " + str(song.suno_url), HORIZONTAL_ALIGNMENT_LEFT, 800, 20, Color(UI.MUTED, 0.8))
	var gs := f.get_string_size(str(r.grade), HORIZONTAL_ALIGNMENT_LEFT, -1, 260)
	c.draw_string(f, Vector2(980 - gs.x * 0.5, 315 + 90), str(r.grade), HORIZONTAL_ALIGNMENT_LEFT, -1, 260, th.c if r.grade == "S" else th.a)


func _songs() -> void:
	get_tree().change_scene_to_file("res://scenes/song_select.tscn")


## After a fail the song keeps playing quietly from where you died.
func _gameover_music() -> void:
	if not r.has("music_pos") or song.is_empty():
		return
	var stream := Library.load_stream(song)
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "Music"
	p.volume_db = -9.0
	add_child(p)
	Settings.set_music_speed(p, 1.0)
	p.finished.connect(func(): p.play())
	p.play(float(r.music_pos))
