#!/usr/bin/env bash
# ubuntu:24.04 컨테이너에서 bootstrap → chezmoi apply 전체를 검증한다.
# 사용법: bash tests/smoke-ubuntu.sh [wsl|desktop]   (기본: 둘 다)
# 소요: 컨텍스트당 10~25분 (brew bottle 다운로드)
set -euo pipefail
cd "$(dirname "$0")/.."
REPO_DIR="$(pwd)"

run_context() {
  local ctx="$1" force_wsl
  case "$ctx" in
    wsl) force_wsl=true ;;
    desktop) force_wsl=false ;;
  esac
  echo "===== smoke: $ctx (FORCE_WSL=$force_wsl) ====="
  docker run --rm \
    -v "$REPO_DIR":/repo:ro \
    -e FORCE_WSL="$force_wsl" \
    ubuntu:24.04 bash -c '
      set -euo pipefail
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq && apt-get install -y -qq sudo >/dev/null
      useradd -m -s /bin/bash tester
      echo "tester ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/tester
      # ubuntu:24.04 이미지는 UID 1000을 내장 ubuntu 유저가 선점하므로 tester는 1001을 받는다.
      # 호스트에서 bind mount된 /repo(:ro)는 호스트 UID 소유라 tester와 불일치 —
      # git의 dubious-ownership 보호(CVE-2022-24765)에 걸려 clone이 거부된다.
      # git clone은 워크트리 경로(/repo)가 아니라 gitdir 경로(/repo/.git)의 소유권을
      # 검사하므로 두 경로 모두 예외 등록이 필요하다.
      # git 설치 전에도 읽히는 시스템 설정 파일에 안전 예외를 등록해 둔다.
      printf "[safe]\n\tdirectory = /repo\n\tdirectory = /repo/.git\n" >> /etc/gitconfig
      sudo -u tester -H \
        env MACHINE_SETUP_REPO=/repo FORCE_WSL="$FORCE_WSL" \
            CHEZMOI_EXTRA_ARGS="--promptString email=t@t.com" \
        bash -c "cd && bash /repo/bootstrap/ubuntu.sh"
      # --- 검증 ---
      sudo -u tester -H bash -c "
        set -e
        eval \"\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)\"
        command -v rg && command -v fd && command -v eza && command -v delta
        grep -q \"oh-my-zsh\" ~/.zshrc
        [ -d ~/.oh-my-zsh ]
        git config --get user.email | grep -q t@t.com
        [ -d ~/.local/share/fonts/JetBrainsMono ]
        getent passwd tester | grep -q /usr/bin/zsh
      "
      echo "===== smoke PASS ====="
    '
}

for ctx in "${@:-wsl desktop}"; do run_context "$ctx"; done
echo "SMOKE PASS"
