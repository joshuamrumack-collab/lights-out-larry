class_name ChartGen
extends RefCounted
## Turns analysed song data into note times for each difficulty.
## Notes are placed on a 16th-note grid. Each slot gets a score from how strong the
## music hits there (onset strength) plus how "important" the slot is musically
## (downbeat > beat 3 > other beats > 8ths > 16ths). Louder bars get more notes.

const DIFFICULTIES := ["easy", "normal", "hard", "expert", "twist"]
const EVENT_TYPES := ["text", "speed", "mirror", "fade", "larry"]

# step: which grid slots are allowed (4 = quarter notes, 2 = 8ths, 1 = 16ths)
# gap:  minimum distance between notes in 16ths
# lo/hi: notes per bar in the quietest / loudest bars
# run:  max consecutive 16th notes (0 = no limit needed)
# need: minimum onset strength for an off-beat note (on-beat notes are always allowed)
const CONFIG := {
	"easy":   {"step": 4, "gap": 8, "lo": 1, "hi": 2, "run": 0, "need": 1.0},
	"normal": {"step": 4, "gap": 4, "lo": 2, "hi": 4, "run": 0, "need": 1.0},
	"hard":   {"step": 2, "gap": 2, "lo": 3, "hi": 7, "run": 0, "need": 0.08},
	"expert": {"step": 1, "gap": 1, "lo": 4, "hi": 11, "run": 3, "need": 0.06},
}


static func slot_bonus(s: int) -> float:
	if s == 0:
		return 0.45
	if s == 8:
		return 0.3
	if s % 4 == 0:
		return 0.18
	if s % 2 == 0:
		return 0.05
	return 0.0


# Hold notes. A note can become a hold in two ways:
#   natural: the gap after it is already long (>= `min` beats), the hold fills the gap
#   swallow: the hold lasts `eat` beats and the few notes under it are removed
# Quieter, sustained parts of the music are preferred (fewer onsets under the hold).
# `margin` beats stay free after a hold, `spacing` beats between hold starts,
# `share` caps how many of the notes become holds.
const HOLDS := {
	"easy":   {"min": 3.0, "eat": 2.0, "margin": 1.0, "max": 4.0, "spacing": 6.0, "share": 0.22},
	"normal": {"min": 2.0, "eat": 2.0, "margin": 1.0, "max": 4.0, "spacing": 6.0, "share": 0.15},
	"hard":   {"min": 1.5, "eat": 1.5, "margin": 0.5, "max": 3.0, "spacing": 5.0, "share": 0.1},
	"expert": {"min": 1.5, "eat": 1.0, "margin": 0.5, "max": 3.0, "spacing": 4.0, "share": 0.08},
}


## Returns {"t": note times, "d": hold durations (0 = tap), "ev": events}.
static func generate(song: Dictionary, diff: String, length: float) -> Dictionary:
	var c := _generate(song, diff, length)
	c["l"] = assign_lanes(song, c.t)
	return c


