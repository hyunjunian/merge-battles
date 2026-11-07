extends RefCounted
## 테스트 기본 클래스. 테스트 파일은 `extends "res://tests/test_case.gd"` 로 시작하고
## `test_` 로 시작하는 메서드를 둔다. 각 메서드는 새 인스턴스에서 실행된다.

var failures: Array[String] = []


func check(condition: bool, message: String = "조건이 거짓") -> void:
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	var numeric := [TYPE_INT, TYPE_FLOAT]
	var same: bool
	if typeof(actual) in numeric and typeof(expected) in numeric:
		same = is_equal_approx(float(actual), float(expected))
	else:
		same = typeof(actual) == typeof(expected) and actual == expected
	if not same:
		var prefix := (message + ": ") if message != "" else ""
		failures.append("%s기대 %s, 실제 %s" % [prefix, var_to_str(expected), var_to_str(actual)])


## 테스트가 만든 노드를 정리할 때 쓴다.
func free_later(node: Node) -> void:
	if is_instance_valid(node):
		node.free()
