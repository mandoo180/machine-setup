#!/usr/bin/env bash
# 저장소의 모든 셸/PowerShell 소스를 린트한다.
# 사용법: bash tests/lint.sh          (셸만)
#        bash tests/lint.sh --ps      (PowerShell 포함 — docker 필요)
set -euo pipefail
cd "$(dirname "$0")/.."

SHELLCHECK="nix run nixpkgs#shellcheck --"
command -v shellcheck >/dev/null 2>&1 && SHELLCHECK="shellcheck"

fail=0

# 1) 순수 bash 파일
for f in bootstrap/*.sh tests/*.sh; do
  [ -f "$f" ] || continue
  echo "shellcheck: $f"
  $SHELLCHECK -s bash "$f" || fail=1
done

# 2) 셸 템플릿: Go 템플릿 표현을 __TMPL__로 치환 후 검사
#    (SC2034: 템플릿 변수 미사용 오탐 / SC2050: 치환된 상수 비교 오탐 제외)
for f in home/.chezmoiscripts/*.sh.tmpl home/dot_zshrc.tmpl; do
  [ -f "$f" ] || continue
  echo "shellcheck(tmpl): $f"
  sed 's/{{[^}]*}}/__TMPL__/g' "$f" | $SHELLCHECK -s bash -e SC2034,SC2050,SC2154 - || fail=1
done

# 3) PowerShell (옵션): PSScriptAnalyzer
if [ "${1:-}" = "--ps" ]; then
  for f in bootstrap/*.ps1 home/.chezmoiscripts/*.ps1.tmpl home/Documents/PowerShell/*.ps1.tmpl; do
    [ -f "$f" ] || continue
    echo "PSScriptAnalyzer: $f"
    sed 's/{{[^}]*}}/__TMPL__/g' "$f" > /tmp/lint-target.ps1
    docker run --rm -v /tmp/lint-target.ps1:/t.ps1:ro mcr.microsoft.com/powershell \
      pwsh -NoProfile -Command \
      'Install-Module PSScriptAnalyzer -Force -Scope CurrentUser | Out-Null; $r = Invoke-ScriptAnalyzer -Path /t.ps1 -Severity Error; $r; if ($r) { exit 1 }' || fail=1
  done
fi

[ "$fail" -eq 0 ] && echo "LINT PASS" || { echo "LINT FAIL"; exit 1; }