static func _generate(song: Dictionary, diff: String, length: float) -> Dictionary:
	if diff == "twist":
		return _twist(song, length)
	var times := generate_taps(song, diff, length)
	var hc: Dictionary = HOLDS.get(diff, HOLDS.normal)
	var bpm := float(song.get("bpm", 120.0))
	var beat := 60.0 / bpm
	var offset := float(song.get("offset", 0.0))
	var grid: Array = song.get("grid", [])
	var energy: Array = song.get("energy", [])
	var end_t := float(song.get("end", length))
	if end_t <= 0.0:
		end_t = length
	var slot := beat / 4.0
	var mid: Array = song.get("mid", [])

	var cands: Array = []
	for i in times.size():
		var g_start := int(roundf((times[i] - offset) / slot))
		if posmod(g_start, 4) != 0:
			continue  # holds start on a beat
		var bar := int((times[i] - offset) / (beat * 4.0))
		var e := float(energy[bar]) if bar >= 0 and bar < energy.size() else 0.6
		if e < 0.2:
			continue
		var nxt := times[i + 1] if i + 1 < times.size() else end_t
		var gap := (nxt - times[i]) / beat
		var natural := gap >= float(hc.min)
		var dur_beats := minf(gap - float(hc.margin), float(hc.max)) if natural else float(hc.eat)
		var sustain := 0.0
		if not mid.is_empty() and g_start < mid.size():
			# Follow the music: how long does the sound that starts here keep ringing?
			var level := maxf(float(mid[g_start]), float(mid[mini(g_start + 1, mid.size() - 1)]))
			if level > 0.25:
				var ring := 0
				var limit_slots := int((minf(gap - float(hc.margin), float(hc.max)) if natural else float(hc.max)) * 4.0)
				while ring < limit_slots and g_start + ring + 1 < mid.size() and float(mid[g_start + ring + 1]) >= level * 0.6:
					ring += 1
				var ring_beats := floorf(ring / 2.0) * 0.5  # snap to half beats
				if ring_beats >= 1.0:
					sustain = ring_beats / float(hc.max)
					dur_beats = ring_beats if not natural else minf(dur_beats, maxf(ring_beats, 1.0))
		if dur_beats < 0.75 or times[i] + (dur_beats + float(hc.margin)) * beat > end_t:
			continue
		# busy-ness of the music under the hold
		var busy := 0.0
		var n := 0
		for g in range(g_start + 1, mini(g_start + int(dur_beats * 4.0) + 1, grid.size())):
			busy += float(grid[g])
			n += 1
		busy = busy / n if n > 0 else 0.3
		var score := (1.0 - busy) + (0.5 if natural else 0.0) + (0.2 if posmod(g_start, 16) == 0 else 0.0) + sustain * 1.5
		cands.append([score, i, dur_beats * beat])
	cands.sort_custom(func(x, y): return x[0] > y[0])

	var durs := PackedFloat64Array()
	durs.resize(times.size())
	durs.fill(0.0)
	var removed := {}
	var starts: Array[float] = []
	var limit := maxi(1, int(times.size() * float(hc.share)))
	for c in cands:
		if starts.size() >= limit:
			break
		var i: int = c[1]
		if removed.has(i):
			continue
		var t0 := times[i]
		var t_end: float = t0 + c[2] + float(hc.margin) * beat
		var ok := true
		for st in starts:
			if absf(st - t0) < float(hc.spacing) * beat:
				ok = false
				break
		# don't swallow the start of another hold
		var j := i + 1
		while ok and j < times.size() and times[j] < t_end - 0.001:
			if durs[j] > 0.0:
				ok = false
			j += 1
		if not ok:
			continue
		durs[i] = c[2]
		starts.append(t0)
		j = i + 1
		while j < times.size() and times[j] < t_end - 0.001:
			removed[j] = true
			j += 1

	var out_t := PackedFloat64Array()
	var out_d := PackedFloat64Array()
	for i in times.size():
		if not removed.has(i):
			out_t.append(times[i])
			out_d.append(durs[i])
	return {"t": out_t, "d": out_d, "ev": []}


# Chaos chart (id "twist"): the Hard chart plus a surprise every 8 bars, announced one bar ahead,
# and "Larry interrupts" where Larry blocks the view and you play by ear.
const TWISTS := [
	["speed", 1.5, "SPEED UP!"], ["mirror", true, "MIRROR!"], ["speed", 1.0, "NORMAL SPEED"],
	["fade", true, "FADE OUT! Feel the beat"], ["mirror", false, "FLIP BACK!"], ["fade", false, "LIGHTS ON"],
	["speed", 0.7, "SLOW MOTION"], ["speed", 1.0, "BACK TO NORMAL"],
]


