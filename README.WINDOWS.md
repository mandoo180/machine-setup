Windows는 winget(패키지) + chezmoi(오케스트레이션) + PowerShell 프로필(dotfile) 조합입니다. macOS의 Homebrew 자리를 winget이, .zshrc 자리를 PowerShell 프로필이 대신합니다 (Windows에선 .zshrc가 .chezmoiignore로 배제됨).

1. 부트스트랩 — bootstrap/windows.ps1

관리자 아닌 일반 PowerShell에서 실행합니다. fresh 머신엔 git이 없으므로 README는 내장 curl.exe로 스크립트만 받아 실행하도록 안내합니다.

curl.exe -fsSLo windows.ps1 https://raw.githubusercontent.com/mandoo180/machine-setup/main/bootstrap/windows.ps1; .\windows.ps1
# WSL Ubuntu까지 한 번에: .\windows.ps1 -InstallWSL

하는 일:
1. winget 존재 확인 (없으면 "Microsoft Store에서 앱 설치 관리자 업데이트" 안내 후 중단)
2. 최소 의존성 3종만 먼저 설치 — Git.Git, twpayne.chezmoi, Microsoft.PowerShell(PS7)
3. 현재 세션 PATH 갱신 (방금 깐 chezmoi/git 즉시 사용)
4. chezmoi init --apply <repo> → 이하 모든 단계가 자동 실행
5. -InstallWSL 지정 시 wsl --install -d Ubuntu (재부팅 후 WSL 안에서 ubuntu.sh 별도 실행)

2. chezmoi가 자동 실행하는 4단계

┌────────┬────────────────────────┬──────────────────────────┐
│  순서  │        스크립트        │         하는 일          │
├────────┼────────────────────────┼──────────────────────────┤
│ before │ 10-packages-windows    │ winget으로 앱 ~40종 설치 │
├────────┼────────────────────────┼──────────────────────────┤
│ after  │ 20-fonts-windows       │ Nerd Font 14종 설치      │
├────────┼────────────────────────┼──────────────────────────┤
│ after  │ 26-psfzf-windows (1회) │ PSFzf 모듈 + 프로필 스텁 │
├────────┼────────────────────────┼──────────────────────────┤
│ after  │ 30-os-settings-windows │ 레지스트리 시스템 설정   │
└────────┴────────────────────────┴──────────────────────────┘

패키지 설치는 멱등(winget list로 이미 있으면 skip)하고 best-effort입니다 — 개별 ID 실패 시 경고만 남기고 계속(사내망 차단·winget ID 변경 대비). packages.yaml 변경 시에만 재실행됩니다.

설치 목록 (단일 소스 packages.yaml):
- CLI: ripgrep, fd, bat, eza, fzf, zoxide, jq, yq, delta, lazygit, dust, duf, procs, tlrc, neovim, emacs, gh, glab, chezmoi
- 런타임: Node LTS, Bun, uv, Go, Rustup, OpenJDK 21
- GUI: PowerShell, Windows Terminal, PowerToys, WezTerm, VS Code, Docker Desktop, Tailscale, 1Password, Slack, Discord, Telegram, Spotify, VLC, Obsidian

3. 폰트 — 20-fonts-windows

Nerd Fonts v3.4.0 zip 14종(JetBrainsMono, FiraCode, Hack, Iosevka 계열, D2Coding 등)을 GitHub에서 받아 %LOCALAPPDATA%\...\Fonts에 풀고 HKCU 레지스트리에 사용자 단위 등록(관리자 불필요). 스테이징 폴더에 풀고 성공 시에만 Move-Item으로 마커를 남겨, 다운로드 실패가 "영구 무성 스킵"으로 굳지 않게 설계했습니다.

4. 시스템 설정 — 30-os-settings-windows

레지스트리로 macOS system.nix 상응 항목을 적용:
- 탐색기: 확장자 표시 + 숨김 파일 표시
- 다크 모드 (앱 + 시스템)
- 키보드 반복 속도 최대(delay 0 / speed 31 — macOS의 빠른 키반복 상응, 재로그인 후 적용)
- explorer 재시작으로 즉시 반영

여기에 더해 Windows Terminal의 기본 프로필을 PowerShell 7로 바꿉니다. Windows 기본값은 Windows PowerShell 5.1이고, §5의 프로필은 PS7 경로(Documents\PowerShell)에만 배포되므로 이걸 바꾸지 않으면 새 탭이 프로필 없는 5.1로 열립니다. settings.json의 defaultProfile 값만 치환하므로(JSON 재직렬화 없음) 사용자가 넣은 주석·서식·키바인딩은 보존되고, 재실행해도 변화가 없으면 파일을 건드리지 않습니다. PowerShell 7 프로필 자체는 Windows Terminal이 pwsh 설치를 감지해 자동 생성하는 동적 프로필(고정 GUID 574e775e-…)이라 별도로 정의하지 않습니다. WT를 한 번도 실행하지 않은 새 머신에서는 defaultProfile만 담은 최소 settings.json을 미리 만들어 둡니다.

5. 셸 환경 — PowerShell 프로필 (dotfile)

Documents/PowerShell/Microsoft.PowerShell_profile.ps1이 배포되어 PS7 셸을 다음처럼 구성합니다:
- PSReadLine Emacs 편집 모드
- PSFzf 키바인딩 — Ctrl+t(파일), Ctrl+r(히스토리)
- zoxide 초기화 (z <dir>)
- EDITOR=nvim
- rebuild(=chezmoi update), update(=winget upgrade --all + rebuild) 함수

26-psfzf 스크립트는 PSFzf 모듈 설치와, OneDrive가 Documents를 리디렉션한 경우 $PROFILE이 실제 배치 위치와 어긋나는 문제를 dot-source 스텁으로 연결합니다.
