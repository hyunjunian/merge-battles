#!/usr/bin/env bash
# 웹 빌드: tools/export_web.sh  →  build/web/index.html
# Godot 웹 export 템플릿이 필요하다 (~/.local/share/godot/export_templates/<버전>/web_nothreads_release.zip).
# GitHub Pages 는 COOP/COEP 헤더를 못 주므로 스레드 없는 빌드(variant/thread_support=false)를 쓴다.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
command -v "$GODOT" >/dev/null || { echo "✗ godot 없음" >&2; exit 2; }
rm -rf build/web
mkdir -p build/web
[ -d .godot ] || timeout 600 "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
timeout 600 "$GODOT" --headless --path . --export-release "Web" build/web/index.html
[ -f build/web/index.html ] || { echo "✗ 웹 빌드 실패" >&2; exit 1; }
touch build/web/.nojekyll
echo "✓ build/web/index.html"
