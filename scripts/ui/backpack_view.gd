class_name BackpackView
extends Control
## 가방 그리드 그리기 + 칸 터치. 로직은 GameState 가 하고, 이 뷰는 그리기와 입력 전달만 한다.

signal cell_pressed(unit_index: int, cell: Vector2i)

var pack: Backpack
var unit_index: int = 0
var cell_size: float = 52.0
var selected: Item = null
var interactive: bool = true


func setup(p_pack: Backpack, p_unit_index: int, p_cell_size: float = 52.0, p_interactive: bool = true) -> void:
	pack = p_pack
	unit_index = p_unit_index
	cell_size = p_cell_size
	interactive = p_interactive
	custom_minimum_size = Vector2(p_pack.width, p_pack.height) * cell_size
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func cell_at(local_pos: Vector2) -> Vector2i:
	var c := Vector2i(floori(local_pos.x / cell_size), floori(local_pos.y / cell_size))
	if c.x < 0 or c.y < 0 or c.x >= pack.width or c.y >= pack.height:
		return Backpack.NO_SPOT
	return c


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var c := cell_at(mb.position)
		if c != Backpack.NO_SPOT:
			cell_pressed.emit(unit_index, c)
			accept_event()


func _draw() -> void:
	if pack == null:
		return
	var font := get_theme_default_font()
	var gap := 2.0
	for y in pack.height:
		for x in pack.width:
			var r := Rect2(Vector2(x, y) * cell_size, Vector2.ONE * cell_size).grow(-gap)
			draw_rect(r, Color(0.16, 0.14, 0.12))
			draw_rect(r, Color(0.35, 0.30, 0.24), false, 1.0)
	for p in pack.placements:
		var item: Item = p["item"]
		var pos: Vector2i = p["pos"]
		var col := item.color()
		for c in item.cells():
			var r := Rect2(Vector2(pos + c) * cell_size, Vector2.ONE * cell_size).grow(-gap)
			draw_rect(r, col)
			# 같은 아이템 칸끼리 이어 보이게 틈을 메운다
			if item.cells().has(c + Vector2i.RIGHT):
				draw_rect(Rect2(r.position + Vector2(r.size.x, 0), Vector2(gap * 2, r.size.y)), col)
			if item.cells().has(c + Vector2i.DOWN):
				draw_rect(Rect2(r.position + Vector2(0, r.size.y), Vector2(r.size.x, gap * 2)), col)
			if item.cells().has(c + Vector2i.ONE) and item.cells().has(c + Vector2i.RIGHT) and item.cells().has(c + Vector2i.DOWN):
				draw_rect(Rect2(r.position + r.size, Vector2.ONE * gap * 2), col)
		if item == selected:
			for c in item.cells():
				var r := Rect2(Vector2(pos + c) * cell_size, Vector2.ONE * cell_size).grow(-gap)
				draw_rect(r, Color.WHITE, false, 3.0)
		var origin := Vector2(pos) * cell_size + Vector2(gap + 3, gap + 2)
		var fs := int(cell_size * 0.30)
		var short_name: String = String(item.def().get("name", "?")).substr(0, 2)
		draw_string(font, origin + Vector2(0, fs), short_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
