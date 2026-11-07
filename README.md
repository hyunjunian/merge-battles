# Merge Battles

Godot 4.7.2.stable · GDScript · 세로 화면(720×1280) 프로토타입

가방 퍼즐 + 오토배틀러. 보유한 아이템을 유닛 가방(3×4 칸)에 넣어 유닛을 만들고, 라운드 예산 안에서 팀을 짜서 매 라운드 강해지는 상대와 자동으로 싸운다.

## 게임 방식 (프로토타입)

- **화면**: 3D 전장이 화면 전체에 깔려 있고 그 위에 UI 가 겹친다(위: 상태 HUD, 아래: 접을 수 있는 편성 시트와 행동 버튼, 가운데: 전투 결과). 시트를 펼치면 카메라가 전장을 시트 위쪽에 맞추고, 접거나 전투 중이면 전장이 화면을 꽉 채운다. 전장 위쪽엔 다음 상대가, 아래쪽엔 우리 유닛 자리 3개가 서 있다. 적을 탭하면 상세 전력(능력치·가방·시너지)을, 우리 유닛을 탭하면 그 유닛의 가방 편집을 아래 패널에 띄운다.
- **베이스 캠프**: 상점에서 아이템 구매·새로고침, 판매, 같은 아이템 2개 합성(★ 등급 상승), 유닛 편성. 준비가 되면 출정한다.
- **유닛 = 가방**: 가방에 넣은 아이템 능력치(체력·공격·방어·공속·회복)가 곧 유닛의 능력치다. 빈 가방은 출전하지 않는다. 아이템마다 칸 모양이 있고 회전할 수 있다.
- **예산**: 가방에 넣은 아이템 비용의 합은 라운드 예산(8 + 4×(라운드−1))을 넘을 수 없다. 합성하면 능력치 2배·비용 1.5배라서 예산을 아낀다.
- **시너지**: 팀 전체에서 같은 태그(전사·수호·자연·비전) 아이템이 2개, 4개 모이면 팀 보너스.
- **전투**: 3D 전장에서 자동으로 싸운다. 유닛 AI가 가장 가까운 적을 골라 다가가 공격하고, 원거리 유닛(단궁·화염지팡이)은 사거리를 유지하며 적이 붙으면 물러난다. 이기면 골드를 받고 다음 라운드(원하면 캠프로 귀환), 지면 베이스 캠프로 돌아와 정비한 뒤 같은 라운드에 다시 도전한다.

## 코드 구조

| 경로 | 내용 |
|---|---|
| `scripts/core/item_db.gd` | 아이템 정의 표 (모양·비용·능력치·태그) |
| `scripts/core/item.gd` | 보유 아이템 (등급, 회전, 능력치·비용 계산) |
| `scripts/core/backpack.gd` | 가방 칸 배치 |
| `scripts/core/synergy.gd` | 태그 시너지 |
| `scripts/core/battle_sim.gd` | 유닛 능력치 계산, 전장 AI(목표 선택·이동·후퇴·충돌 회피)와 결정적 전투 시뮬레이션 |
| `scripts/core/enemy_gen.gd` | 라운드별 상대 팀 생성 |
| `scripts/core/game_state.gd` | 골드·라운드·상점·합성·예산·진행 |
| `scripts/ui/backpack_view.gd` | 가방 그리드 그리기·터치 |
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
tools/screenshot.sh "" 30 demo=camp         # 데모 화면: demo=camp | demo=prep | demo=enemy | demo=battle (t=초 로 전투 시점 지정)
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
