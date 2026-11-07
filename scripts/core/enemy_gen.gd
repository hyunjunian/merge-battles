class_name EnemyGen
extends RefCounted
## 라운드별 상대 팀 생성. 상점과 같은 유닛·아이템을 같은 확률 규칙으로 산다.
## 라운드가 오를수록 쓸 수 있는 돈(가치)과 유닛 수가 늘고, 비싼 물건이 더 자주 나온다.
## 같은 (라운드, 시드) 면 같은 팀이 나온다.


## 상대 팀의 총가치(유닛+아이템 가격 합). 플레이어가 시작 가치 6원에 라운드마다 3원 남짓 버는 것보다 조금 빨리 는다.
static func budget_for_round(round_no: int) -> int:
	return roundi(4.0 + 3.6 * (round_no - 1) + 0.08 * (round_no - 1) * (round_no - 1))


static func max_units(round_no: int) -> int:
	return clampi(1 + (round_no - 1) / 2, 1, BattleSim.SLOT_COUNT)


static func generate(round_no: int, seed_value: int) -> Array[Backpack]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([round_no, seed_value, "enemy"])
	var packs: Array[Backpack] = []
	var remaining := budget_for_round(round_no)
	var limit := max_units(round_no)
	var failures := 0
	while remaining > 0 and failures < 60:
		var want_unit := packs.is_empty() or (packs.size() < limit and rng.randf() < 0.35)
		if want_unit:
			var unit_id := Pricing.roll_unit(round_no, rng)
			if packs.is_empty() and UnitDB.cost(unit_id) > remaining:
				unit_id = _cheapest_unit()
			if UnitDB.cost(unit_id) <= remaining and packs.size() < limit:
				var pack := Backpack.new(unit_id)
				pack.slot = packs.size()
				packs.append(pack)
				remaining -= pack.cost()
			else:
				failures += 1
			continue
		var item := Item.new(Pricing.roll_item(round_no, rng))
		if item.cost() > remaining:
			failures += 1
			continue
		var placed := false
		var start := rng.randi_range(0, packs.size() - 1)
		for k in packs.size():
			var pack := packs[(start + k) % packs.size()]
			var spot := pack.find_spot(item)
			if spot != Backpack.NO_SPOT:
				pack.place(item, spot)
				placed = true
				break
		if placed:
			remaining -= item.cost()
		else:
			failures += 1
	return packs


static func _cheapest_unit() -> String:
	var best := ""
	for id in UnitDB.ids():
		if best == "" or UnitDB.cost(id) < UnitDB.cost(best):
			best = id
	return best


static func total_value(packs: Array[Backpack]) -> int:
	var total := 0
	for p in packs:
		total += p.total_value()
	return total
