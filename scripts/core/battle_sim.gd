class_name BattleSim
extends RefCounted
## 전장 자동 전투 시뮬레이션. 결과를 한 번에 계산하고, 화면은 그 기록(frames, events)을 재생만 한다.
## 같은 입력이면 항상 같은 결과가 나온다(무작위 없음).
##
## 전장: x ∈ [-HALF_W, HALF_W], z ∈ [-HALF_D, HALF_D] 의 평면. 우리 팀(a)은 +z 쪽, 상대(b)는 -z 쪽에서 시작한다.
##
## 유닛 AI (틱마다)
## 1. 목표 고르기: 가장 가까운 적. 지금 목표보다 RETARGET_MARGIN 이상 가까운 적이 생기면 바꾼다.
## 2. 원거리 유닛(사거리 > MELEE_RANGE)은 적이 KITE_DISTANCE 안으로 붙으면 뒤로 물러난다.
## 3. 사거리 밖이면 목표 쪽으로 이동, 안이면 멈춰서 공격.
## 4. 공격: (1 / 공속)초마다. 피해 = max(1, 공격력 - 상대 방어력).
## 5. 유닛끼리 겹치면 서로 밀어낸다. 전장 밖으로는 못 나간다.
## 한쪽이 전멸하면 끝. 제한 시간이 지나면 남은 체력 비율이 높은 쪽이 이긴다.

const DT := 0.1
const MAX_TIME := 60.0

const HALF_W := 4.0
const HALF_D := 7.0
const START_Z := 4.0
const SPACING := 2.2
## 유닛 반지름 (화면 모형: 고리 반지름 0.5 x 크기 1.3 = 0.65)
const RADIUS := 0.65

const BASE_HP := 40.0
const BASE_ATK := 1.0
const BASE_SPD := 0.8
const MIN_SPD := 0.2
const BASE_MOVE := 2.0
const MELEE_RANGE := 0.6
const KITE_DISTANCE := 1.8
const RETARGET_MARGIN := 1.0
const CHAIN_RANGE := 3.5

## frames 의 유닛 하나당 숫자: x, z, hp, cd(다음 공격까지), spd(현재 공속), shield, heal_t, fire_t
const STRIDE := 8
const FRAME_KEYS := ["x", "z", "hp", "cd", "spd", "shield", "heal_t", "fire_t"]


## 유닛 하나 + 팀 보너스 → 전투 능력치. 유닛 기본 능력치에 가방 속 아이템을 더한다.
static func unit_stats(pack: Backpack, bonus: Dictionary = {}) -> Dictionary:
	var s := {"hp": BASE_HP, "atk": BASE_ATK, "armor": 0.0, "spd": BASE_SPD, "regen": 0.0, "range": MELEE_RANGE, "move": BASE_MOVE}
	var base := pack.base_stats()
	for k: String in base.keys():
		s[k] = float(base[k])
	var skill_list: Array = []
	for item in pack.items():
		var st := item.stats()
		for k: String in st.keys():
			s[k] = float(s.get(k, 0.0)) + float(st[k])
		s["range"] = maxf(s["range"], float(item.def().get("range", MELEE_RANGE)))
		if item.has_skill():
			skill_list.append(item.skill())
	s["skills"] = Skills.aggregate(skill_list)
	s["atk"] *= 1.0 + float(bonus.get("atk_mult", 0.0))
	s["spd"] = maxf(MIN_SPD, s["spd"] * (1.0 + float(bonus.get("spd_mult", 0.0))))
	s["armor"] += float(bonus.get("armor", 0.0))
	s["regen"] += float(bonus.get("regen", 0.0))
	return s


## 유닛 목록 → 전투 능력치 목록 (시너지 반영). 각 항목의 "pos" 는 그 유닛 자리의 시작 위치.
static func team_stats(packs: Array[Backpack], side: String = "a") -> Array[Dictionary]:
	var bonus := Synergy.bonuses(Synergy.count_tags(packs))
	var out: Array[Dictionary] = []
	for i in packs.size():
		var s := unit_stats(packs[i], bonus)
		if packs[i].slot < 0 and not packs[i].has_field_pos:
			packs[i].slot = i
		s["pos"] = packs[i].start_pos(side)
		out.append(s)
	return out


