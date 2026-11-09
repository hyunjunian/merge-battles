class_name BattleReport
extends RefCounted
## 전투 뒤 유닛별 기여도: BattleSim.simulate 결과의 이벤트를 모아 센다.
##   dealt   준 피해 (공격·연쇄·독·가시·화염)
##   taken   받은 피해
##   healed  회복시킨 양 (자신·아군)
##   shielded 만든 보호막
## 반환: {"a": [유닛마다 {dealt, taken, healed, shielded}], "b": [...]}

const DAMAGE_KINDS := ["attack", "chain", "poison", "thorns", "burn"]


static func contribution(result: Dictionary) -> Dictionary:
	var out := {"a": _blank(result["max_a"].size()), "b": _blank(result["max_b"].size())}
	for e: Dictionary in result["events"]:
		var side: String = e["side"]
		var foe := "b" if side == "a" else "a"
		var kind: String = e["kind"]
		var src := int(e.get("src", -1))
		if kind in DAMAGE_KINDS:
			var dmg := float(e.get("dmg", 0.0))
			_add(out[side], src, "dealt", dmg)
			_add(out[foe], int(e.get("dst", -1)), "taken", dmg)
		elif kind == "heal":
			_add(out[side], src, "healed", float(e.get("amount", 0.0)))
		elif kind == "shield":
			_add(out[side], src, "shielded", float(e.get("dmg", 0.0)))
	return out


## 그 편에서 key 가 가장 큰 유닛 번호 (모두 0 이면 -1)
static func top(rows: Array, key: String) -> int:
	var best := -1
	var best_v := 0.0
	for i in rows.size():
		var v := float(rows[i][key])
		if v > best_v:
			best_v = v
			best = i
	return best


static func _blank(n: int) -> Array:
	var rows: Array = []
	for i in n:
		rows.append({"dealt": 0.0, "taken": 0.0, "healed": 0.0, "shielded": 0.0})
	return rows


static func _add(rows: Array, idx: int, key: String, v: float) -> void:
	if idx >= 0 and idx < rows.size():
		rows[idx][key] += v
