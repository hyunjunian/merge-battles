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
	check(main.has_node("Sheet/Box/Scroll/Content"), "Content 노드 없음")
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
	var club := Item.new("club")
	state.inventory.append(club)
	main.refresh()
	main._on_field_tapped("a", 0)
	main._on_inventory_pressed(club)
	check(main.selected == club, "보유 아이템 선택")
	main._on_cell_pressed(0, Vector2i(0, 0))
	check_eq(state.unit_of(club), 0, "누른 가방에 들어감")
	check(main.selected == null, "넣으면 선택 해제")
	main._on_cell_pressed(0, Vector2i(0, 0))
	check(main.selected == club, "가방 속 아이템을 누르면 선택")
	main._on_unequip()
	check(state.inventory.has(club), "빼기")
	free_later(main)


func test_buy_unit_appears_on_field() -> void:
	var main := _spawn()
	var state: GameState = main.state
	state.gold = 20
	state.shop[0] = {"kind": "unit", "id": "soldier"}
	main._on_buy(0)
	check_eq(state.units.size(), 2, "유닛 구매")
	check_eq(main.battle_view.unit_count("a"), 2, "전장에 바로 섬")
	check_eq(main.inspect_unit, -1, "구매 후에도 상점 유지")
	main._on_field_tapped("a", 1)
	check_eq(main.inspect_unit, 1, "전장의 유닛을 누르면 그 유닛 정보")
	main._on_sell_unit()
	check_eq(state.units.size(), 1, "판매하면 빠짐")
	check_eq(main.battle_view.unit_count("a"), 1)
	free_later(main)


func test_fight_flow_and_next_round() -> void:
	var main := _spawn()
	var state: GameState = main.state
	main._on_fight()
	check(main.battling, "전투 중")
	check_eq(main.battle_view.speed_mult, 1.0, "기본은 보통 속도")
	main._on_toggle_fast()
	check_eq(main.battle_view.speed_mult, 2.0, "2배속")
	check(main.battling, "배속을 바꿔도 전투는 계속")
	check(main.battle_view.mode == BattleView3D.Mode.PLAYING, "전장에서 전투 재생")
	check(not main.sheet.visible, "전투 중엔 시트 숨김 (전장 전체 화면)")
	main.battle_view.skip()
	check(not main.battling, "전투 끝")
	check_eq(state.round_no, 2, "승패와 상관없이 다음 라운드")
	check(main.popup.get_child_count() > 0, "결과 팝업")
	main._on_continue()
	check(main.battle_view.mode == BattleView3D.Mode.PREVIEW, "다음 상대 미리보기로 돌아옴")
	main._on_fight()
	check_eq(main.battle_view.speed_mult, 2.0, "다음 전투도 2배속 유지")
	free_later(main)


func test_game_over_saves_record_and_restarts() -> void:
	var main := _spawn()
	var path := "user://test_main_records.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	main.records_path = path
	var state: GameState = main.state
	state.hp = 1
	state.units[0].placements.clear()
	state.round_no = 30  # 아주 강한 상대
	main._on_fight()
	main.battle_view.skip()
	check(state.game_over, "체력 0 → 게임 오버")
	check_eq(main.records.get("best_round", 0), 30, "도달 라운드 기록")
	check_eq(Records.load_records(path)["runs"], 1, "파일에 저장")
	main._on_new_run()
	check(main.state != state, "새 판")
	check_eq(main.state.hp, GameState.START_HP)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	free_later(main)


func test_field_shows_units_and_enemy() -> void:
	var main := _spawn()
	var state: GameState = main.state
	check_eq(main.battle_view.unit_count("a"), state.units.size(), "우리 유닛")
	check_eq(main.battle_view.unit_count("b"), state.enemy_team().size(), "이번 상대")
	free_later(main)


