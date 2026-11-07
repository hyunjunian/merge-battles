extends Control
## 메인 장면. 3D 전장이 화면 전체에 깔려 있고, 그 위에 UI 가 자리마다 겹쳐 있다.
##   위: HUD (라운드 배지·체력 바·골드·연승/연패·최고 기록·시너지)
##   아래: 시트. 기본은 상점. 전장의 우리 유닛을 누르면 그 유닛 정보(가방 편성), 적을 누르면 정찰.
##         접을 수 있고, 열리면 전장 카메라가 위쪽으로 물러난다.
##   맨 아래: 행동 버튼. 가운데: 전투 결과·게임 오버 배너.
##   전장 위쪽은 이번 라운드 상대, 아래쪽은 우리 유닛. 우리 유닛은 끌어서 우리 진영 어디로든 옮길 수 있다.
## 게임 규칙은 scripts/core/ (GameState) 에 있고, 여기서는 입력을 넘기고 결과를 보여 주기만 한다.
## 스타일(색·버튼·글꼴)은 scripts/ui/ui_style.gd, 아이콘은 game_icon.gd.
##
## 스크린샷용 데모: 실행 인자 demo=start | demo=shop | demo=units | demo=enemy | demo=battle (t=<초>) | demo=result | demo=gameover

const S := preload("res://scripts/ui/ui_style.gd")
const SHEET_OPEN_HEIGHT := 660.0
## 시트 아래 여백 (전투 시작 버튼이 시트 안으로 들어가 아래 버튼 줄이 없다)
const SHEET_BOTTOM := 10.0
const S_VIEW_HEIGHT := 1280.0

var state: GameState
var records: Dictionary = {}
## 기록을 저장할 파일 (테스트는 다른 경로를 쓴다)
var records_path: String = Records.DEFAULT_PATH
var selected: Item = null
var message: String = ""
## 시트에 정보를 띄운 우리 유닛 번호 (state.units 인덱스, -1 이면 없음)
var inspect_unit: int = -1
## 정찰 중인 적 번호 (-1 이면 없음). 둘 다 -1 이면 시트는 상점.
var inspect_enemy: int = -1
var battling: bool = false
## 전투 2배속 (켜 두면 다음 전투에도 유지)
var fast: bool = false
var last_result: Dictionary = {}
## 전투가 끝난 뒤 보여 줄 GameState.apply_result() 요약
var summary: Dictionary = {}
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
@onready var dim: ColorRect = $Dim
@onready var action_bar: HBoxContainer = $ActionBar


## 순수 로직은 이렇게 작은 함수로 나눠 tests/ 에서 검사한다.
static func clamp_score(score: int) -> int:
	return clampi(score, 0, 999_999)


## 유닛 대표 색: 유닛 종류 색
static func unit_color(pack: Backpack) -> Color:
	return pack.color()


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
			"pos": pack.start_pos(side),
			"color": unit_color(pack),
			"ranged": BattleSim.is_ranged(BattleSim.unit_stats(pack, bonus)),
			"empty": false,
			"label": pack.display_name(),
		})
	return out


## 가방 칸 크기: 큰 유닛도 시트 안에 들어가게
static func cell_size_for(pack: Backpack) -> float:
	return minf(60.0, minf(232.0 / pack.height, 210.0 / pack.width))


## 능력치 표시용 (아이콘, 키, 형식)
const STAT_ICONS := [
	["heart", "hp", "%d"], ["sword", "atk", "%.1f"], ["shield", "armor", "%d"],
	["bolt", "spd", "%.2f"], ["plus", "regen", "%.1f"],
]


func _ready() -> void:
	theme = S.make_theme()
	battle_view.unit_tapped.connect(_on_field_tapped)
	battle_view.unit_moved.connect(_on_unit_moved)
	battle_view.background_tapped.connect(_on_back_to_shop)
	$Hud.gui_input.connect(_on_hud_input)
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
	inspect_unit = -1
	inspect_enemy = -1
	battling = false
	summary = {}
	refresh()


# ── 화면 구성 ─────────────────────────────────────────

