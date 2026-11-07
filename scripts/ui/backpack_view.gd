class_name BackpackView
extends Control
## 가방 그리드 그리기 + 칸 터치. 로직은 GameState 가 하고, 이 뷰는 그리기와 입력 전달만 한다.

signal cell_pressed(unit_index: int, cell: Vector2i)
## 아이템을 끌어 이 가방의 anchor 칸(모양의 왼쪽 위)에 놓았다
signal item_dropped(unit_index: int, item: Item, anchor: Vector2i)

var pack: Backpack
var unit_index: int = 0
var cell_size: float = 52.0
var selected: Item = null
var interactive: bool = true
## 끌어 온 아이템을 anchor 에 놓을 수 있는가: func(item: Item, anchor: Vector2i) -> bool
var drop_check: Callable
var _hover: Dictionary = {}  # 끄는 중 미리보기 {item, anchor, ok}
var _press_cell: Vector2i = Backpack.NO_SPOT


func setup(p_pack: Backpack, p_unit_index: int, p_cell_size: float = 52.0, p_interactive: bool = true) -> void:
	pack = p_pack
	unit_index = p_unit_index
	cell_size = p_cell_size
	interactive = p_interactive
	custom_minimum_size = Vector2(p_pack.width, p_pack.height) * cell_size
	# 보기 전용(interactive=false)이어도 칸 탭은 받는다 (아이템 정보 보기용)
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func cell_at(local_pos: Vector2) -> Vector2i:
	var c := Vector2i(floori(local_pos.x / cell_size), floori(local_pos.y / cell_size))
	if c.x < 0 or c.y < 0 or c.x >= pack.width or c.y >= pack.height:
		return Backpack.NO_SPOT
	return c


## 탭은 뗄 때 보낸다 (누른 채 끌면 드래그가 되고 탭은 없다)
func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var c := cell_at(mb.position)
	if mb.pressed:
		_press_cell = c
		accept_event()
	elif c != Backpack.NO_SPOT and c == _press_cell:
		_press_cell = Backpack.NO_SPOT
		cell_pressed.emit(unit_index, c)
		accept_event()


## 가방 속 아이템 끌기 (편성 가능할 때만)
func _get_drag_data(at: Vector2) -> Variant:
	if not interactive or pack == null:
		return null
	var c := cell_at(at)
	var it := pack.item_at(c) if c != Backpack.NO_SPOT else null
	if it == null:
		return null
	_press_cell = Backpack.NO_SPOT
	var grab := c - pack.position_of(it)
	set_drag_preview(DragItemCard.make_preview(it, cell_size, grab))
	return {"type": "item", "item": it, "from_unit": unit_index, "grab": grab}


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if not interactive or typeof(data) != TYPE_DICTIONARY or data.get("type", "") != "item":
		_set_hover({})
		return false
	var it: Item = data["item"]
	var anchor := Vector2i(floori(at.x / cell_size), floori(at.y / cell_size)) - Vector2i(data.get("grab", Vector2i.ZERO))
	var ok := drop_check.is_valid() and bool(drop_check.call(it, anchor))
	_set_hover({"item": it, "anchor": anchor, "ok": ok})
	return ok


func _drop_data(_at: Vector2, data: Variant) -> void:
	var anchor: Vector2i = _hover.get("anchor", Backpack.NO_SPOT)
	_set_hover({})
	item_dropped.emit(unit_index, data["item"], anchor)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
		_set_hover({})


func _set_hover(h: Dictionary) -> void:
	if h == _hover:
		return
	_hover = h
	queue_redraw()


