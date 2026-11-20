extends Node
## Player settings + input map + audio buses. Saved to user://settings.cfg.

const PATH := "user://settings.cfg"

var offset_ms: float = 0.0        # + means you hit late (audio/input latency); set via Calibrate
var music_volume: float = 0.8
var sfx_volume: float = 0.5
var hit_sound: String = "switch"     # see Sfx.HIT_STYLES
var effects: bool = true          # screen shake + flashes
var background: String = "room"   # "room" (little brother + light switch) or "plain"
var room_theme: String = "auto"   # "auto" (each song gets a room) or one of PixelRoom.THEMES
var scroll_speed: float = 1.0
var no_fail: bool = false
var dual_switch: bool = false   # two light switches (two lanes) on Hard, Expert and Chaos
var fullscreen: bool = false     # kept for old settings files; see window_mode
var window_mode: String = "windowed"   # windowed / fullscreen / borderless
var window_size: Vector2i = Vector2i(1280, 720)
var art_style: String = "smooth"  # "smooth" or "sharp" (blocky pixels) for the pictures
# Assist (accessibility) options
var assist_timing: bool = false   # much wider hit windows
var holds_as_taps: bool = false   # hold notes only need a press
var big_notes: bool = false
var any_key: bool = false         # every key / button / click counts as the hit button
# Eye tracker mode
var eye_mode: bool = false        # fewer notes, notes wait at the ring
var eye_wait: float = 2.0         # seconds a note waits at the ring
var eye_gap: float = 2.5          # minimum seconds between notes
var eye_hover: bool = true        # looking at the ring (pointer over it) counts as a hit
var eye_dwell: float = 0.35       # how long to look at the ring to hit
# Player + class leaderboard
var player_name: String = ""
var leaderboard_url: String = ""  # Google Apps Script web app URL (see tools/leaderboard)
var class_code: String = ""
# Remember last choice
var last_song: String = ""
var last_diff: String = "normal"


func assist_on() -> bool:
	return assist_timing or holds_as_taps or eye_mode


func _ready() -> void:
	_migrate_old_save()
	_setup_input()
	_setup_buses()
	load_settings()
	apply()


func _setup_input() -> void:
	_add_action("hit")
	for k in [KEY_SPACE, KEY_Z, KEY_X, KEY_J, KEY_F]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event("hit", e)
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("hit", m)
	for b in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y]:
		var j := InputEventJoypadButton.new()
		j.button_index = b
		InputMap.action_add_event("hit", j)

	# Two light switches: top (up) and bottom (down).
	_add_action("hit_up")
	_add_action("hit_down")
	for pair in [["hit_up", [KEY_W, KEY_UP, KEY_F, KEY_Z], MOUSE_BUTTON_LEFT, [JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_DPAD_UP]],
			["hit_down", [KEY_S, KEY_DOWN, KEY_J, KEY_X], MOUSE_BUTTON_RIGHT, [JOY_BUTTON_A, JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_DPAD_DOWN]]]:
		for k in pair[1]:
			var ke := InputEventKey.new()
			ke.physical_keycode = k
			InputMap.action_add_event(pair[0], ke)
		var mb := InputEventMouseButton.new()
		mb.button_index = pair[2]
		InputMap.action_add_event(pair[0], mb)
		for b in pair[3]:
			var jb := InputEventJoypadButton.new()
			jb.button_index = b
			InputMap.action_add_event(pair[0], jb)

	_add_action("pause")
	var esc := InputEventKey.new()
	esc.physical_keycode = KEY_ESCAPE
	InputMap.action_add_event("pause", esc)
	var start := InputEventJoypadButton.new()
	start.button_index = JOY_BUTTON_START
	InputMap.action_add_event("pause", start)


func _add_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)


func _setup_buses() -> void:
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")
	# Pitch correction for practice mode (slowed songs keep their pitch). Disabled by default.
	var music := AudioServer.get_bus_index("Music")
	if AudioServer.get_bus_effect_count(music) == 0:
		var ps := AudioEffectPitchShift.new()
		AudioServer.add_bus_effect(music, ps)
		AudioServer.set_bus_effect_enabled(music, 0, false)


## speed < 1 slows the song down in practice mode; pitch is corrected on the Music bus.
func set_music_speed(player: AudioStreamPlayer, speed: float) -> void:
	player.pitch_scale = speed
	var music := AudioServer.get_bus_index("Music")
	var ps := AudioServer.get_bus_effect(music, 0) as AudioEffectPitchShift
	if ps:
		ps.pitch_scale = 1.0 / speed
		AudioServer.set_bus_effect_enabled(music, 0, absf(speed - 1.0) > 0.01)


func apply() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(music_volume, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(sfx_volume, 0.0001)))
	if DisplayServer.get_name() != "headless" and OS.get_name() != "Web":
		var mode := DisplayServer.WINDOW_MODE_WINDOWED
		match window_mode:
			"fullscreen": mode = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
			"borderless": mode = DisplayServer.WINDOW_MODE_FULLSCREEN
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
		if mode == DisplayServer.WINDOW_MODE_WINDOWED:
			var scr := DisplayServer.window_get_current_screen()
			var avail := DisplayServer.screen_get_usable_rect(scr)
			var want := Vector2i(mini(window_size.x, avail.size.x), mini(window_size.y, avail.size.y))
			if DisplayServer.window_get_size() != want:
				DisplayServer.window_set_size(want)
				DisplayServer.window_set_position(avail.position + (avail.size - want) / 2)


