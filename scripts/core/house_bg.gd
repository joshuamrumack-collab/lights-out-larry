class_name HouseBg
extends RefCounted
## Main-menu background: the family house at night. Larry runs from room to room flicking
## the lights (his hand on the switch is hidden behind the curtain), and the family chases
## him through the house, switching lights back off behind him.

# Window rectangles in the house image (x0, y0, x1, y1) and which rooms connect.
const WINDOWS := [
	[641, 151, 700, 225],                                                    # 0 attic
	[384, 328, 452, 423], [513, 328, 581, 424], [762, 328, 830, 424], [891, 328, 960, 424],  # 1-4 upstairs
	[384, 527, 451, 622], [513, 527, 581, 622], [759, 527, 830, 622], [891, 527, 960, 622],  # 5-8 downstairs
]
const NEIGHBOURS := {0: [2, 3], 1: [2, 5], 2: [1, 3, 6, 0], 3: [2, 4, 7, 0], 4: [3, 8],
	5: [1, 6], 6: [5, 7, 2], 7: [6, 8, 3], 8: [7, 4]}
const MAX_LIT := 4
const FAMILY := ["mom", "dad_pj", "big_sis", "little_sis", "grandma", "grandpa"]
# Larry's sprite without the switch plate: only this part of bro_switch.png is ever drawn.
const BRO_SRC := Rect2(62, 0, 108, 193)

var lit_tex: Texture2D = load("res://art/house_lit.png")
var dark_tex: Texture2D = load("res://art/house_dark.png")
var lit_over: Texture2D = load("res://art/house_lit_over.png")    # curtains + frames only
var dark_over: Texture2D = load("res://art/house_dark_over.png")
var bro_tex: Texture2D = load("res://art/sprites/bro_switch.png")
var fam_tex := {}
var on: Array = []          # light level per window (0..1, eased)
var want: Array = []        # target state per window
var lit_order: Array = []   # oldest lit first
var room := 2               # where Larry is
var trail: Array = []       # rooms Larry was in, newest last
var flicks_left := 3
var in_room_t := 0.0
var chasers: Array = []     # {who, lag, room, t}
var rt := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()
	for f in FAMILY:
		fam_tex[f] = load("res://art/sprites/%s.png" % f)
	for i in WINDOWS.size():
		on.append(0.0)
		want.append(false)
	room = [0, 2, 3, 7][_rng.randi() % 4]
	_light(room, true)
	var first: String = FAMILY[_rng.randi() % FAMILY.size()]
	chasers.append({"who": first, "lag": 1, "room": -1, "t": 0.0})


func _light(i: int, v: bool) -> void:
	want[i] = v
	lit_order.erase(i)
	if v:
		lit_order.append(i)


func _move_chasers() -> void:
	for c in chasers:
		var idx: int = trail.size() - int(c.lag)
		var target: int = trail[idx] if idx >= 0 else -1
		if target != c.room:
			if c.room >= 0 and c.room != room and _rng.randf() < 0.8:
				_light(c.room, false)            # click. "and STAY off!"
			c.room = target
			c.t = rt
			if target >= 0 and target != room:
				_light(target, true)             # they switch it on to look for him


## Call on every beat of the menu music.
func beat() -> void:
	if flicks_left > 0:
		_light(room, not want[room])
		flicks_left -= 1
		return
	# run to a neighbouring room, away from whoever is chasing him if he can
	if _rng.randf() < 0.75:
		_light(room, true)
	var nb: Array = (NEIGHBOURS[room] as Array).duplicate()
	var free: Array = nb.filter(func(r): return not chasers.any(func(c): return c.room == r))
	if not free.is_empty():
		nb = free
	trail.append(room)
	if trail.size() > 8:
		trail.pop_front()
	room = nb[_rng.randi() % nb.size()]
	in_room_t = rt
	flicks_left = _rng.randi_range(2, 5)
	_light(room, true)
	_move_chasers()
	# now and then someone else joins the chase, or gives up
	if _rng.randf() < 0.18:
		if chasers.size() < 2:
			var others: Array = FAMILY.filter(func(f): return not chasers.any(func(c): return c.who == f))
			chasers.append({"who": others[_rng.randi() % others.size()], "lag": 2, "room": -1, "t": rt})
		else:
			var quit: Dictionary = chasers.pop_back()
			if quit.room >= 0 and quit.room != room:
				_light(quit.room, false)
		if _rng.randf() < 0.5:
			chasers[0].who = FAMILY[_rng.randi() % FAMILY.size()]
	while lit_order.size() > MAX_LIT:
		var oldest: int = lit_order[0]
		if oldest == room:
			break
		_light(oldest, false)


func update(delta: float) -> void:
	rt += delta
	for i in on.size():
		on[i] = move_toward(on[i], 1.0 if want[i] else 0.0, delta * 18.0)


