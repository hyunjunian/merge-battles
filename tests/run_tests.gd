extends SceneTree
## 헤드리스 테스트 실행기 (애드온 없이 동작).
##   godot --headless --path . -s res://tests/run_tests.gd
## tests/ 의 test_*.gd 파일마다 test_* 메서드를 새 인스턴스에서 실행한다. 실패가 있으면 종료 코드 1.


func _initialize() -> void:
	quit(run_all())


func run_all() -> int:
	var dir := DirAccess.open("res://tests")
	if dir == null:
		printerr("✗ res://tests 를 열 수 없음")
		return 1
	var files := Array(dir.get_files()).filter(func(f: String) -> bool: return f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd")
	files.sort()
	var passed := 0
	var failed := 0
	for f: String in files:
		var script := load("res://tests/" + f) as GDScript
		if script == null or not script.can_instantiate():
			printerr("✗ %s: 스크립트를 불러오지 못함(문법 오류?)" % f)
			failed += 1
			continue
		for m: Dictionary in script.get_script_method_list():
			var method: String = m["name"]
			if not method.begins_with("test_"):
				continue
			var instance: Object = script.new()
			instance.call(method)
			var failures: Array = instance.get("failures")
			if failures.is_empty():
				passed += 1
				print("  ✓ %s::%s" % [f, method])
			else:
				failed += 1
				print("  ✗ %s::%s" % [f, method])
				for msg: String in failures:
					print("      - " + msg)
	print("테스트: 통과 %d, 실패 %d" % [passed, failed])
	if passed + failed == 0:
		printerr("✗ 실행된 테스트가 없음")
		return 1
	return 1 if failed > 0 else 0
