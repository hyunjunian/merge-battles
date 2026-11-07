class_name Skills
extends RefCounted
## 아이템 스킬. 아이템 정의의 "skill": {"type": ..., 값...} 으로 붙고, 전투(BattleSim)에서 발동한다.
## 한 유닛이 여러 스킬 아이템을 가지면 aggregate() 가 하나의 스킬 묶음으로 합친다.
##
## 종류
##   lifesteal  {pct}               공격 피해의 pct 만큼 체력 회복
##   poison     {dps, dur}          맞은 적이 dur 초 동안 초당 dps 피해 (방어 무시)
##   crit       {every, mult}       every 번째 공격마다 mult 배 피해
##   chain      {every, jumps, pct} every 번째 공격마다 근처 적 jumps 명에게 pct 배 피해가 튄다
##   heal       {amount, cd}        cd 초마다 체력 비율이 가장 낮은 아군 amount 회복
##   shield     {amount}            전투 시작 때 amount 보호막 (피해를 먼저 막음)
##   rage       {below, spd}        체력이 below 비율 아래로 처음 떨어지면 공속 +spd 비율
##   fireball   {dmg, radius, cd}   cd 초마다 목표 주변 radius 안의 적 모두에게 dmg 피해
##   thorns     {dmg}               근접·원거리 공격을 맞을 때마다 공격자에게 dmg 피해
##   revive     {pct}               처음 쓰러질 때 최대 체력의 pct 로 되살아남

const NAMES := {
	"lifesteal": "흡혈", "poison": "독", "crit": "치명타", "chain": "연쇄 번개", "heal": "치유",
	"shield": "보호막", "rage": "분노", "fireball": "화염구", "thorns": "가시", "revive": "부활",
}


## 스킬 목록 → 합친 묶음 (없는 스킬은 0)
static func aggregate(list: Array) -> Dictionary:
	var out := {
		"lifesteal": 0.0, "poison_dps": 0.0, "poison_dur": 0.0,
		"crit_every": 0, "crit_mult": 1.0,
		"chain_every": 0, "chain_jumps": 0, "chain_pct": 0.0,
		"heal_amount": 0.0, "heal_cd": 0.0,
		"shield": 0.0, "rage_below": 0.0, "rage_spd": 0.0,
		"fireball_dmg": 0.0, "fireball_radius": 0.0, "fireball_cd": 0.0,
		"thorns": 0.0, "revive": 0.0,
	}
	for sk: Dictionary in list:
		match sk.get("type", ""):
			"lifesteal":
				out["lifesteal"] += float(sk["pct"])
			"poison":
				out["poison_dps"] += float(sk["dps"])
				out["poison_dur"] = maxf(out["poison_dur"], float(sk["dur"]))
			"crit":
				var every := int(sk["every"])
				if out["crit_every"] == 0 or every < out["crit_every"]:
					out["crit_every"] = every
				out["crit_mult"] = maxf(out["crit_mult"], float(sk["mult"]))
			"chain":
				var every := int(sk["every"])
				if out["chain_every"] == 0 or every < out["chain_every"]:
					out["chain_every"] = every
				out["chain_jumps"] += int(sk["jumps"])
				out["chain_pct"] = maxf(out["chain_pct"], float(sk["pct"]))
			"heal":
				out["heal_amount"] += float(sk["amount"])
				out["heal_cd"] = float(sk["cd"]) if out["heal_cd"] == 0.0 else minf(out["heal_cd"], float(sk["cd"]))
			"shield":
				out["shield"] += float(sk["amount"])
			"rage":
				out["rage_below"] = maxf(out["rage_below"], float(sk["below"]))
				out["rage_spd"] += float(sk["spd"])
			"fireball":
				out["fireball_dmg"] += float(sk["dmg"])
				out["fireball_radius"] = maxf(out["fireball_radius"], float(sk["radius"]))
				out["fireball_cd"] = float(sk["cd"]) if out["fireball_cd"] == 0.0 else minf(out["fireball_cd"], float(sk["cd"]))
			"thorns":
				out["thorns"] += float(sk["dmg"])
			"revive":
				out["revive"] = maxf(out["revive"], float(sk["pct"]))
	return out


static func has_any(agg: Dictionary) -> bool:
	for k: String in ["lifesteal", "poison_dps", "heal_amount", "shield", "rage_spd", "fireball_dmg", "thorns", "revive"]:
		if float(agg[k]) > 0.0:
			return true
	return int(agg["crit_every"]) > 0 or int(agg["chain_every"]) > 0


static func describe(sk: Dictionary) -> String:
	var t: String = sk.get("type", "")
	var n: String = NAMES.get(t, t)
	match t:
		"lifesteal":
			return "%s: 공격 피해의 %d%% 만큼 체력 회복" % [n, roundi(float(sk["pct"]) * 100.0)]
		"poison":
			return "%s: 맞은 적이 %d초 동안 초당 %d 피해 (방어 무시)" % [n, roundi(sk["dur"]), roundi(sk["dps"])]
		"crit":
			return "%s: %d번째 공격마다 %.1f배 피해" % [n, int(sk["every"]), float(sk["mult"])]
		"chain":
			return "%s: %d번째 공격마다 근처 적 %d명에게 %d%% 피해" % [n, int(sk["every"]), int(sk["jumps"]), roundi(float(sk["pct"]) * 100.0)]
		"heal":
			return "%s: %d초마다 가장 다친 아군 체력 %d 회복" % [n, roundi(sk["cd"]), roundi(sk["amount"])]
		"shield":
			return "%s: 전투 시작 때 피해 %d 를 막는 보호막" % [n, roundi(sk["amount"])]
		"rage":
			return "%s: 체력 %d%% 아래가 되면 공속 +%d%%" % [n, roundi(float(sk["below"]) * 100.0), roundi(float(sk["spd"]) * 100.0)]
		"fireball":
			return "%s: %d초마다 목표 주변 적 모두에게 %d 피해" % [n, roundi(sk["cd"]), roundi(sk["dmg"])]
		"thorns":
			return "%s: 공격받을 때마다 공격자에게 %d 피해" % [n, roundi(sk["dmg"])]
		"revive":
			return "%s: 처음 쓰러질 때 체력 %d%% 로 되살아남" % [n, roundi(float(sk["pct"]) * 100.0)]
	return n
