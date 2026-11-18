extends Control
## Class leaderboard for the selected song + difficulty: this week and all time.

var list: VBoxContainer
var status: Label
var week_btn: Button
var this_week := true
var song: Dictionary


func _ready() -> void:
	UI.setup_root(self)
	song = Library.find(Library.selected_id)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 520)
	center.add_child(panel)
	var v := UI.vbox(12)
	panel.add_child(v)
	var top := UI.hbox()
	v.add_child(top)
	top.add_child(UI.button("‹ Back", func(): get_tree().change_scene_to_file("res://scenes/song_select.tscn")))
	var t := UI.label("Class leaderboard", 32)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	week_btn = UI.button("This week", _toggle_week)
	top.add_child(week_btn)
	v.add_child(UI.label("%s  ·  %s" % [song.get("title", "?"), UI.DIFF_NAMES.get(Library.difficulty, "")], 22, UI.MUTED))
	status = UI.label("", 20, UI.MUTED)
	v.add_child(status)
	list = UI.vbox(6)
	v.add_child(list)
	Leaderboard.top_received.connect(_on_rows)
	_load()


func _toggle_week() -> void:
	this_week = not this_week
	week_btn.text = "This week" if this_week else "All time"
	_load()


func _load() -> void:
	for c in list.get_children():
		c.queue_free()
	if not Leaderboard.enabled():
		status.text = "No class leaderboard set up yet.\nYour teacher can add one in Settings (see tools/leaderboard/README.md)."
		return
	if song.is_empty():
		status.text = "Pick a song first."
		return
	status.text = "Loading… (%s)" % (Leaderboard.week() if this_week else "all time")
	Leaderboard.fetch_top(str(song.id), Library.difficulty, this_week)


func _on_rows(song_id: String, diff: String, rows: Array) -> void:
	if song_id != str(song.get("id", "")) or diff != Library.difficulty:
		return
	for c in list.get_children():
		c.queue_free()
	status.text = "No scores yet. Be the first!" if rows.is_empty() else ("Week " + Leaderboard.week() if this_week else "All time")
	var medals := ["1st", "2nd", "3rd"]
	for i in rows.size():
		var r: Dictionary = rows[i]
		var h := UI.hbox(16)
		var place := UI.label(medals[i] if i < 3 else "%d." % (i + 1), 24, UI.ACCENT3 if i < 3 else UI.MUTED)
		place.custom_minimum_size.x = 50
		h.add_child(place)
		var me: bool = str(r.get("name", "")) == Settings.player_name
		var name_l := UI.label(str(r.get("name", "?")) + ("  (assist)" if r.get("assist", false) else ""), 24, UI.ACCENT if me else UI.TEXT)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(name_l)
		h.add_child(UI.label(("FC  " if r.get("fc", false) else "") + "%.1f%%" % float(r.get("acc", 0)), 20, UI.MUTED))
		var sc := UI.label(UI.format_score(int(r.get("score", 0))), 24)
		sc.custom_minimum_size.x = 140
		sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(sc)
		list.add_child(h)
