# Native Machine Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** nix flake 기반 개발 환경을 chezmoi + 네이티브 패키지 매니저(brew/apt/winget) 구성으로 대체하여, 새 머신에서 부트스트랩 1회 실행으로 macOS/Ubuntu(desktop·WSL)/Windows 작업 환경을 구성한다.

**Architecture:** chezmoi가 dotfiles와 `.chezmoiscripts`(패키지→폰트→OMZ→OS설정→서비스→입력기)를 관리한다. 패키지 목록은 `.chezmoidata/packages.yaml` 단일 소스이며, `run_onchange` 스크립트 본문에 데이터 해시를 렌더링해 목록 변경 시 재실행된다. 플랫폼 분기는 스크립트 내부의 `.chezmoi.os` + `isWSL` 템플릿 분기.

**Tech Stack:** chezmoi(Go 템플릿), bash, PowerShell 7, Homebrew(macOS/Linux), apt, winget, Docker(스모크 테스트), shellcheck/PSScriptAnalyzer(린트)

**스펙:** `docs/superpowers/specs/2026-07-16-native-machine-setup-design.md` (승인됨)

## Global Constraints

- 모든 bash 스크립트: `set -euo pipefail`. 모든 PowerShell 스크립트: `$ErrorActionPreference = 'Stop'`
- `.chezmoiscripts`의 모든 스크립트는 `.tmpl` 확장자 (비템플릿 금지 — 비대상 플랫폼에서 빈 본문 렌더링으로 실행 생략)
- 실행 순서: `before`(10-packages) → dotfiles 적용 → `after`(20~50, 숫자순). 숫자 프리픽스는 같은 단계 내 정렬용
- Ubuntu 24.04 (noble) 기준. Nerd Fonts는 **v3.4.0** 고정
- 패키지 목록의 단일 소스는 `home/.chezmoidata/packages.yaml` — 스크립트에 패키지명 하드코딩 금지 (예외: apt repo 설정 커맨드, repo-결합 패키지 `docker-ce*`/`tailscale`/`openssh-server`)
- 커밋 메시지에 `Co-Authored-By:` 트레일러 절대 금지 (사용자 전역 지침)
- chezmoi source 디렉터리는 `home/` (`.chezmoiroot`로 지정)
- 이 머신(NixOS-WSL)에서의 검증 도구: `nix run nixpkgs#chezmoi --`, `nix run nixpkgs#shellcheck --`, docker(설치됨), yq(설치됨). PowerShell 린트는 `mcr.microsoft.com/powershell` 컨테이너
- **렌더링 검증 규칙**: `chezmoi execute-template --init`은 `.chezmoidata`를 로드하지 않는다(Task 2 리뷰에서 규명). 스크립트/dotfile 템플릿 렌더링은 반드시 `tests/render.sh <true|false> <file>`(임시 config 생성 → execute-template, Task 3에서 작성)를 사용한다. `--init` 직접 사용은 `.chezmoi.toml.tmpl` 자체를 검증할 때만
- 확정된 패키지 ID (검증 완료 — 임의 변경 금지):
  - brew에서 `tldr`은 disabled → **`tlrc`** 사용. `p7zip` 대신 **`sevenzip`**. `bun`은 core formula. rustup formula는 **`rustup`**
  - Nerd Fonts asset명 함정: SauceCodePro → **`SourceCodePro.zip`**, Terminess → **`Terminus.zip`**
  - winget에 httpie CLI 없음(GUI만) → Windows 서브셋에서 제외. tldr은 **`tldr-pages.tlrc`**
  - Ubuntu emacs: **`ppa:ubuntuhandbook1/emacs`**의 **`emacs-pgtk`**(30.x, Wayland/WSLg 최적)

---

### Task 1: 저장소 뼈대 + 테스트 하네스

**Files:**
- Create: `.chezmoiroot`
- Create: `home/.chezmoi.toml.tmpl`
- Create: `home/.chezmoiignore`
- Create: `tests/lint.sh`
- Create: `.gitignore`

**Interfaces:**
- Produces: 템플릿 변수 `.email`(string), `.isWSL`(bool) — 이후 모든 태스크의 템플릿이 사용
- Produces: `tests/lint.sh` — 이후 모든 태스크의 린트 스텝이 실행 (`bash tests/lint.sh`)
- Produces: `FORCE_WSL` 환경변수 계약 — `chezmoi init` 시점에 `true`/`false`로 isWSL 강제 (스모크 테스트용)

- [ ] **Step 1: `.chezmoiroot`와 `.gitignore` 작성**

`.chezmoiroot` (내용은 이 한 줄, 개행 포함):

```
home
```

`.gitignore`:

```
*.swp
.DS_Store
```

- [ ] **Step 2: `home/.chezmoi.toml.tmpl` 작성**

```
{{- $email := promptStringOnce . "email" "email" -}}
{{- $isWSL := false -}}
{{- if env "FORCE_WSL" -}}
{{-   $isWSL = eq (env "FORCE_WSL") "true" -}}
{{- else if and (eq .chezmoi.os "linux") (contains "microsoft" (.chezmoi.kernel.osrelease | lower)) -}}
{{-   $isWSL = true -}}
{{- end -}}
[data]
    email = {{ $email | quote }}
    isWSL = {{ $isWSL }}
```

주의 2건: (1) `.chezmoi.kernel`은 Linux에서만 존재하므로 반드시 `and (eq .chezmoi.os "linux") (...)` 가드 안에서만 접근한다. (2) `promptStringOnce`의 프롬프트 문구는 반드시 `"email"` 그대로 둔다 — chezmoi의 `--promptString key=value` 주입은 **프롬프트 문구를 키로 매칭**하므로, 문구를 바꾸면 모든 테스트의 `--promptString email=...`이 무시된다(개인/회사 이메일 안내는 bootstrap이 init 직전에 echo로 출력, Task 10).

- [ ] **Step 3: `home/.chezmoiignore` 작성**

```
{{ if ne .chezmoi.os "windows" }}
Documents
{{ end }}
{{ if eq .chezmoi.os "windows" }}
.zshrc
.config/bat
{{ end }}
```

- [ ] **Step 4: `tests/lint.sh` 작성**

셸 템플릿은 `{{...}}`를 플레이스홀더로 치환한 뒤 shellcheck에 통과시킨다(순수 셸 문법 검증). PowerShell은 컨테이너의 PSScriptAnalyzer로 검사한다.

```bash
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
#    SC2034/SC2050/SC2154(치환 잔재), SC1091(source 대상 미추적 info),
#    SC1007(빈 env 프리픽스 `VAR= cmd` 오탐 — zshrc의 WAYLAND_DISPLAY= 관용구)
for f in home/.chezmoiscripts/*.sh.tmpl home/dot_zshrc.tmpl; do
  [ -f "$f" ] || continue
  echo "shellcheck(tmpl): $f"
  strip_tmpl "$f" | $SHELLCHECK -s bash -e SC2034,SC2050,SC2154,SC1091,SC1007 - || fail=1
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
```

- [ ] **Step 5: 린트 하네스 자체 검증**

Run: `bash tests/lint.sh`
Expected: `shellcheck: tests/lint.sh` 출력 후 `LINT PASS` (아직 템플릿 파일이 없으므로 lint.sh 자신만 검사됨)

- [ ] **Step 6: 렌더링 검증 — isWSL 유도와 FORCE_WSL 오버라이드**

Run:

```bash
cd ~/Projects/machine-setup
# 이 머신은 WSL이므로 기본 유도 결과는 true
nix run nixpkgs#chezmoi -- execute-template --init --promptString email=test@test.com \
  "$(cat home/.chezmoi.toml.tmpl)"
# FORCE_WSL 오버라이드
FORCE_WSL=false nix run nixpkgs#chezmoi -- execute-template --init --promptString email=test@test.com \
  "$(cat home/.chezmoi.toml.tmpl)"
```

Expected: 첫 실행은 `isWSL = true`, 둘째 실행은 `isWSL = false`를 포함한 TOML 출력. `email = "test@test.com"` 포함

- [ ] **Step 7: Commit**

```bash
git add .chezmoiroot .gitignore home/.chezmoi.toml.tmpl home/.chezmoiignore tests/lint.sh
git commit -m "feat: chezmoi 저장소 뼈대 + 린트 하네스"
```

---

### Task 2: packages.yaml — 패키지 목록 단일 소스

**Files:**
- Create: `home/.chezmoidata/packages.yaml`

