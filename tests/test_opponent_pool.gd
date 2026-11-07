extends "res://tests/test_case.gd"
## 출전 풀: 수집(봇 대전), 저장·불러오기, 라운드별 상대 선택, 우승


func test_builder_runs_until_one_survivor() -> void:
	var pool := PoolBuilder.build(8, 5)
	check_eq(pool.entry_count(1), 8, "1라운드엔 8명 모두 출전")
	var last := pool.max_round()
	check(last >= 2, "여러 라운드 진행")
	check(pool.entry_count(last) >= 2, "마지막 라운드도 둘 이상 출전")
	for r in range(1, last):
		check(pool.entry_count(r + 1) <= pool.entry_count(r), "출전 인원은 줄기만 함 (%d→%d)" % [r, r + 1])
	check(not pool.has_round(last + 1), "마지막 1명만 남으면 끝")


func test_snapshot_roundtrip() -> void:
	var a := Backpack.new("soldier")
	var sword := Item.new("sword")
	a.place(sword, Vector2i(1, 0))
	var helmet := Item.new("helmet")
	helmet.rotated = true
	a.place(helmet, Vector2i(0, 0))
	a.field_pos = Vector2(1.5, 3.25)
	a.has_field_pos = true
	var entry := OpponentPool.snapshot([a] as Array[Backpack])
	var json: Variant = JSON.parse_string(JSON.stringify(entry))
	var team := OpponentPool.build_team(json)
	check_eq(team.size(), 1)
	var b := team[0]
	check_eq(b.def_id, "soldier")
	check_eq(b.items().size(), 2, "아이템 그대로")
	check(b.item_at(Vector2i(0, 1)) != null and b.item_at(Vector2i(0, 1)).def_id == "helmet", "회전한 투구 자리")
	check_eq(b.start_pos("a"), Vector2(1.5, 3.25), "배치 그대로")
	check_eq(b.start_pos("b"), Vector2(1.5, -3.25), "상대 쪽에선 뒤집힘")


func test_save_and_load() -> void:
	var pool := PoolBuilder.build(4, 9)
	var path := "user://test_pool.json"
	check_eq(pool.save_file(path), OK)
	var loaded := OpponentPool.load_file(path)
	check(loaded != null, "불러오기")
	check_eq(loaded.max_round(), pool.max_round())
	check_eq(loaded.entry_count(1), 4)
	check_eq(int(loaded.meta["players"]), 4)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(OpponentPool.load_file("user://없는파일.json") == null, "없는 파일은 null")


func test_game_uses_pool_round_and_wins_at_the_end() -> void:
	var pool := OpponentPool.new()
	var enemy := Backpack.new("recruit")
	pool.add(1, OpponentPool.snapshot([enemy] as Array[Backpack]))
	pool.add(1, OpponentPool.snapshot([Backpack.new("scout")] as Array[Backpack]))
	var gs := GameState.new(3)
	gs.opponents = pool
	var team := gs.enemy_team()
	check_eq(team.size(), 1)
	check(team[0].def_id in ["recruit", "scout"], "1라운드 출전 세팅 중 하나")
	check_eq(gs.enemy_team()[0].def_id, team[0].def_id, "같은 라운드엔 같은 상대")
	var s := gs.apply_outcome(true, 0)
	check(s["victory"], "2라운드 데이터가 없으면 우승")
	check(gs.victory)
	check(not gs.can_fight(), "우승 뒤엔 더 싸우지 않음")


func test_bundled_pool_exists_and_is_complete() -> void:
	var pool := OpponentPool.load_file()
	check(pool != null, "data/opponent_pool.json 이 있어야 함 (tools/build_pool.gd)")
	if pool == null:
		return
	check_eq(int(pool.meta.get("players", 0)), PoolBuilder.DEFAULT_PLAYERS)
	check_eq(pool.entry_count(1), PoolBuilder.DEFAULT_PLAYERS, "1라운드엔 모든 봇")
	for r in range(1, pool.max_round() + 1):
		check(pool.has_round(r), "라운드 %d 데이터" % r)


func test_pool_has_no_empty_lineups() -> void:
	var pool := OpponentPool.new()
	pool.add(1, [])
	check(not pool.has_round(1), "빈 출전은 저장하지 않음")
	var loaded := OpponentPool.from_dict({"rounds": {"2": [[], [{"u": "recruit", "x": 0.0, "z": 3.0, "i": []}]]}})
	check_eq(loaded.entry_count(2), 1, "불러올 때도 빈 출전은 버림")
	var real := OpponentPool.load_file()
	for r: int in real.rounds.keys():
		for e: Array in real.rounds[r]:
			check(not e.is_empty(), "출전 풀 %d 라운드에 빈 출전" % r)
