extends "res://tests/test_case.gd"
## 메인 장면: 불러오기와 화면 조작 흐름

const Main := preload("res://scripts/main.gd")


func _spawn() -> Node:
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	var main := packed.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	# 테스트 실행기(_initialize) 안에서는 root 가 아직 준비 전이라 _ready 가 자동으로 불리지 않는다.
	if main.get("state") == null:
		main.notification(Node.NOTIFICATION_READY)
	return main


func test_main_scene_loads() -> void:
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	check(packed != null, "메인 장면을 불러오지 못함")
	if packed == null:
		return
	var main := packed.instantiate()
	check(main.has_node("Title"), "Title 노드 없음")
	check(main.has_node("Scroll/Content"), "Content 노드 없음")
	check(main.has_node("ActionBar"), "ActionBar 노드 없음")
	check((main.get_node("Title") as Label).text != "", "제목이 비어 있음")
	free_later(main)


func test_clamp_score() -> void:
	check_eq(Main.clamp_score(-5), 0, "음수")
	check_eq(Main.clamp_score(42), 42, "보통 값")
	check_eq(Main.clamp_score(10_000_000), 999_999, "상한")


func test_select_and_equip_by_taps() -> void:
	var main := _spawn()
	var state: GameState = main.state
	var item: Item = state.inventory[0]
	main._on_inventory_pressed(item)
	check(main.selected == item, "보유 아이템 선택")
	main._on_cell_pressed(1, Vector2i(0, 0))
	check_eq(state.unit_of(item), 1, "누른 가방에 들어감")
	check(main.selected == null, "넣으면 선택 해제")
	main._on_cell_pressed(1, Vector2i(0, 0))
	check(main.selected == item, "가방 속 아이템을 누르면 선택")
	main._on_unequip()
	check(state.inventory.has(item), "빼기")
	free_later(main)


func test_depart_and_fight_flow() -> void:
	var main := _spawn()
	var state: GameState = main.state
	check(state.phase == GameState.Phase.CAMP, "캠프에서 시작")
	main._on_inventory_pressed(state.inventory[0])
	main._on_cell_pressed(0, Vector2i(0, 0))
	main._on_depart()
	check(state.phase == GameState.Phase.EXPEDITION, "출정")
	main._on_fight()
	check(main.battle_view != null, "전투 화면")
	var round_before := state.round_no
	main.battle_view.skip()
	check(main.battle_view.done, "건너뛰면 끝")
	var won: bool = main.last_result["winner"] == "a"
	check_eq(state.round_no, round_before + (1 if won else 0), "결과 반영")
	free_later(main)


func test_unit_color_uses_priciest_item() -> void:
	var pack := Backpack.new()
	pack.place(Item.new("apple"), Vector2i(0, 0))
	pack.place(Item.new("axe"), Vector2i(1, 0))
	check_eq(Main.unit_color(pack), Item.new("axe").color())
	check_eq(Main.unit_color(Backpack.new()), Color.GRAY)
