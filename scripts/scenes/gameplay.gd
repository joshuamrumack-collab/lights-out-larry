extends Control
## The game itself. Notes slide toward the target ring.
## Tap notes: press when they reach the ring. Hold notes: press at the start, hold to the end.
## Also handles record mode, practice mode (slow / loop), daily challenge modifiers,
## assist options and eye tracker mode (fewer notes that wait at the ring, look-to-hit).

const WINDOWS := {"perfect": 0.045, "great": 0.090, "good": 0.135}
const RELEASE_WINDOW := 0.15
const WEIGHT := {"perfect": 1.0, "great": 0.7, "good": 0.4, "miss": 0.0}
const POINTS := {"perfect": 300, "great": 200, "good": 100, "miss": 0}
const HEALTH := {"perfect": 0.02, "great": 0.015, "good": 0.0, "miss": -0.09}
const JUDGE_COLORS := {
	"perfect": Color(0.4, 0.95, 1.0), "great": Color(0.45, 1.0, 0.55),
	"good": Color(1.0, 0.85, 0.3), "miss": Color(1.0, 0.3, 0.35),
}
const APPROACH := {"easy": 1.8, "normal": 1.5, "hard": 1.2, "expert": 1.0, "twist": 1.4}
const WINDOW_SCALE := {"easy": 1.25, "normal": 1.1, "hard": 1.0, "expert": 1.0, "twist": 1.1}
const TIERS := [0, 10, 30, 60]
const FEVER_COMBO := 50
const PARTICLE_COUNT := {"perfect": 16, "great": 10, "good": 6, "miss": 0}
const MILESTONES := [25, 50, 100, 150, 200, 300, 400, 500, 750, 1000]

enum { PENDING, DONE, MISSED, HOLDING, DROPPED }

var song: Dictionary
var diff: String
var record := false
var practice := false
var speed := 1.0
var loop_on := false
var loop_end := 0.0
var play_from := 0.0
var loops := 1
var mod := ""
var eye := false
var th: Dictionary
var tutorial := false
var watching := false     # replaying a saved run
var holds_taps := false
var wide_windows := false

# chart events (twists): speed changes, mirror, fade, text
var events: Array = []
var ev_idx := 0
var speed_target := 1.0
var speed_cur := 1.0
var side_target := 0.0     # 0 = ring on the left, 1 = mirrored (ring on the right)
var side_cur := 0.0
var fade_on := false

# replay
var rec_press_times := PackedFloat64Array()
var rec_release_times := PackedFloat64Array()
var last_held := false
var rp_events: Array = []
var rp_i := 0
var rp_held := false

var notes := PackedFloat64Array()
var lanes := PackedInt32Array()   # two-switch mode: 0 = top (up), 1 = bottom (down)
var dual := false
var hold_lane := 0
var touch_lane := {}               # touch index -> lane
var touches_l := [0, 0]
var last_held_l := [false, false]
var rp_held_l := [false, false]
var rec_press_lanes := PackedInt32Array()
var rec_release_lanes := PackedInt32Array()
var larry_start := -100.0          # "Larry interrupts" (Chaos): he blocks the view, play by ear
var larry_end := -100.0
var larry_tex: Texture2D
var larry_line := ""
const LARRY_LINES := ["Hehe! Can't see?", "Guess where the notes are!", "Bet you can't play blind!", "Peekaboo!", "Use your ears, nerd!"]
var durs := PackedFloat64Array()
var states := PackedInt32Array()
var next_idx := 0
var draw_idx := 0
var holding_idx := -1
var next_tick := 0.0

var player: AudioStreamPlayer
const GAMEOVER_DB := -9.0   # how much quieter the song gets on game over
var sfx: AudioStreamPlayer
var fx_player: AudioStreamPlayer
var tick_player: AudioStreamPlayer
var started := false
var song_time := -2.0
var length := 0.0
var approach := 1.5
var win_scale := 1.0
var wait_time := 0.0
var bpm := 120.0
var beat_len := 0.5
var offset := 0.0
var energy: Array = []
var note_r := 26.0
var room_layer: Control
var _room_rect := Rect2()

var paused := false
var touches_down := 0
var touch_ui := DisplayServer.is_touchscreen_available()
var finished := false
var score := 0
var shown_score := 0.0
var combo := 0
var max_combo := 0
var perfect_streak := 0
var counts := {"perfect": 0, "great": 0, "good": 0, "miss": 0}
var health := 1.0
var acc_sum := 0.0
var judged := 0
var total_judgements := 0
var early_late := {"early": 0, "late": 0}
var misclicks := 0
var last_hit_rt := -10.0
var deltas: Array = []

# effects (rt = real time)
var rt := 0.0
var particles: Array = []
var popups: Array = []
var rings: Array = []
var shake := 0.0
var flash := 0.0
var flash_color := Color.WHITE
var combo_pop := 0.0
var fever_k := 0.0
var level_k := 0.0
var banner_text := ""
var banner_color := Color.WHITE
var banner_at := -10.0
var banner_dur := 1.2
var info_text := ""       # text events (tutorial lessons, twist warnings)
var info_at := -10.0
var broken_combo := 0
var broken_at := -10.0
var judge_text := ""
var judge_sub := ""
var judge_color := Color.WHITE
var judge_at := -10.0
var tap_at := -10.0
var tap_lane := 0
var stars: Array = []
var last_beat := -99999

# eye tracker look-to-hit
var gaze_time := 0.0
var gaze_armed := true

# record mode
var rec_t := PackedFloat64Array()
var rec_d := PackedFloat64Array()
var rec_press := -1.0
var keys_down := 0

var pause_panel: PanelContainer
var font: Font
var room: PixelRoom