static func damage(atk: float, armor: float) -> float:
	return maxf(1.0, atk - armor)


static func is_ranged(stats: Dictionary) -> bool:
	return float(stats.get("range", MELEE_RANGE)) > MELEE_RANGE + 0.01


## 전장 자리: 앞줄 0~2, 뒷줄 3~5. 우리 팀(a)은 +z 쪽, 상대(b)는 -z 쪽.
const SLOT_COUNT := 6
const SLOT_X := [-2.6, 0.0, 2.6]
const FRONT_Z := 3.0
const BACK_Z := 5.4


static func slot_position(side: String, slot: int) -> Vector2:
	var s := clampi(slot, 0, SLOT_COUNT - 1)
	var x: float = SLOT_X[s % 3]
	var z := FRONT_Z if s < 3 else BACK_Z
	return Vector2(x, z if side == "a" else -z)


## 우리 진영: 가운데 선에서 OWN_MIN_Z 이상 떨어진 +z 쪽 절반. 유닛끼리는 MIN_GAP 이상 떨어뜨린다.
const OWN_MIN_Z := 1.0
## 배치할 때 유닛 중심 사이 최소 거리 = 모형 지름 + 틈 (비스듬한 카메라에서 앞 유닛 몸통이 뒤 유닛을 가리지 않게)
const MIN_GAP := RADIUS * 2.0 + 0.35


static func clamp_own(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, -HALF_W, HALF_W), clampf(p.y, OWN_MIN_Z, HALF_D))


static func overlaps(p: Vector2, others: Array[Vector2]) -> bool:
	for o in others:
		if p.distance_to(o) < MIN_GAP - 0.001:
			return true
	return false


## p 를 우리 진영 안으로 넣고, others 와 겹치면(MIN_GAP 보다 가까우면) 가장 가까운 빈자리로 옮긴다.
## 빈자리는 p 둘레를 점점 넓게 돌며 찾는다. 진영이 꽉 차 못 찾으면 진영 안으로만 넣어 돌려준다.
static func place_own(p: Vector2, others: Array[Vector2]) -> Vector2:
	var q := clamp_own(p)
	if not overlaps(q, others):
		return q
	var step := 0.15
	var r := step
	while r <= HALF_W * 2.0 + HALF_D:
		var n := maxi(8, int(TAU * r / step))
		var best := Vector2.INF
		var best_d := INF
		for k in n:
			var c := clamp_own(q + Vector2.from_angle(TAU * k / n) * r)
			if overlaps(c, others):
				continue
			var d := c.distance_to(q)
			if d < best_d:
				best_d = d
				best = c
		if best != Vector2.INF:
			return best
		r += step
	return q


## 자리 번호 없이 줄 세울 때 (테스트용): 가운데 정렬 한 줄.
static func start_position(side: String, index: int, count: int) -> Vector2:
	var x := (index - (count - 1) / 2.0) * SPACING
	return Vector2(x, START_Z if side == "a" else -START_Z)


## 반환값
##   winner:   "a" | "b"
##   duration: 끝난 시각(초)
##   frames:   틱마다 [팀 a 배열, 팀 b 배열]. 배열은 유닛마다 (x, z, hp). frames[0] 은 시작 상태.
##   events:   [{t, kind, side, src, dst, dmg, ...}]  side 는 일으킨 쪽 ("a" | "b")
##             kind: attack(+ranged, crit) | chain(+from) | poison | thorns | fireball(+at: Vector2) | burn
##                   dst 는 side 의 반대편 유닛 번호.
##                   heal(dst 는 같은 편, amount) | shield | rage | revive (src == dst, 같은 편)
##   max_a, max_b: 최대 체력 배열
##   ranged_a, ranged_b: 원거리 유닛 여부 배열
static func simulate(team_a: Array[Dictionary], team_b: Array[Dictionary]) -> Dictionary:
	var sides := {"a": _make_fighters("a", team_a), "b": _make_fighters("b", team_b)}
	var frames: Array = [_snapshot(sides)]
	var events: Array[Dictionary] = []
	var t := 0.0
	var winner := ""
	while winner == "" and t < MAX_TIME - 0.0001:
		t += DT
		for side: String in ["a", "b"]:
			var foe_side := "b" if side == "a" else "a"
			for i in sides[side].size():
				_step_fighter(sides[side][i], side, i, sides[side], sides[foe_side], t, events)
		_separate(sides)
		frames.append(_snapshot(sides))
		var a_alive := _alive_count(sides["a"]) > 0
		var b_alive := _alive_count(sides["b"]) > 0
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
		"max_a": _column(sides["a"], "max_hp"),
		"max_b": _column(sides["b"], "max_hp"),
		"ranged_a": _ranged_flags(sides["a"]),
		"ranged_b": _ranged_flags(sides["b"]),
	}


