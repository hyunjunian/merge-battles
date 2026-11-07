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
| `scripts/core/` | 게임 규칙 (UI 없음, 테스트 대상): 유닛·아이템 정의, 스킬(`skills.gd`), 가격·상점 확률, 가방, 시너지, 전투, 게임 상태(로그라이크), 기록, 상대 출전 풀(`opponent_pool.gd`, 수집 `pool_builder.gd` + 봇 `bot.gd`), 예비 적 생성(`enemy_gen.gd`, 풀이 없을 때만) |
| `data/opponent_pool.json` | 상대 출전 풀. `tools/build_pool.gd` 로 만든다(봇 128명 대전, 라운드별 출전 세팅) |
| `scripts/ui/` | 그리기 전용: 3D 전투 재생 `battle_view_3d.gd`(재생 중 유닛 상태 `live_unit`), 상세 패널 체력·쿨타임 막대 `live_stats.gd`, 가방 그리드, 스타일 `ui_style.gd`(색·테마·버튼 변형·등급 색), 도형 아이콘 `game_icon.gd`, 칸 모양 미리보기 `shape_icon.gd`. 전투 결과는 `BattleSim` 이 미리 계산하고 화면은 재생만 한다 |
| `assets/` | 그림·소리·글꼴. 한글 글꼴은 `assets/theme.tres`(메인 장면 theme)로 적용 |
| `tests/` | `test_*.gd` 테스트(애드온 없는 자체 실행기 `run_tests.gd`) |
| `tools/check.sh` | 임포트 → 문법 검사 → 테스트 |
| `tools/screenshot.sh` | 장면을 실행해 `build/screenshots/<장면>.png` 저장 (xvfb 필요). 추가 인자 `demo=start\|shop\|units\|enemy\|battle\|result\|gameover` 로 데모 화면, `t=<초>` 로 전투 시점, `inspect=a1\|b0` 로 전투 중 상세, `info=1` 로 그 가방 첫 아이템 정보, `demo=units move=1` 아이템 옮기기 확인 창, `demo=victory` 우승 화면 |
| 웹 `#seed=N` | 배포 주소 끝에 붙이면 그 시드로 시작(같은 상점·상대 재현, 브라우저 시험용) |
| `tools/build_pool.gd` | 상대 출전 풀 만들기: `godot --headless --path . -s res://tools/build_pool.gd -- [N] [seed]` → `data/opponent_pool.json` |

