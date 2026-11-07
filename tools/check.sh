#!/usr/bin/env bash
# 프로젝트 점검: Godot 버전 → 임포트 → 모든 .gd 문법 검사 → 테스트. 커밋 전에 매번 실행한다.
#   tools/check.sh
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null; then
  echo "✗ godot 없음 — 클라우드 환경 설정 스크립트에 Godot 설치를 넣으세요 (README 참고)" >&2
  exit 2
fi
have="$("$GODOT" --headless --version 2>/dev/null | grep -E '^[0-9]+\.[0-9]+' | head -1)"
want="$(cat .godot-version 2>/dev/null || true)"
echo "Godot ${have} (프로젝트 기록 ${want:-없음})"
if [[ -n "$want" && "$have" != "$want"* ]]; then
  echo "⚠ 설치된 Godot 이 .godot-version 과 다릅니다. 설정 스크립트의 GODOT_VER 를 맞추세요."
fi
fail=0
log="$(mktemp)"

echo "== 임포트"
timeout 600 "$GODOT" --headless --path . --import >"$log" 2>&1 || true
if grep -E "SCRIPT ERROR|Parse Error|Failed to load|ERROR: .*(res://|resource)" "$log"; then
  echo "✗ 임포트 중 오류 (위 줄 참고)"; fail=1
else
  echo "✓ 임포트"
fi

echo "== 스크립트 문법"
while IFS= read -r -d '' f; do
  rel="res://${f#./}"
  if ! timeout 120 "$GODOT" --headless --path . --check-only --script "$rel" >"$log" 2>&1 \
     || grep -qE "SCRIPT ERROR|Parse Error" "$log"; then
    echo "✗ $rel"; grep -E "ERROR|error" "$log" | head -5; fail=1
  fi
done < <(find . -name '*.gd' -not -path './.godot/*' -not -path './addons/*' -print0 | sort -z)
[ $fail -eq 0 ] && echo "✓ 문법"

echo "== 테스트"
# 테스트 안의 실행 중 오류(null 접근 등)는 Godot 이 출력만 하고 계속하므로 출력에서 찾아 실패로 친다.
timeout 600 "$GODOT" --headless --path . -s res://tests/run_tests.gd 2>&1 | tee "$log"
st=${PIPESTATUS[0]}
if [ "$st" -ne 0 ]; then
  echo "✗ 테스트 실패"; fail=1
elif grep -qE "SCRIPT ERROR" "$log"; then
  echo "✗ 테스트 중 스크립트 오류 (위 SCRIPT ERROR 참고)"; fail=1
fi
rm -f "$log"
[ $fail -eq 0 ] && echo "✓ 점검 통과" || echo "✗ 점검 실패"
exit $fail
