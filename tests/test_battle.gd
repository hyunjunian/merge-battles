extends "res://tests/test_case.gd"
## 시너지, 유닛 능력치, 자동 전투


func _pack(ids: Array) -> Backpack:
	var pack := Backpack.new("", 3, 4)
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
	check_eq(s["hp"], BattleSim.BASE_HP + 15.0)
	check_eq(s["atk"], (BattleSim.BASE_ATK + 5.0) * 1.2)
	check_eq(s["armor"], 3.0)


func test_unit_type_gives_base_stats() -> void:
	var soldier := Backpack.new("soldier")
	var base := BattleSim.unit_stats(soldier)
	check_eq(base["hp"], 70.0, "병사 기본 체력")
	soldier.place(Item.new("sword"), Vector2i(0, 0))
	check_eq(BattleSim.unit_stats(soldier)["atk"], 4.0 + 5.0, "아이템이 능력치를 바꿈")
	check(BattleSim.is_ranged(BattleSim.unit_stats(Backpack.new("archer"))), "궁수는 기본 원거리")


func test_team_stats_use_slot_positions() -> void:
	var a := Backpack.new("recruit")
	a.slot = 4
	var team := BattleSim.team_stats([a] as Array[Backpack], "b")
	check_eq(team[0]["pos"], BattleSim.slot_position("b", 4))
	check(BattleSim.slot_position("a", 4).y > 0.0 and BattleSim.slot_position("b", 4).y < 0.0, "양 팀은 반대편")
	check(absf(BattleSim.slot_position("a", 4).y) > absf(BattleSim.slot_position("a", 1).y), "3~5 는 뒷줄")


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
	check_eq(BattleSim.frame_hp(last, 1, 0), 0.0, "진 쪽 체력 0")


func test_empty_team_loses() -> void:
	var weak: Array[Backpack] = [_pack(["apple"])]
	var r := BattleSim.simulate([] as Array[Dictionary], BattleSim.team_stats(weak))
	check_eq(r["winner"], "b")


func test_attacks_nearest_enemy_first() -> void:
	# 적 두 명 중 0번을 우리 유닛 바로 앞에 두면 그쪽을 먼저 때린다.
	var me := [BattleSim.unit_stats(_pack(["sword"]))] as Array[Dictionary]
	var foes := [BattleSim.unit_stats(_pack(["apple"])), BattleSim.unit_stats(_pack(["apple"]))] as Array[Dictionary]
	var r := BattleSim.simulate(me, foes)
	var first_hit: Dictionary = {}
	for e: Dictionary in r["events"]:
		if e["side"] == "a":
			first_hit = e
			break
	var start_a := BattleSim.start_position("a", 0, 1)
	var d0 := start_a.distance_to(BattleSim.start_position("b", 0, 2))
	var d1 := start_a.distance_to(BattleSim.start_position("b", 1, 2))
	check_eq(first_hit.get("dst", -1), 0 if d0 <= d1 else 1, "가까운 적부터")


func test_choose_target_prefers_nearest_and_sticks() -> void:
	var foes := [
		{"hp": 10.0, "pos": Vector2(0, 5)},
		{"hp": 10.0, "pos": Vector2(0, 2)},
		{"hp": 0.0, "pos": Vector2(0, 0.5)},
	]
	check_eq(BattleSim.choose_target(Vector2.ZERO, -1, foes), 1, "죽은 적은 무시하고 가장 가까운 적")
	foes[0]["pos"] = Vector2(0, 2.5)
	check_eq(BattleSim.choose_target(Vector2.ZERO, 0, foes), 0, "조금 더 가까운 정도로는 목표를 안 바꿈")
	foes[0]["pos"] = Vector2(0, 6)
	check_eq(BattleSim.choose_target(Vector2.ZERO, 0, foes), 1, "훨씬 가까운 적이 있으면 바꿈")


func test_units_move_toward_each_other() -> void:
	var a: Array[Dictionary] = [BattleSim.unit_stats(_pack(["sword"]))]
	var b: Array[Dictionary] = [BattleSim.unit_stats(_pack(["sword"]))]
	var r := BattleSim.simulate(a, b)
	var start: Array = r["frames"][0]
	var later: Array = r["frames"][mini(10, r["frames"].size() - 1)]
	var d0 := BattleSim.frame_pos(start, 0, 0).distance_to(BattleSim.frame_pos(start, 1, 0))
	var d1 := BattleSim.frame_pos(later, 0, 0).distance_to(BattleSim.frame_pos(later, 1, 0))
	check(d1 < d0, "서로 다가감: %.2f → %.2f" % [d0, d1])
	for e: Dictionary in r["events"]:
		check(not e["ranged"], "근접 유닛은 근접 공격")


