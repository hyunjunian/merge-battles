class_name Synergy
extends RefCounted
## 팀 시너지. 전투에 나가는 모든 유닛의 가방에서 같은 태그 아이템 수를 센다.
## 단계(2개, 4개)를 넘으면 팀 전체에 보너스가 붙는다.

const TRAITS: Dictionary = {
	"warrior": {"name": "전사", "thresholds": [2, 4], "stat": "atk_mult", "values": [0.2, 0.5], "desc": "공격력 +%d%%"},
	"guard": {"name": "수호", "thresholds": [2, 4], "stat": "armor", "values": [2.0, 5.0], "desc": "방어 +%d"},
	"nature": {"name": "자연", "thresholds": [2, 4], "stat": "regen", "values": [1.0, 3.0], "desc": "회복 +%d/초"},
	"arcane": {"name": "비전", "thresholds": [2, 4], "stat": "spd_mult", "values": [0.25, 0.6], "desc": "공속 +%d%%"},
}

const TAG_ORDER: Array[String] = ["warrior", "guard", "nature", "arcane"]


static func count_tags(packs: Array[Backpack]) -> Dictionary:
	var counts := {}
	for tag in TAG_ORDER:
		counts[tag] = 0
	for pack in packs:
		for item in pack.items():
			var t := item.tag()
			counts[t] = int(counts.get(t, 0)) + 1
	return counts


## 0 = 비활성, 1 = 1단계, 2 = 2단계
static func level(tag: String, count: int) -> int:
	var lv := 0
	for th: int in TRAITS[tag]["thresholds"]:
		if count >= th:
			lv += 1
	return lv


## 팀 전체에 적용할 보너스: {"atk_mult", "armor", "regen", "spd_mult"}
static func bonuses(counts: Dictionary) -> Dictionary:
	var out := {"atk_mult": 0.0, "armor": 0.0, "regen": 0.0, "spd_mult": 0.0}
	for tag in TAG_ORDER:
		var lv := level(tag, int(counts.get(tag, 0)))
		if lv > 0:
			var t: Dictionary = TRAITS[tag]
			out[t["stat"]] += float(t["values"][lv - 1])
	return out


static func describe(tag: String, count: int) -> String:
	var t: Dictionary = TRAITS[tag]
	var lv := level(tag, count)
	var thresholds: Array = t["thresholds"]
	var next: int = thresholds[mini(lv, thresholds.size() - 1)]
	var text := "%s %d/%d" % [t["name"], count, next if lv < thresholds.size() else thresholds[-1]]
	if lv > 0:
		var v: float = t["values"][lv - 1]
		var shown := roundi(v * 100.0) if t["stat"] in ["atk_mult", "spd_mult"] else roundi(v)
		text += " (" + (t["desc"] % shown) + ")"
	return text
