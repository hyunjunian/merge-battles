extends "res://tests/test_case.gd"
## 합치기: 같은 유닛·같은 별 2개 → 별 하나 위 (최대 3성). 능력치·가방이 커진다.


func _gs() -> GameState:
	var gs := GameState.new(1)
	gs.units.clear()
	gs.inventory.clear()
	gs.gold = 100
	return gs


func test_star_scales_stats_and_bag() -> void:
	var p := Backpack.new("recruit")
	check_eq(Vector2i(p.width, p.height), Vector2i(1, 2))
	var hp1: float = p.base_stats()["hp"]
	p.set_star(2)
	check_eq(Vector2i(p.width, p.height), Vector2i(2, 3), "별 2: 가로·세로 +1")
	check(absf(float(p.base_stats()["hp"]) - hp1 * Backpack.STAR_STAT_MULT) < 0.01, "별 2: 체력 x1.8")
	check_eq(p.cost(), UnitDB.cost("recruit") * 2, "들인 값은 두 마리")
	p.set_star(3)
	check_eq(Vector2i(p.width, p.height), Vector2i(3, 4))
	check_eq(p.copies(), 4)
	p.set_star(9)
	check_eq(p.star, Backpack.MAX_STAR, "최대 3성")


func test_two_same_units_merge() -> void:
	var gs := _gs()
	gs.add_unit(Backpack.new("recruit"))
	var first := gs.units[0]
	var dagger := Item.new("dagger")
	var other := Backpack.new("recruit")
	other.place(dagger, Vector2i(0, 0))
	check_eq(gs.add_unit(other), 0, "같은 유닛이면 합쳐짐")
	check_eq(gs.units.size(), 1)
	check(gs.units[0] == first, "먼저 있던 유닛이 남음")
	check_eq(first.star, 2)
	check(first.has_item(dagger), "합쳐진 유닛의 아이템은 남은 유닛 가방으로")
	gs.add_unit(Backpack.new("scout"))
	check_eq(gs.units.size(), 2, "다른 유닛은 따로")


func test_merge_chains_to_three_stars() -> void:
	var gs := _gs()
	for i in 3:
		gs.add_unit(Backpack.new("recruit"))
	check_eq(gs.units.size(), 2, "별2 + 별1")
	gs.add_unit(Backpack.new("recruit"))
	check_eq(gs.units.size(), 1, "별1 둘 → 별2, 별2 둘 → 별3 (연쇄)")
	check_eq(gs.units[0].star, 3)
	gs.add_unit(Backpack.new("recruit"))
	check_eq(gs.units.size(), 2, "3성은 더 합치지 않음")


func test_buy_merges_even_when_field_is_full() -> void:
	var gs := _gs()
	for id: String in ["recruit", "scout", "soldier", "archer", "knight", "mage"]:
		gs.add_unit(Backpack.new(id))
	gs.shop[0] = {"kind": "unit", "id": "giant"}
	gs.shop[1] = {"kind": "unit", "id": "recruit"}
	check(gs.buy_block_reason(0) != "", "자리가 없으면 새 유닛은 못 삼")
	check(gs.buy(1), "합쳐지는 유닛은 살 수 있음")
	check_eq(gs.units.size(), 6)
	check_eq(gs.units[0].star, 2)


func test_snapshot_keeps_star() -> void:
	var p := Backpack.new("soldier")
	p.set_star(2)
	var team := OpponentPool.build_team(OpponentPool.snapshot([p] as Array[Backpack]))
	check_eq(team[0].star, 2)
	check_eq(team[0].width, 3)