func _ready() -> void:
	UI.setup_root(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	if Settings.background == "room":
		var rtheme := Settings.room_theme
		if not rtheme in PixelRoom.THEMES:
			rtheme = "gamer" if Library.is_tutorial else PixelRoom.theme_for_song(str(Library.current.get("id", "")))
		room = PixelRoom.new(rtheme)
		# the picture gets its own layer so only it uses the pixel-art filter (text stays smooth)
		room_layer = Control.new()
		room_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		room_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		room_layer.show_behind_parent = true
		room_layer.texture_filter = Settings.art_filter()
		room_layer.draw.connect(func(): room.draw(room_layer, _room_rect, not Settings.effects))
		add_child(room_layer)
	th = Progress.theme()
	song = Library.current
	diff = Library.difficulty
	record = Library.mode == "record"
	practice = not Library.practice.is_empty() and not record
	mod = Library.modifier
	tutorial = Library.is_tutorial
	watching = not Library.replay.is_empty() and not record
	eye = Settings.eye_mode and not record
	dual = Settings.dual_for(diff) and not record and not tutorial
	holds_taps = Settings.holds_as_taps
	wide_windows = Settings.assist_timing
	if watching:
		# play back with the settings the run was played with
		eye = bool(Library.replay.get("eye", false))
		holds_taps = bool(Library.replay.get("holds_as_taps", false))
		wide_windows = bool(Library.replay.get("assist_timing", false))
		mod = str(Library.replay.get("mod", ""))
		dual = bool(Library.replay.get("dual", false))
		var presses: Array = Library.replay.get("presses", [])
		var releases: Array = Library.replay.get("releases", [])
		var pl: Array = Library.replay.get("press_lanes", [])
		var rl: Array = Library.replay.get("release_lanes", [])
		for k in presses.size():
			rp_events.append([float(presses[k]), 1, int(pl[k]) if k < pl.size() else -1])
		for k in releases.size():
			rp_events.append([float(releases[k]), 0, int(rl[k]) if k < rl.size() else -1])
		rp_events.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var stream := Library.load_stream(song)
	if stream == null:
		push_error("Could not load audio for " + str(song.get("title", "?")))
		get_tree().change_scene_to_file.call_deferred("res://scenes/song_select.tscn")
		return
	length = stream.get_length()
	bpm = float(song.get("bpm", 120.0))
	beat_len = 60.0 / bpm
	offset = float(song.get("offset", 0.0))
	energy = song.get("energy", [])

	if not record:
		var chart := Library.get_chart(song, diff, length)
		notes = chart.t.duplicate()
		durs = chart.d.duplicate()
		lanes = (chart.get("l", PackedInt32Array()) as PackedInt32Array).duplicate()
		if lanes.size() != notes.size():
			lanes = ChartGen.assign_lanes(song, notes)
		events = chart.get("ev", []).duplicate(true)
		if eye:
			events = events.filter(func(e): return str(e.type) != "larry")
	larry_tex = load("res://art/sprites/bro_laugh.png")
	if eye:
		_thin_for_eye_tracker()
	if holds_taps or eye:
		durs.fill(0.0)
	if mod == "mirror":
		side_target = 1.0
		side_cur = 1.0
	if mod == "fade":
		fade_on = true

	# Practice: start point, loop section, speed.
	if practice:
		speed = clampf(float(Library.practice.get("speed", 1.0)), 0.5, 1.0)
		var start := float(Library.practice.get("start", 0.0))
		var loop_bars := int(Library.practice.get("loop_bars", 0))
		loop_on = loop_bars > 0
		loop_end = start + loop_bars * 4.0 * beat_len if loop_on else INF
		_filter_notes(start - 0.01, loop_end)
		play_from = maxf(0.0, start - 2.0 * 4.0 * beat_len)

	states.resize(notes.size())
	states.fill(PENDING)
	_count_judgements()

	approach = APPROACH.get(diff, 1.5) / maxf(0.25, Settings.scroll_speed)
	if mod == "fast":
		approach *= 0.6
	if eye:
		approach = maxf(approach, 2.2)
	win_scale = WINDOW_SCALE.get(diff, 1.0)
	if wide_windows or eye:
		win_scale *= 1.6
	wait_time = Settings.eye_wait if eye else 0.0
	note_r = 26.0 * (1.35 if Settings.big_notes or eye else 1.0)

	var first := notes[0] if notes.size() > 0 else play_from + 3.0
	if play_from > 0.0:
		song_time = play_from
	else:
		song_time = -maxf(2.0, approach + 1.0 - first)

	player = AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "Music"
	add_child(player)
	Settings.set_music_speed(player, speed)
	player.finished.connect(_on_song_end)
	sfx = _make_player(8)
	fx_player = _make_player(4)
	tick_player = _make_player(2)
	tick_player.stream = Sfx.hit("soft")
	tick_player.volume_db = -8.0
	for i in 60:
		stars.append(Vector3(randf(), randf(), randf_range(0.4, 1.0)))
	_build_pause_menu()
	_apply_events_until(play_from if play_from > 0.0 else song_time, true)
	if play_from > 0.0:
		started = true
		player.play(play_from)


func _exit_tree() -> void:
	if player:
		Settings.set_music_speed(player, 1.0)


func _make_player(poly: int) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "SFX"
	p.max_polyphony = poly
	add_child(p)
	return p


func _count_judgements() -> void:
	total_judgements = notes.size()
	for d in durs:
		if d > 0.0:
			total_judgements += 1


func _filter_notes(from_t: float, to_t: float) -> void:
	var t := PackedFloat64Array()
	var d := PackedFloat64Array()
	var l := PackedInt32Array()
	for i in notes.size():
		if notes[i] >= from_t and notes[i] < to_t:
			t.append(notes[i])
			d.append(minf(durs[i], maxf(0.0, to_t - notes[i] - beat_len)))
			l.append(lanes[i] if i < lanes.size() else 0)
	notes = t
	durs = d
	lanes = l


## Eye tracker mode: keep notes at least Settings.eye_gap seconds apart, preferring strong beats.
func _thin_for_eye_tracker() -> void:
	var t := PackedFloat64Array()
	var d := PackedFloat64Array()
	var last := -INF
	var gap := maxf(Settings.eye_gap, Settings.eye_wait + 0.5)
	var l := PackedInt32Array()
	for i in notes.size():
		if notes[i] - last >= gap:
			t.append(notes[i])
			d.append(0.0)
			l.append(lanes[i] if i < lanes.size() else 0)
			last = notes[i]
	notes = t
	durs = d
	lanes = l


# ---------------------------------------------------------------- timing

func audio_time() -> float:
	if not started:
		return song_time
	return player.get_playback_position() + (AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()) * speed


func game_time() -> float:
	return song_time - Settings.offset_sec()


func multiplier() -> int:
	var m := 1
	for i in TIERS.size():
		if combo >= TIERS[i]:
			m = i + 1
	return m


func _process(delta: float) -> void:
	if paused or player == null:
		return
	rt += delta
	_update_effects(delta)
	if room:
		room.disco = fever_k
		room.update(delta, not Settings.effects)
	if finished:
		queue_redraw()
		return
	if not started:
		song_time += delta * speed
		if song_time >= 0.0:
			started = true
			player.play(song_time)
	else:
		var t := audio_time()
		if t > song_time:
			song_time = t
		if song_time > length + 1.0:
			_on_song_end()
			return

	var gt := game_time()
	_countdown_tick(gt)
	_apply_events_until(gt, false)
	speed_cur = move_toward(speed_cur, speed_target, delta * 2.0)
	side_cur = move_toward(side_cur, side_target, delta * 1.6)
	if record:
		_record_tick(gt)
		queue_redraw()
		return

	if loop_on and gt >= loop_end + 0.4:
		_restart_loop()
		return

	if watching:
		_replay_tick(gt)
	elif Library.autoplay:
		while next_idx < notes.size() and states[next_idx] == PENDING and gt >= notes[next_idx]:
			_on_hit(notes[next_idx], lanes[next_idx] if dual else -1)
	elif dual:
		for ln in 2:
			var h := _button_held(ln)
			if last_held_l[ln] and not h:
				rec_release_times.append(snappedf(gt, 0.0001))
				rec_release_lanes.append(ln)
			last_held_l[ln] = h
	else:
		var held := _button_held()
		if last_held and not held:
			rec_release_times.append(snappedf(gt, 0.0001))
		last_held = held
	if eye and Settings.eye_hover:
		_gaze_tick(delta, gt)
	_hold_tick(gt)
	var late_limit: float = maxf(WINDOWS.good * win_scale, wait_time)
	while next_idx < notes.size() and (states[next_idx] != PENDING or gt - notes[next_idx] > late_limit):
		if states[next_idx] == PENDING:
			_judge(next_idx, "miss", 0.0)
			if durs[next_idx] > 0.0:
				_judge_tail(next_idx, false, true)
			states[next_idx] = MISSED
		next_idx += 1
	queue_redraw()


func _restart_loop() -> void:
	loops += 1
	player.seek(play_from)
	song_time = play_from
	states.fill(PENDING)
	next_idx = 0
	draw_idx = 0
	holding_idx = -1
	ev_idx = 0
	_apply_events_until(play_from, true)
	_banner("Loop %d" % loops, th.a)


func _on_song_end() -> void:
	if loop_on and not finished:
		_restart_loop()
		return
	_finish(false)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F2:
		Library.autoplay = not Library.autoplay
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R and not Settings.any_key:
		get_tree().reload_current_scene()  # instant restart
		return
	# touch: the pause button in the corner, then every finger counts as a hit
	if event is InputEventScreenTouch and event.pressed and _pause_rect().has_point(event.position) and touch_ui:
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if paused or finished or watching:
		return
	if event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION:
		return   # the mouse click a browser/phone fakes from a touch; the touch itself is handled below
	var pressed := false
	var lane := -1
	if dual:
		# two light switches: top / bottom (touch: top or bottom half of the screen)
		if event is InputEventScreenTouch:
			if event.pressed:
				lane = 0 if event.position.y < _target_pos(size).y else 1
				touch_lane[event.index] = lane
				touches_l[lane] += 1
				pressed = true
			elif touch_lane.has(event.index):
				var ln: int = touch_lane[event.index]
				touch_lane.erase(event.index)
				touches_l[ln] = maxi(0, touches_l[ln] - 1)
		elif event.is_action_pressed("hit_up", false, true) and not event.is_echo():
			lane = 0
			pressed = true
		elif event.is_action_pressed("hit_down", false, true) and not event.is_echo():
			lane = 1
			pressed = true
	elif event is InputEventScreenTouch:
		if event.pressed:
			touches_down += 1
			pressed = true
		else:
			touches_down = maxi(0, touches_down - 1)
	elif Settings.any_key:
		if (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton or event is InputEventScreenTouch) and not event.is_echo():
			if event.is_pressed():
				keys_down += 1
				pressed = true
			else:
				keys_down = maxi(0, keys_down - 1)
	elif event.is_action_pressed("hit", false, true) and not event.is_echo():
		pressed = true
	if pressed:
		var t := audio_time() - Settings.offset_sec()
		if not record and not Library.autoplay:
			rec_press_times.append(snappedf(t, 0.0001))
			if dual:
				rec_press_lanes.append(lane)
		_on_hit(t, lane)


func _button_held(lane: int = -1) -> bool:
	if dual and lane >= 0:
		if watching:
			return rp_held_l[lane]
		return touches_l[lane] > 0 or Input.is_action_pressed("hit_up" if lane == 0 else "hit_down")
	if watching:
		return rp_held
	if touches_down > 0:
		return true
	if Settings.any_key:
		return keys_down > 0
	return Input.is_action_pressed("hit")


## On-screen pause button for phones and tablets (bottom-left corner).
func _pause_rect() -> Rect2:
	return Rect2(18, size.y - 96, 78, 78)


func _on_hit(t: float, lane: int = -1) -> void:
	tap_at = game_time()
	if dual and lane >= 0:
		tap_lane = lane
	if record:
		if started:
			rec_press = t
			_play_hit_sound()
			if room:
				room.flip()
		return
	var i := next_idx
	if dual and lane >= 0:
		# the first note still waiting on this switch
		while i < notes.size() and (states[i] != PENDING or lanes[i] != lane):
			if notes[i] - t > WINDOWS.good * win_scale:
				i = notes.size()
				break
			i += 1
	else:
		while i < notes.size() and states[i] != PENDING:
			i += 1
	if i >= notes.size():
		_misclick()
		return
	var d := t - notes[i]
	var ad := absf(d)
	var late_ok := wait_time > 0.0 and d > 0.0 and d <= wait_time + 0.05
	if ad > WINDOWS.good * win_scale and not late_ok:
		_misclick()
		return
	var grade := "good"
	if ad <= WINDOWS.perfect * win_scale:
		grade = "perfect"
	elif ad <= WINDOWS.great * win_scale:
		grade = "great"
	if eye and d > 0.0:
		# Eye tracker mode: reacting while the note waits is the skill, graded on the wait time.
		if d <= maxf(WINDOWS.perfect * win_scale, wait_time * 0.35):
			grade = "perfect"
		elif d <= wait_time * 0.7:
			grade = "great"
	_judge(i, grade, d)
	if durs[i] > 0.0:
		states[i] = HOLDING
		holding_idx = i
		hold_lane = lanes[i] if dual else 0
		next_tick = notes[i] + beat_len / 4.0
	else:
		states[i] = DONE


## Eye tracker: looking at the ring (the pointer over it) for eye_dwell seconds hits the note.
## You have to look away between notes, so it's still about timing.
func _gaze_tick(delta: float, gt: float) -> void:
	var sz := size
	var target := _target_pos(sz)
	var inside := get_local_mouse_position().distance_to(target) < note_r * 3.2
	if not inside:
		gaze_armed = true
		gaze_time = 0.0
		return
	var i := next_idx
	while i < notes.size() and states[i] != PENDING:
		i += 1
	var hittable := i < notes.size() and gt >= notes[i] - WINDOWS.good * win_scale
	if not gaze_armed or not hittable:
		gaze_time = 0.0
		return
	gaze_time += delta
	if gaze_time >= Settings.eye_dwell:
		gaze_time = 0.0
		gaze_armed = false
		_on_hit(gt)


## Pressing when there's no note: breaks your streak. Not in eye tracker mode, not before the
## first note, and not for a double-press right after a hit (key bounce / two keys at once).
func _misclick() -> void:
	if eye or not started or judged == 0 or rt - last_hit_rt < 0.12 or holding_idx >= 0:
		return
	misclicks += 1
	health = clampf(health - 0.04, 0.0, 1.0)
	perfect_streak = 0
	_break_combo()
	_show_judgement("MISCLICK", "no note there", JUDGE_COLORS.miss)
	if room:
		room.taunt()
	_check_fail(false)


func _hold_tick(gt: float) -> void:
	if holding_idx < 0:
		return
	var i := holding_idx
	var end_t := notes[i] + durs[i]
	while next_tick <= minf(gt, end_t):
		score += 10 * multiplier()
		next_tick += beat_len / 4.0
	if randf() < 0.7:
		_spawn_particles(1, _hold_color(i), 160.0, true)
	if gt >= end_t:
		_judge_tail(i, true)
	elif (watching or not Library.autoplay) and not _button_held(hold_lane if dual else -1):
		_judge_tail(i, end_t - gt <= RELEASE_WINDOW * win_scale)


func _judge_tail(i: int, ok: bool, silent: bool = false) -> void:
	if holding_idx == i:
		holding_idx = -1
	judged += 1
	if ok:
		states[i] = DONE
		acc_sum += 1.0
		counts.perfect += 1
		_add_combo()
		score += 300 * multiplier()
		_play_hit_sound()
		_spawn_particles(18, _hold_color(i), 420.0)
		rings.append({"t": rt, "color": _hold_color(i), "big": true, "y": _lane_dy(lanes[i] if dual else 0)})
		_popup("+%d" % (300 * multiplier()), _hold_color(i))
		_show_judgement("HOLD!", "", JUDGE_COLORS.perfect)
	else:
		states[i] = DROPPED if not silent else MISSED
		counts.miss += 1
		health = clampf(health + HEALTH.miss, 0.0, 1.0)
		if not silent:
			_break_combo()
			_show_judgement("DROPPED", "hold until the end", JUDGE_COLORS.miss)
		_check_fail(true)


func _judge(i: int, grade: String, d: float) -> void:
	counts[grade] += 1
	judged += 1
	acc_sum += WEIGHT[grade]
	health = clampf(health + HEALTH[grade], 0.0, 1.0)
	if grade != "miss":
		last_hit_rt = rt
		deltas.append({"d": d, "t": rt, "c": JUDGE_COLORS[grade]})
		if deltas.size() > 30:
			deltas.pop_front()
	if room:
		if grade == "miss":
			room.taunt()
		else:
			room.flip()
	if grade == "miss":
		_break_combo()
		perfect_streak = 0
	else:
		_add_combo()
		perfect_streak = perfect_streak + 1 if grade == "perfect" else 0
		var pts: int = POINTS[grade] * multiplier()
		score += pts
		_play_hit_sound()
		var col: Color = JUDGE_COLORS[grade]
		_spawn_particles(int(PARTICLE_COUNT[grade] * (1.0 + level_k * 0.5)), col, 380.0 if grade == "perfect" else 280.0)
		rings.append({"t": rt, "color": col, "big": grade == "perfect", "y": _lane_dy(lanes[i] if dual else 0)})
		_popup("+%d" % pts, col)
	var sub := ""
	if grade == "great" or grade == "good":
		sub = "early" if d < 0.0 else "late"
		early_late[sub] += 1
	elif grade == "perfect" and perfect_streak >= 5:
		sub = "perfect ×%d" % perfect_streak
	_show_judgement(grade.to_upper(), sub, JUDGE_COLORS[grade])
	_check_fail(grade == "miss")


func _add_combo() -> void:
	var old_mult := multiplier()
	combo += 1
	max_combo = maxi(max_combo, combo)
	combo_pop = 1.0
	if multiplier() > old_mult:
		_banner("×%d MULTIPLIER" % multiplier(), th.c)
		_fx(Sfx.tier_up())
		_kick(6.0, 0.25, th.c)
	if combo in MILESTONES:
		var sz := clampi(MILESTONES.find(combo) / 2, 0, 3)
		_banner("%d COMBO!" % combo, th.b if combo >= FEVER_COMBO else th.a)
		_fx(Sfx.milestone(sz))
		_kick(10.0 + sz * 4.0, 0.35, Color.WHITE)
		_spawn_particles(40, th.b, 600.0)
		if combo == FEVER_COMBO:
			_banner("FEVER!", th.b)


func _break_combo() -> void:
	if combo >= 10:
		broken_combo = combo
		broken_at = rt
		_fx(Sfx.combo_break())
		_kick(8.0, 0.3, UI.BAD)
	combo = 0


func _check_fail(was_miss: bool) -> void:
	if practice or eye:
		return
	if mod == "sudden" and was_miss:
		_finish(true)
	elif health <= 0.0 and not Settings.no_fail:
		_finish(true)


func _show_judgement(text: String, sub: String, col: Color) -> void:
	judge_text = text
	judge_sub = sub
	judge_color = col
	judge_at = rt


func _play_hit_sound() -> void:
	var w := Sfx.hit(Settings.hit_sound, posmod(combo - 1, 8))
	if w:
		sfx.stream = w
		sfx.play()


func _fx(w: AudioStreamWAV) -> void:
	fx_player.stream = w
	fx_player.play()


func accuracy() -> float:
	return acc_sum / judged if judged > 0 else 1.0


func _replay_tick(gt: float) -> void:
	while rp_i < rp_events.size() and rp_events[rp_i][0] <= gt:
		var e: Array = rp_events[rp_i]
		rp_i += 1
		var ln: int = e[2] if e.size() > 2 else -1
		if e[1] == 1:
			rp_held = true
			if ln >= 0:
				rp_held_l[ln] = true
			_on_hit(e[0], ln)
		else:
			rp_held = false
			if ln >= 0:
				rp_held_l[ln] = false
			_hold_tick(gt)


## Applies chart events (twists) up to time t. instant = jump straight to the state (no animation/banner).
func _apply_events_until(t: float, instant: bool) -> void:
	while ev_idx < events.size() and float(events[ev_idx].t) <= t:
		var ev: Dictionary = events[ev_idx]
		ev_idx += 1
		match str(ev.type):
			"speed":
				speed_target = clampf(float(ev.v), 0.4, 2.5)
			"mirror":
				side_target = 1.0 if bool(ev.v) else 0.0
			"fade":
				fade_on = bool(ev.v)
			"text":
				if not instant:
					info_text = str(ev.v)
					info_at = rt
			"larry":
				larry_start = float(ev.t)
				larry_end = larry_start + float(ev.v) * 4.0 * beat_len
				larry_line = LARRY_LINES[randi() % LARRY_LINES.size()]
				if not instant:
					info_text = "Larry's in the way! Keep the beat by ear"
					info_at = rt
					if room:
						room.taunt()
		if not instant and str(ev.type) != "text":
			_kick(4.0, 0.2, th.a)
	if instant:
		speed_cur = speed_target
		side_cur = side_target


## Soft ticks on the 4 beats before the first note, so you feel the tempo before you play.
func _countdown_tick(gt: float) -> void:
	var k := int(floor((gt - offset) / beat_len))
	if k == last_beat:
		return
	last_beat = k
	if notes.is_empty() or judged > 0:
		return
	var to_first := (notes[0] - (offset + k * beat_len)) / beat_len
	if to_first > 0.5 and to_first <= 4.5:
		tick_player.play()
		rings.append({"t": rt, "color": th.ring, "big": false})


func _finish(failed: bool) -> void:
	if finished:
		return
	if holding_idx >= 0:
		_judge_tail(holding_idx, true)
	finished = true
	if failed and player.playing:
		# the song keeps going, quieter, under the game-over screen
		create_tween().tween_property(player, "volume_db", player.volume_db + GAMEOVER_DB, 0.6)
	var acc := accuracy()
	var full_combo: bool = not record and not failed and counts.miss == 0 and misclicks == 0 and judged > 0
	var all_perfect: bool = full_combo and counts.great == 0 and counts.good == 0
	Library.last_result = {
		"record": record,
		"recorded": {"t": rec_t, "d": rec_d},
		"failed": failed,
		"score": score,
		"accuracy": acc,
		"max_combo": max_combo,
		"counts": counts.duplicate(),
		"notes": total_judgements,
		"early_late": early_late.duplicate(),
		"misclicks": misclicks,
		"grade": UI.grade_for(acc, failed),
		"full_combo": full_combo,
		"all_perfect": all_perfect,
		"practice": practice,
		"autoplay": Library.autoplay,
		"assist": Settings.assist_on(),
		"eye": eye,
		"dual": dual,
		"mod": mod,
		"daily": Library.is_daily,
		"tutorial": tutorial,
		"watching": watching,
		"replay": {
			"presses": Array(rec_press_times), "releases": Array(rec_release_times),
			"dual": dual, "press_lanes": Array(rec_press_lanes), "release_lanes": Array(rec_release_lanes),
			"eye": eye, "holds_as_taps": holds_taps, "assist_timing": wide_windows, "mod": mod,
			"notes": notes.size(), "score": score,
		},
	}
	var wait := 0.6
	if failed:
		wait = 1.4
	elif full_combo and not practice:
		_banner("ALL PERFECT!" if all_perfect else "FULL COMBO!", th.c if all_perfect else th.b)
		_fx(Sfx.milestone(3))
		_kick(14.0, 0.5, Color.WHITE)
		_spawn_particles(120, th.c, 800.0)
		wait = 2.5
	queue_redraw()
	await get_tree().create_timer(wait).timeout
	if failed and player.playing:
		Library.last_result["music_pos"] = player.get_playback_position()
	get_tree().change_scene_to_file("res://scenes/results.tscn")


# ---------------------------------------------------------------- record mode

func _record_tick(gt: float) -> void:
	if rec_press < 0.0:
		return
	if not _button_held():
		var dur := gt - rec_press
		rec_t.append(rec_press)
		rec_d.append(dur if dur >= 0.3 else 0.0)
		rec_press = -1.0


# ---------------------------------------------------------------- effects

func _kick(shake_amount: float, flash_amount: float, col: Color) -> void:
	if not Settings.effects:
		return
	shake = maxf(shake, shake_amount)
	flash = maxf(flash, flash_amount)
	flash_color = col


func _banner(text: String, col: Color, dur: float = 1.2) -> void:
	banner_text = text
	banner_color = col
	banner_at = rt
	banner_dur = dur


func _popup(text: String, col: Color) -> void:
	popups.append({"text": text, "t": rt, "col": col, "x": randf_range(-20, 20)})


func _spawn_particles(n: int, col: Color, spd: float, trail: bool = false) -> void:
	var style := Progress.effect_id
	for k in n:
		var a := randf() * TAU
		var v := Vector2(cos(a), sin(a)) * randf_range(0.3, 1.0) * spd
		if trail:
			v = Vector2(randf_range(-60, 40), randf_range(-120, 120))
		var c := col.lerp(Color.WHITE, randf() * 0.4)
		if style == "confetti":
			c = [th.a, th.b, th.c, Color.WHITE][randi() % 4]
		particles.append({
			"p": Vector2.ZERO, "v": v, "life": 0.0,
			"max": randf_range(0.35, 0.8) * (1.6 if style == "confetti" else 1.0), "col": c,
			"s": randf_range(2.0, 5.5), "rot": randf() * TAU, "spin": randf_range(-12, 12),
			"style": "sparks" if trail else style, "burst": style == "fireworks" and not trail and randf() < 0.15,
		})


func _update_effects(delta: float) -> void:
	shake = maxf(0.0, shake - delta * 40.0)
	flash = maxf(0.0, flash - delta * 1.8)
	combo_pop = maxf(0.0, combo_pop - delta * 6.0)
	fever_k = move_toward(fever_k, 1.0 if combo >= FEVER_COMBO and not record else 0.0, delta * 1.5)
	level_k = move_toward(level_k, float(multiplier() - 1) / 3.0, delta * 1.2)
	var keep: Array = []
	var spawned: Array = []
	for p in particles:
		p.life += delta
		if p.life < p.max:
			var gravity := 500.0
			match p.style:
				"confetti":
					gravity = 160.0
					p.v *= 0.94
				"stars":
					gravity = 0.0
					p.v *= 0.92
				_:
					p.v *= 0.9
			p.v.y += gravity * delta
			p.p += p.v * delta
			p.rot += p.spin * delta
			keep.append(p)
		elif p.burst:
			for k in 8:
				var a := k * TAU / 8.0
				spawned.append({"p": p.p, "v": Vector2(cos(a), sin(a)) * 220.0, "life": 0.0, "max": 0.5,
					"col": p.col, "s": 3.0, "rot": 0.0, "spin": 0.0, "style": "sparks", "burst": false})
	particles = keep + spawned
	if particles.size() > 700:
		particles = particles.slice(particles.size() - 700)


func _hold_color(i: int) -> Color:
	return _note_color(notes[i]).lerp(Color.WHITE, 0.15)


func _note_color(t: float) -> Color:
	var sub := posmod(roundi((t - offset) / (beat_len / 4.0)), 4)
	return th.a if sub == 0 else (th.b if sub == 2 else th.c)


func _target_pos(sz: Vector2) -> Vector2:
	return Vector2(sz.x * lerpf(0.2, 0.8, _smooth(side_cur)), sz.y * 0.56)


## Two-switch mode: vertical offset of a lane from the middle (0 = top, 1 = bottom).
func _lane_dy(lane: int) -> float:
	if not dual:
		return 0.0
	return note_r * 1.75 * (-1.0 if lane == 0 else 1.0)


## Larry interrupts (Chaos): Larry pops up in front of the lane and covers the notes for a
## couple of bars. The ring stays, the music keeps going - keep the beat by ear.
func _draw_larry(sz: Vector2, gt: float, target: Vector2, dir: float) -> void:
	if gt < larry_start - 0.3 or gt > larry_end + 0.4:
		return
	var k_in := clampf((gt - (larry_start - 0.3)) / 0.3, 0.0, 1.0)
	var k_out := clampf((larry_end + 0.4 - gt) / 0.4, 0.0, 1.0)
	var k := minf(k_in, k_out)
	var band := note_r * (4.2 if dual else 2.2)
	# the "blanket" over the lane, leaving just the ring
	draw_rect(Rect2(-40, target.y - band, sz.x + 80, band * 2.0), Color(0.05, 0.04, 0.09, 0.96 * k))
	draw_arc(target + Vector2(0, _lane_dy(0)), note_r * 1.55, 0, TAU, 48, Color(th.ring, 0.55 * k), 3.0, true)
	if dual:
		draw_arc(target + Vector2(0, _lane_dy(1)), note_r * 1.55, 0, TAU, 48, Color(th.ring, 0.55 * k), 3.0, true)
	# a ticking beat dot so the screen isn't completely dead
	var phase := fposmod((gt - offset) / beat_len, 1.0)
	draw_circle(target, 6.0 + pow(1.0 - phase, 3.0) * 10.0, Color(1, 1, 1, 0.35 * k))
	# Larry himself, bouncing in front of the lane
	if larry_tex:
		var h := band * 2.9
		var w := larry_tex.get_width() * h / larry_tex.get_height()
		var cx := target.x + dir * sz.x * 0.52
		var bob := absf(sin(rt * 9.0)) * 8.0
		var y := target.y - h * 0.55 - bob + (1.0 - k) * h
		draw_texture_rect(larry_tex, Rect2(cx - w * 0.5, y, w, h), false, Color(1, 1, 1, k))
		# speech bubble
		var bw := 300.0
		var bx := cx - dir * (w * 0.5 + bw * 0.5 + 10.0)
		var by := y + h * 0.18
		draw_rect(Rect2(bx - bw * 0.5, by - 28.0, bw, 40.0), Color(1, 1, 1, 0.92 * k))
		var tip := Vector2(bx + dir * bw * 0.5, by - 8.0)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(dir * 16.0, -6.0), tip + Vector2(0, 10.0)]), Color(1, 1, 1, 0.92 * k))
		_text_center(larry_line, Vector2(bx, by), 20, Color(0.12, 0.08, 0.15, k))


