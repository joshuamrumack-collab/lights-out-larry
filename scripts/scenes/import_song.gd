extends Control
## Import a Suno song (audio file + Suno link), let the game analyse it, then fine-tune timing.
## Also used for "Edit timing" on an existing song (Library.editing).

var file_path := ""
var song: Dictionary = {}
var is_new := true
var saved := false
var stream: AudioStream
var analyzer: SongAnalyzer
var thread: Thread
var analysis: Dictionary = {}
var _looked_up := ""
var _auto_title := ""

var step_pick: VBoxContainer
var step_analyze: VBoxContainer
var step_timing: VBoxContainer
var file_label: Label
var url_edit: LineEdit
var title_edit: LineEdit
var artist_edit: LineEdit
var url_hint: Label
var analyze_btn: Button
var progress_bar: ProgressBar
var status_label: Label
var bpm_spin: SpinBox
var offset_spin: SpinBox
var preview_btn: Button
var tap_btn: Button
var beat_flash: Control
var dialog: FileDialog

var player: AudioStreamPlayer
var click_hi: AudioStreamPlayer
var click_lo: AudioStreamPlayer
var previewing := false
var _last_beat := -999
var _taps: Array[float] = []
var _flash := 0.0
var _flash_bar := false


func _ready() -> void:
	UI.setup_root(self)
	player = AudioStreamPlayer.new()
	player.bus = "Music"
	add_child(player)
	click_hi = AudioStreamPlayer.new()
	click_hi.stream = Sfx.click(2200.0, 0.05, 0.8)
	click_hi.bus = "SFX"
	add_child(click_hi)
	click_lo = AudioStreamPlayer.new()
	click_lo.stream = Sfx.click(1400.0, 0.05, 0.7)
	click_lo.bus = "SFX"
	add_child(click_lo)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 0)
	center.add_child(panel)
	var root := UI.vbox(16)
	panel.add_child(root)

	var head := UI.hbox()
	root.add_child(head)
	head.add_child(UI.button("‹ Back", _back))
	var heading := UI.label("Import a Suno song" if Library.editing.is_empty() else "Edit timing", 32)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(heading)

	_build_pick(root)
	_build_analyze(root)
	_build_timing(root)

	get_window().files_dropped.connect(_on_files_dropped)

	if not Library.editing.is_empty():
		is_new = false
		song = Library.editing
		step_pick.visible = false
		stream = Library.load_stream(song)
		_start_analysis()
	else:
		step_analyze.visible = false
		step_timing.visible = false
		_validate()


var share_info: Label
var share_link: LinkButton


func _build_pick(root: VBoxContainer) -> void:
	step_pick = UI.vbox(12)
	root.add_child(step_pick)
	# A chart shared by a classmate: paste the code (or open the .onebeat file), then add the audio.
	var sh := UI.hbox(8)
	step_pick.add_child(sh)
	sh.add_child(UI.label("Got a chart from a friend?", 18, UI.ACCENT))
	var code_edit := LineEdit.new()
	code_edit.placeholder_text = "paste the share code (ONEBEAT1:…)"
	code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_edit.text_changed.connect(func(t): _use_share(Library.parse_share(t)))
	sh.add_child(code_edit)
	if OS.get_name() != "Web":
		sh.add_child(UI.button("Open file…", _open_share_file))
	share_info = UI.label("", 17, UI.ACCENT3)
	share_info.visible = false
	step_pick.add_child(share_info)
	share_link = LinkButton.new()
	share_link.text = "Open the song on Suno to download it"
	share_link.add_theme_color_override("font_color", UI.ACCENT)
	share_link.visible = false
	share_link.pressed.connect(func(): OS.shell_open(str(Library.share_pending.get("suno_url", ""))))
	step_pick.add_child(share_link)
	step_pick.add_child(HSeparator.new())
	step_pick.add_child(UI.label("On suno.com: open your song → ⋯ → Download → MP3 (or WAV), then choose that file.", 20, UI.MUTED))
	var fh := UI.hbox()
	step_pick.add_child(fh)
	fh.add_child(UI.button("Choose audio file…", _open_dialog))
	file_label = UI.label("…or drag the file onto this window", 18, UI.MUTED)
	file_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_label.clip_text = true
	fh.add_child(file_label)

	step_pick.add_child(UI.label("Suno link (optional, fills in title + artist and is shown as the song's credit):", 20, UI.MUTED))
	url_edit = LineEdit.new()
	url_edit.placeholder_text = "https://suno.com/song/…"
	url_edit.text_changed.connect(func(_t): _validate())
	url_edit.focus_exited.connect(_validate)
	url_edit.text_changed.connect(func(_t): _on_url_entered())
	step_pick.add_child(url_edit)
	url_hint = UI.label("", 16, UI.BAD)
	step_pick.add_child(url_hint)

	var th := UI.hbox()
	step_pick.add_child(th)
	title_edit = LineEdit.new()
	title_edit.placeholder_text = "Title"
	title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_edit.text_changed.connect(func(_t): _validate())
	th.add_child(title_edit)
	artist_edit = LineEdit.new()
	artist_edit.placeholder_text = "Your name / Suno handle"
	artist_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(artist_edit)

	analyze_btn = UI.button("Analyze song  →", _on_analyze)
	analyze_btn.disabled = true
	step_pick.add_child(analyze_btn)


