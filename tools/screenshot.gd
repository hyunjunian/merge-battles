extends SceneTree
## 장면을 몇 프레임 실행한 뒤 화면을 PNG 로 저장한다. tools/screenshot.sh 가 xvfb 위에서 실행한다.
##   godot --path . --rendering-driver opengl3 -s res://tools/screenshot.gd -- <출력.png> [장면] [프레임 수]

var out_path := ""
var frames_left := 30


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out_path = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://build/screenshots/main.png")
	var scene_path: String = args[1] if args.size() > 1 and args[1] != "" else ProjectSettings.get_setting("application/run/main_scene")
	if args.size() > 2:
		frames_left = maxi(1, args[2].to_int())
	var packed := load(scene_path) as PackedScene
	if packed == null:
		printerr("✗ 장면을 불러오지 못함: " + scene_path)
		quit(1)
		return
	root.add_child(packed.instantiate())


func _process(_delta: float) -> bool:
	frames_left -= 1
	if frames_left > 0:
		return false
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		printerr("✗ 화면을 읽지 못함 (디스플레이·렌더러 확인)")
		quit(1)
		return true
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var err := image.save_png(out_path)
	if err != OK:
		printerr("✗ PNG 저장 실패: %s (%s)" % [out_path, error_string(err)])
		quit(1)
	else:
		print("✓ " + out_path)
		quit(0)
	return true
