class_name DropZone
extends PanelContainer
## 끌어 온 것을 받는 영역. accepts(data) 가 true 면 받고, 놓으면 on_drop(data).

var accepts: Callable
var on_drop: Callable


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return accepts.is_valid() and typeof(data) == TYPE_DICTIONARY and bool(accepts.call(data))


func _drop_data(_at: Vector2, data: Variant) -> void:
	if on_drop.is_valid():
		on_drop.call(data)