static func _twist(song: Dictionary, length: float) -> Dictionary:
	var base := _generate(song, "hard", length)
	var beat := 60.0 / float(song.get("bpm", 120.0))
	var bar := beat * 4.0
	var offset := float(song.get("offset", 0.0))
	var end_t := float(song.get("end", length))
	if end_t <= 0.0:
		end_t = length
	var energy: Array = song.get("energy", [])
	var events: Array = []
	var k := 0
	var b := 8
	while offset + b * bar < end_t - 2.0 * bar:
		# skip quiet bars, a twist should land when the music is going
		if b < energy.size() and float(energy[b]) < 0.2:
			b += 1
			continue
		var t := offset + b * bar
		var tw: Array = TWISTS[k % TWISTS.size()]
		events.append({"t": snappedf(t - bar, 0.001), "type": "text", "v": tw[2]})
		events.append({"t": snappedf(t, 0.001), "type": tw[0], "v": tw[1]})
		k += 1
		b += 8
	# Larry interrupts: halfway between twists (every other gap), Larry jumps in front of the
	# lane for 2 bars and you keep the beat by ear. Only steady on-beat notes in there.
	var larry_windows: Array = []
	b = 12
	while offset + (b + LARRY_BARS) * bar < end_t - bar:
		if b < energy.size() and float(energy[b]) < 0.3:
			b += 1
			continue
		var t0 := offset + b * bar
		events.append({"t": snappedf(t0, 0.001), "type": "larry", "v": LARRY_BARS})
		larry_windows.append([t0 - beat * 0.5, t0 + LARRY_BARS * bar])
		b += 16
	events.sort_custom(func(x, y): return float(x.t) < float(y.t))
	# leave room around each twist
	var t_out := PackedFloat64Array()
	var d_out := PackedFloat64Array()
	var src_t: PackedFloat64Array = base.t
	var src_d: PackedFloat64Array = base.d
	for i in src_t.size():
		var clear := true
		for ev in events:
			if ev.type != "text" and ev.type != "larry" and src_t[i] > ev.t - beat * 0.5 and src_t[i] < ev.t + beat:
				clear = false
				break
		var dur := src_d[i]
		for w in larry_windows:
			if src_t[i] + dur > w[0] and src_t[i] < w[1]:
				var g := roundi((src_t[i] - offset) / (beat / 4.0))
				if posmod(g, 4) != 0:
					clear = false        # by ear: quarter notes only
				dur = 0.0                # and no holds you can't see
		if clear:
			t_out.append(src_t[i])
			d_out.append(dur)
	return {"t": t_out, "d": d_out, "ev": events}


const LARRY_BARS := 2