func _smooth(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


# ---------------------------------------------------------------- pause

func _build_pause_menu() -> void:
	pause_panel = PanelContainer.new()
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pause_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := UI.vbox(14)
	pause_panel.add_child(v)
	v.add_child(UI.label("Paused", 40, UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UI.button("Resume", _toggle_pause, 280))
	v.add_child(UI.button("Restart", func(): get_tree().reload_current_scene()))
	if Library.has_meta("return_to_editor"):
		v.add_child(UI.button("Back to editor", func():
			Library.reset_session()
			get_tree().change_scene_to_file("res://scenes/chart_editor.tscn")))
	v.add_child(UI.button("Quit to songs", func(): get_tree().change_scene_to_file("res://scenes/song_select.tscn")))
	pause_panel.visible = false
	add_child(pause_panel)


func _toggle_pause() -> void:
	if finished:
		return
	paused = not paused
	pause_panel.visible = paused
	if started:
		player.stream_paused = paused
	if paused:
		(pause_panel.get_child(0).get_child(1) as Button).grab_focus()
	keys_down = 0
	queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var sz := size
	var gt := game_time()
	var target := _target_pos(sz)
	var target_x := target.x
	var lane_y := target.y
	var sk := _smooth(side_cur)
	var dir := lerpf(1.0, -1.0, sk)
	var far := lerpf(sz.x - target_x + 80.0, target_x + 80.0, sk)
	var appr := approach / maxf(0.3, speed_cur)
	var pps := far / appr
	var ring_col: Color = th.ring

	var shake_off := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	draw_set_transform(shake_off)

	# Beat pulse (also before the song starts, so you can feel the tempo).
	var beats_in := (gt - offset) / beat_len
	var phase := fposmod(beats_in, 1.0)
	var bar := int(floor(beats_in / 4.0))
	var e := 0.6
	if bar >= 0 and bar < energy.size():
		e = float(energy[bar])
	var pulse := pow(1.0 - phase, 3.0) * (0.35 + 0.65 * e)
	var hue := fposmod(rt * 0.08, 1.0)
	var fever_col := Color.from_hsv(hue, 0.7, 1.0)

	# Background gets hotter as the multiplier climbs, then goes rainbow in fever.
	var bg: Color = th.bg
	bg = bg.lerp(th.hot, clampf(pulse * 0.5 + level_k * 0.55, 0.0, 1.0))
	bg = bg.lerp(Color.from_hsv(hue, 0.6, 0.22), fever_k * (0.6 + pulse * 0.4))
	var bg_rect := Rect2(-shake_off - Vector2(20, 20), sz + Vector2(40, 40))
	if room:
		_room_rect = bg_rect
		room_layer.queue_redraw()
		# keep notes readable on top of the picture
		draw_rect(bg_rect, Color(bg, 0.38))
	else:
		draw_rect(bg_rect, bg)

	if level_k > 0.0 or fever_k > 0.0:
		var amount := maxf(level_k * 0.5, fever_k)
		for s: Vector3 in stars:
			var spd := (0.5 + s.z * 1.5) * (0.4 + amount)
			var x := fposmod(s.x - rt * spd * (bpm / 120.0) * 0.5 * dir, 1.0) * (sz.x + 200.0) - 100.0
			var y := s.y * sz.y
			var ln := (40.0 + s.z * 120.0) * dir
			var c := Color.from_hsv(fposmod(hue + s.z * 0.3, 1.0), 0.6, 1.0, 0.25 * amount * s.z) if fever_k > 0.3 else Color(th.a, 0.15 * amount * s.z)
			draw_line(Vector2(x, y), Vector2(x + ln, y), c, 2.0)
		draw_circle(target, 220.0 + pulse * 90.0, Color(fever_col, 0.07 * fever_k))

	var glow := clampf(combo / 60.0, 0.0, 1.0)
	draw_circle(target, 140.0 + pulse * 60.0, Color(ring_col.lerp(fever_col, fever_k), 0.04 + pulse * 0.06 + glow * 0.05))

	# Beat lines.
	var k0 := int(floor((gt - 0.6 - offset) / beat_len))
	var k1 := int(ceil((gt + appr - offset) / beat_len))
	for k in range(k0, k1 + 1):
		var x := target_x + (offset + k * beat_len - gt) * pps * dir
		if x < -5 or x > sz.x + 5:
			continue
		var is_bar := posmod(k, 4) == 0
		var h := (70.0 if is_bar else 40.0) + (note_r * 1.75 if dual else 0.0)
		var base_a := (0.16 if is_bar else 0.06) * (1.0 + level_k * 0.8)
		var lc := Color(1, 1, 1, base_a).lerp(Color(fever_col, 0.3 if is_bar else 0.12), fever_k)
		draw_line(Vector2(x, lane_y - h), Vector2(x, lane_y + h), lc, 2.0)

	# Lane.
	var lane_h := note_r * 1.3
	var edge := Color(ring_col, 0.25 + glow * 0.25 + level_k * 0.2).lerp(Color(fever_col, 0.8), fever_k)
	for ln in (2 if dual else 1):
		var ly := lane_y + _lane_dy(ln)
		draw_rect(Rect2(-40, ly - lane_h, sz.x + 80, lane_h * 2.0), Color(th.lane, 0.62 if room else 0.9))
		draw_line(Vector2(-40, ly - lane_h), Vector2(sz.x + 40, ly - lane_h), edge, 2.0 + fever_k * 2.0 + level_k)
		draw_line(Vector2(-40, ly + lane_h), Vector2(sz.x + 40, ly + lane_h), edge, 2.0 + fever_k * 2.0 + level_k)

	# Hold trails.
	while draw_idx < notes.size() and notes[draw_idx] + durs[draw_idx] + wait_time < gt - 1.0:
		draw_idx += 1
	for i in range(draw_idx, notes.size()):
		var nt := notes[i]
		if nt > gt + appr + 0.1:
			break
		if durs[i] <= 0.0 or states[i] == DONE:
			continue
		var col := _hold_color(i)
		var x0 := target_x + (nt - gt) * pps * dir
		var x1 := target_x + (nt + durs[i] - gt) * pps * dir
		var a := 0.55
		if states[i] == HOLDING:
			x0 = target_x
			a = 0.75 + 0.25 * sin(rt * 30.0)
		elif states[i] == DROPPED or states[i] == MISSED:
			col = Color(0.5, 0.5, 0.6)
			a = 0.3
		var lo := minf(x0, x1)
		var hi := maxf(x0, x1)
		lo = maxf(lo, -60.0)
		hi = minf(hi, sz.x + 60.0)
		if hi > lo:
			var th_h := note_r * 0.58
			var hy := lane_y + _lane_dy(lanes[i] if dual else 0)
			draw_rect(Rect2(lo, hy - th_h, hi - lo, th_h * 2.0), Color(col, a))
			draw_rect(Rect2(lo, hy - th_h * 0.33, hi - lo, th_h * 0.66), Color(1, 1, 1, a * 0.5))
			draw_circle(Vector2(x1, hy), th_h, Color(col, a))
			draw_arc(Vector2(x1, hy), th_h + 3.0, 0, TAU, 24, Color(1, 1, 1, a), 3.0, true)

	# Target ring.
	var tap_k := clampf((gt - tap_at) / 0.12, 0.0, 1.0)
	var base_r := note_r * 1.55
	var ring_r := base_r + (1.0 - tap_k) * 8.0 + (6.0 if holding_idx >= 0 else 0.0) + pulse * 4.0
	var rc := ring_col.lerp(fever_col, fever_k)
	if dual:
		for ln in 2:
			var rpos := target + Vector2(0, _lane_dy(ln))
			var mine := ln == tap_lane
			var rr := base_r + (((1.0 - tap_k) * 8.0) if mine else 0.0) + (6.0 if holding_idx >= 0 and hold_lane == ln else 0.0) + pulse * 4.0
			draw_circle(rpos, rr, Color(rc, 0.12 + ((1.0 - tap_k) * 0.25 if mine else 0.0)))
			draw_arc(rpos, rr, 0, TAU, 48, Color(rc, 0.9), 4.0 + glow * 2.0 + level_k * 2.0, true)
			# which keys work this switch
			var lbl := "W  ↑  L-click" if ln == 0 else "S  ↓  R-click"
			var lx := target_x - (base_r + 70.0) * dir
			_text_center(lbl, Vector2(lx, rpos.y + 6.0), 15, Color(UI.MUTED, 0.75))
	else:
		draw_circle(target, ring_r, Color(rc, 0.12 + (1.0 - tap_k) * 0.25 + (0.2 if holding_idx >= 0 else 0.0)))
		draw_arc(target, ring_r, 0, TAU, 48, Color(rc, 0.9), 4.0 + glow * 2.0 + level_k * 2.0, true)
	if fever_k > 0.0:
		draw_arc(target, ring_r + 10.0 + pulse * 10.0, 0, TAU, 48, Color(fever_col, 0.5 * fever_k), 2.0, true)
	if eye and Settings.eye_hover:
		# look-to-hit zone + dwell progress
		draw_arc(target, note_r * 3.2, 0, TAU, 64, Color(rc, 0.18 if gaze_armed else 0.06), 2.0, true)
		if gaze_time > 0.0:
			draw_arc(target, ring_r + 14.0, -PI / 2.0, -PI / 2.0 + TAU * gaze_time / Settings.eye_dwell, 48, Color.WHITE, 6.0, true)

	# Note heads.
	var shape := Progress.shape_id
	for i in range(draw_idx, notes.size()):
		var nt := notes[i]
		if nt > gt + appr + 0.1:
			break
		if states[i] == DONE or states[i] == HOLDING:
			continue
		var travel := nt - gt
		var waiting := false
		if wait_time > 0.0 and travel < 0.0 and states[i] == PENDING:
			travel = 0.0  # eye tracker mode: the note waits at the ring
			waiting = true
		var pos := Vector2(target_x + travel * pps * dir, lane_y + _lane_dy(lanes[i] if dual else 0))
		var col := _note_color(nt)
		if states[i] == MISSED or states[i] == DROPPED:
			var fade := clampf(1.0 - (gt - nt - wait_time) / 0.5, 0.0, 1.0)
			Cosmetics.draw_shape(self, shape, pos, note_r * 0.9, Color(UI.BAD, 0.5 * fade))
			continue
		var appear := clampf((gt + appr - nt) / 0.2, 0.0, 1.0)
		if fade_on:
			appear *= clampf((absf(pos.x - target_x) - note_r * 4.0) / 160.0, 0.0, 1.0)
		if waiting:
			var left := 1.0 - (gt - nt) / wait_time
			draw_arc(target, ring_r + 8.0, -PI / 2.0, -PI / 2.0 + TAU * left, 48, Color(col, 0.9), 5.0, true)
			pos.y += sin(rt * 10.0) * 2.0
		draw_circle(pos, note_r * 1.3, Color(col, 0.15 * appear))
		Cosmetics.draw_shape(self, shape, pos, note_r, Color(col, appear))
		if durs[i] > 0.0:
			draw_arc(pos, note_r, 0, TAU, 32, Color(1, 1, 1, appear), 4.0, true)
			Cosmetics.draw_shape(self, shape, pos, note_r * 0.35, Color(1, 1, 1, 0.9 * appear))
		else:
			Cosmetics.draw_shape(self, shape, pos, note_r * 0.45, Color(1, 1, 1, 0.85 * appear))

	# Larry interrupts: he jumps in front of the lane, you play by ear.
	_draw_larry(sz, gt, target, dir)

	# Hit rings.
	var keep: Array = []
	for fx in rings:
		var age: float = rt - fx.t
		if age > 0.4:
			continue
		keep.append(fx)
		var k := clampf(age / 0.4, 0.0, 1.0)
		var r := base_r + k * (100.0 if fx.big else 60.0)
		draw_arc(target + Vector2(0, float(fx.get("y", 0.0))), r, 0, TAU, 48, Color(fx.color, 1.0 - k), 7.0 * (1.0 - k) + 1.0, true)
	rings = keep

	# Particles.
	for p in particles:
		var k: float = p.life / p.max
		var pc := Color(p.col, 1.0 - k)
		var pp: Vector2 = target + p.p
		match p.style:
			"confetti":
				var w: Vector2 = Vector2(cos(p.rot), sin(p.rot)) * p.s * 1.4
				var hgt: Vector2 = Vector2(-w.y, w.x) * 0.5
				draw_colored_polygon(PackedVector2Array([pp - w - hgt, pp + w - hgt, pp + w + hgt, pp - w + hgt]), pc)
			"stars":
				Cosmetics.draw_shape(self, "star", pp, p.s * 1.2 * (1.0 - k * 0.5), pc)
			"fireworks":
				draw_line(pp, pp - p.v * 0.04, pc, 2.0)
			_:
				draw_circle(pp, p.s * (1.0 - k * 0.6), pc)

	# Score popups.
	var keep_p: Array = []
	for pp in popups:
		var age: float = rt - pp.t
		if age > 0.7:
			continue
		keep_p.append(pp)
		var a := clampf(1.0 - (age - 0.4) / 0.3, 0.0, 1.0)
		_text_center(pp.text, target + Vector2((70.0 + pp.x) * dir, -30.0 - age * 90.0), 22, Color(pp.col, a))
	popups = keep_p

	# Judgement text.
	var jage := rt - judge_at
	if jage < 0.5 and judge_text != "":
		var a := clampf(1.0 - (jage - 0.25) / 0.25, 0.0, 1.0)
		var rise := minf(jage, 0.1) * 120.0
		var js := 40 + int(maxf(0.0, 0.08 - jage) * 120.0)
		_text_center(judge_text, Vector2(target_x, lane_y - note_r * 3.0 - rise), js, Color(judge_color, a))
		if judge_sub != "":
			_text_center(judge_sub, Vector2(target_x, lane_y - note_r * 2.0 - rise), 20, Color(UI.MUTED.lerp(judge_color, 0.5), a))

	# Countdown on the last 4 beats before the first note.
	if not record and judged == 0 and not notes.is_empty():
		var to_first := (notes[0] - gt) / beat_len
		if to_first > 0.0 and to_first <= 4.0:
			var n := int(ceil(to_first))
			var kk := fposmod(to_first, 1.0)
			_text_center(str(n), Vector2(sz.x * 0.5, sz.y * 0.3), int(64 + kk * 30.0), Color(th.a, 0.4 + kk * 0.6))

	draw_set_transform(Vector2.ZERO)
	_draw_hud(sz, fever_col)

	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, sz), Color(flash_color, flash * 0.25))
	if finished and Library.last_result.get("failed", false):
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.5))
		_text_center("FAILED", sz * 0.5, 72, UI.BAD)


