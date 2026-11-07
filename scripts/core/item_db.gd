class_name ItemDB
extends RefCounted
## 아이템 정의 표. 아이템 하나 = 가방 칸 모양 + 비용 + 능력치 + 시너지 태그.
##
## 능력치 키
##   hp     최대 체력
##   atk    공격력 (한 번 때릴 때 피해)
##   armor  방어력 (받는 피해에서 뺀다)
##   spd    초당 공격 횟수 보너스
##   regen  초당 체력 회복

const MAX_TIER := 3

const DEFS: Dictionary = {
	"dagger": {
		"name": "단검", "cost": 2, "tag": "warrior",
		"shape": [Vector2i(0, 0)],
		"stats": {"atk": 2.0, "spd": 0.15},
		"color": Color(0.80, 0.42, 0.36),
	},
	"sword": {
		"name": "장검", "cost": 3, "tag": "warrior",
		"shape": [Vector2i(0, 0), Vector2i(0, 1)],
		"stats": {"atk": 5.0},
		"color": Color(0.86, 0.33, 0.30),
	},
	"axe": {
		"name": "전투도끼", "cost": 5, "tag": "warrior",
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
		"stats": {"atk": 9.0, "hp": 10.0},
		"color": Color(0.70, 0.22, 0.22),
	},
	"buckler": {
		"name": "버클러", "cost": 2, "tag": "guard",
		"shape": [Vector2i(0, 0)],
		"stats": {"hp": 10.0, "armor": 1.0},
		"color": Color(0.36, 0.55, 0.82),
	},
	"helmet": {
		"name": "투구", "cost": 3, "tag": "guard",
		"shape": [Vector2i(0, 0), Vector2i(1, 0)],
		"stats": {"hp": 20.0, "armor": 1.0},
		"color": Color(0.30, 0.48, 0.74),
	},
	"tower_shield": {
		"name": "대방패", "cost": 4, "tag": "guard",
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
		"stats": {"hp": 35.0, "armor": 2.0},
		"color": Color(0.24, 0.38, 0.66),
	},
	"apple": {
		"name": "사과", "cost": 1, "tag": "nature",
		"shape": [Vector2i(0, 0)],
		"stats": {"hp": 5.0, "regen": 1.0},
		"color": Color(0.42, 0.72, 0.36),
	},
	"herb_pouch": {
		"name": "약초주머니", "cost": 3, "tag": "nature",
		"shape": [Vector2i(0, 0), Vector2i(0, 1)],
		"stats": {"hp": 8.0, "regen": 2.5},
		"color": Color(0.30, 0.60, 0.30),
	},
	"fire_staff": {
		"name": "화염지팡이", "cost": 4, "tag": "arcane",
		"shape": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)],
		"stats": {"atk": 6.0, "spd": 0.1},
		"color": Color(0.66, 0.40, 0.82),
	},
	"mana_orb": {
		"name": "마력구슬", "cost": 3, "tag": "arcane",
		"shape": [Vector2i(0, 0)],
		"stats": {"spd": 0.3},
		"color": Color(0.56, 0.34, 0.76),
	},
}


static func ids() -> Array[String]:
	var out: Array[String] = []
	for k: String in DEFS.keys():
		out.append(k)
	return out


static func has(def_id: String) -> bool:
	return DEFS.has(def_id)


static func get_def(def_id: String) -> Dictionary:
	return DEFS.get(def_id, {})
