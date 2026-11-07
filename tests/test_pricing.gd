extends "res://tests/test_case.gd"
## 가격 규칙, 상점 등장 확률


func test_all_prices_in_range_and_sell_is_lower() -> void:
	for id in ItemDB.ids():
		var c := Pricing.item_cost(id)
		check(c >= 2 and c <= 10, "%s 구매가 2~10: %d" % [id, c])
		var sp := Item.new(id).sell_price()
		check(sp >= 1 and sp < c, "%s 판매가 %d < 구매가 %d" % [id, sp, c])
	for id in UnitDB.ids():
		var c := UnitDB.cost(id)
		check(c >= 2 and c <= 10, "%s 유닛 구매가 2~10: %d" % [id, c])
		var sp := Backpack.new(id).sell_price()
		check(sp >= 1 and sp < c, "%s 유닛 판매가 %d < %d" % [id, sp, c])


func test_bigger_units_cost_more_on_average() -> void:
	var small := 0.0
	var big := 0.0
	var n_small := 0
	var n_big := 0
	for id in UnitDB.ids():
		var s: Vector2i = UnitDB.get_def(id)["size"]
		if s.x * s.y <= 4:
			small += UnitDB.cost(id)
			n_small += 1
		else:
			big += UnitDB.cost(id)
			n_big += 1
	check(big / n_big > small / n_small, "큰 유닛이 평균적으로 비쌈")


func test_small_strong_items_cost_more() -> void:
	# 칸 하나당 성능(공격 + 체력/5)이 높을수록 비싸다: 1칸 루비가 4칸 도끼보다 비쌈
	check(Pricing.item_cost("ruby") > Pricing.item_cost("axe"))
	check(Pricing.item_cost("dragon_scale") > Pricing.item_cost("tower_shield"))


func test_later_rounds_roll_pricier_things() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var avg := func(round_no: int) -> float:
		var total := 0
		for i in 400:
			total += Pricing.item_cost(Pricing.roll_item(round_no, rng))
		return total / 400.0
	var early: float = avg.call(1)
	var late: float = avg.call(15)
	check(late > early + 2.0, "후반 평균 가격이 높음: %.2f → %.2f" % [early, late])
	check(Pricing.weight(10, 1) < Pricing.weight(2, 1), "1라운드엔 싼 게 잘 나옴")
	check(Pricing.weight(10, 18) > Pricing.weight(2, 18), "후반엔 비싼 게 잘 나옴")


func test_records_save_best_round() -> void:
	var path := "user://test_records.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check_eq(Records.load_records(path)["best_round"], 0, "처음엔 기록 없음")
	Records.submit(7, path)
	var rec := Records.submit(4, path)
	check_eq(rec["best_round"], 7, "최고 기록 유지")
	check_eq(rec["last_round"], 4)
	check_eq(rec["runs"], 2)
	check_eq(Records.load_records(path)["runs"], 2, "파일에 저장됨")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
