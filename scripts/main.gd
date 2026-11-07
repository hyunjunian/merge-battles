extends Control
## 메인 장면. 화면 위쪽엔 3D 전장이 항상 떠 있고, 아래 패널에서 유닛을 편성한다.
##   전장 위쪽: 다음 상대 (탭하면 아래 패널에 상세 전력)
##   전장 아래쪽: 우리 유닛 자리 3개 (탭하면 그 유닛의 가방 편집)
##   전투 시작: 같은 전장에서 전투를 재생하고, 끝나면 다음 상대가 다시 선다.
## 게임 규칙은 scripts/core/ 에 있고, 여기서는 입력을 GameState 에 넘기고 결과를 보여 주기만 한다.
##
## 스크린샷용 데모: 실행 인자 demo=camp | demo=prep | demo=enemy | demo=battle (t=<초>)

const PANEL := Color(0.18, 0.16, 0.14)
const ACCENT := Color(0.95, 0.75, 0.30)
const ENEMY := Color(1.0, 0.55, 0.5)

var state: GameState
var selected: Item = null
var message: String = ""
## 편성 중인 우리 유닛 번호
var active_unit: int = 0
## 상세 보기 중인 적 번호 (-1 이면 편성 패널)
var inspect_enemy: int = -1
var battling: bool = false
var last_result: Dictionary = {}
var _result_info: Dictionary = {}  # 전투가 끝난 뒤 보여 줄 {won, reward}

## 화면 제목 (테스트에서 확인한다)
@onready var title: Label = $Title
@onready var header: VBoxContainer = $Header
@onready var battle_view: BattleView3D = $Field/BattleView3D
@onready var content: VBoxContainer = $Scroll/Content
@onready var action_bar: HBoxContainer = $ActionBar


## 순수 로직은 이렇게 작은 함수로 나눠 tests/ 에서 검사한다.
static func clamp_score(score: int) -> int:
	return clampi(score, 0, 999_999)


## 유닛 대표 색: 가방에서 가장 비싼 아이템 색.
static func unit_color(pack: Backpack) -> Color:
	var best: Item = null
	for item in pack.items():
		if best == null or item.cost() > best.cost():
			best = item
	return best.color() if best != null else Color.GRAY


static func stats_line(s: Dictionary) -> String:
	return "체력 %d · 공격 %.1f · 방어 %d\n공속 %.2f · 회복 %.1f · %s" % [
		roundi(s["hp"]), s["atk"], roundi(s["armor"]), s["spd"], s["regen"],
		"원거리 %.1f" % s["range"] if BattleSim.is_ranged(s) else "근접",
	]


## 초당 피해(방어 0 기준)
static func dps(s: Dictionary) -> float:
	return float(s["atk"]) * float(s["spd"])


## 전장 미리보기 명단: 우리 쪽은 자리 3개(빈자리 포함), 상대는 생성된 유닛.
static func roster(packs: Array[Backpack], side: String, label_fmt: String, keep_empty: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var bonus := Synergy.bonuses(Synergy.count_tags(packs))
	for i in packs.size():
		var pack := packs[i]
		if pack.is_empty() and not keep_empty:
			continue
		out.append({
			"pos": BattleSim.start_position(side, i, packs.size()),
			"color": unit_color(pack),
			"ranged": BattleSim.is_ranged(BattleSim.unit_stats(pack, bonus)),
			"empty": pack.is_empty(),
			"label": label_fmt % (i + 1),
		})
	return out


func _ready() -> void:
	state = GameState.new()
	battle_view.unit_tapped.connect(_on_field_tapped)
	battle_view.finished.connect(_on_battle_finished)
	var demo := _demo_arg()
	if demo != "":
		_setup_demo(demo)
	else:
		refresh()


# ── 화면 구성 ─────────────────────────────────────────

func refresh() -> void:
	_clear(content)
	_clear(action_bar)
	_build_header()
	if battling:
		content.add_child(_label("전투 중… 유닛들이 알아서 싸웁니다.", 22, Color(1, 1, 1, 0.8)))
		action_bar.add_child(_big_button("건너뛰기", _on_skip))
		return
	if not _result_info.is_empty():
		_add_result_panel()
		return
	_refresh_field()
	if inspect_enemy >= 0:
		_add_enemy_detail()
	else:
		_add_unit_editor()
		_add_inventory()
		_add_selection_panel()
		if state.phase == GameState.Phase.CAMP:
			_add_shop()
	if message != "":
		content.add_child(_label(message, 20, Color(1, 0.6, 0.5), true))
	_add_main_actions()


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _build_header() -> void:
	_clear(header)
	if battling:
		title.text = "라운드 %d 전투" % state.round_no
	elif state.phase == GameState.Phase.CAMP:
		title.text = "베이스 캠프 · 다음 상대: 라운드 %d" % state.round_no
	else:
		title.text = "원정 · 라운드 %d" % state.round_no
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.add_child(_label("골드 %d" % state.gold, 22, ACCENT))
	var over := state.used_budget() > state.budget()
	row.add_child(_label("예산 %d / %d" % [state.used_budget(), state.budget()], 22, Color.RED if over else Color.WHITE))
	if state.best_round > 0:
		row.add_child(_label("최고 라운드 %d" % state.best_round, 18, Color(1, 1, 1, 0.6)))
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


## 전장 미리보기: 우리 자리 3개 + 다음 상대
func _refresh_field() -> void:
	battle_view.show_preview(roster(state.units, "a", "유닛 %d", true), roster(state.enemy_team(), "b", "적 %d", false))
	if inspect_enemy >= 0:
		battle_view.set_highlight("b", inspect_enemy)
	else:
		battle_view.set_highlight("a", active_unit)


func _add_unit_editor() -> void:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	for i in state.units.size():
		var b := _button("유닛 %d (%d)" % [i + 1, state.units[i].total_cost()], _on_unit_tab.bind(i))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i == active_unit:
			b.add_theme_color_override("font_color", ACCENT)
			b.add_theme_color_override("font_hover_color", ACCENT)
		tabs.add_child(b)
	content.add_child(tabs)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var pack := state.units[active_unit]
	var view := BackpackView.new()
	view.setup(pack, active_unit, 56.0)
	view.selected = selected
	view.cell_pressed.connect(_on_cell_pressed)
	row.add_child(view)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_label("유닛 %d 가방" % (active_unit + 1), 20, ACCENT))
	if pack.is_empty():
		info.add_child(_label("비어 있어 출전하지 않습니다.\n아래 보유 아이템을 고른 뒤 가방 칸을 누르세요.", 16, Color(1, 1, 1, 0.65), true))
	else:
		var s := BattleSim.unit_stats(pack, Synergy.bonuses(Synergy.count_tags(state.units)))
		info.add_child(_label(stats_line(s), 16, Color(1, 1, 1, 0.85), true))
		info.add_child(_label("초당 피해 %.1f" % dps(s), 16, Color(1, 1, 1, 0.6)))
	row.add_child(info)
	content.add_child(row)