func art_filter() -> CanvasItem.TextureFilter:
	return CanvasItem.TEXTURE_FILTER_NEAREST if art_style == "sharp" else CanvasItem.TEXTURE_FILTER_LINEAR


func offset_sec() -> float:
	return offset_ms / 1000.0


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	offset_ms = cfg.get_value("game", "offset_ms", offset_ms)
	scroll_speed = cfg.get_value("game", "scroll_speed", scroll_speed)
	no_fail = cfg.get_value("game", "no_fail", no_fail)
	dual_switch = cfg.get_value("game", "dual_switch", dual_switch)
	music_volume = cfg.get_value("audio", "music_volume", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx_volume", sfx_volume)
	hit_sound = cfg.get_value("audio", "hit_sound", hit_sound)
	if not cfg.has_section_key("audio", "has_switch_sound") and hit_sound == "soft":
		hit_sound = "switch"   # the new light-switch sound replaces the old default once
	effects = cfg.get_value("video", "effects", effects)
	background = cfg.get_value("video", "background", background)
	room_theme = cfg.get_value("video", "room_theme", room_theme)
	fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
	window_mode = cfg.get_value("video", "window_mode", "fullscreen" if fullscreen else window_mode)
	window_size = cfg.get_value("video", "window_size", window_size)
	art_style = cfg.get_value("video", "art_style", art_style)
	assist_timing = cfg.get_value("assist", "timing", assist_timing)
	holds_as_taps = cfg.get_value("assist", "holds_as_taps", holds_as_taps)
	big_notes = cfg.get_value("assist", "big_notes", big_notes)
	any_key = cfg.get_value("assist", "any_key", any_key)
	eye_mode = cfg.get_value("eye", "mode", eye_mode)
	eye_wait = cfg.get_value("eye", "wait", eye_wait)
	eye_gap = cfg.get_value("eye", "gap", eye_gap)
	eye_hover = cfg.get_value("eye", "hover", eye_hover)
	eye_dwell = cfg.get_value("eye", "dwell", eye_dwell)
	player_name = cfg.get_value("player", "name", player_name)
	leaderboard_url = cfg.get_value("player", "leaderboard_url", leaderboard_url)
	class_code = cfg.get_value("player", "class_code", class_code)
	last_song = cfg.get_value("player", "last_song", last_song)
	last_diff = cfg.get_value("player", "last_diff", last_diff)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "offset_ms", offset_ms)
	cfg.set_value("game", "scroll_speed", scroll_speed)
	cfg.set_value("game", "no_fail", no_fail)
	cfg.set_value("game", "dual_switch", dual_switch)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "hit_sound", hit_sound)
	cfg.set_value("audio", "has_switch_sound", true)
	cfg.set_value("video", "effects", effects)
	cfg.set_value("video", "background", background)
	cfg.set_value("video", "room_theme", room_theme)
	cfg.set_value("video", "fullscreen", window_mode != "windowed")
	cfg.set_value("video", "window_mode", window_mode)
	cfg.set_value("video", "window_size", window_size)
	cfg.set_value("video", "art_style", art_style)
	cfg.set_value("assist", "timing", assist_timing)
	cfg.set_value("assist", "holds_as_taps", holds_as_taps)
	cfg.set_value("assist", "big_notes", big_notes)
	cfg.set_value("assist", "any_key", any_key)
	cfg.set_value("eye", "mode", eye_mode)
	cfg.set_value("eye", "wait", eye_wait)
	cfg.set_value("eye", "gap", eye_gap)
	cfg.set_value("eye", "hover", eye_hover)
	cfg.set_value("eye", "dwell", eye_dwell)
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "leaderboard_url", leaderboard_url)
	cfg.set_value("player", "class_code", class_code)
	cfg.set_value("player", "last_song", last_song)
	cfg.set_value("player", "last_diff", last_diff)
	cfg.save(PATH)


## The game used to be called "OneBeat". Godot keeps save data in a folder named after the
## game, so bring the old saves, imported songs and replays over once.
func _migrate_old_save() -> void:
	var user := ProjectSettings.globalize_path("user://").trim_suffix("/")
	var old := user.get_base_dir().path_join("OneBeat")
	if not DirAccess.dir_exists_absolute(old) or FileAccess.file_exists("user://.migrated"):
		return
	_copy_dir(old, user)
	var f := FileAccess.open("user://.migrated", FileAccess.WRITE)
	if f:
		f.store_string("from " + old)


func _copy_dir(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	var d := DirAccess.open(from)
	if d == null:
		return
	for sub in d.get_directories():
		if sub.begins_with("."):
			continue
		_copy_dir(from.path_join(sub), to.path_join(sub))
	for file in d.get_files():
		if not FileAccess.file_exists(to.path_join(file)):
			DirAccess.copy_absolute(from.path_join(file), to.path_join(file))


const DUAL_DIFFS := ["hard", "expert", "twist"]


## Is the two-switch mode on for this difficulty? (Not with eye tracker mode or "any key".)
func dual_for(diff: String) -> bool:
	return dual_switch and diff in DUAL_DIFFS and not eye_mode and not any_key
