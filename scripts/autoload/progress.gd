extends Node
## Long-term progress: stars, unlocked looks, the selected look, the daily challenge and its streak.

const PATH := "user://progress.cfg"
const GRADE_STARS := {"F": 0, "D": 0, "C": 1, "B": 2, "A": 3, "S": 4}

const MODS := {
	"sudden": {"name": "Sudden death", "desc": "One miss and it's over."},
	"fast":   {"name": "Fast notes", "desc": "Notes fly in much faster."},
	"fade":   {"name": "Fade out", "desc": "Notes vanish just before the ring. Feel the beat!"},
	"mirror": {"name": "Mirror", "desc": "Notes come from the left."},
}
const MOD_ORDER := ["sudden", "fast", "fade", "mirror"]
const DAILY_DIFFS := ["normal", "hard", "normal", "expert", "easy", "hard", "normal"]

var theme_id := "neon"
var shape_id := "circle"
var effect_id := "sparks"
var daily_done: Array = []   # "YYYY-MM-DD" strings


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		theme_id = cfg.get_value("look", "theme", theme_id)
		shape_id = cfg.get_value("look", "shape", shape_id)
		effect_id = cfg.get_value("look", "effect", effect_id)
		daily_done = cfg.get_value("daily", "done", [])


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("look", "theme", theme_id)
	cfg.set_value("look", "shape", shape_id)
	cfg.set_value("look", "effect", effect_id)
	cfg.set_value("daily", "done", daily_done)
	cfg.save(PATH)


# ---------------------------------------------------------------- stars + unlocks

static func stars_for(best: Dictionary) -> int:
	if best.is_empty():
		return 0
	return int(GRADE_STARS.get(str(best.get("grade", "D")), 0)) + (1 if best.get("fc", false) else 0)


func total_stars() -> int:
	var total := 0
	for song in Library.songs:
		for d in Library.DIFFICULTIES:
			total += stars_for(Library.get_best(song.id, d))
	return total


func is_unlocked(stars_needed: int) -> bool:
	return total_stars() >= stars_needed


## Things that unlock when going from `before` to `after` stars.
func unlocked_between(before: int, after: int) -> Array:
	var out := []
	for u in Cosmetics.all_unlockables():
		if u.stars > before and u.stars <= after:
			out.append(u)
	return out


func next_unlock() -> Dictionary:
	var stars := total_stars()
	var best := {}
	for u in Cosmetics.all_unlockables():
		if u.stars > stars and (best.is_empty() or u.stars < best.stars):
			best = u
	return best


func theme() -> Dictionary:
	return Cosmetics.theme(theme_id)


# ---------------------------------------------------------------- daily challenge

func _local_unix() -> int:
	return int(Time.get_unix_time_from_system()) + int(Time.get_time_zone_from_system().bias) * 60


func today() -> String:
	return Time.get_date_string_from_unix_time(_local_unix())


## Today's challenge: same for everyone with the same song library on the same day.
func daily() -> Dictionary:
	if Library.songs.is_empty():
		return {}
	var ids: Array = []
	for s in Library.songs:
		ids.append(str(s.id))
	ids.sort()
	var h := absi(today().hash())
	var weekday: int = Time.get_datetime_dict_from_unix_time(_local_unix()).weekday
	return {
		"song_id": ids[h % ids.size()],
		"diff": DAILY_DIFFS[weekday % DAILY_DIFFS.size()],
		"mod": MOD_ORDER[(h / 7) % MOD_ORDER.size()],
		"done": today() in daily_done,
	}


func mark_daily_done() -> void:
	if not today() in daily_done:
		daily_done.append(today())
		if daily_done.size() > 400:
			daily_done = daily_done.slice(daily_done.size() - 400)
		save()


## Days in a row with a completed daily (today counts if done, otherwise counting from yesterday).
func streak() -> int:
	var day := _local_unix()
	if not today() in daily_done:
		day -= 86400
	var n := 0
	while Time.get_date_string_from_unix_time(day) in daily_done:
		n += 1
		day -= 86400
	return n
