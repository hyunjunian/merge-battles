class_name LiveStats
extends Control
## 유닛 상세 패널의 체력·쿨타임 막대.
## source() 가 돌려주는 사전으로 매 프레임 다시 그린다.
##   {hp, max_hp, shield, cd, interval, heal_t, heal_cd, fire_t, fire_cd, live}
##   live 가 false 면 전투 전(고정값): 체력은 가득, 쿨타임은 "N초마다" 로 표시.

const ROW := 30.0
const LABEL_W := 64.0

var source: Callable


static func make(p_source: Callable) -> LiveStats:
	var ls := LiveStats.new()
	ls.source = p_source
	ls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ls._resize(p_source.call())
	return ls


## 그릴 줄: [이름, 비율(0~1), 오른쪽 글자, 색]
static func rows(d: Dictionary) -> Array:
	var out: Array = []
	var live: bool = d.get("live", false)
	var hp: float = d.get("hp", 0.0)
	var mx: float = maxf(1.0, d.get("max_hp", 1.0))
	var hp_text := "%d / %d" % [ceili(hp), roundi(mx)]
	if float(d.get("shield", 0.0)) > 0.0:
		hp_text += "  +%d" % roundi(d["shield"])
	out.append(["체력", clampf(hp / mx, 0.0, 1.0), hp_text if hp > 0.0 else "쓰러짐", UiStyle.GREEN if hp / mx > 0.3 else UiStyle.RED])
	var interval: float = d.get("interval", 1.0)
	if live:
		var cd: float = d.get("cd", 0.0)
		out.append(["공격", clampf(1.0 - cd / interval, 0.0, 1.0), "준비" if cd <= 0.05 else "%.1f초" % cd, UiStyle.GOLD])
	else:
		out.append(["공격", 1.0, "%.2f초마다" % interval, UiStyle.GOLD])
	for sk: Array in [["치유", "heal_t", "heal_cd", Color(0.35, 1.0, 0.55)], ["화염구", "fire_t", "fire_cd", Color(1.0, 0.55, 0.15)]]:
		var total: float = d.get(sk[2], 0.0)
		if total <= 0.0:
			continue
		if live:
			var left: float = d.get(sk[1], 0.0)
			out.append([sk[0], clampf(1.0 - left / total, 0.0, 1.0), "준비" if left <= 0.05 else "%.1f초" % left, sk[3]])
		else:
			out.append([sk[0], 1.0, "%.0f초마다" % total, sk[3]])
	return out


func _resize(d: Dictionary) -> void:
	custom_minimum_size = Vector2(200, rows(d).size() * ROW)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not source.is_valid():
		return
	var d: Dictionary = source.call()
	var list := rows(d)
	if list.size() * ROW != custom_minimum_size.y:
		_resize(d)
	var font := UiStyle.bold()
	for i in list.size():
		var r: Array = list[i]
		var y := i * ROW
		draw_string(font, Vector2(0, y + 21), r[0], HORIZONTAL_ALIGNMENT_LEFT, LABEL_W, 16, UiStyle.MUTED)
		var bar := Rect2(LABEL_W, y + 6, size.x - LABEL_W, ROW - 10)
		draw_style_box(UiStyle.box(Color(0, 0, 0, 0.55), Color(1, 1, 1, 0.12), 1, 6, -1, 0.0), bar)
		var fill := Rect2(bar.position + Vector2(2, 2), Vector2(maxf(0.0, (bar.size.x - 4) * float(r[1])), bar.size.y - 4))
		if fill.size.x > 0.5:
			draw_style_box(UiStyle.box(r[3], Color.TRANSPARENT, 0, 5, -1, 0.0), fill)
		draw_string_outline(font, bar.position + Vector2(8, 15), r[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.7))
		draw_string(font, bar.position + Vector2(8, 15), r[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