**Interfaces:**
- Produces: 템플릿 데이터 `.packages.*` — 이후 모든 패키지/폰트 스크립트가 참조. 키 구조:
  - `.packages.brew.taps` (list), `.packages.brew.formulae` (list, macOS/Linux 공통), `.packages.brew.darwin_only_formulae`, `.packages.brew.casks`, `.packages.brew.font_casks`
  - `.packages.apt.common`, `.packages.apt.desktop`, `.packages.apt.wsl`, `.packages.apt.fonts`
  - `.packages.snap.desktop` (list)
  - `.packages.deb` — `{name, dpkg_name, url}` 오브젝트 리스트 (desktop 전용)
  - `.packages.winget.ids` (list)
  - `.packages.fonts.nerd_version` (string), `.packages.fonts.nerd_zips` (list)

- [ ] **Step 1: `home/.chezmoidata/packages.yaml` 작성**

```yaml
packages:
  brew:
    taps:
      - d12frosted/emacs-plus
    # macOS/Ubuntu 공통 CLI (Linux bottle 전수 확인됨)
    formulae:
      - ripgrep
      - fd
      - bat
      - eza
      - fzf          # >=0.48 필요 (--zsh 통합). brew 최신은 0.74
      - zoxide
      - jq
      - yq
      - htop
      - btop
      - tree
      - tlrc         # tldr 클라이언트 (brew의 tldr formula는 disabled)
      - dust
      - duf
      - procs
      - gh
      - glab
      - lazygit
      - git-delta
      - direnv
      - httpie
      - openssl@3
      - lsof
      - zip
      - unzip
      - sevenzip     # 공식 7-Zip (p7zip은 구버전 fork). 바이너리 7zz
      - xz
      - rsync
      - rename
      - dos2unix
      - watch
      - fswatch
      - pstree
      - node
      - bun
      - uv           # Python은 uv가 관리
      - go
      - rustup       # PATH는 ~/.cargo/bin (zshrc에서 추가)
      - openjdk
      - make         # GNU make (macOS에선 gmake로 설치됨)
      - cmake
      - llvm
      - libtool      # macOS: glibtool로 설치 — Emacs vterm 빌드 의존성
      - neovim
      # LSP류 제외 (스펙 §2): basedpyright, nil, sqls, jdt-language-server, leiningen
    # GNU 유저랜드는 macOS만 (Linux는 시스템 기본이 GNU)
    darwin_only_formulae:
      - git          # Ubuntu는 bootstrap에서 apt로 설치
      - zsh          # macOS 기본 zsh 최신화
      - coreutils
      - findutils
      - grep
      - gnu-sed
      - gawk
      - colima
      - docker       # CLI만 (데몬은 colima)
      - d12frosted/emacs-plus/emacs-plus@30
    casks:
      - arc
      - wezterm
      - visual-studio-code
      - zed
      - godot
      - figma
      - blender
      - love
      - tiled
      - obsidian
      - gimp
      - slack
      - discord
      - telegram
      - spotify
      - vlc
      - 1password
      - appcleaner
      - the-unarchiver
      - hiddenbar
      - stats
    font_casks:
      - font-jetbrains-mono-nerd-font
      - font-fira-code-nerd-font
      - font-hack-nerd-font
      - font-iosevka-nerd-font
      - font-meslo-lg-nerd-font
      - font-sauce-code-pro-nerd-font
      - font-ubuntu-mono-nerd-font
      - font-droid-sans-mono-nerd-font
      - font-terminess-ttf-nerd-font
      - font-zed-mono-nerd-font
      - font-d2coding-nerd-font
      - font-iosevka-term-nerd-font        # 비패치 Term cask 부재 — Nerd판으로 대체
      - font-iosevka-term-slab-nerd-font
      - font-jetbrains-mono
      - font-fira-code
      - font-source-code-pro
      - font-cascadia-code
      - font-departure-mono
      - font-inter
      - font-roboto
      - font-open-sans
      - font-source-sans-3
      - font-source-serif-4
      - font-noto-sans
      - font-noto-serif
      - font-noto-sans-cjk-kr
      - font-noto-serif-cjk-kr
      - font-noto-color-emoji
      - font-d2coding
      - font-fontawesome
      - font-material-icons
      - font-material-symbols
  apt:
    # desktop/WSL 공통 (시스템 통합 계층)
    common:
      - zsh              # brew zsh는 /etc/shells 문제로 apt 고정 (스펙 §6.1)
      - build-essential
      - xclip
      - trash-cli        # nvim Snacks.explorer 안전 삭제 의존성
      - alsa-utils
      - pulseaudio-utils # pactl (pipewire 데몬과 충돌 없음)
      - emacs-pgtk       # ppa:ubuntuhandbook1/emacs (30.x, Wayland/WSLg 네이티브)
      - wezterm          # apt.fury.io/wez repo
    desktop:
      - code             # packages.microsoft.com repo (WSL은 Windows측 VS Code 사용)
      - ffmpeg           # ~/Projects/fulang 비디오 파이프라인 의존성
      - vlc
      - gimp
      - ibus-hangul
    wsl:
      - wslu             # wslview 등
      - fcitx5
      - fcitx5-hangul
      - fcitx5-config-qt
    fonts:
      - fonts-noto
      - fonts-noto-cjk
      - fonts-noto-color-emoji
      - fonts-font-awesome
      - fonts-inter
      - fonts-roboto
      - fonts-open-sans
      - fonts-cascadia-code
      - fonts-jetbrains-mono
      - fonts-firacode
      - fonts-naver-d2coding
      - fonts-materialdesignicons-webfont
      # source-code-pro/source-sans/source-serif/material-symbols는 noble apt에 없음
      # → Nerd SourceCodePro가 코딩 용도 커버 (의도적 제외)
    # snap은 systemd 필요 — 40-services와 동일 가드 하에 설치
  snap:
    desktop:
      - firefox
      - spotify
      - telegram-desktop
  # 공식 deb 직배포 앱 (desktop 전용, dpkg -s로 멱등)
  deb:
    - name: obsidian
      dpkg_name: obsidian
      url: ""            # 빈 값 = GitHub API로 latest 조회 (10-packages-ubuntu 참조)
    - name: slack
      dpkg_name: slack-desktop
      url: "https://downloads.slack-edge.com/desktop-releases/linux/x64/4.50.143/slack-desktop-4.50.143-amd64.deb"
    - name: discord
      dpkg_name: discord
      url: "https://discord.com/api/download?platform=linux&format=deb"
      # slack 버전 업그레이드 시 url의 버전만 교체 (고정 latest URL 없음)
  winget:
    ids:
      # CLI (POSIX 전용 도구 제외 서브셋 — 스펙 §6.2. httpie는 winget에 CLI 없음 → 제외)
      - Git.Git
      - GitHub.cli
      - GLab.GLab
      - BurntSushi.ripgrep.MSVC
      - sharkdp.fd
      - sharkdp.bat
      - eza-community.eza
      - junegunn.fzf
      - ajeetdsouza.zoxide
      - jqlang.jq
      - MikeFarah.yq
      - dandavison.delta
      - JesseDuffield.lazygit
      - bootandy.dust
      - muesli.duf
      - dalance.procs
      - tldr-pages.tlrc
      - Neovim.Neovim
      - GNU.Emacs
      - twpayne.chezmoi
      # 언어 런타임
      - OpenJS.NodeJS.LTS
      - Oven-sh.Bun
      - astral-sh.uv
      - GoLang.Go
      - Rustlang.Rustup
      - Microsoft.OpenJDK.21
      # GUI
      - Microsoft.PowerShell
      - Microsoft.WindowsTerminal
      - Microsoft.PowerToys
      - wez.wezterm
      - Microsoft.VisualStudioCode
      - Docker.DockerDesktop
      - tailscale.Tailscale
      - AgileBits.1Password
      - SlackTechnologies.Slack
      - Discord.Discord
      - Telegram.TelegramDesktop
      - Spotify.Spotify
      - VideoLAN.VLC
      - Obsidian.Obsidian
  fonts:
    nerd_version: "3.4.0"
    # asset명 주의: SauceCodePro → SourceCodePro.zip, Terminess → Terminus.zip
    nerd_zips:
      - JetBrainsMono
      - FiraCode
      - Hack
      - Iosevka
      - IosevkaTerm
      - IosevkaTermSlab
      - Meslo
      - SourceCodePro
      - UbuntuMono
      - DroidSansMono
      - Terminus
      - ZedMono
      - D2Coding
      - DepartureMono
```

- [ ] **Step 2: YAML 문법 + 키 구조 검증**

Run:

```bash
cd ~/Projects/machine-setup
yq '.packages.brew.formulae | length' home/.chezmoidata/packages.yaml
yq '.packages.winget.ids | length' home/.chezmoidata/packages.yaml
yq '.packages.fonts.nerd_zips | length' home/.chezmoidata/packages.yaml
yq '.packages.deb[].dpkg_name' home/.chezmoidata/packages.yaml
```

Expected: `44` / `40` / `14` / `obsidian`·`slack-desktop`·`discord` (에러 없이 출력)