## Draws part of a texture into dst, clipped to clip (in screen space). Optional mirror.
func _draw_clipped(ci: CanvasItem, tex: Texture2D, src: Rect2, dst: Rect2, clip: Rect2, tint: Color, mirror: bool) -> void:
	var vis := dst.intersection(clip)
	if vis.size.x <= 0.0 or vis.size.y <= 0.0:
		return
	var sx := src.size.x / dst.size.x
	var sy := src.size.y / dst.size.y
	var s := Rect2(src.position.x + (vis.position.x - dst.position.x) * sx,
		src.position.y + (vis.position.y - dst.position.y) * sy, vis.size.x * sx, vis.size.y * sy)
	if mirror:
		s.position.x = src.position.x + (dst.end.x - vis.end.x) * sx
		ci.draw_set_transform(Vector2(vis.position.x * 2.0 + vis.size.x, 0), 0.0, Vector2(-1, 1))
		ci.draw_texture_rect_region(tex, vis, s, tint)
		ci.draw_set_transform(Vector2.ZERO)
	else:
		ci.draw_texture_rect_region(tex, vis, s, tint)


func draw(ci: CanvasItem, area: Rect2) -> void:
	var img := Vector2(dark_tex.get_width(), dark_tex.get_height())
	var sc := maxf(area.size.x / img.x, area.size.y / img.y)
	var origin := area.position + (area.size - img * sc) * 0.5
	# stretch the picture's empty left/right edges to fill any gap (sky and lawn keep their rows)
	if origin.x > area.position.x:
		ci.draw_texture_rect_region(dark_tex, Rect2(area.position.x, origin.y, origin.x - area.position.x + 1, img.y * sc), Rect2(0, 0, 24, img.y))
	var right := origin.x + img.x * sc
	if right < area.end.x:
		ci.draw_texture_rect_region(dark_tex, Rect2(right - 1, origin.y, area.end.x - right + 1, img.y * sc), Rect2(img.x - 24, 0, 24, img.y))
	ci.draw_texture_rect(dark_tex, Rect2(origin, img * sc), false)
	for i in WINDOWS.size():
		var w: Array = WINDOWS[i]
		var src := Rect2(w[0], w[1], w[2] - w[0], w[3] - w[1])
		var dst := Rect2(origin + src.position * sc, src.size * sc)
		var a: float = on[i]
		if a > 0.0:
			ci.draw_rect(dst.grow(6.0 * sc), Color(1.0, 0.8, 0.4, 0.10 * a))
			ci.draw_texture_rect_region(lit_tex, dst, src, Color(1, 1, 1, a))
		# people inside the room, seen through the glass (shaded like the room)
		var tint := Color(0.13, 0.13, 0.22).lerp(Color(0.9, 0.78, 0.68), a)
		var clip := dst.grow(-3.0 * sc)
		for c in chasers:
			if c.room == i and i != room:
				var t: Texture2D = fam_tex[c.who]
				var hh := src.size.y * 0.95
				var fw := t.get_width() * hh / t.get_height()
				var age: float = rt - float(c.t)
				var shake := sin(rt * 30.0) * 0.8 if age > 0.3 else 0.0
				var slide := clampf(1.0 - age / 0.3, 0.0, 1.0) * src.size.x * 0.6
				var fp := Vector2(src.position.x + src.size.x * 0.5 - fw * 0.5 + shake + slide, src.position.y + src.size.y * 0.12)
				var mirror: bool = int(WINDOWS[room][0]) > int(w[0])       # face the way Larry ran
				_draw_clipped(ci, t, Rect2(0, 0, t.get_width(), t.get_height()), Rect2(origin + fp * sc, Vector2(fw, hh) * sc), clip, tint, mirror)
		if i == room:
			# Larry: upper body only, his switch hand tucked behind the left curtain
			var hh := src.size.y * 0.9
			var bw := BRO_SRC.size.x * hh / BRO_SRC.size.y
			var hop := absf(sin((rt - in_room_t) * 10.0)) * 2.0
			var bp := Vector2(src.position.x + src.size.x * 0.2, src.position.y + src.size.y * 0.26 - hop)
			_draw_clipped(ci, bro_tex, BRO_SRC, Rect2(origin + bp * sc, Vector2(bw, hh) * sc), clip, tint, false)
		# curtains and window frame go in front of everyone
		ci.draw_texture_rect_region(dark_over, dst, src)
		if a > 0.0:
			ci.draw_texture_rect_region(lit_over, dst, src, Color(1, 1, 1, a))
		# angry marks above a chaser's window
		for c in chasers:
			if c.room == i and i != room:
				var hc := dst.position + Vector2(dst.size.x * 0.5, -4.0 * sc)
				var wob := sin(rt * 12.0) * 2.0
				for k in 3:
					var ang := -PI * 0.5 + (k - 1) * 0.6
					var dir := Vector2(cos(ang), sin(ang))
					ci.draw_line(hc + dir * (5.0 + wob), hc + dir * (13.0 + wob), Color(1, 0.3, 0.2), 3.0)
