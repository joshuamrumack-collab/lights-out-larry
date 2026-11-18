extends Node
## Class leaderboard client. Talks to a Google Apps Script web app that stores scores in a
## Google Sheet (see tools/leaderboard). Weekly boards: scores are grouped by ISO week.

signal top_received(song_id: String, diff: String, rows: Array)
signal submitted(ok: bool)

var _baked_url := ""
var _baked_code := ""


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("res://config/leaderboard.cfg") == OK:
		_baked_url = str(cfg.get_value("leaderboard", "url", ""))
		_baked_code = str(cfg.get_value("leaderboard", "class_code", ""))


func url() -> String:
	return Settings.leaderboard_url.strip_edges() if Settings.leaderboard_url.strip_edges() != "" else _baked_url


func class_code() -> String:
	return Settings.class_code.strip_edges() if Settings.class_code.strip_edges() != "" else _baked_code


func enabled() -> bool:
	return url().begins_with("https://")


## ISO week like "2026-W47".
func week() -> String:
	var unix := int(Time.get_unix_time_from_system()) + int(Time.get_time_zone_from_system().bias) * 60
	var d := Time.get_datetime_dict_from_unix_time(unix)
	var wd: int = (int(d.weekday) + 6) % 7  # Monday = 0
	var thursday := unix + (3 - wd) * 86400
	var td := Time.get_datetime_dict_from_unix_time(thursday)
	var jan1 := Time.get_unix_time_from_datetime_dict({"year": td.year, "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0})
	var wk := int((thursday - jan1) / 86400 / 7) + 1
	return "%d-W%02d" % [td.year, wk]


func submit(song: Dictionary, diff: String, r: Dictionary) -> void:
	if not enabled() or Settings.player_name.strip_edges() == "":
		submitted.emit(false)
		return
	var body := JSON.stringify({
		"code": class_code(), "week": week(), "name": Settings.player_name.strip_edges().left(20),
		"song": str(song.id), "title": str(song.get("title", "")), "diff": diff,
		"score": int(r.score), "acc": snappedf(float(r.accuracy) * 100.0, 0.01), "combo": int(r.max_combo),
		"fc": bool(r.get("full_combo", false)), "assist": bool(r.get("assist", false)),
	})
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(result, code, _h, _b):
		req.queue_free()
		submitted.emit(result == HTTPRequest.RESULT_SUCCESS and code < 400))
	# text/plain avoids a CORS preflight, which Apps Script can't answer.
	req.request(url(), PackedStringArray(["Content-Type: text/plain;charset=utf-8"]), HTTPClient.METHOD_POST, body)


func fetch_top(song_id: String, diff: String, this_week: bool = true) -> void:
	if not enabled():
		top_received.emit(song_id, diff, [])
		return
	var q := "?action=top&code=%s&song=%s&diff=%s&week=%s" % [
		class_code().uri_encode(), song_id.uri_encode(), diff, week() if this_week else "all"]
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(result, code, _h, body: PackedByteArray):
		req.queue_free()
		var rows: Array = []
		if result == HTTPRequest.RESULT_SUCCESS and code < 400:
			var data = JSON.parse_string(body.get_string_from_utf8())
			if typeof(data) == TYPE_DICTIONARY and data.has("rows"):
				rows = data.rows
		top_received.emit(song_id, diff, rows))
	req.request(url() + q)
