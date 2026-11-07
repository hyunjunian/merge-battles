class_name BattleView3D
extends Control
## 항상 떠 있는 3D 전장.
## - 미리보기(show_preview): 우리 유닛 자리와 다음 상대가 시작 위치에 서 있다. 탭하면 unit_tapped.
## - 재생(play): BattleSim.simulate() 기록을 재생한다. 끝나면 finished.
## 시뮬레이션 좌표 (x, z) → 3D (x, 0, z). 우리 팀(a)은 카메라 쪽(+z), 상대(b)는 먼 쪽(-z).
## 체력바·이름·피해 숫자는 3D 위치를 화면 좌표로 바꿔 2D 오버레이에 그린다.

signal finished(winner: String)
signal unit_tapped(side: String, index: int)

const SPEED := 1.25
const LUNGE_TIME := 0.25
const FLASH_TIME := 0.2
const FLOAT_TIME := 0.9
const PROJECTILE_TIME := 0.22
const PICK_RADIUS := 60.0
const TEAM_COLORS := {"a": Color(0.25, 0.55, 0.95), "b": Color(0.92, 0.30, 0.26)}

## 카메라 구도 (720x1280 기준으로 전장 네 모서리를 투영해 고른 값).
## FULL: 전장이 위 HUD(~150px) 아래부터 아래 버튼(~1160px) 위까지 꽉 차게.
## COMPACT: 아래 시트가 열려 있을 때 전장이 HUD 아래 ~ 시트 위(~590px)에 들어오게.
const CAM_LOOK := Vector3(0, 0, 0)
const CAM_DIR := Vector3(0, 0.9397, 0.3420)  # 바라보는 점에서 카메라 쪽 방향 (70도 내려다봄)
const CAM_FULL := {"dist": 16.5, "v_offset": -0.25}
const CAM_COMPACT := {"dist": 30.0, "v_offset": -8.75}
const CAM_LERP := 8.0

enum Mode { PREVIEW, PLAYING }

var mode: Mode = Mode.PREVIEW
var result: Dictionary = {}
var t: float = 0.0
var done: bool = false
## 미리보기에서 강조할 유닛: {"side": "a"|"b", "index": int} 또는 빈 사전
var highlight: Dictionary = {}
## 0 = FULL, 1 = COMPACT (set_compact 로 바꾸면 부드럽게 옮겨 간다)
var framing: float = 0.0
var _framing_target: float = 0.0
## 오버레이에 그리는 시간 표시의 위치 (위 HUD 아래)
var info_top: float = 150.0

var _viewport: SubViewport
var _camera: Camera3D
var _world: Node3D
var _overlay: Control
var _next_event: int = 0
## side → 유닛 정보 배열: {root, body, ring, mat, ring_mat, base_color, facing, lunge, flash, last_target, empty, label, pos}
var _units: Dictionary = {"a": [], "b": []}
var _projectiles: Array = []  # {node, from: Vector3, to: Vector3, age}
var _floats: Array = []  # {side, idx, text, age}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	container.add_child(_viewport)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_build_world()


## 미리보기 명단 항목: {"pos": Vector2, "color": Color, "ranged": bool, "empty": bool, "label": String}
func show_preview(ours: Array[Dictionary], enemies: Array[Dictionary]) -> void:
	mode = Mode.PREVIEW
	result = {}
	done = false
	_clear_units()
	for side: String in ["a", "b"]:
		for e: Dictionary in (ours if side == "a" else enemies):
			var u := _make_unit(side, e.get("color", Color.GRAY), e.get("ranged", false), e.get("empty", false))
			u["label"] = e.get("label", "")
			var p: Vector2 = e["pos"]
			u["pos"] = Vector3(p.x, 0, p.y)
			_units[side].append(u)
	_update_units()
	_overlay.queue_redraw()