- [ ] **Step 3: chezmoi 데이터로 로드되는지 검증**

주의: `execute-template --init`은 `.chezmoidata`를 로드하지 않으므로 임시 config를 먼저 생성한다.

Run:

```bash
cd ~/Projects/machine-setup
mkdir -p /tmp/czt
FORCE_WSL=false nix run nixpkgs#chezmoi -- init --source . --config /tmp/czt/chezmoi.toml \
  --promptString email=t@t.com
nix run nixpkgs#chezmoi -- --source . --config /tmp/czt/chezmoi.toml execute-template \
  '{{ .packages.fonts.nerd_version }} {{ len .packages.brew.formulae }}'
```

Expected: `3.4.0 44`

- [ ] **Step 4: Commit**

```bash
git add home/.chezmoidata/packages.yaml
git commit -m "feat: packages.yaml — 전 플랫폼 패키지 목록 단일 소스 (전수 검증된 ID)"
```

---

### Task 3: dotfiles — zshrc / git config / bat config (+렌더링 헬퍼)

**Files:**
- Create: `tests/render.sh`
- Create: `home/dot_zshrc.tmpl`
- Create: `home/dot_config/git/config.tmpl`
- Create: `home/dot_config/bat/config`

**Interfaces:**
- Consumes: `.email`, `.isWSL` (Task 1), `.packages` (Task 2)
- Produces: `rebuild`/`update` alias 정의 — README(Task 10)가 문서화
- Produces: `tests/render.sh <true|false> <template-file>` — 이후 모든 태스크의 렌더링 검증이 사용 (email은 `t@t.com` 고정)

- [ ] **Step 1: 렌더링 헬퍼 `tests/render.sh` 작성**

```bash
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
```

- [ ] **Step 2: `home/dot_zshrc.tmpl` 작성**

```
# Managed by chezmoi — 수정은 ~/Projects/machine-setup에서.
{{ if eq .chezmoi.os "linux" -}}
# Homebrew on Linux
[ -d /home/linuxbrew/.linuxbrew ] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
{{ end -}}
{{ if eq .chezmoi.os "darwin" -}}
eval "$(/opt/homebrew/bin/brew shellenv)"
{{ end -}}

# oh-my-zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="lambda"
plugins=(git sudo docker kubectl history colored-man-pages)
[ -f "$ZSH/oh-my-zsh.sh" ] && source "$ZSH/oh-my-zsh.sh"

# Emacs keybindings
bindkey -e

# Environment
export EDITOR="emacsclient -a nvim"
export VISUAL="emacsclient -a nvim"
export PAGER="less"
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

# PATH
export PATH="$PATH:$HOME/.npm/bin"
export PATH="$PATH:$HOME/.config/emacs/bin"
export PATH="$PATH:$HOME/.bun/bin"
export PATH="$PATH:$HOME/.local/bin"
export PATH="$PATH:$HOME/.cargo/bin"
export PATH="$PATH:$HOME/Projects/x"

{{ if .isWSL -}}
# --- WSL 전용 ---
# GUI 앱 입력기 (fcitx5)
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
# WSLg에서 Chromium/Electron GPU 비가속 동작
export LIBGL_ALWAYS_SOFTWARE=1
alias open="wslview"

# fcitx5 자동 시작 — WSLg 컴포지터가 zwp_input_method_v1 바인딩을 거부하므로
# WAYLAND_DISPLAY를 비워 X11/XIM 경로로 데몬을 띄운다 (load-bearing).
if command -v fcitx5 >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
  pgrep -x fcitx5 >/dev/null 2>&1 || (WAYLAND_DISPLAY= fcitx5 -d >/dev/null 2>&1 &)
fi
{{ end -}}

# rebuild: 저장소 pull + 적용 / update: 패키지 업그레이드 + rebuild
alias rebuild="chezmoi update"
{{ if eq .chezmoi.os "darwin" -}}
alias update="brew update && brew upgrade && brew upgrade --cask && chezmoi update"
{{ else -}}
alias update="sudo apt-get update && sudo apt-get upgrade -y && brew update && brew upgrade && chezmoi update"
{{ end -}}

# Shell integrations
command -v fzf >/dev/null 2>&1 && eval "$(fzf --zsh)"
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"

# 개인 추가 설정 (있을 때만)
[ -f "$HOME/Projects/x/x.sh" ] && source "$HOME/Projects/x/x.sh"
```

제외 확인: `em`/`emc` 함수, alias `e`/`v`/`ccc`, Jira env — 스펙 §2 사용자 결정으로 포함하지 않는다.

- [ ] **Step 3: `home/dot_config/git/config.tmpl` 작성**

```
[user]
	name = Kyeongsoo
	email = {{ .email }}
[init]
	defaultBranch = main
[pull]
	rebase = true
	ff = true
[push]
	autoSetupRemote = true
[core]
	quotePath = false
	pager = delta
[interactive]
	diffFilter = delta --color-only
[delta]
	navigate = true
[credential]
	helper = store
```

- [ ] **Step 4: `home/dot_config/bat/config` 작성**

```
--theme="Dracula"
```

- [ ] **Step 5: 렌더링 검증 — WSL/desktop 양쪽 컨텍스트**

Run:

```bash
cd ~/Projects/machine-setup
# WSL 컨텍스트: fcitx5 블록 있어야 함
bash tests/render.sh true home/dot_zshrc.tmpl | grep -c "fcitx5 -d"
# desktop 컨텍스트: fcitx5 블록 없어야 함
bash tests/render.sh false home/dot_zshrc.tmpl | grep -c "fcitx5 -d" || true
# git config에 email 주입 확인 (헬퍼는 email=t@t.com 고정)
bash tests/render.sh false home/dot_config/git/config.tmpl | grep "email ="
```

Expected: 첫 grep은 `1`, 둘째 grep은 `0`, 셋째는 `	email = t@t.com`

- [ ] **Step 6: 렌더링된 zshrc 문법 검증**

Run:

```bash
bash tests/render.sh true home/dot_zshrc.tmpl > /tmp/zshrc-rendered
zsh -n /tmp/zshrc-rendered && echo SYNTAX-OK
bash tests/lint.sh
```

Expected: `SYNTAX-OK`, `LINT PASS`

- [ ] **Step 7: Commit**

```bash
git add tests/render.sh home/dot_zshrc.tmpl home/dot_config/git/config.tmpl home/dot_config/bat/config
git commit -m "feat: dotfiles — zshrc/git/bat + 렌더링 헬퍼 (home.nix 이관, 개인 항목 제외)"
```

---

### Task 4: 10-packages-ubuntu (apt repo + apt + brew + deb + snap)

**Files:**
- Create: `home/.chezmoiscripts/run_onchange_before_10-packages-ubuntu.sh.tmpl`

**Interfaces:**
- Consumes: `.packages.apt.*`, `.packages.brew.formulae`, `.packages.deb`, `.packages.snap.desktop`, `.isWSL` (Task 1·2)
- Produces: brew가 `/home/linuxbrew/.linuxbrew`에 설치돼 있다는 전제(bootstrap이 보장, Task 11)

- [ ] **Step 1: 스크립트 작성**