func _build_analyze(root: VBoxContainer) -> void:
	step_analyze = UI.vbox(10)
	root.add_child(step_analyze)
	status_label = UI.label("Listening to the song…", 22)
	step_analyze.add_child(status_label)
	progress_bar = ProgressBar.new()
	progress_bar.max_value = 1.0
	progress_bar.custom_minimum_size.y = 22
	progress_bar.show_percentage = false
	step_analyze.add_child(progress_bar)


func _build_timing(root: VBoxContainer) -> void:
	step_timing = UI.vbox(14)
	root.add_child(step_timing)
	step_timing.add_child(UI.label("Check the beat: press Preview. The clicks should land on the beat\n(high click = start of a bar). Adjust if they don't.", 19, UI.MUTED))

	var row := UI.hbox(16)
	step_timing.add_child(row)
	row.add_child(UI.label("BPM", 22))
	bpm_spin = SpinBox.new()
	bpm_spin.min_value = 40
	bpm_spin.max_value = 260
	bpm_spin.step = 0.01
	bpm_spin.custom_minimum_size.x = 150
	row.add_child(bpm_spin)
	row.add_child(UI.button("÷2", func(): bpm_spin.value = bpm_spin.value / 2.0))
	row.add_child(UI.button("×2", func(): bpm_spin.value = bpm_spin.value * 2.0))
	tap_btn = UI.button("Tap tempo", _tap)
	row.add_child(tap_btn)

	var row2 := UI.hbox(16)
	step_timing.add_child(row2)
	row2.add_child(UI.label("First beat (ms)", 22))
	offset_spin = SpinBox.new()
	offset_spin.min_value = -2000
	offset_spin.max_value = 20000
	offset_spin.step = 1
	offset_spin.custom_minimum_size.x = 150
	row2.add_child(offset_spin)
	row2.add_child(UI.button("−10", func(): offset_spin.value -= 10))
	row2.add_child(UI.button("+10", func(): offset_spin.value += 10))
	row2.add_child(UI.button("Shift 1 beat", func(): offset_spin.value += 60000.0 / bpm_spin.value))

	var row3 := UI.hbox(16)
	step_timing.add_child(row3)
	preview_btn = UI.button("▶  Preview with clicks", _toggle_preview)
	row3.add_child(preview_btn)
	beat_flash = Control.new()
	beat_flash.custom_minimum_size = Vector2(44, 44)
	beat_flash.draw.connect(_draw_flash)
	row3.add_child(beat_flash)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row3.add_child(spacer)
	var save := UI.button("Save song ✓", _save)
	save.add_theme_font_size_override("font_size", 26)
	row3.add_child(save)


# ---------------------------------------------------------------- step 1

func _open_dialog() -> void:
	if dialog == null:
		dialog = FileDialog.new()
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.use_native_dialog = true
		dialog.filters = PackedStringArray(["*.mp3, *.ogg, *.wav ; Audio"])
		dialog.file_selected.connect(_set_file)
		add_child(dialog)
	dialog.popup_centered_ratio(0.7)


func _on_files_dropped(files: PackedStringArray) -> void:
	if not step_pick.visible:
		return
	for f in files:
		if f.get_extension().to_lower() in ["mp3", "ogg", "wav"]:
			_set_file(f)
			return


