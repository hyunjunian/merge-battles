class_name BattleView3D
extends Control
## BattleSim.simulate() 기록을 3D 전장에서 재생한다.
## 시뮬레이션 좌표 (x, z) → 3D (x, 0, z). 우리 팀(a)은 카메라 쪽(+z), 상대(b)는 먼 쪽(-z).
## 체력바·피해 숫자는 3D 위치를 화면 좌표로 바꿔 2D 오버레이에 그린다.

signal finished(winner: String)

const SPEED := 1.25
const LUNGE_TIME := 0.25
const FLASH_TIME := 0.2
const FLOAT_TIME := 0.9
const PROJECTILE_TIME := 0.22
const TEAM_COLORS := {"a": Color(0.30, 0.65, 1.0), "b": Color(1.0, 0.35, 0.30)}

var result: Dictionary = {}
var t: float = 0.0
var done: bool = false

var _viewport: SubViewport
var _camera: Camera3D
var _world: Node3D
var _overlay: Control
var _next_event: int = 0
## side → 유닛 노드 정보 배열: {root, body, mat, base_color, facing, lunge, flash, last_target, ranged}
var _units: Dictionary = {"a": [], "b": []}
var _projectiles: Array = []  # {node, from: Vector3, to: Vector3, age}
var _floats: Array = []  # {side, idx, text, age}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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


## colors_*: 유닛마다 대표 색
func setup(p_result: Dictionary, colors_a: Array[Color], colors_b: Array[Color], start_time: float = 0.0) -> void:
	result = p_result
	t = 0.0
	done = false
	_next_event = 0
	for side: String in ["a", "b"]:
		for u: Dictionary in _units[side]:
			u["root"].queue_free()
		_units[side] = []
		var maxes: PackedFloat32Array = result["max_" + side]
		var ranged: Array = result.get("ranged_" + side, [])
		var colors := colors_a if side == "a" else colors_b
		for i in maxes.size():
			var col: Color = colors[i] if i < colors.size() else Color.GRAY
			_units[side].append(_make_unit(side, col, i < ranged.size() and bool(ranged[i])))
	_advance(start_time)


func skip() -> void:
	_advance(duration() - t + 0.01)


func duration() -> float:
	return float(result.get("duration", 0.0))


func _process(delta: float) -> void:
	if result.is_empty() or done:
		return
	_advance(delta * SPEED)


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


## 현재 시각의 위치·체력 (틱 사이를 선형 보간)
func _state(side: String, i: int) -> Dictionary:
	var frames: Array = result["frames"]
	var s := 0 if side == "a" else 1
	var ft := t / BattleSim.DT
	var f0 := clampi(floori(ft), 0, frames.size() - 1)
	var f1 := mini(f0 + 1, frames.size() - 1)
	var k := clampf(ft - f0, 0.0, 1.0)
	var p := BattleSim.frame_pos(frames[f0], s, i).lerp(BattleSim.frame_pos(frames[f1], s, i), k)
	var prev := BattleSim.frame_pos(frames[maxi(f0 - 1, 0)], s, i)
	return {
		"pos": Vector3(p.x, 0.0, p.y),
		"vel": p - prev,
		"hp": BattleSim.frame_hp(frames[f0], s, i),
	}


func _update_units() -> void:
	for side: String in ["a", "b"]:
		var foe := "b" if side == "a" else "a"
		for i in _units[side].size():
			var u: Dictionary = _units[side][i]
			var st := _state(side, i)
			var root: Node3D = u["root"]
			var pos: Vector3 = st["pos"]
			var alive: bool = st["hp"] > 0.0
			# 바라보는 방향: 마지막으로 때린 적, 없으면 움직이는 방향
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
			var body: Node3D = u["body"]
			if alive:
				var lunge := sin(PI * u["lunge"] / LUNGE_TIME) if u["lunge"] > 0.0 else 0.0
				var bob := absf(sin(t * 12.0)) * 0.08 if vel.length() > 0.02 else 0.0
				body.position = Vector3(0, bob, 0.45 * lunge)
				body.rotation.x = 0.0
			else:
				body.rotation.x = lerpf(body.rotation.x, PI / 2.0, 0.2)
				body.position = Vector3(0, 0.0, 0)
			var mat: StandardMaterial3D = u["mat"]
			var base: Color = u["base_color"] if alive else Color(0.3, 0.3, 0.3)
			mat.albedo_color = base.lerp(Color(1, 0.2, 0.2), u["flash"] / FLASH_TIME) if u["flash"] > 0.0 else base


func _spawn_projectile(side: String, src: int, foe: String, dst: int, age: float) -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.28
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.8, 0.3) if side == "a" else Color(1.0, 0.45, 0.9)
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
		if p["age"] >= PROJECTILE_TIME or done:
			node.queue_free()
			continue
		var k: float = p["age"] / PROJECTILE_TIME
		var from: Vector3 = p["from"]
		var to: Vector3 = p["to"]
		node.position = from.lerp(to, k) + Vector3(0, sin(PI * k) * 0.6, 0)
		keep.append(p)
	_projectiles = keep


# ── 2D 오버레이: 체력바, 피해 숫자, 시간 ──────────────

