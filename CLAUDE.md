# Merge Battles

Godot 4.7.2.stable · GDScript 게임 프로젝트. Claude Code 클라우드 세션(claude.ai/code)에서 개발한다.

## 게임 디자인 원칙 (변하지 않음)
- 핵심 지표는 **체력**과 **돈** 둘뿐이다.
- 체력이 0 이하가 되면 게임이 끝난다.
- 돈은 체력이 떨어지지 않게 하는 여러 전략에 쓰인다.
- 게임의 단일 목표는 **라운드 기준으로 오래 살아남기**다.
- 핵심 재미: 오래 살아남기 위한 여러 전략을 실험하고(탐색) 좋은 전략을 찾아 쓰며(활용) 그 능력을 기르는 것. 생존에 영향을 주는 요소는 **다양하면서도 직관적**이어야 한다.
- 큰 구조: **돈을 적재적소에 쓴다 → 전투에서의 체력 소모를 최소화한다.**
  - 돈을 쓸 곳: 모아서 이자 받기(유보도 쓰임), 상점에서 유닛·아이템 사기/팔기, 상점 새로고침, 상대 새로고침, …
  - 체력이 소모될 곳: 전투 패배(라운드 수 × 상대 남은 체력 비율 — 전투 중 가장 많이 깎았을 때 기준, 올림 — `GameState.hp_loss_for`/`remaining_ratio`), …
  - 새 요소는 이 두 목록 중 어디에 들어가는지로 설명한다.
- 돈을 쓴 결과로 갖게 되는 것(보유 자산)은 **돈 / 유닛 / 아이템 / 새로고침** 이다. 각각 "돈으로서의 가치"와 "전투에 주는 가치"를 언제까지 가지는지로 구분한다.
  | 자산 | 돈으로서의 가치 | 전투에 주는 가치 | 언제까지 |
  |---|---|---|---|
  | 돈 | 액면 그대로 + 라운드 끝 기본 3원 + 연승·연패 보너스(연속 ÷ 3 내림, 최대 3원) + 이자(10원마다 1원, 최대 5원) | 없음(쓰기 전까지) | 쓸 때까지 |
  | 유닛 | 구매 직후 판매가 = 들인 값(가격 × 합친 마리 수)의 절반, 그 뒤 유지 | 기본 능력치 + 아이템을 담을 가방 칸. 출전 슬롯(최대 6) 하나 차지. 같은 유닛·같은 별 2개는 합쳐져 별 +1(최대 3성, 별마다 체력·공격력 ×1.8, 가방 가로·세로 +1 — `Backpack.set_star`, `GameState.add_unit`/`merge_target`) | 팔 때까지 |
  | 아이템 | 구매 직후 판매가 = 구매가의 절반, 그 뒤 유지 | 유닛 가방에 장착했을 때만 능력치·스킬 | 팔 때까지 |
  | 새로고침(상점·상대) | 0 | 새 진열 / 다른 상대 | 그 라운드(전투 전)까지 |
- 정한 것: 돈을 체력으로 바로 바꾸는 길은 있어도 없어도 된다(필수 아님). 연승·연패 보상: 연속 수 ÷ 3 내림, 최대 3원(`GameState.streak_bonus`, HUD 표시는 없음, 결과 화면 수입 내역에 표시).
- 출전 풀을 넘기면 "최장 생존" 축하 후 계속되고, 상대는 라운드마다 강해진다(끝은 체력 0 뿐).
- **설계의 질을 평가하는 기준** (새 장치·수치는 이 기준으로 평가한다):
  1. **운과 실력의 비율**: 초기 라운드에서는 운의 요소가 승패에 더 큰 영향을 주고, 라운드가 높아질수록 운의 요소는 줄고 실력의 요소가 커지게 한다.
  2. **적응형 전략의 필요성**: 항상 같은 전략을 고수하는 것에 한계가 있게 한다.