func _draw() -> void:
	if pack == null:
		return
	var font := UiStyle.bold()
	var gap := 2.5
	var frame := Rect2(Vector2.ZERO, Vector2(pack.width, pack.height) * cell_size).grow(3.0)
	draw_style_box(UiStyle.box(Color(0.03, 0.04, 0.07), Color(0.35, 0.28, 0.16), 2, 8, -1, 0.0), frame)
	for y in pack.height:
		for x in pack.width:
			var r := Rect2(Vector2(x, y) * cell_size, Vector2.ONE * cell_size).grow(-gap)
			draw_style_box(UiStyle.box(Color(0.13, 0.11, 0.09), Color(0.30, 0.25, 0.18), 1, 5, -1, 0.0), r)
	for p in pack.placements:
		var item: Item = p["item"]
		var pos: Vector2i = p["pos"]
		var col := item.color()
		var cells := item.cells()
		for c in cells:
			var r := Rect2(Vector2(pos + c) * cell_size, Vector2.ONE * cell_size).grow(-gap)
			draw_rect(r, col)
			# 같은 아이템 칸끼리 이어 보이게 틈을 메운다
			if cells.has(c + Vector2i.RIGHT):
				draw_rect(Rect2(r.position + Vector2(r.size.x, 0), Vector2(gap * 2, r.size.y)), col)
			if cells.has(c + Vector2i.DOWN):
				draw_rect(Rect2(r.position + Vector2(0, r.size.y), Vector2(r.size.x, gap * 2)), col)
			if cells.has(c + Vector2i.ONE) and cells.has(c + Vector2i.RIGHT) and cells.has(c + Vector2i.DOWN):
				draw_rect(Rect2(r.position + r.size, Vector2.ONE * gap * 2), col)
		# 아이템 외곽선과 윗면 광택
		var bounds := Rect2(Vector2(pos) * cell_size, Vector2(item.size()) * cell_size).grow(-gap)
		draw_rect(Rect2(bounds.position, Vector2(bounds.size.x, minf(8.0, bounds.size.y * 0.15))), Color(1, 1, 1, 0.18))
		var border := Color.WHITE if item == selected else col.darkened(0.5)
		for c in cells:
			var r := Rect2(Vector2(pos + c) * cell_size, Vector2.ONE * cell_size).grow(-gap)
			if not cells.has(c + Vector2i.UP):
				draw_line(r.position, r.position + Vector2(r.size.x, 0), border, 2.5 if item == selected else 2.0)
			if not cells.has(c + Vector2i.DOWN):
				draw_line(r.position + Vector2(0, r.size.y), r.end, border, 2.5 if item == selected else 2.0)
			if not cells.has(c + Vector2i.LEFT):
				draw_line(r.position, r.position + Vector2(0, r.size.y), border, 2.5 if item == selected else 2.0)
			if not cells.has(c + Vector2i.RIGHT):
				draw_line(r.position + Vector2(r.size.x, 0), r.end, border, 2.5 if item == selected else 2.0)
		var fs := int(cell_size * 0.28)
		var origin := Vector2(pos) * cell_size + Vector2(gap + 4, gap + 4 + fs)
		var short_name: String = item.display_name().substr(0, 2)
		draw_string_outline(font, origin, short_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.7))
		draw_string(font, origin, short_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		if item.has_skill():
			# 스킬 아이템: 오른쪽 위 금색 별
			var star_c := Vector2(pos + Vector2i(item.size().x, 0)) * cell_size + Vector2(-gap - 9, gap + 9)
			var pts := PackedVector2Array()
			for k in 10:
				var r := 7.0 if k % 2 == 0 else 3.0
				pts.append(star_c + Vector2.from_angle(-PI / 2 + k * PI / 5) * r)
			draw_colored_polygon(pts, UiStyle.GOLD)
			draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.6), 1.2, true)
	# 끄는 중: 놓일 자리 미리보기 (초록 = 들어감, 빨강 = 안 들어감)
	if not _hover.is_empty():
		var it: Item = _hover["item"]
		var col := Color(0.35, 0.95, 0.45, 0.45) if _hover["ok"] else Color(1.0, 0.3, 0.3, 0.4)
		for c in it.cells():
			var cell: Vector2i = _hover["anchor"] + c
			if cell.x < 0 or cell.y < 0 or cell.x >= pack.width or cell.y >= pack.height:
				continue
			var r := Rect2(Vector2(cell) * cell_size, Vector2.ONE * cell_size).grow(-gap)
			draw_rect(r, col)
			draw_rect(r, Color(col, 0.9), false, 2.0)
