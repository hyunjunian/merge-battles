class_name Backpack
extends RefCounted
## 유닛 하나의 가방. 가방에 넣은 아이템이 곧 그 유닛의 능력치가 된다.
## 아이템이 하나도 없는 가방은 전투에 나가지 않는다.

const WIDTH := 3
const HEIGHT := 4
const NO_SPOT := Vector2i(-1, -1)

## 각 항목: {"item": Item, "pos": Vector2i}
var placements: Array[Dictionary] = []


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
		if cell.x < 0 or cell.y < 0 or cell.x >= WIDTH or cell.y >= HEIGHT:
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
		for y in HEIGHT:
			for x in WIDTH:
				if can_place(item, Vector2i(x, y)):
					return Vector2i(x, y)
		if not item.is_rotatable():
			break
		item.rotated = not item.rotated
	return NO_SPOT


func total_cost() -> int:
	var total := 0
	for item in items():
		total += item.cost()
	return total


func free_cells() -> int:
	var used := 0
	for item in items():
		used += item.cells().size()
	return WIDTH * HEIGHT - used


func _index_of(item: Item) -> int:
	for i in placements.size():
		if placements[i]["item"] == item:
			return i
	return -1
