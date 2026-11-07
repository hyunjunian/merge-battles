extends Control
## 메인 장면. 화면(베이스 캠프 / 원정 준비 / 전투)을 코드로 만들고, 상태가 바뀌면 다시 그린다.
## 게임 규칙은 scripts/core/ 에 있고, 여기서는 입력을 GameState 에 넘기고 결과를 보여 주기만 한다.
##
## 스크린샷용 데모: 실행 인자에 demo=camp | demo=prep | demo=battle 을 주면 그 장면을 미리 꾸며 보여 준다.

const BG := Color(0.11, 0.10, 0.09)
const PANEL := Color(0.18, 0.16, 0.14)
const ACCENT := Color(0.95, 0.75, 0.30)

var state: GameState
var selected: Item = null
var message: String = ""
var battle_view: BattleView3D = null
var last_result: Dictionary = {}

## 화면 제목 (테스트에서 확인한다)
@onready var title: Label = $Title
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
	return "체력 %d  공격 %.1f\n방어 %d  공속 %.2f  회복 %.1f" % [roundi(s["hp"]), s["atk"], roundi(s["armor"]), s["spd"], s["regen"]]


func _ready() -> void:
	state = GameState.new()
	var demo := _demo_arg()
	if demo != "":
		_setup_demo(demo)
	if battle_view == null:
		refresh()


# ── 화면 구성 ─────────────────────────────────────────

func refresh() -> void:
	_clear()
	battle_view = null
	if state.phase == GameState.Phase.CAMP:
		title.text = "Merge Battles · 베이스 캠프"
	else:
		title.text = "Merge Battles · 원정 라운드 %d" % state.round_no
	_add_status_row()
	_add_synergy_row()
	_add_units()
	_add_inventory()
	_add_selection_panel()
	if state.phase == GameState.Phase.CAMP:
		_add_shop()
	else:
		_add_enemy_preview()
	_add_message()
	_add_main_actions()


func _add_status_row() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.add_child(_label("골드 %d" % state.gold, 26, ACCENT))
	var over := state.used_budget() > state.budget()
	row.add_child(_label("예산 %d / %d" % [state.used_budget(), state.budget()], 26, Color.RED if over else Color.WHITE))
	row.add_child(_label("라운드 %d" % state.round_no, 26))
	if state.best_round > 0:
		row.add_child(_label("최고 %d" % state.best_round, 20, Color(1, 1, 1, 0.6)))
	content.add_child(row)


func _add_synergy_row() -> void:
	var counts := Synergy.count_tags(state.units)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	for tag in Synergy.TAG_ORDER:
		var n: int = counts.get(tag, 0)
		var active := Synergy.level(tag, n) > 0
		var chip := _panel(Color(0.35, 0.30, 0.15) if active else PANEL)
		chip.add_child(_label(Synergy.describe(tag, n), 18, ACCENT if active else Color(1, 1, 1, 0.55)))
		row.add_child(chip)
	content.add_child(row)


func _add_units() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	var bonus := Synergy.bonuses(Synergy.count_tags(state.units))
	for i in state.units.size():
		var pack := state.units[i]
		var box := VBoxContainer.new()
		box.add_child(_label("유닛 %d  (%d)" % [i + 1, pack.total_cost()], 20))
		var view := BackpackView.new()
		view.setup(pack, i, 64.0)
		view.selected = selected
		view.cell_pressed.connect(_on_cell_pressed)
		box.add_child(view)
		var info := "비어 있음\n(출전 안 함)" if pack.is_empty() else stats_line(BattleSim.unit_stats(pack, bonus))
		box.add_child(_label(info, 15, Color(1, 1, 1, 0.75)))
		row.add_child(box)
	content.add_child(row)


func _add_inventory() -> void:
	content.add_child(_label("보유 아이템 (눌러서 고르고, 가방 칸을 누르면 넣기)", 18, Color(1, 1, 1, 0.6)))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	if state.inventory.is_empty():
		flow.add_child(_label("(없음)", 18, Color(1, 1, 1, 0.4)))
	for item in state.inventory:
		var b := _item_button(item, "%s\n비용 %d" % [item.display_name(), item.cost()])
		b.pressed.connect(_on_inventory_pressed.bind(item))
		flow.add_child(b)
	content.add_child(flow)


func _add_selection_panel() -> void:
	var panel := _panel(PANEL)
	var box := VBoxContainer.new()
	panel.add_child(box)
	if selected == null:
		box.add_child(_label("아이템을 고르면 정보와 행동이 여기 나옵니다.", 18, Color(1, 1, 1, 0.5), true))
		content.add_child(panel)
		return
	var tag_name: String = Synergy.TRAITS[selected.tag()]["name"]
	var where := state.unit_of(selected)
	var place := "보유함" if where < 0 else "유닛 %d 가방" % (where + 1)
	box.add_child(_label("%s  [%s] · 비용 %d · %s" % [selected.display_name(), tag_name, selected.cost(), place], 20, ACCENT, true))
	box.add_child(_label(selected.describe(), 18, Color.WHITE, true))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	if selected.is_rotatable():
		actions.add_child(_button("회전", _on_rotate))
	if where >= 0:
		actions.add_child(_button("가방에서 빼기", _on_unequip))
	if state.phase == GameState.Phase.CAMP:
		var merge_btn := _button("합성 ★%d" % (selected.tier + 1), _on_merge)
		merge_btn.disabled = state.merge_partner(selected) == null
		actions.add_child(merge_btn)
		actions.add_child(_button("판매 +%d" % selected.sell_price(), _on_sell))
	actions.add_child(_button("선택 해제", _on_deselect))
	box.add_child(actions)
	content.add_child(panel)


