extends "res://tests/test_case.gd"
## 가방 칸 배치·회전·비용


func test_place_and_overlap() -> void:
	var pack := Backpack.new()
	var sword := Item.new("sword")  # 1x2 세로
	check(pack.place(sword, Vector2i(0, 0)), "빈 가방에 놓기")
	check(pack.item_at(Vector2i(0, 1)) == sword, "모양 두 번째 칸 차지")
	check(not pack.can_place(Item.new("dagger"), Vector2i(0, 1)), "겹치면 안 됨")
	check(pack.can_place(Item.new("dagger"), Vector2i(1, 1)), "옆 칸은 됨")


func test_out_of_bounds() -> void:
	var pack := Backpack.new()
	check(not pack.can_place(Item.new("fire_staff"), Vector2i(0, 2)), "1x3 이 아래로 넘침")
	check(not pack.can_place(Item.new("axe"), Vector2i(2, 0)), "2x2 가 오른쪽으로 넘침")
	check(pack.can_place(Item.new("axe"), Vector2i(1, 2)), "오른쪽 아래 2x2")


func test_move_within_pack() -> void:
	var pack := Backpack.new()
	var sword := Item.new("sword")
	pack.place(sword, Vector2i(0, 0))
	check(pack.place(sword, Vector2i(0, 1)), "자기 자리와 겹쳐도 옮길 수 있음")
	check_eq(pack.placements.size(), 1, "중복 배치 없음")
	check_eq(pack.position_of(sword), Vector2i(0, 1))


func test_rotation_changes_cells() -> void:
	var staff := Item.new("fire_staff")
	check_eq(staff.size(), Vector2i(1, 3))
	staff.rotated = true
	check_eq(staff.size(), Vector2i(3, 1))
	check(not Item.new("axe").is_rotatable(), "정사각형은 회전 의미 없음")


func test_find_spot_rotates_when_needed() -> void:
	var pack := Backpack.new()
	# 위 3줄을 채워 맨 아래 한 줄(3x1)만 남긴다
	for y in 3:
		for x in 3:
			pack.place(Item.new("apple"), Vector2i(x, y))
	var staff := Item.new("fire_staff")
	var spot := pack.find_spot(staff)
	check_eq(spot, Vector2i(0, 3), "맨 아래 줄")
	check(staff.rotated, "가로로 돌려야 들어감")
	check_eq(pack.free_cells(), 3)


func test_total_cost_and_tier() -> void:
	var pack := Backpack.new()
	pack.place(Item.new("sword", 2), Vector2i(0, 0))
	pack.place(Item.new("apple"), Vector2i(1, 0))
	check_eq(Item.new("sword", 2).cost(), 5, "3 x 1.5 = 4.5 → 5")
	check_eq(pack.total_cost(), 6)
	check_eq(Item.new("sword", 3).stats()["atk"], 20.0, "3성은 능력치 4배")