## Two light switches: which switch (0 = top / up, 1 = bottom / down) each note goes to.
## Kick-like hits (beats 1 and 3) go down, snare-like hits (2 and 4) go up, off-beats follow
## the music (mid-range sounds up, low hits down) and fast 16th runs alternate like drumming.
static func assign_lanes(song: Dictionary, t: PackedFloat64Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(t.size())
	var beat := 60.0 / float(song.get("bpm", 120.0))
	var offset := float(song.get("offset", 0.0))
	var slot := beat / 4.0
	var grid: Array = song.get("grid", [])
	var mid: Array = song.get("mid", [])
	var prev := 1
	var run := 0
	for i in t.size():
		var g := roundi((t[i] - offset) / slot)
		var s := posmod(g, 16)
		var lane := 1
		var gap := t[i] - t[i - 1] if i > 0 else 99.0
		if i > 0 and gap <= slot * 1.05:
			lane = 1 - prev
		elif s % 8 == 0:
			lane = 1
		elif s % 8 == 4:
			lane = 0
		elif g >= 0 and g < grid.size() and g < mid.size():
			lane = 0 if float(mid[g]) >= float(grid[g]) * 0.8 else 1
		else:
			lane = 1 - prev
		if lane == prev and gap < beat * 1.01:
			run += 1
			if run >= 4:
				lane = 1 - prev
				run = 0
		else:
			run = 0
		out[i] = lane
		prev = lane
	return out


static func generate_taps(song: Dictionary, diff: String, length: float) -> PackedFloat64Array:
	var cfg: Dictionary = CONFIG.get(diff, CONFIG.normal)
	var bpm := float(song.get("bpm", 120.0))
	var offset := float(song.get("offset", 0.0))
	var beat := 60.0 / bpm
	var slot_len := beat / 4.0
	var grid: Array = song.get("grid", [])
	var energy: Array = song.get("energy", [])
	var start_t := float(song.get("start", 0.0))
	var end_t := float(song.get("end", length))
	if end_t <= 0.0:
		end_t = length

	var step: int = cfg.step
	var gap: int = cfg.gap
	# Fast songs: spread the dense difficulties out so they stay playable.
	if bpm >= 150.0 and step < 4:
		step *= 2
		gap *= 2
	var lo: int = cfg.lo
	var hi: int = cfg.hi
	var need: float = cfg.need
	var has_analysis := not grid.is_empty()

	var bars := int(ceil((end_t - offset) / (beat * 4.0)))
	var picked: Array[int] = []

	for bar in bars:
		var bar_t := offset + bar * beat * 4.0
		if bar_t + beat * 4.0 < start_t or bar_t > end_t:
			continue
		var e := 0.6
		if bar < energy.size():
			e = float(energy[bar])
		if has_analysis and e < 0.08:
			continue  # quiet bar: give the player a breather
		var target := roundi(lerpf(lo, hi, clampf(e, 0.0, 1.0)))

		var cands: Array = []
		for s in range(0, 16, step):
			var g := bar * 16 + s
			var t := offset + g * slot_len
			if t < start_t - 0.05 or t > end_t - 0.05 or t < 0.5:
				continue
			var strength := 0.0
			if g < grid.size():
				strength = float(grid[g])
			if has_analysis and s % 4 != 0 and strength < need:
				continue  # don't put off-beat notes where nothing happens in the music
			if has_analysis and s % 4 == 0 and strength < 0.05 and s != 0:
				continue
			cands.append([strength + slot_bonus(s), g])
		cands.sort_custom(func(a, b): return a[0] > b[0])

		var accepted: Array[int] = []
		for c in cands:
			if accepted.size() >= target:
				break
			var g: int = c[1]
			var ok := true
			for other in accepted:
				if absi(other - g) < gap:
					ok = false
					break
			if ok and not picked.is_empty() and g - picked[-1] < gap:
				ok = false
			if ok:
				accepted.append(g)
		accepted.sort()
		picked.append_array(accepted)

	# Limit long 16th runs.
	var run_max: int = cfg.run
	var final: Array[int] = []
	var run := 1
	for g in picked:
		if not final.is_empty() and g - final[-1] == 1:
			run += 1
			if run_max > 0 and run > run_max:
				continue
		else:
			run = 1
		final.append(g)

	var out := PackedFloat64Array()
	for g in final:
		out.append(offset + g * slot_len)
	return out


## Parses a custom chart from song.json. Either an array of notes, or {"notes": [...], "events": [...]}.
## A note is a time (tap) or [time, duration] (hold).
static func from_json(data) -> Dictionary:
	var arr: Array = []
	var ev: Array = []
	if data is Dictionary:
		arr = data.get("notes", [])
		ev = data.get("events", []).duplicate(true)
	elif data is Array:
		arr = data
	var t := PackedFloat64Array()
	var d := PackedFloat64Array()
	var l := PackedInt32Array()
	var has_lanes := false
	for e in arr:
		if e is Array:
			t.append(float(e[0]))
			d.append(float(e[1]) if e.size() > 1 else 0.0)
			l.append(int(e[2]) if e.size() > 2 else 0)
			has_lanes = has_lanes or e.size() > 2
		else:
			t.append(float(e))
			d.append(0.0)
			l.append(0)
	ev.sort_custom(func(a, b): return float(a.t) < float(b.t))
	var c := {"t": t, "d": d, "ev": ev}
	if has_lanes:
		c["l"] = l      # charts without lanes get them assigned by Library.get_chart
	return c


static func to_json(chart: Dictionary) -> Dictionary:
	var out := []
	var t: PackedFloat64Array = chart.t
	var d: PackedFloat64Array = chart.d
	var l: PackedInt32Array = chart.get("l", PackedInt32Array())
	var lanes := l.size() == t.size()
	for i in t.size():
		if lanes:
			out.append([snappedf(t[i], 0.001), snappedf(d[i], 0.001), l[i]])
		elif d[i] > 0.0:
			out.append([snappedf(t[i], 0.001), snappedf(d[i], 0.001)])
		else:
			out.append(snappedf(t[i], 0.001))
	return {"notes": out, "events": chart.get("ev", [])}


## Snaps a chart to the 16th-note grid (used for recorded charts). Holds snap their end too.
static func quantize_chart(chart: Dictionary, bpm: float, offset: float) -> Dictionary:
	var slot := 60.0 / bpm / 4.0
	var t := PackedFloat64Array()
	var d := PackedFloat64Array()
	var last := -1.0
	var src_t: PackedFloat64Array = chart.t
	var src_d: PackedFloat64Array = chart.d
	for i in src_t.size():
		var q := offset + roundf((src_t[i] - offset) / slot) * slot
		if q <= last + 0.001:
			continue
		var dur := 0.0
		if src_d[i] > 0.0:
			var qe := offset + roundf((src_t[i] + src_d[i] - offset) / slot) * slot
			dur = maxf(0.0, qe - q)
			if dur < slot * 2.0:
				dur = 0.0
		t.append(q)
		d.append(dur)
		last = q
	return {"t": t, "d": d, "ev": chart.get("ev", [])}


## Snaps times to the nearest 16th of the song's grid (used for recorded charts).
static func quantize(times: PackedFloat64Array, bpm: float, offset: float) -> PackedFloat64Array:
	var slot := 60.0 / bpm / 4.0
	var out := PackedFloat64Array()
	var last := -1.0
	for t in times:
		var q := offset + roundf((t - offset) / slot) * slot
		if q > last + 0.001:
			out.append(q)
			last = q
	return out
