extends Control
## Plays a steady click; the player taps along. The average difference becomes the offset.

const BPM := 100.0
const BEATS := 32
const START := 1.5
const SKIP := 4  # ignore the first taps while the player finds the beat

var player: AudioStreamPlayer
var running := false
var diffs: Array[float] = []
var info: Label
var result_label: Label
var start_btn: Button
var save_btn: Button
var _flash := 0.0
var _last_k := -1


func _ready() -> void:
	UI.setup_root(self)
	player = AudioStreamPlayer.new()
	player.stream = Sfx.metronome(BPM, BEATS, START)
	player.bus = "SFX"
	player.finished.connect(_done)
	add_child(player)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 680
	center.add_child(panel)
	var v := UI.vbox(16)
	panel.add_child(v)
	v.add_child(UI.label("Calibrate timing", 36))
	info = UI.label("Press Start, then tap SPACE (or click) on every click you hear.\nUse headphones/speakers the way you normally play.", 20, UI.MUTED)
	v.add_child(info)
	result_label = UI.label("Current offset: %+d ms" % int(Settings.offset_ms), 26)
	v.add_child(result_label)
	var h := UI.hbox()
	v.add_child(h)
	start_btn = UI.button("Start", _start, 180)
	h.add_child(start_btn)
	save_btn = UI.button("Use this offset", _save)
	save_btn.disabled = true
	h.add_child(save_btn)
	h.add_child(UI.button("Reset to 0", func():
		Settings.offset_ms = 0.0
		Settings.save_settings()
		result_label.text = "Current offset: +0 ms"))
	h.add_child(UI.button("Back", func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn")))
	start_btn.grab_focus()


func _audio_time() -> float:
	return player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()


func _start() -> void:
	diffs.clear()
	running = true
	save_btn.disabled = true
	start_btn.release_focus()
	start_btn.disabled = true
	player.play()


func _input(event: InputEvent) -> void:
	if not running or not event.is_action_pressed("hit", false, true):
		return
	get_viewport().set_input_as_handled()
	var t := _audio_time() - START
	var beat := 60.0 / BPM
	var k := roundi(t / beat)
	if k < SKIP or k >= BEATS:
		return
	diffs.append(t - k * beat)
	result_label.text = "Taps: %d   ·   average %+d ms" % [diffs.size(), int(_median() * 1000.0)]


func _process(delta: float) -> void:
	if running:
		var k := int(floor((_audio_time() - START) / (60.0 / BPM)))
		if k != _last_k and k >= 0:
			_last_k = k
			_flash = 1.0
	_flash = maxf(0.0, _flash - delta * 4.0)
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2(size.x * 0.5, size.y * 0.15), 20.0 + _flash * 14.0, Color(UI.ACCENT, 0.2 + _flash * 0.8))


func _median() -> float:
	if diffs.is_empty():
		return 0.0
	var s := diffs.duplicate()
	s.sort()
	return s[s.size() / 2]


func _done() -> void:
	running = false
	start_btn.disabled = false
	if diffs.size() >= 8:
		save_btn.disabled = false
		result_label.text = "Measured offset: %+d ms (%d taps)" % [int(_median() * 1000.0), diffs.size()]
		save_btn.grab_focus()
	else:
		result_label.text = "Not enough taps — try again."
		start_btn.grab_focus()


func _save() -> void:
	Settings.offset_ms = roundf(_median() * 1000.0)
	Settings.save_settings()
	result_label.text = "Saved offset: %+d ms" % int(Settings.offset_ms)
	save_btn.disabled = true
