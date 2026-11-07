extends "res://tests/test_case.gd"
## 시너지, 유닛 능력치, 자동 전투


func _pack(ids: Array) -> Backpack:
	var pack := Backpack.new()
	for id: String in ids:
		var item := Item.new(id)
		pack.place(item, pack.find_spot(item))
	return pack


func test_synergy_levels() -> void:
	var packs: Array[Backpack] = [_pack(["dagger", "sword"]), _pack(["sword", "dagger", "buckler"])]
	var counts := Synergy.count_tags(packs)
	check_eq(counts["warrior"], 4)
	check_eq(counts["guard"], 1)
	check_eq(Synergy.level("warrior", 4), 2)
	check_eq(Synergy.level("guard", 1), 0)
	var bonus := Synergy.bonuses(counts)
	check_eq(bonus["atk_mult"], 0.5, "전사 2단계")
	check_eq(bonus["armor"], 0.0, "수호 비활성")


func test_unit_stats_apply_items_and_bonus() -> void:
	var s := BattleSim.unit_stats(_pack(["sword", "buckler"]), {"atk_mult": 0.2, "armor": 2.0})
	check_eq(s["hp"], BattleSim.BASE_HP + 10.0)
	check_eq(s["atk"], (BattleSim.BASE_ATK + 5.0) * 1.2)
	check_eq(s["armor"], 3.0)


func test_empty_packs_do_not_fight() -> void:
	var packs: Array[Backpack] = [_pack(["sword"]), Backpack.new(), Backpack.new()]
	check_eq(BattleSim.team_stats(packs).size(), 1)


func test_damage_floor() -> void:
	check_eq(BattleSim.damage(3.0, 10.0), 1.0, "방어가 높아도 최소 1")
	check_eq(BattleSim.damage(10.0, 3.0), 7.0)


func test_stronger_team_wins_and_is_deterministic() -> void:
	var strong: Array[Backpack] = [_pack(["axe", "tower_shield"])]
	var weak: Array[Backpack] = [_pack(["apple"])]
	var r1 := BattleSim.simulate(BattleSim.team_stats(strong), BattleSim.team_stats(weak))
	var r2 := BattleSim.simulate(BattleSim.team_stats(strong), BattleSim.team_stats(weak))
	check_eq(r1["winner"], "a")
	check_eq(r1["events"].size(), r2["events"].size(), "같은 입력은 같은 결과")
	check(r1["duration"] < BattleSim.MAX_TIME, "시간 제한 전에 끝남")
	var last: Array = r1["frames"][-1]
	check_eq((last[1] as PackedFloat32Array)[0], 0.0, "진 쪽 체력 0")


func test_empty_team_loses() -> void:
	var weak: Array[Backpack] = [_pack(["apple"])]
	var r := BattleSim.simulate([] as Array[Dictionary], BattleSim.team_stats(weak))
	check_eq(r["winner"], "b")


func test_attacks_hit_front_unit_first() -> void:
	var attackers: Array[Backpack] = [_pack(["sword"])]
	var defenders: Array[Backpack] = [_pack(["apple"]), _pack(["apple"])]
	var r := BattleSim.simulate(BattleSim.team_stats(attackers), BattleSim.team_stats(defenders))
	var first_hit: Dictionary = {}
	for e: Dictionary in r["events"]:
		if e["side"] == "a":
			first_hit = e
			break
	check_eq(first_hit.get("dst", -1), 0, "맨 앞 유닛부터")
