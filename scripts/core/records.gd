class_name Records
extends RefCounted
## 플레이 기록 (기기에 저장). 게임이 끝날 때마다 도달 라운드를 남긴다.
##   best_round: 가장 멀리 간 라운드
##   runs:       끝낸 판 수
##   last_round: 바로 전 판의 도달 라운드

const DEFAULT_PATH := "user://records.cfg"


static func load_records(path: String = DEFAULT_PATH) -> Dictionary:
	var cfg := ConfigFile.new()
	var out := {"best_round": 0, "runs": 0, "last_round": 0}
	if cfg.load(path) == OK:
		for k: String in out.keys():
			out[k] = int(cfg.get_value("records", k, 0))
	return out


## 한 판의 결과를 더하고 저장한 기록을 돌려준다.
static func submit(round_reached: int, path: String = DEFAULT_PATH) -> Dictionary:
	var rec := load_records(path)
	rec["runs"] += 1
	rec["last_round"] = round_reached
	rec["best_round"] = maxi(rec["best_round"], round_reached)
	var cfg := ConfigFile.new()
	for k: String in rec.keys():
		cfg.set_value("records", k, rec[k])
	cfg.save(path)
	return rec
