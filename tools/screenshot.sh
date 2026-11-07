#!/usr/bin/env bash
# 장면 스크린샷: tools/screenshot.sh [장면 res:// 경로] [프레임 수] [추가 인자...]
# 추가 인자는 게임에 그대로 넘어간다. 예: tools/screenshot.sh "" 30 demo=battle
# 결과: build/screenshots/<장면 이름>.png  (xvfb-run 이 필요. 클라우드 환경 설정 스크립트에서 설치)
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
scene="${1:-}"
frames="${2:-30}"
shift $(( $# < 2 ? $# : 2 ))
extra=("$@")
name="$(basename "${scene:-main}" .tscn)"
for a in "${extra[@]}"; do name="${name}_${a//[^A-Za-z0-9]/-}"; done
out="$PWD/build/screenshots/${name}.png"
command -v "$GODOT" >/dev/null || { echo "✗ godot 없음" >&2; exit 2; }
if ! command -v xvfb-run >/dev/null; then
  echo "✗ xvfb-run 없음: 스크린샷을 건너뜁니다 (설정 스크립트에 xvfb mesa-utils libgl1-mesa-dri 설치 추가)" >&2
  exit 3
fi
mkdir -p build/screenshots
# 임포트가 안 된 새 클론이면 먼저 임포트 (텍스처 등)
[ -d .godot ] || timeout 300 "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
LIBGL_ALWAYS_SOFTWARE=1 timeout 120 xvfb-run -a -s "-screen 0 1280x1400x24" \
  "$GODOT" --path . --rendering-driver opengl3 --audio-driver Dummy \
  -s res://tools/screenshot.gd -- "$out" "$scene" "$frames" "${extra[@]}"