```
{{ if eq .chezmoi.os "linux" -}}
#!/bin/bash
# packages.yaml 변경 시 재실행: {{ .packages | toJson | sha256sum }}
set -euo pipefail

echo ">> [10-packages-ubuntu] third-party apt repos"

# wezterm (apt.fury.io/wez)
if [ ! -f /etc/apt/sources.list.d/wezterm.list ]; then
  curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg
  sudo chmod 644 /usr/share/keyrings/wezterm-fury.gpg
  echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | sudo tee /etc/apt/sources.list.d/wezterm.list >/dev/null
fi

# VS Code (packages.microsoft.com)
if [ ! -f /etc/apt/sources.list.d/vscode.list ]; then
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --yes --dearmor -o /usr/share/keyrings/microsoft.gpg
  echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
fi

# emacs 30.x PPA (서드파티: ubuntuhandbook1)
if ! compgen -G "/etc/apt/sources.list.d/*ubuntuhandbook1*" > /dev/null; then
  sudo add-apt-repository -y ppa:ubuntuhandbook1/emacs
fi

# docker-ce (다이나믹 codename — docs.docker.com 권장 형태)
if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
fi

{{ if not .isWSL -}}
# tailscale (desktop만 — 스펙 §10)
if [ ! -f /etc/apt/sources.list.d/tailscale.list ]; then
  curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
  curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null
fi
{{ end -}}

echo ">> [10-packages-ubuntu] apt install"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  {{ range .packages.apt.common }}{{ . }} {{ end }} \
  {{ range .packages.apt.fonts }}{{ . }} {{ end }} \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
{{ if .isWSL }}  {{ range .packages.apt.wsl }}{{ . }} {{ end }}
{{ else }}  {{ range .packages.apt.desktop }}{{ . }} {{ end }} tailscale openssh-server
{{ end }}

echo ">> [10-packages-ubuntu] brew install (userland CLI)"
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
brew install --quiet {{ range .packages.brew.formulae }}{{ . }} {{ end }}

{{ if not .isWSL -}}
echo ">> [10-packages-ubuntu] official debs (desktop)"
{{ range .packages.deb -}}
if ! dpkg -s {{ .dpkg_name }} >/dev/null 2>&1; then
  tmp_deb="$(mktemp --suffix=.deb)"
{{ if eq .name "obsidian" -}}
  ver="$(curl -fsSL https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest | jq -r '.tag_name | ltrimstr("v")')"
  curl -fsSL -o "$tmp_deb" "https://github.com/obsidianmd/obsidian-releases/releases/download/v${ver}/obsidian_${ver}_amd64.deb"
{{ else -}}
  curl -fsSL -o "$tmp_deb" "{{ .url }}"
{{ end -}}
  sudo apt-get install -y "$tmp_deb"
  rm -f "$tmp_deb"
fi
{{ end -}}

# snap (systemd 필요 — 컨테이너/미활성 환경에서는 건너뜀)
if [ -d /run/systemd/system ] && command -v snap >/dev/null 2>&1; then
{{ range .packages.snap.desktop -}}
  snap list {{ . }} >/dev/null 2>&1 || sudo snap install {{ . }}
{{ end -}}
else
  echo ">> snap 생략 (systemd 비활성): {{ range .packages.snap.desktop }}{{ . }} {{ end }}"
fi
{{ end -}}

echo ">> [10-packages-ubuntu] done"
{{ end -}}
```

주의: jq는 brew로 설치되지만 obsidian 단계에서 필요하므로 apt 이후·brew 이후 순서가 유지돼야 한다(스크립트 내 순서가 이미 보장).

- [ ] **Step 2: 렌더링 검증 (WSL/desktop 컨텍스트)**

Run:

```bash
cd ~/Projects/machine-setup
SRC=home/.chezmoiscripts/run_onchange_before_10-packages-ubuntu.sh.tmpl
# desktop: tailscale repo 포함, wsl 패키지 미포함
bash tests/render.sh false $SRC | grep -c "tailscale"
# WSL: tailscale 없음, fcitx5 있음
bash tests/render.sh true $SRC > /tmp/r-wsl.sh
grep -c "tailscale" /tmp/r-wsl.sh || true
grep -c "fcitx5" /tmp/r-wsl.sh
bash -n /tmp/r-wsl.sh && echo SYNTAX-OK
```

Expected: desktop grep ≥ `3`, WSL의 tailscale grep `0`, fcitx5 grep ≥ `1`, `SYNTAX-OK`

- [ ] **Step 3: 린트**

Run: `bash tests/lint.sh`
Expected: `LINT PASS`

- [ ] **Step 4: Commit**

```bash
git add home/.chezmoiscripts/run_onchange_before_10-packages-ubuntu.sh.tmpl
git commit -m "feat: Ubuntu 패키지 스크립트 — apt repo/apt/brew/deb/snap"
```

---

### Task 5: 10-packages-darwin + 10-packages-windows

**Files:**
- Create: `home/.chezmoiscripts/run_onchange_before_10-packages-darwin.sh.tmpl`
- Create: `home/.chezmoiscripts/run_onchange_before_10-packages-windows.ps1.tmpl`

**Interfaces:**
- Consumes: `.packages.brew.*`, `.packages.winget.ids` (Task 2)

- [ ] **Step 1: darwin 스크립트 작성 (Brewfile 인라인 생성 + brew bundle)**

```
{{ if eq .chezmoi.os "darwin" -}}
#!/bin/bash
# packages.yaml 변경 시 재실행: {{ .packages | toJson | sha256sum }}
set -euo pipefail
eval "$(/opt/homebrew/bin/brew shellenv)"

echo ">> [10-packages-darwin] brew bundle"
brew bundle --file=/dev/stdin <<'BREWFILE'
cask_args no_quarantine: true
{{ range .packages.brew.taps -}}
tap "{{ . }}"
{{ end -}}
{{ range .packages.brew.formulae -}}
brew "{{ . }}"
{{ end -}}
{{ range .packages.brew.darwin_only_formulae -}}
{{ if eq . "d12frosted/emacs-plus/emacs-plus@30" -}}
brew "{{ . }}", args: ["with-xwidgets", "with-imagemagick"]
{{ else -}}
brew "{{ . }}"
{{ end -}}
{{ end -}}
{{ range .packages.brew.casks -}}
cask "{{ . }}"
{{ end -}}
BREWFILE
echo ">> [10-packages-darwin] done"
{{ end -}}
```

주의: heredoc 구분자는 `'BREWFILE'`(따옴표)로 셸 확장을 막지만, chezmoi 템플릿은 셸 실행 전에 렌더링되므로 `{{ range }}`는 정상 전개된다.

- [ ] **Step 2: windows 스크립트 작성**

```
{{ if eq .chezmoi.os "windows" -}}
# packages.yaml 변경 시 재실행: {{ .packages | toJson | sha256sum }}
$ErrorActionPreference = 'Stop'
Write-Host ">> [10-packages-windows] winget install"
$ids = @(
{{ range .packages.winget.ids -}}
  '{{ . }}',
{{ end -}}
  $null
) | Where-Object { $_ }
foreach ($id in $ids) {
  winget list --id $id --exact --accept-source-agreements 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "   already installed: $id"
  } else {
    winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { Write-Warning "install failed: $id" }
  }
}
Write-Host ">> [10-packages-windows] done"
{{ end -}}
```

주의: winget 실패는 경고로 처리(개별 패키지 장애가 전체 apply를 막지 않도록). `$null` 트릭은 마지막 원소의 trailing comma를 무해하게 만든다.

- [ ] **Step 3: 렌더링·린트 검증**

Run:

```bash
cd ~/Projects/machine-setup
# darwin 스크립트는 linux 컨텍스트에서 빈 본문이어야 함
bash tests/render.sh false home/.chezmoiscripts/run_onchange_before_10-packages-darwin.sh.tmpl | wc -c
bash tests/lint.sh
bash tests/lint.sh --ps
```

Expected: `wc -c`는 `0` 또는 공백 수준(빈 렌더링), `LINT PASS` 두 번

- [ ] **Step 4: Commit**

```bash
git add home/.chezmoiscripts/run_onchange_before_10-packages-darwin.sh.tmpl \
        home/.chezmoiscripts/run_onchange_before_10-packages-windows.ps1.tmpl
git commit -m "feat: macOS Brewfile 번들 + Windows winget 설치 스크립트"
```

---

### Task 6: 20-fonts (ubuntu / darwin / windows)

**Files:**
- Create: `home/.chezmoiscripts/run_onchange_after_20-fonts-ubuntu.sh.tmpl`
- Create: `home/.chezmoiscripts/run_onchange_after_20-fonts-darwin.sh.tmpl`
- Create: `home/.chezmoiscripts/run_onchange_after_20-fonts-windows.ps1.tmpl`

**Interfaces:**
- Consumes: `.packages.fonts.nerd_version`, `.packages.fonts.nerd_zips`, `.packages.brew.font_casks` (Task 2)
- Produces: Linux 폰트 설치 위치 `~/.local/share/fonts/<ZipName>/` — 디렉터리 존재가 멱등 마커

- [ ] **Step 1: ubuntu 폰트 스크립트 작성**

```
{{ if eq .chezmoi.os "linux" -}}
#!/bin/bash
# fonts 목록 변경 시 재실행: {{ .packages.fonts | toJson | sha256sum }}
set -euo pipefail
NERD_VER="{{ .packages.fonts.nerd_version }}"
FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"
changed=0
{{ range .packages.fonts.nerd_zips -}}
if [ ! -d "$FONT_DIR/{{ . }}" ]; then
  echo ">> [20-fonts] {{ . }} v${NERD_VER}"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/{{ . }}.zip" \
    "https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERD_VER}/{{ . }}.zip"
  unzip -q "$tmp/{{ . }}.zip" -d "$FONT_DIR/{{ . }}"
  rm -rf "$tmp"
  changed=1
fi
{{ end -}}
[ "$changed" -eq 1 ] && fc-cache -f "$FONT_DIR" || true
echo ">> [20-fonts-ubuntu] done"
{{ end -}}
```

주의: unzip은 bootstrap 시점에 없을 수 있으나 이 스크립트는 after(=10-packages의 apt/brew 완료 후)에 돌므로 brew unzip이 존재한다. Nerd Fonts 버전을 올릴 때는 `nerd_version`만 수정하면 해시가 바뀌어 재실행되지만, 기존 디렉터리 마커 때문에 재다운로드는 안 됨 — 버전 업그레이드 시에는 `rm -rf ~/.local/share/fonts/<Name>` 후 rebuild (README에 기재, Task 10).

