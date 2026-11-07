extends "res://tests/test_case.gd"
## 예시 테스트. 새 기능을 만들면 tests/test_<기능>.gd 를 추가한다.

const Main := preload("res://scripts/main.gd")


func test_main_scene_loads() -> void:
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	check(packed != null, "메인 장면을 불러오지 못함")
	if packed == null:
		return
	var main := packed.instantiate()
	check(main.has_node("Title"), "Title 노드 없음")
	check((main.get_node("Title") as Label).text != "", "제목이 비어 있음")
	free_later(main)


func test_clamp_score() -> void:
	check_eq(Main.clamp_score(-5), 0, "음수")
	check_eq(Main.clamp_score(42), 42, "보통 값")
	check_eq(Main.clamp_score(10_000_000), 999_999, "상한")
