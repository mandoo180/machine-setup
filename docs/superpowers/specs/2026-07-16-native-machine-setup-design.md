# Native Machine Setup — 디자인 문서

- 날짜: 2026-07-16
- 상태: 사용자 리뷰 대기
- 대체 대상: `~/Projects/nix` (nix-darwin / NixOS / NixOS-WSL flake)

## 1. 배경과 목표

기존 개발 환경은 nix flake(`~/Projects/nix`)로 macOS(nix-darwin), NixOS 데스크톱, NixOS-WSL을 관리했다. nix는 일반적인 환경(FHS 바이너리, npm 전역 패키지, 사내 도구 등)과의 호환성이 나빠 `nix-ld` 같은 우회 계층이 계속 필요했다. 이를 **각 OS의 native 도구 체계로 전환**한다.

**목표**: 새 머신에서 OS별 부트스트랩 스크립트 1회 실행만으로, 기존 nix 환경과 동등한 작업 환경을 구성한다. 이후에는 스크립트/`chezmoi update` 재실행으로 패키지·dotfiles가 저장소 상태와 동기화된다(멱등).

**대상 플랫폼** (4종):

| 플랫폼 | 기존 (nix) | 신규 (native) |
|---|---|---|
| macOS (Apple Silicon) | nix-darwin + home-manager + Homebrew(casks) | Homebrew 단독 |
| Ubuntu desktop (24.04 LTS+) | NixOS desktop 호스트 | apt + Homebrew on Linux |
| Ubuntu WSL (24.04 LTS+) | NixOS-WSL | apt + Homebrew on Linux |
| Windows 11 | (없음 — 신규) | winget |

## 2. 범위

### 포함

1. **CLI 패키지** — 기존 `shared/packages.nix`의 도구 이관 (tmux 제외)
2. **폰트** — `shared/fonts.nix`의 Nerd Fonts, 프로그래밍 폰트, CJK 폰트, 아이콘 폰트
3. **dotfiles** — zsh(+oh-my-zsh), git(+delta), bat, fzf/zoxide 셸 통합, PowerShell 프로필(신규)
4. **GUI 앱** — macOS casks 기존 목록, Ubuntu desktop/Windows 대응 목록
5. **OS 시스템 설정** — macOS defaults, GNOME gsettings, Windows 레지스트리/설정
6. **한글 입력기** — Ubuntu desktop: ibus-hangul, WSL: fcitx5-hangul(+WSLg 워크어라운드)
7. **서비스** — docker, tailscale, openssh(Ubuntu desktop만)

### 제외 (의도적)

- **tmux** — 설치·설정 모두 이관하지 않음 (사용자 결정)
- **zshrc 개인 항목** — `em`/`emc` 함수, alias `e`/`v`/`ccc`, Jira 환경변수 (사용자 결정)
- **nix-ld** — native 환경에서는 불필요 (전환 이유 그 자체)
- **NixOS 전용 자산** — installer ISO, disko, nixos-anywhere 설치 자동화, blog-agent/fuiz-daily 호스트 자동화
- **기존 머신 마이그레이션** — 스크립트는 깨끗한 OS 전제. 기존 nix 머신은 OS 재설치 후 적용
- **비밀/자격증명 배포** — SSH 키, 토큰 등은 수동 관리 유지

## 3. 아키텍처 개요

**chezmoi 중심 구성**을 채택한다.

