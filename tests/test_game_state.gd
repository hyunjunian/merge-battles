extends "res://tests/test_case.gd"
## 예산, 상점, 합성, 라운드 진행, 적 생성


func test_start_state() -> void:
	var gs := GameState.new(42)
	check_eq(gs.gold, GameState.START_GOLD)
	check_eq(gs.round_no, 1)
	check_eq(gs.units.size(), GameState.UNIT_SLOTS)
	check_eq(gs.inventory.size(), GameState.START_ITEMS.size())
	check_eq(gs.shop.size(), GameState.SHOP_SIZE)
	check(not gs.has_team(), "처음엔 편성 없음")


func test_budget_limits_equip() -> void:
	var gs := GameState.new(1)
	gs.inventory.clear()
	var axe := Item.new("axe")           # 5
	var shield := Item.new("tower_shield")  # 4
	gs.inventory.append_array([axe, shield])
	check_eq(gs.budget(), 8)
	check(gs.equip(axe, 0, Vector2i(0, 0)), "예산 안")
	check(not gs.can_equip(shield, 1, Vector2i(0, 0)), "5 + 4 > 8")
	check_eq(gs.used_budget(), 5)
	# 이미 장착한 아이템은 옮겨도 예산이 늘지 않는다
	check(gs.equip(axe, 1, Vector2i(1, 2)), "다른 유닛으로 이동")
	check_eq(gs.unit_of(axe), 1)
	check(gs.units[0].is_empty(), "원래 가방에서 빠짐")


func test_unequip_returns_to_inventory() -> void:
	var gs := GameState.new(1)
	var item := gs.inventory[0]
	gs.equip(item, 0, Vector2i(0, 0))
	check(not gs.inventory.has(item))
	check(gs.unequip(item))
	check(gs.inventory.has(item))
	check_eq(gs.used_budget(), 0)


func test_buy_and_sell() -> void:
	var gs := GameState.new(7)
	var item := gs.shop[0]
	var price := item.cost()
	check(gs.buy(0), "구매")
	check_eq(gs.gold, GameState.START_GOLD - price)
	check(gs.inventory.has(item))
	check(gs.sell(item), "판매")
	check_eq(gs.gold, GameState.START_GOLD - price + item.sell_price())
	gs.gold = 0
	check(not gs.buy(0), "골드 부족")
	check(not gs.reroll(), "새로고침도 골드 필요")


func test_merge_two_into_higher_tier() -> void:
	var gs := GameState.new(3)
	gs.inventory.clear()
	var a := Item.new("sword")
	var b := Item.new("sword")
	gs.inventory.append_array([a, b, Item.new("dagger")])
	gs.equip(b, 0, Vector2i(0, 0))
	var merged := gs.merge(a)
	check(merged != null, "합성 성공")
	check_eq(merged.tier, 2)
	check(not gs.owns(a) and not gs.owns(b), "재료는 사라짐")
	check(gs.units[0].is_empty(), "가방에 있던 재료도 빠짐")
	check(gs.merge(merged) == null, "짝이 없으면 실패")


func test_shop_and_merge_only_in_camp() -> void:
	var gs := GameState.new(5)
	gs.equip(gs.inventory[0], 0, Vector2i(0, 0))
	check(gs.start_expedition(), "편성이 있으면 출정")
	check(not gs.buy(0), "원정 중엔 구매 불가")
	check(not gs.reroll(), "원정 중엔 새로고침 불가")


func test_round_progress() -> void:
	var gs := GameState.new(9)
	gs.equip(gs.inventory[0], 0, Vector2i(0, 0))
	gs.start_expedition()
	var gold := gs.gold
	gs.apply_result(true)
	check_eq(gs.round_no, 2, "승리하면 다음 라운드")
	check_eq(gs.gold, gold + GameState.reward_for(1, true))
	check_eq(gs.phase, GameState.Phase.EXPEDITION)
	gs.apply_result(false)
	check_eq(gs.round_no, 2, "패배해도 라운드 유지")
	check_eq(gs.phase, GameState.Phase.CAMP, "패배하면 베이스 캠프")


func test_enemy_grows_with_rounds() -> void:
	check(EnemyGen.budget_for_round(10) > EnemyGen.budget_for_round(1), "예산 증가")
	check_eq(EnemyGen.unit_count(1), 1)
	check_eq(EnemyGen.unit_count(6), 3)
	for r in [1, 3, 8]:
		var team := EnemyGen.generate(r, 123)
		check(team.size() >= 1, "라운드 %d 적 있음" % r)
		var cost := 0
		for p in team:
			cost += p.total_cost()
		check(cost <= EnemyGen.budget_for_round(r), "라운드 %d 예산 지킴" % r)
	var a := EnemyGen.generate(4, 99)
	var b := EnemyGen.generate(4, 99)
	check_eq(a.size(), b.size(), "같은 시드는 같은 팀")
	check_eq(a[0].total_cost(), b[0].total_cost())


func test_round1_is_winnable_with_starting_items() -> void:
	var gs := GameState.new(2024)
	for item in gs.inventory.duplicate():
		gs.equip(item, 0, gs.units[0].find_spot(item))
	check_eq(gs.inventory.size(), 0, "시작 아이템 전부 장착")
	var wins := 0
	for s in 20:
		gs.run_seed = s
		if gs.fight()["winner"] == "a":
			wins += 1
	check(wins >= 10, "1라운드 승률이 너무 낮음: %d/20" % wins)
