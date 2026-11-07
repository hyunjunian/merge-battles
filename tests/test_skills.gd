extends "res://tests/test_case.gd"
## 스킬 아이템: 정의, 합치기, 전투 중 발동


func _unit(unit_id: String, items: Array) -> Backpack:
	var pack := Backpack.new(unit_id)
	for id: String in items:
		var item := Item.new(id)
		var spot := pack.find_spot(item)
		check(spot != Backpack.NO_SPOT, "%s 가 %s 에 들어가야 함" % [id, unit_id])
		pack.place(item, spot)
	return pack


func _team(packs: Array, side: String) -> Array[Dictionary]:
	var arr: Array[Backpack] = []
	for i in packs.size():
		var p: Backpack = packs[i]
		p.slot = i
		arr.append(p)
	return BattleSim.team_stats(arr, side)


func _events(r: Dictionary, kind: String, side: String = "") -> Array:
	return r["events"].filter(func(e: Dictionary) -> bool: return e["kind"] == kind and (side == "" or e["side"] == side))


func test_every_skill_item_is_described_and_priced() -> void:
	var count := 0
	for id in ItemDB.ids():
		var item := Item.new(id)
		if not item.has_skill():
			continue
		count += 1
		check(Skills.NAMES.has(item.skill()["type"]), "%s 스킬 종류" % id)
		check(item.describe().contains(Skills.NAMES[item.skill()["type"]]), "%s 설명에 스킬 이름" % id)
		check(item.cost() >= 5, "%s 스킬 아이템은 5원 이상" % id)
	check(count >= 10, "스킬 아이템 10종 이상: %d" % count)


func test_aggregate_stacks() -> void:
	var agg := Skills.aggregate([
		{"type": "lifesteal", "pct": 0.2}, {"type": "lifesteal", "pct": 0.3},
		{"type": "crit", "every": 4, "mult": 2.0}, {"type": "crit", "every": 3, "mult": 1.5},
	])
	check_eq(agg["lifesteal"], 0.5, "흡혈 합산")
	check_eq(agg["crit_every"], 3, "치명타 주기는 짧은 쪽")
	check_eq(agg["crit_mult"], 2.0, "배율은 큰 쪽")
	check(Skills.has_any(agg))
	check(not Skills.has_any(Skills.aggregate([])))


func test_crit_every_third_attack() -> void:
	var r := BattleSim.simulate(_team([_unit("soldier", ["hawk_lens"])], "a"), _team([_unit("giant", [])], "b"))
	var hits := _events(r, "attack", "a")
	check(hits.size() >= 3, "공격 3번 이상")
	check(not hits[0]["crit"] and not hits[1]["crit"] and hits[2]["crit"], "세 번째가 치명타")
	check_eq(hits[2]["dmg"], hits[0]["dmg"] * 2.5, "2.5배")


func test_lifesteal_heals_attacker() -> void:
	var r := BattleSim.simulate(_team([_unit("soldier", ["vampire_tooth"])], "a"), _team([_unit("giant", [])], "b"))
	check(_events(r, "heal", "a").size() > 0, "흡혈 회복 이벤트")


func test_poison_ticks_ignore_armor() -> void:
	var r := BattleSim.simulate(_team([_unit("soldier", ["venom_fang"])], "a"), _team([_unit("giant", ["dragon_scale"])], "b"))
	var ticks := _events(r, "poison", "a")
	check(ticks.size() >= 2, "독 피해가 여러 번")
	check(float(ticks[0]["dmg"]) >= 3.9, "방어(5)를 무시하고 초당 4")


func test_shield_absorbs_first_damage() -> void:
	var r := BattleSim.simulate(_team([_unit("recruit", ["ward_charm"])], "a"), _team([_unit("recruit", ["club"])], "b"))
	check_eq(_events(r, "shield", "a").size(), 1, "시작 때 보호막")
	var first_hit: Dictionary = _events(r, "attack", "b")[0]
	var fi := roundi(float(first_hit["t"]) / BattleSim.DT)
	var hp_after := BattleSim.frame_hp(r["frames"][fi], 0, 0)
	check(hp_after >= r["max_a"][0] - 0.01, "첫 피해는 보호막이 막음")


func test_thorns_hurt_attacker() -> void:
	var r := BattleSim.simulate(_team([_unit("recruit", ["club"])], "a"), _team([_unit("soldier", ["thorn_mail"])], "b"))
	var th := _events(r, "thorns", "b")
	check(th.size() > 0, "가시 반사")
	check_eq(th[0]["dst"], 0, "공격자에게")


func test_rage_triggers_below_half() -> void:
	var r := BattleSim.simulate(_team([_unit("soldier", ["berserker_mask"])], "a"), _team([_unit("knight", ["sword", "sword"])], "b"))
	var rage := _events(r, "rage", "a")
	check_eq(rage.size(), 1, "분노는 한 번")


func test_revive_once() -> void:
	var r := BattleSim.simulate(_team([_unit("recruit", ["phoenix_feather"])], "a"), _team([_unit("giant", ["axe"])], "b"))
	check_eq(_events(r, "revive", "a").size(), 1, "한 번 부활")


func test_heal_targets_most_injured_ally() -> void:
	var healer := _unit("archer", ["healing_grail"])
	var tank := _unit("soldier", [])
	var r := BattleSim.simulate(_team([tank, healer], "a"), _team([_unit("knight", ["sword"])], "b"))
	var heals := _events(r, "heal", "a")
	check(heals.size() > 0, "치유 발동")
	check(heals.any(func(e: Dictionary) -> bool: return e["src"] == 1 and float(e["amount"]) > 0.0), "치유사가 회복")


func test_fireball_hits_clustered_enemies() -> void:
	var foes := [_unit("recruit", []), _unit("recruit", []), _unit("recruit", [])]
	var r := BattleSim.simulate(_team([_unit("knight", ["fire_scroll"])], "a"), _team(foes, "b"))
	check(_events(r, "fireball", "a").size() > 0, "화염구 발동")
	var burned := {}
	for e: Dictionary in _events(r, "burn", "a"):
		burned[e["dst"]] = true
	check(burned.size() >= 2, "여러 적이 맞음: %d" % burned.size())


func test_chain_jumps_to_other_enemies() -> void:
	var foes := [_unit("soldier", []), _unit("soldier", []), _unit("soldier", [])]
	var r := BattleSim.simulate(_team([_unit("mage", ["storm_rod"])], "a"), _team(foes, "b"))
	var chains := _events(r, "chain", "a")
	check(chains.size() > 0, "연쇄 번개")
	for e: Dictionary in chains:
		check(e["dst"] != e["from"], "다른 적에게 튐")


func test_nearest_others() -> void:
	var foes := [
		{"hp": 10.0, "pos": Vector2(0, 0)}, {"hp": 10.0, "pos": Vector2(3, 0)},
		{"hp": 10.0, "pos": Vector2(1, 0)}, {"hp": 0.0, "pos": Vector2(0.5, 0)},
	]
	check_eq(BattleSim.nearest_others(foes, 0, 2, 5.0), [2, 1] as Array[int], "가까운 순, 죽은 적 제외")
	check_eq(BattleSim.nearest_others(foes, 0, 2, 2.0), [2] as Array[int], "거리 제한")