- [chezmoi](https://www.chezmoi.io): 단일 바이너리 dotfiles 매니저. macOS/Linux/Windows 네이티브 지원, 템플릿으로 플랫폼 분기, `run_once_`/`run_onchange_` 스크립트 훅 내장
- dotfiles와 설정 스크립트는 chezmoi가 관리하고, 패키지 설치는 플랫폼 네이티브 매니저(brew/apt/winget)를 chezmoi 스크립트가 호출
- home-manager가 하던 "프로그램 설치 + config 생성"은 → "packages.yaml(데이터) + dotfile 템플릿" 두 축으로 분해

**기각한 대안**:
- *plain scripts + 심링크*: 의존성은 없지만 플랫폼 분기·멱등성·Windows 심링크를 전부 수작업 구현해야 함
- *Ansible*: Windows 제어(WinRM)가 번거롭고 Python 의존이 생겨 "일반 환경 호환성" 목표와 상충

## 4. 저장소 구조

저장소: `~/Projects/machine-setup` (chezmoi source repo, git 관리)

```
machine-setup/
├── README.md                      # 플랫폼별 부트스트랩 1줄 + 수동 검증 체크리스트
├── .chezmoiroot                   # "home" — chezmoi source를 home/ 하위로 지정
├── bootstrap/                     # 진입점 — 각 OS에서 이것만 실행
│   ├── macos.sh                   # Xcode CLT → Homebrew → chezmoi → init --apply
│   ├── ubuntu.sh                  # apt 기본 → Homebrew(Linux) → chezmoi → init --apply
│   │                              #   desktop/WSL 자동 감지 (스크립트 하나)
│   └── windows.ps1                # winget 확인 → chezmoi → init --apply
│                                  #   (+ 선택 플래그: wsl --install -d Ubuntu)
├── home/                          # chezmoi source
│   ├── .chezmoi.toml.tmpl         # 최초 실행 시 머신별 값 프롬프트 (git email 등)
│   ├── .chezmoidata/packages.yaml # ★ 패키지 목록 단일 소스 (플랫폼별 섹션)
│   ├── dot_zshrc.tmpl
│   ├── dot_config/git/config.tmpl
│   ├── dot_config/bat/config
│   ├── Documents/PowerShell/Microsoft.PowerShell_profile.ps1.tmpl  # Windows 전용
│   └── .chezmoiscripts/
│       ├── run_onchange_before_10-packages-darwin.sh.tmpl
│       ├── run_onchange_before_10-packages-ubuntu.sh.tmpl
│       ├── run_onchange_before_10-packages-windows.ps1.tmpl
│       ├── run_onchange_after_20-fonts-{darwin,ubuntu,windows}.*
│       ├── run_onchange_after_30-os-settings-{darwin,gnome,windows}.*
│       ├── run_onchange_after_40-services-{darwin,ubuntu,windows}.*
│       └── run_once_after_50-input-method-{gnome,wsl}.sh
└── docs/superpowers/specs/        # 이 문서
```

- 파일별 플랫폼 적용 여부는 `.chezmoiignore` 템플릿 분기로 제어 (예: PowerShell 프로필은 Windows 외 무시)
- 스크립트 파일명의 `darwin`/`ubuntu`/`windows` 접미사는 가독성용이고, 실제 실행 조건은 각 템플릿 내부의 `.chezmoi.os` 분기가 결정

## 5. 부트스트랩 흐름

모든 OS에서 동일한 3단계:

1. **`bootstrap/<os>` 실행** — 최소 의존성만 설치: 패키지 매니저(Homebrew/winget 확인) + git + chezmoi
2. **`chezmoi init --apply <repo>`** — dotfiles 배치 + `.chezmoiscripts`가 패키지 → 폰트 → OS 설정 → 서비스 → 입력기 순으로 자동 실행
3. **이후 동기화** — `chezmoi update` 한 방 (nix의 `rebuild`에 대응; 셸 alias `rebuild`로 등록)

플랫폼 감지:
- OS: `.chezmoi.os` (`darwin` / `linux` / `windows`)
- WSL 여부: `.chezmoi.kernel.osrelease`에 `microsoft` 포함 여부 (템플릿 변수 `isWSL`로 노출)
- 머신별 값: `.chezmoi.toml.tmpl`이 최초 1회 프롬프트 — git email(개인 `mandoo180@gmail.com` / 회사 `kyeongsoo@douzone.com` 선택), 이후 `~/.config/chezmoi/chezmoi.toml`에 저장

## 6. 패키지 관리

### 6.1 소스 매핑

| 계층 | macOS | Ubuntu (desktop/WSL) | Windows |
|---|---|---|---|
| CLI 도구 | Homebrew | Homebrew on Linux | winget |
| 언어 런타임 | Homebrew | Homebrew on Linux | winget |
| GUI 앱 | brew cask | apt 공식 repo → 없으면 snap/공식 deb | winget |
| 폰트 | brew cask (`font-*`) | 설치 스크립트(GitHub release → `~/.local/share/fonts`) + apt(`fonts-noto-cjk`) | 설치 스크립트(사용자 폰트 등록) |

**Ubuntu에서 brew/apt 경계**: 셸 유저랜드 CLI는 전부 brew(최신 버전 확보), 시스템 통합이 필요한 것(docker, GUI 앱, 입력기, 시스템 폰트 패키지)은 apt. Ubuntu 24.04 apt의 모던 CLI 도구(eza, delta, dust, duf, procs, lazygit 등)는 부재하거나 낡았기 때문.

### 6.2 패키지 목록 (`.chezmoidata/packages.yaml`)

기존 `shared/packages.nix` 기준, tmux 제외:

- **CLI 공통** (macOS/Ubuntu = brew, Windows = winget): ripgrep, fd, bat, eza, fzf, zoxide, jq, yq, htop, btop, tree, tldr, dust, duf, procs, git, gh, glab, lazygit, delta, direnv, curl, wget, httpie, p7zip, rsync, watch, fswatch, dos2unix, rename, pstree
  - Windows는 POSIX 전용 도구(rsync, watch, pstree 등) 제외한 서브셋
- **언어/개발**: node, bun, uv, go, rustup, jdk(OpenJDK), gnumake, cmake, llvm
  - Python은 uv가 관리 (uv 설치로 갈음). basedpyright/nil/sqls/jdt-language-server/leiningen은 필요 시 언어별 도구로 개별 설치 — 기본 목록에서 제외하되 packages.yaml에 주석으로 남김
  - 컴파일러: macOS = Xcode CLT, Ubuntu = build-essential, Windows = 기본 제외(필요 시 VS Build Tools)
- **에디터/터미널**: neovim(brew/winget), emacs(macOS: `d12frosted/emacs-plus` tap `emacs-plus@30`, Ubuntu: PPA로 30.x, Windows: winget `GNU.Emacs`), wezterm(macOS cask / Ubuntu 공식 apt repo / winget)
- **GUI 앱 (macOS casks, 기존 목록 유지)**: arc, wezterm, visual-studio-code, docker-desktop 대신 colima(brew)+docker CLI, zed, godot, figma, blender, love, tiled, obsidian, gimp, slack, discord, telegram, spotify, vlc, 1password, appcleaner, the-unarchiver, hiddenbar, stats
- **GUI 앱 (Ubuntu desktop)**: wezterm, vscode(MS apt repo), firefox(기본), vlc, gimp(apt), obsidian(공식 deb), slack, discord, telegram, spotify(snap)
- **GUI 앱 (Windows)**: wezterm, vscode, Docker Desktop, PowerToys, Windows Terminal, 1Password, Slack, Discord, Telegram, Spotify, VLC, Obsidian
- **폰트**: Nerd Fonts(JetBrainsMono, FiraCode, Hack, Iosevka, MesloLG, SauceCodePro, UbuntuMono, DroidSansMono, Terminess, ZedMono, D2Coding), 비패치(jetbrains-mono, fira-code, source-code-pro, cascadia-code, departure-mono, Iosevka Term/Term Slab), Sans/Serif(inter, roboto, open-sans, source-sans, source-serif), CJK(D2Coding, Noto CJK Sans/Serif, Noto Color Emoji), 아이콘(font-awesome, material-design-icons, material-symbols)

### 6.3 멱등 재실행 메커니즘

`run_onchange_` 스크립트 본문에 `packages.yaml` 내용 해시가 템플릿으로 렌더링된다. 목록이 바뀌면 chezmoi가 "스크립트 변경"으로 인식해 해당 스크립트만 재실행한다. brew `Brewfile`(bundle), apt, winget 모두 기설치 항목은 no-op이므로 이중으로 안전하다.

## 7. dotfiles 매핑

| home-manager | chezmoi 대상 | 내용 |
|---|---|---|
| `programs.zsh` | `dot_zshrc.tmpl` | oh-my-zsh(테마 lambda, 플러그인 git/sudo/docker/kubectl/history/colored-man-pages), `bindkey -e`, WSL fcitx5 자동 시작 분기, PATH 추가(`~/.npm/bin`, `~/.config/emacs/bin`, `~/.bun/bin`, `~/.local/bin`, `~/Projects/x`), `[ -f ~/Projects/x/x.sh ] && source ~/Projects/x/x.sh`(존재 가드), brew shellenv(Linux), `rebuild`/`update` alias |
| `programs.git` + `programs.delta` | `dot_config/git/config.tmpl` | user.name/email(프롬프트 값), `init.defaultBranch=main`, `pull.rebase=true`, `pull.ff=true`, `push.autoSetupRemote=true`, `core.quotePath=false`, `credential.helper=store`, delta pager 통합 |
| `programs.fzf` / `programs.zoxide` | zshrc 내 init | `eval "$(fzf --zsh)"`, `eval "$(zoxide init zsh)"` |
| `programs.bat` | `dot_config/bat/config` | `--theme="Dracula"` |
| `programs.tmux` | — | 이관하지 않음 |
| (신규) | `Microsoft.PowerShell_profile.ps1.tmpl` | PSReadLine 기본, fzf/zoxide init, `rebuild` 함수(`chezmoi update`) |
| `environment.variables` | zshrc / PowerShell 프로필 | `EDITOR`/`VISUAL=emacsclient -a nvim`(Windows는 nvim), `PAGER=less`, `LANG`/`LC_ALL=en_US.UTF-8` |

제외 (사용자 결정): `em`/`emc` 함수, alias `e`/`v`/`ccc`, Jira 환경변수(`JIRA_BASE_URL`, `JIRA_PROJECT_KEY`).

oh-my-zsh 자체는 `run_once_` 스크립트로 비대화식 설치(`RUNZSH=no KEEP_ZSHRC=yes`), 기본 셸 전환은 `chsh -s $(which zsh)`(Ubuntu; macOS는 기본이 zsh).

## 8. OS 시스템 설정

### macOS (`run_onchange_after_30-os-settings-darwin.sh`)

`darwin/system.nix`의 `system.defaults`를 `defaults write`로 1:1 변환:
- Dock: autohide(+딜레이 0), 최근 앱 숨김, 크기 48, 핫코너 비활성
- Finder: 확장자/숨김 파일/경로바/상태바 표시, 현재 폴더 검색, 리스트 뷰
- NSGlobalDomain: 다크 모드, 24시간제, 키 반복(InitialKeyRepeat 15 / KeyRepeat 2), 자동 대문자·따옴표·맞춤법 비활성, 탭 클릭, 내추럴 스크롤 해제
- 스크린샷: `~/Pictures/Screenshots`, png, 그림자 제거
- `.DS_Store` 네트워크/USB 기록 금지, 개인화 광고 비활성, TextEdit plain text
- TouchID sudo: `/etc/pam.d/sudo_local`에 `pam_tid.so` 라인 추가(idempotent)
- 적용 후 `killall Dock Finder SystemUIServer`

### Ubuntu desktop — GNOME (`run_onchange_after_30-os-settings-gnome.sh`)

gsettings로 macOS 대응 항목: 다크 모드(`color-scheme prefer-dark`), 24시간제, 키 반복(`repeat-interval 30ms`, `delay 225ms`), 자연 스크롤 해제. GNOME 자체는 Ubuntu 기본이라 설치 불필요. WSL에서는 실행하지 않음.

### Windows (`run_onchange_after_30-os-settings-windows.ps1`)

레지스트리/PowerShell로: 탐색기 파일 확장자·숨김 파일 표시, 다크 모드(Apps/System), 키보드 반복 속도(`HKCU:\Control Panel\Keyboard`). 적용 후 탐색기 재시작 안내.

## 9. 한글 입력기

- **Ubuntu desktop**: `ibus-hangul`(apt) 설치 + gsettings `input-sources`에 `('ibus', 'hangul')` 등록. GNOME 통합 — nix 구성과 동일한 선택
- **Ubuntu WSL**: `fcitx5`, `fcitx5-hangul`(apt) 설치 + IM 환경변수(`GTK_IM_MODULE`/`QT_IM_MODULE`/`XMODIFIERS=fcitx`) + zshrc의 자동 시작 로직 이관 — WSLg 컴포지터가 `zwp_input_method_v1` 바인딩을 거부하므로 `WAYLAND_DISPLAY=` 를 비운 채 X11/XIM 경로로 데몬을 띄우는 기존 워크어라운드 유지. 최초 1회 `fcitx5-configtool`에서 Hangul 엔진 추가 안내 출력
- **macOS / Windows**: OS 기본 한글 IME 사용, 작업 없음

## 10. 서비스

| 서비스 | macOS | Ubuntu desktop | Ubuntu WSL | Windows |
|---|---|---|---|---|
| Docker | colima + docker CLI(brew) | docker-ce(공식 apt repo) + `usermod -aG docker` | 좌동 (systemd 필요) | Docker Desktop(winget) |
| Tailscale | cask | 공식 apt repo, 최초 1회 `sudo tailscale up --ssh` 안내 | 좌동 (선택) | winget |
| OpenSSH 서버 | — | `openssh-server` + 패스워드 인증 비활성 | — (불필요) | — |
| 오디오(pipewire) | — | Ubuntu 24.04 기본 내장, 작업 없음 | — | — |

**WSL systemd**: 일반 Ubuntu WSL은 `/etc/wsl.conf`에 `[boot] systemd=true`가 있어야 docker/tailscale 서비스가 동작한다. 부트스트랩이 이를 기록하고, 변경 시 `wsl --shutdown` 후 재진입하라는 안내를 마지막에 출력한다(자동 재시작은 하지 않음 — 세션이 끊기므로).

## 11. 멱등성 · 에러 처리

- bash: `set -euo pipefail` / PowerShell: `$ErrorActionPreference = 'Stop'`
- 부트스트랩 각 단계는 설치 여부 체크 후 skip — 어느 지점에서 실패해도 재실행하면 이어서 진행
- 실행 순서는 파일명 프리픽스로 보장: `10-packages → 20-fonts → 30-os-settings → 40-services → 50-input-method`
- `run_onchange_`: 데이터(packages.yaml) 변경 시만 재실행 / `run_once_`: oh-my-zsh, 입력기 초기 설정 등 1회성
- sudo 필요 단계(apt, `/etc/wsl.conf`, defaults 일부)는 스크립트 도입부에서 한 번에 인증
- 재시작이 필요한 항목(WSL systemd, 일부 macOS defaults, Windows 탐색기)은 실패가 아니라 **말미 안내 메시지**로 처리
- 네트워크 등 외부 실패: chezmoi가 해당 스크립트에서 중단하고 에러 표시 → 원인 해결 후 `chezmoi apply` 재실행으로 복구

## 12. 검증

- **자동 (CI 없이 로컬)**:
  - `ubuntu:24.04` Docker 컨테이너에서 `bootstrap/ubuntu.sh` 스모크 테스트 — WSL 분기는 환경변수로 모킹, systemd 서비스는 "설치까지"만 검증
  - `shellcheck`(bash 전부), `PSScriptAnalyzer`(PowerShell 전부)
  - `chezmoi apply --dry-run --verbose`, `chezmoi doctor`
- **수동 (실기기 체크리스트, README 수록)**: 부트스트랩 1줄 실행 → 셸(zsh+oh-my-zsh) → 폰트(터미널에서 Nerd Font 아이콘) → git/delta → 한글 입력 → docker run hello-world → tailscale 상태
- **성공 기준**: 새 머신에서 부트스트랩 1회 실행으로 기존 nix 환경과 동등한 작업 환경(tmux 제외) 구성, 재실행 시 오류·중복 작업 없음

## 13. 구현 단계에서 확정할 항목

1. **winget 패키지 ID 전수 검증** — CLI 도구·GUI 앱의 정확한 ID(`BurntSushi.ripgrep.MSVC` 등)를 구현 시 `winget search`로 전수 확인
2. **brew cask 폰트 이름 매핑** — `font-jetbrains-mono-nerd-font` 등 정확한 cask 이름 확인
3. **Ubuntu 폰트 다운로드 스크립트의 버전 고정 방식** — Nerd Fonts release 버전을 packages.yaml에 명시할지, latest를 따를지
4. **Obsidian/Slack 등 Ubuntu deb 배포 URL의 안정성** — snap 대체 여부 개별 판단
5. **emacs-plus 빌드 옵션** — 기존 `with-xwidgets`, `with-imagemagick` 유지 여부