## 한 유닛의 한 틱: 회복·독·스킬 타이머 → 목표 선택 → 이동 → 공격.
static func _step_fighter(f: Dictionary, side: String, i: int, allies: Array, foes: Array, t: float, events: Array[Dictionary]) -> void:
	if f["hp"] <= 0.0:
		return
	var foe_side := "b" if side == "a" else "a"
	var sk: Dictionary = f["sk"]
	if not f["started"]:
		f["started"] = true
		if f["shield"] > 0.0:
			events.append({"t": t, "kind": "shield", "side": side, "src": i, "dst": i, "dmg": f["shield"]})
	f["hp"] = minf(f["max_hp"], f["hp"] + f["regen"] * DT)
	f["cd"] = maxf(0.0, f["cd"] - DT)
	_tick_poison(f, foe_side, i, t, events)
	if f["hp"] <= 0.0:
		return
	_tick_heal(f, side, i, allies, t, events)
	var target := choose_target(f["pos"], int(f["target"]), foes)
	f["target"] = target
	if target < 0:
		return
	_tick_fireball(f, side, i, foes, target, t, events)
	var foe: Dictionary = foes[target]
	var pos: Vector2 = f["pos"]
	var to_foe: Vector2 = foe["pos"] - pos
	var dist := to_foe.length()
	var reach: float = f["range"] + RADIUS * 2.0
	var step: float = f["move"] * DT
	var ranged: bool = f["range"] > MELEE_RANGE + 0.01
	if ranged and dist < KITE_DISTANCE and f["cd"] > 0.0:
		# 원거리: 쏠 준비가 안 됐을 때 적이 붙으면 물러난다. 벽에 막히면 옆으로 빠진다.
		f["pos"] = kite_step(pos, foe["pos"], step * 0.8)
	elif dist > reach:
		f["pos"] = _clamp_field(pos + to_foe.normalized() * minf(step, dist - reach + 0.05))
	elif f["cd"] <= 0.0001 and foe["hp"] > 0.0:
		_attack(f, side, i, allies, foes, target, ranged, t, events)
		f["cd"] = 1.0 / f["spd"]


