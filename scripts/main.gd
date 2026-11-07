extends Control
## 메인 장면. 3D 전장이 화면 전체에 깔려 있고, 그 위에 UI 가 자리마다 겹쳐 있다.
##   위: HUD (라운드·연승/연패·상대 시너지)
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
## 보기 전용 상세(전투 중·적 정찰)에서 누른 아이템 (정보만 보여 줌)
var info_item: Item = null
var message: String = ""
## 다른 유닛의 아이템을 옮기기 전 확인: {item, unit, anchor}
var pending_move: Dictionary = {}
var _confirm_layer: Control = null
## 시트에 정보를 띄운 우리 유닛 번호 (state.units 인덱스, -1 이면 없음)
var inspect_unit: int = -1
## 정찰 중인 적 번호 (-1 이면 없음). 둘 다 -1 이면 시트는 상점.
var inspect_enemy: int = -1
var battling: bool = false
## 전투 2배속 (켜 두면 다음 전투에도 유지)
var speed: int = 1
const MAX_SPEED := 16
var last_result: Dictionary = {}
## 전투가 끝난 뒤 보여 줄 GameState.apply_result() 요약
var summary: Dictionary = {}
var _laid_out: bool = false
var _fit_token: int = 0

## 화면 제목 (테스트에서 확인한다)
@onready var title: Label = $Title
@onready var header: VBoxContainer = $Header
## 우리 팀 시너지: 시트 바로 위 (상대 시너지는 위 HUD)
@onready var own_synergy: HFlowContainer = $OwnSynergy
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
		new_run(_web_seed())


## 상대 출전 풀 (data/opponent_pool.json, 한 번만 읽는다)
static var _pool: OpponentPool = null
static var _pool_loaded: bool = false


static func opponent_pool() -> OpponentPool:
	if not _pool_loaded:
		_pool_loaded = true
		_pool = OpponentPool.load_file()
	return _pool


func new_run(seed_value: int = 0) -> void:
	state = GameState.new(seed_value)
	state.opponents = opponent_pool()
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
	if not summary.is_empty() and not battling:
		_layout_sheet(false)
		if summary.get("victory", false):
			_add_victory_panel()
		elif summary.get("game_over", false):
			_add_game_over_panel()
		else:
			_add_result_panel()
		return
	_build_sheet_head()
	if battling:
		# 전투 중: 전장은 재생 중이라 다시 만들지 않고 강조만 바꾼다
		_refresh_highlight()
	else:
		_refresh_field()
	if inspect_enemy >= 0:
		_add_enemy_detail()
	elif inspect_unit >= 0:
		_add_unit_editor()
		if not battling:
			_add_selection_panel()
	else:
		_add_shop()
	if message != "":
		var m := _label(message, 17, S.RED, true)
		content.add_child(m)
	# 시트는 내용 높이에 맞춘다(아래 여백 없음). 내용이 최대 높이를 넘으면 스크롤.
	_layout_sheet(true, true)
	_update_confirm()


## 시트 보이기와 카메라 구도를 맞춘다. fit 이면 시트 높이를 내용에 맞춘다.
func _layout_sheet(show: bool, fit: bool = false) -> void:
	sheet.visible = show
	var h := SHEET_OPEN_HEIGHT
	if show and fit:
		h = minf(SHEET_OPEN_HEIGHT, sheet_fit_height())
	_apply_sheet_height(show, h)
	if show and fit:
		_refit_next_frame()


func _apply_sheet_height(show: bool, h: float) -> void:
	sheet.offset_bottom = -SHEET_BOTTOM
	sheet.offset_top = -(SHEET_BOTTOM + h)
	# 우리 시너지는 시트 바로 위에 붙는다 (시트가 없으면 숨김)
	own_synergy.visible = show
	own_synergy.offset_bottom = sheet.offset_top - 8.0
	own_synergy.offset_top = own_synergy.offset_bottom - own_synergy.get_combined_minimum_size().y
	var bottom := (S_VIEW_HEIGHT - SHEET_BOTTOM - h) if show else BattleView3D.FULL_BOTTOM_Y
	# 첫 화면은 바로, 그 뒤엔 부드럽게 카메라를 옮긴다.
	battle_view.set_framing(BattleView3D.framing_for_bottom(bottom), _laid_out)
	_laid_out = true


