# Merge Battles

Godot 4.7.2.stable · GDScript · 세로 화면(720×1280) 프로토타입

가방 퍼즐 + 오토배틀러. 보유한 아이템을 유닛 가방(3×4 칸)에 넣어 유닛을 만들고, 라운드 예산 안에서 팀을 짜서 매 라운드 강해지는 상대와 자동으로 싸운다.

## 게임 방식 (프로토타입, 로그라이크)

- **한 판**: 체력 100, 1라운드부터 시작. 매 라운드 상대와 자동 전투를 하고 승패와 상관없이 다음 라운드로 간다. 지면 **라운드 수 × 상대 남은 체력 비율**(전투 중 상대 체력 합을 가장 많이 깎았을 때의 남은 체력 합 ÷ 최대 체력 합, 올림)만큼 체력이 줄고(10라운드에 상대가 30% 남기고 이기면 −3, 완패면 −10), 0 이하가 되면 끝. 도달 라운드가 기기에 기록된다(최고 라운드, 판 수).
- **돈**: 라운드가 끝날 때마다 기본 3원 + 승리 1원(이겼을 때) + 연승·연패 보너스(연속 수 ÷ 3 내림, 연승은 최대 1원, 연패는 최대 3원) + 이자(전투가 끝났을 때 가진 돈 10원마다 1원, 최대 5원).
- **상점**: 5칸 진열, 칸마다 40% 확률로 유닛 아니면 아이템(개수·순서 고정 없음, 새로고침 1원, 라운드마다 새 진열). 가격은 2~10원, 판매가는 구매가의 절반(최소 1원)이라 항상 더 낮다. 라운드가 오를수록 비싼 물건이 나올 확률이 커진다.
  - **유닛**: 1x2 ~ 3x4 크기의 가방. 클수록 비싸고 기본 능력치가 높다. 사면 바로 전장에 투입되고(최대 6), 빼려면 팔아야 한다(가방 속 아이템은 보유함으로). 전장에서 끌어 우리 진영 어디로든 자유롭게 배치할 수 있고, 전투는 그 자리에서 시작한다.
  - **합치기**: 같은 유닛·같은 별 2개를 모으면(사는 순간 자동) 별이 하나 오른다(최대 ★★★). 별마다 체력·공격력 ×1.8, 가방 가로·세로 +1칸. 합쳐진 유닛의 아이템은 남는 유닛 가방으로(자리가 없으면 보유함). 전장이 꽉 차도 합쳐지는 유닛은 살 수 있다.
  - **아이템**: 작고 성능이 좋을수록 비싸다. 유닛 가방에 넣어 능력치를 바꾼다. 넣고 빼고 회전할 수 있다.
- **시작**: 4원과 1x2 유닛(견습병) 하나.
- **상대**: 미리 봇 128명이 같은 규칙으로 서로 싸우며(살아남은 봇끼리 매 라운드 무작위 짝, 마지막 1명까지) 라운드별 출전 세팅을 모은 **출전 풀**(`data/opponent_pool.json`)에서, k 라운드에는 그 라운드에 출전했던 세팅 중 하나가 무작위로 나온다. 풀의 마지막 라운드를 넘기면(=마지막 생존 봇보다 오래 살아남음) **최장 생존** 축하 후 계속 이어진다. 그 뒤 상대는 풀의 마지막 5라운드 세팅과 우리 팀의 최근 5라운드 세팅 중 하나이고, 넘긴 라운드마다 체력·공격력이 10%씩 강해진다. 화면 오른쪽 위 **상대 바꾸기**로 같은 후보 안의 다른 상대로 바꿀 수 있다(가격: 라운드 수 ÷ 10 올림, 1~10라운드 1원, 11~20라운드 2원 …).
- **스킬 아이템**(★): 전투 중 발동한다. 흡혈(흡혈송곳니), 독(독니단검), 치명타(매의렌즈), 연쇄 번개(번개지팡이), 치유(치유의성배), 보호막(수호부적), 분노(광전사가면), 화염구(화염두루마리), 가시(가시갑옷), 부활(불사조깃털). 상대도 같은 스킬 아이템을 산다.
- **시너지**: 팀 전체에서 같은 태그(전사·수호·자연·비전) 아이템이 2개, 4개 모이면 팀 보너스.
- **전투**: 3D 전장에서 유닛 AI 가 가장 가까운 적을 골라 싸운다. 원거리 유닛(궁수·마법사, 단궁·화염지팡이)은 사거리를 유지하며 적이 붙으면 물러난다.
- **화면**: 3D 전장이 화면 전체에 깔리고 UI 가 겹친다(위: 상태 HUD, 아래: 접을 수 있는 시트와 행동 버튼, 가운데: 결과 팝업). 시트는 기본으로 상점이고, 전장의 우리 유닛을 탭하면 그 유닛 정보(가방 편성·판매), 적을 탭하면 정찰로 바뀐다. 같은 유닛을 다시 탭하거나 "◀ 상점"으로 돌아간다.

