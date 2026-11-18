extends Node
## Song library, chart cache, scores and the "what are we playing" session state.
##
## A song is a folder containing song.json + an audio file (mp3/ogg/wav).
##   res://songs/<id>/   songs bundled with the game (exported with it)
##   user://songs/<id>/  songs imported by the player
## song.json keys: id, title, artist, suno_url, audio, bpm, offset, start, end, length,
##                 energy[], grid[], charts{difficulty: [times]} (custom charts only)

const USER_DIR := "user://songs"
const RES_DIR := "res://songs"
const SCORES_PATH := "user://scores.cfg"
const DIFFICULTIES := ["easy", "normal", "hard", "expert", "twist"]
const REPLAY_DIR := "user://replays"
const SHARE_PREFIX := "ONEBEAT1:"
const SUNO_PATTERN := "^(https?://)?([a-z0-9-]+\\.)*suno\\.(com|ai)/\\S*[A-Za-z0-9]{4,}"

var songs: Array[Dictionary] = []

# Session state, shared between scenes.
var current: Dictionary = {}
var difficulty: String = "normal"
var mode: String = "play"            # "play" or "record"
var last_result: Dictionary = {}
var editing: Dictionary = {}         # song being re-timed in the import screen
var selected_id: String = ""
var practice: Dictionary = {}        # {"speed": 0.75, "start": seconds, "loop_bars": 0 (=no loop)}
var modifier: String = ""            # daily challenge modifier (see Progress.MODS)
var is_daily := false
var autoplay := false
var is_tutorial := false
var replay: Dictionary = {}          # set to watch a replay
var share_pending: Dictionary = {}   # shared chart waiting for its audio file (import screen)                # watch the chart play itself (toggle with F2 in game)

var _chart_cache: Dictionary = {}
var _scores := ConfigFile.new()


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	_scores.load(SCORES_PATH)
	refresh()
	selected_id = Settings.last_song
	if Settings.last_diff in DIFFICULTIES:
		difficulty = Settings.last_diff


## Remembers the selected song + difficulty between sessions.
func remember_selection() -> void:
	Settings.last_song = selected_id
	Settings.last_diff = difficulty
	Settings.save_settings()


func reset_session() -> void:
	practice = {}
	modifier = ""
	is_daily = false
	is_tutorial = false
	replay = {}
	mode = "play"


## The built-in tutorial song (res://tutorial), not part of the song list.
func tutorial_song() -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://tutorial/song.json"))
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	data["_dir"] = "res://tutorial"
	data["_builtin"] = true
	return data


func start_tutorial() -> void:
	reset_session()
	current = tutorial_song()
	difficulty = "normal"
	is_tutorial = true
	invalidate(current)


# ---------------------------------------------------------------- replays

func _replay_path(song_id: String, diff: String) -> String:
	return REPLAY_DIR.path_join("%s_%s.json" % [song_id, diff])


func save_replay(song_id: String, diff: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(REPLAY_DIR)
	var f := FileAccess.open(_replay_path(song_id, diff), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_replay(song_id: String, diff: String) -> Dictionary:
	var p := _replay_path(song_id, diff)
	if not FileAccess.file_exists(p):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if typeof(d) == TYPE_DICTIONARY else {}


func has_replay(song_id: String, diff: String) -> bool:
	return FileAccess.file_exists(_replay_path(song_id, diff))


# ---------------------------------------------------------------- sharing charts

## What gets shared: song info, timing and your own charts. Never the audio (classmates get it from Suno).
func share_data(song: Dictionary) -> Dictionary:
	return {
		"format": "onebeat-chart", "version": 1,
		"title": song.get("title", ""), "artist": song.get("artist", ""), "suno_url": song.get("suno_url", ""),
		"bpm": song.get("bpm", 120.0), "offset": song.get("offset", 0.0), "charts": song.get("charts", {}),
	}


func share_code(song: Dictionary) -> String:
	var raw := JSON.stringify(share_data(song)).to_utf8_buffer()
	return SHARE_PREFIX + Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_GZIP))


