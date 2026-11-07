class_name GameState
extends RefCounted
## 한 판(로그라이크)의 진행 상태.
##
## 규칙
## - 체력 100, 1라운드부터 시작. 매 라운드 전투를 하고, 승패와 상관없이 다음 라운드로 간다.
## - 지면 그 라운드 수만큼 체력이 준다. 0 이하가 되면 게임 오버(기록 저장).
## - 라운드가 끝날 때마다 돈을 받는다: 기본 BASE_INCOME + 연승/연패 보너스(연속 라운드 수 - 1, 최대 MAX_STREAK_BONUS).
## - 상점에서 유닛과 아이템을 산다. 유닛은 사는 즉시 전장에 나가고 빼려면 팔아야 한다.
##   아이템은 보유함에 들어가고, 유닛 가방에 넣고 뺄 수 있다. 판매가는 항상 구매가보다 낮다.
## - 시작: 돈 START_GOLD, 1x2 유닛(견습병) 하나.

const START_HP := 100
const START_GOLD := 4
const START_UNIT := "recruit"
const BASE_INCOME := 3
const MAX_STREAK_BONUS := 5
## 상점 칸 수. 칸마다 UNIT_CHANCE 확률로 유닛, 아니면 아이템 (개수·순서 고정 없음)
const SHOP_SIZE := 5
const UNIT_CHANCE := 0.4
const REROLL_COST := 1
const ENEMY_REROLL_COST := 1
const INTEREST_PER := 10

var hp: int = START_HP
var gold: int = START_GOLD
var round_no: int = 1
## 연속 기록: 양수면 연승 수, 음수면 연패 수
var streak: int = 0
var game_over: bool = false
## 전장의 우리 유닛 (각자 기본 slot 과, 옮겼다면 field_pos 를 가진다)
var units: Array[Backpack] = []
## 가방에 넣지 않은 보유 아이템
var inventory: Array[Item] = []
## 상점 진열: {"kind": "unit" | "item", "id": String}. 산 칸은 빈 사전.
var shop: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var run_seed: int = 0


func _init(seed_value: int = 0) -> void:
	run_seed = seed_value if seed_value != 0 else randi()
	rng.seed = run_seed
	_deploy(Backpack.new(START_UNIT))
	refill_shop()


# ── 돈 · 체력 규칙 ────────────────────────────────────

## 연속 라운드 수에 비례한 보너스 (2연속부터 +1, 3연속 +2, ...)
static func streak_bonus(streak_value: int) -> int:
	return clampi(absi(streak_value) - 1, 0, MAX_STREAK_BONUS)


static func income_for(streak_value: int) -> int:
	return BASE_INCOME + streak_bonus(streak_value)


## 이자: 전투가 끝났을 때 가진 돈 10원마다 1원
static func interest_for(gold_value: int) -> int:
	return maxi(0, gold_value) / INTEREST_PER


## 지면 잃는 체력 = 그 라운드 수
static func hp_loss_for(round_value: int) -> int:
	return maxi(1, round_value)


# ── 전장 자리 ─────────────────────────────────────────

## 새 유닛이 설 기본 자리: 다른 유닛과 겹치지 않는 첫 자리 번호
func free_slot() -> int:
	for s in BattleSim.SLOT_COUNT:
		var p := BattleSim.slot_position("a", s)
		var clear := true
		for u in units:
			if u.start_pos("a").distance_to(p) < BattleSim.MIN_GAP:
				clear = false
				break
		if clear:
			return s
	return 0


func has_free_slot() -> bool:
	return units.size() < BattleSim.SLOT_COUNT


func _deploy(pack: Backpack) -> void:
	pack.slot = free_slot()
	pack.field_pos = place_unit_pos(BattleSim.slot_position("a", pack.slot), pack)
	pack.has_field_pos = true
	units.append(pack)


func _other_positions(except: Backpack) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for u in units:
		if u != except:
			out.append(u.start_pos("a"))
	return out


func place_unit_pos(p: Vector2, pack: Backpack) -> Vector2:
	return BattleSim.place_own(p, _other_positions(pack))


## 유닛을 전장의 원하는 곳으로 옮긴다 (우리 진영 안, 겹치면 밀어냄). 실제 놓인 위치를 돌려준다.
func move_unit(index: int, p: Vector2) -> Vector2:
	if game_over or index < 0 or index >= units.size():
		return Vector2.ZERO
	var pack := units[index]
	pack.field_pos = place_unit_pos(p, pack)
	pack.has_field_pos = true
	return pack.field_pos