func test_tap_enemy_shows_detail_and_tap_own_unit_edits() -> void:
	var main := _spawn()
	main._on_field_tapped("b", 0)
	check_eq(main.inspect_enemy, 0, "적 상세 보기")
	check_eq(main.battle_view.highlight.get("side", ""), "b", "적 강조")
	main._on_field_tapped("a", 0)
	check_eq(main.inspect_enemy, -1, "우리 유닛을 누르면 정찰 닫힘")
	check_eq(main.inspect_unit, 0, "우리 유닛 정보")
	main._on_field_tapped("a", 0)
	check_eq(main.inspect_unit, -1, "같은 유닛을 다시 누르면 상점")
	main._on_field_tapped("b", 0)
	main.battle_view.background_tapped.emit()
	check(main.inspect_unit == -1 and main.inspect_enemy == -1, "패널 밖(빈 바닥)을 누르면 상점")
	main._on_field_tapped("a", 0)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	main._on_hud_input(up)
	check_eq(main.inspect_unit, -1, "위 HUD 를 눌러도 상점")
	var has_back := false
	main._on_field_tapped("a", 0)
	for c in main.sheet_head.get_children():
		if c is Button and (c as Button).text.contains("상점"):
			has_back = true
	check(not has_back, "상점 돌아가기 버튼 없음")
	free_later(main)


func test_shop_sheet_fits_content() -> void:
	var main := _spawn()
	var h: float = -main.sheet.offset_top - main.SHEET_BOTTOM
	check(h < main.SHEET_OPEN_HEIGHT, "상점 시트는 최대 높이보다 낮음: %d" % h)
	check(absf(h - main.sheet_fit_height()) < 1.0, "내용 높이에 딱 맞음")
	check(main.battle_view._framing_target < 1.0, "남는 공간만큼 전장을 크게")
	main._on_field_tapped("b", 0)
	check_eq(-main.sheet.offset_top - main.SHEET_BOTTOM, main.SHEET_OPEN_HEIGHT, "정찰은 최대 높이")
	check_eq(BattleView3D.framing_for_bottom(1160.0), 0.0)
	check_eq(BattleView3D.framing_for_bottom(590.0), 1.0)
	free_later(main)


func test_fight_button_sits_in_sheet_head() -> void:
	var main := _spawn()
	var found := false
	for c in main.sheet_head.get_children():
		if c is Button and (c as Button).text == "전투 시작":
			found = true
	check(found, "전투 시작 버튼이 시트 머리에 있음")
	check_eq(main.action_bar.get_child_count(), 0, "아래 버튼 줄은 비어 있음")
	free_later(main)


func test_default_sheet_is_shop() -> void:
	var main := _spawn()
	check(main.inspect_unit == -1 and main.inspect_enemy == -1, "처음엔 상점")
	var row_cards := 0
	for c in main.content.get_children():
		if c is HBoxContainer and c.get_child_count() > 0 and c.get_child(0) is Button:
			row_cards = c.get_child_count()
	check_eq(row_cards, GameState.UNIT_OFFERS + GameState.ITEM_OFFERS, "상점 카드 5개가 한 줄")
	free_later(main)


func test_drag_moves_unit_on_field() -> void:
	var main := _spawn()
	var state: GameState = main.state
	main._on_unit_moved(0, Vector2(-3.0, 6.0))
	check_eq(state.units[0].start_pos("a"), Vector2(-3.0, 6.0), "옮긴 자리")
	check_eq(BattleSim.team_stats(state.units, "a")[0]["pos"], Vector2(-3.0, 6.0), "전투도 그 자리에서 시작")
	main._on_unit_moved(0, Vector2(0.0, -5.0))
	check(state.units[0].start_pos("a").y >= BattleSim.OWN_MIN_Z, "상대 진영으로는 못 감")
	free_later(main)


func test_ui_helpers() -> void:
	check_eq(Main.streak_text(3), "3연승")
	check_eq(Main.streak_text(-2), "2연패")
	check_eq(Main.streak_text(1), "")
	var big := Backpack.new("warlord")
	check(Main.cell_size_for(big) * big.height <= 232.0 + 0.01, "큰 가방도 시트에 들어감")
	var packs: Array[Backpack] = [Backpack.new("archer")]
	packs[0].slot = 4
	var r := Main.roster(packs, "a")
	check(r[0]["ranged"], "원거리 표시")
	check_eq(r[0]["pos"], BattleSim.slot_position("a", 4), "자리 위치")
