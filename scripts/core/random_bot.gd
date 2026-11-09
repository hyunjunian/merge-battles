class_name RandomBot
extends Bot
## 실력 측정용 "아무렇게나" 플레이어: 살 수 있는 것 중 무작위로 사고, 아이템은 아무 데나, 배치도 아무 데나.
## 새로고침·상대 바꾸기는 하지 않는다.


func shop_turn() -> void:
	var guard := 0
	while guard < 30:
		guard += 1
		if rng.randf() < 0.25:
			break
		var choices: Array[int] = []
		for i in state.shop.size():
			if not state.shop[i].is_empty() and state.buy_block_reason(i) == "":
				choices.append(i)
		if choices.is_empty():
			break
		state.buy(choices[rng.randi_range(0, choices.size() - 1)])
	# 보유 아이템을 무작위 유닛의 빈 곳에
	for item: Item in state.inventory.duplicate():
		if state.units.is_empty():
			break
		var u := rng.randi_range(0, state.units.size() - 1)
		var spot := state.units[u].find_spot(item)
		if spot != Backpack.NO_SPOT:
			state.equip(item, u, spot)
	for i in state.units.size():
		state.move_unit(i, Vector2(rng.randf_range(-BattleSim.HALF_W, BattleSim.HALF_W), rng.randf_range(BattleSim.OWN_MIN_Z, BattleSim.HALF_D)))
