extends "res://tests/test_case.gd"
## 운과 실력 측정 도구


func test_eta_squared() -> void:
	var same := {"a": [1.0, 0.0, 1.0, 0.0] as Array[float], "b": [1.0, 0.0, 1.0, 0.0] as Array[float]}
	check_eq(SkillMeter.eta_squared(same), 0.0, "정책 차이 없음 → 실력 몫 0")
	var split := {"a": [1.0, 1.0, 1.0] as Array[float], "b": [0.0, 0.0, 0.0] as Array[float]}
	check_eq(SkillMeter.eta_squared(split), 1.0, "정책이 결과를 다 가름 → 1")


func test_runs_and_report() -> void:
	var pool := PoolBuilder.build(4, 9)
	var rep := SkillMeter.measure(2, 3, pool, 6)
	check(not rep["brackets"].is_empty(), "구간별 결과")
	var b: Dictionary = rep["brackets"][0]
	check(float(b["skill"]) >= 0.0 and float(b["skill"]) <= 1.0)
	check(SkillMeter.format_report(rep).contains("실력 몫"))
	var run := SkillMeter.play_run("random", 5, pool, 3)
	check(run.size() <= 3 and not run.is_empty(), "최대 라운드까지만")