## 규칙
1. **커밋 전 `tools/check.sh`가 통과해야 한다.** 실패하면 고친 뒤 커밋한다.
2. 화면이 바뀌는 작업은 `tools/screenshot.sh [res://scenes/x.tscn]`로 찍고, PNG를 직접 열어 확인한 뒤 사용자에게 보여 준다. xvfb가 없으면 그 사실을 알린다.
3. 로직은 테스트할 수 있게 작은 함수·클래스로 나누고, 새 기능에는 `tests/test_<기능>.gd`를 추가한다(`extends "res://tests/test_case.gd"`, `test_` 메서드, `check`/`check_eq`).
4. GDScript는 정적 타입을 쓴다(`var speed: float = 200.0`, `func move(dir: Vector2) -> void`). 들여쓰기는 탭.
5. `.tscn`을 손으로 쓸 때: `[gd_scene ... format=3]` 머리글, `ext_resource`의 `id`는 파일 안에서 유일하게, 노드의 `parent` 경로를 정확히. 쓴 뒤 `tools/check.sh`로 불러와지는지 확인한다.
6. Godot이 만드는 `*.uid` 파일(스크립트 옆)은 커밋한다. `.godot/`와 `build/`는 커밋하지 않는다(`.gitignore`).
7. Godot 버전을 올릴 때는 설정 스크립트의 `GODOT_VER`, `.godot-version`, `project.godot`의 `config/features`를 함께 바꾸고 `tools/check.sh`를 돌린다.
8. 외부 애드온(Asset Library·GitHub)은 사용자와 상의한 뒤 `addons/`에 넣는다. 클라우드 세션은 GitHub 다운로드가 막혀 있을 수 있다.
9. 화면은 세로 720×1280. 3D 전장(`BattleView3D`, 장면에 고정)이 전체 화면에 깔리고 UI 는 그 위에 겹친다(`Hud`, `Sheet`, `Popup`, `ActionBar`). 시너지는 상대 팀은 위 HUD, 우리 팀은 시트 바로 위(`OwnSynergy`). 상점 시트 머리 오른쪽에 체력과 전투 시작 버튼이 있고(상세 패널에는 시트 머리가 없다), 전투 중에는 그 자리가 배속 버튼이 된다(상세 패널 머리에는 두지 않는다). 전투 중에도 시트(상점·상세)는 보이지만 구매·편성·판매는 막는다. `ActionBar` 는 결과·게임 오버 때만 쓴다. 전장은 미리보기/재생과 카메라 구도(`set_compact`)만 바꾼다. 전장 입력은 `unit_tapped`(탭)과 `unit_moved`(우리 유닛 끌어 놓기) 시그널로 main 에 넘기고, 위치 규칙(우리 진영·겹침)은 `BattleSim.place_own`/`GameState.move_unit` 이 정한다. 시트는 기본 상점, 유닛을 누르면 그 유닛 정보/정찰. 상세 패널은 2x2 칸: [이름 | 정보] / [가방 | 아이템 목록]. 아이템은 끌어 놓기로 장착·이동·해제한다(`DragItemCard` → `BackpackView` 의 `drop_check`/`item_dropped`, 목록은 `DropZone`; 규칙은 `GameState.can_equip_flexible`/`equip_flexible`/`fits_in`). 상세 패널 밖(전장 빈 곳 `background_tapped`, 위 HUD)을 누르면 상점으로 돌아간다(돌아가기 버튼 없음). UI 빈 곳의 탭이 전장으로 가도록 컨테이너는 `mouse_filter = IGNORE`. 나머지 UI 는 `scripts/main.gd` 가 코드로 만든다. 규칙은 `scripts/core/` 에 두고 UI 에서 직접 계산하지 않는다.
10. 글꼴을 프로젝트 설정(`gui/theme/custom_font`)으로 지정하지 않는다. 새 클론의 첫 임포트 때 로드 오류가 난다. 장면의 theme 로 적용한다.
11. UI 색·버튼은 `UiStyle` 을 쓴다(새 색을 흩어 놓지 않는다). 버튼 종류는 `theme_type_variation` 으로: PrimaryButton(금색), GoButton(초록), DangerButton(빨강), TabButton/TabButtonOn. 아이콘은 이미지 대신 `GameIcon.make("heart" …)`.
12. 새 스킬은 `Skills`(종류·aggregate·describe)와 `BattleSim`(발동, 이벤트 kind)과 `BattleView3D._show_event`(표시)를 함께 고치고 `tests/test_skills.gd` 에 발동 테스트를 넣는다.
13. 상대는 출전 풀에서 고른다: k 라운드 상대 = 풀의 k 라운드 출전 세팅 중 하나(run_seed 로 고정), k 라운드 데이터가 없으면 우승. 정찰 패널의 "상대 바꾸기"(라운드/10 올림 원, `GameState.reroll_enemy`/`enemy_reroll_cost`)는 같은 라운드의 다른 출전으로 바꾼다(`OpponentPool.pick_index`, 라운드마다 초기화). 빈 출전은 풀에 넣지 않는다. 전투·유닛·아이템·가격·상점·경제 규칙을 바꾸면 `tools/build_pool.gd` 로 풀을 다시 만들어 함께 커밋한다(옛 풀은 옛 규칙의 세팅이다). 웹 빌드에 들어가도록 `export_presets.cfg` 의 `include_filter` 에 `data/*.json` 이 있다.