## 코드 구조

| 경로 | 내용 |
|---|---|
| `scripts/core/unit_db.gd` | 유닛 정의 표 (가방 크기·가격·기본 능력치) |
| `scripts/core/item_db.gd` | 아이템 정의 표 (모양·가격·능력치·태그) |
| `scripts/core/item.gd` | 보유 아이템 (회전, 능력치, 스킬) |
| `scripts/core/skills.gd` | 스킬 종류·합치기·설명 (발동은 battle_sim.gd) |
| `scripts/core/backpack.gd` | 유닛 = 가방 (크기, 전장 자리, 칸 배치) |
| `scripts/core/pricing.gd` | 가격 규칙(판매가), 라운드별 상점 등장 확률 |
| `scripts/core/records.gd` | 플레이 기록 저장 (`user://records.cfg`) |
| `scripts/core/synergy.gd` | 태그 시너지 |
| `scripts/core/battle_sim.gd` | 유닛 능력치 계산, 전장 AI(목표 선택·이동·후퇴·충돌 회피)와 결정적 전투 시뮬레이션 |
| `scripts/core/enemy_gen.gd` | 라운드별 상대 팀 생성 |
| `scripts/core/game_state.gd` | 체력·골드·라운드·연승/연패·상점·판매·게임 오버 |
| `scripts/ui/backpack_view.gd` | 가방 그리드 그리기·터치 |
| `scripts/ui/ui_style.gd`, `game_icon.gd`, `shape_icon.gd` | UI 스타일(색·버튼·등급), 도형 아이콘, 칸 모양 미리보기 |
| `scripts/ui/battle_view_3d.gd` | 전투 기록을 3D 전장에서 재생 (체력바·피해 숫자는 2D 오버레이) |
| `scripts/main.gd` | 화면 구성과 입력 처리 |
| `assets/fonts/` | Noto Sans KR (SIL OFL, `OFL.txt`) |

## 클라우드 세션에서 개발하기 (claude.ai/code)

이 저장소로 세션을 열기 전에, 클라우드 환경의 설정 스크립트(Setup script)에 Godot 설치를 넣어 둡니다. `GODOT_VER`는 `.godot-version`과 맞춥니다(`4.5.1.stable` → `4.5.1-stable`).

```bash
#!/bin/bash
set -e
GODOT_VER=4.7.2-stable
cd /tmp
ZIP="Godot_v${GODOT_VER}_linux.x86_64.zip"
curl -fsSL -o godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VER}/${ZIP}" \
  || curl -fsSL -o godot.zip "https://downloads.godotengine.org/?version=${GODOT_VER%-*}&flavor=${GODOT_VER#*-}&slug=linux.x86_64.zip"
unzip -q -o godot.zip
mv "Godot_v${GODOT_VER}_linux.x86_64" /usr/local/bin/godot
chmod +x /usr/local/bin/godot
# 스크린샷 확인용 (선택)
apt-get update -qq && apt-get install -y -qq xvfb mesa-utils libgl1-mesa-dri
```

## 명령

```bash
tools/check.sh                              # 임포트 → 문법 → 테스트
tools/screenshot.sh                         # 메인 장면 스크린샷 → build/screenshots/main.png
tools/screenshot.sh res://scenes/x.tscn 60  # 다른 장면, 60프레임 뒤
tools/screenshot.sh "" 30 demo=shop         # 데모 화면: demo=start | shop | units | enemy | battle (t=초) | result | gameover
```

## 웹 배포 (GitHub Pages)

`main`에 push하면 `.github/workflows/pages.yml`이 점검(`tools/check.sh`) → 웹 빌드(`tools/export_web.sh`) → GitHub Pages 배포를 한다.
처음 한 번 저장소 **Settings → Pages → Build and deployment → Source**를 **GitHub Actions**로 바꿔야 한다.
주소: `https://<사용자>.github.io/merge-battles/`

로컬 웹 빌드: `tools/export_web.sh` → `build/web/` (Godot 웹 export 템플릿 필요). GitHub Pages는 COOP/COEP 헤더를 못 주므로 스레드 없는 빌드를 쓴다.

## 내 컴퓨터에서 열기

Godot 4.7.2.stable(표준판)으로 `project.godot`을 엽니다.

---
이 프로젝트는 `godot-setup` 스킬 v1.0.0로 만들어졌습니다.
