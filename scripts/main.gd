extends Control
## 메인 장면. 3D 전장이 화면 전체에 깔려 있고, 그 위에 UI 가 자리마다 겹쳐 있다.
##   위: 상태 HUD (라운드·체력·골드·연승/연패·최고 기록·시너지)
##   아래: 시트 (유닛 편성 / 적 상세 / 상점). 접을 수 있고, 열리면 전장 카메라가 위쪽으로 물러난다.
##   맨 아래: 행동 버튼. 가운데: 전투 결과·게임 오버 팝업.
##   전장 위쪽은 이번 라운드 상대 (탭하면 상세 전력), 아래쪽은 우리 유닛 (탭하면 그 유닛 편성).
## 게임 규칙은 scripts/core/ (GameState) 에 있고, 여기서는 입력을 넘기고 결과를 보여 주기만 한다.
##
## 스크린샷용 데모: 실행 인자 demo=start | demo=shop | demo=enemy | demo=battle (t=<초>) | demo=result | demo=gameover

const PANEL := Color(0.18, 0.16, 0.14)
const ACCENT := Color(0.95, 0.75, 0.30)
const ENEMY := Color(1.0, 0.55, 0.5)
const SHEET_OPEN_HEIGHT := 568.0
const SHEET_CLOSED_HEIGHT := 64.0
const SHEET_BOTTOM := 112.0

var state: GameState
var records: Dictionary = {}
## 기록을 저장할 파일 (테스트는 다른 경로를 쓴다)
var records_path: String = Records.DEFAULT_PATH
var selected: Item = null
var message: String = ""
## 편성 중인 우리 유닛 번호 (state.units 의 인덱스)
var active_unit: int = 0
## 상세 보기 중인 적 번호 (-1 이면 편성 패널)
var inspect_enemy: int = -1
var battling: bool = false
var last_result: Dictionary = {}
## 전투가 끝난 뒤 보여 줄 GameState.apply_result() 요약
var summary: Dictionary = {}
## 아래 시트가 펼쳐져 있는가
var sheet_open: bool = true
var _laid_out: bool = false

## 화면 제목 (테스트에서 확인한다)
@onready var title: Label = $Title
@onready var header: VBoxContainer = $Header
@onready var battle_view: BattleView3D = $Field/BattleView3D
@onready var sheet: PanelContainer = $Sheet
@onready var sheet_head: HBoxContainer = $Sheet/Box/SheetHead
@onready var scroll: ScrollContainer = $Sheet/Box/Scroll
@onready var content: VBoxContainer = $Sheet/Box/Scroll/Content
@onready var popup: CenterContainer = $Popup
@onready var action_bar: HBoxContainer = $ActionBar


## 순수 로직은 이렇게 작은 함수로 나눠 tests/ 에서 검사한다.
static func clamp_score(score: int) -> int:
	return clampi(score, 0, 999_999)


## 유닛 대표 색: 유닛 종류 색
static func unit_color(pack: Backpack) -> Color:
	return pack.color()


static func stats_line(s: Dictionary) -> String:
	return "체력 %d · 공격 %.1f · 방어 %d\n공속 %.2f · 회복 %.1f · %s" % [
		roundi(s["hp"]), s["atk"], roundi(s["armor"]), s["spd"], s["regen"],
		"원거리 %.1f" % s["range"] if BattleSim.is_ranged(s) else "근접",
	]


## 초당 피해(방어 0 기준)
static func dps(s: Dictionary) -> float:
	return float(s["atk"]) * float(s["spd"])


static func streak_text(streak: int) -> String:
	if streak >= 2:
		return "%d연승" % streak
	if streak <= -2:
		return "%d연패" % -streak
	return ""


