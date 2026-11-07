class_name Backpack
extends RefCounted
## 유닛 하나 = 가방 하나. 유닛 종류(def_id)가 가방 크기와 기본 능력치를 정하고,
## 가방에 넣은 아이템이 능력치를 바꾼다. slot 은 전장에서 서는 자리 번호.

const NO_SPOT := Vector2i(-1, -1)

static var _next_uid: int = 1

var uid: int
var def_id: String = ""
var width: int = 3
var height: int = 4
## 전장 자리 번호 (BattleSim.slot_position). -1 이면 아직 없음.
var slot: int = -1
## 각 항목: {"item": Item, "pos": Vector2i}
var placements: Array[Dictionary] = []


## def_id 가 있으면 UnitDB 에서 크기를 가져온다. 없으면 w x h 크기의 이름 없는 가방.
func _init(p_def_id: String = "", w: int = 3, h: int = 4) -> void:
	uid = _next_uid
	_next_uid += 1
	def_id = p_def_id
	if UnitDB.has(def_id):
		var s: Vector2i = UnitDB.get_def(def_id)["size"]
		width = s.x
		height = s.y
	else:
		width = w
		height = h


func def() -> Dictionary:
	return UnitDB.get_def(def_id)


func display_name() -> String:
	return def().get("name", "유닛")


func color() -> Color:
	return def().get("color", Color.GRAY)


func cost() -> int:
	return int(def().get("cost", 0))


func sell_price() -> int:
	return Pricing.sell_price(cost())


## 유닛 기본 능력치 (아이템 제외)
func base_stats() -> Dictionary:
	var out := {}
	var base: Dictionary = def().get("stats", {})
	for k: String in base.keys():
		out[k] = float(base[k])
	return out


func items() -> Array[Item]:
	var out: Array[Item] = []
	for p in placements:
		out.append(p["item"])
	return out


func is_empty() -> bool:
	return placements.is_empty()


func has_item(item: Item) -> bool:
	return _index_of(item) >= 0


func position_of(item: Item) -> Vector2i:
	var i := _index_of(item)
	return placements[i]["pos"] if i >= 0 else NO_SPOT


func item_at(cell: Vector2i) -> Item:
	for p in placements:
		var item: Item = p["item"]
		var pos: Vector2i = p["pos"]
		for c in item.cells():
			if pos + c == cell:
				return item
	return null


## item 을 pos(모양의 왼쪽 위) 에 놓을 수 있는가. item 이 이미 가방에 있으면 자기 자리는 빈 칸으로 본다.
func can_place(item: Item, pos: Vector2i) -> bool:
	for c in item.cells():
		var cell := pos + c
		if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
			return false
		var other := item_at(cell)
		if other != null and other != item:
			return false
	return true


func place(item: Item, pos: Vector2i) -> bool:
	if not can_place(item, pos):
		return false
	remove(item)
	placements.append({"item": item, "pos": pos})
	return true


func remove(item: Item) -> bool:
	var i := _index_of(item)
	if i < 0:
		return false
	placements.remove_at(i)
	return true


## 빈 자리를 위→아래, 왼→오 순서로 찾는다. 못 찾으면 회전해서 다시 찾고, 그래도 없으면 NO_SPOT.
## 찾았을 때 회전이 필요했다면 item.rotated 가 바뀐 채로 돌아온다.
func find_spot(item: Item) -> Vector2i:
	for attempt in 2:
		for y in height:
			for x in width:
				if can_place(item, Vector2i(x, y)):
					return Vector2i(x, y)
		if not item.is_rotatable():
			break
		item.rotated = not item.rotated
	return NO_SPOT


## 가방 속 아이템 가격 합
func items_cost() -> int:
	var total := 0
	for item in items():
		total += item.cost()
	return total


## 유닛 + 아이템 가격 합
func total_value() -> int:
	return cost() + items_cost()


func free_cells() -> int:
	var used := 0
	for item in items():
		used += item.cells().size()
	return width * height - used


func _index_of(item: Item) -> int:
	for i in placements.size():
		if placements[i]["item"] == item:
			return i
	return -1