## colors_*: 전투에 나가는 유닛마다 대표 색 (result 의 유닛 순서)
func play(p_result: Dictionary, colors_a: Array[Color], colors_b: Array[Color], start_time: float = 0.0) -> void:
	mode = Mode.PLAYING
	result = p_result
	t = 0.0
	done = false
	_next_event = 0
	highlight = {}
	_clear_units()
	for side: String in ["a", "b"]:
		var maxes: PackedFloat32Array = result["max_" + side]
		var ranged: Array = result.get("ranged_" + side, [])
		var colors := colors_a if side == "a" else colors_b
		for i in maxes.size():
			var col: Color = colors[i] if i < colors.size() else Color.GRAY
			_units[side].append(_make_unit(side, col, i < ranged.size() and bool(ranged[i]), false))
	_advance(start_time)


func skip() -> void:
	if mode == Mode.PLAYING:
		_advance(duration() - t + 0.01)


func duration() -> float:
	return float(result.get("duration", 0.0))


func unit_count(side: String) -> int:
	return _units[side].size()


func set_highlight(side: String, index: int) -> void:
	highlight = {"side": side, "index": index} if index >= 0 else {}
	_update_units()
	_overlay.queue_redraw()


## 화면 좌표 → 가장 가까운 유닛 {side, index}. 없으면 빈 사전.
func pick(screen_pos: Vector2) -> Dictionary:
	var best := {}
	var best_d := PICK_RADIUS
	for side: String in ["a", "b"]:
		for i in _units[side].size():
			var u: Dictionary = _units[side][i]
			var root: Node3D = u["root"]
			var p := _camera.unproject_position(root.position + Vector3(0, 0.9, 0))
			var d := p.distance_to(screen_pos)
			if d < best_d:
				best_d = d
				best = {"side": side, "index": i}
	return best


## 유닛 발밑의 화면 좌표 (테스트·탭 안내용)
func screen_position(side: String, index: int) -> Vector2:
	var root: Node3D = _units[side][index]["root"]
	return _camera.unproject_position(root.position + Vector3(0, 0.7, 0))


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT or mode != Mode.PREVIEW:
		return
	var hit := pick(mb.position)
	if not hit.is_empty():
		unit_tapped.emit(hit["side"], hit["index"])
		accept_event()


func set_compact(compact: bool, animate: bool = true) -> void:
	_framing_target = 1.0 if compact else 0.0
	if not animate:
		framing = _framing_target
	_apply_camera()


func _apply_camera() -> void:
	var dist := lerpf(CAM_FULL["dist"], CAM_COMPACT["dist"], framing)
	_camera.look_at_from_position(CAM_LOOK + CAM_DIR.normalized() * dist, CAM_LOOK, Vector3.UP)
	_camera.v_offset = lerpf(CAM_FULL["v_offset"], CAM_COMPACT["v_offset"], framing)
	_overlay.queue_redraw()


func _process(delta: float) -> void:
	if not is_equal_approx(framing, _framing_target):
		framing = move_toward(framing, _framing_target, delta * CAM_LERP * maxf(0.15, absf(_framing_target - framing)))
		if absf(framing - _framing_target) < 0.002:
			framing = _framing_target
		_apply_camera()
	if mode == Mode.PLAYING and not done:
		_advance(delta * SPEED)
	elif mode == Mode.PREVIEW:
		_idle()


# ── 미리보기 ──────────────────────────────────────────

func _idle() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for side: String in ["a", "b"]:
		for i in _units[side].size():
			var body: Node3D = _units[side][i]["body"]
			body.position.y = absf(sin(now * 2.0 + i * 1.3 + (0.0 if side == "a" else 0.7))) * 0.05


# ── 재생 ──────────────────────────────────────────────

func _advance(dt: float) -> void:
	t = minf(t + dt, duration())
	for side: String in ["a", "b"]:
		for u: Dictionary in _units[side]:
			u["lunge"] = maxf(0.0, u["lunge"] - dt)
			u["flash"] = maxf(0.0, u["flash"] - dt)
	for f: Dictionary in _floats:
		f["age"] += dt
	_floats = _floats.filter(func(f: Dictionary) -> bool: return f["age"] < FLOAT_TIME)
	_consume_events()
	_update_units()
	_update_projectiles(dt)
	_overlay.queue_redraw()
	if t >= duration() and not done:
		done = true
		finished.emit(result.get("winner", "b"))