- [ ] **Step 2: darwin 폰트 스크립트 작성**

```
{{ if eq .chezmoi.os "darwin" -}}
#!/bin/bash
# font casks 변경 시 재실행: {{ .packages.brew.font_casks | toJson | sha256sum }}
set -euo pipefail
eval "$(/opt/homebrew/bin/brew shellenv)"
echo ">> [20-fonts-darwin] font casks"
brew install --cask --quiet {{ range .packages.brew.font_casks }}{{ . }} {{ end }}
echo ">> [20-fonts-darwin] done"
{{ end -}}
```

- [ ] **Step 3: windows 폰트 스크립트 작성 (사용자 레벨 설치 — 관리자 불필요)**

```
{{ if eq .chezmoi.os "windows" -}}
# fonts 목록 변경 시 재실행: {{ .packages.fonts | toJson | sha256sum }}
$ErrorActionPreference = 'Stop'
$nerdVer = '{{ .packages.fonts.nerd_version }}'
$fontRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$regPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
New-Item -ItemType Directory -Force -Path $fontRoot | Out-Null
if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }

$zips = @(
{{ range .packages.fonts.nerd_zips -}}
  '{{ . }}',
{{ end -}}
  $null
) | Where-Object { $_ }

foreach ($z in $zips) {
  # 멱등 마커($marker)는 성공 시에만 존재해야 한다: 스테이징에 풀고 성공 시 이동,
  # 실패 시 마커 제거 — Expand-Archive는 실패해도 대상 디렉터리를 만들기 때문.
  $marker = Join-Path $fontRoot $z
  if (Test-Path $marker) { continue }
  Write-Host ">> [20-fonts] $z v$nerdVer"
  $tmp = Join-Path $env:TEMP "$z.zip"
  $staging = Join-Path $env:TEMP "nf-$z"
  try {
    Invoke-WebRequest -Uri "https://github.com/ryanoasis/nerd-fonts/releases/download/v$nerdVer/$z.zip" -OutFile $tmp
    if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
    Expand-Archive -Path $tmp -DestinationPath $staging -Force
    Move-Item -Path $staging -Destination $marker
    Get-ChildItem -Path $marker -Include '*.ttf','*.otf' -Recurse | ForEach-Object {
      $name = "$($_.BaseName) (TrueType)"
      New-ItemProperty -Path $regPath -Name $name -Value $_.FullName -PropertyType String -Force | Out-Null
    }
  } catch {
    if (Test-Path $marker) { Remove-Item -Recurse -Force $marker }
    throw
  } finally {
    Remove-Item -Force -ErrorAction SilentlyContinue $tmp
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $staging
  }
}
Write-Host ">> [20-fonts-windows] done (새 앱 세션부터 인식)"
{{ end -}}
```

- [ ] **Step 4: 렌더링·린트 검증**

Run:

```bash
cd ~/Projects/machine-setup
bash tests/render.sh false home/.chezmoiscripts/run_onchange_after_20-fonts-ubuntu.sh.tmpl > /tmp/r-fonts.sh
bash -n /tmp/r-fonts.sh && echo SYNTAX-OK
grep -c 'NERD_VER="3.4.0"' /tmp/r-fonts.sh                    # 버전 고정 확인 (URL은 ${NERD_VER} 변수 참조)
grep -c "nerd-fonts/releases/download" /tmp/r-fonts.sh        # 14개 폰트 블록 = 14개 다운로드 URL
grep -c "SourceCodePro.zip" /tmp/r-fonts.sh                   # SauceCodePro가 아님을 확인 (블록당 3줄 매치)
bash tests/lint.sh && bash tests/lint.sh --ps
```

Expected: `SYNTAX-OK`, 첫 grep `1`, 둘째 grep `14`, 셋째 grep `3`, `LINT PASS` 두 번

- [ ] **Step 5: Commit**

```bash
git add home/.chezmoiscripts/run_onchange_after_20-fonts-*.tmpl
git commit -m "feat: 폰트 설치 — Nerd Fonts v3.4.0 + cask/사용자레벨 설치"
```

---

### Task 7: 25-oh-my-zsh + 30-os-settings (darwin / gnome / windows)

**Files:**
- Create: `home/.chezmoiscripts/run_once_after_25-oh-my-zsh.sh.tmpl`
- Create: `home/.chezmoiscripts/run_onchange_after_30-os-settings-darwin.sh.tmpl`
- Create: `home/.chezmoiscripts/run_onchange_after_30-os-settings-gnome.sh.tmpl`
- Create: `home/.chezmoiscripts/run_onchange_after_30-os-settings-windows.ps1.tmpl`

**Interfaces:**
- Consumes: `.isWSL` (Task 1)
- Produces: 없음 (말단 설정)

- [ ] **Step 1: oh-my-zsh 스크립트 작성**

```
{{ if ne .chezmoi.os "windows" -}}
#!/bin/bash
set -euo pipefail
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo ">> [25-oh-my-zsh] install (unattended)"
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc
fi
{{ if eq .chezmoi.os "linux" -}}
# 기본 셸 전환 (apt zsh = /usr/bin/zsh, /etc/shells 등재 자동)
if [ "$(getent passwd "$USER" | cut -d: -f7)" != "/usr/bin/zsh" ]; then
  echo ">> [25-oh-my-zsh] chsh -s /usr/bin/zsh"
  sudo chsh -s /usr/bin/zsh "$USER"
fi
{{ end -}}
echo ">> [25-oh-my-zsh] done"
{{ end -}}
```

`--unattended`는 RUNZSH=no + CHSH=no와 동일(검증됨), `--keep-zshrc`는 chezmoi가 배치한 `.zshrc`를 보존한다.

- [ ] **Step 2: darwin OS 설정 스크립트 작성 — `~/Projects/nix/darwin/system.nix` 전 항목 1:1**

```
{{ if eq .chezmoi.os "darwin" -}}
#!/bin/bash
set -euo pipefail
echo ">> [30-os-settings-darwin] defaults write"

# --- Dock ---
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0.0
defaults write com.apple.dock autohide-time-modifier -float 0.4
defaults write com.apple.dock expose-animation-duration -float 0.1
defaults write com.apple.dock minimize-to-application -bool true
defaults write com.apple.dock mru-spaces -bool false
defaults write com.apple.dock orientation -string "bottom"
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock showhidden -bool true
defaults write com.apple.dock tilesize -int 48
defaults write com.apple.dock persistent-apps -array
defaults write com.apple.dock wvous-tl-corner -int 1
defaults write com.apple.dock wvous-tr-corner -int 1
defaults write com.apple.dock wvous-bl-corner -int 1
defaults write com.apple.dock wvous-br-corner -int 1

# --- Finder ---
defaults write com.apple.finder AppleShowAllExtensions -bool true
defaults write com.apple.finder AppleShowAllFiles -bool true
defaults write com.apple.finder CreateDesktop -bool false
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"
defaults write com.apple.finder QuitMenuItem -bool true
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
defaults write com.apple.finder _FXSortFoldersFirst -bool true

# --- NSGlobalDomain ---
defaults write NSGlobalDomain AppleInterfaceStyle -string "Dark"
defaults write NSGlobalDomain AppleInterfaceStyleSwitchesAutomatically -bool false
defaults write NSGlobalDomain AppleICUForce24HourTime -bool true
defaults write NSGlobalDomain AppleMeasurementUnits -string "Centimeters"
defaults write NSGlobalDomain AppleMetricUnits -int 1
defaults write NSGlobalDomain AppleTemperatureUnit -string "Celsius"
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write NSGlobalDomain AppleShowAllFiles -bool true
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true
defaults write NSGlobalDomain NSTableViewDefaultSizeMode -int 2
defaults write NSGlobalDomain NSWindowResizeTime -float 0.1
defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false
defaults write NSGlobalDomain com.apple.trackpad.scaling -float 2.0

# --- Trackpad ---
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
defaults write com.apple.AppleMultitouchTrackpad TrackpadRightClick -bool true
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRightClick -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -bool true

# --- Login window / Clock / Screensaver / Screenshots ---
sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false
sudo defaults write /Library/Preferences/com.apple.loginwindow DisableConsoleAccess -bool true
defaults write com.apple.menuextra.clock Show24Hour -bool true
defaults write com.apple.menuextra.clock ShowDate -int 1
defaults write com.apple.menuextra.clock ShowDayOfWeek -bool true
defaults write com.apple.menuextra.clock ShowSeconds -bool false
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 5
mkdir -p "$HOME/Pictures/Screenshots"
defaults write com.apple.screencapture disable-shadow -bool true
defaults write com.apple.screencapture location -string "$HOME/Pictures/Screenshots"
defaults write com.apple.screencapture type -string "png"

# --- Custom preferences ---
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true
defaults write com.apple.AdLib allowApplePersonalizedAdvertising -bool false
defaults write com.apple.TextEdit RichText -int 0
defaults write com.apple.DiskUtility DUDebugMenuEnabled -bool true
defaults write com.apple.DiskUtility advanced-image-options -bool true

# --- 시동음 ---
sudo nvram StartupMute=%01

# --- TouchID sudo (idempotent) ---
if [ ! -f /etc/pam.d/sudo_local ] || ! grep -q pam_tid.so /etc/pam.d/sudo_local; then
  echo "auth       sufficient     pam_tid.so" | sudo tee -a /etc/pam.d/sudo_local >/dev/null
fi

# --- emacs-plus Emacs.app → /Applications (Spotlight) ---
EMACS_APP="$(find /opt/homebrew/Cellar/emacs-plus@30 -maxdepth 2 -name "Emacs.app" -type d 2>/dev/null | head -1)"
if [ -n "$EMACS_APP" ] && [ ! -d /Applications/Emacs.app ]; then
  echo ">> copying Emacs.app to /Applications"
  cp -R "$EMACS_APP" /Applications/
fi

killall Dock Finder SystemUIServer 2>/dev/null || true
echo ">> [30-os-settings-darwin] done (일부 항목은 재로그인 필요)"
{{ end -}}
```

