class_name UnitDB
extends RefCounted
## 유닛(가방) 정의 표. 유닛 = 가방 크기(가로 x 세로) + 가격 + 기본 능력치.
## 클수록 비싸다. 가격은 2~10원.
##
## 기본 능력치 키: hp, atk, armor, spd(초당 공격), regen, range(사거리, 없으면 근접), move(초당 이동)

const DEFS: Dictionary = {
	"recruit": {
		"name": "견습병", "cost": 2, "size": Vector2i(1, 2),
		"stats": {"hp": 45.0, "atk": 3.0, "spd": 0.8, "move": 2.0},
		"color": Color(0.70, 0.66, 0.55),
	},
	"scout": {
		"name": "척후병", "cost": 3, "size": Vector2i(1, 3),
		"stats": {"hp": 40.0, "atk": 3.0, "spd": 1.0, "move": 2.6},
		"color": Color(0.45, 0.70, 0.45),
	},
	"soldier": {
		"name": "병사", "cost": 4, "size": Vector2i(2, 2),
		"stats": {"hp": 70.0, "atk": 4.0, "armor": 1.0, "spd": 0.8, "move": 2.0},
		"color": Color(0.55, 0.55, 0.65),
	},
	"archer": {
		"name": "궁수", "cost": 4, "size": Vector2i(2, 2),
		"stats": {"hp": 40.0, "atk": 3.0, "spd": 0.8, "range": 4.5, "move": 1.9},
		"color": Color(0.80, 0.60, 0.30),
	},
	"knight": {
		"name": "기사", "cost": 6, "size": Vector2i(2, 3),
		"stats": {"hp": 100.0, "atk": 5.0, "armor": 2.0, "spd": 0.75, "move": 1.8},
		"color": Color(0.40, 0.50, 0.80),
	},
	"mage": {
		"name": "마법사", "cost": 7, "size": Vector2i(3, 2),
		"stats": {"hp": 55.0, "atk": 6.0, "spd": 0.7, "range": 4.0, "move": 1.8},
		"color": Color(0.60, 0.35, 0.80),
	},
	"giant": {
		"name": "거인", "cost": 8, "size": Vector2i(3, 3),
		"stats": {"hp": 160.0, "atk": 7.0, "armor": 2.0, "spd": 0.6, "move": 1.5},
		"color": Color(0.55, 0.40, 0.30),
	},
	"warlord": {
		"name": "군주", "cost": 10, "size": Vector2i(3, 4),
		"stats": {"hp": 200.0, "atk": 9.0, "armor": 3.0, "spd": 0.7, "move": 1.6},
		"color": Color(0.85, 0.70, 0.20),
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


static func cost(def_id: String) -> int:
	return int(get_def(def_id).get("cost", 0))
