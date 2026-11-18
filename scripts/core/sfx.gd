class_name Sfx
extends RefCounted
## Procedurally generated sounds, so the project ships without any audio assets.

const RATE := 44100

static var _cache: Dictionary = {}


## A short percussive tick. Higher freq = brighter.
static func click(freq: float = 1800.0, dur: float = 0.06, vol: float = 0.7) -> AudioStreamWAV:
	var key := "click_%d_%d_%d" % [int(freq), int(dur * 1000), int(vol * 100)]
	if _cache.has(key):
		return _cache[key]
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 55.0)
		var s := (sin(TAU * freq * t) * 0.7 + sin(TAU * freq * 2.01 * t) * 0.3) * env * vol
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var w := _wav(data)
	_cache[key] = w
	return w


## A metronome track: `beats` clicks at `bpm`, starting at `start` seconds. Downbeats are higher.
static func metronome(bpm: float, beats: int, start: float = 1.0) -> AudioStreamWAV:
	var beat := 60.0 / bpm
	var total := start + beats * beat + 0.5
	var n := int(total * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var click_len := int(0.05 * RATE)
	for b in beats:
		var freq := 2000.0 if b % 4 == 0 else 1400.0
		var s0 := int((start + b * beat) * RATE)
		for i in click_len:
			var idx := s0 + i
			if idx >= n:
				break
			var t := float(i) / RATE
			var s := sin(TAU * freq * t) * exp(-t * 60.0) * 0.8
			data.encode_s16(idx * 2, int(s * 32767.0))
	return _wav(data)


# ---------------------------------------------------------------- hit sounds

const HIT_STYLES := ["switch", "soft", "kick", "clap", "chime", "off"]
const HIT_NAMES := {"switch": "Light switch", "soft": "Soft tap", "kick": "Kick", "clap": "Clap", "chime": "Rising chime", "off": "Off"}
# Major pentatonic steps (semitones), used by the rising chime and the milestone sounds.
const PENTA := [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24]


## step only matters for "chime": higher steps = higher notes (climbs with your combo).
static func hit(style: String, step: int = 0) -> AudioStreamWAV:
	var key := "hit_%s_%d" % [style, step if style == "chime" else (step % 2 if style == "switch" else 0)]
	if _cache.has(key):
		return _cache[key]
	var w: AudioStreamWAV
	match style:
		"switch":
			w = light_switch(step % 2 == 0)
		"soft":
			w = _render(0.06, func(t: float) -> float:
				# warm wooden tap: falling sine + tiny filtered click
				var f := 380.0 + 260.0 * exp(-t * 90.0)
				return sin(TAU * f * t) * exp(-t * 70.0) * 0.55 + _noise() * exp(-t * 900.0) * 0.08)
		"kick":
			w = _render(0.12, func(t: float) -> float:
				var phase := TAU * (55.0 * t + 90.0 * (1.0 - exp(-t * 35.0)) / 35.0)
				return sin(phase) * exp(-t * 28.0) * 0.8)
		"clap":
			w = _render(0.12, func(t: float) -> float:
				var env := 0.0
				for k in 3:
					var tk := t - k * 0.009
					if tk >= 0.0:
						env = maxf(env, exp(-tk * (180.0 if k < 2 else 38.0)))
				return _noise() * env * 0.35)
		"chime":
			var semis: int = PENTA[clampi(step, 0, PENTA.size() - 1)]
			var f0 := 659.25 * pow(2.0, semis / 12.0)  # from E5
			w = _render(0.25, func(t: float) -> float:
				return (sin(TAU * f0 * t) + 0.35 * sin(TAU * f0 * 2.0 * t) * exp(-t * 20.0)) * exp(-t * 14.0) * 0.32)
		_:
			return null
	_cache[key] = w
	return w


## A bright ascending arpeggio for combo milestones. `size` 0..3 = bigger milestone, more notes.
static func milestone(size: int) -> AudioStreamWAV:
	var key := "milestone_%d" % size
	if _cache.has(key):
		return _cache[key]
	var notes := 3 + size
	var spacing := 0.055
	var w := _render(notes * spacing + 0.5, func(t: float) -> float:
		var v := 0.0
		for i in notes:
			var tt := t - i * spacing
			if tt < 0.0:
				break
			var f := 523.25 * pow(2.0, float(PENTA[mini(i * 2, 10)]) / 12.0)
			v += (sin(TAU * f * tt) + 0.3 * sin(TAU * f * 3.0 * tt) * exp(-tt * 30.0)) * exp(-tt * 7.0) * 0.18
		return v)
	_cache[key] = w
	return w


## Rising "whoosh" when the score multiplier goes up.
static func tier_up() -> AudioStreamWAV:
	if _cache.has("tier"):
		return _cache.tier
	var w := _render(0.35, func(t: float) -> float:
		var f := 300.0 + 1500.0 * t * t / 0.12
		var env := sin(PI * clampf(t / 0.35, 0.0, 1.0))
		return (sin(TAU * f * t) * 0.25 + _noise() * 0.12) * env * 0.5)
	_cache.tier = w
	return w


## Soft low "thunk" when a big combo breaks.
static func combo_break() -> AudioStreamWAV:
	if _cache.has("break"):
		return _cache["break"]
	var w := _render(0.35, func(t: float) -> float:
		var f := 220.0 * exp(-t * 4.0)
		return sin(TAU * f * t) * exp(-t * 9.0) * 0.4 + _noise() * exp(-t * 40.0) * 0.06)
	_cache["break"] = w
	return w


static var _noise_state := 22222
## A plastic rocker light switch: a sharp snap, the hollow ring of the switch plate, a soft
## thunk from the wall box and a tiny contact bounce. "Up" and "down" sound slightly different,
## so flicking on and off alternates like the real thing.
static func light_switch(up: bool) -> AudioStreamWAV:
	var n := int(0.09 * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var k := 1.0 if up else 0.86          # down-flicks are a touch lower
	var bounce := 0.0065 if up else 0.0085
	var prev := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var nz := _noise()
		var hp := nz - prev                # crude high-pass: a bright snap
		prev = nz
		lp += (nz - lp) * 0.25             # duller noise for the thunk
		var v := 0.0
		# main snap
		v += hp * exp(-t / 0.0011) * 0.55
		v += sin(TAU * 2650.0 * k * t) * exp(-t * 650.0) * 0.32
		v += sin(TAU * 4400.0 * k * t) * exp(-t * 950.0) * 0.16
		v += sin(TAU * 1300.0 * k * t + 0.6) * exp(-t * 380.0) * 0.22
		# wall-box thunk
		v += sin(TAU * (170.0 * k) * t) * exp(-t * 110.0) * 0.28
		v += lp * exp(-t * 160.0) * 0.18
		# contact bounce, a few ms later
		var tb := t - bounce
		if tb >= 0.0:
			v += hp * exp(-tb / 0.0008) * 0.22
			v += sin(TAU * 3100.0 * k * tb) * exp(-tb * 900.0) * 0.12
		if i > n - 160:
			v *= float(n - i) / 160.0
		data.encode_s16(i * 2, int(clampf(v * 0.75, -1.0, 1.0) * 32767.0))
	return _wav(data)


static func _noise() -> float:
	_noise_state = (_noise_state * 1103515245 + 12345) & 0x7fffffff
	return float(_noise_state) / 1073741823.5 - 1.0


static func _render(dur: float, fn: Callable) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var fade := int(0.004 * RATE)
	for i in n:
		var v: float = fn.call(float(i) / RATE)
		if i > n - fade:
			v *= float(n - i) / fade
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	return _wav(data)


static func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
