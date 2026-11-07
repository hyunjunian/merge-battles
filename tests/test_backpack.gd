extends "res://tests/test_case.gd"
## 유닛 가방: 크기, 칸 배치, 회전, 가격


func test_unit_size_comes_from_unit_type() -> void:
	var recruit := Backpack.new("recruit")
	check_eq(Vector2i(recruit.width, recruit.height), Vector2i(1, 2), "견습병은 1x2")
	var warlord := Backpack.new("warlord")
	check_eq(Vector2i(warlord.width, warlord.height), Vector2i(3, 4))
	check(warlord.cost() > recruit.cost(), "클수록 비쌈")
	check(recruit.base_stats().has("hp"), "기본 능력치")


func test_place_and_overlap() -> void:
	var pack := Backpack.new("", 3, 4)
	var sword := Item.new("sword")  # 1x2 세로
	check(pack.place(sword, Vector2i(0, 0)), "빈 가방에 놓기")
	check(pack.item_at(Vector2i(0, 1)) == sword, "모양 두 번째 칸 차지")
	check(not pack.can_place(Item.new("dagger"), Vector2i(0, 1)), "겹치면 안 됨")
	check(pack.can_place(Item.new("dagger"), Vector2i(1, 1)), "옆 칸은 됨")


func test_small_unit_limits_items() -> void:
	var recruit := Backpack.new("recruit")  # 1x2
	check(not recruit.can_place(Item.new("axe"), Vector2i(0, 0)), "2x2 는 안 들어감")
	check(recruit.place(Item.new("sword"), Vector2i(0, 0)), "1x2 는 꽉 차게 들어감")
	check_eq(recruit.free_cells(), 0)
	var helmet := Item.new("helmet")  # 2x1
	check_eq(Backpack.new("recruit").find_spot(helmet), Vector2i(0, 0), "돌려서 넣음")
	check(helmet.rotated, "세로로 돌아감")


func test_move_within_pack() -> void:
	var pack := Backpack.new("", 3, 4)
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


func test_values() -> void:
	var pack := Backpack.new("soldier")
	pack.place(Item.new("sword"), Vector2i(0, 0))
	pack.place(Item.new("apple"), Vector2i(1, 0))
	check_eq(pack.items_cost(), 5)
	check_eq(pack.total_value(), 4 + 5)