func refresh() -> void:
	_clear(content)
	_clear(sheet_head)
	_clear(action_bar)
	_clear(popup)
	dim.visible = not summary.is_empty() and not battling
	if inspect_unit >= state.units.size():
		inspect_unit = -1
	_build_header()
	if battling:
		_layout_sheet(false)
		action_bar.add_child(_action_button("2배속 켜짐" if fast else "2배속", _on_toggle_fast, "PrimaryButton" if fast else "Button", "bolt"))
		return
	if not summary.is_empty():
		_layout_sheet(false)
		if summary.get("game_over", false):
			_add_game_over_panel()
		else:
			_add_result_panel()
		return
	_build_sheet_head()
	_refresh_field()
	if inspect_enemy >= 0:
		_add_enemy_detail()
	elif inspect_unit >= 0:
		_add_unit_editor()
		_add_inventory()
		_add_selection_panel()
	else:
		_add_shop()
	if message != "":
		var m := _label(message, 17, S.RED, true)
		content.add_child(m)
	# 상점은 내용 높이에 딱 맞추고(아래 여백 없음), 유닛 정보·정찰은 최대 높이에 스크롤
	_layout_sheet(true, inspect_unit < 0 and inspect_enemy < 0)


## 시트 보이기와 카메라 구도를 맞춘다. fit 이면 시트 높이를 내용에 맞춘다.
func _layout_sheet(show: bool, fit: bool = false) -> void:
	sheet.visible = show
	var h := SHEET_OPEN_HEIGHT
	if show and fit:
		h = minf(SHEET_OPEN_HEIGHT, sheet_fit_height())
	sheet.offset_bottom = -SHEET_BOTTOM
	sheet.offset_top = -(SHEET_BOTTOM + h)
	var bottom := (S_VIEW_HEIGHT - SHEET_BOTTOM - h) if show else BattleView3D.FULL_BOTTOM_Y
	# 첫 화면은 바로, 그 뒤엔 부드럽게 카메라를 옮긴다.
	battle_view.set_framing(BattleView3D.framing_for_bottom(bottom), _laid_out)
	_laid_out = true


## 시트 머리 + 내용 + 여백을 합친 높이
func sheet_fit_height() -> float:
	var sb := sheet.get_theme_stylebox("panel")
	var box_sep := float((sheet.get_child(0) as VBoxContainer).get_theme_constant("separation"))
	var margins := sb.get_minimum_size().y if sb != null else 0.0
	return sheet_head.get_combined_minimum_size().y + box_sep + content.get_combined_minimum_size().y + margins


func _build_sheet_head() -> void:
	sheet_head.add_theme_constant_override("separation", 8)
	if inspect_enemy >= 0 or inspect_unit >= 0:
		# 상점으로는 패널 밖(전장 빈 곳·위 HUD)을 눌러 돌아간다
		if inspect_enemy >= 0:
			sheet_head.add_child(_label("적 %d 정찰" % (inspect_enemy + 1), 22, S.RED, false, true))
		else:
			var u := state.units[inspect_unit]
			sheet_head.add_child(_label(u.display_name(), 22, u.color().lightened(0.35), false, true))
	else:
		sheet_head.add_child(_label("상점", 24, S.GOLD, false, true))
		sheet_head.add_child(_badge("coin", str(state.gold), S.GOLD))
		var reroll := _button("새로고침 %d원" % GameState.REROLL_COST, _on_reroll)
		reroll.disabled = state.gold < GameState.REROLL_COST
		sheet_head.add_child(reroll)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_head.add_child(spacer)
	# 시트 오른쪽 위: 체력 + 전투 시작
	sheet_head.add_child(_hp_widget())
	var fight := _button("전투 시작", _on_fight)
	fight.theme_type_variation = "GoButton"
	fight.custom_minimum_size = Vector2(176, 56)
	fight.add_theme_font_size_override("font_size", 22)
	var ic := GameIcon.make("sword", 24, Color.WHITE)
	ic.position = Vector2(10, 13)
	fight.add_child(ic)
	fight.disabled = not state.can_fight()
	sheet_head.add_child(fight)


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _build_header() -> void:
	_clear(header)
	title.text = ("라운드 %d · 전투" if battling else "라운드 %d") % state.round_no
	title.add_theme_font_override("font", S.bold())
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var st := streak_text(state.streak)
	if st != "":
		row.add_child(_badge("flame" if state.streak > 0 else "skull", st, Color(1.0, 0.6, 0.2) if state.streak > 0 else S.MUTED))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_badge("flag", "최고 %d" % records.get("best_round", 0), S.MUTED, 16))
	header.add_child(row)
	var counts := Synergy.count_tags(state.units)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 4)
	for tag in Synergy.TAG_ORDER:
		var n: int = counts.get(tag, 0)
		var lv := Synergy.level(tag, n)
		var on := lv > 0
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", S.box(Color(0.42, 0.30, 0.06, 0.9) if on else Color(0, 0, 0, 0.3), S.GOLD if on else Color(1, 1, 1, 0.12), 2, 10, -1, 4.0))
		chip.add_child(_label(Synergy.describe(tag, n), 14, S.GOLD if on else S.MUTED, false, on))
		chips.add_child(chip)
	header.add_child(chips)


