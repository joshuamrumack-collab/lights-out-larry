class_name PixelRoom
extends RefCounted
## Background: a bedroom where an annoying little brother flicks the light switch every time
## you hit a note. Art is AI-generated pixel art in res://art (rooms + sprites).
## Funny little scenes play out across light and dark; the brother reacts to your misses.

const THEMES := ["gamer", "teen", "cozy", "spooky"]
const THEME_NAMES := {"gamer": "Gamer room", "teen": "Teen room", "cozy": "Cozy room", "spooky": "Spooky room"}

# Layout of each room image (pixels in the room image).
const LAYOUT := {
	"gamer":  {"floor": 207, "bed": [175, 385, 135], "window": [350, 475, 5, 95], "ceil_x": 250, "sib": Vector2(282, 104)},
	"teen":   {"floor": 212, "bed": [185, 385, 135], "window": [400, 525, 0, 110], "ceil_x": 290, "sib": Vector2(204, 112)},
	"cozy":   {"floor": 148, "bed": [190, 410, 78], "window": [290, 390, 8, 60], "ceil_x": 250},
	"spooky": {"floor": 166, "bed": [205, 400, 100], "window": [415, 520, 5, 110], "ceil_x": 300},
}

# Little scenes. size = sprite height as a fraction of the room height.
const SCENES := {
	"cool_cat": {"size": 0.22, "text": "sup", "dur": 4.5},
	"cat_hang": {"size": 0.38, "text": "MEOW?!", "dur": 4.0},
	"dad":      {"size": 0.5, "text": "STOP IT!!", "dur": 3.5},
	"alien":    {"size": 0.3, "text": "hi :)", "dur": 4.0},
	"monster":  {"size": 0.34, "text": "mine!", "dur": 4.0},
	"pizza":    {"size": 0.2, "text": "how?", "dur": 4.0},
	"ghost":    {"size": 0.36, "text": "boo, I guess", "dur": 4.5},
	"trex":     {"size": 0.62, "text": "RAWR!!", "dur": 5.0},
	# the family storms in from the door, fed up with the light show
	"mom":        {"size": 0.74, "text": ["LARRY! BED! NOW!", "I just did my hair!", "The power bill, LARRY!"], "dur": 4.5, "family": true},
	"dad_pj":     {"size": 0.76, "text": ["I have work at 6!", "That's it, no tablet!", "WHO touched the switch?"], "dur": 4.5, "family": true},
	"big_sis":    {"size": 0.72, "text": ["I'm on a CALL!", "you're SO cringe", "MOM, he's doing it again!"], "dur": 4.5, "family": true},
	"little_sis": {"size": 0.52, "text": ["I'm scared of the dark!", "waaaah!", "teddy can't sleep!"], "dur": 4.5, "family": true},
	"grandma":    {"size": 0.68, "text": ["In MY day we had candles!", "I'll call your mother!", "Young man!!"], "dur": 4.5, "family": true},
	"grandpa":    {"size": 0.66, "text": ["Is it a power cut?!", "I brought a candle!", "Who's there?!"], "dur": 4.5, "family": true},
}

const BRO_REPLIES := ["wasn't me!", "hehe", "it's for a game!", "*click*", "the switch did it"]

var theme := "gamer"
var lay: Dictionary
var lit_tex: Texture2D
var dark_tex: Texture2D
var bro := {}          # pose -> [lit, silhouette]
var spr := {}          # scene id -> texture
var sib_tex: Texture2D
var W := 670.0
var H := 215.0

# state
var light_on := true
var light := 1.0
var on_t := -10.0
var flick_t := -10.0
var taunt_t := -10.0
var taunt_pose := "bro_laugh"
var detail := ""
var detail_t := -10.0
var detail_text := ""
var _family_ids: Array = []
var last_detail_t := -10.0
var eyes_t := -10.0
var speech := ""
var speech_t := -10.0
var speech_at := Vector2.ZERO
var disco := 0.0
var rt := 0.0
var debris: Array = []
var _rng := RandomNumberGenerator.new()


