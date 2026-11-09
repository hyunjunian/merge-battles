extends SceneTree
## 운과 실력의 비율 측정: 실력이 다른 정책(무작위 / 기본 봇)이 같은 시드들로 한 판씩 끝까지 싸운다.
##   godot --headless --path . -s res://tools/measure_skill.gd -- [판 수] [seed]
## 결과: 표를 출력하고 build/skill_report.md 에 저장


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var n := args[0].to_int() if args.size() > 0 else 60
	var seed_value := args[1].to_int() if args.size() > 1 else 1
	var pool := OpponentPool.load_file()
	if pool == null:
		printerr("✗ 출전 풀이 없습니다 (tools/build_pool.gd)")
		quit(1)
		return
	var t0 := Time.get_ticks_msec()
	var rep := SkillMeter.measure(n, seed_value, pool)
	var text := "# 운과 실력 측정 (정책별 %d판, seed %d)\n\n%s\n" % [n, seed_value, SkillMeter.format_report(rep)]
	print(text)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	var f := FileAccess.open("res://build/skill_report.md", FileAccess.WRITE)
	if f != null:
		f.store_string(text)
	print("✓ build/skill_report.md (%.1f초)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)