func _draw_timing_bar(center: Vector2) -> void:
	var w := 260.0
	var lim: float = WINDOWS.good * win_scale
	var px := (w * 0.5) / lim
	var h := 8.0
	draw_rect(Rect2(center.x - w * 0.5, center.y - h * 0.5, w, h), Color(JUDGE_COLORS.good, 0.25))
	var gw: float = WINDOWS.great * win_scale * px
	draw_rect(Rect2(center.x - gw, center.y - h * 0.5, gw * 2.0, h), Color(JUDGE_COLORS.great, 0.3))
	var pw: float = WINDOWS.perfect * win_scale * px
	draw_rect(Rect2(center.x - pw, center.y - h * 0.5, pw * 2.0, h), Color(JUDGE_COLORS.perfect, 0.35))
	draw_line(center + Vector2(0, -h), center + Vector2(0, h), Color(1, 1, 1, 0.5), 1.0)
	var sum := 0.0
	var n := 0
	for dd in deltas:
		var age: float = rt - dd.t
		if age > 12.0:
			continue
		var x := clampf(dd.d * px, -w * 0.5, w * 0.5)
		var a := clampf(1.0 - age / 12.0, 0.15, 1.0)
		draw_line(center + Vector2(x, -h - 3), center + Vector2(x, h + 3), Color(dd.c, a), 2.0)
		sum += dd.d
		n += 1
	if n >= 3:
		var mx := clampf(sum / n * px, -w * 0.5, w * 0.5)
		draw_colored_polygon(PackedVector2Array([center + Vector2(mx, -h - 4), center + Vector2(mx - 6, -h - 13), center + Vector2(mx + 6, -h - 13)]), Color.WHITE)
	draw_string(font, center + Vector2(-w * 0.5, h + 20), "early", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(UI.MUTED, 0.6))
	draw_string(font, center + Vector2(w * 0.5 - 30, h + 20), "late", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(UI.MUTED, 0.6))