func _init(theme_id: String = "gamer") -> void:
	theme = theme_id if theme_id in THEMES else "gamer"
	lay = LAYOUT[theme]
	_rng.randomize()
	lit_tex = load("res://art/rooms/%s_lit.png" % theme)
	dark_tex = load("res://art/rooms/%s_dark.png" % theme)
	W = lit_tex.get_width()
	H = lit_tex.get_height()
	for p in ["bro_switch", "bro_laugh", "bro_angry", "bro_shout", "bro_dance1", "bro_dance2"]:
		bro[p] = [load("res://art/sprites/%s.png" % p), load("res://art/sprites/%s_sil.png" % p)]
	for id in SCENES:
		spr[id] = load("res://art/sprites/%s.png" % id)
		if SCENES[id].get("family", false):
			_family_ids.append(id)
	# (the sleeping-sibling sprite was removed: the family now storms in instead)


static func theme_for_song(song_id: String) -> String:
	return THEMES[absi(song_id.hash()) % THEMES.size()]


# ---------------------------------------------------------------- game hooks

func flip() -> void:
	light_on = not light_on
	flick_t = rt
	if light_on:
		on_t = rt
	if detail == "" and rt - last_detail_t > 2.5 and _rng.randf() < (0.35 if light_on else 0.2):
		# about half of all scenes are a family member barging in
		if _rng.randf() < 0.5:
			detail = _family_ids[_rng.randi() % _family_ids.size()]
		else:
			detail = SCENES.keys()[_rng.randi() % SCENES.size()]
		detail_t = rt
		last_detail_t = rt
		var tx: Variant = SCENES[detail].text
		detail_text = str(tx[_rng.randi() % tx.size()]) if tx is Array else str(tx)
	elif not light_on and _rng.randf() < 0.15 and rt - eyes_t > 2.5:
		eyes_t = rt
	elif light_on and sib_tex and _rng.randf() < 0.12:
		_say(["MOOOM!", "I'm SLEEPING!", "STOP IT!", "ugh...", "I'll tell Dad!"][_rng.randi() % 5], Vector2(lay.sib) + Vector2(36, 0))
	elif light_on and _rng.randf() < 0.07:
		_say(["hehe", "ON!", "again!", "click click!", "I'm the light master"][_rng.randi() % 5], _bro_head())


func taunt() -> void:
	taunt_t = rt
	taunt_pose = ["bro_laugh", "bro_angry", "bro_shout"][_rng.randi() % 3]
	if _rng.randf() < 0.5:
		_say(["missed! hehe", "too slow!", "nyeh nyeh", "haha!"][_rng.randi() % 4], _bro_head())


func _say(t: String, at: Vector2) -> void:
	speech = t
	speech_t = rt
	speech_at = at


func update(delta: float, gentle: bool) -> void:
	rt += delta
	var target := 0.0
	if light_on:
		target = 1.0
		var since := rt - on_t
		if since < 0.14 and not gentle:   # bulb warm-up flicker
			target = [0.55, 0.2, 0.8, 0.45, 1.0][clampi(int(since / 0.028), 0, 4)]
	light = move_toward(light, target, delta * (6.0 if gentle else 14.0))
	if detail != "" and rt - detail_t > float(SCENES[detail].dur):
		detail = ""
	if detail == "trex" and debris.is_empty() and rt - detail_t > 1.1 and rt - detail_t < 1.15:
		for i in 14:
			debris.append({"p": Vector2(W - 140 + _rng.randf_range(-40, 40), float(lay.floor) - 60),
				"v": Vector2(_rng.randf_range(-180, 60), _rng.randf_range(-220, -80)), "r": _rng.randf() * TAU,
				"spin": _rng.randf_range(-8, 8), "s": _rng.randf_range(5, 11),
				"c": [Color8(160, 110, 70), Color8(230, 220, 200), Color8(120, 80, 160), Color8(80, 80, 90)][i % 4]})
	var keep: Array = []
	for d in debris:
		d.p += d.v * delta
		d.v.y += 300.0 * delta
		d.r += d.spin * delta
		if d.p.y < H + 30:
			keep.append(d)
	debris = keep