# ── 상점 ──────────────────────────────────────────────

func refill_shop() -> void:
	shop.clear()
	for i in SHOP_SIZE:
		if rng.randf() < UNIT_CHANCE:
			shop.append({"kind": "unit", "id": Pricing.roll_unit(round_no, rng)})
		else:
			shop.append({"kind": "item", "id": Pricing.roll_item(round_no, rng)})


static func offer_cost(offer: Dictionary) -> int:
	if offer.is_empty():
		return 0
	return UnitDB.cost(offer["id"]) if offer["kind"] == "unit" else Pricing.item_cost(offer["id"])


## 살 수 없으면 이유, 살 수 있으면 빈 문자열
func buy_block_reason(index: int) -> String:
	if game_over:
		return "게임이 끝났습니다"
	if index < 0 or index >= shop.size() or shop[index].is_empty():
		return "팔린 물건입니다"
	if gold < offer_cost(shop[index]):
		return "돈이 부족합니다"
	if shop[index]["kind"] == "unit" and not has_free_slot():
		return "전장에 자리가 없습니다 (최대 %d)" % BattleSim.SLOT_COUNT
	return ""


func buy(index: int) -> bool:
	if buy_block_reason(index) != "":
		return false
	var offer := shop[index]
	gold -= offer_cost(offer)
	if offer["kind"] == "unit":
		_deploy(Backpack.new(offer["id"]))
	else:
		inventory.append(Item.new(offer["id"]))
	shop[index] = {}
	return true


## 이번 라운드 상대 새로고침 횟수 (라운드가 바뀌면 0)
func enemy_reroll_count() -> int:
	return _enemy_rerolls if _enemy_rerolls_round == round_no else 0


## 상대 새로고침: 전투 전 1원으로 이번 라운드 상대를 같은 라운드의 다른 출전으로 바꾼다
func can_reroll_enemy() -> bool:
	if game_over or victory or gold < ENEMY_REROLL_COST:
		return false
	# 풀에 이 라운드 출전이 하나뿐이면 바꿀 상대가 없다
	return opponents == null or opponents.entry_count(round_no) >= 2


func reroll_enemy() -> bool:
	if not can_reroll_enemy():
		return false
	gold -= ENEMY_REROLL_COST
	_enemy_rerolls = enemy_reroll_count() + 1
	_enemy_rerolls_round = round_no
	return true


func reroll() -> bool:
	if game_over or gold < REROLL_COST:
		return false
	gold -= REROLL_COST
	refill_shop()
	return true


## 유닛 판매: 가방 속 아이템은 보유함으로 돌아온다.
func sell_unit(pack: Backpack) -> bool:
	if game_over or not units.has(pack):
		return false
	for item in pack.items():
		pack.remove(item)
		inventory.append(item)
	units.erase(pack)
	gold += pack.sell_price()
	return true


func sell_item(item: Item) -> bool:
	if game_over or not owns(item):
		return false
	unequip(item)
	inventory.erase(item)
	gold += item.sell_price()
	return true


# ── 아이템 장착 ───────────────────────────────────────

## 아이템이 들어 있는 유닛 번호. 보유함에 있으면 -1.
func unit_of(item: Item) -> int:
	for i in units.size():
		if units[i].has_item(item):
			return i
	return -1


func owns(item: Item) -> bool:
	return inventory.has(item) or unit_of(item) >= 0


func can_equip(item: Item, unit_idx: int, pos: Vector2i) -> bool:
	if game_over or unit_idx < 0 or unit_idx >= units.size() or not owns(item):
		return false
	return units[unit_idx].can_place(item, pos)


## 지금 방향으로 안 들어가면 돌려서라도 놓을 수 있는가
func can_equip_flexible(item: Item, unit_idx: int, pos: Vector2i) -> bool:
	if can_equip(item, unit_idx, pos):
		return true
	if not item.is_rotatable():
		return false
	item.rotated = not item.rotated
	var ok := can_equip(item, unit_idx, pos)
	item.rotated = not item.rotated
	return ok


## 끌어 놓기용 장착: 지금 방향으로 안 되면 돌려서 넣는다
func equip_flexible(item: Item, unit_idx: int, pos: Vector2i) -> bool:
	if equip(item, unit_idx, pos):
		return true
	if not item.is_rotatable():
		return false
	item.rotated = not item.rotated
	if equip(item, unit_idx, pos):
		return true
	item.rotated = not item.rotated
	return false