## 줄바꿈 글자는 폭이 정해진 뒤에야 높이가 맞으므로 한 프레임 뒤 다시 잰다.
func _refit_next_frame() -> void:
	_fit_token += 1
	var token := _fit_token
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if token != _fit_token or not sheet.visible or not is_inside_tree():
		return
	_apply_sheet_height(true, minf(SHEET_OPEN_HEIGHT, sheet_fit_height()))


## 시트 머리 + 내용 + 여백을 합친 높이
func sheet_fit_height() -> float:
	var sb := sheet.get_theme_stylebox("panel")
	var box_sep := float((sheet.get_child(0) as VBoxContainer).get_theme_constant("separation"))
	var margins := sb.get_minimum_size().y if sb != null else 0.0
	var head := sheet_head.get_combined_minimum_size().y + box_sep if sheet_head.visible else 0.0
	return head + content.get_combined_minimum_size().y + margins


func _build_sheet_head() -> void:
	sheet_head.add_theme_constant_override("separation", 8)
	# 상세 패널(유닛 정보·정찰)에는 머리가 없다 (이름 칸이 제목 역할). 상점으로는 패널 밖을 눌러 돌아간다
	sheet_head.visible = inspect_unit < 0 and inspect_enemy < 0
	if not sheet_head.visible:
		return
	sheet_head.add_child(_label("상점", 24, S.GOLD, false, true))
	sheet_head.add_child(_badge("coin", str(state.gold), S.GOLD))
	var reroll := _button("새로고침 %d원" % GameState.REROLL_COST, _on_reroll)
	reroll.disabled = battling or state.gold < GameState.REROLL_COST
	sheet_head.add_child(reroll)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_head.add_child(spacer)
	# 상점 오른쪽 위: 체력 + 전투 시작(전투 중엔 배속)
	sheet_head.add_child(_hp_widget())
	# 전투 중에는 같은 자리가 배속 버튼
	var fight: Button
	if battling:
		fight = _button("배속 x%d" % speed, _on_toggle_fast)
		fight.theme_type_variation = "PrimaryButton" if speed > 1 else "Button"
	else:
		fight = _button("전투 시작", _on_fight)
		fight.theme_type_variation = "GoButton"
		fight.disabled = not state.can_fight()
	fight.custom_minimum_size = Vector2(176, 56)
	fight.add_theme_font_size_override("font_size", 22)
	var ic := GameIcon.make("bolt" if battling else "sword", 24, Color(0.3, 0.18, 0.02) if battling and speed > 1 else Color.WHITE)
	ic.position = Vector2(10, 13)
	fight.add_child(ic)
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
	header.add_child(row)
	# 위: 상대 팀 시너지, 아래(시트 위): 우리 팀 시너지
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 4)
	_add_synergy_chips(chips, Synergy.count_tags(state.enemy_team()), S.RED, "상대")
	header.add_child(chips)
	_clear(own_synergy)
	_add_synergy_chips(own_synergy, Synergy.count_tags(state.units), S.GOLD, "우리")


## 시너지 칩 줄: [팀 이름] + 특성마다 칩 (켜진 것은 accent 색)
func _add_synergy_chips(flow: HFlowContainer, counts: Dictionary, accent: Color, team: String) -> void:
	var name_chip := PanelContainer.new()
	name_chip.add_theme_stylebox_override("panel", S.box(Color(accent.darkened(0.55), 0.95), accent, 2, 10, -1, 4.0))
	name_chip.add_child(_label(team, 14, accent.lightened(0.3), false, true))
	flow.add_child(name_chip)
	for tag in Synergy.TAG_ORDER:
		var n: int = counts.get(tag, 0)
		var on := Synergy.level(tag, n) > 0
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", S.box(Color(accent.darkened(0.6), 0.9) if on else Color(0, 0, 0, 0.45), accent if on else Color(1, 1, 1, 0.12), 2, 10, -1, 4.0))
		chip.add_child(_label(Synergy.describe(tag, n), 14, accent.lightened(0.25) if on else S.MUTED, false, on))
		flow.add_child(chip)


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
	_refresh_highlight()