## 전투 시작 버튼 옆 체력: 하트 + 굵은 숫자 + 작은 막대 (남은 비율에 따라 초록·노랑·빨강)
func _hp_widget() -> Control:
	var ratio := clampf(float(state.hp) / GameState.START_HP, 0.0, 1.0)
	var col := S.GREEN if ratio > 0.5 else (S.GOLD if ratio > 0.25 else S.RED)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(GameIcon.make("heart", 34))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(_label("%d" % state.hp, 22, col, false, true))
	var bar := PanelContainer.new()
	bar.custom_minimum_size = Vector2(60, 10)
	bar.add_theme_stylebox_override("panel", S.box(Color(0, 0, 0, 0.6), Color(1, 1, 1, 0.15), 1, 4, -1, 1.0))
	var fill := ColorRect.new()
	fill.color = col
	fill.custom_minimum_size = Vector2(maxf(2.0, 58.0 * ratio), 8)
	fill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bar.add_child(fill)
	v.add_child(bar)
	box.add_child(v)
	box.tooltip_text = "체력 %d / %d" % [state.hp, GameState.START_HP]
	return box


## 아이콘 + 굵은 숫자 배지
func _badge(icon: String, text: String, color: Color, font_size: int = 22) -> Control:
	var p := PanelContainer.new()
	var sb := S.box(Color(0, 0, 0, 0.4), Color(color, 0.5), 2, 16, -1, 4.0)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 12.0
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.add_child(GameIcon.make(icon, font_size + 4))
	h.add_child(_label(text, font_size, color, false, true))
	p.add_child(h)
	return p


## 전장 미리보기: 우리 유닛 + 이번 라운드 상대
func _refresh_field() -> void:
	battle_view.show_preview(roster(state.units, "a"), roster(state.enemy_team(), "b"))
	if inspect_enemy >= 0:
		battle_view.set_highlight("b", inspect_enemy)
	elif inspect_unit >= 0:
		battle_view.set_highlight("a", inspect_unit)
	else:
		battle_view.set_highlight("a", -1)


## 능력치 칩 줄
func _stat_row(s: Dictionary, font_size: int = 16) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 4)
	for e: Array in STAT_ICONS:
		var v: float = s.get(e[1], 0.0)
		if v == 0.0 and e[1] in ["armor", "regen"]:
			continue
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 3)
		h.add_child(GameIcon.make(e[0], font_size + 4))
		h.add_child(_label(e[2] % v, font_size, S.TEXT, false, true))
		flow.add_child(h)
	if BattleSim.is_ranged(s):
		var h := HBoxContainer.new()
		h.add_child(GameIcon.make("bow", font_size + 4))
		h.add_child(_label("%.1f" % s["range"], font_size, S.TEXT, false, true))
		flow.add_child(h)
	return flow