func _set_file(path: String) -> void:
	file_path = path
	print("Import: picked ", path)
	file_label.text = path.get_file()
	file_label.add_theme_color_override("font_color", UI.TEXT)
	if title_edit.text.strip_edges() == "" or title_edit.text == _auto_title:
		title_edit.text = path.get_file().get_basename().replace("_", " ")
		_auto_title = title_edit.text
	_validate()


func _open_share_file() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = true
	fd.filters = PackedStringArray(["*.onebeat ; Lights Out, Larry! chart"])
	fd.file_selected.connect(func(p): _use_share(Library.parse_share(FileAccess.get_file_as_string(p))))
	add_child(fd)
	fd.popup_centered_ratio(0.7)


func _use_share(d: Dictionary) -> void:
	Library.share_pending = d
	share_info.visible = not d.is_empty()
	share_link.visible = not d.is_empty() and str(d.get("suno_url", "")) != ""
	if d.is_empty():
		return
	share_info.text = "Chart for \"%s\" by %s (%d custom chart(s)). Now choose the song's audio file." % [d.get("title", "?"), d.get("artist", "?"), (d.get("charts", {}) as Dictionary).size()]
	url_edit.text = str(d.get("suno_url", ""))
	title_edit.text = str(d.get("title", ""))
	artist_edit.text = str(d.get("artist", ""))
	_auto_title = ""
	_validate()


func _validate() -> void:
	var url := url_edit.text.strip_edges()
	var msg := ""
	if url != "" and not Library.is_suno_url(url):
		msg = "That link isn't from suno.com (the link is optional, you can leave it empty)."
	elif file_path == "":
		msg = "Choose the audio file you downloaded from Suno."
	url_hint.add_theme_color_override("font_color", UI.BAD)
	url_hint.text = msg
	analyze_btn.disabled = msg != ""


func _on_analyze() -> void:
	_import_file(file_path)


## When a valid Suno link is pasted, fill in title/artist from the Suno page.
func _on_url_entered() -> void:
	var url := url_edit.text.strip_edges()
	if not Library.is_suno_url(url) or url == _looked_up:
		return
	_looked_up = url
	var info := await _fetch_suno_info(url)
	if info.has("title") and (title_edit.text.strip_edges() == "" or title_edit.text == _auto_title):
		title_edit.text = info.title
	if info.has("artist") and artist_edit.text.strip_edges() == "":
		artist_edit.text = info.artist


func _fetch_failed(text: String) -> void:
	url_hint.add_theme_color_override("font_color", UI.BAD)
	url_hint.text = text
	analyze_btn.disabled = false


func _import_file(path: String) -> void:
	var title := title_edit.text.strip_edges()
	if title == "":
		title = path.get_file().get_basename()
	song = Library.import_audio(path, title, artist_edit.text.strip_edges(), url_edit.text.strip_edges())
	if song.is_empty():
		_fetch_failed("Couldn't copy the audio file.")
		return
	stream = Library.load_stream(song)
	if stream == null:
		_fetch_failed("Couldn't read that audio file. Try the MP3 or WAV download from Suno.")
		Library.delete_song(song)
		song = {}
		return
	step_pick.visible = false
	_start_analysis()


## Loads the Suno song page and pulls out the audio URL, title and artist.
func _fetch_suno_info(url: String) -> Dictionary:
	if not url.begins_with("http"):
		url = "https://" + url
	var req := HTTPRequest.new()
	req.max_redirects = 8
	add_child(req)
	var headers := PackedStringArray(["User-Agent: Mozilla/5.0 (Lights Out Larry rhythm game)"])
	if req.request(url, headers) != OK:
		req.queue_free()
		return {}
	var res: Array = await req.request_completed
	req.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or int(res[1]) >= 400:
		return {}
	var html := (res[3] as PackedByteArray).get_string_from_utf8()
	var info := {}
	var re := RegEx.new()
	re.compile("<meta[^>]+property=\"og:title\"[^>]+content=\"([^\"]*)\"")
	var m := re.search(html)
	if m:
		var t := m.get_string(1).replace("&amp;", "&").replace("&#x27;", "'").replace("&quot;", "\"").replace("&#39;", "'")
		# Suno titles often look like "Song Name by artist | Suno"
		t = t.split(" | ")[0]
		var by := t.rfind(" by ")
		if by > 0:
			info["artist"] = t.substr(by + 4)
			t = t.substr(0, by)
		info["title"] = t.strip_edges()
	return info


# ---------------------------------------------------------------- step 2