- [ ] **Step 3: gnome OS 설정 스크립트 작성**

```
{{ if and (eq .chezmoi.os "linux") (not .isWSL) -}}
#!/bin/bash
set -euo pipefail
if ! command -v gsettings >/dev/null 2>&1; then
  echo ">> [30-os-settings-gnome] gsettings 없음 — 건너뜀 (GNOME 미설치 환경)"
  exit 0
fi
echo ">> [30-os-settings-gnome] gsettings"
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface clock-format '24h'
gsettings set org.gnome.desktop.peripherals.keyboard repeat-interval 30
gsettings set org.gnome.desktop.peripherals.keyboard delay 225
gsettings set org.gnome.desktop.peripherals.mouse natural-scroll false
gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll false

if command -v timedatectl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  sudo timedatectl set-timezone Asia/Seoul
fi
echo ">> [30-os-settings-gnome] done"
{{ end -}}
```

- [ ] **Step 4: windows OS 설정 스크립트 작성**

```
{{ if eq .chezmoi.os "windows" -}}
$ErrorActionPreference = 'Stop'
Write-Host ">> [30-os-settings-windows] registry"

# 탐색기: 확장자 표시, 숨김 파일 표시
$adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
Set-ItemProperty -Path $adv -Name HideFileExt -Value 0 -Type DWord
Set-ItemProperty -Path $adv -Name Hidden -Value 1 -Type DWord

# 다크 모드 (Apps/System)
$pers = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
if (-not (Test-Path $pers)) { New-Item -Path $pers -Force | Out-Null }
Set-ItemProperty -Path $pers -Name AppsUseLightTheme -Value 0 -Type DWord
Set-ItemProperty -Path $pers -Name SystemUsesLightTheme -Value 0 -Type DWord

# 키보드 반복 (macOS InitialKeyRepeat=15/KeyRepeat=2 상응) — 재로그인 시 적용
$kbd = 'HKCU:\Control Panel\Keyboard'
Set-ItemProperty -Path $kbd -Name KeyboardDelay -Value '0' -Type String
Set-ItemProperty -Path $kbd -Name KeyboardSpeed -Value '31' -Type String

# 탐색기 재시작 (확장자/숨김/다크모드 즉시 반영)
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Write-Host ">> [30-os-settings-windows] done (키보드 반복 속도는 재로그인 후 적용)"
{{ end -}}
```

- [ ] **Step 5: 렌더링·린트 검증**

Run:

```bash
cd ~/Projects/machine-setup
# gnome 스크립트: desktop 컨텍스트에서만 본문 렌더링
bash tests/render.sh false home/.chezmoiscripts/run_onchange_after_30-os-settings-gnome.sh.tmpl | grep -c gsettings
bash tests/render.sh true home/.chezmoiscripts/run_onchange_after_30-os-settings-gnome.sh.tmpl | wc -c
bash tests/lint.sh && bash tests/lint.sh --ps
```

Expected: desktop grep ≥ `7`, WSL `wc -c`는 0~수 바이트(빈 본문), `LINT PASS` 두 번

- [ ] **Step 6: Commit**

```bash
git add home/.chezmoiscripts/run_once_after_25-oh-my-zsh.sh.tmpl \
        home/.chezmoiscripts/run_onchange_after_30-os-settings-*.tmpl
git commit -m "feat: oh-my-zsh 비대화식 설치 + OS 설정 (darwin 1:1/gnome/windows)"
```

---

### Task 8: 40-services (ubuntu / darwin) + 50-input-method (gnome / wsl)

**Files:**
- Create: `home/.chezmoiscripts/run_onchange_after_40-services-ubuntu.sh.tmpl`
- Create: `home/.chezmoiscripts/run_onchange_after_40-services-darwin.sh.tmpl`
- Create: `home/.chezmoiscripts/run_once_after_50-input-method-gnome.sh.tmpl`
- Create: `home/.chezmoiscripts/run_once_after_50-input-method-wsl.sh.tmpl`

**Interfaces:**
- Consumes: `.isWSL` (Task 1). docker-ce/tailscale/openssh-server 패키지는 Task 4가 설치
- Produces: 없음 (말단 설정). Windows 서비스 스크립트는 없음 — winget 설치만으로 충분 (스펙 §10)

- [ ] **Step 1: ubuntu 서비스 스크립트 작성 (systemd 첫 실행 가드 — 스펙 §10)**

```
{{ if eq .chezmoi.os "linux" -}}
#!/bin/bash
set -euo pipefail
SYSTEMD_UP=0
[ -d /run/systemd/system ] && SYSTEMD_UP=1

echo ">> [40-services-ubuntu] docker group"
sudo usermod -aG docker "$(id -un)"

if [ "$SYSTEMD_UP" -eq 1 ]; then
  echo ">> [40-services-ubuntu] enable+start services"
  sudo systemctl enable --now docker
{{ if not .isWSL -}}
  sudo systemctl enable --now tailscaled
  # openssh 하드닝 (drop-in — 원본 linux/system.nix 이관)
  sudo tee /etc/ssh/sshd_config.d/50-hardening.conf >/dev/null <<'EOF'
PasswordAuthentication no
PermitRootLogin no
EOF
  sudo systemctl enable --now ssh
  sudo systemctl reload ssh || true
  tailscale status >/dev/null 2>&1 || echo ">> tailscale: 최초 1회 'sudo tailscale up --ssh' 실행 필요"
{{ end -}}
else
  echo ">> [40-services-ubuntu] systemd 비활성 — 서비스 기동 생략"
{{ if .isWSL -}}
  echo ">>   'wsl --shutdown' 후 재진입하면 systemd가 활성화되고, 'rebuild' 재실행 시 서비스가 기동됩니다"
{{ end -}}
fi
echo ">> [40-services-ubuntu] done"
{{ end -}}
```

주의: openssh 하드닝은 데스크톱 최초 로그인 전 `~/.ssh/authorized_keys`가 없으면 원격 SSH 접속이 막힌다 — 로컬 콘솔 접근 가능한 개인 데스크톱 전제(스펙 §2 비밀 배포 제외). README 체크리스트에 명시(Task 10).

- [ ] **Step 2: darwin 서비스 스크립트 작성**

```
{{ if eq .chezmoi.os "darwin" -}}
#!/bin/bash
set -euo pipefail
eval "$(/opt/homebrew/bin/brew shellenv)"
echo ">> [40-services-darwin] colima (docker 엔진)"
if ! brew services list | grep -E '^colima\s+started' >/dev/null 2>&1; then
  brew services start colima
  echo ">> colima 최초 기동은 VM 생성으로 수 분 걸릴 수 있습니다"
fi
echo ">> [40-services-darwin] done"
{{ end -}}
```

- [ ] **Step 3: gnome 입력기 스크립트 작성 (설치는 Task 4의 apt — 여기선 등록만)**

```
{{ if and (eq .chezmoi.os "linux") (not .isWSL) -}}
#!/bin/bash
set -euo pipefail
if ! command -v gsettings >/dev/null 2>&1; then
  echo ">> [50-input-method-gnome] gsettings 없음 — 건너뜀"
  exit 0
fi
current="$(gsettings get org.gnome.desktop.input-sources sources)"
if ! echo "$current" | grep -q "hangul"; then
  echo ">> [50-input-method-gnome] ibus-hangul 입력 소스 등록"
  gsettings set org.gnome.desktop.input-sources sources "[('xkb', 'us'), ('ibus', 'hangul')]"
fi
echo ">> [50-input-method-gnome] done (전환: Super+Space)"
{{ end -}}
```

