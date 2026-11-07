extends "res://tests/test_case.gd"
## 로그라이크 규칙: 시작 상태, 상점, 판매, 체력, 수입(연승/연패), 게임 오버, 적 생성


## 유닛 하나의 프레임 값 (BattleSim.STRIDE 개, hp 는 세 번째)
func _unit_frame(hp: float) -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	arr.resize(BattleSim.STRIDE)
	arr[2] = hp
	return arr


func _result(winner: String, enemy_alive: int, enemy_total: int = 3) -> Dictionary:
	# 마지막 프레임만 의미 있는 가짜 전투 결과
	var a := _unit_frame(10.0)
	var b := PackedFloat32Array()
	var maxes := PackedFloat32Array()
	for i in enemy_total:
		b.append_array(_unit_frame(5.0 if i < enemy_alive else 0.0))
		maxes.append(10.0)
	return {"winner": winner, "frames": [[a, b]], "max_a": PackedFloat32Array([10.0]), "max_b": maxes}


func test_start_state() -> void:
	var gs := GameState.new(42)
	check_eq(gs.hp, 100)
	check_eq(gs.gold, 4, "시작 돈 4원")
	check_eq(gs.round_no, 1)
	check_eq(gs.units.size(), 1, "유닛 하나로 시작")
	var u := gs.units[0]
	check_eq(Vector2i(u.width, u.height), Vector2i(1, 2), "1x2 유닛")
	check_eq(u.slot, 0, "전장 첫 자리")
	check(gs.inventory.is_empty(), "아이템 없음")
	check_eq(gs.shop.size(), GameState.UNIT_OFFERS + GameState.ITEM_OFFERS)


func test_buying_unit_deploys_immediately() -> void:
	var gs := GameState.new(1)
	gs.gold = 50
	gs.shop[0] = {"kind": "unit", "id": "soldier"}
	check(gs.buy(0), "구매")
	check_eq(gs.units.size(), 2, "바로 전장에 투입")
	check_eq(gs.units[1].slot, 1, "빈 자리에 섬")
	check_eq(gs.gold, 50 - UnitDB.cost("soldier"))
	check(gs.shop[0].is_empty(), "산 칸은 비움")
	check(not gs.buy(0), "같은 칸은 다시 못 삼")


func test_field_has_slot_limit() -> void:
	var gs := GameState.new(1)
	gs.gold = 999
	for i in BattleSim.SLOT_COUNT - 1:
		gs.shop[0] = {"kind": "unit", "id": "recruit"}
		check(gs.buy(0), "자리 있음 %d" % i)
	gs.shop[0] = {"kind": "unit", "id": "recruit"}
	check(gs.buy_block_reason(0) != "", "자리 꽉 참")
	check(not gs.buy(0))


func test_buying_item_goes_to_inventory_and_equips() -> void:
	var gs := GameState.new(1)
	gs.gold = 10
	gs.shop[GameState.UNIT_OFFERS] = {"kind": "item", "id": "sword"}
	check(gs.buy(GameState.UNIT_OFFERS))
	var sword := gs.inventory[0]
	check(gs.equip(sword, 0, Vector2i(0, 0)), "견습병 1x2 에 장검")
	check_eq(gs.unit_of(sword), 0)
	check(gs.unequip(sword), "아이템은 뺄 수 있음")
	check(gs.inventory.has(sword))


func test_not_enough_gold() -> void:
	var gs := GameState.new(1)
	gs.gold = 1
	gs.shop[0] = {"kind": "unit", "id": "warlord"}
	check(not gs.buy(0), "돈 부족")
	check_eq(gs.buy_block_reason(0), "돈이 부족합니다")


func test_selling_unit_returns_items_and_less_gold() -> void:
	var gs := GameState.new(1)
	var unit := gs.units[0]
	var club := Item.new("club")
	gs.inventory.append(club)
	gs.equip(club, 0, Vector2i(0, 0))
	var gold := gs.gold
	check(gs.sell_unit(unit), "유닛 판매")
	check(gs.units.is_empty(), "전장에서 빠짐")
	check(gs.inventory.has(club), "가방 속 아이템은 보유함으로")
	check_eq(gs.gold, gold + unit.sell_price())
	check(unit.sell_price() < unit.cost(), "판매가 < 구매가")
	check(gs.sell_item(club))
	check_eq(gs.gold, gold + unit.sell_price() + club.sell_price())


func test_loss_reduces_hp_by_surviving_enemies() -> void:
	var gs := GameState.new(1)
	var s := gs.apply_result(_result("b", 2))
	check(not s["won"])
	check_eq(s["survivors"], 2)
	check_eq(gs.hp, 100 - 2 * GameState.HP_LOSS_PER_UNIT)
	check_eq(gs.round_no, 2, "져도 다음 라운드")
	var hp := gs.hp
	gs.apply_result(_result("a", 0))
	check_eq(gs.hp, hp, "이기면 체력 그대로")


func test_income_grows_with_streaks() -> void:
	check_eq(GameState.income_for(1), GameState.BASE_INCOME, "1연승은 보너스 없음")
	check_eq(GameState.income_for(3), GameState.BASE_INCOME + 2, "3연승 +2")
	check_eq(GameState.income_for(-4), GameState.BASE_INCOME + 3, "4연패 +3")
	check_eq(GameState.income_for(50), GameState.BASE_INCOME + GameState.MAX_STREAK_BONUS, "상한")
	var gs := GameState.new(1)
	var g := gs.gold
	gs.apply_result(_result("a", 0))
	gs.apply_result(_result("a", 0))
	check_eq(gs.streak, 2)
	check_eq(gs.gold, g + GameState.income_for(1) + GameState.income_for(2), "연승 수입")
	gs.apply_result(_result("b", 1))
	check_eq(gs.streak, -1, "지면 연패로 바뀜")