## 전장 미리보기 명단 (유닛 자리 기준)
static func roster(packs: Array[Backpack], side: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var bonus := Synergy.bonuses(Synergy.count_tags(packs))
	for pack in packs:
		out.append({
			"pos": BattleSim.slot_position(side, pack.slot),
			"color": unit_color(pack),
			"ranged": BattleSim.is_ranged(BattleSim.unit_stats(pack, bonus)),
			"empty": false,
			"label": pack.display_name(),
		})
	return out


## 가방 칸 크기: 큰 유닛도 시트 안에 들어가게
static func cell_size_for(pack: Backpack) -> float:
	return minf(56.0, minf(224.0 / pack.height, 200.0 / pack.width))


func _ready() -> void:
	battle_view.unit_tapped.connect(_on_field_tapped)
	battle_view.finished.connect(_on_battle_finished)
	var demo := _demo_arg()
	if demo != "":
		_setup_demo(demo)
	else:
		new_run()


func new_run(seed_value: int = 0) -> void:
	state = GameState.new(seed_value)
	records = Records.load_records(records_path)
	selected = null
	message = ""
	active_unit = 0
	inspect_enemy = -1
	battling = false
	summary = {}
	sheet_open = true
	refresh()


# ── 화면 구성 ─────────────────────────────────────────

func refresh() -> void:
	_clear(content)
	_clear(sheet_head)
	_clear(action_bar)
	_clear(popup)
	active_unit = clampi(active_unit, 0, maxi(0, state.units.size() - 1))
	_build_header()
	if battling:
		_layout_sheet(false, false)
		action_bar.add_child(_big_button("건너뛰기", _on_skip))
		return
	if not summary.is_empty():
		_layout_sheet(false, false)
		if summary.get("game_over", false):
			_add_game_over_panel()
		else:
			_add_result_panel()
		return
	_layout_sheet(true, sheet_open)
	_build_sheet_head()
	_refresh_field()
	if inspect_enemy >= 0:
		_add_enemy_detail()
	else:
		_add_unit_editor()
		_add_inventory()
		_add_selection_panel()
		_add_shop()
	if message != "":
		content.add_child(_label(message, 18, Color(1, 0.6, 0.5), true))
	var fight := _big_button("전투 시작 · 라운드 %d" % state.round_no, _on_fight)
	fight.disabled = not state.can_fight()
	action_bar.add_child(fight)


## 시트 보이기/펼치기와 카메라 구도를 맞춘다.
func _layout_sheet(show: bool, expanded: bool) -> void:
	sheet.visible = show
	scroll.visible = expanded
	var h := SHEET_OPEN_HEIGHT if expanded else SHEET_CLOSED_HEIGHT
	sheet.offset_top = -(SHEET_BOTTOM + h)
	# 첫 화면은 바로, 그 뒤엔 부드럽게 카메라를 옮긴다.
	battle_view.set_compact(show and expanded, _laid_out)
	_laid_out = true


func _build_sheet_head() -> void:
	var text := "적 %d 상세 전력" % (inspect_enemy + 1) if inspect_enemy >= 0 else "편성 · 상점"
	sheet_head.add_child(_label(text, 20, ENEMY if inspect_enemy >= 0 else ACCENT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_head.add_child(spacer)
	sheet_head.add_child(_button("▼ 접기" if sheet_open else "▲ 펼치기", _on_toggle_sheet))


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _build_header() -> void:
	_clear(header)
	title.text = ("라운드 %d 전투" if battling else "라운드 %d") % state.round_no
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var hp_col := Color(0.5, 0.9, 0.5) if state.hp > 50 else (ACCENT if state.hp > 25 else Color(1, 0.4, 0.35))
	row.add_child(_label("체력 %d" % state.hp, 22, hp_col))
	row.add_child(_label("골드 %d" % state.gold, 22, ACCENT))
	var st := streak_text(state.streak)
	if st != "":
		row.add_child(_label(st, 20, Color(0.6, 0.85, 1.0) if state.streak > 0 else ENEMY))
	row.add_child(_label("최고 라운드 %d" % records.get("best_round", 0), 17, Color(1, 1, 1, 0.55)))
	header.add_child(row)
	var counts := Synergy.count_tags(state.units)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 4)
	for tag in Synergy.TAG_ORDER:
		var n: int = counts.get(tag, 0)
		var active := Synergy.level(tag, n) > 0
		var chip := _panel(Color(0.35, 0.30, 0.15) if active else PANEL, 6)
		chip.add_child(_label(Synergy.describe(tag, n), 15, ACCENT if active else Color(1, 1, 1, 0.55)))
		chips.add_child(chip)
	header.add_child(chips)


## 전장 미리보기: 우리 유닛 + 이번 라운드 상대
func _refresh_field() -> void:
	battle_view.show_preview(roster(state.units, "a"), roster(state.enemy_team(), "b"))
	if inspect_enemy >= 0:
		battle_view.set_highlight("b", inspect_enemy)
	elif not state.units.is_empty():
		battle_view.set_highlight("a", active_unit)


func _add_unit_editor() -> void:
	if state.units.is_empty():
		content.add_child(_label("전장에 유닛이 없습니다. 아래 상점에서 유닛을 사세요.", 18, Color(1, 1, 1, 0.75), true))
		return
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	for i in state.units.size():
		var u := state.units[i]
		var b := _button("%s %dx%d" % [u.display_name(), u.width, u.height], _on_unit_tab.bind(i))
		b.custom_minimum_size = Vector2(150, 44)
		if i == active_unit:
			b.add_theme_color_override("font_color", ACCENT)
			b.add_theme_color_override("font_hover_color", ACCENT)
		tabs.add_child(b)
	content.add_child(tabs)
	var pack := state.units[active_unit]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var view := BackpackView.new()
	view.setup(pack, active_unit, cell_size_for(pack))
	view.selected = selected
	view.cell_pressed.connect(_on_cell_pressed)
	row.add_child(view)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_label("%s (%dx%d 가방)" % [pack.display_name(), pack.width, pack.height], 20, ACCENT, true))
	var s := BattleSim.unit_stats(pack, Synergy.bonuses(Synergy.count_tags(state.units)))
	info.add_child(_label(stats_line(s), 16, Color(1, 1, 1, 0.85), true))
	info.add_child(_label("초당 피해 %.1f · 가치 %d원" % [dps(s), pack.total_value()], 15, Color(1, 1, 1, 0.6), true))
	info.add_child(_button("유닛 판매 +%d원" % pack.sell_price(), _on_sell_unit))
	row.add_child(info)
	content.add_child(row)


func _add_inventory() -> void:
	content.add_child(_label("보유 아이템 (고른 뒤 가방 칸을 누르면 넣기)", 16, Color(1, 1, 1, 0.6)))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	if state.inventory.is_empty():
		flow.add_child(_label("(없음)", 16, Color(1, 1, 1, 0.4)))
	for item in state.inventory:
		var b := _color_button(item.color(), "%s %dx%d" % [item.display_name(), item.size().x, item.size().y], item == selected)
		b.pressed.connect(_on_inventory_pressed.bind(item))
		flow.add_child(b)
	content.add_child(flow)


func _add_selection_panel() -> void:
	if selected == null:
		return
	var panel := _panel(PANEL)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var tag_name: String = Synergy.TRAITS[selected.tag()]["name"]
	var where := state.unit_of(selected)
	var place := "보유함" if where < 0 else "%s 가방" % state.units[where].display_name()
	box.add_child(_label("%s [%s] · %d원 · %s" % [selected.display_name(), tag_name, selected.cost(), place], 18, ACCENT, true))
	box.add_child(_label(selected.describe(), 16, Color.WHITE, true))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	if selected.is_rotatable():
		actions.add_child(_button("회전", _on_rotate))
	if where >= 0:
		actions.add_child(_button("빼기", _on_unequip))
	actions.add_child(_button("판매 +%d원" % selected.sell_price(), _on_sell_item))
	actions.add_child(_button("닫기", _on_deselect))
	box.add_child(actions)
	content.add_child(panel)


func _add_shop() -> void:
	var head := HBoxContainer.new()
	head.add_child(_label("상점", 20, ACCENT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var reroll := _button("새로고침 (%d원)" % GameState.REROLL_COST, _on_reroll)
	reroll.disabled = state.gold < GameState.REROLL_COST
	head.add_child(reroll)
	content.add_child(head)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	for i in state.shop.size():
		var offer := state.shop[i]
		if offer.is_empty():
			var sold := _color_button(Color(0.2, 0.2, 0.2), "판매됨", false)
			sold.disabled = true
			flow.add_child(sold)
			continue
		var b: Button
		if offer["kind"] == "unit":
			var d := UnitDB.get_def(offer["id"])
			var sz: Vector2i = d["size"]
			b = _color_button(d["color"], "유닛 %s %dx%d\n%d원" % [d["name"], sz.x, sz.y, d["cost"]], false)
			b.tooltip_text = Pricing.describe_stats(d["stats"], float(d["stats"].get("range", 0.0)))
		else:
			var item := Item.new(offer["id"])
			b = _color_button(item.color(), "%s %dx%d\n%d원" % [item.display_name(), item.size().x, item.size().y, item.cost()], false)
			b.tooltip_text = item.describe()
		b.disabled = state.buy_block_reason(i) != ""
		b.pressed.connect(_on_buy.bind(i))
		flow.add_child(b)
	content.add_child(flow)


## 적 상세 전력: 유닛 종류, 능력치, 가방, 아이템 목록, 팀 시너지
func _add_enemy_detail() -> void:
	var enemies := state.enemy_team()
	if inspect_enemy >= enemies.size():
		inspect_enemy = -1
		_add_unit_editor()
		return
	var pack := enemies[inspect_enemy]
	var counts := Synergy.count_tags(enemies)
	var s := BattleSim.unit_stats(pack, Synergy.bonuses(counts))
	var head := HBoxContainer.new()
	head.add_child(_label("%s (%dx%d) · 라운드 %d 상대" % [pack.display_name(), pack.width, pack.height, state.round_no], 18, Color(1, 1, 1, 0.75)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(_button("편성으로", _on_close_enemy))
	content.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var view := BackpackView.new()
	view.setup(pack, inspect_enemy, cell_size_for(pack), false)
	row.add_child(view)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_label(stats_line(s), 17, Color.WHITE, true))
	info.add_child(_label("초당 피해 %.1f · 가치 %d원" % [dps(s), pack.total_value()], 16, Color(1, 1, 1, 0.65), true))
	var syn: PackedStringArray = []
	for tag in Synergy.TAG_ORDER:
		if Synergy.level(tag, counts[tag]) > 0:
			syn.append(Synergy.describe(tag, counts[tag]))
	info.add_child(_label("팀 시너지: " + (", ".join(syn) if not syn.is_empty() else "없음"), 15, ACCENT, true))
	row.add_child(info)
	content.add_child(row)
	for item in pack.items():
		var tag_name: String = Synergy.TRAITS[item.tag()]["name"]
		content.add_child(_label("· %s [%s] — %s" % [item.display_name(), tag_name, item.describe()], 16, Color(1, 1, 1, 0.85), true))
	content.add_child(_label("상대 팀 전체: 유닛 %d · 총가치 %d원 · 지면 최대 체력 -%d" % [
		enemies.size(), EnemyGen.total_value(enemies), GameState.hp_loss_for(enemies.size())], 15, Color(1, 1, 1, 0.55), true))


func _add_result_panel() -> void:
	var won: bool = summary["won"]
	var panel := _panel(Color(0.20, 0.30, 0.18, 0.95) if won else Color(0.35, 0.16, 0.14, 0.95), 18)
	panel.custom_minimum_size = Vector2(540, 0)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	box.add_child(_label("라운드 %d %s" % [summary["round_played"], "승리!" if won else "패배…"], 40, ACCENT if won else ENEMY))
	if not won:
		box.add_child(_label("체력 -%d (살아남은 적 %d) → %d" % [summary["hp_loss"], summary["survivors"], state.hp], 22, Color.WHITE, true))
	var income_text := "골드 +%d" % summary["income"]
	if summary["bonus"] > 0:
		income_text += " (기본 %d + %s 보너스 %d)" % [GameState.BASE_INCOME, streak_text(summary["streak"]), summary["bonus"]]
	box.add_child(_label(income_text, 22, ACCENT, true))
	popup.add_child(panel)
	action_bar.add_child(_big_button("다음 라운드 · %d" % state.round_no, _on_continue))


func _add_game_over_panel() -> void:
	var panel := _panel(Color(0.12, 0.10, 0.10, 0.95), 20)
	panel.custom_minimum_size = Vector2(560, 0)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	box.add_child(_label("게임 오버", 48, ENEMY))
	box.add_child(_label("라운드 %d 까지 도달" % summary["round_played"], 28, Color.WHITE))
	var best: int = records.get("best_round", 0)
	var record_text := "최고 기록 라운드 %d · %d번째 판" % [best, records.get("runs", 0)]
	if summary["round_played"] >= best:
		record_text = "새 최고 기록! · %d번째 판" % records.get("runs", 0)
	box.add_child(_label(record_text, 22, ACCENT))
	popup.add_child(panel)
	action_bar.add_child(_big_button("새로 시작", _on_new_run))


# ── 입력 처리 ─────────────────────────────────────────

func _on_toggle_sheet() -> void:
	sheet_open = not sheet_open
	refresh()


func _on_field_tapped(side: String, index: int) -> void:
	message = ""
	sheet_open = true
	if side == "b":
		inspect_enemy = -1 if inspect_enemy == index else index
	else:
		inspect_enemy = -1
		active_unit = index
	refresh()


func _on_unit_tab(index: int) -> void:
	active_unit = index
	inspect_enemy = -1
	refresh()


func _on_close_enemy() -> void:
	inspect_enemy = -1
	refresh()


func _on_inventory_pressed(item: Item) -> void:
	selected = null if selected == item else item
	message = ""
	refresh()


func _on_cell_pressed(unit_index: int, cell: Vector2i) -> void:
	var pack := state.units[unit_index]
	var at := pack.item_at(cell)
	message = ""
	if selected == null:
		selected = at
	elif at == selected:
		selected = null
	elif state.equip(selected, unit_index, cell):
		selected = null
	elif at != null:
		selected = at
	else:
		message = "그 자리에는 들어가지 않습니다. (회전해 보세요)"
	refresh()


func _on_rotate() -> void:
	if selected != null and not state.rotate(selected):
		message = "가방 안에서 돌릴 공간이 없습니다."
	refresh()


func _on_unequip() -> void:
	if selected != null:
		state.unequip(selected)
	refresh()


func _on_sell_item() -> void:
	if selected != null and state.sell_item(selected):
		selected = null
	refresh()


func _on_sell_unit() -> void:
	if active_unit < state.units.size():
		var pack := state.units[active_unit]
		if state.sell_unit(pack):
			message = "%s 판매 (+%d원). 가방 속 아이템은 보유함으로 돌아왔습니다." % [pack.display_name(), pack.sell_price()]
			active_unit = 0
	refresh()


func _on_deselect() -> void:
	selected = null
	refresh()


func _on_buy(index: int) -> void:
	var offer := state.shop[index]
	var reason := state.buy_block_reason(index)
	if reason != "":
		message = reason
	elif state.buy(index):
		message = ""
		if offer["kind"] == "unit":
			active_unit = state.units.size() - 1
			inspect_enemy = -1
	refresh()


func _on_reroll() -> void:
	state.reroll()
	refresh()


func _on_fight() -> void:
	_start_battle(0.0)


func _start_battle(start_time: float) -> void:
	if not state.can_fight():
		return
	selected = null
	message = ""
	inspect_enemy = -1
	var colors_a: Array[Color] = []
	for u in state.units:
		colors_a.append(unit_color(u))
	var colors_b: Array[Color] = []
	for u in state.enemy_team():
		colors_b.append(unit_color(u))
	last_result = state.fight()
	battling = true
	refresh()
	battle_view.play(last_result, colors_a, colors_b, start_time)


func _on_skip() -> void:
	battle_view.skip()


func _on_battle_finished(_winner: String) -> void:
	if not battling:
		return
	battling = false
	summary = state.apply_result(last_result)
	if summary["game_over"]:
		records = Records.submit(summary["round_played"], records_path)
	refresh()


func _on_continue() -> void:
	summary = {}
	refresh()


func _on_new_run() -> void:
	new_run()


# ── 데모 (스크린샷) ───────────────────────────────────

func _demo_arg() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("demo="):
			return a.substr(5)
	return ""


func _setup_demo(kind: String) -> void:
	new_run(7)
	if kind == "start":
		return
	# 4라운드쯤: 견습병(장검) + 병사(투구·사과) + 궁수(단검)
	state.round_no = 4
	state.gold = 6
	state.hp = 76
	state.streak = 2
	state.units.append(Backpack.new("soldier"))
	state.units[1].slot = 1
	state.units.append(Backpack.new("archer"))
	state.units[2].slot = 2
	var plan := [[0, "sword"], [1, "helmet"], [1, "apple"], [2, "dagger"]]
	for p: Array in plan:
		var item := Item.new(p[1])
		state.inventory.append(item)
		state.equip(item, p[0], state.units[p[0]].find_spot(item))
	state.inventory.append_array([Item.new("club"), Item.new("herb_pouch")])
	state.refill_shop()
	active_unit = 1
	if kind == "shop":
		selected = state.inventory[0]
	elif kind == "enemy":
		inspect_enemy = 0
	elif kind == "battle":
		var at := 3.0
		for a in OS.get_cmdline_user_args():
			if a.begins_with("t="):
				at = a.substr(2).to_float()
		_start_battle(at)
		return
	elif kind == "result":
		last_result = state.fight()
		summary = state.apply_result(last_result)
	elif kind == "gameover":
		state.hp = 1
		summary = {"won": false, "hp_loss": 16, "survivors": 2, "streak": -3, "round_played": 9, "income": 0, "bonus": 0, "game_over": true}
		records = {"best_round": 12, "runs": 5, "last_round": 9}
	refresh()


# ── 위젯 도우미 ───────────────────────────────────────

func _label(text: String, font_size: int = 20, color: Color = Color.WHITE, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _panel(color: Color, margin: int = 10) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(margin)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(on_press)
	return b


func _big_button(text: String, on_press: Callable, primary: bool = true) -> Button:
	var b := _button(text, on_press)
	b.custom_minimum_size = Vector2(0, 84)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 28)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.75, 0.45, 0.15) if primary else Color(0.30, 0.27, 0.24)
	sb.set_corner_radius_all(10)
	b.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = sb.bg_color.lightened(0.1)
	b.add_theme_stylebox_override("hover", hover)
	var dis := sb.duplicate() as StyleBoxFlat
	dis.bg_color = Color(0.25, 0.24, 0.22)
	b.add_theme_stylebox_override("disabled", dis)
	return b


## 색 칩 버튼 (아이템·상점 진열)
func _color_button(color: Color, text: String, is_selected: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(130, 60)
	b.add_theme_font_size_override("font_size", 15)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color.darkened(0.25)
	sb.set_corner_radius_all(8)
	if is_selected:
		sb.set_border_width_all(4)
		sb.border_color = Color.WHITE
	b.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = color
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	var dis := sb.duplicate() as StyleBoxFlat
	dis.bg_color = color.darkened(0.7)
	b.add_theme_stylebox_override("disabled", dis)
	return b
