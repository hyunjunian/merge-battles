class_name Pricing
extends RefCounted
## 가격 규칙과 상점 등장 확률.
## - 모든 가격은 1~10원. 구매가는 2~10원, 판매가는 구매가의 절반(내림, 최소 1원)이라 항상 구매가보다 낮다.
## - 상점 등장 확률: 라운드가 오를수록 비싼 물건이 나올 확률이 커진다.
##   가격 c 의 가중치 = exp(-(c - 평균)^2 / (2 * 폭^2)), 평균은 라운드마다 오른다.

const MIN_PRICE := 1
const MAX_PRICE := 10


static func sell_price(buy_price: int) -> int:
	return clampi(buy_price / 2, MIN_PRICE, MAX_PRICE)


## 라운드별 등장 가격의 중심
static func mean_cost(round_no: int) -> float:
	return minf(2.0 + 0.45 * (round_no - 1), 9.5)


static func spread(round_no: int) -> float:
	return 1.4 + 0.06 * round_no


static func weight(cost: int, round_no: int) -> float:
	var d := float(cost) - mean_cost(round_no)
	var w := spread(round_no)
	return exp(-(d * d) / (2.0 * w * w))


## ids 중 하나를 라운드 확률에 따라 고른다. cost_of: def_id → 가격.
static func roll(ids: Array[String], cost_of: Callable, round_no: int, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	var weights: Array[float] = []
	for id in ids:
		var w := weight(int(cost_of.call(id)), round_no)
		weights.append(w)
		total += w
	var r := rng.randf() * total
	for i in ids.size():
		r -= weights[i]
		if r <= 0.0:
			return ids[i]
	return ids[-1]


static func item_cost(def_id: String) -> int:
	return int(ItemDB.get_def(def_id).get("cost", 1))


static func roll_item(round_no: int, rng: RandomNumberGenerator) -> String:
	return roll(ItemDB.ids(), item_cost, round_no, rng)


static func roll_unit(round_no: int, rng: RandomNumberGenerator) -> String:
	return roll(UnitDB.ids(), UnitDB.cost, round_no, rng)


static func describe_stats(s: Dictionary, range_value: float = 0.0) -> String:
	var parts: PackedStringArray = []
	var labels := {"hp": "체력", "atk": "공격", "armor": "방어", "spd": "공속", "regen": "회복", "move": "이동"}
	for k: String in ["hp", "atk", "armor", "spd", "regen"]:
		if s.has(k) and float(s[k]) != 0.0:
			parts.append("%s +%s" % [labels[k], ("%.2f" % float(s[k])).rstrip("0").rstrip(".")])
	if range_value > 0.0:
		parts.append("사거리 %.1f (원거리)" % range_value)
	return ", ".join(parts)