## 기본 공격과 공격에 붙는 스킬 (치명타, 흡혈, 독, 가시, 연쇄 번개)
static func _attack(f: Dictionary, side: String, i: int, allies: Array, foes: Array, target: int, ranged: bool, t: float, events: Array[Dictionary]) -> void:
	var sk: Dictionary = f["sk"]
	var foe_side := "b" if side == "a" else "a"
	var foe: Dictionary = foes[target]
	f["attacks"] += 1
	var dmg := damage(f["atk"], foe["armor"])
	var crit := int(sk["crit_every"]) > 0 and int(f["attacks"]) % int(sk["crit_every"]) == 0
	if crit:
		dmg *= float(sk["crit_mult"])
	events.append({"t": t, "kind": "attack", "side": side, "src": i, "dst": target, "dmg": dmg, "ranged": ranged, "crit": crit})
	var dealt := _apply_damage(foe, dmg, foe_side, target, t, events)
	if sk["lifesteal"] > 0.0 and dealt > 0.0:
		var heal := dealt * float(sk["lifesteal"])
		f["hp"] = minf(f["max_hp"], f["hp"] + heal)
		if heal >= 1.0:
			events.append({"t": t, "kind": "heal", "side": side, "src": i, "dst": i, "amount": heal})
	if sk["poison_dps"] > 0.0:
		foe["poison_dps"] = maxf(foe["poison_dps"], float(sk["poison_dps"]))
		foe["poison_left"] = float(sk["poison_dur"])
	var thorns: float = foe["sk"]["thorns"]
	if thorns > 0.0:
		events.append({"t": t, "kind": "thorns", "side": foe_side, "src": target, "dst": i, "dmg": thorns})
		_apply_damage(f, thorns, side, i, t, events)
	if int(sk["chain_every"]) > 0 and int(f["attacks"]) % int(sk["chain_every"]) == 0:
		var from: Vector2 = foe["pos"]
		for j in nearest_others(foes, target, int(sk["chain_jumps"]), CHAIN_RANGE):
			var jd := damage(f["atk"] * float(sk["chain_pct"]), foes[j]["armor"])
			events.append({"t": t, "kind": "chain", "side": side, "src": i, "from": target, "dst": j, "dmg": jd})
			_apply_damage(foes[j], jd, foe_side, j, t, events)
			from = foes[j]["pos"]


## 피해 적용: 보호막이 먼저 막고, 쓰러지면 부활을 확인하고, 체력이 낮아지면 분노를 확인한다.
## 실제로 깎인 체력(보호막 제외)을 돌려준다.
static func _apply_damage(f: Dictionary, amount: float, side: String, idx: int, t: float, events: Array[Dictionary]) -> float:
	if f["hp"] <= 0.0 or amount <= 0.0:
		return 0.0
	var rest := amount
	if f["shield"] > 0.0:
		var absorbed := minf(f["shield"], rest)
		f["shield"] -= absorbed
		rest -= absorbed
	var before: float = f["hp"]
	f["hp"] = maxf(0.0, f["hp"] - rest)
	var sk: Dictionary = f["sk"]
	if f["hp"] <= 0.0 and sk["revive"] > 0.0 and not f["revived"]:
		f["revived"] = true
		f["hp"] = f["max_hp"] * float(sk["revive"])
		f["poison_left"] = 0.0
		events.append({"t": t, "kind": "revive", "side": side, "src": idx, "dst": idx})
	elif f["hp"] > 0.0 and sk["rage_spd"] > 0.0 and not f["raged"] and f["hp"] < f["max_hp"] * float(sk["rage_below"]):
		f["raged"] = true
		f["spd"] *= 1.0 + float(sk["rage_spd"])
		events.append({"t": t, "kind": "rage", "side": side, "src": idx, "dst": idx})
	return before - maxf(f["hp"], 0.0) if f["hp"] < before else 0.0


## 독: 1초마다 쌓인 피해를 준다 (방어 무시). side 는 독을 건 쪽.
static func _tick_poison(f: Dictionary, poisoner_side: String, idx: int, t: float, events: Array[Dictionary]) -> void:
	if f["poison_left"] <= 0.0:
		return
	f["poison_left"] -= DT
	f["poison_acc"] += f["poison_dps"] * DT
	f["poison_tick"] += DT
	if f["poison_tick"] >= 1.0 - 0.0001 or f["poison_left"] <= 0.0:
		var dmg: float = f["poison_acc"]
		f["poison_acc"] = 0.0
		f["poison_tick"] = 0.0
		if f["poison_left"] <= 0.0:
			f["poison_dps"] = 0.0
		var my_side := "b" if poisoner_side == "a" else "a"
		events.append({"t": t, "kind": "poison", "side": poisoner_side, "src": -1, "dst": idx, "dmg": dmg})
		_apply_damage(f, dmg, my_side, idx, t, events)