func _consume_events() -> void:
	var events: Array = result.get("events", [])
	while _next_event < events.size() and float(events[_next_event]["t"]) <= t:
		var e: Dictionary = events[_next_event]
		var side: String = e["side"]
		var foe := "b" if side == "a" else "a"
		var src: Dictionary = _units[side][e["src"]]
		var age := t - float(e["t"])
		src["last_target"] = int(e["dst"])
		if e.get("ranged", false):
			_spawn_projectile(side, int(e["src"]), foe, int(e["dst"]), age)
		else:
			src["lunge"] = maxf(0.0, LUNGE_TIME - age)
		var dst: Dictionary = _units[foe][e["dst"]]
		dst["flash"] = maxf(0.0, FLASH_TIME - age)
		_floats.append({"side": foe, "idx": e["dst"], "text": "-%d" % roundi(e["dmg"]), "age": age})
		_next_event += 1


## 현재 위치·체력. 재생 중이면 기록을 틱 사이 선형 보간, 미리보기면 고정 위치.
func _state(side: String, i: int) -> Dictionary:
	if mode == Mode.PREVIEW:
		return {"pos": _units[side][i]["pos"], "vel": Vector2.ZERO, "hp": 1.0}
	var frames: Array = result["frames"]
	var s := 0 if side == "a" else 1
	var ft := t / BattleSim.DT
	var f0 := clampi(floori(ft), 0, frames.size() - 1)
	var f1 := mini(f0 + 1, frames.size() - 1)
	var k := clampf(ft - f0, 0.0, 1.0)
	var p := BattleSim.frame_pos(frames[f0], s, i).lerp(BattleSim.frame_pos(frames[f1], s, i), k)
	var prev := BattleSim.frame_pos(frames[maxi(f0 - 1, 0)], s, i)
	return {"pos": Vector3(p.x, 0.0, p.y), "vel": p - prev, "hp": BattleSim.frame_hp(frames[f0], s, i)}


func _update_units() -> void:
	for side: String in ["a", "b"]:
		var foe := "b" if side == "a" else "a"
		for i in _units[side].size():
			var u: Dictionary = _units[side][i]
			var st := _state(side, i)
			var root: Node3D = u["root"]
			var pos: Vector3 = st["pos"]
			var alive: bool = st["hp"] > 0.0
			var look := Vector3.ZERO
			if u["last_target"] >= 0 and u["last_target"] < _units[foe].size():
				look = _state(foe, u["last_target"])["pos"] - pos
			var vel: Vector2 = st["vel"]
			if vel.length() > 0.02:
				look = Vector3(vel.x, 0, vel.y)
			if look.length() > 0.01:
				u["facing"] = lerp_angle(u["facing"], atan2(look.x, look.z), 0.25)
			root.position = pos
			root.rotation.y = u["facing"]
			var lit: bool = not highlight.is_empty() and highlight["side"] == side and highlight["index"] == i
			var ring: MeshInstance3D = u["ring"]
			ring.scale = Vector3.ONE * (1.4 if lit else 1.0)
			var ring_col: Color = TEAM_COLORS[side]
			if u["empty"]:
				ring_col.a = 0.35
			(u["ring_mat"] as StandardMaterial3D).albedo_color = Color(1.0, 0.8, 0.1) if lit else ring_col
			if u["empty"]:
				continue
			var body: Node3D = u["body"]
			if mode == Mode.PLAYING:
				if alive:
					var lunge := sin(PI * u["lunge"] / LUNGE_TIME) if u["lunge"] > 0.0 else 0.0
					var bob := absf(sin(t * 12.0)) * 0.08 if vel.length() > 0.02 else 0.0
					body.position = Vector3(0, bob, 0.45 * lunge)
					body.rotation.x = 0.0
				else:
					body.rotation.x = lerpf(body.rotation.x, PI / 2.0, 0.2)
					body.position = Vector3.ZERO
			var mat: StandardMaterial3D = u["mat"]
			var base: Color = u["base_color"] if alive else Color(0.5, 0.5, 0.5)
			mat.albedo_color = base.lerp(Color(1, 0.2, 0.2), u["flash"] / FLASH_TIME) if u["flash"] > 0.0 else base


