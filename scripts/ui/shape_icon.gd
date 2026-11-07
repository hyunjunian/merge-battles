class_name ShapeIcon
extends Control
## 칸 모양 미리보기 (아이템 모양, 유닛 가방 크기). 상점 카드·보유 아이템 카드에 쓴다.

var cells: Array[Vector2i] = []
var grid: Vector2i = Vector2i.ONE
var color: Color = Color.WHITE
var cell: float = 14.0
## true 면 빈 칸 격자(유닛 가방), false 면 채운 칸(아이템 모양)
var outline_only: bool = false


static func for_item(item: Item, p_cell: float = 14.0) -> ShapeIcon:
	var icon := ShapeIcon.new()
	icon.cells = item.cells()
	icon.grid = item.size()
	icon.color = item.color()
	icon.cell = p_cell
	icon._fit()
	return icon


static func for_unit(size_cells: Vector2i, p_color: Color, p_cell: float = 12.0) -> ShapeIcon:
	var icon := ShapeIcon.new()
	icon.grid = size_cells
	for y in size_cells.y:
		for x in size_cells.x:
			icon.cells.append(Vector2i(x, y))
	icon.color = p_color
	icon.cell = p_cell
	icon.outline_only = true
	icon._fit()
	return icon


func _fit() -> void:
	custom_minimum_size = Vector2(grid) * cell + Vector2(2, 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var origin := (size - Vector2(grid) * cell) / 2.0
	for c in cells:
		var r := Rect2(origin + Vector2(c) * cell, Vector2.ONE * cell).grow(-1.0)
		if outline_only:
			draw_rect(r, Color(0, 0, 0, 0.35))
			draw_rect(r, color.lightened(0.2), false, 1.5)
		else:
			draw_rect(r, color)
			draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.3)), color.lightened(0.25))
			draw_rect(r, color.darkened(0.45), false, 1.5)