func _add_unit_editor() -> void:
	var pack := state.units[inspect_unit]
	var panel := _panel(S.NAVY_DEEP, S.EDGE)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var view := BackpackView.new()
	view.setup(pack, inspect_unit, cell_size_for(pack))
	view.selected = selected
	view.cell_pressed.connect(_on_cell_pressed)
	row.add_child(view)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	info.add_child(_label(pack.display_name(), 24, pack.color().lightened(0.35), false, true))
	info.add_child(_label("%dx%d 가방 · 가치 %d원" % [pack.width, pack.height, pack.total_value()], 15, S.MUTED))
	var s := BattleSim.unit_stats(pack, Synergy.bonuses(Synergy.count_tags(state.units)))
	info.add_child(_stat_row(s))
	info.add_child(_label("초당 피해 %.1f" % dps(s), 15, S.MUTED))
	_add_skill_lines(info, pack)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(spacer)
	var sell := _button("판매 +%d원" % pack.sell_price(), _on_sell_unit)
	sell.theme_type_variation = "DangerButton"
	info.add_child(sell)
	row.add_child(info)
	content.add_child(panel)


func _add_inventory() -> void:
	content.add_child(_section("보유 아이템", "아이템을 고른 뒤 가방 칸을 누르면 들어갑니다"))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	if state.inventory.is_empty():
		flow.add_child(_label("비어 있음 — 상점에서 아이템을 사세요", 16, S.MUTED))
	for item in state.inventory:
		var card := _card(S.rarity_color(item.cost()), item == selected, Vector2(104, 100), _on_inventory_pressed.bind(item))
		var v := _card_box(card)
		v.add_child(_center(ShapeIcon.for_item(item, 13.0)))
		v.add_child(_label(item.display_name(), 14, S.TEXT, false, true, true))
		if item.has_skill():
			v.add_child(_skill_tag(item, 16))
		flow.add_child(card)
	content.add_child(flow)


func _add_selection_panel() -> void:
	if selected == null:
		return
	var panel := _panel(Color(0.25, 0.19, 0.06, 0.95), S.GOLD)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var tag_name: String = Synergy.TRAITS[selected.tag()]["name"]
	var where := state.unit_of(selected)
	var place := "보유함" if where < 0 else "%s 가방" % state.units[where].display_name()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(ShapeIcon.for_item(selected, 14.0))
	head.add_child(_label(selected.display_name(), 22, S.GOLD, false, true))
	head.add_child(_label("[%s] · %s" % [tag_name, place], 15, S.MUTED))
	box.add_child(head)
	box.add_child(_label(selected.describe(), 16, S.TEXT, true))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	if selected.is_rotatable():
		actions.add_child(_button("회전", _on_rotate))
	if where >= 0:
		actions.add_child(_button("빼기", _on_unequip))
	var sell := _button("판매 +%d원" % selected.sell_price(), _on_sell_item)
	sell.theme_type_variation = "DangerButton"
	actions.add_child(sell)
	actions.add_child(_button("닫기", _on_deselect))
	box.add_child(actions)
	content.add_child(panel)


func _add_shop() -> void:
	# 진열 5개(유닛 2 + 아이템 3)를 한 줄에 같은 폭으로
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for i in state.shop.size():
		var card := _offer_card(i, state.shop[i])
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
	content.add_child(row)