## Accepts a share code or the text of a .onebeat file. Returns {} if it isn't valid.
func parse_share(text: String) -> Dictionary:
	text = text.strip_edges()
	if text.is_empty():
		return {}
	var json_text := text
	if text.begins_with(SHARE_PREFIX):
		var raw := Marshalls.base64_to_raw(text.substr(SHARE_PREFIX.length()))
		if raw.is_empty():
			return {}
		json_text = raw.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP).get_string_from_utf8()
	var j := JSON.new()
	if j.parse(json_text) != OK:
		return {}
	var d = j.data
	if typeof(d) != TYPE_DICTIONARY or d.get("format", "") != "onebeat-chart":
		return {}
	return d


func export_share_file(song: Dictionary, path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(share_data(song), "\t"))
	return true


func refresh() -> void:
	songs.clear()
	_scan(USER_DIR, false)
	_scan(RES_DIR, true)   # bundled copies of songs you also have imported are skipped
	songs.sort_custom(func(a, b): return str(a.title).naturalnocasecmp_to(str(b.title)) < 0)


func _scan(dir_path: String, builtin: bool) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		var folder := dir_path.path_join(sub)
		var json_path := folder.path_join("song.json")
		if not FileAccess.file_exists(json_path):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(json_path))
		if typeof(data) != TYPE_DICTIONARY:
			push_warning("Bad song.json in " + folder)
			continue
		data["_dir"] = folder
		data["_builtin"] = builtin
		if not data.has("id"):
			data["id"] = sub
		if not find(str(data.id)).is_empty():
			continue
		songs.append(data)


func is_suno_url(url: String) -> bool:
	var re := RegEx.new()
	re.compile(SUNO_PATTERN)
	return re.search(url.strip_edges().to_lower()) != null


func find(id: String) -> Dictionary:
	for s in songs:
		if s.id == id:
			return s
	return {}


func load_stream(song: Dictionary) -> AudioStream:
	var path: String = str(song._dir).path_join(str(song.audio))
	if path.begins_with("res://"):
		return load(path) as AudioStream
	return load_audio_file(path)


static func load_audio_file(path: String) -> AudioStream:
	match path.get_extension().to_lower():
		"mp3":
			return AudioStreamMP3.load_from_file(path)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"wav":
			return AudioStreamWAV.load_from_file(path)
	return null


## Copies an audio file into user://songs/<id>/ and returns the new (unsaved) song dict.
func import_audio(src_path: String, title: String, artist: String, suno_url: String) -> Dictionary:
	var id := _make_id(title, suno_url if suno_url != "" else src_path)
	var folder := USER_DIR.path_join(id)
	DirAccess.make_dir_recursive_absolute(folder)
	var audio_name := "audio." + src_path.get_extension().to_lower()
	var err := DirAccess.copy_absolute(ProjectSettings.globalize_path(src_path), ProjectSettings.globalize_path(folder.path_join(audio_name)))
	if err != OK:
		return {}
	return {
		"id": id, "title": title, "artist": artist, "suno_url": suno_url.strip_edges(),
		"audio": audio_name, "bpm": 120.0, "offset": 0.0, "charts": {},
		"_dir": folder, "_builtin": false,
	}


func _make_id(title: String, url: String) -> String:
	var slug := ""
	for c in title.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			slug += c
		elif not slug.ends_with("-"):
			slug += "-"
	slug = slug.trim_prefix("-").trim_suffix("-").left(32)
	if slug.is_empty():
		slug = "song"
	return "%s-%s" % [slug, str(url.hash() & 0xFFFFFF).pad_zeros(8).right(6)]


func save_song(song: Dictionary) -> void:
	var out := {}
	for k in song.keys():
		if not str(k).begins_with("_"):
			out[k] = song[k]
	var f := FileAccess.open(str(song._dir).path_join("song.json"), FileAccess.WRITE)
	if f == null:
		push_error("Can't write song.json (bundled songs are read-only in exports)")
		return
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	invalidate(song)
	refresh()