func _refresh_highlight() -> void:
	if inspect_enemy >= 0:
		battle_view.set_highlight("b", inspect_enemy)
	elif inspect_unit >= 0:
		battle_view.set_highlight("a", inspect_unit)
	else:
		battle_view.set_highlight("a", -1)


## 능력치 칩 줄
func _stat_row(s: Dictionary, font_size: int = 16, with_hp: bool = true) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 4)
	for e: Array in STAT_ICONS:
		if e[1] == "hp" and not with_hp:
			continue
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


## 상세 패널 2x2 틀: [이름 | 정보] / [가방 | 아이템 목록]. 왼쪽 칸 폭은 가방에 맞춘다.
func _detail_grid(left_w: float, name_box: Control, info_box: Control, bag_box: Control, list_box: Control, edge: Color) -> Control:
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 8)
	for pair: Array in [[name_box, info_box], [bag_box, list_box]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		for i in 2:
			var cell: Control = pair[i]
			var panel: PanelContainer = cell if cell is PanelContainer else PanelContainer.new()
			if panel != cell:
				panel.add_child(cell)
			panel.add_theme_stylebox_override("panel", S.box(Color(S.NAVY_DEEP, 0.92), edge, 2, 14, -1, 10.0))
			if i == 0:
				panel.custom_minimum_size.x = left_w
			else:
				panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(panel)
		grid.add_child(row)
	return grid


## 이름 칸: 이름, (편성 중) 모두 빼기·판매
func _name_box(pack: Backpack, color: Color, with_actions: bool) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.add_child(_label(pack.display_name(), 26, color, false, true))
	if with_actions:
		var strip := _button("모두 빼기", _on_unequip_all)
		strip.disabled = pack.is_empty()
		strip.custom_minimum_size = Vector2(0, 42)
		v.add_child(strip)
		var sell := _button("판매 +%d원" % pack.sell_price(), _on_sell_unit)
		sell.theme_type_variation = "DangerButton"
		sell.custom_minimum_size = Vector2(0, 42)
		v.add_child(sell)
	return v


## 정보 칸: 위에서부터 체력 막대, 공격 쿨타임 막대(+스킬 쿨타임), 나머지 능력치(체력 제외), 초당 피해, 스킬
func _info_box(pack: Backpack, s: Dictionary, side: String, idx: int) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(LiveStats.make(_live_source.bind(side, idx, s)))
	v.add_child(_stat_row(s, 16, false))
	v.add_child(_label("초당 피해 %.1f" % dps(s), 14, S.MUTED))
	_add_skill_lines(v, pack)
	return v


func _bag_box(view: BackpackView) -> Control:
	var c := CenterContainer.new()
	c.add_child(view)
	return c


## 상세 패널 아이템 카드 (끌기 가능하면 DragItemCard)
func _list_item_card(item: Item, dim: bool, draggable: bool, on_press: Callable, cell: float, owner_name: String = "") -> Button:
	var card := DragItemCard.new()
	card.item = item
	card.draggable = draggable
	card.preview_cell = cell
	_card(S.rarity_color(item.cost()), item == selected or item == info_item, Vector2(96, 92), on_press, card)
	card.add_theme_font_size_override("font_size", 17)
	var v := _card_box(card)
	v.add_child(_center(ShapeIcon.for_item(item, 12.0)))
	v.add_child(_label(item.display_name(), 14, S.TEXT, false, true, true))
	if item.has_skill():
		v.add_child(_skill_tag(item, 12))
	if owner_name != "":
		v.add_child(_label(owner_name + " 장착", 11, S.MUTED, false, false, true))
	if dim:
		card.modulate = Color(1, 1, 1, 0.35)
	return card


func _add_unit_editor() -> void:
	var pack := state.units[inspect_unit]
	var cell := cell_size_for(pack)
	var view := BackpackView.new()
	view.setup(pack, inspect_unit, cell, not battling)
	view.selected = info_item if battling else selected
	if battling:
		view.cell_pressed.connect(_on_info_cell.bind(pack))
	else:
		view.cell_pressed.connect(_on_cell_pressed)
		view.drop_check = func(item: Item, anchor: Vector2i) -> bool: return state.can_equip_flexible(item, inspect_unit, anchor)
		view.item_dropped.connect(_on_item_dropped)
	var s := BattleSim.unit_stats(pack, Synergy.bonuses(Synergy.count_tags(state.units)))
	# 아이템 목록 칸: 보유 아이템. 이 가방에 안 들어가는 건 흐리게. 가방 아이템을 여기로 끌면 뺀다.
	var zone := DropZone.new()
	zone.accepts = func(data: Dictionary) -> bool: return not battling and data.get("type", "") == "item" and int(data.get("from_unit", -1)) >= 0
	zone.on_drop = func(data: Dictionary) -> void: _on_item_dropped_to_list(data["item"])
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	lv.add_child(_label("장착 가능 아이템", 18, S.GOLD, false, true))
	lv.add_child(_label("전투 중에는 편성할 수 없습니다" if battling else "끌어서 가방에 넣기 · 가방에서 여기로 끌면 빼기", 12, S.MUTED, true))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	var others := state.items_on_other_units(inspect_unit)
	if state.inventory.is_empty() and others.is_empty():
		flow.add_child(_label("보유 아이템 없음", 15, S.MUTED))
	var items := state.inventory.duplicate()
	items.sort_custom(func(a: Item, b: Item) -> bool: return int(state.fits_in(a, inspect_unit)) > int(state.fits_in(b, inspect_unit)))
	for item: Item in items:
		var fits := state.fits_in(item, inspect_unit)
		flow.add_child(_list_item_card(item, not fits, fits and not battling, _on_inventory_pressed.bind(item), cell))
	# 다른 유닛이 장착 중인 아이템: 흐리게. 끌어 넣으면 옮길지 묻는다.
	others.sort_custom(func(a: Array, b: Array) -> bool: return int(state.fits_in(a[0], inspect_unit)) > int(state.fits_in(b[0], inspect_unit)))
	for e: Array in others:
		var item: Item = e[0]
		var fits := state.fits_in(item, inspect_unit)
		flow.add_child(_list_item_card(item, true, fits and not battling, _on_inventory_pressed.bind(item), cell, state.units[e[1]].display_name()))
	lv.add_child(flow)
	zone.add_child(lv)
	var left_w := maxf(200.0, pack.width * cell + 24.0)
	content.add_child(_detail_grid(left_w, _name_box(pack, pack.color().lightened(0.35), not battling), _info_box(pack, s, "a", inspect_unit), _bag_box(view), zone, S.EDGE))
	if battling:
		_add_item_info(pack)


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
	var w := Vector2(100, 262)
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
	card.disabled = battling or state.buy_block_reason(index) != ""
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
	# 핵심 능력치 (세로로 한 줄에 하나)
	var shown := 0
	for e: Array in STAT_ICONS:
		if shown >= 2 or not stats.has(e[1]) or float(stats[e[1]]) == 0.0:
			continue
		var line := HBoxContainer.new()
		line.alignment = BoxContainer.ALIGNMENT_CENTER
		line.add_theme_constant_override("separation", 5)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(GameIcon.make(e[0], 24))
		line.add_child(_label((e[2] % float(stats[e[1]])).replace(".00", ""), 22, S.TEXT, false, true))
		v.add_child(line)
		shown += 1
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
	var cell := cell_size_for(pack)
	var view := BackpackView.new()
	view.setup(pack, inspect_enemy, cell, false)
	view.selected = info_item
	view.cell_pressed.connect(_on_info_cell.bind(pack))
	# 아이템 목록 칸: 상대 가방 속 아이템 (누르면 정보)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	lv.add_child(_label("가방 속 아이템", 18, S.RED.lightened(0.3), false, true))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	if pack.is_empty():
		flow.add_child(_label("아이템 없음", 15, S.MUTED))
	for item in pack.items():
		flow.add_child(_list_item_card(item, false, false, _on_info_item.bind(item), cell))
	lv.add_child(flow)
	var left_w := maxf(200.0, pack.width * cell + 24.0)
	var name_box := _name_box(pack, S.RED.lightened(0.3), false)
	# 전투 전: 1원으로 이번 라운드 상대를 다른 출전으로 바꾼다
	var change := _button("상대 바꾸기 %d원" % state.enemy_reroll_cost(), _on_reroll_enemy)
	change.disabled = battling or not state.can_reroll_enemy()
	change.custom_minimum_size = Vector2(0, 42)
	name_box.add_child(change)
	content.add_child(_detail_grid(left_w, name_box, _info_box(pack, s, "b", inspect_enemy), _bag_box(view), lv, Color(S.RED, 0.6)))
	_add_item_info(pack)
	var syn: PackedStringArray = []
	for tag in Synergy.TAG_ORDER:
		if Synergy.level(tag, counts[tag]) > 0:
			syn.append(Synergy.describe(tag, counts[tag]))
	content.add_child(_label("상대 시너지: " + (", ".join(syn) if not syn.is_empty() else "없음"), 15, S.GOLD, true))
	content.add_child(_label("상대 팀 유닛 %d · 총가치 %d원 · 지면 체력 -%d" % [
		enemies.size(), EnemyGen.total_value(enemies), GameState.hp_loss_for(state.round_no)], 15, S.MUTED, true))


## 결과 배너
func _add_result_panel() -> void:
	var won: bool = summary["won"]
	var accent := S.GOLD if won else S.RED
	var panel := _banner(accent)
	var box: VBoxContainer = panel.get_child(0)
	box.add_child(_label("ROUND %d" % summary["round_played"], 18, S.MUTED, false, true, true))
	box.add_child(_label("승리!" if won else "패배", 64, accent, false, true, true))
	if not won:
		box.add_child(_line_icon("heart", "체력 -%d  (라운드 %d)" % [summary["hp_loss"], summary["round_played"]], S.RED))
	var income_text := "+%d원" % summary["income"]
	var parts: PackedStringArray = ["기본 %d" % GameState.BASE_INCOME]
	if summary["bonus"] > 0:
		parts.append("%s %d" % [streak_text(summary["streak"]), summary["bonus"]])
	if int(summary.get("interest", 0)) > 0:
		parts.append("이자 %d" % summary["interest"])
	if parts.size() > 1:
		income_text += "  (%s)" % " + ".join(parts)
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


## 우승: 출전 풀에 다음 라운드 상대가 없다 (모든 라운드를 이겨 냄)
func _add_victory_panel() -> void:
	var panel := _banner(S.GOLD)
	var box: VBoxContainer = panel.get_child(0)
	box.add_child(_center(GameIcon.make("star", 72, S.GOLD)))
	box.add_child(_label("우승!", 64, S.GOLD, false, true, true))
	box.add_child(_label("라운드 %d 까지 모든 상대를 이겼습니다" % summary["round_played"], 24, S.TEXT, false, true, true))
	var pool_meta: Dictionary = state.opponents.meta if state.opponents != null else {}
	if pool_meta.has("players"):
		box.add_child(_label("봇 %d명 중 마지막까지 살아남은 상대를 꺾었습니다" % int(pool_meta["players"]), 18, S.MUTED, false, false, true))
	box.add_child(_line_icon("heart", "남은 체력 %d" % state.hp, S.GREEN))
	box.add_child(_line_icon("flag", "%d번째 판" % records.get("runs", 0), S.MUTED))
	popup.add_child(panel)
	action_bar.add_child(_action_button("새로 시작", _on_new_run, "PrimaryButton", "refresh"))


# ── 입력 처리 ─────────────────────────────────────────

## 전장 탭: 같은 유닛을 다시 누르면 상점으로 돌아간다.
func _on_field_tapped(side: String, index: int) -> void:
	message = ""
	selected = null
	info_item = null
	if side == "b":
		inspect_enemy = -1 if inspect_enemy == index else index
		inspect_unit = -1
	else:
		inspect_unit = -1 if inspect_unit == index else index
		inspect_enemy = -1
	refresh()


## 전장에서 우리 유닛을 끌어 놓았다
func _on_unit_moved(index: int, pos: Vector2) -> void:
	if battling:
		return
	state.move_unit(index, pos)
	message = ""
	refresh()


func _on_hud_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and (inspect_unit >= 0 or inspect_enemy >= 0):
		_on_back_to_shop()


## 상세 패널 밖을 누르면 상점으로
func _on_back_to_shop() -> void:
	if inspect_unit < 0 and inspect_enemy < 0 and selected == null and info_item == null:
		return
	inspect_unit = -1
	inspect_enemy = -1
	selected = null
	info_item = null
	message = ""
	refresh()


func _on_inventory_pressed(item: Item) -> void:
	if battling:
		return
	selected = null if selected == item else item
	message = ""
	refresh()


func _on_cell_pressed(unit_index: int, cell: Vector2i) -> void:
	if battling:
		return
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


## 아이템을 가방 칸에 끌어 놓음 (보유함에서 또는 가방 안에서 옮김)
func _on_item_dropped(unit_index: int, item: Item, anchor: Vector2i) -> void:
	if battling:
		return
	if state.is_taken_from_other(item, unit_index) and state.can_equip_flexible(item, unit_index, anchor):
		# 다른 유닛이 장착 중: 옮길지 먼저 묻는다
		pending_move = {"item": item, "unit": unit_index, "anchor": anchor}
		refresh()
		return
	if state.equip_flexible(item, unit_index, anchor):
		selected = null
		message = ""
	else:
		message = "그 자리에는 들어가지 않습니다."
	refresh()


func _on_confirm_move() -> void:
	var m := pending_move
	pending_move = {}
	if m.is_empty() or battling:
		refresh()
		return
	if state.equip_flexible(m["item"], m["unit"], m["anchor"]):
		selected = null
		message = ""
	else:
		message = "그 자리에는 들어가지 않습니다."
	refresh()


func _on_cancel_move() -> void:
	pending_move = {}
	refresh()


## 옮기기 확인 창: 화면 전체를 덮고(밖을 누르면 취소) 가운데에 묻는다
func _update_confirm() -> void:
	if _confirm_layer != null:
		remove_child(_confirm_layer)
		_confirm_layer.queue_free()
		_confirm_layer = null
	if pending_move.is_empty():
		return
	var item: Item = pending_move["item"]
	var from := state.unit_of(item)
	if from < 0 or int(pending_move["unit"]) >= state.units.size():
		pending_move = {}
		return
	var layer := ColorRect.new()
	layer.color = Color(0.02, 0.03, 0.06, 0.55)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.gui_input.connect(func(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_on_cancel_move.call_deferred())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	var panel := _banner(S.GOLD)
	panel.custom_minimum_size = Vector2(560, 0)
	var box: VBoxContainer = panel.get_child(0)
	box.add_child(_label("아이템 옮기기", 28, S.GOLD, false, true, true))
	box.add_child(_center(ShapeIcon.for_item(item, 18.0)))
	box.add_child(_label("%s 가방의 %s을(를)\n%s 가방으로 옮길까요?" % [
		state.units[from].display_name(), item.display_name(), state.units[pending_move["unit"]].display_name()], 20, S.TEXT, true, false, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var cancel := _button("취소", _on_cancel_move)
	cancel.custom_minimum_size = Vector2(180, 64)
	row.add_child(cancel)
	var ok := _button("옮기기", _on_confirm_move)
	ok.theme_type_variation = "PrimaryButton"
	ok.custom_minimum_size = Vector2(180, 64)
	row.add_child(ok)
	box.add_child(row)
	center.add_child(panel)
	add_child(layer)
	_confirm_layer = layer


## 가방 아이템을 목록으로 끌어 놓음 → 빼기
func _on_item_dropped_to_list(item: Item) -> void:
	if battling:
		return
	state.unequip(item)
	selected = null
	refresh()


## 보기 전용 목록의 아이템을 누르면 정보 (다시 누르면 닫힘)
func _on_info_item(item: Item) -> void:
	info_item = null if info_item == item else item
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
	if battling:
		return
	if selected != null and state.sell_item(selected):
		selected = null
	refresh()


func _on_unequip_all() -> void:
	if battling or inspect_unit < 0:
		return
	var n := state.unequip_all(inspect_unit)
	selected = null
	message = "아이템 %d개를 보유함으로 뺐습니다." % n if n > 0 else ""
	refresh()


func _on_sell_unit() -> void:
	if battling:
		return
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
	if battling:
		return
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
	if battling:
		return
	state.reroll()
	refresh()


func _on_reroll_enemy() -> void:
	if battling or not state.reroll_enemy():
		return
	# 새 상대 팀의 첫 유닛을 정찰한다
	inspect_enemy = 0
	info_item = null
	refresh()


func _on_fight() -> void:
	_start_battle(0.0)


func _start_battle(start_time: float) -> void:
	if not state.can_fight():
		return
	selected = null
	info_item = null
	message = ""
	inspect_enemy = -1
	inspect_unit = -1
	var colors_a: Array[Color] = []
	for u in state.units:
		colors_a.append(unit_color(u))
	var colors_b: Array[Color] = []
	for u in state.enemy_team():
		colors_b.append(unit_color(u))
	last_result = state.fight()
	battling = true
	refresh()
	battle_view.speed_mult = float(speed)
	battle_view.play(last_result, colors_a, colors_b, start_time)


## 배속: 1 → 2 → 4 → 8 → 16 → 1 (다음 전투에도 유지)
static func next_speed(current: int) -> int:
	return 1 if current >= MAX_SPEED else current * 2


func _on_toggle_fast() -> void:
	speed = next_speed(speed)
	battle_view.speed_mult = float(speed)
	refresh()


func _on_battle_finished(_winner: String) -> void:
	if not battling:
		return
	battling = false
	summary = state.apply_result(last_result)
	if summary["game_over"] or summary.get("victory", false):
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

## 웹에서 주소 끝에 #seed=123 을 붙이면 그 시드로 시작한다 (같은 상점·상대로 다시 해 보기·시험용). 없으면 0(무작위).
func _web_seed() -> int:
	if not OS.has_feature("web"):
		return 0
	var hash_text: Variant = JavaScriptBridge.eval("window.location.hash", true)
	return seed_from_hash(String(hash_text) if hash_text != null else "")


static func seed_from_hash(text: String) -> int:
	var t := text.trim_prefix("#")
	for part in t.split("&"):
		if part.begins_with("seed="):
			return maxi(0, part.substr(5).to_int())
	return 0


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
		# move=1 : 다른 유닛(궁수)의 단검을 옮길지 묻는 창 (스크린샷용)
		if OS.get_cmdline_user_args().has("move=1"):
			selected = null
			pending_move = {"item": state.units[2].items()[0], "unit": 1, "anchor": Vector2i(0, 0)}
	elif kind == "enemy":
		inspect_enemy = 0
	elif kind == "battle":
		var at := 3.0
		for a in OS.get_cmdline_user_args():
			if a.begins_with("t="):
				at = a.substr(2).to_float()
		_start_battle(at)
		# inspect=a1 / inspect=b0 : 전투 중 상세 보기 (스크린샷용)
		for a in OS.get_cmdline_user_args():
			if a.begins_with("inspect=") and a.length() >= 10:
				_on_field_tapped(a.substr(8, 1), a.substr(9).to_int())
		# info=1 : 상세 패널 가방의 첫 아이템 정보 열기 (스크린샷용)
		if OS.get_cmdline_user_args().has("info=1") and inspect_unit >= 0:
			var pack := state.units[inspect_unit]
			if not pack.is_empty():
				_on_info_cell(inspect_unit, pack.placements[0]["pos"], pack)
		return
	elif kind == "result":
		state.gold = maxi(state.gold, 12)  # 이자도 보이게
		last_result = state.fight()
		summary = state.apply_result(last_result)
	elif kind == "victory":
		state.hp = 64
		summary = {"won": true, "hp_loss": 0, "streak": 5, "round_played": 24, "income": 7, "bonus": 4, "game_over": false, "victory": true}
		records = {"best_round": 24, "runs": 6, "last_round": 24}
	elif kind == "gameover":
		state.hp = 1
		summary = {"won": false, "hp_loss": 9, "streak": -3, "round_played": 9, "income": 0, "bonus": 0, "game_over": true}
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


## 상세 패널의 체력·쿨타임 값. 전투 중이면 재생 중인 그 순간 값, 아니면 고정값.
func _live_source(side: String, idx: int, s: Dictionary) -> Dictionary:
	var sk: Dictionary = s.get("skills", Skills.aggregate([]))
	var d := {
		"hp": s["hp"], "max_hp": s["hp"], "shield": sk["shield"], "cd": 0.0,
		"interval": 1.0 / maxf(0.01, s["spd"]), "live": false,
		"heal_cd": sk["heal_cd"] if sk["heal_amount"] > 0.0 else 0.0, "heal_t": 0.0,
		"fire_cd": sk["fireball_cd"] if sk["fireball_dmg"] > 0.0 else 0.0, "fire_t": 0.0,
	}
	if battling and is_instance_valid(battle_view):
		var live := battle_view.live_unit(side, idx)
		if not live.is_empty():
			for k: String in ["hp", "max_hp", "shield", "cd", "heal_t", "fire_t"]:
				d[k] = live[k]
			d["interval"] = 1.0 / maxf(0.01, live["spd"])
			d["live"] = true
	return d


## 보기 전용 가방에서 아이템을 누르면 그 정보 (같은 아이템을 다시 누르면 닫힘)
func _on_info_cell(_unit_index: int, cell: Vector2i, pack: Backpack) -> void:
	var at := pack.item_at(cell)
	info_item = null if at == info_item else at
	refresh()


## 아이템 정보 패널 (보기 전용)
func _add_item_info(pack: Backpack) -> void:
	if info_item == null or not pack.has_item(info_item):
		return
	var item := info_item
	var panel := _panel(Color(0.25, 0.19, 0.06, 0.95), S.rarity_color(item.cost()))
	var box := VBoxContainer.new()
	panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(ShapeIcon.for_item(item, 16.0))
	head.add_child(_label(item.display_name(), 24, S.GOLD, false, true))
	var tag_name: String = Synergy.TRAITS[item.tag()]["name"]
	head.add_child(_label("[%s] · %s · %d원" % [tag_name, S.rarity_name(item.cost()), item.cost()], 15, S.MUTED))
	box.add_child(head)
	box.add_child(_label(Pricing.describe_stats(item.stats(), float(item.def().get("range", 0.0))), 18, S.TEXT, true))
	if item.has_skill():
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		h.add_child(GameIcon.make("star", 20, S.GOLD))
		h.add_child(_label(Skills.describe(item.skill()), 17, S.GOLD, true))
		box.add_child(h)
	content.add_child(panel)


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
func _card(edge: Color, is_selected: bool, card_size: Vector2, on_press: Callable, b: Button = null) -> Button:
	if b == null:
		b = _button("", on_press)
	elif on_press.is_valid():
		b.pressed.connect(on_press)
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
