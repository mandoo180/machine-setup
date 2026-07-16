#!/usr/bin/env bash
# Ubuntu (desktop/WSL) 부트스트랩 — 이 스크립트 하나만 실행하면 된다.
#   bash bootstrap/ubuntu.sh
# 이후 동기화: rebuild (= chezmoi update)
set -euo pipefail

REPO="${MACHINE_SETUP_REPO:-https://github.com/mandoo180/machine-setup.git}"

echo ">> [bootstrap] apt 최소 의존성"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  git zsh curl ca-certificates build-essential procps file \
  gnupg software-properties-common

# WSL: systemd 활성화 기록 (스펙 §10 — 담당: bootstrap)
if grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
  if [ ! -f /etc/wsl.conf ] || ! grep -q "systemd=true" /etc/wsl.conf; then
    echo ">> [bootstrap] /etc/wsl.conf에 systemd=true 기록"
    printf '[boot]\nsystemd=true\n' | sudo tee -a /etc/wsl.conf >/dev/null
  fi
fi

if [ ! -d /home/linuxbrew/.linuxbrew ]; then
  echo ">> [bootstrap] Homebrew on Linux 설치"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

command -v chezmoi >/dev/null 2>&1 || brew install chezmoi

echo ">> [bootstrap] chezmoi init --apply ($REPO)"
echo ">> email 프롬프트에는 개인(mandoo180@gmail.com) 또는 회사(kyeongsoo@douzone.com) 주소를 입력하십시오"
# CHEZMOI_EXTRA_ARGS: 비대화 실행용 (예: --promptString email=t@t.com — 스모크 테스트가 사용)
# shellcheck disable=SC2086
chezmoi init --apply "$REPO" ${CHEZMOI_EXTRA_ARGS:-}

echo ">> [bootstrap] 완료. 새 셸을 시작하십시오: exec zsh"
if grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null && [ ! -d /run/systemd/system ]; then
  echo ">> WSL: PowerShell에서 'wsl --shutdown' 후 재진입하면 systemd/서비스가 활성화됩니다. 재진입 후 'rebuild' 한 번 더 실행하십시오."
fi