- 메커니즘·밸런스를 바꿀 때는 이 지표와 목표를 바꾸지 않고, 새 규칙이 이 틀 안에서 어떤 역할(체력을 지키는 전략 / 돈의 쓰임)을 하는지 설명할 수 있어야 한다.

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
| `scripts/core/` | 게임 규칙 (UI 없음, 테스트 대상): 전투 뒤 유닛별 기여도(`battle_report.gd`: 준·받은 피해, 회복·보호막 — 결과·게임 오버 화면에 표시), 유닛·아이템 정의, 스킬(`skills.gd`), 가격·상점 확률, 가방, 시너지, 전투, 게임 상태(로그라이크), 기록, 상대 출전 풀(`opponent_pool.gd`, 수집 `pool_builder.gd` + 봇 `bot.gd`), 예비 적 생성(`enemy_gen.gd`, 풀이 없을 때만) |
| `data/opponent_pool.json` | 상대 출전 풀. `tools/build_pool.gd` 로 만든다(봇 128명 대전, 라운드별 출전 세팅) |
| `scripts/ui/` | 그리기 전용: 3D 전투 재생 `battle_view_3d.gd`(재생 중 유닛 상태 `live_unit`), 상세 패널 체력·쿨타임 막대 `live_stats.gd`, 가방 그리드, 스타일 `ui_style.gd`(색·테마·버튼 변형·등급 색), 도형 아이콘 `game_icon.gd`, 칸 모양 미리보기 `shape_icon.gd`. 전투 결과는 `BattleSim` 이 미리 계산하고 화면은 재생만 한다 |
| `assets/` | 그림·소리·글꼴. 한글 글꼴은 `assets/theme.tres`(메인 장면 theme)로 적용 |
| `tests/` | `test_*.gd` 테스트(애드온 없는 자체 실행기 `run_tests.gd`) |
| `tools/check.sh` | 임포트 → 문법 검사 → 테스트 |
| `tools/screenshot.sh` | 장면을 실행해 `build/screenshots/<장면>.png` 저장 (xvfb 필요). 추가 인자 `demo=start\|shop\|units\|enemy\|battle\|result\|gameover` 로 데모 화면, `demo=result lose=1` 패배 결과, `t=<초>` 로 전투 시점, `inspect=a1\|b0` 로 전투 중 상세, `info=1` 로 그 가방 첫 아이템 정보, `demo=units move=1` 아이템 옮기기 확인 창, `demo=victory` 최장 생존 축하 화면 |
| 웹 `#seed=N` | 배포 주소 끝에 붙이면 그 시드로 시작(같은 상점·상대 재현, 브라우저 시험용) |
| `tools/measure_skill.gd` | 운과 실력 측정(설계 기준 1): `godot --headless --path . -s res://tools/measure_skill.gd -- [판 수] [seed]` → 정책(`SkillMeter.POLICIES`: 무작위 `RandomBot` / 기본 봇 `Bot`)별로 같은 시드로 한 판씩, 라운드 5개 구간마다 승패 중 정책 차이로 설명되는 몫(eta²)을 "실력 몫"으로 출력, `build/skill_report.md` 저장 |
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
13. 상대는 출전 풀에서 고른다: k 라운드 상대 = 풀의 k 라운드 출전 세팅 중 하나(run_seed 로 고정), 풀의 마지막 라운드를 넘기면 "최장 생존" 축하 후 계속: 그 뒤 상대는 풀의 마지막 5라운드 세팅 + 우리 최근 5라운드 세팅(`GameState.history`) 중 하나이고, 넘긴 라운드마다 체력·공격력 +10%(`endless_candidates`/`enemy_power_mult`/`enemy_fighters`). HUD 오른쪽 위 "상대 바꾸기"(라운드/10 올림 원, `GameState.reroll_enemy`/`enemy_reroll_cost`)는 같은 라운드의 다른 출전으로 바꾼다(`OpponentPool.pick_index`, 라운드마다 초기화). 빈 출전은 풀에 넣지 않는다. 전투·유닛·아이템·가격·상점·경제 규칙을 바꾸면 `tools/build_pool.gd` 로 풀을 다시 만들어 함께 커밋한다(옛 풀은 옛 규칙의 세팅이다). 웹 빌드에 들어가도록 `export_presets.cfg` 의 `include_filter` 에 `data/*.json` 이 있다.
