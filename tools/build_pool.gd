extends SceneTree
## 출전 풀 만들기 (1단계): 봇 N명이 마지막 1명이 남을 때까지 대전하며 라운드별 출전 세팅을 모은다.
##   godot --headless --path . -s res://tools/build_pool.gd -- [N] [seed]
## 결과: res://data/opponent_pool.json


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var players := args[0].to_int() if args.size() > 0 else PoolBuilder.DEFAULT_PLAYERS
	var seed_value := args[1].to_int() if args.size() > 1 else 20261107
	var t0 := Time.get_ticks_msec()
	var pool := PoolBuilder.build(players, seed_value, true)
	var err := pool.save_file(OpponentPool.DEFAULT_PATH)
	if err != OK:
		printerr("✗ 저장 실패: %s" % error_string(err))
		quit(1)
		return
	print("✓ %s : 봇 %d명, %d라운드, %.1f초" % [OpponentPool.DEFAULT_PATH, players, pool.max_round(), (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)
