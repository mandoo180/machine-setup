#!/usr/bin/env bash
# macOS 부트스트랩 — 이 스크립트 하나만 실행하면 된다.
#   bash bootstrap/macos.sh
set -euo pipefail

REPO="${MACHINE_SETUP_REPO:-https://github.com/mandoo180/machine-setup.git}"

if ! xcode-select -p >/dev/null 2>&1; then
  echo ">> [bootstrap] Xcode Command Line Tools 설치 (GUI 창 승인 필요)"
  xcode-select --install
  # 30분 타임아웃 — 사용자가 GUI 설치를 취소하면 무한 대기하지 않는다
  waited=0
  until xcode-select -p >/dev/null 2>&1; do
    sleep 10
    waited=$((waited + 10))
    if [ "$waited" -ge 1800 ]; then
      echo "!! CLT 설치가 30분 내 완료되지 않았습니다. 설치 완료 후 이 스크립트를 다시 실행하십시오." >&2
      exit 1
    fi
    if [ $((waited % 60)) -eq 0 ]; then
      echo ">> CLT 설치 대기 중... (${waited}s)"
    fi
  done
fi

if [ ! -x /opt/homebrew/bin/brew ]; then
  echo ">> [bootstrap] Homebrew 설치"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/opt/homebrew/bin/brew shellenv)"

command -v chezmoi >/dev/null 2>&1 || brew install chezmoi

echo ">> [bootstrap] chezmoi init --apply ($REPO)"
echo ">> email 프롬프트에는 개인(mandoo180@gmail.com) 또는 회사(kyeongsoo@douzone.com) 주소를 입력하십시오"
chezmoi init --apply "$REPO"

echo ">> [bootstrap] 완료. 터미널을 재시작하십시오."
