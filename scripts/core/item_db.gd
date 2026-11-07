class_name ItemDB
extends RefCounted
## 아이템 정의 표. 아이템 = 가방 칸 모양 + 가격 + 능력치 변화 + 시너지 태그.
## 작고 성능이 좋을수록 비싸다. 가격은 2~10원 (판매가는 그보다 낮은 1원 이상).
##
## 능력치 키
##   hp     최대 체력
##   atk    공격력 (한 번 때릴 때 피해)
##   armor  방어력 (받는 피해에서 뺀다)
##   spd    초당 공격 횟수
##   regen  초당 체력 회복
## 선택 필드
##   range  공격 사거리. 가방에 하나라도 있으면 그 유닛은 원거리 유닛이 된다 (가장 긴 값).

const DEFS: Dictionary = {
	"apple": {
		"name": "사과", "cost": 2, "tag": "nature",
		"shape": [Vector2i(0, 0)],
		"stats": {"hp": 10.0, "regen": 0.5},
		"color": Color(0.42, 0.72, 0.36),
	},
	"club": {
		"name": "몽둥이", "cost": 2, "tag": "warrior",
		"shape": [Vector2i(0, 0), Vector2i(0, 1)],
		"stats": {"atk": 3.0},
		"color": Color(0.62, 0.45, 0.30),
	},
	"helmet": {
		"name": "투구", "cost": 2, "tag": "guard",
		"shape": [Vector2i(0, 0), Vector2i(1, 0)],
		"stats": {"hp": 20.0, "armor": 1.0},
		"color": Color(0.30, 0.48, 0.74),
	},
	"sword": {
		"name": "장검", "cost": 3, "tag": "warrior",
		"shape": [Vector2i(0, 0), Vector2i(0, 1)],
		"stats": {"atk": 5.0},
		"color": Color(0.86, 0.33, 0.30),
	},
	"axe": {
		"name": "전투도끼", "cost": 3, "tag": "warrior",
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
		"stats": {"atk": 8.0, "hp": 10.0},
		"color": Color(0.70, 0.22, 0.22),
	},
	"herb_pouch": {
		"name": "약초주머니", "cost": 3, "tag": "nature",
		"shape": [Vector2i(0, 0), Vector2i(0, 1)],
		"stats": {"hp": 8.0, "regen": 2.0},
		"color": Color(0.30, 0.60, 0.30),
	},
	"dagger": {
		"name": "단검", "cost": 4, "tag": "warrior",
		"shape": [Vector2i(0, 0)],
		"stats": {"atk": 4.0, "spd": 0.15},
		"color": Color(0.80, 0.42, 0.36),
	},
	"buckler": {
		"name": "버클러", "cost": 4, "tag": "guard",
		"shape": [Vector2i(0, 0)],
		"stats": {"hp": 15.0, "armor": 1.0},
		"color": Color(0.36, 0.55, 0.82),
	},
	"tower_shield": {
		"name": "대방패", "cost": 4, "tag": "guard",
		"shape": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
		"stats": {"hp": 40.0, "armor": 2.0},
		"color": Color(0.24, 0.38, 0.66),
	},
	"short_bow": {
		"name": "단궁", "cost": 4, "tag": "warrior", "range": 4.5,
		"shape": [Vector2i(0, 0), Vector2i(0, 1)],
		"stats": {"atk": 3.0, "spd": 0.1},
		"color": Color(0.78, 0.56, 0.30),
	},
	"fire_staff": {
		"name": "화염지팡이", "cost": 5, "tag": "arcane", "range": 4.0,
		"shape": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)],
		"stats": {"atk": 7.0},
		"color": Color(0.66, 0.40, 0.82),
	},
	"mana_orb": {
		"name": "마력구슬", "cost": 6, "tag": "arcane",
		"shape": [Vector2i(0, 0)],
		"stats": {"spd": 0.35},
		"color": Color(0.56, 0.34, 0.76),
	},
	"ruby": {
		"name": "루비", "cost": 7, "tag": "arcane",
		"shape": [Vector2i(0, 0)],
		"stats": {"atk": 8.0},
		"color": Color(0.85, 0.15, 0.35),
	},
	"dragon_scale": {
		"name": "용비늘", "cost": 8, "tag": "guard",
		"shape": [Vector2i(0, 0)],
		"stats": {"hp": 50.0, "armor": 3.0},
		"color": Color(0.20, 0.55, 0.50),
	},
	"war_banner": {
		"name": "군기", "cost": 8, "tag": "warrior",
		"shape": [Vector2i(0, 0), Vector2i(0, 1)],
		"stats": {"atk": 6.0, "spd": 0.25, "hp": 20.0},
		"color": Color(0.90, 0.60, 0.15),
	},
	"phoenix_feather": {
		"name": "불사조깃털", "cost": 10, "tag": "nature",
		"shape": [Vector2i(0, 0)],
		"stats": {"hp": 40.0, "regen": 5.0, "atk": 5.0},
		"color": Color(1.0, 0.45, 0.10),
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
