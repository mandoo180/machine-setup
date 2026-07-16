#!/usr/bin/env bash
# 렌더링 헬퍼: isWSL 컨텍스트를 강제한 임시 config로 템플릿을 렌더링한다.
# 사용법: bash tests/render.sh <true|false> <template-file>
# 배경: execute-template --init은 .chezmoidata를 로드하지 않으므로,
#       임시 config를 생성(init, apply 없음)한 뒤 execute-template을 쓴다.
set -euo pipefail
cd "$(dirname "$0")/.."
ctx="$1"
file="$2"
CZ="nix run nixpkgs#chezmoi --"
command -v chezmoi >/dev/null 2>&1 && CZ="chezmoi"
tmp="${TMPDIR:-/tmp}/cz-render-$ctx"
mkdir -p "$tmp"
FORCE_WSL="$ctx" $CZ init --source "$(pwd)" --config "$tmp/chezmoi.toml" \
  --promptString email=t@t.com >/dev/null
$CZ --source "$(pwd)" --config "$tmp/chezmoi.toml" execute-template < "$file"
