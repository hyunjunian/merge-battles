class_name BattleView
extends Control
## BattleSim.simulate() 결과를 재생한다. 위쪽이 상대, 아래쪽이 우리 팀. 0번 유닛이 맨 앞(가운데 쪽)이다.

signal finished(winner: String)

const SPEED := 1.5
const CARD := Vector2(190, 150)
const FLASH_TIME := 0.25
const FLOAT_TIME := 0.8

var result: Dictionary = {}
var t: float = 0.0
var done: bool = false
var _next_event: int = 0
## 피격 표시: [{side, idx, age}] / 피해 숫자: [{side, idx, text, age}] / 공격 모션: [{side, idx, age}]
var _flashes: Array = []
var _floats: Array = []
var _lunges: Array = []
var _colors_a: Array[Color] = []
var _colors_b: Array[Color] = []


## colors_*: 유닛마다 대표 색(가방에서 가장 비싼 아이템 색)
func setup(p_result: Dictionary, colors_a: Array[Color], colors_b: Array[Color], start_time: float = 0.0) -> void:
	result = p_result
	_colors_a = colors_a
	_colors_b = colors_b
	t = 0.0
	done = false
	_next_event = 0
	if start_time > 0.0:
		_advance(start_time)
	queue_redraw()


func skip() -> void:
	_advance(duration() - t + 0.01)


func duration() -> float:
	return float(result.get("duration", 0.0))


func _process(delta: float) -> void:
	if result.is_empty() or done:
		return
	_advance(delta * SPEED)


func _advance(dt: float) -> void:
	t = minf(t + dt, duration())
	for list: Array in [_flashes, _floats, _lunges]:
		for e: Dictionary in list:
			e["age"] += dt
	_flashes = _flashes.filter(func(e: Dictionary) -> bool: return e["age"] < FLASH_TIME)
	_floats = _floats.filter(func(e: Dictionary) -> bool: return e["age"] < FLOAT_TIME)
	_lunges = _lunges.filter(func(e: Dictionary) -> bool: return e["age"] < FLASH_TIME)
	var events: Array = result.get("events", [])
	while _next_event < events.size() and float(events[_next_event]["t"]) <= t:
		var e: Dictionary = events[_next_event]
		var foe := "b" if e["side"] == "a" else "a"
		var age := t - float(e["t"])
		_lunges.append({"side": e["side"], "idx": e["src"], "age": age})
		_flashes.append({"side": foe, "idx": e["dst"], "age": age})
		_floats.append({"side": foe, "idx": e["dst"], "text": "-%d" % roundi(e["dmg"]), "age": age})
		_next_event += 1
	if t >= duration() and not done:
		done = true
		finished.emit(result.get("winner", "b"))
	queue_redraw()


func hp_at(side: String, idx: int) -> float:
	var frames: Array = result.get("frames", [])
	if frames.is_empty():
		return 0.0
	var fi := clampi(int(round(t / BattleSim.DT)), 0, frames.size() - 1)
	var arr: PackedFloat32Array = frames[fi][0 if side == "a" else 1]
	return arr[idx] if idx < arr.size() else 0.0


func _card_rect(side: String, idx: int, count: int) -> Rect2:
	var gap := 20.0
	var total := count * CARD.x + (count - 1) * gap
	var x0 := (size.x - total) / 2.0
	# 0번(맨 앞)이 가운데 쪽: 상대는 아래줄, 우리는 윗줄에 가깝게 놓고 뒤 유닛은 바깥쪽으로 밀린다.
	var mid := size.y / 2.0
	var depth := 30.0 * idx
	var y := mid - 70.0 - CARD.y - depth if side == "b" else mid + 70.0 + depth
	return Rect2(Vector2(x0 + idx * (CARD.x + gap), y), CARD)


func _draw() -> void:
	if result.is_empty():
		return
	var font := get_theme_default_font()
	var mid := size.y / 2.0
	draw_line(Vector2(40, mid), Vector2(size.x - 40, mid), Color(1, 1, 1, 0.15), 2.0)
	draw_string(font, Vector2(0, mid + 10), "VS", HORIZONTAL_ALIGNMENT_CENTER, size.x, 32, Color(1, 1, 1, 0.5))
	for side: String in ["b", "a"]:
		var maxes: PackedFloat32Array = result["max_a"] if side == "a" else result["max_b"]
		var colors := _colors_a if side == "a" else _colors_b
		for i in maxes.size():
			_draw_card(font, side, i, maxes.size(), maxes[i], colors[i] if i < colors.size() else Color.GRAY)
	draw_string(font, Vector2(24, 40), "%.1f초" % t, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.7))


func _draw_card(font: Font, side: String, i: int, count: int, max_hp: float, col: Color) -> void:
	var r := _card_rect(side, i, count)
	for l: Dictionary in _lunges:
		if l["side"] == side and l["idx"] == i:
			var k: float = sin(PI * l["age"] / FLASH_TIME)
			r.position.y += (-18.0 if side == "a" else 18.0) * k
	var hp := hp_at(side, i)
	var alive := hp > 0.0
	var body := col if alive else Color(0.25, 0.25, 0.25)
	draw_rect(r, body.darkened(0.45))
	draw_rect(Rect2(r.position + Vector2(10, 10), Vector2(r.size.x - 20, 70)), body)
	for f: Dictionary in _flashes:
		if f["side"] == side and f["idx"] == i:
			draw_rect(r, Color(1, 0.2, 0.2, 0.5 * (1.0 - f["age"] / FLASH_TIME)))
	draw_rect(r, Color.WHITE if side == "a" else Color(1, 0.5, 0.5), false, 2.0)
	var label_text := ("유닛 %d" if side == "a" else "적 %d") % (i + 1)
	if alive:
		draw_string(font, r.position + Vector2(0, 54), label_text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 24, Color.WHITE)
	# 체력 막대
	var bar := Rect2(r.position + Vector2(10, 94), Vector2(r.size.x - 20, 18))
	draw_rect(bar, Color(0.1, 0.1, 0.1))
	var ratio := clampf(hp / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), Color(0.35, 0.85, 0.4) if side == "a" else Color(0.9, 0.35, 0.3))
	draw_string(font, r.position + Vector2(0, 138), "%d / %d" % [ceili(hp), roundi(max_hp)], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 18, Color(1, 1, 1, 0.85))
	if not alive:
		draw_string(font, r.position + Vector2(0, 54), "쓰러짐", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 28, Color(1, 0.4, 0.4))
	for fl: Dictionary in _floats:
		if fl["side"] == side and fl["idx"] == i:
			var a: float = 1.0 - fl["age"] / FLOAT_TIME
			var p := r.position + Vector2(r.size.x - 50, 30 - 40.0 * fl["age"])
			draw_string(font, p, fl["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 0.85, 0.3, a))
