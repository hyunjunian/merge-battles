class_name BattleSim
extends RefCounted
## 자동 전투 시뮬레이션. 결과를 한 번에 계산하고, 화면은 그 기록(frames, events)을 재생만 한다.
## 같은 입력이면 항상 같은 결과가 나온다(무작위 없음).
##
## 규칙
## - 각 유닛은 (1 / 공속)초마다 상대 팀의 맨 앞(살아 있는 가장 작은 번호) 유닛을 때린다.
## - 피해 = max(1, 공격력 - 상대 방어력)
## - 매 틱마다 회복량만큼 체력이 찬다(최대 체력까지).
## - 한쪽이 전멸하면 끝. 제한 시간이 지나면 남은 체력 비율이 높은 쪽이 이긴다.

const DT := 0.1
const MAX_TIME := 60.0

const BASE_HP := 40.0
const BASE_ATK := 1.0
const BASE_SPD := 0.8
const MIN_SPD := 0.2


## 가방 하나 + 팀 보너스 → 전투 능력치.
static func unit_stats(pack: Backpack, bonus: Dictionary = {}) -> Dictionary:
	var s := {"hp": BASE_HP, "atk": BASE_ATK, "armor": 0.0, "spd": BASE_SPD, "regen": 0.0}
	for item in pack.items():
		var st := item.stats()
		for k: String in st.keys():
			s[k] = float(s.get(k, 0.0)) + float(st[k])
	s["atk"] *= 1.0 + float(bonus.get("atk_mult", 0.0))
	s["spd"] = maxf(MIN_SPD, s["spd"] * (1.0 + float(bonus.get("spd_mult", 0.0))))
	s["armor"] += float(bonus.get("armor", 0.0))
	s["regen"] += float(bonus.get("regen", 0.0))
	return s


## 가방 목록 → 전투에 나가는 유닛 능력치 목록 (빈 가방은 빠진다, 시너지 반영).
static func team_stats(packs: Array[Backpack]) -> Array[Dictionary]:
	var active: Array[Backpack] = []
	for p in packs:
		if not p.is_empty():
			active.append(p)
	var bonus := Synergy.bonuses(Synergy.count_tags(active))
	var out: Array[Dictionary] = []
	for p in active:
		out.append(unit_stats(p, bonus))
	return out


static func damage(atk: float, armor: float) -> float:
	return maxf(1.0, atk - armor)


## 반환값
##   winner:   "a" | "b"
##   duration: 끝난 시각(초)
##   frames:   틱마다 [팀 a 체력 배열, 팀 b 체력 배열]  (frames[0] 은 시작 상태)
##   events:   [{t, side, src, dst, dmg}]  side 는 때린 쪽 ("a" | "b")
##   max_a, max_b: 최대 체력 배열
static func simulate(team_a: Array[Dictionary], team_b: Array[Dictionary]) -> Dictionary:
	var sides := {"a": _make_fighters(team_a), "b": _make_fighters(team_b)}
	var frames: Array = [_snapshot(sides)]
	var events: Array[Dictionary] = []
	var t := 0.0
	var winner := ""
	while winner == "" and t < MAX_TIME - 0.0001:
		t += DT
		for side: String in ["a", "b"]:
			var foe_side := "b" if side == "a" else "a"
			for i in sides[side].size():
				var f: Dictionary = sides[side][i]
				if f["hp"] <= 0.0:
					continue
				f["hp"] = minf(f["max_hp"], f["hp"] + f["regen"] * DT)
				f["cd"] -= DT
				if f["cd"] > 0.0001:
					continue
				var target := _front(sides[foe_side])
				if target < 0:
					break
				var foe: Dictionary = sides[foe_side][target]
				var dmg := damage(f["atk"], foe["armor"])
				foe["hp"] = maxf(0.0, foe["hp"] - dmg)
				f["cd"] += 1.0 / f["spd"]
				events.append({"t": t, "side": side, "src": i, "dst": target, "dmg": dmg})
		frames.append(_snapshot(sides))
		var a_alive := _front(sides["a"]) >= 0
		var b_alive := _front(sides["b"]) >= 0
		if not b_alive:
			winner = "a"
		elif not a_alive:
			winner = "b"
	if winner == "":
		winner = "a" if _hp_ratio(sides["a"]) > _hp_ratio(sides["b"]) else "b"
	return {
		"winner": winner,
		"duration": t,
		"frames": frames,
		"events": events,
		"max_a": _max_hp(sides["a"]),
		"max_b": _max_hp(sides["b"]),
	}


static func _make_fighters(team: Array[Dictionary]) -> Array:
	var out: Array = []
	for s in team:
		var spd: float = maxf(MIN_SPD, float(s["spd"]))
		out.append({
			"hp": float(s["hp"]), "max_hp": float(s["hp"]), "atk": float(s["atk"]),
			"armor": float(s["armor"]), "spd": spd, "regen": float(s["regen"]),
			"cd": 1.0 / spd,
		})
	return out


static func _front(fighters: Array) -> int:
	for i in fighters.size():
		if fighters[i]["hp"] > 0.0:
			return i
	return -1


static func _snapshot(sides: Dictionary) -> Array:
	var a := PackedFloat32Array()
	var b := PackedFloat32Array()
	for f: Dictionary in sides["a"]:
		a.append(f["hp"])
	for f: Dictionary in sides["b"]:
		b.append(f["hp"])
	return [a, b]


static func _hp_ratio(fighters: Array) -> float:
	var hp := 0.0
	var mx := 0.0
	for f: Dictionary in fighters:
		hp += f["hp"]
		mx += f["max_hp"]
	return hp / mx if mx > 0.0 else 0.0


static func _max_hp(fighters: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for f: Dictionary in fighters:
		out.append(f["max_hp"])
	return out
