class_name Bot
extends RefCounted
## 출전 풀 수집용 자동 플레이어. 사용자와 같은 GameState 규칙으로 상점을 이용한다.
## 봇마다 성향(원하는 유닛 수, 새로고침 성향, 원거리 선호)이 달라 출전 세팅이 다양해진다.

var state: GameState
var rng := RandomNumberGenerator.new()
## 원하는 유닛 수 (2~6)
var unit_target: int
## 살 게 없을 때 새로고침할 확률
var reroll_chance: float
## 남길 최소 돈 (이자처럼 아끼는 성향은 없지만, 가끔 다음 라운드를 위해 남긴다)
var keep_gold: int


func _init(seed_value: int, style_rng: RandomNumberGenerator) -> void:
	state = GameState.new(seed_value)
	rng.seed = seed_value + 7
	unit_target = style_rng.randi_range(2, 6)
	reroll_chance = style_rng.randf_range(0.0, 0.7)
	keep_gold = style_rng.randi_range(0, 2)


## 한 라운드의 상점 정리: 사기 → 넣기 → 배치
func shop_turn() -> void:
	var guard := 0
	while guard < 30:
		guard += 1
		if _buy_one():
			_equip_all()
			continue
		if state.gold - GameState.REROLL_COST >= keep_gold and rng.randf() < reroll_chance:
			state.reroll()
			continue
		break
	_equip_all()
	_arrange()


## 살 만한 것 하나를 산다. 샀으면 true.
func _buy_one() -> bool:
	var best := -1
	var best_score := -INF
	for i in state.shop.size():
		var offer := state.shop[i]
		if offer.is_empty() or state.buy_block_reason(i) != "":
			continue
		var cost := GameState.offer_cost(offer)
		if state.gold - cost < 0:
			continue
		var score := float(cost) + rng.randf() * 1.5
		if offer["kind"] == "unit":
			if state.units.size() >= unit_target:
				continue
			score += 6.0 if state.units.size() < 2 else 2.0
		else:
			if not _fits_somewhere(Item.new(offer["id"])):
				continue
		if score > best_score:
			best_score = score
			best = i
	if best < 0:
		return false
	return state.buy(best)


func _fits_somewhere(item: Item) -> bool:
	for u in state.units:
		if u.find_spot(item) != Backpack.NO_SPOT:
			return true
	return false


## 보유 아이템을 비싼 것부터 빈 가방에 넣는다
func _equip_all() -> void:
	var inv := state.inventory.duplicate()
	inv.sort_custom(func(a: Item, b: Item) -> bool: return a.cost() > b.cost())
	for item: Item in inv:
		var order := range(state.units.size())
		order.sort_custom(func(a: int, b: int) -> bool: return state.units[a].free_cells() > state.units[b].free_cells())
		for u: int in order:
			var spot := state.units[u].find_spot(item)
			if spot != Backpack.NO_SPOT and state.equip(item, u, spot):
				break


## 배치: 근접은 앞줄, 원거리는 뒷줄, x 는 조금씩 흩뜨린다
func _arrange() -> void:
	var bonus := Synergy.bonuses(Synergy.count_tags(state.units))
	for i in state.units.size():
		var ranged := BattleSim.is_ranged(BattleSim.unit_stats(state.units[i], bonus))
		var z := rng.randf_range(4.8, 6.5) if ranged else rng.randf_range(1.6, 3.4)
		var x := rng.randf_range(-BattleSim.HALF_W + 0.5, BattleSim.HALF_W - 0.5)
		state.move_unit(i, Vector2(x, z))
