class_name SkillMeter
extends RefCounted
## 운과 실력의 비율 측정 (설계 기준 1).
## 실력이 다른 플레이어(정책)들이 같은 시드들로 출전 풀 상대와 한 판씩 끝까지 싸운다.
## 라운드 구간마다 승패 중 "정책 차이로 설명되는 몫"(eta², 0~1)을 실력 몫으로 본다.
## 나머지는 같은 정책 안의 편차 = 운(상점·상대 뽑기)의 몫.
## 초반 구간은 실력 몫이 작고, 라운드가 오를수록 커지면 기준 1을 지킨 것이다.

const POLICIES := ["random", "bot"]
const POLICY_NAMES := {"random": "무작위", "bot": "기본 봇"}
const MAX_ROUNDS := 80
const BRACKET := 5


static func make_player(policy: String, seed_value: int, pool: OpponentPool) -> Bot:
	var style := RandomNumberGenerator.new()
	style.seed = seed_value
	var p: Bot = RandomBot.new(seed_value, style) if policy == "random" else Bot.new(seed_value, style)
	if policy == "bot":
		# 실력 비교가 목적이라 성향은 고정 (원하는 유닛 6, 가끔 새로고침)
		p.unit_target = 6
		p.reroll_chance = 0.3
		p.keep_gold = 0
	p.state.opponents = pool
	return p


## 한 판: 라운드마다 {round, won, hp_loss}. 체력 0 이 되거나 MAX_ROUNDS 에서 끝.
static func play_run(policy: String, seed_value: int, pool: OpponentPool, max_rounds: int = MAX_ROUNDS) -> Array:
	var p := make_player(policy, seed_value, pool)
	var out: Array = []
	while not p.state.game_over and p.state.round_no <= max_rounds:
		var r := p.state.round_no
		p.shop_turn()
		var s := p.state.apply_result(p.state.fight())
		out.append({"round": r, "won": bool(s["won"]), "hp_loss": int(s["hp_loss"])})
	return out


## runs[policy] = [판 기록 Array, ...] → 보고서
static func measure(runs_count: int, base_seed: int, pool: OpponentPool, max_rounds: int = MAX_ROUNDS) -> Dictionary:
	var runs := {}
	for policy: String in POLICIES:
		runs[policy] = []
		for k in runs_count:
			runs[policy].append(play_run(policy, hash([base_seed, k]), pool, max_rounds))
	return summarize(runs)


static func summarize(runs: Dictionary) -> Dictionary:
	var brackets: Array = []
	var last := 0
	for policy: String in runs.keys():
		for run: Array in runs[policy]:
			if not run.is_empty():
				last = maxi(last, int(run[-1]["round"]))
	var start := 1
	while start <= last:
		var end := start + BRACKET - 1
		var groups := {}
		for policy: String in runs.keys():
			var ys: Array[float] = []
			for run: Array in runs[policy]:
				for e: Dictionary in run:
					if int(e["round"]) >= start and int(e["round"]) <= end:
						ys.append(1.0 if e["won"] else 0.0)
			groups[policy] = ys
		brackets.append({"from": start, "to": end, "skill": eta_squared(groups), "win_rate": _rates(groups), "samples": _counts(groups)})
		start = end + 1
	var survival := {}
	for policy: String in runs.keys():
		var lens: Array[float] = []
		for run: Array in runs[policy]:
			lens.append(float(run[-1]["round"]) if not run.is_empty() else 0.0)
		survival[policy] = {"mean": _mean(lens), "std": _std(lens)}
	var all_groups := {}
	for policy: String in survival.keys():
		var lens: Array[float] = []
		for run: Array in runs[policy]:
			lens.append(float(run[-1]["round"]) if not run.is_empty() else 0.0)
		all_groups[policy] = lens
	return {"brackets": brackets, "survival": survival, "survival_skill": eta_squared(all_groups)}


## 집단 차이로 설명되는 분산의 비율 (0~1). 값이 하나뿐인 집단만 있거나 분산이 없으면 0.
static func eta_squared(groups: Dictionary) -> float:
	var all: Array[float] = []
	for g: String in groups.keys():
		all.append_array(groups[g])
	if all.size() < 2:
		return 0.0
	var grand := _mean(all)
	var total := 0.0
	for y in all:
		total += (y - grand) * (y - grand)
	if total <= 0.0:
		return 0.0
	var between := 0.0
	for g: String in groups.keys():
		var ys: Array[float] = groups[g]
		if ys.is_empty():
			continue
		var m := _mean(ys)
		between += ys.size() * (m - grand) * (m - grand)
	return between / total


static func format_report(rep: Dictionary) -> String:
	var lines: PackedStringArray = []
	var head := "| 라운드 | 실력 몫 |"
	var sep := "|---|---|"
	for p: String in POLICIES:
		head += " %s 승률 (표본) |" % POLICY_NAMES[p]
		sep += "---|"
	lines.append(head)
	lines.append(sep)
	for b: Dictionary in rep["brackets"]:
		var row := "| %d~%d | %s |" % [b["from"], b["to"], _bar(float(b["skill"]))]
		for p: String in POLICIES:
			var n: int = b["samples"].get(p, 0)
			row += (" %d%% (%d) |" % [roundi(float(b["win_rate"][p]) * 100.0), n]) if n > 0 else " - |"
		lines.append(row)
	lines.append("")
	for p: String in POLICIES:
		var s: Dictionary = rep["survival"][p]
		lines.append("- %s: 평균 %.1f라운드 생존 (표준편차 %.1f)" % [POLICY_NAMES[p], s["mean"], s["std"]])
	lines.append("- 생존 라운드 중 실력 몫: %d%%" % roundi(float(rep["survival_skill"]) * 100.0))
	return "\n".join(lines)


static func _bar(v: float) -> String:
	return "%d%% %s" % [roundi(v * 100.0), "█".repeat(roundi(v * 20.0))]


static func _rates(groups: Dictionary) -> Dictionary:
	var out := {}
	for g: String in groups.keys():
		var ys: Array[float] = groups[g]
		out[g] = _mean(ys) if not ys.is_empty() else 0.0
	return out


static func _counts(groups: Dictionary) -> Dictionary:
	var out := {}
	for g: String in groups.keys():
		out[g] = (groups[g] as Array).size()
	return out


static func _mean(ys: Array[float]) -> float:
	if ys.is_empty():
		return 0.0
	var s := 0.0
	for y in ys:
		s += y
	return s / ys.size()


static func _std(ys: Array[float]) -> float:
	if ys.size() < 2:
		return 0.0
	var m := _mean(ys)
	var s := 0.0
	for y in ys:
		s += (y - m) * (y - m)
	return sqrt(s / (ys.size() - 1))
