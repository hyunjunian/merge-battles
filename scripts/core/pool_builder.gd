class_name PoolBuilder
extends RefCounted
## 출전 풀 수집 (1단계).
## 1. 봇 N명이 각자 한 판(GameState)을 병렬로 진행한다.
## 2. 매 라운드 살아 있는 봇끼리 무작위로 둘씩 싸운다. 홀수면 남은 한 명은 다른 봇 세팅의 "유령"과 싸운다(유령은 피해 없음).
## 3. 매 라운드 상점 정리가 끝난 모든 생존 봇의 출전 세팅을 그 라운드에 저장한다.
## 4. 마지막 1명이 남으면 끝.

const DEFAULT_PLAYERS := 128
const MAX_ROUNDS := 80


## 반환: OpponentPool (meta 에 players, seed, rounds, winner_round 기록)
static func build(players: int = DEFAULT_PLAYERS, seed_value: int = 1, log_progress: bool = false) -> OpponentPool:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bots: Array[Bot] = []
	for i in players:
		bots.append(Bot.new(hash([seed_value, i]), rng))
	var pool := OpponentPool.new()
	var round_no := 1
	while round_no <= MAX_ROUNDS:
		var alive: Array[Bot] = []
		for b in bots:
			if not b.state.game_over:
				alive.append(b)
		if alive.size() <= 1:
			break
		# 상점 정리 → 출전 세팅 저장
		for b in alive:
			b.shop_turn()
			pool.add(round_no, OpponentPool.snapshot(b.state.units))
		# 무작위 짝
		var order := alive.duplicate()
		_shuffle(order, rng)
		var i := 0
		while i + 1 < order.size():
			_duel(order[i], order[i + 1])
			i += 2
		if i < order.size():
			var ghost: Bot = order[rng.randi_range(0, order.size() - 2)]
			_ghost_duel(order[i], ghost)
		if log_progress:
			print("라운드 %d: 출전 %d명" % [round_no, alive.size()])
		round_no += 1
	pool.meta = {"players": players, "seed": seed_value, "rounds": pool.max_round()}
	return pool


static func _duel(a: Bot, b: Bot) -> void:
	var r := BattleSim.simulate(BattleSim.team_stats(a.state.units, "a"), BattleSim.team_stats(b.state.units, "b"))
	# 승자가 없으면(둘 다 유닛 없음) 둘 다 진다
	var a_won: bool = r["winner"] == "a"
	var b_won: bool = r["winner"] == "b"
	a.state.apply_outcome(a_won, 0 if a_won else GameState.surviving(r, 1))
	b.state.apply_outcome(b_won, 0 if b_won else GameState.surviving(r, 0))


## 유령전: real 만 결과를 받는다
static func _ghost_duel(real: Bot, ghost: Bot) -> void:
	var ghost_units := OpponentPool.build_team(OpponentPool.snapshot(ghost.state.units))
	var r := BattleSim.simulate(BattleSim.team_stats(real.state.units, "a"), BattleSim.team_stats(ghost_units, "b"))
	var won: bool = r["winner"] == "a"
	real.state.apply_outcome(won, 0 if won else GameState.surviving(r, 1))


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
