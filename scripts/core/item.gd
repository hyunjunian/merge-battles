class_name Item
extends RefCounted
## 보유한 아이템 하나.

static var _next_uid: int = 1

var uid: int
var def_id: String
## true 면 모양을 90도 돌린다 (x, y 를 바꾼다).
var rotated: bool = false


func _init(p_def_id: String = "apple") -> void:
	uid = _next_uid
	_next_uid += 1
	def_id = p_def_id


func def() -> Dictionary:
	return ItemDB.get_def(def_id)


func display_name() -> String:
	return def().get("name", def_id)


func tag() -> String:
	return def().get("tag", "")


func color() -> Color:
	return def().get("color", Color.GRAY)


func cost() -> int:
	return int(def().get("cost", 1))


func sell_price() -> int:
	return Pricing.sell_price(cost())


func stats() -> Dictionary:
	var out := {}
	var base: Dictionary = def().get("stats", {})
	for k: String in base.keys():
		out[k] = float(base[k])
	return out


## 회전을 반영한 칸 목록 (왼쪽 위가 (0, 0)).
func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Vector2i in def().get("shape", [Vector2i.ZERO]):
		out.append(Vector2i(c.y, c.x) if rotated else c)
	return out


func size() -> Vector2i:
	var s := Vector2i.ZERO
	for c in cells():
		s.x = maxi(s.x, c.x + 1)
		s.y = maxi(s.y, c.y + 1)
	return s


func is_rotatable() -> bool:
	var s := size()
	return s.x != s.y


func skill() -> Dictionary:
	return def().get("skill", {})


func has_skill() -> bool:
	return not skill().is_empty()


func describe() -> String:
	var text := Pricing.describe_stats(stats(), float(def().get("range", 0.0)))
	if has_skill():
		text += ("\n" if text != "" else "") + Skills.describe(skill())
	return text