func _draw_hud(sz: Vector2, fever_col: Color) -> void:
	if touch_ui and not finished:
		var pr := _pause_rect()
		draw_rect(pr, Color(0, 0, 0, 0.35))
		draw_rect(pr, Color(1, 1, 1, 0.5), false, 2.0)
		for k in 2:
			draw_rect(Rect2(pr.position + Vector2(24 + k * 20, 20), Vector2(10, 38)), Color(1, 1, 1, 0.85))
	if sz.y > sz.x * 1.05:
		_text_center("Turn your device sideways for the best view", Vector2(sz.x * 0.5, sz.y * 0.12), 28, UI.ACCENT3)
	var title := "%s  ·  %s" % [song.get("title", ""), UI.DIFF_NAMES.get(diff, diff)]
	if practice:
		title += "  ·  PRACTICE %d%%" % int(speed * 100.0)
	if mod != "":
		title += "  ·  " + str(Progress.MODS[mod].name)
	if eye:
		title += "  ·  EYE TRACKER"
	if Library.autoplay and not record:
		title += "  ·  AUTOPLAY (F2)"
	if watching:
		title += "  ·  REPLAY"
	if tutorial:
		title = "Learn to play"
	if record:
		title = "RECORDING %s chart  ·  %s" % [UI.DIFF_NAMES.get(diff, diff), song.get("title", "")]
	draw_string(font, Vector2(30, 46), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UI.MUTED)
	if record:
		var msg := "Tap along with the music · hold for long notes · %d notes" % rec_t.size()
		if rec_press >= 0.0:
			msg = "HOLDING…"
		_text_center(msg, Vector2(sz.x * 0.5, sz.y * 0.85), 26, UI.TEXT)
	else:
		shown_score = lerpf(shown_score, float(score), 0.25) if absf(shown_score - score) > 1.0 else float(score)
		draw_string(font, Vector2(sz.x - 330, 50), UI.format_score(int(shown_score)), HORIZONTAL_ALIGNMENT_RIGHT, 300, 36, UI.TEXT)
		draw_string(font, Vector2(sz.x - 330, 82), "%.2f%%" % (accuracy() * 100.0), HORIZONTAL_ALIGNMENT_RIGHT, 300, 22, UI.MUTED)
		var m := multiplier()
		var mcol: Color = [UI.MUTED, th.a, th.c, th.b][m - 1]
		if fever_k > 0.5:
			mcol = fever_col
		draw_string(font, Vector2(sz.x - 330, 124), "×%d" % m, HORIZONTAL_ALIGNMENT_RIGHT, 300, 34 + int(combo_pop * 6.0), mcol)
		if m < TIERS.size():
			var lo: int = TIERS[m - 1]
			var hi: int = TIERS[m]
			var k := float(combo - lo) / float(hi - lo)
			draw_rect(Rect2(sz.x - 130, 134, 100, 4), Color(1, 1, 1, 0.1))
			draw_rect(Rect2(sz.x - 130, 134, 100 * k, 4), mcol)
		if combo >= 3:
			var cs := 64 + int(combo_pop * 22.0) + int(fever_k * 12.0)
			var ccol := UI.TEXT.lerp(fever_col, fever_k)
			_text_center(str(combo), Vector2(sz.x * 0.5, sz.y * 0.3), cs, Color(ccol, 0.95))
			_text_center("FEVER" if fever_k > 0.5 else "combo", Vector2(sz.x * 0.5, sz.y * 0.3 + 30), 20, Color(ccol, 0.7) if fever_k > 0.5 else UI.MUTED)
		var bage := rt - broken_at
		if bage < 0.7:
			_text_center(str(broken_combo), Vector2(sz.x * 0.5, sz.y * 0.3 + bage * bage * 500.0), 64, Color(UI.BAD, 1.0 - bage / 0.7))
		if not practice:
			var hb := Rect2(30, 64, 300, 10)
			draw_rect(hb, Color(1, 1, 1, 0.08))
			var hc: Color = th.a if health > 0.3 else UI.BAD
			draw_rect(Rect2(hb.position, Vector2(hb.size.x * health, hb.size.y)), hc)

	var bn := rt - banner_at
	if bn < banner_dur and banner_text != "":
		var pop := 1.0 + maxf(0.0, 0.15 - bn) * 4.0
		var a := clampf(1.0 - (bn - (banner_dur - 0.4)) / 0.4, 0.0, 1.0)
		var fs := 52 if banner_text.length() < 22 else 36
		_text_center(banner_text, Vector2(sz.x * 0.5, sz.y * 0.18), int(fs * pop), Color(banner_color, a))

	var ia := rt - info_at
	if ia < 3.4 and info_text != "":
		var a := clampf(minf(ia / 0.15, (3.4 - ia) / 0.4), 0.0, 1.0)
		var fs := 34 if info_text.length() < 40 else 26
		var w := font.get_string_size(info_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_rect(Rect2(sz.x * 0.5 - w * 0.5 - 20, sz.y * 0.8 - fs - 6, w + 40, fs + 26), Color(0, 0, 0, 0.45 * a))
		_text_center(info_text, Vector2(sz.x * 0.5, sz.y * 0.8), fs, Color(th.b.lerp(Color.WHITE, 0.3), a))

	var prog := clampf(song_time / maxf(1.0, length), 0.0, 1.0)
	draw_rect(Rect2(0, sz.y - 6, sz.x, 6), Color(1, 1, 1, 0.06))
	draw_rect(Rect2(0, sz.y - 6, sz.x * prog, 6), Color(th.b, 0.8).lerp(fever_col, fever_k))

	if song_time < 0.0 and not paused and not notes.is_empty() and (notes[0] - game_time()) / beat_len > 4.0:
		_text_center("Get ready", Vector2(sz.x * 0.5, sz.y * 0.3), 56, UI.TEXT)
	if song_time < 1.0 and judged == 0 and not paused and not tutorial:
		var hint := "Tap on the beat · hold the long notes · R = restart"
		if eye:
			hint = "Look at the ring when a note arrives · notes wait %.1f s" % wait_time if Settings.eye_hover else "Click when a note reaches the ring · notes wait %.1f s" % wait_time
		_text_center(hint, Vector2(sz.x * 0.5, sz.y * 0.88), 22, UI.MUTED)


func _text_center(text: String, pos: Vector2, fsize: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	draw_string(font, pos - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)