func _add_inventory() -> void:
	content.add_child(_label("보유 아이템", 18, Color(1, 1, 1, 0.6)))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	if state.inventory.is_empty():
		flow.add_child(_label("(없음)", 18, Color(1, 1, 1, 0.4)))
	for item in state.inventory:
		var b := _item_button(item, "%s\n비용 %d" % [item.display_name(), item.cost()])
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
	var place := "보유함" if where < 0 else "유닛 %d 가방" % (where + 1)
	box.add_child(_label("%s  [%s] · 비용 %d · %s" % [selected.display_name(), tag_name, selected.cost(), place], 18, ACCENT, true))
	box.add_child(_label(selected.describe(), 16, Color.WHITE, true))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	if selected.is_rotatable():
		actions.add_child(_button("회전", _on_rotate))
	if where >= 0:
		actions.add_child(_button("빼기", _on_unequip))
	if state.phase == GameState.Phase.CAMP:
		var merge_btn := _button("합성 ★%d" % (selected.tier + 1), _on_merge)
		merge_btn.disabled = state.merge_partner(selected) == null
		actions.add_child(merge_btn)
		actions.add_child(_button("판매 +%d" % selected.sell_price(), _on_sell))
	actions.add_child(_button("닫기", _on_deselect))
	box.add_child(actions)
	content.add_child(panel)