func _add_shop() -> void:
	var head := HBoxContainer.new()
	head.add_child(_label("상점", 22, ACCENT))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var reroll := _button("새로고침 (%d골드)" % GameState.REROLL_COST, _on_reroll)
	reroll.disabled = state.gold < GameState.REROLL_COST
	head.add_child(reroll)
	content.add_child(head)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	for i in state.shop.size():
		var item := state.shop[i]
		var b := _item_button(item, "%s\n%d골드" % [item.display_name(), item.cost()])
		b.tooltip_text = item.describe()
		b.disabled = state.gold < item.cost()
		b.pressed.connect(_on_buy.bind(i))
		row.add_child(b)
	content.add_child(row)


func _add_enemy_preview() -> void:
	var enemies := state.enemy_team()
	var cost := 0
	for p in enemies:
		cost += p.total_cost()
	content.add_child(_label("상대 팀 · 유닛 %d · 아이템 가치 %d" % [enemies.size(), cost], 22, Color(1, 0.55, 0.5)))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	var bonus := Synergy.bonuses(Synergy.count_tags(enemies))
	for i in enemies.size():
		var box := VBoxContainer.new()
		var view := BackpackView.new()
		view.setup(enemies[i], i, 36.0, false)
		box.add_child(view)
		box.add_child(_label(stats_line(BattleSim.unit_stats(enemies[i], bonus)), 13, Color(1, 1, 1, 0.7)))
		row.add_child(box)
	content.add_child(row)


func _add_message() -> void:
	if message != "":
		content.add_child(_label(message, 20, Color(1, 0.6, 0.5), true))


func _add_main_actions() -> void:
	var row := action_bar
	if state.phase == GameState.Phase.CAMP:
		var go := _big_button("출정 → 라운드 %d" % state.round_no, _on_depart)
		go.disabled = not state.has_team()
		row.add_child(go)
	else:
		row.add_child(_big_button("캠프로 귀환", _on_return_camp, false))
		var fight := _big_button("전투 시작", _on_fight)
		fight.disabled = not state.has_team() or state.used_budget() > state.budget()
		row.add_child(fight)


func _clear() -> void:
	for box: Node in [content, action_bar]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()


func _show_battle(result: Dictionary, start_time: float = 0.0) -> void:
	_clear()
	title.text = "Merge Battles · 라운드 %d 전투" % state.round_no
	last_result = result
	battle_view = BattleView3D.new()
	battle_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battle_view.custom_minimum_size = Vector2(0, 1060)
	content.add_child(battle_view)
	var colors_a: Array[Color] = []
	for u in state.units:
		if not u.is_empty():
			colors_a.append(unit_color(u))
	var colors_b: Array[Color] = []
	for u in state.enemy_team():
		colors_b.append(unit_color(u))
	battle_view.setup(result, colors_a, colors_b, start_time)
	battle_view.finished.connect(_on_battle_finished)
	action_bar.add_child(_big_button("건너뛰기", func() -> void: battle_view.skip()))


func _show_result(won: bool, reward: int) -> void:
	for c in action_bar.get_children():
		action_bar.remove_child(c)
		c.queue_free()
	var panel := _panel(Color(0.20, 0.30, 0.18) if won else Color(0.35, 0.16, 0.14))
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	box.add_child(_label("승리!" if won else "패배…", 40, ACCENT if won else Color(1, 0.5, 0.45)))
	if won:
		box.add_child(_label("골드 +%d · 다음은 라운드 %d (예산 %d)" % [reward, state.round_no, state.budget()], 22))
		action_bar.add_child(_big_button("다음 라운드 준비", _on_continue))
	else:
		box.add_child(_label("골드 +%d · 베이스 캠프로 돌아가 정비합니다" % reward, 22))
		action_bar.add_child(_big_button("베이스 캠프로", _on_continue))
	content.add_child(panel)


# ── 입력 처리 ─────────────────────────────────────────

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
	selected = null
	message = ""
	_show_battle(state.fight())


func _on_battle_finished(winner: String) -> void:
	var won := winner == "a"
	var reward := state.apply_result(won)
	_show_result(won, reward)


func _on_continue() -> void:
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
	if kind == "prep" or kind == "battle":
		state.start_expedition()
		selected = null
	if kind == "battle":
		var at := 3.0
		for a in OS.get_cmdline_user_args():
			if a.begins_with("t="):
				at = a.substr(2).to_float()
		_show_battle(state.fight(), at)


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


func _panel(color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(on_press)
	return b


func _big_button(text: String, on_press: Callable, primary: bool = true) -> Button:
	var b := _button(text, on_press)
	b.custom_minimum_size = Vector2(0, 88)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 30)
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
	b.custom_minimum_size = Vector2(158, 72)
	b.add_theme_font_size_override("font_size", 18)
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