# ---------------------------------------------------------------- layout helpers

func _bro_size() -> Vector2:
	var t: Texture2D = bro.bro_switch[0]
	var h := H * 0.66
	return Vector2(t.get_width() * h / t.get_height(), h)


func _bro_pos() -> Vector2:
	return Vector2(6, float(lay.floor) - _bro_size().y + 4)


func _bro_head() -> Vector2:
	return _bro_pos() + Vector2(_bro_size().x * 0.6, 0)


func _scene_size(id: String) -> Vector2:
	var t: Texture2D = spr[id]
	var h: float = H * float(SCENES[id].size)
	return Vector2(t.get_width() * h / t.get_height(), h)


## Start (A), stay (P) and end (B) positions of a scene, in room pixels.
func _scene_path(id: String) -> Array:
	var s := _scene_size(id)
	var floor_y: float = lay.floor
	var bed: Array = lay.bed
	var bx := (float(bed[0]) + float(bed[1])) * 0.5
	var win: Array = lay.window
	var wx := (float(win[0]) + float(win[1])) * 0.5
	var cx: float = lay.ceil_x
	match id:
		"cool_cat":
			var p := Vector2(bx - s.x * 0.3, float(bed[2]) - s.y * 0.8)
			return [Vector2(float(bed[1]), p.y + s.y * 0.6), p, Vector2(W + 10, p.y)]
		"cat_hang":
			return [Vector2(cx, -s.y), Vector2(cx, -2), Vector2(cx, -s.y)]
		"dad":
			var p := Vector2(W - s.x, H * 0.18)
			return [Vector2(W + 4, p.y), p, Vector2(W + 4, p.y)]
		"alien":
			var p := Vector2(wx - s.x * 0.5, float(win[3]) - s.y)
			return [Vector2(p.x, p.y + s.y * 0.8), p, Vector2(W + 10, p.y - 20)]
		"monster":
			var p := Vector2(bx - s.x * 0.5, floor_y - s.y)
			return [Vector2(p.x + 30, floor_y - s.y * 0.2), p, Vector2(p.x + 30, floor_y - s.y * 0.2)]
		"pizza":
			var p := Vector2(cx + 90, 2)
			return [Vector2(p.x, -s.y), p, Vector2(p.x, floor_y - s.y)]
		"ghost":
			return [Vector2(float(bed[0]) - s.x, H * 0.12), Vector2(bx - s.x * 0.5, H * 0.06), Vector2(W, H * 0.02)]
		"trex":
			var p := Vector2(W - s.x * 1.6, floor_y - s.y)
			return [Vector2(W + 8, p.y), p, Vector2(W + 8, p.y)]
	if SCENES[id].get("family", false):
		var p := Vector2(W * 0.62 - s.x * 0.5, floor_y - s.y + 2)
		return [Vector2(W + 6, p.y), p, Vector2(W + 6, p.y)]
	return [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]


func _scene_pos(id: String, age: float) -> Vector2:
	var path := _scene_path(id)
	var dur: float = SCENES[id].dur
	var enter := 0.8
	var exit := 0.8
	var pos: Vector2 = path[1]
	if age < enter:
		pos = (path[0] as Vector2).lerp(path[1], _ease(age / enter))
		if id == "pizza":
			pos = path[1]
	elif age > dur - exit:
		pos = (path[1] as Vector2).lerp(path[2], _ease((age - (dur - exit)) / exit))
	elif id == "ghost" or id == "alien":
		pos.y += sin(age * 5.0) * 2.0
	if SCENES[id].get("family", false):
		var walking := age < enter or age > dur - exit
		if walking:
			pos.y -= absf(sin(age * 14.0)) * 3.0     # stomp stomp
		else:
			pos.x += sin(age * 30.0) * 0.8          # shaking with rage
	if id == "trex" and age < dur - exit:
		pos.y -= absf(sin(age * 9.0)) * 4.0
	return pos