func delete_song(song: Dictionary) -> void:
	if song.get("_builtin", false):
		return
	var folder: String = song._dir
	var dir := DirAccess.open(folder)
	if dir:
		for f in dir.get_files():
			dir.remove(f)
	DirAccess.remove_absolute(folder)
	refresh()


func invalidate(song: Dictionary) -> void:
	for d in DIFFICULTIES:
		_chart_cache.erase(str(song.id) + ":" + d)


func has_custom_chart(song: Dictionary, diff: String) -> bool:
	return song.get("charts", {}).has(diff)


## Returns {"t": PackedFloat64Array note times, "d": PackedFloat64Array hold durations (0 = tap)}.
func get_chart(song: Dictionary, diff: String, length: float = -1.0) -> Dictionary:
	var key := str(song.id) + ":" + diff
	if _chart_cache.has(key):
		return _chart_cache[key]
	var chart: Dictionary
	var custom: Dictionary = song.get("charts", {})
	if custom.has(diff):
		chart = ChartGen.from_json(custom[diff])
	else:
		if length < 0.0:
			length = float(song.get("length", 180.0))
		chart = ChartGen.generate(song, diff, length)
	_chart_cache[key] = chart
	return chart


func chart_counts(song: Dictionary, diff: String) -> Vector2i:
	var c := get_chart(song, diff)
	var holds := 0
	for d in c.d:
		if d > 0.0:
			holds += 1
	return Vector2i(c.t.size(), holds)


## Difficulty level 1-12 from note density (average and the busiest 4 seconds).
func chart_level(song: Dictionary, diff: String) -> int:
	var c := get_chart(song, diff)
	var t: PackedFloat64Array = c.t
	if t.size() < 2:
		return 1
	var dur := maxf(10.0, t[t.size() - 1] - t[0])
	var weight := 0.0
	for d in c.d:
		weight += 0.7 if d > 0.0 else 1.0
	var nps := weight / dur
	var peak := 0
	var j := 0
	for i in t.size():
		while t[i] - t[j] > 4.0:
			j += 1
		peak = maxi(peak, i - j + 1)
	return clampi(int(round(0.5 + nps * 1.1 + peak / 4.0 * 0.6)), 1, 12)


## Where to start the song preview: the loudest 4 bars (usually the chorus).
func preview_start(song: Dictionary) -> float:
	var energy: Array = song.get("energy", [])
	var beat := 60.0 / float(song.get("bpm", 120.0))
	if energy.size() < 6:
		return float(song.get("length", 60.0)) * 0.35
	var best := 0
	var best_v := -1.0
	for b in range(0, energy.size() - 4):
		var v := 0.0
		for k in 4:
			v += float(energy[b + k])
		if v > best_v + 0.01:
			best_v = v
			best = b
	return float(song.get("offset", 0.0)) + best * beat * 4.0


## Copies an imported song into res://songs so it ships with exports (only works from the editor).
func bundle_song(song: Dictionary) -> bool:
	if song.get("_builtin", false):
		return false
	var dest := RES_DIR.path_join(str(song.id))
	var gdest := ProjectSettings.globalize_path(dest)
	DirAccess.make_dir_recursive_absolute(gdest)
	var src: String = song._dir
	for f in DirAccess.get_files_at(src):
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(src.path_join(f)), gdest.path_join(f)) != OK:
			return false
	return true


# ---------------------------------------------------------------- scores

func get_best(song_id: String, diff: String) -> Dictionary:
	return _scores.get_value(song_id, diff, {})


## Returns true if this was a new best.
func submit_score(song_id: String, diff: String, result: Dictionary) -> bool:
	var best := get_best(song_id, diff)
	if best.is_empty() or int(result.score) > int(best.get("score", 0)):
		_scores.set_value(song_id, diff, {
			"score": result.score, "accuracy": result.accuracy,
			"max_combo": result.max_combo, "grade": result.grade,
			"fc": result.get("full_combo", false) or best.get("fc", false),
		})
		_scores.save(SCORES_PATH)
		return true
	return false