- [ ] **Step 4: wsl 입력기 스크립트 작성**

```
{{ if and (eq .chezmoi.os "linux") .isWSL -}}
#!/bin/bash
set -euo pipefail
echo ">> [50-input-method-wsl] fcitx5 확인"
if ! command -v fcitx5 >/dev/null 2>&1; then
  echo "!! fcitx5 미설치 — 10-packages가 실패했는지 확인" >&2
  exit 1
fi
cat <<'EOF'
>> fcitx5 데몬은 zsh 시작 시 자동 기동됩니다 (WAYLAND_DISPLAY= 워크어라운드).
>> 최초 1회 수동 설정:
>>   1) exec zsh          # 셸 재시작 (fcitx5 자동 시작)
>>   2) pgrep -a fcitx5   # 데몬 확인
>>   3) fcitx5-configtool # Hangul 엔진 추가 + 전환 핫키 설정
>> GUI 앱은 WSL 셸에서 실행해야 IM 환경변수를 상속합니다.
EOF
{{ end -}}
```

- [ ] **Step 5: 렌더링·린트 검증**

Run:

```bash
cd ~/Projects/machine-setup
SVC=home/.chezmoiscripts/run_onchange_after_40-services-ubuntu.sh.tmpl
# WSL: tailscale/ssh 하드닝 없음 + wsl --shutdown 안내 있음
bash tests/render.sh true $SVC > /tmp/r-svc.sh
grep -c "tailscale" /tmp/r-svc.sh || true
grep -c "wsl --shutdown" /tmp/r-svc.sh
bash -n /tmp/r-svc.sh && echo SYNTAX-OK
bash tests/lint.sh
```

Expected: tailscale grep `0`, shutdown grep `1`, `SYNTAX-OK`, `LINT PASS`

- [ ] **Step 6: Commit**

```bash
git add home/.chezmoiscripts/run_onchange_after_40-services-*.tmpl \
        home/.chezmoiscripts/run_once_after_50-input-method-*.tmpl
git commit -m "feat: 서비스(docker/tailscale/ssh/colima) + 한글 입력기 설정"
```

---

### Task 9: PowerShell 프로필 + PSFzf 설치 스크립트

**Files:**
- Create: `home/Documents/PowerShell/Microsoft.PowerShell_profile.ps1.tmpl`
- Create: `home/.chezmoiscripts/run_once_after_26-psfzf-windows.ps1.tmpl`

**Interfaces:**
- Consumes: winget `junegunn.fzf`·`Microsoft.PowerShell` 설치 완료 (Task 5)
- Produces: `$PROFILE` 경로가 배치 위치와 다른 머신(OneDrive 리디렉션)에서는 스텁이 dot-source

- [ ] **Step 1: PowerShell 프로필 작성**

```
# Managed by chezmoi — 수정은 ~/Projects/machine-setup에서.
$ErrorActionPreference = 'Continue'

# PSReadLine (PSFzf보다 먼저 import — 키 핸들러 등록 순서)
Import-Module PSReadLine
Set-PSReadLineOption -EditMode Emacs

# PSFzf (fzf 키바인딩: Ctrl+t 파일, Ctrl+r 히스토리)
if (Get-Module -ListAvailable -Name PSFzf) {
  Import-Module PSFzf
  Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
}

# zoxide
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
  Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

# Environment
$env:EDITOR = 'nvim'

# rebuild / update
function rebuild { chezmoi update }
function update { winget upgrade --all; chezmoi update }
```

- [ ] **Step 2: PSFzf 설치 + $PROFILE 스텁 스크립트 작성**

```
{{ if eq .chezmoi.os "windows" -}}
$ErrorActionPreference = 'Stop'
Write-Host ">> [26-psfzf-windows] PSFzf 모듈"
if (-not (Get-Module -ListAvailable -Name PSFzf)) {
  Install-Module -Name PSFzf -Scope CurrentUser -Force
}

# OneDrive Documents 리디렉션 대응: $PROFILE이 배치 위치와 다르면 dot-source 스텁 생성
$deployed = Join-Path $HOME 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'
if (($PROFILE -ne $deployed) -and (-not (Test-Path $PROFILE))) {
  New-Item -ItemType Directory -Force -Path (Split-Path $PROFILE) | Out-Null
  Set-Content -Path $PROFILE -Value ". `"$deployed`""
  Write-Host ">> \$PROFILE 스텁 생성: $PROFILE → $deployed"
}
Write-Host ">> [26-psfzf-windows] done"
{{ end -}}
```

- [ ] **Step 3: 린트 검증**

Run: `bash tests/lint.sh --ps`
Expected: `LINT PASS` (PSScriptAnalyzer Error 0건)

- [ ] **Step 4: Commit**

```bash
git add home/Documents/PowerShell/Microsoft.PowerShell_profile.ps1.tmpl \
        home/.chezmoiscripts/run_once_after_26-psfzf-windows.ps1.tmpl
git commit -m "feat: PowerShell 프로필(PSFzf/zoxide) + \$PROFILE 리디렉션 스텁"
```

---

### Task 10: bootstrap 스크립트 3종 + README

**Files:**
- Create: `bootstrap/ubuntu.sh`
- Create: `bootstrap/macos.sh`
- Create: `bootstrap/windows.ps1`
- Create: `README.md`

**Interfaces:**
- Consumes: 저장소 전체 (chezmoi init이 모든 스크립트 실행)
- Produces: 환경변수 계약 `MACHINE_SETUP_REPO`(기본 `https://github.com/mandoo180/machine-setup.git`, 로컬 경로 허용 — 스모크 테스트가 사용), `FORCE_WSL`(Task 1)

- [ ] **Step 1: `bootstrap/ubuntu.sh` 작성**

```bash
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
```

- [ ] **Step 2: `bootstrap/macos.sh` 작성**

```bash
#!/usr/bin/env bash
# macOS 부트스트랩 — 이 스크립트 하나만 실행하면 된다.
#   bash bootstrap/macos.sh
set -euo pipefail

REPO="${MACHINE_SETUP_REPO:-https://github.com/mandoo180/machine-setup.git}"

if ! xcode-select -p >/dev/null 2>&1; then
  echo ">> [bootstrap] Xcode Command Line Tools 설치 (GUI 창 승인 필요)"
  xcode-select --install
  until xcode-select -p >/dev/null 2>&1; do sleep 10; done
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
```

- [ ] **Step 3: `bootstrap/windows.ps1` 작성**

```powershell
# Windows 11 부트스트랩 — PowerShell(관리자 아님)에서 실행:
#   Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap\windows.ps1
# WSL Ubuntu까지 설치하려면: .\bootstrap\windows.ps1 -InstallWSL
param([switch]$InstallWSL)
$ErrorActionPreference = 'Stop'

$repo = if ($env:MACHINE_SETUP_REPO) { $env:MACHINE_SETUP_REPO } else { 'https://github.com/mandoo180/machine-setup.git' }

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
  throw "winget이 없습니다. Microsoft Store에서 '앱 설치 관리자'를 업데이트하십시오."
}

Write-Host ">> [bootstrap] 최소 의존성 (git, chezmoi, PowerShell 7)"
foreach ($id in @('Git.Git', 'twpayne.chezmoi', 'Microsoft.PowerShell')) {
  winget list --id $id --exact --accept-source-agreements 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) {
    winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements
  }
}

# PATH 갱신 (이 세션에서 chezmoi/git을 바로 쓰기 위함)
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')

Write-Host ">> [bootstrap] chezmoi init --apply ($repo)"
chezmoi init --apply $repo

if ($InstallWSL) {
  Write-Host ">> [bootstrap] WSL Ubuntu 설치 (재부팅 필요할 수 있음)"
  wsl --install -d Ubuntu
  Write-Host ">> WSL 진입 후: bash <(curl -fsSL https://raw.githubusercontent.com/mandoo180/machine-setup/main/bootstrap/ubuntu.sh)"
}

Write-Host ">> [bootstrap] 완료. 새 터미널(pwsh 7)을 여십시오."
```

- [ ] **Step 4: `README.md` 작성**

````markdown
# machine-setup

새 머신 초기 세팅 (macOS / Ubuntu desktop / Ubuntu WSL / Windows 11).
`~/Projects/nix` (nix flake)를 대체하는 native 구성 — chezmoi + brew/apt/winget.

## 부트스트랩 (새 머신에서 1회)

