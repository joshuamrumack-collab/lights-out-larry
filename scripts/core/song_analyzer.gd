class_name SongAnalyzer
extends RefCounted
## Listens to a song offline and works out what the charts need:
##   bpm, offset (time of the first downbeat), start/end of the music,
##   energy per bar (0..1) and onset strength per 16th-note slot (0..1).
## Safe to run on a Thread. Poll `progress` (0..1) from the main thread.

const RATE_SCALE := 4.0     # decode 4x faster than real time = cheap downsampling
const HOP := 256            # analysis frame size in decoded samples (~23 ms)
const MIN_BPM := 70.0
const MAX_BPM := 180.0

var progress: float = 0.0
var fps: float = 0.0
var length: float = 0.0
var onset := PackedFloat32Array()      # combined onset envelope, normalised
var low_onset := PackedFloat32Array()  # kick-ish band only
var high_onset := PackedFloat32Array() # hats / snares / vocals consonants
var full_onset := PackedFloat32Array()
var full_energy := PackedFloat32Array()
var mid_energy := PackedFloat32Array()   # 250 Hz - 3 kHz: vocals, pads, synths (sustained sounds)


func analyze(stream: AudioStream) -> Dictionary:
	_decode(stream)
	if onset.size() < 200:
		return {}
	progress = 0.65
	var coarse := _coarse_tempo()
	progress = 0.8
	var fine := _fine_tempo(coarse)
	# Slow results are often half the real tempo: prefer the double if the beat holds up there.
	if float(fine.bpm) < 90.0 and float(fine.bpm) * 2.0 <= MAX_BPM:
		var dbl := _fine_tempo(float(fine.bpm) * 2.0)
		if float(dbl.score) >= float(fine.score) * 0.75:
			fine = dbl
	progress = 0.9
	var bpm: float = fine.bpm
	var beat := 60.0 / bpm
	var first_beat: float = fine.phase / fps
	var offset := _pick_downbeat(first_beat, beat)
	var result := build(bpm, offset)
	progress = 1.0
	return result


## Builds the song data for a given bpm/offset. Call again after the user tweaks timing.
func build(bpm: float, offset: float) -> Dictionary:
	var beat := 60.0 / bpm
	var se := _music_bounds()
	return {
		"bpm": snappedf(bpm, 0.01),
		"offset": snappedf(offset, 0.0001),
		"start": snappedf(se.x, 0.01),
		"end": snappedf(se.y, 0.01),
		"length": snappedf(length, 0.01),
		"energy": _bar_energy(offset, beat),
		"grid": _grid_strength(offset, beat),
		"mid": _mid_level(offset, beat),
	}


# ---------------------------------------------------------------- decoding

func _decode(stream: AudioStream) -> void:
	length = stream.get_length()
	var rate := AudioServer.get_mix_rate() / RATE_SCALE
	fps = rate / HOP
	var hops := int(length * rate / HOP)
	if hops <= 0:
		return
	var pb := stream.instantiate_playback()
	pb.start(0.0)

	var e_full := PackedFloat32Array()
	var e_low := PackedFloat32Array()
	var e_high := PackedFloat32Array()
	e_full.resize(hops)
	e_low.resize(hops)
	e_high.resize(hops)

	var a := 1.0 - exp(-TAU * 160.0 / rate)
	var a_lo := 1.0 - exp(-TAU * 250.0 / rate)
	var a_hi := 1.0 - exp(-TAU * 3000.0 / rate)
	var lp := 0.0
	var lp_lo := 0.0
	var lp_hi := 0.0
	var e_mid := PackedFloat32Array()
	e_mid.resize(hops)
	for h in hops:
		var buf: PackedVector2Array = pb.mix_audio(RATE_SCALE, HOP)
		var ef := 0.0
		var el := 0.0
		var eh := 0.0
		var em := 0.0
		for v in buf:
			var x := (v.x + v.y) * 0.5
			lp += a * (x - lp)
			lp_lo += a_lo * (x - lp_lo)
			lp_hi += a_hi * (x - lp_hi)
			var hp := x - lp
			var md := lp_hi - lp_lo
			ef += x * x
			el += lp * lp
			eh += hp * hp
			em += md * md
		e_full[h] = ef / HOP
		e_low[h] = el / HOP
		e_high[h] = eh / HOP
		e_mid[h] = sqrt(em / HOP)
		if h % 128 == 0:
			progress = 0.6 * float(h) / hops
	pb.stop()
	full_energy = e_full
	mid_energy = e_mid

	# Onset = positive change in log energy, per band. Each band is normalised on its own
	# so quiet hi-hats still register next to loud kicks.
	var of := PackedFloat32Array()
	var ol := PackedFloat32Array()
	var oh := PackedFloat32Array()
	of.resize(hops)
	ol.resize(hops)
	oh.resize(hops)
	var pf := log(e_full[0] + 1e-7)
	var pl := log(e_low[0] + 1e-7)
	var ph := log(e_high[0] + 1e-7)
	for h in range(1, hops):
		var lf := log(e_full[h] + 1e-7)
		var ll := log(e_low[h] + 1e-7)
		var lh := log(e_high[h] + 1e-7)
		of[h] = maxf(0.0, lf - pf) * sqrt(e_full[h])
		ol[h] = maxf(0.0, ll - pl) * sqrt(e_low[h])
		oh[h] = maxf(0.0, lh - ph) * sqrt(e_high[h])
		pf = lf
		pl = ll
		ph = lh
	var nf := _normalise(_remove_local_mean(of, 8))
	low_onset = _normalise(_remove_local_mean(ol, 8))
	high_onset = _normalise(_remove_local_mean(oh, 8))
	onset.resize(hops)
	for h in hops:
		onset[h] = 0.35 * nf[h] + 0.4 * low_onset[h] + 0.25 * high_onset[h]
	full_onset = nf


