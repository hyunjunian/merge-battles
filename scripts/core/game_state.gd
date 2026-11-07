class_name GameState
extends RefCounted
## 한 판의 진행 상태: 골드, 라운드, 보유 아이템, 유닛 가방, 상점.
##
## 흐름
##   베이스 캠프(상점·합성·편성) → 출정 → 라운드 N 전투
##     승리: 골드를 받고 라운드 N+1 로 (원정 계속, 원하면 캠프로 귀환)
##     패배: 베이스 캠프로 돌아온다. 라운드는 유지되어 정비 후 같은 라운드에 다시 도전한다.
##
## 예산: 가방에 넣은 아이템 비용의 합은 라운드 예산을 넘을 수 없다.

enum Phase { CAMP, EXPEDITION }

const UNIT_SLOTS := 3
const START_GOLD := 10
const SHOP_SIZE := 4
const REROLL_COST := 1
const START_ITEMS: Array[String] = ["sword", "buckler", "apple"]

var gold: int = START_GOLD
var round_no: int = 1
var best_round: int = 0
var phase: Phase = Phase.CAMP
## 가방에 넣지 않은 보유 아이템
var inventory: Array[Item] = []
var units: Array[Backpack] = []
var shop: Array[Item] = []
var rng := RandomNumberGenerator.new()
var run_seed: int = 0


func _init(seed_value: int = 0) -> void:
	run_seed = seed_value if seed_value != 0 else randi()
	rng.seed = run_seed
	for i in UNIT_SLOTS:
		units.append(Backpack.new())
	for id in START_ITEMS:
		inventory.append(Item.new(id))
	refill_shop()


# ── 예산 ──────────────────────────────────────────────

static func budget_for_round(r: int) -> int:
	return 8 + 4 * (r - 1)


func budget() -> int:
	return budget_for_round(round_no)


func used_budget() -> int:
	var total := 0
	for u in units:
		total += u.total_cost()
	return total


## 보상: 승리하면 3 + 라운드, 패배하면 2.
static func reward_for(r: int, won: bool) -> int:
	return 3 + r if won else 2


# ── 아이템 위치 ────────────────────────────────────────

## 아이템이 들어 있는 유닛 번호. 보유함에 있으면 -1.
func unit_of(item: Item) -> int:
	for i in units.size():
		if units[i].has_item(item):
			return i
	return -1


func owns(item: Item) -> bool:
	return inventory.has(item) or unit_of(item) >= 0


## 아이템을 unit_idx 번 유닛 가방의 pos 에 놓을 수 있는가 (칸과 예산 모두 확인).
func can_equip(item: Item, unit_idx: int, pos: Vector2i) -> bool:
	if unit_idx < 0 or unit_idx >= units.size() or not owns(item):
		return false
	if not units[unit_idx].can_place(item, pos):
		return false
	var current := unit_of(item)
	var extra := 0 if current >= 0 else item.cost()
	return used_budget() + extra <= budget()


## 보유함 → 가방, 또는 가방 → 다른 자리/다른 가방.
func equip(item: Item, unit_idx: int, pos: Vector2i) -> bool:
	if not can_equip(item, unit_idx, pos):
		return false
	var current := unit_of(item)
	if current >= 0 and current != unit_idx:
		units[current].remove(item)
	inventory.erase(item)
	units[unit_idx].place(item, pos)
	return true


func unequip(item: Item) -> bool:
	var current := unit_of(item)
	if current < 0:
		return false
	units[current].remove(item)
	inventory.append(item)
	return true


## 회전. 가방 안에 있으면 같은 자리에서 돌아갈 수 있을 때만.
func rotate(item: Item) -> bool:
	if not item.is_rotatable():
		return false
	var current := unit_of(item)
	item.rotated = not item.rotated
	if current >= 0 and not units[current].can_place(item, units[current].position_of(item)):
		item.rotated = not item.rotated
		return false
	return true


# ── 상점 · 판매 · 합성 (베이스 캠프에서만) ─────────────

func refill_shop() -> void:
	shop.clear()
	var ids := ItemDB.ids()
	for i in SHOP_SIZE:
		shop.append(Item.new(ids[rng.randi_range(0, ids.size() - 1)]))


func reroll() -> bool:
	if phase != Phase.CAMP or gold < REROLL_COST:
		return false
	gold -= REROLL_COST
	refill_shop()
	return true


func buy(index: int) -> bool:
	if phase != Phase.CAMP or index < 0 or index >= shop.size():
		return false
	var item := shop[index]
	if gold < item.cost():
		return false
	gold -= item.cost()
	shop.remove_at(index)
	inventory.append(item)
	return true


func sell(item: Item) -> bool:
	if phase != Phase.CAMP or not owns(item):
		return false
	unequip(item)
	inventory.erase(item)
	gold += item.sell_price()
	return true


## item 과 합성할 수 있는 다른 보유 아이템 (보유함 우선, 없으면 가방 안).
func merge_partner(item: Item) -> Item:
	for other in inventory:
		if item.can_merge_with(other):
			return other
	for u in units:
		for other in u.items():
			if item.can_merge_with(other):
				return other
	return null


## 합성 결과는 보유함으로 들어간다. 실패하면 null.
func merge(item: Item) -> Item:
	if phase != Phase.CAMP or not owns(item):
		return null
	var partner := merge_partner(item)
	if partner == null:
		return null
	for it: Item in [item, partner]:
		unequip(it)
		inventory.erase(it)
	var result := Item.new(item.def_id, item.tier + 1)
	inventory.append(result)
	return result


# ── 전투 ──────────────────────────────────────────────

func has_team() -> bool:
	for u in units:
		if not u.is_empty():
			return true
	return false


func enemy_team() -> Array[Backpack]:
	return EnemyGen.generate(round_no, run_seed)


func start_expedition() -> bool:
	if not has_team():
		return false
	phase = Phase.EXPEDITION
	return true


func return_to_camp() -> void:
	phase = Phase.CAMP
	refill_shop()


func fight() -> Dictionary:
	return BattleSim.simulate(BattleSim.team_stats(units), BattleSim.team_stats(enemy_team()))


## 전투 결과 반영. 받은 골드를 돌려준다.
func apply_result(won: bool) -> int:
	var reward := reward_for(round_no, won)
	gold += reward
	if won:
		best_round = maxi(best_round, round_no)
		round_no += 1
	else:
		return_to_camp()
	return reward
