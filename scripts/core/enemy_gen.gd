class_name EnemyGen
extends RefCounted
## 라운드별 상대 팀 생성. 라운드가 오를수록 예산·유닛 수·아이템 등급이 커진다.
## 같은 (라운드, 시드) 면 같은 팀이 나온다.

const MAX_UNITS := 3


## 플레이어 예산과 같은 공식에 라운드 배율을 곱한다. 초반엔 플레이어보다 약하고 후반엔 강하다.
static func budget_for_round(round_no: int) -> int:
	return roundi(float(GameState.budget_for_round(round_no)) * (0.7 + 0.06 * round_no))


static func unit_count(round_no: int) -> int:
	return clampi(1 + round_no / 2, 1, MAX_UNITS)


## 아이템 등급 확률: 2라운드부터 2성, 6라운드부터 3성이 섞인다.
static func roll_tier(round_no: int, rng: RandomNumberGenerator) -> int:
	var r := rng.randf()
	var p3 := clampf(0.06 * (round_no - 5), 0.0, 0.3)
	var p2 := clampf(0.12 * (round_no - 1), 0.0, 0.6)
	if r < p3:
		return 3
	if r < p3 + p2:
		return 2
	return 1


static func generate(round_no: int, seed_value: int) -> Array[Backpack]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([round_no, seed_value])
	var packs: Array[Backpack] = []
	for i in unit_count(round_no):
		packs.append(Backpack.new())
	var remaining := budget_for_round(round_no)
	var ids := ItemDB.ids()
	var failures := 0
	var next_pack := 0
	while remaining > 0 and failures < 40:
		var item := Item.new(ids[rng.randi_range(0, ids.size() - 1)], roll_tier(round_no, rng))
		if item.cost() > remaining:
			failures += 1
			continue
		var placed := false
		for k in packs.size():
			var pack := packs[(next_pack + k) % packs.size()]
			var spot := pack.find_spot(item)
			if spot != Backpack.NO_SPOT:
				pack.place(item, spot)
				placed = true
				break
		if placed:
			remaining -= item.cost()
			next_pack = (next_pack + 1) % packs.size()
		else:
			failures += 1
	# 빈 가방은 전투에 안 나가므로 빼 둔다.
	var out: Array[Backpack] = []
	for p in packs:
		if not p.is_empty():
			out.append(p)
	return out