func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


# ---------------------------------------------------------------- drawing

func draw(ci: CanvasItem, area: Rect2, gentle: bool) -> void:
	var sc := area.size.x / W
	var room_h := H * sc
	var origin := Vector2(area.position.x, area.end.y - room_h)
	var dest := Rect2(origin, Vector2(area.size.x, room_h))
	var lit_mod := Color(1, 1, 1)
	if disco > 0.0:
		lit_mod = lit_mod.lerp(Color.from_hsv(fposmod(rt * 0.6, 1.0), 0.45, 1.0), disco * 0.6)
	var dark_mod := Color(1.35, 1.35, 1.35) if gentle else Color(1, 1, 1)

	# the wall continues above the picture (stretch its top strip)
	var top := Rect2(area.position, Vector2(area.size.x, origin.y - area.position.y + 2))
	if top.size.y > 0:
		ci.draw_texture_rect_region(dark_tex, top, Rect2(0, 0, W, 6), dark_mod)
		if light > 0.0:
			ci.draw_texture_rect_region(lit_tex, top, Rect2(0, 0, W, 6), Color(lit_mod, light))
	ci.draw_texture_rect(dark_tex, dest, false, dark_mod)
	if light > 0.0:
		ci.draw_texture_rect(lit_tex, dest, false, Color(lit_mod, light))

	var shadow := Color(0.16, 0.16, 0.26) if theme != "spooky" else Color(0.12, 0.2, 0.2)
	var smod := shadow.lerp(lit_mod, light)

	# sleeping sibling: furious (shaking, red) when the light is on
	if sib_tex:
		var sp: Vector2 = lay.sib
		var ss := Vector2(sib_tex.get_width(), sib_tex.get_height()) * (H * 0.27 / sib_tex.get_height())
		var shake := Vector2(sin(rt * 40.0), 0) * 1.2 * light
		var angry := Color(1.0, 0.8, 0.8).lerp(Color(1, 1, 1), 1.0 - light)
		ci.draw_texture_rect(sib_tex, Rect2(origin + (sp + shake) * sc, ss * sc), false, smod * angry)
		if light > 0.6:
			var f := ThemeDB.fallback_font
			ci.draw_string(f, origin + (sp + Vector2(ss.x * 0.9, 6)) * sc, "!!", HORIZONTAL_ALIGNMENT_LEFT, -1, int(sc * 14), Color(1, 0.2, 0.2, light))

	# the active scene (visible as a dark shape when the light is off)
	if detail != "":
		var age := rt - detail_t
		var pos := _scene_pos(detail, age)
		var s := _scene_size(detail)
		ci.draw_texture_rect(spr[detail], Rect2(origin + pos * sc, s * sc), false, smod)
		var dur: float = SCENES[detail].dur
		if age > 0.8 and age < dur - 0.8 and light > 0.5:
			_bubble(ci, detail_text, origin + (pos + Vector2(s.x * 0.5, 0)) * sc, sc, light)
		if SCENES[detail].get("family", false) and age > 0.8 and age < dur - 0.8:
			# angry marks over their head
			var hc := origin + (pos + Vector2(s.x * 0.8, s.y * 0.08)) * sc
			var wob := sin(age * 12.0) * 2.0 * sc
			for k in 3:
				var ang := -PI * 0.5 + (k - 1) * 0.6
				var dir := Vector2(cos(ang), sin(ang))
				ci.draw_line(hc + dir * (6.0 * sc + wob), hc + dir * (13.0 * sc + wob), Color(1, 0.25, 0.2, maxf(light, 0.35)), maxf(2.0, sc * 1.3))
			# the brother answers back
			if age > dur - 1.6 and rt - speech_t > 2.0 and light > 0.5:
				_say(BRO_REPLIES[_rng.randi() % BRO_REPLIES.size()], _bro_head())

	# glowing eyes under the bed in the dark
	var ea := rt - eyes_t
	if ea < 2.4 and light < 0.6:
		var blink := 0.0 if fposmod(ea, 1.1) > 1.0 else 1.0
		var fade := clampf(minf(ea / 0.3, (2.4 - ea) / 0.3), 0.0, 1.0) * (1.0 - light) * blink
		var bed: Array = lay.bed
		var ep := Vector2(float(bed[1]) - 60 + sin(ea * 2.0) * 4.0, float(lay.floor) - 10)
		for dx in [0.0, 14.0]:
			ci.draw_circle(origin + (ep + Vector2(dx, 0)) * sc, 3.0 * sc, Color(1, 0.95, 0.4, fade))

	for d in debris:
		var dp: Vector2 = d.p
		var dr: float = d.r
		var ds: float = d.s
		var c: Vector2 = origin + dp * sc
		var hw: Vector2 = Vector2(cos(dr), sin(dr)) * ds * sc * 0.5
		var hh: Vector2 = Vector2(-hw.y, hw.x) * 0.6
		ci.draw_colored_polygon(PackedVector2Array([c - hw - hh, c + hw - hh, c + hw + hh, c - hw + hh]), Color(d.c, maxf(light, 0.3)))

	# the brother
	var pose := "bro_switch"
	var since := rt - flick_t
	if rt - taunt_t < 0.7:
		pose = taunt_pose
	elif disco > 0.5:
		pose = "bro_dance1" if int(rt * 4.0) % 2 == 0 else "bro_dance2"
	var bsize := _bro_size()
	var bpos := _bro_pos()
	var squash := 1.0
	if pose == "bro_switch" and since < 0.12:
		squash = 0.95
	var tex: Texture2D = bro[pose][0]   # same darkening as everyone else in the room
	var real := Vector2(tex.get_width() * bsize.y / tex.get_height(), bsize.y)
	var r := Rect2(origin + (bpos + Vector2(0, real.y * (1.0 - squash))) * sc, Vector2(real.x, real.y * squash) * sc)
	ci.draw_texture_rect(tex, r, false, smod)
	# flick lines at the switch
	if since < 0.25 and pose == "bro_switch":
		var a := 1.0 - since / 0.25
		var lc := Color(1.0, 0.95, 0.5, a) if light_on else Color(0.8, 0.85, 1.0, a)
		var c0 := origin + (bpos + Vector2(real.x * 0.1, real.y * 0.52)) * sc
		for k in 3:
			var ang := PI + (k - 1) * 0.7
			var dir := Vector2(cos(ang), sin(ang))
			ci.draw_line(c0 + dir * 10.0 * sc, c0 + dir * (18.0 + since * 30.0) * sc, lc, maxf(2.0, sc * 1.2))

	if rt - speech_t < 1.6 and speech != "":
		_bubble(ci, speech, origin + speech_at * sc, sc, 1.0)


func _bubble(ci: CanvasItem, text: String, p: Vector2, sc: float, a: float) -> void:
	var f := ThemeDB.fallback_font
	var fs := int(clampf(sc * 8.0, 13, 24))
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var r := Rect2(p.x - tw * 0.5 - 8, p.y - fs - 16, tw + 16, fs + 10)
	r.position.x = maxf(4.0, r.position.x)
	ci.draw_rect(r.grow(2), Color(0, 0, 0, a))
	ci.draw_rect(r, Color(1, 1, 1, a))
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-5, -7), p + Vector2(5, -7), p]), Color(1, 1, 1, a))
	ci.draw_string(f, Vector2(r.position.x + 8, r.position.y + fs + 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.1, 0.1, 0.15, a))
