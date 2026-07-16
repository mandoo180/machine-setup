# Native Machine Setup — 디자인 문서

- 날짜: 2026-07-16
- 상태: 사용자 리뷰 대기 (셀프 리뷰 28건 반영)
- 대체 대상: `~/Projects/nix` (nix-darwin / NixOS / NixOS-WSL flake)

## 1. 배경과 목표

기존 개발 환경은 nix flake(`~/Projects/nix`)로 macOS(nix-darwin), NixOS 데스크톱, NixOS-WSL을 관리했다. nix는 일반적인 환경(FHS 바이너리, npm 전역 패키지, 사내 도구 등)과의 호환성이 나빠 `nix-ld` 같은 우회 계층이 계속 필요했다. 이를 **각 OS의 native 도구 체계로 전환**한다.

**목표**: 새 머신에서 OS별 부트스트랩 스크립트 1회 실행만으로, 기존 nix 환경과 동등한 작업 환경을 구성한다. 이후에는 `rebuild`(=`chezmoi update`) 재실행으로 패키지·dotfiles가 저장소 상태와 동기화된다(멱등).

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
7. **서비스** — docker, tailscale(desktop만), openssh(Ubuntu desktop만)

### 제외 (의도적)

- **tmux** — 설치·설정 모두 이관하지 않음 (사용자 결정)
- **zshrc 개인 항목** — `em`/`emc` 함수, alias `e`/`v`/`ccc`, Jira 환경변수 (사용자 결정)
- **nix-ld** — native 환경에서는 불필요 (전환 이유 그 자체)
- **NixOS 전용 자산** — installer ISO, disko, nixos-anywhere 설치 자동화, blog-agent/fuiz-daily 호스트 자동화
- **기존 머신 마이그레이션** — 스크립트는 깨끗한 OS 전제. 기존 nix 머신은 OS 재설치 후 적용
- **비밀/자격증명 배포** — SSH 키, 토큰 등은 수동 관리 유지
- **LSP/언어 서버류** — basedpyright, nil, sqls, jdt-language-server, leiningen은 기본 목록에서 제외 (필요 시 언어별 도구로 개별 설치; packages.yaml에 주석으로 남김)

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
│   ├── ubuntu.sh                  # apt 기본(git, zsh, curl 등) → /etc/wsl.conf(WSL만)
│   │                              #   → Homebrew(Linux) → chezmoi → init --apply
│   └── windows.ps1                # winget 확인 → PowerShell 7 + chezmoi → init --apply
│                                  #   (+ 선택 플래그: wsl --install -d Ubuntu)
├── home/                          # chezmoi source
│   ├── .chezmoi.toml.tmpl         # 머신별 값: git email 프롬프트, isWSL 유도(아래 §5)
│   ├── .chezmoidata/packages.yaml # ★ 패키지 목록 단일 소스 (플랫폼별 섹션)
│   ├── .chezmoiignore             # 플랫폼별 파일 제외 (예: PowerShell 프로필은 Windows 외 무시)
│   ├── dot_zshrc.tmpl
│   ├── dot_config/git/config.tmpl
│   ├── dot_config/bat/config
│   ├── Documents/PowerShell/Microsoft.PowerShell_profile.ps1.tmpl  # Windows 전용 (pwsh 7)
│   └── .chezmoiscripts/           # 전부 .tmpl (비템플릿 스크립트는 두지 않는다 — 아래 규칙 참조)
│       ├── run_onchange_before_10-packages-darwin.sh.tmpl
│       ├── run_onchange_before_10-packages-ubuntu.sh.tmpl
│       ├── run_onchange_before_10-packages-windows.ps1.tmpl
│       ├── run_onchange_after_20-fonts-{darwin,ubuntu,windows}.{sh,ps1}.tmpl
│       ├── run_once_after_25-oh-my-zsh.sh.tmpl                # OMZ 설치 + chsh (macOS/Ubuntu)
│       ├── run_onchange_after_30-os-settings-{darwin,gnome,windows}.{sh,ps1}.tmpl
│       ├── run_onchange_after_40-services-{darwin,ubuntu,windows}.{sh,ps1}.tmpl
│       └── run_once_after_50-input-method-{gnome,wsl}.sh.tmpl  # 설정만 (설치는 10번)
└── docs/superpowers/specs/        # 이 문서
```

**스크립트 실행 조건 규칙**: 모든 스크립트는 `.tmpl`이며, 실행 여부는 각 템플릿 내부의 **`.chezmoi.os` + `isWSL` 분기**가 결정한다(비대상 플랫폼에서는 빈 본문으로 렌더링 → chezmoi가 실행 생략). `.chezmoi.os`는 Ubuntu desktop과 WSL에서 모두 `linux`이므로 desktop/WSL 구분은 반드시 `isWSL`을 쓴다. 파일명의 `darwin`/`ubuntu`/`gnome`/`wsl`/`windows` 접미사는 가독성용이다.

## 5. 부트스트랩 흐름

모든 OS에서 동일한 3단계:

1. **`bootstrap/<os>` 실행** — 최소 전제조건 설치: 패키지 매니저(Homebrew 설치/winget 확인) + git + zsh(Ubuntu, apt) + chezmoi. **WSL에서는 추가로 `/etc/wsl.conf`에 `[boot] systemd=true`를 기록**한다(이미 설정돼 있으면 skip)
2. **`chezmoi init --apply <repo>`** — before 스크립트(패키지 설치) → dotfiles 배치 → after 스크립트(폰트 → OMZ → OS 설정 → 서비스 → 입력기) 순으로 자동 실행
3. **이후 동기화** — `rebuild` alias = `chezmoi update`(repo pull + apply). 패키지 업그레이드는 별도의 `update` alias (§7)

플랫폼 감지 및 머신별 값 (`.chezmoi.toml.tmpl`):
- OS: `.chezmoi.os` (`darwin` / `linux` / `windows`)
- **WSL 여부**: config 생성 시 `isWSL` 값을 `[data]`에 저장한다. 기본값은 `.chezmoi.kernel.osrelease`에 `microsoft` 포함 여부로 유도하되, **환경변수 `FORCE_WSL`(true/false)이 있으면 그 값을 우선**한다 — Docker 컨테이너 테스트에서 양쪽 분기를 주입하기 위함(§12). 템플릿에서는 `.isWSL`로 참조
- 머신별 프롬프트: **git email만** 프롬프트한다(개인 `mandoo180@gmail.com` / 회사 `kyeongsoo@douzone.com` 선택). `user.name`은 `Kyeongsoo` 고정값. 이후 `~/.config/chezmoi/chezmoi.toml`에 저장되어 재실행 시 묻지 않음

## 6. 패키지 관리

### 6.1 소스 매핑

| 계층 | macOS | Ubuntu (desktop/WSL) | Windows |
|---|---|---|---|
| CLI 도구 | Homebrew | Homebrew on Linux | winget |
| 언어 런타임 | Homebrew | Homebrew on Linux | winget |
| GUI 앱 | brew cask | apt 공식 repo → 없으면 snap/공식 deb | winget |
| 폰트 | brew cask (`font-*`) | 설치 스크립트(GitHub release → `~/.local/share/fonts`) + apt(`fonts-noto`, `fonts-noto-cjk`, `fonts-noto-color-emoji`) | 설치 스크립트(사용자 폰트 등록) |
| 시스템 통합 패키지 | — | **apt**: zsh, docker-ce, 입력기(ibus-hangul/fcitx5*), xclip, GUI 앱, 시스템 폰트 | — |

**Ubuntu에서 brew/apt 경계**: 셸 유저랜드 CLI는 전부 brew(최신 버전 확보), 시스템 통합이 필요한 것은 apt. **예외: zsh는 apt로 설치**한다 — brew 경로(`/home/linuxbrew/.linuxbrew/bin/zsh`)는 `/etc/shells`에 없어 `chsh`가 실패하기 때문. Ubuntu 24.04 apt의 모던 CLI 도구(eza, delta, dust, duf, procs, lazygit 등)는 부재하거나 낡았기 때문에 brew를 쓴다.

### 6.2 패키지 목록 (`.chezmoidata/packages.yaml`)

기존 `shared/packages.nix` 기준, tmux 제외:

- **CLI 공통** (macOS/Ubuntu = brew, Windows = winget): ripgrep, fd, bat, eza, fzf, zoxide, jq, yq, htop, btop, tree, tldr, dust, duf, procs, git, gh, glab, lazygit, delta, direnv, curl, wget, httpie, openssl, lsof, zip, unzip, p7zip, xz, rsync, rename, dos2unix, watch, fswatch, pstree
  - Windows는 POSIX 전용 도구를 제외한 서브셋 — 정확한 멤버십은 packages.yaml의 `windows` 섹션이 정의(구현 시 winget 검증과 함께 확정, §13)
  - GNU 유저랜드(coreutils, findutils, grep, gnu-sed, gawk): macOS에서 brew로 설치하되 **PATH 우선순위는 기본값 유지(g-prefix 이름으로 사용)** — BSD 기본 도구를 가리지 않는다
- **언어/개발**: node, bun, uv, go, rustup, jdk(OpenJDK), gnumake, cmake, llvm, libtool
  - Python은 uv가 관리 (uv 설치로 갈음)
  - libtool: macOS에서 brew가 `glibtool` 이름으로 설치 — Emacs vterm 빌드 의존성(기존 darwin activation script의 glibtool 심링크를 대체)
  - 컴파일러: macOS = Xcode CLT, Ubuntu = build-essential, Windows = 기본 제외(필요 시 VS Build Tools)
- **에디터/터미널**: neovim(brew/winget), emacs(macOS: `d12frosted/emacs-plus` tap `emacs-plus@30`, Ubuntu: `ppa:ubuntuhandbook1/emacs`로 30.x — 서드파티 PPA, §13에서 재확인, Windows: winget `GNU.Emacs`), wezterm(macOS cask / Ubuntu 공식 apt repo / winget)
- **Linux 전용** (원본 `isLinux` 블록 이관): xclip(desktop/WSL), trash-cli(nvim Snacks.explorer 안전 삭제 의존성), alsa-utils, pulseaudio-utils(`pactl` 제공 — pipewire 데몬과 충돌 없음), firefox(desktop/WSL 모두 — WSLg로 실행 가능)
- **Ubuntu desktop 전용**: ffmpeg(`~/Projects/fulang` 비디오 파이프라인 의존성)
- **WSL 전용**: wslu(`wslview` 등 WSL 유틸리티)
- **Windows 전용**: `Microsoft.PowerShell`(pwsh 7 — 프로필 로드 전제조건), PSFzf 모듈(§7)
- **한글 입력기** (apt — 설치는 10-packages, 설정은 50번 스크립트): desktop = `ibus-hangul`, WSL = `fcitx5`, `fcitx5-hangul`, `fcitx5-config-qt`
- **GUI 앱 (macOS casks, 기존 목록 유지)**: arc, wezterm, visual-studio-code, colima(brew)+docker CLI(docker-desktop 대신), zed, godot, figma, blender, love, tiled, obsidian, gimp, slack, discord, telegram, spotify, vlc, 1password, appcleaner, the-unarchiver, hiddenbar, stats
  - Brewfile에 `cask_args no_quarantine` 명시 (Gatekeeper 경고 억제 — 기존 `caskArgs.no_quarantine` 이관)
- **GUI 앱 (Ubuntu desktop)**: wezterm, vscode(MS apt repo), firefox(기본), vlc, gimp(apt), obsidian(공식 deb), slack, discord, telegram, spotify(snap)
- **GUI 앱 (Windows)**: wezterm, vscode, Docker Desktop, PowerToys, Windows Terminal, 1Password, Slack, Discord, Telegram, Spotify, VLC, Obsidian
- **폰트**: Nerd Fonts(JetBrainsMono, FiraCode, Hack, Iosevka, MesloLG, SauceCodePro, UbuntuMono, DroidSansMono, Terminess, ZedMono, D2Coding), 비패치(jetbrains-mono, fira-code, source-code-pro, cascadia-code, departure-mono, Iosevka Term/Term Slab), Sans/Serif(inter, roboto, open-sans, source-sans, source-serif), **범용 Noto Sans/Serif**(fallback 커버리지 — Ubuntu는 `fonts-noto`), CJK(D2Coding, Noto CJK Sans/Serif, Noto Color Emoji), 아이콘(font-awesome, material-design-icons, material-symbols)

### 6.3 멱등 재실행 메커니즘

`run_onchange_` 스크립트는 **렌더링된 본문이 바뀔 때** 재실행된다. 패키지/폰트 스크립트는 `packages.yaml` 내용 해시를 본문에 템플릿으로 포함시켜, 목록 변경 = 본문 변경 = 재실행이 되도록 연동한다. OS 설정/서비스 스크립트(30·40번)는 스크립트 자체를 수정할 때 재실행된다. brew `Brewfile`(bundle), apt, winget 모두 기설치 항목은 no-op이므로 이중으로 안전하다.

## 7. dotfiles 매핑

| home-manager | chezmoi 대상 | 내용 |
|---|---|---|
| `programs.zsh` | `dot_zshrc.tmpl` | oh-my-zsh(테마 lambda, 플러그인 git/sudo/docker/kubectl/history/colored-man-pages), `bindkey -e`, PATH 추가(`~/.npm/bin`, `~/.config/emacs/bin`, `~/.bun/bin`, `~/.local/bin`, `~/Projects/x`), `[ -f ~/Projects/x/x.sh ] && source ~/Projects/x/x.sh`(존재 가드), brew shellenv(Linux), `rebuild`/`update` alias. **WSL 분기**: fcitx5 자동 시작(`WAYLAND_DISPLAY=` 워크어라운드), IM 환경변수(`GTK_IM_MODULE`/`QT_IM_MODULE`/`XMODIFIERS=fcitx`), `LIBGL_ALWAYS_SOFTWARE=1`, alias `open=wslview` |
| `programs.git` + `programs.delta` | `dot_config/git/config.tmpl` | `user.name=Kyeongsoo`(고정), `user.email`(프롬프트 값), `init.defaultBranch=main`, `pull.rebase=true`, `pull.ff=true`, `push.autoSetupRemote=true`, `core.quotePath=false`, `credential.helper=store`, delta pager 통합 |
| `programs.fzf` / `programs.zoxide` | zshrc 내 init | `eval "$(fzf --zsh)"`, `eval "$(zoxide init zsh)"` |
| `programs.bat` | `dot_config/bat/config` | `--theme="Dracula"` |
| `programs.tmux` | — | 이관하지 않음 |
| (신규) | `Microsoft.PowerShell_profile.ps1.tmpl` | PSReadLine 기본, `zoxide init powershell`, **PSFzf 모듈**(fzf는 PowerShell 공식 셸 통합이 없음 — `Install-Module PSFzf`는 run_once 스크립트, 프로필에서 `Import-Module`), `rebuild` 함수(`chezmoi update`) |
| `environment.variables` | zshrc / PowerShell 프로필 | `EDITOR`/`VISUAL=emacsclient -a nvim`(Windows는 nvim), `PAGER=less`, `LANG`/`LC_ALL=en_US.UTF-8` |

제외 (사용자 결정): `em`/`emc` 함수, alias `e`/`v`/`ccc`, Jira 환경변수(`JIRA_BASE_URL`, `JIRA_PROJECT_KEY`).

**alias 정의** (nix의 rebuild/update 워크플로우 대응):
- `rebuild` = `chezmoi update` — repo pull + apply (상태 동기화; 패키지 목록 변경분 설치 포함)
- `update` = 패키지 업그레이드 + rebuild — macOS: `brew update && brew upgrade && brew upgrade --cask`; Ubuntu: `sudo apt update && sudo apt upgrade -y && brew update && brew upgrade`; Windows: `winget upgrade --all`; 이후 공통으로 `chezmoi update`

**oh-my-zsh** (`run_once_after_25-oh-my-zsh.sh.tmpl`, macOS/Ubuntu만): `CHSH=no RUNZSH=no KEEP_ZSHRC=yes`로 비대화식 설치(CHSH 기본값이 yes라 명시하지 않으면 대화식 프롬프트 발생). dotfiles 적용(after) 이후 실행되므로 `KEEP_ZSHRC=yes`가 chezmoi의 zshrc를 보존한다. 같은 스크립트에서 Ubuntu는 `chsh -s /usr/bin/zsh`(apt 설치 경로 — `/etc/shells` 등록 자동), macOS는 기본 셸이 이미 zsh라 skip.

## 8. OS 시스템 설정

### macOS (`run_onchange_after_30-os-settings-darwin.sh.tmpl`)

`darwin/system.nix`의 `system.defaults` **전 항목을 1:1 변환**한다 — 원본 파일이 구현 체크리스트다. 대표 항목:
- Dock: autohide(+딜레이 0, 속도 0.4), minimize-to-application, mru-spaces=false, showhidden, show-recents=false, 크기 48, persistent-apps 초기화, 핫코너 비활성
- Finder: 확장자/숨김 파일/경로바/상태바 표시, 현재 폴더 검색, 리스트 뷰, CreateDesktop=false, QuitMenuItem, POSIX 경로 타이틀, 폴더 우선 정렬, 확장자 변경 경고 해제
- NSGlobalDomain: 다크 모드, 24시간제, 측정 단위(cm/섭씨), **ApplePressAndHoldEnabled=false**(키 반복의 전제조건 — 없으면 악센트 메뉴가 떠서 KeyRepeat이 무력화됨), InitialKeyRepeat=15 / KeyRepeat=2, 자동 대문자·따옴표·대시·마침표·맞춤법 비활성, iCloud 기본 저장 해제, 저장/인쇄 다이얼로그 확장, NSWindowResizeTime=0.1, 탭 클릭, 내추럴 스크롤 해제, 트랙패드 스케일 2.0
- trackpad: 탭 클릭, 두 손가락 우클릭, 세 손가락 드래그
- loginwindow(게스트 비활성, 콘솔 접근 차단), menuExtraClock(24시간, 날짜/요일 상시), screensaver(암호 요구 5초), 시동음 비활성
- 스크린샷: `~/Pictures/Screenshots`, png, 그림자 제거
- CustomUserPreferences: `.DS_Store` 네트워크/USB 기록 금지, 개인화 광고 비활성, TextEdit plain text, Disk Utility 디버그 메뉴
- TouchID sudo: `/etc/pam.d/sudo_local`에 `pam_tid.so` 라인 추가(idempotent)
- **emacs-plus 후처리**: `/opt/homebrew/Cellar/emacs-plus@30/.../Emacs.app`을 `/Applications`로 복사 (Spotlight 인덱싱 — 기존 darwin activation script 이관)
- 적용 후 `killall Dock Finder SystemUIServer`

### Ubuntu desktop — GNOME (`run_onchange_after_30-os-settings-gnome.sh.tmpl`, isWSL=false만)

- gsettings로 macOS 대응 항목: 다크 모드(`color-scheme prefer-dark`), 24시간제, 키 반복(`repeat-interval 30ms`, `delay 225ms`), 자연 스크롤 해제
- timezone: `timedatectl set-timezone Asia/Seoul` (원본 `time.timeZone` 이관; WSL은 Windows 시간 상속이라 불필요)
- GNOME 자체는 Ubuntu 기본이라 설치 불필요

### Windows (`run_onchange_after_30-os-settings-windows.ps1.tmpl`)

- 탐색기: 파일 확장자 표시, 숨김 파일 표시 (Explorer Advanced 레지스트리 → 탐색기 재시작으로 즉시 적용)
- 다크 모드: Apps/System (`AppsUseLightTheme=0`, `SystemUsesLightTheme=0`)
- 키보드 반복: `HKCU:\Control Panel\Keyboard`에 **`KeyboardDelay=0`, `KeyboardSpeed=31`**(최고 속도 — macOS InitialKeyRepeat=15/KeyRepeat=2에 상응). **재로그인 시 적용**됨을 말미에 안내(§11)

## 9. 한글 입력기

패키지 설치는 §6.2대로 10-packages(apt)가 담당하고, 50번 스크립트는 **설정만** 수행한다:

- **Ubuntu desktop** (`run_once_after_50-input-method-gnome.sh.tmpl`): gsettings `input-sources`에 `('ibus', 'hangul')` 등록
- **Ubuntu WSL** (`run_once_after_50-input-method-wsl.sh.tmpl`): fcitx5 초기 설정 확인 + 최초 1회 `fcitx5-configtool`에서 Hangul 엔진 추가 안내 출력. 데몬 자동 시작·IM 환경변수는 zshrc가 담당(§7) — WSLg 컴포지터가 `zwp_input_method_v1` 바인딩을 거부하므로 `WAYLAND_DISPLAY=`를 비운 채 X11/XIM 경로로 데몬을 띄우는 기존 워크어라운드 유지
- **macOS / Windows**: OS 기본 한글 IME 사용, 작업 없음

## 10. 서비스

| 서비스 | macOS | Ubuntu desktop | Ubuntu WSL | Windows |
|---|---|---|---|---|
| Docker | colima + docker CLI(brew) | docker-ce(공식 apt repo) 설치 + `usermod -aG docker $USER` + systemd enable | desktop과 동일 절차 (systemd 활성 전제 — 아래) | Docker Desktop(winget) |
| Tailscale | cask | 공식 apt repo 설치 + systemd enable, 최초 1회 `sudo tailscale up --ssh` 안내 | **설치하지 않음** (원본 nix에서도 WSL 미포함; 필요 시 수동) | winget |
| OpenSSH 서버 | — | `openssh-server` + `PasswordAuthentication no`, `PermitRootLogin no` | — (불필요) | — |
| 오디오(pipewire) | — | Ubuntu 24.04 기본 내장, 작업 없음 | — | — |

**WSL systemd 처리** (담당: `bootstrap/ubuntu.sh`):
1. 부트스트랩이 `/etc/wsl.conf`에 `[boot] systemd=true`를 기록한다(§5 1단계; 이미 있으면 skip)
2. **첫 실행 규칙**: `40-services-ubuntu`는 systemd 활성 여부(`[ -d /run/systemd/system ]`)를 검사해, 비활성이면 **패키지 설치·enable까지만 하고 start는 skip** — `set -euo pipefail` 아래에서 전체 apply가 실패하지 않도록. 말미에 "`wsl --shutdown` 후 재진입하면 서비스가 기동된다"를 안내한다(자동 재시작은 하지 않음 — 세션이 끊기므로)

## 11. 멱등성 · 에러 처리

- bash: `set -euo pipefail` / PowerShell: `$ErrorActionPreference = 'Stop'`
- 부트스트랩 각 단계는 설치 여부 체크 후 skip — 어느 지점에서 실패해도 재실행하면 이어서 진행
- **실행 순서**: chezmoi 의미론이 1차 — `before` 스크립트 전부(10-packages) → dotfiles 적용 → `after` 스크립트 전부(20~50). 숫자 프리픽스는 **같은 단계(before/after) 내부의 알파벳 정렬용**이다. 새 스크립트를 추가할 때 before/after 속성이 실행 시점을 결정함에 유의
- `run_onchange_`: 렌더링 본문 변경 시 재실행(§6.3) / `run_once_`: oh-my-zsh, 입력기 초기 설정 등 1회성
- sudo 필요 단계(apt, `/etc/wsl.conf`, defaults 일부)는 스크립트 도입부에서 한 번에 인증
- 재시작·재로그인이 필요한 항목은 실패가 아니라 **말미 안내 메시지**로 처리: WSL systemd(`wsl --shutdown`), 일부 macOS defaults(재로그인), Windows 탐색기(자동 재시작), Windows 키보드 반복(재로그인)
- 네트워크 등 외부 실패: chezmoi가 해당 스크립트에서 중단하고 에러 표시 → 원인 해결 후 `chezmoi apply` 재실행으로 복구

## 12. 검증

- **자동 (CI 없이 로컬)**:
  - `ubuntu:24.04` Docker 컨테이너에서 `bootstrap/ubuntu.sh` 스모크 테스트 — **비root sudo 유저를 만들어 실행**(Homebrew는 root 설치를 거부; 컨테이너에 sudo 사전 설치 필요). WSL/desktop 분기는 `FORCE_WSL=true|false` 주입으로 양쪽 모두 테스트(§5의 isWSL 유도 규칙과 동일 메커니즘). systemd 서비스는 "설치·enable까지"만 검증
  - 정적 검사: 템플릿은 렌더링 후 검사한다 — `chezmoi execute-template`(또는 `chezmoi cat`)로 darwin/ubuntu(desktop/WSL)/windows 각 컨텍스트를 렌더링한 결과에 `shellcheck` / `PSScriptAnalyzer` 적용
  - `chezmoi apply --dry-run --verbose`, `chezmoi doctor`
- **수동 (실기기 체크리스트, README 수록)**: 부트스트랩 1줄 실행 → 셸(zsh+oh-my-zsh) → 폰트(터미널에서 Nerd Font 아이콘) → git/delta → 한글 입력 → docker run hello-world → tailscale 상태(desktop)
- **성공 기준**: 새 머신에서 부트스트랩 1회 실행으로 기존 nix 환경과 동등한 작업 환경(tmux 제외) 구성, 재실행 시 오류·중복 작업 없음

## 13. 구현 단계에서 확정할 항목

1. **winget 패키지 ID 전수 검증** — CLI 도구·GUI 앱의 정확한 ID(`BurntSushi.ripgrep.MSVC` 등)를 구현 시 `winget search`로 전수 확인. Windows CLI 서브셋의 최종 멤버십도 이때 확정
2. **brew cask 폰트 이름 매핑** — `font-jetbrains-mono-nerd-font` 등 정확한 cask 이름 확인
3. **Ubuntu 폰트 다운로드 스크립트의 버전 고정 방식** — Nerd Fonts release 버전을 packages.yaml에 명시할지, latest를 따를지
4. **Obsidian/Slack 등 Ubuntu deb 배포 URL의 안정성** — snap 대체 여부 개별 판단
5. **emacs-plus 빌드 옵션** — 기존 `with-xwidgets`, `with-imagemagick` 유지 여부
6. **Ubuntu emacs PPA 신뢰성 재확인** — `ppa:ubuntuhandbook1/emacs`(서드파티) 유지 vs apt 기본 29.x 수용
7. **Windows PowerShell 프로필 경로** — OneDrive가 Documents를 리디렉션한 머신에서는 `$PROFILE`이 `~/OneDrive/Documents/...`가 됨. `$PROFILE` 실제 값 기준 배치 방법 확정