## 이 아이템이 그 유닛 가방 어딘가에 들어갈 수 있는가 (이미 들어 있으면 true). 아이템은 바꾸지 않는다.
func fits_in(item: Item, unit_idx: int) -> bool:
	if unit_idx < 0 or unit_idx >= units.size():
		return false
	var pack := units[unit_idx]
	if pack.has_item(item):
		return true
	var probe := Item.new(item.def_id)
	probe.rotated = item.rotated
	return pack.find_spot(probe) != Backpack.NO_SPOT


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


## 유닛 가방의 아이템을 모두 보유함으로. 뺀 개수를 돌려준다.
func unequip_all(unit_idx: int) -> int:
	if game_over or unit_idx < 0 or unit_idx >= units.size():
		return 0
	var pack := units[unit_idx]
	var n := 0
	for item in pack.items():
		pack.remove(item)
		inventory.append(item)
		n += 1
	return n


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


# ── 전투 ──────────────────────────────────────────────

## 상대 출전 풀 (OpponentPool). 없으면 EnemyGen 으로 상대를 만든다.
var opponents: OpponentPool = null
## 풀에 다음 라운드 상대가 없어 이긴 상태
var victory: bool = false
var _enemy_rerolls: int = 0
var _enemy_rerolls_round: int = 0
var _enemy_cache_key: int = 0
var _enemy_cache: Array[Backpack] = []


func enemy_team() -> Array[Backpack]:
	var rerolls := enemy_reroll_count()
	var key := hash([round_no, run_seed, opponents != null, rerolls])
	if _enemy_cache_key != key or _enemy_cache.is_empty():
		_enemy_cache_key = key
		if opponents != null and opponents.has_round(round_no):
			_enemy_cache = opponents.team_for(round_no, run_seed, rerolls)
		else:
			_enemy_cache = EnemyGen.generate(round_no, run_seed if rerolls == 0 else hash([run_seed, rerolls]))
	# 같은 라운드 안에서는 같은 팀 (화면이 여러 번 물어봐도)
	var out: Array[Backpack] = []
	for p in _enemy_cache:
		out.append(p)
	return out


func can_fight() -> bool:
	# 유닛이 없어도 전투는 시작할 수 있다 (바로 진다)
	return not game_over and not victory


func fight() -> Dictionary:
	return BattleSim.simulate(BattleSim.team_stats(units, "a"), BattleSim.team_stats(enemy_team(), "b"))


static func surviving(result: Dictionary, side: int) -> int:
	var last: Array = result["frames"][-1]
	var n := 0
	var count: int = (result["max_a"] if side == 0 else result["max_b"]).size()
	for i in count:
		if BattleSim.frame_hp(last, side, i) > 0.0:
			n += 1
	return n


## 전투 결과 반영(우리가 a 쪽). apply_outcome 참고.
func apply_result(result: Dictionary) -> Dictionary:
	var won: bool = result["winner"] == "a"
	return apply_outcome(won)


## 승패로 체력(지면 라운드 수만큼)·연속 기록·수입·다음 라운드·상점을 갱신한다.
## 출전 풀 수집(봇끼리 대전)에서도 양쪽 플레이어에 각각 쓴다.
## 반환: {won, hp_loss, income, bonus, interest, streak, round_played, game_over, victory}
func apply_outcome(won: bool) -> Dictionary:
	var played := round_no
	var loss := 0 if won else hp_loss_for(played)
	hp -= loss
	if won:
		streak = streak + 1 if streak > 0 else 1
	else:
		streak = streak - 1 if streak < 0 else -1
	var summary := {
		"won": won, "hp_loss": loss, "streak": streak,
		"round_played": played, "income": 0, "bonus": 0, "interest": 0, "game_over": false, "victory": false,
	}
	if hp <= 0:
		hp = 0
		game_over = true
		summary["game_over"] = true
		return summary
	# 수입 = 기본 + 연승/연패 보너스 + 이자(전투 끝에 가진 돈 기준)
	var interest := interest_for(gold)
	var income := income_for(streak) + interest
	gold += income
	summary["income"] = income
	summary["bonus"] = streak_bonus(streak)
	summary["interest"] = interest
	round_no += 1
	refill_shop()
	# 출전 풀에 다음 라운드 상대가 없으면 우승
	if opponents != null and not opponents.has_round(round_no):
		victory = true
		summary["victory"] = true
	return summary
