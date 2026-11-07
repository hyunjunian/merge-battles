# Merge Battles

Godot 4.7.2.stable · GDScript

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
```

## 내 컴퓨터에서 열기

Godot 4.7.2.stable(표준판)으로 `project.godot`을 엽니다.

---
이 프로젝트는 `godot-setup` 스킬 v1.0.0로 만들어졌습니다.
