class_name OpponentPool
extends RefCounted
## 상대 출전 풀: 라운드마다 실제로 출전했던 팀 세팅 모음.
## tools/build_pool.gd 가 봇 N명의 대전(PoolBuilder)으로 만들어 data/opponent_pool.json 에 저장하고,
## 사용자 게임은 k 라운드에 그 라운드 세팅 중 하나를 무작위로 상대로 쓴다.
##
## 팀 세팅(entry) = 유닛 배열. 유닛 = {"u": 유닛 id, "x", "z": 우리 팀 좌표 위치, "i": [[아이템 id, x, y, 회전 0|1], ...]}

const DEFAULT_PATH := "res://data/opponent_pool.json"

## 라운드 번호(int) → 팀 세팅 배열
var rounds: Dictionary = {}
var meta: Dictionary = {}


func add(round_no: int, entry: Array) -> void:
	if not rounds.has(round_no):
		rounds[round_no] = []
	rounds[round_no].append(entry)


func has_round(round_no: int) -> bool:
	return rounds.has(round_no) and not (rounds[round_no] as Array).is_empty()


func entry_count(round_no: int) -> int:
	return (rounds[round_no] as Array).size() if rounds.has(round_no) else 0


func max_round() -> int:
	var m := 0
	for k: int in rounds.keys():
		m = maxi(m, k)
	return m


## k 라운드 세팅 중 하나 (같은 seed·라운드면 같은 팀)
func team_for(round_no: int, seed_value: int) -> Array[Backpack]:
	if not has_round(round_no):
		return []
	var list: Array = rounds[round_no]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, round_no, "pool"])
	return build_team(list[rng.randi_range(0, list.size() - 1)])


## 유닛 목록 → 팀 세팅
static func snapshot(units: Array[Backpack]) -> Array:
	var out: Array = []
	for u in units:
		var p := u.start_pos("a")
		var items: Array = []
		for pl in u.placements:
			var it: Item = pl["item"]
			var pos: Vector2i = pl["pos"]
			items.append([it.def_id, pos.x, pos.y, 1 if it.rotated else 0])
		out.append({"u": u.def_id, "x": snappedf(p.x, 0.01), "z": snappedf(p.y, 0.01), "i": items})
	return out


## 팀 세팅 → 유닛 목록 (상대로 쓸 때는 start_pos("b") 가 좌표를 뒤집는다)
static func build_team(entry: Array) -> Array[Backpack]:
	var out: Array[Backpack] = []
	for i in entry.size():
		var d: Dictionary = entry[i]
		var pack := Backpack.new(String(d["u"]))
		pack.slot = i
		pack.field_pos = Vector2(float(d["x"]), float(d["z"]))
		pack.has_field_pos = true
		for e: Array in d.get("i", []):
			var item := Item.new(String(e[0]))
			item.rotated = int(e[3]) == 1
			pack.place(item, Vector2i(int(e[1]), int(e[2])))
		out.append(pack)
	return out


func to_dict() -> Dictionary:
	var r := {}
	for k: int in rounds.keys():
		r[str(k)] = rounds[k]
	return {"meta": meta, "rounds": r}


static func from_dict(d: Dictionary) -> OpponentPool:
	var pool := OpponentPool.new()
	pool.meta = d.get("meta", {})
	var r: Dictionary = d.get("rounds", {})
	for k: String in r.keys():
		pool.rounds[k.to_int()] = r[k]
	return pool


func save_file(path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict()))
	return OK


## 파일이 없거나 깨졌으면 null
static func load_file(path: String = DEFAULT_PATH) -> OpponentPool:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return from_dict(parsed)
