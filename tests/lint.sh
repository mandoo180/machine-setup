#!/usr/bin/env bash
# 저장소의 모든 셸/PowerShell 소스를 린트한다.
# 사용법: bash tests/lint.sh          (셸만)
#        bash tests/lint.sh --ps      (PowerShell 포함 — docker 필요)
set -euo pipefail
cd "$(dirname "$0")/.."

SHELLCHECK="nix run nixpkgs#shellcheck --"
command -v shellcheck >/dev/null 2>&1 && SHELLCHECK="shellcheck"

# 템플릿 → 린트 가능 텍스트 변환:
# 순수 템플릿 태그 줄({{ if }}, {{ range }}, {{ end }} 등)은 줄 자체를 삭제하고
# (빈 줄로 남기면 1행 {{ if }} 뒤의 shebang이 SC1128에 걸리고,
#  그대로 두면 PowerShell 배열 리터럴에서 ParseError를 일으킴),
# 인라인 태그({{ . }} 등)만 __TMPL__ 플레이스홀더로 치환한다.
# 실제 chezmoi 렌더링의 `-}}` 트리밍과 동등한 효과.
strip_tmpl() {
  sed -e '/^[[:space:]]*{{[^}]*}}[[:space:]]*$/d' -e 's/{{[^}]*}}/__TMPL__/g' "$1"
}

fail=0

# 1) 순수 bash 파일
for f in bootstrap/*.sh tests/*.sh; do
  [ -f "$f" ] || continue
  echo "shellcheck: $f"
  $SHELLCHECK -s bash "$f" || fail=1
done

# 2) 셸 템플릿: Go 템플릿 표현을 __TMPL__로 치환 후 검사. 오탐 제외:
#    SC2034/SC2050/SC2154(치환 잔재), SC1091(source 대상 미추적 info)
for f in home/.chezmoiscripts/*.sh.tmpl home/dot_zshrc.tmpl; do
  [ -f "$f" ] || continue
  echo "shellcheck(tmpl): $f"
  strip_tmpl "$f" | $SHELLCHECK -s bash -e SC2034,SC2050,SC2154,SC1091 - || fail=1
done

# 3) PowerShell (옵션): PSScriptAnalyzer
if [ "${1:-}" = "--ps" ]; then
  for f in bootstrap/*.ps1 home/.chezmoiscripts/*.ps1.tmpl home/Documents/PowerShell/*.ps1.tmpl; do
    [ -f "$f" ] || continue
    echo "PSScriptAnalyzer: $f"
    strip_tmpl "$f" > /tmp/lint-target.ps1
    # PSScriptAnalyzer 1.21.0 고정: 컨테이너 pwsh(7.4.2)와 호환되는 검증된 버전.
    # $ErrorActionPreference=Stop — 모듈 설치/로드 실패가 조용히 PASS 되지 않도록.
    docker run --rm -v /tmp/lint-target.ps1:/t.ps1:ro mcr.microsoft.com/powershell \
      pwsh -NoProfile -Command \
      '$ErrorActionPreference = "Stop"; Install-Module PSScriptAnalyzer -RequiredVersion 1.21.0 -Force -Scope CurrentUser | Out-Null; Import-Module PSScriptAnalyzer -RequiredVersion 1.21.0; $r = Invoke-ScriptAnalyzer -Path /t.ps1 -Severity Error,ParseError; $r; if ($r) { exit 1 }' || fail=1
  done
fi

if [ "$fail" -eq 0 ]; then
  echo "LINT PASS"
else
  echo "LINT FAIL"
  exit 1
fi
