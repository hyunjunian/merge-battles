extends "res://tests/test_case.gd"
## 전투 뒤 유닛별 기여도


func test_contribution_sums_events() -> void:
	var r := {"max_a": PackedFloat32Array([10, 10]), "max_b": PackedFloat32Array([10]), "events": [
		{"kind": "attack", "side": "a", "src": 0, "dst": 0, "dmg": 5.0},
		{"kind": "poison", "side": "a", "src": 1, "dst": 0, "dmg": 2.0},
		{"kind": "attack", "side": "b", "src": 0, "dst": 1, "dmg": 3.0},
		{"kind": "thorns", "side": "b", "src": 0, "dst": 0, "dmg": 1.0},
		{"kind": "heal", "side": "a", "src": 1, "dst": 0, "amount": 4.0},
		{"kind": "shield", "side": "a", "src": 0, "dst": 0, "dmg": 6.0},
	]}
	var c := BattleReport.contribution(r)
	check_eq(c["a"][0]["dealt"], 5.0)
	check_eq(c["a"][1]["dealt"], 2.0, "독 피해는 독을 건 유닛 몫")
	check_eq(c["b"][0]["taken"], 7.0)
	check_eq(c["a"][1]["taken"], 3.0)
	check_eq(c["a"][0]["taken"], 1.0, "가시 피해")
	check_eq(c["b"][0]["dealt"], 4.0)
	check_eq(c["a"][1]["healed"], 4.0)
	check_eq(c["a"][0]["shielded"], 6.0)
	check_eq(BattleReport.top(c["a"], "dealt"), 0)


func test_real_battle_damage_matches() -> void:
	var a: Array[Backpack] = [Backpack.new("soldier"), Backpack.new("archer")]
	var b: Array[Backpack] = [Backpack.new("recruit")]
	var dagger := Item.new("venom_fang")
	a[0].place(dagger, a[0].find_spot(dagger))
	var r := BattleSim.simulate(BattleSim.team_stats(a, "a"), BattleSim.team_stats(b, "b"))
	var c := BattleReport.contribution(r)
	var dealt := 0.0
	for row: Dictionary in c["a"]:
		dealt += float(row["dealt"])
	check(dealt > 0.0, "우리 팀이 피해를 줌")
	check(absf(dealt - float(c["b"][0]["taken"])) < 0.01, "준 피해 합 = 상대가 받은 피해 합")