## 치유: 쿨다운마다 체력 비율이 가장 낮은(다친) 아군을 회복
static func _tick_heal(f: Dictionary, side: String, i: int, allies: Array, t: float, events: Array[Dictionary]) -> void:
	var sk: Dictionary = f["sk"]
	if sk["heal_amount"] <= 0.0:
		return
	f["heal_timer"] -= DT
	if f["heal_timer"] > 0.0:
		return
	var best := -1
	var best_ratio := 1.0
	for j in allies.size():
		var a: Dictionary = allies[j]
		if a["hp"] <= 0.0:
			continue
		var ratio: float = a["hp"] / a["max_hp"]
		if ratio < best_ratio - 0.0001:
			best = j
			best_ratio = ratio
	if best < 0:
		f["heal_timer"] = 0.5
		return
	var target: Dictionary = allies[best]
	var amount := minf(float(sk["heal_amount"]), target["max_hp"] - target["hp"])
	target["hp"] += amount
	f["heal_timer"] = float(sk["heal_cd"])
	events.append({"t": t, "kind": "heal", "side": side, "src": i, "dst": best, "amount": amount})


## 화염구: 쿨다운마다 목표 주변 반경 안의 적 모두에게 피해 (방어 무시)
static func _tick_fireball(f: Dictionary, side: String, i: int, foes: Array, target: int, t: float, events: Array[Dictionary]) -> void:
	var sk: Dictionary = f["sk"]
	if sk["fireball_dmg"] <= 0.0:
		return
	f["fire_timer"] -= DT
	if f["fire_timer"] > 0.0:
		return
	f["fire_timer"] = float(sk["fireball_cd"])
	var at: Vector2 = foes[target]["pos"]
	var foe_side := "b" if side == "a" else "a"
	events.append({"t": t, "kind": "fireball", "side": side, "src": i, "dst": target, "at": at, "radius": float(sk["fireball_radius"])})
	for j in foes.size():
		if foes[j]["hp"] > 0.0 and foes[j]["pos"].distance_to(at) <= float(sk["fireball_radius"]):
			events.append({"t": t, "kind": "burn", "side": side, "src": i, "dst": j, "dmg": float(sk["fireball_dmg"])})
			_apply_damage(foes[j], float(sk["fireball_dmg"]), foe_side, j, t, events)


## target 을 뺀 살아 있는 적 중 target 에서 가까운 순으로 count 명 (max_dist 안)
static func nearest_others(foes: Array, target: int, count: int, max_dist: float) -> Array[int]:
	var cands: Array = []
	var from: Vector2 = foes[target]["pos"]
	for j in foes.size():
		if j == target or foes[j]["hp"] <= 0.0:
			continue
		var d: float = from.distance_to(foes[j]["pos"])
		if d <= max_dist:
			cands.append([d, j])
	cands.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	var out: Array[int] = []
	for c: Array in cands.slice(0, count):
		out.append(int(c[1]))
	return out


## 적에게서 멀어지는 한 걸음. 뒤가 막혀 거의 못 움직이면 전장 가운데 쪽 옆으로 비켜선다.
static func kite_step(pos: Vector2, enemy: Vector2, step: float) -> Vector2:
	var away := (pos - enemy).normalized() if pos.distance_to(enemy) > 0.0001 else Vector2(0, 1)
	var back := _clamp_field(pos + away * step)
	if back.distance_to(pos) >= step * 0.5:
		return back
	var side := Vector2(-away.y, away.x)
	if side.dot(-pos) < 0.0:
		side = -side
	return _clamp_field(pos + side * step)


## 가장 가까운 살아 있는 적. 지금 목표가 살아 있으면 RETARGET_MARGIN 이상 가까운 적이 있을 때만 바꾼다.
static func choose_target(pos: Vector2, current: int, foes: Array) -> int:
	var best := -1
	var best_d := INF
	for j in foes.size():
		if foes[j]["hp"] <= 0.0:
			continue
		var d := pos.distance_to(foes[j]["pos"])
		if d < best_d - 0.0001:
			best = j
			best_d = d
	if current >= 0 and current < foes.size() and foes[current]["hp"] > 0.0:
		var cur_d := pos.distance_to(foes[current]["pos"])
		if cur_d <= best_d + RETARGET_MARGIN:
			return current
	return best