func _remove_local_mean(a: PackedFloat32Array, radius: int) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var sum := 0.0
	var count := 0
	# running window [h - radius, h + radius]
	for i in mini(radius, n):
		sum += a[i]
		count += 1
	for h in n:
		var add := h + radius
		if add < n:
			sum += a[add]
			count += 1
		var rem := h - radius - 1
		if rem >= 0:
			sum -= a[rem]
			count -= 1
		out[h] = maxf(0.0, a[h] - sum / maxf(1.0, count))
	return out


func _normalise(a: PackedFloat32Array) -> PackedFloat32Array:
	var ref := _percentile(a, 0.98)
	if ref <= 0.0:
		return a
	var out := PackedFloat32Array()
	out.resize(a.size())
	for i in a.size():
		out[i] = minf(1.0, a[i] / ref)
	return out


func _percentile(a: PackedFloat32Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return s[clampi(int(p * (s.size() - 1)), 0, s.size() - 1)]


func _sample(a: PackedFloat32Array, pos: float) -> float:
	var i := int(pos)
	if i < 0 or i + 1 >= a.size():
		return 0.0
	var f := pos - i
	return a[i] * (1.0 - f) + a[i + 1] * f


# ---------------------------------------------------------------- tempo

## Coarse tempo: comb filter at every whole BPM in range (Suno songs are nearly always whole BPMs).
func _coarse_tempo() -> float:
	var best_bpm := 120.0
	var best := -1.0
	var bpm := MIN_BPM
	while bpm <= MAX_BPM:
		var r := _comb(bpm, 1.0)
		# Mild preference for common tempos around 120.
		var octave := log(bpm / 120.0) / log(2.0)
		var w := exp(-0.5 * pow(octave / 1.2, 2.0))
		if r.score * w > best:
			best = r.score * w
			best_bpm = bpm
		bpm += 1.0
	return best_bpm


## Comb filter: for tempos near the coarse guess, find tempo + phase where beats land on onsets.
func _fine_tempo(coarse: float) -> Dictionary:
	var best := {"bpm": coarse, "phase": 0.0, "score": -1.0}
	var bpm := coarse - 1.0
	while bpm <= coarse + 1.0:
		var r := _comb(bpm, 0.5)
		if r.score > best.score:
			best = r
		bpm += 0.05
	# Suno tracks are almost always on whole-number tempos; snap if it's nearly as good.
	var whole := roundf(best.bpm)
	var rw := _comb(whole, 0.5)
	if rw.score >= best.score * 0.995:
		best = rw
	# Refine phase.
	var p0: float = best.phase
	var refined: Dictionary = best
	var p := p0 - 0.5
	while p <= p0 + 0.5:
		var s := _comb_score(best.bpm, p)
		if s > refined.score:
			refined = {"bpm": best.bpm, "phase": p, "score": s}
		p += 0.05
	return refined


func _comb(bpm: float, step: float) -> Dictionary:
	var period := fps * 60.0 / bpm
	var best_phase := 0.0
	var best := -1.0
	var p := 0.0
	while p < period:
		var s := _comb_score(bpm, p)
		if s > best:
			best = s
			best_phase = p
		p += step
	return {"bpm": bpm, "phase": best_phase, "score": best}


func _comb_score(bpm: float, phase: float) -> float:
	var period := fps * 60.0 / bpm
	var s := 0.0
	var pos := phase
	var count := 0
	var n := onset.size() - 1
	while pos < n:
		s += _sample(onset, pos)
		# off-beat 8ths count a bit too, helps lock syncopated tracks
		s += 0.25 * _sample(onset, pos + period * 0.5)
		pos += period
		count += 1
	return s / maxf(1.0, count)


## Chooses which of the 4 beats in a bar is the downbeat (strongest kicks), returns its first time >= 0.
func _pick_downbeat(first_beat: float, beat: float) -> float:
	var sums := [0.0, 0.0, 0.0, 0.0]
	var k := 0
	var t := first_beat
	while t * fps < low_onset.size() - 1:
		var v := maxf(_sample(low_onset, t * fps), _sample(onset, t * fps) * 0.5)
		sums[k % 4] += v
		k += 1
		t += beat
	# Kicks usually land on beats 1 and 3, so compare pairs, then pick the stronger of the pair.
	var pair_a: float = sums[0] + sums[2]
	var pair_b: float = sums[1] + sums[3]
	var idx := 0
	if pair_a >= pair_b:
		idx = 0 if sums[0] >= sums[2] else 2
	else:
		idx = 1 if sums[1] >= sums[3] else 3
	var offset := first_beat + idx * beat
	return fposmod(offset, beat * 4.0)


# ---------------------------------------------------------------- structure

func _music_bounds() -> Vector2:
	var ref := _percentile(full_energy, 0.95)
	var thresh := ref * 0.02
	var s := 0
	while s < full_energy.size() and full_energy[s] < thresh:
		s += 1
	var e := full_energy.size() - 1
	while e > s and full_energy[e] < thresh:
		e -= 1
	return Vector2(s / fps, e / fps)


func _bar_energy(offset: float, beat: float) -> Array:
	var bar_len := beat * 4.0
	var bars := int(ceil((length - offset) / bar_len))
	var raw := PackedFloat32Array()
	raw.resize(bars)
	for b in bars:
		var h0 := int((offset + b * bar_len) * fps)
		var h1 := mini(int((offset + (b + 1) * bar_len) * fps), full_energy.size())
		var s := 0.0
		for h in range(maxi(h0, 0), h1):
			s += sqrt(full_energy[h])
		raw[b] = s / maxf(1.0, h1 - h0)
	var lo := _percentile(raw, 0.1)
	var hi := _percentile(raw, 0.95)
	var out := []
	for v in raw:
		out.append(snappedf(clampf((v - lo * 0.5) / maxf(1e-6, hi - lo * 0.5), 0.0, 1.0), 0.01))
	return out


## Mid-band loudness per 16th slot (0..1). Steady values over several slots = a held sound.
func _mid_level(offset: float, beat: float) -> Array:
	var slot := beat / 4.0
	var slots := int((length - offset) / slot)
	var ref := _percentile(mid_energy, 0.95)
	var out := []
	for i in slots:
		var h0 := int((offset + i * slot) * fps)
		var h1 := maxi(h0 + 1, int((offset + (i + 1) * slot) * fps))
		var s := 0.0
		var n := 0
		for h in range(maxi(h0, 0), mini(h1, mid_energy.size())):
			s += mid_energy[h]
			n += 1
		out.append(snappedf(clampf(s / maxf(1, n) / maxf(ref, 1e-6), 0.0, 1.0), 0.01))
	return out


func _grid_strength(offset: float, beat: float) -> Array:
	var slot := beat / 4.0
	var slots := int((length - offset) / slot)
	var out := []
	for i in slots:
		var c := (offset + i * slot) * fps
		var v := 0.0
		for d in [-1.0, 0.0, 1.0]:
			v = maxf(v, maxf(_sample(full_onset, c + d), maxf(_sample(low_onset, c + d), 0.8 * _sample(high_onset, c + d))))
		out.append(snappedf(v, 0.01))
	return out