## 상점 카드: 등급 띠, 모양, 이름, 핵심 능력치, 가격표
func _offer_card(index: int, offer: Dictionary) -> Control:
	var w := Vector2(100, 228)
	if offer.is_empty():
		var sold := _card(Color(0.3, 0.3, 0.3), false, w, Callable())
		sold.disabled = true
		var v := _card_box(sold)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(_label("판매 완료", 18, S.MUTED, false, false, true))
		return sold
	var cost := GameState.offer_cost(offer)
	var col := S.rarity_color(cost)
	var card := _card(col, false, w, _on_buy.bind(index))
	card.disabled = state.buy_block_reason(index) != ""
	var v := _card_box(card)
	var tag := _label(("유닛 · " if offer["kind"] == "unit" else "") + S.rarity_name(cost), 15, col.lightened(0.3), false, true, true)
	v.add_child(tag)
	var stats: Dictionary
	if offer["kind"] == "unit":
		var d := UnitDB.get_def(offer["id"])
		v.add_child(_center(ShapeIcon.for_unit(d["size"], d["color"], minf(18.0, 44.0 / float(d["size"].y)))))
		v.add_child(_label(d["name"], 20, S.TEXT, false, true, true))
		stats = d["stats"]
		card.tooltip_text = Pricing.describe_stats(stats, float(stats.get("range", 0.0)))
	else:
		var item := Item.new(offer["id"])
		v.add_child(_center(ShapeIcon.for_item(item, minf(20.0, 44.0 / item.size().y))))
		v.add_child(_label(item.display_name(), 20, S.TEXT, false, true, true))
		stats = item.stats()
		card.tooltip_text = item.describe()
		if item.has_skill():
			v.add_child(_skill_tag(item, 16))
	# 핵심 능력치 두 개
	var mini := HBoxContainer.new()
	mini.alignment = BoxContainer.ALIGNMENT_CENTER
	mini.add_theme_constant_override("separation", 3)
	var shown := 0
	for e: Array in STAT_ICONS:
		if shown >= 2 or not stats.has(e[1]) or float(stats[e[1]]) == 0.0:
			continue
		mini.add_child(GameIcon.make(e[0], 18))
		mini.add_child(_label((e[2] % float(stats[e[1]])).replace(".00", ""), 16, S.TEXT, false, true))
		shown += 1
	mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(mini)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(spacer)
	var price := HBoxContainer.new()
	price.alignment = BoxContainer.ALIGNMENT_CENTER
	price.add_theme_constant_override("separation", 4)
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price.add_child(GameIcon.make("coin", 30))
	price.add_child(_label(str(cost), 28, S.GOLD if state.gold >= cost else S.RED, false, true))
	v.add_child(price)
	return card


## 적 정찰: 유닛 종류, 능력치, 가방, 아이템 목록, 팀 시너지
func _add_enemy_detail() -> void:
	var enemies := state.enemy_team()
	if inspect_enemy >= enemies.size():
		inspect_enemy = -1
		_add_shop()
		return
	var pack := enemies[inspect_enemy]
	var counts := Synergy.count_tags(enemies)
	var s := BattleSim.unit_stats(pack, Synergy.bonuses(counts))
	var panel := _panel(Color(0.20, 0.08, 0.08, 0.95), S.RED)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	var view := BackpackView.new()
	view.setup(pack, inspect_enemy, cell_size_for(pack), false)
	row.add_child(view)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	info.add_child(_label(pack.display_name(), 24, S.RED.lightened(0.3), false, true))
	info.add_child(_label("%dx%d 가방 · 가치 %d원" % [pack.width, pack.height, pack.total_value()], 15, S.MUTED))
	info.add_child(_stat_row(s))
	info.add_child(_label("초당 피해 %.1f" % dps(s), 15, S.MUTED))
	_add_skill_lines(info, pack)
	row.add_child(info)
	content.add_child(panel)
	for item in pack.items():
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		line.add_child(ShapeIcon.for_item(item, 11.0))
		var tag_name: String = Synergy.TRAITS[item.tag()]["name"]
		line.add_child(_label("%s [%s] %s" % [item.display_name(), tag_name, item.describe()], 15, S.TEXT, true))
		content.add_child(line)
	var syn: PackedStringArray = []
	for tag in Synergy.TAG_ORDER:
		if Synergy.level(tag, counts[tag]) > 0:
			syn.append(Synergy.describe(tag, counts[tag]))
	content.add_child(_label("상대 시너지: " + (", ".join(syn) if not syn.is_empty() else "없음"), 15, S.GOLD, true))
	content.add_child(_label("상대 팀 유닛 %d · 총가치 %d원 · 지면 최대 체력 -%d" % [
		enemies.size(), EnemyGen.total_value(enemies), GameState.hp_loss_for(enemies.size())], 15, S.MUTED, true))


## 결과 배너
func _add_result_panel() -> void:
	var won: bool = summary["won"]
	var accent := S.GOLD if won else S.RED
	var panel := _banner(accent)
	var box: VBoxContainer = panel.get_child(0)
	box.add_child(_label("ROUND %d" % summary["round_played"], 18, S.MUTED, false, true, true))
	box.add_child(_label("승리!" if won else "패배", 64, accent, false, true, true))
	if not won:
		box.add_child(_line_icon("heart", "체력 -%d  (살아남은 적 %d)" % [summary["hp_loss"], summary["survivors"]], S.RED))
	var income_text := "+%d원" % summary["income"]
	if summary["bonus"] > 0:
		income_text += "  (기본 %d + %s %d)" % [GameState.BASE_INCOME, streak_text(summary["streak"]), summary["bonus"]]
	box.add_child(_line_icon("coin", income_text, S.GOLD))
	popup.add_child(panel)
	action_bar.add_child(_action_button("다음 라운드 %d" % state.round_no, _on_continue, "PrimaryButton", "flag"))


