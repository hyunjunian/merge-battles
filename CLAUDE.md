# Merge Battles

Godot 4.7.2.stable · GDScript 게임 프로젝트. Claude Code 클라우드 세션(claude.ai/code)에서 개발한다.

## 환경
- `godot`은 클라우드 환경의 **설정 스크립트**가 세션마다 `/usr/local/bin/godot`에 설치한다. 버전은 `.godot-version`과 같아야 한다(세션 시작 훅이 다르면 경고).
- 컨테이너는 임시다. **작업 단위가 끝날 때마다 커밋하고 push한다.** push하지 않은 작업은 세션이 끝나면 사라진다.
- 편집기 GUI는 없다. 장면(`.tscn`)과 리소스(`.tres`)는 텍스트로 직접 쓰고, 결과는 테스트와 스크린샷으로 확인한다.
- 렌더러는 GL Compatibility(클라우드의 소프트웨어 OpenGL과 웹 내보내기에서 동작). Forward+로 바꾸면 클라우드에서 스크린샷이 안 될 수 있다.

## 구조
| 경로 | 내용 |
|---|---|
| `project.godot` | 프로젝트 설정. 메인 장면 `res://scenes/main.tscn` |
| `scenes/` | 장면(`.tscn`) |
| `scripts/` | GDScript |
| `scripts/core/` | 게임 규칙 (UI 없음, 테스트 대상): 유닛·아이템 정의, 스킬(`skills.gd`), 가격·상점 확률, 가방, 시너지, 전투, 적 생성, 게임 상태(로그라이크), 기록 |
| `scripts/ui/` | 그리기 전용: 3D 전투 재생 `battle_view_3d.gd`, 가방 그리드, 스타일 `ui_style.gd`(색·테마·버튼 변형·등급 색), 도형 아이콘 `game_icon.gd`, 칸 모양 미리보기 `shape_icon.gd`. 전투 결과는 `BattleSim` 이 미리 계산하고 화면은 재생만 한다 |
| `assets/` | 그림·소리·글꼴. 한글 글꼴은 `assets/theme.tres`(메인 장면 theme)로 적용 |
| `tests/` | `test_*.gd` 테스트(애드온 없는 자체 실행기 `run_tests.gd`) |
| `tools/check.sh` | 임포트 → 문법 검사 → 테스트 |
| `tools/screenshot.sh` | 장면을 실행해 `build/screenshots/<장면>.png` 저장 (xvfb 필요). 추가 인자 `demo=start\|shop\|units\|enemy\|battle\|result\|gameover` 로 데모 화면, `t=<초>` 로 전투 시점 |

## 규칙
1. **커밋 전 `tools/check.sh`가 통과해야 한다.** 실패하면 고친 뒤 커밋한다.
2. 화면이 바뀌는 작업은 `tools/screenshot.sh [res://scenes/x.tscn]`로 찍고, PNG를 직접 열어 확인한 뒤 사용자에게 보여 준다. xvfb가 없으면 그 사실을 알린다.
3. 로직은 테스트할 수 있게 작은 함수·클래스로 나누고, 새 기능에는 `tests/test_<기능>.gd`를 추가한다(`extends "res://tests/test_case.gd"`, `test_` 메서드, `check`/`check_eq`).
4. GDScript는 정적 타입을 쓴다(`var speed: float = 200.0`, `func move(dir: Vector2) -> void`). 들여쓰기는 탭.
5. `.tscn`을 손으로 쓸 때: `[gd_scene ... format=3]` 머리글, `ext_resource`의 `id`는 파일 안에서 유일하게, 노드의 `parent` 경로를 정확히. 쓴 뒤 `tools/check.sh`로 불러와지는지 확인한다.
6. Godot이 만드는 `*.uid` 파일(스크립트 옆)은 커밋한다. `.godot/`와 `build/`는 커밋하지 않는다(`.gitignore`).
7. Godot 버전을 올릴 때는 설정 스크립트의 `GODOT_VER`, `.godot-version`, `project.godot`의 `config/features`를 함께 바꾸고 `tools/check.sh`를 돌린다.
8. 외부 애드온(Asset Library·GitHub)은 사용자와 상의한 뒤 `addons/`에 넣는다. 클라우드 세션은 GitHub 다운로드가 막혀 있을 수 있다.
9. 화면은 세로 720×1280. 3D 전장(`BattleView3D`, 장면에 고정)이 전체 화면에 깔리고 UI 는 그 위에 겹친다(`Hud`, `Sheet`, `Popup`, `ActionBar`). 전투 시작 버튼은 시트 머리 오른쪽에 있고, `ActionBar` 는 전투 중(2배속)·결과·게임 오버 때만 쓴다. 전장은 미리보기/재생과 카메라 구도(`set_compact`)만 바꾼다. 전장 입력은 `unit_tapped`(탭)과 `unit_moved`(우리 유닛 끌어 놓기) 시그널로 main 에 넘기고, 위치 규칙(우리 진영·겹침)은 `BattleSim.place_own`/`GameState.move_unit` 이 정한다. 시트는 기본 상점, 유닛을 누르면 그 유닛 정보/정찰. 상세 패널 밖(전장 빈 곳 `background_tapped`, 위 HUD)을 누르면 상점으로 돌아간다(돌아가기 버튼 없음). UI 빈 곳의 탭이 전장으로 가도록 컨테이너는 `mouse_filter = IGNORE`. 나머지 UI 는 `scripts/main.gd` 가 코드로 만든다. 규칙은 `scripts/core/` 에 두고 UI 에서 직접 계산하지 않는다.
10. 글꼴을 프로젝트 설정(`gui/theme/custom_font`)으로 지정하지 않는다. 새 클론의 첫 임포트 때 로드 오류가 난다. 장면의 theme 로 적용한다.
11. UI 색·버튼은 `UiStyle` 을 쓴다(새 색을 흩어 놓지 않는다). 버튼 종류는 `theme_type_variation` 으로: PrimaryButton(금색), GoButton(초록), DangerButton(빨강), TabButton/TabButtonOn. 아이콘은 이미지 대신 `GameIcon.make("heart" …)`.
12. 새 스킬은 `Skills`(종류·aggregate·describe)와 `BattleSim`(발동, 이벤트 kind)과 `BattleView3D._show_event`(표시)를 함께 고치고 `tests/test_skills.gd` 에 발동 테스트를 넣는다.
