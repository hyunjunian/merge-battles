class_name Item
extends RefCounted
## 보유한 아이템 하나. 같은 종류·같은 등급 두 개를 합성하면 등급이 오른다.
## 등급이 오르면 능력치는 2배, 비용은 1.5배라서 합성할수록 예산과 가방 칸을 아낀다.

const STAT_GROWTH := 2.0
const COST_GROWTH := 1.5

static var _next_uid: int = 1

var uid: int
var def_id: String
var tier: int
## true 면 모양을 90도 돌린다 (x, y 를 바꾼다).
var rotated: bool = false


func _init(p_def_id: String = "dagger", p_tier: int = 1) -> void:
	uid = _next_uid
	_next_uid += 1
	def_id = p_def_id
	tier = clampi(p_tier, 1, ItemDB.MAX_TIER)


func def() -> Dictionary:
	return ItemDB.get_def(def_id)


func display_name() -> String:
	return "%s%s" % [def().get("name", def_id), "★".repeat(tier)]


func tag() -> String:
	return def().get("tag", "")


func color() -> Color:
	return def().get("color", Color.GRAY)


func cost() -> int:
	return roundi(float(def().get("cost", 1)) * pow(COST_GROWTH, tier - 1))


## 판매 가격: 비용의 절반 (최소 1).
func sell_price() -> int:
	return maxi(1, cost() / 2)


func stats() -> Dictionary:
	var out := {}
	var base: Dictionary = def().get("stats", {})
	var mult := pow(STAT_GROWTH, tier - 1)
	for k: String in base.keys():
		out[k] = float(base[k]) * mult
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


func can_merge_with(other: Item) -> bool:
	return other != null and other != self and other.def_id == def_id and other.tier == tier and tier < ItemDB.MAX_TIER


func describe() -> String:
	var parts: PackedStringArray = []
	var s := stats()
	var labels := {"hp": "체력", "atk": "공격", "armor": "방어", "spd": "공속", "regen": "회복"}
	for k: String in ["hp", "atk", "armor", "spd", "regen"]:
		if s.has(k):
			var v: float = s[k]
			parts.append("%s +%s" % [labels[k], ("%.2f" % v).rstrip("0").rstrip(".")])
	if def().has("range"):
		parts.append("사거리 %.1f (원거리)" % float(def()["range"]))
	return ", ".join(parts)