func _add_game_over_panel() -> void:
	var panel := _banner(S.RED)
	var box: VBoxContainer = panel.get_child(0)
	box.add_child(_center(GameIcon.make("skull", 64)))
	box.add_child(_label("게임 오버", 58, S.RED, false, true, true))
	box.add_child(_label("라운드 %d 까지 도달" % summary["round_played"], 28, S.TEXT, false, true, true))
	var best: int = records.get("best_round", 0)
	var record_text := "최고 기록 라운드 %d · %d번째 판" % [best, records.get("runs", 0)]
	if summary["round_played"] >= best:
		record_text = "새 최고 기록! · %d번째 판" % records.get("runs", 0)
	box.add_child(_line_icon("star", record_text, S.GOLD))
	popup.add_child(panel)
	action_bar.add_child(_action_button("새로 시작", _on_new_run, "PrimaryButton", "refresh"))


# ── 입력 처리 ─────────────────────────────────────────

## 전장 탭: 같은 유닛을 다시 누르면 상점으로 돌아간다.
func _on_field_tapped(side: String, index: int) -> void:
	message = ""
	selected = null
	if side == "b":
		inspect_enemy = -1 if inspect_enemy == index else index
		inspect_unit = -1
	else:
		inspect_unit = -1 if inspect_unit == index else index
		inspect_enemy = -1
	refresh()


## 전장에서 우리 유닛을 끌어 놓았다
func _on_unit_moved(index: int, pos: Vector2) -> void:
	state.move_unit(index, pos)
	message = ""
	refresh()


func _on_hud_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and (inspect_unit >= 0 or inspect_enemy >= 0):
		_on_back_to_shop()


## 상세 패널 밖을 누르면 상점으로
func _on_back_to_shop() -> void:
	if inspect_unit < 0 and inspect_enemy < 0 and selected == null:
		return
	inspect_unit = -1
	inspect_enemy = -1
	selected = null
	message = ""
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
	if inspect_unit >= 0 and inspect_unit < state.units.size():
		var pack := state.units[inspect_unit]
		if state.sell_unit(pack):
			message = "%s 판매 (+%d원). 가방 속 아이템은 보유함으로 돌아왔습니다." % [pack.display_name(), pack.sell_price()]
			inspect_unit = -1
			selected = null
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
		if offer["kind"] == "unit":
			message = "%s 투입! 전장에서 끌어 자리를 바꿀 수 있습니다." % UnitDB.get_def(offer["id"])["name"]
		else:
			message = "아이템은 전장의 유닛을 눌러 가방에 넣으세요."
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
	battle_view.speed_mult = 2.0 if fast else 1.0
	battle_view.play(last_result, colors_a, colors_b, start_time)


func _on_toggle_fast() -> void:
	fast = not fast
	battle_view.speed_mult = 2.0 if fast else 1.0
	refresh()


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
	inspect_unit = -1
	inspect_enemy = -1
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
	# 4라운드쯤: 견습병(장검) + 병사(투구·수호부적·흡혈송곳니) + 궁수(단검·화염두루마리)
	state.round_no = 4
	state.gold = 6
	state.hp = 76
	state.streak = 2
	state.units.append(Backpack.new("soldier"))
	state.units[1].slot = 1
	state.units.append(Backpack.new("archer"))
	state.units[2].slot = 2
	# 자유 배치: 병사는 앞 가운데, 견습병은 왼쪽, 궁수는 오른쪽 뒤
	state.move_unit(1, Vector2(0.0, 1.8))
	state.move_unit(0, Vector2(-2.0, 2.4))
	state.move_unit(2, Vector2(2.8, 6.2))
	var plan := [[0, "sword"], [1, "helmet"], [1, "ward_charm"], [1, "vampire_tooth"], [2, "dagger"], [2, "fire_scroll"]]
	for p: Array in plan:
		var item := Item.new(p[1])
		state.inventory.append(item)
		state.equip(item, p[0], state.units[p[0]].find_spot(item))
	state.inventory.append_array([Item.new("venom_fang"), Item.new("herb_pouch")])
	state.shop = [
		{"kind": "unit", "id": "mage"}, {"kind": "unit", "id": "knight"},
		{"kind": "item", "id": "storm_rod"}, {"kind": "item", "id": "healing_grail"}, {"kind": "item", "id": "hawk_lens"},
	]
	if kind == "units":
		inspect_unit = 1
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