func _add_shop() -> void:
	var head := HBoxContainer.new()
	head.add_child(_label("상점", 20, ACCENT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var reroll := _button("새로고침 (%d골드)" % GameState.REROLL_COST, _on_reroll)
	reroll.disabled = state.gold < GameState.REROLL_COST
	head.add_child(reroll)
	content.add_child(head)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	for i in state.shop.size():
		var item := state.shop[i]
		var b := _item_button(item, "%s\n%d골드" % [item.display_name(), item.cost()])
		b.tooltip_text = item.describe()
		b.disabled = state.gold < item.cost()
		b.pressed.connect(_on_buy.bind(i))
		row.add_child(b)
	content.add_child(row)


## 적 상세 전력: 능력치, 가방, 아이템 목록, 팀 시너지
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
	head.add_child(_label("적 %d 상세 전력 (라운드 %d)" % [inspect_enemy + 1, state.round_no], 22, ENEMY))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(_button("닫기", _on_close_enemy))
	content.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var view := BackpackView.new()
	view.setup(pack, inspect_enemy, 52.0, false)
	row.add_child(view)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_label(stats_line(s), 17, Color.WHITE, true))
	info.add_child(_label("초당 피해 %.1f · 아이템 가치 %d" % [dps(s), pack.total_cost()], 16, Color(1, 1, 1, 0.65), true))
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
	var total := 0
	for p in enemies:
		total += p.total_cost()
	content.add_child(_label("상대 팀 전체: 유닛 %d · 아이템 가치 %d (우리 예산 %d)" % [enemies.size(), total, state.budget()], 15, Color(1, 1, 1, 0.55), true))


func _add_main_actions() -> void:
	if state.phase == GameState.Phase.CAMP:
		var go := _big_button("출정 → 라운드 %d" % state.round_no, _on_depart)
		go.disabled = not state.has_team()
		action_bar.add_child(go)
	else:
		action_bar.add_child(_big_button("캠프로", _on_return_camp, false))
		var fight := _big_button("전투 시작", _on_fight)
		fight.disabled = not state.has_team() or state.used_budget() > state.budget()
		action_bar.add_child(fight)


func _add_result_panel() -> void:
	var won: bool = _result_info["won"]
	var panel := _panel(Color(0.20, 0.30, 0.18) if won else Color(0.35, 0.16, 0.14))
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(_label("승리!" if won else "패배…", 40, ACCENT if won else ENEMY))
	if won:
		box.add_child(_label("골드 +%d · 다음은 라운드 %d (예산 %d)" % [_result_info["reward"], state.round_no, state.budget()], 20, Color.WHITE, true))
	else:
		box.add_child(_label("골드 +%d · 베이스 캠프로 돌아가 정비합니다" % _result_info["reward"], 20, Color.WHITE, true))
	content.add_child(panel)
	action_bar.add_child(_big_button("다음 라운드 준비" if won else "베이스 캠프로", _on_continue))


# ── 입력 처리 ─────────────────────────────────────────

func _on_field_tapped(side: String, index: int) -> void:
	message = ""
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
	elif not pack.can_place(selected, cell):
		message = "그 자리에는 들어가지 않습니다. (회전해 보세요)"
	else:
		message = "예산이 부족합니다. (%d / %d)" % [state.used_budget(), state.budget()]
	refresh()


func _on_rotate() -> void:
	if selected != null and not state.rotate(selected):
		message = "가방 안에서 돌릴 공간이 없습니다."
	refresh()


func _on_unequip() -> void:
	if selected != null:
		state.unequip(selected)
	refresh()


func _on_merge() -> void:
	if selected != null:
		var merged := state.merge(selected)
		if merged != null:
			selected = merged
			message = "%s 합성 완료!" % merged.display_name()
	refresh()


func _on_sell() -> void:
	if selected != null and state.sell(selected):
		selected = null
	refresh()


func _on_deselect() -> void:
	selected = null
	refresh()


func _on_buy(index: int) -> void:
	state.buy(index)
	message = ""
	refresh()


func _on_reroll() -> void:
	state.reroll()
	refresh()


func _on_depart() -> void:
	if state.start_expedition():
		selected = null
		message = ""
	refresh()


func _on_return_camp() -> void:
	state.return_to_camp()
	selected = null
	message = ""
	refresh()


func _on_fight() -> void:
	_start_battle(0.0)


func _start_battle(start_time: float) -> void:
	selected = null
	message = ""
	inspect_enemy = -1
	var colors_a: Array[Color] = []
	for u in state.units:
		if not u.is_empty():
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


func _on_battle_finished(winner: String) -> void:
	if not battling:
		return
	battling = false
	var won := winner == "a"
	var reward := state.apply_result(won)
	_result_info = {"won": won, "reward": reward}
	refresh()


func _on_continue() -> void:
	_result_info = {}
	refresh()


# ── 데모 (스크린샷) ───────────────────────────────────

func _demo_arg() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("demo="):
			return a.substr(5)
	return ""


func _setup_demo(kind: String) -> void:
	state = GameState.new(7)
	state.round_no = 3
	state.inventory.clear()
	# 유닛 1: 장검+버클러(근접), 유닛 2: 투구+사과(탱커), 유닛 3: 단궁(원거리)
	var plan := [[0, "sword"], [0, "buckler"], [1, "helmet"], [1, "apple"], [2, "short_bow"]]
	for p: Array in plan:
		var item := Item.new(p[1])
		state.inventory.append(item)
		state.equip(item, p[0], state.units[p[0]].find_spot(item))
	state.inventory.append_array([Item.new("sword"), Item.new("mana_orb")])
	selected = state.inventory[0]
	if kind != "camp":
		state.start_expedition()
		selected = null
	if kind == "enemy":
		inspect_enemy = 0
	if kind == "battle":
		var at := 3.0
		for a in OS.get_cmdline_user_args():
			if a.begins_with("t="):
				at = a.substr(2).to_float()
		_start_battle(at)
	else:
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
	b.custom_minimum_size = Vector2(0, 48)
	b.add_theme_font_size_override("font_size", 18)
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


func _item_button(item: Item, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(130, 62)
	b.add_theme_font_size_override("font_size", 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = item.color().darkened(0.25)
	sb.set_corner_radius_all(8)
	if item == selected:
		sb.set_border_width_all(4)
		sb.border_color = Color.WHITE
	b.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = item.color()
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	var dis := sb.duplicate() as StyleBoxFlat
	dis.bg_color = item.color().darkened(0.7)
	b.add_theme_stylebox_override("disabled", dis)
	return b