func test_ranged_unit_attacks_from_distance() -> void:
	var archer := BattleSim.unit_stats(_pack(["short_bow"]))
	check(BattleSim.is_ranged(archer), "단궁이 있으면 원거리")
	check(not BattleSim.is_ranged(BattleSim.unit_stats(_pack(["sword"]))), "장검은 근접")
	var r := BattleSim.simulate([archer] as Array[Dictionary], [BattleSim.unit_stats(_pack(["tower_shield"]))] as Array[Dictionary])
	var first: Dictionary = {}
	for e: Dictionary in r["events"]:
		if e["side"] == "a":
			first = e
			break
	check(first.get("ranged", false), "원거리 공격 이벤트")
	var fi := roundi(float(first["t"]) / BattleSim.DT)
	var frame: Array = r["frames"][fi]
	var dist := BattleSim.frame_pos(frame, 0, 0).distance_to(BattleSim.frame_pos(frame, 1, 0))
	check(dist > BattleSim.MELEE_RANGE + BattleSim.RADIUS * 2.0 + 0.5, "멀리서 쏨: %.2f" % dist)


func test_units_stay_in_field_and_apart() -> void:
	var a: Array[Dictionary] = []
	var b: Array[Dictionary] = []
	for i in 3:
		a.append(BattleSim.unit_stats(_pack(["axe"])))
		b.append(BattleSim.unit_stats(_pack(["tower_shield", "herb_pouch"])))
	var r := BattleSim.simulate(a, b)
	for frame: Array in r["frames"]:
		for side in 2:
			for i in 3:
				var p := BattleSim.frame_pos(frame, side, i)
				check(absf(p.x) <= BattleSim.HALF_W + 0.001 and absf(p.y) <= BattleSim.HALF_D + 0.001, "전장 안")
	var last: Array = r["frames"][-1]
	for i in 3:
		for j in range(i + 1, 3):
			if BattleSim.frame_hp(last, 0, i) > 0.0 and BattleSim.frame_hp(last, 0, j) > 0.0:
				var d := BattleSim.frame_pos(last, 0, i).distance_to(BattleSim.frame_pos(last, 0, j))
				check(d > BattleSim.RADIUS * 2.0 - 0.3, "아군끼리 겹치지 않음: %.2f" % d)


func test_kite_step_moves_away_or_sidesteps() -> void:
	var p := BattleSim.kite_step(Vector2(0, 2), Vector2(0, 1), 0.2)
	check(p.distance_to(Vector2(0, 1)) > 1.0, "적에게서 멀어짐")
	# 오른쪽 아래 구석에 몰린 상태: 뒤(+z)와 오른쪽이 막힘 → 가운데 쪽 옆으로
	var corner := Vector2(BattleSim.HALF_W, BattleSim.HALF_D)
	var q := BattleSim.kite_step(corner, corner - Vector2(0, 1), 0.2)
	check(q.distance_to(corner) > 0.1, "구석에서도 움직임")
	check(q.x < corner.x, "가운데 쪽으로 비켜섬")


func test_empty_side_loses_at_once() -> void:
	var team: Array[Backpack] = [_pack(["sword"])]
	var none: Array[Backpack] = []
	var r := BattleSim.simulate(BattleSim.team_stats(none, "a"), BattleSim.team_stats(team, "b"))
	check_eq(r["winner"], "b", "유닛 없는 a 가 진다")
	check_eq(r["duration"], 0.0, "싸우지 않고 바로 끝")
	check_eq(GameState.surviving(r, 1), 1, "상대 유닛은 모두 살아 있음")
	r = BattleSim.simulate(BattleSim.team_stats(team, "a"), BattleSim.team_stats(none, "b"))
	check_eq(r["winner"], "a", "유닛 없는 b 가 진다")


func test_player_without_units_can_fight_and_loses() -> void:
	var gs := GameState.new(7)
	gs.sell_unit(gs.units[0])
	check(gs.units.is_empty())
	check(gs.can_fight(), "유닛이 없어도 전투 시작 가능")
	var r := gs.fight()
	var summary := gs.apply_result(r)
	check(not summary["won"], "유닛이 없으면 패배")
	check_eq(summary["hp_loss"], GameState.hp_loss_for(GameState.surviving(r, 1)), "살아남은 상대 유닛만큼 체력 감소")