func _spawn_projectile(side: String, src: int, foe: String, dst: int, age: float) -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.28
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.7, 0.1) if side == "a" else Color(0.85, 0.2, 0.8)
	mesh.material_override = mat
	_world.add_child(mesh)
	var from: Vector3 = _state(side, src)["pos"] + Vector3(0, 1.1, 0)
	var to: Vector3 = _state(foe, dst)["pos"] + Vector3(0, 0.8, 0)
	_projectiles.append({"node": mesh, "from": from, "to": to, "age": age})
	_update_projectiles(0.0)


func _update_projectiles(dt: float) -> void:
	var keep: Array = []
	for p: Dictionary in _projectiles:
		p["age"] += dt
		var node: MeshInstance3D = p["node"]
		if p["age"] >= PROJECTILE_TIME or done or mode != Mode.PLAYING:
			node.queue_free()
			continue
		var k: float = p["age"] / PROJECTILE_TIME
		var from: Vector3 = p["from"]
		var to: Vector3 = p["to"]
		node.position = from.lerp(to, k) + Vector3(0, sin(PI * k) * 0.6, 0)
		keep.append(p)
	_projectiles = keep


func _clear_units() -> void:
	for side: String in ["a", "b"]:
		for u: Dictionary in _units[side]:
			(u["root"] as Node).queue_free()
		_units[side] = []
	for p: Dictionary in _projectiles:
		(p["node"] as Node).queue_free()
	_projectiles = []
	_floats = []


# ── 2D 오버레이: 이름, 체력바, 피해 숫자, 시간 ────────

func _draw_overlay() -> void:
	if _camera == null:
		return
	var font := get_theme_default_font()
	for side: String in ["a", "b"]:
		for i in _units[side].size():
			var u: Dictionary = _units[side][i]
			var st := _state(side, i)
			if mode == Mode.PREVIEW:
				var foot := _camera.unproject_position(st["pos"])
				var col := Color(0.15, 0.15, 0.2) if not u["empty"] else Color(0.45, 0.45, 0.5)
				_overlay.draw_string(font, foot + Vector2(-50, 34), u["label"], HORIZONTAL_ALIGNMENT_CENTER, 100, 17, col)
				if u["empty"]:
					_overlay.draw_string(font, foot + Vector2(-50, 52), "빈자리", HORIZONTAL_ALIGNMENT_CENTER, 100, 14, col)
				continue
			if st["hp"] <= 0.0:
				continue
			var head: Vector3 = st["pos"] + Vector3(0, 2.5, 0)
			if _camera.is_position_behind(head):
				continue
			var p := _camera.unproject_position(head)
			var maxes: PackedFloat32Array = result["max_" + side]
			var bar := Rect2(p - Vector2(30, 6), Vector2(60, 8))
			_overlay.draw_rect(bar.grow(1.5), Color(0, 0, 0, 0.75))
			var ratio := clampf(st["hp"] / maxes[i], 0.0, 1.0)
			_overlay.draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), TEAM_COLORS[side])
	for f: Dictionary in _floats:
		var st := _state(f["side"], f["idx"])
		var p := _camera.unproject_position(st["pos"] + Vector3(0, 2.2, 0))
		var a: float = 1.0 - f["age"] / FLOAT_TIME
		p += Vector2(14, -10 - 50.0 * f["age"])
		_overlay.draw_string_outline(font, p, f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 4, Color(0, 0, 0, a))
		_overlay.draw_string(font, p, f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 0.85, 0.3, a))
	if mode == Mode.PLAYING:
		_overlay.draw_string(font, Vector2(0, info_top + 26), "%.1f초" % t, HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color(0.2, 0.2, 0.25))