func _start_analysis() -> void:
	step_analyze.visible = true
	step_timing.visible = false
	if stream == null:
		status_label.text = "Couldn't load the audio for this song."
		return
	analyzer = SongAnalyzer.new()
	thread = Thread.new()
	thread.start(analyzer.analyze.bind(stream))
	set_process(true)


func _process(delta: float) -> void:
	if thread and thread.is_started():
		progress_bar.value = analyzer.progress
		if not thread.is_alive():
			var result: Dictionary = thread.wait_to_finish()
			thread = null
			_on_analyzed(result)
	if previewing:
		_preview_tick()
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.0)
		beat_flash.queue_redraw()


func _on_analyzed(result: Dictionary) -> void:
	analysis = result
	step_analyze.visible = false
	step_timing.visible = true
	if result.is_empty():
		status_label.text = "Couldn't analyse the song. Set the BPM by hand (tap tempo helps)."
		step_analyze.visible = true
		bpm_spin.value = float(song.get("bpm", 120.0))
		offset_spin.value = float(song.get("offset", 0.0)) * 1000.0
		return
	if is_new and not Library.share_pending.is_empty():
		# use the timing the chart was made with
		bpm_spin.value = float(Library.share_pending.get("bpm", result.bpm))
		offset_spin.value = roundf(float(Library.share_pending.get("offset", result.offset)) * 1000.0)
	elif is_new:
		bpm_spin.value = result.bpm
		offset_spin.value = roundf(float(result.offset) * 1000.0)
	else:
		# keep the player's existing timing when editing
		bpm_spin.value = float(song.get("bpm", result.bpm))
		offset_spin.value = roundf(float(song.get("offset", result.offset)) * 1000.0)
	preview_btn.grab_focus()


# ---------------------------------------------------------------- step 3

func _toggle_preview() -> void:
	previewing = not previewing
	preview_btn.text = "■  Stop preview" if previewing else "▶  Preview with clicks"
	if previewing:
		player.stream = stream
		player.play(maxf(0.0, float(analysis.get("start", 0.0)) - 0.5))
		_last_beat = -999
	else:
		player.stop()


func _preview_tick() -> void:
	if not player.playing:
		return
	var t := player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
	var beat := 60.0 / bpm_spin.value
	var off := offset_spin.value / 1000.0
	var k := int(floor((t - off) / beat))
	if k != _last_beat and k >= 0:
		_last_beat = k
		_flash = 1.0
		_flash_bar = k % 4 == 0
		if _flash_bar:
			click_hi.play()
		else:
			click_lo.play()


func _draw_flash() -> void:
	var c := beat_flash.size * 0.5
	var col := UI.ACCENT2 if _flash_bar else UI.ACCENT
	beat_flash.draw_circle(c, 18.0, Color(col, 0.15 + _flash * 0.85))


func _tap() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not _taps.is_empty() and now - _taps[-1] > 2.0:
		_taps.clear()
	_taps.append(now)
	if _taps.size() > 12:
		_taps.pop_front()
	if _taps.size() >= 4:
		var avg := (_taps[-1] - _taps[0]) / (_taps.size() - 1)
		bpm_spin.value = snappedf(60.0 / avg, 0.5)
	tap_btn.text = "Tap tempo (%d)" % _taps.size()


func _save() -> void:
	player.stop()
	var bpm: float = bpm_spin.value
	var off: float = offset_spin.value / 1000.0
	if analyzer and analyzer.onset.size() > 0:
		var data := analyzer.build(bpm, off)
		for k in data:
			song[k] = data[k]
	else:
		song["bpm"] = bpm
		song["offset"] = off
		song["length"] = stream.get_length() if stream else 0.0
	if not Library.share_pending.is_empty():
		song["charts"] = (Library.share_pending.get("charts", {}) as Dictionary).duplicate(true)
		Library.share_pending = {}
	saved = true
	Library.save_song(song)
	Library.selected_id = song.id
	Library.editing = {}
	get_tree().change_scene_to_file("res://scenes/song_select.tscn")


func _back() -> void:
	player.stop()
	if thread and thread.is_started():
		thread.wait_to_finish()
	if is_new and not saved and not song.is_empty():
		Library.delete_song(song)
	Library.editing = {}
	Library.share_pending = {}
	get_tree().change_scene_to_file("res://scenes/song_select.tscn")


func _exit_tree() -> void:
	if thread and thread.is_started():
		thread.wait_to_finish()
