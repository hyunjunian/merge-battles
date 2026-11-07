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
	check(main.has_node("Field/BattleView3D"), "전장 노드 없음")
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
	var round_before := state.round_no
	main._on_fight()
	check(main.battling, "전투 중")
	check(main.battle_view.mode == BattleView3D.Mode.PLAYING, "전장에서 전투 재생")
	main.battle_view.skip()
	check(main.battle_view.done, "건너뛰면 끝")
	var won: bool = main.last_result["winner"] == "a"
	check_eq(state.round_no, round_before + (1 if won else 0), "결과 반영")
	check(not main.battling, "전투 끝")
	main._on_continue()
	check(main.battle_view.mode == BattleView3D.Mode.PREVIEW, "다음 상대 미리보기로 돌아옴")
	free_later(main)


func test_field_always_shows_slots_and_next_enemy() -> void:
	var main := _spawn()
	var state: GameState = main.state
	check_eq(main.battle_view.unit_count("a"), GameState.UNIT_SLOTS, "빈자리 포함 우리 자리 3개")
	check_eq(main.battle_view.unit_count("b"), state.enemy_team().size(), "다음 상대가 서 있음")
	free_later(main)


func test_tap_enemy_shows_detail_and_tap_own_unit_edits() -> void:
	var main := _spawn()
	main._on_field_tapped("b", 0)
	check_eq(main.inspect_enemy, 0, "적 상세 보기")
	check_eq(main.battle_view.highlight.get("side", ""), "b", "적 강조")
	main._on_field_tapped("a", 2)
	check_eq(main.inspect_enemy, -1, "우리 유닛을 누르면 상세 닫힘")
	check_eq(main.active_unit, 2, "그 유닛 편집")
	# 편성은 고른 유닛 가방으로 들어간다
	var item: Item = main.state.inventory[0]
	main._on_inventory_pressed(item)
	main._on_cell_pressed(main.active_unit, Vector2i(0, 0))
	check_eq(main.state.unit_of(item), 2)
	free_later(main)


func test_roster_keeps_empty_slots_for_our_side() -> void:
	var packs: Array[Backpack] = [Backpack.new(), Backpack.new(), Backpack.new()]
	packs[1].place(Item.new("short_bow"), Vector2i(0, 0))
	var ours := Main.roster(packs, "a", "유닛 %d", true)
	check_eq(ours.size(), 3)
	check(ours[0]["empty"] and not ours[1]["empty"], "빈자리 표시")
	check(ours[1]["ranged"], "원거리 표시")
	check_eq(ours[1]["pos"], BattleSim.start_position("a", 1, 3), "전투 시작 위치와 같음")
	check_eq(Main.roster(packs, "b", "적 %d", false).size(), 1, "상대는 빈 가방 제외")


func test_unit_color_uses_priciest_item() -> void:
	var pack := Backpack.new()
	pack.place(Item.new("apple"), Vector2i(0, 0))
	pack.place(Item.new("axe"), Vector2i(1, 0))
	check_eq(Main.unit_color(pack), Item.new("axe").color())
	check_eq(Main.unit_color(Backpack.new()), Color.GRAY)