## 살아 있는 유닛끼리 겹치면 반씩 밀어낸다 (양 팀 모두).
static func _separate(sides: Dictionary) -> void:
	var all: Array = []
	for side: String in ["a", "b"]:
		for f: Dictionary in sides[side]:
			if f["hp"] > 0.0:
				all.append(f)
	for n in all.size():
		for m in range(n + 1, all.size()):
			var p: Vector2 = all[n]["pos"]
			var q: Vector2 = all[m]["pos"]
			var d := p.distance_to(q)
			var min_d := RADIUS * 2.0
			if d >= min_d:
				continue
			var dir := (p - q).normalized() if d > 0.0001 else Vector2(1, 0)
			var push := (min_d - d) / 2.0
			all[n]["pos"] = _clamp_field(p + dir * push)
			all[m]["pos"] = _clamp_field(q - dir * push)


static func _clamp_field(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, -HALF_W, HALF_W), clampf(p.y, -HALF_D, HALF_D))


static func _make_fighters(side: String, team: Array[Dictionary]) -> Array:
	var out: Array = []
	for i in team.size():
		var s := team[i]
		var spd: float = maxf(MIN_SPD, float(s["spd"]))
		var sk: Dictionary = s.get("skills", Skills.aggregate([]))
		out.append({
			"hp": float(s["hp"]), "max_hp": float(s["hp"]), "atk": float(s["atk"]),
			"armor": float(s["armor"]), "spd": spd, "regen": float(s["regen"]),
			"range": float(s.get("range", MELEE_RANGE)), "move": float(s.get("move", BASE_MOVE)),
			"pos": s.get("pos", start_position(side, i, team.size())), "target": -1,
			"cd": 0.5 / spd,
			# 스킬 상태
			"sk": sk, "shield": float(sk["shield"]), "started": false, "attacks": 0,
			"poison_dps": 0.0, "poison_left": 0.0, "poison_acc": 0.0, "poison_tick": 0.0,
			"heal_timer": float(sk["heal_cd"]), "fire_timer": float(sk["fireball_cd"]) * 0.5,
			"raged": false, "revived": false,
		})
	return out


static func _alive_count(fighters: Array) -> int:
	var n := 0
	for f: Dictionary in fighters:
		if f["hp"] > 0.0:
			n += 1
	return n


static func _snapshot(sides: Dictionary) -> Array:
	var out: Array = []
	for side: String in ["a", "b"]:
		var arr := PackedFloat32Array()
		for f: Dictionary in sides[side]:
			var p: Vector2 = f["pos"]
			arr.append(p.x)
			arr.append(p.y)
			arr.append(f["hp"])
			arr.append(f["cd"])
			arr.append(f["spd"])
			arr.append(f["shield"])
			arr.append(maxf(0.0, f["heal_timer"]))
			arr.append(maxf(0.0, f["fire_timer"]))
		out.append(arr)
	return out


## 기록 읽기 도우미 (side: 0 = a, 1 = b)
static func frame_pos(frame: Array, side: int, i: int) -> Vector2:
	var arr: PackedFloat32Array = frame[side]
	return Vector2(arr[i * STRIDE], arr[i * STRIDE + 1])


static func frame_hp(frame: Array, side: int, i: int) -> float:
	var arr: PackedFloat32Array = frame[side]
	return arr[i * STRIDE + 2]


## 한 유닛의 그 순간 상태 {x, z, hp, cd, spd, shield, heal_t, fire_t}
static func frame_unit(frame: Array, side: int, i: int) -> Dictionary:
	var arr: PackedFloat32Array = frame[side]
	var out := {}
	for k in FRAME_KEYS.size():
		out[FRAME_KEYS[k]] = arr[i * STRIDE + k]
	return out


static func _hp_ratio(fighters: Array) -> float:
	var hp := 0.0
	var mx := 0.0
	for f: Dictionary in fighters:
		hp += f["hp"]
		mx += f["max_hp"]
	return hp / mx if mx > 0.0 else 0.0


static func _column(fighters: Array, key: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for f: Dictionary in fighters:
		out.append(f[key])
	return out


static func _ranged_flags(fighters: Array) -> Array[bool]:
	var out: Array[bool] = []
	for f: Dictionary in fighters:
		out.append(f["range"] > MELEE_RANGE + 0.01)
	return out