func _label(text: String, font_size: int = 20, color: Color = S.TEXT, wrap: bool = false, is_bold: bool = false, centered: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_bold:
		l.add_theme_font_override("font", S.bold())
		l.add_theme_constant_override("outline_size", maxi(3, font_size / 6))
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## 스킬 아이템 표시: 별 + 스킬 이름
func _skill_tag(item: Item, font_size: int = 13) -> Control:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 3)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(GameIcon.make("star", font_size + 3, S.GOLD))
	h.add_child(_label(Skills.NAMES.get(item.skill()["type"], "스킬"), font_size, S.GOLD, false, true))
	return h


## 유닛이 가진 스킬 목록
func _add_skill_lines(box: VBoxContainer, pack: Backpack) -> void:
	for item in pack.items():
		if item.has_skill():
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 4)
			h.add_child(GameIcon.make("star", 16, S.GOLD))
			h.add_child(_label(Skills.describe(item.skill()), 14, S.GOLD, true))
			box.add_child(h)


## 제목 + 작은 설명
func _section(title_text: String, sub: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.add_child(_label(title_text, 22, S.GOLD, false, true))
	v.add_child(_label(sub, 13, S.MUTED))
	return v


func _panel(bg: Color, border: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", S.box(bg, border, 2, 14, -1, 12.0))
	return p


## 가운데 배너 (팝업)
func _banner(accent: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := S.shadow(S.box(Color(S.NAVY_DEEP, 0.96), accent, 4, 22, 8, 26.0), 24, 0.5)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(560, 0)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	p.add_child(box)
	return p


func _line_icon(icon: String, text: String, color: Color) -> Control:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 8)
	h.add_child(GameIcon.make(icon, 28))
	h.add_child(_label(text, 22, color, false, true))
	return h


func _center(c: Control) -> Control:
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(c)
	return cc


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 50)
	b.add_theme_font_size_override("font_size", 17)
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


## 맨 아래 큰 버튼 (아이콘 + 글자)
func _action_button(text: String, on_press: Callable, variation: String, icon: String) -> Button:
	var b := _button(text, on_press)
	b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(0, 88)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 32)
	if icon != "":
		var ic := GameIcon.make(icon, 40, Color.WHITE if variation != "PrimaryButton" else Color(0.3, 0.18, 0.02))
		ic.position = Vector2(28, 18)
		b.add_child(ic)
	return b


## 카드 버튼 (테두리 색 = 등급/유닛 색, 고르면 금색 굵은 테두리)
func _card(edge: Color, is_selected: bool, card_size: Vector2, on_press: Callable) -> Button:
	var b := _button("", on_press)
	b.custom_minimum_size = card_size
	b.theme_type_variation = ""
	var border := S.GOLD if is_selected else edge
	var width := 4 if is_selected else 2
	var normal := S.box(Color(S.NAVY_DEEP, 0.95), border, width, 14, 6, 6.0)
	var hover := S.box(S.NAVY, border.lightened(0.2), width, 14, 6, 6.0)
	var pressed := S.box(S.NAVY_LIGHT, border, width, 14, 2, 6.0)
	var dis := S.box(Color(0.05, 0.06, 0.09, 0.9), Color(border, 0.35), 2, 14, 6, 6.0)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", dis)
	return b


## 카드 안 내용 상자
func _card_box(card: Button) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 6
	v.offset_right = -6
	v.offset_top = 6
	v.offset_bottom = -10
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	if card.disabled:
		v.modulate = Color(1, 1, 1, 0.45)
	return v
