#!/usr/bin/env python3
"""Lights Out, Larry! - auto-beatmap draft tool.

Listens to a Suno track, finds the beats and the hits, and writes a draft chart for every
difficulty (easy, normal, hard, expert, chaos). Open the song in the game's chart editor
afterwards and hand-tune the drafts instead of building charts from scratch.

Usage
    python auto_chart.py SONG                  # SONG = a song folder (songs/<id>/) or an audio file
    python auto_chart.py SONG --preview        # also writes preview_<difficulty>.wav with clicks
    python auto_chart.py SONG --only hard expert
    python auto_chart.py SONG --new-tempo      # detect the tempo again (default: use song.json's)
    python auto_chart.py SONG --dry-run        # just print what it would make

With a song folder, the drafts go straight into that song.json under "charts" (a backup is
saved as song.json.bak first). With a plain audio file, a new folder is created next to it
with audio + song.json, ready to copy into the game's songs folder.

Needs: pip install librosa soundfile numpy
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

import numpy as np

try:
    import librosa
except ImportError:
    sys.exit("librosa is missing. Install it with:  pip install librosa soundfile numpy")

SR = 22050
HOP = 256
DIFFS = ["easy", "normal", "hard", "expert", "twist"]          # "twist" is shown as Chaos in the game
NAMES = {"twist": "chaos"}

# Same ideas as the game's own generator (scripts/core/chart_gen.gd):
#   step  - which 16th slots are allowed (4 = quarters, 2 = 8ths, 1 = 16ths)
#   gap   - minimum distance between notes, in 16ths
#   lo/hi - notes per bar in the quietest / loudest bars
#   need  - how strong an off-beat hit must be to get a note
#   hold  - (min beats of free time for a hold, max hold beats, share of notes that may be holds)
CONFIG = {
    "easy":   dict(step=4, gap=8, lo=1, hi=2, need=1.00, hold=(3.0, 4.0, 0.22)),
    "normal": dict(step=4, gap=4, lo=2, hi=4, need=1.00, hold=(2.0, 4.0, 0.15)),
    "hard":   dict(step=2, gap=2, lo=3, hi=7, need=0.30, hold=(1.5, 3.0, 0.10)),
    "expert": dict(step=1, gap=1, lo=4, hi=11, need=0.25, hold=(1.5, 3.0, 0.08)),
    "twist":  dict(step=2, gap=2, lo=3, hi=7, need=0.30, hold=(1.5, 3.0, 0.08)),
}
TWISTS = [  # Chaos events, one every 8 bars, announced a bar ahead (same as the game)
    ("speed", 1.5, "SPEED UP!"), ("mirror", True, "MIRROR!"), ("speed", 1.0, "NORMAL SPEED"),
    ("fade", True, "FADE OUT! Feel the beat"), ("mirror", False, "FLIP BACK!"), ("fade", False, "LIGHTS ON"),
    ("speed", 0.7, "SLOW MOTION"), ("speed", 1.0, "BACK TO NORMAL"),
]
LARRY_BARS = 2


# ----------------------------------------------------------------------------- analysis

def analyse(path: Path, bpm: float | None = None, offset: float | None = None) -> dict:
    """Beats, a 16th-note grid, and hit strength per slot.
    With bpm/offset (from the game's song.json) the grid matches the game's beat lines exactly;
    without, the beats are detected and the grid follows them."""
    y, sr = librosa.load(str(path), sr=SR, mono=True)
    length = len(y) / sr

    # onset envelopes: everything, the low end (kick/bass) and the mids/highs (snare, claps, vocals)
    mel = librosa.feature.melspectrogram(y=y, sr=sr, hop_length=HOP, n_mels=64, fmax=8000)
    db = librosa.power_to_db(mel)
    env = librosa.onset.onset_strength(S=db, sr=sr, hop_length=HOP)
    env_low = librosa.onset.onset_strength(S=db[:8], sr=sr, hop_length=HOP)      # ~ < 200 Hz
    env_high = librosa.onset.onset_strength(S=db[24:], sr=sr, hop_length=HOP)   # ~ > 1 kHz
    rms = librosa.feature.rms(y=y, hop_length=HOP)[0]

    if bpm:
        beat = 60.0 / bpm
        first = offset % (beat * 4) if offset is not None else 0.0
        nb = int((length - first) / beat) + 1
        beats = first + np.arange(nb) * beat
        return _finish(y, sr, length, bpm, first, beats, env, env_low, env_high, rms)
    tempo, beats = librosa.beat.beat_track(onset_envelope=env, sr=sr, hop_length=HOP, units="time", tightness=120)
    tempo = float(np.atleast_1d(tempo)[0])
    beats = np.asarray(beats, dtype=float)
    if len(beats) < 8:
        sys.exit(f"Couldn't find a steady beat in {path.name}.")
    # Keep the tempo in a playable range (Suno songs are often detected at half/double speed).
    while tempo < 85:
        tempo *= 2
        beats = np.sort(np.concatenate([beats, (beats[:-1] + beats[1:]) / 2]))
    while tempo > 185:
        tempo /= 2
        beats = beats[::2]
    bpm = round(60.0 / float(np.median(np.diff(beats))), 2)
    beat = 60.0 / bpm

    # Downbeat: the beat phase (0-3) whose beats carry the most low-end punch.
    low_at = np.array([_peak(env_low, t, sr) for t in beats])
    phase = int(np.argmax([low_at[p::4].mean() for p in range(4)]))
    beats = beats[phase:]
    offset = float(beats[0] % (beat * 4))   # first bar line, like the game's song.json "offset"
    return _finish(y, sr, length, bpm, offset, beats, env, env_low, env_high, rms)


def _finish(y, sr, length, bpm, offset, beats, env, env_low, env_high, rms) -> dict:
    beat = 60.0 / bpm
    # 16th-note slots that follow the detected beats (handles small tempo drift).
    slots = []
    for a, b in zip(beats[:-1], beats[1:]):
        slots.extend(a + (b - a) * k / 4 for k in range(4))
    slots.append(beats[-1])
    slots = np.array(slots)

    def norm(v):
        v = np.asarray(v, dtype=float)
        top = np.percentile(v, 98) or 1.0
        return np.clip(v / top, 0, 1)

    strength = norm([_peak(env, t, sr) for t in slots])
    low = norm([_peak(env_low, t, sr) for t in slots])
    high = norm([_peak(env_high, t, sr) for t in slots])
    loud = np.array([rms[min(len(rms) - 1, int(t * sr / HOP))] for t in slots])

    # loudness per bar, 0..1 (quiet intros/breakdowns get fewer notes)
    nbars = len(slots) // 16
    bar_e = np.array([loud[i * 16:(i + 1) * 16].mean() for i in range(nbars)]) if nbars else np.array([0.5])
    bar_e = np.clip((bar_e - np.percentile(bar_e, 10)) / max(1e-6, np.percentile(bar_e, 95) - np.percentile(bar_e, 10)), 0, 1)

    # sustain: how much the sound keeps ringing after a slot (for hold notes)
    sustain = norm(loud)
    return dict(length=length, bpm=bpm, beat=beat, offset=offset, beats_first=float(beats[0]),
                slots=slots, strength=strength, low=low, high=high, bar_e=bar_e, sustain=sustain)


def _peak(env: np.ndarray, t: float, sr: int, win: float = 0.035) -> float:
    a = max(0, int((t - win) * sr / HOP))
    b = min(len(env), int((t + win) * sr / HOP) + 1)
    return float(env[a:b].max()) if b > a else 0.0


# ----------------------------------------------------------------------------- charting

SLOT_BONUS = {0: 0.45, 8: 0.30, 4: 0.18, 12: 0.18}


def make_chart(a: dict, diff: str) -> dict:
    cfg = CONFIG[diff]
    slots, strength = a["slots"], a["strength"]
    n = len(slots)
    chosen: list[int] = []
    for bar in range(n // 16):
        e = a["bar_e"][bar] if bar < len(a["bar_e"]) else 0.5
        if e < 0.05:
            continue
        want = round(cfg["lo"] + (cfg["hi"] - cfg["lo"]) * e)
        cands = []
        for s in range(16):
            g = bar * 16 + s
            if s % cfg["step"]:
                continue
            on_beat = s % 4 == 0
            if not on_beat and strength[g] < cfg["need"] * 0.6:
                continue
            cands.append((strength[g] + SLOT_BONUS.get(s, 0.05 if s % 2 == 0 else 0.0), g))
        cands.sort(reverse=True)
        picked: list[int] = []
        for sc, g in cands:
            if len(picked) >= want:
                break
            if all(abs(g - p) >= cfg["gap"] for p in picked) and (not chosen or g - chosen[-1] >= cfg["gap"]):
                picked.append(g)
        chosen.extend(sorted(picked))
    chosen.sort()

    # holds: long free gap after a note on a beat, where the sound keeps ringing
    hmin, hmax, share = cfg["hold"]
    durs = [0.0] * len(chosen)
    limit = int(len(chosen) * share)
    scored = []
    for i, g in enumerate(chosen):
        if g % 4:
            continue
        nxt = chosen[i + 1] if i + 1 < len(chosen) else n - 1
        free_beats = (nxt - g) / 4
        if free_beats < hmin:
            continue
        ring = a["sustain"][g:nxt].mean() if nxt > g else 0
        scored.append((ring + (0.2 if g % 16 == 0 else 0), i, min(free_beats - 0.5, hmax)))
    scored.sort(reverse=True)
    for _, i, beats_long in scored[:limit]:
        if beats_long >= 1:
            g = chosen[i]
            end = min(len(slots) - 1, g + int(beats_long * 4))
            durs[i] = float(slots[end] - slots[g])

    lanes = assign_lanes(a, chosen)
    events: list[dict] = []
    if diff == "twist":
        chosen, durs, lanes, events = add_chaos(a, chosen, durs, lanes)

    notes = []
    for g, d, l in zip(chosen, durs, lanes):
        notes.append([round(float(slots[g]), 3), round(d, 3), int(l)])
    return {"notes": notes, "events": events}


def assign_lanes(a: dict, chosen: list[int]) -> list[int]:
    """Two-switch mode: low/kick hits go to the bottom switch, snares and highs to the top one,
    fast 16th runs alternate."""
    lanes, prev, run = [], 1, 0
    for i, g in enumerate(chosen):
        s = g % 16
        gap = g - chosen[i - 1] if i else 99
        if i and gap <= 1:
            lane = 1 - prev
        elif s % 8 == 0:
            lane = 1
        elif s % 8 == 4:
            lane = 0
        else:
            lane = 0 if a["high"][g] >= a["low"][g] else 1
        if lane == prev and gap < 4:
            run += 1
            if run >= 4:
                lane, run = 1 - prev, 0
        else:
            run = 0
        lanes.append(lane)
        prev = lane
    return lanes


def add_chaos(a, chosen, durs, lanes):
    """Chaos: a twist every 8 bars (announced a bar ahead) + Larry interrupts, where Larry
    blocks the view for 2 bars and only steady quarter notes are left, played by ear."""
    slots, bar_e = a["slots"], a["bar_e"]
    nbars = len(slots) // 16
    bar_t = lambda b: float(slots[min(len(slots) - 1, b * 16)])
    beat = a["beat"]
    events, k, b = [], 0, 8
    while b < nbars - 2:
        if b < len(bar_e) and bar_e[b] < 0.2:
            b += 1
            continue
        kind, value, text = TWISTS[k % len(TWISTS)]
        events.append({"t": round(bar_t(b - 1), 3), "type": "text", "v": text})
        events.append({"t": round(bar_t(b), 3), "type": kind, "v": value})
        k += 1
        b += 8
    larry = []
    b = 12
    while b + LARRY_BARS < nbars - 1:
        if b < len(bar_e) and bar_e[b] < 0.3:
            b += 1
            continue
        events.append({"t": round(bar_t(b), 3), "type": "larry", "v": LARRY_BARS})
        larry.append((b * 16, (b + LARRY_BARS) * 16))
        b += 16
    events.sort(key=lambda e: e["t"])

    twist_t = [e["t"] for e in events if e["type"] not in ("text", "larry")]
    out = ([], [], [])
    for g, d, l in zip(chosen, durs, lanes):
        t = float(slots[g])
        if any(tt - beat * 0.5 < t < tt + beat for tt in twist_t):
            continue    # leave room around each twist
        in_larry = any(s0 - 2 <= g < s1 for s0, s1 in larry)
        if in_larry:
            if g % 4:
                continue          # by ear: quarter notes only
            d = 0.0               # no holds you can't see
        out[0].append(g)
        out[1].append(d)
        out[2].append(l)
    return out[0], out[1], out[2], events


# ----------------------------------------------------------------------------- output

def write_preview(audio: Path, chart: dict, dest: Path) -> None:
    """Song + a click on every note (higher click = top switch), to check the draft by ear."""
    import soundfile as sf
    y, sr = librosa.load(str(audio), sr=44100, mono=True)
    out = y * 0.6
    for t, d, lane in chart["notes"]:
        f = 2400 if lane == 0 else 1500
        n = int(0.03 * sr)
        tt = np.arange(n) / sr
        click = np.sin(2 * np.pi * f * tt) * np.exp(-tt * 140) * 0.5
        i = int(t * sr)
        if i + n < len(out):
            out[i:i + n] += click
    sf.write(str(dest), np.clip(out, -1, 1), sr)


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-") or "song"


def main() -> None:
    ap = argparse.ArgumentParser(description="Make draft charts for a Lights Out, Larry! song.")
    ap.add_argument("song", type=Path, help="song folder (with song.json) or an audio file")
    ap.add_argument("--only", nargs="+", choices=DIFFS + ["chaos"], help="only these difficulties")
    ap.add_argument("--preview", action="store_true", help="also write preview_<difficulty>.wav with clicks")
    ap.add_argument("--new-tempo", action="store_true", help="detect the tempo again instead of using bpm/offset from song.json")
    ap.add_argument("--dry-run", action="store_true", help="don't write anything")
    args = ap.parse_args()

    src = args.song.resolve()
    if src.is_dir():
        folder = src
        meta_path = folder / "song.json"
        meta = json.loads(meta_path.read_text(encoding="utf-8")) if meta_path.exists() else {}
        audio = folder / meta.get("audio", "") if meta.get("audio") else None
        if not audio or not audio.exists():
            audio = next((p for p in folder.iterdir() if p.suffix.lower() in (".ogg", ".mp3", ".wav", ".m4a")), None)
        if audio is None:
            sys.exit(f"No audio file found in {folder}")
    elif src.is_file():
        audio = src
        title = re.sub(r"[-_]+[0-9a-f]{8}$", "", src.stem).replace("_", " ").strip()
        folder = src.parent / slug(title)
        meta_path = folder / "song.json"
        meta = {"id": folder.name, "title": title, "artist": "DorkTeach", "audio": "audio" + src.suffix.lower(), "charts": {}}
    else:
        sys.exit(f"Not found: {src}")

    diffs = [("twist" if d == "chaos" else d) for d in (args.only or DIFFS)]
    print(f"Listening to {audio.name} ...")
    use_game_tempo = "bpm" in meta and not args.new_tempo
    a = analyse(audio, float(meta["bpm"]), float(meta.get("offset", 0.0))) if use_game_tempo else analyse(audio)
    print(f"  tempo {a['bpm']} BPM, first bar at {a['offset']:.3f}s, {len(a['slots']) // 16} bars")

    if not use_game_tempo:
        meta["bpm"] = a["bpm"]
        meta["offset"] = round(a["offset"], 4)
        meta["length"] = round(a["length"], 2)
        if args.new_tempo:
            # the game's own analysis was made for the old tempo: let the game redo it
            for k in ("grid", "mid", "energy"):
                meta.pop(k, None)
    charts = meta.setdefault("charts", {})
    for d in diffs:
        c = make_chart(a, d)
        charts[d] = c
        holds = sum(1 for n in c["notes"] if n[1] > 0)
        top = sum(1 for n in c["notes"] if n[2] == 0)
        extra = f", {sum(1 for e in c['events'] if e['type'] == 'larry')} Larry interrupts" if d == "twist" else ""
        print(f"  {NAMES.get(d, d):7s} {len(c['notes']):4d} notes ({holds} holds, {top} on the top switch){extra}")
        if args.preview and not args.dry_run:
            folder.mkdir(parents=True, exist_ok=True)
            write_preview(audio, c, folder / f"preview_{NAMES.get(d, d)}.wav")

    if args.dry_run:
        print("Dry run: nothing written.")
        return
    folder.mkdir(parents=True, exist_ok=True)
    if src.is_file():
        shutil.copy(audio, folder / meta["audio"])
    elif meta_path.exists():
        shutil.copy(meta_path, meta_path.with_suffix(".json.bak"))
    meta_path.write_text(json.dumps(meta, indent="\t", ensure_ascii=False), encoding="utf-8")
    print(f"Saved drafts to {meta_path}")
    print("Next: open the song in the game > Edit chart, and tune the drafts by hand.")


if __name__ == "__main__":
    main()