```bash
# macOS
bash <(curl -fsSL https://raw.githubusercontent.com/mandoo180/machine-setup/main/bootstrap/macos.sh)

# Ubuntu (desktop / WSL 자동 감지)
bash <(curl -fsSL https://raw.githubusercontent.com/mandoo180/machine-setup/main/bootstrap/ubuntu.sh)
```

```powershell
# Windows 11 (PowerShell)
Set-ExecutionPolicy -Scope Process Bypass -Force
git clone https://github.com/mandoo180/machine-setup.git; .\machine-setup\bootstrap\windows.ps1
# WSL까지: .\machine-setup\bootstrap\windows.ps1 -InstallWSL
```

최초 실행 시 git email을 묻는다 (개인 mandoo180@gmail.com / 회사 kyeongsoo@douzone.com).

## 일상 워크플로우

```bash
rebuild   # 저장소 pull + 적용 (패키지 목록 변경분 설치 포함)
update    # 패키지 업그레이드(brew/apt/winget) + rebuild
```

패키지 추가·삭제: `home/.chezmoidata/packages.yaml` 수정 → commit/push → 각 머신에서 `rebuild`.

## 구조

- `bootstrap/` — OS별 진입점 (최소 의존성 + chezmoi init --apply)
- `home/` — chezmoi source (dotfiles + `.chezmoiscripts`)
- `home/.chezmoidata/packages.yaml` — 패키지 목록 단일 소스
- 실행 순서: 10-packages(before) → dotfiles → 20-fonts → 25-omz → 30-os → 40-services → 50-input-method

## 수동 검증 체크리스트 (부트스트랩 후)

- [ ] `exec zsh` → oh-my-zsh lambda 프롬프트
- [ ] 터미널에서 Nerd Font 아이콘 렌더링 (`echo " "`)
- [ ] `git log`에서 delta 페이저 동작, `git config user.email` 확인
- [ ] `docker run hello-world` (WSL: `wsl --shutdown` 후 재진입 + `rebuild` 필요할 수 있음)
- [ ] 한글 입력: desktop = Super+Space(ibus), WSL = fcitx5-configtool에서 Hangul 엔진 추가 후 GUI 앱 확인
- [ ] desktop: `sudo tailscale up --ssh` (최초 1회), **원격 SSH 쓸 거면 `~/.ssh/authorized_keys` 먼저 배치** (패스워드 인증 꺼져 있음)
- [ ] Windows: 새 pwsh 7 창에서 Ctrl+r(PSFzf), `z <dir>`(zoxide)

## 주의사항

- Nerd Fonts 버전 업그레이드: `packages.yaml`의 `nerd_version` 수정 후, 각 머신에서 `rm -rf ~/.local/share/fonts/<이름>` 후 `rebuild` (다운로드 마커가 디렉터리라서)
- deb 직배포 앱(obsidian/slack/discord)은 `update`로 업그레이드되지 않음 — 앱 내 업데이트 또는 재설치
- 기존 nix 머신에는 적용하지 않는다 (깨끗한 OS 전제 — 스펙 §2)

## 테스트

```bash
bash tests/lint.sh          # shellcheck (+--ps: PSScriptAnalyzer)
bash tests/smoke-ubuntu.sh  # Docker 컨테이너 e2e (desktop/WSL 양쪽 컨텍스트)
```
````

- [ ] **Step 5: 린트 검증**

Run: `bash tests/lint.sh && bash tests/lint.sh --ps`
Expected: `LINT PASS` 두 번

- [ ] **Step 6: Commit**

```bash
git add bootstrap/ README.md
git commit -m "feat: OS별 부트스트랩 진입점 + README"
```

---

### Task 11: Docker 스모크 테스트 (ubuntu e2e)

**Files:**
- Create: `tests/smoke-ubuntu.sh`

**Interfaces:**
- Consumes: `bootstrap/ubuntu.sh`(MACHINE_SETUP_REPO 계약), `FORCE_WSL` (Task 1·10)

- [ ] **Step 1: `tests/smoke-ubuntu.sh` 작성**

```bash
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
```

주의 2건: (1) `chezmoi init /repo`는 저장소를 **클론**하므로 커밋되지 않은 변경은 스모크에 반영되지 않는다 — 실행 전 커밋할 것. (2) 컨테이너에는 systemd가 없으므로 snap/서비스 기동은 스크립트 가드에 의해 자동 생략된다 — 이 경로가 정상 동작하는지도 이 테스트의 검증 대상이다.

- [ ] **Step 2: WSL 컨텍스트 스모크 실행**

Run: `bash tests/smoke-ubuntu.sh wsl 2>&1 | tail -20`
Expected: `===== smoke wsl PASS =====` 및 `SMOKE PASS`. 실패 시 원인 수정 후 재실행(멱등)

- [ ] **Step 3: desktop 컨텍스트 스모크 실행**

Run: `bash tests/smoke-ubuntu.sh desktop 2>&1 | tail -20`
Expected: `===== smoke desktop PASS =====`. deb 3종(obsidian/slack/discord) 설치 포함이라 wsl보다 오래 걸림

- [ ] **Step 4: 재실행 멱등성 검증 (같은 컨테이너에서 2회 apply)**

Run:

```bash
docker run --rm -v "$(pwd)":/repo:ro ubuntu:24.04 bash -c '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get install -y -qq sudo >/dev/null
    useradd -m -s /bin/bash tester && echo "tester ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/tester
    sudo -u tester -H \
      env MACHINE_SETUP_REPO=/repo FORCE_WSL=true \
          CHEZMOI_EXTRA_ARGS="--promptString email=t@t.com" \
      bash -c "cd && bash /repo/bootstrap/ubuntu.sh"
    echo "--- 2nd apply ---"
    sudo -u tester -H bash -c "
      eval \"\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)\"
      chezmoi apply --verbose"
    echo IDEMPOTENT-PASS'
```

Expected: 2차 apply에서 `run_once` 스크립트 미실행·`run_onchange` 미변경 재실행 없음, `IDEMPOTENT-PASS`

- [ ] **Step 5: Commit**

```bash
git add tests/smoke-ubuntu.sh
git commit -m "test: ubuntu 컨테이너 e2e 스모크 (desktop/WSL 컨텍스트 + 멱등성)"
```

---

### Task 12: 최종 검증 + 마무리

**Files:**
- Modify: (발견된 결함 수정)

- [ ] **Step 1: 전체 린트 + 전체 스모크 재실행**

Run:

```bash
bash tests/lint.sh && bash tests/lint.sh --ps
bash tests/smoke-ubuntu.sh
```

Expected: `LINT PASS` × 2, `SMOKE PASS`

- [ ] **Step 2: 전 템플릿 × 양쪽 컨텍스트 렌더링 새니티 (이 머신에는 적용하지 않는다 — 스펙 §2 기존 머신 제외)**

Run:

```bash
cd ~/Projects/machine-setup
for f in home/.chezmoiscripts/*.tmpl home/dot_zshrc.tmpl home/dot_config/git/config.tmpl; do
  for fw in true false; do
    bash tests/render.sh "$fw" "$f" > /dev/null \
      || { echo "RENDER FAIL: $f (FORCE_WSL=$fw)"; exit 1; }
  done
done && echo RENDER-OK
```

Expected: `RENDER-OK` (템플릿 문법 오류 0건)

- [ ] **Step 3: 스펙 대비 커버리지 최종 점검**

스펙 §6.2의 패키지·§7 dotfiles·§8 OS 설정·§9 입력기·§10 서비스 각 항목이 저장소 파일에 존재하는지 grep으로 확인:

```bash
grep -r "ApplePressAndHoldEnabled" home/ | wc -l   # 1 이상
grep -r "fcitx5" home/ | wc -l                     # 3 이상 (zshrc, packages, 50-wsl)
grep -r "tailscale up --ssh" home/ README.md | wc -l  # 1 이상
grep -r "Co-Authored-By" . --include="*.md" | wc -l   # 0 (커밋 규칙 확인용)
```

Expected: 주석대로

- [ ] **Step 4: Commit (수정분이 있을 때만)**

```bash
git add -A && git diff --cached --quiet || git commit -m "fix: 최종 검증에서 발견된 결함 수정"
```

---

## 실행 후 남는 수동 작업 (자동화 범위 밖 — 스펙 §2)

| 작업 | 시점 |
|---|---|
| GitHub에 이 저장소 push (`gh repo create mandoo180/machine-setup`) | 최초 1회 — bootstrap URL이 이를 전제 |
| macOS/Windows 실기기 검증 (README 체크리스트) | 해당 머신 확보 시 |
| `sudo tailscale up --ssh` | desktop 부트스트랩 후 1회 |
| SSH authorized_keys 배치 | desktop 원격 접속 필요 시 |
| fcitx5-configtool에서 Hangul 엔진 추가 | WSL 부트스트랩 후 1회 |