func _draw_overlay() -> void:
	if result.is_empty() or _camera == null:
		return
	var font := get_theme_default_font()
	for side: String in ["a", "b"]:
		var maxes: PackedFloat32Array = result["max_" + side]
		for i in maxes.size():
			var st := _state(side, i)
			if st["hp"] <= 0.0:
				continue
			var head: Vector3 = st["pos"] + Vector3(0, 2.0, 0)
			if _camera.is_position_behind(head):
				continue
			var p := _camera.unproject_position(head)
			var bar := Rect2(p - Vector2(34, 6), Vector2(68, 9))
			_overlay.draw_rect(bar.grow(1.5), Color(0, 0, 0, 0.7))
			var ratio := clampf(st["hp"] / maxes[i], 0.0, 1.0)
			_overlay.draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), TEAM_COLORS[side])
	for f: Dictionary in _floats:
		var st := _state(f["side"], f["idx"])
		var p := _camera.unproject_position(st["pos"] + Vector3(0, 2.2, 0))
		var a: float = 1.0 - f["age"] / FLOAT_TIME
		p += Vector2(14, -10 - 50.0 * f["age"])
		_overlay.draw_string_outline(font, p, f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 4, Color(0, 0, 0, a))
		_overlay.draw_string(font, p, f["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 0.85, 0.3, a))
	_overlay.draw_string_outline(font, Vector2(16, 36), "%.1f초" % t, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 4, Color(0, 0, 0, 0.6))
	_overlay.draw_string(font, Vector2(16, 36), "%.1f초" % t, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)


# ── 3D 장면 만들기 ────────────────────────────────────

func _build_world() -> void:
	_world = Node3D.new()
	_viewport.add_child(_world)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.20, 0.26)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	_world.add_child(sun)

	_camera = Camera3D.new()
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = 46.0
	_camera.position = Vector3(0, 11.0, 13.0)
	_world.add_child(_camera)
	_camera.look_at_from_position(_camera.position, Vector3(0, 0, 2.6), Vector3.UP)

	var w := BattleSim.HALF_W * 2.0
	var d := BattleSim.HALF_D * 2.0
	# 바깥 땅, 전장, 진영 표시, 가운데 선
	_add_box(Vector3(0, -0.06, 0), Vector3(w + 8, 0.1, d + 8), Color(0.22, 0.30, 0.18))
	_add_box(Vector3(0, -0.02, 0), Vector3(w + 1.0, 0.04, d + 1.0), Color(0.42, 0.36, 0.26))
	_add_box(Vector3(0, -0.005, d / 4.0 + 0.25), Vector3(w + 1.0, 0.02, d / 2.0 - 0.5), Color(0.40, 0.38, 0.30))
	_add_box(Vector3(0, -0.005, -d / 4.0 - 0.25), Vector3(w + 1.0, 0.02, d / 2.0 - 0.5), Color(0.44, 0.34, 0.26))
	_add_box(Vector3(0, 0.0, 0), Vector3(w + 1.0, 0.02, 0.08), Color(0.85, 0.80, 0.65))
	# 울타리 기둥
	for x in [-w / 2.0 - 0.6, w / 2.0 + 0.6]:
		var z := -d / 2.0 - 0.5
		while z <= d / 2.0 + 0.6:
			_add_box(Vector3(x, 0.3, z), Vector3(0.18, 0.6, 0.18), Color(0.45, 0.32, 0.20))
			z += 1.5
	# 바위 몇 개 (장식)
	var rocks := [Vector3(-6.2, 0.3, -3), Vector3(6.0, 0.25, 2.5), Vector3(-5.8, 0.2, 5.5), Vector3(6.3, 0.35, -6)]
	for r: Vector3 in rocks:
		_add_box(r, Vector3(0.9, r.y * 2.0, 0.8), Color(0.45, 0.45, 0.48))


func _add_box(pos: Vector3, box_size: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = box_size
	m.mesh = box
	m.material_override = _mat(color)
	m.position = pos
	_world.add_child(m)
	return m


func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat


## 유닛 모형: 진영 고리 + 몸통(캡슐) + 머리 + 무기
func _make_unit(side: String, color: Color, ranged: bool) -> Dictionary:
	var root := Node3D.new()
	_world.add_child(root)

	var ring := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.5
	disc.bottom_radius = 0.5
	disc.height = 0.03
	ring.mesh = disc
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = TEAM_COLORS[side]
	ring.material_override = ring_mat
	ring.position.y = 0.02
	root.add_child(ring)

	var body := Node3D.new()
	root.add_child(body)
	# 몸통은 팀 색, 모자·망토는 유닛 대표 색(가장 비싼 아이템)
	var team_body: Color = TEAM_COLORS[side].lerp(Color(0.9, 0.9, 0.9), 0.15)
	var mat := _mat(team_body)
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

	# 앞쪽(+z)을 보는 무기
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
		glow.albedo_color = Color(1.0, 0.85, 0.4)
		tip.material_override = glow
		tip.position = Vector3(0.36, 1.45, 0.15)
		body.add_child(tip)
	else:
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.08, 0.08, 0.8)
		blade.mesh = bm
		blade.material_override = _mat(Color(0.85, 0.87, 0.9))
		blade.position = Vector3(0.36, 0.7, 0.4)
		body.add_child(blade)

	return {
		"root": root, "body": body, "mat": mat, "base_color": team_body,
		"facing": 0.0 if side == "b" else PI, "lunge": 0.0, "flash": 0.0,
		"last_target": -1, "ranged": ranged,
	}