# ── 3D 장면 ───────────────────────────────────────────

func _build_world() -> void:
	_world = Node3D.new()
	_viewport.add_child(_world)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.86, 0.87, 0.89)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -25, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	_world.add_child(sun)

	_camera = Camera3D.new()
	# 세로 화면이므로 가로 시야각을 고정한다 (전장 폭이 화면 폭에 맞게)
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = 40.0
	_world.add_child(_camera)
	_apply_camera()

	# 흰 바닥 (전장 크기)
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(BattleSim.HALF_W * 2.0 + 1.6, 0.1, BattleSim.HALF_D * 2.0 + 1.6)
	floor_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.roughness = 1.0
	floor_mesh.material_override = mat
	floor_mesh.position.y = -0.05
	_world.add_child(floor_mesh)


func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat


## 유닛 모형: 진영 고리 + 몸통(팀 색) + 머리 + 모자·망토(유닛 색) + 무기. empty 면 고리만.
func _make_unit(side: String, color: Color, ranged: bool, empty: bool) -> Dictionary:
	var root := Node3D.new()
	root.scale = Vector3.ONE * 1.3
	_world.add_child(root)

	var ring := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.5
	disc.bottom_radius = 0.5
	disc.height = 0.03
	ring.mesh = disc
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = TEAM_COLORS[side]
	ring.material_override = ring_mat
	ring.position.y = 0.02
	root.add_child(ring)

	var body := Node3D.new()
	root.add_child(body)
	var team_body: Color = TEAM_COLORS[side].lerp(Color.WHITE, 0.15)
	var mat := _mat(team_body)
	var info := {
		"root": root, "body": body, "ring": ring, "mat": mat, "ring_mat": ring_mat, "base_color": team_body,
		"facing": 0.0 if side == "b" else PI, "lunge": 0.0, "flash": 0.0,
		"last_target": -1, "empty": empty, "label": "", "pos": Vector3.ZERO,
	}
	if empty:
		return info

	var torso := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.1
	torso.mesh = capsule
	torso.material_override = mat
	torso.position.y = 0.6
	body.add_child(torso)

	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	head.mesh = sphere
	head.material_override = _mat(Color(0.95, 0.82, 0.68))
	head.position.y = 1.32
	body.add_child(head)

	var hat := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.26
	cone.height = 0.36
	hat.mesh = cone
	hat.material_override = _mat(color)
	hat.position.y = 1.6
	body.add_child(hat)

	var cape := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.5, 0.75, 0.05)
	cape.mesh = cm
	cape.material_override = _mat(color.darkened(0.15))
	cape.position = Vector3(0, 0.75, -0.3)
	body.add_child(cape)

	if ranged:
		var staff := MeshInstance3D.new()
		var stick := CylinderMesh.new()
		stick.top_radius = 0.04
		stick.bottom_radius = 0.04
		stick.height = 1.3
		staff.mesh = stick
		staff.material_override = _mat(Color(0.45, 0.30, 0.18))
		staff.position = Vector3(0.36, 0.75, 0.15)
		body.add_child(staff)
		var tip := MeshInstance3D.new()
		var gem := SphereMesh.new()
		gem.radius = 0.11
		gem.height = 0.22
		tip.mesh = gem
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.albedo_color = Color(1.0, 0.75, 0.2)
		tip.material_override = glow
		tip.position = Vector3(0.36, 1.45, 0.15)
		body.add_child(tip)
	else:
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.08, 0.08, 0.8)
		blade.mesh = bm
		blade.material_override = _mat(Color(0.55, 0.57, 0.62))
		blade.position = Vector3(0.36, 0.7, 0.4)
		body.add_child(blade)
	return info
