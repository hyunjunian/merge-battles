class_name DragItemCard
extends Button
## 아이템 카드 버튼. draggable 이면 끌어서 가방에 놓을 수 있다 (탭은 그대로 pressed).
## 끌기 데이터: {"type": "item", "item": Item, "from_unit": -1, "grab": Vector2i.ZERO}

var item: Item = null
var draggable: bool = false
## 끌 때 미리보기 칸 크기 (가방 칸 크기와 맞춘다)
var preview_cell: float = 40.0


func _get_drag_data(_at: Vector2) -> Variant:
	if not draggable or item == null:
		return null
	set_drag_preview(DragItemCard.make_preview(item, preview_cell, Vector2i.ZERO))
	return {"type": "item", "item": item, "from_unit": -1, "grab": Vector2i.ZERO}


## 끄는 동안 손가락 아래 보이는 아이템 모양. grab 칸이 손가락 아래에 오게 한다.
static func make_preview(p_item: Item, cell: float, grab: Vector2i) -> Control:
	var holder := Control.new()
	var icon := ShapeIcon.for_item(p_item, cell)
	icon.modulate = Color(1, 1, 1, 0.85)
	icon.position = -Vector2(grab) * cell - Vector2.ONE * cell * 0.5
	holder.add_child(icon)
	return holder