func test_game_over_when_hp_runs_out() -> void:
	var gs := GameState.new(1)
	gs.hp = 10
	var s := gs.apply_result(_result("b", 3))
	check(s["game_over"], "게임 오버")
	check(gs.game_over)
	check_eq(gs.hp, 0)
	check_eq(s["round_played"], 1, "도달 라운드 기록용")
	check(not gs.can_fight(), "더 못 싸움")
	check(not gs.buy(0), "더 못 삼")


func test_shop_refreshes_each_round_and_reroll_costs() -> void:
	var gs := GameState.new(3)
	gs.shop[0] = {}
	gs.apply_result(_result("a", 0))
	check(not gs.shop[0].is_empty(), "라운드가 끝나면 새 진열")
	gs.gold = 1
	check(gs.reroll())
	check_eq(gs.gold, 0)
	check(not gs.reroll(), "돈 없으면 새로고침 불가")


func test_enemy_grows_with_rounds() -> void:
	check(EnemyGen.budget_for_round(10) > EnemyGen.budget_for_round(1), "가치 증가")
	check_eq(EnemyGen.max_units(1), 1)
	check(EnemyGen.max_units(9) > EnemyGen.max_units(3), "유닛 수 증가")
	for r in [1, 4, 10, 20]:
		var team := EnemyGen.generate(r, 123)
		check(team.size() >= 1 and team.size() <= EnemyGen.max_units(r), "라운드 %d 유닛 수" % r)
		check(EnemyGen.total_value(team) <= EnemyGen.budget_for_round(r), "라운드 %d 가치 지킴" % r)
		var slots := {}
		for p in team:
			slots[p.slot] = true
		check_eq(slots.size(), team.size(), "자리 겹치지 않음")
	check(EnemyGen.total_value(EnemyGen.generate(12, 9)) > EnemyGen.total_value(EnemyGen.generate(2, 9)), "후반이 더 강함")
	var a := EnemyGen.generate(4, 99)
	var b := EnemyGen.generate(4, 99)
	check_eq(EnemyGen.total_value(a), EnemyGen.total_value(b), "같은 시드는 같은 팀")


func test_round1_is_winnable_after_shopping() -> void:
	# 시작 돈 4원으로 장검(3)을 사서 넣으면 1라운드는 대체로 이긴다
	var wins := 0
	for s in range(1, 21):
		var gs := GameState.new(s)
		var sword := Item.new("sword")
		gs.inventory.append(sword)
		gs.equip(sword, 0, Vector2i(0, 0))
		if gs.fight()["winner"] == "a":
			wins += 1
	check(wins >= 12, "1라운드 승률이 너무 낮음: %d/20" % wins)


func test_move_unit_clamps_and_separates() -> void:
	var gs := GameState.new(1)
	gs.gold = 50
	gs.shop[0] = {"kind": "unit", "id": "soldier"}
	gs.buy(0)
	var p := gs.move_unit(1, Vector2(99.0, 99.0))
	check_eq(p, Vector2(BattleSim.HALF_W, BattleSim.HALF_D), "진영 밖은 가장자리로")
	var q := gs.move_unit(1, Vector2(0.0, -3.0))
	check_eq(q.y, BattleSim.OWN_MIN_Z, "가운데 선을 못 넘음")
	var first := gs.units[0].start_pos("a")
	var r := gs.move_unit(1, first)
	check(r.distance_to(first) >= BattleSim.MIN_GAP - 0.01, "겹치면 밀어냄")
	check(not gs.units[1].start_pos("b").is_equal_approx(gs.units[1].start_pos("a")), "상대 쪽 좌표는 뒤집힘")


func test_new_units_do_not_stack() -> void:
	var gs := GameState.new(1)
	gs.gold = 99
	for i in 3:
		gs.shop[0] = {"kind": "unit", "id": "recruit"}
		gs.buy(0)
	for i in gs.units.size():
		for j in range(i + 1, gs.units.size()):
			check(gs.units[i].start_pos("a").distance_to(gs.units[j].start_pos("a")) >= BattleSim.MIN_GAP - 0.01, "새 유닛끼리 안 겹침")


func test_placement_never_overlaps_even_when_crowded() -> void:
	var gs := GameState.new(1)
	gs.gold = 999
	for i in BattleSim.SLOT_COUNT - 1:
		gs.shop[0] = {"kind": "unit", "id": "recruit"}
		gs.buy(0)
	# 모두 같은 구석으로 끌어 놓아도 서로 겹치지 않는다
	for i in gs.units.size():
		gs.move_unit(i, Vector2(BattleSim.HALF_W, BattleSim.HALF_D))
	for i in gs.units.size():
		var p := gs.units[i].start_pos("a")
		check(p.y >= BattleSim.OWN_MIN_Z and absf(p.x) <= BattleSim.HALF_W, "진영 안")
		for j in range(i + 1, gs.units.size()):
			var d := p.distance_to(gs.units[j].start_pos("a"))
			check(d >= BattleSim.MIN_GAP - 0.01, "겹치지 않음 %d-%d: %.2f" % [i, j, d])


func test_place_own_picks_nearest_free_spot() -> void:
	var others: Array[Vector2] = [Vector2(0, 3)]
	var q := BattleSim.place_own(Vector2(0.1, 3.0), others)
	check(not BattleSim.overlaps(q, others), "빈자리")
	check(q.distance_to(Vector2(0.1, 3.0)) < BattleSim.MIN_GAP + 0.2, "가까운 곳")
	check_eq(BattleSim.place_own(Vector2(2, 5), others), Vector2(2, 5), "빈 곳은 그대로")
