extends Control

var list: ItemList
var info_title: Label
var info_meta: Label
var info_best: Label
var suno_link: LinkButton
var diff_buttons: Dictionary = {}
var play_btn: Button
var record_btn: Button
var reset_btn: Button
var edit_btn: Button
var delete_btn: Button
var empty_label: Label
var detail: VBoxContainer
var preview: AudioStreamPlayer
var _preview_id := ""
var practice_box: HBoxContainer
var speed_opt: OptionButton
var start_slider: HSlider
var start_label: Label
var loop_opt: OptionButton


var watch_btn: Button
var share_btn: Button


func _ready() -> void:
	UI.setup_root(self)
	Library.reset_session()
	if Library.has_meta("return_to_editor"):
		Library.remove_meta("return_to_editor")
	preview = AudioStreamPlayer.new()
	preview.bus = "Music"
	preview.volume_db = -6.0
	add_child(preview)

	var root := UI.vbox(18)
	UI.margin(self, 36).add_child(root)

	var top := UI.hbox(12)
	root.add_child(top)
	top.add_child(UI.button("‹ Back", func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn")))
	var title := UI.label("Choose a song", 36)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UI.button("+ Import Suno song", _import))
	top.add_child(UI.button("Learn to play", func():
		Library.start_tutorial()
		get_tree().change_scene_to_file("res://scenes/gameplay.tscn")))
	top.add_child(UI.button("Leaderboard", func(): get_tree().change_scene_to_file("res://scenes/leaderboard_screen.tscn")))
	if OS.get_name() != "Web":
		top.add_child(UI.button("Open songs folder", func(): OS.shell_open(ProjectSettings.globalize_path(Library.USER_DIR))))

	var body := UI.hbox(24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	list = ItemList.new()
	# drag the song list with a finger
	list.gui_input.connect(func(e: InputEvent):
		if e is InputEventScreenDrag:
			list.get_v_scroll_bar().value -= e.relative.y)
	list.custom_minimum_size.x = 420
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_font_size_override("font_size", 22)
	list.item_selected.connect(_on_select)
	list.item_activated.connect(func(_i): _play())
	body.add_child(list)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	detail = UI.vbox(14)
	panel.add_child(detail)
	empty_label = UI.label("No songs yet.\n\nNew here? Press \"Learn to play\" first.\n\nThen make a song on Suno, download it as MP3,\nand press \"+ Import Suno song\".", 24, UI.MUTED)
	panel.add_child(empty_label)

	info_title = UI.label("", 36)
	info_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(info_title)
	info_meta = UI.label("", 20, UI.MUTED)
	detail.add_child(info_meta)
	suno_link = LinkButton.new()
	suno_link.text = "Listen on Suno"
	suno_link.add_theme_color_override("font_color", UI.ACCENT)
	suno_link.pressed.connect(func():
		var s := _selected()
		if not s.is_empty():
			OS.shell_open(str(s.get("suno_url", ""))))
	detail.add_child(suno_link)

	var dh := UI.hbox(10)
	detail.add_child(dh)
	for d in Library.DIFFICULTIES:
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size.x = 132
		b.add_theme_font_size_override("font_size", 17)
		b.add_theme_color_override("font_pressed_color", UI.DIFF_COLORS[d])
		b.pressed.connect(_set_diff.bind(d))
		dh.add_child(b)
		diff_buttons[d] = b

	info_best = UI.label("", 22)
	detail.add_child(info_best)

	var ph := UI.hbox(12)
	detail.add_child(ph)
	play_btn = UI.button("Play", _play, 260)
	play_btn.add_theme_font_size_override("font_size", 30)
	ph.add_child(play_btn)
	ph.add_child(UI.button("Practice", _practice))
	watch_btn = UI.button("Watch best run", _watch)
	ph.add_child(watch_btn)

	# Practice options: speed, where to start, loop a section.
	practice_box = UI.hbox(10)
	detail.add_child(practice_box)
	practice_box.add_child(UI.label("Practice:", 18, UI.MUTED))
	speed_opt = OptionButton.new()
	for sp in ["50%", "75%", "90%", "100%"]:
		speed_opt.add_item(sp)
	speed_opt.selected = 1
	practice_box.add_child(speed_opt)
	start_label = UI.label("from 0:00", 18, UI.MUTED)
	start_label.custom_minimum_size.x = 90
	practice_box.add_child(start_label)
	start_slider = HSlider.new()
	start_slider.custom_minimum_size.x = 160
	start_slider.max_value = 0.95
	start_slider.step = 0.01
	start_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	start_slider.value_changed.connect(func(_v): _update_start_label())
	practice_box.add_child(start_slider)
	loop_opt = OptionButton.new()
	for lp in ["no loop", "loop 4 bars", "loop 8 bars", "loop 16 bars"]:
		loop_opt.add_item(lp)
	practice_box.add_child(loop_opt)

	var tools := UI.hbox(10)
	detail.add_child(tools)
	record_btn = UI.button("Record chart", _record)
	var edit_chart_btn := UI.button("Edit chart", _edit_chart)
	share_btn = UI.button("Share chart", _share)
	reset_btn = UI.button("Use generated chart", _reset_chart)
	edit_btn = UI.button("Edit timing", _edit)
	delete_btn = UI.button("Delete", _delete)
	var tool_buttons: Array = [edit_chart_btn, record_btn, reset_btn, share_btn, edit_btn, delete_btn]
	if OS.has_feature("editor"):
		tool_buttons.append(UI.button("Bundle into game", _bundle))
	for b in tool_buttons:
		b.add_theme_font_size_override("font_size", 18)
		tools.add_child(b)

	detail.add_child(UI.label("Tap on the beat · long notes: hold until the end · SPACE / Z / X / click / gamepad · ESC pause", 18, UI.MUTED))

	_populate()


func _populate() -> void:
	list.clear()
	var sel := 0
	for i in Library.songs.size():
		var s: Dictionary = Library.songs[i]
		list.add_item(str(s.get("title", "?")))
		if s.id == Library.selected_id:
			sel = i
	var has := Library.songs.size() > 0
	detail.visible = has
	empty_label.visible = not has
	if has:
		list.select(sel)
		_on_select(sel)
		list.grab_focus()


func _selected() -> Dictionary:
	var items := list.get_selected_items()
	if items.is_empty():
		return {}
	return Library.songs[items[0]]


func _on_select(i: int) -> void:
	var s: Dictionary = Library.songs[i]
	Library.selected_id = s.id
	Library.remember_selection()
	_update_start_label()
	info_title.text = str(s.get("title", "?"))
	var mins := int(float(s.get("length", 0)) / 60.0)
	var secs := int(float(s.get("length", 0))) % 60
	info_meta.text = "%s   ·   %s BPM   ·   %d:%02d" % [s.get("artist", ""), str(s.get("bpm", "?")), mins, secs]
	suno_link.visible = str(s.get("suno_url", "")) != ""
	edit_btn.disabled = s.get("_builtin", false)
	delete_btn.disabled = s.get("_builtin", false)
	_refresh_diffs()
	_start_preview(s)


func _refresh_diffs() -> void:
	var s := _selected()
	if s.is_empty():
		return
	for d in Library.DIFFICULTIES:
		var b: Button = diff_buttons[d]
		var n := Library.chart_counts(s, d)
		var tag := " ✎" if Library.has_custom_chart(s, d) else ""
		b.text = "%s%s  Lv %d\n%d notes · %d holds" % [UI.DIFF_NAMES[d], tag, Library.chart_level(s, d), n.x, n.y]
		b.button_pressed = d == Library.difficulty
	var best := Library.get_best(s.id, Library.difficulty)
	if best.is_empty():
		info_best.text = "Best: —"
	else:
		info_best.text = "Best: %s   %s   %.2f%%   max combo %d%s" % [best.grade, UI.format_score(int(best.score)), float(best.accuracy) * 100.0, int(best.max_combo), "   ★ FC" if best.get("fc", false) else ""]
	reset_btn.disabled = not Library.has_custom_chart(s, Library.difficulty) or s.get("_builtin", false)
	record_btn.disabled = s.get("_builtin", false)
	play_btn.disabled = Library.chart_counts(s, Library.difficulty).x == 0
	watch_btn.disabled = not Library.has_replay(str(s.id), Library.difficulty)


func _set_diff(d: String) -> void:
	Library.difficulty = d
	Library.remember_selection()
	_refresh_diffs()


func _start_preview(s: Dictionary) -> void:
	if _preview_id == s.id:
		return
	_preview_id = s.id
	var stream := Library.load_stream(s)
	if stream == null:
		preview.stop()
		return
	preview.stream = stream
	preview.play(Library.preview_start(s))


func _unhandled_input(event: InputEvent) -> void:
	if Library.songs.is_empty():
		return
	var idx := Library.DIFFICULTIES.find(Library.difficulty)
	if event.is_action_pressed("ui_left"):
		_set_diff(Library.DIFFICULTIES[maxi(0, idx - 1)])
	elif event.is_action_pressed("ui_right"):
		_set_diff(Library.DIFFICULTIES[mini(Library.DIFFICULTIES.size() - 1, idx + 1)])


func _play() -> void:
	var s := _selected()
	if s.is_empty() or Library.chart_counts(s, Library.difficulty).x == 0:
		return
	Library.current = s
	Library.mode = "play"
	get_tree().change_scene_to_file("res://scenes/gameplay.tscn")


func _watch() -> void:
	var s := _selected()
	if s.is_empty():
		return
	var rp := Library.load_replay(str(s.id), Library.difficulty)
	if rp.is_empty():
		return
	Library.current = s
	Library.mode = "play"
	Library.replay = rp
	get_tree().change_scene_to_file("res://scenes/gameplay.tscn")


func _edit_chart() -> void:
	var s := _selected()
	if s.is_empty() or s.get("_builtin", false):
		return
	preview.stop()
	Library.current = s
	get_tree().change_scene_to_file("res://scenes/chart_editor.tscn")


## Share: a code to paste in chat (classmates import it) or a .onebeat file. The audio is never included.
func _share() -> void:
	var s := _selected()
	if s.is_empty():
		return
	var code := Library.share_code(s)
	DisplayServer.clipboard_set(code)
	var dlg := AcceptDialog.new()
	dlg.title = "Share chart"
	var custom := (s.get("charts", {}) as Dictionary).size()
	dlg.dialog_text = "Share code copied to the clipboard! Paste it in your class chat.\n\nClassmates open Import → \"Got a chart from a friend?\", paste the code,\nand download the song from Suno themselves:\n%s\n\nIt includes the timing and your %d custom chart(s); other difficulties get generated." % [s.get("suno_url", "(no Suno link)"), custom]
	if OS.get_name() != "Web":
		dlg.add_button("Also save as file…", true, "file")
		dlg.custom_action.connect(func(action):
			if action == "file":
				dlg.hide()
				var fd := FileDialog.new()
				fd.file_mode = FileDialog.FILE_MODE_SAVE_FILE
				fd.access = FileDialog.ACCESS_FILESYSTEM
				fd.use_native_dialog = true
				fd.filters = PackedStringArray(["*.onebeat ; Lights Out, Larry! chart"])
				fd.current_file = "%s.onebeat" % s.id
				fd.file_selected.connect(func(p): Library.export_share_file(s, p))
				add_child(fd)
				fd.popup_centered_ratio(0.7))
	add_child(dlg)
	dlg.popup_centered()


func _practice() -> void:
	var s := _selected()
	if s.is_empty() or Library.chart_counts(s, Library.difficulty).x == 0:
		return
	Library.current = s
	Library.mode = "play"
	Library.practice = {
		"speed": [0.5, 0.75, 0.9, 1.0][speed_opt.selected],
		"start": _start_time(s),
		"loop_bars": [0, 4, 8, 16][loop_opt.selected],
	}
	get_tree().change_scene_to_file("res://scenes/gameplay.tscn")


## Practice start time, snapped to a bar line.
func _start_time(s: Dictionary) -> float:
	var length := float(s.get("length", 60.0))
	var bar := 60.0 / float(s.get("bpm", 120.0)) * 4.0
	var off := float(s.get("offset", 0.0))
	var t := start_slider.value * length
	if t <= 0.01:
		return 0.0
	return off + floorf((t - off) / bar) * bar


func _update_start_label() -> void:
	var s := _selected()
	if s.is_empty() or start_label == null:
		return
	var t := _start_time(s)
	start_label.text = "from %d:%02d" % [int(t) / 60, int(t) % 60]


func _bundle() -> void:
	var s := _selected()
	if s.is_empty():
		return
	var ok := Library.bundle_song(s)
	var dlg := AcceptDialog.new()
	dlg.dialog_text = ("Copied to res://songs/%s. It will be included when you export the game (also the web build)." % s.id) if ok else "Couldn't copy the song (only works when running from the Godot editor)."
	add_child(dlg)
	dlg.popup_centered()


func _record() -> void:
	var s := _selected()
	if s.is_empty():
		return
	Library.current = s
	Library.mode = "record"
	get_tree().change_scene_to_file("res://scenes/gameplay.tscn")


func _reset_chart() -> void:
	var s := _selected()
	if s.is_empty():
		return
	var charts: Dictionary = s.get("charts", {})
	charts.erase(Library.difficulty)
	s["charts"] = charts
	Library.save_song(s)
	_populate()


func _edit() -> void:
	var s := _selected()
	if s.is_empty():
		return
	Library.editing = s
	get_tree().change_scene_to_file("res://scenes/import_song.tscn")


func _delete() -> void:
	var s := _selected()
	if s.is_empty():
		return
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Delete \"%s\" from your library?" % s.title
	dlg.confirmed.connect(func():
		preview.stop()
		_preview_id = ""
		Library.delete_song(s)
		_populate())
	add_child(dlg)
	dlg.popup_centered()


func _import() -> void:
	Library.editing = {}
	get_tree().change_scene_to_file("res://scenes/import_song.tscn")
